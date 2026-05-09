module tltm_stage1_driver
   use, intrinsic :: iso_fortran_env, only: int64
   use param_mod, only: config, read_parameters
   use utils
   use solve_flow, only: flow, set_intode_strict_mode
   use model, only: grand
   use mt95, only: getseed, sgrnd
   use markovchain_metropolis, only: metropolis_step
   use markovchain_phase, only: compute_phase_factor
   use tltm_types_mod, only: tltm_replica_t, allocate_tltm_replica, release_tltm_replica, record_tltm_local_transition
   implicit none

   integer, parameter :: stage1_cycle_cap_default = 200
   integer, parameter :: stage1_init_attempts_default = 200
   real(dp), parameter :: stage1_init_sigma_default = 0.10_dp

contains

   subroutine execute_tltm_stage1()
      type(tltm_replica_t), allocatable :: replicas(:)
      real(dp), allocatable :: flow_ladder(:)
      character(len=512) :: summary_file
      integer :: n_replicas, base_seed, cycle_count, local_updates, x_size
      real(dp) :: max_flow_time, init_sigma
      logical :: ok
      integer :: i, cycle_idx
      real(dp) :: run_t0, elapsed, replica_t0

      call set_intode_strict_mode(.true.)
      call read_parameters()

      x_size = config%state%x_size
      call resolve_base_seed(base_seed)
      call resolve_stage1_controls(config%integrator%initial_flow_time, config%chain%length, config%chain%hmc_repeat, &
                                   n_replicas, flow_ladder, max_flow_time, cycle_count, local_updates, init_sigma)
      call resolve_summary_file(summary_file)

      write (*, '(A,I0,A,F8.4,A,I0,A,I0,A,F8.4)') "[TLTM-S1] replicas=", n_replicas, &
         " max_flow=", max_flow_time, " cycles=", cycle_count, " local_updates=", local_updates, &
         " init_sigma=", init_sigma
      write (*, '(A,F8.4,A,I0,A,F8.4)') "[TLTM-S1] local params: L=", config%integrator%trajectory_length, &
         " nstep=", config%integrator%integration_steps, " max_flow(test)=", max_flow_time

      allocate (replicas(n_replicas))
      do i = 1, n_replicas
         replicas(i)%replica_id = i - 1
         replicas(i)%flow_time = flow_ladder(i)
         replicas(i)%rng_seed = derive_replica_seed(base_seed, i)
         call allocate_tltm_replica(replicas(i), x_size)
         call initialize_replica(replicas(i), init_sigma, stage1_init_attempts_default, ok)
         if (.not. ok) then
            write (*, '(A,I0,A,F8.4,A)') "[ERROR][TLTM-S1] Replica ", replicas(i)%replica_id, &
               " initialization failed at flow_time=", replicas(i)%flow_time, "."
            call release_all_replicas(replicas)
            error stop 1
         end if
      end do

      call sgrnd(base_seed)
      run_t0 = wall_time_seconds()
      do cycle_idx = 1, cycle_count
         do i = 1, n_replicas
            replica_t0 = wall_time_seconds()
            call run_local_updates(replicas(i), local_updates)
            replicas(i)%local_runtime = replicas(i)%local_runtime + (wall_time_seconds() - replica_t0)
            call measure_replica(replicas(i))
         end do

         if (cycle_idx == 1 .or. mod(cycle_idx, 10) == 0 .or. cycle_idx == cycle_count) then
            write (*, '(A,I0,A,I0)') "[TLTM-S1] cycle ", cycle_idx, "/", cycle_count
         end if
      end do
      elapsed = wall_time_seconds() - run_t0

      call write_stage1_summary(summary_file, replicas, cycle_count, local_updates, elapsed)
      call release_all_replicas(replicas)
      if (allocated(flow_ladder)) deallocate (flow_ladder)

      write (*, '(A,1X,A)') "[DONE][TLTM-S1] Summary written to", trim(summary_file)
   end subroutine execute_tltm_stage1

   subroutine initialize_replica(replica, init_sigma, max_attempts, ok)
      type(tltm_replica_t), intent(inout) :: replica
      real(dp), intent(in) :: init_sigma
      integer, intent(in) :: max_attempts
      logical, intent(out) :: ok

      real(dp), allocatable :: x_seed(:)
      logical :: flow_failed
      integer :: attempt

      ok = .false.
      allocate (x_seed(max(1, size(replica%x) - 1)))
      call sgrnd(replica%rng_seed)

      do attempt = 1, max_attempts
         call grand(x_seed)
         x_seed = init_sigma*x_seed
         call x_set_flow_time(replica%x, replica%flow_time)
         call x_set_seed_real(replica%x, x_seed)
         call flow(replica%x, replica%z, replica%jac, flow_failed)
         if (.not. flow_failed) then
            ok = .true.
            exit
         end if
      end do

      if (ok) then
         call measure_replica(replica)
      end if
      if (allocated(x_seed)) deallocate (x_seed)
   end subroutine initialize_replica

   subroutine run_local_updates(replica, local_updates)
      type(tltm_replica_t), intent(inout) :: replica
      integer, intent(in) :: local_updates

      integer :: update_idx, z_size
      real(dp), allocatable :: x_new(:)
      complex(dp), allocatable :: z_new(:), j_new(:, :)
      logical :: accepted, proposal_failed
      integer :: transition_status

      z_size = size(replica%z)
      allocate (x_new(size(replica%x)))
      allocate (z_new(z_size), j_new(z_size, z_size))

      do update_idx = 1, local_updates
         call metropolis_step(replica%x, replica%z, replica%jac, config%integrator%trajectory_length, &
                              config%integrator%integration_steps, x_new, z_new, j_new, accepted, proposal_failed, transition_status)
         if (accepted) then
            replica%x = x_new
            replica%z = z_new
            replica%jac = j_new
         end if
         call record_tltm_local_transition(replica, accepted, proposal_failed, transition_status)
      end do

      if (allocated(x_new)) deallocate (x_new)
      if (allocated(z_new)) deallocate (z_new)
      if (allocated(j_new)) deallocate (j_new)
   end subroutine run_local_updates

   subroutine measure_replica(replica)
      type(tltm_replica_t), intent(inout) :: replica
      complex(dp) :: phi
      logical :: error

      call compute_phase_factor(replica%z, replica%jac, phi, error)
      if (.not. error) then
         replica%phi_sum = replica%phi_sum + phi
         replica%observable_samples = replica%observable_samples + 1
      end if
   end subroutine measure_replica

   subroutine resolve_base_seed(base_seed)
      integer, intent(out) :: base_seed
      character(len=64) :: seed_env
      integer :: env_len, env_status, ios

      seed_env = ""
      call get_environment_variable("CHAIN_RNG_SEED", seed_env, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         read (seed_env(1:env_len), *, iostat=ios) base_seed
         if (ios /= 0 .or. base_seed <= 0) then
            base_seed = getseed()
         end if
      else
         base_seed = getseed()
      end if
      write (*, '(A,I0)') "[TLTM-S1] CHAIN_RNG_SEED=", base_seed
   end subroutine resolve_base_seed

   subroutine resolve_stage1_controls(default_max_flow, config_chain_length, config_hmc_repeat, n_replicas, flow_ladder, &
                                      max_flow_time, cycle_count, local_updates, init_sigma)
      real(dp), intent(in) :: default_max_flow
      integer, intent(in) :: config_chain_length, config_hmc_repeat
      integer, intent(out) :: n_replicas, cycle_count, local_updates
      real(dp), allocatable, intent(out) :: flow_ladder(:)
      real(dp), intent(out) :: max_flow_time, init_sigma

      character(len=1024) :: ladder_text
      integer :: env_len, env_status
      logical :: ok
      real(dp), allocatable :: parsed(:)

      n_replicas = 2
      call parse_int_env("TLTM_STAGE1_NUM_REPLICAS", n_replicas, n_replicas)
      if (n_replicas < 1) then
         write (*, '(A)') "[ERROR][TLTM-S1] TLTM_STAGE1_NUM_REPLICAS must be >= 1."
         error stop 1
      end if

      max_flow_time = max(0.0_dp, default_max_flow)
      call parse_real_env("TLTM_STAGE1_MAX_FLOW_TIME", max_flow_time, max_flow_time)
      if (max_flow_time < 0.0_dp) then
         write (*, '(A)') "[ERROR][TLTM-S1] TLTM_STAGE1_MAX_FLOW_TIME must be >= 0."
         error stop 1
      end if

      ladder_text = ""
      call get_environment_variable("TLTM_STAGE1_FLOW_TIME_LADDER", ladder_text, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         call parse_real_list(ladder_text(1:env_len), parsed, ok)
         if (.not. ok .or. .not. allocated(parsed)) then
            write (*, '(A)') "[ERROR][TLTM-S1] Failed to parse TLTM_STAGE1_FLOW_TIME_LADDER."
            error stop 1
         end if
         n_replicas = size(parsed)
         allocate (flow_ladder(n_replicas))
         flow_ladder = parsed
         max_flow_time = maxval(flow_ladder)
         if (allocated(parsed)) deallocate (parsed)
      else
         call build_linear_ladder(n_replicas, max_flow_time, flow_ladder)
      end if

      cycle_count = max(1, min(max(1, config_chain_length), stage1_cycle_cap_default))
      call parse_int_env("TLTM_STAGE1_CYCLES", cycle_count, cycle_count)
      if (cycle_count < 1) then
         write (*, '(A)') "[ERROR][TLTM-S1] TLTM_STAGE1_CYCLES must be >= 1."
         error stop 1
      end if

      local_updates = max(1, config_hmc_repeat)
      call parse_int_env("TLTM_STAGE1_LOCAL_UPDATES", local_updates, local_updates)
      if (local_updates < 1) then
         write (*, '(A)') "[ERROR][TLTM-S1] TLTM_STAGE1_LOCAL_UPDATES must be >= 1."
         error stop 1
      end if

      init_sigma = stage1_init_sigma_default
      call parse_real_env("TLTM_STAGE1_INIT_SIGMA", init_sigma, init_sigma)
      if (init_sigma <= 0.0_dp) then
         write (*, '(A)') "[ERROR][TLTM-S1] TLTM_STAGE1_INIT_SIGMA must be > 0."
         error stop 1
      end if
   end subroutine resolve_stage1_controls

   subroutine resolve_summary_file(path)
      character(len=*), intent(out) :: path
      integer :: env_len, env_status

      path = "../output/tests/tltm_stage1_summary.dat"
      call get_environment_variable("TLTM_STAGE1_SUMMARY_FILE", path, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         path = trim(path(1:env_len))
      else
         path = "../output/tests/tltm_stage1_summary.dat"
      end if
   end subroutine resolve_summary_file

   subroutine write_stage1_summary(summary_file, replicas, cycle_count, local_updates, elapsed)
      character(len=*), intent(in) :: summary_file
      type(tltm_replica_t), intent(in) :: replicas(:)
      integer, intent(in) :: cycle_count, local_updates
      real(dp), intent(in) :: elapsed

      integer, parameter :: unit_summary = 77
      integer :: ios, i, total_count
      integer :: metropolis_reject_total, reverse_gate_reject_total, proposal_failure_total
      integer :: hamiltonian_invalid_total, delta_h_invalid_total, output_size_mismatch_total
      real(dp) :: accept_rate, abs_mean_phi

      open (unit=unit_summary, file=trim(summary_file), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S1] Cannot open summary file:", trim(summary_file)
         error stop 1
      end if

      write (unit_summary, '(A)') "# TLTM stage-1 summary"
      write (unit_summary, '(A,I0)') "# replicas=", size(replicas)
      write (unit_summary, '(A,I0)') "# cycles=", cycle_count
      write (unit_summary, '(A,I0)') "# local_updates=", local_updates
      write (unit_summary, '(A,F12.6)') "# elapsed_sec=", elapsed
      metropolis_reject_total = 0
      reverse_gate_reject_total = 0
      proposal_failure_total = 0
      hamiltonian_invalid_total = 0
      delta_h_invalid_total = 0
      output_size_mismatch_total = 0
      do i = 1, size(replicas)
         metropolis_reject_total = metropolis_reject_total + replicas(i)%metropolis_reject_count
         reverse_gate_reject_total = reverse_gate_reject_total + replicas(i)%reverse_gate_reject_count
         proposal_failure_total = proposal_failure_total + replicas(i)%proposal_failure_count
         hamiltonian_invalid_total = hamiltonian_invalid_total + replicas(i)%hamiltonian_invalid_count
         delta_h_invalid_total = delta_h_invalid_total + replicas(i)%delta_h_invalid_count
         output_size_mismatch_total = output_size_mismatch_total + replicas(i)%output_size_mismatch_count
      end do
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# local_transition_totals metropolis_reject=", metropolis_reject_total, &
         " reverse_gate_reject=", reverse_gate_reject_total, " proposal_failure=", proposal_failure_total, &
         " hamiltonian_invalid=", hamiltonian_invalid_total, " delta_h_invalid=", delta_h_invalid_total, &
         " output_size_mismatch=", output_size_mismatch_total
      write (unit_summary, '(A)') &
         "# replica_id flow_time accepts rejects accept_rate projection_fail samples abs_mean_phi runtime_sec " // &
         "metropolis_reject reverse_gate_reject proposal_failure hamiltonian_invalid delta_h_invalid output_size_mismatch"

      do i = 1, size(replicas)
         total_count = replicas(i)%local_accept_count + replicas(i)%local_reject_count
         if (total_count > 0) then
            accept_rate = real(replicas(i)%local_accept_count, dp)/real(total_count, dp)
         else
            accept_rate = 0.0_dp
         end if

         if (replicas(i)%observable_samples > 0) then
            abs_mean_phi = abs(replicas(i)%phi_sum/real(replicas(i)%observable_samples, dp))
         else
            abs_mean_phi = 0.0_dp
         end if

         write (unit_summary, '(I4,1X,F10.6,1X,I8,1X,I8,1X,F9.5,1X,I8,1X,I8,1X,ES16.8,1X,F12.6,6(1X,I8))') &
            replicas(i)%replica_id, replicas(i)%flow_time, replicas(i)%local_accept_count, replicas(i)%local_reject_count, &
            accept_rate, replicas(i)%projection_failure_count, replicas(i)%observable_samples, &
            abs_mean_phi, replicas(i)%local_runtime, replicas(i)%metropolis_reject_count, replicas(i)%reverse_gate_reject_count, &
            replicas(i)%proposal_failure_count, replicas(i)%hamiltonian_invalid_count, replicas(i)%delta_h_invalid_count, &
            replicas(i)%output_size_mismatch_count
      end do

      close (unit_summary)
   end subroutine write_stage1_summary

   subroutine release_all_replicas(replicas)
      type(tltm_replica_t), allocatable, intent(inout) :: replicas(:)
      integer :: i

      if (.not. allocated(replicas)) return
      do i = 1, size(replicas)
         call release_tltm_replica(replicas(i))
      end do
      deallocate (replicas)
   end subroutine release_all_replicas

   integer function derive_replica_seed(base_seed, replica_index) result(seed_value)
      integer, intent(in) :: base_seed, replica_index
      integer(int64) :: temp_seed

      temp_seed = int(abs(base_seed), int64) + 104729_int64*int(replica_index, int64)
      seed_value = int(modulo(temp_seed, 2147483646_int64) + 1_int64)
   end function derive_replica_seed

   subroutine build_linear_ladder(n_replicas, max_flow_time, flow_ladder)
      integer, intent(in) :: n_replicas
      real(dp), intent(in) :: max_flow_time
      real(dp), allocatable, intent(out) :: flow_ladder(:)
      integer :: i

      allocate (flow_ladder(n_replicas))
      if (n_replicas == 1) then
         flow_ladder(1) = max_flow_time
      else
         do i = 1, n_replicas
            flow_ladder(i) = max_flow_time*real(i - 1, dp)/real(n_replicas - 1, dp)
         end do
      end if
   end subroutine build_linear_ladder

   subroutine parse_int_env(name, default_value, value_out)
      character(len=*), intent(in) :: name
      integer, intent(in) :: default_value
      integer, intent(out) :: value_out
      character(len=128) :: env_text
      integer :: env_len, env_status, ios

      value_out = default_value
      env_text = ""
      call get_environment_variable(name, env_text, length=env_len, status=env_status)
      if (env_status /= 0 .or. env_len <= 0) return

      read (env_text(1:env_len), *, iostat=ios) value_out
      if (ios /= 0) value_out = default_value
   end subroutine parse_int_env

   subroutine parse_real_env(name, default_value, value_out)
      character(len=*), intent(in) :: name
      real(dp), intent(in) :: default_value
      real(dp), intent(out) :: value_out
      character(len=128) :: env_text
      integer :: env_len, env_status, ios

      value_out = default_value
      env_text = ""
      call get_environment_variable(name, env_text, length=env_len, status=env_status)
      if (env_status /= 0 .or. env_len <= 0) return

      read (env_text(1:env_len), *, iostat=ios) value_out
      if (ios /= 0) value_out = default_value
   end subroutine parse_real_env

   subroutine parse_real_list(text, values, ok)
      character(len=*), intent(in) :: text
      real(dp), allocatable, intent(out) :: values(:)
      logical, intent(out) :: ok

      character(len=1024) :: cleaned
      character(len=128) :: token
      integer :: i, n, pos, count, ios
      logical :: has_token

      ok = .false.
      if (allocated(values)) deallocate (values)

      cleaned = adjustl(trim(text))
      n = len_trim(cleaned)
      if (n <= 0) return

      do i = 1, n
         if (cleaned(i:i) == ',' .or. cleaned(i:i) == ';') cleaned(i:i) = ' '
      end do

      count = 0
      pos = 1
      do
         call next_token(cleaned, pos, token, has_token)
         if (.not. has_token) exit
         count = count + 1
      end do
      if (count <= 0) return

      allocate (values(count))
      pos = 1
      i = 0
      do
         call next_token(cleaned, pos, token, has_token)
         if (.not. has_token) exit
         i = i + 1
         read (token, *, iostat=ios) values(i)
         if (ios /= 0) then
            deallocate (values)
            return
         end if
      end do

      ok = .true.
   end subroutine parse_real_list

   subroutine next_token(line, pos, token, found)
      character(len=*), intent(in) :: line
      integer, intent(inout) :: pos
      character(len=*), intent(out) :: token
      logical, intent(out) :: found
      integer :: n, start

      token = ""
      found = .false.
      n = len_trim(line)
      if (pos < 1) pos = 1

      do while (pos <= n .and. line(pos:pos) == ' ')
         pos = pos + 1
      end do
      if (pos > n) return

      start = pos
      do while (pos <= n .and. line(pos:pos) /= ' ')
         pos = pos + 1
      end do
      token = adjustl(line(start:pos - 1))
      found = .true.
   end subroutine next_token

end module tltm_stage1_driver

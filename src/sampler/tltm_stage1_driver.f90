module tltm_stage1_driver
   use, intrinsic :: iso_fortran_env, only: int64
   use param_mod, only: config, read_parameters
   use runtime_env_mod, only: parse_int_env, parse_real_env, read_string_env, parse_real_list
   use utils, only: dp, wall_time_seconds, x_set_flow_time, x_set_seed_real
   use solve_flow, only: flow, intode_status_unknown, intode_status_is_strict_success
   use model, only: grand
   use mt95, only: getseed, mt95_get_state, mt95_seed_state, mt95_set_state
   use markovchain_metropolis, only: metropolis_step
   use markovchain_phase, only: compute_phase_factor
   use hmc_constraints, only: reset_newton_eval_flow_status_counts, get_newton_eval_flow_status_counts
   use hmc_integrator_core, only: reset_reverse_gate_replay_status_counts, get_reverse_gate_replay_status_counts, &
                                  hmc_policy_context_t, hmc_replay_diagnostics_context_t
   use quasi_newton_solver_mod, only: reset_quasi_eval_flow_status_counts, get_quasi_eval_flow_status_counts, &
                                      qn_diagnostics_context_t, release_qn_diagnostics_context, &
                                      qn_policy_context_t, release_qn_policy_context
   use tltm_types_mod, only: tltm_replica_t, allocate_tltm_replica, release_tltm_replica, record_tltm_local_transition
   use tltm_run_context_mod, only: tltm_run_context_t, release_tltm_run_context
   implicit none

   integer, parameter :: stage1_cycle_cap_default = 200
   integer, parameter :: stage1_init_attempts_default = 200
   real(dp), parameter :: stage1_init_sigma_default = 0.10_dp

contains

   subroutine execute_tltm_stage1()
      type(tltm_replica_t), allocatable :: replicas(:)
      type(tltm_run_context_t), allocatable :: run_contexts(:)
      type(qn_diagnostics_context_t) :: qn_diagnostics_context
      type(qn_policy_context_t) :: qn_policy_context
      type(hmc_policy_context_t) :: hmc_policy_context
      type(hmc_replay_diagnostics_context_t) :: hmc_replay_diagnostics_context
      real(dp), allocatable :: flow_ladder(:)
      character(len=512) :: summary_file
      integer :: n_replicas, base_seed, cycle_count, local_updates, x_size
      real(dp) :: max_flow_time, init_sigma
      logical :: ok
      integer :: i, cycle_idx
      real(dp) :: run_t0, elapsed, replica_t0

      call read_parameters()
      call reset_newton_eval_flow_status_counts()
      call reset_quasi_eval_flow_status_counts(qn_diagnostics_context)
      call reset_reverse_gate_replay_status_counts(hmc_replay_diagnostics_context)

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
      write (*, '(A)') "[TLTM-S1] rng_stream_contract=per_replica_rng_v1"

      allocate (replicas(n_replicas), run_contexts(n_replicas))
      do i = 1, n_replicas
         replicas(i)%replica_id = i - 1
         replicas(i)%flow_time = flow_ladder(i)
         replicas(i)%rng_seed = derive_replica_seed(base_seed, i)
         call allocate_tltm_replica(replicas(i), x_size)
         call initialize_replica(replicas(i), init_sigma, stage1_init_attempts_default, ok, run_contexts(i))
         if (.not. ok) then
            write (*, '(A,I0,A,F8.4,A)') "[ERROR][TLTM-S1] Replica ", replicas(i)%replica_id, &
               " initialization failed at flow_time=", replicas(i)%flow_time, "."
            call release_qn_diagnostics_context(qn_diagnostics_context)
            call release_qn_policy_context(qn_policy_context)
            call release_all_run_contexts(run_contexts)
            call release_all_replicas(replicas)
            error stop 1
         end if
      end do

      run_t0 = wall_time_seconds()
      do cycle_idx = 1, cycle_count
         do i = 1, n_replicas
            replica_t0 = wall_time_seconds()
            call run_local_updates(replicas(i), local_updates, run_contexts(i), qn_diagnostics_context, qn_policy_context, &
                                   hmc_policy_context, hmc_replay_diagnostics_context)
            replicas(i)%local_runtime = replicas(i)%local_runtime + (wall_time_seconds() - replica_t0)
            call measure_replica(replicas(i))
         end do

         if (cycle_idx == 1 .or. mod(cycle_idx, 10) == 0 .or. cycle_idx == cycle_count) then
            write (*, '(A,I0,A,I0)') "[TLTM-S1] cycle ", cycle_idx, "/", cycle_count
         end if
      end do
      elapsed = wall_time_seconds() - run_t0

      call write_stage1_summary(summary_file, replicas, cycle_count, local_updates, elapsed, base_seed, qn_diagnostics_context, &
                                hmc_replay_diagnostics_context)
      call release_qn_diagnostics_context(qn_diagnostics_context)
      call release_qn_policy_context(qn_policy_context)
      call release_all_run_contexts(run_contexts)
      call release_all_replicas(replicas)
      if (allocated(flow_ladder)) deallocate (flow_ladder)

      write (*, '(A,1X,A)') "[DONE][TLTM-S1] Summary written to", trim(summary_file)
   end subroutine execute_tltm_stage1

   subroutine initialize_replica(replica, init_sigma, max_attempts, ok, run_context)
      type(tltm_replica_t), intent(inout) :: replica
      real(dp), intent(in) :: init_sigma
      integer, intent(in) :: max_attempts
      logical, intent(out) :: ok
      type(tltm_run_context_t), intent(inout) :: run_context

      real(dp), allocatable :: x_seed(:)
      logical :: flow_failed
      integer :: attempt, flow_status

      ok = .false.
      allocate (x_seed(max(1, size(replica%x) - 1)))
      call mt95_seed_state(replica%rng_state, replica%rng_seed)
      call mt95_set_state(replica%rng_state)

      do attempt = 1, max_attempts
         call grand(x_seed)
         x_seed = init_sigma*x_seed
         call x_set_flow_time(replica%x, replica%flow_time)
         call x_set_seed_real(replica%x, x_seed)
         flow_status = intode_status_unknown
         call flow(replica%x, replica%z, replica%jac, flow_failed, flow_status, run_context%flow%workspace)
         if ((.not. flow_failed) .and. intode_status_is_strict_success(flow_status)) then
            ok = .true.
            exit
         end if
      end do

      if (ok) then
         call mt95_get_state(replica%rng_state)
         call measure_replica(replica)
      end if
      if (allocated(x_seed)) deallocate (x_seed)
   end subroutine initialize_replica

   subroutine run_local_updates(replica, local_updates, run_context, qn_diagnostics_context, qn_policy_context, &
                                hmc_policy_context, hmc_replay_diagnostics_context)
      type(tltm_replica_t), intent(inout) :: replica
      integer, intent(in) :: local_updates
      type(tltm_run_context_t), intent(inout) :: run_context
      type(qn_diagnostics_context_t), intent(inout), target :: qn_diagnostics_context
      type(qn_policy_context_t), intent(inout), target :: qn_policy_context
      type(hmc_policy_context_t), intent(inout), target :: hmc_policy_context
      type(hmc_replay_diagnostics_context_t), intent(inout), target :: hmc_replay_diagnostics_context

      integer :: update_idx, z_size
      real(dp), allocatable :: x_new(:)
      complex(dp), allocatable :: z_new(:), j_new(:, :)
      logical :: accepted, proposal_failed
      integer :: transition_status

      z_size = size(replica%z)
      allocate (x_new(size(replica%x)))
      allocate (z_new(z_size), j_new(z_size, z_size))

      call mt95_set_state(replica%rng_state)
      do update_idx = 1, local_updates
         call metropolis_step(replica%x, replica%z, replica%jac, config%integrator%trajectory_length, &
                              config%integrator%integration_steps, x_new, z_new, j_new, accepted, proposal_failed, transition_status, &
                              context=run_context%hmc, flow_workspace=run_context%flow%workspace, &
                              qn_context=run_context%qn%workspace, qn_diagnostics=qn_diagnostics_context, qn_policy=qn_policy_context, &
                              hmc_policy=hmc_policy_context, hmc_replay_diagnostics=hmc_replay_diagnostics_context, &
                              hmc_reversibility=run_context%diagnostics%hmc_reversibility)
         if (accepted) then
            replica%x = x_new
            replica%z = z_new
            replica%jac = j_new
         end if
         call record_tltm_local_transition(replica, accepted, proposal_failed, transition_status)
      end do
      call mt95_get_state(replica%rng_state)

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
      integer :: ios
      logical :: has_seed_env

      seed_env = ""
      call read_string_env("CHAIN_RNG_SEED", seed_env, has_seed_env)
      if (has_seed_env) then
         read (seed_env, *, iostat=ios) base_seed
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
      logical :: ok
      logical :: has_ladder_env
      real(dp), allocatable :: parsed(:)

      n_replicas = 2
      call parse_int_env("TLTM_STAGE1_NUM_REPLICAS", n_replicas)
      if (n_replicas < 1) then
         write (*, '(A)') "[ERROR][TLTM-S1] TLTM_STAGE1_NUM_REPLICAS must be >= 1."
         error stop 1
      end if

      max_flow_time = max(0.0_dp, default_max_flow)
      call parse_real_env("TLTM_STAGE1_MAX_FLOW_TIME", max_flow_time)
      if (max_flow_time < 0.0_dp) then
         write (*, '(A)') "[ERROR][TLTM-S1] TLTM_STAGE1_MAX_FLOW_TIME must be >= 0."
         error stop 1
      end if

      ladder_text = ""
      call read_string_env("TLTM_STAGE1_FLOW_TIME_LADDER", ladder_text, has_ladder_env)
      if (has_ladder_env) then
         call parse_real_list(ladder_text, parsed, ok)
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
      call parse_int_env("TLTM_STAGE1_CYCLES", cycle_count)
      if (cycle_count < 1) then
         write (*, '(A)') "[ERROR][TLTM-S1] TLTM_STAGE1_CYCLES must be >= 1."
         error stop 1
      end if

      local_updates = max(1, config_hmc_repeat)
      call parse_int_env("TLTM_STAGE1_LOCAL_UPDATES", local_updates)
      if (local_updates < 1) then
         write (*, '(A)') "[ERROR][TLTM-S1] TLTM_STAGE1_LOCAL_UPDATES must be >= 1."
         error stop 1
      end if

      init_sigma = stage1_init_sigma_default
      call parse_real_env("TLTM_STAGE1_INIT_SIGMA", init_sigma)
      if (init_sigma <= 0.0_dp) then
         write (*, '(A)') "[ERROR][TLTM-S1] TLTM_STAGE1_INIT_SIGMA must be > 0."
         error stop 1
      end if
   end subroutine resolve_stage1_controls

   subroutine resolve_summary_file(path)
      character(len=*), intent(out) :: path

      path = "../output/tests/tltm_stage1_summary.dat"
      call read_string_env("TLTM_STAGE1_SUMMARY_FILE", path)
   end subroutine resolve_summary_file

   subroutine write_stage1_summary(summary_file, replicas, cycle_count, local_updates, elapsed, base_seed, qn_diagnostics_context, &
                                   hmc_replay_diagnostics_context)
      character(len=*), intent(in) :: summary_file
      type(tltm_replica_t), intent(in) :: replicas(:)
      integer, intent(in) :: cycle_count, local_updates, base_seed
      real(dp), intent(in) :: elapsed
      type(qn_diagnostics_context_t), intent(inout), target :: qn_diagnostics_context
      type(hmc_replay_diagnostics_context_t), intent(inout), target :: hmc_replay_diagnostics_context

      integer, parameter :: unit_summary = 77
      integer :: ios, i, total_count
      integer :: metropolis_reject_total, reverse_gate_reject_total, proposal_failure_total
      integer :: hamiltonian_invalid_total, delta_h_invalid_total, output_size_mismatch_total
      real(dp) :: accept_rate, abs_mean_phi
      integer(int64) :: qn_flow_success_count, qn_flow_zero_time_count, qn_flow_stiff_rescue_count
      integer(int64) :: qn_flow_solver_assist_count, qn_flow_failure_max_steps_count, qn_flow_failure_invalid_count
      integer(int64) :: qn_flow_failure_h_min_count, qn_flow_unknown_count
      integer(int64) :: newton_flow_success_count, newton_flow_zero_time_count, newton_flow_stiff_rescue_count
      integer(int64) :: newton_flow_solver_assist_count, newton_flow_failure_max_steps_count, newton_flow_failure_invalid_count
      integer(int64) :: newton_flow_failure_h_min_count, newton_flow_unknown_count
      integer(int64) :: rg_replay_success_count, rg_replay_output_size_mismatch_count, rg_replay_momentum_size_mismatch_count
      integer(int64) :: rg_replay_initial_force_failed_count, rg_replay_constraint_failed_count, rg_replay_final_flow_failed_count
      integer(int64) :: rg_replay_final_force_failed_count, rg_replay_final_projection_failed_count, rg_replay_reverse_gate_rejected_count
      integer(int64) :: rg_replay_final_flow_max_steps_count, rg_replay_final_flow_invalid_count, rg_replay_final_flow_h_min_count
      integer(int64) :: rg_replay_final_flow_non_strict_success_count, rg_replay_unknown_count

      open (unit=unit_summary, file=trim(summary_file), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S1] Cannot open summary file:", trim(summary_file)
         error stop 1
      end if

      write (unit_summary, '(A)') "# TLTM stage-1 summary"
      write (unit_summary, '(A,I0)') "# replicas=", size(replicas)
      write (unit_summary, '(A,I0)') "# cycles=", cycle_count
      write (unit_summary, '(A,I0)') "# local_updates=", local_updates
      write (unit_summary, '(A)') "# rng_stream_contract=per_replica_rng_v1"
      write (unit_summary, '(A)') "# seed_policy=CHAIN_RNG_SEED base seed plus deterministic per-replica local-update streams"
      write (unit_summary, '(A,I0)') "# base_seed=", base_seed
      write (unit_summary, '(A,F12.6)') "# elapsed_sec=", elapsed
      call get_newton_eval_flow_status_counts(newton_flow_success_count, newton_flow_zero_time_count, newton_flow_stiff_rescue_count, &
                                              newton_flow_solver_assist_count, newton_flow_failure_max_steps_count, &
                                              newton_flow_failure_invalid_count, newton_flow_failure_h_min_count, newton_flow_unknown_count)
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# newton_eval_flow_status success=", newton_flow_success_count, " zero_time=", newton_flow_zero_time_count, &
         " stiff_rescue=", newton_flow_stiff_rescue_count, " solver_assist=", newton_flow_solver_assist_count, &
         " failure_max_steps=", newton_flow_failure_max_steps_count, " failure_invalid=", newton_flow_failure_invalid_count, &
         " failure_h_min=", newton_flow_failure_h_min_count, " unknown=", newton_flow_unknown_count
      call get_reverse_gate_replay_status_counts(rg_replay_success_count, rg_replay_output_size_mismatch_count, &
                                                 rg_replay_momentum_size_mismatch_count, rg_replay_initial_force_failed_count, &
                                                 rg_replay_constraint_failed_count, rg_replay_final_flow_failed_count, &
                                                 rg_replay_final_force_failed_count, rg_replay_final_projection_failed_count, &
                                                 rg_replay_reverse_gate_rejected_count, rg_replay_final_flow_max_steps_count, &
                                                 rg_replay_final_flow_invalid_count, rg_replay_final_flow_h_min_count, &
                                                 rg_replay_final_flow_non_strict_success_count, rg_replay_unknown_count, &
                                                 hmc_replay_diagnostics_context)
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# reverse_gate_replay_status success=", rg_replay_success_count, &
         " output_size_mismatch=", rg_replay_output_size_mismatch_count, &
         " momentum_size_mismatch=", rg_replay_momentum_size_mismatch_count, &
         " initial_force_failed=", rg_replay_initial_force_failed_count, " constraint_failed=", rg_replay_constraint_failed_count, &
         " final_flow_failed=", rg_replay_final_flow_failed_count, " final_force_failed=", rg_replay_final_force_failed_count, &
         " final_projection_failed=", rg_replay_final_projection_failed_count, &
         " reverse_gate_rejected=", rg_replay_reverse_gate_rejected_count, &
         " final_flow_max_steps=", rg_replay_final_flow_max_steps_count, " final_flow_invalid=", rg_replay_final_flow_invalid_count, &
         " final_flow_h_min=", rg_replay_final_flow_h_min_count, &
         " final_flow_non_strict_success=", rg_replay_final_flow_non_strict_success_count, " unknown=", rg_replay_unknown_count
      call get_quasi_eval_flow_status_counts(qn_flow_success_count, qn_flow_zero_time_count, qn_flow_stiff_rescue_count, &
                                             qn_flow_solver_assist_count, qn_flow_failure_max_steps_count, &
                                             qn_flow_failure_invalid_count, qn_flow_failure_h_min_count, qn_flow_unknown_count, &
                                             qn_diagnostics_context)
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# qn_eval_flow_status success=", qn_flow_success_count, " zero_time=", qn_flow_zero_time_count, &
         " stiff_rescue=", qn_flow_stiff_rescue_count, " solver_assist=", qn_flow_solver_assist_count, &
         " failure_max_steps=", qn_flow_failure_max_steps_count, " failure_invalid=", qn_flow_failure_invalid_count, &
         " failure_h_min=", qn_flow_failure_h_min_count, " unknown=", qn_flow_unknown_count
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

   subroutine release_all_run_contexts(run_contexts)
      type(tltm_run_context_t), allocatable, intent(inout) :: run_contexts(:)
      integer :: i

      if (.not. allocated(run_contexts)) return
      do i = 1, size(run_contexts)
         call release_tltm_run_context(run_contexts(i))
      end do
      deallocate (run_contexts)
   end subroutine release_all_run_contexts

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

end module tltm_stage1_driver

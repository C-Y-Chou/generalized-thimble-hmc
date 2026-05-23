program compare_swap_reflow_backends
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use, intrinsic :: iso_fortran_env, only: int64
   use model, only: calculate_action
   use param_mod, only: config, read_parameters
   use runtime_env_mod, only: parse_real_list
   use solve_flow, only: flow_at, flow_at_dense_targets, flow_continue, flow_workspace_t, intode_status_is_strict_success, &
                         intode_status_unknown
   use utils, only: dp, log_determinant, wall_time_seconds
   implicit none

   character(len=512) :: input_x_file, target_text
   integer :: argc, record_start, record_count, record_stride, state_size
   real(dp), allocatable :: target_times(:)
   logical :: ok

   argc = command_argument_count()
   if (argc < 5 .or. argc > 6) call usage_and_stop()
   call get_command_argument(1, input_x_file)
   call get_command_argument(2, target_text)
   call read_integer_arg(3, record_start)
   call read_integer_arg(4, record_count)
   call read_integer_arg(5, record_stride)
   if (record_start < 0 .or. record_count < 1 .or. record_stride < 1) call usage_and_stop()

   call parse_real_list(trim(target_text), target_times, ok)
   if ((.not. ok) .or. size(target_times) < 1) then
      write (*, '(A)') "[ERROR][SWAP-REFLOW-CMP] target times must be a nonempty comma-separated real list."
      stop 2
   end if
   if (.not. target_times_are_valid(target_times)) then
      write (*, '(A)') "[ERROR][SWAP-REFLOW-CMP] target times must be finite, nonnegative, and nondecreasing."
      stop 2
   end if

   call read_parameters()
   state_size = config%state%z_size
   if (state_size < 1) then
      write (*, '(A)') "[ERROR][SWAP-REFLOW-CMP] invalid physical state size."
      stop 2
   end if

   call compare_backends(trim(input_x_file), target_times, record_start, record_count, record_stride, state_size)

contains

   subroutine usage_and_stop()
      write (*, '(A)') "Usage: compare_swap_reflow_backends INPUT_X_BANK TARGET_TIMES RECORD_START RECORD_COUNT RECORD_STRIDE"
      write (*, '(A)') "Example: TLTM_PARAMETERS_FILE=data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat " // &
                       "bin/compare_swap_reflow_backends x_bank.dat 0,0.01,0.03 0 2 40"
      stop 2
   end subroutine usage_and_stop

   subroutine read_integer_arg(arg_idx, value)
      integer, intent(in) :: arg_idx
      integer, intent(out) :: value
      character(len=128) :: text
      integer :: ios

      call get_command_argument(arg_idx, text)
      read (text, *, iostat=ios) value
      if (ios /= 0) call usage_and_stop()
   end subroutine read_integer_arg

   pure logical function target_times_are_valid(times) result(valid)
      real(dp), intent(in) :: times(:)
      integer :: i

      valid = .true.
      do i = 1, size(times)
         if ((.not. ieee_is_finite(times(i))) .or. times(i) < 0.0_dp) then
            valid = .false.
            return
         end if
         if (i > 1 .and. times(i) < times(i - 1)) then
            valid = .false.
            return
         end if
      end do
   end function target_times_are_valid

   subroutine compare_backends(input_file, times, start_record, n_records, stride, n)
      character(len=*), intent(in) :: input_file
      real(dp), intent(in) :: times(:)
      integer, intent(in) :: start_record, n_records, stride, n

      integer :: unit_x, ios, rec_idx, target_idx, source_record, n_targets
      integer :: direct_status, dense_status, multi_status, continue_status
      integer(int64) :: pos_bytes, record_bytes
      real(dp) :: t0, direct_sec, dense_single_sec, dense_multi_sec, continue_sec
      real(dp) :: max_z_single, max_j_single, max_e_single, max_z_multi, max_j_multi, max_e_multi
      real(dp) :: max_z_continue, max_j_continue, max_e_continue, continue_energy_value
      real(dp) :: max_acc_single, max_acc_multi
      integer :: success_direct, success_dense_single, success_dense_multi, success_continue, continue_attempts
      integer :: status_mismatch_single, status_mismatch_multi, status_mismatch_continue, unavailable_single, unavailable_multi
      integer :: pair_count, decision_mismatch_single, decision_mismatch_multi
      real(dp), allocatable :: x_state(:), z_direct(:, :), z_single(:, :), z_multi(:, :)
      complex(dp), allocatable :: cz_direct(:), cz_continue(:), cz_single(:, :), cz_multi(:, :)
      complex(dp), allocatable :: cj_direct(:, :), cj_continue(:, :), cj_single(:, :, :), cj_multi(:, :, :)
      complex(dp), allocatable :: cz_direct_all(:, :), cj_direct_all(:, :, :)
      real(dp), allocatable :: direct_energy(:, :), single_energy(:, :), multi_energy(:, :)
      logical, allocatable :: direct_ok(:, :), single_ok(:, :), multi_ok(:, :)
      real(dp) :: single_times(1)
      logical :: direct_failed, dense_failed, multi_failed, continue_failed, continue_ok, continue_energy_ok, single_available(1)
      logical, allocatable :: multi_available(:)
      type(flow_workspace_t) :: direct_workspace, single_workspace, multi_workspace, continue_workspace

      n_targets = size(times)
      allocate (x_state(n))
      allocate (z_direct(n, n_targets), z_single(n, n_targets), z_multi(n, n_targets))
      allocate (cz_direct(n), cz_continue(n), cz_single(n, n_targets), cz_multi(n, n_targets))
      allocate (cj_direct(n, n), cj_continue(n, n), cj_single(n, n, n_targets), cj_multi(n, n, n_targets))
      allocate (cz_direct_all(n, n_targets), cj_direct_all(n, n, n_targets))
      allocate (direct_energy(n_records, n_targets), single_energy(n_records, n_targets), multi_energy(n_records, n_targets))
      allocate (direct_ok(n_records, n_targets), single_ok(n_records, n_targets), multi_ok(n_records, n_targets))
      allocate (multi_available(n_targets))

      direct_sec = 0.0_dp
      dense_single_sec = 0.0_dp
      dense_multi_sec = 0.0_dp
      continue_sec = 0.0_dp
      max_z_single = 0.0_dp
      max_j_single = 0.0_dp
      max_e_single = 0.0_dp
      max_z_multi = 0.0_dp
      max_j_multi = 0.0_dp
      max_e_multi = 0.0_dp
      max_z_continue = 0.0_dp
      max_j_continue = 0.0_dp
      max_e_continue = 0.0_dp
      success_direct = 0
      success_dense_single = 0
      success_dense_multi = 0
      success_continue = 0
      continue_attempts = 0
      status_mismatch_single = 0
      status_mismatch_multi = 0
      status_mismatch_continue = 0
      unavailable_single = 0
      unavailable_multi = 0
      direct_ok = .false.
      single_ok = .false.
      multi_ok = .false.
      direct_energy = 0.0_dp
      single_energy = 0.0_dp
      multi_energy = 0.0_dp

      open (newunit=unit_x, file=trim(input_file), status='old', access='stream', form='unformatted', action='read', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][SWAP-REFLOW-CMP] cannot open input x bank:", trim(input_file)
         stop 2
      end if

      record_bytes = int(n, int64)*8_int64
      do rec_idx = 1, n_records
         source_record = start_record + (rec_idx - 1)*stride
         pos_bytes = 1_int64 + int(source_record, int64)*record_bytes
         read (unit_x, pos=pos_bytes, iostat=ios) x_state
         if (ios /= 0) then
            write (*, '(A,I0,A,1X,A)') "[ERROR][SWAP-REFLOW-CMP] cannot read source_record=", source_record, &
               " file=", trim(input_file)
            stop 2
         end if
         if (any(.not. ieee_is_finite(x_state))) then
            write (*, '(A,I0)') "[ERROR][SWAP-REFLOW-CMP] nonfinite x source_record=", source_record
            stop 2
         end if

         t0 = wall_time_seconds()
         call flow_at_dense_targets(times, x_state, cz_multi, cj_multi, multi_available, multi_failed, multi_status, &
                                    multi_workspace)
         dense_multi_sec = dense_multi_sec + (wall_time_seconds() - t0)

         do target_idx = 1, n_targets
            direct_status = intode_status_unknown
            t0 = wall_time_seconds()
            call flow_at(times(target_idx), x_state, cz_direct, cj_direct, direct_failed, direct_status, direct_workspace)
            direct_sec = direct_sec + (wall_time_seconds() - t0)
            direct_ok(rec_idx, target_idx) = (.not. direct_failed) .and. intode_status_is_strict_success(direct_status)
            if (direct_ok(rec_idx, target_idx)) then
               z_direct(:, target_idx) = real(cz_direct, dp)
               cz_direct_all(:, target_idx) = cz_direct
               cj_direct_all(:, :, target_idx) = cj_direct
               success_direct = success_direct + 1
               call effective_energy(cz_direct, cj_direct, direct_energy(rec_idx, target_idx), direct_ok(rec_idx, target_idx))
            end if

            single_times(1) = times(target_idx)
            dense_status = intode_status_unknown
            t0 = wall_time_seconds()
            call flow_at_dense_targets(single_times, x_state, cz_single(:, target_idx:target_idx), &
                                       cj_single(:, :, target_idx:target_idx), single_available, dense_failed, dense_status, &
                                       single_workspace)
            dense_single_sec = dense_single_sec + (wall_time_seconds() - t0)
            single_ok(rec_idx, target_idx) = (.not. dense_failed) .and. single_available(1) .and. &
                                             intode_status_is_strict_success(dense_status)
            if (single_ok(rec_idx, target_idx)) then
               z_single(:, target_idx) = real(cz_single(:, target_idx), dp)
               success_dense_single = success_dense_single + 1
               call effective_energy(cz_single(:, target_idx), cj_single(:, :, target_idx), &
                                     single_energy(rec_idx, target_idx), single_ok(rec_idx, target_idx))
            else if (.not. single_available(1)) then
               unavailable_single = unavailable_single + 1
            end if

            multi_ok(rec_idx, target_idx) = multi_available(target_idx)
            if (multi_ok(rec_idx, target_idx)) then
               z_multi(:, target_idx) = real(cz_multi(:, target_idx), dp)
               success_dense_multi = success_dense_multi + 1
               call effective_energy(cz_multi(:, target_idx), cj_multi(:, :, target_idx), &
                                     multi_energy(rec_idx, target_idx), multi_ok(rec_idx, target_idx))
            else if (.not. multi_available(target_idx)) then
               unavailable_multi = unavailable_multi + 1
            end if

            if (direct_ok(rec_idx, target_idx) .neqv. single_ok(rec_idx, target_idx)) status_mismatch_single = status_mismatch_single + 1
            if (direct_ok(rec_idx, target_idx) .neqv. multi_ok(rec_idx, target_idx)) status_mismatch_multi = status_mismatch_multi + 1
            if (direct_ok(rec_idx, target_idx) .and. single_ok(rec_idx, target_idx)) then
               max_z_single = max(max_z_single, maxval(abs(cz_direct - cz_single(:, target_idx))))
               max_j_single = max(max_j_single, maxval(abs(cj_direct - cj_single(:, :, target_idx))))
               max_e_single = max(max_e_single, abs(direct_energy(rec_idx, target_idx) - single_energy(rec_idx, target_idx)))
            end if
            if (direct_ok(rec_idx, target_idx) .and. multi_ok(rec_idx, target_idx)) then
               max_z_multi = max(max_z_multi, maxval(abs(cz_direct - cz_multi(:, target_idx))))
               max_j_multi = max(max_j_multi, maxval(abs(cj_direct - cj_multi(:, :, target_idx))))
               max_e_multi = max(max_e_multi, abs(direct_energy(rec_idx, target_idx) - multi_energy(rec_idx, target_idx)))
            end if
         end do

         do target_idx = 1, n_targets - 1
            if (.not. direct_ok(rec_idx, target_idx)) cycle
            continue_attempts = continue_attempts + 1
            continue_status = intode_status_unknown
            t0 = wall_time_seconds()
            call flow_continue(times(target_idx), times(target_idx + 1), cz_direct_all(:, target_idx), &
                               cj_direct_all(:, :, target_idx), cz_continue, cj_continue, continue_failed, &
                               continue_status, continue_workspace)
            continue_sec = continue_sec + (wall_time_seconds() - t0)
            continue_ok = (.not. continue_failed) .and. intode_status_is_strict_success(continue_status)
            if (continue_ok) then
               success_continue = success_continue + 1
               call effective_energy(cz_continue, cj_continue, continue_energy_value, continue_energy_ok)
            else
               continue_energy_ok = .false.
            end if
            if (direct_ok(rec_idx, target_idx + 1) .neqv. continue_ok) status_mismatch_continue = status_mismatch_continue + 1
            if (direct_ok(rec_idx, target_idx + 1) .and. continue_ok) then
               max_z_continue = max(max_z_continue, maxval(abs(cz_direct_all(:, target_idx + 1) - cz_continue)))
               max_j_continue = max(max_j_continue, maxval(abs(cj_direct_all(:, :, target_idx + 1) - cj_continue)))
               if (continue_energy_ok) then
                  max_e_continue = max(max_e_continue, abs(direct_energy(rec_idx, target_idx + 1) - continue_energy_value))
               end if
            end if
         end do
      end do
      close (unit_x)

      call compare_swap_acceptance(direct_energy, single_energy, multi_energy, direct_ok, single_ok, multi_ok, &
                                   max_acc_single, max_acc_multi, decision_mismatch_single, decision_mismatch_multi, pair_count)

      write (*, '(A)') "[SWAP-REFLOW-CMP] schema=swap_reflow_backend_comparison.v1"
      write (*, '(A,1X,A)') "[SWAP-REFLOW-CMP] input_x_bank=", trim(input_file)
      write (*, '(A,I0,A,I0,A,I0,A,I0)') "[SWAP-REFLOW-CMP] record_start=", start_record, &
         " record_count=", n_records, " record_stride=", stride, " target_count=", n_targets
      write (*, '(A,I0,A,I0,A,I0)') "[SWAP-REFLOW-CMP] successes direct=", success_direct, &
         " dense_single=", success_dense_single, " dense_multi=", success_dense_multi
      write (*, '(A,I0,A,I0)') "[SWAP-REFLOW-CMP] continue_adjacent attempts=", continue_attempts, &
         " successes=", success_continue
      write (*, '(A,I0,A,I0,A,I0,A,I0)') "[SWAP-REFLOW-CMP] mismatches single=", status_mismatch_single, &
         " multi=", status_mismatch_multi, " unavailable_single=", unavailable_single, " unavailable_multi=", unavailable_multi
      write (*, '(A,I0)') "[SWAP-REFLOW-CMP] continue_adjacent_status_mismatches=", status_mismatch_continue
      write (*, '(A,3(1X,ES14.6E3))') "[SWAP-REFLOW-CMP] single_max_abs z jac energy=", &
         max_z_single, max_j_single, max_e_single
      write (*, '(A,3(1X,ES14.6E3))') "[SWAP-REFLOW-CMP] multi_max_abs z jac energy=", &
         max_z_multi, max_j_multi, max_e_multi
      write (*, '(A,3(1X,ES14.6E3))') "[SWAP-REFLOW-CMP] continue_adjacent_max_abs z jac energy=", &
         max_z_continue, max_j_continue, max_e_continue
      write (*, '(A,I0,A,ES14.6E3,A,ES14.6E3,A,I0,A,I0)') "[SWAP-REFLOW-CMP] adjacent_accept pairs=", pair_count, &
         " max_abs_single=", max_acc_single, " max_abs_multi=", max_acc_multi, &
         " decision_mismatch_single=", decision_mismatch_single, " decision_mismatch_multi=", decision_mismatch_multi
      write (*, '(A,3(1X,F12.6))') "[SWAP-REFLOW-CMP] wall_sec direct_all dense_single_all dense_multi_all=", &
         direct_sec, dense_single_sec, dense_multi_sec
      write (*, '(A,1X,F12.6)') "[SWAP-REFLOW-CMP] wall_sec continue_adjacent_all=", continue_sec
      if (direct_sec > 0.0_dp) then
         write (*, '(A,2(1X,F12.6))') "[SWAP-REFLOW-CMP] speed_ratio direct_over_dense_single direct_over_dense_multi=", &
            direct_sec/dense_single_sec, direct_sec/dense_multi_sec
      end if
   end subroutine compare_backends

   subroutine effective_energy(z, jac, energy, ok)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: energy
      logical, intent(out) :: ok

      complex(dp) :: action_value, log_det_j
      logical :: det_error

      energy = 0.0_dp
      ok = .false.
      if (size(jac, 1) /= size(z) .or. size(jac, 2) /= size(z)) return
      if (any(.not. ieee_is_finite(real(z, dp))) .or. any(.not. ieee_is_finite(aimag(z))) .or. &
          any(.not. ieee_is_finite(real(jac, dp))) .or. any(.not. ieee_is_finite(aimag(jac)))) return
      call calculate_action(z, action_value)
      call log_determinant(jac, log_det_j, det_error)
      if (det_error) return
      energy = real(action_value, dp) - real(log_det_j, dp)
      ok = ieee_is_finite(energy)
      if (.not. ok) energy = 0.0_dp
   end subroutine effective_energy

   subroutine compare_swap_acceptance(e_direct, e_single, e_multi, ok_direct, ok_single, ok_multi, &
                                      max_acc_single, max_acc_multi, decision_mismatch_single, &
                                      decision_mismatch_multi, pair_count)
      real(dp), intent(in) :: e_direct(:, :), e_single(:, :), e_multi(:, :)
      logical, intent(in) :: ok_direct(:, :), ok_single(:, :), ok_multi(:, :)
      real(dp), intent(out) :: max_acc_single, max_acc_multi
      integer, intent(out) :: decision_mismatch_single, decision_mismatch_multi, pair_count

      integer :: rec_idx, target_idx, uniform_idx
      real(dp) :: p_direct, p_single, p_multi, uniform_value
      real(dp), parameter :: uniform_grid(7) = [0.0_dp, 0.1_dp, 0.25_dp, 0.5_dp, 0.75_dp, 0.9_dp, 0.999999_dp]

      max_acc_single = 0.0_dp
      max_acc_multi = 0.0_dp
      decision_mismatch_single = 0
      decision_mismatch_multi = 0
      pair_count = 0
      if (size(e_direct, 1) < 2 .or. size(e_direct, 2) < 2) return
      do rec_idx = 1, size(e_direct, 1) - 1
         do target_idx = 1, size(e_direct, 2) - 1
            if (ok_direct(rec_idx, target_idx) .and. ok_direct(rec_idx, target_idx + 1) .and. &
                ok_direct(rec_idx + 1, target_idx) .and. ok_direct(rec_idx + 1, target_idx + 1)) then
               p_direct = swap_accept_probability(e_direct(rec_idx + 1, target_idx) + e_direct(rec_idx, target_idx + 1) - &
                                                  e_direct(rec_idx, target_idx) - e_direct(rec_idx + 1, target_idx + 1))
               if (ok_single(rec_idx, target_idx) .and. ok_single(rec_idx, target_idx + 1) .and. &
                   ok_single(rec_idx + 1, target_idx) .and. ok_single(rec_idx + 1, target_idx + 1)) then
                  p_single = swap_accept_probability(e_single(rec_idx + 1, target_idx) + e_single(rec_idx, target_idx + 1) - &
                                                     e_single(rec_idx, target_idx) - e_single(rec_idx + 1, target_idx + 1))
                  max_acc_single = max(max_acc_single, abs(p_direct - p_single))
                  do uniform_idx = 1, size(uniform_grid)
                     uniform_value = uniform_grid(uniform_idx)
                     if ((uniform_value <= p_direct) .neqv. (uniform_value <= p_single)) then
                        decision_mismatch_single = decision_mismatch_single + 1
                     end if
                  end do
               end if
               if (ok_multi(rec_idx, target_idx) .and. ok_multi(rec_idx, target_idx + 1) .and. &
                   ok_multi(rec_idx + 1, target_idx) .and. ok_multi(rec_idx + 1, target_idx + 1)) then
                  p_multi = swap_accept_probability(e_multi(rec_idx + 1, target_idx) + e_multi(rec_idx, target_idx + 1) - &
                                                    e_multi(rec_idx, target_idx) - e_multi(rec_idx + 1, target_idx + 1))
                  max_acc_multi = max(max_acc_multi, abs(p_direct - p_multi))
                  do uniform_idx = 1, size(uniform_grid)
                     uniform_value = uniform_grid(uniform_idx)
                     if ((uniform_value <= p_direct) .neqv. (uniform_value <= p_multi)) then
                        decision_mismatch_multi = decision_mismatch_multi + 1
                     end if
                  end do
               end if
               pair_count = pair_count + 1
            end if
         end do
      end do
   end subroutine compare_swap_acceptance

   pure real(dp) function swap_accept_probability(delta) result(probability)
      real(dp), intent(in) :: delta

      if (delta <= 0.0_dp) then
         probability = 1.0_dp
      else
         probability = exp(-delta)
      end if
   end function swap_accept_probability

end program compare_swap_reflow_backends

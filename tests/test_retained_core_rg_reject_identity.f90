program test_retained_core_rg_reject_identity
   use hmc, only: hmc_proposal_status_reverse_gate_rejected, integrate_hmc_proposal
   use markovchain_metropolis, only: metropolis_step
   use markovchain_transition_status, only: metropolis_status_reverse_gate_rejected
   use param_mod, only: istest, read_parameters, state_seed_size_cfg, testmom
   use solve_flow, only: flow, intode_status_is_strict_success, intode_status_unknown
   use tltm_types_mod, only: allocate_tltm_slot, make_tltm_local_transition_event, release_tltm_slot, &
                              record_tltm_local_transition, tltm_counter_denominator_local_transition, &
                              tltm_diag_schema_version_local_transition, tltm_event_context_local_transition, &
                              tltm_local_transition_event_t, tltm_slot_t
   use utils, only: dp, x_set_flow_time, x_set_seed_real
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   implicit none

   integer :: failures, n_seed, x_size, flow_status, proposal_status, transition_status
   real(dp), allocatable :: seed(:), x(:), hmc_x(:), metro_x(:)
   complex(dp), allocatable :: z(:), hmc_z(:), metro_z(:), jac(:,:), hmc_jac(:,:), metro_jac(:,:)
   real(dp) :: h_initial, h_final
   logical :: flow_failed, proposal_ok, accepted, proposal_failed, found_reject

   failures = 0
   call read_parameters()
   n_seed = state_seed_size_cfg()
   x_size = 1 + n_seed

   allocate (seed(n_seed), x(x_size), hmc_x(x_size), metro_x(x_size))
   allocate (z(n_seed), hmc_z(n_seed), metro_z(n_seed))
   allocate (jac(n_seed, n_seed), hmc_jac(n_seed, n_seed), metro_jac(n_seed, n_seed))

   call fill_seed(seed)
   call x_set_flow_time(x, 0.08_dp)
   call x_set_seed_real(x, seed)
   flow_status = intode_status_unknown
   call flow(x, z, jac, flow_failed, flow_status)
   if (flow_failed .or. (.not. intode_status_is_strict_success(flow_status))) then
      write (*, '(A,I0)') "[ERROR] initial flow failed. status=", flow_status
      error stop 1
   end if

   istest = .true.
   found_reject = .false.
   call set_test_momentum(1.0_dp)

   call integrate_hmc_proposal(x, z, 0.002_dp, 1, hmc_x, hmc_z, h_initial, h_final, jac, hmc_jac, &
                               proposal_ok, proposal_status)
   found_reject = (.not. proposal_ok) .and. proposal_status == hmc_proposal_status_reverse_gate_rejected
   call check_hmc_reject_identity(found_reject, proposal_ok, proposal_status, hmc_x, hmc_z, hmc_jac, jac, failures)

   call set_test_momentum(1.0_dp)
   call metropolis_step(x, z, jac, 0.002_dp, 1, metro_x, metro_z, metro_jac, accepted, proposal_failed, transition_status)
   call check_metropolis_reject_identity(accepted, proposal_failed, transition_status, metro_x, metro_z, metro_jac, jac, failures)
   call check_transition_accounting(accepted, proposal_failed, transition_status, failures)

   istest = .false.

   deallocate (seed, x, hmc_x, metro_x)
   deallocate (z, hmc_z, metro_z)
   deallocate (jac, hmc_jac, metro_jac)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] retained-core RG reject identity failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] retained-core RG reject identity contract complete."

contains

   subroutine fill_seed(seed)
      real(dp), intent(out) :: seed(:)
      integer :: i

      do i = 1, size(seed)
         seed(i) = 0.12_dp + 0.04_dp*real(i - 1, dp)
      end do
   end subroutine fill_seed

   subroutine set_test_momentum(scale)
      real(dp), intent(in) :: scale
      integer :: i

      do i = 1, size(testmom)
         testmom(i) = scale*(0.75_dp + 0.05_dp*real(i, dp))
         if (mod(i, 2) == 0) testmom(i) = -testmom(i)
      end do
   end subroutine set_test_momentum

   subroutine check_hmc_reject_identity(found_reject, proposal_ok, proposal_status, out_x, out_z, out_jac, in_jac, failures)
      logical, intent(in) :: found_reject, proposal_ok
      integer, intent(in) :: proposal_status
      real(dp), intent(in) :: out_x(:)
      complex(dp), intent(in) :: out_z(:), out_jac(:, :), in_jac(:, :)
      integer, intent(inout) :: failures
      logical :: ok
      real(dp) :: dx, dz, dj

      dx = maxabs_real(out_x - x)
      dz = maxabs_complex(out_z - z)
      dj = maxabs_complex_mat(out_jac - in_jac)
      ok = found_reject .and. (.not. proposal_ok) .and. proposal_status == hmc_proposal_status_reverse_gate_rejected .and. &
           ieee_is_finite(dx) .and. ieee_is_finite(dz) .and. ieee_is_finite(dj) .and. &
           dx == 0.0_dp .and. dz == 0.0_dp .and. dj == 0.0_dp
      write (*, '(A,L1,A,L1,A,I0,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] hmc_rg_reject_stay_put ok=", ok, &
         " proposal_ok=", proposal_ok, " status=", proposal_status, " dx=", dx, " dz=", dz, " dj=", dj
      if (.not. ok) failures = failures + 1
   end subroutine check_hmc_reject_identity

   subroutine check_metropolis_reject_identity(accepted, proposal_failed, transition_status, out_x, out_z, out_jac, in_jac, failures)
      logical, intent(in) :: accepted, proposal_failed
      integer, intent(in) :: transition_status
      real(dp), intent(in) :: out_x(:)
      complex(dp), intent(in) :: out_z(:), out_jac(:, :), in_jac(:, :)
      integer, intent(inout) :: failures
      logical :: ok
      real(dp) :: dx, dz, dj

      dx = maxabs_real(out_x - x)
      dz = maxabs_complex(out_z - z)
      dj = maxabs_complex_mat(out_jac - in_jac)
      ok = (.not. accepted) .and. proposal_failed .and. transition_status == metropolis_status_reverse_gate_rejected .and. &
           ieee_is_finite(dx) .and. ieee_is_finite(dz) .and. ieee_is_finite(dj) .and. &
           dx == 0.0_dp .and. dz == 0.0_dp .and. dj == 0.0_dp
      write (*, '(A,L1,A,L1,A,L1,A,I0,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] metropolis_rg_reject_stay_put ok=", ok, &
         " accepted=", accepted, " proposal_failed=", proposal_failed, " status=", transition_status, &
         " dx=", dx, " dz=", dz, " dj=", dj
      if (.not. ok) failures = failures + 1
   end subroutine check_metropolis_reject_identity

   subroutine check_transition_accounting(accepted, proposal_failed, transition_status, failures)
      logical, intent(in) :: accepted, proposal_failed
      integer, intent(in) :: transition_status
      integer, intent(inout) :: failures

      type(tltm_slot_t) :: slot
      type(tltm_local_transition_event_t) :: event
      logical :: ok
      real(dp) :: dx, dz, dj

      event = make_tltm_local_transition_event(accepted, proposal_failed, transition_status)
      call allocate_tltm_slot(slot, size(x))
      slot%x = x
      slot%z = z
      slot%jac = jac
      call record_tltm_local_transition(slot, accepted, proposal_failed, transition_status)
      dx = maxabs_real(slot%x - x)
      dz = maxabs_complex(slot%z - z)
      dj = maxabs_complex_mat(slot%jac - jac)
      ok = event%schema_version == tltm_diag_schema_version_local_transition .and. &
           event%context_id == tltm_event_context_local_transition .and. &
           event%counter_denominator == tltm_counter_denominator_local_transition .and. &
           (.not. event%accepted) .and. event%proposal_failed .and. &
           event%transition_status == metropolis_status_reverse_gate_rejected .and. &
           slot%local_accept_count == 0 .and. slot%local_reject_count == 1 .and. &
           slot%projection_failure_count == 1 .and. slot%reverse_gate_reject_count == 1 .and. &
           slot%metropolis_reject_count == 0 .and. slot%proposal_failure_count == 0 .and. &
           slot%hamiltonian_invalid_count == 0 .and. slot%delta_h_invalid_count == 0 .and. &
           slot%output_size_mismatch_count == 0 .and. dx == 0.0_dp .and. dz == 0.0_dp .and. dj == 0.0_dp
      write (*, '(A,L1,A,I0,A,I0,A,I0,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] rg_reject_transition_accounting ok=", ok, &
         " local_reject=", slot%local_reject_count, " legacy_projection_failure=", slot%projection_failure_count, &
         " reverse_gate_reject=", slot%reverse_gate_reject_count, " dx=", dx, " dz=", dz, " dj=", dj
      if (.not. ok) failures = failures + 1
      call release_tltm_slot(slot)
   end subroutine check_transition_accounting

   pure real(dp) function maxabs_real(vec) result(value)
      real(dp), intent(in) :: vec(:)
      if (size(vec) == 0) then
         value = 0.0_dp
      else
         value = maxval(abs(vec))
      end if
   end function maxabs_real

   pure real(dp) function maxabs_complex(vec) result(value)
      complex(dp), intent(in) :: vec(:)
      if (size(vec) == 0) then
         value = 0.0_dp
      else
         value = maxval(abs(vec))
      end if
   end function maxabs_complex

   pure real(dp) function maxabs_complex_mat(mat) result(value)
      complex(dp), intent(in) :: mat(:, :)
      if (size(mat) == 0) then
         value = 0.0_dp
      else
         value = maxval(abs(mat))
      end if
   end function maxabs_complex_mat

end program test_retained_core_rg_reject_identity

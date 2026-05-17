program test_retained_core_rg_reject_identity
   use hmc, only: hmc_proposal_status_constraint_failed, hmc_proposal_status_final_flow_failed, &
                  hmc_proposal_status_final_projection_failed, hmc_proposal_status_force_failed, &
                  hmc_proposal_status_initial_projection_failed, hmc_proposal_status_no_progress, &
                  hmc_proposal_status_output_size_mismatch, hmc_proposal_status_reverse_gate_rejected, &
                  hmc_proposal_status_step_failed, hmc_proposal_status_success, &
                  integrate_hmc_proposal, integrate_hmc_warmup
   use hmc_integrator_core, only: hmc_policy_context_t, hmc_step_status_reverse_gate_rejected, rattle_step_core
   use hmc_kernels, only: decompose2
   use hmc_state_buffers, only: release_rattle_step_workspace, rattle_step_workspace_t
   use markovchain_metropolis, only: metropolis_status_from_hmc_status, metropolis_step
   use markovchain_transition_status, only: metropolis_status_accepted, metropolis_status_output_size_mismatch, &
                                           metropolis_status_proposal_failed, metropolis_status_rejected, &
                                           metropolis_status_reverse_gate_rejected
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
   call check_direct_core_rg_reject_identity(failures)
   call check_warmup_failure_output_reset(failures)
   call check_hmc_to_metropolis_status_mapping(failures)
   call check_finite_metropolis_reject_output_reset(failures)

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
      type(tltm_local_transition_event_t) :: event, accepted_event
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
      accepted_event = make_tltm_local_transition_event(.true., .true., metropolis_status_reverse_gate_rejected)
      ok = ok .and. accepted_event%accepted .and. (.not. accepted_event%proposal_failed) .and. &
           accepted_event%transition_status == metropolis_status_accepted
      write (*, '(A,L1,A,I0,A,I0,A,I0,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] rg_reject_transition_accounting ok=", ok, &
         " local_reject=", slot%local_reject_count, " legacy_projection_failure=", slot%projection_failure_count, &
         " reverse_gate_reject=", slot%reverse_gate_reject_count, " dx=", dx, " dz=", dz, " dj=", dj
      if (.not. ok) failures = failures + 1
      call release_tltm_slot(slot)
   end subroutine check_transition_accounting

   subroutine check_direct_core_rg_reject_identity(failures)
      integer, intent(inout) :: failures

      real(dp), parameter :: step_candidates(5) = [0.001_dp, 0.002_dp, 0.003_dp, 0.004_dp, 0.006_dp]
      real(dp), parameter :: momentum_scales(5) = [0.5_dp, 0.75_dp, 1.0_dp, 1.25_dp, 1.5_dp]
      type(hmc_policy_context_t) :: local_hmc_policy
      type(rattle_step_workspace_t) :: local_ws
      real(dp), allocatable :: momentum(:), full_coord(:), tangent(:), normal(:)
      logical :: converged, failed, found_reject, ok
      integer :: step_status, i_step, i_scale
      real(dp) :: dx, dz, dj

      allocate (momentum(2*n_seed), full_coord(2*n_seed), tangent(2*n_seed), normal(2*n_seed))
      found_reject = .false.
      ok = .false.
      step_status = -999
      dx = huge(1.0_dp)
      dz = huge(1.0_dp)
      dj = huge(1.0_dp)
      local_hmc_policy%hmc_policy_loaded = .true.
      local_hmc_policy%qn_reverse_gate_enabled = .true.
      local_hmc_policy%qn_reverse_gate_tol = 1.0e-20_dp

      do i_step = 1, size(step_candidates)
         do i_scale = 1, size(momentum_scales)
            call fill_trial_momentum(momentum, momentum_scales(i_scale))
            call decompose2(momentum, full_coord, tangent, normal, jac, failed)
            if (failed) cycle
            momentum = tangent
            hmc_x = -999.0_dp
            hmc_z = cmplx(-999.0_dp, 777.0_dp, kind=dp)
            hmc_jac = cmplx(-999.0_dp, 777.0_dp, kind=dp)
            converged = .true.
            step_status = -999
            call rattle_step_core(x, z, step_candidates(i_step), hmc_x, hmc_z, jac, hmc_jac, momentum, &
                                  converged, local_ws, step_status, hmc_policy=local_hmc_policy)
            if ((.not. converged) .and. step_status == hmc_step_status_reverse_gate_rejected) then
               found_reject = .true.
               dx = maxabs_real(hmc_x - x)
               dz = maxabs_complex(hmc_z - z)
               dj = maxabs_complex_mat(hmc_jac - jac)
               ok = ieee_is_finite(dx) .and. ieee_is_finite(dz) .and. ieee_is_finite(dj) .and. &
                    dx == 0.0_dp .and. dz == 0.0_dp .and. dj == 0.0_dp
               exit
            end if
         end do
         if (found_reject) exit
      end do

      write (*, '(A,L1,A,L1,A,I0,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] direct_core_rg_reject_stay_put ok=", ok, " found_reject=", found_reject, &
         " status=", step_status, " dx=", dx, " dz=", dz, " dj=", dj
      if (.not. ok) failures = failures + 1
      call release_rattle_step_workspace(local_ws)
      deallocate (momentum, full_coord, tangent, normal)
   end subroutine check_direct_core_rg_reject_identity

   subroutine check_warmup_failure_output_reset(failures)
      integer, intent(inout) :: failures

      real(dp), parameter :: step_candidates(7) = [0.002_dp, 0.004_dp, 0.008_dp, 0.016_dp, &
                                                   0.032_dp, 0.064_dp, 0.128_dp]
      type(hmc_policy_context_t) :: local_hmc_policy
      logical :: found_failure, ok
      integer :: i_step
      real(dp) :: h_initial, h_final
      real(dp) :: dx, dz, dj

      found_failure = .false.
      ok = .false.
      dx = huge(1.0_dp)
      dz = huge(1.0_dp)
      dj = huge(1.0_dp)
      local_hmc_policy%hmc_policy_loaded = .true.
      local_hmc_policy%qn_reverse_gate_enabled = .true.
      local_hmc_policy%qn_reverse_gate_tol = 1.0e-20_dp

      do i_step = 1, size(step_candidates)
         hmc_x = -999.0_dp
         hmc_z = cmplx(-999.0_dp, 777.0_dp, kind=dp)
         hmc_jac = cmplx(-999.0_dp, 777.0_dp, kind=dp)
         h_initial = huge(1.0_dp)
         h_final = huge(1.0_dp)
         call integrate_hmc_warmup(x, z, step_candidates(i_step), 1, hmc_x, hmc_z, h_initial, h_final, jac, hmc_jac, &
                                   hmc_policy=local_hmc_policy)
         if (.not. ieee_is_finite(h_final)) then
            found_failure = .true.
            dx = maxabs_real(hmc_x - x)
            dz = maxabs_complex(hmc_z - z)
            dj = maxabs_complex_mat(hmc_jac - jac)
            ok = ieee_is_finite(h_initial) .and. ieee_is_finite(dx) .and. ieee_is_finite(dz) .and. &
                 ieee_is_finite(dj) .and. dx == 0.0_dp .and. dz == 0.0_dp .and. dj == 0.0_dp
            exit
         end if
      end do

      write (*, '(A,L1,A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] warmup_failure_output_reset ok=", ok, " found_failure=", found_failure, &
         " dx=", dx, " dz=", dz, " dj=", dj
      if (.not. ok) failures = failures + 1
   end subroutine check_warmup_failure_output_reset

   subroutine check_hmc_to_metropolis_status_mapping(failures)
      integer, intent(inout) :: failures
      logical :: ok

      ok = metropolis_status_from_hmc_status(hmc_proposal_status_output_size_mismatch) == metropolis_status_output_size_mismatch .and. &
           metropolis_status_from_hmc_status(hmc_proposal_status_reverse_gate_rejected) == metropolis_status_reverse_gate_rejected .and. &
           metropolis_status_from_hmc_status(hmc_proposal_status_success) == metropolis_status_proposal_failed .and. &
           metropolis_status_from_hmc_status(hmc_proposal_status_initial_projection_failed) == metropolis_status_proposal_failed .and. &
           metropolis_status_from_hmc_status(hmc_proposal_status_step_failed) == metropolis_status_proposal_failed .and. &
           metropolis_status_from_hmc_status(hmc_proposal_status_no_progress) == metropolis_status_proposal_failed .and. &
           metropolis_status_from_hmc_status(hmc_proposal_status_final_projection_failed) == metropolis_status_proposal_failed .and. &
           metropolis_status_from_hmc_status(hmc_proposal_status_constraint_failed) == metropolis_status_proposal_failed .and. &
           metropolis_status_from_hmc_status(hmc_proposal_status_final_flow_failed) == metropolis_status_proposal_failed .and. &
           metropolis_status_from_hmc_status(hmc_proposal_status_force_failed) == metropolis_status_proposal_failed
      write (*, '(A,L1,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "[CHECK] hmc_to_metropolis_status_mapping ok=", ok, &
         " output_size=", metropolis_status_from_hmc_status(hmc_proposal_status_output_size_mismatch), &
         " reverse_gate=", metropolis_status_from_hmc_status(hmc_proposal_status_reverse_gate_rejected), &
         " success=", metropolis_status_from_hmc_status(hmc_proposal_status_success), &
         " initial_projection=", metropolis_status_from_hmc_status(hmc_proposal_status_initial_projection_failed), &
         " step_failed=", metropolis_status_from_hmc_status(hmc_proposal_status_step_failed), &
         " no_progress=", metropolis_status_from_hmc_status(hmc_proposal_status_no_progress), &
         " final_projection=", metropolis_status_from_hmc_status(hmc_proposal_status_final_projection_failed), &
         " constraint=", metropolis_status_from_hmc_status(hmc_proposal_status_constraint_failed), &
         " final_flow=", metropolis_status_from_hmc_status(hmc_proposal_status_final_flow_failed), &
         " force=", metropolis_status_from_hmc_status(hmc_proposal_status_force_failed)
      if (.not. ok) failures = failures + 1
   end subroutine check_hmc_to_metropolis_status_mapping

   subroutine check_finite_metropolis_reject_output_reset(failures)
      integer, intent(inout) :: failures

      real(dp), parameter :: step_candidates(8) = [0.0002_dp, 0.0005_dp, 0.001_dp, 0.002_dp, &
                                                   0.003_dp, 0.004_dp, 0.006_dp, 0.008_dp]
      real(dp), parameter :: momentum_scales(8) = [0.05_dp, 0.1_dp, 0.2_dp, 0.35_dp, &
                                                   0.5_dp, 0.75_dp, 1.0_dp, 1.5_dp]
      type(hmc_policy_context_t) :: local_hmc_policy
      logical :: accepted, proposal_failed, found_reject, ok
      integer :: transition_status, i_step, i_scale
      real(dp) :: h_initial, h_final, delta_h, accept_probability
      real(dp) :: dx, dz, dj

      found_reject = .false.
      ok = .false.
      transition_status = -999
      dx = huge(1.0_dp)
      dz = huge(1.0_dp)
      dj = huge(1.0_dp)
      h_initial = huge(1.0_dp)
      h_final = huge(1.0_dp)
      delta_h = huge(1.0_dp)
      accept_probability = 0.0_dp
      local_hmc_policy%hmc_policy_loaded = .true.
      local_hmc_policy%qn_reverse_gate_enabled = .false.

      do i_step = 1, size(step_candidates)
         do i_scale = 1, size(momentum_scales)
            call set_test_momentum(momentum_scales(i_scale))
            metro_x = -999.0_dp
            metro_z = cmplx(-999.0_dp, 777.0_dp, kind=dp)
            metro_jac = cmplx(-999.0_dp, 777.0_dp, kind=dp)
            call metropolis_step(x, z, jac, step_candidates(i_step), 1, metro_x, metro_z, metro_jac, accepted, proposal_failed, &
                                 transition_status, h_initial_out=h_initial, h_final_out=h_final, delta_h_out=delta_h, &
                                 accept_probability_out=accept_probability, hmc_policy=local_hmc_policy, accept_uniform=1.0_dp)
            if ((.not. accepted) .and. (.not. proposal_failed) .and. transition_status == metropolis_status_rejected) then
               found_reject = .true.
               dx = maxabs_real(metro_x - x)
               dz = maxabs_complex(metro_z - z)
               dj = maxabs_complex_mat(metro_jac - jac)
               ok = ieee_is_finite(h_initial) .and. ieee_is_finite(h_final) .and. ieee_is_finite(delta_h) .and. &
                    ieee_is_finite(accept_probability) .and. delta_h > 0.0_dp .and. accept_probability < 1.0_dp .and. &
                    ieee_is_finite(dx) .and. ieee_is_finite(dz) .and. ieee_is_finite(dj) .and. &
                    dx == 0.0_dp .and. dz == 0.0_dp .and. dj == 0.0_dp
               exit
            end if
         end do
         if (found_reject) exit
      end do

      write (*, '(A,L1,A,L1,A,I0,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] finite_metropolis_reject_output_reset ok=", ok, " found_reject=", found_reject, &
         " status=", transition_status, " delta_h=", delta_h, " accept_probability=", accept_probability, &
         " dx=", dx, " dz=", dz, " dj=", dj
      if (.not. ok) failures = failures + 1
   end subroutine check_finite_metropolis_reject_output_reset

   subroutine fill_trial_momentum(momentum, scale)
      real(dp), intent(out) :: momentum(:)
      real(dp), intent(in) :: scale
      integer :: i

      do i = 1, size(momentum)
         momentum(i) = scale*(0.75_dp + 0.05_dp*real(i, dp))
         if (mod(i, 2) == 0) momentum(i) = -momentum(i)
      end do
   end subroutine fill_trial_momentum

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

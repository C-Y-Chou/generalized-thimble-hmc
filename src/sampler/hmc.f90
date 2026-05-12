module hmc
   use, intrinsic :: ieee_arithmetic, only: ieee_quiet_nan, ieee_value
   use param_mod, only: eo, istest, testmom
   use utils, only: dp
   use model, only: grand
   use solve_flow, only: set_intode_rattle_trace, clear_intode_runtime_trace, get_intode_fallback_stats
   use hmc_kernels, only: decompose2, calculate_hamiltonian
   use hmc_constraints, only: reset_constraint_newton_warm_start
   use hmc_state_buffers, only: rattle_step_workspace_t, release_rattle_step_workspace
   use hmc_integrator_core, only: rattle_step_core, &
                                  hmc_step_status_output_size_mismatch, &
                                  hmc_step_status_momentum_size_mismatch, &
                                  hmc_step_status_initial_force_failed, &
                                  hmc_step_status_constraint_failed, &
                                  hmc_step_status_final_flow_failed, &
                                  hmc_step_status_final_force_failed, &
                                  hmc_step_status_final_projection_failed, &
                                  hmc_step_status_reverse_gate_rejected, &
                                  hmc_step_status_final_flow_max_steps, &
                                  hmc_step_status_final_flow_invalid, &
                                  hmc_step_status_final_flow_h_min, &
                                  hmc_step_status_final_flow_non_strict_success
   use hmc_reversibility_checks, only: report_state_progress_diagnostic, reversibility_probe_should_run, report_reversibility_probe
   implicit none

   integer, parameter :: hmc_proposal_status_success = 0
   integer, parameter :: hmc_proposal_status_output_size_mismatch = 1
   integer, parameter :: hmc_proposal_status_initial_projection_failed = 2
   integer, parameter :: hmc_proposal_status_step_failed = 3
   integer, parameter :: hmc_proposal_status_no_progress = 4 ! Reserved legacy status; no longer emitted as an active gate.
   integer, parameter :: hmc_proposal_status_final_projection_failed = 5
   integer, parameter :: hmc_proposal_status_reverse_gate_rejected = 6
   integer, parameter :: hmc_proposal_status_constraint_failed = 7
   integer, parameter :: hmc_proposal_status_final_flow_failed = 8
   integer, parameter :: hmc_proposal_status_force_failed = 9

contains

   subroutine integrate_hmc_proposal(state_x, state_z, step_size, num_steps, &
                                     final_x, final_z, initial_hamiltonian, final_hamiltonian, jaci, jacf, proposal_ok, &
                                     proposal_status, initial_momentum_out, final_momentum_out)
      implicit none
      real(dp), intent(in) :: state_x(:)
      complex(dp), intent(in) :: state_z(:)
      real(dp), intent(in) :: step_size
      integer, intent(in) :: num_steps
      complex(dp), intent(in) :: jaci(:, :)
      complex(dp), intent(out) :: jacf(:, :)
      real(dp), intent(out) :: final_x(:)
      complex(dp), intent(out) :: final_z(:)
      real(dp), intent(out) :: initial_hamiltonian
      real(dp), intent(out) :: final_hamiltonian
      logical, intent(out), optional :: proposal_ok
      integer, intent(out), optional :: proposal_status
      real(dp), intent(out), optional :: initial_momentum_out(:), final_momentum_out(:)
      logical :: local_ok
      integer :: local_status

      call rattle(state_x, state_z, step_size, num_steps, final_x, final_z, initial_hamiltonian, final_hamiltonian, jaci, jacf, &
                  local_ok, local_status, initial_momentum_out, final_momentum_out)
      if (present(proposal_ok)) proposal_ok = local_ok
      if (present(proposal_status)) proposal_status = local_status
   end subroutine integrate_hmc_proposal

   subroutine integrate_hmc_warmup(state_x, state_z, step_size, num_steps, &
                                   final_x, final_z, initial_hamiltonian, final_hamiltonian, jaci, jacf)
      implicit none
      real(dp), intent(in) :: state_x(:)
      complex(dp), intent(in) :: state_z(:)
      real(dp), intent(in) :: step_size
      integer, intent(in) :: num_steps
      complex(dp), intent(in) :: jaci(:, :)
      complex(dp), intent(out) :: jacf(:, :)
      real(dp), intent(out) :: final_x(:)
      complex(dp), intent(out) :: final_z(:)
      real(dp), intent(out) :: initial_hamiltonian
      real(dp), intent(out) :: final_hamiltonian

      call rattle2(state_x, state_z, step_size, num_steps, final_x, final_z, initial_hamiltonian, final_hamiltonian, jaci, jacf)
   end subroutine integrate_hmc_warmup

   subroutine rattle(state_x, state_z, step_size, num_steps, &
                     final_x, final_z, initial_hamiltonian, final_hamiltonian, jaci, jacf, proposal_ok, proposal_status, &
                     initial_momentum_out, final_momentum_out)
      implicit none

      real(dp), intent(in) :: state_x(:)
      complex(dp), intent(in) :: state_z(:)
      real(dp), intent(in) :: step_size
      integer, intent(in) :: num_steps
      complex(dp), intent(in) :: jaci(:, :)
      complex(dp), intent(out) :: jacf(:, :)

      real(dp), intent(out) :: final_x(:)
      complex(dp), intent(out) :: final_z(:)
      real(dp), intent(out) :: initial_hamiltonian
      real(dp), intent(out) :: final_hamiltonian
      logical, intent(out) :: proposal_ok
      integer, intent(out) :: proposal_status
      real(dp), intent(out), optional :: initial_momentum_out(:), final_momentum_out(:)

      integer :: step, state_size
      real(dp) :: integration_step_size
      logical :: method_converged, has_error, fallback_used, reverse_ok
      integer :: fb_calls_before, fb_calls_integrating_before, fb_attempts_before, fb_success_before, fb_failure_before
      integer :: fb_max_steps_before, fb_invalid_before, fb_h_min_before
      integer :: fb_calls_after, fb_calls_integrating_after, fb_attempts_after, fb_success_after, fb_failure_after
      integer :: fb_max_steps_after, fb_invalid_after, fb_h_min_after
      integer :: rev_calls_before, rev_calls_integrating_before, rev_attempts_before, rev_success_before, rev_failure_before
      integer :: rev_max_steps_before, rev_invalid_before, rev_h_min_before
      integer :: rev_calls_after, rev_calls_integrating_after, rev_attempts_after, rev_success_after, rev_failure_after
      integer :: rev_max_steps_after, rev_invalid_after, rev_h_min_after
      real(dp) :: reverse_initial_hamiltonian, reverse_final_hamiltonian
      real(dp) :: dx_inf, dz_inf, dj_inf, dp_inf
      integer :: step_status, reverse_status

      real(dp), allocatable :: momentum(:), momentumuv(:), momentumu(:), momentumv(:), initial_momentum(:)
      real(dp), allocatable :: temp_x(:)
      real(dp), allocatable :: reverse_x(:), reverse_momentum(:)
      complex(dp), allocatable :: temp_z(:), temp_jac(:, :), reverse_z(:), reverse_jac(:, :)
      type(rattle_step_workspace_t) :: ws

      has_error = .false.
      method_converged = .false.
      proposal_ok = .false.
      proposal_status = hmc_proposal_status_step_failed
      state_size = size(state_z)
      initial_hamiltonian = unavailable_hamiltonian()
      final_hamiltonian = unavailable_hamiltonian()
      call clear_optional_momentum(initial_momentum_out)
      call clear_optional_momentum(final_momentum_out)

      if (size(final_x) /= size(state_x) .or. size(final_z) /= state_size) then
         proposal_status = hmc_proposal_status_output_size_mismatch
         jacf = jaci
         return
      end if

      allocate (momentum(2*state_size))
      allocate (momentumuv(2*state_size), momentumu(2*state_size), momentumv(2*state_size))
      allocate (temp_x(size(state_x)), temp_z(state_size))
      allocate (temp_jac(size(jaci, 1), size(jaci, 2)))
      allocate (initial_momentum(2*state_size))
      allocate (reverse_x(size(state_x)), reverse_momentum(2*state_size))
      allocate (reverse_z(state_size), reverse_jac(size(jaci, 1), size(jaci, 2)))

      final_x = state_x
      final_z = state_z
      temp_jac = jaci

      call grand(momentum)
      if (istest) momentum = testmom
      call decompose2(momentum, momentumuv, momentumu, momentumv, temp_jac, has_error)
      if (has_error) then
         proposal_status = hmc_proposal_status_initial_projection_failed
         call abort_with_failure()
         return
      end if
      momentum = momentumu
      initial_momentum = momentum
      call publish_optional_momentum(initial_momentum_out, initial_momentum)
      call calculate_hamiltonian(state_z, momentum, initial_hamiltonian)
      call clear_intode_runtime_trace()
      call reset_constraint_newton_warm_start()
      call get_intode_fallback_stats(fb_calls_before, fb_calls_integrating_before, fb_attempts_before, fb_success_before, fb_failure_before, &
                                     fb_max_steps_before, fb_invalid_before, fb_h_min_before)

      do step = 1, num_steps
         integration_step_size = step_size/real(num_steps, dp)
         temp_x = final_x
         temp_z = final_z

         call set_intode_rattle_trace(step, 1)
         call rattle_step_core(temp_x, temp_z, integration_step_size, final_x, final_z, temp_jac, jacf, momentum, method_converged, ws, &
                               step_status)
         if (.not. method_converged) then
            proposal_status = proposal_status_from_step_status(step_status)
            call abort_with_failure()
            return
         end if
         temp_jac = jacf
      end do

      call report_state_progress_diagnostic("proposal", temp_x, final_x)

      call decompose2(momentum, momentumuv, momentumu, momentumv, temp_jac, has_error)
      if (has_error) then
         proposal_status = hmc_proposal_status_final_projection_failed
         call abort_with_failure()
         return
      end if
      momentum = momentumu
      call publish_optional_momentum(final_momentum_out, momentum)

      call calculate_hamiltonian(final_z, momentum, final_hamiltonian)
      call get_intode_fallback_stats(fb_calls_after, fb_calls_integrating_after, fb_attempts_after, fb_success_after, fb_failure_after, &
                                     fb_max_steps_after, fb_invalid_after, fb_h_min_after)
      fallback_used = (fb_attempts_after > fb_attempts_before)
      if (reversibility_probe_should_run(fallback_used)) then
         reverse_momentum = -momentum
         call get_intode_fallback_stats(rev_calls_before, rev_calls_integrating_before, rev_attempts_before, rev_success_before, rev_failure_before, &
                                        rev_max_steps_before, rev_invalid_before, rev_h_min_before)
         call propagate_with_given_momentum(final_x, final_z, jacf, reverse_momentum, reverse_x, reverse_z, reverse_jac, reverse_momentum, &
                                            reverse_initial_hamiltonian, reverse_final_hamiltonian, reverse_ok, reverse_status)
         call get_intode_fallback_stats(rev_calls_after, rev_calls_integrating_after, rev_attempts_after, rev_success_after, rev_failure_after, &
                                        rev_max_steps_after, rev_invalid_after, rev_h_min_after)
         if (reverse_ok) then
            dx_inf = maxabs_real_vec(reverse_x - state_x)
            dz_inf = maxabs_complex_vec(reverse_z - state_z)
            dj_inf = maxabs_complex_mat(reverse_jac - jaci)
            dp_inf = maxabs_real_vec(reverse_momentum + initial_momentum)
         else
            dx_inf = huge(1.0_dp)
            dz_inf = huge(1.0_dp)
            dj_inf = huge(1.0_dp)
            dp_inf = huge(1.0_dp)
         end if
         call report_reversibility_probe(fallback_used, .true., reverse_ok, &
                                         fb_attempts_after - fb_attempts_before, fb_success_after - fb_success_before, &
                                         fb_failure_after - fb_failure_before, rev_attempts_after - rev_attempts_before, &
                                         rev_success_after - rev_success_before, rev_failure_after - rev_failure_before, &
                                         final_hamiltonian - initial_hamiltonian, reverse_final_hamiltonian - reverse_initial_hamiltonian, &
                                         dx_inf, dz_inf, dj_inf, dp_inf)
      end if
      proposal_ok = .true.
      proposal_status = hmc_proposal_status_success
      call deallocate_all()
      return

   contains

      subroutine propagate_with_given_momentum(start_x, start_z, start_jac, start_momentum, out_x, out_z, out_jac, out_momentum, &
                                               h_initial, h_final, ok, local_proposal_status)
         real(dp), intent(in) :: start_x(:), start_momentum(:)
         complex(dp), intent(in) :: start_z(:), start_jac(:, :)
         real(dp), intent(out) :: out_x(:), out_momentum(:)
         complex(dp), intent(out) :: out_z(:), out_jac(:, :)
         real(dp), intent(out) :: h_initial, h_final
         logical, intent(out) :: ok
         integer, intent(out) :: local_proposal_status

         integer :: local_step
         logical :: local_method_converged, local_error
         integer :: local_step_status
         real(dp) :: local_step_size
         real(dp), allocatable :: local_momentum(:), local_momentumuv(:), local_momentumu(:), local_momentumv(:)
         real(dp), allocatable :: local_prev_x(:)
         complex(dp), allocatable :: local_prev_z(:), local_jac(:, :)
         type(rattle_step_workspace_t) :: local_ws

         ok = .false.
         local_proposal_status = hmc_proposal_status_step_failed
         allocate (local_momentum(2*state_size))
         allocate (local_momentumuv(2*state_size), local_momentumu(2*state_size), local_momentumv(2*state_size))
         allocate (local_prev_x(size(start_x)), local_prev_z(size(start_z)))
         allocate (local_jac(size(start_jac, 1), size(start_jac, 2)))

         out_x = start_x
         out_z = start_z
         out_jac = start_jac
         local_jac = start_jac
         local_momentum = start_momentum

         call calculate_hamiltonian(start_z, local_momentum, h_initial)
         h_final = unavailable_hamiltonian()
         call clear_intode_runtime_trace()
         call reset_constraint_newton_warm_start()

         do local_step = 1, num_steps
            local_step_size = step_size/real(num_steps, dp)
            local_prev_x = out_x
            local_prev_z = out_z
            call set_intode_rattle_trace(local_step, 1)
            call rattle_step_core(local_prev_x, local_prev_z, local_step_size, out_x, out_z, local_jac, out_jac, local_momentum, &
                                  local_method_converged, local_ws, local_step_status)
            if (.not. local_method_converged) then
               local_proposal_status = proposal_status_from_step_status(local_step_status)
               out_x = start_x
               out_z = start_z
               out_jac = start_jac
               out_momentum = start_momentum
               h_final = unavailable_hamiltonian()
               call release_rattle_step_workspace(local_ws)
               if (allocated(local_momentum)) deallocate (local_momentum)
               if (allocated(local_momentumuv)) deallocate (local_momentumuv)
               if (allocated(local_momentumu)) deallocate (local_momentumu)
               if (allocated(local_momentumv)) deallocate (local_momentumv)
               if (allocated(local_prev_x)) deallocate (local_prev_x)
               if (allocated(local_prev_z)) deallocate (local_prev_z)
               if (allocated(local_jac)) deallocate (local_jac)
               call clear_intode_runtime_trace()
               return
            end if
            local_jac = out_jac
         end do

         call report_state_progress_diagnostic("reverse_probe", local_prev_x, out_x)

         call decompose2(local_momentum, local_momentumuv, local_momentumu, local_momentumv, local_jac, local_error)
         if (local_error) then
            local_proposal_status = hmc_proposal_status_final_projection_failed
            out_x = start_x
            out_z = start_z
            out_jac = start_jac
            out_momentum = start_momentum
            h_final = unavailable_hamiltonian()
            call release_rattle_step_workspace(local_ws)
            if (allocated(local_momentum)) deallocate (local_momentum)
            if (allocated(local_momentumuv)) deallocate (local_momentumuv)
            if (allocated(local_momentumu)) deallocate (local_momentumu)
            if (allocated(local_momentumv)) deallocate (local_momentumv)
            if (allocated(local_prev_x)) deallocate (local_prev_x)
            if (allocated(local_prev_z)) deallocate (local_prev_z)
            if (allocated(local_jac)) deallocate (local_jac)
            call clear_intode_runtime_trace()
            return
         end if

         out_momentum = local_momentumu
         call calculate_hamiltonian(out_z, out_momentum, h_final)
         ok = .true.
         local_proposal_status = hmc_proposal_status_success

         call release_rattle_step_workspace(local_ws)
         if (allocated(local_momentum)) deallocate (local_momentum)
         if (allocated(local_momentumuv)) deallocate (local_momentumuv)
         if (allocated(local_momentumu)) deallocate (local_momentumu)
         if (allocated(local_momentumv)) deallocate (local_momentumv)
         if (allocated(local_prev_x)) deallocate (local_prev_x)
         if (allocated(local_prev_z)) deallocate (local_prev_z)
         if (allocated(local_jac)) deallocate (local_jac)
         call clear_intode_runtime_trace()
      end subroutine propagate_with_given_momentum

      pure integer function proposal_status_from_step_status(step_failure_status) result(status)
         integer, intent(in) :: step_failure_status

         select case (step_failure_status)
         case (hmc_step_status_output_size_mismatch, hmc_step_status_momentum_size_mismatch)
            status = hmc_proposal_status_output_size_mismatch
         case (hmc_step_status_initial_force_failed, hmc_step_status_final_force_failed)
            status = hmc_proposal_status_force_failed
         case (hmc_step_status_constraint_failed)
            status = hmc_proposal_status_constraint_failed
         case (hmc_step_status_final_flow_failed, hmc_step_status_final_flow_max_steps, &
               hmc_step_status_final_flow_invalid, hmc_step_status_final_flow_h_min, &
               hmc_step_status_final_flow_non_strict_success)
            status = hmc_proposal_status_final_flow_failed
         case (hmc_step_status_final_projection_failed)
            status = hmc_proposal_status_final_projection_failed
         case (hmc_step_status_reverse_gate_rejected)
            status = hmc_proposal_status_reverse_gate_rejected
         case default
            status = hmc_proposal_status_step_failed
         end select
      end function proposal_status_from_step_status

      pure real(dp) function maxabs_real_vec(vec)
         real(dp), intent(in) :: vec(:)
         if (size(vec) <= 0) then
            maxabs_real_vec = 0.0_dp
         else
            maxabs_real_vec = maxval(abs(vec))
         end if
      end function maxabs_real_vec

      pure real(dp) function maxabs_complex_vec(vec)
         complex(dp), intent(in) :: vec(:)
         if (size(vec) <= 0) then
            maxabs_complex_vec = 0.0_dp
         else
            maxabs_complex_vec = maxval(abs(vec))
         end if
      end function maxabs_complex_vec

      pure real(dp) function maxabs_complex_mat(mat)
         complex(dp), intent(in) :: mat(:, :)
         if (size(mat) <= 0) then
            maxabs_complex_mat = 0.0_dp
         else
            maxabs_complex_mat = maxval(abs(mat))
         end if
      end function maxabs_complex_mat

      subroutine clear_optional_momentum(momentum_out)
         real(dp), intent(out), optional :: momentum_out(:)

         if (present(momentum_out)) momentum_out = ieee_value(0.0_dp, ieee_quiet_nan)
      end subroutine clear_optional_momentum

      subroutine publish_optional_momentum(momentum_out, momentum_value)
         real(dp), intent(out), optional :: momentum_out(:)
         real(dp), intent(in) :: momentum_value(:)

         if (present(momentum_out)) then
            if (size(momentum_out) == size(momentum_value)) momentum_out = momentum_value
         end if
      end subroutine publish_optional_momentum

      subroutine deallocate_all()
         if (allocated(momentum)) deallocate (momentum)
         if (allocated(momentumuv)) deallocate (momentumuv)
         if (allocated(momentumu)) deallocate (momentumu)
         if (allocated(momentumv)) deallocate (momentumv)
         if (allocated(initial_momentum)) deallocate (initial_momentum)
         if (allocated(temp_x)) deallocate (temp_x)
         if (allocated(temp_z)) deallocate (temp_z)
         if (allocated(temp_jac)) deallocate (temp_jac)
         if (allocated(reverse_x)) deallocate (reverse_x)
         if (allocated(reverse_momentum)) deallocate (reverse_momentum)
         if (allocated(reverse_z)) deallocate (reverse_z)
         if (allocated(reverse_jac)) deallocate (reverse_jac)
         call release_rattle_step_workspace(ws)
         call clear_intode_runtime_trace()
      end subroutine deallocate_all

      subroutine abort_with_failure()
         final_x = state_x
         final_z = state_z
         final_hamiltonian = unavailable_hamiltonian()
         jacf = jaci
         call deallocate_all()
      end subroutine abort_with_failure

   end subroutine rattle

   subroutine rattle2(state_x, state_z, step_size, num_steps, &
                      final_x, final_z, initial_hamiltonian, final_hamiltonian, jaci, jacf)
      implicit none

      real(dp), intent(in) :: state_x(:)
      complex(dp), intent(in) :: state_z(:)
      real(dp), intent(in) :: step_size
      integer, intent(in) :: num_steps
      complex(dp), intent(in) :: jaci(:, :)
      complex(dp), intent(out) :: jacf(:, :)

      real(dp), intent(out) :: final_x(:)
      complex(dp), intent(out) :: final_z(:)
      real(dp), intent(out) :: initial_hamiltonian
      real(dp), intent(out) :: final_hamiltonian

      integer :: step, state_size, wi, substep
      real(dp) :: integration_step_size
      logical :: method_converged

      real(dp), allocatable :: momentum(:)
      real(dp), allocatable :: temp_x(:)
      complex(dp), allocatable :: temp_z(:), temp_jac(:, :)
      type(rattle_step_workspace_t) :: ws
      real(dp), parameter :: w_rattle(1) = (/1.0_dp/(2.0_dp - 2.0_dp**(1.0_dp/3.0_dp))/)

      state_size = size(state_z)
      method_converged = .false.
      initial_hamiltonian = unavailable_hamiltonian()
      final_hamiltonian = unavailable_hamiltonian()

      if (size(final_x) /= size(state_x) .or. size(final_z) /= state_size) then
         jacf = jaci
         return
      end if

      allocate (momentum(2*state_size))
      allocate (temp_x(size(state_x)), temp_z(state_size))
      allocate (temp_jac(size(jaci, 1), size(jaci, 2)))

      final_x = state_x
      final_z = state_z
      temp_jac = jaci

      momentum = 0.0_dp
      call calculate_hamiltonian(state_z, momentum, initial_hamiltonian)
      call clear_intode_runtime_trace()
      call reset_constraint_newton_warm_start()

      do step = 1, num_steps
         if (eo) then
            do wi = 0, size(w_rattle) - 1
               temp_x = final_x
               temp_z = final_z
               integration_step_size = w_rattle(size(w_rattle) - wi)*step_size/real(num_steps, dp)
               substep = wi + 1
               call set_intode_rattle_trace(step, substep)
               call rattle_step_core(temp_x, temp_z, integration_step_size, final_x, final_z, temp_jac, jacf, momentum, method_converged, ws)
               if (.not. method_converged) then
                  call abort_with_failure()
                  return
               end if
               temp_jac = jacf
            end do

            temp_x = final_x
            temp_z = final_z
            integration_step_size = (1.0_dp - 2.0_dp*sum(w_rattle))*step_size/real(num_steps, dp)
            substep = size(w_rattle) + 1
            call set_intode_rattle_trace(step, substep)
            call rattle_step_core(temp_x, temp_z, integration_step_size, final_x, final_z, temp_jac, jacf, momentum, method_converged, ws)
            if (.not. method_converged) then
               call abort_with_failure()
               return
            end if
            temp_jac = jacf

            do wi = 1, size(w_rattle)
               temp_x = final_x
               temp_z = final_z
               integration_step_size = w_rattle(wi)*step_size/real(num_steps, dp)
               substep = size(w_rattle) + 1 + wi
               call set_intode_rattle_trace(step, substep)
               call rattle_step_core(temp_x, temp_z, integration_step_size, final_x, final_z, temp_jac, jacf, momentum, method_converged, ws)
               if (.not. method_converged) then
                  call abort_with_failure()
                  return
               end if
               temp_jac = jacf
            end do
         else
            integration_step_size = step_size/real(num_steps, dp)
            temp_x = final_x
            temp_z = final_z
            call set_intode_rattle_trace(step, 1)
            call rattle_step_core(temp_x, temp_z, integration_step_size, final_x, final_z, temp_jac, jacf, momentum, method_converged, ws)
            if (.not. method_converged) then
               call abort_with_failure()
               return
            end if
            temp_jac = jacf
         end if
      end do

      call report_state_progress_diagnostic("warmup", temp_x, final_x)

      momentum = 0.0_dp
      call calculate_hamiltonian(final_z, momentum, final_hamiltonian)

      call deallocate_all()
      return

   contains

      subroutine deallocate_all()
         if (allocated(momentum)) deallocate (momentum)
         if (allocated(temp_x)) deallocate (temp_x)
         if (allocated(temp_z)) deallocate (temp_z)
         if (allocated(temp_jac)) deallocate (temp_jac)
         call release_rattle_step_workspace(ws)
         call clear_intode_runtime_trace()
      end subroutine deallocate_all

      subroutine abort_with_failure()
         final_hamiltonian = unavailable_hamiltonian()
         jacf = jaci
         call deallocate_all()
      end subroutine abort_with_failure

   end subroutine rattle2

   real(dp) function unavailable_hamiltonian() result(value)
      implicit none
      value = ieee_value(0.0_dp, ieee_quiet_nan)
   end function unavailable_hamiltonian

end module hmc

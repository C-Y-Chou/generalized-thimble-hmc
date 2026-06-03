module wv_hmc_constraints
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use model, only: calculate_action, ds
   use solve_flow, only: flow_at, flowz_at, flow_workspace_t, intode_diagnostics_context_t, &
                         intode_status_success_zero_time, intode_status_unknown
   use utils, only: complex_to_real, dp
   use wv_hmc_kernels, only: wv_force_dense_with_jacobian, wv_project_dense_with_jacobian, &
                             wv_reflect_flow_component_dense_with_jacobian, &
                             wv_simplified_newton_update_dense_with_jacobian, wv_xi_from_action_gradient
   use wv_hmc_potential, only: wv_potential_profile_t, wv_potential_value_and_derivative
   implicit none

   private
   public :: wv_apply_simplified_boundary_rule, wv_calculate_hamiltonian, wv_first_constraint_residual_dense, &
             wv_newton_stop_converged, wv_newton_stop_divergence, wv_newton_stop_invalid_input, &
             wv_newton_stop_max_iter, wv_newton_stop_nonfinite, wv_newton_stop_not_run, &
             wv_newton_stop_residual_error, wv_newton_stop_stagnation, wv_newton_stop_unknown, &
             wv_newton_stop_update_error, wv_newton_stop_boundary_exit, wv_newton_stop_large_residual, &
             wv_boundary_policy_paper_full_flip, wv_boundary_policy_normal_reflect, &
             wv_boundary_policy_name, wv_newton_trace_context_t, wv_set_boundary_policy, &
             wv_set_newton_large_residual_stop, &
             wv_rattle_step_dense_with_boundary, wv_rattle_step_dense_no_boundary, wv_solve_first_constraint_dense

   real(dp), parameter :: wv_rattle_step_default_constraint_tol = 1.0e-10_dp
   integer, parameter :: wv_boundary_policy_paper_full_flip = 1
   integer, parameter :: wv_boundary_policy_normal_reflect = 2
   integer, parameter :: wv_newton_stop_unknown = 0
   integer, parameter :: wv_newton_stop_converged = 1
   integer, parameter :: wv_newton_stop_max_iter = 2
   integer, parameter :: wv_newton_stop_residual_error = 3
   integer, parameter :: wv_newton_stop_update_error = 4
   integer, parameter :: wv_newton_stop_nonfinite = 5
   integer, parameter :: wv_newton_stop_divergence = 6
   integer, parameter :: wv_newton_stop_stagnation = 7
   integer, parameter :: wv_newton_stop_invalid_input = 8
   integer, parameter :: wv_newton_stop_not_run = 9
   integer, parameter :: wv_newton_stop_boundary_exit = 10
   integer, parameter :: wv_newton_stop_large_residual = 11

   type :: wv_newton_trace_context_t
      integer :: unit = 0
      integer :: solve_count = 0
      integer :: cycle = 0
      integer :: direction = 0
      integer :: step = 0
   end type wv_newton_trace_context_t

   logical :: newton_large_residual_stop_enabled = .false.
   real(dp) :: newton_large_residual_threshold = huge(1.0_dp)
   integer :: newton_large_residual_min_iter = 8
   integer :: newton_large_residual_patience = 4
   real(dp) :: newton_large_residual_min_rel_improvement = 5.0e-4_dp
   integer :: boundary_policy = wv_boundary_policy_paper_full_flip

contains

   subroutine wv_set_boundary_policy(policy, error)
      character(len=*), intent(in) :: policy
      logical, intent(out) :: error
      character(len=len(policy)) :: token

      token = lower_ascii(adjustl(policy))
      error = .false.
      select case (trim(token))
      case ("paper_full_flip", "full_flip", "paper", "full")
         boundary_policy = wv_boundary_policy_paper_full_flip
      case ("normal_reflect", "normal_reflection", "legacy_normal", "legacy")
         boundary_policy = wv_boundary_policy_normal_reflect
      case default
         error = .true.
      end select
   end subroutine wv_set_boundary_policy

   function wv_boundary_policy_name() result(name)
      character(len=32) :: name

      select case (boundary_policy)
      case (wv_boundary_policy_paper_full_flip)
         name = "paper_full_flip"
      case (wv_boundary_policy_normal_reflect)
         name = "normal_reflect"
      case default
         name = "invalid"
      end select
   end function wv_boundary_policy_name

   subroutine wv_set_newton_large_residual_stop(enabled, threshold, min_iter, patience, min_rel_improvement)
      logical, intent(in) :: enabled
      real(dp), intent(in) :: threshold, min_rel_improvement
      integer, intent(in) :: min_iter, patience

      newton_large_residual_stop_enabled = enabled
      if (.not. enabled) then
         newton_large_residual_threshold = huge(1.0_dp)
         newton_large_residual_min_iter = 8
         newton_large_residual_patience = 4
         newton_large_residual_min_rel_improvement = 5.0e-4_dp
         return
      end if
      newton_large_residual_threshold = threshold
      newton_large_residual_min_iter = max(1, min_iter)
      newton_large_residual_patience = max(1, patience)
      newton_large_residual_min_rel_improvement = max(0.0_dp, min_rel_improvement)
   end subroutine wv_set_newton_large_residual_stop

   subroutine wv_calculate_hamiltonian(z, pi, w_value, hamiltonian, error)
      complex(dp), intent(in) :: z(:)
      real(dp), intent(in) :: pi(:), w_value
      real(dp), intent(out) :: hamiltonian
      logical, intent(out) :: error

      complex(dp) :: action_value

      hamiltonian = huge(1.0_dp)
      error = .true.
      if (size(z) <= 0) return
      if (size(pi) /= 2*size(z)) return
      if (.not. ieee_is_finite(w_value)) return
      if (.not. valid_complex_vector(z)) return
      if (.not. valid_real_vector(pi)) return

      call calculate_action(z, action_value)
      if ((.not. ieee_is_finite(real(action_value, dp))) .or. (.not. ieee_is_finite(aimag(action_value)))) return
      hamiltonian = 0.5_dp*dot_product(pi, pi) + real(action_value, dp) + w_value
      if (.not. ieee_is_finite(hamiltonian)) then
         hamiltonian = huge(1.0_dp)
         return
      end if
      error = .false.
   end subroutine wv_calculate_hamiltonian

   subroutine wv_apply_simplified_boundary_rule(t0, t1, d0, d1, flow_time_current, x_current, z_current, &
                                                jac_current, pi_current, flow_time_trial, x_trial, z_trial, &
                                                jac_trial, pi_trial, flow_time_out, x_out, z_out, jac_out, &
                                                pi_out, bounced, error)
      real(dp), intent(in) :: t0, t1, d0, d1, flow_time_current, flow_time_trial
      real(dp), intent(in) :: x_current(:), pi_current(:), x_trial(:), pi_trial(:)
      complex(dp), intent(in) :: z_current(:), jac_current(:, :), z_trial(:), jac_trial(:, :)
      real(dp), intent(out) :: flow_time_out, x_out(:), pi_out(:)
      complex(dp), intent(out) :: z_out(:), jac_out(:, :)
      logical, intent(out) :: bounced, error

      integer :: n
      real(dp) :: lower_bound, upper_bound

      flow_time_out = flow_time_current
      x_out = 0.0_dp
      z_out = cmplx(0.0_dp, 0.0_dp, dp)
      jac_out = cmplx(0.0_dp, 0.0_dp, dp)
      pi_out = 0.0_dp
      bounced = .false.
      error = .true.

      n = size(z_current)
      if (n <= 0) return
      if (size(z_trial) /= n) return
      if (size(x_current) /= n .or. size(x_trial) /= n .or. size(x_out) /= n) return
      if (size(jac_current, 1) /= n .or. size(jac_current, 2) /= n) return
      if (size(jac_trial, 1) /= n .or. size(jac_trial, 2) /= n) return
      if (size(jac_out, 1) /= n .or. size(jac_out, 2) /= n) return
      if (size(pi_current) /= 2*n .or. size(pi_trial) /= 2*n .or. size(pi_out) /= 2*n) return
      if (.not. all(ieee_is_finite([t0, t1, d0, d1, flow_time_current, flow_time_trial]))) return
      if (t1 < t0) return
      if (d0 < 0.0_dp .or. d1 < 0.0_dp) return
      lower_bound = t0 - d0
      upper_bound = t1 + d1
      if ((.not. ieee_is_finite(lower_bound)) .or. (.not. ieee_is_finite(upper_bound))) return
      if (.not. valid_real_vector(x_current)) return
      if (.not. valid_real_vector(x_trial)) return
      if (.not. valid_real_vector(pi_current)) return
      if (.not. valid_real_vector(pi_trial)) return
      if (.not. valid_complex_vector(z_current)) return
      if (.not. valid_complex_vector(z_trial)) return
      if (.not. valid_complex_matrix(jac_current)) return
      if (.not. valid_complex_matrix(jac_trial)) return

      if (flow_time_trial < lower_bound .or. flow_time_trial > upper_bound) then
         flow_time_out = flow_time_current
         x_out = x_current
         z_out = z_current
         jac_out = jac_current
         call apply_boundary_momentum_rule(z_current, jac_current, pi_current, pi_out, error)
         if (error) return
         bounced = .true.
      else
         flow_time_out = flow_time_trial
         x_out = x_trial
         z_out = z_trial
         jac_out = jac_trial
         pi_out = pi_trial
         bounced = .false.
      end if
      error = .false.
   end subroutine wv_apply_simplified_boundary_rule

   subroutine wv_first_constraint_residual_dense(flow_time, x_base, z_base, del_z, h, u_interleaved, lambda, &
                                                residual, error, status, z_new_out, jac_new_out, flow_workspace, &
                                                intode_diagnostics, target_flow_time_min, target_flow_time_max, &
                                                boundary_exit)
      real(dp), intent(in) :: flow_time, x_base(:), del_z(:), h, u_interleaved(:), lambda(:)
      complex(dp), intent(in) :: z_base(:)
      real(dp), intent(out) :: residual(:)
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      complex(dp), intent(out), optional :: z_new_out(:), jac_new_out(:, :)
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      real(dp), intent(in), optional :: target_flow_time_min, target_flow_time_max
      logical, intent(out), optional :: boundary_exit

      integer :: n, i, flow_status
      real(dp) :: target_flow_time
      real(dp) :: x_trial(size(x_base))
      complex(dp) :: z_new(size(z_base))
      logical :: flow_failed, need_jacobian

      residual = 0.0_dp
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status
      if (present(boundary_exit)) boundary_exit = .false.

      n = size(z_base)
      if (n <= 0) return
      if (size(x_base) /= n) return
      if (size(del_z) /= 2*n .or. size(u_interleaved) /= 2*n .or. size(lambda) /= 2*n .or. size(residual) /= 2*n) return
      if (present(z_new_out)) then
         if (size(z_new_out) /= n) return
      end if
      if (present(jac_new_out)) then
         if (size(jac_new_out, 1) /= n .or. size(jac_new_out, 2) /= n) return
      end if
      if ((.not. ieee_is_finite(flow_time)) .or. (.not. ieee_is_finite(h))) return
      target_flow_time = flow_time + h
      if (.not. ieee_is_finite(target_flow_time)) return
      if (present(target_flow_time_min)) then
         if (.not. ieee_is_finite(target_flow_time_min)) return
         if (target_flow_time < target_flow_time_min) then
            if (present(boundary_exit)) boundary_exit = .true.
            return
         end if
      end if
      if (present(target_flow_time_max)) then
         if (.not. ieee_is_finite(target_flow_time_max)) return
         if (target_flow_time > target_flow_time_max) then
            if (present(boundary_exit)) boundary_exit = .true.
            return
         end if
      end if
      if (target_flow_time < 0.0_dp) return
      if (.not. valid_real_vector(x_base)) return
      if (.not. valid_real_vector(del_z)) return
      if (.not. valid_real_vector(u_interleaved)) return
      if (.not. valid_real_vector(lambda)) return
      if (.not. valid_complex_vector(z_base)) return

      do i = 1, n
         x_trial(i) = x_base(i) + u_interleaved(2*i - 1)
      end do
      if (.not. valid_real_vector(x_trial)) return

      z_new = cmplx(0.0_dp, 0.0_dp, dp)
      need_jacobian = present(jac_new_out)
      if (need_jacobian) then
         jac_new_out = cmplx(0.0_dp, 0.0_dp, dp)
         if (present(flow_workspace)) then
            call flow_at(target_flow_time, x_trial, z_new, jac_new_out, flow_failed, flow_status, flow_workspace, intode_diagnostics)
         else
            call flow_at(target_flow_time, x_trial, z_new, jac_new_out, flow_failed, flow_status, intode_diagnostics=intode_diagnostics)
         end if
      else
         if (present(flow_workspace)) then
            call flowz_at(target_flow_time, x_trial, z_new, flow_failed, flow_status, flow_workspace, intode_diagnostics)
         else
            call flowz_at(target_flow_time, x_trial, z_new, flow_failed, flow_status, intode_diagnostics=intode_diagnostics)
         end if
      end if
      if (present(status)) status = flow_status
      if (flow_failed) return

      call complex_to_real(z_base - z_new, residual)
      residual = residual + del_z - lambda
      if (.not. valid_real_vector(residual)) then
         residual = 0.0_dp
         return
      end if
      if (present(z_new_out)) z_new_out = z_new
      error = .false.
   end subroutine wv_first_constraint_residual_dense

   subroutine wv_solve_first_constraint_dense(tol, max_iter, flow_time, x_base, z_base, jac_base, del_z, xi_real, &
                                             h, u_interleaved, lambda, residual_norm, iterations, converged, error, status, &
                                             flow_workspace, intode_diagnostics, stop_reason, adaptive_stop_enabled, &
                                             trace_context, target_flow_time_min, target_flow_time_max)
      real(dp), intent(in) :: tol, flow_time, x_base(:), del_z(:), xi_real(:)
      integer, intent(in) :: max_iter
      complex(dp), intent(in) :: z_base(:), jac_base(:, :)
      real(dp), intent(out) :: h, u_interleaved(:), lambda(:), residual_norm
      integer, intent(out) :: iterations
      logical, intent(out) :: converged, error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      integer, intent(out), optional :: stop_reason
      logical, intent(in), optional :: adaptive_stop_enabled
      type(wv_newton_trace_context_t), intent(inout), optional :: trace_context
      real(dp), intent(in), optional :: target_flow_time_min, target_flow_time_max

      integer :: n, iter, flow_status, iter_cap, iter_cap_hard, near_extend_chunk
      integer :: diverge_count, severe_diverge_count, stagnation_count, tiny_step_count, local_stop_reason
      integer :: boundary_clamp_count, boundary_clamp_limit, large_residual_count
      real(dp) :: residual(size(del_z)), delta_u(size(del_z)), delta_lambda(size(del_z))
      real(dp) :: delta_h, c_b, alpha2
      real(dp) :: residual_prev, residual_best, rel_improvement
      real(dp) :: near_tol, stagnation_floor, diverge_floor, update_norm, update_floor
      real(dp) :: local_target_flow_time_min, local_target_flow_time_max
      real(dp) :: target_before_update, target_after_update, boundary_margin, update_scale, bound_scale
      logical :: residual_error, update_error, use_adaptive_stop, boundary_exit, update_clamped
      logical :: has_target_flow_time_min, has_target_flow_time_max
      integer :: solve_id

      h = 0.0_dp
      u_interleaved = 0.0_dp
      lambda = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      converged = .false.
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status
      local_stop_reason = wv_newton_stop_invalid_input
      if (present(stop_reason)) stop_reason = local_stop_reason
      use_adaptive_stop = .false.
      if (present(adaptive_stop_enabled)) use_adaptive_stop = adaptive_stop_enabled
      solve_id = 0
      if (present(trace_context)) then
         trace_context%solve_count = trace_context%solve_count + 1
         solve_id = trace_context%solve_count
      end if

      n = size(z_base)
      if (n <= 0) return
      if (max_iter < 0) return
      if ((.not. ieee_is_finite(tol)) .or. tol <= 0.0_dp) return
      if (size(x_base) /= n) return
      if (size(jac_base, 1) /= n .or. size(jac_base, 2) /= n) return
      if (size(del_z) /= 2*n .or. size(xi_real) /= 2*n) return
      if (size(u_interleaved) /= 2*n .or. size(lambda) /= 2*n) return
      if (.not. valid_real_vector(del_z)) return
      if (.not. valid_real_vector(xi_real)) return
      if (.not. valid_complex_vector(z_base)) return

      local_stop_reason = wv_newton_stop_unknown
      if (present(stop_reason)) stop_reason = local_stop_reason
      near_tol = max(2.0e2_dp*tol, 1.0e-10_dp)
      stagnation_floor = max(1.0e4_dp*tol, 1.0e-8_dp)
      diverge_floor = max(1.0e5_dp*tol, 1.0e-6_dp)
      near_extend_chunk = max(4, max(1, max_iter/4))
      iter_cap = max_iter
      iter_cap_hard = max_iter + max(16, max_iter)
      diverge_count = 0
      severe_diverge_count = 0
      stagnation_count = 0
      tiny_step_count = 0
      boundary_clamp_count = 0
      boundary_clamp_limit = max(4, min(12, max(1, max_iter/4)))
      large_residual_count = 0
      residual_prev = huge(1.0_dp)
      residual_best = huge(1.0_dp)
      update_norm = huge(1.0_dp)
      local_target_flow_time_min = -huge(1.0_dp)
      local_target_flow_time_max = huge(1.0_dp)
      has_target_flow_time_min = present(target_flow_time_min)
      has_target_flow_time_max = present(target_flow_time_max)
      if (has_target_flow_time_min) local_target_flow_time_min = target_flow_time_min
      if (has_target_flow_time_max) local_target_flow_time_max = target_flow_time_max

      iter = 0
      do
         if (present(flow_workspace)) then
            call wv_first_constraint_residual_dense(flow_time, x_base, z_base, del_z, h, u_interleaved, lambda, &
                                                    residual, residual_error, flow_status, flow_workspace=flow_workspace, &
                                                    intode_diagnostics=intode_diagnostics, &
                                                    target_flow_time_min=local_target_flow_time_min, &
                                                    target_flow_time_max=local_target_flow_time_max, &
                                                    boundary_exit=boundary_exit)
         else
            call wv_first_constraint_residual_dense(flow_time, x_base, z_base, del_z, h, u_interleaved, lambda, &
                                                    residual, residual_error, flow_status, intode_diagnostics=intode_diagnostics, &
                                                    target_flow_time_min=local_target_flow_time_min, &
                                                    target_flow_time_max=local_target_flow_time_max, &
                                                    boundary_exit=boundary_exit)
         end if
         if (present(status)) status = flow_status
         if (residual_error) then
            if (boundary_exit) then
               local_stop_reason = wv_newton_stop_boundary_exit
            else
               local_stop_reason = wv_newton_stop_residual_error
            end if
            if (present(stop_reason)) stop_reason = local_stop_reason
            call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, lambda, &
                                        local_stop_reason)
            return
         end if

         residual_norm = norm2(residual)
         iterations = iter
         if (.not. ieee_is_finite(residual_norm)) then
            local_stop_reason = wv_newton_stop_nonfinite
            if (present(stop_reason)) stop_reason = local_stop_reason
            call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, lambda, &
                                        local_stop_reason)
            return
         end if
         if (residual_norm <= tol) then
            converged = .true.
            error = .false.
            local_stop_reason = wv_newton_stop_converged
            if (present(stop_reason)) stop_reason = local_stop_reason
            call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, lambda, &
                                        local_stop_reason)
            return
         end if
         call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, lambda, &
                                     wv_newton_stop_unknown)

         if (iter > 0) then
            if (residual_norm < residual_best) residual_best = residual_norm
            if (use_adaptive_stop .and. residual_norm <= near_tol .and. iter_cap < iter_cap_hard) then
               iter_cap = min(iter_cap_hard, iter_cap + near_extend_chunk)
            end if
            if (residual_norm > 1.20_dp*residual_prev) then
               diverge_count = diverge_count + 1
            else
               diverge_count = max(0, diverge_count - 1)
            end if
            if (residual_norm > 1.50_dp*residual_prev .and. residual_norm > diverge_floor) then
               severe_diverge_count = severe_diverge_count + 1
            else
               severe_diverge_count = max(0, severe_diverge_count - 1)
            end if
            rel_improvement = abs(residual_prev - residual_norm)/max(1.0_dp, residual_prev)
            if (rel_improvement < 5.0e-4_dp) then
               stagnation_count = stagnation_count + 1
            else
               stagnation_count = 0
            end if
            if (newton_large_residual_stop_enabled .and. &
                iter >= newton_large_residual_min_iter .and. &
                residual_best > newton_large_residual_threshold .and. &
                residual_norm > newton_large_residual_threshold) then
               if (residual_norm >= residual_prev .or. &
                   rel_improvement < newton_large_residual_min_rel_improvement) then
                  large_residual_count = large_residual_count + 1
               else
                  large_residual_count = max(0, large_residual_count - 1)
               end if
            else
               large_residual_count = 0
            end if
            update_floor = sqrt(epsilon(1.0_dp))*max(1.0_dp, abs(h) + norm2(u_interleaved) + norm2(lambda))
            if (update_norm <= 10.0_dp*update_floor) then
               tiny_step_count = tiny_step_count + 1
            else
               tiny_step_count = max(0, tiny_step_count - 1)
            end if
            if (use_adaptive_stop .and. (severe_diverge_count >= 2 .or. diverge_count >= 4)) then
               local_stop_reason = wv_newton_stop_divergence
               if (present(stop_reason)) stop_reason = local_stop_reason
               call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, &
                                           lambda, local_stop_reason)
               return
            end if
            if (newton_large_residual_stop_enabled .and. &
                large_residual_count >= newton_large_residual_patience) then
               local_stop_reason = wv_newton_stop_large_residual
               if (present(stop_reason)) stop_reason = local_stop_reason
               call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, &
                                           lambda, local_stop_reason)
               return
            end if
            if (use_adaptive_stop .and. iter >= min(8, max_iter) .and. stagnation_count >= 6 .and. &
                tiny_step_count >= 3 .and. &
                residual_norm > stagnation_floor .and. residual_best > max(20.0_dp*tol, 5.0e-10_dp)) then
               local_stop_reason = wv_newton_stop_stagnation
               if (present(stop_reason)) stop_reason = local_stop_reason
               call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, &
                                           lambda, local_stop_reason)
               return
            end if
         else
            residual_best = residual_norm
         end if

         if (iter >= iter_cap) exit

         call wv_simplified_newton_update_dense_with_jacobian(residual, xi_real, jac_base, delta_h, delta_u, &
                                                             delta_lambda, c_b, alpha2, update_error)
         if (update_error) then
            local_stop_reason = wv_newton_stop_update_error
            if (present(stop_reason)) stop_reason = local_stop_reason
            call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, lambda, &
                                        local_stop_reason)
            return
         end if
         update_norm = sqrt(delta_h*delta_h + norm2(delta_u)**2 + norm2(delta_lambda)**2)
         if (.not. ieee_is_finite(update_norm)) then
            local_stop_reason = wv_newton_stop_nonfinite
            if (present(stop_reason)) stop_reason = local_stop_reason
            call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, lambda, &
                                        local_stop_reason)
            return
         end if
         target_before_update = flow_time + h
         target_after_update = target_before_update + delta_h
         boundary_margin = 1000.0_dp*epsilon(1.0_dp)*max(1.0_dp, abs(flow_time))
         if (has_target_flow_time_min) boundary_margin = max(boundary_margin, &
                                                             1000.0_dp*epsilon(1.0_dp)*abs(local_target_flow_time_min))
         if (has_target_flow_time_max) boundary_margin = max(boundary_margin, &
                                                             1000.0_dp*epsilon(1.0_dp)*abs(local_target_flow_time_max))
         update_scale = 1.0_dp
         update_clamped = .false.
         if (has_target_flow_time_min .and. &
             target_after_update < local_target_flow_time_min + boundary_margin .and. delta_h < 0.0_dp) then
            bound_scale = (local_target_flow_time_min + boundary_margin - target_before_update)/delta_h
            update_scale = min(update_scale, max(0.0_dp, 0.95_dp*bound_scale))
            update_clamped = .true.
         end if
         if (has_target_flow_time_max .and. &
             target_after_update > local_target_flow_time_max - boundary_margin .and. delta_h > 0.0_dp) then
            bound_scale = (local_target_flow_time_max - boundary_margin - target_before_update)/delta_h
            update_scale = min(update_scale, max(0.0_dp, 0.95_dp*bound_scale))
            update_clamped = .true.
         end if
         if (update_clamped) then
            boundary_clamp_count = boundary_clamp_count + 1
            if (update_scale <= 10.0_dp*epsilon(1.0_dp) .or. &
                (boundary_clamp_count >= boundary_clamp_limit .and. residual_norm > near_tol)) then
               local_stop_reason = wv_newton_stop_boundary_exit
               if (present(stop_reason)) stop_reason = local_stop_reason
               call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, lambda, &
                                           local_stop_reason)
               return
            end if
            delta_h = update_scale*delta_h
            delta_u = update_scale*delta_u
            delta_lambda = update_scale*delta_lambda
            update_norm = update_scale*update_norm
         else
            boundary_clamp_count = max(0, boundary_clamp_count - 1)
         end if
         h = h + delta_h
         u_interleaved = u_interleaved + delta_u
         lambda = lambda + delta_lambda
         if ((.not. ieee_is_finite(h)) .or. (.not. valid_real_vector(u_interleaved)) .or. &
             (.not. valid_real_vector(lambda))) then
            local_stop_reason = wv_newton_stop_nonfinite
            if (present(stop_reason)) stop_reason = local_stop_reason
            call write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, lambda, &
                                        local_stop_reason)
            return
         end if
         residual_prev = residual_norm
         iter = iter + 1
      end do

      local_stop_reason = wv_newton_stop_max_iter
      if (present(stop_reason)) stop_reason = local_stop_reason
      call write_newton_trace_row(trace_context, solve_id, iterations, residual_norm, tol, h, u_interleaved, lambda, &
                                  local_stop_reason)
      error = .true.
   end subroutine wv_solve_first_constraint_dense

   subroutine wv_rattle_step_dense_no_boundary(step_size, wprime, flow_time, x_base, z_base, jac_base, pi, &
                                               flow_time_new, x_new, z_new, jac_new, pi_new, residual_norm, iterations, &
                                               error, status, flow_workspace, intode_diagnostics, constraint_tol, &
                                               constraint_max_iter, solver_stop_reason, adaptive_stop_enabled, &
                                               trace_context, potential, target_flow_time_min, target_flow_time_max)
      real(dp), intent(in) :: step_size, wprime, flow_time, x_base(:), pi(:)
      complex(dp), intent(in) :: z_base(:), jac_base(:, :)
      real(dp), intent(out) :: flow_time_new, x_new(:), pi_new(:), residual_norm
      complex(dp), intent(out) :: z_new(:), jac_new(:, :)
      integer, intent(out) :: iterations
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      real(dp), intent(in), optional :: constraint_tol
      integer, intent(in), optional :: constraint_max_iter
      integer, intent(out), optional :: solver_stop_reason
      logical, intent(in), optional :: adaptive_stop_enabled
      type(wv_newton_trace_context_t), intent(inout), optional :: trace_context
      type(wv_potential_profile_t), intent(in), optional :: potential
      real(dp), intent(in), optional :: target_flow_time_min, target_flow_time_max

      integer :: n, i, flow_status, local_stop_reason
      integer :: local_max_iter
      real(dp) :: h, alpha2, c, local_constraint_tol, wprime_new, w_value_new
      real(dp) :: local_target_flow_time_min, local_target_flow_time_max
      real(dp) :: del_z(size(pi)), u(size(pi)), lambda(size(pi)), residual(size(pi))
      real(dp) :: xi_real(size(pi)), xi_new_real(size(pi)), force_base(size(pi)), force_new(size(pi))
      real(dp) :: pi_tilde(size(pi)), pi_rejected(size(pi))
      complex(dp) :: grad(size(z_base)), grad_new(size(z_base)), xi(size(z_base)), xi_new(size(z_base))
      logical :: converged, local_error

      flow_time_new = flow_time
      x_new = 0.0_dp
      z_new = cmplx(0.0_dp, 0.0_dp, dp)
      jac_new = cmplx(0.0_dp, 0.0_dp, dp)
      pi_new = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status
      local_stop_reason = wv_newton_stop_not_run
      if (present(solver_stop_reason)) solver_stop_reason = local_stop_reason

      n = size(z_base)
      if (n <= 0) return
      if ((.not. ieee_is_finite(step_size)) .or. step_size <= 0.0_dp) return
      if (.not. ieee_is_finite(wprime)) return
      local_constraint_tol = wv_rattle_step_default_constraint_tol
      if (present(constraint_tol)) local_constraint_tol = constraint_tol
      if ((.not. ieee_is_finite(local_constraint_tol)) .or. local_constraint_tol <= 0.0_dp) return
      local_max_iter = 48
      if (present(constraint_max_iter)) local_max_iter = constraint_max_iter
      if (local_max_iter < 0) return
      local_target_flow_time_min = -huge(1.0_dp)
      local_target_flow_time_max = huge(1.0_dp)
      if (present(target_flow_time_min)) local_target_flow_time_min = target_flow_time_min
      if (present(target_flow_time_max)) local_target_flow_time_max = target_flow_time_max
      if (size(x_base) /= n .or. size(x_new) /= n) return
      if (size(jac_base, 1) /= n .or. size(jac_base, 2) /= n) return
      if (size(z_new) /= n .or. size(jac_new, 1) /= n .or. size(jac_new, 2) /= n) return
      if (size(pi) /= 2*n .or. size(pi_new) /= 2*n) return
      if (.not. valid_real_vector(x_base)) return
      if (.not. valid_real_vector(pi)) return
      if (.not. valid_complex_vector(z_base)) return

      call ds(z_base, grad)
      call wv_xi_from_action_gradient(grad, xi, local_error)
      if (local_error) return
      call complex_to_real(xi, xi_real)
      call wv_force_dense_with_jacobian(xi_real, jac_base, wprime, force_base, alpha2, local_error)
      if (local_error) return

      del_z = step_size*pi - step_size*step_size*force_base
      if (present(flow_workspace)) then
         call wv_solve_first_constraint_dense(local_constraint_tol, local_max_iter, flow_time, x_base, z_base, jac_base, del_z, xi_real, &
                                              h, u, lambda, residual_norm, iterations, converged, local_error, flow_status, &
                                              flow_workspace, intode_diagnostics, local_stop_reason, adaptive_stop_enabled, &
                                              trace_context, local_target_flow_time_min, local_target_flow_time_max)
      else
         call wv_solve_first_constraint_dense(local_constraint_tol, local_max_iter, flow_time, x_base, z_base, jac_base, del_z, xi_real, &
                                              h, u, lambda, residual_norm, iterations, converged, local_error, flow_status, &
                                              intode_diagnostics=intode_diagnostics, stop_reason=local_stop_reason, &
                                              adaptive_stop_enabled=adaptive_stop_enabled, trace_context=trace_context, &
                                              target_flow_time_min=local_target_flow_time_min, &
                                              target_flow_time_max=local_target_flow_time_max)
      end if
      if (present(status)) status = flow_status
      if (present(solver_stop_reason)) solver_stop_reason = local_stop_reason
      if (local_error .or. .not. converged) return

      if (present(flow_workspace)) then
         call wv_first_constraint_residual_dense(flow_time, x_base, z_base, del_z, h, u, lambda, residual, local_error, &
                                                 flow_status, z_new, jac_new, flow_workspace, intode_diagnostics)
      else
         call wv_first_constraint_residual_dense(flow_time, x_base, z_base, del_z, h, u, lambda, residual, local_error, &
                                                 flow_status, z_new, jac_new, intode_diagnostics=intode_diagnostics)
      end if
      if (present(status)) status = flow_status
      if (local_error) return

      flow_time_new = flow_time + h
      do i = 1, n
         x_new(i) = x_base(i) + u(2*i - 1)
      end do

      call ds(z_new, grad_new)
      call wv_xi_from_action_gradient(grad_new, xi_new, local_error)
      if (local_error) return
      call complex_to_real(xi_new, xi_new_real)
      wprime_new = wprime
      if (present(potential)) then
         call wv_potential_value_and_derivative(potential, flow_time_new, w_value_new, wprime_new, local_error)
         if (local_error) return
      end if
      call wv_force_dense_with_jacobian(xi_new_real, jac_new, wprime_new, force_new, alpha2, local_error)
      if (local_error) return

      pi_tilde = pi - step_size*(force_base + force_new) - lambda/step_size
      call wv_project_dense_with_jacobian(pi_tilde, xi_new_real, jac_new, pi_new, pi_rejected, c, alpha2, local_error)
      if (local_error) return
      if (.not. valid_real_vector(pi_new)) return
      error = .false.
   end subroutine wv_rattle_step_dense_no_boundary

   subroutine wv_rattle_step_dense_with_boundary(step_size, wprime, t0, t1, d0, d1, flow_time, x_base, z_base, &
                                                 jac_base, pi, flow_time_new, x_new, z_new, jac_new, pi_new, &
                                                 residual_norm, iterations, bounced, error, status, flow_workspace, &
                                                 intode_diagnostics, constraint_tol, constraint_max_iter, solver_stop_reason, &
                                                 adaptive_stop_enabled, trace_context, potential)
      real(dp), intent(in) :: step_size, wprime, t0, t1, d0, d1, flow_time, x_base(:), pi(:)
      complex(dp), intent(in) :: z_base(:), jac_base(:, :)
      real(dp), intent(out) :: flow_time_new, x_new(:), pi_new(:), residual_norm
      complex(dp), intent(out) :: z_new(:), jac_new(:, :)
      integer, intent(out) :: iterations
      logical, intent(out) :: bounced, error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      real(dp), intent(in), optional :: constraint_tol
      integer, intent(in), optional :: constraint_max_iter
      integer, intent(out), optional :: solver_stop_reason
      logical, intent(in), optional :: adaptive_stop_enabled
      type(wv_newton_trace_context_t), intent(inout), optional :: trace_context
      type(wv_potential_profile_t), intent(in), optional :: potential

      integer :: n, flow_status, local_stop_reason
      real(dp) :: flow_time_trial, lower_bound, upper_bound, boundary_tol, predicted_h, predicted_flow_time
      real(dp) :: x_trial(size(x_base)), pi_trial(size(pi))
      complex(dp) :: z_trial(size(z_base)), jac_trial(size(z_base), size(z_base))
      logical :: local_error, predicted_boundary_bounce

      flow_time_new = flow_time
      x_new = 0.0_dp
      z_new = cmplx(0.0_dp, 0.0_dp, dp)
      jac_new = cmplx(0.0_dp, 0.0_dp, dp)
      pi_new = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      bounced = .false.
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status
      local_stop_reason = wv_newton_stop_not_run
      if (present(solver_stop_reason)) solver_stop_reason = local_stop_reason

      n = size(z_base)
      if (n <= 0) return
      if (size(x_base) /= n .or. size(x_new) /= n) return
      if (size(z_new) /= n .or. size(jac_new, 1) /= n .or. size(jac_new, 2) /= n) return
      if (size(pi) /= 2*n .or. size(pi_new) /= 2*n) return
      if (.not. all(ieee_is_finite([step_size, wprime, t0, t1, d0, d1, flow_time]))) return
      if (step_size <= 0.0_dp) return
      if (t1 < t0) return
      if (d0 < 0.0_dp .or. d1 < 0.0_dp) return
      if (.not. valid_real_vector(x_base)) return
      if (.not. valid_real_vector(pi)) return
      if (.not. valid_complex_vector(z_base)) return
      if (.not. valid_complex_matrix(jac_base)) return

      lower_bound = t0 - d0
      upper_bound = t1 + d1
      if ((.not. ieee_is_finite(lower_bound)) .or. (.not. ieee_is_finite(upper_bound))) return
      if (upper_bound < lower_bound) return

      call wv_predict_first_constraint_delta_h(step_size, wprime, z_base, jac_base, pi, predicted_h, local_error)
      if (local_error) return
      predicted_flow_time = flow_time + predicted_h
      if (.not. ieee_is_finite(predicted_flow_time)) return
      boundary_tol = 10.0_dp*epsilon(1.0_dp)*max(1.0_dp, abs(flow_time), abs(lower_bound), abs(upper_bound))
      predicted_boundary_bounce = predicted_flow_time < lower_bound - boundary_tol .or. &
                                  predicted_flow_time > upper_bound + boundary_tol

      if (predicted_flow_time < -boundary_tol .and. predicted_boundary_bounce) then
         flow_status = intode_status_success_zero_time
         if (present(status)) status = flow_status
         if (present(solver_stop_reason)) solver_stop_reason = local_stop_reason
         flow_time_new = flow_time
         x_new = x_base
         z_new = z_base
         jac_new = jac_base
         call apply_boundary_momentum_rule(z_base, jac_base, pi, pi_new, local_error)
         if (local_error) return
         residual_norm = 0.0_dp
         iterations = 0
         bounced = .true.
         error = .false.
         return
      end if

      if (present(flow_workspace)) then
         call wv_rattle_step_dense_no_boundary(step_size, wprime, flow_time, x_base, z_base, jac_base, pi, &
                                               flow_time_trial, x_trial, z_trial, jac_trial, pi_trial, residual_norm, &
                                               iterations, local_error, flow_status, flow_workspace, intode_diagnostics, &
                                               constraint_tol, constraint_max_iter, local_stop_reason, adaptive_stop_enabled, &
                                               trace_context, potential)
      else
         call wv_rattle_step_dense_no_boundary(step_size, wprime, flow_time, x_base, z_base, jac_base, pi, &
                                               flow_time_trial, x_trial, z_trial, jac_trial, pi_trial, residual_norm, &
                                               iterations, local_error, flow_status, intode_diagnostics=intode_diagnostics, &
                                               constraint_tol=constraint_tol, constraint_max_iter=constraint_max_iter, &
                                               solver_stop_reason=local_stop_reason, adaptive_stop_enabled=adaptive_stop_enabled, &
                                               trace_context=trace_context, potential=potential)
      end if
      if (present(status)) status = flow_status
      if (present(solver_stop_reason)) solver_stop_reason = local_stop_reason
      if (local_error) then
         if (predicted_boundary_bounce) then
            flow_time_new = flow_time
            x_new = x_base
            z_new = z_base
            jac_new = jac_base
            call apply_boundary_momentum_rule(z_base, jac_base, pi, pi_new, local_error)
            if (local_error) return
            residual_norm = 0.0_dp
            iterations = 0
            bounced = .true.
            error = .false.
         end if
         return
      end if

      call wv_apply_simplified_boundary_rule(t0, t1, d0, d1, flow_time, x_base, z_base, jac_base, pi, &
                                             flow_time_trial, x_trial, z_trial, jac_trial, pi_trial, flow_time_new, &
                                             x_new, z_new, jac_new, pi_new, bounced, local_error)
      if (local_error) return
      error = .false.
   end subroutine wv_rattle_step_dense_with_boundary

   subroutine wv_predict_first_constraint_delta_h(step_size, wprime, z_base, jac_base, pi, delta_h, error)
      real(dp), intent(in) :: step_size, wprime, pi(:)
      complex(dp), intent(in) :: z_base(:), jac_base(:, :)
      real(dp), intent(out) :: delta_h
      logical, intent(out) :: error

      integer :: n
      real(dp) :: alpha2, c_b
      real(dp) :: del_z(size(pi)), delta_u(size(pi)), delta_lambda(size(pi))
      real(dp) :: xi_real(size(pi)), force_base(size(pi))
      complex(dp) :: grad(size(z_base)), xi(size(z_base))

      delta_h = 0.0_dp
      error = .true.
      n = size(z_base)
      if (n <= 0) return
      if ((.not. ieee_is_finite(step_size)) .or. step_size <= 0.0_dp) return
      if (.not. ieee_is_finite(wprime)) return
      if (size(jac_base, 1) /= n .or. size(jac_base, 2) /= n) return
      if (size(pi) /= 2*n) return
      if (.not. valid_real_vector(pi)) return
      if (.not. valid_complex_vector(z_base)) return
      if (.not. valid_complex_matrix(jac_base)) return

      call ds(z_base, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) return
      call complex_to_real(xi, xi_real)
      call wv_force_dense_with_jacobian(xi_real, jac_base, wprime, force_base, alpha2, error)
      if (error) return

      del_z = step_size*pi - step_size*step_size*force_base
      call wv_simplified_newton_update_dense_with_jacobian(del_z, xi_real, jac_base, delta_h, delta_u, delta_lambda, &
                                                          c_b, alpha2, error)
      if (error) then
         delta_h = 0.0_dp
         return
      end if
      if (.not. ieee_is_finite(delta_h)) then
         delta_h = 0.0_dp
         error = .true.
         return
      end if
      error = .false.
   end subroutine wv_predict_first_constraint_delta_h

   subroutine write_newton_trace_row(trace_context, solve_id, iter, residual_norm, tol, h, u_interleaved, lambda, &
                                     stop_reason)
      type(wv_newton_trace_context_t), intent(inout), optional :: trace_context
      integer, intent(in) :: solve_id, iter, stop_reason
      real(dp), intent(in) :: residual_norm, tol, h, u_interleaved(:), lambda(:)

      if (.not. present(trace_context)) return
      if (trace_context%unit == 0) return
      write (trace_context%unit, '(*(g0,:,","))') solve_id, trace_context%cycle, trace_context%direction, &
         trace_context%step, iter, residual_norm, tol, h, norm2(u_interleaved), norm2(lambda), stop_reason
   end subroutine write_newton_trace_row

   subroutine apply_boundary_momentum_rule(z_current, jac_current, pi_current, pi_out, error)
      complex(dp), intent(in) :: z_current(:), jac_current(:, :)
      real(dp), intent(in) :: pi_current(:)
      real(dp), intent(out) :: pi_out(:)
      logical, intent(out) :: error

      real(dp) :: xi_real(size(pi_current)), c, alpha2
      complex(dp) :: grad(size(z_current)), xi(size(z_current))

      pi_out = 0.0_dp
      error = .true.
      if (size(pi_out) /= size(pi_current)) return
      select case (boundary_policy)
      case (wv_boundary_policy_paper_full_flip)
         pi_out = -pi_current
      case (wv_boundary_policy_normal_reflect)
         call ds(z_current, grad)
         call wv_xi_from_action_gradient(grad, xi, error)
         if (error) return
         call complex_to_real(xi, xi_real)
         call wv_reflect_flow_component_dense_with_jacobian(pi_current, xi_real, jac_current, pi_out, c, alpha2, error)
         if (error) return
      case default
         return
      end select
      if (.not. valid_real_vector(pi_out)) then
         pi_out = 0.0_dp
         error = .true.
         return
      end if
      error = .false.
   end subroutine apply_boundary_momentum_rule

   pure function lower_ascii(text) result(lower)
      character(len=*), intent(in) :: text
      character(len=len(text)) :: lower
      integer :: i, code

      lower = text
      do i = 1, len(text)
         code = iachar(text(i:i))
         if (code >= iachar('A') .and. code <= iachar('Z')) lower(i:i) = achar(code + iachar('a') - iachar('A'))
      end do
   end function lower_ascii

   logical function valid_real_vector(vec) result(ok)
      real(dp), intent(in) :: vec(:)

      ok = size(vec) > 0 .and. all(ieee_is_finite(vec))
   end function valid_real_vector

   logical function valid_complex_vector(vec) result(ok)
      complex(dp), intent(in) :: vec(:)

      ok = size(vec) > 0 .and. all(ieee_is_finite(real(vec, dp))) .and. all(ieee_is_finite(aimag(vec)))
   end function valid_complex_vector

   logical function valid_complex_matrix(mat) result(ok)
      complex(dp), intent(in) :: mat(:, :)

      ok = size(mat, 1) > 0 .and. size(mat, 2) > 0 .and. &
           all(ieee_is_finite(real(mat, dp))) .and. all(ieee_is_finite(aimag(mat)))
   end function valid_complex_matrix

end module wv_hmc_constraints

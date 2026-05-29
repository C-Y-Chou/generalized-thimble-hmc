module wv_hmc_constraints
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use model, only: calculate_action, ds
   use solve_flow, only: flow_at, flow_workspace_t, intode_diagnostics_context_t, intode_status_success_zero_time, &
                         intode_status_unknown
   use utils, only: complex_to_real, dp
   use wv_hmc_kernels, only: wv_force_dense_with_jacobian, wv_project_dense_with_jacobian, &
                             wv_simplified_newton_update_dense_with_jacobian, wv_xi_from_action_gradient
   implicit none

   private
   public :: wv_apply_simplified_boundary_rule, wv_calculate_hamiltonian, wv_first_constraint_residual_dense, &
             wv_rattle_step_dense_with_boundary, wv_rattle_step_dense_no_boundary, wv_solve_first_constraint_dense

   real(dp), parameter :: wv_rattle_step_default_constraint_tol = 1.0e-8_dp

contains

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
         pi_out = -pi_current
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
                                                intode_diagnostics)
      real(dp), intent(in) :: flow_time, x_base(:), del_z(:), h, u_interleaved(:), lambda(:)
      complex(dp), intent(in) :: z_base(:)
      real(dp), intent(out) :: residual(:)
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      complex(dp), intent(out), optional :: z_new_out(:), jac_new_out(:, :)
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      integer :: n, i, flow_status
      real(dp) :: target_flow_time
      real(dp) :: x_trial(size(x_base))
      complex(dp) :: z_new(size(z_base)), jac_new(size(z_base), size(z_base))
      logical :: flow_failed

      residual = 0.0_dp
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status

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
      jac_new = cmplx(0.0_dp, 0.0_dp, dp)
      if (present(flow_workspace)) then
         call flow_at(target_flow_time, x_trial, z_new, jac_new, flow_failed, flow_status, flow_workspace, intode_diagnostics)
      else
         call flow_at(target_flow_time, x_trial, z_new, jac_new, flow_failed, flow_status, intode_diagnostics=intode_diagnostics)
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
      if (present(jac_new_out)) jac_new_out = jac_new
      error = .false.
   end subroutine wv_first_constraint_residual_dense

   subroutine wv_solve_first_constraint_dense(tol, max_iter, flow_time, x_base, z_base, jac_base, del_z, xi_real, &
                                             h, u_interleaved, lambda, residual_norm, iterations, converged, error, status, &
                                             flow_workspace, intode_diagnostics)
      real(dp), intent(in) :: tol, flow_time, x_base(:), del_z(:), xi_real(:)
      integer, intent(in) :: max_iter
      complex(dp), intent(in) :: z_base(:), jac_base(:, :)
      real(dp), intent(out) :: h, u_interleaved(:), lambda(:), residual_norm
      integer, intent(out) :: iterations
      logical, intent(out) :: converged, error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      integer :: n, iter, flow_status
      real(dp) :: residual(size(del_z)), delta_u(size(del_z)), delta_lambda(size(del_z))
      real(dp) :: delta_h, c_b, alpha2
      logical :: residual_error, update_error

      h = 0.0_dp
      u_interleaved = 0.0_dp
      lambda = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      converged = .false.
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status

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

      do iter = 0, max_iter
         if (present(flow_workspace)) then
            call wv_first_constraint_residual_dense(flow_time, x_base, z_base, del_z, h, u_interleaved, lambda, &
                                                    residual, residual_error, flow_status, flow_workspace=flow_workspace, &
                                                    intode_diagnostics=intode_diagnostics)
         else
            call wv_first_constraint_residual_dense(flow_time, x_base, z_base, del_z, h, u_interleaved, lambda, &
                                                    residual, residual_error, flow_status, intode_diagnostics=intode_diagnostics)
         end if
         if (present(status)) status = flow_status
         if (residual_error) return

         residual_norm = norm2(residual)
         iterations = iter
         if (.not. ieee_is_finite(residual_norm)) return
         if (residual_norm <= tol) then
            converged = .true.
            error = .false.
            return
         end if
         if (iter >= max_iter) exit

         call wv_simplified_newton_update_dense_with_jacobian(residual, xi_real, jac_base, delta_h, delta_u, delta_lambda, &
                                                             c_b, alpha2, update_error)
         if (update_error) return
         h = h + delta_h
         u_interleaved = u_interleaved + delta_u
         lambda = lambda + delta_lambda
         if ((.not. ieee_is_finite(h)) .or. (.not. valid_real_vector(u_interleaved)) .or. &
             (.not. valid_real_vector(lambda))) return
      end do

      error = .true.
   end subroutine wv_solve_first_constraint_dense

   subroutine wv_rattle_step_dense_no_boundary(step_size, wprime, flow_time, x_base, z_base, jac_base, pi, &
                                               flow_time_new, x_new, z_new, jac_new, pi_new, residual_norm, iterations, &
                                               error, status, flow_workspace, intode_diagnostics, constraint_tol, &
                                               constraint_max_iter)
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

      integer :: n, i, flow_status
      integer :: local_max_iter
      real(dp) :: h, alpha2, c, local_constraint_tol
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

      n = size(z_base)
      if (n <= 0) return
      if ((.not. ieee_is_finite(step_size)) .or. step_size <= 0.0_dp) return
      if (.not. ieee_is_finite(wprime)) return
      local_constraint_tol = wv_rattle_step_default_constraint_tol
      if (present(constraint_tol)) local_constraint_tol = constraint_tol
      if ((.not. ieee_is_finite(local_constraint_tol)) .or. local_constraint_tol <= 0.0_dp) return
      local_max_iter = 16
      if (present(constraint_max_iter)) local_max_iter = constraint_max_iter
      if (local_max_iter < 0) return
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
                                              flow_workspace, intode_diagnostics)
      else
         call wv_solve_first_constraint_dense(local_constraint_tol, local_max_iter, flow_time, x_base, z_base, jac_base, del_z, xi_real, &
                                              h, u, lambda, residual_norm, iterations, converged, local_error, flow_status, &
                                              intode_diagnostics=intode_diagnostics)
      end if
      if (present(status)) status = flow_status
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
      call wv_force_dense_with_jacobian(xi_new_real, jac_new, wprime, force_new, alpha2, local_error)
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
                                                 intode_diagnostics, constraint_tol, constraint_max_iter)
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

      integer :: n, flow_status
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
         flow_time_new = flow_time
         x_new = x_base
         z_new = z_base
         jac_new = jac_base
         pi_new = -pi
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
                                               constraint_tol, constraint_max_iter)
      else
         call wv_rattle_step_dense_no_boundary(step_size, wprime, flow_time, x_base, z_base, jac_base, pi, &
                                               flow_time_trial, x_trial, z_trial, jac_trial, pi_trial, residual_norm, &
                                               iterations, local_error, flow_status, intode_diagnostics=intode_diagnostics, &
                                               constraint_tol=constraint_tol, constraint_max_iter=constraint_max_iter)
      end if
      if (present(status)) status = flow_status
      if (local_error) then
         if (predicted_boundary_bounce) then
            flow_time_new = flow_time
            x_new = x_base
            z_new = z_base
            jac_new = jac_base
            pi_new = -pi
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

module wv_hmc_trajectory
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use model, only: ds
   use solve_flow, only: flow_workspace_t, intode_diagnostics_context_t, intode_status_unknown
   use utils, only: complex_to_real, dp
   use wv_hmc_constraints, only: wv_calculate_hamiltonian, wv_rattle_step_dense_with_boundary
   use wv_hmc_kernels, only: wv_project_dense_with_jacobian, wv_xi_from_action_gradient
   use wv_hmc_potential, only: wv_potential_profile_t, wv_potential_value_and_derivative
   implicit none

   private
   public :: wv_metropolis_accept_probability, wv_trajectory_diagnostics_t, wv_trajectory_dense, &
             wv_transition_diagnostics_t, wv_transition_dense

   real(dp), parameter :: wv_reverse_gate_state_tol_default = 1.0e-6_dp
   real(dp), parameter :: wv_reverse_gate_momentum_tol_default = 1.0e-4_dp

   type :: wv_trajectory_diagnostics_t
      integer :: attempted_steps = 0
      integer :: completed_steps = 0
      integer :: bounced_steps = 0
      integer :: solver_iterations_total = 0
      integer :: last_status = intode_status_unknown
      real(dp) :: max_constraint_residual = 0.0_dp
      real(dp) :: initial_hamiltonian = huge(1.0_dp)
      real(dp) :: final_hamiltonian = huge(1.0_dp)
      real(dp) :: delta_hamiltonian = huge(1.0_dp)
   end type wv_trajectory_diagnostics_t

   type :: wv_transition_diagnostics_t
      type(wv_trajectory_diagnostics_t) :: trajectory
      type(wv_trajectory_diagnostics_t) :: reverse_trajectory
      logical :: accepted = .false.
      logical :: reverse_gate_checked = .false.
      logical :: reverse_gate_passed = .false.
      logical :: reverse_gate_rejected = .false.
      logical :: reverse_gate_failed = .false.
      real(dp) :: accept_probability = 0.0_dp
      real(dp) :: projection_alpha2 = 0.0_dp
      real(dp) :: projection_rejected_norm = huge(1.0_dp)
      real(dp) :: reverse_gate_t_error = huge(1.0_dp)
      real(dp) :: reverse_gate_state_error = huge(1.0_dp)
      real(dp) :: reverse_gate_momentum_error = huge(1.0_dp)
   end type wv_transition_diagnostics_t

contains

   subroutine wv_metropolis_accept_probability(delta_hamiltonian, probability, error)
      real(dp), intent(in) :: delta_hamiltonian
      real(dp), intent(out) :: probability
      logical, intent(out) :: error

      probability = 0.0_dp
      error = .true.
      if (.not. ieee_is_finite(delta_hamiltonian)) return
      if (delta_hamiltonian <= 0.0_dp) then
         probability = 1.0_dp
      else if (delta_hamiltonian > log(huge(1.0_dp))) then
         probability = 0.0_dp
      else
         probability = exp(-delta_hamiltonian)
      end if
      if (.not. ieee_is_finite(probability)) then
         probability = 0.0_dp
         return
      end if
      error = .false.
   end subroutine wv_metropolis_accept_probability

   subroutine wv_trajectory_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time, x, z, jac, pi, &
                                  flow_time_out, x_out, z_out, jac_out, pi_out, diagnostics, error, status, &
                                  flow_workspace, intode_diagnostics, constraint_tol, constraint_max_iter)
      real(dp), intent(in) :: step_size, t0, t1, d0, d1, flow_time, x(:), pi(:)
      integer, intent(in) :: num_steps
      type(wv_potential_profile_t), intent(in) :: potential
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: flow_time_out, x_out(:), pi_out(:)
      complex(dp), intent(out) :: z_out(:), jac_out(:, :)
      type(wv_trajectory_diagnostics_t), intent(out) :: diagnostics
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      real(dp), intent(in), optional :: constraint_tol
      integer, intent(in), optional :: constraint_max_iter

      integer :: n, step_idx, step_status, iterations
      real(dp) :: w_value, wprime, residual_norm
      real(dp) :: t_current, t_next
      real(dp) :: x_current(size(x)), x_next(size(x)), pi_current(size(pi)), pi_next(size(pi))
      complex(dp) :: z_current(size(z)), z_next(size(z)), jac_current(size(z), size(z)), jac_next(size(z), size(z))
      logical :: local_error, bounced

      diagnostics = wv_trajectory_diagnostics_t()
      flow_time_out = flow_time
      x_out = 0.0_dp
      z_out = cmplx(0.0_dp, 0.0_dp, dp)
      jac_out = cmplx(0.0_dp, 0.0_dp, dp)
      pi_out = 0.0_dp
      error = .true.
      step_status = intode_status_unknown
      if (present(status)) status = step_status

      n = size(z)
      if (n <= 0) return
      if (num_steps < 0) return
      if ((.not. ieee_is_finite(step_size)) .or. step_size <= 0.0_dp) return
      if (size(x) /= n .or. size(x_out) /= n) return
      if (size(jac, 1) /= n .or. size(jac, 2) /= n) return
      if (size(z_out) /= n .or. size(jac_out, 1) /= n .or. size(jac_out, 2) /= n) return
      if (size(pi) /= 2*n .or. size(pi_out) /= 2*n) return

      t_current = flow_time
      x_current = x
      z_current = z
      jac_current = jac
      pi_current = pi

      call wv_potential_value_and_derivative(potential, t_current, w_value, wprime, local_error)
      if (local_error) return
      call wv_calculate_hamiltonian(z_current, pi_current, w_value, diagnostics%initial_hamiltonian, local_error)
      if (local_error) return

      do step_idx = 1, num_steps
         diagnostics%attempted_steps = diagnostics%attempted_steps + 1
         call wv_potential_value_and_derivative(potential, t_current, w_value, wprime, local_error)
         if (local_error) return
         if (present(flow_workspace)) then
            call wv_rattle_step_dense_with_boundary(step_size, wprime, t0, t1, d0, d1, t_current, x_current, &
                                                    z_current, jac_current, pi_current, t_next, x_next, z_next, &
                                                    jac_next, pi_next, residual_norm, iterations, bounced, local_error, &
                                                    step_status, flow_workspace, intode_diagnostics, constraint_tol, &
                                                    constraint_max_iter)
         else
            call wv_rattle_step_dense_with_boundary(step_size, wprime, t0, t1, d0, d1, t_current, x_current, &
                                                    z_current, jac_current, pi_current, t_next, x_next, z_next, &
                                                    jac_next, pi_next, residual_norm, iterations, bounced, local_error, &
                                                    step_status, intode_diagnostics=intode_diagnostics, &
                                                    constraint_tol=constraint_tol, constraint_max_iter=constraint_max_iter)
         end if
         diagnostics%last_status = step_status
         if (present(status)) status = step_status
         if (local_error) return

         diagnostics%completed_steps = diagnostics%completed_steps + 1
         diagnostics%solver_iterations_total = diagnostics%solver_iterations_total + iterations
         diagnostics%max_constraint_residual = max(diagnostics%max_constraint_residual, residual_norm)
         if (bounced) diagnostics%bounced_steps = diagnostics%bounced_steps + 1
         t_current = t_next
         x_current = x_next
         z_current = z_next
         jac_current = jac_next
         pi_current = pi_next
      end do

      call wv_potential_value_and_derivative(potential, t_current, w_value, wprime, local_error)
      if (local_error) return
      call wv_calculate_hamiltonian(z_current, pi_current, w_value, diagnostics%final_hamiltonian, local_error)
      if (local_error) return
      diagnostics%delta_hamiltonian = diagnostics%final_hamiltonian - diagnostics%initial_hamiltonian

      flow_time_out = t_current
      x_out = x_current
      z_out = z_current
      jac_out = jac_current
      pi_out = pi_current
      error = .false.
   end subroutine wv_trajectory_dense

   subroutine wv_transition_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time, x, z, jac, raw_pi, &
                                  uniform01, flow_time_out, x_out, z_out, jac_out, diagnostics, error, status, &
                                  flow_workspace, intode_diagnostics, constraint_tol, constraint_max_iter, &
                                  reverse_gate_state_tol, reverse_gate_momentum_tol)
      real(dp), intent(in) :: step_size, t0, t1, d0, d1, flow_time, x(:), raw_pi(:), uniform01
      integer, intent(in) :: num_steps
      type(wv_potential_profile_t), intent(in) :: potential
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: flow_time_out, x_out(:)
      complex(dp), intent(out) :: z_out(:), jac_out(:, :)
      type(wv_transition_diagnostics_t), intent(out) :: diagnostics
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      real(dp), intent(in), optional :: constraint_tol
      integer, intent(in), optional :: constraint_max_iter
      real(dp), intent(in), optional :: reverse_gate_state_tol, reverse_gate_momentum_tol

      integer :: n, flow_status
      real(dp) :: c
      real(dp) :: pi(size(raw_pi)), pi_rejected(size(raw_pi)), pi_proposed(size(raw_pi))
      real(dp) :: flow_time_proposed, x_proposed(size(x))
      complex(dp) :: z_proposed(size(z)), jac_proposed(size(z), size(z)), grad(size(z)), xi(size(z))
      real(dp) :: xi_real(size(raw_pi))
      logical :: local_error

      diagnostics = wv_transition_diagnostics_t()
      flow_time_out = flow_time
      x_out = 0.0_dp
      z_out = cmplx(0.0_dp, 0.0_dp, dp)
      jac_out = cmplx(0.0_dp, 0.0_dp, dp)
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status

      n = size(z)
      if (n <= 0) return
      if ((.not. ieee_is_finite(uniform01)) .or. uniform01 < 0.0_dp .or. uniform01 > 1.0_dp) return
      if (size(x) /= n .or. size(x_out) /= n) return
      if (size(jac, 1) /= n .or. size(jac, 2) /= n) return
      if (size(z_out) /= n .or. size(jac_out, 1) /= n .or. size(jac_out, 2) /= n) return
      if (size(raw_pi) /= 2*n) return

      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, local_error)
      if (local_error) return
      call complex_to_real(xi, xi_real)
      call wv_project_dense_with_jacobian(raw_pi, xi_real, jac, pi, pi_rejected, c, diagnostics%projection_alpha2, &
                                          local_error)
      if (local_error) return
      diagnostics%projection_rejected_norm = norm2(pi_rejected)

      if (present(flow_workspace)) then
         call wv_trajectory_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time, x, z, jac, pi, &
                                  flow_time_proposed, x_proposed, z_proposed, jac_proposed, pi_proposed, &
                                  diagnostics%trajectory, local_error, flow_status, flow_workspace, intode_diagnostics, &
                                  constraint_tol, constraint_max_iter)
      else
         call wv_trajectory_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time, x, z, jac, pi, &
                                  flow_time_proposed, x_proposed, z_proposed, jac_proposed, pi_proposed, &
                                  diagnostics%trajectory, local_error, flow_status, intode_diagnostics=intode_diagnostics, &
                                  constraint_tol=constraint_tol, constraint_max_iter=constraint_max_iter)
      end if
      if (present(status)) status = flow_status
      if (local_error) return
      call wv_reverse_gate_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time, x, z, jac, pi, &
                                 flow_time_proposed, x_proposed, z_proposed, jac_proposed, pi_proposed, &
                                 diagnostics, local_error, flow_status, flow_workspace, intode_diagnostics, &
                                 constraint_tol, constraint_max_iter, reverse_gate_state_tol, reverse_gate_momentum_tol)
      if (present(status)) status = flow_status
      if (local_error) then
         diagnostics%reverse_gate_rejected = .true.
         flow_time_out = flow_time
         x_out = x
         z_out = z
         jac_out = jac
         error = .false.
         return
      end if
      if (.not. diagnostics%reverse_gate_passed) then
         flow_time_out = flow_time
         x_out = x
         z_out = z
         jac_out = jac
         error = .false.
         return
      end if
      call wv_metropolis_accept_probability(diagnostics%trajectory%delta_hamiltonian, diagnostics%accept_probability, &
                                            local_error)
      if (local_error) return

      diagnostics%accepted = uniform01 <= diagnostics%accept_probability
      if (diagnostics%accepted) then
         flow_time_out = flow_time_proposed
         x_out = x_proposed
         z_out = z_proposed
         jac_out = jac_proposed
      else
         flow_time_out = flow_time
         x_out = x
         z_out = z
         jac_out = jac
      end if
      error = .false.
   end subroutine wv_transition_dense

   subroutine wv_reverse_gate_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time_initial, x_initial, &
                                    z_initial, jac_initial, pi_initial, flow_time_forward, x_forward, z_forward, &
                                    jac_forward, pi_forward, diagnostics, error, status, flow_workspace, &
                                    intode_diagnostics, constraint_tol, constraint_max_iter, reverse_gate_state_tol, &
                                    reverse_gate_momentum_tol)
      real(dp), intent(in) :: step_size, t0, t1, d0, d1, flow_time_initial, flow_time_forward
      real(dp), intent(in) :: x_initial(:), pi_initial(:), x_forward(:), pi_forward(:)
      integer, intent(in) :: num_steps
      type(wv_potential_profile_t), intent(in) :: potential
      complex(dp), intent(in) :: z_initial(:), jac_initial(:, :), z_forward(:), jac_forward(:, :)
      type(wv_transition_diagnostics_t), intent(inout) :: diagnostics
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      real(dp), intent(in), optional :: constraint_tol
      integer, intent(in), optional :: constraint_max_iter
      real(dp), intent(in), optional :: reverse_gate_state_tol, reverse_gate_momentum_tol

      integer :: flow_status
      real(dp) :: flow_time_reverse, t_scale, x_scale, z_scale, jac_scale, pi_scale
      real(dp) :: x_reverse(size(x_initial)), pi_reverse(size(pi_initial))
      real(dp) :: x_error, z_error, jac_error, state_tol, momentum_tol
      complex(dp) :: z_reverse(size(z_initial)), jac_reverse(size(z_initial), size(z_initial))
      logical :: local_error

      diagnostics%reverse_gate_checked = .true.
      diagnostics%reverse_gate_passed = .false.
      diagnostics%reverse_gate_rejected = .false.
      diagnostics%reverse_gate_failed = .false.
      diagnostics%reverse_gate_t_error = huge(1.0_dp)
      diagnostics%reverse_gate_state_error = huge(1.0_dp)
      diagnostics%reverse_gate_momentum_error = huge(1.0_dp)
      error = .false.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status

      state_tol = wv_reverse_gate_state_tol_default
      momentum_tol = wv_reverse_gate_momentum_tol_default
      if (present(reverse_gate_state_tol)) state_tol = reverse_gate_state_tol
      if (present(reverse_gate_momentum_tol)) momentum_tol = reverse_gate_momentum_tol
      if ((.not. ieee_is_finite(state_tol)) .or. state_tol < 0.0_dp) then
         error = .true.
         return
      end if
      if ((.not. ieee_is_finite(momentum_tol)) .or. momentum_tol < 0.0_dp) then
         error = .true.
         return
      end if

      if (present(flow_workspace)) then
         call wv_trajectory_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time_forward, x_forward, &
                                  z_forward, jac_forward, -pi_forward, flow_time_reverse, x_reverse, z_reverse, &
                                  jac_reverse, pi_reverse, diagnostics%reverse_trajectory, local_error, flow_status, &
                                  flow_workspace, intode_diagnostics, constraint_tol, constraint_max_iter)
      else
         call wv_trajectory_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time_forward, x_forward, &
                                  z_forward, jac_forward, -pi_forward, flow_time_reverse, x_reverse, z_reverse, &
                                  jac_reverse, pi_reverse, diagnostics%reverse_trajectory, local_error, flow_status, &
                                  intode_diagnostics=intode_diagnostics, constraint_tol=constraint_tol, &
                                  constraint_max_iter=constraint_max_iter)
      end if
      if (present(status)) status = flow_status
      if (local_error) then
         diagnostics%reverse_gate_failed = .true.
         diagnostics%reverse_gate_rejected = .true.
         return
      end if

      t_scale = max(1.0_dp, abs(flow_time_initial))
      x_scale = max(1.0_dp, norm2(x_initial))
      z_scale = max(1.0_dp, sqrt(sum(abs(z_initial)**2)))
      jac_scale = max(1.0_dp, sqrt(sum(abs(jac_initial)**2)))
      pi_scale = max(1.0_dp, norm2(pi_initial))
      diagnostics%reverse_gate_t_error = abs(flow_time_reverse - flow_time_initial)/t_scale
      x_error = norm2(x_reverse - x_initial)/x_scale
      z_error = sqrt(sum(abs(z_reverse - z_initial)**2))/z_scale
      jac_error = sqrt(sum(abs(jac_reverse - jac_initial)**2))/jac_scale
      diagnostics%reverse_gate_state_error = max(max(diagnostics%reverse_gate_t_error, x_error), &
                                                 max(z_error, jac_error))
      diagnostics%reverse_gate_momentum_error = norm2(pi_reverse + pi_initial)/pi_scale
      diagnostics%reverse_gate_passed = diagnostics%reverse_gate_state_error <= state_tol .and. &
                                        diagnostics%reverse_gate_momentum_error <= momentum_tol
      diagnostics%reverse_gate_rejected = .not. diagnostics%reverse_gate_passed
   end subroutine wv_reverse_gate_dense

end module wv_hmc_trajectory

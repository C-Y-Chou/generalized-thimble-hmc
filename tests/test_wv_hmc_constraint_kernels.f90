program test_wv_hmc_constraint_kernels
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite, ieee_quiet_nan, ieee_value
   use model, only: calculate_action, ds
   use model_observables, only: model_observable_count
   use param_mod, only: read_parameters, set_derivative_mode, stephanov_emit_diagnostics, stephanov_include_mu_prefactor, &
                        stephanov_mass, stephanov_mu, stephanov_n, stephanov_nf, stephanov_tau
   use solve_flow, only: flow_apply_worldvolume_operator_at, flow_at
   use utils, only: complex_to_real, dp
   use wv_hmc_constraints, only: wv_apply_simplified_boundary_rule, wv_calculate_hamiltonian, &
                                 wv_first_constraint_residual_dense, wv_rattle_step_dense_no_boundary, &
                                 wv_rattle_step_dense_with_boundary, wv_solve_first_constraint_dense
   use wv_hmc_kernels, only: wv_decompose_matrix_free_at, wv_force_dense_with_jacobian, &
                             wv_force_matrix_free_at, wv_project_dense_with_jacobian, wv_project_matrix_free_at, &
                             wv_simplified_newton_update_dense_with_jacobian, &
                             wv_simplified_newton_update_matrix_free_at, wv_xi_from_action_gradient
   use wv_hmc_potential, only: wv_potential_zero
   use wv_hmc_trajectory, only: wv_metropolis_accept_probability, wv_trajectory_dense, wv_trajectory_diagnostics_t, &
                                wv_transition_dense, wv_transition_diagnostics_t
   use wv_hmc_driver, only: wv_dense_chain_summary_t, wv_run_dense_chain
   use wv_hmc_measurement, only: wv_accumulate_weighted_observables, wv_dense_alpha2, wv_dense_measurement_factor, &
                                 wv_init_weighted_observable_accumulator, wv_measurement_factor_t, &
                                 wv_weighted_observable_accumulator_t, wv_weighted_observable_estimates, &
                                 wv_weighted_observable_phase_coherence
   implicit none

   integer :: failures

   failures = 0
   call configure_stephanov_test_model()
   call check_zero_residual(failures)
   call check_linearized_update_reduces_residual(failures)
   call check_dense_first_constraint_solver(failures)
   call check_final_momentum_projection_after_solve(failures)
   call check_dense_rattle_step_reversibility_smoke(failures)
   call check_dense_rattle_energy_scaling_smoke(failures)
   call check_simplified_boundary_rule(failures)
   call check_dense_rattle_boundary_wrapper(failures)
   call check_matrix_free_operator_zero_time(failures)
   call check_matrix_free_decompose_reconstructs_operator_image(failures)
   call check_matrix_free_zero_time_matches_dense_wrappers(failures)
   call check_dense_trajectory_matches_one_step_wrapper(failures)
   call check_wv_metropolis_accept_probability(failures)
   call check_dense_transition_accepts_uniform_zero(failures)
   call check_dense_chain_driver_smoke(failures)
   call check_dense_measurement_factor(failures)
   call check_weighted_observable_accumulator(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] WV-HMC constraint kernel failures=", failures
      error stop 1
   end if
   write (*, '(A)') "[PASS] WV-HMC constraint kernels"

contains

   subroutine check_zero_residual(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status
      real(dp), allocatable :: x(:), del_z(:), u(:), lambda(:), residual(:)
      complex(dp), allocatable :: z(:), jac(:, :)
      logical :: error, ok

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), del_z(2*n_state), u(2*n_state), lambda(2*n_state), residual(2*n_state))
      allocate (z(n_state), jac(n_state, n_state))
      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_zero_constraint_residual flow_failed status=", status
         return
      end if

      del_z = 0.0_dp
      u = 0.0_dp
      lambda = 0.0_dp
      call wv_first_constraint_residual_dense(0.0_dp, x, z, del_z, 0.0_dp, u, lambda, residual, error, status)
      ok = (.not. error) .and. norm2(residual) <= 1.0e-14_dp

      write (*, '(A,L1,A,ES12.4)') "[CHECK] wv_zero_constraint_residual ok=", ok, " residual=", norm2(residual)
      if (.not. ok) failures = failures + 1
   end subroutine check_zero_residual

   subroutine check_linearized_update_reduces_residual(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status
      real(dp), allocatable :: x(:), del_z(:), u(:), lambda(:), residual0(:), residual1(:)
      real(dp), allocatable :: xi_real(:)
      complex(dp), allocatable :: z(:), jac(:, :), grad(:), xi(:)
      real(dp) :: step_size, delta_h, c_b, alpha2, initial_norm, updated_norm, xi_norm
      logical :: error, ok

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), del_z(2*n_state), u(2*n_state), lambda(2*n_state), residual0(2*n_state), residual1(2*n_state))
      allocate (xi_real(2*n_state), z(n_state), jac(n_state, n_state), grad(n_state), xi(n_state))
      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_linearized_update_residual flow_failed status=", status
         return
      end if

      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_linearized_update_residual xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)

      step_size = 2.0e-4_dp
      xi_norm = norm2(xi_real)
      if (xi_norm <= 0.0_dp) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_linearized_update_residual xi_zero"
         return
      end if
      del_z = step_size*xi_real/xi_norm
      u = 0.0_dp
      lambda = 0.0_dp
      call wv_first_constraint_residual_dense(0.0_dp, x, z, del_z, 0.0_dp, u, lambda, residual0, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_linearized_update_residual initial_residual_failed status=", status
         return
      end if
      initial_norm = norm2(residual0)

      call wv_simplified_newton_update_dense_with_jacobian(del_z, xi_real, jac, delta_h, u, lambda, c_b, alpha2, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_linearized_update_residual update_failed"
         return
      end if
      call wv_first_constraint_residual_dense(0.0_dp, x, z, del_z, delta_h, u, lambda, residual1, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4)') &
            "[CHECK] wv_linearized_update_residual updated_residual_failed status=", status, &
            " delta_h=", delta_h, " u_norm=", norm2(u), " lambda_norm=", norm2(lambda), " alpha2=", alpha2
         return
      end if
      updated_norm = norm2(residual1)

      ok = initial_norm > 0.0_dp .and. updated_norm < 2.0e-2_dp*initial_norm .and. updated_norm < 1.0e-5_dp
      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] wv_linearized_update_residual ok=", ok, &
         " initial=", initial_norm, " updated=", updated_norm, " ratio=", updated_norm/max(initial_norm, tiny(1.0_dp))
      if (.not. ok) failures = failures + 1
   end subroutine check_linearized_update_reduces_residual

   subroutine check_dense_first_constraint_solver(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status, iterations
      real(dp), allocatable :: x(:), del_z(:), u(:), lambda(:), residual(:), xi_real(:)
      complex(dp), allocatable :: z(:), jac(:, :), grad(:), xi(:)
      real(dp) :: step_size, h, residual_norm, final_residual_norm, xi_norm
      logical :: converged, error, ok

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), del_z(2*n_state), u(2*n_state), lambda(2*n_state), residual(2*n_state), xi_real(2*n_state))
      allocate (z(n_state), jac(n_state, n_state), grad(n_state), xi(n_state))
      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_dense_first_constraint_solver flow_failed status=", status
         return
      end if

      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_first_constraint_solver xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)
      xi_norm = norm2(xi_real)
      if (xi_norm <= 0.0_dp) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_first_constraint_solver xi_zero"
         return
      end if

      step_size = 2.0e-4_dp
      del_z = step_size*xi_real/xi_norm
      call wv_solve_first_constraint_dense(1.0e-10_dp, 8, 0.0_dp, x, z, jac, del_z, xi_real, h, u, lambda, &
                                           residual_norm, iterations, converged, error, status)
      if (.not. error) then
         call wv_first_constraint_residual_dense(0.0_dp, x, z, del_z, h, u, lambda, residual, error, status)
      end if
      if (.not. error) then
         final_residual_norm = norm2(residual)
      else
         final_residual_norm = huge(1.0_dp)
      end if

      ok = converged .and. (.not. error) .and. residual_norm <= 1.0e-10_dp .and. &
           final_residual_norm <= 1.0e-10_dp .and. iterations > 0 .and. iterations <= 8
      write (*, '(A,L1,A,I0,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] wv_dense_first_constraint_solver ok=", ok, &
         " iterations=", iterations, " residual=", residual_norm, " final=", final_residual_norm, " h=", h
      if (.not. ok) failures = failures + 1
   end subroutine check_dense_first_constraint_solver

   subroutine check_final_momentum_projection_after_solve(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status, iterations
      real(dp), allocatable :: x(:), del_z(:), u(:), lambda(:), residual(:), xi_real(:), xi_new_real(:)
      real(dp), allocatable :: pi(:), pi_tilde(:), force_base(:), force_new(:), pi_projected(:), pi_rejected(:)
      real(dp), allocatable :: pi_reprojected(:), pi_reproject_rejected(:)
      complex(dp), allocatable :: z(:), jac(:, :), z_new(:), jac_new(:, :), grad(:), grad_new(:), xi(:), xi_new(:)
      real(dp) :: step_size, h, residual_norm, xi_norm, alpha2, c
      real(dp) :: projection_recon_norm, rejected_orthogonality, reproject_reject_norm
      logical :: converged, error, ok

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), del_z(2*n_state), u(2*n_state), lambda(2*n_state), residual(2*n_state), &
                xi_real(2*n_state), xi_new_real(2*n_state), pi(2*n_state), pi_tilde(2*n_state), &
                force_base(2*n_state), force_new(2*n_state), pi_projected(2*n_state), pi_rejected(2*n_state), &
                pi_reprojected(2*n_state), pi_reproject_rejected(2*n_state))
      allocate (z(n_state), jac(n_state, n_state), z_new(n_state), jac_new(n_state, n_state), grad(n_state), &
                grad_new(n_state), xi(n_state), xi_new(n_state))

      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_final_momentum_projection flow_failed status=", status
         return
      end if
      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_final_momentum_projection xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)
      xi_norm = norm2(xi_real)
      if (xi_norm <= 0.0_dp) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_final_momentum_projection xi_zero"
         return
      end if

      step_size = 2.0e-4_dp
      pi = xi_real/xi_norm
      call wv_force_dense_with_jacobian(xi_real, jac, 0.0_dp, force_base, alpha2, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_final_momentum_projection force_base_failed"
         return
      end if
      del_z = step_size*pi - step_size*step_size*force_base

      call wv_solve_first_constraint_dense(1.0e-10_dp, 8, 0.0_dp, x, z, jac, del_z, xi_real, h, u, lambda, &
                                           residual_norm, iterations, converged, error, status)
      if (error .or. .not. converged) then
         failures = failures + 1
         write (*, '(A,L1,A,I0,A,ES12.4)') "[CHECK] wv_final_momentum_projection solve_failed converged=", &
            converged, " status=", status, " residual=", residual_norm
         return
      end if
      call wv_first_constraint_residual_dense(0.0_dp, x, z, del_z, h, u, lambda, residual, error, status, z_new, jac_new)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_final_momentum_projection final_residual_failed status=", status
         return
      end if

      call ds(z_new, grad_new)
      call wv_xi_from_action_gradient(grad_new, xi_new, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_final_momentum_projection xi_new_failed"
         return
      end if
      call complex_to_real(xi_new, xi_new_real)
      call wv_force_dense_with_jacobian(xi_new_real, jac_new, 0.0_dp, force_new, alpha2, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_final_momentum_projection force_new_failed"
         return
      end if

      pi_tilde = pi - step_size*(force_base + force_new) - lambda/step_size
      call wv_project_dense_with_jacobian(pi_tilde, xi_new_real, jac_new, pi_projected, pi_rejected, c, alpha2, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_final_momentum_projection project_failed"
         return
      end if
      call wv_project_dense_with_jacobian(pi_projected, xi_new_real, jac_new, pi_reprojected, pi_reproject_rejected, &
                                          c, alpha2, error)
      projection_recon_norm = norm2(pi_projected + pi_rejected - pi_tilde)
      rejected_orthogonality = abs(dot_product(pi_projected, pi_rejected))
      reproject_reject_norm = norm2(pi_reproject_rejected)
      ok = (.not. error) .and. projection_recon_norm <= 1.0e-10_dp .and. rejected_orthogonality <= 1.0e-10_dp .and. &
           reproject_reject_norm <= 1.0e-10_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] wv_final_momentum_projection ok=", ok, &
         " recon=", projection_recon_norm, " orth=", rejected_orthogonality, " reproject_reject=", reproject_reject_norm
      if (.not. ok) failures = failures + 1
   end subroutine check_final_momentum_projection_after_solve

   subroutine check_dense_rattle_step_reversibility_smoke(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status, iterations_forward, iterations_reverse
      real(dp), allocatable :: x(:), x_forward(:), x_back(:), xi_real(:), pi(:), pi_forward(:), pi_back(:)
      complex(dp), allocatable :: z(:), jac(:, :), z_forward(:), jac_forward(:, :), z_back(:), jac_back(:, :)
      complex(dp), allocatable :: grad(:), xi(:)
      real(dp) :: step_size, t_forward, t_back, residual_forward, residual_reverse, xi_norm
      real(dp) :: x_back_norm, z_back_norm, pi_back_norm, t_back_abs
      logical :: error, ok

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), x_forward(n_state), x_back(n_state), xi_real(2*n_state), pi(2*n_state), &
                pi_forward(2*n_state), pi_back(2*n_state))
      allocate (z(n_state), jac(n_state, n_state), z_forward(n_state), jac_forward(n_state, n_state), &
                z_back(n_state), jac_back(n_state, n_state), grad(n_state), xi(n_state))

      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_dense_rattle_reversibility flow_failed status=", status
         return
      end if
      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_reversibility xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)
      xi_norm = norm2(xi_real)
      if (xi_norm <= 0.0_dp) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_reversibility xi_zero"
         return
      end if

      step_size = 5.0e-5_dp
      pi = xi_real/xi_norm
      call wv_rattle_step_dense_no_boundary(step_size, 0.0_dp, 0.0_dp, x, z, jac, pi, t_forward, x_forward, &
                                            z_forward, jac_forward, pi_forward, residual_forward, iterations_forward, &
                                            error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0,A,ES12.4)') "[CHECK] wv_dense_rattle_reversibility forward_failed status=", status, &
            " residual=", residual_forward
         return
      end if
      call wv_rattle_step_dense_no_boundary(step_size, 0.0_dp, t_forward, x_forward, z_forward, jac_forward, -pi_forward, &
                                            t_back, x_back, z_back, jac_back, pi_back, residual_reverse, iterations_reverse, &
                                            error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0,A,ES12.4,A,ES12.4)') "[CHECK] wv_dense_rattle_reversibility reverse_failed status=", status, &
            " t_forward=", t_forward, " residual=", residual_reverse
         return
      end if

      t_back_abs = abs(t_back)
      x_back_norm = norm2(x_back - x)
      z_back_norm = sqrt(sum(abs(z_back - z)**2))
      pi_back_norm = norm2(pi_back + pi)
      ok = t_back_abs <= 1.0e-7_dp .and. x_back_norm <= 1.0e-7_dp .and. z_back_norm <= 1.0e-7_dp .and. &
           pi_back_norm <= 5.0e-5_dp .and. residual_forward <= 1.0e-8_dp .and. residual_reverse <= 1.0e-8_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4,A,I0,A,I0)') &
         "[CHECK] wv_dense_rattle_reversibility ok=", ok, " dt=", t_back_abs, " dx=", x_back_norm, &
         " dz=", z_back_norm, " dpi=", pi_back_norm, " it_f=", iterations_forward, " it_r=", iterations_reverse
      if (.not. ok) failures = failures + 1
   end subroutine check_dense_rattle_step_reversibility_smoke

   subroutine check_dense_rattle_energy_scaling_smoke(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status, iterations_large, iterations_mid, iterations_small, i
      real(dp), allocatable :: x(:), x_large(:), x_mid(:), x_small(:), xi_real(:), raw_pi(:), pi(:), pi_rejected(:)
      real(dp), allocatable :: pi_large(:), pi_mid(:), pi_small(:)
      complex(dp), allocatable :: z(:), jac(:, :), z_large(:), jac_large(:, :), z_mid(:), jac_mid(:, :)
      complex(dp), allocatable :: z_small(:), jac_small(:, :)
      complex(dp), allocatable :: grad(:), xi(:)
      real(dp) :: step_large, step_small, t_large, t_mid, t_small, residual_large, residual_mid, residual_small, xi_norm
      real(dp) :: c, alpha2, h_initial, h_large, h_small, delta_large, delta_small
      logical :: error, ok

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), x_large(n_state), x_mid(n_state), x_small(n_state), xi_real(2*n_state), raw_pi(2*n_state), &
                pi(2*n_state), pi_rejected(2*n_state), pi_large(2*n_state), pi_mid(2*n_state), pi_small(2*n_state))
      allocate (z(n_state), jac(n_state, n_state), z_large(n_state), jac_large(n_state, n_state), &
                z_mid(n_state), jac_mid(n_state, n_state), z_small(n_state), jac_small(n_state, n_state), &
                grad(n_state), xi(n_state))

      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_dense_rattle_energy_scaling flow_failed status=", status
         return
      end if
      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_energy_scaling xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)
      xi_norm = norm2(xi_real)
      if (xi_norm <= 0.0_dp) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_energy_scaling xi_zero"
         return
      end if

      do i = 1, size(raw_pi)
         raw_pi(i) = (-1.0_dp)**i*(0.03_dp + 0.002_dp*real(i, dp))
      end do
      call wv_project_dense_with_jacobian(raw_pi, xi_real, jac, pi, pi_rejected, c, alpha2, error)
      if (error .or. norm2(pi) <= 0.0_dp) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_energy_scaling project_failed"
         return
      end if
      pi = pi/norm2(pi)

      call wv_calculate_hamiltonian(z, pi, 0.0_dp, h_initial, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_energy_scaling initial_h_failed"
         return
      end if

      step_large = 1.0e-4_dp
      step_small = 5.0e-5_dp
      call wv_rattle_step_dense_no_boundary(step_large, 0.0_dp, 0.0_dp, x, z, jac, pi, t_large, x_large, &
                                            z_large, jac_large, pi_large, residual_large, iterations_large, &
                                            error, status, constraint_tol=1.0e-12_dp, constraint_max_iter=24)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0,A,ES12.4)') "[CHECK] wv_dense_rattle_energy_scaling large_step_failed status=", status, &
            " residual=", residual_large
         return
      end if
      call wv_rattle_step_dense_no_boundary(step_small, 0.0_dp, 0.0_dp, x, z, jac, pi, t_mid, x_mid, &
                                            z_mid, jac_mid, pi_mid, residual_mid, iterations_mid, &
                                            error, status, constraint_tol=1.0e-12_dp, constraint_max_iter=24)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0,A,ES12.4)') "[CHECK] wv_dense_rattle_energy_scaling first_half_failed status=", status, &
            " residual=", residual_mid
         return
      end if
      call wv_rattle_step_dense_no_boundary(step_small, 0.0_dp, t_mid, x_mid, z_mid, jac_mid, pi_mid, t_small, x_small, &
                                            z_small, jac_small, pi_small, residual_small, iterations_small, &
                                            error, status, constraint_tol=1.0e-12_dp, constraint_max_iter=24)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0,A,ES12.4)') "[CHECK] wv_dense_rattle_energy_scaling second_half_failed status=", status, &
            " residual=", residual_small
         return
      end if
      call wv_calculate_hamiltonian(z_large, pi_large, 0.0_dp, h_large, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_energy_scaling large_h_failed"
         return
      end if
      call wv_calculate_hamiltonian(z_small, pi_small, 0.0_dp, h_small, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_energy_scaling small_h_failed"
         return
      end if

      delta_large = abs(h_large - h_initial)
      delta_small = abs(h_small - h_initial)
      ok = delta_large > 0.0_dp .and. delta_small > 0.0_dp .and. delta_small < delta_large .and. &
           residual_large <= 1.0e-8_dp .and. residual_mid <= 1.0e-8_dp .and. residual_small <= 1.0e-8_dp
      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,I0,A,I0,A,I0)') &
         "[CHECK] wv_dense_rattle_energy_scaling ok=", ok, " dH_large=", delta_large, " dH_small=", delta_small, &
         " it_large=", iterations_large, " it_mid=", iterations_mid, " it_small=", iterations_small
      if (.not. ok) failures = failures + 1
   end subroutine check_dense_rattle_energy_scaling_smoke

   subroutine check_simplified_boundary_rule(failures)
      integer, intent(inout) :: failures
      integer, parameter :: n = 4
      real(dp) :: x_current(n), x_trial(n), x_out(n), pi_current(2*n), pi_trial(2*n), pi_out(2*n)
      complex(dp) :: z_current(n), z_trial(n), z_out(n), jac_current(n, n), jac_trial(n, n), jac_out(n, n)
      real(dp) :: t_out
      logical :: bounced, error, ok

      call fill_boundary_fixture(x_current, x_trial, z_current, z_trial, jac_current, jac_trial, pi_current, pi_trial)

      call wv_apply_simplified_boundary_rule(0.0_dp, 0.03_dp, 0.002_dp, 0.004_dp, 0.01_dp, &
                                             x_current, z_current, jac_current, pi_current, 0.034_dp, &
                                             x_trial, z_trial, jac_trial, pi_trial, t_out, x_out, z_out, &
                                             jac_out, pi_out, bounced, error)
      ok = (.not. error) .and. (.not. bounced) .and. abs(t_out - 0.034_dp) <= 1.0e-14_dp .and. &
           norm2(x_out - x_trial) <= 1.0e-14_dp .and. sqrt(sum(abs(z_out - z_trial)**2)) <= 1.0e-14_dp .and. &
           sqrt(sum(abs(jac_out - jac_trial)**2)) <= 1.0e-14_dp .and. norm2(pi_out - pi_trial) <= 1.0e-14_dp

      call wv_apply_simplified_boundary_rule(0.0_dp, 0.03_dp, 0.002_dp, 0.004_dp, 0.01_dp, &
                                             x_current, z_current, jac_current, pi_current, -0.0020001_dp, &
                                             x_trial, z_trial, jac_trial, pi_trial, t_out, x_out, z_out, &
                                             jac_out, pi_out, bounced, error)
      ok = ok .and. (.not. error) .and. bounced .and. abs(t_out - 0.01_dp) <= 1.0e-14_dp .and. &
           norm2(x_out - x_current) <= 1.0e-14_dp .and. sqrt(sum(abs(z_out - z_current)**2)) <= 1.0e-14_dp .and. &
           sqrt(sum(abs(jac_out - jac_current)**2)) <= 1.0e-14_dp .and. norm2(pi_out + pi_current) <= 1.0e-14_dp

      call wv_apply_simplified_boundary_rule(0.0_dp, 0.03_dp, 0.002_dp, 0.004_dp, 0.01_dp, &
                                             x_current, z_current, jac_current, pi_current, 0.0340001_dp, &
                                             x_trial, z_trial, jac_trial, pi_trial, t_out, x_out, z_out, &
                                             jac_out, pi_out, bounced, error)
      ok = ok .and. (.not. error) .and. bounced .and. norm2(pi_out + pi_current) <= 1.0e-14_dp

      call wv_apply_simplified_boundary_rule(0.0_dp, 0.03_dp, -0.002_dp, 0.004_dp, 0.01_dp, &
                                             x_current, z_current, jac_current, pi_current, 0.02_dp, &
                                             x_trial, z_trial, jac_trial, pi_trial, t_out, x_out, z_out, &
                                             jac_out, pi_out, bounced, error)
      ok = ok .and. error

      write (*, '(A,L1,A,ES12.4,A,L1)') "[CHECK] wv_simplified_boundary_rule ok=", ok, &
         " t_out=", t_out, " bounced=", bounced
      if (.not. ok) failures = failures + 1
   end subroutine check_simplified_boundary_rule

   subroutine check_dense_rattle_boundary_wrapper(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status, iterations_trial, iterations_wrap
      real(dp), allocatable :: x(:), x_trial(:), x_wrap(:), xi_real(:), pi(:), pi_trial(:), pi_wrap(:)
      complex(dp), allocatable :: z(:), jac(:, :), z_trial(:), jac_trial(:, :), z_wrap(:), jac_wrap(:, :)
      complex(dp), allocatable :: grad(:), xi(:)
      real(dp) :: step_size, t_trial, t_wrap, t_start, residual_trial, residual_wrap, xi_norm
      logical :: error, bounced, ok

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), x_trial(n_state), x_wrap(n_state), xi_real(2*n_state), pi(2*n_state), &
                pi_trial(2*n_state), pi_wrap(2*n_state))
      allocate (z(n_state), jac(n_state, n_state), z_trial(n_state), jac_trial(n_state, n_state), &
                z_wrap(n_state), jac_wrap(n_state, n_state), grad(n_state), xi(n_state))

      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_dense_rattle_boundary_wrapper flow_failed status=", status
         return
      end if
      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_boundary_wrapper xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)
      xi_norm = norm2(xi_real)
      if (xi_norm <= 0.0_dp) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_boundary_wrapper xi_zero"
         return
      end if

      step_size = 5.0e-5_dp
      pi = xi_real/xi_norm
      call wv_rattle_step_dense_no_boundary(step_size, 0.0_dp, 0.0_dp, x, z, jac, pi, t_trial, x_trial, &
                                            z_trial, jac_trial, pi_trial, residual_trial, iterations_trial, &
                                            error, status)
      if (error .or. t_trial <= 0.0_dp) then
         failures = failures + 1
         write (*, '(A,I0,A,ES12.4,A,ES12.4)') "[CHECK] wv_dense_rattle_boundary_wrapper trial_failed status=", &
            status, " t_trial=", t_trial, " residual=", residual_trial
         return
      end if

      call wv_rattle_step_dense_with_boundary(step_size, 0.0_dp, 0.0_dp, 0.1_dp, 0.0_dp, 0.0_dp, 0.0_dp, &
                                             x, z, jac, pi, t_wrap, x_wrap, z_wrap, jac_wrap, pi_wrap, residual_wrap, &
                                             iterations_wrap, bounced, error, status)
      ok = (.not. error) .and. (.not. bounced) .and. abs(t_wrap - t_trial) <= 1.0e-12_dp .and. &
           norm2(x_wrap - x_trial) <= 1.0e-12_dp .and. sqrt(sum(abs(z_wrap - z_trial)**2)) <= 1.0e-12_dp .and. &
           norm2(pi_wrap - pi_trial) <= 1.0e-12_dp .and. residual_wrap <= 1.0e-8_dp .and. &
           iterations_wrap == iterations_trial

      call wv_rattle_step_dense_with_boundary(step_size, 0.0_dp, 0.0_dp, 0.5_dp*t_trial, 0.0_dp, 0.0_dp, 0.0_dp, &
                                             x, z, jac, pi, t_wrap, x_wrap, z_wrap, jac_wrap, pi_wrap, residual_wrap, &
                                             iterations_wrap, bounced, error, status)
      ok = ok .and. (.not. error) .and. bounced .and. abs(t_wrap) <= 1.0e-14_dp .and. &
           norm2(x_wrap - x) <= 1.0e-14_dp .and. sqrt(sum(abs(z_wrap - z)**2)) <= 1.0e-14_dp .and. &
           sqrt(sum(abs(jac_wrap - jac)**2)) <= 1.0e-14_dp .and. norm2(pi_wrap + pi) <= 1.0e-14_dp

      pi_trial = -pi
      call wv_rattle_step_dense_with_boundary(step_size, 0.0_dp, 0.0_dp, 0.1_dp, 0.0_dp, 0.0_dp, 0.0_dp, &
                                             x, z, jac, pi_trial, t_wrap, x_wrap, z_wrap, jac_wrap, pi_wrap, residual_wrap, &
                                             iterations_wrap, bounced, error, status)
      ok = ok .and. (.not. error) .and. bounced .and. abs(t_wrap) <= 1.0e-14_dp .and. &
           norm2(x_wrap - x) <= 1.0e-14_dp .and. sqrt(sum(abs(z_wrap - z)**2)) <= 1.0e-14_dp .and. &
           sqrt(sum(abs(jac_wrap - jac)**2)) <= 1.0e-14_dp .and. norm2(pi_wrap - pi) <= 1.0e-14_dp .and. &
           residual_wrap <= 1.0e-14_dp .and. iterations_wrap == 0

      t_start = 1.0e-8_dp
      call flow_at(t_start, x, z_trial, jac_trial, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_dense_rattle_boundary_wrapper near_lower_flow_failed status=", status
         return
      end if
      call ds(z_trial, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_boundary_wrapper near_lower_xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)
      xi_norm = norm2(xi_real)
      if (xi_norm <= 0.0_dp) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_rattle_boundary_wrapper near_lower_xi_zero"
         return
      end if
      pi_trial = -xi_real/xi_norm
      call wv_rattle_step_dense_with_boundary(step_size, 0.0_dp, 0.0_dp, 0.1_dp, 0.0_dp, 0.0_dp, t_start, &
                                             x, z_trial, jac_trial, pi_trial, t_wrap, x_wrap, z_wrap, jac_wrap, &
                                             pi_wrap, residual_wrap, iterations_wrap, bounced, error, status)
      ok = ok .and. (.not. error) .and. bounced .and. abs(t_wrap - t_start) <= 1.0e-14_dp .and. &
           norm2(x_wrap - x) <= 1.0e-14_dp .and. sqrt(sum(abs(z_wrap - z_trial)**2)) <= 1.0e-14_dp .and. &
           sqrt(sum(abs(jac_wrap - jac_trial)**2)) <= 1.0e-14_dp .and. norm2(pi_wrap + pi_trial) <= 1.0e-14_dp .and. &
           residual_wrap <= 1.0e-14_dp .and. iterations_wrap == 0

      write (*, '(A,L1,A,ES12.4,A,L1,A,I0)') "[CHECK] wv_dense_rattle_boundary_wrapper ok=", ok, &
         " t_trial=", t_trial, " bounced=", bounced, " iterations=", iterations_wrap
      if (.not. ok) failures = failures + 1
   end subroutine check_dense_rattle_boundary_wrapper

   subroutine check_matrix_free_operator_zero_time(failures)
      integer, intent(inout) :: failures
      integer :: n_state, i, status
      real(dp), allocatable :: x(:), w0(:), tangent(:), normal(:), combined(:)
      complex(dp), allocatable :: z(:)
      real(dp) :: z_error, tangent_error, normal_error, combined_error
      logical :: error, ok

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), w0(2*n_state), tangent(2*n_state), normal(2*n_state), combined(2*n_state), z(n_state))
      call fill_base_x(x)
      do i = 1, n_state
         w0(2*i - 1) = 0.011_dp*real(i, dp)
         w0(2*i) = -0.007_dp*real(i, dp)
      end do

      call flow_apply_worldvolume_operator_at(0.0_dp, x, w0, z, tangent, normal, combined, error, status)
      z_error = sqrt(sum(abs(z - cmplx(x, 0.0_dp, dp))**2))
      tangent_error = norm2(tangent(1::2) - w0(1::2)) + norm2(tangent(2::2))
      normal_error = norm2(normal(1::2)) + norm2(normal(2::2) - w0(2::2))
      combined_error = norm2(combined - w0)
      ok = (.not. error) .and. z_error <= 1.0e-14_dp .and. tangent_error <= 1.0e-14_dp .and. &
           normal_error <= 1.0e-14_dp .and. combined_error <= 1.0e-14_dp
      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] wv_matrix_free_operator_zero_time ok=", ok, &
         " z=", z_error, " tangent=", tangent_error, " combined=", combined_error
      if (.not. ok) failures = failures + 1
   end subroutine check_matrix_free_operator_zero_time

   subroutine check_matrix_free_decompose_reconstructs_operator_image(failures)
      integer, intent(inout) :: failures
      integer :: n_state, i, status, iterations
      real(dp), allocatable :: x(:), w0(:), b(:), tangent_expected(:), normal_expected(:)
      real(dp), allocatable :: coords(:), tangent(:), normal(:)
      complex(dp), allocatable :: z(:)
      real(dp) :: flow_time, residual_norm, coord_error, tangent_error, normal_error, reconstruct_error
      logical :: error, ok

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), w0(2*n_state), b(2*n_state), tangent_expected(2*n_state), normal_expected(2*n_state), &
                coords(2*n_state), tangent(2*n_state), normal(2*n_state), z(n_state))
      call fill_base_x(x)
      do i = 1, n_state
         w0(2*i - 1) = 0.009_dp*cos(real(i, dp))
         w0(2*i) = 0.006_dp*sin(real(i, dp))
      end do

      flow_time = 1.0e-5_dp
      call flow_apply_worldvolume_operator_at(flow_time, x, w0, z, tangent_expected, normal_expected, b, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_matrix_free_decompose_reconstructs apply_failed status=", status
         return
      end if
      call wv_decompose_matrix_free_at(flow_time, x, b, coords, tangent, normal, residual_norm, iterations, &
                                       1.0e-8_dp, 80, error, status)
      coord_error = norm2(coords - w0)
      tangent_error = norm2(tangent - tangent_expected)
      normal_error = norm2(normal - normal_expected)
      reconstruct_error = norm2(tangent + normal - b)
      ok = (.not. error) .and. iterations > 0 .and. residual_norm <= 1.0e-7_dp .and. coord_error <= 1.0e-6_dp .and. &
           tangent_error <= 1.0e-6_dp .and. normal_error <= 1.0e-6_dp .and. reconstruct_error <= 1.0e-7_dp
      write (*, '(A,L1,A,I0,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] wv_matrix_free_decompose_reconstructs ok=", ok, " iterations=", iterations, &
         " residual=", residual_norm, " coord=", coord_error, " recon=", reconstruct_error
      if (.not. ok) failures = failures + 1
   end subroutine check_matrix_free_decompose_reconstructs_operator_image

   subroutine check_matrix_free_zero_time_matches_dense_wrappers(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status, iterations
      real(dp), allocatable :: x(:), w(:), xi_real(:), force_dense(:), force_mf(:)
      real(dp), allocatable :: par_dense(:), perp_dense(:), par_mf(:), perp_mf(:)
      real(dp), allocatable :: du_dense(:), dlambda_dense(:), du_mf(:), dlambda_mf(:)
      complex(dp), allocatable :: z(:), jac(:, :), grad(:), xi(:)
      real(dp) :: c_dense, c_mf, alpha_dense, alpha_mf, residual_norm
      real(dp) :: dh_dense, dh_mf, cb_dense, cb_mf, force_error, project_error, newton_error
      logical :: error, ok

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), w(2*n_state), xi_real(2*n_state), force_dense(2*n_state), force_mf(2*n_state), &
                par_dense(2*n_state), perp_dense(2*n_state), par_mf(2*n_state), perp_mf(2*n_state), &
                du_dense(2*n_state), dlambda_dense(2*n_state), du_mf(2*n_state), dlambda_mf(2*n_state), &
                z(n_state), jac(n_state, n_state), grad(n_state), xi(n_state))
      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_matrix_free_zero_time_dense flow_failed status=", status
         return
      end if
      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_matrix_free_zero_time_dense xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)
      w = 0.0_dp
      w(1::2) = 0.013_dp
      w(2::2) = -0.005_dp

      call wv_project_dense_with_jacobian(w, xi_real, jac, par_dense, perp_dense, c_dense, alpha_dense, error)
      ok = .not. error
      call wv_project_matrix_free_at(0.0_dp, x, w, xi_real, par_mf, perp_mf, c_mf, alpha_mf, residual_norm, &
                                     iterations, 1.0e-10_dp, 64, error, status)
      project_error = norm2(par_mf - par_dense) + norm2(perp_mf - perp_dense) + abs(c_mf - c_dense) + &
                      abs(alpha_mf - alpha_dense)
      ok = ok .and. (.not. error) .and. project_error <= 1.0e-8_dp

      call wv_force_dense_with_jacobian(xi_real, jac, 0.4_dp, force_dense, alpha_dense, error)
      ok = ok .and. (.not. error)
      call wv_force_matrix_free_at(0.0_dp, x, xi_real, 0.4_dp, force_mf, alpha_mf, residual_norm, iterations, &
                                   1.0e-10_dp, 64, error, status)
      force_error = norm2(force_mf - force_dense) + abs(alpha_mf - alpha_dense)
      ok = ok .and. (.not. error) .and. force_error <= 1.0e-8_dp

      call wv_simplified_newton_update_dense_with_jacobian(w, xi_real, jac, dh_dense, du_dense, dlambda_dense, &
                                                           cb_dense, alpha_dense, error)
      ok = ok .and. (.not. error)
      call wv_simplified_newton_update_matrix_free_at(0.0_dp, x, w, xi_real, dh_mf, du_mf, dlambda_mf, &
                                                      cb_mf, alpha_mf, residual_norm, iterations, 1.0e-10_dp, 64, &
                                                      error, status)
      newton_error = abs(dh_mf - dh_dense) + norm2(du_mf - du_dense) + norm2(dlambda_mf - dlambda_dense) + &
                     abs(cb_mf - cb_dense) + abs(alpha_mf - alpha_dense)
      ok = ok .and. (.not. error) .and. newton_error <= 1.0e-8_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] wv_matrix_free_zero_time_dense ok=", ok, &
         " project=", project_error, " force=", force_error, " newton=", newton_error
      if (.not. ok) failures = failures + 1
   end subroutine check_matrix_free_zero_time_matches_dense_wrappers

   subroutine check_dense_trajectory_matches_one_step_wrapper(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status, iterations
      real(dp), allocatable :: x(:), x_step(:), x_traj(:), xi_real(:), pi(:), pi_step(:), pi_traj(:)
      complex(dp), allocatable :: z(:), jac(:, :), z_step(:), jac_step(:, :), z_traj(:), jac_traj(:, :)
      complex(dp), allocatable :: grad(:), xi(:)
      real(dp) :: step_size, t_step, t_traj, residual_step, xi_norm
      real(dp) :: x_error, z_error, jac_error, pi_error, t_error
      logical :: error, bounced, ok
      type(wv_trajectory_diagnostics_t) :: diag

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), x_step(n_state), x_traj(n_state), xi_real(2*n_state), pi(2*n_state), &
                pi_step(2*n_state), pi_traj(2*n_state))
      allocate (z(n_state), jac(n_state, n_state), z_step(n_state), jac_step(n_state, n_state), &
                z_traj(n_state), jac_traj(n_state, n_state), grad(n_state), xi(n_state))

      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_dense_trajectory_one_step flow_failed status=", status
         return
      end if
      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_trajectory_one_step xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)
      xi_norm = norm2(xi_real)
      if (xi_norm <= 0.0_dp) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_trajectory_one_step xi_zero"
         return
      end if

      step_size = 5.0e-5_dp
      pi = xi_real/xi_norm
      call wv_rattle_step_dense_with_boundary(step_size, 0.0_dp, 0.0_dp, 0.2_dp, 0.0_dp, 0.0_dp, 0.0_dp, &
                                             x, z, jac, pi, t_step, x_step, z_step, jac_step, pi_step, residual_step, &
                                             iterations, bounced, error, status)
      if (error .or. bounced) then
         failures = failures + 1
         write (*, '(A,I0,A,L1)') "[CHECK] wv_dense_trajectory_one_step step_failed status=", status, &
            " bounced=", bounced
         return
      end if
      call wv_trajectory_dense(step_size, 1, wv_potential_zero(), 0.0_dp, 0.2_dp, 0.0_dp, 0.0_dp, 0.0_dp, &
                               x, z, jac, pi, t_traj, x_traj, z_traj, jac_traj, pi_traj, diag, error, status)

      t_error = abs(t_traj - t_step)
      x_error = norm2(x_traj - x_step)
      z_error = sqrt(sum(abs(z_traj - z_step)**2))
      jac_error = sqrt(sum(abs(jac_traj - jac_step)**2))
      pi_error = norm2(pi_traj - pi_step)
      ok = (.not. error) .and. diag%attempted_steps == 1 .and. diag%completed_steps == 1 .and. &
           diag%bounced_steps == 0 .and. diag%solver_iterations_total == iterations .and. &
           diag%max_constraint_residual <= 1.0e-8_dp .and. ieee_is_finite(diag%delta_hamiltonian) .and. &
           t_error <= 1.0e-14_dp .and. x_error <= 1.0e-14_dp .and. z_error <= 1.0e-14_dp .and. &
           jac_error <= 1.0e-14_dp .and. pi_error <= 1.0e-14_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] wv_dense_trajectory_one_step ok=", ok, &
         " dt=", t_error, " dx=", x_error, " dpi=", pi_error
      if (.not. ok) failures = failures + 1
   end subroutine check_dense_trajectory_matches_one_step_wrapper

   subroutine check_wv_metropolis_accept_probability(failures)
      integer, intent(inout) :: failures
      real(dp) :: probability
      logical :: error, ok

      call wv_metropolis_accept_probability(-0.5_dp, probability, error)
      ok = (.not. error) .and. abs(probability - 1.0_dp) <= 1.0e-14_dp
      call wv_metropolis_accept_probability(log(4.0_dp), probability, error)
      ok = ok .and. (.not. error) .and. abs(probability - 0.25_dp) <= 1.0e-14_dp
      call wv_metropolis_accept_probability(2.0_dp*log(huge(1.0_dp)), probability, error)
      ok = ok .and. (.not. error) .and. probability == 0.0_dp
      call wv_metropolis_accept_probability(ieee_value(0.0_dp, ieee_quiet_nan), probability, error)
      ok = ok .and. error .and. probability == 0.0_dp

      write (*, '(A,L1,A,ES12.4)') "[CHECK] wv_metropolis_accept_probability ok=", ok, " probability=", probability
      if (.not. ok) failures = failures + 1
   end subroutine check_wv_metropolis_accept_probability

   subroutine check_dense_transition_accepts_uniform_zero(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status
      real(dp), allocatable :: x(:), x_transition(:), x_expected(:), x_rejected(:)
      real(dp), allocatable :: raw_pi(:), projected_pi(:), rejected_pi(:), pi_expected(:)
      complex(dp), allocatable :: z(:), jac(:, :), z_transition(:), jac_transition(:, :)
      complex(dp), allocatable :: z_expected(:), jac_expected(:, :), z_rejected(:), jac_rejected(:, :)
      complex(dp), allocatable :: grad(:), xi(:)
      real(dp), allocatable :: xi_real(:)
      real(dp) :: step_size, t_transition, t_expected, t_rejected, c, alpha2, residual_expected
      real(dp) :: t_error, x_error, z_error, jac_error, reject_state_error
      integer :: iterations_expected
      logical :: error, bounced, ok
      type(wv_transition_diagnostics_t) :: transition_diag, reject_diag

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), x_transition(n_state), x_expected(n_state), x_rejected(n_state), &
                raw_pi(2*n_state), projected_pi(2*n_state), &
                rejected_pi(2*n_state), pi_expected(2*n_state), xi_real(2*n_state), z(n_state), jac(n_state, n_state), &
                z_transition(n_state), jac_transition(n_state, n_state), z_expected(n_state), jac_expected(n_state, n_state), &
                z_rejected(n_state), jac_rejected(n_state, n_state), grad(n_state), xi(n_state))

      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_dense_transition_accept flow_failed status=", status
         return
      end if
      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_transition_accept xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)
      raw_pi = xi_real/norm2(xi_real)
      call wv_project_dense_with_jacobian(raw_pi, xi_real, jac, projected_pi, rejected_pi, c, alpha2, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_transition_accept project_failed"
         return
      end if

      step_size = 5.0e-5_dp
      call wv_rattle_step_dense_with_boundary(step_size, 0.0_dp, 0.0_dp, 0.2_dp, 0.0_dp, 0.0_dp, 0.0_dp, &
                                             x, z, jac, projected_pi, t_expected, x_expected, z_expected, jac_expected, &
                                             pi_expected, residual_expected, iterations_expected, bounced, error, status)
      if (error .or. bounced) then
         failures = failures + 1
         write (*, '(A,I0,A,L1)') "[CHECK] wv_dense_transition_accept step_failed status=", status, &
            " bounced=", bounced
         return
      end if
      call wv_transition_dense(step_size, 1, wv_potential_zero(), 0.0_dp, 0.2_dp, 0.0_dp, 0.0_dp, 0.0_dp, &
                               x, z, jac, raw_pi, 0.0_dp, t_transition, x_transition, z_transition, jac_transition, &
                               transition_diag, error, status)
      t_error = abs(t_transition - t_expected)
      x_error = norm2(x_transition - x_expected)
      z_error = sqrt(sum(abs(z_transition - z_expected)**2))
      jac_error = sqrt(sum(abs(jac_transition - jac_expected)**2))
      ok = (.not. error) .and. transition_diag%accepted .and. transition_diag%accept_probability > 0.0_dp .and. &
           transition_diag%trajectory%completed_steps == 1 .and. &
           transition_diag%reverse_gate_checked .and. transition_diag%reverse_gate_passed .and. &
           (.not. transition_diag%reverse_gate_rejected) .and. &
           transition_diag%reverse_gate_state_error <= 1.0e-6_dp .and. &
           transition_diag%reverse_gate_momentum_error <= 1.0e-4_dp .and. &
           abs(transition_diag%projection_alpha2 - alpha2) <= 1.0e-12_dp .and. &
           abs(transition_diag%projection_rejected_norm - norm2(rejected_pi)) <= 1.0e-12_dp .and. &
           t_error <= 1.0e-14_dp .and. x_error <= 1.0e-14_dp .and. z_error <= 1.0e-14_dp .and. &
           jac_error <= 1.0e-14_dp

      call wv_transition_dense(step_size, 1, wv_potential_zero(), 0.0_dp, 0.2_dp, 0.0_dp, 0.0_dp, 0.0_dp, &
                               x, z, jac, raw_pi, 0.0_dp, t_rejected, x_rejected, z_rejected, jac_rejected, &
                               reject_diag, error, status, reverse_gate_state_tol=1.0e-20_dp, &
                               reverse_gate_momentum_tol=1.0e-20_dp)
      reject_state_error = abs(t_rejected) + norm2(x_rejected - x) + sqrt(sum(abs(z_rejected - z)**2)) + &
                           sqrt(sum(abs(jac_rejected - jac)**2))
      ok = ok .and. (.not. error) .and. (.not. reject_diag%accepted) .and. reject_diag%reverse_gate_checked .and. &
           reject_diag%reverse_gate_rejected .and. (.not. reject_diag%reverse_gate_passed) .and. &
           reject_state_error <= 1.0e-12_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] wv_dense_transition_accept ok=", ok, &
         " accept_prob=", transition_diag%accept_probability, " dx=", x_error, " dz=", z_error, &
         " rg_state=", transition_diag%reverse_gate_state_error
      if (.not. ok) failures = failures + 1
   end subroutine check_dense_transition_accepts_uniform_zero

   subroutine check_dense_chain_driver_smoke(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status, observable_count, first_accepted, first_rejected, first_odex_failure
      real(dp), allocatable :: x(:), x_out(:)
      complex(dp), allocatable :: z_out(:), jac_out(:, :), estimates(:)
      real(dp) :: flow_time_out, coherence, first_coherence, first_max_residual
      logical :: error, ok
      type(wv_dense_chain_summary_t) :: summary
      type(wv_weighted_observable_accumulator_t) :: accumulator

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), x_out(n_state), z_out(n_state), jac_out(n_state, n_state))
      call fill_base_x(x)
      observable_count = model_observable_count()
      allocate (estimates(observable_count))
      call wv_init_weighted_observable_accumulator(accumulator, observable_count, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_chain_driver accumulator_init_failed"
         return
      end if

      call wv_run_dense_chain(20260529, 3, 5.0e-5_dp, 1, wv_potential_zero(), 0.0_dp, 0.2_dp, 0.0_dp, 0.0_dp, &
                              1.0e-5_dp, x, flow_time_out, x_out, z_out, jac_out, summary, error, status, &
                              observable_accumulator=accumulator)
      call wv_weighted_observable_estimates(accumulator, estimates, error)
      ok = (.not. error) .and. summary%cycles_requested == 3 .and. summary%cycles_completed == 3 .and. &
           summary%transitions_failed == 0 .and. summary%accepted + summary%rejected == 3 .and. &
           summary%rejected == summary%metropolis_rejected + summary%reverse_gate_rejected .and. &
           summary%reverse_gate_rejected == 0 .and. &
           summary%trajectory_steps == 3 .and. summary%max_constraint_residual <= 1.0e-7_dp .and. &
           summary%odex_failure == 0 .and. ieee_is_finite(flow_time_out) .and. valid_complex_vector_for_test(z_out) .and. &
           valid_complex_matrix_for_test(jac_out) .and. valid_real_vector_for_test(x_out) .and. &
           valid_complex_vector_for_test(estimates) .and. accumulator%sample_count == 3 .and. &
           summary%measurement_attempted == 3 .and. summary%measurement_included == 3 .and. &
           summary%measurement_skipped == 0 .and. summary%measurement_failed == 0 .and. &
           summary%flow_time_observations == 4 .and. ieee_is_finite(summary%flow_time_min) .and. &
           ieee_is_finite(summary%flow_time_max) .and. ieee_is_finite(summary%flow_time_sum) .and. &
           summary%flow_time_min <= min(1.0e-5_dp, flow_time_out) .and. &
           summary%flow_time_max >= max(1.0e-5_dp, flow_time_out)
      call wv_weighted_observable_phase_coherence(accumulator, coherence, error)
      ok = ok .and. (.not. error) .and. ieee_is_finite(coherence) .and. coherence > 0.0_dp
      first_accepted = summary%accepted
      first_rejected = summary%rejected
      first_odex_failure = summary%odex_failure
      first_max_residual = summary%max_constraint_residual
      first_coherence = coherence
      call wv_init_weighted_observable_accumulator(accumulator, observable_count, error)
      ok = ok .and. (.not. error)
      call wv_run_dense_chain(20260529, 3, 5.0e-5_dp, 1, wv_potential_zero(), 0.0_dp, 0.2_dp, 0.0_dp, 0.0_dp, &
                              1.0e-5_dp, x, flow_time_out, x_out, z_out, jac_out, summary, error, status, &
                              observable_accumulator=accumulator, measurement_t0=0.1_dp, measurement_t1=0.2_dp)
      ok = ok .and. (.not. error) .and. summary%cycles_completed == 3 .and. summary%measurement_attempted == 0 .and. &
           summary%measurement_included == 0 .and. summary%measurement_skipped == 3 .and. &
           summary%measurement_failed == 0 .and. accumulator%sample_count == 0 .and. summary%reverse_gate_rejected == 0
      call wv_init_weighted_observable_accumulator(accumulator, observable_count, error)
      ok = ok .and. (.not. error)
      call wv_run_dense_chain(20260529, 3, 5.0e-5_dp, 1, wv_potential_zero(), 0.0_dp, 0.2_dp, 0.0_dp, 0.0_dp, &
                              1.0e-5_dp, x, flow_time_out, x_out, z_out, jac_out, summary, error, status, &
                              observable_accumulator=accumulator, measurement_t0=-1.0e-5_dp, measurement_t1=0.2_dp)
      ok = ok .and. error .and. summary%cycles_attempted == 0 .and. accumulator%sample_count == 0

      call wv_init_weighted_observable_accumulator(accumulator, observable_count, error)
      ok = ok .and. (.not. error)
      call wv_run_dense_chain(20260529, 3, 5.0e-5_dp, 1, wv_potential_zero(), 0.0_dp, 0.2_dp, 0.0_dp, 0.0_dp, &
                              1.0e-5_dp, x, flow_time_out, x_out, z_out, jac_out, summary, error, status, &
                              observable_accumulator=accumulator, constraint_max_iter=0)
      ok = ok .and. (.not. error) .and. summary%cycles_attempted == 3 .and. summary%cycles_completed == 3 .and. &
           summary%transitions_failed == 3 .and. summary%accepted == 0 .and. summary%rejected == 3 .and. &
           summary%measurement_attempted == 3 .and. summary%measurement_included == 3 .and. &
           summary%measurement_failed == 0 .and. accumulator%sample_count == 3

      write (*, '(A,L1,A,I0,A,I0,A,ES12.4,A,ES12.4,A,I0)') "[CHECK] wv_dense_chain_driver ok=", ok, &
         " accepted=", first_accepted, " rejected=", first_rejected, &
         " max_residual=", first_max_residual, " coherence=", first_coherence, &
         " odex_failure=", first_odex_failure
      if (.not. ok) failures = failures + 1
   end subroutine check_dense_chain_driver_smoke

   subroutine check_dense_measurement_factor(failures)
      integer, intent(inout) :: failures
      integer :: n_state, status
      real(dp), allocatable :: x(:), xi_real(:)
      complex(dp), allocatable :: z(:), jac(:, :), grad(:), xi(:)
      complex(dp) :: action_value, expected_phase, expected_factor
      real(dp) :: alpha2, expected_alpha2
      logical :: error, ok
      type(wv_measurement_factor_t) :: factor

      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), z(n_state), jac(n_state, n_state), grad(n_state), xi(n_state), xi_real(2*n_state))
      call fill_base_x(x)
      call flow_at(0.0_dp, x, z, jac, error, status)
      if (error) then
         failures = failures + 1
         write (*, '(A,I0)') "[CHECK] wv_dense_measurement_factor flow_failed status=", status
         return
      end if

      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         failures = failures + 1
         write (*, '(A)') "[CHECK] wv_dense_measurement_factor xi_failed"
         return
      end if
      call complex_to_real(xi, xi_real)
      expected_alpha2 = sum(xi_real(2::2)**2)
      call calculate_action(z, action_value)
      expected_phase = exp(cmplx(0.0_dp, -aimag(action_value), dp))
      expected_factor = expected_phase/sqrt(expected_alpha2)

      call wv_dense_alpha2(z, jac, alpha2, error)
      ok = (.not. error) .and. abs(alpha2 - expected_alpha2) <= 1.0e-10_dp*max(1.0_dp, expected_alpha2)
      call wv_dense_measurement_factor(z, jac, factor, error)
      ok = ok .and. (.not. error) .and. &
           abs(factor%alpha2 - expected_alpha2) <= 1.0e-10_dp*max(1.0_dp, expected_alpha2) .and. &
           abs(factor%alpha - sqrt(expected_alpha2)) <= 1.0e-10_dp*max(1.0_dp, sqrt(expected_alpha2)) .and. &
           abs(factor%phase_factor - expected_phase) <= 1.0e-10_dp .and. &
           abs(factor%wv_factor - expected_factor) <= 1.0e-10_dp*max(1.0_dp, abs(expected_factor))

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] wv_dense_measurement_factor ok=", ok, &
         " alpha2=", factor%alpha2, " phase_abs=", abs(factor%phase_factor), " factor_abs=", abs(factor%wv_factor)
      if (.not. ok) failures = failures + 1
   end subroutine check_dense_measurement_factor

   subroutine check_weighted_observable_accumulator(failures)
      integer, intent(inout) :: failures
      complex(dp) :: weights(2), observables(2, 2), estimates(2), expected(2), denominator
      real(dp) :: coherence, expected_coherence
      logical :: error, ok
      type(wv_weighted_observable_accumulator_t) :: accumulator

      weights = [cmplx(1.0_dp, 0.5_dp, dp), cmplx(2.0_dp, -0.25_dp, dp)]
      observables(:, 1) = [cmplx(0.3_dp, 0.1_dp, dp), cmplx(-0.4_dp, 0.2_dp, dp)]
      observables(:, 2) = [cmplx(0.8_dp, -0.2_dp, dp), cmplx(0.5_dp, 0.7_dp, dp)]
      denominator = weights(1) + weights(2)
      expected = (weights(1)*observables(:, 1) + weights(2)*observables(:, 2))/denominator
      expected_coherence = abs(denominator)/(abs(weights(1)) + abs(weights(2)))

      call wv_init_weighted_observable_accumulator(accumulator, 2, error)
      ok = .not. error
      call wv_accumulate_weighted_observables(accumulator, weights(1), observables(:, 1), error)
      ok = ok .and. (.not. error)
      call wv_accumulate_weighted_observables(accumulator, weights(2), observables(:, 2), error)
      ok = ok .and. (.not. error)
      call wv_weighted_observable_estimates(accumulator, estimates, error)
      ok = ok .and. (.not. error) .and. maxval(abs(estimates - expected)) <= 1.0e-14_dp
      call wv_weighted_observable_phase_coherence(accumulator, coherence, error)
      ok = ok .and. (.not. error) .and. abs(coherence - expected_coherence) <= 1.0e-14_dp .and. &
           accumulator%sample_count == 2

      write (*, '(A,L1,A,ES12.4,A,ES12.4)') "[CHECK] wv_weighted_observable_accumulator ok=", ok, &
         " coherence=", coherence, " estimate0_abs=", abs(estimates(1))
      if (.not. ok) failures = failures + 1
   end subroutine check_weighted_observable_accumulator

   subroutine configure_stephanov_test_model()
      call read_parameters()
      stephanov_n = 2
      stephanov_nf = 1
      stephanov_mass = 0.2_dp
      stephanov_mu = 0.3_dp
      stephanov_tau = 0.0_dp
      stephanov_include_mu_prefactor = .false.
      stephanov_emit_diagnostics = .true.
      call set_derivative_mode("manual")
   end subroutine configure_stephanov_test_model

   subroutine fill_base_x(x)
      real(dp), intent(out) :: x(:)
      integer :: i

      do i = 1, size(x)
         x(i) = 0.02_dp + 0.001_dp*real(i, dp)
      end do
   end subroutine fill_base_x

   subroutine fill_boundary_fixture(x_current, x_trial, z_current, z_trial, jac_current, jac_trial, &
                                    pi_current, pi_trial)
      real(dp), intent(out) :: x_current(:), x_trial(:), pi_current(:), pi_trial(:)
      complex(dp), intent(out) :: z_current(:), z_trial(:), jac_current(:, :), jac_trial(:, :)
      integer :: i, j

      do i = 1, size(x_current)
         x_current(i) = 0.1_dp + 0.01_dp*real(i, dp)
         x_trial(i) = -0.2_dp + 0.02_dp*real(i, dp)
         z_current(i) = cmplx(x_current(i), 0.3_dp*x_current(i), dp)
         z_trial(i) = cmplx(x_trial(i), -0.4_dp*x_trial(i), dp)
      end do
      do i = 1, size(pi_current)
         pi_current(i) = 0.05_dp*real(i, dp)
         pi_trial(i) = -0.07_dp*real(i, dp)
      end do
      jac_current = cmplx(0.0_dp, 0.0_dp, dp)
      jac_trial = cmplx(0.0_dp, 0.0_dp, dp)
      do j = 1, size(jac_current, 2)
         do i = 1, size(jac_current, 1)
            jac_current(i, j) = cmplx(0.01_dp*real(i + j, dp), 0.02_dp*real(i - j, dp), dp)
            jac_trial(i, j) = cmplx(-0.03_dp*real(i + 2*j, dp), 0.04_dp*real(2*i - j, dp), dp)
         end do
      end do
   end subroutine fill_boundary_fixture

   logical function valid_real_vector_for_test(values) result(ok)
      real(dp), intent(in) :: values(:)

      ok = all(ieee_is_finite(values))
   end function valid_real_vector_for_test

   logical function valid_complex_vector_for_test(values) result(ok)
      complex(dp), intent(in) :: values(:)

      ok = all(ieee_is_finite(real(values, dp))) .and. all(ieee_is_finite(aimag(values)))
   end function valid_complex_vector_for_test

   logical function valid_complex_matrix_for_test(values) result(ok)
      complex(dp), intent(in) :: values(:, :)

      ok = all(ieee_is_finite(real(values, dp))) .and. all(ieee_is_finite(aimag(values)))
   end function valid_complex_matrix_for_test

end program test_wv_hmc_constraint_kernels

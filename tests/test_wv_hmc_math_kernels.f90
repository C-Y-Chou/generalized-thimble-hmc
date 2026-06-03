program test_wv_hmc_math_kernels
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use hmc_kernels, only: decompose_tangent_projection
   use model, only: calculate_action, ds, hessian_vec
   use param_mod, only: at, rt, set_derivative_mode, stephanov_emit_diagnostics, stephanov_include_mu_prefactor, &
                        stephanov_mass, stephanov_mu, stephanov_n, stephanov_nf, stephanov_tau
   use solve_flow, only: flow_at
   use utils, only: complex_to_real, dp, log_determinant, real_vec
   use wv_hmc_potential, only: wv_potential_paper_wall, wv_potential_polynomial, wv_potential_profile_t, &
                               wv_potential_value_and_derivative, wv_potential_zero
   use wv_hmc_kernels, only: wv_alpha2, wv_decompose_iterative_with_jacobian, wv_force_dense_with_jacobian, &
                             wv_force_from_sigma_components, wv_force_iterative_with_jacobian, &
                             wv_project_dense_with_jacobian, wv_project_from_sigma_components, &
                             wv_project_iterative_with_jacobian, &
                             wv_real_inner_product, wv_simplified_newton_update_from_sigma_decomposition, &
                             wv_simplified_newton_update_dense_with_jacobian, &
                             wv_simplified_newton_update_iterative_with_jacobian, &
                             wv_simplified_newton_linear_residuals, wv_xi_from_action_gradient, &
                             wv_tangent_flow_rhs_from_hessian_vec, wv_normal_flow_rhs_from_hessian_vec
   use wv_hmc_measurement, only: wv_dense_alpha2, wv_dense_measurement_factor, wv_measurement_factor_t
   implicit none

   integer :: failures

   failures = 0

   call check_inner_product_and_alpha(failures)
   call check_projection_contract(failures)
   call check_dense_projection_wrapper(failures)
   call check_iterative_projection_oracle(failures)
   call check_iterative_force_and_newton_oracles(failures)
   call check_potential_provider(failures)
   call check_force_contract(failures)
   call check_random_complex_force_flow_conventions(failures)
   call check_nonzero_flow_projection_geometry(failures)
   call check_worldvolume_force_finite_difference(failures)
   call check_worldvolume_measure_factor_identity(failures)
   call check_simplified_newton_contract(failures)
   call check_dense_simplified_newton_oracle(failures)
   call check_fail_closed_guards(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] WV-HMC math kernel failures=", failures
      error stop 1
   end if
   write (*, '(A)') "[PASS] WV-HMC math kernels"

contains

   subroutine check_inner_product_and_alpha(failures)
      integer, intent(inout) :: failures
      real(dp) :: xi_n(4), value, alpha2
      logical :: error, ok

      xi_n = [0.0_dp, 1.0_dp, 0.0_dp, 2.0_dp]
      call wv_real_inner_product(xi_n, xi_n, value, error)
      call wv_alpha2(xi_n, alpha2, error)

      ok = (.not. error) .and. near(value, 5.0_dp) .and. near(alpha2, 5.0_dp)
      write (*, '(A,L1)') "[CHECK] wv_inner_product_alpha ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_inner_product_and_alpha

   subroutine check_projection_contract(failures)
      integer, intent(inout) :: failures
      real(dp) :: w_v(4), w_n(4), xi_v(4), xi_n(4), w_parallel(4), w_perp(4)
      real(dp) :: c, alpha2, orthogonality
      logical :: error, ok

      w_v = [1.0_dp, 0.0_dp, -3.0_dp, 0.0_dp]
      w_n = [0.0_dp, 2.0_dp, 0.0_dp, 5.0_dp]
      xi_v = [0.25_dp, 0.0_dp, -0.5_dp, 0.0_dp]
      xi_n = [0.0_dp, 1.0_dp, 0.0_dp, 2.0_dp]

      call wv_project_from_sigma_components(w_v, w_n, xi_v, xi_n, w_parallel, w_perp, c, alpha2, error)
      orthogonality = dot_product(w_parallel, w_perp)
      ok = (.not. error) .and. near(alpha2, 5.0_dp) .and. near(c, 2.4_dp) .and. &
           all_near(w_parallel, [1.0_dp, 2.4_dp, -3.0_dp, 4.8_dp]) .and. &
           all_near(w_perp, [0.0_dp, -0.4_dp, 0.0_dp, 0.2_dp]) .and. &
           all_near(w_parallel + w_perp, w_v + w_n) .and. near(orthogonality, 0.0_dp)

      write (*, '(A,L1)') "[CHECK] wv_projection_contract ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_projection_contract

   subroutine check_dense_projection_wrapper(failures)
      integer, intent(inout) :: failures
      real(dp) :: w(4), xi(4), w_parallel(4), w_perp(4)
      real(dp) :: w_coords(4), w_v(4), w_n(4)
      real(dp) :: xi_coords(4), xi_v(4), xi_n(4)
      real(dp) :: expected_parallel(4), expected_perp(4)
      real(dp) :: c, alpha2, expected_c, expected_alpha2
      complex(dp) :: jac(2, 2)
      logical :: error, ierr, expected_error, ok

      w = [1.0_dp, 2.0_dp, -3.0_dp, 5.0_dp]
      xi = [0.25_dp, 1.0_dp, -0.5_dp, 2.0_dp]
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      jac(1, 1) = cmplx(1.0_dp, 0.2_dp, dp)
      jac(1, 2) = cmplx(0.1_dp, -0.3_dp, dp)
      jac(2, 1) = cmplx(-0.4_dp, 0.05_dp, dp)
      jac(2, 2) = cmplx(1.3_dp, -0.1_dp, dp)

      call decompose_tangent_projection(w, w_coords, w_v, w_n, jac, ierr)
      ok = .not. ierr
      call decompose_tangent_projection(xi, xi_coords, xi_v, xi_n, jac, ierr)
      ok = ok .and. (.not. ierr)
      call wv_project_from_sigma_components(w_v, w_n, xi_v, xi_n, expected_parallel, expected_perp, expected_c, &
                                            expected_alpha2, expected_error)
      ok = ok .and. (.not. expected_error)

      call wv_project_dense_with_jacobian(w, xi, jac, w_parallel, w_perp, c, alpha2, error)
      ok = ok .and. (.not. error) .and. near(c, expected_c) .and. near(alpha2, expected_alpha2) .and. &
           all_near(w_parallel, expected_parallel) .and. all_near(w_perp, expected_perp) .and. &
           all_near(w_parallel + w_perp, w)

      write (*, '(A,L1)') "[CHECK] wv_dense_projection_wrapper ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_dense_projection_wrapper

   subroutine check_iterative_projection_oracle(failures)
      integer, intent(inout) :: failures
      real(dp) :: w(4), xi(4)
      real(dp) :: dense_coords(4), dense_tangent(4), dense_normal(4)
      real(dp) :: iter_coords(4), iter_tangent(4), iter_normal(4)
      real(dp) :: dense_parallel(4), dense_perp(4), iter_parallel(4), iter_perp(4)
      real(dp) :: dense_c, dense_alpha2, iter_c, iter_alpha2, residual_norm
      integer :: iterations
      complex(dp) :: jac(2, 2)
      logical :: error, ierr, ok

      w = [1.0_dp, 2.0_dp, -3.0_dp, 5.0_dp]
      xi = [0.25_dp, 1.0_dp, -0.5_dp, 2.0_dp]
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      jac(1, 1) = cmplx(1.0_dp, 0.2_dp, dp)
      jac(1, 2) = cmplx(0.1_dp, -0.3_dp, dp)
      jac(2, 1) = cmplx(-0.4_dp, 0.05_dp, dp)
      jac(2, 2) = cmplx(1.3_dp, -0.1_dp, dp)

      call decompose_tangent_projection(w, dense_coords, dense_tangent, dense_normal, jac, ierr)
      ok = .not. ierr
      call wv_decompose_iterative_with_jacobian(w, jac, iter_coords, iter_tangent, iter_normal, residual_norm, &
                                                iterations, 1.0e-12_dp, 64, error)
      ok = ok .and. (.not. error) .and. iterations > 0 .and. residual_norm <= 1.0e-11_dp .and. &
           all_close(iter_coords, dense_coords, 1.0e-10_dp) .and. all_close(iter_tangent, dense_tangent, 1.0e-10_dp) .and. &
           all_close(iter_normal, dense_normal, 1.0e-10_dp)

      call wv_project_dense_with_jacobian(w, xi, jac, dense_parallel, dense_perp, dense_c, dense_alpha2, error)
      ok = ok .and. (.not. error)
      call wv_project_iterative_with_jacobian(w, xi, jac, iter_parallel, iter_perp, iter_c, iter_alpha2, residual_norm, &
                                             iterations, 1.0e-12_dp, 64, error)
      ok = ok .and. (.not. error) .and. iterations > 0 .and. residual_norm <= 1.0e-11_dp .and. &
           abs(iter_c - dense_c) <= 1.0e-10_dp .and. abs(iter_alpha2 - dense_alpha2) <= 1.0e-10_dp .and. &
           all_close(iter_parallel, dense_parallel, 1.0e-10_dp) .and. all_close(iter_perp, dense_perp, 1.0e-10_dp)

      write (*, '(A,L1,A,I0,A,ES12.4)') "[CHECK] wv_iterative_projection_oracle ok=", ok, &
         " iterations=", iterations, " residual=", residual_norm
      if (.not. ok) failures = failures + 1
   end subroutine check_iterative_projection_oracle

   subroutine check_iterative_force_and_newton_oracles(failures)
      integer, intent(inout) :: failures
      real(dp) :: b(4), xi(4), force_dense(4), force_iter(4), delta_u_dense(4), delta_lambda_dense(4)
      real(dp) :: delta_u_iter(4), delta_lambda_iter(4)
      real(dp) :: alpha2_dense, alpha2_iter, delta_h_dense, delta_h_iter, c_dense, c_iter, residual_norm
      integer :: iterations
      complex(dp) :: jac(2, 2)
      logical :: error, ok

      b = [0.75_dp, 1.25_dp, -0.35_dp, 0.80_dp]
      xi = [0.45_dp, -0.20_dp, 0.30_dp, 0.65_dp]
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      jac(1, 1) = cmplx(1.0_dp, 0.2_dp, dp)
      jac(1, 2) = cmplx(0.1_dp, -0.3_dp, dp)
      jac(2, 1) = cmplx(-0.4_dp, 0.05_dp, dp)
      jac(2, 2) = cmplx(1.3_dp, -0.1_dp, dp)

      call wv_force_dense_with_jacobian(xi, jac, 1.25_dp, force_dense, alpha2_dense, error)
      ok = .not. error
      call wv_force_iterative_with_jacobian(xi, jac, 1.25_dp, force_iter, alpha2_iter, residual_norm, iterations, &
                                            1.0e-12_dp, 64, error)
      ok = ok .and. (.not. error) .and. iterations > 0 .and. residual_norm <= 1.0e-11_dp .and. &
           abs(alpha2_iter - alpha2_dense) <= 1.0e-10_dp .and. all_close(force_iter, force_dense, 1.0e-10_dp)

      call wv_simplified_newton_update_dense_with_jacobian(b, xi, jac, delta_h_dense, delta_u_dense, &
                                                           delta_lambda_dense, c_dense, alpha2_dense, error)
      ok = ok .and. (.not. error)
      call wv_simplified_newton_update_iterative_with_jacobian(b, xi, jac, delta_h_iter, delta_u_iter, &
                                                               delta_lambda_iter, c_iter, alpha2_iter, residual_norm, &
                                                               iterations, 1.0e-12_dp, 64, error)
      ok = ok .and. (.not. error) .and. iterations > 0 .and. residual_norm <= 1.0e-11_dp .and. &
           abs(delta_h_iter - delta_h_dense) <= 1.0e-10_dp .and. abs(c_iter - c_dense) <= 1.0e-10_dp .and. &
           abs(alpha2_iter - alpha2_dense) <= 1.0e-10_dp .and. all_close(delta_u_iter, delta_u_dense, 1.0e-10_dp) .and. &
           all_close(delta_lambda_iter, delta_lambda_dense, 1.0e-10_dp)

      write (*, '(A,L1,A,I0,A,ES12.4)') "[CHECK] wv_iterative_force_newton_oracles ok=", ok, &
         " iterations=", iterations, " residual=", residual_norm
      if (.not. ok) failures = failures + 1
   end subroutine check_iterative_force_and_newton_oracles

   subroutine check_potential_provider(failures)
      integer, intent(inout) :: failures
      type(wv_potential_profile_t) :: profile
      real(dp) :: t, h, value, derivative, value_p, value_m, derivative_fd, max_derivative_diff
      real(dp) :: t0, t1, d0, d1, gamma, c0, c1
      logical :: error, ok

      profile = wv_potential_zero()
      call wv_potential_value_and_derivative(profile, 0.25_dp, value, derivative, error)
      ok = (.not. error) .and. near(value, 0.0_dp) .and. near(derivative, 0.0_dp)
      max_derivative_diff = 0.0_dp

      profile = wv_potential_polynomial(0.75_dp, -0.4_dp, 1.6_dp)
      t = 0.31_dp
      h = 1.0e-5_dp
      call wv_potential_value_and_derivative(profile, t, value, derivative, error)
      ok = ok .and. (.not. error)
      call wv_potential_value_and_derivative(profile, t + h, value_p, derivative_fd, error)
      ok = ok .and. (.not. error)
      call wv_potential_value_and_derivative(profile, t - h, value_m, derivative_fd, error)
      ok = ok .and. (.not. error)
      derivative_fd = (value_p - value_m)/(2.0_dp*h)
      ok = ok .and. abs(derivative - derivative_fd) <= 1.0e-10_dp
      max_derivative_diff = max(max_derivative_diff, abs(derivative - derivative_fd))

      t0 = 0.02_dp
      t1 = 0.10_dp
      d0 = 0.01_dp
      d1 = 0.015_dp
      gamma = 20.0_dp
      c0 = 1.0_dp
      c1 = 1.5_dp
      profile = wv_potential_paper_wall(t0, t1, d0, d1, gamma, c0, c1)
      call check_paper_wall_point(profile, 0.015_dp, ok, max_derivative_diff)
      call check_paper_wall_point(profile, 0.050_dp, ok, max_derivative_diff)
      call check_paper_wall_point(profile, 0.115_dp, ok, max_derivative_diff)
      call wv_potential_value_and_derivative(profile, t0, value, derivative, error)
      ok = ok .and. (.not. error) .and. abs(value) <= 1.0e-14_dp .and. abs(derivative + gamma) <= 1.0e-12_dp
      call wv_potential_value_and_derivative(profile, t1, value, derivative, error)
      ok = ok .and. (.not. error) .and. abs(value + gamma*(t1 - t0)) <= 1.0e-12_dp .and. &
           abs(derivative + gamma) <= 1.0e-12_dp
      profile = wv_potential_paper_wall(t0, t1, 0.0_dp, d1, gamma, c0, c1)
      call wv_potential_value_and_derivative(profile, 0.015_dp, value, derivative, error)
      ok = ok .and. error

      write (*, '(A,L1,A,ES12.4,A,ES12.4)') "[CHECK] wv_potential_provider ok=", ok, &
         " value=", value, " derivative_diff=", max_derivative_diff
      if (.not. ok) failures = failures + 1
   end subroutine check_potential_provider

   subroutine check_paper_wall_point(profile, t, ok, max_derivative_diff)
      type(wv_potential_profile_t), intent(in) :: profile
      real(dp), intent(in) :: t
      logical, intent(inout) :: ok
      real(dp), intent(inout) :: max_derivative_diff
      real(dp) :: h, value, derivative, value_p, value_m, derivative_fd
      logical :: error

      h = 1.0e-6_dp
      call wv_potential_value_and_derivative(profile, t, value, derivative, error)
      ok = ok .and. (.not. error)
      call wv_potential_value_and_derivative(profile, t + h, value_p, derivative_fd, error)
      ok = ok .and. (.not. error)
      call wv_potential_value_and_derivative(profile, t - h, value_m, derivative_fd, error)
      ok = ok .and. (.not. error)
      derivative_fd = (value_p - value_m)/(2.0_dp*h)
      max_derivative_diff = max(max_derivative_diff, abs(derivative - derivative_fd))
      ok = ok .and. abs(derivative - derivative_fd) <= 1.0e-7_dp*max(1.0_dp, abs(derivative_fd))
   end subroutine check_paper_wall_point

   subroutine check_force_contract(failures)
      integer, intent(inout) :: failures
      real(dp) :: xi(4), xi_n(4), force(4), alpha2
      logical :: error, ok

      xi = [0.25_dp, 1.0_dp, -0.5_dp, 2.0_dp]
      xi_n = [0.0_dp, 1.0_dp, 0.0_dp, 2.0_dp]

      call wv_force_from_sigma_components(xi, xi_n, 3.0_dp, force, alpha2, error)
      ok = (.not. error) .and. near(alpha2, 5.0_dp) .and. &
           all_near(force, [0.125_dp, 0.8_dp, -0.25_dp, 1.6_dp])

      write (*, '(A,L1)') "[CHECK] wv_force_contract ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_force_contract

   subroutine check_random_complex_force_flow_conventions(failures)
      integer, intent(inout) :: failures
      integer, parameter :: n_model = 2
      integer :: n_state, seed_size, i, j
      integer, allocatable :: rng_seed(:)
      real(dp), allocatable :: random_real(:), random_imag(:)
      complex(dp), allocatable :: z(:), z_work(:), v(:), grad(:), grad_p2(:), grad_p1(:), grad_m1(:), grad_m2(:)
      complex(dp), allocatable :: xi(:), xi_p2(:), xi_p1(:), xi_m1(:), xi_m2(:), xi_fd(:), hv(:), tangent_rhs(:), normal_rhs(:)
      complex(dp), allocatable :: jac(:, :)
      real(dp), allocatable :: xi_real(:), v_real(:), xi_coords(:), xi_tangent(:), xi_normal(:), force(:), expected_force(:)
      complex(dp) :: action_p2, action_p1, action_m1, action_m2
      real(dp) :: h, directional_fd, directional_inner, tangent_norm, alpha2, c
      real(dp) :: projection_recon_norm, force_zero_norm, force_wprime_norm, force_directional_diff
      logical :: error, ok

      call configure_stephanov_test_model(n_model)
      call random_seed(size=seed_size)
      allocate (rng_seed(seed_size))
      rng_seed = [(864203 + 37*i, i=1, seed_size)]
      call random_seed(put=rng_seed)

      n_state = 2*stephanov_n*stephanov_n
      allocate (z(n_state), z_work(n_state), v(n_state), grad(n_state), grad_p2(n_state), grad_p1(n_state), &
                grad_m1(n_state), grad_m2(n_state), xi(n_state), xi_p2(n_state), xi_p1(n_state), xi_m1(n_state), &
                xi_m2(n_state), xi_fd(n_state), hv(n_state), tangent_rhs(n_state), normal_rhs(n_state), &
                jac(n_state, n_state))
      allocate (xi_real(2*n_state), v_real(2*n_state), xi_coords(2*n_state), xi_tangent(2*n_state), xi_normal(2*n_state), force(2*n_state), &
                expected_force(2*n_state), random_real(n_state*n_state), random_imag(n_state*n_state))

      call random_number(random_real(1:n_state))
      call random_number(random_imag(1:n_state))
      do i = 1, n_state
         z(i) = cmplx(0.18_dp*(2.0_dp*random_real(i) - 1.0_dp), &
                      0.14_dp*(2.0_dp*random_imag(i) - 1.0_dp), dp)
      end do
      call random_number(random_real(1:n_state))
      call random_number(random_imag(1:n_state))
      do i = 1, n_state
         v(i) = cmplx(0.20_dp*(2.0_dp*random_real(i) - 1.0_dp), &
                      0.16_dp*(2.0_dp*random_imag(i) - 1.0_dp), dp)
      end do

      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      ok = .not. error
      call complex_to_real(xi, xi_real)
      call complex_to_real(v, v_real)

      h = 2.0e-5_dp
      z_work = z + 2.0_dp*h*v
      call calculate_action(z_work, action_p2)
      call ds(z_work, grad_p2)
      call wv_xi_from_action_gradient(grad_p2, xi_p2, error)
      ok = ok .and. (.not. error)
      z_work = z + h*v
      call calculate_action(z_work, action_p1)
      call ds(z_work, grad_p1)
      call wv_xi_from_action_gradient(grad_p1, xi_p1, error)
      ok = ok .and. (.not. error)
      z_work = z - h*v
      call calculate_action(z_work, action_m1)
      call ds(z_work, grad_m1)
      call wv_xi_from_action_gradient(grad_m1, xi_m1, error)
      ok = ok .and. (.not. error)
      z_work = z - 2.0_dp*h*v
      call calculate_action(z_work, action_m2)
      call ds(z_work, grad_m2)
      call wv_xi_from_action_gradient(grad_m2, xi_m2, error)
      ok = ok .and. (.not. error)

      directional_fd = (-real(action_p2, dp) + 8.0_dp*real(action_p1, dp) - 8.0_dp*real(action_m1, dp) + &
                        real(action_m2, dp))/(12.0_dp*h)
      directional_inner = dot_product(xi_real, v_real)
      ok = ok .and. abs(directional_fd - directional_inner) <= 2.0e-7_dp

      call hessian_vec(z, v, hv)
      call wv_tangent_flow_rhs_from_hessian_vec(hv, tangent_rhs, error)
      ok = ok .and. (.not. error)
      call wv_normal_flow_rhs_from_hessian_vec(hv, normal_rhs, error)
      ok = ok .and. (.not. error) .and. maxval(abs(normal_rhs + tangent_rhs)) <= 1.0e-14_dp

      xi_fd = (-xi_p2 + 8.0_dp*xi_p1 - 8.0_dp*xi_m1 + xi_m2)/(12.0_dp*h)
      tangent_norm = sqrt(sum(abs(xi_fd - tangent_rhs)**2))
      ok = ok .and. tangent_norm <= 3.0e-6_dp

      call fill_diagonally_dominant_jacobian(jac, random_real, random_imag)
      call decompose_tangent_projection(xi_real, xi_coords, xi_tangent, xi_normal, jac, error)
      projection_recon_norm = sqrt(sum((xi_tangent + xi_normal - xi_real)**2))
      ok = ok .and. (.not. error) .and. projection_recon_norm <= 1.0e-10_dp
      call wv_alpha2(xi_normal, alpha2, error)
      ok = ok .and. (.not. error) .and. alpha2 > 0.0_dp

      call wv_force_dense_with_jacobian(xi_real, jac, 0.0_dp, force, alpha2, error)
      force_zero_norm = sqrt(sum((force - 0.5_dp*xi_real)**2))
      force_directional_diff = abs(dot_product(force, v_real) - 0.5_dp*directional_fd)
      ok = ok .and. (.not. error) .and. force_zero_norm <= 1.0e-12_dp .and. &
           force_directional_diff <= 1.0e-7_dp

      call wv_force_dense_with_jacobian(xi_real, jac, 1.75_dp, force, alpha2, error)
      expected_force = 0.5_dp*(xi_real + (1.75_dp/alpha2)*xi_normal)
      force_wprime_norm = sqrt(sum((force - expected_force)**2))
      ok = ok .and. (.not. error) .and. force_wprime_norm <= 1.0e-12_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] wv_random_complex_force_flow ok=", ok, &
         " directional_diff=", abs(directional_fd - directional_inner), " tangent_rhs_diff=", tangent_norm, &
         " projection_recon=", projection_recon_norm, " force0=", force_zero_norm, " forcew=", force_wprime_norm
      if (.not. ok) failures = failures + 1
   end subroutine check_random_complex_force_flow_conventions

   subroutine check_nonzero_flow_projection_geometry(failures)
      integer, intent(inout) :: failures
      integer, parameter :: n_model = 2
      integer :: n_state, status, i, case_idx
      real(dp), allocatable :: x(:), w(:), xi_real(:), w_parallel(:), w_perp(:), dx(:), tangent_real(:)
      complex(dp), allocatable :: z(:), jac(:, :), grad(:), xi(:), tangent_complex(:)
      real(dp) :: flow_time, c, alpha2, reconstruction_norm, orthogonality_max, tangent_norm, scale
      real(dp) :: direction_t
      logical :: error, ok

      call configure_stephanov_test_model(n_model)
      stephanov_tau = 0.1_dp
      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), w(2*n_state), xi_real(2*n_state), w_parallel(2*n_state), w_perp(2*n_state), &
                dx(n_state), tangent_real(2*n_state), z(n_state), jac(n_state, n_state), grad(n_state), &
                xi(n_state), tangent_complex(n_state))

      call prepare_nonzero_flow_fixture(n_state, flow_time, x, z, jac, ok, status)
      do i = 1, n_state
         w(2*i - 1) = 0.17_dp*cos(0.23_dp*real(i, dp)) - 0.04_dp*sin(0.41_dp*real(i, dp))
         w(2*i) = -0.11_dp*sin(0.29_dp*real(i, dp)) + 0.03_dp*cos(0.53_dp*real(i, dp))
      end do
      c = 0.0_dp
      alpha2 = 0.0_dp
      if (ok) then
         call ds(z, grad)
         call wv_xi_from_action_gradient(grad, xi, error)
         ok = ok .and. (.not. error)
      end if
      if (ok) call complex_to_real(xi, xi_real)
      if (ok) then
         call wv_project_dense_with_jacobian(w, xi_real, jac, w_parallel, w_perp, c, alpha2, error)
         ok = ok .and. (.not. error) .and. alpha2 > 0.0_dp
      end if

      reconstruction_norm = huge(1.0_dp)
      orthogonality_max = huge(1.0_dp)
      if (ok) then
         reconstruction_norm = norm2(w_parallel + w_perp - w)
         orthogonality_max = 0.0_dp
         do case_idx = 1, 5
            do i = 1, n_state
               dx(i) = 0.09_dp*cos((0.17_dp + 0.03_dp*real(case_idx, dp))*real(i, dp)) + &
                       0.04_dp*sin((0.11_dp + 0.02_dp*real(case_idx, dp))*real(i*i, dp))
            end do
            direction_t = -0.35_dp + 0.17_dp*real(case_idx, dp)
            tangent_complex = matmul(jac, cmplx(dx, 0.0_dp, dp)) + direction_t*xi
            call complex_to_real(tangent_complex, tangent_real)
            tangent_norm = norm2(tangent_real)
            scale = max(1.0_dp, norm2(w_perp)*tangent_norm)
            orthogonality_max = max(orthogonality_max, abs(dot_product(w_perp, tangent_real))/scale)
         end do
         ok = ok .and. reconstruction_norm <= 1.0e-10_dp .and. orthogonality_max <= 1.0e-9_dp
      end if

      write (*, '(A,L1,A,I0,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] wv_nonzero_flow_projection_geometry ok=", ok, " status=", status, &
         " reconstruction=", reconstruction_norm, " orthogonality=", orthogonality_max, " alpha2=", alpha2
      if (.not. ok) failures = failures + 1
   end subroutine check_nonzero_flow_projection_geometry

   subroutine check_worldvolume_force_finite_difference(failures)
      integer, intent(inout) :: failures
      integer, parameter :: n_model = 2
      integer :: n_state, status, i
      real(dp), allocatable :: x(:), dx(:), xi_real(:), tangent_real(:), force(:)
      complex(dp), allocatable :: z(:), jac(:, :), grad(:), xi(:), tangent_complex(:)
      type(wv_potential_profile_t) :: profile
      real(dp) :: flow_time, direction_t, eps_fd, w_value, wprime, alpha2
      real(dp) :: value_p2, value_p1, value_m1, value_m2, directional_fd, force_directional
      logical :: error, ok, fd_ready
      logical :: err_p2, err_p1, err_m1, err_m2
      integer :: status_p2, status_p1, status_m1, status_m2

      call configure_stephanov_test_model(n_model)
      stephanov_tau = 0.1_dp
      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), dx(n_state), xi_real(2*n_state), tangent_real(2*n_state), force(2*n_state), &
                z(n_state), jac(n_state, n_state), grad(n_state), xi(n_state), tangent_complex(n_state))

      call prepare_nonzero_flow_fixture(n_state, flow_time, x, z, jac, ok, status)
      do i = 1, n_state
         dx(i) = 0.00035_dp*cos(0.37_dp*real(i, dp)) - 0.00020_dp*sin(0.19_dp*real(i, dp))
      end do
      direction_t = 0.02_dp
      profile = wv_potential_paper_wall(flow_time - 2.0e-4_dp, flow_time + 2.0e-4_dp, &
                                        1.0e-4_dp, 2.5e-4_dp, 0.2_dp, 1.0_dp, 1.0_dp)

      alpha2 = 0.0_dp
      directional_fd = 0.0_dp
      force_directional = 0.0_dp
      if (ok) then
         call ds(z, grad)
         call wv_xi_from_action_gradient(grad, xi, error)
         ok = ok .and. (.not. error)
      end if
      if (ok) call complex_to_real(xi, xi_real)
      if (ok) then
         call wv_potential_value_and_derivative(profile, flow_time, w_value, wprime, error)
         ok = ok .and. (.not. error)
      end if
      if (ok) then
         call wv_force_dense_with_jacobian(xi_real, jac, wprime, force, alpha2, error)
         ok = ok .and. (.not. error)
      end if
      fd_ready = .false.
      status_p2 = -999
      status_p1 = -999
      status_m1 = -999
      status_m2 = -999
      if (ok) then
         tangent_complex = matmul(jac, cmplx(dx, 0.0_dp, dp)) + direction_t*xi
         call complex_to_real(tangent_complex, tangent_real)
         eps_fd = 1.0e-4_dp
         call evaluate_worldvolume_tangent_potential(flow_time, z, tangent_complex, direction_t, 2.0_dp*eps_fd, &
                                                     profile, value_p2, err_p2, status_p2)
         call evaluate_worldvolume_tangent_potential(flow_time, z, tangent_complex, direction_t, eps_fd, &
                                                     profile, value_p1, err_p1, status_p1)
         call evaluate_worldvolume_tangent_potential(flow_time, z, tangent_complex, direction_t, -eps_fd, &
                                                     profile, value_m1, err_m1, status_m1)
         call evaluate_worldvolume_tangent_potential(flow_time, z, tangent_complex, direction_t, -2.0_dp*eps_fd, &
                                                     profile, value_m2, err_m2, status_m2)
         fd_ready = (.not. err_p2) .and. (.not. err_p1) .and. (.not. err_m1) .and. (.not. err_m2) .and. &
                    ieee_is_finite(value_p2) .and. ieee_is_finite(value_p1) .and. &
                    ieee_is_finite(value_m1) .and. ieee_is_finite(value_m2)
         ok = ok .and. fd_ready
      end if

      if (ok .and. fd_ready) then
         force_directional = 2.0_dp*dot_product(force, tangent_real)
         directional_fd = (-value_p2 + 8.0_dp*value_p1 - 8.0_dp*value_m1 + value_m2)/(12.0_dp*eps_fd)
         ok = ok .and. ieee_is_finite(directional_fd) .and. ieee_is_finite(force_directional)
         ok = ok .and. abs(directional_fd - force_directional) <= 5.0e-7_dp*max(1.0_dp, abs(directional_fd))
      end if

      write (*, '(A,L1,A,ES12.4,A,L1,A,4(I0,1X),A,ES12.4,A,ES12.4)') &
         "[CHECK] wv_worldvolume_force_fd ok=", ok, " fd=", directional_fd, &
         " fd_ready=", fd_ready, " status=", status_p2, status_p1, status_m1, status_m2, &
         " force_dir=", force_directional, " diff=", abs(directional_fd - force_directional)
      if (.not. ok) failures = failures + 1
   end subroutine check_worldvolume_force_finite_difference

   subroutine check_worldvolume_measure_factor_identity(failures)
      integer, intent(inout) :: failures
      logical :: ok
      real(dp) :: max_alpha_rel_error, max_logabs_identity_error, max_logdet_volume_error

      ok = .true.
      max_alpha_rel_error = 0.0_dp
      max_logabs_identity_error = 0.0_dp
      max_logdet_volume_error = 0.0_dp
      call check_worldvolume_measure_factor_identity_case(2, 1.0e-3_dp, 0.125_dp, ok, max_alpha_rel_error, &
                                                          max_logabs_identity_error, max_logdet_volume_error)
      call check_worldvolume_measure_factor_identity_case(6, 3.0e-3_dp, 0.125_dp, ok, max_alpha_rel_error, &
                                                          max_logabs_identity_error, max_logdet_volume_error)

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] wv_worldvolume_measure_factor_identity ok=", ok, &
         " alpha_rel=", max_alpha_rel_error, " logabs_identity=", max_logabs_identity_error, &
         " logdet_volume=", max_logdet_volume_error
      if (.not. ok) failures = failures + 1
   end subroutine check_worldvolume_measure_factor_identity

   subroutine check_worldvolume_measure_factor_identity_case(n_model, flow_time, w_value, ok, max_alpha_rel_error, &
                                                            max_logabs_identity_error, max_logdet_volume_error)
      integer, intent(in) :: n_model
      real(dp), intent(in) :: flow_time, w_value
      logical, intent(inout) :: ok
      real(dp), intent(inout) :: max_alpha_rel_error, max_logabs_identity_error, max_logdet_volume_error

      integer :: n_state, status, i
      real(dp), allocatable :: x(:), xi_real(:), e_real(:, :), gamma(:, :), gram(:, :)
      complex(dp), allocatable :: z(:), jac(:, :), grad(:), xi(:)
      complex(dp) :: action_value, log_det_j
      real(dp) :: alpha2_code, alpha_code, alpha_gram, logdet_gamma, logdet_gram
      real(dp) :: log_abs_det_j, log_volume_sigma, log_abs_direct, log_abs_from_wv_measure
      logical :: error, det_error, local_ok
      type(wv_measurement_factor_t) :: factor

      call configure_stephanov_test_model(n_model)
      stephanov_tau = 0.1_dp
      n_state = 2*stephanov_n*stephanov_n
      allocate (x(n_state), xi_real(2*n_state), e_real(2*n_state, n_state), gamma(n_state, n_state), &
                gram(n_state + 1, n_state + 1), z(n_state), jac(n_state, n_state), grad(n_state), xi(n_state))

      do i = 1, n_state
         x(i) = 0.012_dp*cos(0.17_dp*real(i, dp)) + 0.006_dp*sin(0.11_dp*real(i*i, dp))
      end do
      call flow_at(flow_time, x, z, jac, error, status)
      if (error) then
         write (*, '(A,I0,A,I0)') "[CHECK] wv_worldvolume_measure_factor_identity flow_failed n=", n_model, &
            " status=", status
         ok = .false.
         return
      end if

      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         write (*, '(A,I0)') "[CHECK] wv_worldvolume_measure_factor_identity xi_failed n=", n_model
         ok = .false.
         return
      end if
      call complex_to_real(xi, xi_real)
      call wv_dense_alpha2(z, jac, alpha2_code, error)
      if (error) then
         write (*, '(A,I0)') "[CHECK] wv_worldvolume_measure_factor_identity alpha_failed n=", n_model
         ok = .false.
         return
      end if
      alpha_code = sqrt(alpha2_code)

      call tangent_real_matrix_from_jacobian(jac, e_real)
      gamma = matmul(transpose(e_real), e_real)
      gram = 0.0_dp
      gram(1, 1) = dot_product(xi_real, xi_real)
      do i = 1, n_state
         gram(1, i + 1) = dot_product(xi_real, e_real(:, i))
         gram(i + 1, 1) = gram(1, i + 1)
      end do
      gram(2:n_state + 1, 2:n_state + 1) = gamma
      call log_abs_det_real_square(gamma, logdet_gamma, det_error)
      if (det_error) then
         write (*, '(A,I0)') "[CHECK] wv_worldvolume_measure_factor_identity gamma_det_failed n=", n_model
         ok = .false.
         return
      end if
      call log_abs_det_real_square(gram, logdet_gram, det_error)
      if (det_error) then
         write (*, '(A,I0)') "[CHECK] wv_worldvolume_measure_factor_identity gram_det_failed n=", n_model
         ok = .false.
         return
      end if
      alpha_gram = exp(0.5_dp*(logdet_gram - logdet_gamma))

      call log_determinant(jac, log_det_j, det_error)
      if (det_error) then
         write (*, '(A,I0)') "[CHECK] wv_worldvolume_measure_factor_identity complex_det_failed n=", n_model
         ok = .false.
         return
      end if
      log_abs_det_j = real(log_det_j, dp)
      log_volume_sigma = 0.5_dp*logdet_gamma

      call calculate_action(z, action_value)
      call wv_dense_measurement_factor(z, jac, factor, error, w_value=w_value)
      if (error) then
         write (*, '(A,I0)') "[CHECK] wv_worldvolume_measure_factor_identity factor_failed n=", n_model
         ok = .false.
         return
      end if

      log_abs_direct = -real(action_value, dp) - w_value + log_abs_det_j
      log_abs_from_wv_measure = -real(action_value, dp) - w_value + log(alpha_gram) + log_abs_det_j + &
                                 log(abs(factor%wv_factor))
      local_ok = abs(alpha_gram - alpha_code) <= 1.0e-7_dp*max(1.0_dp, alpha_gram, alpha_code) .and. &
                 abs(log_abs_from_wv_measure - log_abs_direct) <= 1.0e-7_dp .and. &
                 abs(log_volume_sigma - log_abs_det_j) <= 1.0e-7_dp*max(1.0_dp, abs(log_abs_det_j))
      max_alpha_rel_error = max(max_alpha_rel_error, abs(alpha_gram - alpha_code)/max(1.0_dp, alpha_gram, alpha_code))
      max_logabs_identity_error = max(max_logabs_identity_error, abs(log_abs_from_wv_measure - log_abs_direct))
      max_logdet_volume_error = max(max_logdet_volume_error, abs(log_volume_sigma - log_abs_det_j))
      if (.not. local_ok) then
         write (*, '(A,I0,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4)') &
            "[CHECK] wv_worldvolume_measure_factor_identity case_failed n=", n_model, &
            " alpha_code=", alpha_code, " alpha_gram=", alpha_gram, &
            " log_identity=", log_abs_from_wv_measure - log_abs_direct, &
            " logdet_vol=", log_volume_sigma, " logdet_complex=", log_abs_det_j, &
            " factor_abs=", abs(factor%wv_factor)
      end if
      write (*, '(A,L1,A,I0,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] wv_worldvolume_measure_factor_identity_case ok=", local_ok, " n=", n_model, &
         " flow_time=", flow_time, &
         " alpha_rel=", abs(alpha_gram - alpha_code)/max(1.0_dp, alpha_gram, alpha_code), &
         " logabs_identity=", abs(log_abs_from_wv_measure - log_abs_direct), &
         " logdet_volume=", abs(log_volume_sigma - log_abs_det_j)
      ok = ok .and. local_ok
   end subroutine check_worldvolume_measure_factor_identity_case

   subroutine tangent_real_matrix_from_jacobian(jac, e_real)
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: e_real(:, :)
      integer :: i, j, n

      n = size(jac, 1)
      e_real = 0.0_dp
      do j = 1, n
         do i = 1, n
            e_real(2*i - 1, j) = real(jac(i, j), dp)
            e_real(2*i, j) = aimag(jac(i, j))
         end do
      end do
   end subroutine tangent_real_matrix_from_jacobian

   subroutine log_abs_det_real_square(matrix, log_abs_det, error)
      real(dp), intent(in) :: matrix(:, :)
      real(dp), intent(out) :: log_abs_det
      logical, intent(out) :: error

      integer :: n, info, i
      integer, allocatable :: ipiv(:)
      real(dp), allocatable :: lu(:, :)
      external :: dgetrf

      log_abs_det = 0.0_dp
      error = .true.
      n = size(matrix, 1)
      if (n <= 0 .or. size(matrix, 2) /= n) return
      if (.not. all(ieee_is_finite(matrix))) return
      allocate (lu(n, n), ipiv(n))
      lu = matrix
      call dgetrf(n, n, lu, n, ipiv, info)
      if (info /= 0) return
      do i = 1, n
         if ((.not. ieee_is_finite(lu(i, i))) .or. abs(lu(i, i)) <= 0.0_dp) return
         log_abs_det = log_abs_det + log(abs(lu(i, i)))
      end do
      error = .false.
   end subroutine log_abs_det_real_square

   subroutine prepare_nonzero_flow_fixture(n_state, flow_time, x, z, jac, ok, status)
      integer, intent(in) :: n_state
      real(dp), intent(out) :: flow_time, x(:)
      complex(dp), intent(out) :: z(:), jac(:, :)
      logical, intent(out) :: ok
      integer, intent(out) :: status

      integer :: i, scale_idx, time_idx
      real(dp), parameter :: scales(6) = [0.01_dp, 0.03_dp, 0.08_dp, 0.16_dp, 0.32_dp, 0.64_dp]
      real(dp), parameter :: times(8) = [5.0e-3_dp, 1.0e-3_dp, 3.0e-4_dp, 1.0e-4_dp, 3.0e-5_dp, &
                                         1.0e-5_dp, 3.0e-6_dp, 1.0e-6_dp]
      logical :: flow_error

      ok = .false.
      status = -999
      flow_time = 0.0_dp
      x = 0.0_dp
      z = cmplx(0.0_dp, 0.0_dp, dp)
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      if (size(x) /= n_state .or. size(z) /= n_state) return
      if (size(jac, 1) /= n_state .or. size(jac, 2) /= n_state) return

      if (n_state == 8) then
         x = [0.076085349224890866_dp, 0.18799367260748823_dp, 0.032189982075346159_dp, &
              -0.099477108823300978_dp, -0.25101485205581014_dp, 0.39002871581192344_dp, &
              -1.0899446745680696_dp, -0.42841450356707877_dp]
         do time_idx = 1, size(times)
            call flow_at(times(time_idx), x, z, jac, flow_error, status)
            if ((.not. flow_error) .and. status >= 0 .and. valid_complex_vector_for_test(z) .and. &
                valid_complex_matrix_for_test(jac)) then
               flow_time = times(time_idx)
               ok = .true.
               return
            end if
         end do

         x = [0.0067898307652725608_dp, 0.21230054292167105_dp, 0.046613173758163672_dp, &
              -0.08609827338729012_dp, -0.31423804203734262_dp, 0.46948395070341509_dp, &
              -1.0659519313958072_dp, -0.44017779479105279_dp]
         do time_idx = 1, size(times)
            call flow_at(times(time_idx), x, z, jac, flow_error, status)
            if ((.not. flow_error) .and. status >= 0 .and. valid_complex_vector_for_test(z) .and. &
                valid_complex_matrix_for_test(jac)) then
               flow_time = times(time_idx)
               ok = .true.
               return
            end if
         end do
      end if

      do scale_idx = 1, size(scales)
         do i = 1, n_state
            x(i) = scales(scale_idx)*(0.37_dp*sin(0.31_dp*real(i, dp)) + &
                                      0.29_dp*cos(0.47_dp*real(i*i, dp)))
         end do
         do time_idx = 1, size(times)
            call flow_at(times(time_idx), x, z, jac, flow_error, status)
            if ((.not. flow_error) .and. status >= 0 .and. valid_complex_vector_for_test(z) .and. &
                valid_complex_matrix_for_test(jac)) then
               flow_time = times(time_idx)
               ok = .true.
               return
            end if
         end do
      end do
   end subroutine prepare_nonzero_flow_fixture

   subroutine evaluate_worldvolume_tangent_potential(flow_time_base, z_base, tangent, direction_t, offset, profile, value, &
                                                     error, status)
      real(dp), intent(in) :: flow_time_base, direction_t, offset
      complex(dp), intent(in) :: z_base(:), tangent(:)
      type(wv_potential_profile_t), intent(in) :: profile
      real(dp), intent(out) :: value
      logical, intent(out) :: error
      integer, intent(out) :: status

      real(dp) :: shifted_time, w_shifted, wprime_shifted
      complex(dp) :: z_shifted(size(z_base)), action_shifted

      value = huge(1.0_dp)
      error = .true.
      status = 0
      if (size(tangent) /= size(z_base)) then
         status = -1
         return
      end if
      shifted_time = flow_time_base + offset*direction_t
      z_shifted = z_base + offset*tangent
      call calculate_action(z_shifted, action_shifted)
      if ((.not. ieee_is_finite(real(action_shifted, dp))) .or. (.not. ieee_is_finite(aimag(action_shifted)))) then
         status = -2
         return
      end if
      call wv_potential_value_and_derivative(profile, shifted_time, w_shifted, wprime_shifted, error)
      if (error) then
         status = -3
         return
      end if
      value = real(action_shifted, dp) + w_shifted
      error = .not. ieee_is_finite(value)
      if (error) status = -4
   end subroutine evaluate_worldvolume_tangent_potential

   subroutine configure_stephanov_test_model(n_model)
      integer, intent(in) :: n_model

      stephanov_n = n_model
      stephanov_nf = 1
      stephanov_mass = 0.2_dp
      stephanov_mu = 0.3_dp
      stephanov_tau = 0.0_dp
      stephanov_include_mu_prefactor = .false.
      stephanov_emit_diagnostics = .true.
      ! The nonzero-flow fixture only supports geometry/force finite-difference
      ! checks at O(1e-7); 1e-12 full-Jacobian flow can fail h_min before adding
      ! useful test signal.
      at = 1.0e-9_dp
      rt = 1.0e-9_dp
      call set_derivative_mode("manual")
   end subroutine configure_stephanov_test_model

   subroutine fill_diagonally_dominant_jacobian(jac, random_real, random_imag)
      complex(dp), intent(out) :: jac(:, :)
      real(dp), intent(inout) :: random_real(:), random_imag(:)
      integer :: n, i, j, idx

      n = size(jac, 1)
      call random_number(random_real(1:n*n))
      call random_number(random_imag(1:n*n))
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      idx = 0
      do j = 1, n
         do i = 1, n
            idx = idx + 1
            if (i == j) then
               jac(i, j) = cmplx(1.0_dp + 0.02_dp*(2.0_dp*random_real(idx) - 1.0_dp), &
                                 0.02_dp*(2.0_dp*random_imag(idx) - 1.0_dp), dp)
            else
               jac(i, j) = cmplx(0.006_dp*(2.0_dp*random_real(idx) - 1.0_dp), &
                                 0.006_dp*(2.0_dp*random_imag(idx) - 1.0_dp), dp)
            end if
         end do
      end do
   end subroutine fill_diagonally_dominant_jacobian

   subroutine check_simplified_newton_contract(failures)
      integer, intent(inout) :: failures
      real(dp) :: b0_v(4), b_n(4), xi0_v(4), xi_n(4), delta_u(4), delta_lambda(4)
      real(dp) :: tangent_residual(4), normal_residual(4), lambda_orthogonality
      real(dp) :: delta_h, c_b, alpha2
      logical :: error, ok

      b0_v = [1.0_dp, 0.0_dp, -2.0_dp, 0.0_dp]
      b_n = [0.0_dp, 2.0_dp, 0.0_dp, 5.0_dp]
      xi0_v = [0.5_dp, 0.0_dp, -1.0_dp, 0.0_dp]
      xi_n = [0.0_dp, 1.0_dp, 0.0_dp, 2.0_dp]

      call wv_simplified_newton_update_from_sigma_decomposition(b0_v, b_n, xi0_v, xi_n, delta_h, delta_u, &
                                                                delta_lambda, c_b, alpha2, error)
      call wv_simplified_newton_linear_residuals(b0_v, b_n, xi0_v, xi_n, delta_h, delta_u, delta_lambda, &
                                                 tangent_residual, normal_residual, lambda_orthogonality, error)
      ok = (.not. error) .and. near(alpha2, 5.0_dp) .and. near(c_b, 2.4_dp) .and. near(delta_h, 2.4_dp) .and. &
           all_near(delta_u, [-0.2_dp, 0.0_dp, 0.4_dp, 0.0_dp]) .and. &
           all_near(delta_lambda, [0.0_dp, -0.4_dp, 0.0_dp, 0.2_dp]) .and. &
           near(dot_product(delta_lambda, xi_n), 0.0_dp) .and. &
           sqrt(sum(tangent_residual**2)) <= 1.0e-14_dp .and. sqrt(sum(normal_residual**2)) <= 1.0e-14_dp .and. &
           abs(lambda_orthogonality) <= 1.0e-14_dp

      write (*, '(A,L1)') "[CHECK] wv_simplified_newton_contract ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_simplified_newton_contract

   subroutine check_dense_simplified_newton_oracle(failures)
      integer, intent(inout) :: failures
      real(dp) :: b(4), xi(4), b_coords(4), b_tangent(4), b_normal(4), xi_coords(4), xi_tangent(4), xi_normal(4)
      real(dp) :: delta_u(4), delta_lambda(4), tangent_residual(4), normal_residual(4)
      real(dp) :: delta_h, c_b, alpha2, lambda_orthogonality, tangent_norm, normal_norm
      complex(dp) :: jac(2, 2)
      logical :: error, ok

      b = [0.75_dp, 1.25_dp, -0.35_dp, 0.80_dp]
      xi = [0.45_dp, -0.20_dp, 0.30_dp, 0.65_dp]
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      jac(1, 1) = cmplx(1.0_dp, 0.2_dp, dp)
      jac(1, 2) = cmplx(0.1_dp, -0.3_dp, dp)
      jac(2, 1) = cmplx(-0.4_dp, 0.05_dp, dp)
      jac(2, 2) = cmplx(1.3_dp, -0.1_dp, dp)

      call decompose_tangent_projection(b, b_coords, b_tangent, b_normal, jac, error)
      ok = .not. error
      call decompose_tangent_projection(xi, xi_coords, xi_tangent, xi_normal, jac, error)
      ok = ok .and. (.not. error)
      call real_vec(b_coords)
      call real_vec(xi_coords)

      call wv_simplified_newton_update_dense_with_jacobian(b, xi, jac, delta_h, delta_u, delta_lambda, c_b, alpha2, error)
      ok = ok .and. (.not. error)
      call wv_simplified_newton_linear_residuals(b_coords, b_normal, xi_coords, xi_normal, delta_h, delta_u, delta_lambda, &
                                                 tangent_residual, normal_residual, lambda_orthogonality, error)
      tangent_norm = sqrt(sum(tangent_residual**2))
      normal_norm = sqrt(sum(normal_residual**2))
      ok = ok .and. (.not. error) .and. alpha2 > 0.0_dp .and. tangent_norm <= 1.0e-12_dp .and. &
           normal_norm <= 1.0e-12_dp .and. abs(lambda_orthogonality) <= 1.0e-12_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] wv_dense_simplified_newton_oracle ok=", ok, &
         " tangent_res=", tangent_norm, " normal_res=", normal_norm, " lambda_orth=", abs(lambda_orthogonality)
      if (.not. ok) failures = failures + 1
   end subroutine check_dense_simplified_newton_oracle

   subroutine check_fail_closed_guards(failures)
      integer, intent(inout) :: failures
      real(dp) :: zero_normal(4), nonzero(4), out(4), out2(4), scalar, alpha2
      real(dp) :: bad_shape(3)
      logical :: error, ok

      zero_normal = 0.0_dp
      nonzero = [1.0_dp, 0.0_dp, -1.0_dp, 0.0_dp]
      out = 9.0_dp
      out2 = 9.0_dp
      scalar = 9.0_dp
      alpha2 = 9.0_dp

      call wv_force_from_sigma_components(nonzero, zero_normal, 1.0_dp, out, alpha2, error)
      ok = error .and. maxval(abs(out)) == 0.0_dp .and. alpha2 == 0.0_dp

      call wv_project_from_sigma_components(nonzero, nonzero, nonzero, zero_normal, out, out2, scalar, alpha2, error)
      ok = ok .and. error .and. maxval(abs(out)) == 0.0_dp .and. maxval(abs(out2)) == 0.0_dp .and. &
           scalar == 0.0_dp .and. alpha2 == 0.0_dp

      bad_shape = 1.0_dp
      call wv_real_inner_product(nonzero, bad_shape, scalar, error)
      ok = ok .and. error .and. scalar == 0.0_dp

      write (*, '(A,L1)') "[CHECK] wv_fail_closed_guards ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_fail_closed_guards

   logical function near(a, b) result(ok)
      real(dp), intent(in) :: a, b

      ok = abs(a - b) <= 64.0_dp * epsilon(1.0_dp) * max(1.0_dp, abs(a), abs(b))
   end function near

   logical function all_near(a, b) result(ok)
      real(dp), intent(in) :: a(:), b(:)
      integer :: i

      ok = size(a) == size(b)
      if (.not. ok) return
      do i = 1, size(a)
         if (.not. near(a(i), b(i))) then
            ok = .false.
            return
         end if
      end do
   end function all_near

   logical function all_close(a, b, tol) result(ok)
      real(dp), intent(in) :: a(:), b(:), tol
      integer :: i

      ok = size(a) == size(b)
      if (.not. ok) return
      do i = 1, size(a)
         if (abs(a(i) - b(i)) > tol) then
            ok = .false.
            return
         end if
      end do
   end function all_close

   logical function valid_complex_vector_for_test(values) result(ok)
      complex(dp), intent(in) :: values(:)

      ok = size(values) > 0 .and. all(ieee_is_finite(real(values, dp))) .and. all(ieee_is_finite(aimag(values)))
   end function valid_complex_vector_for_test

   logical function valid_complex_matrix_for_test(values) result(ok)
      complex(dp), intent(in) :: values(:, :)

      ok = size(values, 1) > 0 .and. size(values, 2) > 0 .and. &
           all(ieee_is_finite(real(values, dp))) .and. all(ieee_is_finite(aimag(values)))
   end function valid_complex_matrix_for_test

end program test_wv_hmc_math_kernels

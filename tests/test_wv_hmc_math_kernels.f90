program test_wv_hmc_math_kernels
   use hmc_kernels, only: decompose_tangent_projection
   use model, only: calculate_action, ds, hessian_vec
   use param_mod, only: set_derivative_mode, stephanov_emit_diagnostics, stephanov_include_mu_prefactor, &
                        stephanov_mass, stephanov_mu, stephanov_n, stephanov_nf, stephanov_tau
   use utils, only: complex_to_real, dp, real_vec
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

   subroutine configure_stephanov_test_model(n_model)
      integer, intent(in) :: n_model

      stephanov_n = n_model
      stephanov_nf = 1
      stephanov_mass = 0.2_dp
      stephanov_mu = 0.3_dp
      stephanov_tau = 0.0_dp
      stephanov_include_mu_prefactor = .false.
      stephanov_emit_diagnostics = .true.
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

end program test_wv_hmc_math_kernels

module wv_hmc_kernels
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use hmc_kernels, only: decompose_tangent_projection
   use solve_flow, only: flow_apply_worldvolume_operator_at, flow_workspace_t, intode_diagnostics_context_t, &
                         intode_status_unknown
   use utils, only: dp, map_to_real_mat, real_vec
   implicit none

   private
   public :: wv_alpha2, wv_decompose_iterative_with_jacobian, wv_decompose_matrix_free_at, &
             wv_force_dense_with_jacobian, &
             wv_force_from_sigma_components, wv_force_iterative_with_jacobian, wv_project_dense_with_jacobian, &
             wv_force_matrix_free_at, wv_project_from_sigma_components, wv_project_iterative_with_jacobian, &
             wv_project_matrix_free_at, &
             wv_reflect_flow_component_dense_with_jacobian, &
             wv_real_inner_product, wv_simplified_newton_update_from_sigma_decomposition, &
             wv_simplified_newton_update_dense_with_jacobian, wv_simplified_newton_update_iterative_with_jacobian, &
             wv_simplified_newton_update_matrix_free_at, wv_simplified_newton_linear_residuals, &
             wv_xi_from_action_gradient, wv_tangent_flow_rhs_from_hessian_vec, wv_normal_flow_rhs_from_hessian_vec

contains

   subroutine wv_real_inner_product(a, b, value, error)
      real(dp), intent(in) :: a(:), b(:)
      real(dp), intent(out) :: value
      logical, intent(out) :: error

      value = 0.0_dp
      error = .true.
      if (.not. valid_pair(a, b)) return
      value = dot_product(a, b)
      if (.not. ieee_is_finite(value)) then
         value = 0.0_dp
         return
      end if
      error = .false.
   end subroutine wv_real_inner_product

   subroutine wv_alpha2(xi_normal, alpha2, error)
      real(dp), intent(in) :: xi_normal(:)
      real(dp), intent(out) :: alpha2
      logical, intent(out) :: error

      alpha2 = 0.0_dp
      error = .true.
      if (.not. valid_vector(xi_normal)) return
      alpha2 = dot_product(xi_normal, xi_normal)
      if (.not. ieee_is_finite(alpha2)) then
         alpha2 = 0.0_dp
         return
      end if
      if (alpha2 <= 0.0_dp) then
         alpha2 = 0.0_dp
         return
      end if
      error = .false.
   end subroutine wv_alpha2

   subroutine wv_xi_from_action_gradient(grad, xi, error)
      complex(dp), intent(in) :: grad(:)
      complex(dp), intent(out) :: xi(:)
      logical, intent(out) :: error

      xi = cmplx(0.0_dp, 0.0_dp, dp)
      error = .true.
      if (.not. valid_complex_pair(grad, xi)) return
      xi = conjg(grad)
      if (.not. valid_complex_vector(xi)) then
         xi = cmplx(0.0_dp, 0.0_dp, dp)
         return
      end if
      error = .false.
   end subroutine wv_xi_from_action_gradient

   subroutine wv_tangent_flow_rhs_from_hessian_vec(hv, rhs, error)
      complex(dp), intent(in) :: hv(:)
      complex(dp), intent(out) :: rhs(:)
      logical, intent(out) :: error

      rhs = cmplx(0.0_dp, 0.0_dp, dp)
      error = .true.
      if (.not. valid_complex_pair(hv, rhs)) return
      rhs = conjg(hv)
      if (.not. valid_complex_vector(rhs)) then
         rhs = cmplx(0.0_dp, 0.0_dp, dp)
         return
      end if
      error = .false.
   end subroutine wv_tangent_flow_rhs_from_hessian_vec

   subroutine wv_normal_flow_rhs_from_hessian_vec(hv, rhs, error)
      complex(dp), intent(in) :: hv(:)
      complex(dp), intent(out) :: rhs(:)
      logical, intent(out) :: error

      rhs = cmplx(0.0_dp, 0.0_dp, dp)
      error = .true.
      if (.not. valid_complex_pair(hv, rhs)) return
      rhs = -conjg(hv)
      if (.not. valid_complex_vector(rhs)) then
         rhs = cmplx(0.0_dp, 0.0_dp, dp)
         return
      end if
      error = .false.
   end subroutine wv_normal_flow_rhs_from_hessian_vec

   subroutine wv_project_from_sigma_components(w_tangent_sigma, w_normal_sigma, xi_tangent_sigma, xi_normal_sigma, &
                                               w_parallel, w_perp, c, alpha2, error)
      real(dp), intent(in) :: w_tangent_sigma(:), w_normal_sigma(:)
      real(dp), intent(in) :: xi_tangent_sigma(:), xi_normal_sigma(:)
      real(dp), intent(out) :: w_parallel(:), w_perp(:)
      real(dp), intent(out) :: c, alpha2
      logical, intent(out) :: error
      real(dp) :: numerator

      w_parallel = 0.0_dp
      w_perp = 0.0_dp
      c = 0.0_dp
      alpha2 = 0.0_dp
      error = .true.

      if (.not. same_shape4(w_tangent_sigma, w_normal_sigma, xi_tangent_sigma, xi_normal_sigma)) return
      if (size(w_parallel) /= size(w_tangent_sigma) .or. size(w_perp) /= size(w_tangent_sigma)) return
      if (.not. valid_vector(w_tangent_sigma)) return
      if (.not. valid_vector(w_normal_sigma)) return
      if (.not. valid_vector(xi_tangent_sigma)) return
      if (.not. valid_vector(xi_normal_sigma)) return

      call wv_alpha2(xi_normal_sigma, alpha2, error)
      if (error) return

      numerator = dot_product(xi_normal_sigma, w_normal_sigma)
      if (.not. ieee_is_finite(numerator)) then
         alpha2 = 0.0_dp
         return
      end if

      c = numerator / alpha2
      if (.not. ieee_is_finite(c)) then
         c = 0.0_dp
         alpha2 = 0.0_dp
         return
      end if

      w_parallel = w_tangent_sigma + c * xi_normal_sigma
      w_perp = w_normal_sigma - c * xi_normal_sigma
      if (.not. valid_vector(w_parallel) .or. .not. valid_vector(w_perp)) then
         w_parallel = 0.0_dp
         w_perp = 0.0_dp
         c = 0.0_dp
         alpha2 = 0.0_dp
         return
      end if
      error = .false.
   end subroutine wv_project_from_sigma_components

   subroutine wv_project_dense_with_jacobian(w, xi, jac, w_parallel, w_perp, c, alpha2, error)
      real(dp), intent(in) :: w(:), xi(:)
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: w_parallel(:), w_perp(:)
      real(dp), intent(out) :: c, alpha2
      logical, intent(out) :: error
      real(dp) :: w_coords(size(w)), w_tangent(size(w)), w_normal(size(w))
      real(dp) :: xi_coords(size(xi)), xi_tangent(size(xi)), xi_normal(size(xi))
      logical :: ierr

      w_parallel = 0.0_dp
      w_perp = 0.0_dp
      c = 0.0_dp
      alpha2 = 0.0_dp
      error = .true.

      if (.not. valid_pair(w, xi)) return
      if (size(w_parallel) /= size(w) .or. size(w_perp) /= size(w)) return

      call decompose_tangent_projection(w, w_coords, w_tangent, w_normal, jac, ierr)
      if (ierr) return
      call decompose_tangent_projection(xi, xi_coords, xi_tangent, xi_normal, jac, ierr)
      if (ierr) return

      call wv_project_from_sigma_components(w_tangent, w_normal, xi_tangent, xi_normal, w_parallel, w_perp, c, &
                                            alpha2, error)
   end subroutine wv_project_dense_with_jacobian

   subroutine wv_reflect_flow_component_dense_with_jacobian(w, xi, jac, w_reflected, c, alpha2, error)
      real(dp), intent(in) :: w(:), xi(:)
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: w_reflected(:)
      real(dp), intent(out) :: c, alpha2
      logical, intent(out) :: error

      real(dp) :: w_coords(size(w)), w_tangent(size(w)), w_normal(size(w))
      real(dp) :: xi_coords(size(xi)), xi_tangent(size(xi)), xi_normal(size(xi))
      real(dp) :: numerator
      logical :: ierr

      w_reflected = 0.0_dp
      c = 0.0_dp
      alpha2 = 0.0_dp
      error = .true.
      if (.not. valid_pair(w, xi)) return
      if (size(w_reflected) /= size(w)) return

      call decompose_tangent_projection(w, w_coords, w_tangent, w_normal, jac, ierr)
      if (ierr) return
      call decompose_tangent_projection(xi, xi_coords, xi_tangent, xi_normal, jac, ierr)
      if (ierr) return

      call wv_alpha2(xi_normal, alpha2, error)
      if (error) return
      numerator = dot_product(xi_normal, w_normal)
      if (.not. ieee_is_finite(numerator)) return
      c = numerator/alpha2
      if (.not. ieee_is_finite(c)) return

      w_reflected = w_tangent - c*xi_normal
      if (.not. valid_vector(w_reflected)) then
         w_reflected = 0.0_dp
         c = 0.0_dp
         alpha2 = 0.0_dp
         return
      end if
      error = .false.
   end subroutine wv_reflect_flow_component_dense_with_jacobian

   subroutine wv_decompose_iterative_with_jacobian(b, jac, coords, tangent, normal, residual_norm, iterations, &
                                                   tol, max_iter, error)
      real(dp), intent(in) :: b(:), tol
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: coords(:), tangent(:), normal(:), residual_norm
      integer, intent(in) :: max_iter
      integer, intent(out) :: iterations
      logical, intent(out) :: error

      integer :: n
      real(dp) :: jac_real(size(b), size(b)), tangent_coords(size(b))
      logical :: solve_error

      coords = 0.0_dp
      tangent = 0.0_dp
      normal = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      error = .true.

      n = size(b)
      if (n <= 0) return
      if (size(coords) /= n .or. size(tangent) /= n .or. size(normal) /= n) return
      if (size(jac, 1) /= size(jac, 2) .or. n /= 2*size(jac, 1)) return
      if ((.not. ieee_is_finite(tol)) .or. tol <= 0.0_dp) return
      if (max_iter <= 0) return
      if (.not. valid_vector(b)) return
      if (.not. valid_complex_matrix(jac)) return

      call map_to_real_mat(jac, jac_real)
      if (.not. valid_real_matrix(jac_real)) return
      call bicgstab_solve_real(jac_real, b, coords, residual_norm, iterations, tol, max_iter, solve_error)
      if (solve_error) return

      tangent_coords = coords
      call real_vec(tangent_coords)
      tangent = matmul(jac_real, tangent_coords)
      normal = b - tangent
      if (.not. valid_vector(coords) .or. .not. valid_vector(tangent) .or. .not. valid_vector(normal)) then
         coords = 0.0_dp
         tangent = 0.0_dp
         normal = 0.0_dp
         residual_norm = huge(1.0_dp)
         iterations = 0
         return
      end if
      error = .false.
   end subroutine wv_decompose_iterative_with_jacobian

   subroutine wv_decompose_matrix_free_at(flow_time, x_base, b, coords, tangent, normal, residual_norm, iterations, &
                                          tol, max_iter, error, status, flow_workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time, x_base(:), b(:), tol
      real(dp), intent(out) :: coords(:), tangent(:), normal(:), residual_norm
      integer, intent(in) :: max_iter
      integer, intent(out) :: iterations
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      real(dp) :: combined(size(b))
      complex(dp) :: z_dummy(size(x_base))
      logical :: local_error
      integer :: flow_status

      coords = 0.0_dp
      tangent = 0.0_dp
      normal = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status
      if (.not. ieee_is_finite(flow_time)) return
      if (.not. valid_state_vector(x_base)) return
      if (.not. valid_vector(b)) return
      if (size(coords) /= size(b) .or. size(tangent) /= size(b) .or. size(normal) /= size(b)) return
      if (size(b) /= 2*size(x_base)) return
      if ((.not. ieee_is_finite(tol)) .or. tol <= 0.0_dp) return
      if (max_iter <= 0) return

      call bicgstab_solve_worldvolume_operator(flow_time, x_base, b, coords, residual_norm, iterations, tol, max_iter, &
                                               local_error, flow_status, flow_workspace, intode_diagnostics)
      if (present(status)) status = flow_status
      if (local_error) return

      call apply_worldvolume_operator_checked(flow_time, x_base, coords, z_dummy, tangent, normal, combined, &
                                             local_error, flow_status, flow_workspace, intode_diagnostics)
      if (present(status)) status = flow_status
      if (local_error) return
      residual_norm = norm2(combined - b)
      if (.not. ieee_is_finite(residual_norm)) return
      if (residual_norm > tol*max(1.0_dp, norm2(b))) return
      error = .false.
   end subroutine wv_decompose_matrix_free_at

   subroutine wv_project_iterative_with_jacobian(w, xi, jac, w_parallel, w_perp, c, alpha2, residual_norm, &
                                                iterations, tol, max_iter, error)
      real(dp), intent(in) :: w(:), xi(:), tol
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: w_parallel(:), w_perp(:), c, alpha2, residual_norm
      integer, intent(in) :: max_iter
      integer, intent(out) :: iterations
      logical, intent(out) :: error

      real(dp) :: w_coords(size(w)), w_tangent(size(w)), w_normal(size(w))
      real(dp) :: xi_coords(size(xi)), xi_tangent(size(xi)), xi_normal(size(xi))
      real(dp) :: residual_w, residual_xi
      integer :: iterations_w, iterations_xi
      logical :: decompose_error

      w_parallel = 0.0_dp
      w_perp = 0.0_dp
      c = 0.0_dp
      alpha2 = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      error = .true.
      if (.not. valid_pair(w, xi)) return
      if (size(w_parallel) /= size(w) .or. size(w_perp) /= size(w)) return

      call wv_decompose_iterative_with_jacobian(w, jac, w_coords, w_tangent, w_normal, residual_w, iterations_w, &
                                                tol, max_iter, decompose_error)
      if (decompose_error) return
      call wv_decompose_iterative_with_jacobian(xi, jac, xi_coords, xi_tangent, xi_normal, residual_xi, iterations_xi, &
                                                tol, max_iter, decompose_error)
      if (decompose_error) return

      call wv_project_from_sigma_components(w_tangent, w_normal, xi_tangent, xi_normal, w_parallel, w_perp, c, &
                                            alpha2, error)
      if (error) return
      residual_norm = max(residual_w, residual_xi)
      iterations = iterations_w + iterations_xi
   end subroutine wv_project_iterative_with_jacobian

   subroutine wv_project_matrix_free_at(flow_time, x_base, w, xi, w_parallel, w_perp, c, alpha2, residual_norm, &
                                        iterations, tol, max_iter, error, status, flow_workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time, x_base(:), w(:), xi(:), tol
      real(dp), intent(out) :: w_parallel(:), w_perp(:), c, alpha2, residual_norm
      integer, intent(in) :: max_iter
      integer, intent(out) :: iterations
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      real(dp) :: w_coords(size(w)), w_tangent(size(w)), w_normal(size(w))
      real(dp) :: xi_coords(size(xi)), xi_tangent(size(xi)), xi_normal(size(xi))
      real(dp) :: residual_w, residual_xi
      integer :: iterations_w, iterations_xi, flow_status
      logical :: decompose_error

      w_parallel = 0.0_dp
      w_perp = 0.0_dp
      c = 0.0_dp
      alpha2 = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status
      if (.not. valid_pair(w, xi)) return
      if (size(w_parallel) /= size(w) .or. size(w_perp) /= size(w)) return

      call wv_decompose_matrix_free_at(flow_time, x_base, w, w_coords, w_tangent, w_normal, residual_w, &
                                       iterations_w, tol, max_iter, decompose_error, flow_status, flow_workspace, &
                                       intode_diagnostics)
      if (present(status)) status = flow_status
      if (decompose_error) return
      call wv_decompose_matrix_free_at(flow_time, x_base, xi, xi_coords, xi_tangent, xi_normal, residual_xi, &
                                       iterations_xi, tol, max_iter, decompose_error, flow_status, flow_workspace, &
                                       intode_diagnostics)
      if (present(status)) status = flow_status
      if (decompose_error) return

      call wv_project_from_sigma_components(w_tangent, w_normal, xi_tangent, xi_normal, w_parallel, w_perp, c, &
                                            alpha2, error)
      if (error) return
      residual_norm = max(residual_w, residual_xi)
      iterations = iterations_w + iterations_xi
   end subroutine wv_project_matrix_free_at

   subroutine wv_force_from_sigma_components(xi, xi_normal, wprime, force, alpha2, error)
      real(dp), intent(in) :: xi(:), xi_normal(:)
      real(dp), intent(in) :: wprime
      real(dp), intent(out) :: force(:)
      real(dp), intent(out) :: alpha2
      logical, intent(out) :: error

      force = 0.0_dp
      alpha2 = 0.0_dp
      error = .true.

      if (.not. valid_pair(xi, xi_normal)) return
      if (size(force) /= size(xi)) return
      if (.not. ieee_is_finite(wprime)) return

      call wv_alpha2(xi_normal, alpha2, error)
      if (error) return

      force = 0.5_dp * (xi + (wprime / alpha2) * xi_normal)
      if (.not. valid_vector(force)) then
         force = 0.0_dp
         alpha2 = 0.0_dp
         return
      end if
      error = .false.
   end subroutine wv_force_from_sigma_components

   subroutine wv_force_dense_with_jacobian(xi, jac, wprime, force, alpha2, error)
      real(dp), intent(in) :: xi(:)
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(in) :: wprime
      real(dp), intent(out) :: force(:)
      real(dp), intent(out) :: alpha2
      logical, intent(out) :: error
      real(dp) :: xi_coords(size(xi)), xi_tangent(size(xi)), xi_normal(size(xi))
      logical :: ierr

      force = 0.0_dp
      alpha2 = 0.0_dp
      error = .true.
      if (.not. valid_vector(xi)) return
      if (size(force) /= size(xi)) return

      call decompose_tangent_projection(xi, xi_coords, xi_tangent, xi_normal, jac, ierr)
      if (ierr) return

      call wv_force_from_sigma_components(xi, xi_normal, wprime, force, alpha2, error)
   end subroutine wv_force_dense_with_jacobian

   subroutine wv_force_iterative_with_jacobian(xi, jac, wprime, force, alpha2, residual_norm, iterations, &
                                               tol, max_iter, error)
      real(dp), intent(in) :: xi(:), wprime, tol
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: force(:), alpha2, residual_norm
      integer, intent(in) :: max_iter
      integer, intent(out) :: iterations
      logical, intent(out) :: error

      real(dp) :: xi_coords(size(xi)), xi_tangent(size(xi)), xi_normal(size(xi))
      logical :: decompose_error

      force = 0.0_dp
      alpha2 = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      error = .true.
      if (.not. valid_vector(xi)) return
      if (size(force) /= size(xi)) return

      call wv_decompose_iterative_with_jacobian(xi, jac, xi_coords, xi_tangent, xi_normal, residual_norm, iterations, &
                                                tol, max_iter, decompose_error)
      if (decompose_error) return
      call wv_force_from_sigma_components(xi, xi_normal, wprime, force, alpha2, error)
   end subroutine wv_force_iterative_with_jacobian

   subroutine wv_force_matrix_free_at(flow_time, x_base, xi, wprime, force, alpha2, residual_norm, iterations, &
                                      tol, max_iter, error, status, flow_workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time, x_base(:), xi(:), wprime, tol
      real(dp), intent(out) :: force(:), alpha2, residual_norm
      integer, intent(in) :: max_iter
      integer, intent(out) :: iterations
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      real(dp) :: xi_coords(size(xi)), xi_tangent(size(xi)), xi_normal(size(xi))
      integer :: flow_status
      logical :: decompose_error

      force = 0.0_dp
      alpha2 = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status
      if (.not. valid_vector(xi)) return
      if (size(force) /= size(xi)) return

      call wv_decompose_matrix_free_at(flow_time, x_base, xi, xi_coords, xi_tangent, xi_normal, residual_norm, &
                                       iterations, tol, max_iter, decompose_error, flow_status, flow_workspace, &
                                       intode_diagnostics)
      if (present(status)) status = flow_status
      if (decompose_error) return
      call wv_force_from_sigma_components(xi, xi_normal, wprime, force, alpha2, error)
   end subroutine wv_force_matrix_free_at

   subroutine wv_simplified_newton_update_from_sigma_decomposition(b0_tangent, b_normal, xi0_tangent, xi_normal, &
                                                                   delta_h, delta_u, delta_lambda, c_b, alpha2, error)
      real(dp), intent(in) :: b0_tangent(:), b_normal(:), xi0_tangent(:), xi_normal(:)
      real(dp), intent(out) :: delta_h
      real(dp), intent(out) :: delta_u(:), delta_lambda(:)
      real(dp), intent(out) :: c_b, alpha2
      logical, intent(out) :: error
      real(dp) :: numerator

      delta_h = 0.0_dp
      delta_u = 0.0_dp
      delta_lambda = 0.0_dp
      c_b = 0.0_dp
      alpha2 = 0.0_dp
      error = .true.

      if (.not. same_shape4(b0_tangent, b_normal, xi0_tangent, xi_normal)) return
      if (size(delta_u) /= size(b0_tangent) .or. size(delta_lambda) /= size(b0_tangent)) return
      if (.not. valid_vector(b0_tangent)) return
      if (.not. valid_vector(b_normal)) return
      if (.not. valid_vector(xi0_tangent)) return
      if (.not. valid_vector(xi_normal)) return

      call wv_alpha2(xi_normal, alpha2, error)
      if (error) return

      numerator = dot_product(xi_normal, b_normal)
      if (.not. ieee_is_finite(numerator)) then
         alpha2 = 0.0_dp
         return
      end if

      c_b = numerator / alpha2
      if (.not. ieee_is_finite(c_b)) then
         c_b = 0.0_dp
         alpha2 = 0.0_dp
         return
      end if

      delta_h = c_b
      delta_u = b0_tangent - c_b * xi0_tangent
      delta_lambda = b_normal - c_b * xi_normal
      if (.not. ieee_is_finite(delta_h) .or. .not. valid_vector(delta_u) .or. .not. valid_vector(delta_lambda)) then
         delta_h = 0.0_dp
         delta_u = 0.0_dp
         delta_lambda = 0.0_dp
         c_b = 0.0_dp
         alpha2 = 0.0_dp
         return
      end if
      error = .false.
   end subroutine wv_simplified_newton_update_from_sigma_decomposition

   subroutine wv_simplified_newton_update_dense_with_jacobian(b, xi, jac, delta_h, delta_u, delta_lambda, c_b, alpha2, error)
      real(dp), intent(in) :: b(:), xi(:)
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: delta_h
      real(dp), intent(out) :: delta_u(:), delta_lambda(:)
      real(dp), intent(out) :: c_b, alpha2
      logical, intent(out) :: error
      real(dp) :: b_coords(size(b)), b_tangent(size(b)), b_normal(size(b))
      real(dp) :: xi_coords(size(xi)), xi_tangent(size(xi)), xi_normal(size(xi))
      logical :: ierr

      delta_h = 0.0_dp
      delta_u = 0.0_dp
      delta_lambda = 0.0_dp
      c_b = 0.0_dp
      alpha2 = 0.0_dp
      error = .true.
      if (.not. valid_pair(b, xi)) return
      if (size(delta_u) /= size(b) .or. size(delta_lambda) /= size(b)) return

      call decompose_tangent_projection(b, b_coords, b_tangent, b_normal, jac, ierr)
      if (ierr) return
      call decompose_tangent_projection(xi, xi_coords, xi_tangent, xi_normal, jac, ierr)
      if (ierr) return

      call real_vec(b_coords)
      call real_vec(xi_coords)
      call wv_simplified_newton_update_from_sigma_decomposition(b_coords, b_normal, xi_coords, xi_normal, &
                                                                delta_h, delta_u, delta_lambda, c_b, alpha2, error)
   end subroutine wv_simplified_newton_update_dense_with_jacobian

   subroutine wv_simplified_newton_update_iterative_with_jacobian(b, xi, jac, delta_h, delta_u, delta_lambda, &
                                                                  c_b, alpha2, residual_norm, iterations, tol, &
                                                                  max_iter, error)
      real(dp), intent(in) :: b(:), xi(:), tol
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: delta_h, delta_u(:), delta_lambda(:), c_b, alpha2, residual_norm
      integer, intent(in) :: max_iter
      integer, intent(out) :: iterations
      logical, intent(out) :: error

      real(dp) :: b_coords(size(b)), b_tangent(size(b)), b_normal(size(b))
      real(dp) :: xi_coords(size(xi)), xi_tangent(size(xi)), xi_normal(size(xi))
      real(dp) :: residual_b, residual_xi
      integer :: iterations_b, iterations_xi
      logical :: decompose_error

      delta_h = 0.0_dp
      delta_u = 0.0_dp
      delta_lambda = 0.0_dp
      c_b = 0.0_dp
      alpha2 = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      error = .true.
      if (.not. valid_pair(b, xi)) return
      if (size(delta_u) /= size(b) .or. size(delta_lambda) /= size(b)) return

      call wv_decompose_iterative_with_jacobian(b, jac, b_coords, b_tangent, b_normal, residual_b, iterations_b, &
                                                tol, max_iter, decompose_error)
      if (decompose_error) return
      call wv_decompose_iterative_with_jacobian(xi, jac, xi_coords, xi_tangent, xi_normal, residual_xi, iterations_xi, &
                                                tol, max_iter, decompose_error)
      if (decompose_error) return
      call real_vec(b_coords)
      call real_vec(xi_coords)

      call wv_simplified_newton_update_from_sigma_decomposition(b_coords, b_normal, xi_coords, xi_normal, &
                                                                delta_h, delta_u, delta_lambda, c_b, alpha2, error)
      if (error) return
      residual_norm = max(residual_b, residual_xi)
      iterations = iterations_b + iterations_xi
   end subroutine wv_simplified_newton_update_iterative_with_jacobian

   subroutine wv_simplified_newton_update_matrix_free_at(flow_time, x_base, b, xi, delta_h, delta_u, delta_lambda, &
                                                         c_b, alpha2, residual_norm, iterations, tol, max_iter, &
                                                         error, status, flow_workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time, x_base(:), b(:), xi(:), tol
      real(dp), intent(out) :: delta_h, delta_u(:), delta_lambda(:), c_b, alpha2, residual_norm
      integer, intent(in) :: max_iter
      integer, intent(out) :: iterations
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      real(dp) :: b_coords(size(b)), b_tangent(size(b)), b_normal(size(b))
      real(dp) :: xi_coords(size(xi)), xi_tangent(size(xi)), xi_normal(size(xi))
      real(dp) :: residual_b, residual_xi
      integer :: iterations_b, iterations_xi, flow_status
      logical :: decompose_error

      delta_h = 0.0_dp
      delta_u = 0.0_dp
      delta_lambda = 0.0_dp
      c_b = 0.0_dp
      alpha2 = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status
      if (.not. valid_pair(b, xi)) return
      if (size(delta_u) /= size(b) .or. size(delta_lambda) /= size(b)) return

      call wv_decompose_matrix_free_at(flow_time, x_base, b, b_coords, b_tangent, b_normal, residual_b, &
                                       iterations_b, tol, max_iter, decompose_error, flow_status, flow_workspace, &
                                       intode_diagnostics)
      if (present(status)) status = flow_status
      if (decompose_error) return
      call wv_decompose_matrix_free_at(flow_time, x_base, xi, xi_coords, xi_tangent, xi_normal, residual_xi, &
                                       iterations_xi, tol, max_iter, decompose_error, flow_status, flow_workspace, &
                                       intode_diagnostics)
      if (present(status)) status = flow_status
      if (decompose_error) return
      call real_vec(b_coords)
      call real_vec(xi_coords)

      call wv_simplified_newton_update_from_sigma_decomposition(b_coords, b_normal, xi_coords, xi_normal, &
                                                                delta_h, delta_u, delta_lambda, c_b, alpha2, error)
      if (error) return
      residual_norm = max(residual_b, residual_xi)
      iterations = iterations_b + iterations_xi
   end subroutine wv_simplified_newton_update_matrix_free_at

   subroutine wv_simplified_newton_linear_residuals(b0_tangent, b_normal, xi0_tangent, xi_normal, delta_h, delta_u, &
                                                   delta_lambda, tangent_residual, normal_residual, lambda_orthogonality, &
                                                   error)
      real(dp), intent(in) :: b0_tangent(:), b_normal(:), xi0_tangent(:), xi_normal(:)
      real(dp), intent(in) :: delta_h, delta_u(:), delta_lambda(:)
      real(dp), intent(out) :: tangent_residual(:), normal_residual(:), lambda_orthogonality
      logical, intent(out) :: error

      tangent_residual = 0.0_dp
      normal_residual = 0.0_dp
      lambda_orthogonality = 0.0_dp
      error = .true.
      if (.not. same_shape4(b0_tangent, b_normal, xi0_tangent, xi_normal)) return
      if (size(delta_u) /= size(b0_tangent) .or. size(delta_lambda) /= size(b0_tangent)) return
      if (size(tangent_residual) /= size(b0_tangent) .or. size(normal_residual) /= size(b0_tangent)) return
      if (.not. ieee_is_finite(delta_h)) return
      if (.not. valid_vector(delta_u)) return
      if (.not. valid_vector(delta_lambda)) return

      tangent_residual = delta_u + delta_h * xi0_tangent - b0_tangent
      normal_residual = delta_lambda + delta_h * xi_normal - b_normal
      lambda_orthogonality = dot_product(delta_lambda, xi_normal)
      if (.not. valid_vector(tangent_residual) .or. .not. valid_vector(normal_residual) .or. &
          .not. ieee_is_finite(lambda_orthogonality)) then
         tangent_residual = 0.0_dp
         normal_residual = 0.0_dp
         lambda_orthogonality = 0.0_dp
         return
      end if
      error = .false.
   end subroutine wv_simplified_newton_linear_residuals

   subroutine bicgstab_solve_real(a, b, x, residual_norm, iterations, tol, max_iter, error)
      real(dp), intent(in) :: a(:, :), b(:), tol
      real(dp), intent(out) :: x(:), residual_norm
      integer, intent(in) :: max_iter
      integer, intent(out) :: iterations
      logical, intent(out) :: error

      integer :: n, iter
      real(dp) :: r(size(b)), r_hat(size(b)), p(size(b)), v(size(b)), s(size(b)), t(size(b))
      real(dp) :: rho_old, rho_new, alpha, beta, omega, denom, t_norm2, threshold, b_norm

      x = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      error = .true.
      n = size(b)
      if (n <= 0) return
      if (size(a, 1) /= n .or. size(a, 2) /= n .or. size(x) /= n) return
      if ((.not. ieee_is_finite(tol)) .or. tol <= 0.0_dp) return
      if (max_iter <= 0) return
      if (.not. valid_vector(b)) return
      if (.not. valid_real_matrix(a)) return

      r = b
      r_hat = r
      p = 0.0_dp
      v = 0.0_dp
      rho_old = 1.0_dp
      alpha = 1.0_dp
      omega = 1.0_dp
      b_norm = norm2(b)
      threshold = tol*max(1.0_dp, b_norm)
      residual_norm = b_norm
      if (residual_norm <= threshold) then
         error = .false.
         return
      end if

      do iter = 1, max_iter
         rho_new = dot_product(r_hat, r)
         if (.not. ieee_is_finite(rho_new) .or. abs(rho_new) <= tiny(1.0_dp)) return
         if (iter == 1) then
            p = r
         else
            if (abs(omega) <= tiny(1.0_dp)) return
            beta = (rho_new/rho_old)*(alpha/omega)
            if (.not. ieee_is_finite(beta)) return
            p = r + beta*(p - omega*v)
         end if

         v = matmul(a, p)
         denom = dot_product(r_hat, v)
         if (.not. ieee_is_finite(denom) .or. abs(denom) <= tiny(1.0_dp)) return
         alpha = rho_new/denom
         if (.not. ieee_is_finite(alpha)) return
         s = r - alpha*v
         residual_norm = norm2(s)
         if (.not. ieee_is_finite(residual_norm)) return
         if (residual_norm <= threshold) then
            x = x + alpha*p
            iterations = iter
            error = .false.
            return
         end if

         t = matmul(a, s)
         t_norm2 = dot_product(t, t)
         if (.not. ieee_is_finite(t_norm2) .or. t_norm2 <= tiny(1.0_dp)) return
         omega = dot_product(t, s)/t_norm2
         if (.not. ieee_is_finite(omega)) return
         x = x + alpha*p + omega*s
         r = s - omega*t
         residual_norm = norm2(r)
         iterations = iter
         if (.not. ieee_is_finite(residual_norm)) return
         if (residual_norm <= threshold) then
            error = .false.
            return
         end if
         rho_old = rho_new
      end do
   end subroutine bicgstab_solve_real

   subroutine bicgstab_solve_worldvolume_operator(flow_time, x_base, b, x, residual_norm, iterations, tol, max_iter, &
                                                  error, status, flow_workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time, x_base(:), b(:), tol
      real(dp), intent(out) :: x(:), residual_norm
      integer, intent(in) :: max_iter
      integer, intent(out) :: iterations
      logical, intent(out) :: error
      integer, intent(out) :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      integer :: iter
      real(dp) :: r(size(b)), r_hat(size(b)), p(size(b)), v(size(b)), s(size(b)), t(size(b))
      real(dp) :: rho_old, rho_new, alpha, beta, omega, denom, t_norm2, threshold, b_norm
      logical :: apply_error

      x = 0.0_dp
      residual_norm = huge(1.0_dp)
      iterations = 0
      status = intode_status_unknown
      error = .true.
      if (.not. valid_vector(b)) return
      if (size(x) /= size(b)) return
      if ((.not. ieee_is_finite(tol)) .or. tol <= 0.0_dp) return
      if (max_iter <= 0) return

      r = b
      r_hat = r
      p = 0.0_dp
      v = 0.0_dp
      rho_old = 1.0_dp
      alpha = 1.0_dp
      omega = 1.0_dp
      b_norm = norm2(b)
      threshold = tol*max(1.0_dp, b_norm)
      residual_norm = b_norm
      if (residual_norm <= threshold) then
         error = .false.
         return
      end if

      do iter = 1, max_iter
         rho_new = dot_product(r_hat, r)
         if (.not. ieee_is_finite(rho_new) .or. abs(rho_new) <= tiny(1.0_dp)) return
         if (iter == 1) then
            p = r
         else
            if (abs(omega) <= tiny(1.0_dp)) return
            beta = (rho_new/rho_old)*(alpha/omega)
            if (.not. ieee_is_finite(beta)) return
            p = r + beta*(p - omega*v)
         end if

         call apply_worldvolume_operator_combined_checked(flow_time, x_base, p, v, apply_error, status, flow_workspace, &
                                                         intode_diagnostics)
         if (apply_error) return
         denom = dot_product(r_hat, v)
         if (.not. ieee_is_finite(denom) .or. abs(denom) <= tiny(1.0_dp)) return
         alpha = rho_new/denom
         if (.not. ieee_is_finite(alpha)) return
         s = r - alpha*v
         residual_norm = norm2(s)
         if (.not. ieee_is_finite(residual_norm)) return
         if (residual_norm <= threshold) then
            x = x + alpha*p
            iterations = iter
            error = .false.
            return
         end if

         call apply_worldvolume_operator_combined_checked(flow_time, x_base, s, t, apply_error, status, flow_workspace, &
                                                         intode_diagnostics)
         if (apply_error) return
         t_norm2 = dot_product(t, t)
         if (.not. ieee_is_finite(t_norm2) .or. t_norm2 <= tiny(1.0_dp)) return
         omega = dot_product(t, s)/t_norm2
         if (.not. ieee_is_finite(omega)) return
         x = x + alpha*p + omega*s
         r = s - omega*t
         residual_norm = norm2(r)
         iterations = iter
         if (.not. ieee_is_finite(residual_norm)) return
         if (residual_norm <= threshold) then
            error = .false.
            return
         end if
         rho_old = rho_new
      end do
   end subroutine bicgstab_solve_worldvolume_operator

   subroutine apply_worldvolume_operator_combined_checked(flow_time, x_base, w0, combined, error, status, flow_workspace, &
                                                         intode_diagnostics)
      real(dp), intent(in) :: flow_time, x_base(:), w0(:)
      real(dp), intent(out) :: combined(:)
      logical, intent(out) :: error
      integer, intent(out) :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      real(dp) :: tangent(size(w0)), normal(size(w0))
      complex(dp) :: z_dummy(size(x_base))

      call apply_worldvolume_operator_checked(flow_time, x_base, w0, z_dummy, tangent, normal, combined, error, status, &
                                             flow_workspace, intode_diagnostics)
   end subroutine apply_worldvolume_operator_combined_checked

   subroutine apply_worldvolume_operator_checked(flow_time, x_base, w0, z_out, tangent, normal, combined, error, status, &
                                                flow_workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time, x_base(:), w0(:)
      complex(dp), intent(out) :: z_out(:)
      real(dp), intent(out) :: tangent(:), normal(:), combined(:)
      logical, intent(out) :: error
      integer, intent(out) :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      z_out = cmplx(0.0_dp, 0.0_dp, dp)
      tangent = 0.0_dp
      normal = 0.0_dp
      combined = 0.0_dp
      error = .true.
      status = intode_status_unknown
      if (.not. valid_state_vector(x_base)) return
      if (.not. valid_vector(w0)) return
      if (size(w0) /= 2*size(x_base)) return
      if (size(z_out) /= size(x_base) .or. size(tangent) /= size(w0) .or. size(normal) /= size(w0) .or. &
          size(combined) /= size(w0)) return
      if (present(flow_workspace)) then
         call flow_apply_worldvolume_operator_at(flow_time, x_base, w0, z_out, tangent, normal, combined, error, status, &
                                                flow_workspace, intode_diagnostics)
      else
         call flow_apply_worldvolume_operator_at(flow_time, x_base, w0, z_out, tangent, normal, combined, error, status, &
                                                intode_diagnostics=intode_diagnostics)
      end if
      if (error) return
      if (.not. valid_vector(tangent) .or. .not. valid_vector(normal) .or. .not. valid_vector(combined) .or. &
          .not. valid_complex_vector(z_out)) then
         error = .true.
         status = intode_status_unknown
      end if
   end subroutine apply_worldvolume_operator_checked

   logical function valid_pair(a, b) result(ok)
      real(dp), intent(in) :: a(:), b(:)

      ok = size(a) > 0 .and. size(a) == size(b) .and. modulo(size(a), 2) == 0 .and. &
           all(ieee_is_finite(a)) .and. all(ieee_is_finite(b))
   end function valid_pair

   logical function same_shape4(a, b, c, d) result(ok)
      real(dp), intent(in) :: a(:), b(:), c(:), d(:)

      ok = size(a) > 0 .and. size(a) == size(b) .and. size(a) == size(c) .and. size(a) == size(d) .and. &
           modulo(size(a), 2) == 0
   end function same_shape4

   logical function valid_vector(a) result(ok)
      real(dp), intent(in) :: a(:)

      ok = size(a) > 0 .and. modulo(size(a), 2) == 0 .and. all(ieee_is_finite(a))
   end function valid_vector

   logical function valid_real_matrix(a) result(ok)
      real(dp), intent(in) :: a(:, :)

      ok = size(a, 1) > 0 .and. size(a, 2) > 0 .and. all(ieee_is_finite(a))
   end function valid_real_matrix

   logical function valid_state_vector(a) result(ok)
      real(dp), intent(in) :: a(:)

      ok = size(a) > 0 .and. all(ieee_is_finite(a))
   end function valid_state_vector

   logical function valid_complex_pair(a, b) result(ok)
      complex(dp), intent(in) :: a(:), b(:)

      ok = size(a) > 0 .and. size(a) == size(b) .and. valid_complex_vector(a) .and. valid_complex_vector(b)
   end function valid_complex_pair

   logical function valid_complex_vector(a) result(ok)
      complex(dp), intent(in) :: a(:)

      ok = size(a) > 0 .and. all(ieee_is_finite(real(a, dp))) .and. all(ieee_is_finite(aimag(a)))
   end function valid_complex_vector

   logical function valid_complex_matrix(a) result(ok)
      complex(dp), intent(in) :: a(:, :)

      ok = size(a, 1) > 0 .and. size(a, 2) > 0 .and. &
           all(ieee_is_finite(real(a, dp))) .and. all(ieee_is_finite(aimag(a)))
   end function valid_complex_matrix

end module wv_hmc_kernels

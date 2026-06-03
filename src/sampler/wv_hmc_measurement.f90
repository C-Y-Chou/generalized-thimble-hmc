module wv_hmc_measurement
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use model, only: calculate_action, ds
   use solve_flow, only: flow_workspace_t, intode_diagnostics_context_t, intode_status_unknown
   use utils, only: complex_to_real, dp, log_determinant
   use wv_hmc_kernels, only: wv_force_dense_with_jacobian, wv_force_matrix_free_at, wv_xi_from_action_gradient
   implicit none

   private
   public :: wv_measurement_factor_t, wv_weighted_observable_accumulator_t
   public :: wv_dense_alpha2, wv_dense_measurement_factor, wv_operator_alpha2, wv_operator_measurement_factor
   public :: wv_init_weighted_observable_accumulator, wv_accumulate_weighted_observables
   public :: wv_weighted_observable_estimates, wv_weighted_observable_phase_coherence

   type :: wv_measurement_factor_t
      real(dp) :: alpha2 = 0.0_dp
      real(dp) :: alpha = 0.0_dp
      real(dp) :: log_abs_jacobian = 0.0_dp
      complex(dp) :: action = cmplx(0.0_dp, 0.0_dp, dp)
      complex(dp) :: log_det_jacobian = cmplx(0.0_dp, 0.0_dp, dp)
      real(dp) :: potential_value = 0.0_dp
      complex(dp) :: phase_factor = cmplx(1.0_dp, 0.0_dp, dp)
      complex(dp) :: wv_factor = cmplx(0.0_dp, 0.0_dp, dp)
   end type wv_measurement_factor_t

   type :: wv_weighted_observable_accumulator_t
      integer :: sample_count = 0
      complex(dp) :: denominator = cmplx(0.0_dp, 0.0_dp, dp)
      real(dp) :: sum_abs_weight = 0.0_dp
      complex(dp), allocatable :: numerator(:)
   end type wv_weighted_observable_accumulator_t

contains

   subroutine wv_dense_alpha2(z, jac, alpha2, error)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: alpha2
      logical, intent(out) :: error

      complex(dp) :: grad(size(z)), xi(size(z))
      real(dp) :: xi_real(2*size(z)), force_dummy(2*size(z))

      alpha2 = 0.0_dp
      error = .true.
      if (size(z) <= 0) return
      if (size(jac, 1) /= size(z) .or. size(jac, 2) /= size(z)) return
      if (.not. valid_complex_vector(z)) return
      if (.not. valid_complex_matrix(jac)) return

      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) return
      call complex_to_real(xi, xi_real)
      call wv_force_dense_with_jacobian(xi_real, jac, 0.0_dp, force_dummy, alpha2, error)
      if (error) then
         alpha2 = 0.0_dp
         return
      end if
      if ((.not. ieee_is_finite(alpha2)) .or. alpha2 <= 0.0_dp) then
         alpha2 = 0.0_dp
         error = .true.
         return
      end if
      error = .false.
   end subroutine wv_dense_alpha2

   subroutine wv_dense_measurement_factor(z, jac, factor, error, w_value)
      complex(dp), intent(in) :: z(:), jac(:, :)
      type(wv_measurement_factor_t), intent(out) :: factor
      logical, intent(out) :: error
      real(dp), intent(in), optional :: w_value

      complex(dp) :: phase_exponent
      real(dp) :: local_w_value
      logical :: local_error

      factor = wv_measurement_factor_t()
      error = .true.
      if (size(z) <= 0) return
      if (size(jac, 1) /= size(z) .or. size(jac, 2) /= size(z)) return
      if (.not. valid_complex_vector(z)) return
      if (.not. valid_complex_matrix(jac)) return

      call wv_dense_alpha2(z, jac, factor%alpha2, local_error)
      if (local_error) return
      factor%alpha = sqrt(factor%alpha2)
      if ((.not. ieee_is_finite(factor%alpha)) .or. factor%alpha <= 0.0_dp) return

      call log_determinant(jac, factor%log_det_jacobian, local_error)
      if (local_error) return
      factor%log_abs_jacobian = real(factor%log_det_jacobian, dp)
      if (.not. ieee_is_finite(factor%log_abs_jacobian)) return

      call calculate_action(z, factor%action)
      if ((.not. ieee_is_finite(real(factor%action, dp))) .or. (.not. ieee_is_finite(aimag(factor%action)))) return

      local_w_value = 0.0_dp
      if (present(w_value)) local_w_value = w_value
      if (.not. ieee_is_finite(local_w_value)) return
      factor%potential_value = local_w_value

      phase_exponent = cmplx(0.0_dp, aimag(factor%log_det_jacobian) - aimag(factor%action), dp)
      factor%phase_factor = exp(phase_exponent)
      factor%wv_factor = factor%phase_factor/factor%alpha
      if ((.not. valid_complex_scalar(factor%phase_factor)) .or. (.not. valid_complex_scalar(factor%wv_factor))) then
         factor = wv_measurement_factor_t()
         return
      end if
      error = .false.
   end subroutine wv_dense_measurement_factor

   subroutine wv_operator_alpha2(flow_time, x_base, z, alpha2, error, status, flow_workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time, x_base(:)
      complex(dp), intent(in) :: z(:)
      real(dp), intent(out) :: alpha2
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      integer :: n, iterations, flow_status
      real(dp) :: residual_norm
      real(dp) :: xi_real(2*size(z)), force_dummy(2*size(z))
      complex(dp) :: grad(size(z)), xi(size(z))

      alpha2 = 0.0_dp
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status
      n = size(z)
      if (n <= 0) return
      if (size(x_base) /= n) return
      if (.not. ieee_is_finite(flow_time) .or. flow_time < 0.0_dp) return
      if (.not. valid_complex_vector(z)) return
      if (.not. valid_real_vector(x_base)) return

      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) return
      call complex_to_real(xi, xi_real)
      if (present(flow_workspace)) then
         call wv_force_matrix_free_at(flow_time, x_base, xi_real, 0.0_dp, force_dummy, alpha2, residual_norm, &
                                      iterations, 1.0e-10_dp, max(64, 16*n), error, flow_status, flow_workspace, &
                                      intode_diagnostics)
      else
         call wv_force_matrix_free_at(flow_time, x_base, xi_real, 0.0_dp, force_dummy, alpha2, residual_norm, &
                                      iterations, 1.0e-10_dp, max(64, 16*n), error, flow_status, &
                                      intode_diagnostics=intode_diagnostics)
      end if
      if (present(status)) status = flow_status
      if (error) then
         alpha2 = 0.0_dp
         return
      end if
      if ((.not. ieee_is_finite(alpha2)) .or. alpha2 <= 0.0_dp) then
         alpha2 = 0.0_dp
         error = .true.
         return
      end if
      error = .false.
   end subroutine wv_operator_alpha2

   subroutine wv_operator_measurement_factor(flow_time, x_base, z, jac, factor, error, status, flow_workspace, &
                                             intode_diagnostics, w_value)
      real(dp), intent(in) :: flow_time, x_base(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      type(wv_measurement_factor_t), intent(out) :: factor
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      real(dp), intent(in), optional :: w_value

      integer :: flow_status
      complex(dp) :: phase_exponent
      real(dp) :: local_w_value
      logical :: local_error

      factor = wv_measurement_factor_t()
      error = .true.
      flow_status = intode_status_unknown
      if (present(status)) status = flow_status
      if (size(z) <= 0) return
      if (size(x_base) /= size(z)) return
      if (size(jac, 1) /= size(z) .or. size(jac, 2) /= size(z)) return
      if (.not. valid_complex_vector(z)) return
      if (.not. valid_complex_matrix(jac)) return
      if (.not. valid_real_vector(x_base)) return

      if (present(flow_workspace)) then
         call wv_operator_alpha2(flow_time, x_base, z, factor%alpha2, local_error, flow_status, flow_workspace, &
                                 intode_diagnostics)
      else
         call wv_operator_alpha2(flow_time, x_base, z, factor%alpha2, local_error, flow_status, &
                                 intode_diagnostics=intode_diagnostics)
      end if
      if (present(status)) status = flow_status
      if (local_error) return
      factor%alpha = sqrt(factor%alpha2)
      if ((.not. ieee_is_finite(factor%alpha)) .or. factor%alpha <= 0.0_dp) return

      call log_determinant(jac, factor%log_det_jacobian, local_error)
      if (local_error) return
      factor%log_abs_jacobian = real(factor%log_det_jacobian, dp)
      if (.not. ieee_is_finite(factor%log_abs_jacobian)) return

      call calculate_action(z, factor%action)
      if ((.not. ieee_is_finite(real(factor%action, dp))) .or. (.not. ieee_is_finite(aimag(factor%action)))) return

      local_w_value = 0.0_dp
      if (present(w_value)) local_w_value = w_value
      if (.not. ieee_is_finite(local_w_value)) return
      factor%potential_value = local_w_value

      phase_exponent = cmplx(0.0_dp, aimag(factor%log_det_jacobian) - aimag(factor%action), dp)
      factor%phase_factor = exp(phase_exponent)
      factor%wv_factor = factor%phase_factor/factor%alpha
      if ((.not. valid_complex_scalar(factor%phase_factor)) .or. (.not. valid_complex_scalar(factor%wv_factor))) then
         factor = wv_measurement_factor_t()
         return
      end if
      error = .false.
   end subroutine wv_operator_measurement_factor

   subroutine wv_init_weighted_observable_accumulator(accumulator, observable_count, error)
      type(wv_weighted_observable_accumulator_t), intent(out) :: accumulator
      integer, intent(in) :: observable_count
      logical, intent(out) :: error

      accumulator%sample_count = 0
      accumulator%denominator = cmplx(0.0_dp, 0.0_dp, dp)
      accumulator%sum_abs_weight = 0.0_dp
      if (allocated(accumulator%numerator)) deallocate (accumulator%numerator)
      error = .true.
      if (observable_count <= 0) return
      allocate (accumulator%numerator(observable_count))
      accumulator%numerator = cmplx(0.0_dp, 0.0_dp, dp)
      error = .false.
   end subroutine wv_init_weighted_observable_accumulator

   subroutine wv_accumulate_weighted_observables(accumulator, weight, observables, error)
      type(wv_weighted_observable_accumulator_t), intent(inout) :: accumulator
      complex(dp), intent(in) :: weight, observables(:)
      logical, intent(out) :: error

      error = .true.
      if (.not. allocated(accumulator%numerator)) return
      if (size(observables) /= size(accumulator%numerator)) return
      if (.not. valid_complex_scalar(weight)) return
      if (.not. valid_complex_vector(observables)) return

      accumulator%sample_count = accumulator%sample_count + 1
      accumulator%denominator = accumulator%denominator + weight
      accumulator%sum_abs_weight = accumulator%sum_abs_weight + abs(weight)
      accumulator%numerator = accumulator%numerator + weight*observables
      if (.not. valid_complex_scalar(accumulator%denominator)) return
      if ((.not. ieee_is_finite(accumulator%sum_abs_weight)) .or. accumulator%sum_abs_weight < 0.0_dp) return
      if (.not. valid_complex_vector(accumulator%numerator)) return
      error = .false.
   end subroutine wv_accumulate_weighted_observables

   subroutine wv_weighted_observable_estimates(accumulator, estimates, error)
      type(wv_weighted_observable_accumulator_t), intent(in) :: accumulator
      complex(dp), intent(out) :: estimates(:)
      logical, intent(out) :: error

      estimates = cmplx(0.0_dp, 0.0_dp, dp)
      error = .true.
      if (.not. allocated(accumulator%numerator)) return
      if (size(estimates) /= size(accumulator%numerator)) return
      if (accumulator%sample_count <= 0) return
      if (.not. valid_complex_scalar(accumulator%denominator)) return
      if (abs(accumulator%denominator) <= tiny(1.0_dp)) return
      if (.not. valid_complex_vector(accumulator%numerator)) return

      estimates = accumulator%numerator/accumulator%denominator
      if (.not. valid_complex_vector(estimates)) then
         estimates = cmplx(0.0_dp, 0.0_dp, dp)
         return
      end if
      error = .false.
   end subroutine wv_weighted_observable_estimates

   subroutine wv_weighted_observable_phase_coherence(accumulator, coherence, error)
      type(wv_weighted_observable_accumulator_t), intent(in) :: accumulator
      real(dp), intent(out) :: coherence
      logical, intent(out) :: error

      coherence = 0.0_dp
      error = .true.
      if (accumulator%sample_count <= 0) return
      if ((.not. ieee_is_finite(accumulator%sum_abs_weight)) .or. accumulator%sum_abs_weight <= 0.0_dp) return
      if (.not. valid_complex_scalar(accumulator%denominator)) return

      coherence = abs(accumulator%denominator)/accumulator%sum_abs_weight
      if ((.not. ieee_is_finite(coherence)) .or. coherence < 0.0_dp) then
         coherence = 0.0_dp
         return
      end if
      error = .false.
   end subroutine wv_weighted_observable_phase_coherence

   logical function valid_complex_scalar(value) result(ok)
      complex(dp), intent(in) :: value

      ok = ieee_is_finite(real(value, dp)) .and. ieee_is_finite(aimag(value))
   end function valid_complex_scalar

   logical function valid_complex_vector(values) result(ok)
      complex(dp), intent(in) :: values(:)

      ok = size(values) > 0 .and. all(ieee_is_finite(real(values, dp))) .and. all(ieee_is_finite(aimag(values)))
   end function valid_complex_vector

   logical function valid_complex_matrix(values) result(ok)
      complex(dp), intent(in) :: values(:, :)

      ok = size(values, 1) > 0 .and. size(values, 2) > 0 .and. &
           all(ieee_is_finite(real(values, dp))) .and. all(ieee_is_finite(aimag(values)))
   end function valid_complex_matrix

   logical function valid_real_vector(values) result(ok)
      real(dp), intent(in) :: values(:)

      ok = size(values) > 0 .and. all(ieee_is_finite(values))
   end function valid_real_vector

end module wv_hmc_measurement

module model_stephanov
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite, ieee_quiet_nan, ieee_value
   use param_mod, only: stephanov_emit_diagnostics, stephanov_include_mu_prefactor, &
                        stephanov_mass, stephanov_mu, stephanov_n, stephanov_nf, stephanov_tau
   use utils, only: dp, log_determinant
   implicit none
   private

   external :: zgesv

   integer, parameter, public :: stephanov_observable_name_len = 64
   integer, parameter :: stephanov_required_observable_count = 2
   integer, parameter :: stephanov_diagnostic_observable_count = 5
   character(len=stephanov_observable_name_len), parameter :: stephanov_observable_names(stephanov_diagnostic_observable_count) = [ &
      character(len=stephanov_observable_name_len) :: "chiral_condensate", "number_density", &
                                                   "logdet_dirac", "phase_factor", "min_singular_ba_m2" &
   ]
   complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)

   public :: stephanov_calculate_action, stephanov_ds, stephanov_hessian, stephanov_hessian_vec, stephanov_ds_hessian_vec_batch
   public :: stephanov_observable_count, get_stephanov_observable_name, stephanov_evaluate_observables
   public :: stephanov_evaluate_observable_by_index

contains

   integer function stephanov_observable_count() result(count)
      if (stephanov_emit_diagnostics) then
         count = stephanov_diagnostic_observable_count
      else
         count = stephanov_required_observable_count
      end if
   end function stephanov_observable_count

   subroutine get_stephanov_observable_name(index, name)
      integer, intent(in) :: index
      character(len=*), intent(out) :: name

      if (index < 1 .or. index > stephanov_observable_count()) then
         name = ""
      else
         name = trim(stephanov_observable_names(index))
      end if
   end subroutine get_stephanov_observable_name

   subroutine stephanov_calculate_action(z, s)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(out) :: s

      complex(dp), allocatable :: a_mat(:, :), b_mat(:, :), dirac(:, :)
      complex(dp) :: logdet_value, quad
      logical :: logdet_error
      integer :: n_model, i, j

      call validate_stephanov_shape(z, "stephanov_calculate_action", n_model)
      if (stephanov_state_has_nonfinite(z)) then
         s = stephanov_nan()
         return
      end if
      allocate (a_mat(n_model, n_model), b_mat(n_model, n_model), dirac(2*n_model, 2*n_model))

      call build_stephanov_ab(z, n_model, a_mat, b_mat)
      call build_stephanov_dirac(a_mat, b_mat, n_model, dirac)
      call log_determinant(dirac, logdet_value, logdet_error)
      if (logdet_error) then
         s = stephanov_nan()
         return
      end if

      quad = cmplx(0.0_dp, 0.0_dp, dp)
      do j = 1, n_model
         do i = 1, n_model
            quad = quad + z(offset_x(i, j, n_model))**2 + z(offset_y(i, j, n_model))**2
         end do
      end do

      s = cmplx(real(n_model, dp), 0.0_dp, dp)*quad - cmplx(real(stephanov_nf, dp), 0.0_dp, dp)*logdet_value
      if (stephanov_include_mu_prefactor) then
         s = s - cmplx(real(n_model, dp)*stephanov_mu*stephanov_mu, 0.0_dp, dp)
      end if
   end subroutine stephanov_calculate_action

   subroutine stephanov_ds(z, grad)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(out) :: grad(:)

      complex(dp), allocatable :: a_mat(:, :), b_mat(:, :), dirac(:, :), dirac_inv(:, :)
      complex(dp) :: nf_c, n_c
      integer :: n_model, i, j

      call validate_stephanov_state(z, "stephanov_ds", n_model)
      if (size(grad) /= size(z)) then
         write (*, '(A)') "[ERROR] stephanov_ds: gradient size mismatch."
         error stop 1
      end if

      allocate (a_mat(n_model, n_model), b_mat(n_model, n_model), dirac(2*n_model, 2*n_model), &
                dirac_inv(2*n_model, 2*n_model))
      call build_stephanov_ab(z, n_model, a_mat, b_mat)
      call build_stephanov_dirac(a_mat, b_mat, n_model, dirac)
      call invert_complex_matrix(dirac, dirac_inv, "stephanov_ds")

      nf_c = cmplx(real(stephanov_nf, dp), 0.0_dp, dp)
      n_c = cmplx(real(n_model, dp), 0.0_dp, dp)
      grad = cmplx(0.0_dp, 0.0_dp, dp)
      do j = 1, n_model
         do i = 1, n_model
            grad(offset_x(i, j, n_model)) = 2.0_dp*n_c*z(offset_x(i, j, n_model)) - &
               nf_c*ci*(dirac_inv(n_model + j, i) + dirac_inv(i, n_model + j))
            grad(offset_y(i, j, n_model)) = 2.0_dp*n_c*z(offset_y(i, j, n_model)) - &
               nf_c*(dirac_inv(i, n_model + j) - dirac_inv(n_model + j, i))
         end do
      end do
   end subroutine stephanov_ds

   subroutine stephanov_hessian(z, hess)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(out) :: hess(:, :)

      complex(dp), allocatable :: basis(:), hv(:)
      integer :: n_state, col

      n_state = size(z)
      if (size(hess, 1) /= n_state .or. size(hess, 2) /= n_state) then
         write (*, '(A)') "[ERROR] stephanov_hessian: matrix size mismatch."
         error stop 1
      end if

      allocate (basis(n_state), hv(n_state))
      hess = cmplx(0.0_dp, 0.0_dp, dp)
      do col = 1, n_state
         basis = cmplx(0.0_dp, 0.0_dp, dp)
         basis(col) = cmplx(1.0_dp, 0.0_dp, dp)
         call stephanov_hessian_vec(z, basis, hv)
         hess(:, col) = hv
      end do
   end subroutine stephanov_hessian

   subroutine stephanov_hessian_vec(z, v, hv)
      complex(dp), intent(in) :: z(:), v(:)
      complex(dp), intent(out) :: hv(:)

      complex(dp), allocatable :: a_mat(:, :), b_mat(:, :), dirac(:, :), dirac_inv(:, :)
      complex(dp), allocatable :: d_dirac(:, :), work(:, :)
      complex(dp) :: nf_c, n_c, vx, vy
      integer :: n_model, i, j

      call validate_stephanov_state(z, "stephanov_hessian_vec", n_model)
      if (size(v) /= size(z) .or. size(hv) /= size(z)) then
         write (*, '(A)') "[ERROR] stephanov_hessian_vec: vector size mismatch."
         error stop 1
      end if

      allocate (a_mat(n_model, n_model), b_mat(n_model, n_model), dirac(2*n_model, 2*n_model), &
                dirac_inv(2*n_model, 2*n_model), d_dirac(2*n_model, 2*n_model), work(2*n_model, 2*n_model))
      call build_stephanov_ab(z, n_model, a_mat, b_mat)
      call build_stephanov_dirac(a_mat, b_mat, n_model, dirac)
      call invert_complex_matrix(dirac, dirac_inv, "stephanov_hessian_vec")

      d_dirac = cmplx(0.0_dp, 0.0_dp, dp)
      do j = 1, n_model
         do i = 1, n_model
            vx = v(offset_x(i, j, n_model))
            vy = v(offset_y(i, j, n_model))
            d_dirac(i, n_model + j) = ci*(vx + ci*vy)
            d_dirac(n_model + j, i) = ci*(vx - ci*vy)
         end do
      end do

      work = matmul(matmul(dirac_inv, d_dirac), dirac_inv)
      nf_c = cmplx(real(stephanov_nf, dp), 0.0_dp, dp)
      n_c = cmplx(real(n_model, dp), 0.0_dp, dp)
      hv = cmplx(0.0_dp, 0.0_dp, dp)
      do j = 1, n_model
         do i = 1, n_model
            hv(offset_x(i, j, n_model)) = 2.0_dp*n_c*v(offset_x(i, j, n_model)) + &
               nf_c*ci*(work(n_model + j, i) + work(i, n_model + j))
            hv(offset_y(i, j, n_model)) = 2.0_dp*n_c*v(offset_y(i, j, n_model)) + &
               nf_c*(work(i, n_model + j) - work(n_model + j, i))
         end do
      end do
   end subroutine stephanov_hessian_vec

   subroutine stephanov_ds_hessian_vec_batch(z, vectors, grad, hvectors)
      complex(dp), intent(in) :: z(:), vectors(:, :)
      complex(dp), intent(out) :: grad(:), hvectors(:, :)

      complex(dp), allocatable :: a_mat(:, :), b_mat(:, :), dirac(:, :), dirac_inv(:, :)
      complex(dp), allocatable :: d_dirac(:, :), work(:, :)
      complex(dp) :: nf_c, n_c, vx, vy
      integer :: n_model, n_state, i, j, col

      call validate_stephanov_state(z, "stephanov_ds_hessian_vec_batch", n_model)
      n_state = size(z)
      if (size(grad) /= n_state .or. size(vectors, 1) /= n_state .or. size(hvectors, 1) /= n_state .or. &
          size(hvectors, 2) /= size(vectors, 2)) then
         write (*, '(A)') "[ERROR] stephanov_ds_hessian_vec_batch: size mismatch."
         error stop 1
      end if

      allocate (a_mat(n_model, n_model), b_mat(n_model, n_model), dirac(2*n_model, 2*n_model), &
                dirac_inv(2*n_model, 2*n_model), d_dirac(2*n_model, 2*n_model), work(2*n_model, 2*n_model))
      call build_stephanov_ab(z, n_model, a_mat, b_mat)
      call build_stephanov_dirac(a_mat, b_mat, n_model, dirac)
      call invert_complex_matrix(dirac, dirac_inv, "stephanov_ds_hessian_vec_batch")

      nf_c = cmplx(real(stephanov_nf, dp), 0.0_dp, dp)
      n_c = cmplx(real(n_model, dp), 0.0_dp, dp)
      grad = cmplx(0.0_dp, 0.0_dp, dp)
      do j = 1, n_model
         do i = 1, n_model
            grad(offset_x(i, j, n_model)) = 2.0_dp*n_c*z(offset_x(i, j, n_model)) - &
               nf_c*ci*(dirac_inv(n_model + j, i) + dirac_inv(i, n_model + j))
            grad(offset_y(i, j, n_model)) = 2.0_dp*n_c*z(offset_y(i, j, n_model)) - &
               nf_c*(dirac_inv(i, n_model + j) - dirac_inv(n_model + j, i))
         end do
      end do

      hvectors = cmplx(0.0_dp, 0.0_dp, dp)
      do col = 1, size(vectors, 2)
         d_dirac = cmplx(0.0_dp, 0.0_dp, dp)
         do j = 1, n_model
            do i = 1, n_model
               vx = vectors(offset_x(i, j, n_model), col)
               vy = vectors(offset_y(i, j, n_model), col)
               d_dirac(i, n_model + j) = ci*(vx + ci*vy)
               d_dirac(n_model + j, i) = ci*(vx - ci*vy)
            end do
         end do

         work = matmul(matmul(dirac_inv, d_dirac), dirac_inv)
         do j = 1, n_model
            do i = 1, n_model
               hvectors(offset_x(i, j, n_model), col) = 2.0_dp*n_c*vectors(offset_x(i, j, n_model), col) + &
                  nf_c*ci*(work(n_model + j, i) + work(i, n_model + j))
               hvectors(offset_y(i, j, n_model), col) = 2.0_dp*n_c*vectors(offset_y(i, j, n_model), col) + &
                  nf_c*(work(i, n_model + j) - work(n_model + j, i))
            end do
         end do
      end do
   end subroutine stephanov_ds_hessian_vec_batch

   subroutine stephanov_evaluate_observables(z, observables)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(out) :: observables(:)

      complex(dp), allocatable :: a_mat(:, :), b_mat(:, :), q_mat(:, :), q_inv(:, :), a_plus_b(:, :)
      complex(dp), allocatable :: dirac(:, :)
      complex(dp) :: logdet_value, action_value, trace_k, trace_density
      logical :: logdet_error
      integer :: expected_count, n_model, i

      call validate_stephanov_state(z, "stephanov_evaluate_observables", n_model)
      expected_count = stephanov_observable_count()
      if (size(observables) /= expected_count) then
         write (*, '(A,I0,A,I0,A)') "[ERROR] stephanov_evaluate_observables: expected ", &
            expected_count, " values, got ", size(observables), "."
         error stop 1
      end if

      allocate (a_mat(n_model, n_model), b_mat(n_model, n_model), q_mat(n_model, n_model), &
                q_inv(n_model, n_model), a_plus_b(n_model, n_model))
      call build_stephanov_ab(z, n_model, a_mat, b_mat)
      q_mat = matmul(b_mat, a_mat)
      do i = 1, n_model
         q_mat(i, i) = q_mat(i, i) + cmplx(stephanov_mass*stephanov_mass, 0.0_dp, dp)
      end do
      call invert_complex_matrix(q_mat, q_inv, "stephanov_evaluate_observables")

      trace_k = trace_complex(q_inv)
      a_plus_b = a_mat + b_mat
      trace_density = trace_complex(matmul(q_inv, a_plus_b))

      observables = cmplx(0.0_dp, 0.0_dp, dp)
      observables(1) = cmplx(stephanov_mass/real(n_model, dp), 0.0_dp, dp)*trace_k
      observables(2) = cmplx(stephanov_mu, 0.0_dp, dp) - &
         ci/cmplx(2.0_dp*real(n_model, dp), 0.0_dp, dp)*trace_density

      if (expected_count >= stephanov_diagnostic_observable_count) then
         allocate (dirac(2*n_model, 2*n_model))
         call build_stephanov_dirac(a_mat, b_mat, n_model, dirac)
         call log_determinant(dirac, logdet_value, logdet_error)
         if (logdet_error) then
            write (*, '(A)') "[ERROR] stephanov_evaluate_observables: log det failed."
            error stop 1
         end if
         call stephanov_calculate_action(z, action_value)
         observables(3) = logdet_value
         observables(4) = exp(-ci*cmplx(aimag(action_value), 0.0_dp, dp))
         observables(5) = cmplx(min_singular_value_complex(q_mat), 0.0_dp, dp)
      end if
   end subroutine stephanov_evaluate_observables

   subroutine stephanov_evaluate_observable_by_index(z, index, observable)
      complex(dp), intent(in) :: z(:)
      integer, intent(in) :: index
      complex(dp), intent(out) :: observable

      complex(dp), allocatable :: a_mat(:, :), b_mat(:, :), q_mat(:, :), q_inv(:, :), a_plus_b(:, :)
      complex(dp), allocatable :: dirac(:, :)
      complex(dp) :: logdet_value, action_value, trace_k, trace_density
      logical :: logdet_error
      integer :: expected_count, n_model, i

      call validate_stephanov_state(z, "stephanov_evaluate_observable_by_index", n_model)
      expected_count = stephanov_observable_count()
      if (index < 1 .or. index > expected_count) then
         write (*, '(A,I0)') "[ERROR] stephanov_evaluate_observable_by_index: invalid observable index=", index
         error stop 1
      end if

      select case (index)
      case (1, 2)
         allocate (a_mat(n_model, n_model), b_mat(n_model, n_model), q_mat(n_model, n_model), &
                   q_inv(n_model, n_model), a_plus_b(n_model, n_model))
         call build_stephanov_ab(z, n_model, a_mat, b_mat)
         q_mat = matmul(b_mat, a_mat)
         do i = 1, n_model
            q_mat(i, i) = q_mat(i, i) + cmplx(stephanov_mass*stephanov_mass, 0.0_dp, dp)
         end do
         call invert_complex_matrix(q_mat, q_inv, "stephanov_evaluate_observable_by_index")
         if (index == 1) then
            trace_k = trace_complex(q_inv)
            observable = cmplx(stephanov_mass/real(n_model, dp), 0.0_dp, dp)*trace_k
         else
            a_plus_b = a_mat + b_mat
            trace_density = trace_complex(matmul(q_inv, a_plus_b))
            observable = cmplx(stephanov_mu, 0.0_dp, dp) - &
               ci/cmplx(2.0_dp*real(n_model, dp), 0.0_dp, dp)*trace_density
         end if
      case (3)
         allocate (a_mat(n_model, n_model), b_mat(n_model, n_model), dirac(2*n_model, 2*n_model))
         call build_stephanov_ab(z, n_model, a_mat, b_mat)
         call build_stephanov_dirac(a_mat, b_mat, n_model, dirac)
         call log_determinant(dirac, logdet_value, logdet_error)
         if (logdet_error) then
            write (*, '(A)') "[ERROR] stephanov_evaluate_observable_by_index: log det failed."
            error stop 1
         end if
         observable = logdet_value
      case (4)
         call stephanov_calculate_action(z, action_value)
         observable = exp(-ci*cmplx(aimag(action_value), 0.0_dp, dp))
      case (5)
         allocate (a_mat(n_model, n_model), b_mat(n_model, n_model), q_mat(n_model, n_model))
         call build_stephanov_ab(z, n_model, a_mat, b_mat)
         q_mat = matmul(b_mat, a_mat)
         do i = 1, n_model
            q_mat(i, i) = q_mat(i, i) + cmplx(stephanov_mass*stephanov_mass, 0.0_dp, dp)
         end do
         observable = cmplx(min_singular_value_complex(q_mat), 0.0_dp, dp)
      end select
   end subroutine stephanov_evaluate_observable_by_index

   subroutine validate_stephanov_state(z, caller, n_model)
      complex(dp), intent(in) :: z(:)
      character(len=*), intent(in) :: caller
      integer, intent(out) :: n_model

      call validate_stephanov_shape(z, caller, n_model)
      if (stephanov_state_has_nonfinite(z)) then
         write (*, '(A,A,A)') "[ERROR] ", trim(caller), ": z contains nonfinite values."
         error stop 1
      end if
   end subroutine validate_stephanov_state

   subroutine validate_stephanov_shape(z, caller, n_model)
      complex(dp), intent(in) :: z(:)
      character(len=*), intent(in) :: caller
      integer, intent(out) :: n_model
      integer :: expected_size

      n_model = stephanov_n
      expected_size = 2*n_model*n_model
      if (n_model < 2 .or. mod(n_model, 2) /= 0) then
         write (*, '(A,A,A,I0)') "[ERROR] ", trim(caller), ": stephanov_n must be even and >=2; got ", n_model
         error stop 1
      end if
      if (size(z) /= expected_size) then
         write (*, '(A,A,A,I0,A,I0,A)') "[ERROR] ", trim(caller), ": expected z size ", expected_size, &
            ", got ", size(z), "."
         error stop 1
      end if
   end subroutine validate_stephanov_shape

   logical function stephanov_state_has_nonfinite(z) result(has_nonfinite)
      complex(dp), intent(in) :: z(:)

      has_nonfinite = any(.not. ieee_is_finite(real(z, dp))) .or. any(.not. ieee_is_finite(aimag(z)))
   end function stephanov_state_has_nonfinite

   complex(dp) function stephanov_nan() result(value)
      value = cmplx(ieee_value(0.0_dp, ieee_quiet_nan), ieee_value(0.0_dp, ieee_quiet_nan), dp)
   end function stephanov_nan

   subroutine build_stephanov_ab(z, n_model, a_mat, b_mat)
      complex(dp), intent(in) :: z(:)
      integer, intent(in) :: n_model
      complex(dp), intent(out) :: a_mat(:, :), b_mat(:, :)

      complex(dp), allocatable :: c_diag(:)
      complex(dp) :: zx, zy
      integer :: i, j

      if (size(a_mat, 1) /= n_model .or. size(a_mat, 2) /= n_model .or. &
          size(b_mat, 1) /= n_model .or. size(b_mat, 2) /= n_model) then
         write (*, '(A)') "[ERROR] build_stephanov_ab: matrix size mismatch."
         error stop 1
      end if

      allocate (c_diag(n_model))
      call build_stephanov_c_diag(n_model, c_diag)
      a_mat = cmplx(0.0_dp, 0.0_dp, dp)
      b_mat = cmplx(0.0_dp, 0.0_dp, dp)
      do j = 1, n_model
         do i = 1, n_model
            zx = z(offset_x(i, j, n_model))
            zy = z(offset_y(i, j, n_model))
            a_mat(i, j) = zx + ci*zy
            b_mat(j, i) = zx - ci*zy
         end do
      end do
      do i = 1, n_model
         a_mat(i, i) = a_mat(i, i) + c_diag(i)
         b_mat(i, i) = b_mat(i, i) + c_diag(i)
      end do
   end subroutine build_stephanov_ab

   subroutine build_stephanov_c_diag(n_model, c_diag)
      integer, intent(in) :: n_model
      complex(dp), intent(out) :: c_diag(:)
      integer :: i, half_n

      if (size(c_diag) /= n_model) then
         write (*, '(A)') "[ERROR] build_stephanov_c_diag: vector size mismatch."
         error stop 1
      end if
      half_n = n_model/2
      do i = 1, n_model
         if (i <= half_n) then
            c_diag(i) = cmplx(stephanov_tau, -stephanov_mu, dp)
         else
            c_diag(i) = cmplx(-stephanov_tau, -stephanov_mu, dp)
         end if
      end do
   end subroutine build_stephanov_c_diag

   subroutine build_stephanov_dirac(a_mat, b_mat, n_model, dirac)
      complex(dp), intent(in) :: a_mat(:, :), b_mat(:, :)
      integer, intent(in) :: n_model
      complex(dp), intent(out) :: dirac(:, :)
      integer :: i

      if (size(dirac, 1) /= 2*n_model .or. size(dirac, 2) /= 2*n_model) then
         write (*, '(A)') "[ERROR] build_stephanov_dirac: matrix size mismatch."
         error stop 1
      end if
      dirac = cmplx(0.0_dp, 0.0_dp, dp)
      do i = 1, n_model
         dirac(i, i) = cmplx(stephanov_mass, 0.0_dp, dp)
         dirac(n_model + i, n_model + i) = cmplx(stephanov_mass, 0.0_dp, dp)
      end do
      dirac(1:n_model, n_model + 1:2*n_model) = ci*a_mat
      dirac(n_model + 1:2*n_model, 1:n_model) = ci*b_mat
   end subroutine build_stephanov_dirac

   subroutine invert_complex_matrix(matrix, inverse, caller)
      complex(dp), intent(in) :: matrix(:, :)
      complex(dp), intent(out) :: inverse(:, :)
      character(len=*), intent(in) :: caller

      complex(dp), allocatable :: factor(:, :)
      integer, allocatable :: ipiv(:)
      integer :: n_mat, i, info

      n_mat = size(matrix, 1)
      if (size(matrix, 2) /= n_mat .or. size(inverse, 1) /= n_mat .or. size(inverse, 2) /= n_mat) then
         write (*, '(A,A,A)') "[ERROR] ", trim(caller), ": invert_complex_matrix size mismatch."
         error stop 1
      end if

      allocate (factor(n_mat, n_mat), ipiv(n_mat))
      factor = matrix
      inverse = cmplx(0.0_dp, 0.0_dp, dp)
      do i = 1, n_mat
         inverse(i, i) = cmplx(1.0_dp, 0.0_dp, dp)
      end do
      call zgesv(n_mat, n_mat, factor, n_mat, ipiv, inverse, n_mat, info)
      if (info /= 0) then
         write (*, '(A,A,A,I0)') "[ERROR] ", trim(caller), ": complex solve failed, info=", info
         error stop 1
      end if
   end subroutine invert_complex_matrix

   complex(dp) function trace_complex(matrix) result(trace_value)
      complex(dp), intent(in) :: matrix(:, :)
      integer :: i, n_mat

      n_mat = size(matrix, 1)
      if (size(matrix, 2) /= n_mat) then
         write (*, '(A)') "[ERROR] trace_complex: matrix must be square."
         error stop 1
      end if
      trace_value = cmplx(0.0_dp, 0.0_dp, dp)
      do i = 1, n_mat
         trace_value = trace_value + matrix(i, i)
      end do
   end function trace_complex

   real(dp) function min_singular_value_complex(matrix) result(sigma_min)
      complex(dp), intent(in) :: matrix(:, :)

      real(dp), allocatable :: real_block(:, :), gram(:, :)
      real(dp) :: min_eval
      integer :: n_mat, dim, i, j

      n_mat = size(matrix, 1)
      if (size(matrix, 2) /= n_mat) then
         write (*, '(A)') "[ERROR] min_singular_value_complex: matrix must be square."
         error stop 1
      end if

      dim = 2*n_mat
      allocate (real_block(dim, dim), gram(dim, dim))
      real_block = 0.0_dp
      do j = 1, n_mat
         do i = 1, n_mat
            real_block(i, j) = real(matrix(i, j), dp)
            real_block(i, n_mat + j) = -aimag(matrix(i, j))
            real_block(n_mat + i, j) = aimag(matrix(i, j))
            real_block(n_mat + i, n_mat + j) = real(matrix(i, j), dp)
         end do
      end do
      gram = matmul(transpose(real_block), real_block)
      call jacobi_min_eigenvalue_symmetric(gram, min_eval)
      sigma_min = sqrt(max(0.0_dp, min_eval))
   end function min_singular_value_complex

   subroutine jacobi_min_eigenvalue_symmetric(matrix, min_eval)
      real(dp), intent(inout) :: matrix(:, :)
      real(dp), intent(out) :: min_eval

      real(dp) :: app, aqq, apq, tau, t, c, s, tmp_p, tmp_q
      real(dp) :: max_offdiag, scale
      integer :: n_mat, p, q, i, iter, max_iter

      n_mat = size(matrix, 1)
      if (size(matrix, 2) /= n_mat) then
         write (*, '(A)') "[ERROR] jacobi_min_eigenvalue_symmetric: matrix must be square."
         error stop 1
      end if

      max_iter = max(64, 50*n_mat*n_mat)
      do iter = 1, max_iter
         max_offdiag = 0.0_dp
         p = 1
         q = min(2, n_mat)
         do i = 1, n_mat - 1
            call find_row_max_offdiag(matrix, i, i + 1, n_mat, max_offdiag, p, q)
         end do
         scale = max(1.0_dp, maxval(abs(matrix)))
         if (max_offdiag <= 1.0e-12_dp*scale) exit

         apq = matrix(p, q)
         if (apq == 0.0_dp) cycle
         app = matrix(p, p)
         aqq = matrix(q, q)
         tau = (aqq - app)/(2.0_dp*apq)
         if (tau >= 0.0_dp) then
            t = 1.0_dp/(tau + sqrt(1.0_dp + tau*tau))
         else
            t = -1.0_dp/(-tau + sqrt(1.0_dp + tau*tau))
         end if
         c = 1.0_dp/sqrt(1.0_dp + t*t)
         s = t*c

         do i = 1, n_mat
            if (i /= p .and. i /= q) then
               tmp_p = matrix(i, p)
               tmp_q = matrix(i, q)
               matrix(i, p) = c*tmp_p - s*tmp_q
               matrix(p, i) = matrix(i, p)
               matrix(i, q) = s*tmp_p + c*tmp_q
               matrix(q, i) = matrix(i, q)
            end if
         end do
         matrix(p, p) = c*c*app - 2.0_dp*s*c*apq + s*s*aqq
         matrix(q, q) = s*s*app + 2.0_dp*s*c*apq + c*c*aqq
         matrix(p, q) = 0.0_dp
         matrix(q, p) = 0.0_dp
      end do

      min_eval = matrix(1, 1)
      do i = 2, n_mat
         min_eval = min(min_eval, matrix(i, i))
      end do
   end subroutine jacobi_min_eigenvalue_symmetric

   subroutine find_row_max_offdiag(matrix, row, first_col, last_col, current_max, p, q)
      real(dp), intent(in) :: matrix(:, :)
      integer, intent(in) :: row, first_col, last_col
      real(dp), intent(inout) :: current_max
      integer, intent(inout) :: p, q

      real(dp) :: value
      integer :: col

      do col = first_col, last_col
         value = abs(matrix(row, col))
         if (value > current_max) then
            current_max = value
            p = row
            q = col
         end if
      end do
   end subroutine find_row_max_offdiag

   pure integer function offset_x(i, j, n_model) result(index)
      integer, intent(in) :: i, j, n_model
      index = (j - 1)*n_model + i
   end function offset_x

   pure integer function offset_y(i, j, n_model) result(index)
      integer, intent(in) :: i, j, n_model
      index = n_model*n_model + (j - 1)*n_model + i
   end function offset_y

end module model_stephanov

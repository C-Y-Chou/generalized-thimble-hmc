module utils
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use, intrinsic :: iso_fortran_env, only: real64, int64
   integer, parameter :: dp = real64
   integer, parameter :: X_FLOW_TIME_INDEX = 1
   external :: zgetrf
contains

   !-----------------------------------------------------------------------
   !> Monotonic wall-clock time in seconds.
   !-----------------------------------------------------------------------
   function wall_time_seconds() result(t)
      real(dp) :: t
      integer(int64) :: count, rate, count_max

      call system_clock(count, rate, count_max)
      if (rate > 0_int64) then
         t = real(count, dp)/real(rate, dp)
      else
         call cpu_time(t)
      end if
   end function wall_time_seconds

   !-----------------------------------------------------------------------
   !> Convert an (n x n) complex matrix cmat to a (2n x 2n) real matrix rmat.
   !  If cmat(i,j) = a + i*b, then:
   !    rmat(2i-1, 2j-1) = a
   !    rmat(2i-1, 2j  ) = -b
   !    rmat(2i,   2j-1) =  b
   !    rmat(2i,   2j  ) =  a
   !-----------------------------------------------------------------------
   subroutine map_to_real_mat(cmat, rmat)
      implicit none
      ! Inputs
      complex(dp), intent(in)  :: cmat(:, :)
      ! Outputs
      real(dp), intent(out) :: rmat(:, :)

      ! Locals
      integer :: n, i, j

      rmat = 0.0_dp
      n = size(cmat, 1)
      if (size(cmat, 2) /= n) then
         write (*, *) "Error(map_to_real_mat): cmat is not square."
         return
      end if

      if (size(rmat, 1) /= 2*n .or. size(rmat, 2) /= 2*n) then
         write (*, *) "Error(map_to_real_mat): rmat must be (2n x 2n)."
         return
      end if

      do i = 1, n
         do j = 1, n
            rmat(2*i - 1, 2*j - 1) = real(cmat(i, j), dp)
            rmat(2*i - 1, 2*j) = -aimag(cmat(i, j))
            rmat(2*i, 2*j - 1) = aimag(cmat(i, j))
            rmat(2*i, 2*j) = real(cmat(i, j), dp)
         end do
      end do
   end subroutine map_to_real_mat

   !-----------------------------------------------------------------------
   !> Convert a (2n x 2n) real matrix rmat (from map_to_real_mat) back to
   !  an (n x n) complex matrix cmat.
   !-----------------------------------------------------------------------
   subroutine map_to_complex_mat(rmat, cmat)
      implicit none
      ! Inputs
      real(dp), intent(in)  :: rmat(:, :)
      ! Outputs
      complex(dp), intent(out) :: cmat(:, :)

      ! Locals
      integer :: n, i, j

      cmat = cmplx(0.0_dp, 0.0_dp, dp)
      n = size(cmat, 1)
      if (size(cmat, 2) /= n) then
         write (*, *) "Error(map_to_complex_mat): cmat is not square."
         return
      end if
      if (size(rmat, 1) /= 2*n .or. size(rmat, 2) /= 2*n) then
         write (*, *) "Error(map_to_complex_mat): rmat must be (2n x 2n)."
         return
      end if

      do i = 1, n
         do j = 1, n
            cmat(i, j) = cmplx(rmat(2*i - 1, 2*j - 1), &
                               rmat(2*i, 2*j - 1), dp)
         end do
      end do
   end subroutine map_to_complex_mat

   !-----------------------------------------------------------------------
   !> Convert a complex vector c of length n to a real vector r of length 2n,
   !  in interleaved form: [Re(c(1)), Im(c(1)), Re(c(2)), Im(c(2)), ...]
   !-----------------------------------------------------------------------
   subroutine complex_to_real(c, r)
      implicit none
      ! Inputs
      complex(dp), intent(in)  :: c(:)
      ! Outputs
      real(dp), intent(out) :: r(:)

      ! Locals
      integer :: i, n

      r = 0.0_dp
      n = size(c)
      if (size(r) /= 2*n) then
         write (*, *) "Error(complex_to_real): r must have length 2*n."
         return
      end if

      do i = 1, n
         r(2*i - 1) = real(c(i), dp)
         r(2*i) = aimag(c(i))
      end do
   end subroutine complex_to_real

   !-----------------------------------------------------------------------
   !> Convert a real vector r of length 2n (interleaved real/im parts) to
   !  a complex vector c of length n.
   !-----------------------------------------------------------------------
   subroutine real_to_complex(r, c)
      implicit none
      ! Inputs
      real(dp), intent(in)  :: r(:)
      ! Outputs
      complex(dp), intent(out) :: c(:)

      ! Locals
      integer :: i, n

      c = cmplx(0.0_dp, 0.0_dp, dp)
      n = size(c)
      if (size(r) /= 2*n) then
         write (*, *) "Error(real_to_complex): r must have length 2*n."
         return
      end if

      do i = 1, n
         c(i) = cmplx(r(2*i - 1), r(2*i), dp)
      end do
   end subroutine real_to_complex

   !-----------------------------------------------------------------------
   !> Flatten an (n x n) complex matrix mat into a real vector vec of
   !  length 2*n*n, in row-major order:
   !  [Re(mat(1,1)), Im(mat(1,1)), Re(mat(1,2)), Im(mat(1,2)), ...]
   !-----------------------------------------------------------------------
   subroutine map_to_real(mat, vec)
      implicit none
      ! Inputs
      complex(dp), intent(in)  :: mat(:, :)
      ! Outputs
      real(dp), intent(out) :: vec(:)

      ! Locals
      integer :: i, j, n

      vec = 0.0_dp
      n = size(mat, 1)
      if (size(mat, 2) /= n) then
         write (*, *) "Error(map_to_real): mat is not square."
         return
      end if
      if (size(vec) /= 2*n*n) then
         write (*, *) "Error(map_to_real): vec must have length=2*n*n."
         return
      end if

      do i = 1, n
         do j = 1, n
            vec(2*((i - 1)*n + j) - 1) = real(mat(i, j), dp)
            vec(2*((i - 1)*n + j)) = aimag(mat(i, j))
         end do
      end do
   end subroutine map_to_real

   !-----------------------------------------------------------------------
   !> Zero out the imaginary parts in a (2n x 2n) real-block matrix
   !  produced by map_to_real_mat, effectively forcing it to be purely real.
   !-----------------------------------------------------------------------
   subroutine real_mat(mat)
      implicit none
      real(dp), intent(inout) :: mat(:, :)

      integer :: i, j, n

      n = size(mat, 1)/2
      if (size(mat, 2) /= 2*n) then
         write (*, *) "Error(real_mat): mat must be (2n x 2n)."
         return
      end if

      do i = 1, n
         do j = 1, n
            mat(2*i - 1, 2*j) = 0.0_dp
            mat(2*i, 2*j - 1) = 0.0_dp
         end do
      end do
   end subroutine real_mat

   !-----------------------------------------------------------------------
   !> Extract the imaginary part from a (2n x 2n) real-block matrix
   !  (originally from map_to_real_mat) and store it in the "real" slots.
   !  Replaces imaginary slots with 0. This is a trick to handle e.g.
   !  matrix( a + i b ) => ( b ) in the real part, zero out old a.
   !-----------------------------------------------------------------------
   subroutine im_mat(mat)
      implicit none
      real(dp), intent(inout) :: mat(:, :)

      integer :: i, j, n

      n = size(mat, 1)/2
      if (size(mat, 2) /= 2*n) then
         write (*, *) "Error(im_mat): mat must be (2n x 2n)."
         return
      end if

      do i = 1, n
         do j = 1, n
            ! Transfer the imaginary part to real slot
            mat(2*i - 1, 2*j - 1) = mat(2*i - 1, 2*j)
            mat(2*i, 2*j) = mat(2*i, 2*j - 1)
            ! Zero out the old imaginary positions
            mat(2*i - 1, 2*j) = 0.0_dp
            mat(2*i, 2*j - 1) = 0.0_dp
         end do
      end do
   end subroutine im_mat

   !-----------------------------------------------------------------------
   !> Force a real vector (2n) representing interleaved complex data
   !  [a1 b1 a2 b2 ...] to have zero imaginary parts => [a1 0 a2 0 ...].
   !-----------------------------------------------------------------------
   subroutine real_vec(vec)
      implicit none
      real(dp), intent(inout) :: vec(:)

      integer :: i, n

      n = size(vec)/2
      do i = 1, n
         vec(2*i) = 0.0_dp
      end do
   end subroutine real_vec

   !-----------------------------------------------------------------------
   !> Reconstruct an (n x n) complex matrix mat from a real vector vec
   !  of length 2*n*n, which was presumably produced by map_to_real().
   !-----------------------------------------------------------------------
   subroutine map_to_complex(vec, mat)
      implicit none
      real(dp), intent(in)  :: vec(:)
      complex(dp), intent(out) :: mat(:, :)

      integer :: i, j, n

      mat = cmplx(0.0_dp, 0.0_dp, dp)
      n = size(mat, 1)
      if (size(mat, 2) /= n) then
         write (*, *) "Error(map_to_complex): mat is not square."
         return
      end if
      if (size(vec) /= 2*n*n) then
         write (*, *) "Error(map_to_complex): vec must have length 2*n*n."
         return
      end if

      do i = 1, n
         do j = 1, n
            mat(i, j) = cmplx(vec(2*((i - 1)*n + j) - 1), &
                              vec(2*((i - 1)*n + j)), dp)
         end do
      end do
   end subroutine map_to_complex

   !-----------------------------------------------------------------------
   !> Factorial function using recursion. Factorial(0)=1, etc.
   !-----------------------------------------------------------------------
   recursive function factorial(n) result(fact)
      integer, intent(in) :: n
      real(dp)            :: fact

      if (n < 0) then
         print *, "Error: Factorial is undefined for negative n."
         fact = 0.0_dp
      else if (n == 0) then
         fact = 1.0_dp
      else
         fact = real(n, dp)*factorial(n - 1)
      end if
   end function factorial

   !-----------------------------------------------------------------------
   !> Validate that x contains [flow_time, state_seed...].
   !-----------------------------------------------------------------------
   subroutine assert_x_state_shape(x, caller)
      real(dp), intent(in) :: x(:)
      character(len=*), intent(in) :: caller

      if (size(x) < 2) then
         write (*, *) "Error(", trim(caller), "): x must contain flow_time and at least one state entry."
         error stop 1
      end if
   end subroutine assert_x_state_shape

   !-----------------------------------------------------------------------
   !> Number of real state entries (excluding flow time).
   !-----------------------------------------------------------------------
   function x_seed_size(x) result(n_seed)
      real(dp), intent(in) :: x(:)
      integer :: n_seed

      call assert_x_state_shape(x, "x_seed_size")
      n_seed = size(x) - 1
   end function x_seed_size

   !-----------------------------------------------------------------------
   !> Accessors for flow time kept in x(1).
   !-----------------------------------------------------------------------
   function x_get_flow_time(x) result(flow_time)
      real(dp), intent(in) :: x(:)
      real(dp) :: flow_time

      call assert_x_state_shape(x, "x_get_flow_time")
      flow_time = x(X_FLOW_TIME_INDEX)
   end function x_get_flow_time

   subroutine x_set_flow_time(x, flow_time)
      real(dp), intent(inout) :: x(:)
      real(dp), intent(in) :: flow_time

      call assert_x_state_shape(x, "x_set_flow_time")
      x(X_FLOW_TIME_INDEX) = flow_time
   end subroutine x_set_flow_time

   !-----------------------------------------------------------------------
   !> Extract/insert real seed part x(2:).
   !-----------------------------------------------------------------------
   subroutine x_get_seed_real(x, x_seed)
      real(dp), intent(in) :: x(:)
      real(dp), intent(out) :: x_seed(:)

      call assert_x_state_shape(x, "x_get_seed_real")
      if (size(x_seed) /= size(x) - 1) then
         write (*, *) "Error(x_get_seed_real): size mismatch."
         error stop 1
      end if
      x_seed = x(2:)
   end subroutine x_get_seed_real

   subroutine x_set_seed_real(x, x_seed)
      real(dp), intent(inout) :: x(:)
      real(dp), intent(in) :: x_seed(:)

      call assert_x_state_shape(x, "x_set_seed_real")
      if (size(x_seed) /= size(x) - 1) then
         write (*, *) "Error(x_set_seed_real): size mismatch."
         error stop 1
      end if
      x(2:) = x_seed
   end subroutine x_set_seed_real

   !-----------------------------------------------------------------------
   !> Extract/insert complex seed view for z.
   !-----------------------------------------------------------------------
   subroutine x_get_seed_complex(x, z_seed)
      real(dp), intent(in) :: x(:)
      complex(dp), intent(out) :: z_seed(:)

      call assert_x_state_shape(x, "x_get_seed_complex")
      if (size(z_seed) /= size(x) - 1) then
         write (*, *) "Error(x_get_seed_complex): size mismatch."
         error stop 1
      end if
      z_seed = cmplx(x(2:), 0.0_dp, dp)
   end subroutine x_get_seed_complex

   subroutine x_set_seed_from_complex(x, z_seed)
      real(dp), intent(inout) :: x(:)
      complex(dp), intent(in) :: z_seed(:)

      call assert_x_state_shape(x, "x_set_seed_from_complex")
      if (size(z_seed) /= size(x) - 1) then
         write (*, *) "Error(x_set_seed_from_complex): size mismatch."
         error stop 1
      end if
      x(2:) = real(z_seed, dp)
   end subroutine x_set_seed_from_complex

   subroutine read_x_history(filename, x_history)
      implicit none

      character(len=*), intent(in) :: filename
      real(real64), intent(out) :: x_history(:)

      integer :: ios, unit, max_size
      real(real64), allocatable :: buffer(:)
      real(real64) :: temp
      integer :: i

      ! Open the file in stream, unformatted mode (same as writing)
      unit = 23
      inquire (iolength=max_size) temp  ! Get record size
      open (unit=unit, file=filename, access='stream', form='unformatted', status='old', iostat=ios)
      if (ios /= 0) then
         write (*, *) "Error(read_x_history): cannot open", filename
         return
      end if

      read (unit) x_history

      close (unit)
   end subroutine read_x_history

   !-----------------------------------------------------------------------
   !> Compute log(det(matrix)) for a complex (n x n) matrix via LU (zgetrf).
   !  Returns principal-branch complex log-determinant:
   !    Re(log_det) = log(|det(matrix)|)
   !    Im(log_det) = arg(det(matrix))
   !  including the permutation sign from row interchanges.
   !-----------------------------------------------------------------------
   subroutine log_determinant(matrix, log_det, error_flag)
      implicit none

      ! Inputs
      complex(dp), intent(in) :: matrix(:, :)

      ! Outputs
      complex(dp), intent(out) :: log_det
      logical, intent(out) :: error_flag

      ! Locals
      integer :: n, lda, info, i
      integer, allocatable :: ipiv(:)
      complex(dp), allocatable :: lu_matrix(:, :)
      integer :: sign
      error_flag = .false.
      sign = 1
      log_det = cmplx(0.0_dp, 0.0_dp, dp)

      n = size(matrix, 1)
      if (n /= size(matrix, 2)) then
         write (*, *) "Error(log_determinant): matrix must be square."
         error_flag = .true.
         return
      end if
      if (any(.not. ieee_is_finite(real(matrix, dp))) .or. any(.not. ieee_is_finite(aimag(matrix)))) then
         write (*, *) "Error(log_determinant): matrix contains nonfinite values."
         error_flag = .true.
         return
      end if
      lda = n

      allocate (ipiv(n), lu_matrix(n, n))
      lu_matrix = matrix

      ! Perform LU decomposition
      call zgetrf(n, n, lu_matrix, lda, ipiv, info)
      if (info /= 0) then
         write (*, *) "Error(log_determinant): LU decomposition failed, info=", info
         error_flag = .true.
         deallocate (ipiv, lu_matrix)
         return
      end if

      do i = 1, n
         log_det = log_det + log(lu_matrix(i, i))
         if (ipiv(i) /= i) sign = -sign
      end do
      log_det = log_det + log(sign*cmplx(1, 0, dp))

      deallocate (ipiv, lu_matrix)
   end subroutine log_determinant

   !-----------------------------------------------------------------
   ! Function: outer_product
   ! Purpose : Compute the outer product of vectors a and b,
   !           i.e. result(i,j) = a(i)*b(j)
   !-----------------------------------------------------------------
   function outer_product(a, b) result(mat)
      implicit none
      real(dp), intent(in) :: a(:), b(:)
      real(dp), allocatable :: mat(:, :)
      integer :: n, m, i, j

      n = size(a)
      m = size(b)
      allocate (mat(n, m))

      do i = 1, n
         do j = 1, m
            mat(i, j) = a(i)*b(j)
         end do
      end do
   end function outer_product
end module utils

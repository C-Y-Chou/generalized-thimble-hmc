! Lightweight BLAS/LAPACK fallbacks for environments without system libs.
! These routines provide the subset used by this project.

subroutine dgetrf(m, n, a, lda, ipiv, info)
   use, intrinsic :: iso_fortran_env, only: real64
   implicit none
   integer, intent(in) :: m, n, lda
   integer, intent(out) :: ipiv(*)
   integer, intent(out) :: info
   real(real64), intent(inout) :: a(lda, *)
   integer :: i, j, k, minmn, piv
   real(real64) :: maxv, tmp, pivv

   info = 0
   minmn = min(m, n)
   if (m < 0 .or. n < 0 .or. lda < max(1, m)) then
      info = -1
      return
   end if

   do k = 1, minmn
      piv = k
      maxv = abs(a(k, k))
      do i = k + 1, m
         if (abs(a(i, k)) > maxv) then
            maxv = abs(a(i, k))
            piv = i
         end if
      end do
      ipiv(k) = piv

      if (piv /= k) then
         do j = 1, n
            tmp = a(k, j)
            a(k, j) = a(piv, j)
            a(piv, j) = tmp
         end do
      end if

      pivv = a(k, k)
      if (abs(pivv) <= tiny(1.0_real64)) then
         if (info == 0) info = k
         cycle
      end if

      if (k < m) then
         do i = k + 1, m
            a(i, k) = a(i, k)/pivv
            if (k < n) then
               do j = k + 1, n
                  a(i, j) = a(i, j) - a(i, k)*a(k, j)
               end do
            end if
         end do
      end if
   end do
end subroutine dgetrf

subroutine zgetrf(m, n, a, lda, ipiv, info)
   use, intrinsic :: iso_fortran_env, only: real64
   implicit none
   integer, intent(in) :: m, n, lda
   integer, intent(out) :: ipiv(*)
   integer, intent(out) :: info
   complex(real64), intent(inout) :: a(lda, *)
   integer :: i, j, k, minmn, piv
   real(real64) :: maxv
   complex(real64) :: tmp, pivv

   info = 0
   minmn = min(m, n)
   if (m < 0 .or. n < 0 .or. lda < max(1, m)) then
      info = -1
      return
   end if

   do k = 1, minmn
      piv = k
      maxv = abs(a(k, k))
      do i = k + 1, m
         if (abs(a(i, k)) > maxv) then
            maxv = abs(a(i, k))
            piv = i
         end if
      end do
      ipiv(k) = piv

      if (piv /= k) then
         do j = 1, n
            tmp = a(k, j)
            a(k, j) = a(piv, j)
            a(piv, j) = tmp
         end do
      end if

      pivv = a(k, k)
      if (abs(pivv) <= tiny(1.0_real64)) then
         if (info == 0) info = k
         cycle
      end if

      if (k < m) then
         do i = k + 1, m
            a(i, k) = a(i, k)/pivv
            if (k < n) then
               do j = k + 1, n
                  a(i, j) = a(i, j) - a(i, k)*a(k, j)
               end do
            end if
         end do
      end if
   end do
end subroutine zgetrf

subroutine dgetrs(trans, n, nrhs, a, lda, ipiv, b, ldb, info)
   use, intrinsic :: iso_fortran_env, only: real64
   implicit none
   character(len=*), intent(in) :: trans
   integer, intent(in) :: n, nrhs, lda, ldb
   integer, intent(in) :: ipiv(*)
   integer, intent(out) :: info
   real(real64), intent(in) :: a(lda, *)
   real(real64), intent(inout) :: b(*)
   integer :: i, j, k, piv
   integer :: idx_i, idx_p, idx_k
   real(real64) :: tmp, sumv, diagv

   info = 0
   if (n < 0 .or. nrhs < 0 .or. lda < max(1, n) .or. ldb < max(1, n)) then
      info = -1
      return
   end if
   if (trans(1:1) /= 'N' .and. trans(1:1) /= 'n') then
      info = -2
      return
   end if

   do k = 1, n
      piv = ipiv(k)
      if (piv /= k) then
         do j = 1, nrhs
            idx_i = (j - 1)*ldb + k
            idx_p = (j - 1)*ldb + piv
            tmp = b(idx_i)
            b(idx_i) = b(idx_p)
            b(idx_p) = tmp
         end do
      end if
   end do

   do i = 2, n
      do j = 1, nrhs
         idx_i = (j - 1)*ldb + i
         sumv = b(idx_i)
         do k = 1, i - 1
            idx_k = (j - 1)*ldb + k
            sumv = sumv - a(i, k)*b(idx_k)
         end do
         b(idx_i) = sumv
      end do
   end do

   do i = n, 1, -1
      diagv = a(i, i)
      if (abs(diagv) <= tiny(1.0_real64)) then
         info = i
         return
      end if
      do j = 1, nrhs
         idx_i = (j - 1)*ldb + i
         sumv = b(idx_i)
         do k = i + 1, n
            idx_k = (j - 1)*ldb + k
            sumv = sumv - a(i, k)*b(idx_k)
         end do
         b(idx_i) = sumv/diagv
      end do
   end do
end subroutine dgetrs

subroutine dgesv(n, nrhs, a, lda, ipiv, b, ldb, info)
   use, intrinsic :: iso_fortran_env, only: real64
   implicit none
   integer, intent(in) :: n, nrhs, lda, ldb
   integer, intent(out) :: ipiv(*)
   integer, intent(out) :: info
   real(real64), intent(inout) :: a(lda, *)
   real(real64), intent(inout) :: b(*)

   call dgetrf(n, n, a, lda, ipiv, info)
   if (info /= 0) return
   call dgetrs('N', n, nrhs, a, lda, ipiv, b, ldb, info)
end subroutine dgesv

subroutine zgesv(n, nrhs, a, lda, ipiv, b, ldb, info)
   use, intrinsic :: iso_fortran_env, only: real64
   implicit none
   integer, intent(in) :: n, nrhs, lda, ldb
   integer, intent(out) :: ipiv(*)
   integer, intent(out) :: info
   complex(real64), intent(inout) :: a(lda, *)
   complex(real64), intent(inout) :: b(*)
   integer :: i, j, k, piv
   integer :: idx_i, idx_p, idx_k
   complex(real64) :: tmp, sumv, diagv

   call zgetrf(n, n, a, lda, ipiv, info)
   if (info /= 0) return

   do k = 1, n
      piv = ipiv(k)
      if (piv /= k) then
         do j = 1, nrhs
            idx_i = (j - 1)*ldb + k
            idx_p = (j - 1)*ldb + piv
            tmp = b(idx_i)
            b(idx_i) = b(idx_p)
            b(idx_p) = tmp
         end do
      end if
   end do

   do i = 2, n
      do j = 1, nrhs
         idx_i = (j - 1)*ldb + i
         sumv = b(idx_i)
         do k = 1, i - 1
            idx_k = (j - 1)*ldb + k
            sumv = sumv - a(i, k)*b(idx_k)
         end do
         b(idx_i) = sumv
      end do
   end do

   do i = n, 1, -1
      diagv = a(i, i)
      if (abs(diagv) <= tiny(1.0_real64)) then
         info = i
         return
      end if
      do j = 1, nrhs
         idx_i = (j - 1)*ldb + i
         sumv = b(idx_i)
         do k = i + 1, n
            idx_k = (j - 1)*ldb + k
            sumv = sumv - a(i, k)*b(idx_k)
         end do
         b(idx_i) = sumv/diagv
      end do
   end do
   info = 0
end subroutine zgesv

subroutine dgemv(trans, m, n, alpha, a, lda, x, incx, beta, y, incy)
   use, intrinsic :: iso_fortran_env, only: real64
   implicit none
   character(len=*), intent(in) :: trans
   integer, intent(in) :: m, n, lda, incx, incy
   real(real64), intent(in) :: alpha, beta
   real(real64), intent(in) :: a(lda, *)
   real(real64), intent(in) :: x(*)
   real(real64), intent(inout) :: y(*)
   integer :: i, j, ix, iy, jx
   real(real64) :: sumv
   logical :: do_trans

   if (m <= 0 .or. n <= 0) return
   if (incx <= 0 .or. incy <= 0) return

   do_trans = (trans(1:1) == 'T' .or. trans(1:1) == 't' .or. trans(1:1) == 'C' .or. trans(1:1) == 'c')

   if (.not. do_trans) then
      iy = 1
      do i = 1, m
         sumv = 0.0_real64
         jx = 1
         do j = 1, n
            sumv = sumv + a(i, j)*x(jx)
            jx = jx + incx
         end do
         y(iy) = alpha*sumv + beta*y(iy)
         iy = iy + incy
      end do
   else
      iy = 1
      do i = 1, n
         sumv = 0.0_real64
         ix = 1
         do j = 1, m
            sumv = sumv + a(j, i)*x(ix)
            ix = ix + incx
         end do
         y(iy) = alpha*sumv + beta*y(iy)
         iy = iy + incy
      end do
   end if
end subroutine dgemv


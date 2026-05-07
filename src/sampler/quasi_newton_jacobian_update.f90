module quasi_newton_jacobian_update_mod
   use utils
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   implicit none
   external :: dgesv

   real(dp), allocatable, save :: update_mat_fact(:, :), update_rhs(:)
   integer, allocatable, save :: update_ipiv(:)
   real(dp), parameter :: theta_dev_max = 0.5_dp
   real(dp), parameter :: sm_denom_floor = 1.0e-3_dp

contains

   subroutine broyden_rank1_update(Bm, dx, y)
      implicit none
      real(dp), intent(inout) :: Bm(:, :)
      real(dp), intent(in) :: dx(:), y(:)

      integer :: n
      real(dp) :: denom, theta_k
      real(dp), allocatable :: update_vec(:)

      n = size(dx)
      if (size(y) /= n .or. size(Bm, 1) /= n .or. size(Bm, 2) /= n) return
      allocate (update_vec(n))

      denom = dot_product(dx, dx)
      if (denom <= tiny(1.0_dp)) then
         deallocate (update_vec)
         return
      end if

      update_vec = y - matmul(Bm, dx)
      theta_k = safeguarded_theta(Bm, dx, update_vec, denom)
      if (theta_k <= tiny(1.0_dp)) then
         deallocate (update_vec)
         return
      end if
      Bm = Bm + theta_k*outer_product(update_vec, dx)/denom
      deallocate (update_vec)
   end subroutine broyden_rank1_update

   real(dp) function safeguarded_theta(Bm, s, u, s_norm2) result(theta_k)
      implicit none
      real(dp), intent(in) :: Bm(:, :), s(:), u(:), s_norm2

      integer :: n, i, info, ridge_idx
      real(dp) :: alpha, vtbw
      real(dp) :: theta_lo, theta_hi, c_lo, c_hi
      real(dp) :: base_shift, ridge

      n = size(s)
      theta_k = 1.0_dp
      if (size(u) /= n .or. size(Bm, 1) /= n .or. size(Bm, 2) /= n) then
         theta_k = 0.0_dp
         return
      end if
      if (s_norm2 <= tiny(1.0_dp)) then
         theta_k = 0.0_dp
         return
      end if

      call ensure_real_mat_workspace(update_mat_fact, n, n)
      call ensure_real_vec_workspace(update_rhs, n)
      call ensure_int_workspace(update_ipiv, n)

      update_mat_fact = Bm
      update_rhs = u
      call dgesv(n, 1, update_mat_fact, n, update_ipiv, update_rhs, n, info)
      if (info /= 0) then
         base_shift = max(1.0e-12_dp, sqrt(epsilon(1.0_dp))*maxval(abs(Bm)))
         do ridge_idx = 1, 3
            ridge = base_shift*10.0_dp**real(ridge_idx - 1, dp)
            update_mat_fact = Bm
            do i = 1, n
               update_mat_fact(i, i) = update_mat_fact(i, i) + ridge
            end do
            update_rhs = u
            call dgesv(n, 1, update_mat_fact, n, update_ipiv, update_rhs, n, info)
            if (info == 0) exit
         end do
      end if

      if (info /= 0) then
         theta_k = 0.0_dp
         return
      end if

      vtbw = dot_product(s, update_rhs)/s_norm2
      alpha = vtbw
      if (.not. ieee_is_finite(alpha)) then
         theta_k = 0.0_dp
         return
      end if

      if (abs(1.0_dp + alpha) >= sm_denom_floor) then
         theta_k = 1.0_dp
         return
      end if

      theta_lo = max(0.0_dp, 1.0_dp - theta_dev_max)
      theta_hi = 1.0_dp + theta_dev_max
      c_lo = abs(1.0_dp + theta_lo*alpha)
      c_hi = abs(1.0_dp + theta_hi*alpha)
      if (c_hi >= c_lo) then
         theta_k = theta_hi
      else
         theta_k = theta_lo
      end if

      if (abs(1.0_dp + theta_k*alpha) < sm_denom_floor) then
         theta_k = 0.0_dp
      end if
   end function safeguarded_theta

   subroutine ensure_int_workspace(buf, n_need)
      implicit none
      integer, allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_int_workspace

   subroutine ensure_real_mat_workspace(buf, nr, nc)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:, :)
      integer, intent(in) :: nr, nc

      if (.not. allocated(buf)) then
         allocate (buf(nr, nc))
      elseif (size(buf, 1) < nr .or. size(buf, 2) < nc) then
         deallocate (buf)
         allocate (buf(nr, nc))
      end if
   end subroutine ensure_real_mat_workspace

   subroutine ensure_real_vec_workspace(buf, n_need)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_real_vec_workspace

end module quasi_newton_jacobian_update_mod

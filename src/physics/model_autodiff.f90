module model_autodiff
   use utils, only: dp
   implicit none

   type :: ad2_t
      complex(dp) :: val = cmplx(0.0_dp, 0.0_dp, dp)
      complex(dp), allocatable :: grad(:)
      complex(dp), allocatable :: hess(:, :)
   end type ad2_t

   type :: ad_hvp_t
      complex(dp) :: val = cmplx(0.0_dp, 0.0_dp, dp)
      complex(dp), allocatable :: grad(:)
      complex(dp) :: dot = cmplx(0.0_dp, 0.0_dp, dp)
      complex(dp), allocatable :: hv(:)
   end type ad_hvp_t

   interface operator(+)
      module procedure ad_add_ad
      module procedure ad_add_c
      module procedure c_add_ad
      module procedure hvp_add_hvp
      module procedure hvp_add_c
      module procedure c_add_hvp
   end interface

   interface operator(-)
      module procedure ad_sub_ad
      module procedure ad_sub_c
      module procedure c_sub_ad
      module procedure ad_uminus
      module procedure hvp_sub_hvp
      module procedure hvp_sub_c
      module procedure c_sub_hvp
      module procedure hvp_uminus
   end interface

   interface operator(*)
      module procedure ad_mul_ad
      module procedure ad_mul_c
      module procedure c_mul_ad
      module procedure hvp_mul_hvp
      module procedure hvp_mul_c
      module procedure c_mul_hvp
   end interface

   interface operator(/)
      module procedure ad_div_ad
      module procedure ad_div_c
      module procedure c_div_ad
      module procedure hvp_div_hvp
      module procedure hvp_div_c
      module procedure c_div_hvp
   end interface

   interface operator(**)
      module procedure ad_pow_int
      module procedure hvp_pow_int
   end interface

   interface log
      module procedure ad_log
      module procedure hvp_log
   end interface

   interface exp
      module procedure ad_exp
      module procedure hvp_exp
   end interface

contains

   subroutine evaluate_action_ad(z, alpha, beta, action, grad, hess)
      implicit none
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: action
      complex(dp), intent(out), optional :: grad(:)
      complex(dp), intent(out), optional :: hess(:, :)

      type(ad2_t) :: total
      type(ad2_t), allocatable :: z_ad(:)
      integer :: i, n

      n = size(z)
      if (present(grad)) then
         if (size(grad) /= n) then
            write (*, '(A)') "[ERROR] evaluate_action_ad: grad has invalid size."
            error stop 1
         end if
      end if
      if (present(hess)) then
         if (size(hess, 1) /= n .or. size(hess, 2) /= n) then
            write (*, '(A)') "[ERROR] evaluate_action_ad: hess has invalid size."
            error stop 1
         end if
      end if

      allocate (z_ad(n))
      do i = 1, n
         z_ad(i) = ad_var(z(i), n, i)
      end do
      call evaluate_action_ad2_kernel(z_ad, alpha, beta, total)

      action = total%val
      if (present(grad)) grad = total%grad
      if (present(hess)) hess = total%hess
   end subroutine evaluate_action_ad

   subroutine evaluate_hessian_vec_ad(z, alpha, beta, vec, hv)
      implicit none
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(in) :: vec(:)
      complex(dp), intent(out) :: hv(:)

      type(ad_hvp_t) :: total
      type(ad_hvp_t), allocatable :: z_ad(:)
      integer :: i, n

      n = size(z)
      if (size(vec) /= n .or. size(hv) /= n) then
         write (*, '(A)') "[ERROR] evaluate_hessian_vec_ad: vector size mismatch."
         error stop 1
      end if

      allocate (z_ad(n))
      do i = 1, n
         z_ad(i) = hvp_var(z(i), n, i, vec(i))
      end do
      call evaluate_action_hvp_kernel(z_ad, alpha, beta, total)

      hv = total%hv
   end subroutine evaluate_hessian_vec_ad

   subroutine evaluate_action_ad2_kernel(z, alpha, beta, s)
      implicit none
      type(ad2_t), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      type(ad2_t), intent(out) :: s
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
      type(ad2_t) :: zero
      integer :: i, n

      n = size(z)
      zero = ad_const(cmplx(0.0_dp, 0.0_dp, dp), n)
      include "model_action_body.inc"
   end subroutine evaluate_action_ad2_kernel

   subroutine evaluate_action_hvp_kernel(z, alpha, beta, s)
      implicit none
      type(ad_hvp_t), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      type(ad_hvp_t), intent(out) :: s
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
      type(ad_hvp_t) :: zero
      integer :: i, n

      n = size(z)
      zero = hvp_const(cmplx(0.0_dp, 0.0_dp, dp), n)
      include "model_action_body.inc"
   end subroutine evaluate_action_hvp_kernel

   function ad_const(value, n) result(a)
      implicit none
      complex(dp), intent(in) :: value
      integer, intent(in) :: n
      type(ad2_t) :: a

      call ad_allocate(a, n)
      a%val = value
   end function ad_const

   function ad_var(value, n, idx) result(a)
      implicit none
      complex(dp), intent(in) :: value
      integer, intent(in) :: n, idx
      type(ad2_t) :: a

      call ad_allocate(a, n)
      a%val = value
      a%grad(idx) = cmplx(1.0_dp, 0.0_dp, dp)
   end function ad_var

   subroutine ad_allocate(a, n)
      implicit none
      type(ad2_t), intent(inout) :: a
      integer, intent(in) :: n

      if (allocated(a%grad)) deallocate (a%grad)
      if (allocated(a%hess)) deallocate (a%hess)
      allocate (a%grad(n), a%hess(n, n))
      a%grad = cmplx(0.0_dp, 0.0_dp, dp)
      a%hess = cmplx(0.0_dp, 0.0_dp, dp)
      a%val = cmplx(0.0_dp, 0.0_dp, dp)
   end subroutine ad_allocate

   function ad_clone(a) result(r)
      implicit none
      type(ad2_t), intent(in) :: a
      type(ad2_t) :: r
      integer :: n

      n = size(a%grad)
      call ad_allocate(r, n)
      r%val = a%val
      r%grad = a%grad
      r%hess = a%hess
   end function ad_clone

   subroutine add_outer(mat, g_left, g_right, scale)
      implicit none
      complex(dp), intent(inout) :: mat(:, :)
      complex(dp), intent(in) :: g_left(:), g_right(:)
      complex(dp), intent(in) :: scale
      integer :: i, j, n

      n = size(g_left)
      do i = 1, n
         do j = 1, n
            mat(i, j) = mat(i, j) + scale*g_left(i)*g_right(j)
         end do
      end do
   end subroutine add_outer

   function ad_add_ad(a, b) result(r)
      implicit none
      type(ad2_t), intent(in) :: a, b
      type(ad2_t) :: r

      r = ad_clone(a)
      r%val = a%val + b%val
      r%grad = a%grad + b%grad
      r%hess = a%hess + b%hess
   end function ad_add_ad

   function ad_add_c(a, b) result(r)
      implicit none
      type(ad2_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(ad2_t) :: r

      r = ad_clone(a)
      r%val = a%val + b
   end function ad_add_c

   function c_add_ad(a, b) result(r)
      implicit none
      complex(dp), intent(in) :: a
      type(ad2_t), intent(in) :: b
      type(ad2_t) :: r

      r = ad_add_c(b, a)
   end function c_add_ad

   function ad_sub_ad(a, b) result(r)
      implicit none
      type(ad2_t), intent(in) :: a, b
      type(ad2_t) :: r

      r = ad_clone(a)
      r%val = a%val - b%val
      r%grad = a%grad - b%grad
      r%hess = a%hess - b%hess
   end function ad_sub_ad

   function ad_sub_c(a, b) result(r)
      implicit none
      type(ad2_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(ad2_t) :: r

      r = ad_clone(a)
      r%val = a%val - b
   end function ad_sub_c

   function c_sub_ad(a, b) result(r)
      implicit none
      complex(dp), intent(in) :: a
      type(ad2_t), intent(in) :: b
      type(ad2_t) :: r

      r = ad_clone(b)
      r%val = a - b%val
      r%grad = -b%grad
      r%hess = -b%hess
   end function c_sub_ad

   function ad_uminus(a) result(r)
      implicit none
      type(ad2_t), intent(in) :: a
      type(ad2_t) :: r

      r = ad_clone(a)
      r%val = -a%val
      r%grad = -a%grad
      r%hess = -a%hess
   end function ad_uminus

   function ad_mul_ad(a, b) result(r)
      implicit none
      type(ad2_t), intent(in) :: a, b
      type(ad2_t) :: r
      complex(dp) :: av, bv

      r = ad_clone(a)
      av = a%val
      bv = b%val

      r%val = av*bv
      r%grad = a%grad*bv + av*b%grad
      r%hess = a%hess*bv + av*b%hess
      call add_outer(r%hess, a%grad, b%grad, cmplx(1.0_dp, 0.0_dp, dp))
      call add_outer(r%hess, b%grad, a%grad, cmplx(1.0_dp, 0.0_dp, dp))
   end function ad_mul_ad

   function ad_mul_c(a, b) result(r)
      implicit none
      type(ad2_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(ad2_t) :: r

      r = ad_clone(a)
      r%val = a%val*b
      r%grad = a%grad*b
      r%hess = a%hess*b
   end function ad_mul_c

   function c_mul_ad(a, b) result(r)
      implicit none
      complex(dp), intent(in) :: a
      type(ad2_t), intent(in) :: b
      type(ad2_t) :: r

      r = ad_mul_c(b, a)
   end function c_mul_ad

   function ad_recip(a) result(r)
      implicit none
      type(ad2_t), intent(in) :: a
      type(ad2_t) :: r
      complex(dp) :: inv1, inv2, inv3

      r = ad_clone(a)
      inv1 = 1.0_dp/a%val
      inv2 = inv1*inv1
      inv3 = inv2*inv1

      r%val = inv1
      r%grad = -a%grad*inv2
      r%hess = -a%hess*inv2
      call add_outer(r%hess, a%grad, a%grad, cmplx(2.0_dp, 0.0_dp, dp)*inv3)
   end function ad_recip

   function ad_div_ad(a, b) result(r)
      implicit none
      type(ad2_t), intent(in) :: a, b
      type(ad2_t) :: r

      r = ad_mul_ad(a, ad_recip(b))
   end function ad_div_ad

   function ad_div_c(a, b) result(r)
      implicit none
      type(ad2_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(ad2_t) :: r

      r = ad_clone(a)
      r%val = a%val/b
      r%grad = a%grad/b
      r%hess = a%hess/b
   end function ad_div_c

   function c_div_ad(a, b) result(r)
      implicit none
      complex(dp), intent(in) :: a
      type(ad2_t), intent(in) :: b
      type(ad2_t) :: r

      r = ad_mul_c(ad_recip(b), a)
   end function c_div_ad

   recursive function ad_pow_int(a, p) result(r)
      implicit none
      type(ad2_t), intent(in) :: a
      integer, intent(in) :: p
      type(ad2_t) :: r
      complex(dp) :: a_pow, a_pow_m1, a_pow_m2
      complex(dp) :: cp, cpp

      if (p == 0) then
         r = ad_const(cmplx(1.0_dp, 0.0_dp, dp), size(a%grad))
         return
      end if

      if (p < 0) then
         r = ad_pow_int(ad_recip(a), -p)
         return
      end if

      if (p == 1) then
         r = ad_clone(a)
         return
      end if

      r = ad_clone(a)
      cp = cmplx(real(p, dp), 0.0_dp, dp)
      cpp = cmplx(real(p*(p - 1), dp), 0.0_dp, dp)
      a_pow = a%val**p
      a_pow_m1 = a%val**(p - 1)
      a_pow_m2 = a%val**(p - 2)

      r%val = a_pow
      r%grad = cp*a_pow_m1*a%grad
      r%hess = cp*a_pow_m1*a%hess
      call add_outer(r%hess, a%grad, a%grad, cpp*a_pow_m2)
   end function ad_pow_int

   function ad_log(a) result(r)
      implicit none
      type(ad2_t), intent(in) :: a
      type(ad2_t) :: r
      complex(dp) :: inv1, inv2

      r = ad_clone(a)
      inv1 = 1.0_dp/a%val
      inv2 = inv1*inv1

      r%val = log(a%val)
      r%grad = a%grad*inv1
      r%hess = a%hess*inv1
      call add_outer(r%hess, a%grad, a%grad, -inv2)
   end function ad_log

   function ad_exp(a) result(r)
      implicit none
      type(ad2_t), intent(in) :: a
      type(ad2_t) :: r
      complex(dp) :: ev

      r = ad_clone(a)
      ev = exp(a%val)

      r%val = ev
      r%grad = ev*a%grad
      r%hess = ev*a%hess
      call add_outer(r%hess, a%grad, a%grad, ev)
   end function ad_exp

   function hvp_const(value, n) result(a)
      implicit none
      complex(dp), intent(in) :: value
      integer, intent(in) :: n
      type(ad_hvp_t) :: a

      call hvp_allocate(a, n)
      a%val = value
   end function hvp_const

   function hvp_var(value, n, idx, seed) result(a)
      implicit none
      complex(dp), intent(in) :: value
      complex(dp), intent(in) :: seed
      integer, intent(in) :: n, idx
      type(ad_hvp_t) :: a

      call hvp_allocate(a, n)
      a%val = value
      a%grad(idx) = cmplx(1.0_dp, 0.0_dp, dp)
      a%dot = seed
   end function hvp_var

   subroutine hvp_allocate(a, n)
      implicit none
      type(ad_hvp_t), intent(inout) :: a
      integer, intent(in) :: n

      if (allocated(a%grad)) deallocate (a%grad)
      if (allocated(a%hv)) deallocate (a%hv)
      allocate (a%grad(n), a%hv(n))
      a%val = cmplx(0.0_dp, 0.0_dp, dp)
      a%grad = cmplx(0.0_dp, 0.0_dp, dp)
      a%dot = cmplx(0.0_dp, 0.0_dp, dp)
      a%hv = cmplx(0.0_dp, 0.0_dp, dp)
   end subroutine hvp_allocate

   function hvp_clone(a) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a
      type(ad_hvp_t) :: r
      integer :: n

      n = size(a%grad)
      call hvp_allocate(r, n)
      r%val = a%val
      r%grad = a%grad
      r%dot = a%dot
      r%hv = a%hv
   end function hvp_clone

   function hvp_add_hvp(a, b) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a, b
      type(ad_hvp_t) :: r

      r = hvp_clone(a)
      r%val = a%val + b%val
      r%grad = a%grad + b%grad
      r%dot = a%dot + b%dot
      r%hv = a%hv + b%hv
   end function hvp_add_hvp

   function hvp_add_c(a, b) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(ad_hvp_t) :: r

      r = hvp_clone(a)
      r%val = a%val + b
   end function hvp_add_c

   function c_add_hvp(a, b) result(r)
      implicit none
      complex(dp), intent(in) :: a
      type(ad_hvp_t), intent(in) :: b
      type(ad_hvp_t) :: r

      r = hvp_add_c(b, a)
   end function c_add_hvp

   function hvp_sub_hvp(a, b) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a, b
      type(ad_hvp_t) :: r

      r = hvp_clone(a)
      r%val = a%val - b%val
      r%grad = a%grad - b%grad
      r%dot = a%dot - b%dot
      r%hv = a%hv - b%hv
   end function hvp_sub_hvp

   function hvp_sub_c(a, b) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(ad_hvp_t) :: r

      r = hvp_clone(a)
      r%val = a%val - b
   end function hvp_sub_c

   function c_sub_hvp(a, b) result(r)
      implicit none
      complex(dp), intent(in) :: a
      type(ad_hvp_t), intent(in) :: b
      type(ad_hvp_t) :: r

      r = hvp_clone(b)
      r%val = a - b%val
      r%grad = -b%grad
      r%dot = -b%dot
      r%hv = -b%hv
   end function c_sub_hvp

   function hvp_uminus(a) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a
      type(ad_hvp_t) :: r

      r = hvp_clone(a)
      r%val = -a%val
      r%grad = -a%grad
      r%dot = -a%dot
      r%hv = -a%hv
   end function hvp_uminus

   function hvp_mul_hvp(a, b) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a, b
      type(ad_hvp_t) :: r
      complex(dp) :: av, bv, adot, bdot

      r = hvp_clone(a)
      av = a%val
      bv = b%val
      adot = a%dot
      bdot = b%dot

      r%val = av*bv
      r%grad = a%grad*bv + av*b%grad
      r%dot = adot*bv + av*bdot
      r%hv = a%hv*bv + av*b%hv + adot*b%grad + bdot*a%grad
   end function hvp_mul_hvp

   function hvp_mul_c(a, b) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(ad_hvp_t) :: r

      r = hvp_clone(a)
      r%val = a%val*b
      r%grad = a%grad*b
      r%dot = a%dot*b
      r%hv = a%hv*b
   end function hvp_mul_c

   function c_mul_hvp(a, b) result(r)
      implicit none
      complex(dp), intent(in) :: a
      type(ad_hvp_t), intent(in) :: b
      type(ad_hvp_t) :: r

      r = hvp_mul_c(b, a)
   end function c_mul_hvp

   function hvp_recip(a) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a
      type(ad_hvp_t) :: r
      complex(dp) :: inv1, inv2, inv3

      r = hvp_clone(a)
      inv1 = 1.0_dp/a%val
      inv2 = inv1*inv1
      inv3 = inv2*inv1

      r%val = inv1
      r%grad = -a%grad*inv2
      r%dot = -a%dot*inv2
      r%hv = -a%hv*inv2 + (cmplx(2.0_dp, 0.0_dp, dp)*a%dot*inv3)*a%grad
   end function hvp_recip

   function hvp_div_hvp(a, b) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a, b
      type(ad_hvp_t) :: r

      r = hvp_mul_hvp(a, hvp_recip(b))
   end function hvp_div_hvp

   function hvp_div_c(a, b) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(ad_hvp_t) :: r

      r = hvp_clone(a)
      r%val = a%val/b
      r%grad = a%grad/b
      r%dot = a%dot/b
      r%hv = a%hv/b
   end function hvp_div_c

   function c_div_hvp(a, b) result(r)
      implicit none
      complex(dp), intent(in) :: a
      type(ad_hvp_t), intent(in) :: b
      type(ad_hvp_t) :: r

      r = hvp_mul_c(hvp_recip(b), a)
   end function c_div_hvp

   recursive function hvp_pow_int(a, p) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a
      integer, intent(in) :: p
      type(ad_hvp_t) :: r
      complex(dp) :: a_pow, a_pow_m1, a_pow_m2
      complex(dp) :: cp, cpp

      if (p == 0) then
         r = hvp_const(cmplx(1.0_dp, 0.0_dp, dp), size(a%grad))
         return
      end if

      if (p < 0) then
         r = hvp_pow_int(hvp_recip(a), -p)
         return
      end if

      if (p == 1) then
         r = hvp_clone(a)
         return
      end if

      r = hvp_clone(a)
      cp = cmplx(real(p, dp), 0.0_dp, dp)
      cpp = cmplx(real(p*(p - 1), dp), 0.0_dp, dp)
      a_pow = a%val**p
      a_pow_m1 = a%val**(p - 1)
      a_pow_m2 = a%val**(p - 2)

      r%val = a_pow
      r%grad = cp*a_pow_m1*a%grad
      r%dot = cp*a_pow_m1*a%dot
      r%hv = cp*a_pow_m1*a%hv + cpp*a_pow_m2*a%dot*a%grad
   end function hvp_pow_int

   function hvp_log(a) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a
      type(ad_hvp_t) :: r
      complex(dp) :: inv1, inv2

      r = hvp_clone(a)
      inv1 = 1.0_dp/a%val
      inv2 = inv1*inv1

      r%val = log(a%val)
      r%grad = a%grad*inv1
      r%dot = a%dot*inv1
      r%hv = a%hv*inv1 - (a%dot*inv2)*a%grad
   end function hvp_log

   function hvp_exp(a) result(r)
      implicit none
      type(ad_hvp_t), intent(in) :: a
      type(ad_hvp_t) :: r
      complex(dp) :: ev

      r = hvp_clone(a)
      ev = exp(a%val)

      r%val = ev
      r%grad = ev*a%grad
      r%dot = ev*a%dot
      r%hv = ev*a%hv + (ev*a%dot)*a%grad
   end function hvp_exp

end module model_autodiff

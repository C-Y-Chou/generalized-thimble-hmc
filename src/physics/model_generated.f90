! This file is auto-generated. Do not edit manually.
! Source action body: src/physics/model_action_body.inc
! Backend: tape-generic
module model_generated
   use utils, only: dp
   use model_tape_ad, only: rev_t, tape_begin, tape_input, tape_const, tape_set_inputs, &
                            tape_forward_values, tape_grad, tape_hvp, &
                            operator(+), operator(-), operator(*), operator(/), operator(**), log, exp
   implicit none
   logical, save :: tape_ready = .false.
   logical, save :: tape_point_ready = .false.
   integer, save :: tape_n = 0
   integer, save :: tape_out_id = 0
   complex(dp), save :: tape_alpha = cmplx(0.0_dp, 0.0_dp, dp)
   complex(dp), save :: tape_beta = cmplx(0.0_dp, 0.0_dp, dp)
   complex(dp), allocatable, save :: tape_last_z(:)

contains

   subroutine calculate_action_generated(z, alpha, beta, s)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: s
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
      complex(dp) :: zero
      integer :: i

      zero = cmplx(0.0_dp, 0.0_dp, dp)
      s = zero
      do i = 1, size(z)
         s = s - ci*(z(i)**3/three + z(i)*alpha) - log(z(i) - ci*beta)
      end do
   end subroutine calculate_action_generated

   subroutine build_action_tape(z_in, alpha, beta, out_id)
      complex(dp), intent(in) :: z_in(:)
      complex(dp), intent(in) :: alpha, beta
      integer, intent(out) :: out_id
      type(rev_t), allocatable :: z(:)
      type(rev_t) :: s, zero
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
      integer :: i, n

      n = size(z_in)
      call tape_begin(n)

      allocate (z(n))
      do i = 1, n
         z(i) = tape_input(z_in(i), i)
      end do

      zero = tape_const(cmplx(0.0_dp, 0.0_dp, dp))
      s = zero
      do i = 1, size(z)
         s = s - ci*(z(i)**3/three + z(i)*alpha) - log(z(i) - ci*beta)
      end do
      out_id = s%id
   end subroutine build_action_tape

   subroutine ensure_action_tape(z, alpha, beta)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      integer :: n

      n = size(z)
      if (.not. tape_ready .or. tape_n /= n .or. alpha /= tape_alpha .or. beta /= tape_beta) then
         call build_action_tape(z, alpha, beta, tape_out_id)
         tape_n = n
         tape_alpha = alpha
         tape_beta = beta
         tape_ready = .true.
         if (allocated(tape_last_z)) then
            if (size(tape_last_z) /= n) deallocate (tape_last_z)
         end if
         if (.not. allocated(tape_last_z)) allocate (tape_last_z(n))
         tape_last_z = z
         tape_point_ready = .true.
      else
         if (.not. tape_point_ready .or. any(z /= tape_last_z)) then
            call tape_set_inputs(z)
            call tape_forward_values()
            tape_last_z = z
            tape_point_ready = .true.
         end if
      end if
   end subroutine ensure_action_tape

   subroutine ds_generated(z, alpha, beta, s)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: s(:)
      integer :: n

      n = size(z)
      if (size(s) /= n) then
         write (*, '(A)') '[ERROR] ds_generated: vector size mismatch.'
         error stop 1
      end if

      call ensure_action_tape(z, alpha, beta)
      call tape_grad(tape_out_id, s)
   end subroutine ds_generated

   subroutine hessian_generated(z, alpha, beta, h)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: h(:, :)
      complex(dp) :: e(size(z))
      integer :: n
      integer :: j

      n = size(z)
      if (size(h, 1) /= n .or. size(h, 2) /= n) then
         write (*, '(A)') '[ERROR] hessian_generated: matrix size mismatch.'
         error stop 1
      end if

      h = cmplx(0.0_dp, 0.0_dp, dp)
      call ensure_action_tape(z, alpha, beta)
      do j = 1, n
         e = cmplx(0.0_dp, 0.0_dp, dp)
         e(j) = cmplx(1.0_dp, 0.0_dp, dp)
         call tape_hvp(tape_out_id, e, h(:, j))
      end do
   end subroutine hessian_generated

   subroutine hessian_vec_generated(z, alpha, beta, v, hv)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(in) :: v(:)
      complex(dp), intent(out) :: hv(:)
      integer :: n

      n = size(z)
      if (size(v) /= n .or. size(hv) /= n) then
         write (*, '(A)') '[ERROR] hessian_vec_generated: vector size mismatch.'
         error stop 1
      end if

      call ensure_action_tape(z, alpha, beta)
      call tape_hvp(tape_out_id, v, hv)
   end subroutine hessian_vec_generated

end module model_generated

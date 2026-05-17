! This file is auto-generated. Do not edit manually.
! Source action body: src/physics/model_action_body.inc
! Backend: tape-generic
module model_generated
   use utils, only: dp
   use model_tape_ad, only: rev_t, model_tape_context_t, bind_model_tape_context, &
                            bind_module_model_tape_context, release_model_tape_context, &
                            tape_begin, tape_input, tape_const, tape_set_inputs, &
                            tape_forward_values, tape_grad, tape_hvp, &
                            operator(+), operator(-), operator(*), operator(/), operator(**), log, exp
   implicit none

   type, public :: model_context_t
      type(model_tape_context_t) :: tape_context
      logical :: tape_ready = .false.
      logical :: tape_point_ready = .false.
      integer :: tape_n = 0
      integer :: tape_out_id = 0
      complex(dp) :: tape_alpha = cmplx(0.0_dp, 0.0_dp, dp)
      complex(dp) :: tape_beta = cmplx(0.0_dp, 0.0_dp, dp)
      complex(dp), allocatable :: tape_last_z(:)
   end type model_context_t

   type(model_context_t), target, save :: module_model_context
   type(model_context_t), pointer, save :: active_model_context => null()

   public :: bind_model_context, bind_module_model_context, release_model_context

contains

   subroutine ensure_model_context_bound()
      if (.not. associated(active_model_context)) call bind_module_model_context()
      call bind_model_tape_context(active_model_context%tape_context)
   end subroutine ensure_model_context_bound

   subroutine bind_model_context(context)
      type(model_context_t), intent(inout), target :: context

      active_model_context => context
      call bind_model_tape_context(active_model_context%tape_context)
   end subroutine bind_model_context

   subroutine bind_module_model_context()
      active_model_context => module_model_context
      call bind_module_model_tape_context()
      call bind_model_tape_context(active_model_context%tape_context)
   end subroutine bind_module_model_context

   subroutine release_model_context(context)
      type(model_context_t), intent(inout), target :: context
      logical :: was_active

      was_active = associated(active_model_context)
      if (was_active) was_active = associated(active_model_context, context)
      if (allocated(context%tape_last_z)) deallocate (context%tape_last_z)
      call release_model_tape_context(context%tape_context)
      context%tape_ready = .false.
      context%tape_point_ready = .false.
      context%tape_n = 0
      context%tape_out_id = 0
      context%tape_alpha = cmplx(0.0_dp, 0.0_dp, dp)
      context%tape_beta = cmplx(0.0_dp, 0.0_dp, dp)
      if (was_active) call bind_module_model_context()
   end subroutine release_model_context

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

      call ensure_model_context_bound()
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

      call ensure_model_context_bound()
      n = size(z)
      if (.not. active_model_context%tape_ready .or. active_model_context%tape_n /= n .or. &
          alpha /= active_model_context%tape_alpha .or. beta /= active_model_context%tape_beta) then
         call build_action_tape(z, alpha, beta, active_model_context%tape_out_id)
         active_model_context%tape_n = n
         active_model_context%tape_alpha = alpha
         active_model_context%tape_beta = beta
         active_model_context%tape_ready = .true.
         if (allocated(active_model_context%tape_last_z)) then
            if (size(active_model_context%tape_last_z) /= n) deallocate (active_model_context%tape_last_z)
         end if
         if (.not. allocated(active_model_context%tape_last_z)) allocate (active_model_context%tape_last_z(n))
         active_model_context%tape_last_z = z
         active_model_context%tape_point_ready = .true.
      else
         if (.not. active_model_context%tape_point_ready .or. any(z /= active_model_context%tape_last_z)) then
            call tape_set_inputs(z)
            call tape_forward_values()
            active_model_context%tape_last_z = z
            active_model_context%tape_point_ready = .true.
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
      call tape_grad(active_model_context%tape_out_id, s)
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
         call tape_hvp(active_model_context%tape_out_id, e, h(:, j))
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
      call tape_hvp(active_model_context%tape_out_id, v, hv)
   end subroutine hessian_vec_generated

end module model_generated

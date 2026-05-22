module model
   use utils, only: dp
   use mt95, only: gaussrnd
   use model_stephanov, only: stephanov_calculate_action, stephanov_ds, stephanov_hessian, stephanov_hessian_vec, &
                              stephanov_ds_hessian_vec_batch

   implicit none

   type, public :: model_context_t
      integer :: unused = 0
   end type model_context_t

contains

   ! ======================== RANDOM NUMBER GENERATION ==========================
   ! Generates Gaussian random numbers using the Box-Muller method
   subroutine grand(gaus_rand)
      real(dp), dimension(:), intent(inout) :: gaus_rand
      integer :: n, i

      n = size(gaus_rand)
      do i = 1, n
         gaus_rand(i) = gaussrnd()
      end do
   end subroutine grand

   subroutine bind_model_context(context)
      type(model_context_t), intent(inout), target :: context

      context%unused = 0
   end subroutine bind_model_context

   subroutine release_model_context(context)
      type(model_context_t), intent(inout), target :: context

      context%unused = 0
   end subroutine release_model_context

   subroutine bind_module_model_context()
   end subroutine bind_module_model_context

   subroutine calculate_action(z, s)
      ! Input/Output parameters
      complex(dp), dimension(:), intent(in) :: z
      complex(dp), intent(out) :: s
      call stephanov_calculate_action(z, s)
   end subroutine calculate_action

   subroutine ds(z, s)
      ! Input and Output parameters
      complex(dp), dimension(:), intent(in) :: z
      complex(dp), dimension(:), intent(out) :: s

      call stephanov_ds(z, s)
   end subroutine ds

   subroutine hessian(z, h)
      implicit none

      ! Input and Output parameters
      complex(dp), dimension(:), intent(in)  :: z
      complex(dp), dimension(:, :), intent(out) :: h

      call stephanov_hessian(z, h)
   end subroutine hessian

   subroutine hessian_vec(z, v, hv)
      implicit none
      complex(dp), intent(in) :: z(:), v(:)
      complex(dp), intent(out) :: hv(:)

      call stephanov_hessian_vec(z, v, hv)
   end subroutine hessian_vec

   logical function batched_ds_hessian_vec_available() result(available)
      available = .true.
   end function batched_ds_hessian_vec_available

   subroutine ds_hessian_vec_batch(z, vectors, grad, hvectors)
      implicit none
      complex(dp), intent(in) :: z(:), vectors(:, :)
      complex(dp), intent(out) :: grad(:), hvectors(:, :)

      call stephanov_ds_hessian_vec_batch(z, vectors, grad, hvectors)
   end subroutine ds_hessian_vec_batch

   subroutine ds_hessian_vec_batch_fallback(z, vectors, grad, hvectors)
      implicit none
      complex(dp), intent(in) :: z(:), vectors(:, :)
      complex(dp), intent(out) :: grad(:), hvectors(:, :)
      integer :: col

      call ds(z, grad)
      do col = 1, size(vectors, 2)
         call hessian_vec(z, vectors(:, col), hvectors(:, col))
      end do
   end subroutine ds_hessian_vec_batch_fallback

end module model

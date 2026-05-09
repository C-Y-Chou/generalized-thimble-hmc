module model
   use param_mod, only: alpha, beta
   use utils
   use mt95
   use model_generated, only: calculate_action_generated, ds_generated, hessian_generated, hessian_vec_generated

   implicit none

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

      subroutine calculate_action(z, s)
      ! Input/Output parameters
      complex(dp), dimension(:), intent(in) :: z
      complex(dp), intent(out) :: s
      call calculate_action_generated(z, alpha, beta, s)
   end subroutine calculate_action

   subroutine ds(z, s)
      ! Input and Output parameters
      complex(dp), dimension(:), intent(in) :: z
      complex(dp), dimension(:), intent(out) :: s

      call ds_generated(z, alpha, beta, s)
   end subroutine ds

   subroutine hessian(z, h)
      implicit none

      ! Input and Output parameters
      complex(dp), dimension(:), intent(in)  :: z
      complex(dp), dimension(:, :), intent(out) :: h

      call hessian_generated(z, alpha, beta, h)
   end subroutine hessian

   subroutine hessian_vec(z, v, hv)
      implicit none
      complex(dp), intent(in) :: z(:), v(:)
      complex(dp), intent(out) :: hv(:)

      call hessian_vec_generated(z, alpha, beta, v, hv)
   end subroutine hessian_vec

end module model

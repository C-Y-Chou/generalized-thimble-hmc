module markovchain_phase
   use utils, only: dp, log_determinant
   use model, only: calculate_action
   implicit none

contains

   subroutine compute_phase_factor(z, j, phi, error)
      implicit none

      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: j(:, :)
      complex(dp), intent(out) :: phi
      logical, intent(out) :: error

      complex(dp) :: log_det_j, s_val
      real(dp) :: s_imag

      ! log_det_j = log(det(J)); its imaginary part is the Jacobian phase.
      call log_determinant(j, log_det_j, error)
      if (error) then
         phi = cmplx(1.0_dp, 0.0_dp, dp)
         return
      end if

      call calculate_action(z, s_val)
      s_imag = aimag(s_val)
      phi = exp(cmplx(0.0_dp, -1.0_dp, dp)*s_imag + cmplx(0.0_dp, 1.0_dp, dp)*aimag(log_det_j))
   end subroutine compute_phase_factor

end module markovchain_phase

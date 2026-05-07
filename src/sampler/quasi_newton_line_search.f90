module quasi_newton_line_search_mod
   use utils
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   implicit none

contains

   logical function accept_full_step(fx_norm, y_norm, d_norm, gamma, rho)
      implicit none
      real(dp), intent(in) :: fx_norm, y_norm, d_norm, gamma, rho

      accept_full_step = ieee_is_finite(fx_norm) .and. &
                         (fx_norm <= gamma*y_norm - rho*d_norm*d_norm)
   end function accept_full_step

   logical function accept_backtracking(fx_norm, phi, etak, sigma, step_norm)
      implicit none
      real(dp), intent(in) :: fx_norm, phi, etak, sigma, step_norm

      accept_backtracking = ieee_is_finite(fx_norm) .and. &
                            (fx_norm <= (1.0_dp + etak)*phi - sigma*step_norm*step_norm)
   end function accept_backtracking

   subroutine update_merit_from_ndls(phi_k, etak, fx_next_norm, tau, t_next, phi_next)
      implicit none
      real(dp), intent(in) :: phi_k, etak, fx_next_norm, tau
      real(dp), intent(out) :: t_next, phi_next

      t_next = ((1.0_dp + etak)*phi_k + 1.0_dp)*fx_next_norm/(fx_next_norm + 1.0_dp)
      phi_next = (1.0_dp - tau)*t_next + tau*fx_next_norm
   end subroutine update_merit_from_ndls

end module quasi_newton_line_search_mod

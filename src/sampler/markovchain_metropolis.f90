module markovchain_metropolis
   use utils
   use mt95, only: grnd
   use hmc, only: integrate_hmc_proposal
   implicit none

contains

   subroutine metropolis_step(x, z, j, total_step_size, num_steps, x_new, z_new, j_new, accept, proposal_failed)
      implicit none

      real(dp), intent(in) :: x(:)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: j(:, :)
      real(dp), intent(in) :: total_step_size
      integer, intent(in) :: num_steps

      real(dp), intent(out) :: x_new(:)
      complex(dp), intent(out) :: z_new(:)
      complex(dp), intent(out) :: j_new(:, :)
      logical, intent(out) :: accept
      logical, intent(out), optional :: proposal_failed

      real(dp) :: h_initial
      real(dp) :: h_final
      real(dp) :: accept_probability
      real(dp) :: rand

      accept = .false.
      if (present(proposal_failed)) proposal_failed = .false.

      if (size(x_new) /= size(x) .or. size(z_new) /= size(z) .or. &
          size(j_new, 1) /= size(j, 1) .or. size(j_new, 2) /= size(j, 2)) then
         write (*, *) "Error(metropolis_step): output buffer size mismatch."
         if (present(proposal_failed)) proposal_failed = .true.
         return
      end if

      call integrate_hmc_proposal(x, z, total_step_size, num_steps, x_new, z_new, h_initial, h_final, j, j_new)

      accept_probability = exp(-(h_final - h_initial))
      rand = grnd()

      if (accept_probability >= 1.0_dp .or. rand <= accept_probability) then
         accept = .true.
      else
         accept = .false.
      end if

      if (h_final == 0.0_dp) then
         accept = .false.
         if (present(proposal_failed)) proposal_failed = .true.
      end if
   end subroutine metropolis_step

end module markovchain_metropolis

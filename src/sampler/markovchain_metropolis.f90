module markovchain_metropolis
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use utils, only: dp
   use mt95, only: grnd
   use markovchain_transition_status, only: metropolis_status_accepted, metropolis_status_delta_h_invalid, &
                                            metropolis_status_hamiltonian_invalid, metropolis_status_output_size_mismatch, &
                                            metropolis_status_proposal_failed, metropolis_status_rejected, &
                                            metropolis_status_reverse_gate_rejected
   use hmc, only: integrate_hmc_proposal, &
                  hmc_proposal_status_output_size_mismatch, &
                  hmc_proposal_status_reverse_gate_rejected
   implicit none

contains

   subroutine metropolis_step(x, z, j, total_step_size, num_steps, x_new, z_new, j_new, accept, proposal_failed, transition_status)
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
      integer, intent(out), optional :: transition_status

      real(dp) :: h_initial
      real(dp) :: h_final
      real(dp) :: delta_h
      real(dp) :: accept_probability
      real(dp) :: rand
      logical :: proposal_ok
      integer :: hmc_status

      accept = .false.
      if (present(proposal_failed)) proposal_failed = .false.
      if (present(transition_status)) transition_status = metropolis_status_rejected

      if (size(x_new) /= size(x) .or. size(z_new) /= size(z) .or. &
          size(j_new, 1) /= size(j, 1) .or. size(j_new, 2) /= size(j, 2)) then
         write (*, *) "Error(metropolis_step): output buffer size mismatch."
         if (present(proposal_failed)) proposal_failed = .true.
         if (present(transition_status)) transition_status = metropolis_status_output_size_mismatch
         return
      end if

      call integrate_hmc_proposal(x, z, total_step_size, num_steps, x_new, z_new, h_initial, h_final, j, j_new, &
                                  proposal_ok, hmc_status)

      if (.not. proposal_ok) then
         accept = .false.
         if (present(proposal_failed)) proposal_failed = .true.
         if (present(transition_status)) transition_status = metropolis_status_from_hmc_status(hmc_status)
         return
      end if

      if ((.not. ieee_is_finite(h_initial)) .or. (.not. ieee_is_finite(h_final))) then
         accept = .false.
         if (present(proposal_failed)) proposal_failed = .true.
         if (present(transition_status)) transition_status = metropolis_status_hamiltonian_invalid
         return
      end if

      delta_h = h_final - h_initial
      if (.not. ieee_is_finite(delta_h)) then
         accept = .false.
         if (present(proposal_failed)) proposal_failed = .true.
         if (present(transition_status)) transition_status = metropolis_status_delta_h_invalid
         return
      end if

      if (delta_h <= 0.0_dp) then
         accept_probability = 1.0_dp
      else
         accept_probability = exp(-delta_h)
      end if

      rand = grnd()
      if (accept_probability >= 1.0_dp .or. rand <= accept_probability) then
         accept = .true.
         if (present(transition_status)) transition_status = metropolis_status_accepted
      else
         accept = .false.
         if (present(transition_status)) transition_status = metropolis_status_rejected
      end if
   end subroutine metropolis_step

   pure integer function metropolis_status_from_hmc_status(hmc_status) result(status)
      integer, intent(in) :: hmc_status

      select case (hmc_status)
      case (hmc_proposal_status_output_size_mismatch)
         status = metropolis_status_output_size_mismatch
      case (hmc_proposal_status_reverse_gate_rejected)
         status = metropolis_status_reverse_gate_rejected
      case default
         status = metropolis_status_proposal_failed
      end select
   end function metropolis_status_from_hmc_status

end module markovchain_metropolis

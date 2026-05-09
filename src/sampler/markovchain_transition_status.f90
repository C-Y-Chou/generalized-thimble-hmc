module markovchain_transition_status
   implicit none

   integer, parameter :: metropolis_status_accepted = 0
   integer, parameter :: metropolis_status_rejected = 1
   integer, parameter :: metropolis_status_proposal_failed = 2
   integer, parameter :: metropolis_status_reverse_gate_rejected = 3
   integer, parameter :: metropolis_status_hamiltonian_invalid = 4
   integer, parameter :: metropolis_status_delta_h_invalid = 5
   integer, parameter :: metropolis_status_output_size_mismatch = 6
end module markovchain_transition_status

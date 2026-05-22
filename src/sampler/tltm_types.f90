module tltm_types_mod
   use, intrinsic :: iso_fortran_env, only: int64
   use mt95, only: mt95_state_t
   use utils, only: dp
   use markovchain_transition_status, only: metropolis_status_rejected, &
                                            metropolis_status_accepted, &
                                            metropolis_status_proposal_failed, &
                                            metropolis_status_reverse_gate_rejected, &
                                            metropolis_status_hamiltonian_invalid, &
                                            metropolis_status_delta_h_invalid, &
                                            metropolis_status_output_size_mismatch
   implicit none

   integer, parameter :: tltm_diag_schema_version_local_transition = 1
   integer, parameter :: tltm_event_context_local_transition = 1
   integer, parameter :: tltm_counter_denominator_local_transition = 1
   integer, parameter :: tltm_reflow_cache_entries = 2

   type :: tltm_local_transition_event_t
      integer :: schema_version = tltm_diag_schema_version_local_transition
      integer :: context_id = tltm_event_context_local_transition
      integer :: counter_denominator = tltm_counter_denominator_local_transition
      integer :: transition_status = metropolis_status_rejected
      logical :: accepted = .false.
      logical :: proposal_failed = .false.
   end type tltm_local_transition_event_t

   type :: tltm_replica_t
      integer :: replica_id = -1
      integer :: rng_seed = 0
      type(mt95_state_t) :: rng_state
      real(dp) :: flow_time = 0.0_dp
      real(dp) :: local_runtime = 0.0_dp
      real(dp), allocatable :: x(:)
      complex(dp), allocatable :: z(:)
      complex(dp), allocatable :: jac(:, :)
      integer :: local_accept_count = 0
      integer :: local_reject_count = 0
      integer :: projection_failure_count = 0
      integer :: metropolis_reject_count = 0
      integer :: reverse_gate_reject_count = 0
      integer :: proposal_failure_count = 0
      integer :: hamiltonian_invalid_count = 0
      integer :: delta_h_invalid_count = 0
      integer :: output_size_mismatch_count = 0
      integer :: observable_samples = 0
      complex(dp) :: phi_sum = cmplx(0.0_dp, 0.0_dp, dp)
   end type tltm_replica_t

   type :: tltm_slot_t
      integer :: slot_id = -1
      integer :: label_id = -1
      integer :: rng_seed = 0
      type(mt95_state_t) :: rng_state
      real(dp) :: flow_time = 0.0_dp
      real(dp) :: local_runtime = 0.0_dp
      real(dp), allocatable :: x(:)
      complex(dp), allocatable :: z(:)
      complex(dp), allocatable :: jac(:, :)
      integer :: local_accept_count = 0
      integer :: local_reject_count = 0
      integer :: projection_failure_count = 0
      integer :: metropolis_reject_count = 0
      integer :: reverse_gate_reject_count = 0
      integer :: proposal_failure_count = 0
      integer :: hamiltonian_invalid_count = 0
      integer :: delta_h_invalid_count = 0
      integer :: output_size_mismatch_count = 0
      integer :: observable_samples = 0
      complex(dp) :: phi_sum = cmplx(0.0_dp, 0.0_dp, dp)
      integer(int64) :: state_version = 0_int64
      integer(int64) :: phase_cache_version = -1_int64
      logical :: phase_cache_valid = .false.
      complex(dp) :: cached_phase_factor = cmplx(1.0_dp, 0.0_dp, dp)
      complex(dp) :: cached_action = cmplx(0.0_dp, 0.0_dp, dp)
      complex(dp) :: cached_log_det_j = cmplx(0.0_dp, 0.0_dp, dp)
      real(dp) :: phase_cache_fingerprint = -1.0_dp
      integer(int64) :: reflow_cache_version(tltm_reflow_cache_entries) = -1_int64
      real(dp) :: reflow_cache_target_time(tltm_reflow_cache_entries) = 0.0_dp
      real(dp) :: reflow_cache_source_fingerprint(tltm_reflow_cache_entries) = -1.0_dp
      logical :: reflow_cache_valid(tltm_reflow_cache_entries) = .false.
      integer :: reflow_cache_next_entry = 1
      complex(dp), allocatable :: reflow_cache_z(:, :)
      complex(dp), allocatable :: reflow_cache_jac(:, :, :)
   end type tltm_slot_t

   type :: tltm_pair_stats_t
      integer :: pair_id = -1
      integer :: slot_a = -1
      integer :: slot_b = -1
      integer :: proposal_count = 0
      integer :: accept_count = 0
      integer :: reject_count = 0
      real(dp) :: last_accept_probability = 0.0_dp
   end type tltm_pair_stats_t

   type :: tltm_label_track_t
      integer :: label_id = -1
      integer :: current_slot = -1
      integer :: farthest_slot_reached = -1
      integer :: last_extreme_visited = -1
      integer :: round_trip_count = 0
      integer :: last_round_trip_start_cycle = -1
      real(dp) :: round_trip_time_sum = 0.0_dp
      logical :: hot_reached_after_cold = .false.
   end type tltm_label_track_t

   interface record_tltm_local_transition
      module procedure record_replica_local_transition
      module procedure record_slot_local_transition
   end interface record_tltm_local_transition

contains

   subroutine mark_tltm_slot_state_changed(slot)
      type(tltm_slot_t), intent(inout) :: slot

      slot%state_version = slot%state_version + 1_int64
      slot%phase_cache_version = -1_int64
      slot%phase_cache_valid = .false.
      slot%phase_cache_fingerprint = -1.0_dp
      slot%reflow_cache_valid = .false.
   end subroutine mark_tltm_slot_state_changed

   pure function make_tltm_local_transition_event(accepted, proposal_failed, transition_status) result(event)
      logical, intent(in) :: accepted, proposal_failed
      integer, intent(in) :: transition_status
      type(tltm_local_transition_event_t) :: event

      event%schema_version = tltm_diag_schema_version_local_transition
      event%context_id = tltm_event_context_local_transition
      event%counter_denominator = tltm_counter_denominator_local_transition
      event%accepted = accepted
      event%proposal_failed = proposal_failed .and. (.not. accepted)
      event%transition_status = transition_status
      if (accepted) event%transition_status = metropolis_status_accepted
   end function make_tltm_local_transition_event

   subroutine record_replica_local_transition(replica, accepted, proposal_failed, transition_status)
      type(tltm_replica_t), intent(inout) :: replica
      logical, intent(in) :: accepted, proposal_failed
      integer, intent(in) :: transition_status
      type(tltm_local_transition_event_t) :: event

      event = make_tltm_local_transition_event(accepted, proposal_failed, transition_status)
      call record_replica_local_transition_event(replica, event)
   end subroutine record_replica_local_transition

   subroutine record_slot_local_transition(slot, accepted, proposal_failed, transition_status)
      type(tltm_slot_t), intent(inout) :: slot
      logical, intent(in) :: accepted, proposal_failed
      integer, intent(in) :: transition_status
      type(tltm_local_transition_event_t) :: event

      event = make_tltm_local_transition_event(accepted, proposal_failed, transition_status)
      call record_slot_local_transition_event(slot, event)
   end subroutine record_slot_local_transition

   subroutine record_replica_local_transition_event(replica, event)
      type(tltm_replica_t), intent(inout) :: replica
      type(tltm_local_transition_event_t), intent(in) :: event

      if (event%accepted) then
         replica%local_accept_count = replica%local_accept_count + 1
      else
         replica%local_reject_count = replica%local_reject_count + 1
      end if
      if (event%proposal_failed) replica%projection_failure_count = replica%projection_failure_count + 1
      call record_replica_transition_detail(replica, event)
   end subroutine record_replica_local_transition_event

   subroutine record_slot_local_transition_event(slot, event)
      type(tltm_slot_t), intent(inout) :: slot
      type(tltm_local_transition_event_t), intent(in) :: event

      if (event%accepted) then
         slot%local_accept_count = slot%local_accept_count + 1
      else
         slot%local_reject_count = slot%local_reject_count + 1
      end if
      if (event%proposal_failed) slot%projection_failure_count = slot%projection_failure_count + 1
      call record_slot_transition_detail(slot, event)
   end subroutine record_slot_local_transition_event

   subroutine record_replica_transition_detail(replica, event)
      type(tltm_replica_t), intent(inout) :: replica
      type(tltm_local_transition_event_t), intent(in) :: event

      select case (event%transition_status)
      case (metropolis_status_rejected)
         if (.not. event%accepted) replica%metropolis_reject_count = replica%metropolis_reject_count + 1
      case (metropolis_status_reverse_gate_rejected)
         replica%reverse_gate_reject_count = replica%reverse_gate_reject_count + 1
      case (metropolis_status_proposal_failed)
         replica%proposal_failure_count = replica%proposal_failure_count + 1
      case (metropolis_status_hamiltonian_invalid)
         replica%hamiltonian_invalid_count = replica%hamiltonian_invalid_count + 1
      case (metropolis_status_delta_h_invalid)
         replica%delta_h_invalid_count = replica%delta_h_invalid_count + 1
      case (metropolis_status_output_size_mismatch)
         replica%output_size_mismatch_count = replica%output_size_mismatch_count + 1
      end select
   end subroutine record_replica_transition_detail

   subroutine record_slot_transition_detail(slot, event)
      type(tltm_slot_t), intent(inout) :: slot
      type(tltm_local_transition_event_t), intent(in) :: event

      select case (event%transition_status)
      case (metropolis_status_rejected)
         if (.not. event%accepted) slot%metropolis_reject_count = slot%metropolis_reject_count + 1
      case (metropolis_status_reverse_gate_rejected)
         slot%reverse_gate_reject_count = slot%reverse_gate_reject_count + 1
      case (metropolis_status_proposal_failed)
         slot%proposal_failure_count = slot%proposal_failure_count + 1
      case (metropolis_status_hamiltonian_invalid)
         slot%hamiltonian_invalid_count = slot%hamiltonian_invalid_count + 1
      case (metropolis_status_delta_h_invalid)
         slot%delta_h_invalid_count = slot%delta_h_invalid_count + 1
      case (metropolis_status_output_size_mismatch)
         slot%output_size_mismatch_count = slot%output_size_mismatch_count + 1
      end select
   end subroutine record_slot_transition_detail

   subroutine allocate_tltm_replica(replica, physical_state_size)
      type(tltm_replica_t), intent(inout) :: replica
      integer, intent(in) :: physical_state_size
      integer :: z_size

      z_size = max(1, physical_state_size)
      if (.not. allocated(replica%x)) allocate (replica%x(z_size))
      if (.not. allocated(replica%z)) allocate (replica%z(z_size))
      if (.not. allocated(replica%jac)) allocate (replica%jac(z_size, z_size))
   end subroutine allocate_tltm_replica

   subroutine release_tltm_replica(replica)
      type(tltm_replica_t), intent(inout) :: replica

      if (allocated(replica%x)) deallocate (replica%x)
      if (allocated(replica%z)) deallocate (replica%z)
      if (allocated(replica%jac)) deallocate (replica%jac)
   end subroutine release_tltm_replica

   subroutine allocate_tltm_slot(slot, physical_state_size)
      type(tltm_slot_t), intent(inout) :: slot
      integer, intent(in) :: physical_state_size
      integer :: z_size

      z_size = max(1, physical_state_size)
      if (.not. allocated(slot%x)) allocate (slot%x(z_size))
      if (.not. allocated(slot%z)) allocate (slot%z(z_size))
      if (.not. allocated(slot%jac)) allocate (slot%jac(z_size, z_size))
      if (.not. allocated(slot%reflow_cache_z)) allocate (slot%reflow_cache_z(z_size, tltm_reflow_cache_entries))
      if (.not. allocated(slot%reflow_cache_jac)) allocate (slot%reflow_cache_jac(z_size, z_size, tltm_reflow_cache_entries))
      slot%state_version = 0_int64
      slot%phase_cache_version = -1_int64
      slot%phase_cache_valid = .false.
      slot%phase_cache_fingerprint = -1.0_dp
      slot%reflow_cache_version = -1_int64
      slot%reflow_cache_target_time = 0.0_dp
      slot%reflow_cache_source_fingerprint = -1.0_dp
      slot%reflow_cache_valid = .false.
      slot%reflow_cache_next_entry = 1
   end subroutine allocate_tltm_slot

   subroutine release_tltm_slot(slot)
      type(tltm_slot_t), intent(inout) :: slot

      if (allocated(slot%x)) deallocate (slot%x)
      if (allocated(slot%z)) deallocate (slot%z)
      if (allocated(slot%jac)) deallocate (slot%jac)
      if (allocated(slot%reflow_cache_z)) deallocate (slot%reflow_cache_z)
      if (allocated(slot%reflow_cache_jac)) deallocate (slot%reflow_cache_jac)
   end subroutine release_tltm_slot

end module tltm_types_mod

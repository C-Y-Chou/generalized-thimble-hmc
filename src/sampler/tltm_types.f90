module tltm_types_mod
   use utils
   implicit none

   type :: tltm_replica_t
      integer :: replica_id = -1
      integer :: rng_seed = 0
      real(dp) :: flow_time = 0.0_dp
      real(dp) :: local_runtime = 0.0_dp
      real(dp), allocatable :: x(:)
      complex(dp), allocatable :: z(:)
      complex(dp), allocatable :: jac(:, :)
      integer :: local_accept_count = 0
      integer :: local_reject_count = 0
      integer :: projection_failure_count = 0
      integer :: observable_samples = 0
      complex(dp) :: phi_sum = cmplx(0.0_dp, 0.0_dp, dp)
   end type tltm_replica_t

   type :: tltm_slot_t
      integer :: slot_id = -1
      integer :: label_id = -1
      integer :: rng_seed = 0
      real(dp) :: flow_time = 0.0_dp
      real(dp) :: local_runtime = 0.0_dp
      real(dp), allocatable :: x(:)
      complex(dp), allocatable :: z(:)
      complex(dp), allocatable :: jac(:, :)
      integer :: local_accept_count = 0
      integer :: local_reject_count = 0
      integer :: projection_failure_count = 0
      integer :: observable_samples = 0
      complex(dp) :: phi_sum = cmplx(0.0_dp, 0.0_dp, dp)
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

contains

   subroutine allocate_tltm_replica(replica, x_size)
      type(tltm_replica_t), intent(inout) :: replica
      integer, intent(in) :: x_size
      integer :: z_size

      z_size = max(1, x_size - 1)
      if (.not. allocated(replica%x)) allocate (replica%x(x_size))
      if (.not. allocated(replica%z)) allocate (replica%z(z_size))
      if (.not. allocated(replica%jac)) allocate (replica%jac(z_size, z_size))
   end subroutine allocate_tltm_replica

   subroutine release_tltm_replica(replica)
      type(tltm_replica_t), intent(inout) :: replica

      if (allocated(replica%x)) deallocate (replica%x)
      if (allocated(replica%z)) deallocate (replica%z)
      if (allocated(replica%jac)) deallocate (replica%jac)
   end subroutine release_tltm_replica

   subroutine allocate_tltm_slot(slot, x_size)
      type(tltm_slot_t), intent(inout) :: slot
      integer, intent(in) :: x_size
      integer :: z_size

      z_size = max(1, x_size - 1)
      if (.not. allocated(slot%x)) allocate (slot%x(x_size))
      if (.not. allocated(slot%z)) allocate (slot%z(z_size))
      if (.not. allocated(slot%jac)) allocate (slot%jac(z_size, z_size))
   end subroutine allocate_tltm_slot

   subroutine release_tltm_slot(slot)
      type(tltm_slot_t), intent(inout) :: slot

      if (allocated(slot%x)) deallocate (slot%x)
      if (allocated(slot%z)) deallocate (slot%z)
      if (allocated(slot%jac)) deallocate (slot%jac)
   end subroutine release_tltm_slot

end module tltm_types_mod

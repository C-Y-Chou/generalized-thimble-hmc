module perf_profile
   use runtime_env_mod, only: read_string_env
   use utils, only: dp, wall_time_seconds
   implicit none

   integer, parameter :: PERF_INTODE = 1
   integer, parameter :: PERF_FLOW = 2
   integer, parameter :: PERF_FLOWZ = 3
   integer, parameter :: PERF_FLOWZR = 4
   integer, parameter :: PERF_RATTLE_STEP_CORE = 5
   integer, parameter :: PERF_DECOMPOSE2 = 6
   integer, parameter :: PERF_NEWTON = 7
   integer, parameter :: PERF_PROJECTED_STEP = 8
   integer, parameter :: PERF_NSLOTS = 8

   type :: perf_profile_context_t
      real(dp) :: accum(PERF_NSLOTS) = 0.0_dp
      integer :: calls(PERF_NSLOTS) = 0
      logical :: enabled_flag = .false.
      logical :: initialized = .false.
   end type perf_profile_context_t

   type(perf_profile_context_t), target, save :: module_perf_context

contains

   subroutine resolve_perf_context(context, active_context)
      implicit none
      type(perf_profile_context_t), intent(inout), optional, target :: context
      type(perf_profile_context_t), pointer :: active_context

      if (present(context)) then
         active_context => context
      else
         active_context => module_perf_context
      end if
   end subroutine resolve_perf_context

   subroutine perf_init(context)
      implicit none
      type(perf_profile_context_t), intent(inout), optional, target :: context

      character(len=32) :: env_value
      logical :: env_present
      type(perf_profile_context_t), pointer :: active_context

      call resolve_perf_context(context, active_context)
      if (active_context%initialized) return
      active_context%initialized = .true.

      env_value = ""
      call read_string_env("PERF_PROFILE", env_value, env_present)
      if (env_present) then
         if (trim(adjustl(env_value)) /= "0") then
            active_context%enabled_flag = .true.
         end if
      end if
   end subroutine perf_init

   logical function perf_enabled(context)
      implicit none
      type(perf_profile_context_t), intent(inout), optional, target :: context

      type(perf_profile_context_t), pointer :: active_context

      call perf_init(context)
      call resolve_perf_context(context, active_context)
      perf_enabled = active_context%enabled_flag
   end function perf_enabled

   subroutine perf_tic(t0, context)
      implicit none
      real(dp), intent(out) :: t0
      type(perf_profile_context_t), intent(inout), optional, target :: context

      type(perf_profile_context_t), pointer :: active_context

      call perf_init(context)
      call resolve_perf_context(context, active_context)
      if (active_context%enabled_flag) then
         t0 = wall_time_seconds()
      else
         t0 = 0.0_dp
      end if
   end subroutine perf_tic

   subroutine perf_toc(slot, t0, context)
      implicit none
      integer, intent(in) :: slot
      real(dp), intent(in) :: t0
      type(perf_profile_context_t), intent(inout), optional, target :: context

      type(perf_profile_context_t), pointer :: active_context

      call resolve_perf_context(context, active_context)
      if (.not. active_context%enabled_flag) return
      if (slot < 1 .or. slot > PERF_NSLOTS) return

      active_context%accum(slot) = active_context%accum(slot) + (wall_time_seconds() - t0)
      active_context%calls(slot) = active_context%calls(slot) + 1
   end subroutine perf_toc

   subroutine perf_reset(context)
      implicit none
      type(perf_profile_context_t), intent(inout), optional, target :: context

      type(perf_profile_context_t), pointer :: active_context

      call resolve_perf_context(context, active_context)
      active_context%accum = 0.0_dp
      active_context%calls = 0
   end subroutine perf_reset

   subroutine perf_report(unit, context)
      implicit none
      integer, intent(in), optional :: unit
      type(perf_profile_context_t), intent(inout), optional, target :: context

      integer :: out_unit, slot
      real(dp) :: total
      type(perf_profile_context_t), pointer :: active_context
      character(len=32), parameter :: labels(PERF_NSLOTS) = [character(len=32) :: &
         "intode", "flow", "flowz", "flowzr", &
         "rattle_step_core", "decompose2", "solve_constraint_newton", "solve_projected_step"]

      call resolve_perf_context(context, active_context)
      if (.not. active_context%enabled_flag) return

      out_unit = 6
      if (present(unit)) out_unit = unit

      total = 0.0_dp
      do slot = 1, PERF_NSLOTS
         total = total + active_context%accum(slot)
      end do

      write (out_unit, '(A)') "[PERF] ---- Profiling Summary ----"
      write (out_unit, '(A,F12.6,A)') "[PERF] total_accumulated=", total, "s"
      do slot = 1, PERF_NSLOTS
         if (active_context%calls(slot) > 0) then
            write (out_unit, '(A,A,A,F12.6,A,I0,A,F12.6)') "[PERF] ", trim(labels(slot)), &
               ": time=", active_context%accum(slot), "s calls=", active_context%calls(slot), &
               " avg=", active_context%accum(slot)/real(active_context%calls(slot), dp)
         end if
      end do
   end subroutine perf_report

   subroutine release_perf_profile_context(context)
      implicit none
      type(perf_profile_context_t), intent(inout) :: context

      call perf_reset(context)
      context%enabled_flag = .false.
      context%initialized = .false.
   end subroutine release_perf_profile_context

end module perf_profile

module perf_profile
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

   real(dp), save :: perf_accum(PERF_NSLOTS) = 0.0_dp
   integer, save :: perf_calls(PERF_NSLOTS) = 0
   logical, save :: perf_enabled_flag = .false.
   logical, save :: perf_initialized = .false.

contains

   subroutine perf_init()
      implicit none
      character(len=32) :: env_value
      integer :: env_len, env_status

      if (perf_initialized) return
      perf_initialized = .true.

      env_value = ""
      call get_environment_variable("PERF_PROFILE", env_value, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         if (trim(adjustl(env_value(1:env_len))) /= "0") then
            perf_enabled_flag = .true.
         end if
      end if
   end subroutine perf_init

   logical function perf_enabled()
      implicit none
      call perf_init()
      perf_enabled = perf_enabled_flag
   end function perf_enabled

   subroutine perf_tic(t0)
      implicit none
      real(dp), intent(out) :: t0
      call perf_init()
      if (perf_enabled_flag) then
         t0 = wall_time_seconds()
      else
         t0 = 0.0_dp
      end if
   end subroutine perf_tic

   subroutine perf_toc(slot, t0)
      implicit none
      integer, intent(in) :: slot
      real(dp), intent(in) :: t0

      if (.not. perf_enabled_flag) return
      if (slot < 1 .or. slot > PERF_NSLOTS) return

      perf_accum(slot) = perf_accum(slot) + (wall_time_seconds() - t0)
      perf_calls(slot) = perf_calls(slot) + 1
   end subroutine perf_toc

   subroutine perf_reset()
      implicit none
      perf_accum = 0.0_dp
      perf_calls = 0
   end subroutine perf_reset

   subroutine perf_report(unit)
      implicit none
      integer, intent(in), optional :: unit

      integer :: out_unit, slot
      real(dp) :: total
      character(len=32), parameter :: labels(PERF_NSLOTS) = [character(len=32) :: &
         "intode", "flow", "flowz", "flowzr", &
         "rattle_step_core", "decompose2", "solve_constraint_newton", "solve_projected_step"]

      if (.not. perf_enabled_flag) return

      out_unit = 6
      if (present(unit)) out_unit = unit

      total = 0.0_dp
      do slot = 1, PERF_NSLOTS
         total = total + perf_accum(slot)
      end do

      write (out_unit, '(A)') "[PERF] ---- Profiling Summary ----"
      write (out_unit, '(A,F12.6,A)') "[PERF] total_accumulated=", total, "s"
      do slot = 1, PERF_NSLOTS
         if (perf_calls(slot) > 0) then
            write (out_unit, '(A,A,A,F12.6,A,I0,A,F12.6)') "[PERF] ", trim(labels(slot)), &
               ": time=", perf_accum(slot), "s calls=", perf_calls(slot), &
               " avg=", perf_accum(slot)/real(perf_calls(slot), dp)
         end if
      end do
   end subroutine perf_report

end module perf_profile

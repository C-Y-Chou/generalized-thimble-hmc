program test_perf_profile_context_contract
   use perf_profile, only: PERF_FLOW, PERF_FLOWZ, PERF_NSLOTS, perf_enabled, perf_profile_context_t, &
                           perf_reset, perf_tic, perf_toc, release_perf_profile_context
   use utils, only: dp
   implicit none

   type(perf_profile_context_t) :: context_a, context_b
   real(dp) :: t0

   context_a%initialized = .true.
   context_a%enabled_flag = .true.
   context_b%initialized = .true.
   context_b%enabled_flag = .false.

   call assert_true(perf_enabled(context_a), "explicit enabled context reports enabled")
   call assert_true(.not. perf_enabled(context_b), "explicit disabled context reports disabled")

   call perf_tic(t0, context_a)
   call perf_toc(PERF_FLOW, t0, context_a)
   call assert_equal_int(context_a%calls(PERF_FLOW), 1, "enabled context records one flow call")
   call assert_equal_int(context_b%calls(PERF_FLOW), 0, "disabled context remains isolated")

   call perf_tic(t0, context_b)
   call perf_toc(PERF_FLOWZ, t0, context_b)
   call assert_equal_int(context_b%calls(PERF_FLOWZ), 0, "disabled context does not record flowz call")
   call assert_equal_int(context_a%calls(PERF_FLOWZ), 0, "enabled context slot isolation holds")

   call perf_toc(0, t0, context_a)
   call perf_toc(PERF_NSLOTS + 1, t0, context_a)
   call assert_equal_int(sum(context_a%calls), 1, "invalid slots are ignored")

   call perf_reset(context_a)
   call assert_equal_int(sum(context_a%calls), 0, "reset clears explicit context calls")
   call assert_true(context_a%enabled_flag, "reset preserves enabled policy")

   call release_perf_profile_context(context_a)
   call assert_equal_int(sum(context_a%calls), 0, "release clears explicit context calls")
   call assert_true(.not. context_a%enabled_flag, "release disables explicit context")
   call assert_true(.not. context_a%initialized, "release clears explicit context initialization")

   write (*, '(A)') "[PASS] perf profile context contract"

contains

   subroutine assert_true(condition, message)
      logical, intent(in) :: condition
      character(len=*), intent(in) :: message

      if (.not. condition) then
         write (*, '(A,A)') "[FAIL] ", trim(message)
         error stop 1
      end if
   end subroutine assert_true

   subroutine assert_equal_int(observed, expected, message)
      integer, intent(in) :: observed, expected
      character(len=*), intent(in) :: message

      if (observed /= expected) then
         write (*, '(A,A,A,I0,A,I0)') "[FAIL] ", trim(message), " observed=", observed, " expected=", expected
         error stop 1
      end if
   end subroutine assert_equal_int

end program test_perf_profile_context_contract

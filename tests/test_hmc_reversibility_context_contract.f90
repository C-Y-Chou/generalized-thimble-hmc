program test_hmc_reversibility_context_contract
   use hmc_reversibility_checks, only: hmc_reversibility_context_t, report_reversibility_probe, &
                                       report_state_progress_diagnostic, reversibility_probe_should_run, &
                                       release_hmc_reversibility_context
   use utils, only: dp
   implicit none

   type(hmc_reversibility_context_t) :: context_a, context_b
   real(dp) :: x_before(3), x_after(3)

   x_before = [0.0_dp, 1.0_dp, -2.0_dp]
   x_after = x_before

   context_a%progress_diag_config_loaded = .true.
   context_a%progress_diag_enabled = .true.
   context_a%progress_diag_limit = 1
   context_b%progress_diag_config_loaded = .true.
   context_b%progress_diag_enabled = .true.
   context_b%progress_diag_limit = 2

   call report_state_progress_diagnostic("context_a", x_before, x_after, context_a)
   call assert_equal_int(context_a%progress_diag_count, 1, "context A records one progress diagnostic")
   call assert_equal_int(context_b%progress_diag_count, 0, "context B progress diagnostic remains isolated")

   call report_state_progress_diagnostic("context_a", x_before, x_after, context_a)
   call assert_equal_int(context_a%progress_diag_count, 1, "progress diagnostic limit is local to context A")

   context_a%probe_config_loaded = .true.
   context_a%probe_enabled = .true.
   context_a%probe_fallback_only = .true.
   context_a%probe_limit = 1
   context_b%probe_config_loaded = .true.
   context_b%probe_enabled = .true.
   context_b%probe_fallback_only = .true.
   context_b%probe_limit = 2

   call assert_true(.not. reversibility_probe_should_run(.false., context_a), &
                    "fallback-only probe ignores non-fallback proposal")
   call assert_true(reversibility_probe_should_run(.true., context_a), &
                    "fallback-only probe accepts fallback proposal before limit")

   call report_reversibility_probe(.true., .true., .true., &
                                   1, 1, 0, &
                                   1, 1, 0, &
                                   0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, context_a)
   call assert_equal_int(context_a%probe_count, 1, "context A records one reversibility probe")
   call assert_equal_int(context_b%probe_count, 0, "context B reversibility probe remains isolated")
   call assert_true(.not. reversibility_probe_should_run(.true., context_a), &
                    "reversibility probe limit is local to context A")

   call release_hmc_reversibility_context(context_a)
   call assert_true(.not. context_a%probe_config_loaded, "release clears probe config state")
   call assert_true(.not. context_a%probe_enabled, "release disables reversibility probe")
   call assert_equal_int(context_a%probe_limit, 0, "release clears reversibility probe limit")
   call assert_equal_int(context_a%probe_count, 0, "release clears reversibility probe count")
   call assert_true(.not. context_a%progress_diag_config_loaded, "release clears progress config state")
   call assert_true(.not. context_a%progress_diag_enabled, "release disables progress diagnostic")
   call assert_equal_int(context_a%progress_diag_limit, 0, "release clears progress diagnostic limit")
   call assert_equal_int(context_a%progress_diag_count, 0, "release clears progress diagnostic count")

   write (*, '(A)') "[PASS] hmc reversibility context contract"

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

end program test_hmc_reversibility_context_contract

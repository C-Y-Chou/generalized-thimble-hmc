program test_odex_assist_policy
   use solve_flow, only: get_intode_solver_assist_policy, intode_ctx_flow, intode_ctx_flowz, intode_ctx_flowzr, &
                         intode_ctx_unknown, intode_reason_h_min, intode_reason_invalid, &
                         intode_reason_max_steps, intode_solver_assist_policy_allows, intode_stage_external, &
                         intode_stage_newton, intode_stage_quasi, intode_stage_quasi_retry, intode_stage_rattle_flow, &
                         intode_stage_unknown
   implicit none

   character(len=32) :: mode
   integer :: failures
   logical :: expected_enabled

   failures = 0
   expected_enabled = .false.
   mode = "disabled"
   if (command_argument_count() >= 1) call get_command_argument(1, mode)
   if (trim(mode) == "enabled") expected_enabled = .true.

   write (*, '(A,A,A,L1)') "[INIT] ODEX assist policy test mode=", trim(mode), " expected_enabled=", expected_enabled

   call check_policy_visibility(expected_enabled, failures)
   call check_policy_gate(expected_enabled, failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] ODEX assist policy failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] ODEX assist policy test complete."

contains

   subroutine check_policy_visibility(expected_enabled, failures)
      logical, intent(in) :: expected_enabled
      integer, intent(inout) :: failures
      logical :: enabled, fast_hmin_assist, ok
      integer :: max_uses

      call get_intode_solver_assist_policy(enabled, max_uses, fast_hmin_assist)
      ok = (enabled .eqv. expected_enabled) .and. fast_hmin_assist .and. max_uses <= 0
      write (*, '(A,L1,A,L1,A,I0,A,L1)') "[CHECK] policy_visibility enabled=", enabled, &
         " fast_hmin=", fast_hmin_assist, " max_uses=", max_uses, " ok=", ok
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] solver-assist policy visibility mismatch."
      end if
   end subroutine check_policy_visibility

   subroutine check_policy_gate(expected_enabled, failures)
      logical, intent(in) :: expected_enabled
      integer, intent(inout) :: failures

      call expect_policy("hmin_newton_flowz", intode_reason_h_min, intode_ctx_flowz, intode_stage_newton, &
                         expected_enabled, failures)
      call expect_policy("hmin_quasi_flowz", intode_reason_h_min, intode_ctx_flowz, intode_stage_quasi, &
                         expected_enabled, failures)
      call expect_policy("hmin_retry_flowzr", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi_retry, &
                         expected_enabled, failures)
      call expect_policy("wrong_reason_invalid", intode_reason_invalid, intode_ctx_flowz, intode_stage_newton, &
                         .false., failures)
      call expect_policy("wrong_reason_max_steps", intode_reason_max_steps, intode_ctx_flowz, intode_stage_newton, &
                         .false., failures)
      call expect_policy("unknown_context", intode_reason_h_min, intode_ctx_unknown, intode_stage_newton, &
                         .false., failures)
      call expect_policy("final_flow_context", intode_reason_h_min, intode_ctx_flow, intode_stage_newton, &
                         .false., failures)
      call expect_policy("unknown_stage", intode_reason_h_min, intode_ctx_flowz, intode_stage_unknown, &
                         .false., failures)
      call expect_policy("external_stage", intode_reason_h_min, intode_ctx_flowz, intode_stage_external, &
                         .false., failures)
      call expect_policy("rattle_flow_stage", intode_reason_h_min, intode_ctx_flowz, intode_stage_rattle_flow, &
                         .false., failures)
   end subroutine check_policy_gate

   subroutine expect_policy(label, reason_code, context_code, stage_code, expected, failures)
      character(len=*), intent(in) :: label
      integer, intent(in) :: reason_code, context_code, stage_code
      logical, intent(in) :: expected
      integer, intent(inout) :: failures
      logical :: actual

      actual = intode_solver_assist_policy_allows(reason_code, context_code, stage_code, 0)
      write (*, '(A,A,A,L1,A,L1)') "[CHECK] ", trim(label), " actual=", actual, " expected=", expected
      if (actual .neqv. expected) then
         failures = failures + 1
         write (*, '(A,A)') "[FAIL] policy gate mismatch: ", trim(label)
      end if
   end subroutine expect_policy

end program test_odex_assist_policy

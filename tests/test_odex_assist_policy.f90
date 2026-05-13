program test_odex_assist_policy
   use solve_flow, only: get_intode_solver_assist_policy_code, intode_ctx_flow, intode_ctx_flowz, intode_ctx_flowzr, &
                         intode_ctx_unknown, intode_reason_h_min, intode_reason_invalid, &
                         intode_reason_max_steps, intode_solver_assist_policy_allows, &
                         intode_solver_assist_policy_all_navigation_diagnostic, intode_solver_assist_policy_off, &
                         intode_solver_assist_policy_qn_navigation, intode_stage_external, intode_stage_newton, &
                         intode_stage_quasi, intode_stage_quasi_retry, intode_stage_rattle_flow, intode_stage_unknown, &
                         intode_role_certification, intode_role_final_flow, intode_role_nt_strict, intode_role_qn_navigation, &
                         intode_role_reverse_replay
   implicit none

   character(len=64) :: mode
   integer :: expected_policy, failures
   logical :: expected_enabled

   failures = 0
   mode = "qn_navigation"
   if (command_argument_count() >= 1) call get_command_argument(1, mode)

   select case (trim(mode))
   case ("off", "disabled")
      expected_policy = intode_solver_assist_policy_off
      expected_enabled = .false.
   case ("qn_navigation", "default", "canonical")
      expected_policy = intode_solver_assist_policy_qn_navigation
      expected_enabled = .true.
   case ("all_navigation_diagnostic", "enabled", "legacy_enabled")
      expected_policy = intode_solver_assist_policy_all_navigation_diagnostic
      expected_enabled = .true.
   case default
      write (*, '(A,A)') "[ERROR] Unknown ODEX assist policy test mode: ", trim(mode)
      error stop 1
   end select

   write (*, '(A,A,A,I0,A,L1)') "[INIT] ODEX assist policy test mode=", trim(mode), &
      " expected_policy=", expected_policy, " expected_enabled=", expected_enabled

   call check_policy_visibility(expected_policy, expected_enabled, failures)
   call check_policy_gate(expected_policy, failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] ODEX assist policy failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] ODEX assist policy test complete."

contains

   subroutine check_policy_visibility(expected_policy, expected_enabled, failures)
      integer, intent(in) :: expected_policy
      logical, intent(in) :: expected_enabled
      integer, intent(inout) :: failures
      logical :: enabled, fast_hmin_assist, ok
      integer :: max_uses, policy_code

      call get_intode_solver_assist_policy_code(policy_code, enabled, max_uses, fast_hmin_assist)
      ok = policy_code == expected_policy .and. (enabled .eqv. expected_enabled) .and. fast_hmin_assist .and. max_uses <= 0
      write (*, '(A,I0,A,I0,A,L1,A,L1,A,I0,A,L1)') "[CHECK] policy_visibility policy=", policy_code, &
         " expected=", expected_policy, " enabled=", enabled, " fast_hmin=", fast_hmin_assist, " max_uses=", max_uses, " ok=", ok
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] solver-assist policy visibility mismatch."
      end if
   end subroutine check_policy_visibility

   subroutine check_policy_gate(expected_policy, failures)
      integer, intent(in) :: expected_policy
      integer, intent(inout) :: failures

      select case (expected_policy)
      case (intode_solver_assist_policy_off)
         call check_off_policy(failures)
      case (intode_solver_assist_policy_qn_navigation)
         call check_qn_navigation_policy(failures)
      case (intode_solver_assist_policy_all_navigation_diagnostic)
         call check_all_navigation_diagnostic_policy(failures)
      case default
         failures = failures + 1
         write (*, '(A,I0)') "[FAIL] unrecognized expected policy code=", expected_policy
      end select
   end subroutine check_policy_gate

   subroutine check_off_policy(failures)
      integer, intent(inout) :: failures

      call expect_policy("off_newton_nt", intode_reason_h_min, intode_ctx_flowz, intode_stage_newton, intode_role_nt_strict, &
                         .false., failures)
      call expect_policy("off_quasi_qn", intode_reason_h_min, intode_ctx_flowz, intode_stage_quasi, intode_role_qn_navigation, &
                         .false., failures)
      call expect_policy("off_retry_reverse", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi_retry, &
                         intode_role_reverse_replay, .false., failures)
   end subroutine check_off_policy

   subroutine check_qn_navigation_policy(failures)
      integer, intent(inout) :: failures

      call expect_policy("hmin_newton_nt", intode_reason_h_min, intode_ctx_flowz, intode_stage_newton, intode_role_nt_strict, &
                         .false., failures)
      call expect_policy("hmin_quasi_qn", intode_reason_h_min, intode_ctx_flowz, intode_stage_quasi, intode_role_qn_navigation, &
                         .true., failures)
      call expect_policy("hmin_retry_qn", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi_retry, intode_role_qn_navigation, &
                         .true., failures)
      call expect_policy("hmin_quasi_reverse_replay", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi, &
                         intode_role_reverse_replay, .true., failures)
      call expect_policy("certification_strict", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi, &
                         intode_role_certification, .false., failures)
      call expect_policy("final_flow_strict", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi, &
                         intode_role_final_flow, .false., failures)
      call check_negative_gates(failures)
   end subroutine check_qn_navigation_policy

   subroutine check_all_navigation_diagnostic_policy(failures)
      integer, intent(inout) :: failures

      call expect_policy("diagnostic_newton_nt", intode_reason_h_min, intode_ctx_flowz, intode_stage_newton, &
                         intode_role_nt_strict, .true., failures)
      call expect_policy("diagnostic_quasi_qn", intode_reason_h_min, intode_ctx_flowz, intode_stage_quasi, &
                         intode_role_qn_navigation, .true., failures)
      call expect_policy("diagnostic_retry_reverse", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi_retry, &
                         intode_role_reverse_replay, .true., failures)
      call expect_policy("diagnostic_certification_strict", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi, &
                         intode_role_certification, .false., failures)
      call expect_policy("diagnostic_final_flow_strict", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi, &
                         intode_role_final_flow, .false., failures)
      call check_negative_gates(failures)
   end subroutine check_all_navigation_diagnostic_policy

   subroutine check_negative_gates(failures)
      integer, intent(inout) :: failures

      call expect_policy("wrong_reason_invalid", intode_reason_invalid, intode_ctx_flowz, intode_stage_quasi, &
                         intode_role_qn_navigation, .false., failures)
      call expect_policy("wrong_reason_max_steps", intode_reason_max_steps, intode_ctx_flowz, intode_stage_quasi, &
                         intode_role_qn_navigation, .false., failures)
      call expect_policy("unknown_context", intode_reason_h_min, intode_ctx_unknown, intode_stage_quasi, &
                         intode_role_qn_navigation, .false., failures)
      call expect_policy("final_flow_context", intode_reason_h_min, intode_ctx_flow, intode_stage_quasi, &
                         intode_role_qn_navigation, .false., failures)
      call expect_policy("unknown_stage", intode_reason_h_min, intode_ctx_flowz, intode_stage_unknown, &
                         intode_role_qn_navigation, .false., failures)
      call expect_policy("external_stage", intode_reason_h_min, intode_ctx_flowz, intode_stage_external, &
                         intode_role_qn_navigation, .false., failures)
      call expect_policy("rattle_flow_stage", intode_reason_h_min, intode_ctx_flowz, intode_stage_rattle_flow, &
                         intode_role_qn_navigation, .false., failures)
   end subroutine check_negative_gates

   subroutine expect_policy(label, reason_code, context_code, stage_code, role_code, expected, failures)
      character(len=*), intent(in) :: label
      integer, intent(in) :: reason_code, context_code, stage_code, role_code
      logical, intent(in) :: expected
      integer, intent(inout) :: failures
      logical :: actual

      actual = intode_solver_assist_policy_allows(reason_code, context_code, stage_code, 0, role_code)
      write (*, '(A,A,A,L1,A,L1)') "[CHECK] ", trim(label), " actual=", actual, " expected=", expected
      if (actual .neqv. expected) then
         failures = failures + 1
         write (*, '(A,A)') "[FAIL] policy gate mismatch: ", trim(label)
      end if
   end subroutine expect_policy

end program test_odex_assist_policy

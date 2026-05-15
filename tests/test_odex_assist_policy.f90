program test_odex_assist_policy
   use solve_flow, only: get_intode_solver_assist_policy_code, intode_ctx_flow, intode_ctx_flowz, intode_ctx_flowzr, &
                         intode_ctx_unknown, intode_reason_h_min, intode_reason_invalid, &
                         intode_reason_max_steps, intode_solver_assist_policy_allows, &
                         intode_solver_assist_policy_off, intode_stage_external, intode_stage_newton, &
                         intode_stage_quasi, intode_stage_quasi_retry, intode_stage_rattle_flow, intode_stage_unknown, &
                         intode_role_certification, intode_role_final_flow, intode_role_nt_strict, intode_role_qn_navigation, &
                         intode_role_reverse_replay
   implicit none

   character(len=64) :: mode
   integer :: failures

   failures = 0
   mode = "default"
   if (command_argument_count() >= 1) call get_command_argument(1, mode)

   write (*, '(A,A)') "[INIT] ODEX assist deletion policy test mode=", trim(mode)

   call check_policy_visibility(failures)
   call check_policy_gate_deleted(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] ODEX assist deletion policy failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] ODEX assist deletion policy test complete."

contains

   subroutine check_policy_visibility(failures)
      integer, intent(inout) :: failures
      logical :: enabled, fast_hmin_assist, ok
      integer :: max_uses, policy_code

      call get_intode_solver_assist_policy_code(policy_code, enabled, max_uses, fast_hmin_assist)
      ok = policy_code == intode_solver_assist_policy_off .and. .not. enabled .and. &
           .not. fast_hmin_assist .and. max_uses == 0
      write (*, '(A,I0,A,L1,A,L1,A,I0,A,L1)') "[CHECK] policy_visibility policy=", policy_code, &
         " enabled=", enabled, " fast_hmin=", fast_hmin_assist, " max_uses=", max_uses, " ok=", ok
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] deleted solver-assist policy is visible as active."
      end if
   end subroutine check_policy_visibility

   subroutine check_policy_gate_deleted(failures)
      integer, intent(inout) :: failures

      call expect_policy("hmin_newton_nt", intode_reason_h_min, intode_ctx_flowz, intode_stage_newton, intode_role_nt_strict, failures)
      call expect_policy("hmin_quasi_qn", intode_reason_h_min, intode_ctx_flowz, intode_stage_quasi, intode_role_qn_navigation, failures)
      call expect_policy("hmin_retry_qn", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi_retry, intode_role_qn_navigation, failures)
      call expect_policy("hmin_quasi_reverse_replay", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi, &
                         intode_role_reverse_replay, failures)
      call expect_policy("certification_strict", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi, &
                         intode_role_certification, failures)
      call expect_policy("final_flow_strict", intode_reason_h_min, intode_ctx_flowzr, intode_stage_quasi, &
                         intode_role_final_flow, failures)
      call expect_policy("wrong_reason_invalid", intode_reason_invalid, intode_ctx_flowz, intode_stage_quasi, &
                         intode_role_qn_navigation, failures)
      call expect_policy("wrong_reason_max_steps", intode_reason_max_steps, intode_ctx_flowz, intode_stage_quasi, &
                         intode_role_qn_navigation, failures)
      call expect_policy("unknown_context", intode_reason_h_min, intode_ctx_unknown, intode_stage_quasi, &
                         intode_role_qn_navigation, failures)
      call expect_policy("final_flow_context", intode_reason_h_min, intode_ctx_flow, intode_stage_quasi, &
                         intode_role_qn_navigation, failures)
      call expect_policy("unknown_stage", intode_reason_h_min, intode_ctx_flowz, intode_stage_unknown, &
                         intode_role_qn_navigation, failures)
      call expect_policy("external_stage", intode_reason_h_min, intode_ctx_flowz, intode_stage_external, &
                         intode_role_qn_navigation, failures)
      call expect_policy("rattle_flow_stage", intode_reason_h_min, intode_ctx_flowz, intode_stage_rattle_flow, &
                         intode_role_qn_navigation, failures)
   end subroutine check_policy_gate_deleted

   subroutine expect_policy(label, reason_code, context_code, stage_code, role_code, failures)
      character(len=*), intent(in) :: label
      integer, intent(in) :: reason_code, context_code, stage_code, role_code
      integer, intent(inout) :: failures
      logical :: actual

      actual = intode_solver_assist_policy_allows(reason_code, context_code, stage_code, 0, role_code)
      write (*, '(A,A,A,L1)') "[CHECK] ", trim(label), " allowed=", actual
      if (actual) then
         failures = failures + 1
         write (*, '(A,A)') "[FAIL] deleted solver-assist gate allowed route: ", trim(label)
      end if
   end subroutine expect_policy

end program test_odex_assist_policy

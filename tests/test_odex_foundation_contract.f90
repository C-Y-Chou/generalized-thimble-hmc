module test_odex_foundation_rhs
   use, intrinsic :: ieee_arithmetic, only: ieee_quiet_nan, ieee_value
   use utils, only: dp
   implicit none
   real(dp) :: exp_lambda = 0.0_dp
contains
   function rhs_exp(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy(1) = exp_lambda*y(1)
   end function rhs_exp

   function rhs_nan(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy = ieee_value(0.0_dp, ieee_quiet_nan)
   end function rhs_nan

   function rhs_nan_context(y, context) result(dy)
      real(dp), intent(in) :: y(:)
      class(*), intent(inout) :: context
      real(dp) :: dy(size(y))

      dy = ieee_value(0.0_dp, ieee_quiet_nan)
   end function rhs_nan_context
end module test_odex_foundation_rhs

program test_odex_foundation_contract
   use param_mod, only: at, rt
   use solve_flow, only: build_nsteps, get_intode_fallback_stats, &
                         get_intode_last_failure_meta, get_intode_last_failure_trace, get_intode_rescue_stats, &
                         get_intode_solver_assist_policy_code, intode, intode_with_context, &
                         intode_diagnostics_context_t, flow_workspace_t, release_flow_workspace, release_intode_diagnostics_context, &
                         set_intode_rattle_trace, set_intode_stage_trace, set_intode_newton_iter_trace, set_intode_quasi_iter_trace, &
                         intode_ctx_flowzr, intode_stage_quasi, &
                         intode_reason_h_min, intode_reason_invalid, &
                         intode_status_failure_h_min, intode_status_failure_invalid, &
                         intode_solver_assist_policy_off, &
                         intode_status_is_strict_success, intode_status_success, &
                         intode_status_success_solver_assist, intode_status_success_zero_time, &
                         reset_intode_fallback_stats
   use test_odex_foundation_rhs, only: exp_lambda, rhs_exp, rhs_nan, rhs_nan_context
   use utils, only: dp
   implicit none

   integer :: failures

   failures = 0
   at = 3.0e-14_dp
   rt = 3.0e-14_dp

   write (*, '(A,ES12.4,A,ES12.4)') "[INIT] ODEX foundation contract starts. abs_tol=", at, " rel_tol=", rt

   call check_iwork3_sequence(failures)
   call check_strict_status_predicate(failures)
   call check_zero_time_contract(failures)
   call check_forward_backward_composition(failures)
   call check_unknown_context_failure_contract(failures)
   call check_explicit_diagnostics_context_isolation(failures)
   call check_workspace_runtime_trace_context(failures)
   call check_solver_assist_policy_visibility(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] ODEX foundation contract failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] ODEX foundation contract complete."

contains

   subroutine check_iwork3_sequence(failures)
      integer, intent(inout) :: failures
      integer :: actual(11)
      integer :: expected(11)

      expected = [2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96]
      call build_nsteps(size(actual), actual)
      write (*, '(A,*(1X,I0))') "[CHECK] iwork3_sequence actual=", actual
      if (any(actual /= expected)) then
         failures = failures + 1
         write (*, '(A,*(1X,I0))') "[FAIL] expected=", expected
      end if
   end subroutine check_iwork3_sequence

   subroutine check_strict_status_predicate(failures)
      integer, intent(inout) :: failures
      logical :: ok

	      ok = intode_status_is_strict_success(intode_status_success) .and. &
	           intode_status_is_strict_success(intode_status_success_zero_time) .and. &
	           .not. intode_status_is_strict_success(intode_status_success_solver_assist) .and. &
	           .not. intode_status_is_strict_success(intode_status_failure_invalid) .and. &
	           .not. intode_status_is_strict_success(intode_status_failure_h_min)
      write (*, '(A,L1)') "[CHECK] strict_status_predicate ok=", ok
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] strict status predicate accepts or rejects the wrong status."
      end if
   end subroutine check_strict_status_predicate

   subroutine check_zero_time_contract(failures)
      integer, intent(inout) :: failures
      real(dp) :: y0(1), y_out(1), err
      logical :: failed
      integer :: status

      call reset_intode_fallback_stats()
      y0(1) = -0.375_dp
      exp_lambda = -2.0_dp
      call intode(rhs_exp, y0, 0.0_dp, y_out, failed, status)
      err = maxval(abs(y_out - y0))
      write (*, '(A,L1,A,I0,A,ES12.4)') "[CHECK] zero_time failed=", failed, " status=", status, " err=", err
      if (failed .or. status /= intode_status_success_zero_time .or. err /= 0.0_dp) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] zero-time contract changed."
      end if
   end subroutine check_zero_time_contract

   subroutine check_forward_backward_composition(failures)
      integer, intent(inout) :: failures
      real(dp) :: y0(1), y_mid(1), y_back(1), err
      logical :: failed_mid, failed_back
      integer :: status_mid, status_back

      call reset_intode_fallback_stats()
      exp_lambda = -1.3_dp
      y0(1) = 0.8125_dp
      call intode(rhs_exp, y0, 0.75_dp, y_mid, failed_mid, status_mid)
      call intode(rhs_exp, y_mid, -0.75_dp, y_back, failed_back, status_back)
      err = maxval(abs(y_back - y0))
      write (*, '(A,L1,A,L1,A,I0,A,I0,A,ES12.4)') "[CHECK] forward_backward failed_mid=", failed_mid, &
         " failed_back=", failed_back, " status_mid=", status_mid, " status_back=", status_back, " err=", err
      if (failed_mid .or. failed_back .or. status_mid /= intode_status_success .or. &
          status_back /= intode_status_success .or. err > 2.0e-11_dp) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] forward/backward endpoint composition drifted."
      end if
   end subroutine check_forward_backward_composition

   subroutine check_unknown_context_failure_contract(failures)
      integer, intent(inout) :: failures
      real(dp) :: y0(1), y_out(1), t_remaining
      logical :: failed, available
      integer :: status, reason_code, context_code, state_dim
      integer :: calls_total, calls_integrating
      integer :: fallback_attempts, fallback_success, fallback_failure
      integer :: fallback_max_steps, fallback_invalid, fallback_h_min
      integer :: success_radau_adaptive, success_radau_adaptive_robust
      integer :: success_radau_fixed_tol, success_radau_chunked, success_solver_assist
      integer :: fail_radau_adaptive_robust, fail_radau_fixed_tol, fail_radau_chunked, fail_solver_assist
      logical :: ok

      call reset_intode_fallback_stats()
      y0(1) = 1.0_dp
      call intode(rhs_nan, y0, 1.0_dp, y_out, failed, status)
      call get_intode_fallback_stats(calls_total, calls_integrating, fallback_attempts, fallback_success, &
                                     fallback_failure, fallback_max_steps, fallback_invalid, fallback_h_min)
      call get_intode_last_failure_meta(available, reason_code, context_code, state_dim, t_remaining)
      call get_intode_rescue_stats(success_radau_adaptive, success_radau_adaptive_robust, success_radau_fixed_tol, &
                                   success_radau_chunked, success_solver_assist, fail_radau_adaptive_robust, &
                                   fail_radau_fixed_tol, fail_radau_chunked, fail_solver_assist)

	      ok = failed .and. status == intode_status_failure_invalid .and. fallback_attempts == 1 .and. &
	           fallback_success == 0 .and. fallback_failure == 1 .and. fallback_invalid == 1 .and. fallback_h_min == 0 .and. &
	           success_solver_assist == 0 .and. fail_solver_assist == 0 .and. available .and. &
	           reason_code == intode_reason_invalid .and. context_code == 0 .and. state_dim == 1
	      write (*, '(A,L1,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') "[CHECK] unknown_context_failure ok=", ok, &
	         " status=", status, " attempts=", fallback_attempts, " success=", fallback_success, &
	         " failure=", fallback_failure, " invalid=", fallback_invalid, " hmin=", fallback_h_min, &
	         " assist_success=", success_solver_assist
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,L1)') "[FAIL] failure contract changed: reason=", reason_code, &
            " context=", context_code, " state_dim=", state_dim, " assist_fail=", fail_solver_assist, &
            " calls=", calls_total, " available=", available
      end if
   end subroutine check_unknown_context_failure_contract

   subroutine check_explicit_diagnostics_context_isolation(failures)
      integer, intent(inout) :: failures
      type(intode_diagnostics_context_t) :: diag_a, diag_b
      real(dp) :: y0(1), y_out(1), t_remaining
      logical :: failed, available_a, available_module
      integer :: status, reason_code, context_code, state_dim
      integer :: calls_total_a, calls_integrating_a, attempts_a, success_a, failure_a, max_steps_a, invalid_a, h_min_a
      integer :: calls_total_b, calls_integrating_b, attempts_b, success_b, failure_b, max_steps_b, invalid_b, h_min_b
      integer :: calls_total_m, calls_integrating_m, attempts_m, success_m, failure_m, max_steps_m, invalid_m, h_min_m
      logical :: ok

      call reset_intode_fallback_stats()
      call reset_intode_fallback_stats(diag_a)
      call reset_intode_fallback_stats(diag_b)
      y0(1) = 1.0_dp
      call intode(rhs_nan, y0, 1.0_dp, y_out, failed, status, diag_a)
      call get_intode_fallback_stats(calls_total_a, calls_integrating_a, attempts_a, success_a, failure_a, max_steps_a, invalid_a, h_min_a, diag_a)
      call get_intode_fallback_stats(calls_total_b, calls_integrating_b, attempts_b, success_b, failure_b, max_steps_b, invalid_b, h_min_b, diag_b)
      call get_intode_fallback_stats(calls_total_m, calls_integrating_m, attempts_m, success_m, failure_m, max_steps_m, invalid_m, h_min_m)
      call get_intode_last_failure_meta(available_a, reason_code, context_code, state_dim, t_remaining, diag_a)
      call get_intode_last_failure_meta(available_module, reason_code, context_code, state_dim, t_remaining)

	      ok = failed .and. status == intode_status_failure_invalid .and. calls_total_a == 1 .and. attempts_a == 1 .and. &
	           failure_a == 1 .and. invalid_a == 1 .and. h_min_a == 0 .and. calls_total_b == 0 .and. attempts_b == 0 .and. &
	           calls_total_m == 0 .and. attempts_m == 0 .and. available_a .and. .not. available_module
      write (*, '(A,L1,A,I0,A,I0,A,I0)') "[CHECK] explicit_diagnostics_context_isolation ok=", ok, &
         " attempts_a=", attempts_a, " attempts_b=", attempts_b, " attempts_module=", attempts_m
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A,I0,A,I0,A,I0,A,L1,A,L1)') "[FAIL] explicit diagnostics isolation drifted: calls_a=", calls_total_a, &
            " calls_b=", calls_total_b, " calls_module=", calls_total_m, " available_a=", available_a, &
            " available_module=", available_module
      end if
      call release_intode_diagnostics_context(diag_a)
      call release_intode_diagnostics_context(diag_b)
   end subroutine check_explicit_diagnostics_context_isolation

   subroutine check_workspace_runtime_trace_context(failures)
      integer, intent(inout) :: failures
      type(intode_diagnostics_context_t) :: diag
      type(flow_workspace_t) :: workspace
      real(dp) :: y0(1), y_out(1), t_remaining
      logical :: failed, available_meta, available_trace
      integer :: status, reason_code, context_code, state_dim
      integer :: rattle_step, rattle_substep, stage_code, newton_iter, quasi_iter
      logical :: ok

      call reset_intode_fallback_stats()
      call reset_intode_fallback_stats(diag)
      call set_intode_rattle_trace(7, 2, workspace)
      call set_intode_stage_trace(intode_stage_quasi, workspace)
      call set_intode_newton_iter_trace(3, workspace)
      call set_intode_quasi_iter_trace(5, workspace)
      workspace%intode_trace%current_context = intode_ctx_flowzr
      y0(1) = 1.0_dp
      call intode_with_context(rhs_nan_context, y0, 1.0_dp, y_out, failed, status, workspace, diag)
      call get_intode_last_failure_meta(available_meta, reason_code, context_code, state_dim, t_remaining, diag)
      call get_intode_last_failure_trace(available_trace, rattle_step, rattle_substep, stage_code, newton_iter, quasi_iter, diag)

	      ok = failed .and. status == intode_status_failure_invalid .and. available_meta .and. available_trace .and. &
	           reason_code == intode_reason_invalid .and. context_code == intode_ctx_flowzr .and. &
           rattle_step == 7 .and. rattle_substep == 2 .and. stage_code == intode_stage_quasi .and. &
           newton_iter == 3 .and. quasi_iter == 5
      write (*, '(A,L1,A,I0,A,I0,A,I0,A,I0,A,I0)') "[CHECK] workspace_runtime_trace_context ok=", ok, &
         " context=", context_code, " rattle_step=", rattle_step, " substep=", rattle_substep, &
         " newton_iter=", newton_iter, " quasi_iter=", quasi_iter
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A,I0,A,I0,A,L1,A,L1)') "[FAIL] workspace trace context drifted: reason=", reason_code, &
            " stage=", stage_code, " available_meta=", available_meta, " available_trace=", available_trace
      end if
      call release_flow_workspace(workspace)
      call release_intode_diagnostics_context(diag)
   end subroutine check_workspace_runtime_trace_context

   subroutine check_solver_assist_policy_visibility(failures)
      integer, intent(inout) :: failures
      logical :: enabled, fast_hmin_assist, ok
      integer :: max_uses, policy_code

      call get_intode_solver_assist_policy_code(policy_code, enabled, max_uses, fast_hmin_assist)
      ok = policy_code == intode_solver_assist_policy_off .and. .not. enabled .and. .not. fast_hmin_assist .and. max_uses == 0
      write (*, '(A,I0,A,L1,A,L1,A,I0,A,L1)') "[CHECK] solver_assist_policy policy=", policy_code, " enabled=", enabled, &
         " fast_hmin=", fast_hmin_assist, " max_uses=", max_uses, " ok=", ok
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] deleted solver-assist policy is visible as active."
      end if
   end subroutine check_solver_assist_policy_visibility

end program test_odex_foundation_contract

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
end module test_odex_foundation_rhs

program test_odex_foundation_contract
   use param_mod, only: at, rt
   use solve_flow, only: build_nsteps, get_intode_fallback_stats, &
                         get_intode_last_failure_meta, get_intode_rescue_stats, &
                         get_intode_solver_assist_policy, intode, &
                         intode_reason_h_min, intode_status_failure_h_min, &
                         intode_status_is_strict_success, intode_status_success, &
                         intode_status_success_solver_assist, intode_status_success_zero_time, &
                         reset_intode_fallback_stats
   use test_odex_foundation_rhs, only: exp_lambda, rhs_exp, rhs_nan
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

      ok = failed .and. status == intode_status_failure_h_min .and. fallback_attempts == 1 .and. &
           fallback_success == 0 .and. fallback_failure == 1 .and. fallback_h_min == 1 .and. &
           success_solver_assist == 0 .and. fail_solver_assist >= 1 .and. available .and. &
           reason_code == intode_reason_h_min .and. context_code == 0 .and. state_dim == 1
      write (*, '(A,L1,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') "[CHECK] unknown_context_failure ok=", ok, &
         " status=", status, " attempts=", fallback_attempts, " success=", fallback_success, &
         " failure=", fallback_failure, " hmin=", fallback_h_min, " assist_success=", success_solver_assist
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,L1)') "[FAIL] failure contract changed: reason=", reason_code, &
            " context=", context_code, " state_dim=", state_dim, " assist_fail=", fail_solver_assist, &
            " calls=", calls_total, " available=", available
      end if
   end subroutine check_unknown_context_failure_contract

   subroutine check_solver_assist_policy_visibility(failures)
      integer, intent(inout) :: failures
      logical :: enabled, fast_hmin_assist, ok
      integer :: max_uses

      call get_intode_solver_assist_policy(enabled, max_uses, fast_hmin_assist)
      ok = enabled .and. fast_hmin_assist .and. max_uses <= 0
      write (*, '(A,L1,A,L1,A,I0,A,L1)') "[CHECK] solver_assist_policy enabled=", enabled, &
         " fast_hmin=", fast_hmin_assist, " max_uses=", max_uses, " ok=", ok
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] solver-assist policy visibility changed."
      end if
   end subroutine check_solver_assist_policy_visibility

end program test_odex_foundation_contract

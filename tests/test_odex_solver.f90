module test_odex_solver_rhs
   use utils, only: dp
   implicit none
   real(dp) :: exp_lambda = 0.0_dp
contains
   function rhs_exp(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy(1) = exp_lambda*y(1)
   end function rhs_exp

   function rhs_oscillator(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy(1) = y(2)
      dy(2) = -y(1)
   end function rhs_oscillator
end module test_odex_solver_rhs

program test_odex_solver
   use param_mod, only: at, rt
   use solve_flow, only: intode, set_intode_strict_mode, reset_intode_fallback_stats, &
                         get_intode_fallback_context_stats, &
                         intode_status_success, intode_status_success_zero_time
   use test_odex_solver_rhs, only: exp_lambda, rhs_exp, rhs_oscillator
   use utils, only: dp
   implicit none

   integer :: failures

   at = 3.0e-14_dp
   rt = 3.0e-14_dp
   failures = 0
   call set_intode_strict_mode(.true.)
   call reset_intode_fallback_stats()

   write (*, '(A,ES12.4,A,ES12.4)') "[INIT] ODEX solver test starts. abs_tol=", at, " rel_tol=", rt

   call check_exp_case("exp_decay_forward", 1.0_dp, -2.0_dp, 1.0_dp, 2.0e-12_dp, failures)
   call check_exp_case("exp_decay_backward", 1.0_dp, -2.0_dp, -0.5_dp, 2.0e-12_dp, failures)
   call check_oscillator_case("oscillator_forward", 0.7_dp, 5.0e-12_dp, failures)
   call check_oscillator_case("oscillator_backward", -0.7_dp, 5.0e-12_dp, failures)
   call check_exp_split_consistency("exp_split_consistency", 1.0_dp, -2.0_dp, 1.0_dp, 2.0e-12_dp, failures)
   call check_osc_split_consistency("osc_split_consistency", 0.7_dp, 5.0e-12_dp, failures)
   call check_zero_time_status(failures)
   call check_no_fallbacks(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] ODEX solver test failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] ODEX solver test complete."

contains

   subroutine check_exp_case(label, y0_scalar, lambda, t, tolerance, failures)
      character(len=*), intent(in) :: label
      real(dp), intent(in) :: y0_scalar, lambda, t, tolerance
      integer, intent(inout) :: failures
      real(dp) :: y0(1), y_out(1), y_exact(1), err
      logical :: failed
      integer :: status

      exp_lambda = lambda
      y0(1) = y0_scalar
      call intode(rhs_exp, y0, t, y_out, failed, status)
      y_exact(1) = y0_scalar*exp(lambda*t)
      err = maxval(abs(y_out - y_exact))
      call report_check(label, failed, err, tolerance, failures)
      call report_status_check(label, status, intode_status_success, failures)
   end subroutine check_exp_case

   subroutine check_oscillator_case(label, t, tolerance, failures)
      character(len=*), intent(in) :: label
      real(dp), intent(in) :: t, tolerance
      integer, intent(inout) :: failures
      real(dp) :: y0(2), y_out(2), y_exact(2), err
      logical :: failed
      integer :: status

      y0 = [1.0_dp, 0.0_dp]
      call intode(rhs_oscillator, y0, t, y_out, failed, status)
      y_exact = [cos(t), -sin(t)]
      err = maxval(abs(y_out - y_exact))
      call report_check(label, failed, err, tolerance, failures)
      call report_status_check(label, status, intode_status_success, failures)
   end subroutine check_oscillator_case

   subroutine check_exp_split_consistency(label, y0_scalar, lambda, t, tolerance, failures)
      character(len=*), intent(in) :: label
      real(dp), intent(in) :: y0_scalar, lambda, t, tolerance
      integer, intent(inout) :: failures
      real(dp) :: y0(1), y_full(1), y_mid(1), y_split(1), err
      logical :: failed_full, failed_mid, failed_split
      integer :: status_full, status_mid, status_split

      exp_lambda = lambda
      y0(1) = y0_scalar
      call intode(rhs_exp, y0, t, y_full, failed_full, status_full)
      call intode(rhs_exp, y0, 0.5_dp*t, y_mid, failed_mid, status_mid)
      call intode(rhs_exp, y_mid, 0.5_dp*t, y_split, failed_split, status_split)
      err = maxval(abs(y_full - y_split))
      call report_check(label, failed_full .or. failed_mid .or. failed_split, err, tolerance, failures)
      call report_status_check(label//"_full", status_full, intode_status_success, failures)
      call report_status_check(label//"_mid", status_mid, intode_status_success, failures)
      call report_status_check(label//"_split", status_split, intode_status_success, failures)
   end subroutine check_exp_split_consistency

   subroutine check_osc_split_consistency(label, t, tolerance, failures)
      character(len=*), intent(in) :: label
      real(dp), intent(in) :: t, tolerance
      integer, intent(inout) :: failures
      real(dp) :: y0(2), y_full(2), y_mid(2), y_split(2), err
      logical :: failed_full, failed_mid, failed_split
      integer :: status_full, status_mid, status_split

      y0 = [1.0_dp, 0.0_dp]
      call intode(rhs_oscillator, y0, t, y_full, failed_full, status_full)
      call intode(rhs_oscillator, y0, 0.5_dp*t, y_mid, failed_mid, status_mid)
      call intode(rhs_oscillator, y_mid, 0.5_dp*t, y_split, failed_split, status_split)
      err = maxval(abs(y_full - y_split))
      call report_check(label, failed_full .or. failed_mid .or. failed_split, err, tolerance, failures)
      call report_status_check(label//"_full", status_full, intode_status_success, failures)
      call report_status_check(label//"_mid", status_mid, intode_status_success, failures)
      call report_status_check(label//"_split", status_split, intode_status_success, failures)
   end subroutine check_osc_split_consistency

   subroutine check_zero_time_status(failures)
      integer, intent(inout) :: failures
      real(dp) :: y0(2), y_out(2), err
      logical :: failed
      integer :: status

      y0 = [1.25_dp, -0.75_dp]
      call intode(rhs_oscillator, y0, 0.0_dp, y_out, failed, status)
      err = maxval(abs(y_out - y0))
      call report_check("zero_time", failed, err, 0.0_dp, failures)
      call report_status_check("zero_time", status, intode_status_success_zero_time, failures)
   end subroutine check_zero_time_status

   subroutine check_no_fallbacks(failures)
      integer, intent(inout) :: failures
      integer :: attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown
      integer :: fail_flowz, fail_flowzr, fail_flow, fail_unknown
      integer :: attempts, fails

      call get_intode_fallback_context_stats(attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                             fail_flowz, fail_flowzr, fail_flow, fail_unknown)
      attempts = attempt_flowz + attempt_flowzr + attempt_flow + attempt_unknown
      fails = fail_flowz + fail_flowzr + fail_flow + fail_unknown
      write (*, '(A,I0,A,I0)') "[CHECK] fallback attempts=", attempts, " fallback failures=", fails
      if (attempts /= 0 .or. fails /= 0) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] Expected analytic ODE checks to use ODEX without fallback."
      end if
      call reset_intode_fallback_stats()
   end subroutine check_no_fallbacks

   subroutine report_check(label, failed, err, tolerance, failures)
      character(len=*), intent(in) :: label
      logical, intent(in) :: failed
      real(dp), intent(in) :: err, tolerance
      integer, intent(inout) :: failures

      write (*, '(A,A,A,L1,A,ES12.4,A,ES12.4)') "[CHECK] ", trim(label), " failed=", failed, &
         " err=", err, " tol=", tolerance
      if (failed .or. err > tolerance) then
         failures = failures + 1
         write (*, '(A,A)') "[FAIL] ", trim(label)
      end if
   end subroutine report_check

   subroutine report_status_check(label, status, expected_status, failures)
      character(len=*), intent(in) :: label
      integer, intent(in) :: status, expected_status
      integer, intent(inout) :: failures

      write (*, '(A,A,A,I0,A,I0)') "[CHECK] ", trim(label), " status=", status, " expected=", expected_status
      if (status /= expected_status) then
         failures = failures + 1
         write (*, '(A,A)') "[FAIL] ", trim(label)
      end if
   end subroutine report_status_check

end program test_odex_solver

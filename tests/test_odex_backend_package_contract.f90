module test_odex_backend_package_rhs
   use utils, only: dp
   implicit none
   real(dp) :: exp_lambda = 0.0_dp
contains
   function rhs_exp(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy(1) = exp_lambda*y(1)
   end function rhs_exp
end module test_odex_backend_package_rhs

program test_odex_backend_package_contract
   use odex_backend, only: build_nsteps, odex_default_options, odex_integrate_endpoint, &
                           odex_options, odex_result, odex_status_failure_invalid, odex_status_success, &
                           odex_status_success_zero_time, odex_step_sequence_iwork3, &
                           odex_stability_control_conservative, odex_workspace
   use test_odex_backend_package_rhs, only: exp_lambda, rhs_exp
   use utils, only: dp
   implicit none

   integer :: failures

   failures = 0
   write (*, '(A)') "[INIT] standalone ODEX backend package contract starts."

   call check_iwork3_sequence(failures)
   call check_endpoint_accuracy(failures)
   call check_forward_backward(failures)
   call check_conservative_stability_surface(failures)
   call check_invalid_options_failure(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] standalone ODEX backend package failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] standalone ODEX backend package contract complete."

contains

   subroutine check_iwork3_sequence(failures)
      integer, intent(inout) :: failures
      integer :: actual(11), expected(11)
      logical :: ok

      expected = [2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96]
      call build_nsteps(size(actual), actual)
      ok = all(actual == expected)
      write (*, '(A,L1,*(1X,I0))') "[CHECK] package_iwork3 ok=", ok, actual
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] standalone backend IWORK(3) sequence changed."
      end if
   end subroutine check_iwork3_sequence

   subroutine check_endpoint_accuracy(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_state
      real(dp) :: y0(1), y_out(1), y_exact(1), err
      logical :: failed, ok

      call odex_default_options(options, 3.0e-14_dp, 3.0e-14_dp)
      exp_lambda = -2.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      y_exact(1) = y0(1)*exp(exp_lambda)
      err = maxval(abs(y_out - y_exact))
      ok = (.not. failed) .and. result_state%status == odex_status_success .and. &
           result_state%endpoint_available .and. err <= 2.0e-12_dp
      write (*, '(A,L1,A,I0,A,ES12.4)') "[CHECK] package_endpoint_accuracy ok=", ok, &
         " status=", result_state%status, " err=", err
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] standalone backend endpoint accuracy changed."
      end if
   end subroutine check_endpoint_accuracy

   subroutine check_forward_backward(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_mid, result_back
      real(dp) :: y0(1), y_mid(1), y_back(1), err
      logical :: failed_mid, failed_back, ok

      call odex_default_options(options, 3.0e-14_dp, 3.0e-14_dp)
      exp_lambda = -1.3_dp
      y0(1) = 0.8125_dp
      call odex_integrate_endpoint(rhs_exp, y0, 0.75_dp, y_mid, failed_mid, result_mid, workspace, options)
      call odex_integrate_endpoint(rhs_exp, y_mid, -0.75_dp, y_back, failed_back, result_back, workspace, options)
      err = maxval(abs(y_back - y0))
      ok = (.not. failed_mid) .and. (.not. failed_back) .and. &
           result_mid%status == odex_status_success .and. result_back%status == odex_status_success .and. &
           err <= 2.0e-11_dp
      write (*, '(A,L1,A,I0,A,I0,A,ES12.4)') "[CHECK] package_forward_backward ok=", ok, &
         " status_mid=", result_mid%status, " status_back=", result_back%status, " err=", err
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] standalone backend forward/backward endpoint composition changed."
      end if
   end subroutine check_forward_backward

   subroutine check_conservative_stability_surface(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_state
      real(dp) :: y0(1), y_out(1)
      logical :: failed, ok

      call odex_default_options(options, 1.0e-10_dp, 1.0e-10_dp)
      options%stability_control = odex_stability_control_conservative
      options%stability_growth_limit = 1.0001_dp
      exp_lambda = 1.0e6_dp
      y0(1) = 1.0e6_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0e-8_dp, y_out, failed, result_state, workspace, options)
      ok = (.not. failed) .and. result_state%status == odex_status_success .and. &
           result_state%stability_rejects > 0 .and. result_state%rejected_steps >= result_state%stability_rejects
      write (*, '(A,L1,A,I0,A,I0,A,I0)') "[CHECK] package_stability_surface ok=", ok, &
         " status=", result_state%status, " rejects=", result_state%rejected_steps, &
         " stability=", result_state%stability_rejects
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] conservative stability-control surface did not fire as expected."
      end if
   end subroutine check_conservative_stability_surface

   subroutine check_invalid_options_failure(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_state
      real(dp) :: y0(1), y_out(1)
      logical :: failed, ok

      call odex_default_options(options, 3.0e-14_dp, 3.0e-14_dp)
      options%step_sequence = odex_step_sequence_iwork3 + 100
      exp_lambda = -2.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      ok = failed .and. result_state%status == odex_status_failure_invalid .and. &
           .not. result_state%endpoint_available
      write (*, '(A,L1,A,I0,A,L1)') "[CHECK] package_invalid_options ok=", ok, &
         " status=", result_state%status, " endpoint=", result_state%endpoint_available
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] standalone backend invalid-option failure contract changed."
      end if
   end subroutine check_invalid_options_failure

end program test_odex_backend_package_contract

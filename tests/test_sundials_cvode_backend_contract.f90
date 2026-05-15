module test_sundials_cvode_backend_rhs
   use utils, only: dp
   implicit none

   type :: rhs_context_t
      real(dp) :: lambda = 0.0_dp
   end type rhs_context_t

   real(dp) :: exp_lambda = 0.0_dp

contains

   function rhs_exp(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy = exp_lambda*y
   end function rhs_exp

   function rhs_exp_context(y, context) result(dy)
      real(dp), intent(in) :: y(:)
      class(*), intent(inout) :: context
      real(dp) :: dy(size(y))

      dy = 0.0_dp
      select type (rhs_context => context)
      type is (rhs_context_t)
         dy = rhs_context%lambda*y
      end select
   end function rhs_exp_context

end module test_sundials_cvode_backend_rhs

program test_sundials_cvode_backend_contract
   use odex_backend, only: odex_backend_kind_sundials_cvode, odex_default_options, odex_integrate_endpoint, &
                           odex_integrate_endpoint_context, odex_options, odex_result, odex_status_success, &
                           odex_status_success_zero_time, odex_sundials_cvode_available, odex_workspace
   use runtime_env_mod, only: parse_logical_env
   use test_sundials_cvode_backend_rhs, only: exp_lambda, rhs_context_t, rhs_exp, rhs_exp_context
   use utils, only: dp
   implicit none

   integer :: failures
   logical :: expect_available

   failures = 0
   expect_available = .false.
   call parse_logical_env("TLTM_EXPECT_SUNDIALS_CVODE", expect_available)

   write (*, '(A)') "[INIT] SUNDIALS CVODE backend contract starts."
   write (*, '(A,L1)') "[CHECK] sundials_cvode_available=", odex_sundials_cvode_available()

   if (.not. odex_sundials_cvode_available()) then
      if (expect_available) then
         write (*, '(A)') "[FAIL] SUNDIALS CVODE bridge was expected but is not available."
         error stop 1
      end if
      write (*, '(A)') "[SKIP] SUNDIALS CVODE bridge is stubbed in this build."
      stop
   end if

   call check_endpoint_accuracy(failures)
   call check_forward_backward(failures)
   call check_context_endpoint_accuracy(failures)
   call check_zero_time(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] SUNDIALS CVODE backend contract failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] SUNDIALS CVODE backend contract complete."

contains

   subroutine check_endpoint_accuracy(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_state
      real(dp) :: y0(2), y_out(2), y_exact(2), err
      logical :: failed, ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      options%backend = odex_backend_kind_sundials_cvode
      options%cvode_fixedpoint_m = 2
      options%cvode_max_order = 8
      exp_lambda = -2.0_dp
      y0 = [1.0_dp, -0.25_dp]

      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed, result_state, workspace, options)

      y_exact = y0*exp(exp_lambda)
      err = maxval(abs(y_out - y_exact))
      ok = (.not. failed) .and. result_state%status == odex_status_success .and. &
           result_state%endpoint_available .and. result_state%cvode_backend_used .and. &
           result_state%cvode_rhs_evals > 0 .and. result_state%final_order > 0 .and. err <= 1.0e-9_dp
      write (*, '(A,L1,A,I0,A,ES12.4,A,I0,A,I0,A,I0)') "[CHECK] cvode_endpoint_accuracy ok=", ok, &
         " status=", result_state%status, " err=", err, " steps=", result_state%accepted_steps, &
         " rhs_evals=", result_state%cvode_rhs_evals, " final_order=", result_state%final_order
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] SUNDIALS CVODE endpoint accuracy contract failed."
      end if
   end subroutine check_endpoint_accuracy

   subroutine check_forward_backward(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_mid, result_back
      real(dp) :: y0(2), y_mid(2), y_back(2), err
      logical :: failed_mid, failed_back, ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      options%backend = odex_backend_kind_sundials_cvode
      exp_lambda = -1.3_dp
      y0 = [0.8125_dp, -0.3125_dp]

      call odex_integrate_endpoint(rhs_exp, y0, 0.75_dp, y_mid, failed_mid, result_mid, workspace, options)
      call odex_integrate_endpoint(rhs_exp, y_mid, -0.75_dp, y_back, failed_back, result_back, workspace, options)

      err = maxval(abs(y_back - y0))
      ok = (.not. failed_mid) .and. (.not. failed_back) .and. &
           result_mid%status == odex_status_success .and. result_back%status == odex_status_success .and. &
           err <= 1.0e-8_dp
      write (*, '(A,L1,A,I0,A,I0,A,ES12.4)') "[CHECK] cvode_forward_backward ok=", ok, &
         " status_mid=", result_mid%status, " status_back=", result_back%status, " err=", err
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] SUNDIALS CVODE forward/backward endpoint composition failed."
      end if
   end subroutine check_forward_backward

   subroutine check_context_endpoint_accuracy(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_state
      type(rhs_context_t), target :: rhs_context
      real(dp) :: y0(2), y_out(2), y_exact(2), err
      logical :: failed, ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      options%backend = odex_backend_kind_sundials_cvode
      rhs_context%lambda = -0.7_dp
      y0 = [0.5_dp, 2.0_dp]

      call odex_integrate_endpoint_context(rhs_exp_context, y0, 1.25_dp, y_out, failed, result_state, &
                                           workspace, options, rhs_context)

      y_exact = y0*exp(rhs_context%lambda*1.25_dp)
      err = maxval(abs(y_out - y_exact))
      ok = (.not. failed) .and. result_state%status == odex_status_success .and. &
           result_state%endpoint_available .and. err <= 1.0e-9_dp
      write (*, '(A,L1,A,I0,A,ES12.4)') "[CHECK] cvode_context_endpoint ok=", ok, &
         " status=", result_state%status, " err=", err
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] SUNDIALS CVODE context endpoint contract failed."
      end if
   end subroutine check_context_endpoint_accuracy

   subroutine check_zero_time(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_state
      real(dp) :: y0(2), y_out(2), err
      logical :: failed, ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      options%backend = odex_backend_kind_sundials_cvode
      exp_lambda = -2.0_dp
      y0 = [1.0_dp, -0.25_dp]

      call odex_integrate_endpoint(rhs_exp, y0, 0.0_dp, y_out, failed, result_state, workspace, options)

      err = maxval(abs(y_out - y0))
      ok = (.not. failed) .and. result_state%status == odex_status_success_zero_time .and. err == 0.0_dp
      write (*, '(A,L1,A,I0,A,ES12.4)') "[CHECK] cvode_zero_time ok=", ok, &
         " status=", result_state%status, " err=", err
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] SUNDIALS CVODE zero-time contract failed."
      end if
   end subroutine check_zero_time

end program test_sundials_cvode_backend_contract

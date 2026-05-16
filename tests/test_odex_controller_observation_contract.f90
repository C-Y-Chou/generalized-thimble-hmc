module test_odex_controller_observation_rhs
   use, intrinsic :: ieee_arithmetic, only: ieee_quiet_nan, ieee_value
   use utils, only: dp
   implicit none
   real(dp) :: exp_lambda = 0.0_dp
contains
   function rhs_exp(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy = exp_lambda*y
   end function rhs_exp

   function rhs_zero(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy = 0.0_dp
   end function rhs_zero

   function rhs_nan(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy = ieee_value(0.0_dp, ieee_quiet_nan)
   end function rhs_nan

   function rhs_late_nan(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      if (any(abs(y - 1.0_dp) > 1.0e-14_dp)) then
         dy = ieee_value(0.0_dp, ieee_quiet_nan)
      else
         dy = 1.0_dp
      end if
   end function rhs_late_nan
end module test_odex_controller_observation_rhs

program test_odex_controller_observation_contract
   use odex_backend, only: build_nsteps, ensure_odex_workspace_object, odex_default_options, &
                           odex_integrate_endpoint, odex_observe_controller_estimate, &
                           odex_observe_h_min, odex_observe_initial_step, &
                           odex_observe_large_error_threshold, odex_observe_stability_reject, &
                           odex_options, odex_reason_h_min, odex_reason_invalid, odex_reason_max_steps, odex_result, &
                           odex_status_failure_h_min, odex_status_failure_invalid, &
                           odex_status_failure_max_steps, odex_status_success, &
                           odex_stability_control_conservative, odex_workspace
   use test_odex_controller_observation_rhs, only: exp_lambda, rhs_exp, rhs_late_nan, rhs_nan, rhs_zero
   use utils, only: dp
   implicit none

   integer :: failures

   failures = 0
   write (*, '(A)') "[INIT] ODEX controller observation contract starts."

   call check_initial_step_and_h_min(failures)
   call check_step_sequence_and_work_estimate(failures)
   call check_signed_endpoint_interval(failures)
   call check_failure_classification_surfaces(failures)
   call check_stability_observation(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] ODEX controller observation failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] ODEX controller observation contract complete."

contains

   subroutine check_initial_step_and_h_min(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      real(dp) :: h_min, h_min_fp, h_min_tol, h_min_span
      real(dp) :: expected_fp, expected_tol, expected_span, expected_h_min
      real(dp) :: t_short, t_long, h_short, h_long
      logical :: ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-10_dp)
      t_short = 0.25_dp
      t_long = -5.0_dp

      call odex_observe_h_min(options, t_short, h_min, h_min_fp, h_min_tol, h_min_span)
      expected_fp = options%h_min_c_fp*epsilon(1.0_dp)*max(1.0_dp, abs(t_short))
      expected_tol = options%h_min_c_tol*max(options%abs_tol, options%rel_tol, epsilon(1.0_dp))
      expected_span = options%h_min_c_span*abs(t_short)
      expected_h_min = max(expected_fp, min(expected_tol, expected_span))
      h_short = odex_observe_initial_step(options, t_short)
      h_long = odex_observe_initial_step(options, t_long)

      ok = nearly_equal(h_min_fp, expected_fp, 1.0e-15_dp) .and. &
           nearly_equal(h_min_tol, expected_tol, 1.0e-18_dp) .and. &
           nearly_equal(h_min_span, expected_span, 1.0e-18_dp) .and. &
           nearly_equal(h_min, expected_h_min, 1.0e-18_dp) .and. &
           nearly_equal(h_short, t_short*options%initial_step_fraction, 1.0e-18_dp) .and. &
           nearly_equal(h_long, t_long*options%initial_step_fraction, 1.0e-18_dp)
      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] h0_hmin_observation ok=", ok, &
         " h_short=", h_short, " h_long=", h_long, " h_min=", h_min
      call count_failure(ok, "[FAIL] initial-step or h-min observation changed.", failures)
   end subroutine check_initial_step_and_h_min

   subroutine check_step_sequence_and_work_estimate(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      integer :: actual(6), expected(6), order_idx
      real(dp) :: h, er1, h_candidate, work_estimate, scale, ak_expected
      real(dp) :: h_floor_candidate, work_floor_estimate, facmin, floor_scale
      logical :: ok

      expected = [2, 4, 6, 8, 12, 16]
      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      call build_nsteps(size(actual), actual)
      call ensure_odex_workspace_object(workspace, 6, 1)

      order_idx = 4
      h = -0.125_dp
      er1 = 0.25_dp
      scale = 0.94_dp*(0.65_dp/er1)**(1.0_dp/(2.0_dp*real(order_idx, dp) - 1.0_dp))
      facmin = options%step_size_bound_fac1**(1.0_dp/(2.0_dp*real(order_idx, dp) - 1.0_dp))
      scale = min(1.0_dp/facmin, max(facmin/options%step_size_bound_fac2, scale))
      call odex_observe_controller_estimate(workspace, h, er1, order_idx, h_candidate, work_estimate, options)
      ak_expected = 1.0_dp + sum(real(expected(1:order_idx), dp))

      call odex_observe_controller_estimate(workspace, abs(h), 0.0_dp, order_idx, &
                                            h_floor_candidate, work_floor_estimate, options)
      floor_scale = 0.94_dp*(0.65_dp/1.0e-14_dp)**(1.0_dp/(2.0_dp*real(order_idx, dp) - 1.0_dp))
      floor_scale = min(1.0_dp/facmin, max(facmin/options%step_size_bound_fac2, floor_scale))

      ok = all(actual == expected) .and. h_candidate < 0.0_dp .and. work_estimate > 0.0_dp .and. &
           nearly_equal(h_candidate, h*scale, 1.0e-14_dp) .and. &
           nearly_equal(work_estimate, ak_expected/(abs(h)*scale), 1.0e-12_dp) .and. &
           nearly_equal(h_floor_candidate, abs(h)*floor_scale, 1.0e-6_dp) .and. &
           work_floor_estimate > 0.0_dp .and. &
           nearly_equal(odex_observe_large_error_threshold(order_idx), real((order_idx*order_idx + 1)**2, dp), &
                        1.0e-12_dp)
      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] sequence_work_observation ok=", ok, &
         " h_candidate=", h_candidate, " work=", work_estimate, " h_floor=", h_floor_candidate
      call count_failure(ok, "[FAIL] step sequence, signed estimate, error floor, or threshold changed.", failures)
   end subroutine check_step_sequence_and_work_estimate

   subroutine check_signed_endpoint_interval(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_state
      real(dp) :: y0(1), y_out(1), expected(1), err
      logical :: failed, ok

      call odex_default_options(options, 3.0e-14_dp, 3.0e-14_dp)
      exp_lambda = -0.7_dp
      y0(1) = 0.75_dp
      call odex_integrate_endpoint(rhs_exp, y0, -0.25_dp, y_out, failed, result_state, workspace, options)
      expected = y0*exp(exp_lambda*(-0.25_dp))
      err = maxval(abs(y_out - expected))
      ok = (.not. failed) .and. result_state%status == odex_status_success .and. &
           result_state%final_step_size < 0.0_dp .and. err <= 3.0e-12_dp
      write (*, '(A,L1,A,I0,A,ES12.4,A,ES12.4)') "[CHECK] signed_endpoint_observation ok=", ok, &
         " status=", result_state%status, " final_h=", result_state%final_step_size, " err=", err
      call count_failure(ok, "[FAIL] signed negative endpoint interval behavior changed.", failures)
   end subroutine check_signed_endpoint_interval

   subroutine check_failure_classification_surfaces(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_state
      real(dp) :: y0(1), y_out(1)
      logical :: failed, ok_budget, ok_hmin, ok_initial_invalid, ok_late_invalid

      call odex_default_options(options, 1.0e-10_dp, 1.0e-10_dp)
      options%max_steps = 1
      options%initial_step_fraction = 0.25_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_zero, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      ok_budget = failed .and. result_state%status == odex_status_failure_max_steps .and. &
                  result_state%failure_reason == odex_reason_max_steps .and. &
                  result_state%accepted_steps == 1 .and. &
                  nearly_equal(result_state%t_remaining, 0.75_dp, 1.0e-14_dp) .and. &
                  .not. result_state%endpoint_available
      write (*, '(A,L1,A,I0,A,I0,A,I0,A,ES12.4)') "[CHECK] max_steps_failure_observation ok=", ok_budget, &
         " status=", result_state%status, " accepted=", result_state%accepted_steps, &
         " rejected=", result_state%rejected_steps, " t_remaining=", result_state%t_remaining
      call count_failure(ok_budget, "[FAIL] max-step failure classification changed.", failures)

      call odex_default_options(options, 1.0e-10_dp, 1.0e-10_dp)
      options%max_steps = 1000
      options%stability_control = odex_stability_control_conservative
      options%stability_growth_limit = 1.0001_dp
      options%h_min_c_fp = 0.0_dp
      options%h_min_c_tol = 1.0e12_dp
      options%h_min_c_span = 0.5_dp
      exp_lambda = 1.0e6_dp
      y0(1) = 1.0e6_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      ok_hmin = failed .and. result_state%status == odex_status_failure_h_min .and. &
                result_state%failure_reason == odex_reason_h_min .and. &
                result_state%rejected_steps > 0 .and. .not. result_state%endpoint_available
      write (*, '(A,L1,A,I0,A,I0,A,ES12.4)') "[CHECK] hmin_failure_observation ok=", ok_hmin, &
         " status=", result_state%status, " rejected=", result_state%rejected_steps, &
         " final_h=", result_state%final_step_size
      call count_failure(ok_hmin, "[FAIL] h-min rejection classification changed.", failures)

      call odex_default_options(options, 1.0e-10_dp, 1.0e-10_dp)
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_nan, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      ok_initial_invalid = failed .and. result_state%status == odex_status_failure_invalid .and. &
                           result_state%failure_reason == odex_reason_invalid .and. &
                           result_state%accepted_steps == 0 .and. result_state%rejected_steps == 0 .and. &
                           .not. result_state%endpoint_available
      write (*, '(A,L1,A,I0,A,I0,A,I0)') "[CHECK] initial_invalid_rhs_observation ok=", ok_initial_invalid, &
         " status=", result_state%status, " accepted=", result_state%accepted_steps, &
         " rejected=", result_state%rejected_steps
      call count_failure(ok_initial_invalid, "[FAIL] initial invalid-RHS classification changed.", failures)

      call odex_integrate_endpoint(rhs_late_nan, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      ok_late_invalid = failed .and. result_state%status == odex_status_failure_invalid .and. &
                        result_state%failure_reason == odex_reason_invalid .and. &
                        result_state%accepted_steps == 0 .and. result_state%rejected_steps == 0 .and. &
                        .not. result_state%endpoint_available
      write (*, '(A,L1,A,I0,A,I0,A,I0)') "[CHECK] later_invalid_rhs_observation ok=", ok_late_invalid, &
         " status=", result_state%status, " accepted=", result_state%accepted_steps, &
         " rejected=", result_state%rejected_steps
      call count_failure(ok_late_invalid, "[FAIL] later invalid-RHS classification changed.", failures)
   end subroutine check_failure_classification_surfaces

   subroutine check_stability_observation(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      real(dp) :: values(1)
      logical :: reject_none, reject_large, reject_small_dt, ok

      call odex_default_options(options, 1.0e-10_dp, 1.0e-10_dp)
      values(1) = 20.0_dp
      reject_none = odex_observe_stability_reject(values, 1.0_dp, 0.1_dp, options)

      options%stability_control = odex_stability_control_conservative
      options%stability_growth_limit = 4.0_dp
      reject_large = odex_observe_stability_reject(values, 1.0_dp, 0.1_dp, options)
      reject_small_dt = odex_observe_stability_reject(values, 1.0_dp, 0.01_dp, options)

      ok = (.not. reject_none) .and. reject_large .and. (.not. reject_small_dt)
      write (*, '(A,L1,A,L1,A,L1,A,L1)') "[CHECK] stability_observation ok=", ok, &
         " none=", reject_none, " large=", reject_large, " small_dt=", reject_small_dt
      call count_failure(ok, "[FAIL] stability-control observation changed.", failures)
   end subroutine check_stability_observation

   logical function nearly_equal(actual, expected, tol) result(ok)
      real(dp), intent(in) :: actual, expected, tol

      ok = abs(actual - expected) <= tol*max(1.0_dp, abs(expected))
   end function nearly_equal

   subroutine count_failure(ok, message, failures)
      logical, intent(in) :: ok
      character(len=*), intent(in) :: message
      integer, intent(inout) :: failures

      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') message
      end if
   end subroutine count_failure

end program test_odex_controller_observation_contract

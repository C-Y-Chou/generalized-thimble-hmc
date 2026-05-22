module test_odex_backend_package_rhs
   use, intrinsic :: ieee_arithmetic, only: ieee_quiet_nan, ieee_value
   use utils, only: dp
   implicit none
   real(dp) :: exp_lambda = 0.0_dp
   type :: dummy_context_t
      integer :: unused = 0
   end type dummy_context_t
contains
   function rhs_exp(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy = 0.0_dp
      dy(1) = exp_lambda*y(1)
   end function rhs_exp

   function rhs_nan(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy = ieee_value(0.0_dp, ieee_quiet_nan)
   end function rhs_nan

   function rhs_exp_context(y, context) result(dy)
      real(dp), intent(in) :: y(:)
      class(*), intent(inout) :: context
      real(dp) :: dy(size(y))

      dy = 0.0_dp
      select type (context)
      type is (dummy_context_t)
         context%unused = context%unused + 0
      class default
         continue
      end select
      dy(1) = exp_lambda*y(1)
   end function rhs_exp_context

   function rhs_nan_context(y, context) result(dy)
      real(dp), intent(in) :: y(:)
      class(*), intent(inout) :: context
      real(dp) :: dy(size(y))

      select type (context)
      type is (dummy_context_t)
         context%unused = context%unused + 0
      class default
         continue
      end select
      dy = ieee_value(0.0_dp, ieee_quiet_nan)
   end function rhs_nan_context
end module test_odex_backend_package_rhs

program test_odex_backend_package_contract
   use odex_backend, only: build_nsteps, odex_backend_kind_dop853, odex_controller_policy_hairer_experimental, &
                           odex_default_options, odex_integrate_endpoint, odex_integrate_endpoint_context, &
                           odex_options, odex_reason_h_min, odex_reason_max_rhs_evals, odex_reason_max_rejects, &
                           odex_reason_stiffness, odex_result, odex_status_failure_h_min, &
                           odex_status_failure_invalid, odex_status_failure_max_rhs_evals, &
                           odex_status_failure_max_rejects, odex_status_failure_max_steps, &
                           odex_status_failure_stiffness, &
                           odex_status_success, odex_status_success_zero_time, odex_observe_stability_reject, &
                           odex_step_sequence_iwork3, odex_stability_control_conservative, odex_workspace
   use test_odex_backend_package_rhs, only: dummy_context_t, exp_lambda, rhs_exp, rhs_exp_context, &
                                            rhs_nan, rhs_nan_context
   use utils, only: dp
   implicit none

   integer :: failures

   failures = 0
   write (*, '(A)') "[INIT] standalone ODEX backend package contract starts."

   call check_iwork3_sequence(failures)
   call check_endpoint_accuracy(failures)
   call check_dop853_backend_contract(failures)
   call check_hairer_experimental_endpoint_accuracy(failures)
   call check_hairer_experimental_analytic_gates(failures)
   call check_forward_backward(failures)
   call check_conservative_stability_observer_surface(failures)
   call check_invalid_options_failure(failures)
   call check_invalid_rhs_failure(failures)
   call check_output_size_guard(failures)

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
      type(odex_workspace) :: workspace, workspace_context
      type(odex_result) :: result_state, result_context
      type(dummy_context_t) :: rhs_context
      real(dp) :: y0(1), y_out(1), y_out_context(1), y_exact(1), err, err_context
      logical :: failed, failed_context, ok, ok_context

      call odex_default_options(options, 3.0e-14_dp, 3.0e-14_dp)
      exp_lambda = -2.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      y_exact(1) = y0(1)*exp(exp_lambda)
      err = maxval(abs(y_out - y_exact))
      ok = (.not. failed) .and. result_state%status == odex_status_success .and. &
           result_state%endpoint_available .and. result_state%final_order >= 2 .and. &
           result_state%odex_rhs_evals > 0 .and. &
           result_state%odex_midpoint_rows > 0 .and. &
           result_state%odex_accept_k_minus_1 + result_state%odex_accept_k + result_state%odex_accept_k_plus_1 == &
           result_state%accepted_steps .and. result_state%accepted_steps < 1000 .and. &
           result_state%odex_rhs_evals < 100000 .and. &
           result_state%odex_hairer_policy_steps == result_state%accepted_steps + result_state%rejected_steps .and. &
           result_state%odex_tltm_policy_steps == 0 .and. result_state%odex_first_step_entries == 1 .and. &
           result_state%odex_last_step_entries == 1 .and. &
           result_state%odex_row_j1_calls + result_state%odex_row_j2_calls + result_state%odex_row_jge3_calls == &
           result_state%odex_midpoint_rows .and. result_state%odex_error_estimates > 0 .and. &
           result_state%odex_row_j1_no_error_returns == result_state%odex_row_j1_calls .and. &
           result_state%odex_hairer_scal_estimates == result_state%odex_error_estimates .and. &
           result_state%odex_default_scal_estimates == 0 .and. &
           result_state%odex_kopt_accept_updates == result_state%accepted_steps .and. &
           result_state%odex_kopt_demotions + result_state%odex_kopt_keeps + result_state%odex_kopt_promotions == &
           result_state%odex_kopt_accept_updates .and. &
           result_state%odex_errold_checks == result_state%odex_error_estimates .and. &
           result_state%odex_atov_events == 0 .and. &
           result_state%odex_after_reject_clamps == 0 .and. &
           err <= 2.0e-12_dp
      write (*, '(A,L1,A,I0,A,ES12.4)') "[CHECK] package_endpoint_accuracy ok=", ok, &
         " status=", result_state%status, " err=", err
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] standalone backend default Hairer endpoint accuracy changed."
      end if
   end subroutine check_endpoint_accuracy

   subroutine check_dop853_backend_contract(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options, budget_options, hmin_options, maxstep_options, reject_options, stiff_options
      type(odex_workspace) :: workspace, workspace_context
      type(odex_result) :: result_state, result_context, budget_result, hmin_result, maxstep_result
      type(odex_result) :: reject_result, stiff_result
      type(dummy_context_t) :: rhs_context
      real(dp) :: y0(1), y_out(1), y_out_context(1), y_exact(1), err, err_context, err_maxstep
      logical :: failed, failed_context, failed_budget, failed_hmin, failed_maxstep, failed_reject, failed_stiff
      logical :: ok, ok_context, budget_ok, hmin_ok, maxstep_ok, reject_ok, stiff_ok

      call odex_default_options(options, 1.0e-11_dp, 1.0e-11_dp)
      options%backend = odex_backend_kind_dop853
      options%initial_step_fraction = 0.02_dp
      exp_lambda = -2.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      y_exact(1) = y0(1)*exp(exp_lambda)
      err = maxval(abs(y_out - y_exact))
      ok = (.not. failed) .and. result_state%status == odex_status_success .and. &
           result_state%endpoint_available .and. result_state%final_order == 8 .and. &
           result_state%accepted_steps > 0 .and. result_state%accepted_steps < 1000 .and. &
           result_state%odex_rhs_evals > 0 .and. &
           result_state%odex_rhs_evals <= 2 + 12*result_state%odex_error_estimates .and. &
           result_state%odex_error_estimates == result_state%accepted_steps + result_state%rejected_steps .and. &
           result_state%odex_hairer_policy_steps == 0 .and. result_state%odex_tltm_policy_steps == 0 .and. &
           err <= 1.0e-9_dp

      call odex_integrate_endpoint_context(rhs_exp_context, y0, 1.0_dp, y_out_context, failed_context, &
                                           result_context, workspace_context, options, rhs_context)
      err_context = maxval(abs(y_out_context - y_exact))
      ok_context = (.not. failed_context) .and. result_context%status == odex_status_success .and. &
                   result_context%endpoint_available .and. result_context%final_order == 8 .and. &
                   result_context%accepted_steps > 0 .and. &
                   result_context%odex_error_estimates == result_context%accepted_steps + &
                   result_context%rejected_steps .and. err_context <= 1.0e-9_dp

      call odex_default_options(budget_options, 1.0e-12_dp, 1.0e-12_dp)
      budget_options%backend = odex_backend_kind_dop853
      budget_options%initial_step_fraction = 0.5_dp
      budget_options%dop853_max_rhs_evals = 12
      exp_lambda = -100.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed_budget, budget_result, workspace, budget_options)
      budget_ok = failed_budget .and. budget_result%status == odex_status_failure_max_rhs_evals .and. &
                  budget_result%failure_reason == odex_reason_max_rhs_evals .and. &
                  .not. budget_result%endpoint_available .and. budget_result%odex_rhs_evals <= 12 .and. &
                  budget_result%odex_error_estimates <= 1

      call odex_default_options(hmin_options, 1.0e-10_dp, 1.0e-10_dp)
      hmin_options%backend = odex_backend_kind_dop853
      hmin_options%initial_step_fraction = 0.01_dp
      hmin_options%dop853_min_step = 2.0_dp
      exp_lambda = -2.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed_hmin, hmin_result, workspace, hmin_options)
      hmin_ok = failed_hmin .and. hmin_result%status == odex_status_failure_h_min .and. &
                hmin_result%failure_reason == odex_reason_h_min .and. .not. hmin_result%endpoint_available .and. &
                hmin_result%accepted_steps == 0 .and. hmin_result%rejected_steps == 0 .and. &
                hmin_result%odex_rhs_evals == 0

      call odex_default_options(maxstep_options, 1.0e-10_dp, 1.0e-10_dp)
      maxstep_options%backend = odex_backend_kind_dop853
      maxstep_options%dop853_max_step = 0.05_dp
      exp_lambda = -2.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed_maxstep, maxstep_result, workspace, maxstep_options)
      err_maxstep = maxval(abs(y_out - y_exact))
      maxstep_ok = (.not. failed_maxstep) .and. maxstep_result%status == odex_status_success .and. &
                   maxstep_result%accepted_steps >= 20 .and. abs(maxstep_result%final_step_size) <= 0.0500000001_dp .and. &
                   err_maxstep <= 1.0e-9_dp

      call odex_default_options(reject_options, 1.0e-14_dp, 1.0e-14_dp)
      reject_options%backend = odex_backend_kind_dop853
      reject_options%dop853_hinit_enabled = .false.
      reject_options%initial_step_fraction = 1.0_dp
      reject_options%dop853_max_reject = 1
      exp_lambda = -100.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed_reject, reject_result, workspace, reject_options)
      reject_ok = failed_reject .and. reject_result%status == odex_status_failure_max_rejects .and. &
                  reject_result%failure_reason == odex_reason_max_rejects .and. reject_result%rejected_steps == 1 .and. &
                  reject_result%odex_error_estimates == 1

      call odex_default_options(stiff_options, 1.0e-10_dp, 1.0e-10_dp)
      stiff_options%backend = odex_backend_kind_dop853
      stiff_options%dop853_stiffness_check_interval = 1
      stiff_options%dop853_stiffness_max_hits = 1
      stiff_options%dop853_stiffness_threshold = 1.0e-12_dp
      exp_lambda = -2.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed_stiff, stiff_result, workspace, stiff_options)
      stiff_ok = failed_stiff .and. stiff_result%status == odex_status_failure_stiffness .and. &
                 stiff_result%failure_reason == odex_reason_stiffness .and. stiff_result%accepted_steps >= 1

      write (*, '(A,L1,A,L1,A,L1,A,L1,A,L1,A,L1,A,L1,A,I0,A,I0,A,ES12.4)') "[CHECK] dop853_backend ok=", ok, &
         " context=", ok_context, " budget=", budget_ok, " hmin=", hmin_ok, " maxstep=", maxstep_ok, &
         " reject=", reject_ok, " stiff=", stiff_ok, &
         " accepted=", result_state%accepted_steps, " rhs=", result_state%odex_rhs_evals, " err=", err
      if (.not. (ok .and. ok_context .and. budget_ok .and. hmin_ok .and. maxstep_ok .and. reject_ok .and. stiff_ok)) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] DOP853 backend contract changed."
         write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0)') "[DETAIL] dop853 status=", result_state%status, &
            " accepted=", result_state%accepted_steps, " rejected=", result_state%rejected_steps, &
            " rhs=", result_state%odex_rhs_evals, " attempts=", result_state%odex_error_estimates
         write (*, '(A,I0,A,I0,A,I0,A,I0)') "[DETAIL] dop853 budget status=", budget_result%status, &
            " rhs=", budget_result%odex_rhs_evals, " accepted=", budget_result%accepted_steps, &
            " rejected=", budget_result%rejected_steps
         write (*, '(A,I0,A,I0,A,I0)') "[DETAIL] dop853 hmin status=", hmin_result%status, &
            " reason=", hmin_result%failure_reason, " rhs=", hmin_result%odex_rhs_evals
         write (*, '(A,I0,A,I0,A,I0,A,I0)') "[DETAIL] dop853 maxstep status=", maxstep_result%status, &
            " accepted=", maxstep_result%accepted_steps, " rejected=", maxstep_result%rejected_steps, &
            " rhs=", maxstep_result%odex_rhs_evals
         write (*, '(A,I0,A,I0,A,I0,A,I0)') "[DETAIL] dop853 reject status=", reject_result%status, &
            " reason=", reject_result%failure_reason, " rejected=", reject_result%rejected_steps, &
            " attempts=", reject_result%odex_error_estimates
         write (*, '(A,I0,A,I0,A,I0,A,I0)') "[DETAIL] dop853 stiff status=", stiff_result%status, &
            " reason=", stiff_result%failure_reason, " accepted=", stiff_result%accepted_steps, &
            " attempts=", stiff_result%odex_error_estimates
      end if
   end subroutine check_dop853_backend_contract

   subroutine check_hairer_experimental_endpoint_accuracy(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace, workspace_context
      type(odex_result) :: result_state, result_context
      type(dummy_context_t) :: rhs_context
      real(dp) :: y0(1), y_out(1), y_out_context(1), y_exact(1), err, err_context
      logical :: failed, failed_context, ok, ok_context

      call odex_default_options(options, 3.0e-14_dp, 3.0e-14_dp)
      options%controller_policy = odex_controller_policy_hairer_experimental
      exp_lambda = -2.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      y_exact(1) = y0(1)*exp(exp_lambda)
      err = maxval(abs(y_out - y_exact))
      ok = (.not. failed) .and. result_state%status == odex_status_success .and. &
           result_state%endpoint_available .and. result_state%final_order >= 2 .and. &
           result_state%odex_rhs_evals > 0 .and. result_state%odex_midpoint_rows > 0 .and. &
           result_state%odex_accept_k_minus_1 + result_state%odex_accept_k + result_state%odex_accept_k_plus_1 == &
           result_state%accepted_steps .and. result_state%accepted_steps < 1000 .and. &
           result_state%odex_rhs_evals < 100000 .and. &
           result_state%odex_hairer_policy_steps == result_state%accepted_steps + result_state%rejected_steps .and. &
           result_state%odex_tltm_policy_steps == 0 .and. result_state%odex_first_step_entries == 1 .and. &
           result_state%odex_last_step_entries == 1 .and. &
           result_state%odex_row_j1_calls + result_state%odex_row_j2_calls + result_state%odex_row_jge3_calls == &
           result_state%odex_midpoint_rows .and. result_state%odex_error_estimates > 0 .and. &
           result_state%odex_row_j1_no_error_returns == result_state%odex_row_j1_calls .and. &
           result_state%odex_hairer_scal_estimates == result_state%odex_error_estimates .and. &
           result_state%odex_default_scal_estimates == 0 .and. &
           result_state%odex_kopt_accept_updates == result_state%accepted_steps .and. &
           result_state%odex_kopt_demotions + result_state%odex_kopt_keeps + result_state%odex_kopt_promotions == &
           result_state%odex_kopt_accept_updates .and. &
           result_state%odex_errold_checks == result_state%odex_error_estimates .and. &
           result_state%odex_atov_events == 0 .and. result_state%odex_after_reject_clamps == 0 .and. &
           err <= 2.0e-12_dp

      call odex_integrate_endpoint_context(rhs_exp_context, y0, 1.0_dp, y_out_context, failed_context, &
                                           result_context, workspace_context, options, rhs_context)
      err_context = maxval(abs(y_out_context - y_exact))
      ok_context = (.not. failed_context) .and. result_context%status == odex_status_success .and. &
                   result_context%endpoint_available .and. result_context%final_order >= 2 .and. &
                   result_context%odex_rhs_evals > 0 .and. result_context%odex_midpoint_rows > 0 .and. &
                   result_context%odex_accept_k_minus_1 + result_context%odex_accept_k + &
                   result_context%odex_accept_k_plus_1 == result_context%accepted_steps .and. &
                   result_context%accepted_steps < 1000 .and. result_context%odex_rhs_evals < 100000 .and. &
                   result_context%odex_hairer_policy_steps == &
                   result_context%accepted_steps + result_context%rejected_steps .and. &
                   result_context%odex_tltm_policy_steps == 0 .and. result_context%odex_first_step_entries == 1 .and. &
                   result_context%odex_last_step_entries == 1 .and. &
                   result_context%odex_row_j1_calls + result_context%odex_row_j2_calls + &
                   result_context%odex_row_jge3_calls == result_context%odex_midpoint_rows .and. &
                   result_context%odex_error_estimates > 0 .and. &
                   result_context%odex_row_j1_no_error_returns == result_context%odex_row_j1_calls .and. &
                   result_context%odex_hairer_scal_estimates == result_context%odex_error_estimates .and. &
                   result_context%odex_default_scal_estimates == 0 .and. &
                   result_context%odex_kopt_accept_updates == result_context%accepted_steps .and. &
                   result_context%odex_kopt_demotions + result_context%odex_kopt_keeps + &
                   result_context%odex_kopt_promotions == result_context%odex_kopt_accept_updates .and. &
                   result_context%odex_errold_checks == result_context%odex_error_estimates .and. &
                   result_context%odex_atov_events == 0 .and. result_context%odex_after_reject_clamps == 0 .and. &
                   err_context <= 2.0e-12_dp

      write (*, '(A,L1,A,L1,A,I0,A,I0,A,I0,A,ES12.4,A,ES12.4)') "[CHECK] package_hairer_experimental ok=", ok, &
         " context=", ok_context, &
         " order=", result_state%final_order, " accepted=", result_state%accepted_steps, &
         " rhs=", result_state%odex_rhs_evals, " err=", err, " context_err=", err_context
      if (.not. (ok .and. ok_context)) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] Hairer endpoint contract changed."
         write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') "[DETAIL] hairer counters accepted=", &
            result_state%accepted_steps, " rejected=", result_state%rejected_steps, &
            " kminus=", result_state%odex_accept_k_minus_1, " k=", result_state%odex_accept_k, &
            " kplus=", result_state%odex_accept_k_plus_1, " error_estimates=", result_state%odex_error_estimates
         write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') "[DETAIL] hairer controller hairer_steps=", &
            result_state%odex_hairer_policy_steps, " tltm_steps=", result_state%odex_tltm_policy_steps, &
            " first=", result_state%odex_first_step_entries, " basic=", result_state%odex_basic_step_entries, &
            " last=", result_state%odex_last_step_entries, " errold=", result_state%odex_errold_checks
         write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') "[DETAIL] hairer reject atov=", &
            result_state%odex_atov_events, " kopt=", result_state%odex_kopt_accept_updates, &
            " demote=", result_state%odex_kopt_demotions, " keep=", result_state%odex_kopt_keeps, &
            " promote=", result_state%odex_kopt_promotions, " clamp=", result_state%odex_after_reject_clamps
      end if
   end subroutine check_hairer_experimental_endpoint_accuracy

   subroutine check_hairer_experimental_analytic_gates(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options, loose_options, reject_options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_mid, result_back, result_k2, result_reject
      real(dp) :: y0(1), y_mid(1), y_back(1), y_out(1), err
      logical :: failed_mid, failed_back, failed_k2, failed_reject
      logical :: signed_ok, k2_ok, reject_ok

      call odex_default_options(options, 3.0e-14_dp, 3.0e-14_dp)
      options%controller_policy = odex_controller_policy_hairer_experimental
      exp_lambda = -1.3_dp
      y0(1) = 0.8125_dp
      call odex_integrate_endpoint(rhs_exp, y0, 0.75_dp, y_mid, failed_mid, result_mid, workspace, options)
      call odex_integrate_endpoint(rhs_exp, y_mid, -0.75_dp, y_back, failed_back, result_back, workspace, options)
      err = maxval(abs(y_back - y0))
      signed_ok = (.not. failed_mid) .and. (.not. failed_back) .and. &
                  result_mid%status == odex_status_success .and. result_back%status == odex_status_success .and. &
                  result_mid%odex_hairer_policy_steps > 0 .and. result_back%odex_hairer_policy_steps > 0 .and. &
                  result_mid%odex_tltm_policy_steps == 0 .and. result_back%odex_tltm_policy_steps == 0 .and. &
                  result_back%final_step_size < 0.0_dp .and. err <= 2.0e-11_dp

      call odex_default_options(loose_options, 1.0e-1_dp, 1.0e-1_dp)
      loose_options%controller_policy = odex_controller_policy_hairer_experimental
      loose_options%max_steps = 1
      exp_lambda = -0.5_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed_k2, result_k2, workspace, loose_options)
      k2_ok = failed_k2 .and. result_k2%status == odex_status_failure_max_steps .and. &
              result_k2%accepted_steps == 1 .and. result_k2%odex_hairer_policy_steps == 1 .and. &
              result_k2%odex_row_j2_calls >= 1 .and. result_k2%odex_row_jge3_calls == 0 .and. &
              result_k2%odex_tltm_policy_steps == 0

      call odex_default_options(reject_options, 1.0e-12_dp, 1.0e-12_dp)
      reject_options%controller_policy = odex_controller_policy_hairer_experimental
      reject_options%max_steps = 10000
      exp_lambda = -100.0_dp
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed_reject, result_reject, workspace, reject_options)
      reject_ok = (.not. failed_reject) .and. result_reject%status == odex_status_success .and. &
                  result_reject%rejected_steps > 0 .and. result_reject%odex_hairer_policy_steps == &
                  result_reject%accepted_steps + result_reject%rejected_steps .and. &
                  result_reject%odex_reject_updates + result_reject%odex_atov_events > 0 .and. &
                  result_reject%odex_tltm_policy_steps == 0

      write (*, '(A,L1,A,L1,A,L1,A,ES12.4,A,I0,A,I0)') "[CHECK] hairer_analytic_gates signed=", &
         signed_ok, " k2=", k2_ok, " reject=", reject_ok, " fb_err=", err, &
         " rejects=", result_reject%rejected_steps, " atov=", result_reject%odex_atov_events
      if (.not. (signed_ok .and. k2_ok .and. reject_ok)) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] Hairer analytic endpoint gates changed."
         write (*, '(A,I0,A,I0,A,I0,A,I0)') "[DETAIL] k2 status=", result_k2%status, &
            " accepted=", result_k2%accepted_steps, " j2=", result_k2%odex_row_j2_calls, &
            " jge3=", result_k2%odex_row_jge3_calls
         write (*, '(A,I0,A,I0,A,I0,A,I0)') "[DETAIL] reject status=", result_reject%status, &
            " accepted=", result_reject%accepted_steps, " rejected=", result_reject%rejected_steps, &
            " updates=", result_reject%odex_reject_updates
      end if
   end subroutine check_hairer_experimental_analytic_gates

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

   subroutine check_conservative_stability_observer_surface(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      real(dp) :: values(1)
      logical :: reject_default, reject_conservative, reject_small_dt, ok

      call odex_default_options(options, 1.0e-10_dp, 1.0e-10_dp)
      values(1) = 100.0_dp
      reject_default = odex_observe_stability_reject(values, 1.0_dp, 0.1_dp, options)
      options%stability_control = odex_stability_control_conservative
      options%stability_growth_limit = 4.0_dp
      reject_conservative = odex_observe_stability_reject(values, 1.0_dp, 0.1_dp, options)
      reject_small_dt = odex_observe_stability_reject(values, 1.0_dp, 0.01_dp, options)
      ok = (.not. reject_default) .and. reject_conservative .and. (.not. reject_small_dt)
      write (*, '(A,L1,A,L1,A,L1,A,L1)') "[CHECK] package_stability_observer_surface ok=", ok, &
         " default=", reject_default, " conservative=", reject_conservative, &
         " small_dt=", reject_small_dt
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] conservative stability-control observer surface changed."
      end if
   end subroutine check_conservative_stability_observer_surface

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

   subroutine check_invalid_rhs_failure(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_state, result_context
      type(dummy_context_t) :: rhs_context
      real(dp) :: y0(1), y_out(1), y_out_context(1)
      logical :: failed, failed_context, ok, ok_context

      call odex_default_options(options, 3.0e-14_dp, 3.0e-14_dp)
      y0(1) = 1.0_dp
      call odex_integrate_endpoint(rhs_nan, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      ok = failed .and. result_state%status == odex_status_failure_invalid .and. &
           result_state%accepted_steps == 0 .and. result_state%rejected_steps == 0 .and. &
           result_state%odex_rhs_evals == 1 .and. result_state%odex_midpoint_rows == 0 .and. &
           .not. result_state%endpoint_available

      call odex_integrate_endpoint_context(rhs_nan_context, y0, 1.0_dp, y_out_context, failed_context, &
                                           result_context, workspace, options, rhs_context)
      ok_context = failed_context .and. result_context%status == odex_status_failure_invalid .and. &
                   result_context%accepted_steps == 0 .and. result_context%rejected_steps == 0 .and. &
                   result_context%odex_rhs_evals == 1 .and. result_context%odex_midpoint_rows == 0 .and. &
                   .not. result_context%endpoint_available

      write (*, '(A,L1,A,L1,A,I0,A,I0)') "[CHECK] package_invalid_rhs ok=", ok, &
         " context=", ok_context, " status=", result_state%status, " context_status=", result_context%status
      if (.not. (ok .and. ok_context)) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] standalone backend invalid-RHS failure contract changed."
      end if
   end subroutine check_invalid_rhs_failure

   subroutine check_output_size_guard(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_result) :: result_state, result_context
      type(dummy_context_t) :: rhs_context
      real(dp) :: y0(2), y_out(1), y_out_context(1)
      logical :: failed, failed_context, ok, ok_context

      call odex_default_options(options, 3.0e-14_dp, 3.0e-14_dp)
      exp_lambda = -2.0_dp
      y0 = [1.0_dp, 2.0_dp]
      y_out = -999.0_dp
      y_out_context = -999.0_dp

      call odex_integrate_endpoint(rhs_exp, y0, 1.0_dp, y_out, failed, result_state, workspace, options)
      ok = failed .and. result_state%status == odex_status_failure_invalid .and. &
           .not. result_state%endpoint_available

      call odex_integrate_endpoint_context(rhs_exp_context, y0, 1.0_dp, y_out_context, failed_context, &
                                           result_context, workspace, options, rhs_context)
      ok_context = failed_context .and. result_context%status == odex_status_failure_invalid .and. &
                   .not. result_context%endpoint_available

      write (*, '(A,L1,A,L1,A,I0,A,I0)') "[CHECK] package_output_size_guard ok=", ok, &
         " context=", ok_context, " status=", result_state%status, " context_status=", result_context%status
      if (.not. (ok .and. ok_context)) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] standalone backend output-size guard changed."
      end if
   end subroutine check_output_size_guard

end program test_odex_backend_package_contract

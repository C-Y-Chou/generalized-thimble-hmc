program test_odex_result_contract
   use param_mod, only: at, rt
   use solve_flow, only: ensure_odex_workspace_object, intode_reason_h_min, intode_reason_invalid, &
                         intode_reason_max_steps, intode_reason_none, intode_status_failure_h_min, &
                         intode_status_failure_invalid, intode_status_failure_max_steps, intode_status_success, &
                         intode_status_success_solver_assist, intode_status_success_zero_time, intode_status_unknown, &
                         odex_default_options, odex_k_max, odex_k_min, odex_options, odex_result, &
                         odex_result_mark_failure, odex_result_mark_success, odex_result_reset, &
                         odex_result_to_intode_status, odex_status_failure_h_min, odex_status_failure_invalid, &
                         odex_status_failure_max_steps, odex_status_from_failure_reason, odex_status_is_failure, &
                         odex_status_is_mechanism_status, odex_status_success, odex_status_success_zero_time, &
                         odex_status_unknown, odex_step_sequence_iwork3, odex_stability_control_none, odex_workspace
   use odex_backend, only: odex_apply_controller_policy_name, odex_controller_policy_hairer_experimental, &
                           odex_controller_policy_name, odex_controller_policy_tltm_endpoint
   use utils, only: dp
   implicit none

   integer :: failures

   failures = 0
   at = 3.0e-14_dp
   rt = 4.0e-14_dp

   write (*, '(A,ES12.4,A,ES12.4)') "[INIT] ODEX result contract starts. abs_tol=", at, " rel_tol=", rt

   call check_default_options(failures)
   call check_workspace_contract(failures)
   call check_result_reset_and_success_mapping(failures)
   call check_failure_mapping(failures)
   call check_policy_status_boundary(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] ODEX result contract failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] ODEX result contract complete."

contains

   subroutine check_default_options(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      logical :: ok

      call odex_default_options(options)
      ok = options%abs_tol == at .and. options%rel_tol == rt .and. &
           options%k_min == odex_k_min .and. options%k_max == odex_k_max .and. &
           options%max_steps > 0 .and. options%step_sequence == odex_step_sequence_iwork3 .and. &
           options%controller_policy == odex_controller_policy_tltm_endpoint .and. &
           options%stability_control == odex_stability_control_none .and. options%endpoint_only
      write (*, '(A,L1,A,I0,A,I0,A,I0,A,L1)') "[CHECK] default_options ok=", ok, &
         " k_min=", options%k_min, " k_max=", options%k_max, " step_sequence=", options%step_sequence, &
         " endpoint_only=", options%endpoint_only
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] ODEX default options no longer match the current source contract."
      end if

      call odex_apply_controller_policy_name(options, "hairer_experimental")
      ok = options%controller_policy == odex_controller_policy_hairer_experimental .and. &
           trim(odex_controller_policy_name(options%controller_policy)) == "hairer_experimental"
      write (*, '(A,L1,A,A)') "[CHECK] controller_policy_name ok=", ok, &
         " policy=", trim(odex_controller_policy_name(options%controller_policy))
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] ODEX controller policy opt-in contract changed."
      end if
   end subroutine check_default_options

   subroutine check_workspace_contract(failures)
      integer, intent(inout) :: failures
      type(odex_workspace) :: workspace
      logical :: ok

      call ensure_odex_workspace_object(workspace, 11, 3)
      ok = allocated(workspace%tableau) .and. size(workspace%tableau, 1) == 11 .and. &
           size(workspace%tableau, 2) == 11 .and. size(workspace%tableau, 3) == 3 .and. &
           allocated(workspace%yprev) .and. size(workspace%yprev) == 3 .and. &
           allocated(workspace%ycurr) .and. size(workspace%ycurr) == 3 .and. &
           allocated(workspace%ynext) .and. size(workspace%ynext) == 3 .and. &
           allocated(workspace%fval) .and. size(workspace%fval) == 3 .and. &
           allocated(workspace%fbase) .and. size(workspace%fbase) == 3

      call ensure_odex_workspace_object(workspace, 4, 2)
      ok = ok .and. size(workspace%tableau, 1) == 11 .and. size(workspace%tableau, 3) == 3 .and. &
           size(workspace%yprev) == 3

      call ensure_odex_workspace_object(workspace, 12, 5)
      ok = ok .and. size(workspace%tableau, 1) >= 12 .and. size(workspace%tableau, 2) >= 12 .and. &
           size(workspace%tableau, 3) >= 5 .and. size(workspace%yprev) >= 5 .and. &
           size(workspace%ycurr) >= 5 .and. size(workspace%ynext) >= 5 .and. &
           size(workspace%fval) >= 5 .and. size(workspace%fbase) >= 5

      write (*, '(A,L1,A,I0,A,I0,A,I0)') "[CHECK] workspace_contract ok=", ok, &
         " k1=", size(workspace%tableau, 1), " k2=", size(workspace%tableau, 2), &
         " n=", size(workspace%tableau, 3)
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] ODEX workspace allocation contract changed."
      end if
   end subroutine check_workspace_contract

   subroutine check_result_reset_and_success_mapping(failures)
      integer, intent(inout) :: failures
      type(odex_result) :: result_state
      logical :: ok

      call odex_result_reset(result_state)
      ok = result_state%status == odex_status_unknown .and. &
           result_state%failure_reason == intode_reason_none .and. &
           result_state%accepted_steps == 0 .and. result_state%rejected_steps == 0 .and. &
           result_state%odex_rhs_evals == 0 .and. result_state%odex_midpoint_rows == 0 .and. &
           result_state%odex_kplus1_attempts == 0 .and. result_state%odex_kplus1_rejects == 0 .and. &
           result_state%odex_hairer_policy_steps == 0 .and. result_state%odex_tltm_policy_steps == 0 .and. &
           result_state%odex_first_step_entries == 0 .and. result_state%odex_last_step_entries == 0 .and. &
           result_state%odex_basic_step_entries == 0 .and. result_state%odex_row_j1_calls == 0 .and. &
           result_state%odex_row_j2_calls == 0 .and. result_state%odex_row_jge3_calls == 0 .and. &
           result_state%odex_row_j1_no_error_returns == 0 .and. &
           result_state%odex_error_estimates == 0 .and. result_state%odex_hairer_scal_estimates == 0 .and. &
           result_state%odex_default_scal_estimates == 0 .and. result_state%odex_errold_checks == 0 .and. &
           result_state%odex_atov_events == 0 .and. result_state%odex_convergence_rejects == 0 .and. &
           result_state%odex_kplus1_hope_rejects == 0 .and. &
           result_state%odex_reject_kc_k_minus_1 == 0 .and. result_state%odex_reject_kc_k == 0 .and. &
           result_state%odex_reject_kc_k_plus_1 == 0 .and. result_state%odex_kopt_accept_updates == 0 .and. &
           result_state%odex_kopt_demotions == 0 .and. result_state%odex_kopt_keeps == 0 .and. &
           result_state%odex_kopt_promotions == 0 .and. result_state%odex_after_reject_clamps == 0 .and. &
           result_state%odex_reject_updates == 0 .and. &
           .not. result_state%endpoint_available .and. &
           odex_result_to_intode_status(result_state) == intode_status_unknown
      write (*, '(A,L1,A,I0)') "[CHECK] result_reset ok=", ok, " status=", result_state%status
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] ODEX result reset contract changed."
      end if

      call odex_result_mark_success(result_state, odex_status_success_zero_time, 0, 0, 0.0_dp)
      ok = result_state%status == odex_status_success_zero_time .and. &
           odex_result_to_intode_status(result_state) == intode_status_success_zero_time .and. &
           result_state%endpoint_available .and. .not. odex_status_is_failure(result_state%status)
      write (*, '(A,L1,A,I0)') "[CHECK] zero_success_mapping ok=", ok, " status=", result_state%status
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] zero-time ODEX result mapping changed."
      end if

      call odex_result_mark_success(result_state, odex_status_success, 7, 5, 0.125_dp)
      ok = result_state%status == odex_status_success .and. &
           odex_result_to_intode_status(result_state) == intode_status_success .and. &
           result_state%accepted_steps == 7 .and. result_state%final_order == 5 .and. &
           result_state%final_step_size == 0.125_dp .and. result_state%endpoint_available
      write (*, '(A,L1,A,I0,A,I0,A,I0)') "[CHECK] success_mapping ok=", ok, &
         " status=", result_state%status, " accepted=", result_state%accepted_steps, &
         " order=", result_state%final_order
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] successful ODEX result mapping changed."
      end if
   end subroutine check_result_reset_and_success_mapping

   subroutine check_failure_mapping(failures)
      integer, intent(inout) :: failures
      type(odex_result) :: result_state
      logical :: ok

      ok = odex_status_from_failure_reason(intode_reason_max_steps) == odex_status_failure_max_steps .and. &
           odex_status_from_failure_reason(intode_reason_invalid) == odex_status_failure_invalid .and. &
           odex_status_from_failure_reason(intode_reason_h_min) == odex_status_failure_h_min .and. &
           odex_status_from_failure_reason(intode_reason_none) == odex_status_unknown

      call odex_result_reset(result_state)
      call odex_result_mark_failure(result_state, intode_reason_max_steps, 3, 1, 4, 0.25_dp, 0.5_dp)
      ok = ok .and. result_state%status == odex_status_failure_max_steps .and. &
           odex_result_to_intode_status(result_state) == intode_status_failure_max_steps .and. &
           result_state%failure_reason == intode_reason_max_steps .and. &
           result_state%accepted_steps == 3 .and. result_state%rejected_steps == 1 .and. &
           .not. result_state%endpoint_available .and. odex_status_is_failure(result_state%status)

      call odex_result_mark_failure(result_state, intode_reason_invalid, 2, 1, 4, 0.125_dp, 0.25_dp)
      ok = ok .and. result_state%status == odex_status_failure_invalid .and. &
           odex_result_to_intode_status(result_state) == intode_status_failure_invalid

      call odex_result_mark_failure(result_state, intode_reason_h_min, 5, 1, 6, 1.0e-16_dp, 0.125_dp)
      ok = ok .and. result_state%status == odex_status_failure_h_min .and. &
           odex_result_to_intode_status(result_state) == intode_status_failure_h_min

      call odex_result_mark_failure(result_state, intode_reason_none, 0, 0, 0, 0.0_dp, 0.0_dp)
      ok = ok .and. result_state%status == odex_status_unknown .and. &
           odex_result_to_intode_status(result_state) == intode_status_unknown

      write (*, '(A,L1,A,I0,A,I0)') "[CHECK] failure_mapping ok=", ok, &
         " status=", result_state%status, " reason=", result_state%failure_reason
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] ODEX failure mapping changed."
      end if
   end subroutine check_failure_mapping

   subroutine check_policy_status_boundary(failures)
      integer, intent(inout) :: failures
      logical :: ok

      ok = odex_status_is_mechanism_status(odex_status_success) .and. &
           odex_status_is_mechanism_status(odex_status_success_zero_time) .and. &
           odex_status_is_mechanism_status(odex_status_failure_h_min) .and. &
           .not. odex_status_is_mechanism_status(intode_status_success_solver_assist)
      write (*, '(A,L1)') "[CHECK] policy_status_boundary ok=", ok
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] ODEX mechanism status boundary now includes TLTM policy statuses."
      end if
   end subroutine check_policy_status_boundary

end program test_odex_result_contract

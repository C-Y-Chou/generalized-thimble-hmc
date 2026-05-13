module solve_flow
   use param_mod, only: at, rt
   use utils, only: dp, complex_to_real, map_to_complex, real_to_complex
   use model, only: ds, hessian_vec
   use odex_backend, only: build_nsteps, ensure_odex_workspace_object, ode_rhs, ode_rhs_context, &
                           odex_backend_default_options => odex_default_options, &
                           odex_integrate_endpoint, odex_integrate_endpoint_context, odex_k_max, odex_k_min, odex_max_steps_default, &
                           odex_options, odex_reason_h_min, odex_reason_invalid, odex_reason_max_steps, &
                           odex_reason_none, odex_result, odex_result_mark_failure, odex_result_mark_success, &
                           odex_result_reset, odex_result_to_intode_status, odex_status_failure_h_min, &
                           odex_status_failure_invalid, odex_status_failure_max_steps, &
                           odex_status_from_failure_reason, odex_status_is_failure, &
                           odex_status_is_mechanism_status, odex_status_success, &
                           odex_status_success_zero_time, odex_status_unknown, odex_step_sequence_iwork3, &
                           odex_stability_control_conservative, odex_stability_control_none, odex_workspace
   use perf_profile, only: perf_tic, perf_toc, PERF_INTODE, PERF_FLOW, PERF_FLOWZ, PERF_FLOWZR
   use runtime_env_mod, only: parse_logical_env, read_string_env, to_lower_ascii
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   implicit none

   type :: flow_workspace_t
      real(dp), allocatable :: intode_yc(:), intode_yf(:)
      real(dp), allocatable :: flow_vec_y(:), flow_vec_yf(:)
      real(dp), allocatable :: flow_jac_y(:), flow_jac_yf(:)
      complex(dp), allocatable :: flow_vec_z(:), flow_vec_ds(:)
      complex(dp), allocatable :: flow_jac_z(:), flow_jac_ds(:)
      complex(dp), allocatable :: flow_jac_j(:, :), flow_jac_jprod(:, :)
      real(dp) :: flow_vec_rhs_scale = 1.0_dp
      type(odex_workspace) :: intode_odex_workspace
   end type flow_workspace_t

   integer, parameter :: intode_max_steps = odex_max_steps_default
   integer, parameter :: intode_reason_none = odex_reason_none
   integer, parameter :: intode_reason_max_steps = odex_reason_max_steps
   integer, parameter :: intode_reason_invalid = odex_reason_invalid
   integer, parameter :: intode_reason_h_min = odex_reason_h_min
   integer, parameter :: intode_status_unknown = odex_status_unknown
   integer, parameter :: intode_status_success = odex_status_success
   integer, parameter :: intode_status_success_zero_time = odex_status_success_zero_time
   integer, parameter :: intode_status_success_stiff_rescue = 2
   integer, parameter :: intode_status_success_solver_assist = 3
   integer, parameter :: intode_status_failure_max_steps = odex_status_failure_max_steps
   integer, parameter :: intode_status_failure_invalid = odex_status_failure_invalid
   integer, parameter :: intode_status_failure_h_min = odex_status_failure_h_min
   integer, parameter :: intode_ctx_unknown = 0
   integer, parameter :: intode_ctx_flowz = 1
   integer, parameter :: intode_ctx_flowzr = 2
   integer, parameter :: intode_ctx_flow = 3
   integer, parameter :: intode_stage_unknown = 0
   integer, parameter :: intode_stage_newton = 1
   integer, parameter :: intode_stage_quasi = 2
   integer, parameter :: intode_stage_quasi_retry = 3
   integer, parameter :: intode_stage_rattle_flow = 4
   integer, parameter :: intode_stage_external = 5
   integer, parameter :: intode_role_unknown = 0
   integer, parameter :: intode_role_nt_strict = 1
   integer, parameter :: intode_role_qn_navigation = 2
   integer, parameter :: intode_role_certification = 3
   integer, parameter :: intode_role_final_flow = 4
   integer, parameter :: intode_role_reverse_replay = 5
   integer, parameter :: intode_solver_assist_policy_off = 0
   integer, parameter :: intode_solver_assist_policy_qn_navigation = 1
   integer, parameter :: intode_solver_assist_policy_all_navigation_diagnostic = 2
   integer, save :: intode_calls_total = 0
   integer, save :: intode_calls_integrating = 0
   integer, save :: intode_fallback_attempts = 0
   integer, save :: intode_fallback_success = 0
   integer, save :: intode_fallback_failure = 0
   integer, save :: intode_fallback_max_steps = 0
   integer, save :: intode_fallback_invalid = 0
   integer, save :: intode_fallback_h_min = 0
   integer, save :: intode_fallback_attempts_ctx(intode_ctx_unknown:intode_ctx_flow) = 0
   integer, save :: intode_fallback_failures_ctx(intode_ctx_unknown:intode_ctx_flow) = 0
   integer, save :: intode_rescue_success_solver_assist = 0
   integer, save :: intode_solver_assist_fail = 0
   integer, parameter :: intode_solver_assist_policy_default = intode_solver_assist_policy_qn_navigation
   integer, save :: intode_solver_assist_policy = intode_solver_assist_policy_default
   logical, save :: intode_enable_solver_assist = .true.
   logical, save :: intode_solver_assist_policy_loaded = .false.
   logical, parameter :: intode_fast_hmin_assist = .true.
   logical, parameter :: intode_verbose_logs = .false.
   ! <= 0 means unlimited solver-assist uses (still context-gated).
   integer, parameter :: intode_solver_assist_max_uses = 0
   integer, save :: intode_solver_assist_log_count = 0
   integer, parameter :: intode_solver_assist_log_limit = 20
   integer, save :: intode_trace_rattle_step = 0
   integer, save :: intode_trace_rattle_substep = 0
   integer, save :: intode_trace_stage = intode_stage_unknown
   integer, save :: intode_trace_newton_iter = 0
   integer, save :: intode_trace_quasi_iter = 0
   integer, save :: intode_trace_role = intode_role_unknown
   integer, save :: intode_current_context = intode_ctx_unknown
   logical, save :: intode_capture_failures = .true.
   logical, save :: intode_last_failure_available = .false.
   integer, save :: intode_last_failure_reason = intode_reason_none
   integer, save :: intode_last_failure_context = intode_ctx_unknown
   integer, save :: intode_last_failure_rattle_step = 0
   integer, save :: intode_last_failure_rattle_substep = 0
   integer, save :: intode_last_failure_stage = intode_stage_unknown
   integer, save :: intode_last_failure_newton_iter = 0
   integer, save :: intode_last_failure_quasi_iter = 0
   integer, save :: intode_failure_log_count = 0
   integer, parameter :: intode_failure_log_limit = 20
   real(dp), save :: intode_last_failure_t = 0.0_dp
   real(dp), allocatable, save :: intode_last_failure_y(:)

contains

   subroutine odex_default_options(options)
      implicit none
      type(odex_options), intent(out) :: options

      call odex_backend_default_options(options, at, rt)
   end subroutine odex_default_options

   subroutine intode(f, y, t, res, error_flag, status)
      implicit none
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      integer, intent(out), optional :: status

      integer :: state_size, failure_reason
      logical :: rescue_failed, solver_assist_ok
      real(dp) :: t_remaining
      type(odex_options) :: integration_options
      type(odex_result) :: integration_result
      type(flow_workspace_t) :: local_workspace
      real(dp) :: t_prof

      call perf_tic(t_prof)
      call odex_result_reset(integration_result)
      call set_intode_status(status, intode_status_unknown)
      intode_calls_total = intode_calls_total + 1
      if (t == 0.0_dp) then
         res = y
         error_flag = .false.
         call odex_result_mark_success(integration_result, odex_status_success_zero_time, 0, 0, 0.0_dp)
         call set_intode_status(status, odex_result_to_intode_status(integration_result))
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if
      intode_calls_integrating = intode_calls_integrating + 1

      state_size = size(y)
      call ensure_real_workspace(local_workspace%intode_yc, state_size)
      call ensure_real_workspace(local_workspace%intode_yf, state_size)

      call odex_default_options(integration_options)
      call odex_integrate_endpoint(f, y, t, local_workspace%intode_yf(1:state_size), error_flag, &
                                   integration_result, local_workspace%intode_odex_workspace, integration_options)
      if (.not. error_flag) then
         res = local_workspace%intode_yf(1:state_size)
         call set_intode_status(status, odex_result_to_intode_status(integration_result))
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if

      failure_reason = integration_result%failure_reason
      if (failure_reason /= intode_reason_max_steps .and. failure_reason /= intode_reason_invalid .and. &
          failure_reason /= intode_reason_h_min) then
         failure_reason = intode_reason_invalid
         call odex_result_mark_failure(integration_result, failure_reason, integration_result%accepted_steps, &
                                       max(1, integration_result%rejected_steps), integration_result%final_order, &
                                       integration_result%final_step_size, integration_result%t_remaining)
      end if
      t_remaining = integration_result%t_remaining
      local_workspace%intode_yc(1:state_size) = local_workspace%intode_yf(1:state_size)

      intode_fallback_attempts = intode_fallback_attempts + 1
      select case (failure_reason)
      case (intode_reason_max_steps)
         intode_fallback_max_steps = intode_fallback_max_steps + 1
      case (intode_reason_invalid)
         intode_fallback_invalid = intode_fallback_invalid + 1
      case (intode_reason_h_min)
         intode_fallback_h_min = intode_fallback_h_min + 1
      end select
      call record_intode_fallback_attempt_context(intode_current_context)

      if (failure_reason == intode_reason_h_min .and. intode_fast_hmin_assist) then
         call intode_try_solver_assist(local_workspace%intode_yc(1:state_size), t_remaining, failure_reason, &
                                       local_workspace%intode_yf(1:state_size), solver_assist_ok)
         if (solver_assist_ok) then
            intode_fallback_success = intode_fallback_success + 1
            res = local_workspace%intode_yf(1:state_size)
            error_flag = .false.
            call set_intode_status(status, intode_status_success_solver_assist)
            call perf_toc(PERF_INTODE, t_prof)
            return
         end if
      end if

      call intode_stiff_rescue(f, local_workspace%intode_yc(1:state_size), t_remaining, local_workspace%intode_yf(1:state_size), rescue_failed)
      if (.not. rescue_failed) then
         intode_fallback_success = intode_fallback_success + 1
         res = local_workspace%intode_yf(1:state_size)
         error_flag = .false.
         call set_intode_status(status, intode_status_success_stiff_rescue)
      else
         call intode_try_solver_assist(local_workspace%intode_yc(1:state_size), t_remaining, failure_reason, &
                                       local_workspace%intode_yf(1:state_size), solver_assist_ok)
         if (solver_assist_ok) then
            intode_fallback_success = intode_fallback_success + 1
            res = local_workspace%intode_yf(1:state_size)
            error_flag = .false.
            call set_intode_status(status, intode_status_success_solver_assist)
         else
            intode_fallback_failure = intode_fallback_failure + 1
            call record_intode_fallback_failure_context(intode_current_context)
            call record_intode_last_failure(local_workspace%intode_yc(1:state_size), t_remaining, failure_reason)
            res = local_workspace%intode_yc(1:state_size)
            error_flag = .true.
            call set_intode_status(status, odex_result_to_intode_status(integration_result))
         end if
      end if
      call perf_toc(PERF_INTODE, t_prof)
   end subroutine intode

   subroutine intode_with_context(f, y, t, res, error_flag, status, workspace)
      implicit none
      procedure(ode_rhs_context) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace

      integer :: state_size, failure_reason
      logical :: rescue_failed, solver_assist_ok
      real(dp) :: t_remaining
      type(odex_options) :: integration_options
      type(odex_result) :: integration_result
      real(dp) :: t_prof

      call perf_tic(t_prof)
      call odex_result_reset(integration_result)
      call set_intode_status(status, intode_status_unknown)
      intode_calls_total = intode_calls_total + 1
      if (t == 0.0_dp) then
         res = y
         error_flag = .false.
         call odex_result_mark_success(integration_result, odex_status_success_zero_time, 0, 0, 0.0_dp)
         call set_intode_status(status, odex_result_to_intode_status(integration_result))
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if
      intode_calls_integrating = intode_calls_integrating + 1

      state_size = size(y)
      call ensure_real_workspace(workspace%intode_yc, state_size)
      call ensure_real_workspace(workspace%intode_yf, state_size)

      call odex_default_options(integration_options)
      call odex_integrate_endpoint_context(f, y, t, workspace%intode_yf(1:state_size), error_flag, &
                                           integration_result, workspace%intode_odex_workspace, integration_options, workspace)
      if (.not. error_flag) then
         res = workspace%intode_yf(1:state_size)
         call set_intode_status(status, odex_result_to_intode_status(integration_result))
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if

      failure_reason = integration_result%failure_reason
      if (failure_reason /= intode_reason_max_steps .and. failure_reason /= intode_reason_invalid .and. &
          failure_reason /= intode_reason_h_min) then
         failure_reason = intode_reason_invalid
         call odex_result_mark_failure(integration_result, failure_reason, integration_result%accepted_steps, &
                                       max(1, integration_result%rejected_steps), integration_result%final_order, &
                                       integration_result%final_step_size, integration_result%t_remaining)
      end if
      t_remaining = integration_result%t_remaining
      workspace%intode_yc(1:state_size) = workspace%intode_yf(1:state_size)

      intode_fallback_attempts = intode_fallback_attempts + 1
      select case (failure_reason)
      case (intode_reason_max_steps)
         intode_fallback_max_steps = intode_fallback_max_steps + 1
      case (intode_reason_invalid)
         intode_fallback_invalid = intode_fallback_invalid + 1
      case (intode_reason_h_min)
         intode_fallback_h_min = intode_fallback_h_min + 1
      end select
      call record_intode_fallback_attempt_context(intode_current_context)

      if (failure_reason == intode_reason_h_min .and. intode_fast_hmin_assist) then
         call intode_try_solver_assist(workspace%intode_yc(1:state_size), t_remaining, failure_reason, &
                                       workspace%intode_yf(1:state_size), solver_assist_ok)
         if (solver_assist_ok) then
            intode_fallback_success = intode_fallback_success + 1
            res = workspace%intode_yf(1:state_size)
            error_flag = .false.
            call set_intode_status(status, intode_status_success_solver_assist)
            call perf_toc(PERF_INTODE, t_prof)
            return
         end if
      end if

      call intode_stiff_rescue_context(f, workspace%intode_yc(1:state_size), t_remaining, workspace%intode_yf(1:state_size), &
                                       rescue_failed, workspace)
      if (.not. rescue_failed) then
         intode_fallback_success = intode_fallback_success + 1
         res = workspace%intode_yf(1:state_size)
         error_flag = .false.
         call set_intode_status(status, intode_status_success_stiff_rescue)
      else
         call intode_try_solver_assist(workspace%intode_yc(1:state_size), t_remaining, failure_reason, &
                                       workspace%intode_yf(1:state_size), solver_assist_ok)
         if (solver_assist_ok) then
            intode_fallback_success = intode_fallback_success + 1
            res = workspace%intode_yf(1:state_size)
            error_flag = .false.
            call set_intode_status(status, intode_status_success_solver_assist)
         else
            intode_fallback_failure = intode_fallback_failure + 1
            call record_intode_fallback_failure_context(intode_current_context)
            call record_intode_last_failure(workspace%intode_yc(1:state_size), t_remaining, failure_reason)
            res = workspace%intode_yc(1:state_size)
            error_flag = .true.
            call set_intode_status(status, odex_result_to_intode_status(integration_result))
         end if
      end if
      call perf_toc(PERF_INTODE, t_prof)
   end subroutine intode_with_context

   subroutine set_intode_status(status, status_code)
      implicit none
      integer, intent(out), optional :: status
      integer, intent(in) :: status_code

      if (present(status)) status = status_code
   end subroutine set_intode_status

   pure logical function intode_status_is_strict_success(status_code) result(ok)
      implicit none
      integer, intent(in) :: status_code

      select case (status_code)
      case (intode_status_success, intode_status_success_zero_time)
         ok = .true.
      case default
         ok = .false.
      end select
   end function intode_status_is_strict_success

   subroutine intode_try_solver_assist(y_curr, t_remaining, reason_code, y_out, accepted)
      implicit none
      real(dp), intent(in) :: y_curr(:), t_remaining
      integer, intent(in) :: reason_code
      real(dp), intent(out) :: y_out(:)
      logical, intent(out) :: accepted

      accepted = .false.
      y_out = y_curr

      if (.not. intode_solver_assist_policy_allows(reason_code, intode_current_context, intode_trace_stage, &
                                                   intode_rescue_success_solver_assist, intode_trace_role)) then
         intode_solver_assist_fail = intode_solver_assist_fail + 1
         return
      end if

      accepted = .true.
      intode_rescue_success_solver_assist = intode_rescue_success_solver_assist + 1

      if (intode_verbose_logs) then
         if (intode_solver_assist_log_count < intode_solver_assist_log_limit) then
            write (*, '(A,I0,A,I0,A,ES12.4,A,I0,A,I0,A,I0,A,I0)') "[INTODE][ASSIST] solver_assist_accept context=", &
               intode_current_context, " reason=", reason_code, " t_remaining=", t_remaining, &
               " rattle_step=", intode_trace_rattle_step, " substep=", intode_trace_rattle_substep, &
               " stage=", intode_trace_stage, " role=", intode_trace_role
         else if (intode_solver_assist_log_count == intode_solver_assist_log_limit) then
            write (*, '(A)') "[INTODE][ASSIST] additional solver_assist logs suppressed."
         end if
         intode_solver_assist_log_count = intode_solver_assist_log_count + 1
      end if
   end subroutine intode_try_solver_assist

   logical function intode_solver_assist_policy_allows(reason_code, context_code, stage_code, success_count, role_code) result(allowed)
      implicit none
      integer, intent(in) :: reason_code, context_code, stage_code, success_count
      integer, intent(in), optional :: role_code
      integer :: active_role
      logical :: allow_context, allow_stage

      call ensure_intode_solver_assist_policy()

      allowed = .false.
      active_role = intode_trace_role
      if (present(role_code)) active_role = role_code
      if (intode_solver_assist_policy == intode_solver_assist_policy_off) return
      if (.not. intode_enable_solver_assist) return
      if (reason_code /= intode_reason_h_min) return

      allow_context = (context_code == intode_ctx_flowz .or. context_code == intode_ctx_flowzr)
      if (.not. allow_context) return

      select case (intode_solver_assist_policy)
      case (intode_solver_assist_policy_qn_navigation)
         allow_stage = (stage_code == intode_stage_quasi .or. stage_code == intode_stage_quasi_retry)
         if (.not. allow_stage) return
         if (active_role /= intode_role_qn_navigation .and. active_role /= intode_role_reverse_replay) return
      case (intode_solver_assist_policy_all_navigation_diagnostic)
         allow_stage = (stage_code == intode_stage_newton .or. stage_code == intode_stage_quasi .or. &
                        stage_code == intode_stage_quasi_retry)
         if (.not. allow_stage) return
         if (active_role /= intode_role_nt_strict .and. active_role /= intode_role_qn_navigation .and. &
             active_role /= intode_role_reverse_replay) return
      case default
         return
      end select

      if (intode_solver_assist_max_uses > 0) then
         if (success_count >= intode_solver_assist_max_uses) return
      end if

      allowed = .true.
   end function intode_solver_assist_policy_allows

   subroutine record_intode_fallback_attempt_context(ctx_code)
      implicit none
      integer, intent(in) :: ctx_code
      integer :: idx

      idx = normalize_context_code(ctx_code)
      intode_fallback_attempts_ctx(idx) = intode_fallback_attempts_ctx(idx) + 1
   end subroutine record_intode_fallback_attempt_context

   subroutine record_intode_fallback_failure_context(ctx_code)
      implicit none
      integer, intent(in) :: ctx_code
      integer :: idx

      idx = normalize_context_code(ctx_code)
      intode_fallback_failures_ctx(idx) = intode_fallback_failures_ctx(idx) + 1
   end subroutine record_intode_fallback_failure_context

   integer function normalize_context_code(ctx_code) result(ctx_norm)
      implicit none
      integer, intent(in) :: ctx_code

      if (ctx_code >= intode_ctx_flowz .and. ctx_code <= intode_ctx_flow) then
         ctx_norm = ctx_code
      else
         ctx_norm = intode_ctx_unknown
      end if
   end function normalize_context_code

   subroutine record_intode_last_failure(y, t_remaining, reason_code)
      implicit none
      real(dp), intent(in) :: y(:), t_remaining
      integer, intent(in) :: reason_code

      if (.not. intode_capture_failures) return

      intode_last_failure_available = .true.
      intode_last_failure_reason = reason_code
      intode_last_failure_context = intode_current_context
      intode_last_failure_rattle_step = intode_trace_rattle_step
      intode_last_failure_rattle_substep = intode_trace_rattle_substep
      intode_last_failure_stage = intode_trace_stage
      intode_last_failure_newton_iter = intode_trace_newton_iter
      intode_last_failure_quasi_iter = intode_trace_quasi_iter
      intode_last_failure_t = t_remaining
      if (allocated(intode_last_failure_y)) then
         if (size(intode_last_failure_y) /= size(y)) then
            deallocate (intode_last_failure_y)
            allocate (intode_last_failure_y(size(y)))
         end if
      else
         allocate (intode_last_failure_y(size(y)))
      end if
      intode_last_failure_y = y

      if (intode_verbose_logs) then
         if (intode_failure_log_count < intode_failure_log_limit) then
            write (*, '(A,A,A,A,A,I0,A,I0,A,I0,A,I0,A,ES12.4)') "[INTODE][FAIL] context=", trim(context_name(intode_last_failure_context)), &
               " reason=", trim(reason_name(reason_code)), " rattle_step=", intode_last_failure_rattle_step, &
               " substep=", intode_last_failure_rattle_substep, " newton_iter=", intode_last_failure_newton_iter, &
               " quasi_iter=", intode_last_failure_quasi_iter, " t_remaining=", t_remaining
            write (*, '(A,A)') "               stage=", trim(stage_name(intode_last_failure_stage))
         else if (intode_failure_log_count == intode_failure_log_limit) then
            write (*, '(A)') "[INTODE][FAIL] additional failure logs suppressed."
         end if
         intode_failure_log_count = intode_failure_log_count + 1
      end if

   contains

      function reason_name(reason) result(name)
         implicit none
         integer, intent(in) :: reason
         character(len=20) :: name

         select case (reason)
         case (intode_reason_max_steps)
            name = "max_steps"
         case (intode_reason_invalid)
            name = "invalid"
         case (intode_reason_h_min)
            name = "h_min"
         case default
            name = "unknown"
         end select
      end function reason_name

      function context_name(ctx_code) result(name)
         implicit none
         integer, intent(in) :: ctx_code
         character(len=20) :: name

         select case (ctx_code)
         case (intode_ctx_flowz)
            name = "flowz"
         case (intode_ctx_flowzr)
            name = "flowzr"
         case (intode_ctx_flow)
            name = "flow"
         case default
            name = "unknown"
         end select
      end function context_name

      function stage_name(stage_code) result(name)
         implicit none
         integer, intent(in) :: stage_code
         character(len=20) :: name

         select case (stage_code)
         case (intode_stage_newton)
            name = "newton"
         case (intode_stage_quasi)
            name = "quasi"
         case (intode_stage_quasi_retry)
            name = "quasi_retry"
         case (intode_stage_rattle_flow)
            name = "rattle_flow"
         case (intode_stage_external)
            name = "external"
         case default
            name = "unknown"
         end select
      end function stage_name

   end subroutine record_intode_last_failure

   subroutine intode_stiff_rescue(f, y, t, res, error_flag)
      implicit none
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag

      ! Radau/JFNK rescue was a legacy secondary integrator stack.  It is
      ! intentionally disabled; solver-internal assist is handled separately.
      res = y
      error_flag = .true.
   end subroutine intode_stiff_rescue

   subroutine intode_stiff_rescue_context(f, y, t, res, error_flag, workspace)
      implicit none
      procedure(ode_rhs_context) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      type(flow_workspace_t), intent(inout) :: workspace

      ! Radau/JFNK rescue was a legacy secondary integrator stack.  It is
      ! intentionally disabled; solver-internal assist is handled separately.
      res = y
      error_flag = .true.
   end subroutine intode_stiff_rescue_context

   subroutine get_intode_solver_assist_policy(enabled, max_uses, fast_hmin_assist)
      implicit none
      logical, intent(out) :: enabled
      integer, intent(out) :: max_uses
      logical, intent(out) :: fast_hmin_assist

      call ensure_intode_solver_assist_policy()

      enabled = intode_enable_solver_assist
      max_uses = intode_solver_assist_max_uses
      fast_hmin_assist = intode_fast_hmin_assist
   end subroutine get_intode_solver_assist_policy

   subroutine get_intode_solver_assist_policy_code(policy_code, enabled, max_uses, fast_hmin_assist)
      implicit none
      integer, intent(out) :: policy_code
      logical, intent(out) :: enabled
      integer, intent(out) :: max_uses
      logical, intent(out) :: fast_hmin_assist

      call ensure_intode_solver_assist_policy()

      policy_code = intode_solver_assist_policy
      enabled = intode_enable_solver_assist
      max_uses = intode_solver_assist_max_uses
      fast_hmin_assist = intode_fast_hmin_assist
   end subroutine get_intode_solver_assist_policy_code

   subroutine ensure_intode_solver_assist_policy()
      implicit none
      character(len=128) :: env_value, policy_token
      logical :: env_present, legacy_present, legacy_enabled

      if (intode_solver_assist_policy_loaded) return

      intode_solver_assist_policy = intode_solver_assist_policy_default
      intode_enable_solver_assist = .true.
      call read_string_env("INTODE_SOLVER_ASSIST_POLICY", env_value, env_present)
      if (env_present) then
         policy_token = trim(to_lower_ascii(env_value))
         select case (policy_token)
         case ("", "canonical", "qn_navigation", "qn-navigation", "navigation", "qnav", &
               "nt_strict_qn_navassist_cert_strict_rg_metropolis_v1")
            intode_solver_assist_policy = intode_solver_assist_policy_qn_navigation
         case ("off", "disabled", "disable", "false", "0", "none", "strict")
            intode_solver_assist_policy = intode_solver_assist_policy_off
         case ("all_navigation_diagnostic", "all-navigation-diagnostic", "diagnostic", "all", &
               "legacy_enabled", "nt_qn_navigation_diagnostic")
            intode_solver_assist_policy = intode_solver_assist_policy_all_navigation_diagnostic
         case default
            write (*, '(A,A,A)') "[WARN] Unknown INTODE_SOLVER_ASSIST_POLICY='", trim(env_value), "'; using qn_navigation."
            intode_solver_assist_policy = intode_solver_assist_policy_qn_navigation
         end select
      else
         call read_string_env("INTODE_SOLVER_ASSIST_ENABLED", env_value, legacy_present)
         if (legacy_present) then
            legacy_enabled = .true.
            call parse_logical_env("INTODE_SOLVER_ASSIST_ENABLED", legacy_enabled)
            if (.not. legacy_enabled) then
               intode_solver_assist_policy = intode_solver_assist_policy_off
            else
               intode_solver_assist_policy = intode_solver_assist_policy_all_navigation_diagnostic
            end if
         end if
      end if
      intode_enable_solver_assist = (intode_solver_assist_policy /= intode_solver_assist_policy_off)
      intode_solver_assist_policy_loaded = .true.
   end subroutine ensure_intode_solver_assist_policy

   subroutine get_intode_final_resort_policy(enabled, max_uses, fast_hmin_bypass)
      implicit none
      logical, intent(out) :: enabled
      integer, intent(out) :: max_uses
      logical, intent(out) :: fast_hmin_bypass

      ! Compatibility alias for older diagnostics/output readers.
      call get_intode_solver_assist_policy(enabled, max_uses, fast_hmin_bypass)
   end subroutine get_intode_final_resort_policy

   subroutine set_intode_rattle_trace(rattle_step, rattle_substep)
      implicit none
      integer, intent(in) :: rattle_step, rattle_substep

      intode_trace_rattle_step = max(0, rattle_step)
      intode_trace_rattle_substep = max(0, rattle_substep)
   end subroutine set_intode_rattle_trace

   subroutine set_intode_stage_trace(stage_code)
      implicit none
      integer, intent(in) :: stage_code

      if (stage_code >= intode_stage_unknown .and. stage_code <= intode_stage_external) then
         intode_trace_stage = stage_code
      else
         intode_trace_stage = intode_stage_unknown
      end if
   end subroutine set_intode_stage_trace

   subroutine set_intode_residual_role_trace(role_code)
      implicit none
      integer, intent(in) :: role_code

      if (role_code >= intode_role_unknown .and. role_code <= intode_role_reverse_replay) then
         intode_trace_role = role_code
      else
         intode_trace_role = intode_role_unknown
      end if
   end subroutine set_intode_residual_role_trace

   subroutine get_intode_residual_role_trace(role_code)
      implicit none
      integer, intent(out) :: role_code

      role_code = intode_trace_role
   end subroutine get_intode_residual_role_trace

   subroutine set_intode_newton_iter_trace(iter_idx)
      implicit none
      integer, intent(in) :: iter_idx

      intode_trace_newton_iter = max(0, iter_idx)
   end subroutine set_intode_newton_iter_trace

   subroutine set_intode_quasi_iter_trace(iter_idx)
      implicit none
      integer, intent(in) :: iter_idx

      intode_trace_quasi_iter = max(0, iter_idx)
   end subroutine set_intode_quasi_iter_trace

   subroutine clear_intode_runtime_trace()
      implicit none

      intode_trace_rattle_step = 0
      intode_trace_rattle_substep = 0
      intode_trace_stage = intode_stage_unknown
      intode_trace_newton_iter = 0
      intode_trace_quasi_iter = 0
      intode_trace_role = intode_role_unknown
   end subroutine clear_intode_runtime_trace

   subroutine reset_intode_fallback_stats()
      implicit none

      intode_calls_total = 0
      intode_calls_integrating = 0
      intode_fallback_attempts = 0
      intode_fallback_success = 0
      intode_fallback_failure = 0
      intode_fallback_max_steps = 0
      intode_fallback_invalid = 0
      intode_fallback_h_min = 0
      intode_fallback_attempts_ctx = 0
      intode_fallback_failures_ctx = 0
      intode_rescue_success_solver_assist = 0
      intode_solver_assist_fail = 0
      intode_solver_assist_log_count = 0
      intode_trace_rattle_step = 0
      intode_trace_rattle_substep = 0
      intode_trace_stage = intode_stage_unknown
      intode_trace_newton_iter = 0
      intode_trace_quasi_iter = 0
      intode_trace_role = intode_role_unknown
      intode_last_failure_available = .false.
      intode_last_failure_reason = intode_reason_none
      intode_last_failure_context = intode_ctx_unknown
      intode_last_failure_rattle_step = 0
      intode_last_failure_rattle_substep = 0
      intode_last_failure_stage = intode_stage_unknown
      intode_last_failure_newton_iter = 0
      intode_last_failure_quasi_iter = 0
      intode_failure_log_count = 0
      intode_last_failure_t = 0.0_dp
      if (allocated(intode_last_failure_y)) deallocate (intode_last_failure_y)
   end subroutine reset_intode_fallback_stats

   subroutine get_intode_fallback_stats(calls_total, calls_integrating, fallback_attempts, fallback_success, fallback_failure, &
                                        fallback_max_steps, fallback_invalid, fallback_h_min)
      implicit none
      integer, intent(out) :: calls_total, calls_integrating
      integer, intent(out) :: fallback_attempts, fallback_success, fallback_failure
      integer, intent(out) :: fallback_max_steps, fallback_invalid, fallback_h_min

      calls_total = intode_calls_total
      calls_integrating = intode_calls_integrating
      fallback_attempts = intode_fallback_attempts
      fallback_success = intode_fallback_success
      fallback_failure = intode_fallback_failure
      fallback_max_steps = intode_fallback_max_steps
      fallback_invalid = intode_fallback_invalid
      fallback_h_min = intode_fallback_h_min
   end subroutine get_intode_fallback_stats

   subroutine get_intode_fallback_context_stats(attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                                fail_flowz, fail_flowzr, fail_flow, fail_unknown)
      implicit none
      integer, intent(out) :: attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown
      integer, intent(out) :: fail_flowz, fail_flowzr, fail_flow, fail_unknown

      attempt_flowz = intode_fallback_attempts_ctx(intode_ctx_flowz)
      attempt_flowzr = intode_fallback_attempts_ctx(intode_ctx_flowzr)
      attempt_flow = intode_fallback_attempts_ctx(intode_ctx_flow)
      attempt_unknown = intode_fallback_attempts_ctx(intode_ctx_unknown)
      fail_flowz = intode_fallback_failures_ctx(intode_ctx_flowz)
      fail_flowzr = intode_fallback_failures_ctx(intode_ctx_flowzr)
      fail_flow = intode_fallback_failures_ctx(intode_ctx_flow)
      fail_unknown = intode_fallback_failures_ctx(intode_ctx_unknown)
   end subroutine get_intode_fallback_context_stats

   subroutine get_intode_rescue_stats(success_radau_adaptive, success_radau_adaptive_robust, success_radau_fixed_tol, &
                                      success_radau_chunked, success_final_resort, fail_radau_adaptive_robust, &
                                      fail_radau_fixed_tol, fail_radau_chunked, fail_final_resort)
      implicit none
      integer, intent(out) :: success_radau_adaptive, success_radau_adaptive_robust
      integer, intent(out) :: success_radau_fixed_tol, success_radau_chunked, success_final_resort
      integer, intent(out) :: fail_radau_adaptive_robust, fail_radau_fixed_tol, fail_radau_chunked, fail_final_resort

      success_radau_adaptive = 0
      success_radau_adaptive_robust = 0
      success_radau_fixed_tol = 0
      success_radau_chunked = 0
      success_final_resort = intode_rescue_success_solver_assist
      fail_radau_adaptive_robust = 0
      fail_radau_fixed_tol = 0
      fail_radau_chunked = 0
      fail_final_resort = intode_solver_assist_fail
   end subroutine get_intode_rescue_stats

   subroutine get_intode_radau_diag_stats(adapt_newton_fail, adapt_linear_fail, adapt_error_reject, adapt_hmin_hit)
      implicit none
      integer, intent(out) :: adapt_newton_fail, adapt_linear_fail, adapt_error_reject, adapt_hmin_hit

      adapt_newton_fail = 0
      adapt_linear_fail = 0
      adapt_error_reject = 0
      adapt_hmin_hit = 0
   end subroutine get_intode_radau_diag_stats

   subroutine get_intode_last_failure_meta(available, reason_code, context_code, state_dim, t_remaining)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: reason_code, context_code, state_dim
      real(dp), intent(out) :: t_remaining

      available = intode_last_failure_available .and. allocated(intode_last_failure_y)
      reason_code = intode_last_failure_reason
      context_code = intode_last_failure_context
      t_remaining = intode_last_failure_t
      if (allocated(intode_last_failure_y)) then
         state_dim = size(intode_last_failure_y)
      else
         state_dim = 0
      end if
   end subroutine get_intode_last_failure_meta

   subroutine get_intode_last_failure_trace(available, rattle_step, rattle_substep, stage_code, newton_iter, quasi_iter)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: rattle_step, rattle_substep, stage_code, newton_iter, quasi_iter

      available = intode_last_failure_available
      rattle_step = intode_last_failure_rattle_step
      rattle_substep = intode_last_failure_rattle_substep
      stage_code = intode_last_failure_stage
      newton_iter = intode_last_failure_newton_iter
      quasi_iter = intode_last_failure_quasi_iter
   end subroutine get_intode_last_failure_trace

   function vector_has_invalid(values) result(has_invalid)
      implicit none
      real(dp), intent(in) :: values(:)
      logical :: has_invalid
      integer :: idx

      has_invalid = .false.
      do idx = 1, size(values)
         if (.not. ieee_is_finite(values(idx))) then
            has_invalid = .true.
            return
         end if
      end do
   end function vector_has_invalid

   subroutine flowz(x, z, error, status, workspace)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: workspace

      type(flow_workspace_t) :: local_workspace

      if (present(workspace)) then
         call flowz_with_workspace(x, z, error, status, workspace)
      else
         call flowz_with_workspace(x, z, error, status, local_workspace)
      end if
   end subroutine flowz

   subroutine flowzr(x, z, error, status, workspace)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: workspace

      type(flow_workspace_t) :: local_workspace

      if (present(workspace)) then
         call flowzr_with_workspace(x, z, error, status, workspace)
      else
         call flowzr_with_workspace(x, z, error, status, local_workspace)
      end if
   end subroutine flowzr

   subroutine flow(x, z, j, error, status, workspace)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      complex(dp), dimension(:, :), intent(inout)::j
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: workspace

      type(flow_workspace_t) :: local_workspace

      if (present(workspace)) then
         call flow_with_workspace(x, z, j, error, status, workspace)
      else
         call flow_with_workspace(x, z, j, error, status, local_workspace)
      end if
   end subroutine flow

   subroutine flowz_with_workspace(x, z, error, status, workspace)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace
      integer::n, n_complex
      integer :: flow_status_local
      real(dp)::t1
      real(dp) :: t_prof

      call perf_tic(t_prof)
      call set_intode_status(status, intode_status_unknown)
      n = size(z)*2
      n_complex = size(z)
      t1 = x(1)
      error = .false.

      call ensure_real_workspace(workspace%flow_vec_y, n)
      call ensure_real_workspace(workspace%flow_vec_yf, n)
      call ensure_complex_workspace(workspace%flow_vec_z, n_complex)
      call ensure_complex_workspace(workspace%flow_vec_ds, n_complex)

      workspace%flow_vec_y(1:n:2) = x(2:)
      workspace%flow_vec_y(2:n:2) = 0.0_dp
      intode_current_context = intode_ctx_flowz
      workspace%flow_vec_rhs_scale = 1.0_dp
      call intode_with_context(rhs_flow_vec_context, workspace%flow_vec_y(1:n), t1, workspace%flow_vec_yf(1:n), error, &
                               flow_status_local, workspace)
      intode_current_context = intode_ctx_unknown
      call set_intode_status(status, flow_status_local)
      if (error) then
         call perf_toc(PERF_FLOWZ, t_prof)
         return
      end if
      call real_to_complex(workspace%flow_vec_yf(1:n), z)
      call perf_toc(PERF_FLOWZ, t_prof)
   end subroutine flowz_with_workspace

   subroutine flowzr_with_workspace(x, z, error, status, workspace)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace
      integer::n, n_complex
      integer :: flow_status_local
      real(dp)::t1
      real(dp) :: t_prof

      call perf_tic(t_prof)
      call set_intode_status(status, intode_status_unknown)
      n = size(z)*2
      n_complex = size(z)
      t1 = x(1)
      error = .false.

      call ensure_real_workspace(workspace%flow_vec_y, n)
      call ensure_real_workspace(workspace%flow_vec_yf, n)
      call ensure_complex_workspace(workspace%flow_vec_z, n_complex)
      call ensure_complex_workspace(workspace%flow_vec_ds, n_complex)

      call complex_to_real(z, workspace%flow_vec_y(1:n))
      intode_current_context = intode_ctx_flowzr
      workspace%flow_vec_rhs_scale = -1.0_dp
      call intode_with_context(rhs_flow_vec_context, workspace%flow_vec_y(1:n), t1, workspace%flow_vec_yf(1:n), error, &
                               flow_status_local, workspace)
      intode_current_context = intode_ctx_unknown
      workspace%flow_vec_rhs_scale = 1.0_dp
      call set_intode_status(status, flow_status_local)
      if (error) then
         call perf_toc(PERF_FLOWZR, t_prof)
         return
      end if
      call real_to_complex(workspace%flow_vec_yf(1:n), z)
      call perf_toc(PERF_FLOWZR, t_prof)
   end subroutine flowzr_with_workspace

   subroutine flow_with_workspace(x, z, j, error, status, workspace)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      complex(dp), dimension(:, :), intent(inout)::j
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace
      integer::n, m, n_complex, n_jac
      integer :: total_n
      integer :: flow_status_local
      real(dp)::t1
      real(dp) :: t_prof

      call perf_tic(t_prof)
      call set_intode_status(status, intode_status_unknown)
      n = size(z)*2
      n_complex = size(z)
      n_jac = size(j, 1)
      m = size(j, 1)*size(j, 2)*2
      total_n = n + m
      t1 = x(1)
      error = .false.

      call ensure_real_workspace(workspace%flow_jac_y, total_n)
      call ensure_real_workspace(workspace%flow_jac_yf, total_n)
      call ensure_complex_workspace(workspace%flow_jac_z, n_complex)
      call ensure_complex_workspace(workspace%flow_jac_ds, n_complex)
      call ensure_complex_workspace_mat(workspace%flow_jac_j, n_jac, n_jac)
      call ensure_complex_workspace_mat(workspace%flow_jac_jprod, n_jac, n_jac)

      workspace%flow_jac_y(1:n:2) = x(2:)
      workspace%flow_jac_y(2:n:2) = 0.0_dp
      call fill_identity_real_map(workspace%flow_jac_y(n + 1:total_n), n_jac)
      intode_current_context = intode_ctx_flow
      call intode_with_context(rhs_flow_jac_context, workspace%flow_jac_y(1:total_n), t1, workspace%flow_jac_yf(1:total_n), error, &
                               flow_status_local, workspace)
      intode_current_context = intode_ctx_unknown
      call set_intode_status(status, flow_status_local)
      if (error) then
         call perf_toc(PERF_FLOW, t_prof)
         return
      end if
      call real_to_complex(workspace%flow_jac_yf(1:n), z)
      call map_to_complex(workspace%flow_jac_yf(n + 1:total_n), j)
      call perf_toc(PERF_FLOW, t_prof)
   end subroutine flow_with_workspace

   function rhs_flow_vec_context(y, context) result(f)
      implicit none
      real(dp), intent(in) :: y(:)
      class(*), intent(inout) :: context
      real(dp) :: f(size(y))
      integer :: n_complex

      f = 0.0_dp
      select type (workspace => context)
      type is (flow_workspace_t)
         if (.not. allocated(workspace%flow_vec_z) .or. .not. allocated(workspace%flow_vec_ds)) return
         n_complex = size(workspace%flow_vec_z)
         if (size(y) /= 2*n_complex) return

         call real_to_complex_vec_fast(y, workspace%flow_vec_z(1:n_complex))
         call ds(workspace%flow_vec_z(1:n_complex), workspace%flow_vec_ds(1:n_complex))
         call complex_to_real_vec_conjg_scaled_fast(workspace%flow_vec_ds(1:n_complex), f, workspace%flow_vec_rhs_scale)
      end select
   end function rhs_flow_vec_context

   function rhs_flow_jac_context(y, context) result(f)
      implicit none
      real(dp), intent(in) :: y(:)
      class(*), intent(inout) :: context
      real(dp) :: f(size(y))
      integer :: col
      integer :: n_complex, n_jac, n

      f = 0.0_dp
      select type (workspace => context)
      type is (flow_workspace_t)
         if (.not. allocated(workspace%flow_jac_z) .or. .not. allocated(workspace%flow_jac_ds)) return
         if (.not. allocated(workspace%flow_jac_j) .or. .not. allocated(workspace%flow_jac_jprod)) return

         n_complex = size(workspace%flow_jac_z)
         n_jac = size(workspace%flow_jac_j, 1)
         n = 2*n_complex
         if (size(workspace%flow_jac_j, 2) /= n_jac .or. size(workspace%flow_jac_jprod, 1) /= n_jac .or. &
             size(workspace%flow_jac_jprod, 2) /= n_jac) return
         if (size(y) /= n + 2*n_jac*n_jac) return

         call real_to_complex_vec_fast(y(1:n), workspace%flow_jac_z(1:n_complex))
         call real_to_complex_mat_rowmajor_fast(y(n + 1:), workspace%flow_jac_j(1:n_jac, 1:n_jac))
         call ds(workspace%flow_jac_z(1:n_complex), workspace%flow_jac_ds(1:n_complex))
         call complex_to_real_vec_conjg_scaled_fast(workspace%flow_jac_ds(1:n_complex), f(1:n), 1.0_dp)
         do col = 1, n_jac
            call hessian_vec(workspace%flow_jac_z(1:n_complex), workspace%flow_jac_j(1:n_jac, col), &
                             workspace%flow_jac_jprod(1:n_jac, col))
         end do
         call map_to_real_conjg_scaled(workspace%flow_jac_jprod(1:n_jac, 1:n_jac), f(n + 1:), 1.0_dp)
      end select
   end function rhs_flow_jac_context

   subroutine map_to_real_conjg_scaled(mat, vec, scale)
      implicit none
      complex(dp), intent(in) :: mat(:, :)
      real(dp), intent(out) :: vec(:)
      real(dp), intent(in) :: scale
      integer :: i, j, n

      n = size(mat, 1)
      if (size(mat, 2) /= n) then
         write (*, *) "Error(map_to_real_conjg_scaled): mat is not square."
         return
      end if
      if (size(vec) /= 2*n*n) then
         write (*, *) "Error(map_to_real_conjg_scaled): vec must have length=2*n*n."
         return
      end if

      do i = 1, n
         do j = 1, n
            vec(2*((i - 1)*n + j) - 1) = scale*real(mat(i, j), dp)
            vec(2*((i - 1)*n + j)) = -scale*aimag(mat(i, j))
         end do
      end do
   end subroutine map_to_real_conjg_scaled

   subroutine real_to_complex_vec_fast(r, c)
      implicit none
      real(dp), intent(in) :: r(:)
      complex(dp), intent(out) :: c(:)
      integer :: i

      do i = 1, size(c)
         c(i) = cmplx(r(2*i - 1), r(2*i), dp)
      end do
   end subroutine real_to_complex_vec_fast

   subroutine complex_to_real_vec_conjg_scaled_fast(c, r, scale)
      implicit none
      complex(dp), intent(in) :: c(:)
      real(dp), intent(out) :: r(:)
      real(dp), intent(in) :: scale
      integer :: i

      do i = 1, size(c)
         r(2*i - 1) = scale*real(c(i), dp)
         r(2*i) = -scale*aimag(c(i))
      end do
   end subroutine complex_to_real_vec_conjg_scaled_fast

   subroutine real_to_complex_mat_rowmajor_fast(vec, mat)
      implicit none
      real(dp), intent(in) :: vec(:)
      complex(dp), intent(out) :: mat(:, :)
      integer :: i, j, n, idx

      n = size(mat, 1)
      idx = 1
      do i = 1, n
         do j = 1, n
            mat(i, j) = cmplx(vec(idx), vec(idx + 1), dp)
            idx = idx + 2
         end do
      end do
   end subroutine real_to_complex_mat_rowmajor_fast

   subroutine release_flow_workspace(workspace)
      type(flow_workspace_t), intent(inout) :: workspace

      if (allocated(workspace%intode_yc)) deallocate (workspace%intode_yc)
      if (allocated(workspace%intode_yf)) deallocate (workspace%intode_yf)
      if (allocated(workspace%flow_vec_y)) deallocate (workspace%flow_vec_y)
      if (allocated(workspace%flow_vec_yf)) deallocate (workspace%flow_vec_yf)
      if (allocated(workspace%flow_jac_y)) deallocate (workspace%flow_jac_y)
      if (allocated(workspace%flow_jac_yf)) deallocate (workspace%flow_jac_yf)
      if (allocated(workspace%flow_vec_z)) deallocate (workspace%flow_vec_z)
      if (allocated(workspace%flow_vec_ds)) deallocate (workspace%flow_vec_ds)
      if (allocated(workspace%flow_jac_z)) deallocate (workspace%flow_jac_z)
      if (allocated(workspace%flow_jac_ds)) deallocate (workspace%flow_jac_ds)
      if (allocated(workspace%flow_jac_j)) deallocate (workspace%flow_jac_j)
      if (allocated(workspace%flow_jac_jprod)) deallocate (workspace%flow_jac_jprod)
      if (allocated(workspace%intode_odex_workspace%tableau)) deallocate (workspace%intode_odex_workspace%tableau)
      if (allocated(workspace%intode_odex_workspace%ystate)) deallocate (workspace%intode_odex_workspace%ystate)
      if (allocated(workspace%intode_odex_workspace%yprev)) deallocate (workspace%intode_odex_workspace%yprev)
      if (allocated(workspace%intode_odex_workspace%ycurr)) deallocate (workspace%intode_odex_workspace%ycurr)
      if (allocated(workspace%intode_odex_workspace%ynext)) deallocate (workspace%intode_odex_workspace%ynext)
      if (allocated(workspace%intode_odex_workspace%fval)) deallocate (workspace%intode_odex_workspace%fval)
      if (allocated(workspace%intode_odex_workspace%fbase)) deallocate (workspace%intode_odex_workspace%fbase)
      if (allocated(workspace%intode_odex_workspace%nsteps)) deallocate (workspace%intode_odex_workspace%nsteps)
      if (allocated(workspace%intode_odex_workspace%ak)) deallocate (workspace%intode_odex_workspace%ak)
      if (allocated(workspace%intode_odex_workspace%invexp)) deallocate (workspace%intode_odex_workspace%invexp)
      if (allocated(workspace%intode_odex_workspace%ratio)) deallocate (workspace%intode_odex_workspace%ratio)
      workspace%flow_vec_rhs_scale = 1.0_dp
      workspace%intode_odex_workspace%tables_ready = .false.
      workspace%intode_odex_workspace%table_k = 0
   end subroutine release_flow_workspace

   subroutine ensure_real_workspace(buf, n_need)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_real_workspace

   subroutine ensure_complex_workspace(buf, n_need)
      implicit none
      complex(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_complex_workspace

   subroutine ensure_complex_workspace_mat(buf, nr_need, nc_need)
      implicit none
      complex(dp), allocatable, intent(inout) :: buf(:, :)
      integer, intent(in) :: nr_need, nc_need

      if (.not. allocated(buf)) then
         allocate (buf(nr_need, nc_need))
      elseif (size(buf, 1) < nr_need .or. size(buf, 2) < nc_need) then
         deallocate (buf)
         allocate (buf(nr_need, nc_need))
      end if
   end subroutine ensure_complex_workspace_mat

   subroutine fill_identity_real_map(vec, n)
      implicit none
      real(dp), intent(out) :: vec(:)
      integer, intent(in) :: n
      integer :: i, idx

      if (size(vec) /= 2*n*n) then
         write (*, '(A)') "[ERROR] fill_identity_real_map: vec must have size 2*n*n."
         return
      end if

      vec = 0.0_dp
      do i = 1, n
         idx = 2*((i - 1)*n + i) - 1
         vec(idx) = 1.0_dp
      end do
   end subroutine fill_identity_real_map
end module solve_flow

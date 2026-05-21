module solve_flow
   use param_mod, only: at, rt
   use runtime_env_mod, only: parse_int_env, parse_real_env, read_string_env
   use utils, only: dp, complex_to_real, map_to_complex, pack_legacy_x, real_to_complex
   use model, only: ds, hessian_vec
   use odex_backend, only: build_nsteps, ensure_odex_workspace_object, ode_rhs, ode_rhs_context, &
                           odex_apply_backend_name, odex_apply_controller_policy_name, &
                           odex_backend_default_options => odex_default_options, &
                           odex_integrate_endpoint, odex_integrate_endpoint_context, &
                           odex_k_max, odex_k_min, odex_max_steps_default, &
                           odex_options, odex_reason_h_min, odex_reason_invalid, odex_reason_max_steps, &
                           odex_reason_none, odex_result, odex_result_mark_failure, odex_result_mark_success, &
                           odex_result_reset, odex_result_to_intode_status, odex_status_failure_h_min, &
                           odex_status_failure_invalid, odex_status_failure_max_steps, &
                           odex_status_from_failure_reason, odex_status_is_failure, &
                           odex_status_is_mechanism_status, odex_status_success, &
                           odex_status_success_zero_time, odex_status_unknown, odex_step_sequence_iwork3, &
                           odex_stability_control_conservative, odex_stability_control_none, odex_workspace
   use perf_profile, only: perf_tic, perf_toc, PERF_INTODE, PERF_FLOW, PERF_FLOWZ, PERF_FLOWZR
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use, intrinsic :: iso_fortran_env, only: int64
   implicit none

   type :: intode_runtime_trace_context_t
      integer :: rattle_step = 0
      integer :: rattle_substep = 0
      integer :: stage = 0
      integer :: newton_iter = 0
      integer :: quasi_iter = 0
      integer :: role = 0
      integer :: current_context = 0
   end type intode_runtime_trace_context_t

   type :: flow_workspace_t
      real(dp), allocatable :: intode_yc(:), intode_yf(:)
      real(dp), allocatable :: flow_vec_y(:), flow_vec_yf(:)
      real(dp), allocatable :: flow_jac_y(:), flow_jac_yf(:)
      complex(dp), allocatable :: flow_vec_z(:), flow_vec_ds(:)
      complex(dp), allocatable :: flow_jac_z(:), flow_jac_ds(:)
      complex(dp), allocatable :: flow_jac_j(:, :), flow_jac_jprod(:, :)
      real(dp) :: flow_vec_rhs_scale = 1.0_dp
      type(intode_runtime_trace_context_t) :: intode_trace
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
   logical, parameter :: intode_verbose_logs = .false.
   integer, parameter :: intode_failure_log_limit = 20

   type :: intode_diagnostics_context_t
      integer :: calls_total = 0
      integer :: calls_integrating = 0
      integer :: fallback_attempts = 0
      integer :: fallback_success = 0
      integer :: fallback_failure = 0
      integer :: fallback_max_steps = 0
      integer :: fallback_invalid = 0
      integer :: fallback_h_min = 0
      integer :: fallback_attempts_ctx(intode_ctx_unknown:intode_ctx_flow) = 0
      integer :: fallback_failures_ctx(intode_ctx_unknown:intode_ctx_flow) = 0
      integer(int64) :: cvode_calls = 0_int64
      integer(int64) :: cvode_success = 0_int64
      integer(int64) :: cvode_failure = 0_int64
      integer(int64) :: cvode_steps_sum = 0_int64
      integer(int64) :: cvode_rhs_evals_sum = 0_int64
      integer(int64) :: cvode_error_test_fails_sum = 0_int64
      integer(int64) :: cvode_nonlinear_iters_sum = 0_int64
      integer(int64) :: cvode_nonlinear_conv_fails_sum = 0_int64
      integer(int64) :: cvode_step_solve_fails_sum = 0_int64
      integer(int64) :: cvode_final_order_sum = 0_int64
      integer(int64) :: cvode_max_final_order = 0_int64
      integer(int64) :: cvode_calls_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: cvode_steps_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: cvode_rhs_evals_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: cvode_error_test_fails_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: cvode_nonlinear_iters_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: cvode_nonlinear_conv_fails_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: cvode_step_solve_fails_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: odex_calls = 0_int64
      integer(int64) :: odex_success = 0_int64
      integer(int64) :: odex_failure = 0_int64
      integer(int64) :: odex_accepted_steps_sum = 0_int64
      integer(int64) :: odex_rejected_steps_sum = 0_int64
      integer(int64) :: odex_stability_rejects_sum = 0_int64
      integer(int64) :: odex_rhs_evals_sum = 0_int64
      integer(int64) :: odex_midpoint_rows_sum = 0_int64
      integer(int64) :: odex_kplus1_attempts_sum = 0_int64
      integer(int64) :: odex_accept_k_minus_1_sum = 0_int64
      integer(int64) :: odex_accept_k_sum = 0_int64
      integer(int64) :: odex_accept_k_plus_1_sum = 0_int64
      integer(int64) :: odex_large_error_rejects_sum = 0_int64
      integer(int64) :: odex_kplus1_rejects_sum = 0_int64
      integer(int64) :: odex_hairer_policy_steps_sum = 0_int64
      integer(int64) :: odex_tltm_policy_steps_sum = 0_int64
      integer(int64) :: odex_first_step_entries_sum = 0_int64
      integer(int64) :: odex_last_step_entries_sum = 0_int64
      integer(int64) :: odex_basic_step_entries_sum = 0_int64
      integer(int64) :: odex_row_j1_calls_sum = 0_int64
      integer(int64) :: odex_row_j2_calls_sum = 0_int64
      integer(int64) :: odex_row_jge3_calls_sum = 0_int64
      integer(int64) :: odex_row_j1_no_error_returns_sum = 0_int64
      integer(int64) :: odex_error_estimates_sum = 0_int64
      integer(int64) :: odex_hairer_scal_estimates_sum = 0_int64
      integer(int64) :: odex_default_scal_estimates_sum = 0_int64
      integer(int64) :: odex_errold_checks_sum = 0_int64
      integer(int64) :: odex_atov_events_sum = 0_int64
      integer(int64) :: odex_convergence_rejects_sum = 0_int64
      integer(int64) :: odex_kplus1_hope_rejects_sum = 0_int64
      integer(int64) :: odex_reject_kc_k_minus_1_sum = 0_int64
      integer(int64) :: odex_reject_kc_k_sum = 0_int64
      integer(int64) :: odex_reject_kc_k_plus_1_sum = 0_int64
      integer(int64) :: odex_kopt_accept_updates_sum = 0_int64
      integer(int64) :: odex_kopt_demotions_sum = 0_int64
      integer(int64) :: odex_kopt_keeps_sum = 0_int64
      integer(int64) :: odex_kopt_promotions_sum = 0_int64
      integer(int64) :: odex_after_reject_clamps_sum = 0_int64
      integer(int64) :: odex_reject_updates_sum = 0_int64
      integer(int64) :: odex_final_order_sum = 0_int64
      integer(int64) :: odex_max_final_order = 0_int64
      integer(int64) :: odex_calls_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: odex_accepted_steps_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: odex_rejected_steps_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: odex_rhs_evals_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: odex_midpoint_rows_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      integer(int64) :: odex_kplus1_attempts_ctx(intode_ctx_unknown:intode_ctx_flow) = 0_int64
      logical :: last_odex_result_available = .false.
      type(odex_result) :: last_odex_result
      logical :: capture_failures = .true.
      logical :: last_failure_available = .false.
      integer :: last_failure_reason = intode_reason_none
      integer :: last_failure_context = intode_ctx_unknown
      integer :: last_failure_rattle_step = 0
      integer :: last_failure_rattle_substep = 0
      integer :: last_failure_stage = intode_stage_unknown
      integer :: last_failure_newton_iter = 0
      integer :: last_failure_quasi_iter = 0
      integer :: failure_log_count = 0
      real(dp) :: last_failure_t = 0.0_dp
      real(dp), allocatable :: last_failure_y(:)
   end type intode_diagnostics_context_t

   type(intode_diagnostics_context_t), save, target :: module_intode_diagnostics
   type(intode_runtime_trace_context_t), save :: module_intode_trace
   logical, save :: flowz_capture_ready = .false.
   logical, save :: flowz_capture_enabled = .false.
   logical, save :: flowz_capture_write_error = .false.
   integer, save :: flowz_capture_unit = -1
   integer, save :: flowz_capture_limit = 1000
   integer, save :: flowz_capture_start = 1
   integer, save :: flowz_capture_stride = 1
   integer, save :: flowz_capture_observed = 0
   integer, save :: flowz_capture_written = 0
   character(len=512), save :: flowz_capture_file = ""
   logical, save :: flowz_cost_capture_ready = .false.
   logical, save :: flowz_cost_capture_enabled = .false.
   logical, save :: flowz_cost_capture_write_error = .false.
   integer, save :: flowz_cost_capture_unit = -1
   integer, save :: flowz_cost_capture_limit = 1000
   integer, save :: flowz_cost_capture_min_rhs = 512
   integer, save :: flowz_cost_capture_min_rejected = 16
   integer, save :: flowz_cost_capture_observed = 0
   integer, save :: flowz_cost_capture_written = 0
   character(len=512), save :: flowz_cost_capture_file = ""

contains

   subroutine initialize_flowz_capture()
      implicit none
      logical :: has_capture_file
      integer :: ios

      if (flowz_capture_ready) return
      flowz_capture_ready = .true.
      flowz_capture_enabled = .false.
      flowz_capture_write_error = .false.
      flowz_capture_file = ""
      call read_string_env("TLTM_FLOWZ_CAPTURE_FILE", flowz_capture_file, has_capture_file)
      if (.not. has_capture_file) return

      call parse_int_env("TLTM_FLOWZ_CAPTURE_LIMIT", flowz_capture_limit)
      call parse_int_env("TLTM_FLOWZ_CAPTURE_START", flowz_capture_start)
      call parse_int_env("TLTM_FLOWZ_CAPTURE_STRIDE", flowz_capture_stride)
      flowz_capture_start = max(1, flowz_capture_start)
      flowz_capture_stride = max(1, flowz_capture_stride)

      open (newunit=flowz_capture_unit, file=trim(flowz_capture_file), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         flowz_capture_write_error = .true.
         return
      end if
      write (flowz_capture_unit, '(A)', iostat=ios) "# observed stage newton_iter quasi_iter role x_size x_values..."
      flowz_capture_write_error = (ios /= 0)
      flowz_capture_enabled = .not. flowz_capture_write_error
   end subroutine initialize_flowz_capture

   subroutine maybe_capture_flowz_input(x, intode_trace)
      implicit none
      real(dp), intent(in) :: x(:)
      type(intode_runtime_trace_context_t), intent(in) :: intode_trace
      integer :: ios

      call initialize_flowz_capture()
      if (.not. flowz_capture_enabled) return
      if (flowz_capture_write_error) return

      flowz_capture_observed = flowz_capture_observed + 1
      if (flowz_capture_observed < flowz_capture_start) return
      if (mod(flowz_capture_observed - flowz_capture_start, flowz_capture_stride) /= 0) return
      if (flowz_capture_limit > 0 .and. flowz_capture_written >= flowz_capture_limit) return

      write (flowz_capture_unit, *, iostat=ios) flowz_capture_observed, intode_trace%stage, &
         intode_trace%newton_iter, intode_trace%quasi_iter, intode_trace%role, size(x), x
      if (ios /= 0) then
         flowz_capture_write_error = .true.
         flowz_capture_enabled = .false.
         return
      end if
      flowz_capture_written = flowz_capture_written + 1
   end subroutine maybe_capture_flowz_input

   subroutine maybe_capture_flowz_input_at(flow_time, x_state, intode_trace)
      implicit none
      real(dp), intent(in) :: flow_time
      real(dp), intent(in) :: x_state(:)
      type(intode_runtime_trace_context_t), intent(in) :: intode_trace
      real(dp), allocatable :: x_legacy(:)

      call initialize_flowz_capture()
      if (.not. flowz_capture_enabled) return
      if (flowz_capture_write_error) return

      allocate (x_legacy(size(x_state) + 1))
      call pack_legacy_x(flow_time, x_state, x_legacy)
      call maybe_capture_flowz_input(x_legacy, intode_trace)
      deallocate (x_legacy)
   end subroutine maybe_capture_flowz_input_at

   subroutine initialize_flowz_cost_capture()
      implicit none
      logical :: has_capture_file
      integer :: ios

      if (flowz_cost_capture_ready) return
      flowz_cost_capture_ready = .true.
      flowz_cost_capture_enabled = .false.
      flowz_cost_capture_write_error = .false.
      flowz_cost_capture_file = ""
      flowz_cost_capture_limit = 1000
      flowz_cost_capture_min_rhs = 512
      flowz_cost_capture_min_rejected = 16

      call read_string_env("TLTM_FLOWZ_COST_CAPTURE_FILE", flowz_cost_capture_file, has_capture_file)
      if (.not. has_capture_file) return

      call parse_int_env("TLTM_FLOWZ_COST_CAPTURE_LIMIT", flowz_cost_capture_limit)
      call parse_int_env("TLTM_FLOWZ_COST_CAPTURE_MIN_RHS", flowz_cost_capture_min_rhs)
      call parse_int_env("TLTM_FLOWZ_COST_CAPTURE_MIN_REJECTED", flowz_cost_capture_min_rejected)
      flowz_cost_capture_limit = max(0, flowz_cost_capture_limit)
      flowz_cost_capture_min_rhs = max(0, flowz_cost_capture_min_rhs)
      flowz_cost_capture_min_rejected = max(0, flowz_cost_capture_min_rejected)

      open (newunit=flowz_cost_capture_unit, file=trim(flowz_cost_capture_file), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         flowz_cost_capture_write_error = .true.
         return
      end if
      write (flowz_cost_capture_unit, '(A)', iostat=ios) "# flowz cost capture"
      if (ios == 0) write (flowz_cost_capture_unit, '(A)', iostat=ios) "# data: observed stage newton_iter quasi_iter role x_size"
      if (ios == 0) write (flowz_cost_capture_unit, '(A)', iostat=ios) "# data continuation: x_values"
      if (ios == 0) write (flowz_cost_capture_unit, '(A)', iostat=ios) &
         "# cost: observed written stage newton_iter quasi_iter role x_size flow_status flow_error"
      if (ios == 0) write (flowz_cost_capture_unit, '(A)', iostat=ios) &
         "# cost continuation: odex_status failure_reason accepted_steps rejected_steps stability_rejects"
      if (ios == 0) write (flowz_cost_capture_unit, '(A)', iostat=ios) &
         "# cost continuation: rhs_evals midpoint_rows kplus1_attempts large_error_rejects kplus1_rejects"
      if (ios == 0) write (flowz_cost_capture_unit, '(A)', iostat=ios) &
         "# cost continuation: convergence_rejects kplus1_hope_rejects reject_updates final_order final_step_size t_remaining"
      flowz_cost_capture_write_error = (ios /= 0)
      flowz_cost_capture_enabled = .not. flowz_cost_capture_write_error
   end subroutine initialize_flowz_cost_capture

   subroutine maybe_capture_flowz_cost_input(x, intode_trace, result_state, flow_status, flow_error)
      implicit none
      real(dp), intent(in) :: x(:)
      type(intode_runtime_trace_context_t), intent(in) :: intode_trace
      type(odex_result), intent(in) :: result_state
      integer, intent(in) :: flow_status
      logical, intent(in) :: flow_error
      integer :: ios

      call initialize_flowz_cost_capture()
      if (.not. flowz_cost_capture_enabled) return
      if (flowz_cost_capture_write_error) return

      flowz_cost_capture_observed = flowz_cost_capture_observed + 1
      if (.not. flowz_cost_capture_should_write(result_state, flow_error)) return
      if (flowz_cost_capture_limit > 0 .and. flowz_cost_capture_written >= flowz_cost_capture_limit) return

      write (flowz_cost_capture_unit, '(A,7(1X,I0))', iostat=ios) "# cost_a", flowz_cost_capture_observed, &
         flowz_cost_capture_written + 1, intode_trace%stage, intode_trace%newton_iter, intode_trace%quasi_iter, &
         intode_trace%role, size(x)
      if (ios == 0) write (flowz_cost_capture_unit, '(A,7(1X,I0))', iostat=ios) "# cost_b", flow_status, &
         merge(1, 0, flow_error), result_state%status, result_state%failure_reason, result_state%accepted_steps, &
         result_state%rejected_steps, result_state%stability_rejects
      if (ios == 0) write (flowz_cost_capture_unit, '(A,7(1X,I0))', iostat=ios) "# cost_c", &
         result_state%odex_rhs_evals, result_state%odex_midpoint_rows, result_state%odex_kplus1_attempts, &
         result_state%odex_large_error_rejects, result_state%odex_kplus1_rejects, &
         result_state%odex_convergence_rejects, result_state%odex_kplus1_hope_rejects
      if (ios == 0) write (flowz_cost_capture_unit, '(A,1X,I0,1X,I0,2(1X,ES24.16E3))', iostat=ios) "# cost_d", &
         result_state%odex_reject_updates, result_state%final_order, result_state%final_step_size, result_state%t_remaining
      if (ios == 0) write (flowz_cost_capture_unit, *, iostat=ios) flowz_cost_capture_observed, &
         intode_trace%stage, intode_trace%newton_iter, intode_trace%quasi_iter, intode_trace%role, size(x)
      if (ios == 0) write (flowz_cost_capture_unit, *, iostat=ios) x
      if (ios /= 0) then
         flowz_cost_capture_write_error = .true.
         flowz_cost_capture_enabled = .false.
         return
      end if
      flowz_cost_capture_written = flowz_cost_capture_written + 1
   end subroutine maybe_capture_flowz_cost_input

   subroutine maybe_capture_flowz_cost_input_at(flow_time, x_state, intode_trace, result_state, flow_status, flow_error)
      implicit none
      real(dp), intent(in) :: flow_time
      real(dp), intent(in) :: x_state(:)
      type(intode_runtime_trace_context_t), intent(in) :: intode_trace
      type(odex_result), intent(in) :: result_state
      integer, intent(in) :: flow_status
      logical, intent(in) :: flow_error
      real(dp), allocatable :: x_legacy(:)

      call initialize_flowz_cost_capture()
      if (.not. flowz_cost_capture_enabled) return
      if (flowz_cost_capture_write_error) return

      allocate (x_legacy(size(x_state) + 1))
      call pack_legacy_x(flow_time, x_state, x_legacy)
      call maybe_capture_flowz_cost_input(x_legacy, intode_trace, result_state, flow_status, flow_error)
      deallocate (x_legacy)
   end subroutine maybe_capture_flowz_cost_input_at

   logical function flowz_cost_capture_should_write(result_state, flow_error) result(should_write)
      implicit none
      type(odex_result), intent(in) :: result_state
      logical, intent(in) :: flow_error

      should_write = flow_error
      should_write = should_write .or. result_state%status /= odex_status_success
      if (flowz_cost_capture_min_rhs > 0) then
         should_write = should_write .or. result_state%odex_rhs_evals >= flowz_cost_capture_min_rhs
      end if
      if (flowz_cost_capture_min_rejected > 0) then
         should_write = should_write .or. result_state%rejected_steps >= flowz_cost_capture_min_rejected
      end if
      should_write = should_write .or. result_state%odex_kplus1_rejects > 0
      should_write = should_write .or. result_state%odex_convergence_rejects > 0
      should_write = should_write .or. result_state%odex_kplus1_hope_rejects > 0
   end function flowz_cost_capture_should_write

   subroutine odex_default_options(options)
      implicit none
      type(odex_options), intent(out) :: options
      character(len=128) :: backend_token
      character(len=128) :: controller_policy_token
      logical :: has_backend
      logical :: has_controller_policy

      call odex_backend_default_options(options, at, rt)
      call read_string_env("TLTM_ODE_BACKEND", backend_token, has_backend)
      if (has_backend) call odex_apply_backend_name(options, backend_token)
      call read_string_env("TLTM_ODE_CONTROLLER_POLICY", controller_policy_token, has_controller_policy)
      if (has_controller_policy) call odex_apply_controller_policy_name(options, controller_policy_token)
      call parse_int_env("TLTM_CVODE_FIXEDPOINT_M", options%cvode_fixedpoint_m)
      call parse_int_env("TLTM_CVODE_MAX_ORDER", options%cvode_max_order)
      call parse_int_env("TLTM_CVODE_MAX_STEPS", options%cvode_max_steps)
      call parse_real_env("TLTM_CVODE_MIN_STEP", options%cvode_min_step)
      call parse_int_env("TLTM_CVODE_MAX_ERR_TEST_FAILS", options%cvode_max_err_test_fails)
      call parse_int_env("TLTM_CVODE_MAX_CONV_FAILS", options%cvode_max_conv_fails)
      call parse_int_env("TLTM_CVODE_MAX_NONLIN_ITERS", options%cvode_max_nonlin_iters)
   end subroutine odex_default_options

   subroutine intode(f, y, t, res, error_flag, status, intode_diagnostics)
      implicit none
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      integer, intent(out), optional :: status
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      integer :: state_size, failure_reason
      logical :: rescue_failed
      real(dp) :: t_remaining
      type(odex_options) :: integration_options
      type(odex_result) :: integration_result
      type(flow_workspace_t) :: local_workspace
      type(intode_diagnostics_context_t), pointer :: active_diagnostics
      real(dp) :: t_prof

      call perf_tic(t_prof)
      call odex_result_reset(integration_result)
      call set_intode_status(status, intode_status_unknown)
      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      active_diagnostics%last_odex_result_available = .false.
      call odex_result_reset(active_diagnostics%last_odex_result)
      active_diagnostics%calls_total = active_diagnostics%calls_total + 1
      if (t == 0.0_dp) then
         res = y
         error_flag = .false.
         call odex_result_mark_success(integration_result, odex_status_success_zero_time, 0, 0, 0.0_dp)
         call set_intode_status(status, odex_result_to_intode_status(integration_result))
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if
      active_diagnostics%calls_integrating = active_diagnostics%calls_integrating + 1

      state_size = size(y)
      call ensure_real_workspace(local_workspace%intode_yc, state_size)
      call ensure_real_workspace(local_workspace%intode_yf, state_size)

      call odex_default_options(integration_options)
      call odex_integrate_endpoint(f, y, t, local_workspace%intode_yf(1:state_size), error_flag, &
                                   integration_result, local_workspace%intode_odex_workspace, integration_options)
      call record_intode_cvode_result(integration_result, active_diagnostics, module_intode_trace%current_context)
      call record_intode_odex_result(integration_result, active_diagnostics, module_intode_trace%current_context)
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

      active_diagnostics%fallback_attempts = active_diagnostics%fallback_attempts + 1
      select case (failure_reason)
      case (intode_reason_max_steps)
         active_diagnostics%fallback_max_steps = active_diagnostics%fallback_max_steps + 1
      case (intode_reason_invalid)
         active_diagnostics%fallback_invalid = active_diagnostics%fallback_invalid + 1
      case (intode_reason_h_min)
         active_diagnostics%fallback_h_min = active_diagnostics%fallback_h_min + 1
      end select
      call record_intode_fallback_attempt_context(active_diagnostics, module_intode_trace%current_context)

      call intode_stiff_rescue(f, local_workspace%intode_yc(1:state_size), t_remaining, local_workspace%intode_yf(1:state_size), rescue_failed)
      if (.not. rescue_failed) then
         active_diagnostics%fallback_success = active_diagnostics%fallback_success + 1
         res = local_workspace%intode_yf(1:state_size)
         error_flag = .false.
         call set_intode_status(status, intode_status_success_stiff_rescue)
      else
         active_diagnostics%fallback_failure = active_diagnostics%fallback_failure + 1
         call record_intode_fallback_failure_context(active_diagnostics, module_intode_trace%current_context)
         call record_intode_last_failure(local_workspace%intode_yc(1:state_size), t_remaining, failure_reason, &
                                         active_diagnostics, module_intode_trace)
         res = local_workspace%intode_yc(1:state_size)
         error_flag = .true.
         call set_intode_status(status, odex_result_to_intode_status(integration_result))
      end if
      call perf_toc(PERF_INTODE, t_prof)
   end subroutine intode

   subroutine intode_with_context(f, y, t, res, error_flag, status, workspace, intode_diagnostics)
      implicit none
      procedure(ode_rhs_context) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      integer :: state_size, failure_reason
      logical :: rescue_failed
      real(dp) :: t_remaining
      type(odex_options) :: integration_options
      type(odex_result) :: integration_result
      type(intode_diagnostics_context_t), pointer :: active_diagnostics
      real(dp) :: t_prof

      call perf_tic(t_prof)
      call odex_result_reset(integration_result)
      call set_intode_status(status, intode_status_unknown)
      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      active_diagnostics%last_odex_result_available = .false.
      call odex_result_reset(active_diagnostics%last_odex_result)
      active_diagnostics%calls_total = active_diagnostics%calls_total + 1
      if (t == 0.0_dp) then
         res = y
         error_flag = .false.
         call odex_result_mark_success(integration_result, odex_status_success_zero_time, 0, 0, 0.0_dp)
         call set_intode_status(status, odex_result_to_intode_status(integration_result))
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if
      active_diagnostics%calls_integrating = active_diagnostics%calls_integrating + 1

      state_size = size(y)
      call ensure_real_workspace(workspace%intode_yc, state_size)
      call ensure_real_workspace(workspace%intode_yf, state_size)

      call odex_default_options(integration_options)
      call odex_integrate_endpoint_context(f, y, t, workspace%intode_yf(1:state_size), error_flag, &
                                           integration_result, workspace%intode_odex_workspace, integration_options, workspace)
      call record_intode_cvode_result(integration_result, active_diagnostics, workspace%intode_trace%current_context)
      call record_intode_odex_result(integration_result, active_diagnostics, workspace%intode_trace%current_context)
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

      active_diagnostics%fallback_attempts = active_diagnostics%fallback_attempts + 1
      select case (failure_reason)
      case (intode_reason_max_steps)
         active_diagnostics%fallback_max_steps = active_diagnostics%fallback_max_steps + 1
      case (intode_reason_invalid)
         active_diagnostics%fallback_invalid = active_diagnostics%fallback_invalid + 1
      case (intode_reason_h_min)
         active_diagnostics%fallback_h_min = active_diagnostics%fallback_h_min + 1
      end select
      call record_intode_fallback_attempt_context(active_diagnostics, workspace%intode_trace%current_context)

      call intode_stiff_rescue_context(f, workspace%intode_yc(1:state_size), t_remaining, workspace%intode_yf(1:state_size), &
                                       rescue_failed, workspace)
      if (.not. rescue_failed) then
         active_diagnostics%fallback_success = active_diagnostics%fallback_success + 1
         res = workspace%intode_yf(1:state_size)
         error_flag = .false.
         call set_intode_status(status, intode_status_success_stiff_rescue)
      else
         active_diagnostics%fallback_failure = active_diagnostics%fallback_failure + 1
         call record_intode_fallback_failure_context(active_diagnostics, workspace%intode_trace%current_context)
         call record_intode_last_failure(workspace%intode_yc(1:state_size), t_remaining, failure_reason, &
                                         active_diagnostics, workspace%intode_trace)
         res = workspace%intode_yc(1:state_size)
         error_flag = .true.
         call set_intode_status(status, odex_result_to_intode_status(integration_result))
      end if
      call perf_toc(PERF_INTODE, t_prof)
   end subroutine intode_with_context

   subroutine set_intode_status(status, status_code)
      implicit none
      integer, intent(out), optional :: status
      integer, intent(in) :: status_code

      if (present(status)) status = status_code
   end subroutine set_intode_status

   subroutine resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      implicit none
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics

      if (present(intode_diagnostics)) then
         active_diagnostics => intode_diagnostics
      else
         active_diagnostics => module_intode_diagnostics
      end if
   end subroutine resolve_intode_diagnostics_context

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

   logical function intode_solver_assist_policy_allows(reason_code, context_code, stage_code, success_count, role_code) result(allowed)
      implicit none
      integer, intent(in) :: reason_code, context_code, stage_code, success_count
      integer, intent(in), optional :: role_code

      allowed = .false.
   end function intode_solver_assist_policy_allows

   subroutine record_intode_fallback_attempt_context(intode_diagnostics, ctx_code)
      implicit none
      type(intode_diagnostics_context_t), intent(inout) :: intode_diagnostics
      integer, intent(in) :: ctx_code
      integer :: idx

      idx = normalize_context_code(ctx_code)
      intode_diagnostics%fallback_attempts_ctx(idx) = intode_diagnostics%fallback_attempts_ctx(idx) + 1
   end subroutine record_intode_fallback_attempt_context

   subroutine record_intode_fallback_failure_context(intode_diagnostics, ctx_code)
      implicit none
      type(intode_diagnostics_context_t), intent(inout) :: intode_diagnostics
      integer, intent(in) :: ctx_code
      integer :: idx

      idx = normalize_context_code(ctx_code)
      intode_diagnostics%fallback_failures_ctx(idx) = intode_diagnostics%fallback_failures_ctx(idx) + 1
   end subroutine record_intode_fallback_failure_context

   subroutine record_intode_cvode_result(result_state, intode_diagnostics, context_code)
      implicit none
      type(odex_result), intent(in) :: result_state
      type(intode_diagnostics_context_t), intent(inout) :: intode_diagnostics
      integer, intent(in) :: context_code
      integer :: idx

      if (.not. result_state%cvode_backend_used) return

      idx = normalize_context_code(context_code)
      intode_diagnostics%cvode_calls = intode_diagnostics%cvode_calls + 1_int64
      intode_diagnostics%cvode_calls_ctx(idx) = intode_diagnostics%cvode_calls_ctx(idx) + 1_int64
      if (result_state%status == odex_status_success) then
         intode_diagnostics%cvode_success = intode_diagnostics%cvode_success + 1_int64
      else
         intode_diagnostics%cvode_failure = intode_diagnostics%cvode_failure + 1_int64
      end if

      intode_diagnostics%cvode_steps_sum = intode_diagnostics%cvode_steps_sum + int(max(0, result_state%accepted_steps), int64)
      intode_diagnostics%cvode_rhs_evals_sum = intode_diagnostics%cvode_rhs_evals_sum + int(max(0, result_state%cvode_rhs_evals), int64)
      intode_diagnostics%cvode_error_test_fails_sum = intode_diagnostics%cvode_error_test_fails_sum + &
         int(max(0, result_state%cvode_error_test_fails), int64)
      intode_diagnostics%cvode_nonlinear_iters_sum = intode_diagnostics%cvode_nonlinear_iters_sum + &
         int(max(0, result_state%cvode_nonlinear_iters), int64)
      intode_diagnostics%cvode_nonlinear_conv_fails_sum = intode_diagnostics%cvode_nonlinear_conv_fails_sum + &
         int(max(0, result_state%cvode_nonlinear_conv_fails), int64)
      intode_diagnostics%cvode_step_solve_fails_sum = intode_diagnostics%cvode_step_solve_fails_sum + &
         int(max(0, result_state%cvode_step_solve_fails), int64)
      intode_diagnostics%cvode_final_order_sum = intode_diagnostics%cvode_final_order_sum + int(max(0, result_state%final_order), int64)
      intode_diagnostics%cvode_max_final_order = max(intode_diagnostics%cvode_max_final_order, &
                                                     int(max(0, result_state%final_order), int64))

      intode_diagnostics%cvode_steps_ctx(idx) = intode_diagnostics%cvode_steps_ctx(idx) + int(max(0, result_state%accepted_steps), int64)
      intode_diagnostics%cvode_rhs_evals_ctx(idx) = intode_diagnostics%cvode_rhs_evals_ctx(idx) + &
         int(max(0, result_state%cvode_rhs_evals), int64)
      intode_diagnostics%cvode_error_test_fails_ctx(idx) = intode_diagnostics%cvode_error_test_fails_ctx(idx) + &
         int(max(0, result_state%cvode_error_test_fails), int64)
      intode_diagnostics%cvode_nonlinear_iters_ctx(idx) = intode_diagnostics%cvode_nonlinear_iters_ctx(idx) + &
         int(max(0, result_state%cvode_nonlinear_iters), int64)
      intode_diagnostics%cvode_nonlinear_conv_fails_ctx(idx) = intode_diagnostics%cvode_nonlinear_conv_fails_ctx(idx) + &
         int(max(0, result_state%cvode_nonlinear_conv_fails), int64)
      intode_diagnostics%cvode_step_solve_fails_ctx(idx) = intode_diagnostics%cvode_step_solve_fails_ctx(idx) + &
         int(max(0, result_state%cvode_step_solve_fails), int64)
   end subroutine record_intode_cvode_result

   subroutine record_intode_odex_result(result_state, intode_diagnostics, context_code)
      implicit none
      type(odex_result), intent(in) :: result_state
      type(intode_diagnostics_context_t), intent(inout) :: intode_diagnostics
      integer, intent(in) :: context_code
      integer :: idx

      if (result_state%cvode_backend_used) then
         intode_diagnostics%last_odex_result_available = .false.
         call odex_result_reset(intode_diagnostics%last_odex_result)
         return
      end if

      idx = normalize_context_code(context_code)
      intode_diagnostics%last_odex_result = result_state
      intode_diagnostics%last_odex_result_available = .true.
      intode_diagnostics%odex_calls = intode_diagnostics%odex_calls + 1_int64
      intode_diagnostics%odex_calls_ctx(idx) = intode_diagnostics%odex_calls_ctx(idx) + 1_int64
      if (result_state%status == odex_status_success) then
         intode_diagnostics%odex_success = intode_diagnostics%odex_success + 1_int64
      else
         intode_diagnostics%odex_failure = intode_diagnostics%odex_failure + 1_int64
      end if

      intode_diagnostics%odex_accepted_steps_sum = intode_diagnostics%odex_accepted_steps_sum + &
         int(max(0, result_state%accepted_steps), int64)
      intode_diagnostics%odex_rejected_steps_sum = intode_diagnostics%odex_rejected_steps_sum + &
         int(max(0, result_state%rejected_steps), int64)
      intode_diagnostics%odex_stability_rejects_sum = intode_diagnostics%odex_stability_rejects_sum + &
         int(max(0, result_state%stability_rejects), int64)
      intode_diagnostics%odex_rhs_evals_sum = intode_diagnostics%odex_rhs_evals_sum + &
         int(max(0, result_state%odex_rhs_evals), int64)
      intode_diagnostics%odex_midpoint_rows_sum = intode_diagnostics%odex_midpoint_rows_sum + &
         int(max(0, result_state%odex_midpoint_rows), int64)
      intode_diagnostics%odex_kplus1_attempts_sum = intode_diagnostics%odex_kplus1_attempts_sum + &
         int(max(0, result_state%odex_kplus1_attempts), int64)
      intode_diagnostics%odex_accept_k_minus_1_sum = intode_diagnostics%odex_accept_k_minus_1_sum + &
         int(max(0, result_state%odex_accept_k_minus_1), int64)
      intode_diagnostics%odex_accept_k_sum = intode_diagnostics%odex_accept_k_sum + &
         int(max(0, result_state%odex_accept_k), int64)
      intode_diagnostics%odex_accept_k_plus_1_sum = intode_diagnostics%odex_accept_k_plus_1_sum + &
         int(max(0, result_state%odex_accept_k_plus_1), int64)
      intode_diagnostics%odex_large_error_rejects_sum = intode_diagnostics%odex_large_error_rejects_sum + &
         int(max(0, result_state%odex_large_error_rejects), int64)
      intode_diagnostics%odex_kplus1_rejects_sum = intode_diagnostics%odex_kplus1_rejects_sum + &
         int(max(0, result_state%odex_kplus1_rejects), int64)
      intode_diagnostics%odex_hairer_policy_steps_sum = intode_diagnostics%odex_hairer_policy_steps_sum + &
         int(max(0, result_state%odex_hairer_policy_steps), int64)
      intode_diagnostics%odex_tltm_policy_steps_sum = intode_diagnostics%odex_tltm_policy_steps_sum + &
         int(max(0, result_state%odex_tltm_policy_steps), int64)
      intode_diagnostics%odex_first_step_entries_sum = intode_diagnostics%odex_first_step_entries_sum + &
         int(max(0, result_state%odex_first_step_entries), int64)
      intode_diagnostics%odex_last_step_entries_sum = intode_diagnostics%odex_last_step_entries_sum + &
         int(max(0, result_state%odex_last_step_entries), int64)
      intode_diagnostics%odex_basic_step_entries_sum = intode_diagnostics%odex_basic_step_entries_sum + &
         int(max(0, result_state%odex_basic_step_entries), int64)
      intode_diagnostics%odex_row_j1_calls_sum = intode_diagnostics%odex_row_j1_calls_sum + &
         int(max(0, result_state%odex_row_j1_calls), int64)
      intode_diagnostics%odex_row_j2_calls_sum = intode_diagnostics%odex_row_j2_calls_sum + &
         int(max(0, result_state%odex_row_j2_calls), int64)
      intode_diagnostics%odex_row_jge3_calls_sum = intode_diagnostics%odex_row_jge3_calls_sum + &
         int(max(0, result_state%odex_row_jge3_calls), int64)
      intode_diagnostics%odex_row_j1_no_error_returns_sum = intode_diagnostics%odex_row_j1_no_error_returns_sum + &
         int(max(0, result_state%odex_row_j1_no_error_returns), int64)
      intode_diagnostics%odex_error_estimates_sum = intode_diagnostics%odex_error_estimates_sum + &
         int(max(0, result_state%odex_error_estimates), int64)
      intode_diagnostics%odex_hairer_scal_estimates_sum = intode_diagnostics%odex_hairer_scal_estimates_sum + &
         int(max(0, result_state%odex_hairer_scal_estimates), int64)
      intode_diagnostics%odex_default_scal_estimates_sum = intode_diagnostics%odex_default_scal_estimates_sum + &
         int(max(0, result_state%odex_default_scal_estimates), int64)
      intode_diagnostics%odex_errold_checks_sum = intode_diagnostics%odex_errold_checks_sum + &
         int(max(0, result_state%odex_errold_checks), int64)
      intode_diagnostics%odex_atov_events_sum = intode_diagnostics%odex_atov_events_sum + &
         int(max(0, result_state%odex_atov_events), int64)
      intode_diagnostics%odex_convergence_rejects_sum = intode_diagnostics%odex_convergence_rejects_sum + &
         int(max(0, result_state%odex_convergence_rejects), int64)
      intode_diagnostics%odex_kplus1_hope_rejects_sum = intode_diagnostics%odex_kplus1_hope_rejects_sum + &
         int(max(0, result_state%odex_kplus1_hope_rejects), int64)
      intode_diagnostics%odex_reject_kc_k_minus_1_sum = intode_diagnostics%odex_reject_kc_k_minus_1_sum + &
         int(max(0, result_state%odex_reject_kc_k_minus_1), int64)
      intode_diagnostics%odex_reject_kc_k_sum = intode_diagnostics%odex_reject_kc_k_sum + &
         int(max(0, result_state%odex_reject_kc_k), int64)
      intode_diagnostics%odex_reject_kc_k_plus_1_sum = intode_diagnostics%odex_reject_kc_k_plus_1_sum + &
         int(max(0, result_state%odex_reject_kc_k_plus_1), int64)
      intode_diagnostics%odex_kopt_accept_updates_sum = intode_diagnostics%odex_kopt_accept_updates_sum + &
         int(max(0, result_state%odex_kopt_accept_updates), int64)
      intode_diagnostics%odex_kopt_demotions_sum = intode_diagnostics%odex_kopt_demotions_sum + &
         int(max(0, result_state%odex_kopt_demotions), int64)
      intode_diagnostics%odex_kopt_keeps_sum = intode_diagnostics%odex_kopt_keeps_sum + &
         int(max(0, result_state%odex_kopt_keeps), int64)
      intode_diagnostics%odex_kopt_promotions_sum = intode_diagnostics%odex_kopt_promotions_sum + &
         int(max(0, result_state%odex_kopt_promotions), int64)
      intode_diagnostics%odex_after_reject_clamps_sum = intode_diagnostics%odex_after_reject_clamps_sum + &
         int(max(0, result_state%odex_after_reject_clamps), int64)
      intode_diagnostics%odex_reject_updates_sum = intode_diagnostics%odex_reject_updates_sum + &
         int(max(0, result_state%odex_reject_updates), int64)
      intode_diagnostics%odex_final_order_sum = intode_diagnostics%odex_final_order_sum + &
         int(max(0, result_state%final_order), int64)
      intode_diagnostics%odex_max_final_order = max(intode_diagnostics%odex_max_final_order, &
                                                    int(max(0, result_state%final_order), int64))

      intode_diagnostics%odex_accepted_steps_ctx(idx) = intode_diagnostics%odex_accepted_steps_ctx(idx) + &
         int(max(0, result_state%accepted_steps), int64)
      intode_diagnostics%odex_rejected_steps_ctx(idx) = intode_diagnostics%odex_rejected_steps_ctx(idx) + &
         int(max(0, result_state%rejected_steps), int64)
      intode_diagnostics%odex_rhs_evals_ctx(idx) = intode_diagnostics%odex_rhs_evals_ctx(idx) + &
         int(max(0, result_state%odex_rhs_evals), int64)
      intode_diagnostics%odex_midpoint_rows_ctx(idx) = intode_diagnostics%odex_midpoint_rows_ctx(idx) + &
         int(max(0, result_state%odex_midpoint_rows), int64)
      intode_diagnostics%odex_kplus1_attempts_ctx(idx) = intode_diagnostics%odex_kplus1_attempts_ctx(idx) + &
         int(max(0, result_state%odex_kplus1_attempts), int64)
   end subroutine record_intode_odex_result

   integer function normalize_context_code(ctx_code) result(ctx_norm)
      implicit none
      integer, intent(in) :: ctx_code

      if (ctx_code >= intode_ctx_flowz .and. ctx_code <= intode_ctx_flow) then
         ctx_norm = ctx_code
      else
         ctx_norm = intode_ctx_unknown
      end if
   end function normalize_context_code

   subroutine record_intode_last_failure(y, t_remaining, reason_code, intode_diagnostics, intode_trace)
      implicit none
      real(dp), intent(in) :: y(:), t_remaining
      integer, intent(in) :: reason_code
      type(intode_diagnostics_context_t), intent(inout) :: intode_diagnostics
      type(intode_runtime_trace_context_t), intent(in) :: intode_trace

      if (.not. intode_diagnostics%capture_failures) return

      intode_diagnostics%last_failure_available = .true.
      intode_diagnostics%last_failure_reason = reason_code
      intode_diagnostics%last_failure_context = intode_trace%current_context
      intode_diagnostics%last_failure_rattle_step = intode_trace%rattle_step
      intode_diagnostics%last_failure_rattle_substep = intode_trace%rattle_substep
      intode_diagnostics%last_failure_stage = intode_trace%stage
      intode_diagnostics%last_failure_newton_iter = intode_trace%newton_iter
      intode_diagnostics%last_failure_quasi_iter = intode_trace%quasi_iter
      intode_diagnostics%last_failure_t = t_remaining
      if (allocated(intode_diagnostics%last_failure_y)) then
         if (size(intode_diagnostics%last_failure_y) /= size(y)) then
            deallocate (intode_diagnostics%last_failure_y)
            allocate (intode_diagnostics%last_failure_y(size(y)))
         end if
      else
         allocate (intode_diagnostics%last_failure_y(size(y)))
      end if
      intode_diagnostics%last_failure_y = y

      if (intode_verbose_logs) then
         if (intode_diagnostics%failure_log_count < intode_failure_log_limit) then
            write (*, '(A,A,A,A,A,I0,A,I0,A,I0,A,I0,A,ES12.4)') "[INTODE][FAIL] context=", &
               trim(context_name(intode_diagnostics%last_failure_context)), &
               " reason=", trim(reason_name(reason_code)), " rattle_step=", intode_diagnostics%last_failure_rattle_step, &
               " substep=", intode_diagnostics%last_failure_rattle_substep, " newton_iter=", &
               intode_diagnostics%last_failure_newton_iter, " quasi_iter=", intode_diagnostics%last_failure_quasi_iter, &
               " t_remaining=", t_remaining
            write (*, '(A,A)') "               stage=", trim(stage_name(intode_diagnostics%last_failure_stage))
         else if (intode_diagnostics%failure_log_count == intode_failure_log_limit) then
            write (*, '(A)') "[INTODE][FAIL] additional failure logs suppressed."
         end if
         intode_diagnostics%failure_log_count = intode_diagnostics%failure_log_count + 1
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

      ! Radau/JFNK rescue was a legacy secondary integrator stack. It is
      ! intentionally disabled; solver-internal assist has been deleted.
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

      ! Radau/JFNK rescue was a legacy secondary integrator stack. It is
      ! intentionally disabled; solver-internal assist has been deleted.
      res = y
      error_flag = .true.
   end subroutine intode_stiff_rescue_context

   subroutine get_intode_solver_assist_policy(enabled, max_uses, fast_hmin_assist)
      implicit none
      logical, intent(out) :: enabled
      integer, intent(out) :: max_uses
      logical, intent(out) :: fast_hmin_assist

      enabled = .false.
      max_uses = 0
      fast_hmin_assist = .false.
   end subroutine get_intode_solver_assist_policy

   subroutine get_intode_solver_assist_policy_code(policy_code, enabled, max_uses, fast_hmin_assist)
      implicit none
      integer, intent(out) :: policy_code
      logical, intent(out) :: enabled
      integer, intent(out) :: max_uses
      logical, intent(out) :: fast_hmin_assist

      policy_code = intode_solver_assist_policy_off
      enabled = .false.
      max_uses = 0
      fast_hmin_assist = .false.
   end subroutine get_intode_solver_assist_policy_code

   subroutine get_intode_final_resort_policy(enabled, max_uses, fast_hmin_bypass)
      implicit none
      logical, intent(out) :: enabled
      integer, intent(out) :: max_uses
      logical, intent(out) :: fast_hmin_bypass

      ! Compatibility alias for older diagnostics/output readers.
      call get_intode_solver_assist_policy(enabled, max_uses, fast_hmin_bypass)
   end subroutine get_intode_final_resort_policy

   subroutine set_intode_rattle_trace(rattle_step, rattle_substep, workspace)
      implicit none
      integer, intent(in) :: rattle_step, rattle_substep
      type(flow_workspace_t), intent(inout), optional :: workspace

      if (present(workspace)) then
         workspace%intode_trace%rattle_step = max(0, rattle_step)
         workspace%intode_trace%rattle_substep = max(0, rattle_substep)
      else
         module_intode_trace%rattle_step = max(0, rattle_step)
         module_intode_trace%rattle_substep = max(0, rattle_substep)
      end if
   end subroutine set_intode_rattle_trace

   subroutine set_intode_stage_trace(stage_code, workspace)
      implicit none
      integer, intent(in) :: stage_code
      type(flow_workspace_t), intent(inout), optional :: workspace
      integer :: normalized_stage

      if (stage_code >= intode_stage_unknown .and. stage_code <= intode_stage_external) then
         normalized_stage = stage_code
      else
         normalized_stage = intode_stage_unknown
      end if
      if (present(workspace)) then
         workspace%intode_trace%stage = normalized_stage
      else
         module_intode_trace%stage = normalized_stage
      end if
   end subroutine set_intode_stage_trace

   subroutine set_intode_residual_role_trace(role_code, workspace)
      implicit none
      integer, intent(in) :: role_code
      type(flow_workspace_t), intent(inout), optional :: workspace
      integer :: normalized_role

      if (role_code >= intode_role_unknown .and. role_code <= intode_role_reverse_replay) then
         normalized_role = role_code
      else
         normalized_role = intode_role_unknown
      end if
      if (present(workspace)) then
         workspace%intode_trace%role = normalized_role
      else
         module_intode_trace%role = normalized_role
      end if
   end subroutine set_intode_residual_role_trace

   subroutine get_intode_residual_role_trace(role_code, workspace)
      implicit none
      integer, intent(out) :: role_code
      type(flow_workspace_t), intent(in), optional :: workspace

      if (present(workspace)) then
         role_code = workspace%intode_trace%role
      else
         role_code = module_intode_trace%role
      end if
   end subroutine get_intode_residual_role_trace

   subroutine set_intode_newton_iter_trace(iter_idx, workspace)
      implicit none
      integer, intent(in) :: iter_idx
      type(flow_workspace_t), intent(inout), optional :: workspace

      if (present(workspace)) then
         workspace%intode_trace%newton_iter = max(0, iter_idx)
      else
         module_intode_trace%newton_iter = max(0, iter_idx)
      end if
   end subroutine set_intode_newton_iter_trace

   subroutine set_intode_quasi_iter_trace(iter_idx, workspace)
      implicit none
      integer, intent(in) :: iter_idx
      type(flow_workspace_t), intent(inout), optional :: workspace

      if (present(workspace)) then
         workspace%intode_trace%quasi_iter = max(0, iter_idx)
      else
         module_intode_trace%quasi_iter = max(0, iter_idx)
      end if
   end subroutine set_intode_quasi_iter_trace

   subroutine clear_intode_runtime_trace(workspace)
      implicit none
      type(flow_workspace_t), intent(inout), optional :: workspace

      if (present(workspace)) then
         call reset_intode_runtime_trace_context(workspace%intode_trace)
      else
         call reset_intode_runtime_trace_context(module_intode_trace)
      end if
   end subroutine clear_intode_runtime_trace

   subroutine reset_intode_runtime_trace_context(intode_trace)
      implicit none
      type(intode_runtime_trace_context_t), intent(inout) :: intode_trace

      intode_trace%rattle_step = 0
      intode_trace%rattle_substep = 0
      intode_trace%stage = intode_stage_unknown
      intode_trace%newton_iter = 0
      intode_trace%quasi_iter = 0
      intode_trace%role = intode_role_unknown
      intode_trace%current_context = intode_ctx_unknown
   end subroutine reset_intode_runtime_trace_context

   subroutine reset_intode_diagnostics_values(intode_diagnostics)
      implicit none
      type(intode_diagnostics_context_t), intent(inout) :: intode_diagnostics

      intode_diagnostics%calls_total = 0
      intode_diagnostics%calls_integrating = 0
      intode_diagnostics%fallback_attempts = 0
      intode_diagnostics%fallback_success = 0
      intode_diagnostics%fallback_failure = 0
      intode_diagnostics%fallback_max_steps = 0
      intode_diagnostics%fallback_invalid = 0
      intode_diagnostics%fallback_h_min = 0
      intode_diagnostics%fallback_attempts_ctx = 0
      intode_diagnostics%fallback_failures_ctx = 0
      intode_diagnostics%cvode_calls = 0_int64
      intode_diagnostics%cvode_success = 0_int64
      intode_diagnostics%cvode_failure = 0_int64
      intode_diagnostics%cvode_steps_sum = 0_int64
      intode_diagnostics%cvode_rhs_evals_sum = 0_int64
      intode_diagnostics%cvode_error_test_fails_sum = 0_int64
      intode_diagnostics%cvode_nonlinear_iters_sum = 0_int64
      intode_diagnostics%cvode_nonlinear_conv_fails_sum = 0_int64
      intode_diagnostics%cvode_step_solve_fails_sum = 0_int64
      intode_diagnostics%cvode_final_order_sum = 0_int64
      intode_diagnostics%cvode_max_final_order = 0_int64
      intode_diagnostics%cvode_calls_ctx = 0_int64
      intode_diagnostics%cvode_steps_ctx = 0_int64
      intode_diagnostics%cvode_rhs_evals_ctx = 0_int64
      intode_diagnostics%cvode_error_test_fails_ctx = 0_int64
      intode_diagnostics%cvode_nonlinear_iters_ctx = 0_int64
      intode_diagnostics%cvode_nonlinear_conv_fails_ctx = 0_int64
      intode_diagnostics%cvode_step_solve_fails_ctx = 0_int64
      intode_diagnostics%odex_calls = 0_int64
      intode_diagnostics%odex_success = 0_int64
      intode_diagnostics%odex_failure = 0_int64
      intode_diagnostics%odex_accepted_steps_sum = 0_int64
      intode_diagnostics%odex_rejected_steps_sum = 0_int64
      intode_diagnostics%odex_stability_rejects_sum = 0_int64
      intode_diagnostics%odex_rhs_evals_sum = 0_int64
      intode_diagnostics%odex_midpoint_rows_sum = 0_int64
      intode_diagnostics%odex_kplus1_attempts_sum = 0_int64
      intode_diagnostics%odex_accept_k_minus_1_sum = 0_int64
      intode_diagnostics%odex_accept_k_sum = 0_int64
      intode_diagnostics%odex_accept_k_plus_1_sum = 0_int64
      intode_diagnostics%odex_large_error_rejects_sum = 0_int64
      intode_diagnostics%odex_kplus1_rejects_sum = 0_int64
      intode_diagnostics%odex_hairer_policy_steps_sum = 0_int64
      intode_diagnostics%odex_tltm_policy_steps_sum = 0_int64
      intode_diagnostics%odex_first_step_entries_sum = 0_int64
      intode_diagnostics%odex_last_step_entries_sum = 0_int64
      intode_diagnostics%odex_basic_step_entries_sum = 0_int64
      intode_diagnostics%odex_row_j1_calls_sum = 0_int64
      intode_diagnostics%odex_row_j2_calls_sum = 0_int64
      intode_diagnostics%odex_row_jge3_calls_sum = 0_int64
      intode_diagnostics%odex_row_j1_no_error_returns_sum = 0_int64
      intode_diagnostics%odex_error_estimates_sum = 0_int64
      intode_diagnostics%odex_hairer_scal_estimates_sum = 0_int64
      intode_diagnostics%odex_default_scal_estimates_sum = 0_int64
      intode_diagnostics%odex_errold_checks_sum = 0_int64
      intode_diagnostics%odex_atov_events_sum = 0_int64
      intode_diagnostics%odex_convergence_rejects_sum = 0_int64
      intode_diagnostics%odex_kplus1_hope_rejects_sum = 0_int64
      intode_diagnostics%odex_reject_kc_k_minus_1_sum = 0_int64
      intode_diagnostics%odex_reject_kc_k_sum = 0_int64
      intode_diagnostics%odex_reject_kc_k_plus_1_sum = 0_int64
      intode_diagnostics%odex_kopt_accept_updates_sum = 0_int64
      intode_diagnostics%odex_kopt_demotions_sum = 0_int64
      intode_diagnostics%odex_kopt_keeps_sum = 0_int64
      intode_diagnostics%odex_kopt_promotions_sum = 0_int64
      intode_diagnostics%odex_after_reject_clamps_sum = 0_int64
      intode_diagnostics%odex_reject_updates_sum = 0_int64
      intode_diagnostics%odex_final_order_sum = 0_int64
      intode_diagnostics%odex_max_final_order = 0_int64
      intode_diagnostics%odex_calls_ctx = 0_int64
      intode_diagnostics%odex_accepted_steps_ctx = 0_int64
      intode_diagnostics%odex_rejected_steps_ctx = 0_int64
      intode_diagnostics%odex_rhs_evals_ctx = 0_int64
      intode_diagnostics%odex_midpoint_rows_ctx = 0_int64
      intode_diagnostics%odex_kplus1_attempts_ctx = 0_int64
      intode_diagnostics%last_odex_result_available = .false.
      call odex_result_reset(intode_diagnostics%last_odex_result)
      intode_diagnostics%capture_failures = .true.
      intode_diagnostics%last_failure_available = .false.
      intode_diagnostics%last_failure_reason = intode_reason_none
      intode_diagnostics%last_failure_context = intode_ctx_unknown
      intode_diagnostics%last_failure_rattle_step = 0
      intode_diagnostics%last_failure_rattle_substep = 0
      intode_diagnostics%last_failure_stage = intode_stage_unknown
      intode_diagnostics%last_failure_newton_iter = 0
      intode_diagnostics%last_failure_quasi_iter = 0
      intode_diagnostics%failure_log_count = 0
      intode_diagnostics%last_failure_t = 0.0_dp
      if (allocated(intode_diagnostics%last_failure_y)) deallocate (intode_diagnostics%last_failure_y)
   end subroutine reset_intode_diagnostics_values

   subroutine reset_intode_fallback_stats(intode_diagnostics)
      implicit none
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      call reset_intode_diagnostics_values(active_diagnostics)
      if (.not. present(intode_diagnostics)) call reset_intode_runtime_trace_context(module_intode_trace)
   end subroutine reset_intode_fallback_stats

   subroutine release_intode_diagnostics_context(intode_diagnostics)
      implicit none
      type(intode_diagnostics_context_t), intent(inout) :: intode_diagnostics

      call reset_intode_diagnostics_values(intode_diagnostics)
   end subroutine release_intode_diagnostics_context

   subroutine get_intode_fallback_stats(calls_total, calls_integrating, fallback_attempts, fallback_success, fallback_failure, &
                                         fallback_max_steps, fallback_invalid, fallback_h_min, intode_diagnostics)
      implicit none
      integer, intent(out) :: calls_total, calls_integrating
      integer, intent(out) :: fallback_attempts, fallback_success, fallback_failure
      integer, intent(out) :: fallback_max_steps, fallback_invalid, fallback_h_min
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      calls_total = active_diagnostics%calls_total
      calls_integrating = active_diagnostics%calls_integrating
      fallback_attempts = active_diagnostics%fallback_attempts
      fallback_success = active_diagnostics%fallback_success
      fallback_failure = active_diagnostics%fallback_failure
      fallback_max_steps = active_diagnostics%fallback_max_steps
      fallback_invalid = active_diagnostics%fallback_invalid
      fallback_h_min = active_diagnostics%fallback_h_min
   end subroutine get_intode_fallback_stats

   subroutine get_intode_cvode_stats(calls, success, failure, steps_sum, rhs_evals_sum, error_test_fails_sum, &
                                     nonlinear_iters_sum, nonlinear_conv_fails_sum, step_solve_fails_sum, &
                                     final_order_sum, max_final_order, intode_diagnostics)
      implicit none
      integer(int64), intent(out) :: calls, success, failure, steps_sum, rhs_evals_sum
      integer(int64), intent(out) :: error_test_fails_sum, nonlinear_iters_sum, nonlinear_conv_fails_sum
      integer(int64), intent(out) :: step_solve_fails_sum, final_order_sum, max_final_order
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      calls = active_diagnostics%cvode_calls
      success = active_diagnostics%cvode_success
      failure = active_diagnostics%cvode_failure
      steps_sum = active_diagnostics%cvode_steps_sum
      rhs_evals_sum = active_diagnostics%cvode_rhs_evals_sum
      error_test_fails_sum = active_diagnostics%cvode_error_test_fails_sum
      nonlinear_iters_sum = active_diagnostics%cvode_nonlinear_iters_sum
      nonlinear_conv_fails_sum = active_diagnostics%cvode_nonlinear_conv_fails_sum
      step_solve_fails_sum = active_diagnostics%cvode_step_solve_fails_sum
      final_order_sum = active_diagnostics%cvode_final_order_sum
      max_final_order = active_diagnostics%cvode_max_final_order
   end subroutine get_intode_cvode_stats

   subroutine get_intode_odex_stats(calls, success, failure, accepted_steps_sum, rejected_steps_sum, stability_rejects_sum, &
                                    rhs_evals_sum, midpoint_rows_sum, kplus1_attempts_sum, accept_k_minus_1_sum, &
                                    accept_k_sum, accept_k_plus_1_sum, large_error_rejects_sum, kplus1_rejects_sum, &
                                    hairer_policy_steps_sum, tltm_policy_steps_sum, first_step_entries_sum, &
                                    last_step_entries_sum, basic_step_entries_sum, row_j1_calls_sum, row_j2_calls_sum, &
                                    row_jge3_calls_sum, row_j1_no_error_returns_sum, error_estimates_sum, &
                                    hairer_scal_estimates_sum, default_scal_estimates_sum, errold_checks_sum, &
                                    atov_events_sum, convergence_rejects_sum, kplus1_hope_rejects_sum, &
                                    reject_kc_k_minus_1_sum, reject_kc_k_sum, reject_kc_k_plus_1_sum, &
                                    kopt_accept_updates_sum, kopt_demotions_sum, kopt_keeps_sum, kopt_promotions_sum, &
                                    after_reject_clamps_sum, reject_updates_sum, &
                                    final_order_sum, max_final_order, intode_diagnostics)
      implicit none
      integer(int64), intent(out) :: calls, success, failure, accepted_steps_sum, rejected_steps_sum
      integer(int64), intent(out) :: stability_rejects_sum, rhs_evals_sum, midpoint_rows_sum, kplus1_attempts_sum
      integer(int64), intent(out) :: accept_k_minus_1_sum, accept_k_sum, accept_k_plus_1_sum
      integer(int64), intent(out) :: large_error_rejects_sum, kplus1_rejects_sum
      integer(int64), intent(out) :: hairer_policy_steps_sum, tltm_policy_steps_sum
      integer(int64), intent(out) :: first_step_entries_sum, last_step_entries_sum, basic_step_entries_sum
      integer(int64), intent(out) :: row_j1_calls_sum, row_j2_calls_sum, row_jge3_calls_sum
      integer(int64), intent(out) :: row_j1_no_error_returns_sum, error_estimates_sum
      integer(int64), intent(out) :: hairer_scal_estimates_sum, default_scal_estimates_sum
      integer(int64), intent(out) :: errold_checks_sum, atov_events_sum
      integer(int64), intent(out) :: convergence_rejects_sum, kplus1_hope_rejects_sum
      integer(int64), intent(out) :: reject_kc_k_minus_1_sum, reject_kc_k_sum, reject_kc_k_plus_1_sum
      integer(int64), intent(out) :: kopt_accept_updates_sum, kopt_demotions_sum, kopt_keeps_sum, kopt_promotions_sum
      integer(int64), intent(out) :: after_reject_clamps_sum, reject_updates_sum
      integer(int64), intent(out) :: final_order_sum, max_final_order
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      calls = active_diagnostics%odex_calls
      success = active_diagnostics%odex_success
      failure = active_diagnostics%odex_failure
      accepted_steps_sum = active_diagnostics%odex_accepted_steps_sum
      rejected_steps_sum = active_diagnostics%odex_rejected_steps_sum
      stability_rejects_sum = active_diagnostics%odex_stability_rejects_sum
      rhs_evals_sum = active_diagnostics%odex_rhs_evals_sum
      midpoint_rows_sum = active_diagnostics%odex_midpoint_rows_sum
      kplus1_attempts_sum = active_diagnostics%odex_kplus1_attempts_sum
      accept_k_minus_1_sum = active_diagnostics%odex_accept_k_minus_1_sum
      accept_k_sum = active_diagnostics%odex_accept_k_sum
      accept_k_plus_1_sum = active_diagnostics%odex_accept_k_plus_1_sum
      large_error_rejects_sum = active_diagnostics%odex_large_error_rejects_sum
      kplus1_rejects_sum = active_diagnostics%odex_kplus1_rejects_sum
      hairer_policy_steps_sum = active_diagnostics%odex_hairer_policy_steps_sum
      tltm_policy_steps_sum = active_diagnostics%odex_tltm_policy_steps_sum
      first_step_entries_sum = active_diagnostics%odex_first_step_entries_sum
      last_step_entries_sum = active_diagnostics%odex_last_step_entries_sum
      basic_step_entries_sum = active_diagnostics%odex_basic_step_entries_sum
      row_j1_calls_sum = active_diagnostics%odex_row_j1_calls_sum
      row_j2_calls_sum = active_diagnostics%odex_row_j2_calls_sum
      row_jge3_calls_sum = active_diagnostics%odex_row_jge3_calls_sum
      row_j1_no_error_returns_sum = active_diagnostics%odex_row_j1_no_error_returns_sum
      error_estimates_sum = active_diagnostics%odex_error_estimates_sum
      hairer_scal_estimates_sum = active_diagnostics%odex_hairer_scal_estimates_sum
      default_scal_estimates_sum = active_diagnostics%odex_default_scal_estimates_sum
      errold_checks_sum = active_diagnostics%odex_errold_checks_sum
      atov_events_sum = active_diagnostics%odex_atov_events_sum
      convergence_rejects_sum = active_diagnostics%odex_convergence_rejects_sum
      kplus1_hope_rejects_sum = active_diagnostics%odex_kplus1_hope_rejects_sum
      reject_kc_k_minus_1_sum = active_diagnostics%odex_reject_kc_k_minus_1_sum
      reject_kc_k_sum = active_diagnostics%odex_reject_kc_k_sum
      reject_kc_k_plus_1_sum = active_diagnostics%odex_reject_kc_k_plus_1_sum
      kopt_accept_updates_sum = active_diagnostics%odex_kopt_accept_updates_sum
      kopt_demotions_sum = active_diagnostics%odex_kopt_demotions_sum
      kopt_keeps_sum = active_diagnostics%odex_kopt_keeps_sum
      kopt_promotions_sum = active_diagnostics%odex_kopt_promotions_sum
      after_reject_clamps_sum = active_diagnostics%odex_after_reject_clamps_sum
      reject_updates_sum = active_diagnostics%odex_reject_updates_sum
      final_order_sum = active_diagnostics%odex_final_order_sum
      max_final_order = active_diagnostics%odex_max_final_order
   end subroutine get_intode_odex_stats

   subroutine get_intode_cvode_context_stats(context_code, calls, steps_sum, rhs_evals_sum, error_test_fails_sum, &
                                             nonlinear_iters_sum, nonlinear_conv_fails_sum, step_solve_fails_sum, intode_diagnostics)
      implicit none
      integer, intent(in) :: context_code
      integer(int64), intent(out) :: calls, steps_sum, rhs_evals_sum, error_test_fails_sum
      integer(int64), intent(out) :: nonlinear_iters_sum, nonlinear_conv_fails_sum, step_solve_fails_sum
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics
      integer :: idx

      idx = normalize_context_code(context_code)
      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      calls = active_diagnostics%cvode_calls_ctx(idx)
      steps_sum = active_diagnostics%cvode_steps_ctx(idx)
      rhs_evals_sum = active_diagnostics%cvode_rhs_evals_ctx(idx)
      error_test_fails_sum = active_diagnostics%cvode_error_test_fails_ctx(idx)
      nonlinear_iters_sum = active_diagnostics%cvode_nonlinear_iters_ctx(idx)
      nonlinear_conv_fails_sum = active_diagnostics%cvode_nonlinear_conv_fails_ctx(idx)
      step_solve_fails_sum = active_diagnostics%cvode_step_solve_fails_ctx(idx)
   end subroutine get_intode_cvode_context_stats

   subroutine get_intode_odex_context_stats(context_code, calls, accepted_steps_sum, rejected_steps_sum, rhs_evals_sum, &
                                            midpoint_rows_sum, kplus1_attempts_sum, intode_diagnostics)
      implicit none
      integer, intent(in) :: context_code
      integer(int64), intent(out) :: calls, accepted_steps_sum, rejected_steps_sum, rhs_evals_sum
      integer(int64), intent(out) :: midpoint_rows_sum, kplus1_attempts_sum
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics
      integer :: idx

      idx = normalize_context_code(context_code)
      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      calls = active_diagnostics%odex_calls_ctx(idx)
      accepted_steps_sum = active_diagnostics%odex_accepted_steps_ctx(idx)
      rejected_steps_sum = active_diagnostics%odex_rejected_steps_ctx(idx)
      rhs_evals_sum = active_diagnostics%odex_rhs_evals_ctx(idx)
      midpoint_rows_sum = active_diagnostics%odex_midpoint_rows_ctx(idx)
      kplus1_attempts_sum = active_diagnostics%odex_kplus1_attempts_ctx(idx)
   end subroutine get_intode_odex_context_stats

   subroutine get_intode_fallback_context_stats(attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                                fail_flowz, fail_flowzr, fail_flow, fail_unknown, intode_diagnostics)
      implicit none
      integer, intent(out) :: attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown
      integer, intent(out) :: fail_flowz, fail_flowzr, fail_flow, fail_unknown
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      attempt_flowz = active_diagnostics%fallback_attempts_ctx(intode_ctx_flowz)
      attempt_flowzr = active_diagnostics%fallback_attempts_ctx(intode_ctx_flowzr)
      attempt_flow = active_diagnostics%fallback_attempts_ctx(intode_ctx_flow)
      attempt_unknown = active_diagnostics%fallback_attempts_ctx(intode_ctx_unknown)
      fail_flowz = active_diagnostics%fallback_failures_ctx(intode_ctx_flowz)
      fail_flowzr = active_diagnostics%fallback_failures_ctx(intode_ctx_flowzr)
      fail_flow = active_diagnostics%fallback_failures_ctx(intode_ctx_flow)
      fail_unknown = active_diagnostics%fallback_failures_ctx(intode_ctx_unknown)
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
      success_final_resort = 0
      fail_radau_adaptive_robust = 0
      fail_radau_fixed_tol = 0
      fail_radau_chunked = 0
      fail_final_resort = 0
   end subroutine get_intode_rescue_stats

   subroutine get_intode_radau_diag_stats(adapt_newton_fail, adapt_linear_fail, adapt_error_reject, adapt_hmin_hit)
      implicit none
      integer, intent(out) :: adapt_newton_fail, adapt_linear_fail, adapt_error_reject, adapt_hmin_hit

      adapt_newton_fail = 0
      adapt_linear_fail = 0
      adapt_error_reject = 0
      adapt_hmin_hit = 0
   end subroutine get_intode_radau_diag_stats

   subroutine get_intode_last_failure_meta(available, reason_code, context_code, state_dim, t_remaining, intode_diagnostics)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: reason_code, context_code, state_dim
      real(dp), intent(out) :: t_remaining
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      available = active_diagnostics%last_failure_available .and. allocated(active_diagnostics%last_failure_y)
      reason_code = active_diagnostics%last_failure_reason
      context_code = active_diagnostics%last_failure_context
      t_remaining = active_diagnostics%last_failure_t
      if (allocated(active_diagnostics%last_failure_y)) then
         state_dim = size(active_diagnostics%last_failure_y)
      else
         state_dim = 0
      end if
   end subroutine get_intode_last_failure_meta

   subroutine get_intode_last_failure_trace(available, rattle_step, rattle_substep, stage_code, newton_iter, quasi_iter, &
                                            intode_diagnostics)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: rattle_step, rattle_substep, stage_code, newton_iter, quasi_iter
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      available = active_diagnostics%last_failure_available
      rattle_step = active_diagnostics%last_failure_rattle_step
      rattle_substep = active_diagnostics%last_failure_rattle_substep
      stage_code = active_diagnostics%last_failure_stage
      newton_iter = active_diagnostics%last_failure_newton_iter
      quasi_iter = active_diagnostics%last_failure_quasi_iter
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

   function complex_vector_has_invalid(values) result(has_invalid)
      implicit none
      complex(dp), intent(in) :: values(:)
      logical :: has_invalid
      integer :: idx

      has_invalid = .false.
      do idx = 1, size(values)
         if (.not. ieee_is_finite(real(values(idx), dp)) .or. .not. ieee_is_finite(aimag(values(idx)))) then
            has_invalid = .true.
            return
         end if
      end do
   end function complex_vector_has_invalid

   logical function flow_x_z_shape_ok(x, z) result(ok)
      implicit none
      real(dp), intent(in) :: x(:)
      complex(dp), intent(in) :: z(:)

      ok = (size(z) > 0) .and. (size(x) == size(z) + 1)
   end function flow_x_z_shape_ok

   logical function flow_state_z_shape_ok(x_state, z) result(ok)
      implicit none
      real(dp), intent(in) :: x_state(:)
      complex(dp), intent(in) :: z(:)

      ok = (size(z) > 0) .and. (size(x_state) == size(z))
   end function flow_state_z_shape_ok

   logical function flow_x_z_j_shape_ok(x, z, j) result(ok)
      implicit none
      real(dp), intent(in) :: x(:)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: j(:, :)

      ok = flow_x_z_shape_ok(x, z) .and. size(j, 1) == size(z) .and. size(j, 2) == size(z)
   end function flow_x_z_j_shape_ok

   logical function flow_state_z_j_shape_ok(x_state, z, j) result(ok)
      implicit none
      real(dp), intent(in) :: x_state(:)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: j(:, :)

      ok = flow_state_z_shape_ok(x_state, z) .and. size(j, 1) == size(z) .and. size(j, 2) == size(z)
   end function flow_state_z_j_shape_ok

   subroutine set_complex_identity(mat)
      implicit none
      complex(dp), intent(out) :: mat(:, :)
      integer :: idx, n

      mat = cmplx(0.0_dp, 0.0_dp, dp)
      n = min(size(mat, 1), size(mat, 2))
      do idx = 1, n
         mat(idx, idx) = cmplx(1.0_dp, 0.0_dp, dp)
      end do
   end subroutine set_complex_identity

   subroutine flowz(x, z, error, status, workspace, intode_diagnostics)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      type(flow_workspace_t) :: local_workspace

      if (present(workspace)) then
         call flowz_with_workspace(x, z, error, status, workspace, intode_diagnostics)
      else
         call flowz_with_workspace(x, z, error, status, local_workspace, intode_diagnostics)
      end if
   end subroutine flowz

   subroutine flowz_at(flow_time, x_state, z, error, status, workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time
      real(dp), intent(in) :: x_state(:)
      complex(dp), intent(inout) :: z(:)
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      type(flow_workspace_t) :: local_workspace

      if (present(workspace)) then
         call flowz_at_with_workspace(flow_time, x_state, z, error, status, workspace, intode_diagnostics)
      else
         call flowz_at_with_workspace(flow_time, x_state, z, error, status, local_workspace, intode_diagnostics)
      end if
   end subroutine flowz_at

   subroutine flowzr(x, z, error, status, workspace, intode_diagnostics)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      type(flow_workspace_t) :: local_workspace

      if (present(workspace)) then
         call flowzr_with_workspace(x, z, error, status, workspace, intode_diagnostics)
      else
         call flowzr_with_workspace(x, z, error, status, local_workspace, intode_diagnostics)
      end if
   end subroutine flowzr

   subroutine flowzr_at(flow_time, z, error, status, workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time
      complex(dp), intent(inout) :: z(:)
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      type(flow_workspace_t) :: local_workspace

      if (present(workspace)) then
         call flowzr_at_with_workspace(flow_time, z, error, status, workspace, intode_diagnostics)
      else
         call flowzr_at_with_workspace(flow_time, z, error, status, local_workspace, intode_diagnostics)
      end if
   end subroutine flowzr_at

   subroutine flow(x, z, j, error, status, workspace, intode_diagnostics)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      complex(dp), dimension(:, :), intent(inout)::j
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      type(flow_workspace_t) :: local_workspace

      if (present(workspace)) then
         call flow_with_workspace(x, z, j, error, status, workspace, intode_diagnostics)
      else
         call flow_with_workspace(x, z, j, error, status, local_workspace, intode_diagnostics)
      end if
   end subroutine flow

   subroutine flow_at(flow_time, x_state, z, j, error, status, workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time
      real(dp), intent(in) :: x_state(:)
      complex(dp), intent(inout) :: z(:)
      complex(dp), dimension(:, :), intent(inout) :: j
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout), optional :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      type(flow_workspace_t) :: local_workspace

      if (present(workspace)) then
         call flow_at_with_workspace(flow_time, x_state, z, j, error, status, workspace, intode_diagnostics)
      else
         call flow_at_with_workspace(flow_time, x_state, z, j, error, status, local_workspace, intode_diagnostics)
      end if
   end subroutine flow_at

   subroutine flowz_with_workspace(x, z, error, status, workspace, intode_diagnostics)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      call set_intode_status(status, intode_status_unknown)
      if (.not. flow_x_z_shape_ok(x, z)) then
         error = .true.
         call set_intode_status(status, intode_status_failure_invalid)
         return
      end if
      call flowz_at_with_workspace(x(1), x(2:), z, error, status, workspace, intode_diagnostics)
   end subroutine flowz_with_workspace

   subroutine flowz_at_with_workspace(flow_time, x_state, z, error, status, workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time
      real(dp), intent(in) :: x_state(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(intode_diagnostics_context_t), pointer :: active_diagnostics
      integer::n, n_complex
      integer :: flow_status_local
      real(dp)::t1
      real(dp) :: t_prof

      call perf_tic(t_prof)
      call set_intode_status(status, intode_status_unknown)
      if (.not. flow_state_z_shape_ok(x_state, z)) then
         error = .true.
         call set_intode_status(status, intode_status_failure_invalid)
         call perf_toc(PERF_FLOWZ, t_prof)
         return
      end if
      n = size(z)*2
      n_complex = size(z)
      t1 = flow_time
      error = .false.
      z = cmplx(x_state, 0.0_dp, dp)
      if ((.not. ieee_is_finite(flow_time)) .or. vector_has_invalid(x_state)) then
         error = .true.
         call set_intode_status(status, intode_status_failure_invalid)
         call perf_toc(PERF_FLOWZ, t_prof)
         return
      end if
      call maybe_capture_flowz_input_at(flow_time, x_state, workspace%intode_trace)

      call ensure_real_workspace(workspace%flow_vec_y, n)
      call ensure_real_workspace(workspace%flow_vec_yf, n)
      call ensure_complex_workspace(workspace%flow_vec_z, n_complex)
      call ensure_complex_workspace(workspace%flow_vec_ds, n_complex)

      workspace%flow_vec_y(1:n:2) = x_state
      workspace%flow_vec_y(2:n:2) = 0.0_dp
      workspace%intode_trace%current_context = intode_ctx_flowz
      workspace%flow_vec_rhs_scale = 1.0_dp
      call intode_with_context(rhs_flow_vec_context, workspace%flow_vec_y(1:n), t1, workspace%flow_vec_yf(1:n), error, &
                               flow_status_local, workspace, intode_diagnostics)
      call resolve_intode_diagnostics_context(intode_diagnostics, active_diagnostics)
      if (active_diagnostics%last_odex_result_available) then
         call maybe_capture_flowz_cost_input_at(flow_time, x_state, workspace%intode_trace, &
                                                active_diagnostics%last_odex_result, flow_status_local, error)
      end if
      workspace%intode_trace%current_context = intode_ctx_unknown
      call set_intode_status(status, flow_status_local)
      if (error) then
         call perf_toc(PERF_FLOWZ, t_prof)
         return
      end if
      call real_to_complex(workspace%flow_vec_yf(1:n), z)
      call perf_toc(PERF_FLOWZ, t_prof)
   end subroutine flowz_at_with_workspace

   subroutine flowzr_with_workspace(x, z, error, status, workspace, intode_diagnostics)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      call set_intode_status(status, intode_status_unknown)
      if (.not. flow_x_z_shape_ok(x, z)) then
         error = .true.
         call set_intode_status(status, intode_status_failure_invalid)
         return
      end if
      call flowzr_at_with_workspace(x(1), z, error, status, workspace, intode_diagnostics)
   end subroutine flowzr_with_workspace

   subroutine flowzr_at_with_workspace(flow_time, z, error, status, workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      integer::n, n_complex
      integer :: flow_status_local
      real(dp)::t1
      real(dp) :: t_prof

      call perf_tic(t_prof)
      call set_intode_status(status, intode_status_unknown)
      if (size(z) <= 0) then
         error = .true.
         call set_intode_status(status, intode_status_failure_invalid)
         call perf_toc(PERF_FLOWZR, t_prof)
         return
      end if
      n = size(z)*2
      n_complex = size(z)
      t1 = flow_time
      error = .false.
      if ((.not. ieee_is_finite(flow_time)) .or. complex_vector_has_invalid(z)) then
         error = .true.
         call set_intode_status(status, intode_status_failure_invalid)
         call perf_toc(PERF_FLOWZR, t_prof)
         return
      end if

      call ensure_real_workspace(workspace%flow_vec_y, n)
      call ensure_real_workspace(workspace%flow_vec_yf, n)
      call ensure_complex_workspace(workspace%flow_vec_z, n_complex)
      call ensure_complex_workspace(workspace%flow_vec_ds, n_complex)

      call complex_to_real(z, workspace%flow_vec_y(1:n))
      workspace%intode_trace%current_context = intode_ctx_flowzr
      workspace%flow_vec_rhs_scale = -1.0_dp
      call intode_with_context(rhs_flow_vec_context, workspace%flow_vec_y(1:n), t1, workspace%flow_vec_yf(1:n), error, &
                               flow_status_local, workspace, intode_diagnostics)
      workspace%intode_trace%current_context = intode_ctx_unknown
      workspace%flow_vec_rhs_scale = 1.0_dp
      call set_intode_status(status, flow_status_local)
      if (error) then
         call perf_toc(PERF_FLOWZR, t_prof)
         return
      end if
      call real_to_complex(workspace%flow_vec_yf(1:n), z)
      call perf_toc(PERF_FLOWZR, t_prof)
   end subroutine flowzr_at_with_workspace

   subroutine flow_with_workspace(x, z, j, error, status, workspace, intode_diagnostics)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      complex(dp), dimension(:, :), intent(inout)::j
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      call set_intode_status(status, intode_status_unknown)
      if (.not. flow_x_z_j_shape_ok(x, z, j)) then
         error = .true.
         call set_intode_status(status, intode_status_failure_invalid)
         return
      end if
      call flow_at_with_workspace(x(1), x(2:), z, j, error, status, workspace, intode_diagnostics)
   end subroutine flow_with_workspace

   subroutine flow_at_with_workspace(flow_time, x_state, z, j, error, status, workspace, intode_diagnostics)
      real(dp), intent(in) :: flow_time
      real(dp), intent(in) :: x_state(:)
      complex(dp), intent(inout)::z(:)
      complex(dp), dimension(:, :), intent(inout)::j
      logical, intent(out)::error
      integer, intent(out), optional :: status
      type(flow_workspace_t), intent(inout) :: workspace
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      integer::n, m, n_complex, n_jac
      integer :: total_n
      integer :: flow_status_local
      real(dp)::t1
      real(dp) :: t_prof

      call perf_tic(t_prof)
      call set_intode_status(status, intode_status_unknown)
      if (.not. flow_state_z_j_shape_ok(x_state, z, j)) then
         error = .true.
         call set_intode_status(status, intode_status_failure_invalid)
         call perf_toc(PERF_FLOW, t_prof)
         return
      end if
      n = size(z)*2
      n_complex = size(z)
      n_jac = size(j, 1)
      m = size(j, 1)*size(j, 2)*2
      total_n = n + m
      t1 = flow_time
      error = .false.
      z = cmplx(x_state, 0.0_dp, dp)
      call set_complex_identity(j)
      if ((.not. ieee_is_finite(flow_time)) .or. vector_has_invalid(x_state)) then
         error = .true.
         call set_intode_status(status, intode_status_failure_invalid)
         call perf_toc(PERF_FLOW, t_prof)
         return
      end if

      call ensure_real_workspace(workspace%flow_jac_y, total_n)
      call ensure_real_workspace(workspace%flow_jac_yf, total_n)
      call ensure_complex_workspace(workspace%flow_jac_z, n_complex)
      call ensure_complex_workspace(workspace%flow_jac_ds, n_complex)
      call ensure_complex_workspace_mat(workspace%flow_jac_j, n_jac, n_jac)
      call ensure_complex_workspace_mat(workspace%flow_jac_jprod, n_jac, n_jac)

      workspace%flow_jac_y(1:n:2) = x_state
      workspace%flow_jac_y(2:n:2) = 0.0_dp
      call fill_identity_real_map(workspace%flow_jac_y(n + 1:total_n), n_jac)
      workspace%intode_trace%current_context = intode_ctx_flow
      call intode_with_context(rhs_flow_jac_context, workspace%flow_jac_y(1:total_n), t1, workspace%flow_jac_yf(1:total_n), error, &
                               flow_status_local, workspace, intode_diagnostics)
      workspace%intode_trace%current_context = intode_ctx_unknown
      call set_intode_status(status, flow_status_local)
      if (error) then
         call perf_toc(PERF_FLOW, t_prof)
         return
      end if
      call real_to_complex(workspace%flow_jac_yf(1:n), z)
      call map_to_complex(workspace%flow_jac_yf(n + 1:total_n), j)
      call perf_toc(PERF_FLOW, t_prof)
   end subroutine flow_at_with_workspace

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
      call reset_intode_runtime_trace_context(workspace%intode_trace)
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

module hmc_integrator_core
   use, intrinsic :: iso_fortran_env, only: int64
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use runtime_env_mod, only: read_string_env
   use solve_flow, only: flow, flowz, flowzr, flow_workspace_t, set_intode_stage_trace, set_intode_newton_iter_trace, set_intode_quasi_iter_trace, &
                         intode_stage_newton, intode_stage_quasi, intode_stage_rattle_flow, intode_stage_external, &
                         intode_status_success_stiff_rescue, intode_status_success_solver_assist, intode_status_failure_max_steps, &
                         intode_status_failure_invalid, intode_status_failure_h_min, &
                         get_intode_fallback_context_stats, get_intode_rescue_stats, intode_status_is_strict_success
   use param_mod, only: cttol, quasi_fallback_enabled
   use utils, only: dp, complex_to_real
   use model, only: ds
   use hmc_kernels, only: calculate_dV, decompose2
   use hmc_constraints, only: solve_constraint_newton
   use hmc_state_buffers, only: rattle_step_workspace_t, ensure_rattle_step_workspace, release_rattle_step_workspace
   use quasi_newton_solver_mod, only: solve_constraint_quasi_newton, evaluate_constraint_residual, &
                                      get_quasi_newton_last_trace_r2c, get_quasi_newton_last_trace_stats, qn_context_t, &
                                      qn_diagnostics_context_t, qn_policy_context_t
   use constraint_solver_stats_mod, only: record_constraint_solver_newton_success, &
                                           record_constraint_solver_quasi_success, &
                                           record_constraint_solver_fail, &
                                           record_constraint_near_fail_candidate, record_constraint_far_fail, &
                                           record_constraint_near_rescue_attempt, &
                                           record_constraint_near_rescue_success, &
                                           record_constraint_near_unusable, &
                                           record_constraint_solver_far_investment, &
                                           record_constraint_solver_quasi_class, &
                                           record_constraint_solver_far_route, &
                                           record_constraint_solver_quasi_stage_attempt, &
                                           record_constraint_solver_quasi_stage_success, &
                                           record_constraint_solver_reverse_gate, &
                                           push_constraint_solver_stats_suppression, &
                                           pop_constraint_solver_stats_suppression, &
                                           constraint_quasi_stage_probe, constraint_quasi_stage_full, &
                                           constraint_quasi_class_local, constraint_quasi_class_mid, &
                                           constraint_quasi_class_global, &
                                           constraint_quasi_far_route_skip, &
                                           constraint_quasi_far_route_light, &
                                           constraint_quasi_far_route_anchor
   use perf_profile, only: perf_tic, perf_toc, PERF_RATTLE_STEP_CORE
   implicit none

   integer, parameter :: quasi_case_far = 0
   integer, parameter :: quasi_case_near = 1
   integer, parameter :: quasi_case_mid = 2

   integer, parameter :: hmc_step_status_success = 0
   integer, parameter :: hmc_step_status_output_size_mismatch = 1
   integer, parameter :: hmc_step_status_momentum_size_mismatch = 2
   integer, parameter :: hmc_step_status_initial_force_failed = 3
   integer, parameter :: hmc_step_status_constraint_failed = 4
   integer, parameter :: hmc_step_status_final_flow_failed = 5
   integer, parameter :: hmc_step_status_final_force_failed = 6
   integer, parameter :: hmc_step_status_final_projection_failed = 7
   integer, parameter :: hmc_step_status_reverse_gate_rejected = 8
   integer, parameter :: hmc_step_status_final_flow_max_steps = 9
   integer, parameter :: hmc_step_status_final_flow_invalid = 10
   integer, parameter :: hmc_step_status_final_flow_h_min = 11
   integer, parameter :: hmc_step_status_final_flow_non_strict_success = 12
   integer, parameter :: hmc_step_status_unknown = -1

   integer, parameter :: s1_probe_max_iter_default = 28
   integer, parameter :: s1_near_full_max_iter_default = 100
   integer, parameter :: s1_non_near_cheap_full_max_iter_default = 36
   real(dp), parameter :: qn_reverse_gate_tol_default = 1.0e-8_dp

   type :: hmc_policy_context_t
      logical :: s1_fallback_policy_loaded = .false.
      integer :: s1_probe_max_iter = s1_probe_max_iter_default
      integer :: s1_near_full_max_iter = s1_near_full_max_iter_default
      integer :: s1_non_near_cheap_full_max_iter = s1_non_near_cheap_full_max_iter_default
      logical :: s1_near_rescue_enabled = .false.
      logical :: s1_nonnear_rescue_enabled = .false.
      logical :: qn_reverse_gate_enabled = .false.
      real(dp) :: qn_reverse_gate_tol = qn_reverse_gate_tol_default
      real(dp) :: qn_quasi_tol_override = -1.0_dp
   end type hmc_policy_context_t

   type :: hmc_replay_runtime_context_t
      logical :: qn_reverse_gate_active = .false.
   end type hmc_replay_runtime_context_t

   type :: hmc_replay_diagnostics_context_t
      integer(int64) :: reverse_gate_replay_status_success = 0_int64
      integer(int64) :: reverse_gate_replay_status_output_size_mismatch = 0_int64
      integer(int64) :: reverse_gate_replay_status_momentum_size_mismatch = 0_int64
      integer(int64) :: reverse_gate_replay_status_initial_force_failed = 0_int64
      integer(int64) :: reverse_gate_replay_status_constraint_failed = 0_int64
      integer(int64) :: reverse_gate_replay_status_final_flow_failed = 0_int64
      integer(int64) :: reverse_gate_replay_status_final_force_failed = 0_int64
      integer(int64) :: reverse_gate_replay_status_final_projection_failed = 0_int64
      integer(int64) :: reverse_gate_replay_status_reverse_gate_rejected = 0_int64
      integer(int64) :: reverse_gate_replay_status_final_flow_max_steps = 0_int64
      integer(int64) :: reverse_gate_replay_status_final_flow_invalid = 0_int64
      integer(int64) :: reverse_gate_replay_status_final_flow_h_min = 0_int64
      integer(int64) :: reverse_gate_replay_status_final_flow_non_strict_success = 0_int64
      integer(int64) :: reverse_gate_replay_status_unknown = 0_int64
   end type hmc_replay_diagnostics_context_t

   type(hmc_policy_context_t), save, target :: module_hmc_policy_context
   type(hmc_replay_runtime_context_t), save, target :: module_hmc_replay_runtime_context
   type(hmc_replay_diagnostics_context_t), save, target :: module_hmc_replay_diagnostics_context

contains

   subroutine reset_reverse_gate_replay_status_counts(hmc_replay_diagnostics)
      implicit none
      type(hmc_replay_diagnostics_context_t), intent(inout), optional, target :: hmc_replay_diagnostics
      type(hmc_replay_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_hmc_replay_diagnostics(hmc_replay_diagnostics, active_diagnostics)
      active_diagnostics%reverse_gate_replay_status_success = 0_int64
      active_diagnostics%reverse_gate_replay_status_output_size_mismatch = 0_int64
      active_diagnostics%reverse_gate_replay_status_momentum_size_mismatch = 0_int64
      active_diagnostics%reverse_gate_replay_status_initial_force_failed = 0_int64
      active_diagnostics%reverse_gate_replay_status_constraint_failed = 0_int64
      active_diagnostics%reverse_gate_replay_status_final_flow_failed = 0_int64
      active_diagnostics%reverse_gate_replay_status_final_force_failed = 0_int64
      active_diagnostics%reverse_gate_replay_status_final_projection_failed = 0_int64
      active_diagnostics%reverse_gate_replay_status_reverse_gate_rejected = 0_int64
      active_diagnostics%reverse_gate_replay_status_final_flow_max_steps = 0_int64
      active_diagnostics%reverse_gate_replay_status_final_flow_invalid = 0_int64
      active_diagnostics%reverse_gate_replay_status_final_flow_h_min = 0_int64
      active_diagnostics%reverse_gate_replay_status_final_flow_non_strict_success = 0_int64
      active_diagnostics%reverse_gate_replay_status_unknown = 0_int64
   end subroutine reset_reverse_gate_replay_status_counts

   subroutine get_reverse_gate_replay_status_counts(success, output_size_mismatch, momentum_size_mismatch, initial_force_failed, &
                                                    constraint_failed, final_flow_failed, final_force_failed, final_projection_failed, &
                                                    reverse_gate_rejected, final_flow_max_steps, final_flow_invalid, final_flow_h_min, &
                                                    final_flow_non_strict_success, unknown, hmc_replay_diagnostics)
      implicit none
      integer(int64), intent(out) :: success, output_size_mismatch, momentum_size_mismatch, initial_force_failed
      integer(int64), intent(out) :: constraint_failed, final_flow_failed, final_force_failed, final_projection_failed
      integer(int64), intent(out) :: reverse_gate_rejected, final_flow_max_steps, final_flow_invalid, final_flow_h_min
      integer(int64), intent(out) :: final_flow_non_strict_success, unknown
      type(hmc_replay_diagnostics_context_t), intent(inout), optional, target :: hmc_replay_diagnostics
      type(hmc_replay_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_hmc_replay_diagnostics(hmc_replay_diagnostics, active_diagnostics)
      success = active_diagnostics%reverse_gate_replay_status_success
      output_size_mismatch = active_diagnostics%reverse_gate_replay_status_output_size_mismatch
      momentum_size_mismatch = active_diagnostics%reverse_gate_replay_status_momentum_size_mismatch
      initial_force_failed = active_diagnostics%reverse_gate_replay_status_initial_force_failed
      constraint_failed = active_diagnostics%reverse_gate_replay_status_constraint_failed
      final_flow_failed = active_diagnostics%reverse_gate_replay_status_final_flow_failed
      final_force_failed = active_diagnostics%reverse_gate_replay_status_final_force_failed
      final_projection_failed = active_diagnostics%reverse_gate_replay_status_final_projection_failed
      reverse_gate_rejected = active_diagnostics%reverse_gate_replay_status_reverse_gate_rejected
      final_flow_max_steps = active_diagnostics%reverse_gate_replay_status_final_flow_max_steps
      final_flow_invalid = active_diagnostics%reverse_gate_replay_status_final_flow_invalid
      final_flow_h_min = active_diagnostics%reverse_gate_replay_status_final_flow_h_min
      final_flow_non_strict_success = active_diagnostics%reverse_gate_replay_status_final_flow_non_strict_success
      unknown = active_diagnostics%reverse_gate_replay_status_unknown
   end subroutine get_reverse_gate_replay_status_counts

   subroutine record_reverse_gate_replay_status(step_status, hmc_replay_diagnostics)
      implicit none
      integer, intent(in) :: step_status
      type(hmc_replay_diagnostics_context_t), intent(inout), optional, target :: hmc_replay_diagnostics
      type(hmc_replay_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_hmc_replay_diagnostics(hmc_replay_diagnostics, active_diagnostics)
      select case (step_status)
      case (hmc_step_status_success)
         active_diagnostics%reverse_gate_replay_status_success = active_diagnostics%reverse_gate_replay_status_success + 1_int64
      case (hmc_step_status_output_size_mismatch)
         active_diagnostics%reverse_gate_replay_status_output_size_mismatch = &
            active_diagnostics%reverse_gate_replay_status_output_size_mismatch + 1_int64
      case (hmc_step_status_momentum_size_mismatch)
         active_diagnostics%reverse_gate_replay_status_momentum_size_mismatch = &
            active_diagnostics%reverse_gate_replay_status_momentum_size_mismatch + 1_int64
      case (hmc_step_status_initial_force_failed)
         active_diagnostics%reverse_gate_replay_status_initial_force_failed = &
            active_diagnostics%reverse_gate_replay_status_initial_force_failed + 1_int64
      case (hmc_step_status_constraint_failed)
         active_diagnostics%reverse_gate_replay_status_constraint_failed = &
            active_diagnostics%reverse_gate_replay_status_constraint_failed + 1_int64
      case (hmc_step_status_final_flow_failed)
         active_diagnostics%reverse_gate_replay_status_final_flow_failed = &
            active_diagnostics%reverse_gate_replay_status_final_flow_failed + 1_int64
      case (hmc_step_status_final_force_failed)
         active_diagnostics%reverse_gate_replay_status_final_force_failed = &
            active_diagnostics%reverse_gate_replay_status_final_force_failed + 1_int64
      case (hmc_step_status_final_projection_failed)
         active_diagnostics%reverse_gate_replay_status_final_projection_failed = &
            active_diagnostics%reverse_gate_replay_status_final_projection_failed + 1_int64
      case (hmc_step_status_reverse_gate_rejected)
         active_diagnostics%reverse_gate_replay_status_reverse_gate_rejected = &
            active_diagnostics%reverse_gate_replay_status_reverse_gate_rejected + 1_int64
      case (hmc_step_status_final_flow_max_steps)
         active_diagnostics%reverse_gate_replay_status_final_flow_max_steps = &
            active_diagnostics%reverse_gate_replay_status_final_flow_max_steps + 1_int64
      case (hmc_step_status_final_flow_invalid)
         active_diagnostics%reverse_gate_replay_status_final_flow_invalid = &
            active_diagnostics%reverse_gate_replay_status_final_flow_invalid + 1_int64
      case (hmc_step_status_final_flow_h_min)
         active_diagnostics%reverse_gate_replay_status_final_flow_h_min = &
            active_diagnostics%reverse_gate_replay_status_final_flow_h_min + 1_int64
      case (hmc_step_status_final_flow_non_strict_success)
         active_diagnostics%reverse_gate_replay_status_final_flow_non_strict_success = &
            active_diagnostics%reverse_gate_replay_status_final_flow_non_strict_success + 1_int64
      case default
         active_diagnostics%reverse_gate_replay_status_unknown = active_diagnostics%reverse_gate_replay_status_unknown + 1_int64
      end select
   end subroutine record_reverse_gate_replay_status

   subroutine rattle_step_core(state_x, state_z, step_size, final_x, final_z, jaci, jacf, momentum, &
                               method_converged, ws, step_status, flow_workspace, qn_context, qn_diagnostics, qn_policy, &
                               hmc_policy, hmc_replay_runtime, hmc_replay_diagnostics)
      implicit none

      real(dp), intent(in) :: state_x(:)
      complex(dp), intent(in) :: state_z(:)
      real(dp), intent(in) :: step_size
      real(dp), intent(out) :: final_x(:)
      complex(dp), intent(out) :: final_z(:)
      complex(dp), intent(in) :: jaci(:, :)
      complex(dp), intent(out) :: jacf(:, :)
      real(dp), intent(inout) :: momentum(:)
      logical, intent(out) :: method_converged
      type(rattle_step_workspace_t), intent(inout) :: ws
      integer, intent(out), optional :: step_status
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      type(hmc_policy_context_t), intent(inout), optional, target :: hmc_policy
      type(hmc_replay_runtime_context_t), intent(inout), optional, target :: hmc_replay_runtime
      type(hmc_replay_diagnostics_context_t), intent(inout), optional, target :: hmc_replay_diagnostics

      integer :: n_state
      logical :: has_error
      real(dp) :: t_prof
      logical :: quasi_trace_available
      integer :: quasi_proposal_count
      real(dp) :: quasi_tol
      integer :: quasi_case
      logical :: quasi_solved_ok
      logical :: trace_stats_available, trace_all_eval_ok, is_near_case
      logical :: near_rescue_done
      logical :: near_rescue_started
      logical :: reverse_gate_used_probe_only, reverse_gate_used_full_stage
      logical :: reverse_gate_used_near_rescue, reverse_gate_used_nonnear_route
      logical :: reverse_gate_used_class_local, reverse_gate_used_class_mid, reverse_gate_used_class_global
      logical :: reverse_gate_used_far_skip, reverse_gate_used_far_light, reverse_gate_used_far_anchor
      logical :: reverse_gate_passed
      integer :: reverse_gate_far_route
      integer :: reverse_gate_class_code
      integer :: trace_count, trace_valid_count
      integer :: attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown
      integer :: fail_flowz, fail_flowzr, fail_flow, fail_unknown
      integer :: success_radau_adaptive, success_radau_adaptive_robust
      integer :: success_radau_fixed_tol, success_radau_chunked, success_final_resort
      integer :: fail_radau_adaptive_robust, fail_radau_fixed_tol, fail_radau_chunked, fail_final_resort
      integer :: radau_rescue_ok, radau_rescue_fail
      integer :: final_flow_status
      integer :: quasi_budget_used, quasi_budget_limit
      logical :: quasi_budget_hit
      real(dp) :: trace_first_res, trace_best_res, trace_last_res, trace_regress_ratio, trace_progress_ratio
      real(dp) :: trace_valid_fraction
      real(dp) :: near_case_res_threshold, class2_retry_res_threshold
      real(dp) :: trace_best_over_tol
      real(dp), allocatable :: initial_momentum_for_gate(:)
      complex(dp), allocatable :: quasi_z_proposed(:), quasi_z_flowed(:)
      real(dp), allocatable :: quasi_res_norm(:), quasi_alpha(:)
      integer, allocatable :: quasi_iter(:), quasi_backtrack(:), quasi_attempt(:)
      logical, allocatable :: quasi_accepted(:), quasi_eval_ok(:)
      type(hmc_policy_context_t), pointer :: active_hmc_policy
      type(hmc_replay_runtime_context_t), pointer :: active_hmc_replay_runtime
      type(hmc_replay_diagnostics_context_t), pointer :: active_hmc_replay_diagnostics

      call perf_tic(t_prof)
      call resolve_hmc_policy(hmc_policy, active_hmc_policy)
      call resolve_hmc_replay_runtime(hmc_replay_runtime, active_hmc_replay_runtime)
      call resolve_hmc_replay_diagnostics(hmc_replay_diagnostics, active_hmc_replay_diagnostics)
      n_state = size(state_z)
      has_error = .false.
      method_converged = .false.
      if (present(step_status)) step_status = hmc_step_status_constraint_failed
      quasi_solved_ok = .false.
      trace_stats_available = .false.
      trace_count = 0
      trace_valid_count = 0
      trace_first_res = 0.0_dp
      trace_best_res = 0.0_dp
      trace_last_res = 0.0_dp
      trace_valid_fraction = 0.0_dp
      trace_progress_ratio = 1.0_dp
      trace_regress_ratio = 1.0_dp
      trace_best_over_tol = -1.0_dp
      near_rescue_started = .false.
      near_rescue_done = .false.
      reverse_gate_used_probe_only = .false.
      reverse_gate_used_full_stage = .false.
      reverse_gate_used_near_rescue = .false.
      reverse_gate_used_nonnear_route = .false.
      reverse_gate_used_class_local = .false.
      reverse_gate_used_class_mid = .false.
      reverse_gate_used_class_global = .false.
      reverse_gate_used_far_skip = .false.
      reverse_gate_used_far_light = .false.
      reverse_gate_used_far_anchor = .false.
      reverse_gate_passed = .false.
      reverse_gate_far_route = -1
      reverse_gate_class_code = 0
      quasi_case = quasi_case_far
      is_near_case = .false.
      quasi_budget_hit = .false.
      quasi_budget_used = -1
      quasi_budget_limit = -1

      if (size(final_x) /= size(state_x) .or. size(final_z) /= n_state) then
         if (present(step_status)) step_status = hmc_step_status_output_size_mismatch
         call perf_toc(PERF_RATTLE_STEP_CORE, t_prof)
         return
      end if
      if (size(momentum) /= 2*n_state) then
         if (present(step_status)) step_status = hmc_step_status_momentum_size_mismatch
         call perf_toc(PERF_RATTLE_STEP_CORE, t_prof)
         return
      end if

      call ensure_rattle_step_workspace(ws, size(state_x), n_state, size(jaci, 1), size(jaci, 2))
      call load_s1_fallback_policy(active_hmc_policy)
      if (active_hmc_policy%qn_reverse_gate_enabled .and. (.not. active_hmc_replay_runtime%qn_reverse_gate_active)) then
         allocate (initial_momentum_for_gate(size(momentum)))
         initial_momentum_for_gate = momentum
      end if

      final_x = state_x
      final_z = state_z
      ws%temp_jac = jaci
      ws%temp_x = final_x
      ws%temp_z = final_z

      call ds(state_z, ws%ds_val)
      ws%E0 = conjg(ws%ds_val)
      call complex_to_real(ws%E0, ws%E0_real)
      call calculate_dV(n_state, ws%E0_real, ws%E0_perp, ws%dV, has_error)
      if (has_error) then
         if (present(step_status)) step_status = hmc_step_status_initial_force_failed
         if (allocated(initial_momentum_for_gate)) deallocate (initial_momentum_for_gate)
         call perf_toc(PERF_RATTLE_STEP_CORE, t_prof)
         return
      end if

      ws%del_z = step_size*momentum - step_size**2*ws%dV

      call set_intode_stage_trace(intode_stage_newton)
      call set_intode_newton_iter_trace(0)
      call set_intode_quasi_iter_trace(0)
      call solve_constraint_newton(cttol, 100, ws%temp_x, ws%temp_z, ws%del_z, step_size, has_error, ws%Jl, final_x, &
                                   ws%temp_jac, workspace=ws%newton_ws, flow_workspace=flow_workspace)
      if (.not. has_error) then
         call record_constraint_solver_newton_success()
      else
         if (quasi_fallback_enabled) then
            call set_intode_stage_trace(intode_stage_quasi)
            call set_intode_quasi_iter_trace(0)
            quasi_tol = cttol
            if (active_hmc_policy%qn_quasi_tol_override > 0.0_dp) quasi_tol = active_hmc_policy%qn_quasi_tol_override
            trace_stats_available = .false.
            trace_all_eval_ok = .false.
            trace_count = 0
            trace_valid_count = 0
            trace_first_res = huge(1.0_dp)
            trace_best_res = huge(1.0_dp)
            trace_last_res = huge(1.0_dp)
            trace_progress_ratio = huge(1.0_dp)
            trace_regress_ratio = huge(1.0_dp)
            trace_valid_fraction = 0.0_dp
            near_case_res_threshold = huge(1.0_dp)
            class2_retry_res_threshold = huge(1.0_dp)
            is_near_case = .false.
            quasi_case = quasi_case_far
            near_rescue_done = .false.
            near_rescue_started = .false.

            ! S1-only fallback path: probe -> classify -> one stage-1 rescue pass.
            call try_quasi_stage(quasi_tol, active_hmc_policy%s1_probe_max_iter, constraint_quasi_stage_probe, ws, has_error, final_x, &
                                 flow_workspace, qn_context, qn_diagnostics, qn_policy)
            if (.not. has_error) then
               quasi_solved_ok = .true.
            else
               call get_quasi_newton_last_trace_stats(trace_stats_available, trace_count, trace_first_res, trace_best_res, trace_last_res, &
                                                      trace_all_eval_ok, trace_valid_count, trace_valid_fraction, qn_context=qn_context)
               call update_quasi_trace_gate_metrics(trace_stats_available, trace_first_res, trace_best_res, &
                                                    trace_last_res, quasi_tol, trace_progress_ratio, &
                                                    trace_regress_ratio, class2_retry_res_threshold, near_case_res_threshold)
               if (trace_stats_available .and. quasi_tol > 0.0_dp) then
                  trace_best_over_tol = trace_best_res/quasi_tol
               else
                  trace_best_over_tol = -1.0_dp
               end if
               quasi_case = classify_quasi_failure_case(trace_stats_available, trace_valid_count, trace_valid_fraction, &
                                                        trace_best_res, quasi_tol, &
                                                        near_case_res_threshold, class2_retry_res_threshold, &
                                                        trace_progress_ratio, trace_regress_ratio)
               reverse_gate_class_code = map_quasi_case_to_online_class(quasi_case)
               call record_constraint_solver_quasi_class(reverse_gate_class_code)
               select case (reverse_gate_class_code)
               case (constraint_quasi_class_local)
                  reverse_gate_used_class_local = .true.
               case (constraint_quasi_class_mid)
                  reverse_gate_used_class_mid = .true.
               case (constraint_quasi_class_global)
                  reverse_gate_used_class_global = .true.
               end select
               is_near_case = (quasi_case == quasi_case_near)

               call run_s1_rescue_path(quasi_tol, quasi_case, &
                                                trace_stats_available, trace_valid_fraction, &
                                                trace_progress_ratio, trace_regress_ratio, trace_best_over_tol, &
                                                step_size, ws, has_error, final_x, near_rescue_started, near_rescue_done, &
                                                quasi_solved_ok, reverse_gate_used_full_stage, &
                                                reverse_gate_used_nonnear_route, reverse_gate_far_route, flow_workspace, qn_context, &
                                                qn_diagnostics, qn_policy, active_hmc_policy)

               reverse_gate_used_near_rescue = near_rescue_started
               select case (reverse_gate_far_route)
               case (constraint_quasi_far_route_skip)
                  reverse_gate_used_far_skip = .true.
               case (constraint_quasi_far_route_light)
                  reverse_gate_used_far_light = .true.
               case (constraint_quasi_far_route_anchor)
                  reverse_gate_used_far_anchor = .true.
               end select

               if (has_error) then
                  call get_quasi_newton_last_trace_stats(trace_stats_available, trace_count, trace_first_res, trace_best_res, trace_last_res, &
                                                         trace_all_eval_ok, trace_valid_count, trace_valid_fraction, qn_context=qn_context)
                  if (trace_stats_available) then
                     call update_quasi_trace_gate_metrics(trace_stats_available, trace_first_res, trace_best_res, &
                                                          trace_last_res, quasi_tol, trace_progress_ratio, &
                                                          trace_regress_ratio, class2_retry_res_threshold, near_case_res_threshold)
                  end if
                  if (trace_stats_available .and. quasi_tol > 0.0_dp) then
                     trace_best_over_tol = trace_best_res/quasi_tol
                  else
                     trace_best_over_tol = -1.0_dp
                  end if
                  quasi_case = classify_quasi_failure_case(trace_stats_available, trace_valid_count, trace_valid_fraction, &
                                                           trace_best_res, quasi_tol, &
                                                           near_case_res_threshold, class2_retry_res_threshold, &
                                                           trace_progress_ratio, trace_regress_ratio)
                  is_near_case = (quasi_case == quasi_case_near)
                  if (is_near_case) then
                     call record_constraint_near_fail_candidate()
                  else
                     call record_constraint_far_fail()
                  end if
               end if
            end if

            if (has_error) then
               call get_intode_fallback_context_stats(attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                                      fail_flowz, fail_flowzr, fail_flow, fail_unknown)
               call get_intode_rescue_stats(success_radau_adaptive, success_radau_adaptive_robust, &
                                            success_radau_fixed_tol, success_radau_chunked, success_final_resort, &
                                            fail_radau_adaptive_robust, fail_radau_fixed_tol, fail_radau_chunked, &
                                            fail_final_resort)
               radau_rescue_ok = success_radau_fixed_tol + success_radau_chunked
               radau_rescue_fail = fail_radau_adaptive_robust + fail_radau_fixed_tol + fail_radau_chunked
               if (trace_stats_available .and. quasi_tol > 0.0_dp) then
                  trace_best_over_tol = trace_best_res/quasi_tol
               else
                  trace_best_over_tol = -1.0_dp
               end if

               call get_quasi_newton_last_trace_r2c(quasi_trace_available, quasi_proposal_count, quasi_z_proposed, quasi_z_flowed, &
                                                    quasi_res_norm, quasi_alpha, quasi_iter, quasi_backtrack, quasi_attempt, &
                                                    quasi_accepted, quasi_eval_ok, qn_context=qn_context)
               if (quasi_trace_available .and. quasi_proposal_count > 0) then
                  call record_constraint_solver_fail(state_z, ws%del_z, state_x, &
                                                     quasi_z_proposed=quasi_z_proposed, quasi_z_flowed=quasi_z_flowed, &
                                                     quasi_res_norm=quasi_res_norm, quasi_alpha=quasi_alpha, &
                                                     quasi_iter=quasi_iter, quasi_backtrack=quasi_backtrack, quasi_attempt=quasi_attempt, &
                                                     quasi_accepted=quasi_accepted, quasi_eval_ok=quasi_eval_ok, &
                                                     quasi_case=quasi_case, online_class=map_quasi_case_to_online_class(quasi_case), &
                                                     trace_valid_fraction=trace_valid_fraction, trace_progress_ratio=trace_progress_ratio, &
                                                     trace_regress_ratio=trace_regress_ratio, trace_best_over_tol=trace_best_over_tol, &
                                                     is_near_case=is_near_case, near_rescue_started=near_rescue_started, &
                                                     near_rescue_done=near_rescue_done, near_fail_fast=.false., &
                                                     near_fail_fast_reason=0, far_fail_fast=.false., far_fail_fast_reason=0, &
                                                     attempt_flowz=attempt_flowz, attempt_flowzr=attempt_flowzr, &
                                                     attempt_flow=attempt_flow, attempt_unknown=attempt_unknown, &
                                                     fail_flowz=fail_flowz, fail_flowzr=fail_flowzr, fail_flow=fail_flow, &
                                                     fail_unknown=fail_unknown, success_final_resort=success_final_resort, &
                                                     fail_final_resort=fail_final_resort, radau_rescue_ok=radau_rescue_ok, &
                                                     radau_rescue_fail=radau_rescue_fail, &
                                                     final_resort_budget_hit=quasi_budget_hit, &
                                                     final_resort_budget_used=quasi_budget_used, &
                                                     final_resort_budget_limit=quasi_budget_limit)
               else
                  call record_constraint_solver_fail(state_z, ws%del_z, state_x, &
                                                     quasi_case=quasi_case, online_class=map_quasi_case_to_online_class(quasi_case), &
                                                     trace_valid_fraction=trace_valid_fraction, trace_progress_ratio=trace_progress_ratio, &
                                                     trace_regress_ratio=trace_regress_ratio, trace_best_over_tol=trace_best_over_tol, &
                                                     is_near_case=is_near_case, near_rescue_started=near_rescue_started, &
                                                     near_rescue_done=near_rescue_done, near_fail_fast=.false., &
                                                     near_fail_fast_reason=0, far_fail_fast=.false., far_fail_fast_reason=0, &
                                                     attempt_flowz=attempt_flowz, attempt_flowzr=attempt_flowzr, &
                                                     attempt_flow=attempt_flow, attempt_unknown=attempt_unknown, &
                                                     fail_flowz=fail_flowz, fail_flowzr=fail_flowzr, fail_flow=fail_flow, &
                                                     fail_unknown=fail_unknown, success_final_resort=success_final_resort, &
                                                     fail_final_resort=fail_final_resort, radau_rescue_ok=radau_rescue_ok, &
                                                     radau_rescue_fail=radau_rescue_fail, &
                                                     final_resort_budget_hit=quasi_budget_hit, &
                                                     final_resort_budget_used=quasi_budget_used, &
                                                     final_resort_budget_limit=quasi_budget_limit)
               end if
            end if
         else
            call record_constraint_far_fail()
            call get_intode_fallback_context_stats(attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                                   fail_flowz, fail_flowzr, fail_flow, fail_unknown)
            call get_intode_rescue_stats(success_radau_adaptive, success_radau_adaptive_robust, &
                                         success_radau_fixed_tol, success_radau_chunked, success_final_resort, &
                                         fail_radau_adaptive_robust, fail_radau_fixed_tol, fail_radau_chunked, &
                                         fail_final_resort)
            radau_rescue_ok = success_radau_fixed_tol + success_radau_chunked
            radau_rescue_fail = fail_radau_adaptive_robust + fail_radau_fixed_tol + fail_radau_chunked
            call record_constraint_solver_fail(state_z, ws%del_z, state_x, &
                                               quasi_case=quasi_case_far, online_class=constraint_quasi_class_global, &
                                               trace_valid_fraction=-1.0_dp, trace_progress_ratio=-1.0_dp, &
                                               trace_regress_ratio=-1.0_dp, trace_best_over_tol=-1.0_dp, &
                                               is_near_case=.false., near_rescue_started=.false., near_rescue_done=.false., &
                                               near_fail_fast=.false., near_fail_fast_reason=0, &
                                               far_fail_fast=.false., far_fail_fast_reason=0, &
                                               attempt_flowz=attempt_flowz, attempt_flowzr=attempt_flowzr, &
                                               attempt_flow=attempt_flow, attempt_unknown=attempt_unknown, &
                                               fail_flowz=fail_flowz, fail_flowzr=fail_flowzr, fail_flow=fail_flow, &
                                               fail_unknown=fail_unknown, success_final_resort=success_final_resort, &
                                               fail_final_resort=fail_final_resort, radau_rescue_ok=radau_rescue_ok, &
                                               radau_rescue_fail=radau_rescue_fail, &
                                               final_resort_budget_hit=quasi_budget_hit, &
                                               final_resort_budget_used=quasi_budget_used, &
                                               final_resort_budget_limit=quasi_budget_limit)
         end if
      end if

      if (has_error) then
         if (present(step_status)) step_status = hmc_step_status_constraint_failed
         if (allocated(initial_momentum_for_gate)) deallocate (initial_momentum_for_gate)
         call perf_toc(PERF_RATTLE_STEP_CORE, t_prof)
         return
      end if

      call set_intode_stage_trace(intode_stage_rattle_flow)
      call set_intode_newton_iter_trace(0)
      call set_intode_quasi_iter_trace(0)
      call flow(final_x, final_z, ws%temp_jac, has_error, final_flow_status, flow_workspace)
      if (has_error .or. (.not. intode_status_is_strict_success(final_flow_status))) then
         has_error = .true.
         if (present(step_status)) step_status = hmc_step_status_from_final_flow_status(final_flow_status)
         if (allocated(initial_momentum_for_gate)) deallocate (initial_momentum_for_gate)
         call perf_toc(PERF_RATTLE_STEP_CORE, t_prof)
         return
      end if
      if (quasi_solved_ok) call record_constraint_solver_quasi_success()

      call complex_to_real((final_z - ws%temp_z)/step_size, momentum)
      call ds(final_z, ws%ds_val)
      ws%E0 = conjg(ws%ds_val)
      call complex_to_real(ws%E0, ws%E0_real)

      call calculate_dV(n_state, ws%E0_real, ws%E0_perp, ws%dV, has_error)
      if (has_error) then
         if (present(step_status)) step_status = hmc_step_status_final_force_failed
         if (allocated(initial_momentum_for_gate)) deallocate (initial_momentum_for_gate)
         call perf_toc(PERF_RATTLE_STEP_CORE, t_prof)
         return
      end if

      momentum = momentum - step_size*ws%dV
      call decompose2(momentum, ws%E0_perp, ws%del_z, ws%Jl, ws%temp_jac, has_error, ws%decompose_ws)
      if (has_error) then
         if (present(step_status)) step_status = hmc_step_status_final_projection_failed
         if (allocated(initial_momentum_for_gate)) deallocate (initial_momentum_for_gate)
         call perf_toc(PERF_RATTLE_STEP_CORE, t_prof)
         return
      end if
      momentum = ws%del_z

      if (active_hmc_policy%qn_reverse_gate_enabled .and. (.not. active_hmc_replay_runtime%qn_reverse_gate_active)) then
         reverse_gate_used_probe_only = (.not. reverse_gate_used_full_stage) .and. &
                                        (.not. reverse_gate_used_near_rescue) .and. &
                                        (.not. reverse_gate_used_nonnear_route)
         reverse_gate_passed = qn_reverse_gate_accepts(state_x, state_z, initial_momentum_for_gate, &
                                                       final_x, final_z, jaci, ws%temp_jac, momentum, step_size, flow_workspace, &
                                                       qn_context, qn_diagnostics, qn_policy, active_hmc_policy, &
                                                       active_hmc_replay_runtime, active_hmc_replay_diagnostics)
         call record_constraint_solver_reverse_gate(reverse_gate_passed, reverse_gate_used_probe_only, &
                                                    reverse_gate_used_full_stage, reverse_gate_used_near_rescue, &
                                                    reverse_gate_used_nonnear_route, reverse_gate_used_class_local, &
                                                    reverse_gate_used_class_mid, reverse_gate_used_class_global, &
                                                    reverse_gate_used_far_skip, reverse_gate_used_far_light, &
                                                    reverse_gate_used_far_anchor)
         if (.not. reverse_gate_passed) then
            if (present(step_status)) step_status = hmc_step_status_reverse_gate_rejected
            if (size(state_z) >= 1 .and. size(ws%del_z) >= 2 .and. size(state_x) >= 2) then
               write (*, '(A,1X,ES24.16,1X,ES24.16,1X,ES24.16,1X,ES24.16,1X,ES24.16,1X,ES24.16,1X,ES24.16,1X,ES24.16)') &
                  '[RG_REJECT_CASE] z0_re z0_im delz_u delz_v x0_u zacc_re zacc_im xacc_u=', &
                  real(state_z(1), dp), aimag(state_z(1)), ws%del_z(1), ws%del_z(2), state_x(2), &
                  real(final_z(1), dp), aimag(final_z(1)), final_x(2)
            end if
            if (allocated(initial_momentum_for_gate)) deallocate (initial_momentum_for_gate)
            call perf_toc(PERF_RATTLE_STEP_CORE, t_prof)
            return
         end if
      end if

      jacf = ws%temp_jac
      method_converged = .true.
      if (present(step_status)) step_status = hmc_step_status_success
      call set_intode_stage_trace(intode_stage_external)
      if (allocated(initial_momentum_for_gate)) deallocate (initial_momentum_for_gate)
      call perf_toc(PERF_RATTLE_STEP_CORE, t_prof)
   end subroutine rattle_step_core

   pure integer function hmc_step_status_from_final_flow_status(flow_status) result(status)
      implicit none
      integer, intent(in) :: flow_status

      select case (flow_status)
      case (intode_status_failure_max_steps)
         status = hmc_step_status_final_flow_max_steps
      case (intode_status_failure_invalid)
         status = hmc_step_status_final_flow_invalid
      case (intode_status_failure_h_min)
         status = hmc_step_status_final_flow_h_min
      case (intode_status_success_stiff_rescue, intode_status_success_solver_assist)
         status = hmc_step_status_final_flow_non_strict_success
      case default
         status = hmc_step_status_final_flow_failed
      end select
   end function hmc_step_status_from_final_flow_status

   logical function qn_reverse_gate_accepts(state_x, state_z, initial_momentum, final_x, final_z, initial_jac, final_jac, &
                                            final_momentum, step_size, flow_workspace, qn_context, qn_diagnostics, qn_policy, &
                                            hmc_policy, hmc_replay_runtime, hmc_replay_diagnostics) result(accepts)
      implicit none
      real(dp), intent(in) :: state_x(:), initial_momentum(:), final_x(:), final_momentum(:), step_size
      complex(dp), intent(in) :: state_z(:), final_z(:), initial_jac(:, :), final_jac(:, :)
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      type(hmc_policy_context_t), intent(inout), optional, target :: hmc_policy
      type(hmc_replay_runtime_context_t), intent(inout), optional, target :: hmc_replay_runtime
      type(hmc_replay_diagnostics_context_t), intent(inout), optional, target :: hmc_replay_diagnostics

      real(dp), allocatable :: reverse_x(:), reverse_momentum(:)
      complex(dp), allocatable :: reverse_z(:), reverse_jac(:, :)
      type(rattle_step_workspace_t) :: reverse_ws
      logical :: reverse_ok
      integer :: reverse_step_status
      real(dp) :: dx_inf, dz_inf, dj_inf, dp_inf
      type(hmc_policy_context_t), pointer :: active_hmc_policy
      type(hmc_replay_runtime_context_t), pointer :: active_hmc_replay_runtime
      type(hmc_replay_diagnostics_context_t), pointer :: active_hmc_replay_diagnostics

      accepts = .false.
      call resolve_hmc_policy(hmc_policy, active_hmc_policy)
      call resolve_hmc_replay_runtime(hmc_replay_runtime, active_hmc_replay_runtime)
      call resolve_hmc_replay_diagnostics(hmc_replay_diagnostics, active_hmc_replay_diagnostics)
      if (size(initial_momentum) /= size(final_momentum)) return
      if (size(state_x) /= size(final_x)) return
      if (size(state_z) /= size(final_z)) return
      if (size(initial_jac, 1) /= size(final_jac, 1) .or. size(initial_jac, 2) /= size(final_jac, 2)) return

      allocate (reverse_x(size(final_x)), reverse_momentum(size(final_momentum)))
      allocate (reverse_z(size(final_z)), reverse_jac(size(final_jac, 1), size(final_jac, 2)))

      reverse_momentum = -final_momentum
      active_hmc_replay_runtime%qn_reverse_gate_active = .true.
      reverse_step_status = hmc_step_status_unknown
      call push_constraint_solver_stats_suppression()
      call rattle_step_core(final_x, final_z, step_size, reverse_x, reverse_z, final_jac, reverse_jac, reverse_momentum, &
                            reverse_ok, reverse_ws, reverse_step_status, flow_workspace, qn_context, qn_diagnostics, qn_policy, &
                            active_hmc_policy, active_hmc_replay_runtime, active_hmc_replay_diagnostics)
      call pop_constraint_solver_stats_suppression()
      active_hmc_replay_runtime%qn_reverse_gate_active = .false.
      call record_reverse_gate_replay_status(reverse_step_status, active_hmc_replay_diagnostics)

      if (reverse_ok) then
         dx_inf = max_abs_real_local(reverse_x - state_x)
         dz_inf = max_abs_complex_local(reverse_z - state_z)
         dj_inf = maxval(abs(reverse_jac - initial_jac))
         dp_inf = max_abs_real_local(reverse_momentum + initial_momentum)
         accepts = (dx_inf <= active_hmc_policy%qn_reverse_gate_tol .and. dz_inf <= active_hmc_policy%qn_reverse_gate_tol .and. &
                    dj_inf <= active_hmc_policy%qn_reverse_gate_tol .and. dp_inf <= active_hmc_policy%qn_reverse_gate_tol)
      end if

      call release_rattle_step_workspace(reverse_ws)
      if (allocated(reverse_x)) deallocate (reverse_x)
      if (allocated(reverse_momentum)) deallocate (reverse_momentum)
      if (allocated(reverse_z)) deallocate (reverse_z)
      if (allocated(reverse_jac)) deallocate (reverse_jac)
   end function qn_reverse_gate_accepts

   subroutine try_quasi_stage(quasi_tol, quasi_max_iter, stage_code, ws, has_error, final_x, flow_workspace, qn_context, qn_diagnostics, &
                              qn_policy)
      implicit none
      real(dp), intent(in) :: quasi_tol
      integer, intent(in) :: quasi_max_iter, stage_code
      type(rattle_step_workspace_t), intent(inout) :: ws
      logical, intent(out) :: has_error
      real(dp), intent(inout) :: final_x(:)
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy

      call record_constraint_solver_quasi_stage_attempt(stage_code)
      call solve_constraint_quasi_newton(evaluate_constraint_residual, quasi_tol, quasi_max_iter, ws%temp_x, ws%temp_z, ws%del_z, &
                                         has_error, ws%Jl, final_x, ws%temp_jac, flow_workspace=flow_workspace, qn_context=qn_context, &
                                         qn_diagnostics=qn_diagnostics, qn_policy=qn_policy)
      if (.not. has_error) then
         call record_constraint_solver_quasi_stage_success(stage_code)
      end if
   end subroutine try_quasi_stage

   subroutine refresh_quasi_trace_gate_state(quasi_tol, trace_available, trace_valid_fraction, &
                                             trace_progress_ratio, trace_regress_ratio, trace_best_over_tol, qn_context)
      implicit none
      real(dp), intent(in) :: quasi_tol
      logical, intent(out) :: trace_available
      real(dp), intent(out) :: trace_valid_fraction
      real(dp), intent(out) :: trace_progress_ratio, trace_regress_ratio, trace_best_over_tol
      integer :: trace_count, trace_valid_count
      real(dp) :: trace_first_res, trace_best_res, trace_last_res
      real(dp) :: class2_retry_res_threshold, near_case_res_threshold
      logical :: trace_all_eval_ok
      type(qn_context_t), intent(inout), optional, target :: qn_context

      trace_available = .false.
      trace_valid_fraction = 0.0_dp
      trace_progress_ratio = huge(1.0_dp)
      trace_regress_ratio = huge(1.0_dp)
      trace_best_over_tol = -1.0_dp
      trace_count = 0
      trace_valid_count = 0
      trace_first_res = huge(1.0_dp)
      trace_best_res = huge(1.0_dp)
      trace_last_res = huge(1.0_dp)
      trace_all_eval_ok = .false.
      class2_retry_res_threshold = huge(1.0_dp)
      near_case_res_threshold = huge(1.0_dp)

      call get_quasi_newton_last_trace_stats(trace_available, trace_count, trace_first_res, trace_best_res, trace_last_res, &
                                             trace_all_eval_ok, trace_valid_count, trace_valid_fraction, qn_context=qn_context)
      if (trace_available) then
         call update_quasi_trace_gate_metrics(trace_available, trace_first_res, trace_best_res, trace_last_res, &
                                              quasi_tol, trace_progress_ratio, trace_regress_ratio, &
                                              class2_retry_res_threshold, near_case_res_threshold)
      end if
      if (trace_available .and. quasi_tol > 0.0_dp) then
         trace_best_over_tol = trace_best_res/quasi_tol
      end if
   end subroutine refresh_quasi_trace_gate_state

   subroutine run_s1_rescue_path(quasi_tol, quasi_case, &
                                          trace_stats_available, trace_valid_fraction, trace_progress_ratio, &
                                          trace_regress_ratio, trace_best_over_tol, &
                                          step_size, ws, has_error, final_x, near_rescue_started, near_rescue_done, &
                                          quasi_solved_ok, used_full_stage, &
                                          used_nonnear_route, far_route_used, flow_workspace, qn_context, qn_diagnostics, qn_policy, &
                                          hmc_policy)
      implicit none
      real(dp), intent(in) :: quasi_tol
      real(dp), intent(in) :: step_size
      integer, intent(in) :: quasi_case
      logical, intent(inout) :: trace_stats_available
      real(dp), intent(inout) :: trace_valid_fraction, trace_progress_ratio, trace_regress_ratio, trace_best_over_tol
      type(rattle_step_workspace_t), intent(inout) :: ws
      logical, intent(inout) :: has_error
      real(dp), intent(inout) :: final_x(:)
      logical, intent(inout) :: near_rescue_started
      logical, intent(inout) :: near_rescue_done
      logical, intent(inout) :: quasi_solved_ok
      logical, intent(inout) :: used_full_stage
      logical, intent(inout) :: used_nonnear_route
      integer, intent(inout) :: far_route_used
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      type(hmc_policy_context_t), intent(in) :: hmc_policy
      integer :: far_route

      if (.not. has_error) return

      if (quasi_case == quasi_case_near) then
         if (.not. hmc_policy%s1_near_rescue_enabled) then
            call record_constraint_near_unusable()
            return
         end if
         near_rescue_started = .true.
         call record_constraint_near_rescue_attempt()
         used_full_stage = .true.
         call try_quasi_stage(quasi_tol, hmc_policy%s1_near_full_max_iter, constraint_quasi_stage_full, ws, has_error, final_x, &
                              flow_workspace, qn_context, qn_diagnostics, qn_policy)
         if (.not. has_error) then
            near_rescue_done = .true.
            call record_constraint_near_rescue_success()
            quasi_solved_ok = .true.
            return
         end if

         call refresh_quasi_trace_gate_state(quasi_tol, trace_stats_available, trace_valid_fraction, &
                                             trace_progress_ratio, trace_regress_ratio, trace_best_over_tol, qn_context)
         call record_constraint_near_unusable()
         return
      end if

      far_route = classify_far_rescue_route(trace_stats_available, trace_valid_fraction, &
                                            trace_progress_ratio, trace_regress_ratio, trace_best_over_tol)
      far_route_used = far_route
      call record_constraint_solver_far_route(far_route)
      if (hmc_policy%s1_nonnear_rescue_enabled .and. far_route >= constraint_quasi_far_route_light) then
         used_full_stage = .true.
         used_nonnear_route = .true.
         call try_quasi_stage(quasi_tol, hmc_policy%s1_non_near_cheap_full_max_iter, constraint_quasi_stage_full, ws, has_error, final_x, &
                              flow_workspace, qn_context, qn_diagnostics, qn_policy)
      end if
      if (has_error) then
         call refresh_quasi_trace_gate_state(quasi_tol, trace_stats_available, trace_valid_fraction, &
                                             trace_progress_ratio, trace_regress_ratio, trace_best_over_tol, qn_context)
      end if
      call record_constraint_solver_far_investment((.not. has_error), .false., 0, 0)
      if (.not. has_error) quasi_solved_ok = .true.
   end subroutine run_s1_rescue_path

   integer function classify_quasi_failure_case(trace_available, trace_valid_count, trace_valid_fraction, trace_best_res, quasi_tol, &
                                                near_case_res_threshold, class2_retry_res_threshold, &
                                                trace_progress_ratio, trace_regress_ratio)
      implicit none
      logical, intent(in) :: trace_available
      integer, intent(in) :: trace_valid_count
      real(dp), intent(in) :: trace_valid_fraction
      real(dp), intent(in) :: trace_best_res, quasi_tol
      real(dp), intent(in) :: near_case_res_threshold, class2_retry_res_threshold
      real(dp), intent(in) :: trace_progress_ratio, trace_regress_ratio
      real(dp) :: tol_floor, best_over_tol
      integer, parameter :: local_valid_count_gate = 3
      integer, parameter :: mid_valid_count_gate = 2
      real(dp), parameter :: local_valid_fraction_gate = 0.50_dp
      real(dp), parameter :: mid_valid_fraction_gate = 0.30_dp
      real(dp), parameter :: mid_valid_fraction_relaxed_gate = 0.20_dp
      real(dp), parameter :: local_tol_ratio_gate = 1.0e10_dp
      real(dp), parameter :: local_progress_gate = 0.60_dp
      real(dp), parameter :: local_regress_gate = 96.0_dp
      real(dp), parameter :: mid_progress_gate = 0.90_dp
      real(dp), parameter :: mid_regress_gate = 192.0_dp

      if (.not. trace_available) then
         classify_quasi_failure_case = quasi_case_far
         return
      end if

      tol_floor = max(quasi_tol, tiny(1.0_dp))
      best_over_tol = trace_best_res/tol_floor

      if ((trace_valid_count >= local_valid_count_gate) .and. &
          (trace_valid_fraction >= local_valid_fraction_gate) .and. &
          (best_over_tol <= local_tol_ratio_gate) .and. &
          (trace_progress_ratio <= local_progress_gate) .and. &
          (trace_regress_ratio <= local_regress_gate)) then
         classify_quasi_failure_case = quasi_case_near
      else if ((trace_valid_count >= local_valid_count_gate) .and. &
               (trace_valid_fraction >= local_valid_fraction_gate) .and. &
               (trace_best_res <= near_case_res_threshold) .and. &
               (trace_progress_ratio <= local_progress_gate) .and. &
               (trace_regress_ratio <= local_regress_gate)) then
         classify_quasi_failure_case = quasi_case_near
      else if ((trace_valid_count >= mid_valid_count_gate) .and. &
               (trace_valid_fraction >= mid_valid_fraction_gate) .and. &
               (trace_best_res <= class2_retry_res_threshold) .and. &
               (trace_progress_ratio <= mid_progress_gate) .and. &
               (trace_regress_ratio <= mid_regress_gate)) then
         classify_quasi_failure_case = quasi_case_mid
      else if ((trace_valid_count >= mid_valid_count_gate) .and. &
               (trace_valid_fraction >= mid_valid_fraction_relaxed_gate) .and. &
               (trace_best_res <= class2_retry_res_threshold)) then
         classify_quasi_failure_case = quasi_case_mid
      else
         classify_quasi_failure_case = quasi_case_far
      end if
   end function classify_quasi_failure_case

   integer function map_quasi_case_to_online_class(quasi_case) result(class_code)
      implicit none
      integer, intent(in) :: quasi_case

      select case (quasi_case)
      case (quasi_case_near)
         class_code = constraint_quasi_class_local
      case (quasi_case_mid)
         class_code = constraint_quasi_class_mid
      case default
         class_code = constraint_quasi_class_global
      end select
   end function map_quasi_case_to_online_class

   integer function classify_far_rescue_route(trace_available, trace_valid_fraction, trace_progress_ratio, &
                                              trace_regress_ratio, trace_best_over_tol)
      implicit none
      logical, intent(in) :: trace_available
      real(dp), intent(in) :: trace_valid_fraction
      real(dp), intent(in) :: trace_progress_ratio, trace_regress_ratio
      real(dp), intent(in) :: trace_best_over_tol
      real(dp), parameter :: far_anchor_valid_fraction_gate = 0.40_dp
      real(dp), parameter :: far_anchor_progress_gate = 0.75_dp
      real(dp), parameter :: far_anchor_regress_gate = 128.0_dp
      real(dp), parameter :: far_anchor_best_over_tol_gate = 2.0e12_dp
      real(dp), parameter :: far_light_valid_fraction_gate = 0.22_dp
      real(dp), parameter :: far_light_progress_gate = 0.95_dp
      real(dp), parameter :: far_light_regress_gate = 256.0_dp
      real(dp), parameter :: far_light_best_over_tol_gate = 1.0e14_dp

      classify_far_rescue_route = constraint_quasi_far_route_skip
      if ((.not. trace_available) .or. (trace_best_over_tol <= 0.0_dp)) return

      if ((trace_valid_fraction >= far_anchor_valid_fraction_gate) .and. &
          (trace_progress_ratio <= far_anchor_progress_gate) .and. &
          (trace_regress_ratio <= far_anchor_regress_gate) .and. &
          (trace_best_over_tol <= far_anchor_best_over_tol_gate)) then
         classify_far_rescue_route = constraint_quasi_far_route_anchor
         return
      end if

      if ((trace_valid_fraction >= far_light_valid_fraction_gate) .and. &
          (trace_progress_ratio <= far_light_progress_gate) .and. &
          (trace_regress_ratio <= far_light_regress_gate) .and. &
          (trace_best_over_tol <= far_light_best_over_tol_gate)) then
         classify_far_rescue_route = constraint_quasi_far_route_light
      end if
   end function classify_far_rescue_route

   subroutine update_quasi_trace_gate_metrics(trace_available, trace_first_res, trace_best_res, trace_last_res, &
                                              quasi_tol, trace_progress_ratio, trace_regress_ratio, &
                                              class2_retry_res_threshold, near_case_res_threshold)
      implicit none
      logical, intent(in) :: trace_available
      real(dp), intent(in) :: trace_first_res, trace_best_res, trace_last_res, quasi_tol
      real(dp), intent(out) :: trace_progress_ratio, trace_regress_ratio
      real(dp), intent(out) :: class2_retry_res_threshold, near_case_res_threshold
      real(dp), parameter :: class2_retry_res_ratio = 8.0e-2_dp
      real(dp), parameter :: class2_retry_tol_scale = 1.0e4_dp
      real(dp), parameter :: near_case_res_ratio = 1.0e-3_dp
      real(dp), parameter :: near_case_tol_scale = 256.0_dp
      real(dp) :: tol_floor, trace_scale

      trace_progress_ratio = huge(1.0_dp)
      trace_regress_ratio = huge(1.0_dp)
      class2_retry_res_threshold = huge(1.0_dp)
      near_case_res_threshold = huge(1.0_dp)
      if (.not. trace_available) return

      tol_floor = max(quasi_tol, tiny(1.0_dp))
      trace_scale = max(trace_first_res, tol_floor)
      class2_retry_res_threshold = max(class2_retry_tol_scale*tol_floor, class2_retry_res_ratio*trace_scale)

      near_case_res_threshold = max(near_case_tol_scale*tol_floor, near_case_res_ratio*trace_scale)
      near_case_res_threshold = min(near_case_res_threshold, class2_retry_res_threshold)

      if (trace_best_res > 0.0_dp) then
         trace_regress_ratio = trace_last_res/trace_best_res
      end if
      if (trace_first_res > 0.0_dp) then
         trace_progress_ratio = trace_best_res/trace_first_res
      end if
   end subroutine update_quasi_trace_gate_metrics

   subroutine resolve_hmc_policy(hmc_policy, active_policy)
      implicit none
      type(hmc_policy_context_t), intent(inout), optional, target :: hmc_policy
      type(hmc_policy_context_t), pointer, intent(out) :: active_policy

      if (present(hmc_policy)) then
         active_policy => hmc_policy
      else
         active_policy => module_hmc_policy_context
      end if
   end subroutine resolve_hmc_policy

   subroutine resolve_hmc_replay_runtime(hmc_replay_runtime, active_runtime)
      implicit none
      type(hmc_replay_runtime_context_t), intent(inout), optional, target :: hmc_replay_runtime
      type(hmc_replay_runtime_context_t), pointer, intent(out) :: active_runtime

      if (present(hmc_replay_runtime)) then
         active_runtime => hmc_replay_runtime
      else
         active_runtime => module_hmc_replay_runtime_context
      end if
   end subroutine resolve_hmc_replay_runtime

   subroutine resolve_hmc_replay_diagnostics(hmc_replay_diagnostics, active_diagnostics)
      implicit none
      type(hmc_replay_diagnostics_context_t), intent(inout), optional, target :: hmc_replay_diagnostics
      type(hmc_replay_diagnostics_context_t), pointer, intent(out) :: active_diagnostics

      if (present(hmc_replay_diagnostics)) then
         active_diagnostics => hmc_replay_diagnostics
      else
         active_diagnostics => module_hmc_replay_diagnostics_context
      end if
   end subroutine resolve_hmc_replay_diagnostics

   subroutine load_s1_fallback_policy(hmc_policy)
      implicit none
      type(hmc_policy_context_t), intent(inout) :: hmc_policy
      character(len=64) :: env_value
      logical :: env_present
      integer :: parsed_value, ios

      if (hmc_policy%s1_fallback_policy_loaded) return
      hmc_policy%s1_fallback_policy_loaded = .true.
      hmc_policy%s1_probe_max_iter = s1_probe_max_iter_default
      hmc_policy%s1_near_full_max_iter = s1_near_full_max_iter_default
      hmc_policy%s1_non_near_cheap_full_max_iter = s1_non_near_cheap_full_max_iter_default
      hmc_policy%s1_near_rescue_enabled = .false.
      hmc_policy%s1_nonnear_rescue_enabled = .false.
      hmc_policy%qn_reverse_gate_enabled = .false.
      hmc_policy%qn_reverse_gate_tol = qn_reverse_gate_tol_default
      hmc_policy%qn_quasi_tol_override = -1.0_dp


      call read_string_env("QN_S1_PROBE_MAX_ITER", env_value, env_present)
      if (env_present) then
         read (env_value, *, iostat=ios) parsed_value
         if (ios == 0 .and. parsed_value >= 1) then
            hmc_policy%s1_probe_max_iter = parsed_value
         else
            write (*, '(A)') "[WARN] Invalid QN_S1_PROBE_MAX_ITER; using default 28."
         end if
      end if

      call read_string_env("QN_S1_NEAR_FULL_MAX_ITER", env_value, env_present)
      if (env_present) then
         read (env_value, *, iostat=ios) parsed_value
         if (ios == 0 .and. parsed_value >= 1) then
            hmc_policy%s1_near_full_max_iter = parsed_value
         else
            write (*, '(A)') "[WARN] Invalid QN_S1_NEAR_FULL_MAX_ITER; using default 100."
         end if
      end if

      call read_string_env("QN_S1_NONNEAR_CHEAP_MAX_ITER", env_value, env_present)
      if (env_present) then
         read (env_value, *, iostat=ios) parsed_value
         if (ios == 0 .and. parsed_value >= 1) then
            hmc_policy%s1_non_near_cheap_full_max_iter = parsed_value
         else
            write (*, '(A)') "[WARN] Invalid QN_S1_NONNEAR_CHEAP_MAX_ITER; using default 36."
         end if
      end if

      call read_string_env("QN_S1_NONNEAR_RESCUE_ENABLED", env_value, env_present)
      if (env_present) then
         select case (trim(adjustl(env_value)))
         case ("0", "false", "FALSE", "False", "off", "OFF", "Off", "no", "NO", "No")
            hmc_policy%s1_nonnear_rescue_enabled = .false.
         case default
            hmc_policy%s1_nonnear_rescue_enabled = .true.
         end select
      end if

      call read_string_env("QN_S1_NEAR_RESCUE_ENABLED", env_value, env_present)
      if (env_present) then
         select case (trim(adjustl(env_value)))
         case ("0", "false", "FALSE", "False", "off", "OFF", "Off", "no", "NO", "No")
            hmc_policy%s1_near_rescue_enabled = .false.
         case default
            hmc_policy%s1_near_rescue_enabled = .true.
         end select
      end if

      call read_string_env("QN_REVERSE_GATE_ENABLED", env_value, env_present)
      if (env_present) then
         select case (trim(adjustl(env_value)))
         case ("0", "false", "FALSE", "False", "off", "OFF", "Off", "no", "NO", "No")
            hmc_policy%qn_reverse_gate_enabled = .false.
         case default
            hmc_policy%qn_reverse_gate_enabled = .true.
         end select
      end if

      call read_string_env("QN_REVERSE_GATE_TOL", env_value, env_present)
      if (env_present) then
         read (env_value, *, iostat=ios) hmc_policy%qn_reverse_gate_tol
         if (ios /= 0 .or. hmc_policy%qn_reverse_gate_tol <= 0.0_dp) then
            hmc_policy%qn_reverse_gate_tol = qn_reverse_gate_tol_default
            write (*, '(A)') "[WARN] Invalid QN_REVERSE_GATE_TOL; using default 1e-8."
         end if
      end if

      call read_string_env("QN_QUASI_TOL_OVERRIDE", env_value, env_present)
      if (env_present) then
         read (env_value, *, iostat=ios) hmc_policy%qn_quasi_tol_override
         if (ios /= 0 .or. hmc_policy%qn_quasi_tol_override <= 0.0_dp) then
            hmc_policy%qn_quasi_tol_override = -1.0_dp
            write (*, '(A)') "[WARN] Invalid QN_QUASI_TOL_OVERRIDE; using cttol."
         end if
      end if

      write (*, *) "[INFO] s1 fallback controls: probe_iter=", hmc_policy%s1_probe_max_iter, &
         " near_full_iter=", hmc_policy%s1_near_full_max_iter, &
         " nonnear_cheap_iter=", hmc_policy%s1_non_near_cheap_full_max_iter, &
         " near_rescue_enabled=", hmc_policy%s1_near_rescue_enabled, &
         " nonnear_rescue_enabled=", hmc_policy%s1_nonnear_rescue_enabled, &
         " reverse_gate_enabled=", hmc_policy%qn_reverse_gate_enabled, &
         " reverse_gate_tol=", hmc_policy%qn_reverse_gate_tol, &
         " quasi_tol_override=", hmc_policy%qn_quasi_tol_override
   end subroutine load_s1_fallback_policy

   real(dp) function max_abs_real_local(vals) result(out)
      implicit none
      real(dp), intent(in) :: vals(:)

      if (size(vals) <= 0) then
         out = 0.0_dp
      else
         out = maxval(abs(vals))
      end if
   end function max_abs_real_local

   real(dp) function max_abs_complex_local(vals) result(out)
      implicit none
      complex(dp), intent(in) :: vals(:)

      if (size(vals) <= 0) then
         out = 0.0_dp
      else
         out = maxval(abs(vals))
      end if
   end function max_abs_complex_local

end module hmc_integrator_core

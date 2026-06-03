module wv_hmc_app_common
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use, intrinsic :: iso_fortran_env, only: int64
   use model_observables, only: get_model_observable_name, model_observable_count
   use param_mod, only: config, read_parameters, set_derivative_mode
   use runtime_env_mod, only: parse_int_env, parse_logical_env, parse_real_env, read_string_env, to_lower_ascii
   use solve_flow, only: intode_status_unknown
   use tltm_rng, only: tltm_rng_domain_wv_hmc_init, tltm_rng_fill_normal, tltm_rng_uniform
   use utils, only: dp
   use wv_hmc_constraints, only: wv_boundary_policy_name, wv_newton_trace_context_t, wv_set_boundary_policy, &
                                 wv_set_newton_large_residual_stop
   use wv_hmc_driver, only: wv_dense_chain_summary_t, wv_run_dense_chain
   use wv_hmc_measurement, only: wv_dense_measurement_factor, wv_init_weighted_observable_accumulator, &
                                 wv_measurement_factor_t, wv_weighted_observable_accumulator_t, &
                                 wv_weighted_observable_estimates
   use wv_hmc_potential, only: wv_potential_paper_wall, wv_potential_polynomial, wv_potential_profile_t, &
                               wv_potential_value_and_derivative, wv_potential_zero
   implicit none

   private
   public :: run_wv_hmc_env_app

contains

   subroutine run_wv_hmc_env_app(app_label, env_prefix, default_cycle_count, default_flow_time, &
                                 default_summary_file, default_observable_file, default_write_files)
      character(len=*), intent(in) :: app_label, env_prefix, default_summary_file, default_observable_file
      integer, intent(in) :: default_cycle_count
      real(dp), intent(in) :: default_flow_time
      logical, intent(in) :: default_write_files

      integer :: n, num_steps, cycle_count, base_seed, status, observable_count, measurement_start_cycle
      integer :: init_bank_record, init_bank_selected_record, init_bank_record_count, constraint_max_iter
      integer :: large_residual_min_iter, large_residual_patience
      integer :: newton_trace_unit, observable_history_unit, x_history_unit, state_history_unit, history_stride
      integer :: snapshot_index_unit, snapshot_interval, snapshot_slots
      real(dp) :: step_size, flow_time, sampler_t0, sampler_t1, d0, d1, measurement_t0, measurement_t1
      real(dp) :: final_w_value, final_wprime
      real(dp) :: w_gamma, w_c0, w_c1, reverse_gate_state_tol, reverse_gate_momentum_tol, init_sigma
      real(dp) :: constraint_tol, large_residual_threshold, large_residual_min_rel_improvement
      real(dp) :: flow_time_out
      real(dp), allocatable :: x(:), x_out(:)
      complex(dp), allocatable :: z_out(:), jac_out(:, :)
      logical :: error, adaptive_newton_stop_enabled, large_residual_stop_enabled
      logical :: has_summary_file, has_observable_file, has_w_profile, has_init_mode, has_init_bank_file
      logical :: found_summary_file, found_observable_file, has_newton_trace_file, has_final_state_file
      logical :: has_observable_history_file, has_x_history_file, has_state_history_file
      logical :: has_snapshot_prefix, has_snapshot_index_file
      logical :: has_boundary_policy
      character(len=512) :: summary_file, observable_file, final_state_file
      character(len=512) :: init_bank_file, newton_trace_file, observable_history_file, x_history_file, state_history_file
      character(len=512) :: snapshot_prefix, snapshot_index_file
      character(len=64) :: w_profile_name, init_mode_name, boundary_policy_name
      type(wv_dense_chain_summary_t) :: summary
      type(wv_measurement_factor_t) :: measurement_factor
      type(wv_potential_profile_t) :: potential
      type(wv_weighted_observable_accumulator_t) :: observable_accumulator
      type(wv_newton_trace_context_t) :: newton_trace_context
      complex(dp), allocatable :: observable_estimates(:)

      call read_parameters()
      call set_derivative_mode("manual")

      n = config%state%physical_size
      if (n <= 0) then
         write (*, '(A)') "ERROR invalid_physical_state_size"
         stop 2
      end if

      step_size = 5.0e-5_dp
      num_steps = 1
      cycle_count = default_cycle_count
      base_seed = 20260529
      flow_time = default_flow_time
      measurement_start_cycle = 1
      sampler_t0 = 0.0_dp
      sampler_t1 = 0.2_dp
      d0 = 0.0_dp
      d1 = 0.0_dp
      w_gamma = 0.0_dp
      w_c0 = 1.0_dp
      w_c1 = 1.0_dp
      reverse_gate_state_tol = 1.0e-6_dp
      reverse_gate_momentum_tol = 1.0e-4_dp
      constraint_tol = 1.0e-10_dp
      constraint_max_iter = 48
      adaptive_newton_stop_enabled = .false.
      large_residual_stop_enabled = .false.
      large_residual_threshold = 1.0e-4_dp
      large_residual_min_iter = 8
      large_residual_patience = 4
      large_residual_min_rel_improvement = 5.0e-4_dp
      init_sigma = 0.8_dp
      init_bank_file = ""
      newton_trace_file = ""
      final_state_file = ""
      newton_trace_unit = 0
      observable_history_file = ""
      x_history_file = ""
      state_history_file = ""
      snapshot_prefix = ""
      snapshot_index_file = ""
      observable_history_unit = 0
      x_history_unit = 0
      state_history_unit = 0
      snapshot_index_unit = 0
      history_stride = 1
      snapshot_interval = 0
      snapshot_slots = 1
      init_bank_record = -1
      init_bank_selected_record = -1
      init_bank_record_count = 0
      w_profile_name = "zero"
      init_mode_name = "deterministic"
      boundary_policy_name = "paper_full_flip"
      call parse_real_env(env_name(env_prefix, "STEP_SIZE"), step_size)
      call parse_int_env(env_name(env_prefix, "NUM_STEPS"), num_steps)
      call parse_int_env(env_name(env_prefix, "CYCLES"), cycle_count)
      call parse_int_env(env_name(env_prefix, "BASE_SEED"), base_seed)
      call parse_int_env(env_name(env_prefix, "MEASUREMENT_START_CYCLE"), measurement_start_cycle)
      call parse_real_env(env_name(env_prefix, "FLOW_TIME"), flow_time)
      call parse_real_env(env_name(env_prefix, "T0"), sampler_t0)
      call parse_real_env(env_name(env_prefix, "T1"), sampler_t1)
      call parse_real_env(env_name(env_prefix, "D0"), d0)
      call parse_real_env(env_name(env_prefix, "D1"), d1)
      call read_string_env(env_name(env_prefix, "W_PROFILE"), w_profile_name, has_w_profile)
      w_profile_name = to_lower_ascii(adjustl(w_profile_name))
      call read_string_env(env_name(env_prefix, "INIT_MODE"), init_mode_name, has_init_mode)
      init_mode_name = to_lower_ascii(adjustl(init_mode_name))
      call read_string_env(env_name(env_prefix, "BOUNDARY_POLICY"), boundary_policy_name, has_boundary_policy)
      boundary_policy_name = to_lower_ascii(adjustl(boundary_policy_name))
      call wv_set_boundary_policy(trim(boundary_policy_name), error)
      if (error) then
         write (*, '(*(g0,1X))') "ERROR", "invalid_wv_boundary_policy", trim(boundary_policy_name)
         stop 3
      end if
      call read_string_env(env_name(env_prefix, "INIT_BANK_FILE"), init_bank_file, has_init_bank_file)
      call parse_int_env(env_name(env_prefix, "INIT_BANK_RECORD"), init_bank_record)
      call parse_real_env(env_name(env_prefix, "W_GAMMA"), w_gamma)
      call parse_real_env(env_name(env_prefix, "W_C0"), w_c0)
      call parse_real_env(env_name(env_prefix, "W_C1"), w_c1)
      call parse_real_env(env_name(env_prefix, "INIT_SIGMA"), init_sigma)
      call parse_real_env(env_name(env_prefix, "REVERSE_GATE_STATE_TOL"), reverse_gate_state_tol)
      call parse_real_env(env_name(env_prefix, "REVERSE_GATE_MOMENTUM_TOL"), reverse_gate_momentum_tol)
      call parse_real_env(env_name(env_prefix, "CONSTRAINT_TOL"), constraint_tol)
      call parse_int_env(env_name(env_prefix, "CONSTRAINT_MAX_ITER"), constraint_max_iter)
      call parse_logical_env(env_name(env_prefix, "ADAPTIVE_NEWTON_STOP_ENABLED"), adaptive_newton_stop_enabled)
      call parse_logical_env(env_name(env_prefix, "LARGE_RESIDUAL_STOP_ENABLED"), large_residual_stop_enabled)
      call parse_real_env(env_name(env_prefix, "LARGE_RESIDUAL_THRESHOLD"), large_residual_threshold)
      call parse_int_env(env_name(env_prefix, "LARGE_RESIDUAL_MIN_ITER"), large_residual_min_iter)
      call parse_int_env(env_name(env_prefix, "LARGE_RESIDUAL_PATIENCE"), large_residual_patience)
      call parse_real_env(env_name(env_prefix, "LARGE_RESIDUAL_MIN_REL_IMPROVEMENT"), &
                          large_residual_min_rel_improvement)
      call read_string_env(env_name(env_prefix, "NEWTON_TRACE_FILE"), newton_trace_file, has_newton_trace_file)
      call parse_int_env(env_name(env_prefix, "HISTORY_STRIDE"), history_stride)
      call parse_int_env(env_name(env_prefix, "SNAPSHOT_INTERVAL"), snapshot_interval)
      call parse_int_env(env_name(env_prefix, "SNAPSHOT_SLOTS"), snapshot_slots)
      measurement_t0 = sampler_t0
      measurement_t1 = sampler_t1
      call parse_real_env(env_name(env_prefix, "MEASUREMENT_T0"), measurement_t0)
      call parse_real_env(env_name(env_prefix, "MEASUREMENT_T1"), measurement_t1)
      summary_file = default_summary_file
      observable_file = default_observable_file
      has_summary_file = default_write_files .and. len_trim(summary_file) > 0
      has_observable_file = default_write_files .and. len_trim(observable_file) > 0
      call read_string_env(env_name(env_prefix, "SUMMARY_FILE"), summary_file, found_summary_file)
      call read_string_env(env_name(env_prefix, "OBSERVABLE_FILE"), observable_file, found_observable_file)
      call read_string_env(env_name(env_prefix, "FINAL_STATE_FILE"), final_state_file, has_final_state_file)
      call read_string_env(env_name(env_prefix, "OBSERVABLE_HISTORY_FILE"), observable_history_file, has_observable_history_file)
      call read_string_env(env_name(env_prefix, "X_HISTORY_FILE"), x_history_file, has_x_history_file)
      call read_string_env(env_name(env_prefix, "STATE_HISTORY_FILE"), state_history_file, has_state_history_file)
      call read_string_env(env_name(env_prefix, "SNAPSHOT_PREFIX"), snapshot_prefix, has_snapshot_prefix)
      call read_string_env(env_name(env_prefix, "SNAPSHOT_INDEX_FILE"), snapshot_index_file, has_snapshot_index_file)
      if (found_summary_file) has_summary_file = .true.
      if (found_observable_file) has_observable_file = .true.

      allocate (x(n), x_out(n), z_out(n), jac_out(n, n))
      call fill_initial_state(x, flow_time, trim(init_mode_name), init_sigma, base_seed, trim(init_bank_file), &
                              init_bank_record, init_bank_selected_record, init_bank_record_count, error)
      if (error) then
         write (*, '(*(g0,1X))') "ERROR", "invalid_initial_state", trim(init_mode_name), init_sigma, &
            trim(init_bank_file), init_bank_record
         stop 3
      end if
      write (*, '(*(g0,1X))') "WV_HMC_INIT", "base_seed", base_seed, "init_mode", trim(init_mode_name), &
         "flow_time", flow_time, "init_bank_file", trim(init_bank_file), &
         "init_bank_record_request", init_bank_record, "init_bank_record", init_bank_selected_record, &
         "init_bank_record_count", init_bank_record_count
      observable_count = model_observable_count()
      allocate (observable_estimates(observable_count))
      call wv_init_weighted_observable_accumulator(observable_accumulator, observable_count, error)
      if (error) then
         write (*, '(A)') "ERROR observable_accumulator_init_failed"
         stop 3
      end if
      call build_potential(trim(w_profile_name), sampler_t0, sampler_t1, d0, d1, w_gamma, w_c0, w_c1, potential, error)
      if (error) then
         write (*, '(*(g0,1X))') "ERROR", "invalid_w_profile", trim(w_profile_name), &
            "sampler_t0", sampler_t0, "sampler_t1", sampler_t1, "d0", d0, "d1", d1, &
            "gamma", w_gamma, "c0", w_c0, "c1", w_c1
         stop 3
      end if
      if ((.not. ieee_is_finite(constraint_tol)) .or. constraint_tol <= 0.0_dp .or. constraint_max_iter < 0) then
         write (*, '(*(g0,1X))') "ERROR", "invalid_wv_newton_controls", constraint_tol, constraint_max_iter
         stop 3
      end if
      if (large_residual_stop_enabled) then
         if ((.not. ieee_is_finite(large_residual_threshold)) .or. large_residual_threshold <= constraint_tol .or. &
             large_residual_min_iter < 1 .or. large_residual_patience < 1 .or. &
             (.not. ieee_is_finite(large_residual_min_rel_improvement)) .or. &
             large_residual_min_rel_improvement < 0.0_dp) then
            write (*, '(*(g0,1X))') "ERROR", "invalid_wv_large_residual_controls", &
               large_residual_threshold, large_residual_min_iter, large_residual_patience, &
               large_residual_min_rel_improvement
            stop 3
         end if
      end if
      call wv_set_newton_large_residual_stop(large_residual_stop_enabled, large_residual_threshold, &
                                             large_residual_min_iter, large_residual_patience, &
                                             large_residual_min_rel_improvement)
      if (history_stride < 1) then
         write (*, '(*(g0,1X))') "ERROR", "invalid_wv_history_stride", history_stride
         stop 3
      end if
      if (has_snapshot_prefix .and. len_trim(snapshot_prefix) > 0) then
         if (snapshot_interval < 1 .or. snapshot_slots < 1) then
            write (*, '(*(g0,1X))') "ERROR", "invalid_wv_snapshot_controls", snapshot_interval, snapshot_slots, &
               trim(snapshot_prefix)
            stop 3
         end if
      end if
      if (has_newton_trace_file .and. len_trim(newton_trace_file) > 0) then
         open (newunit=newton_trace_unit, file=trim(newton_trace_file), status='replace', action='write', iostat=status)
         if (status /= 0) then
            write (*, '(A,1X,A)') "ERROR cannot_write_wv_newton_trace_file", trim(newton_trace_file)
            stop 6
         end if
         write (newton_trace_unit, '(A)') &
            "solve_id,cycle,direction,step,iter,residual_norm,tol,h,u_norm,lambda_norm,stop_reason"
         newton_trace_context%unit = newton_trace_unit
      end if
      if (has_observable_history_file .and. len_trim(observable_history_file) > 0) then
         open (newunit=observable_history_unit, file=trim(observable_history_file), status='replace', action='write', &
               iostat=status)
         if (status /= 0) then
            write (*, '(A,1X,A)') "ERROR cannot_write_wv_observable_history_file", trim(observable_history_file)
            stop 6
         end if
         call write_observable_history_header(observable_history_unit, observable_count)
      end if
      if (has_x_history_file .and. len_trim(x_history_file) > 0) then
         open (newunit=x_history_unit, file=trim(x_history_file), status='replace', access='stream', form='unformatted', &
               action='write', iostat=status)
         if (status /= 0) then
            write (*, '(A,1X,A)') "ERROR cannot_write_wv_x_history_file", trim(x_history_file)
            if (observable_history_unit /= 0) close (observable_history_unit)
            stop 6
         end if
      end if
      if (has_state_history_file .and. len_trim(state_history_file) > 0) then
         open (newunit=state_history_unit, file=trim(state_history_file), status='replace', access='stream', &
               form='unformatted', action='write', iostat=status)
         if (status /= 0) then
            write (*, '(A,1X,A)') "ERROR cannot_write_wv_state_history_file", trim(state_history_file)
            if (observable_history_unit /= 0) close (observable_history_unit)
            if (x_history_unit /= 0) close (x_history_unit)
            stop 6
         end if
      end if
      if (has_snapshot_prefix .and. len_trim(snapshot_prefix) > 0 .and. &
          has_snapshot_index_file .and. len_trim(snapshot_index_file) > 0) then
         open (newunit=snapshot_index_unit, file=trim(snapshot_index_file), status='replace', action='write', &
               iostat=status)
         if (status /= 0) then
            write (*, '(A,1X,A)') "ERROR cannot_write_wv_snapshot_index_file", trim(snapshot_index_file)
            if (observable_history_unit /= 0) close (observable_history_unit)
            if (x_history_unit /= 0) close (x_history_unit)
            if (state_history_unit /= 0) close (state_history_unit)
            stop 6
         end if
         write (snapshot_index_unit, '(A)') "cycle,slot,flow_time,path"
      end if

      status = intode_status_unknown
      call wv_run_dense_chain(base_seed, cycle_count, step_size, num_steps, potential, sampler_t0, sampler_t1, d0, d1, &
                              flow_time, x, flow_time_out, x_out, z_out, jac_out, summary, error, status, &
                              observable_accumulator=observable_accumulator, measurement_t0=measurement_t0, &
                              measurement_t1=measurement_t1, reverse_gate_state_tol=reverse_gate_state_tol, &
                              reverse_gate_momentum_tol=reverse_gate_momentum_tol, &
                              measurement_start_cycle=measurement_start_cycle, constraint_tol=constraint_tol, &
                              constraint_max_iter=constraint_max_iter, &
                              adaptive_stop_enabled=adaptive_newton_stop_enabled, &
                              newton_trace_context=newton_trace_context, &
                              observable_history_unit=observable_history_unit, x_history_unit=x_history_unit, &
                              state_history_unit=state_history_unit, history_stride=history_stride, &
                              snapshot_prefix=snapshot_prefix, snapshot_interval=snapshot_interval, &
                              snapshot_slots=snapshot_slots, snapshot_index_unit=snapshot_index_unit)
      if (newton_trace_unit /= 0) close (newton_trace_unit)
      if (observable_history_unit /= 0) close (observable_history_unit)
      if (x_history_unit /= 0) close (x_history_unit)
      if (state_history_unit /= 0) close (state_history_unit)
      if (snapshot_index_unit /= 0) close (snapshot_index_unit)
      if (error) then
         write (*, '(*(g0,1X))') "ERROR", "dense_chain_failed", "status", status, &
            "cycles_attempted", summary%cycles_attempted, &
            "cycles_completed", summary%cycles_completed, &
            "transitions_failed", summary%transitions_failed, &
            "last_attempted_steps", summary%last_attempted_steps, &
            "last_completed_steps", summary%last_completed_steps, &
            "last_constraint_residual", summary%last_constraint_residual, &
            "last_projection_alpha2", summary%last_projection_alpha2, &
            "last_projection_rejected_norm", summary%last_projection_rejected_norm, &
            "odex_calls", summary%odex_calls, &
            "odex_failure", summary%odex_failure
         stop 3
      end if
      call wv_weighted_observable_estimates(observable_accumulator, observable_estimates, error)
      if (error) then
         write (*, '(*(g0,1X))') "ERROR", "observable_estimate_failed", &
            "measurement_attempted", summary%measurement_attempted, &
            "measurement_included", summary%measurement_included, &
            "measurement_skipped", summary%measurement_skipped, &
            "measurement_failed", summary%measurement_failed
         stop 4
      end if
      call wv_potential_value_and_derivative(potential, flow_time_out, final_w_value, final_wprime, error)
      if (.not. error) call wv_dense_measurement_factor(z_out, jac_out, measurement_factor, error, w_value=final_w_value)
      if (error) then
         write (*, '(*(g0,1X))') "ERROR", "measurement_factor_failed", "status", status, &
            "cycles_completed", summary%cycles_completed
         stop 4
      end if

      write (*, '(*(g0,1X))') trim(app_label), &
         "status", status, &
         "base_seed", base_seed, &
         "cycles_requested", summary%cycles_requested, &
         "cycles_completed", summary%cycles_completed, &
         "accepted", summary%accepted, &
         "rejected", summary%rejected, &
         "metropolis_rejected", summary%metropolis_rejected, &
         "transitions_failed", summary%transitions_failed, &
         "reverse_gate_rejected", summary%reverse_gate_rejected, &
         "accept_probability_mean", safe_ratio(summary%accept_probability_sum, summary%cycles_completed), &
         "delta_hamiltonian_mean", safe_ratio(summary%delta_hamiltonian_sum, summary%cycles_completed), &
         "flow_time_in", flow_time, &
         "flow_time_out", flow_time_out, &
         "flow_time_min", summary%flow_time_min, &
         "flow_time_max", summary%flow_time_max, &
         "flow_time_mean", safe_ratio(summary%flow_time_sum, summary%flow_time_observations), &
         "flow_time_observations", summary%flow_time_observations, &
         "sampler_t0", sampler_t0, &
         "sampler_t1", sampler_t1, &
         "sampler_d0", d0, &
         "sampler_d1", d1, &
         "w_profile", trim(w_profile_name), &
         "boundary_policy", trim(wv_boundary_policy_name()), &
         "init_mode", trim(init_mode_name), &
         "init_sigma", init_sigma, &
         "init_bank_file", trim(init_bank_file), &
         "init_bank_record", init_bank_selected_record, &
         "init_bank_record_count", init_bank_record_count, &
         "w_gamma", w_gamma, &
         "w_c0", w_c0, &
         "w_c1", w_c1, &
         "reverse_gate_state_tol", reverse_gate_state_tol, &
         "reverse_gate_momentum_tol", reverse_gate_momentum_tol, &
         "constraint_tol", constraint_tol, &
         "constraint_max_iter", constraint_max_iter, &
         "adaptive_newton_stop_enabled", adaptive_newton_stop_enabled, &
         "large_residual_stop_enabled", large_residual_stop_enabled, &
         "large_residual_threshold", large_residual_threshold, &
         "large_residual_min_iter", large_residual_min_iter, &
         "large_residual_patience", large_residual_patience, &
         "large_residual_min_rel_improvement", large_residual_min_rel_improvement, &
         "newton_trace_file", trim(newton_trace_file), &
         "history_stride", history_stride, &
         "observable_history_file", trim(observable_history_file), &
         "x_history_file", trim(x_history_file), &
         "state_history_file", trim(state_history_file), &
         "snapshot_prefix", trim(snapshot_prefix), &
         "snapshot_index_file", trim(snapshot_index_file), &
         "snapshot_interval", snapshot_interval, &
         "snapshot_slots", snapshot_slots, &
         "snapshots_written", summary%snapshots_written, &
         "snapshot_write_errors", summary%snapshot_write_errors, &
         "last_reverse_gate_state_error", summary%last_reverse_gate_state_error, &
         "last_reverse_gate_momentum_error", summary%last_reverse_gate_momentum_error, &
         "reverse_gate_checked", summary%reverse_gate_checked_count, &
         "reverse_gate_passed", summary%reverse_gate_passed_count, &
         "reverse_gate_failed", summary%reverse_gate_failed_count, &
         "reverse_gate_error_samples", summary%reverse_gate_error_sample_count, &
         "reverse_gate_state_error_mean", safe_ratio(summary%reverse_gate_state_error_sum, &
                                                     summary%reverse_gate_error_sample_count), &
         "reverse_gate_momentum_error_mean", safe_ratio(summary%reverse_gate_momentum_error_sum, &
                                                        summary%reverse_gate_error_sample_count), &
         "reverse_gate_state_error_max", summary%reverse_gate_state_error_max, &
         "reverse_gate_momentum_error_max", summary%reverse_gate_momentum_error_max, &
         "trajectory_steps", summary%trajectory_steps, &
         "bounced_steps", summary%bounced_steps, &
         "solver_iterations", summary%solver_iterations_total, &
         "reverse_trajectory_steps", summary%reverse_trajectory_steps, &
         "reverse_solver_iterations", summary%reverse_solver_iterations_total, &
         "last_solver_stop_reason", summary%last_solver_stop_reason, &
         "last_reverse_solver_stop_reason", summary%last_reverse_solver_stop_reason, &
         "solver_stop_converged", summary%solver_stop_converged_count, &
         "solver_stop_max_iter", summary%solver_stop_max_iter_count, &
         "solver_stop_divergence", summary%solver_stop_divergence_count, &
         "solver_stop_stagnation", summary%solver_stop_stagnation_count, &
         "solver_stop_not_run", summary%solver_stop_not_run_count, &
         "solver_stop_boundary_exit", summary%solver_stop_boundary_exit_count, &
         "solver_stop_large_residual", summary%solver_stop_large_residual_count, &
         "solver_stop_failure", summary%solver_stop_failure_count, &
         "reverse_solver_stop_converged", summary%reverse_solver_stop_converged_count, &
         "reverse_solver_stop_max_iter", summary%reverse_solver_stop_max_iter_count, &
         "reverse_solver_stop_divergence", summary%reverse_solver_stop_divergence_count, &
         "reverse_solver_stop_stagnation", summary%reverse_solver_stop_stagnation_count, &
         "reverse_solver_stop_not_run", summary%reverse_solver_stop_not_run_count, &
         "reverse_solver_stop_boundary_exit", summary%reverse_solver_stop_boundary_exit_count, &
         "reverse_solver_stop_large_residual", summary%reverse_solver_stop_large_residual_count, &
         "reverse_solver_stop_failure", summary%reverse_solver_stop_failure_count, &
         "max_constraint_residual", summary%max_constraint_residual, &
         "reverse_max_constraint_residual", summary%reverse_max_constraint_residual, &
         "measurement_t0", measurement_t0, &
         "measurement_t1", measurement_t1, &
         "measurement_start_cycle", measurement_start_cycle, &
         "measurement_attempted", summary%measurement_attempted, &
         "measurement_included", summary%measurement_included, &
         "measurement_skipped", summary%measurement_skipped, &
         "measurement_failed", summary%measurement_failed, &
         "measurement_phase_coherence", summary%measurement_phase_coherence, &
         "wv_denominator_re", real(observable_accumulator%denominator, dp), &
         "wv_denominator_im", aimag(observable_accumulator%denominator), &
         "wv_sum_abs_weight", observable_accumulator%sum_abs_weight, &
         "odex_calls", summary%odex_calls, &
         "odex_failure", summary%odex_failure, &
         "alpha", measurement_factor%alpha, &
         "alpha2", measurement_factor%alpha2, &
         "phase_re", real(measurement_factor%phase_factor, dp), &
         "phase_im", aimag(measurement_factor%phase_factor), &
         "wv_factor_re", real(measurement_factor%wv_factor, dp), &
         "wv_factor_im", aimag(measurement_factor%wv_factor)

      if (has_summary_file) call write_summary_file(trim(summary_file), base_seed, flow_time, flow_time_out, summary, &
                                                    measurement_factor, observable_accumulator, sampler_t0, sampler_t1, &
                                                    d0, d1, trim(w_profile_name), w_gamma, w_c0, w_c1, &
                                                    measurement_t0, measurement_t1, measurement_start_cycle, &
                                                    reverse_gate_state_tol, reverse_gate_momentum_tol, constraint_tol, &
                                                    constraint_max_iter, adaptive_newton_stop_enabled, &
                                                    large_residual_stop_enabled, large_residual_threshold, &
                                                    large_residual_min_iter, large_residual_patience, &
                                                    large_residual_min_rel_improvement, &
                                                    trim(newton_trace_file), trim(init_mode_name), trim(init_bank_file), &
                                                    init_bank_record, init_bank_selected_record, init_bank_record_count, &
                                                    trim(snapshot_prefix), trim(snapshot_index_file), &
                                                    snapshot_interval, snapshot_slots)
      if (has_observable_file) call write_observable_file(trim(observable_file), observable_estimates)
      if (has_final_state_file .and. len_trim(final_state_file) > 0) call write_final_state_file(trim(final_state_file), &
                                                                                                  flow_time_out, x_out)
   end subroutine run_wv_hmc_env_app

   pure function env_name(prefix, suffix) result(name)
      character(len=*), intent(in) :: prefix, suffix
      character(len=128) :: name

      name = trim(prefix)//"_"//trim(suffix)
   end function env_name

   subroutine fill_deterministic_x(x_values)
      real(dp), intent(out) :: x_values(:)
      integer :: i

      do i = 1, size(x_values)
         x_values(i) = 0.02_dp + 0.001_dp*real(i, dp)
      end do
   end subroutine fill_deterministic_x

   subroutine fill_initial_state(x_values, flow_time_value, init_mode, init_sigma, base_seed, init_bank_file, &
                                 init_bank_record_request, init_bank_selected_record, init_bank_record_count, error)
      real(dp), intent(out) :: x_values(:)
      real(dp), intent(inout) :: flow_time_value
      character(len=*), intent(in) :: init_mode, init_bank_file
      real(dp), intent(in) :: init_sigma
      integer, intent(in) :: base_seed, init_bank_record_request
      integer, intent(out) :: init_bank_selected_record, init_bank_record_count
      logical, intent(out) :: error

      error = .true.
      init_bank_selected_record = -1
      init_bank_record_count = 0
      x_values = 0.0_dp
      select case (trim(init_mode))
      case ("deterministic")
         call fill_deterministic_x(x_values)
      case ("zero")
         x_values = 0.0_dp
      case ("random_gaussian", "gaussian")
         if ((.not. ieee_is_finite(init_sigma)) .or. init_sigma < 0.0_dp) return
         call tltm_rng_fill_normal(x_values, tltm_rng_domain_wv_hmc_init, base_seed, 0, 1, 1)
         x_values = init_sigma*x_values
      case ("bank", "x_bank", "checkpoint_bank")
         call fill_bank_initial_x(x_values, trim(init_bank_file), init_bank_record_request, base_seed, &
                                  init_bank_selected_record, init_bank_record_count, error)
         return
      case ("state_bank", "wv_state_bank")
         call fill_state_bank_initial_state(flow_time_value, x_values, trim(init_bank_file), init_bank_record_request, &
                                            base_seed, init_bank_selected_record, init_bank_record_count, error)
         return
      case default
         return
      end select
      if (any(.not. ieee_is_finite(x_values))) return
      if ((.not. ieee_is_finite(flow_time_value)) .or. flow_time_value < 0.0_dp) return
      error = .false.
   end subroutine fill_initial_state

   subroutine fill_bank_initial_x(x_values, init_bank_file, init_bank_record_request, base_seed, selected_record, &
                                  record_count, error)
      real(dp), intent(out) :: x_values(:)
      character(len=*), intent(in) :: init_bank_file
      integer, intent(in) :: init_bank_record_request, base_seed
      integer, intent(out) :: selected_record, record_count
      logical, intent(out) :: error

      logical :: ok
      real(dp) :: draw

      error = .true.
      selected_record = -1
      record_count = 0
      if (len_trim(init_bank_file) == 0) then
         write (*, '(A)') "ERROR wv_init_bank_file_missing"
         return
      end if

      call count_x_bank_records(trim(init_bank_file), size(x_values), record_count, ok)
      if (.not. ok) return
      if (init_bank_record_request >= 0) then
         selected_record = init_bank_record_request
         if (selected_record >= record_count) then
            write (*, '(*(g0,1X))') "ERROR", "wv_init_bank_record_out_of_range", selected_record, record_count
            return
         end if
      else
         draw = tltm_rng_uniform(tltm_rng_domain_wv_hmc_init, base_seed, 0, 1, 2, 1)
         selected_record = int(floor(draw*real(record_count, dp)))
         selected_record = max(0, min(record_count - 1, selected_record))
      end if

      call load_x_bank_record(trim(init_bank_file), selected_record, x_values, ok)
      if (.not. ok) return
      error = .false.
   end subroutine fill_bank_initial_x

   subroutine fill_state_bank_initial_state(flow_time_value, x_values, init_bank_file, init_bank_record_request, base_seed, &
                                            selected_record, record_count, error)
      real(dp), intent(out) :: flow_time_value
      real(dp), intent(out) :: x_values(:)
      character(len=*), intent(in) :: init_bank_file
      integer, intent(in) :: init_bank_record_request, base_seed
      integer, intent(out) :: selected_record, record_count
      logical, intent(out) :: error

      logical :: ok
      real(dp) :: draw

      error = .true.
      selected_record = -1
      record_count = 0
      flow_time_value = 0.0_dp
      x_values = 0.0_dp
      if (len_trim(init_bank_file) == 0) then
         write (*, '(A)') "ERROR wv_init_state_bank_file_missing"
         return
      end if

      call count_state_bank_records(trim(init_bank_file), size(x_values), record_count, ok)
      if (.not. ok) return
      if (init_bank_record_request >= 0) then
         selected_record = init_bank_record_request
         if (selected_record >= record_count) then
            write (*, '(*(g0,1X))') "ERROR", "wv_init_state_bank_record_out_of_range", selected_record, record_count
            return
         end if
      else
         draw = tltm_rng_uniform(tltm_rng_domain_wv_hmc_init, base_seed, 0, 1, 2, 1)
         selected_record = int(floor(draw*real(record_count, dp)))
         selected_record = max(0, min(record_count - 1, selected_record))
      end if

      call load_state_bank_record(trim(init_bank_file), selected_record, flow_time_value, x_values, ok)
      if (.not. ok) return
      error = .false.
   end subroutine fill_state_bank_initial_state

   subroutine count_x_bank_records(init_bank_file, state_size, record_count, ok)
      character(len=*), intent(in) :: init_bank_file
      integer, intent(in) :: state_size
      integer, intent(out) :: record_count
      logical, intent(out) :: ok

      integer :: ios
      integer(int64) :: file_size, record_bytes, count64

      ok = .false.
      record_count = 0
      if (state_size <= 0) return
      inquire (file=trim(init_bank_file), size=file_size, iostat=ios)
      if (ios /= 0 .or. file_size <= 0_int64) then
         write (*, '(A,1X,A)') "ERROR cannot_stat_wv_init_bank_file", trim(init_bank_file)
         return
      end if
      record_bytes = int(state_size, int64)*8_int64
      if (mod(file_size, record_bytes) /= 0_int64) then
         write (*, '(*(g0,1X))') "ERROR", "wv_init_bank_size_mismatch", trim(init_bank_file), file_size, record_bytes
         return
      end if
      count64 = file_size/record_bytes
      if (count64 < 1_int64 .or. count64 > int(huge(record_count), int64)) then
         write (*, '(*(g0,1X))') "ERROR", "wv_init_bank_record_count_invalid", trim(init_bank_file), count64
         return
      end if
      record_count = int(count64)
      ok = .true.
   end subroutine count_x_bank_records

   subroutine count_state_bank_records(init_bank_file, state_size, record_count, ok)
      character(len=*), intent(in) :: init_bank_file
      integer, intent(in) :: state_size
      integer, intent(out) :: record_count
      logical, intent(out) :: ok

      integer :: ios
      integer(int64) :: file_size, record_bytes, count64

      ok = .false.
      record_count = 0
      if (state_size <= 0) return
      inquire (file=trim(init_bank_file), size=file_size, iostat=ios)
      if (ios /= 0 .or. file_size <= 0_int64) then
         write (*, '(A,1X,A)') "ERROR cannot_stat_wv_init_state_bank_file", trim(init_bank_file)
         return
      end if
      record_bytes = int(state_size + 1, int64)*8_int64
      if (mod(file_size, record_bytes) /= 0_int64) then
         write (*, '(*(g0,1X))') "ERROR", "wv_init_state_bank_size_mismatch", trim(init_bank_file), file_size, record_bytes
         return
      end if
      count64 = file_size/record_bytes
      if (count64 < 1_int64 .or. count64 > int(huge(record_count), int64)) then
         write (*, '(*(g0,1X))') "ERROR", "wv_init_state_bank_record_count_invalid", trim(init_bank_file), count64
         return
      end if
      record_count = int(count64)
      ok = .true.
   end subroutine count_state_bank_records

   subroutine load_x_bank_record(init_bank_file, record_index, x_state, ok)
      character(len=*), intent(in) :: init_bank_file
      integer, intent(in) :: record_index
      real(dp), intent(out) :: x_state(:)
      logical, intent(out) :: ok

      integer :: unit_x, ios
      integer(int64) :: pos_bytes, record_bytes

      ok = .false.
      if (record_index < 0) then
         write (*, '(A,I0)') "ERROR invalid_wv_init_bank_record=", record_index
         return
      end if

      record_bytes = int(size(x_state), int64)*8_int64
      pos_bytes = 1_int64 + int(record_index, int64)*record_bytes
      open (newunit=unit_x, file=trim(init_bank_file), status='old', access='stream', form='unformatted', &
            action='read', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "ERROR cannot_open_wv_init_bank_file", trim(init_bank_file)
         return
      end if

      read (unit_x, pos=pos_bytes, iostat=ios) x_state
      close (unit_x)
      if (ios /= 0) then
         write (*, '(A,I0,A,1X,A)') "ERROR cannot_read_wv_init_bank_record=", record_index, "file=", trim(init_bank_file)
         return
      end if
      if (any(.not. ieee_is_finite(x_state))) then
         write (*, '(A,I0)') "ERROR nonfinite_wv_init_bank_record=", record_index
         return
      end if

      ok = .true.
   end subroutine load_x_bank_record

   subroutine load_state_bank_record(init_bank_file, record_index, flow_time_value, x_state, ok)
      character(len=*), intent(in) :: init_bank_file
      integer, intent(in) :: record_index
      real(dp), intent(out) :: flow_time_value
      real(dp), intent(out) :: x_state(:)
      logical, intent(out) :: ok

      integer :: unit_x, ios
      integer(int64) :: pos_bytes, record_bytes
      real(dp) :: packed_state(size(x_state) + 1)

      ok = .false.
      flow_time_value = 0.0_dp
      x_state = 0.0_dp
      if (record_index < 0) then
         write (*, '(A,I0)') "ERROR invalid_wv_init_state_bank_record=", record_index
         return
      end if

      record_bytes = int(size(x_state) + 1, int64)*8_int64
      pos_bytes = 1_int64 + int(record_index, int64)*record_bytes
      open (newunit=unit_x, file=trim(init_bank_file), status='old', access='stream', form='unformatted', &
            action='read', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "ERROR cannot_open_wv_init_state_bank_file", trim(init_bank_file)
         return
      end if

      read (unit_x, pos=pos_bytes, iostat=ios) packed_state
      close (unit_x)
      if (ios /= 0) then
         write (*, '(A,I0,A,1X,A)') "ERROR cannot_read_wv_init_state_bank_record=", record_index, "file=", &
            trim(init_bank_file)
         return
      end if
      flow_time_value = packed_state(1)
      x_state = packed_state(2:)
      if ((.not. ieee_is_finite(flow_time_value)) .or. flow_time_value < 0.0_dp) then
         write (*, '(A,I0)') "ERROR invalid_wv_init_state_bank_flow_time_record=", record_index
         return
      end if
      if (any(.not. ieee_is_finite(x_state))) then
         write (*, '(A,I0)') "ERROR nonfinite_wv_init_state_bank_record=", record_index
         return
      end if

      ok = .true.
   end subroutine load_state_bank_record

   pure real(dp) function safe_ratio(numerator, denominator) result(value)
      real(dp), intent(in) :: numerator
      integer, intent(in) :: denominator

      if (denominator > 0) then
         value = numerator/real(denominator, dp)
      else
         value = 0.0_dp
      end if
   end function safe_ratio

   subroutine build_potential(profile_name, local_t0, local_t1, local_d0, local_d1, local_gamma, local_c0, local_c1, &
                              profile, local_error)
      character(len=*), intent(in) :: profile_name
      real(dp), intent(in) :: local_t0, local_t1, local_d0, local_d1, local_gamma, local_c0, local_c1
      type(wv_potential_profile_t), intent(out) :: profile
      logical, intent(out) :: local_error
      real(dp) :: value, derivative

      local_error = .false.
      select case (trim(profile_name))
      case ("zero", "flat")
         profile = wv_potential_zero()
      case ("linear", "linear_gamma")
         profile = wv_potential_polynomial(local_gamma*local_t0, -local_gamma, 0.0_dp)
      case ("paper_wall")
         profile = wv_potential_paper_wall(local_t0, local_t1, local_d0, local_d1, local_gamma, local_c0, local_c1)
      case default
         profile = wv_potential_zero()
         local_error = .true.
      end select
      if (local_error) return
      call wv_potential_value_and_derivative(profile, max(local_t0, 0.0_dp), value, derivative, local_error)
   end subroutine build_potential

   subroutine write_summary_file(path, local_base_seed, local_flow_time_in, local_flow_time_out, local_summary, &
                                 local_measurement_factor, local_observable_accumulator, local_sampler_t0, local_sampler_t1, &
                                 local_sampler_d0, local_sampler_d1, local_w_profile_name, local_w_gamma, local_w_c0, &
                                 local_w_c1, local_measurement_t0, local_measurement_t1, local_measurement_start_cycle, &
                                 local_reverse_gate_state_tol, local_reverse_gate_momentum_tol, local_constraint_tol, &
                                 local_constraint_max_iter, local_adaptive_newton_stop_enabled, &
                                 local_large_residual_stop_enabled, local_large_residual_threshold, &
                                 local_large_residual_min_iter, local_large_residual_patience, &
                                 local_large_residual_min_rel_improvement, local_newton_trace_file, &
                                 local_init_mode, local_init_bank_file, local_init_bank_record_request, &
                                 local_init_bank_selected_record, local_init_bank_record_count, &
                                 local_snapshot_prefix, local_snapshot_index_file, &
                                 local_snapshot_interval, local_snapshot_slots)
      character(len=*), intent(in) :: path
      integer, intent(in) :: local_base_seed
      real(dp), intent(in) :: local_flow_time_in, local_flow_time_out
      real(dp), intent(in) :: local_sampler_t0, local_sampler_t1, local_sampler_d0, local_sampler_d1
      character(len=*), intent(in) :: local_w_profile_name
      real(dp), intent(in) :: local_w_gamma, local_w_c0, local_w_c1
      real(dp), intent(in) :: local_measurement_t0, local_measurement_t1
      real(dp), intent(in) :: local_reverse_gate_state_tol, local_reverse_gate_momentum_tol
      real(dp), intent(in) :: local_constraint_tol
      real(dp), intent(in) :: local_large_residual_threshold, local_large_residual_min_rel_improvement
      integer, intent(in) :: local_constraint_max_iter, local_large_residual_min_iter, local_large_residual_patience
      logical, intent(in) :: local_adaptive_newton_stop_enabled, local_large_residual_stop_enabled
      character(len=*), intent(in) :: local_newton_trace_file, local_init_mode, local_init_bank_file
      character(len=*), intent(in) :: local_snapshot_prefix, local_snapshot_index_file
      integer, intent(in) :: local_measurement_start_cycle
      integer, intent(in) :: local_init_bank_record_request, local_init_bank_selected_record, local_init_bank_record_count
      integer, intent(in) :: local_snapshot_interval, local_snapshot_slots
      type(wv_dense_chain_summary_t), intent(in) :: local_summary
      type(wv_measurement_factor_t), intent(in) :: local_measurement_factor
      type(wv_weighted_observable_accumulator_t), intent(in) :: local_observable_accumulator
      integer :: unit_id, ios

      open (newunit=unit_id, file=path, status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "ERROR cannot_write_summary_file", trim(path)
         stop 6
      end if
      write (unit_id, '(A)') "base_seed,cycles_requested,cycles_completed,accepted,rejected,transitions_failed,"// &
         "metropolis_rejected,reverse_gate_rejected,accept_probability_mean,delta_hamiltonian_mean,"// &
         "flow_time_in,flow_time_out,flow_time_min,flow_time_max,"// &
         "flow_time_mean,flow_time_observations,flow_time_hist_bins,flow_time_hist_low,flow_time_hist_high,"// &
         "flow_time_hist_inside,measurement_flow_time_hist_inside,accepted_jump_count,accepted_x_jump_sq_mean,"// &
         "accepted_z_jump_sq_mean,accepted_flow_time_jump_abs_mean,effective_x_jump_sq_mean,"// &
         "effective_z_jump_sq_mean,effective_flow_time_jump_abs_mean,max_x_jump_sq,max_z_jump_sq,"// &
         "max_flow_time_jump_abs,trajectory_steps,bounced_steps,"// &
         "solver_iterations,max_constraint_residual,sampler_t0,sampler_t1,sampler_d0,sampler_d1,"// &
         "init_mode,init_bank_file,init_bank_record_request,init_bank_record,init_bank_record_count,w_profile,"// &
         "boundary_policy,"// &
         "w_gamma,w_c0,w_c1,reverse_gate_state_tol,reverse_gate_momentum_tol,"// &
         "constraint_tol,constraint_max_iter,adaptive_newton_stop_enabled,"// &
         "large_residual_stop_enabled,large_residual_threshold,large_residual_min_iter,"// &
         "large_residual_patience,large_residual_min_rel_improvement,newton_trace_file,"// &
         "last_reverse_gate_state_error,last_reverse_gate_momentum_error,"// &
         "reverse_gate_checked,reverse_gate_passed,reverse_gate_failed,reverse_gate_error_samples,"// &
         "reverse_gate_state_error_mean,reverse_gate_momentum_error_mean,"// &
         "reverse_gate_state_error_max,reverse_gate_momentum_error_max,"// &
         "reverse_trajectory_steps,reverse_solver_iterations,reverse_max_constraint_residual,"// &
         "last_solver_stop_reason,last_reverse_solver_stop_reason,"// &
         "solver_stop_converged,solver_stop_max_iter,solver_stop_divergence,solver_stop_stagnation,"// &
         "solver_stop_not_run,solver_stop_boundary_exit,solver_stop_large_residual,solver_stop_failure,"// &
         "reverse_solver_stop_converged,reverse_solver_stop_max_iter,"// &
         "reverse_solver_stop_divergence,reverse_solver_stop_stagnation,reverse_solver_stop_not_run,"// &
         "reverse_solver_stop_boundary_exit,reverse_solver_stop_large_residual,reverse_solver_stop_failure,"// &
         "measurement_t0,measurement_t1,measurement_start_cycle,measurement_attempted,measurement_included,"// &
         "measurement_skipped,measurement_failed,"// &
         "measurement_phase_coherence,wv_denominator_re,wv_denominator_im,wv_sum_abs_weight,odex_calls,"// &
         "odex_failure,snapshot_prefix,snapshot_index_file,snapshot_interval,snapshot_slots,"// &
         "snapshots_written,snapshot_write_errors,"// &
         "alpha,alpha2,phase_re,phase_im,wv_factor_re,wv_factor_im"
      write (unit_id, '(*(g0,:,","))') local_base_seed, local_summary%cycles_requested, local_summary%cycles_completed, &
         local_summary%accepted, local_summary%rejected, local_summary%transitions_failed, &
         local_summary%metropolis_rejected, local_summary%reverse_gate_rejected, &
         safe_ratio(local_summary%accept_probability_sum, local_summary%cycles_completed), &
         safe_ratio(local_summary%delta_hamiltonian_sum, local_summary%cycles_completed), local_flow_time_in, &
         local_flow_time_out, local_summary%flow_time_min, local_summary%flow_time_max, &
         safe_ratio(local_summary%flow_time_sum, local_summary%flow_time_observations), &
         local_summary%flow_time_observations, size(local_summary%flow_time_hist_inside), &
         local_summary%flow_time_hist_low, local_summary%flow_time_hist_high, &
         trim(int_array_semicolon(local_summary%flow_time_hist_inside)), &
         trim(int_array_semicolon(local_summary%measurement_flow_time_hist_inside)), &
         local_summary%accepted_jump_count, &
         safe_ratio(local_summary%accepted_x_jump_sq_sum, local_summary%accepted_jump_count), &
         safe_ratio(local_summary%accepted_z_jump_sq_sum, local_summary%accepted_jump_count), &
         safe_ratio(local_summary%accepted_flow_time_jump_abs_sum, local_summary%accepted_jump_count), &
         safe_ratio(local_summary%effective_x_jump_sq_sum, local_summary%cycles_completed), &
         safe_ratio(local_summary%effective_z_jump_sq_sum, local_summary%cycles_completed), &
         safe_ratio(local_summary%effective_flow_time_jump_abs_sum, local_summary%cycles_completed), &
         local_summary%max_x_jump_sq, local_summary%max_z_jump_sq, local_summary%max_flow_time_jump_abs, &
         local_summary%trajectory_steps, local_summary%bounced_steps, &
         local_summary%solver_iterations_total, local_summary%max_constraint_residual, &
         local_sampler_t0, local_sampler_t1, local_sampler_d0, local_sampler_d1, &
         trim(local_init_mode), trim(local_init_bank_file), local_init_bank_record_request, &
         local_init_bank_selected_record, local_init_bank_record_count, trim(local_w_profile_name), &
         trim(wv_boundary_policy_name()), &
         local_w_gamma, local_w_c0, local_w_c1, &
         local_reverse_gate_state_tol, local_reverse_gate_momentum_tol, &
         local_constraint_tol, local_constraint_max_iter, local_adaptive_newton_stop_enabled, &
         local_large_residual_stop_enabled, local_large_residual_threshold, local_large_residual_min_iter, &
         local_large_residual_patience, local_large_residual_min_rel_improvement, trim(local_newton_trace_file), &
         local_summary%last_reverse_gate_state_error, local_summary%last_reverse_gate_momentum_error, &
         local_summary%reverse_gate_checked_count, local_summary%reverse_gate_passed_count, &
         local_summary%reverse_gate_failed_count, local_summary%reverse_gate_error_sample_count, &
         safe_ratio(local_summary%reverse_gate_state_error_sum, local_summary%reverse_gate_error_sample_count), &
         safe_ratio(local_summary%reverse_gate_momentum_error_sum, local_summary%reverse_gate_error_sample_count), &
         local_summary%reverse_gate_state_error_max, local_summary%reverse_gate_momentum_error_max, &
         local_summary%reverse_trajectory_steps, local_summary%reverse_solver_iterations_total, &
         local_summary%reverse_max_constraint_residual, local_summary%last_solver_stop_reason, &
         local_summary%last_reverse_solver_stop_reason, local_summary%solver_stop_converged_count, &
         local_summary%solver_stop_max_iter_count, local_summary%solver_stop_divergence_count, &
         local_summary%solver_stop_stagnation_count, local_summary%solver_stop_not_run_count, &
         local_summary%solver_stop_boundary_exit_count, local_summary%solver_stop_large_residual_count, &
         local_summary%solver_stop_failure_count, &
         local_summary%reverse_solver_stop_converged_count, &
         local_summary%reverse_solver_stop_max_iter_count, local_summary%reverse_solver_stop_divergence_count, &
         local_summary%reverse_solver_stop_stagnation_count, local_summary%reverse_solver_stop_not_run_count, &
         local_summary%reverse_solver_stop_boundary_exit_count, local_summary%reverse_solver_stop_large_residual_count, &
         local_summary%reverse_solver_stop_failure_count, &
         local_measurement_t0, local_measurement_t1, local_measurement_start_cycle, local_summary%measurement_attempted, &
         local_summary%measurement_included, local_summary%measurement_skipped, local_summary%measurement_failed, &
         local_summary%measurement_phase_coherence, real(local_observable_accumulator%denominator, dp), &
         aimag(local_observable_accumulator%denominator), local_observable_accumulator%sum_abs_weight, &
         local_summary%odex_calls, local_summary%odex_failure, trim(local_snapshot_prefix), &
         trim(local_snapshot_index_file), local_snapshot_interval, local_snapshot_slots, &
         local_summary%snapshots_written, local_summary%snapshot_write_errors, local_measurement_factor%alpha, &
         local_measurement_factor%alpha2, &
         real(local_measurement_factor%phase_factor, dp), aimag(local_measurement_factor%phase_factor), &
         real(local_measurement_factor%wv_factor, dp), aimag(local_measurement_factor%wv_factor)
      close (unit_id)
   end subroutine write_summary_file

   function int_array_semicolon(values) result(text)
      integer, intent(in) :: values(:)
      character(len=2048) :: text
      character(len=32) :: token
      integer :: idx, used, token_len

      text = ""
      used = 0
      do idx = 1, size(values)
         write (token, '(I0)') values(idx)
         token_len = len_trim(token)
         if (idx > 1) then
            if (used + 1 > len(text)) exit
            text(used + 1:used + 1) = ";"
            used = used + 1
         end if
         if (used + token_len > len(text)) exit
         text(used + 1:used + token_len) = token(1:token_len)
         used = used + token_len
      end do
   end function int_array_semicolon

   subroutine write_observable_file(path, estimates)
      character(len=*), intent(in) :: path
      complex(dp), intent(in) :: estimates(:)
      integer :: unit_id, ios, idx
      character(len=64) :: observable_name

      open (newunit=unit_id, file=path, status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "ERROR cannot_write_observable_file", trim(path)
         stop 7
      end if
      write (unit_id, '(A)') "index,name,estimate_re,estimate_im"
      do idx = 1, size(estimates)
         call get_model_observable_name(idx, observable_name)
         write (unit_id, '(I0,",",A,",",g0,",",g0)') idx, trim(observable_name), real(estimates(idx), dp), &
            aimag(estimates(idx))
      end do
      close (unit_id)
   end subroutine write_observable_file

   subroutine write_observable_history_header(unit_id, observable_count)
      integer, intent(in) :: unit_id, observable_count

      integer :: idx

      write (unit_id, '(A)', advance='no') &
         "cycle,flow_time,weight_re,weight_im,abs_weight,phase_re,phase_im,alpha,alpha2"
      do idx = 1, observable_count
         write (unit_id, '(A,I0,A,I0,A,I0,A,I0,A)', advance='no') &
            ",obs_", idx, "_re,obs_", idx, "_im,num_", idx, "_re,num_", idx, "_im"
      end do
      write (unit_id, '(A)') ""
   end subroutine write_observable_history_header

   subroutine write_final_state_file(path, flow_time_value, x_state)
      character(len=*), intent(in) :: path
      real(dp), intent(in) :: flow_time_value, x_state(:)

      integer :: unit_id, ios
      real(dp) :: packed_state(size(x_state) + 1)

      if ((.not. ieee_is_finite(flow_time_value)) .or. flow_time_value < 0.0_dp) then
         write (*, '(A,1X,A)') "ERROR invalid_wv_final_state_flow_time", trim(path)
         stop 8
      end if
      if (any(.not. ieee_is_finite(x_state))) then
         write (*, '(A,1X,A)') "ERROR nonfinite_wv_final_state", trim(path)
         stop 8
      end if

      packed_state(1) = flow_time_value
      packed_state(2:) = x_state
      open (newunit=unit_id, file=path, status='replace', access='stream', form='unformatted', action='write', &
            iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "ERROR cannot_write_final_state_file", trim(path)
         stop 8
      end if
      write (unit_id, iostat=ios) packed_state
      close (unit_id)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "ERROR failed_write_final_state_file", trim(path)
         stop 8
      end if
   end subroutine write_final_state_file

end module wv_hmc_app_common

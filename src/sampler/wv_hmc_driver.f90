module wv_hmc_driver
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use model_observables, only: evaluate_model_observables, model_observable_count
   use solve_flow, only: flow_at, flow_workspace_t, intode_diagnostics_context_t, intode_status_unknown, &
                         reset_intode_fallback_stats
   use tltm_rng, only: tltm_rng_domain_wv_hmc_accept, tltm_rng_domain_wv_hmc_momentum, tltm_rng_fill_normal, &
                       tltm_rng_uniform
   use utils, only: dp
   use wv_hmc_constraints, only: wv_newton_trace_context_t
   use wv_hmc_measurement, only: wv_accumulate_weighted_observables, wv_dense_measurement_factor, &
                                 wv_measurement_factor_t, wv_weighted_observable_accumulator_t, &
                                 wv_weighted_observable_phase_coherence
   use wv_hmc_potential, only: wv_potential_profile_t, wv_potential_value_and_derivative
   use wv_hmc_trajectory, only: wv_transition_dense, wv_transition_diagnostics_t
   implicit none

   private
   public :: wv_dense_chain_summary_t, wv_run_dense_chain
   integer, parameter :: wv_flow_hist_bins = 32

   type :: wv_dense_chain_summary_t
      integer :: cycles_requested = 0
      integer :: cycles_attempted = 0
      integer :: cycles_completed = 0
      integer :: transitions_failed = 0
      integer :: accepted = 0
      integer :: rejected = 0
      integer :: metropolis_rejected = 0
      integer :: reverse_gate_rejected = 0
      integer :: bounced_steps = 0
      integer :: buffer_exit_bounced_steps = 0
      integer :: buffer_exit_low_steps = 0
      integer :: buffer_exit_high_steps = 0
      integer :: trajectory_steps = 0
      integer :: solver_iterations_total = 0
      integer :: reverse_trajectory_steps = 0
      integer :: reverse_buffer_exit_bounced_steps = 0
      integer :: reverse_buffer_exit_low_steps = 0
      integer :: reverse_buffer_exit_high_steps = 0
      integer :: reverse_solver_iterations_total = 0
      integer :: solver_stop_converged_count = 0
      integer :: solver_stop_max_iter_count = 0
      integer :: solver_stop_divergence_count = 0
      integer :: solver_stop_stagnation_count = 0
      integer :: solver_stop_not_run_count = 0
      integer :: solver_stop_boundary_exit_count = 0
      integer :: solver_stop_large_residual_count = 0
      integer :: solver_stop_failure_count = 0
      integer :: reverse_solver_stop_converged_count = 0
      integer :: reverse_solver_stop_max_iter_count = 0
      integer :: reverse_solver_stop_divergence_count = 0
      integer :: reverse_solver_stop_stagnation_count = 0
      integer :: reverse_solver_stop_not_run_count = 0
      integer :: reverse_solver_stop_boundary_exit_count = 0
      integer :: reverse_solver_stop_large_residual_count = 0
      integer :: reverse_solver_stop_failure_count = 0
      integer :: last_solver_stop_reason = 0
      integer :: last_reverse_solver_stop_reason = 0
      integer :: reverse_gate_checked_count = 0
      integer :: reverse_gate_passed_count = 0
      integer :: reverse_gate_failed_count = 0
      integer :: reverse_gate_error_sample_count = 0
      integer :: last_status = intode_status_unknown
      integer :: last_attempted_steps = 0
      integer :: last_completed_steps = 0
      integer :: odex_calls = 0
      integer :: odex_failure = 0
      integer :: measurement_attempted = 0
      integer :: measurement_included = 0
      integer :: measurement_skipped = 0
      integer :: measurement_failed = 0
      integer :: snapshots_written = 0
      integer :: snapshot_write_errors = 0
      integer :: measurement_start_cycle = 1
      integer :: cycle_offset = 0
      integer :: flow_time_observations = 0
      integer :: flow_time_hist_low = 0
      integer :: flow_time_hist_high = 0
      integer :: flow_time_hist_inside(wv_flow_hist_bins) = 0
      integer :: measurement_flow_time_hist_inside(wv_flow_hist_bins) = 0
      integer :: accepted_jump_count = 0
      real(dp) :: accept_probability_sum = 0.0_dp
      real(dp) :: max_constraint_residual = 0.0_dp
      real(dp) :: delta_hamiltonian_sum = 0.0_dp
      real(dp) :: final_flow_time = 0.0_dp
      real(dp) :: flow_time_min = huge(1.0_dp)
      real(dp) :: flow_time_max = -huge(1.0_dp)
      real(dp) :: flow_time_sum = 0.0_dp
      real(dp) :: accepted_x_jump_sq_sum = 0.0_dp
      real(dp) :: accepted_z_jump_sq_sum = 0.0_dp
      real(dp) :: accepted_flow_time_jump_abs_sum = 0.0_dp
      real(dp) :: effective_x_jump_sq_sum = 0.0_dp
      real(dp) :: effective_z_jump_sq_sum = 0.0_dp
      real(dp) :: effective_flow_time_jump_abs_sum = 0.0_dp
      real(dp) :: max_x_jump_sq = 0.0_dp
      real(dp) :: max_z_jump_sq = 0.0_dp
      real(dp) :: max_flow_time_jump_abs = 0.0_dp
      real(dp) :: last_constraint_residual = 0.0_dp
      real(dp) :: reverse_max_constraint_residual = 0.0_dp
      real(dp) :: last_projection_alpha2 = 0.0_dp
      real(dp) :: last_projection_rejected_norm = 0.0_dp
      real(dp) :: last_reverse_gate_state_error = 0.0_dp
      real(dp) :: last_reverse_gate_momentum_error = 0.0_dp
      real(dp) :: reverse_gate_state_error_sum = 0.0_dp
      real(dp) :: reverse_gate_momentum_error_sum = 0.0_dp
      real(dp) :: reverse_gate_state_error_max = 0.0_dp
      real(dp) :: reverse_gate_momentum_error_max = 0.0_dp
      real(dp) :: measurement_phase_coherence = 0.0_dp
   end type wv_dense_chain_summary_t

contains

   subroutine wv_run_dense_chain(base_seed, cycle_count, step_size, num_steps, potential, t0, t1, d0, d1, &
                                 flow_time, x_initial, flow_time_out, x_out, z_out, jac_out, summary, error, &
                                 status, constraint_tol, constraint_max_iter, observable_accumulator, &
                                 measurement_t0, measurement_t1, reverse_gate_state_tol, reverse_gate_momentum_tol, &
                                 measurement_start_cycle, adaptive_stop_enabled, newton_trace_context, &
                                 observable_history_unit, x_history_unit, state_history_unit, history_stride, &
                                 snapshot_prefix, snapshot_interval, snapshot_slots, snapshot_index_unit, cycle_offset)
      integer, intent(in) :: base_seed, cycle_count, num_steps
      real(dp), intent(in) :: step_size, t0, t1, d0, d1, flow_time, x_initial(:)
      type(wv_potential_profile_t), intent(in) :: potential
      real(dp), intent(out) :: flow_time_out, x_out(:)
      complex(dp), intent(out) :: z_out(:), jac_out(:, :)
      type(wv_dense_chain_summary_t), intent(out) :: summary
      logical, intent(out) :: error
      integer, intent(out), optional :: status
      real(dp), intent(in), optional :: constraint_tol
      integer, intent(in), optional :: constraint_max_iter
      type(wv_weighted_observable_accumulator_t), intent(inout), optional :: observable_accumulator
      real(dp), intent(in), optional :: measurement_t0, measurement_t1
      real(dp), intent(in), optional :: reverse_gate_state_tol, reverse_gate_momentum_tol
      integer, intent(in), optional :: measurement_start_cycle
      integer, intent(in), optional :: cycle_offset
      logical, intent(in), optional :: adaptive_stop_enabled
      type(wv_newton_trace_context_t), intent(inout), optional :: newton_trace_context
      integer, intent(in), optional :: observable_history_unit, x_history_unit, state_history_unit, history_stride
      character(len=*), intent(in), optional :: snapshot_prefix
      integer, intent(in), optional :: snapshot_interval, snapshot_slots, snapshot_index_unit

      integer :: n, cycle_idx, absolute_cycle_idx, local_status, observable_count, local_measurement_start_cycle
      integer :: local_history_stride, local_cycle_offset
      integer :: local_snapshot_interval, local_snapshot_slots, snapshot_count
      real(dp) :: flow_time_current, flow_time_next, uniform01, coherence, local_measurement_t0, local_measurement_t1
      real(dp) :: measurement_w_value, measurement_wprime
      real(dp) :: x_jump_sq, z_jump_sq, flow_time_jump_abs
      real(dp), allocatable :: x_current(:), x_next(:), raw_pi(:)
      complex(dp), allocatable :: observable_values(:)
      complex(dp), allocatable :: z_current(:), z_next(:), jac_current(:, :), jac_next(:, :)
      logical :: local_error, has_reverse_gate_error_sample, should_write_history, has_snapshot, snapshot_error
      type(flow_workspace_t) :: flow_workspace
      type(intode_diagnostics_context_t) :: intode_diagnostics
      type(wv_transition_diagnostics_t) :: transition
      type(wv_measurement_factor_t) :: measurement_factor

      summary = wv_dense_chain_summary_t(cycles_requested=cycle_count)
      flow_time_out = flow_time
      x_out = 0.0_dp
      z_out = cmplx(0.0_dp, 0.0_dp, dp)
      jac_out = cmplx(0.0_dp, 0.0_dp, dp)
      error = .true.
      local_status = intode_status_unknown
      if (present(status)) status = local_status

      local_measurement_t0 = t0
      local_measurement_t1 = t1
      if (present(measurement_t0)) local_measurement_t0 = measurement_t0
      if (present(measurement_t1)) local_measurement_t1 = measurement_t1
      local_measurement_start_cycle = 1
      if (present(measurement_start_cycle)) local_measurement_start_cycle = measurement_start_cycle
      summary%measurement_start_cycle = local_measurement_start_cycle
      local_cycle_offset = 0
      if (present(cycle_offset)) local_cycle_offset = cycle_offset
      summary%cycle_offset = local_cycle_offset
      local_history_stride = 1
      if (present(history_stride)) local_history_stride = history_stride
      local_snapshot_interval = 0
      if (present(snapshot_interval)) local_snapshot_interval = snapshot_interval
      local_snapshot_slots = 1
      if (present(snapshot_slots)) local_snapshot_slots = snapshot_slots
      has_snapshot = present(snapshot_prefix) .and. len_trim(snapshot_prefix) > 0
      snapshot_count = 0

      n = size(x_initial)
      if (n <= 0) return
      if (cycle_count < 0 .or. num_steps < 0) return
      if (local_measurement_start_cycle < 1) return
      if (local_cycle_offset < 0) return
      if (local_history_stride < 1) return
      if (has_snapshot .and. (local_snapshot_interval < 1 .or. local_snapshot_slots < 1)) return
      if ((.not. ieee_is_finite(step_size)) .or. step_size <= 0.0_dp) return
      if (.not. all(ieee_is_finite([t0, t1, d0, d1, flow_time, local_measurement_t0, local_measurement_t1]))) return
      if (t1 <= t0) return
      if (d0 < 0.0_dp .or. d1 < 0.0_dp) return
      if (local_measurement_t0 < t0 .or. local_measurement_t1 > t1) return
      if (local_measurement_t1 <= local_measurement_t0) return
      if (size(x_out) /= n .or. size(z_out) /= n) return
      if (size(jac_out, 1) /= n .or. size(jac_out, 2) /= n) return
      if (present(observable_accumulator)) then
         observable_count = model_observable_count()
         if (observable_count <= 0) return
         if (.not. allocated(observable_accumulator%numerator)) return
         if (size(observable_accumulator%numerator) /= observable_count) return
         allocate (observable_values(observable_count))
      end if

      allocate (x_current(n), x_next(n), raw_pi(2*n), z_current(n), z_next(n), jac_current(n, n), jac_next(n, n))
      x_current = x_initial
      flow_time_current = flow_time

      call reset_intode_fallback_stats(intode_diagnostics)
      call flow_at(flow_time_current, x_current, z_current, jac_current, local_error, local_status, flow_workspace, &
                   intode_diagnostics)
      summary%last_status = local_status
      if (present(status)) status = local_status
      if (local_error) then
         summary%odex_calls = intode_diagnostics%odex_calls
         summary%odex_failure = intode_diagnostics%odex_failure
         return
      end if
      call wv_record_flow_time(summary, flow_time_current, t0, t1)
      if (has_snapshot) then
         call wv_write_cyclic_snapshot(snapshot_prefix, snapshot_count, local_snapshot_slots, local_cycle_offset, &
                                       flow_time_current, x_current, snapshot_index_unit, snapshot_error)
         if (snapshot_error) then
            summary%snapshot_write_errors = summary%snapshot_write_errors + 1
            summary%odex_calls = intode_diagnostics%odex_calls
            summary%odex_failure = intode_diagnostics%odex_failure
            return
         end if
         snapshot_count = snapshot_count + 1
         summary%snapshots_written = summary%snapshots_written + 1
      end if

      do cycle_idx = 1, cycle_count
         absolute_cycle_idx = local_cycle_offset + cycle_idx
         summary%cycles_attempted = summary%cycles_attempted + 1
         if (present(newton_trace_context)) newton_trace_context%cycle = absolute_cycle_idx
         call tltm_rng_fill_normal(raw_pi, tltm_rng_domain_wv_hmc_momentum, base_seed, absolute_cycle_idx, 1, 1)
         uniform01 = tltm_rng_uniform(tltm_rng_domain_wv_hmc_accept, base_seed, absolute_cycle_idx, 1, 1, 1)
         call wv_transition_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time_current, x_current, &
                                  z_current, jac_current, raw_pi, uniform01, flow_time_next, x_next, z_next, &
                                  jac_next, transition, local_error, local_status, flow_workspace, intode_diagnostics, &
                                  constraint_tol, constraint_max_iter, reverse_gate_state_tol, reverse_gate_momentum_tol, &
                                  adaptive_stop_enabled, newton_trace_context)
         x_jump_sq = 0.0_dp
         z_jump_sq = 0.0_dp
         flow_time_jump_abs = 0.0_dp
         summary%last_status = local_status
         summary%last_attempted_steps = transition%trajectory%attempted_steps
         summary%last_completed_steps = transition%trajectory%completed_steps
         summary%last_constraint_residual = transition%trajectory%max_constraint_residual
         summary%last_projection_alpha2 = transition%projection_alpha2
         summary%last_projection_rejected_norm = transition%projection_rejected_norm
         summary%last_reverse_gate_state_error = transition%reverse_gate_state_error
         summary%last_reverse_gate_momentum_error = transition%reverse_gate_momentum_error
         if (transition%reverse_gate_checked) then
            summary%reverse_gate_checked_count = summary%reverse_gate_checked_count + 1
            if (transition%reverse_gate_passed) summary%reverse_gate_passed_count = summary%reverse_gate_passed_count + 1
            if (transition%reverse_gate_failed) summary%reverse_gate_failed_count = summary%reverse_gate_failed_count + 1
            has_reverse_gate_error_sample = (.not. transition%reverse_gate_failed) .and. &
                                            ieee_is_finite(transition%reverse_gate_state_error) .and. &
                                            ieee_is_finite(transition%reverse_gate_momentum_error)
            if (has_reverse_gate_error_sample) then
               summary%reverse_gate_error_sample_count = summary%reverse_gate_error_sample_count + 1
               summary%reverse_gate_state_error_sum = summary%reverse_gate_state_error_sum + &
                                                      transition%reverse_gate_state_error
               summary%reverse_gate_state_error_max = max(summary%reverse_gate_state_error_max, &
                                                          transition%reverse_gate_state_error)
               summary%reverse_gate_momentum_error_sum = summary%reverse_gate_momentum_error_sum + &
                                                         transition%reverse_gate_momentum_error
               summary%reverse_gate_momentum_error_max = max(summary%reverse_gate_momentum_error_max, &
                                                             transition%reverse_gate_momentum_error)
            end if
         end if
         if (present(status)) status = local_status
         summary%bounced_steps = summary%bounced_steps + transition%trajectory%bounced_steps
         summary%buffer_exit_bounced_steps = summary%buffer_exit_bounced_steps + &
                                             transition%trajectory%buffer_exit_bounced_steps
         summary%buffer_exit_low_steps = summary%buffer_exit_low_steps + transition%trajectory%buffer_exit_low_steps
         summary%buffer_exit_high_steps = summary%buffer_exit_high_steps + transition%trajectory%buffer_exit_high_steps
         summary%trajectory_steps = summary%trajectory_steps + transition%trajectory%completed_steps
         summary%solver_iterations_total = summary%solver_iterations_total + transition%trajectory%solver_iterations_total
         summary%reverse_trajectory_steps = summary%reverse_trajectory_steps + transition%reverse_trajectory%completed_steps
         summary%reverse_buffer_exit_bounced_steps = summary%reverse_buffer_exit_bounced_steps + &
                                                     transition%reverse_trajectory%buffer_exit_bounced_steps
         summary%reverse_buffer_exit_low_steps = summary%reverse_buffer_exit_low_steps + &
                                                transition%reverse_trajectory%buffer_exit_low_steps
         summary%reverse_buffer_exit_high_steps = summary%reverse_buffer_exit_high_steps + &
                                                 transition%reverse_trajectory%buffer_exit_high_steps
         summary%reverse_solver_iterations_total = summary%reverse_solver_iterations_total + &
                                                   transition%reverse_trajectory%solver_iterations_total
         summary%last_solver_stop_reason = transition%trajectory%last_solver_stop_reason
         summary%last_reverse_solver_stop_reason = transition%reverse_trajectory%last_solver_stop_reason
         call accumulate_solver_stop_counts(summary, transition)
         summary%max_constraint_residual = max(summary%max_constraint_residual, &
                                               transition%trajectory%max_constraint_residual)
         summary%reverse_max_constraint_residual = max(summary%reverse_max_constraint_residual, &
                                                       transition%reverse_trajectory%max_constraint_residual)
         if (local_error) then
            summary%transitions_failed = summary%transitions_failed + 1
            summary%cycles_completed = summary%cycles_completed + 1
            summary%rejected = summary%rejected + 1
            flow_time_next = flow_time_current
            x_next = x_current
            z_next = z_current
            jac_next = jac_current
         end if

         if (.not. local_error) then
            summary%cycles_completed = summary%cycles_completed + 1
            summary%accept_probability_sum = summary%accept_probability_sum + transition%accept_probability
            summary%delta_hamiltonian_sum = summary%delta_hamiltonian_sum + transition%trajectory%delta_hamiltonian
            if (transition%accepted) then
               summary%accepted = summary%accepted + 1
            else
               summary%rejected = summary%rejected + 1
               if (transition%reverse_gate_rejected) then
                  summary%reverse_gate_rejected = summary%reverse_gate_rejected + 1
               else
                  summary%metropolis_rejected = summary%metropolis_rejected + 1
               end if
            end if
         end if

         if (.not. local_error .and. transition%accepted) then
            x_jump_sq = sum((x_next - x_current)**2)/real(n, dp)
            z_jump_sq = sum(abs(z_next - z_current)**2)/real(n, dp)
            flow_time_jump_abs = abs(flow_time_next - flow_time_current)
            summary%accepted_jump_count = summary%accepted_jump_count + 1
            summary%accepted_x_jump_sq_sum = summary%accepted_x_jump_sq_sum + x_jump_sq
            summary%accepted_z_jump_sq_sum = summary%accepted_z_jump_sq_sum + z_jump_sq
            summary%accepted_flow_time_jump_abs_sum = summary%accepted_flow_time_jump_abs_sum + flow_time_jump_abs
         end if
         summary%effective_x_jump_sq_sum = summary%effective_x_jump_sq_sum + x_jump_sq
         summary%effective_z_jump_sq_sum = summary%effective_z_jump_sq_sum + z_jump_sq
         summary%effective_flow_time_jump_abs_sum = summary%effective_flow_time_jump_abs_sum + flow_time_jump_abs
         summary%max_x_jump_sq = max(summary%max_x_jump_sq, x_jump_sq)
         summary%max_z_jump_sq = max(summary%max_z_jump_sq, z_jump_sq)
         summary%max_flow_time_jump_abs = max(summary%max_flow_time_jump_abs, flow_time_jump_abs)

         flow_time_current = flow_time_next
         x_current = x_next
         z_current = z_next
         jac_current = jac_next
         call wv_record_flow_time(summary, flow_time_current, t0, t1)
         if (has_snapshot) then
            if (mod(cycle_idx, local_snapshot_interval) == 0) then
               call wv_write_cyclic_snapshot(snapshot_prefix, snapshot_count, local_snapshot_slots, absolute_cycle_idx, &
                                             flow_time_current, x_current, snapshot_index_unit, snapshot_error)
               if (snapshot_error) then
                  summary%snapshot_write_errors = summary%snapshot_write_errors + 1
                  summary%odex_calls = intode_diagnostics%odex_calls
                  summary%odex_failure = intode_diagnostics%odex_failure
                  flow_time_out = flow_time_current
                  x_out = x_current
                  z_out = z_current
                  jac_out = jac_current
                  return
               end if
               snapshot_count = snapshot_count + 1
               summary%snapshots_written = summary%snapshots_written + 1
            end if
         end if

         if (present(observable_accumulator)) then
            if (cycle_idx < local_measurement_start_cycle) then
               summary%measurement_skipped = summary%measurement_skipped + 1
               cycle
            end if
            if (flow_time_current < local_measurement_t0 .or. flow_time_current > local_measurement_t1) then
               summary%measurement_skipped = summary%measurement_skipped + 1
               cycle
            end if
            summary%measurement_attempted = summary%measurement_attempted + 1
            call wv_potential_value_and_derivative(potential, flow_time_current, measurement_w_value, &
                                                   measurement_wprime, local_error)
            if (.not. local_error) then
               call wv_dense_measurement_factor(z_current, jac_current, measurement_factor, local_error, &
                                                w_value=measurement_w_value)
            end if
            if (.not. local_error) then
               call evaluate_model_observables(z_current, observable_values)
               call wv_accumulate_weighted_observables(observable_accumulator, measurement_factor%wv_factor, &
                                                       observable_values, local_error)
            end if
            if (local_error) then
               summary%measurement_failed = summary%measurement_failed + 1
               summary%odex_calls = intode_diagnostics%odex_calls
               summary%odex_failure = intode_diagnostics%odex_failure
               return
            end if
            summary%measurement_included = summary%measurement_included + 1
            call wv_record_measurement_flow_time(summary, flow_time_current, local_measurement_t0, local_measurement_t1)
            should_write_history = mod(summary%measurement_included - 1, local_history_stride) == 0
            if (should_write_history .and. present(observable_history_unit) .and. observable_history_unit /= 0) then
               call wv_write_observable_history_row(observable_history_unit, absolute_cycle_idx, flow_time_current, &
                                                    measurement_factor, observable_values)
            end if
            if (should_write_history .and. present(x_history_unit) .and. x_history_unit /= 0) then
               call wv_write_x_history_row(x_history_unit, x_current)
            end if
            if (should_write_history .and. present(state_history_unit) .and. state_history_unit /= 0) then
               call wv_write_state_history_row(state_history_unit, flow_time_current, x_current)
            end if
            call wv_weighted_observable_phase_coherence(observable_accumulator, coherence, local_error)
            if (.not. local_error) summary%measurement_phase_coherence = coherence
         end if
      end do

      flow_time_out = flow_time_current
      x_out = x_current
      z_out = z_current
      jac_out = jac_current
      summary%final_flow_time = flow_time_current
      summary%odex_calls = intode_diagnostics%odex_calls
      summary%odex_failure = intode_diagnostics%odex_failure
      error = .false.
   end subroutine wv_run_dense_chain

   subroutine accumulate_solver_stop_counts(summary, transition)
      type(wv_dense_chain_summary_t), intent(inout) :: summary
      type(wv_transition_diagnostics_t), intent(in) :: transition

      summary%solver_stop_converged_count = summary%solver_stop_converged_count + &
                                            transition%trajectory%solver_stop_converged_count
      summary%solver_stop_max_iter_count = summary%solver_stop_max_iter_count + &
                                           transition%trajectory%solver_stop_max_iter_count
      summary%solver_stop_divergence_count = summary%solver_stop_divergence_count + &
                                             transition%trajectory%solver_stop_divergence_count
      summary%solver_stop_stagnation_count = summary%solver_stop_stagnation_count + &
                                             transition%trajectory%solver_stop_stagnation_count
      summary%solver_stop_not_run_count = summary%solver_stop_not_run_count + &
                                          transition%trajectory%solver_stop_not_run_count
      summary%solver_stop_boundary_exit_count = summary%solver_stop_boundary_exit_count + &
                                                transition%trajectory%solver_stop_boundary_exit_count
      summary%solver_stop_large_residual_count = summary%solver_stop_large_residual_count + &
                                                 transition%trajectory%solver_stop_large_residual_count
      summary%solver_stop_failure_count = summary%solver_stop_failure_count + &
                                          transition%trajectory%solver_stop_failure_count
      summary%reverse_solver_stop_converged_count = summary%reverse_solver_stop_converged_count + &
                                                    transition%reverse_trajectory%solver_stop_converged_count
      summary%reverse_solver_stop_max_iter_count = summary%reverse_solver_stop_max_iter_count + &
                                                   transition%reverse_trajectory%solver_stop_max_iter_count
      summary%reverse_solver_stop_divergence_count = summary%reverse_solver_stop_divergence_count + &
                                                     transition%reverse_trajectory%solver_stop_divergence_count
      summary%reverse_solver_stop_stagnation_count = summary%reverse_solver_stop_stagnation_count + &
                                                     transition%reverse_trajectory%solver_stop_stagnation_count
      summary%reverse_solver_stop_not_run_count = summary%reverse_solver_stop_not_run_count + &
                                                  transition%reverse_trajectory%solver_stop_not_run_count
      summary%reverse_solver_stop_boundary_exit_count = summary%reverse_solver_stop_boundary_exit_count + &
                                                       transition%reverse_trajectory%solver_stop_boundary_exit_count
      summary%reverse_solver_stop_large_residual_count = summary%reverse_solver_stop_large_residual_count + &
                                                        transition%reverse_trajectory%solver_stop_large_residual_count
      summary%reverse_solver_stop_failure_count = summary%reverse_solver_stop_failure_count + &
                                                  transition%reverse_trajectory%solver_stop_failure_count
   end subroutine accumulate_solver_stop_counts

   subroutine wv_record_flow_time(summary, flow_time, hist_t0, hist_t1)
      type(wv_dense_chain_summary_t), intent(inout) :: summary
      real(dp), intent(in) :: flow_time, hist_t0, hist_t1
      integer :: bin_idx

      if (.not. ieee_is_finite(flow_time)) return
      summary%flow_time_observations = summary%flow_time_observations + 1
      summary%flow_time_sum = summary%flow_time_sum + flow_time
      summary%flow_time_min = min(summary%flow_time_min, flow_time)
      summary%flow_time_max = max(summary%flow_time_max, flow_time)
      if (hist_t1 <= hist_t0) return
      if (flow_time < hist_t0) then
         summary%flow_time_hist_low = summary%flow_time_hist_low + 1
      else if (flow_time > hist_t1) then
         summary%flow_time_hist_high = summary%flow_time_hist_high + 1
      else
         bin_idx = min(wv_flow_hist_bins, max(1, int((flow_time - hist_t0)/(hist_t1 - hist_t0) &
                                                    *real(wv_flow_hist_bins, dp)) + 1))
         summary%flow_time_hist_inside(bin_idx) = summary%flow_time_hist_inside(bin_idx) + 1
      end if
   end subroutine wv_record_flow_time

   subroutine wv_record_measurement_flow_time(summary, flow_time, hist_t0, hist_t1)
      type(wv_dense_chain_summary_t), intent(inout) :: summary
      real(dp), intent(in) :: flow_time, hist_t0, hist_t1
      integer :: bin_idx

      if (.not. ieee_is_finite(flow_time)) return
      if (hist_t1 <= hist_t0) return
      if (flow_time < hist_t0 .or. flow_time > hist_t1) return
      bin_idx = min(wv_flow_hist_bins, max(1, int((flow_time - hist_t0)/(hist_t1 - hist_t0) &
                                                 *real(wv_flow_hist_bins, dp)) + 1))
      summary%measurement_flow_time_hist_inside(bin_idx) = summary%measurement_flow_time_hist_inside(bin_idx) + 1
   end subroutine wv_record_measurement_flow_time

   subroutine wv_write_observable_history_row(unit_id, cycle_idx, flow_time, factor, observable_values)
      integer, intent(in) :: unit_id, cycle_idx
      real(dp), intent(in) :: flow_time
      type(wv_measurement_factor_t), intent(in) :: factor
      complex(dp), intent(in) :: observable_values(:)

      integer :: idx
      complex(dp) :: numerator_value

      write (unit_id, '(I0,",",g0,",",g0,",",g0,",",g0,",",g0,",",g0,",",g0,",",g0)', advance='no') &
         cycle_idx, flow_time, real(factor%wv_factor, dp), aimag(factor%wv_factor), abs(factor%wv_factor), &
         real(factor%phase_factor, dp), aimag(factor%phase_factor), factor%alpha, factor%alpha2
      do idx = 1, size(observable_values)
         numerator_value = factor%wv_factor*observable_values(idx)
         write (unit_id, '(",",g0,",",g0,",",g0,",",g0)', advance='no') &
            real(observable_values(idx), dp), aimag(observable_values(idx)), &
            real(numerator_value, dp), aimag(numerator_value)
      end do
      write (unit_id, '(A)') ""
   end subroutine wv_write_observable_history_row

   subroutine wv_write_x_history_row(unit_id, x_state)
      integer, intent(in) :: unit_id
      real(dp), intent(in) :: x_state(:)

      write (unit_id) x_state
   end subroutine wv_write_x_history_row

   subroutine wv_write_state_history_row(unit_id, flow_time, x_state)
      integer, intent(in) :: unit_id
      real(dp), intent(in) :: flow_time, x_state(:)

      real(dp) :: packed_state(size(x_state) + 1)

      packed_state(1) = flow_time
      packed_state(2:) = x_state
      write (unit_id) packed_state
   end subroutine wv_write_state_history_row

   subroutine wv_write_cyclic_snapshot(prefix, snapshot_count, slot_count, cycle_idx, flow_time, x_state, &
                                       index_unit, error)
      character(len=*), intent(in) :: prefix
      integer, intent(in) :: snapshot_count, slot_count, cycle_idx
      real(dp), intent(in) :: flow_time, x_state(:)
      integer, intent(in), optional :: index_unit
      logical, intent(out) :: error

      integer :: slot, unit_id, ios
      character(len=32) :: slot_text
      character(len=1024) :: path
      real(dp) :: packed_state(size(x_state) + 1)

      error = .true.
      if (slot_count < 1) return
      if (.not. ieee_is_finite(flow_time)) return
      if (any(.not. ieee_is_finite(x_state))) return

      slot = mod(snapshot_count, slot_count)
      write (slot_text, '(I0)') slot
      if (len_trim(prefix) + len("_slot_.bin") + len_trim(slot_text) > len(path)) return
      path = trim(prefix)//"_slot_"//trim(slot_text)//".bin"

      packed_state(1) = flow_time
      packed_state(2:) = x_state
      open (newunit=unit_id, file=trim(path), status='replace', access='stream', form='unformatted', &
            action='write', iostat=ios)
      if (ios /= 0) return
      write (unit_id, iostat=ios) packed_state
      close (unit_id)
      if (ios /= 0) return

      if (present(index_unit)) then
         if (index_unit /= 0) then
            write (index_unit, '(I0,",",I0,",",g0,",",A)') cycle_idx, slot, flow_time, trim(path)
            flush (index_unit)
         end if
      end if
      error = .false.
   end subroutine wv_write_cyclic_snapshot

end module wv_hmc_driver

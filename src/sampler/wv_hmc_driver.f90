module wv_hmc_driver
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use model_observables, only: evaluate_model_observables, model_observable_count
   use solve_flow, only: flow_at, flow_workspace_t, intode_diagnostics_context_t, intode_status_unknown, &
                         reset_intode_fallback_stats
   use tltm_rng, only: tltm_rng_domain_wv_hmc_accept, tltm_rng_domain_wv_hmc_momentum, tltm_rng_fill_normal, &
                       tltm_rng_uniform
   use utils, only: dp
   use wv_hmc_measurement, only: wv_accumulate_weighted_observables, wv_dense_measurement_factor, &
                                 wv_measurement_factor_t, wv_weighted_observable_accumulator_t, &
                                 wv_weighted_observable_phase_coherence
   use wv_hmc_potential, only: wv_potential_profile_t
   use wv_hmc_trajectory, only: wv_transition_dense, wv_transition_diagnostics_t
   implicit none

   private
   public :: wv_dense_chain_summary_t, wv_run_dense_chain

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
      integer :: trajectory_steps = 0
      integer :: solver_iterations_total = 0
      integer :: last_status = intode_status_unknown
      integer :: last_attempted_steps = 0
      integer :: last_completed_steps = 0
      integer :: odex_calls = 0
      integer :: odex_failure = 0
      integer :: measurement_attempted = 0
      integer :: measurement_included = 0
      integer :: measurement_skipped = 0
      integer :: measurement_failed = 0
      integer :: measurement_start_cycle = 1
      integer :: flow_time_observations = 0
      real(dp) :: accept_probability_sum = 0.0_dp
      real(dp) :: max_constraint_residual = 0.0_dp
      real(dp) :: delta_hamiltonian_sum = 0.0_dp
      real(dp) :: final_flow_time = 0.0_dp
      real(dp) :: flow_time_min = huge(1.0_dp)
      real(dp) :: flow_time_max = -huge(1.0_dp)
      real(dp) :: flow_time_sum = 0.0_dp
      real(dp) :: last_constraint_residual = 0.0_dp
      real(dp) :: last_projection_alpha2 = 0.0_dp
      real(dp) :: last_projection_rejected_norm = 0.0_dp
      real(dp) :: last_reverse_gate_state_error = 0.0_dp
      real(dp) :: last_reverse_gate_momentum_error = 0.0_dp
      real(dp) :: measurement_phase_coherence = 0.0_dp
   end type wv_dense_chain_summary_t

contains

   subroutine wv_run_dense_chain(base_seed, cycle_count, step_size, num_steps, potential, t0, t1, d0, d1, &
                                 flow_time, x_initial, flow_time_out, x_out, z_out, jac_out, summary, error, &
                                 status, constraint_tol, constraint_max_iter, observable_accumulator, &
                                 measurement_t0, measurement_t1, reverse_gate_state_tol, reverse_gate_momentum_tol, &
                                 measurement_start_cycle)
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

      integer :: n, cycle_idx, local_status, observable_count, local_measurement_start_cycle
      real(dp) :: flow_time_current, flow_time_next, uniform01, coherence, local_measurement_t0, local_measurement_t1
      real(dp), allocatable :: x_current(:), x_next(:), raw_pi(:)
      complex(dp), allocatable :: observable_values(:)
      complex(dp), allocatable :: z_current(:), z_next(:), jac_current(:, :), jac_next(:, :)
      logical :: local_error
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

      n = size(x_initial)
      if (n <= 0) return
      if (cycle_count < 0 .or. num_steps < 0) return
      if (local_measurement_start_cycle < 1) return
      if ((.not. ieee_is_finite(step_size)) .or. step_size <= 0.0_dp) return
      if (.not. all(ieee_is_finite([t0, t1, d0, d1, flow_time, local_measurement_t0, local_measurement_t1]))) return
      if (flow_time < 0.0_dp) return
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
      call wv_record_flow_time(summary, flow_time_current)

      do cycle_idx = 1, cycle_count
         summary%cycles_attempted = summary%cycles_attempted + 1
         call tltm_rng_fill_normal(raw_pi, tltm_rng_domain_wv_hmc_momentum, base_seed, cycle_idx, 1, 1)
         uniform01 = tltm_rng_uniform(tltm_rng_domain_wv_hmc_accept, base_seed, cycle_idx, 1, 1, 1)
         call wv_transition_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time_current, x_current, &
                                  z_current, jac_current, raw_pi, uniform01, flow_time_next, x_next, z_next, &
                                  jac_next, transition, local_error, local_status, flow_workspace, intode_diagnostics, &
                                  constraint_tol, constraint_max_iter, reverse_gate_state_tol, reverse_gate_momentum_tol)
         summary%last_status = local_status
         summary%last_attempted_steps = transition%trajectory%attempted_steps
         summary%last_completed_steps = transition%trajectory%completed_steps
         summary%last_constraint_residual = transition%trajectory%max_constraint_residual
         summary%last_projection_alpha2 = transition%projection_alpha2
         summary%last_projection_rejected_norm = transition%projection_rejected_norm
         summary%last_reverse_gate_state_error = transition%reverse_gate_state_error
         summary%last_reverse_gate_momentum_error = transition%reverse_gate_momentum_error
         if (present(status)) status = local_status
         summary%bounced_steps = summary%bounced_steps + transition%trajectory%bounced_steps
         summary%trajectory_steps = summary%trajectory_steps + transition%trajectory%completed_steps
         summary%solver_iterations_total = summary%solver_iterations_total + transition%trajectory%solver_iterations_total
         summary%max_constraint_residual = max(summary%max_constraint_residual, &
                                               transition%trajectory%max_constraint_residual)
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

         flow_time_current = flow_time_next
         x_current = x_next
         z_current = z_next
         jac_current = jac_next
         call wv_record_flow_time(summary, flow_time_current)

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
            call wv_dense_measurement_factor(z_current, jac_current, measurement_factor, local_error)
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

   subroutine wv_record_flow_time(summary, flow_time)
      type(wv_dense_chain_summary_t), intent(inout) :: summary
      real(dp), intent(in) :: flow_time

      if (.not. ieee_is_finite(flow_time)) return
      summary%flow_time_observations = summary%flow_time_observations + 1
      summary%flow_time_sum = summary%flow_time_sum + flow_time
      summary%flow_time_min = min(summary%flow_time_min, flow_time)
      summary%flow_time_max = max(summary%flow_time_max, flow_time)
   end subroutine wv_record_flow_time

end module wv_hmc_driver

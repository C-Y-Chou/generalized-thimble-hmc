module wv_hmc_app_common
   use model_observables, only: get_model_observable_name, model_observable_count
   use param_mod, only: config, read_parameters, set_derivative_mode
   use runtime_env_mod, only: parse_int_env, parse_real_env, read_string_env, to_lower_ascii
   use solve_flow, only: intode_status_unknown
   use utils, only: dp
   use wv_hmc_driver, only: wv_dense_chain_summary_t, wv_run_dense_chain
   use wv_hmc_measurement, only: wv_dense_measurement_factor, wv_init_weighted_observable_accumulator, &
                                 wv_measurement_factor_t, wv_weighted_observable_accumulator_t, &
                                 wv_weighted_observable_estimates
   use wv_hmc_potential, only: wv_potential_paper_wall, wv_potential_profile_t, wv_potential_value_and_derivative, &
                               wv_potential_zero
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

      integer :: n, num_steps, cycle_count, base_seed, status, observable_count
      real(dp) :: step_size, flow_time, sampler_t0, sampler_t1, d0, d1, measurement_t0, measurement_t1
      real(dp) :: w_gamma, w_c0, w_c1, reverse_gate_state_tol, reverse_gate_momentum_tol
      real(dp) :: flow_time_out
      real(dp), allocatable :: x(:), x_out(:)
      complex(dp), allocatable :: z_out(:), jac_out(:, :)
      logical :: error
      logical :: has_summary_file, has_observable_file, has_w_profile
      logical :: found_summary_file, found_observable_file
      character(len=512) :: summary_file, observable_file
      character(len=64) :: w_profile_name
      type(wv_dense_chain_summary_t) :: summary
      type(wv_measurement_factor_t) :: measurement_factor
      type(wv_potential_profile_t) :: potential
      type(wv_weighted_observable_accumulator_t) :: observable_accumulator
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
      sampler_t0 = 0.0_dp
      sampler_t1 = 0.2_dp
      d0 = 0.0_dp
      d1 = 0.0_dp
      w_gamma = 0.0_dp
      w_c0 = 1.0_dp
      w_c1 = 1.0_dp
      reverse_gate_state_tol = 1.0e-6_dp
      reverse_gate_momentum_tol = 1.0e-4_dp
      w_profile_name = "zero"
      call parse_real_env(env_name(env_prefix, "STEP_SIZE"), step_size)
      call parse_int_env(env_name(env_prefix, "NUM_STEPS"), num_steps)
      call parse_int_env(env_name(env_prefix, "CYCLES"), cycle_count)
      call parse_int_env(env_name(env_prefix, "BASE_SEED"), base_seed)
      call parse_real_env(env_name(env_prefix, "FLOW_TIME"), flow_time)
      call parse_real_env(env_name(env_prefix, "T0"), sampler_t0)
      call parse_real_env(env_name(env_prefix, "T1"), sampler_t1)
      call parse_real_env(env_name(env_prefix, "D0"), d0)
      call parse_real_env(env_name(env_prefix, "D1"), d1)
      call read_string_env(env_name(env_prefix, "W_PROFILE"), w_profile_name, has_w_profile)
      w_profile_name = to_lower_ascii(adjustl(w_profile_name))
      call parse_real_env(env_name(env_prefix, "W_GAMMA"), w_gamma)
      call parse_real_env(env_name(env_prefix, "W_C0"), w_c0)
      call parse_real_env(env_name(env_prefix, "W_C1"), w_c1)
      call parse_real_env(env_name(env_prefix, "REVERSE_GATE_STATE_TOL"), reverse_gate_state_tol)
      call parse_real_env(env_name(env_prefix, "REVERSE_GATE_MOMENTUM_TOL"), reverse_gate_momentum_tol)
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
      if (found_summary_file) has_summary_file = .true.
      if (found_observable_file) has_observable_file = .true.

      allocate (x(n), x_out(n), z_out(n), jac_out(n, n))
      call fill_deterministic_x(x)
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

      status = intode_status_unknown
      call wv_run_dense_chain(base_seed, cycle_count, step_size, num_steps, potential, sampler_t0, sampler_t1, d0, d1, &
                              flow_time, x, flow_time_out, x_out, z_out, jac_out, summary, error, status, &
                              observable_accumulator=observable_accumulator, measurement_t0=measurement_t0, &
                              measurement_t1=measurement_t1, reverse_gate_state_tol=reverse_gate_state_tol, &
                              reverse_gate_momentum_tol=reverse_gate_momentum_tol)
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
      call wv_dense_measurement_factor(z_out, jac_out, measurement_factor, error)
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
         "w_gamma", w_gamma, &
         "w_c0", w_c0, &
         "w_c1", w_c1, &
         "reverse_gate_state_tol", reverse_gate_state_tol, &
         "reverse_gate_momentum_tol", reverse_gate_momentum_tol, &
         "last_reverse_gate_state_error", summary%last_reverse_gate_state_error, &
         "last_reverse_gate_momentum_error", summary%last_reverse_gate_momentum_error, &
         "trajectory_steps", summary%trajectory_steps, &
         "bounced_steps", summary%bounced_steps, &
         "solver_iterations", summary%solver_iterations_total, &
         "max_constraint_residual", summary%max_constraint_residual, &
         "measurement_t0", measurement_t0, &
         "measurement_t1", measurement_t1, &
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
                                                    measurement_t0, measurement_t1, reverse_gate_state_tol, &
                                                    reverse_gate_momentum_tol)
      if (has_observable_file) call write_observable_file(trim(observable_file), observable_estimates)
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
      case ("zero")
         profile = wv_potential_zero()
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
                                 local_w_c1, local_measurement_t0, local_measurement_t1, local_reverse_gate_state_tol, &
                                 local_reverse_gate_momentum_tol)
      character(len=*), intent(in) :: path
      integer, intent(in) :: local_base_seed
      real(dp), intent(in) :: local_flow_time_in, local_flow_time_out
      real(dp), intent(in) :: local_sampler_t0, local_sampler_t1, local_sampler_d0, local_sampler_d1
      character(len=*), intent(in) :: local_w_profile_name
      real(dp), intent(in) :: local_w_gamma, local_w_c0, local_w_c1
      real(dp), intent(in) :: local_measurement_t0, local_measurement_t1
      real(dp), intent(in) :: local_reverse_gate_state_tol, local_reverse_gate_momentum_tol
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
         "flow_time_mean,flow_time_observations,trajectory_steps,bounced_steps,"// &
         "solver_iterations,max_constraint_residual,sampler_t0,sampler_t1,sampler_d0,sampler_d1,w_profile,"// &
         "w_gamma,w_c0,w_c1,reverse_gate_state_tol,reverse_gate_momentum_tol,"// &
         "last_reverse_gate_state_error,last_reverse_gate_momentum_error,"// &
         "measurement_t0,measurement_t1,measurement_attempted,measurement_included,"// &
         "measurement_skipped,measurement_failed,"// &
         "measurement_phase_coherence,wv_denominator_re,wv_denominator_im,wv_sum_abs_weight,odex_calls,"// &
         "odex_failure,alpha,alpha2,phase_re,phase_im,wv_factor_re,wv_factor_im"
      write (unit_id, '(*(g0,:,","))') local_base_seed, local_summary%cycles_requested, local_summary%cycles_completed, &
         local_summary%accepted, local_summary%rejected, local_summary%transitions_failed, &
         local_summary%metropolis_rejected, local_summary%reverse_gate_rejected, &
         safe_ratio(local_summary%accept_probability_sum, local_summary%cycles_completed), &
         safe_ratio(local_summary%delta_hamiltonian_sum, local_summary%cycles_completed), local_flow_time_in, &
         local_flow_time_out, local_summary%flow_time_min, local_summary%flow_time_max, &
         safe_ratio(local_summary%flow_time_sum, local_summary%flow_time_observations), &
         local_summary%flow_time_observations, local_summary%trajectory_steps, local_summary%bounced_steps, &
         local_summary%solver_iterations_total, local_summary%max_constraint_residual, &
         local_sampler_t0, local_sampler_t1, local_sampler_d0, local_sampler_d1, trim(local_w_profile_name), &
         local_w_gamma, local_w_c0, local_w_c1, &
         local_reverse_gate_state_tol, local_reverse_gate_momentum_tol, &
         local_summary%last_reverse_gate_state_error, local_summary%last_reverse_gate_momentum_error, &
         local_measurement_t0, local_measurement_t1, local_summary%measurement_attempted, &
         local_summary%measurement_included, local_summary%measurement_skipped, local_summary%measurement_failed, &
         local_summary%measurement_phase_coherence, real(local_observable_accumulator%denominator, dp), &
         aimag(local_observable_accumulator%denominator), local_observable_accumulator%sum_abs_weight, &
         local_summary%odex_calls, local_summary%odex_failure, local_measurement_factor%alpha, &
         local_measurement_factor%alpha2, &
         real(local_measurement_factor%phase_factor, dp), aimag(local_measurement_factor%phase_factor), &
         real(local_measurement_factor%wv_factor, dp), aimag(local_measurement_factor%wv_factor)
      close (unit_id)
   end subroutine write_summary_file

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

end module wv_hmc_app_common

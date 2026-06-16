program probe_wv_hmc_transition_states
   use, intrinsic :: iso_fortran_env, only: int64
   use model, only: ds
   use model_observables, only: evaluate_model_observable_by_index, find_model_observable
   use param_mod, only: config, read_parameters, set_derivative_mode
   use runtime_env_mod, only: parse_int_env, parse_logical_env, parse_real_env, read_string_env, to_lower_ascii
   use solve_flow, only: flow_at, flow_workspace_t, intode_diagnostics_context_t
   use tltm_rng, only: tltm_rng_domain_wv_hmc_accept, tltm_rng_domain_wv_hmc_momentum, tltm_rng_fill_normal, &
                       tltm_rng_uniform
   use utils, only: complex_to_real, dp
   use wv_hmc_constraints, only: wv_calculate_hamiltonian, wv_newton_stop_boundary_exit, wv_newton_stop_converged, &
                                 wv_newton_stop_divergence, wv_newton_stop_large_residual, &
                                 wv_newton_stop_max_iter, wv_newton_stop_not_run, &
                                 wv_newton_stop_stagnation, wv_newton_stop_unknown, &
                                 wv_set_boundary_policy, wv_set_newton_large_residual_stop
   use wv_hmc_kernels, only: wv_project_dense_with_jacobian, wv_xi_from_action_gradient
   use wv_hmc_measurement, only: wv_dense_alpha2, wv_dense_measurement_factor, wv_measurement_factor_t
   use wv_hmc_potential, only: wv_potential_paper_wall, wv_potential_profile_t, &
                               wv_potential_value_and_derivative, wv_potential_zero
   use wv_hmc_trajectory, only: wv_transition_dense, wv_transition_diagnostics_t
   implicit none

   character(len=512) :: state_bank_file, output_csv, w_profile_name, boundary_policy_name
   logical :: has_state_bank_file, has_output_csv, has_w_profile, has_boundary_policy
   logical :: error, adaptive_stop_enabled, large_residual_stop_enabled, include_momentum_flip
   integer :: n, state_size, record_count, record_start, record_stride, record_limit
   integer :: chiral_index, density_index
   integer :: momenta_per_record, base_seed, num_steps, constraint_max_iter
   integer :: large_residual_min_iter, large_residual_patience
   integer :: record_slot, record_index, attempt_idx, state_unit, csv_unit, status
   integer(int64) :: file_size, record_bytes
   real(dp) :: step_size, t0, t1, d0, d1, w_gamma, w_c0, w_c1
   real(dp) :: constraint_tol, reverse_gate_state_tol, reverse_gate_momentum_tol
   real(dp) :: large_residual_threshold, large_residual_min_rel_improvement
   real(dp) :: flow_time, flow_time_out, uniform01, w_value
   real(dp) :: moved_norm, x_norm, pi_norm, projected_pi_norm, rejected_pi_norm
   real(dp) :: h_initial, h_projected, projection_c, pre_projection_alpha2
   real(dp) :: alpha_initial, alpha_out, alpha_ratio
   real(dp), allocatable :: x(:), x_out(:), raw_pi(:), projected_pi(:), rejected_pi(:), xi_real(:)
   complex(dp), allocatable :: z(:), jac(:, :), z_out(:), jac_out(:, :), grad(:), xi(:)
   type(wv_potential_profile_t) :: potential
   type(wv_measurement_factor_t) :: measurement_initial, measurement_out
   type(wv_transition_diagnostics_t) :: diagnostics
   type(flow_workspace_t) :: flow_workspace
   type(intode_diagnostics_context_t), target :: intode_diagnostics

   call read_parameters()
   call set_derivative_mode("manual")

   n = config%state%physical_size
   state_size = n
   if (state_size <= 0) then
      write (*, '(A)') "ERROR invalid_physical_state_size"
      stop 2
   end if
   chiral_index = find_model_observable("chiral_condensate")
   density_index = find_model_observable("number_density")
   if (chiral_index <= 0 .or. density_index <= 0) then
      write (*, '(A)') "ERROR required_observable_indices_unavailable"
      stop 2
   end if

   state_bank_file = ""
   output_csv = "output/wv_hmc_transition_probe.csv"
   w_profile_name = "paper_wall"
   boundary_policy_name = "normal_reflect"
   step_size = 0.009_dp
   num_steps = 10
   t0 = 0.0_dp
   t1 = 0.03_dp
   d0 = 1.0e-4_dp
   d1 = 0.005_dp
   w_gamma = 65.0_dp
   w_c0 = 1.0_dp
   w_c1 = 1.0_dp
   constraint_tol = 1.0e-10_dp
   constraint_max_iter = 192
   reverse_gate_state_tol = 1.0e-5_dp
   reverse_gate_momentum_tol = 1.0e-3_dp
   adaptive_stop_enabled = .false.
   large_residual_stop_enabled = .false.
   large_residual_threshold = 1.0e-4_dp
   large_residual_min_iter = 8
   large_residual_patience = 4
   large_residual_min_rel_improvement = 5.0e-4_dp
   include_momentum_flip = .true.
   base_seed = 20260604
   record_start = 0
   record_stride = 1
   record_limit = 0
   momenta_per_record = 64

   call read_string_env("WV_PROBE_STATE_BANK_FILE", state_bank_file, has_state_bank_file)
   call read_string_env("WV_PROBE_OUTPUT_CSV", output_csv, has_output_csv)
   call read_string_env("WV_PROBE_W_PROFILE", w_profile_name, has_w_profile)
   call read_string_env("WV_PROBE_BOUNDARY_POLICY", boundary_policy_name, has_boundary_policy)
   w_profile_name = to_lower_ascii(adjustl(w_profile_name))
   boundary_policy_name = to_lower_ascii(adjustl(boundary_policy_name))
   call parse_real_env("WV_PROBE_STEP_SIZE", step_size)
   call parse_int_env("WV_PROBE_NUM_STEPS", num_steps)
   call parse_real_env("WV_PROBE_T0", t0)
   call parse_real_env("WV_PROBE_T1", t1)
   call parse_real_env("WV_PROBE_D0", d0)
   call parse_real_env("WV_PROBE_D1", d1)
   call parse_real_env("WV_PROBE_W_GAMMA", w_gamma)
   call parse_real_env("WV_PROBE_W_C0", w_c0)
   call parse_real_env("WV_PROBE_W_C1", w_c1)
   call parse_real_env("WV_PROBE_CONSTRAINT_TOL", constraint_tol)
   call parse_int_env("WV_PROBE_CONSTRAINT_MAX_ITER", constraint_max_iter)
   call parse_real_env("WV_PROBE_REVERSE_GATE_STATE_TOL", reverse_gate_state_tol)
   call parse_real_env("WV_PROBE_REVERSE_GATE_MOMENTUM_TOL", reverse_gate_momentum_tol)
   call parse_logical_env("WV_PROBE_ADAPTIVE_NEWTON_STOP_ENABLED", adaptive_stop_enabled)
   call parse_logical_env("WV_PROBE_LARGE_RESIDUAL_STOP_ENABLED", large_residual_stop_enabled)
   call parse_real_env("WV_PROBE_LARGE_RESIDUAL_THRESHOLD", large_residual_threshold)
   call parse_int_env("WV_PROBE_LARGE_RESIDUAL_MIN_ITER", large_residual_min_iter)
   call parse_int_env("WV_PROBE_LARGE_RESIDUAL_PATIENCE", large_residual_patience)
   call parse_real_env("WV_PROBE_LARGE_RESIDUAL_MIN_REL_IMPROVEMENT", large_residual_min_rel_improvement)
   call parse_logical_env("WV_PROBE_INCLUDE_MOMENTUM_FLIP", include_momentum_flip)
   call parse_int_env("WV_PROBE_BASE_SEED", base_seed)
   call parse_int_env("WV_PROBE_RECORD_START", record_start)
   call parse_int_env("WV_PROBE_RECORD_STRIDE", record_stride)
   call parse_int_env("WV_PROBE_RECORD_LIMIT", record_limit)
   call parse_int_env("WV_PROBE_MOMENTA_PER_RECORD", momenta_per_record)

   if (.not. has_state_bank_file .or. len_trim(state_bank_file) <= 0) then
      write (*, '(A)') "ERROR WV_PROBE_STATE_BANK_FILE is required"
      stop 2
   end if
   if (record_start < 0 .or. record_stride < 1 .or. record_limit < 0 .or. momenta_per_record < 1) then
      write (*, '(A)') "ERROR invalid_record_or_attempt_controls"
      stop 2
   end if
   if (step_size <= 0.0_dp .or. num_steps < 0 .or. t1 <= t0 .or. constraint_tol <= 0.0_dp) then
      write (*, '(A)') "ERROR invalid_wv_probe_controls"
      stop 2
   end if

   call wv_set_boundary_policy(trim(boundary_policy_name), error)
   if (error) then
      write (*, '(A,1X,A)') "ERROR invalid_boundary_policy", trim(boundary_policy_name)
      stop 2
   end if
   call wv_set_newton_large_residual_stop(large_residual_stop_enabled, large_residual_threshold, &
                                          large_residual_min_iter, large_residual_patience, &
                                          large_residual_min_rel_improvement)
   select case (trim(w_profile_name))
   case ("zero")
      potential = wv_potential_zero()
   case ("paper_wall")
      potential = wv_potential_paper_wall(t0, t1, d0, d1, w_gamma, w_c0, w_c1)
   case default
      write (*, '(A,1X,A)') "ERROR invalid_w_profile", trim(w_profile_name)
      stop 2
   end select
   call wv_potential_value_and_derivative(potential, t0, w_value, uniform01, error)
   if (error) then
      write (*, '(A)') "ERROR invalid_potential_parameters"
      stop 2
   end if

   inquire (file=trim(state_bank_file), size=file_size)
   record_bytes = int(state_size + 1, int64)*8_int64
   if (file_size <= 0_int64 .or. mod(file_size, record_bytes) /= 0_int64) then
      write (*, '(*(g0,1X))') "ERROR", "invalid_state_bank_size", trim(state_bank_file), file_size, record_bytes
      stop 2
   end if
   record_count = int(file_size/record_bytes)
   if (record_start >= record_count) then
      write (*, '(*(g0,1X))') "ERROR", "record_start_out_of_range", record_start, record_count
      stop 2
   end if
   if (record_limit == 0) record_limit = (record_count - record_start + record_stride - 1)/record_stride

   allocate (x(n), x_out(n), raw_pi(2*n), projected_pi(2*n), rejected_pi(2*n), xi_real(2*n))
   allocate (z(n), jac(n, n), z_out(n), jac_out(n, n), grad(n), xi(n))

   open (newunit=state_unit, file=trim(state_bank_file), status='old', access='stream', &
         form='unformatted', action='read', iostat=status)
   if (status /= 0) then
      write (*, '(A,1X,A)') "ERROR cannot_open_state_bank", trim(state_bank_file)
      stop 2
   end if
   open (newunit=csv_unit, file=trim(output_csv), status='replace', action='write', iostat=status)
   if (status /= 0) then
      write (*, '(A,1X,A)') "ERROR cannot_open_output_csv", trim(output_csv)
      stop 2
   end if
   call write_header(csv_unit)

   do record_slot = 1, record_limit
      record_index = record_start + (record_slot - 1)*record_stride
      if (record_index >= record_count) exit
      call read_state_record(state_unit, record_index, record_bytes, flow_time, x, status)
      if (status /= 0) then
         call write_flow_error(csv_unit, record_index, -1, flow_time, status)
         cycle
      end if
      call flow_at(flow_time, x, z, jac, error, status)
      if (error) then
         call write_flow_error(csv_unit, record_index, -1, flow_time, status)
         cycle
      end if

      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) then
         call write_flow_error(csv_unit, record_index, -1, flow_time, status)
         cycle
      end if
      call complex_to_real(xi, xi_real)
      x_norm = norm2(x)

      do attempt_idx = 1, momenta_per_record
         call tltm_rng_fill_normal(raw_pi, tltm_rng_domain_wv_hmc_momentum, base_seed, record_index + 1, attempt_idx, 1)
         uniform01 = tltm_rng_uniform(tltm_rng_domain_wv_hmc_accept, base_seed, record_index + 1, attempt_idx, 1, 1)
         call probe_one_momentum(csv_unit, record_index, attempt_idx, 1)
         if (include_momentum_flip) then
            raw_pi = -raw_pi
            call probe_one_momentum(csv_unit, record_index, attempt_idx, -1)
         end if
      end do
   end do

   close (state_unit)
   close (csv_unit)
   write (*, '(*(g0,1X))') "WV_HMC_TRANSITION_STATE_PROBE_COMPLETE", "state_bank", trim(state_bank_file), &
      "output_csv", trim(output_csv), "record_count", record_count, "record_limit", record_limit, &
      "momenta_per_record", momenta_per_record

contains

   subroutine read_state_record(unit_id, record_index, record_bytes, flow_time, x_state, status)
      integer, intent(in) :: unit_id, record_index
      integer(int64), intent(in) :: record_bytes
      real(dp), intent(out) :: flow_time, x_state(:)
      integer, intent(out) :: status
      integer(int64) :: pos

      pos = int(record_index, int64)*record_bytes + 1_int64
      read (unit_id, pos=pos, iostat=status) flow_time, x_state
   end subroutine read_state_record

   subroutine transition_hamiltonian(z_state, pi_state, potential_profile, flow_time_value, h_value, error)
      complex(dp), intent(in) :: z_state(:)
      real(dp), intent(in) :: pi_state(:), flow_time_value
      type(wv_potential_profile_t), intent(in) :: potential_profile
      real(dp), intent(out) :: h_value
      logical, intent(out) :: error
      real(dp) :: wv, wp

      call wv_potential_value_and_derivative(potential_profile, flow_time_value, wv, wp, error)
      if (error) then
         h_value = huge(1.0_dp)
         return
      end if
      call wv_calculate_hamiltonian(z_state, pi_state, wv, h_value, error)
      if (error) then
         h_value = huge(1.0_dp)
         return
      end if
      error = .false.
   end subroutine transition_hamiltonian

   subroutine write_header(unit_id)
      integer, intent(in) :: unit_id
      write (unit_id, '(A)') "record,attempt,momentum_sign,flow_time,x_norm,raw_pi_norm,projected_pi_norm,rejected_pi_norm,"// &
         "initial_raw_h,initial_projected_h,uniform01,flow_time_out,moved_norm,alpha_initial,alpha_out,alpha_ratio,"// &
         "error,status,accepted,"// &
         "accept_probability,projection_alpha2,projection_rejected_norm,trajectory_attempted_steps,"// &
         "trajectory_completed_steps,trajectory_bounced_steps,trajectory_solver_iterations,"// &
         "trajectory_stop_converged,trajectory_stop_boundary_exit,trajectory_stop_max_iter,"// &
         "trajectory_stop_large_residual,trajectory_stop_failure,trajectory_last_stop,"// &
         "trajectory_last_status,trajectory_delta_h,reverse_checked,reverse_passed,reverse_rejected,"// &
         "reverse_failed,reverse_t_error,reverse_state_error,reverse_momentum_error,"// &
         "reverse_attempted_steps,reverse_completed_steps,reverse_bounced_steps,reverse_solver_iterations,"// &
         "reverse_stop_converged,reverse_stop_boundary_exit,reverse_stop_max_iter,reverse_stop_large_residual,"// &
         "reverse_stop_failure,reverse_last_stop,reverse_last_status,reverse_delta_h,"// &
         "initial_measurement_error,out_measurement_error,"// &
         "initial_weight_re,initial_weight_im,out_weight_re,out_weight_im,"// &
         "initial_chiral_re,initial_chiral_im,out_chiral_re,out_chiral_im,"// &
         "initial_density_re,initial_density_im,out_density_re,out_density_im"
   end subroutine write_header

   subroutine write_flow_error(unit_id, record_index, attempt_idx, flow_time, status)
      integer, intent(in) :: unit_id, record_index, attempt_idx, status
      real(dp), intent(in) :: flow_time
      write (unit_id, '(*(g0,:,","))') record_index, attempt_idx, 0, flow_time, -1.0_dp, -1.0_dp, -1.0_dp, &
         -1.0_dp, huge(1.0_dp), huge(1.0_dp), -1.0_dp, flow_time, -1.0_dp, -1.0_dp, -1.0_dp, &
         -1.0_dp, 1, status, 0, &
         0.0_dp, 0.0_dp, -1.0_dp, 0, 0, 0, 0, 0, 0, 0, 0, 0, wv_newton_stop_unknown, status, huge(1.0_dp), &
         0, 0, 0, 0, huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), 0, 0, 0, 0, 0, 0, 0, 0, 0, &
         wv_newton_stop_unknown, status, huge(1.0_dp), 1, 1, &
         huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), &
         huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), &
         huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), huge(1.0_dp)
   end subroutine write_flow_error

   subroutine probe_one_momentum(unit_id, record_index, attempt_idx, momentum_sign)
      integer, intent(in) :: unit_id, record_index, attempt_idx, momentum_sign
      logical :: transition_error, alpha_error, initial_measurement_error, out_measurement_error
      complex(dp) :: initial_chiral, initial_density, out_chiral, out_density

      call wv_project_dense_with_jacobian(raw_pi, xi_real, jac, projected_pi, rejected_pi, projection_c, &
                                          pre_projection_alpha2, error)
      if (error) then
         pi_norm = norm2(raw_pi)
         projected_pi_norm = -1.0_dp
         rejected_pi_norm = -1.0_dp
         h_initial = huge(1.0_dp)
         h_projected = huge(1.0_dp)
      else
         pi_norm = norm2(raw_pi)
         projected_pi_norm = norm2(projected_pi)
         rejected_pi_norm = norm2(rejected_pi)
         call transition_hamiltonian(z, raw_pi, potential, flow_time, h_initial, error)
         if (error) h_initial = huge(1.0_dp)
         call transition_hamiltonian(z, projected_pi, potential, flow_time, h_projected, error)
         if (error) h_projected = huge(1.0_dp)
      end if

      alpha_initial = -1.0_dp
      if (pre_projection_alpha2 > 0.0_dp) alpha_initial = sqrt(pre_projection_alpha2)
      call compute_observable_snapshot(flow_time, z, jac, measurement_initial, initial_chiral, initial_density, &
                                       initial_measurement_error)

      call wv_transition_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time, x, z, jac, raw_pi, &
                               uniform01, flow_time_out, x_out, z_out, jac_out, diagnostics, transition_error, status, &
                               flow_workspace, intode_diagnostics, constraint_tol, constraint_max_iter, &
                               reverse_gate_state_tol, reverse_gate_momentum_tol, adaptive_stop_enabled)
      if (transition_error) then
         moved_norm = -1.0_dp
         alpha_out = -1.0_dp
         alpha_ratio = -1.0_dp
         call compute_observable_snapshot(flow_time, z, jac, measurement_out, out_chiral, out_density, &
                                          out_measurement_error)
      else
         moved_norm = sqrt((flow_time_out - flow_time)**2 + sum((x_out - x)**2))
         call wv_dense_alpha2(z_out, jac_out, alpha_out, alpha_error)
         if (alpha_error .or. alpha_out <= 0.0_dp) then
            alpha_out = -1.0_dp
            alpha_ratio = -1.0_dp
         else
            alpha_out = sqrt(alpha_out)
            if (alpha_initial > 0.0_dp) then
               alpha_ratio = alpha_out/alpha_initial
            else
               alpha_ratio = -1.0_dp
            end if
         end if
         call compute_observable_snapshot(flow_time_out, z_out, jac_out, measurement_out, out_chiral, out_density, &
                                          out_measurement_error)
      end if
      call write_result(unit_id, record_index, attempt_idx, momentum_sign, flow_time, x_norm, pi_norm, &
                        projected_pi_norm, rejected_pi_norm, h_initial, h_projected, uniform01, flow_time_out, &
                        moved_norm, alpha_initial, alpha_out, alpha_ratio, diagnostics, transition_error, status, &
                        measurement_initial, measurement_out, initial_chiral, out_chiral, initial_density, out_density, &
                        initial_measurement_error, out_measurement_error)
   end subroutine probe_one_momentum

   subroutine compute_observable_snapshot(flow_time_value, z_state, jac_state, factor, chiral, density, measurement_error)
      real(dp), intent(in) :: flow_time_value
      complex(dp), intent(in) :: z_state(:), jac_state(:, :)
      type(wv_measurement_factor_t), intent(out) :: factor
      complex(dp), intent(out) :: chiral, density
      logical, intent(out) :: measurement_error
      real(dp) :: local_w_value, local_wprime
      logical :: local_error

      factor = wv_measurement_factor_t()
      chiral = cmplx(huge(1.0_dp), huge(1.0_dp), dp)
      density = cmplx(huge(1.0_dp), huge(1.0_dp), dp)
      measurement_error = .true.

      call wv_potential_value_and_derivative(potential, flow_time_value, local_w_value, local_wprime, local_error)
      if (local_error) return
      call wv_dense_measurement_factor(z_state, jac_state, factor, local_error, local_w_value)
      if (local_error) return
      call evaluate_model_observable_by_index(z_state, chiral_index, chiral)
      call evaluate_model_observable_by_index(z_state, density_index, density)
      measurement_error = .false.
   end subroutine compute_observable_snapshot

   subroutine write_result(unit_id, record_index, attempt_idx, momentum_sign, flow_time, x_norm, raw_pi_norm, projected_pi_norm, &
                           rejected_pi_norm, h_initial, h_projected, uniform01, flow_time_out, moved_norm, &
                           alpha_initial, alpha_out, alpha_ratio, diagnostics, error, status, factor_initial, factor_out, &
                           chiral_initial, chiral_out, density_initial, density_out, initial_measurement_error, &
                           out_measurement_error)
      integer, intent(in) :: unit_id, record_index, attempt_idx, momentum_sign, status
      real(dp), intent(in) :: flow_time, x_norm, raw_pi_norm, projected_pi_norm, rejected_pi_norm
      real(dp), intent(in) :: h_initial, h_projected, uniform01, flow_time_out, moved_norm
      real(dp), intent(in) :: alpha_initial, alpha_out, alpha_ratio
      type(wv_transition_diagnostics_t), intent(in) :: diagnostics
      type(wv_measurement_factor_t), intent(in) :: factor_initial, factor_out
      complex(dp), intent(in) :: chiral_initial, chiral_out, density_initial, density_out
      logical, intent(in) :: initial_measurement_error, out_measurement_error
      logical, intent(in) :: error

      write (unit_id, '(*(g0,:,","))') record_index, attempt_idx, momentum_sign, flow_time, x_norm, raw_pi_norm, &
         projected_pi_norm, rejected_pi_norm, h_initial, h_projected, uniform01, flow_time_out, moved_norm, &
         alpha_initial, alpha_out, alpha_ratio, logical_to_int(error), status, &
         logical_to_int(diagnostics%accepted), diagnostics%accept_probability, &
         diagnostics%projection_alpha2, diagnostics%projection_rejected_norm, &
         diagnostics%trajectory%attempted_steps, diagnostics%trajectory%completed_steps, &
         diagnostics%trajectory%bounced_steps, diagnostics%trajectory%solver_iterations_total, &
         diagnostics%trajectory%solver_stop_converged_count, diagnostics%trajectory%solver_stop_boundary_exit_count, &
         diagnostics%trajectory%solver_stop_max_iter_count, diagnostics%trajectory%solver_stop_large_residual_count, &
         diagnostics%trajectory%solver_stop_failure_count, diagnostics%trajectory%last_solver_stop_reason, &
         diagnostics%trajectory%last_status, diagnostics%trajectory%delta_hamiltonian, &
         logical_to_int(diagnostics%reverse_gate_checked), logical_to_int(diagnostics%reverse_gate_passed), &
         logical_to_int(diagnostics%reverse_gate_rejected), logical_to_int(diagnostics%reverse_gate_failed), &
         diagnostics%reverse_gate_t_error, diagnostics%reverse_gate_state_error, diagnostics%reverse_gate_momentum_error, &
         diagnostics%reverse_trajectory%attempted_steps, diagnostics%reverse_trajectory%completed_steps, &
         diagnostics%reverse_trajectory%bounced_steps, diagnostics%reverse_trajectory%solver_iterations_total, &
         diagnostics%reverse_trajectory%solver_stop_converged_count, &
         diagnostics%reverse_trajectory%solver_stop_boundary_exit_count, &
         diagnostics%reverse_trajectory%solver_stop_max_iter_count, &
         diagnostics%reverse_trajectory%solver_stop_large_residual_count, &
         diagnostics%reverse_trajectory%solver_stop_failure_count, &
         diagnostics%reverse_trajectory%last_solver_stop_reason, diagnostics%reverse_trajectory%last_status, &
         diagnostics%reverse_trajectory%delta_hamiltonian, &
         logical_to_int(initial_measurement_error), logical_to_int(out_measurement_error), &
         real(factor_initial%wv_factor, dp), aimag(factor_initial%wv_factor), &
         real(factor_out%wv_factor, dp), aimag(factor_out%wv_factor), &
         real(chiral_initial, dp), aimag(chiral_initial), real(chiral_out, dp), aimag(chiral_out), &
         real(density_initial, dp), aimag(density_initial), real(density_out, dp), aimag(density_out)
   end subroutine write_result

   integer function logical_to_int(value)
      logical, intent(in) :: value

      if (value) then
         logical_to_int = 1
      else
         logical_to_int = 0
      end if
   end function logical_to_int

end program probe_wv_hmc_transition_states

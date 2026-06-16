program probe_wv_hmc_step_trace
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use, intrinsic :: iso_fortran_env, only: int64
   use model, only: calculate_action, ds
   use param_mod, only: config, read_parameters, set_derivative_mode
   use runtime_env_mod, only: parse_int_env, parse_logical_env, parse_real_env, read_string_env, to_lower_ascii
   use solve_flow, only: flow_at, flow_workspace_t, intode_diagnostics_context_t
   use tltm_rng, only: tltm_rng_domain_wv_hmc_momentum, tltm_rng_fill_normal
   use utils, only: complex_to_real, dp
   use wv_hmc_constraints, only: wv_calculate_hamiltonian, wv_newton_trace_context_t, &
                                 wv_rattle_step_dense_with_boundary, wv_set_boundary_policy, &
                                 wv_set_newton_large_residual_stop
   use wv_hmc_kernels, only: wv_project_dense_with_jacobian, wv_xi_from_action_gradient
   use wv_hmc_measurement, only: wv_dense_alpha2
   use wv_hmc_potential, only: wv_potential_paper_wall, wv_potential_profile_t, &
                               wv_potential_value_and_derivative, wv_potential_zero
   implicit none

   character(len=512) :: state_bank_file, step_trace_csv, newton_trace_csv, w_profile_name, boundary_policy_name
   logical :: has_state_bank_file, has_step_trace_csv, has_newton_trace_csv, has_w_profile, has_boundary_policy
   logical :: error, adaptive_stop_enabled, large_residual_stop_enabled, projection_error
   integer :: n, state_unit, step_unit, newton_unit, ios, status
   integer :: record_index, base_seed, momentum_cycle, attempt_index, momentum_sign
   integer :: num_steps, constraint_max_iter, step_idx, iterations, solver_stop_reason
   integer :: large_residual_min_iter, large_residual_patience
   integer(int64) :: file_size, record_bytes, pos
   real(dp) :: step_size, t0, t1, d0, d1, w_gamma, w_c0, w_c1
   real(dp) :: constraint_tol, large_residual_threshold, large_residual_min_rel_improvement
   real(dp) :: flow_time, t_current, t_next, residual_norm
   real(dp) :: projection_c, projection_alpha2
   real(dp), allocatable :: x(:), x_current(:), x_next(:)
   real(dp), allocatable :: raw_pi(:), pi_current(:), pi_next(:), rejected_pi(:), xi_real(:)
   complex(dp), allocatable :: z(:), z_current(:), z_next(:), jac(:, :), jac_current(:, :), jac_next(:, :)
   complex(dp), allocatable :: grad(:), xi(:)
   logical :: bounced, step_error
   type(wv_potential_profile_t) :: potential
   type(flow_workspace_t) :: flow_workspace
   type(intode_diagnostics_context_t), target :: intode_diagnostics
   type(wv_newton_trace_context_t) :: trace_context

   call read_parameters()
   call set_derivative_mode("manual")

   n = config%state%physical_size
   if (n <= 0) then
      write (*, '(A)') "ERROR invalid_physical_state_size"
      stop 2
   end if

   state_bank_file = ""
   step_trace_csv = "output/wv_hmc_step_trace.csv"
   newton_trace_csv = "output/wv_hmc_newton_trace.csv"
   w_profile_name = "paper_wall"
   boundary_policy_name = "normal_reflect"
   record_index = 0
   base_seed = 9440026
   momentum_cycle = 11005
   attempt_index = 1
   momentum_sign = 1
   step_size = 0.016_dp
   num_steps = 10
   t0 = 1.0e-4_dp
   t1 = 0.03_dp
   d0 = 1.0e-4_dp
   d1 = 0.005_dp
   w_gamma = 55.0_dp
   w_c0 = 1.0_dp
   w_c1 = 1.0_dp
   constraint_tol = 1.0e-10_dp
   constraint_max_iter = 192
   adaptive_stop_enabled = .false.
   large_residual_stop_enabled = .false.
   large_residual_threshold = 1.0e-4_dp
   large_residual_min_iter = 8
   large_residual_patience = 4
   large_residual_min_rel_improvement = 5.0e-4_dp

   call read_string_env("WV_STEP_TRACE_STATE_BANK_FILE", state_bank_file, has_state_bank_file)
   call read_string_env("WV_STEP_TRACE_OUTPUT_CSV", step_trace_csv, has_step_trace_csv)
   call read_string_env("WV_STEP_TRACE_NEWTON_CSV", newton_trace_csv, has_newton_trace_csv)
   call read_string_env("WV_STEP_TRACE_W_PROFILE", w_profile_name, has_w_profile)
   call read_string_env("WV_STEP_TRACE_BOUNDARY_POLICY", boundary_policy_name, has_boundary_policy)
   w_profile_name = to_lower_ascii(adjustl(w_profile_name))
   boundary_policy_name = to_lower_ascii(adjustl(boundary_policy_name))
   call parse_int_env("WV_STEP_TRACE_RECORD_INDEX", record_index)
   call parse_int_env("WV_STEP_TRACE_BASE_SEED", base_seed)
   call parse_int_env("WV_STEP_TRACE_MOMENTUM_CYCLE", momentum_cycle)
   call parse_int_env("WV_STEP_TRACE_ATTEMPT_INDEX", attempt_index)
   call parse_int_env("WV_STEP_TRACE_MOMENTUM_SIGN", momentum_sign)
   call parse_real_env("WV_STEP_TRACE_STEP_SIZE", step_size)
   call parse_int_env("WV_STEP_TRACE_NUM_STEPS", num_steps)
   call parse_real_env("WV_STEP_TRACE_T0", t0)
   call parse_real_env("WV_STEP_TRACE_T1", t1)
   call parse_real_env("WV_STEP_TRACE_D0", d0)
   call parse_real_env("WV_STEP_TRACE_D1", d1)
   call parse_real_env("WV_STEP_TRACE_W_GAMMA", w_gamma)
   call parse_real_env("WV_STEP_TRACE_W_C0", w_c0)
   call parse_real_env("WV_STEP_TRACE_W_C1", w_c1)
   call parse_real_env("WV_STEP_TRACE_CONSTRAINT_TOL", constraint_tol)
   call parse_int_env("WV_STEP_TRACE_CONSTRAINT_MAX_ITER", constraint_max_iter)
   call parse_logical_env("WV_STEP_TRACE_ADAPTIVE_NEWTON_STOP_ENABLED", adaptive_stop_enabled)
   call parse_logical_env("WV_STEP_TRACE_LARGE_RESIDUAL_STOP_ENABLED", large_residual_stop_enabled)
   call parse_real_env("WV_STEP_TRACE_LARGE_RESIDUAL_THRESHOLD", large_residual_threshold)
   call parse_int_env("WV_STEP_TRACE_LARGE_RESIDUAL_MIN_ITER", large_residual_min_iter)
   call parse_int_env("WV_STEP_TRACE_LARGE_RESIDUAL_PATIENCE", large_residual_patience)
   call parse_real_env("WV_STEP_TRACE_LARGE_RESIDUAL_MIN_REL_IMPROVEMENT", large_residual_min_rel_improvement)

   if (.not. has_state_bank_file .or. len_trim(state_bank_file) <= 0) then
      write (*, '(A)') "ERROR WV_STEP_TRACE_STATE_BANK_FILE is required"
      stop 2
   end if
   if (record_index < 0 .or. momentum_cycle < 1 .or. attempt_index < 1) then
      write (*, '(A)') "ERROR invalid_step_trace_indices"
      stop 2
   end if
   if (momentum_sign /= 1 .and. momentum_sign /= -1) then
      write (*, '(A)') "ERROR invalid_momentum_sign"
      stop 2
   end if
   if (step_size <= 0.0_dp .or. num_steps < 0 .or. t1 <= t0 .or. constraint_tol <= 0.0_dp) then
      write (*, '(A)') "ERROR invalid_step_trace_controls"
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

   record_bytes = int(n + 1, int64)*8_int64
   inquire (file=trim(state_bank_file), size=file_size)
   if (file_size <= 0_int64 .or. mod(file_size, record_bytes) /= 0_int64) then
      write (*, '(*(g0,1X))') "ERROR", "invalid_state_bank_size", trim(state_bank_file), file_size, record_bytes
      stop 2
   end if
   if (int(record_index, int64) >= file_size/record_bytes) then
      write (*, '(*(g0,1X))') "ERROR", "record_index_out_of_range", record_index, file_size/record_bytes
      stop 2
   end if

   allocate (x(n), x_current(n), x_next(n))
   allocate (raw_pi(2*n), pi_current(2*n), pi_next(2*n), rejected_pi(2*n), xi_real(2*n))
   allocate (z(n), z_current(n), z_next(n), jac(n, n), jac_current(n, n), jac_next(n, n), grad(n), xi(n))

   open (newunit=state_unit, file=trim(state_bank_file), status='old', access='stream', form='unformatted', &
         action='read', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "ERROR cannot_open_state_bank", trim(state_bank_file)
      stop 2
   end if
   pos = int(record_index, int64)*record_bytes + 1_int64
   read (state_unit, pos=pos, iostat=ios) flow_time, x
   close (state_unit)
   if (ios /= 0) then
      write (*, '(*(g0,1X))') "ERROR cannot_read_state_record", record_index, ios
      stop 2
   end if

   call flow_at(flow_time, x, z, jac, error, status)
   if (error) then
      write (*, '(*(g0,1X))') "ERROR initial_flow_failed", flow_time, status
      stop 2
   end if
   call ds(z, grad)
   call wv_xi_from_action_gradient(grad, xi, error)
   if (error) then
      write (*, '(A)') "ERROR xi_from_action_gradient_failed"
      stop 2
   end if
   call complex_to_real(xi, xi_real)
   call tltm_rng_fill_normal(raw_pi, tltm_rng_domain_wv_hmc_momentum, base_seed, momentum_cycle, attempt_index, 1)
   if (momentum_sign < 0) raw_pi = -raw_pi
   call wv_project_dense_with_jacobian(raw_pi, xi_real, jac, pi_current, rejected_pi, projection_c, &
                                       projection_alpha2, projection_error)
   if (projection_error) then
      write (*, '(A)') "ERROR initial_momentum_projection_failed"
      stop 2
   end if

   open (newunit=step_unit, file=trim(step_trace_csv), status='replace', action='write', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "ERROR cannot_open_step_trace", trim(step_trace_csv)
      stop 2
   end if
   open (newunit=newton_unit, file=trim(newton_trace_csv), status='replace', action='write', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "ERROR cannot_open_newton_trace", trim(newton_trace_csv)
      stop 2
   end if
   call write_step_header(step_unit)
   write (newton_unit, '(A)') "solve_id,cycle,direction,step,iter,residual_norm,tol,h,u_norm,lambda_norm,stop_reason"
   trace_context%unit = newton_unit
   trace_context%cycle = momentum_cycle
   trace_context%direction = 1

   t_current = flow_time
   x_current = x
   z_current = z
   jac_current = jac

   do step_idx = 1, num_steps
      trace_context%step = step_idx
      call run_one_step(step_idx)
      if (step_error) exit
      t_current = t_next
      x_current = x_next
      z_current = z_next
      jac_current = jac_next
      pi_current = pi_next
   end do

   close (step_unit)
   close (newton_unit)
   write (*, '(*(g0,1X))') "WV_HMC_STEP_TRACE_COMPLETE", "state_bank", trim(state_bank_file), &
      "step_csv", trim(step_trace_csv), "newton_csv", trim(newton_trace_csv), "steps_requested", num_steps

contains

   subroutine run_one_step(local_step)
      integer, intent(in) :: local_step
      real(dp) :: h_before, h_after, kinetic_before, kinetic_after
      real(dp) :: action_before_re, action_before_im, action_after_re, action_after_im
      real(dp) :: w_before, wp_before, w_after, wp_after, alpha2_before, alpha2_after
      real(dp) :: x_jump, z_jump, pi_jump
      logical :: h_before_error, h_after_error, alpha_before_error, alpha_after_error
      logical :: action_before_error, action_after_error

      call state_scalars(t_current, z_current, jac_current, pi_current, h_before, h_before_error, &
                         kinetic_before, action_before_re, action_before_im, action_before_error, &
                         w_before, wp_before, alpha2_before, alpha_before_error)

      call wv_rattle_step_dense_with_boundary(step_size, wp_before, t0, t1, d0, d1, t_current, x_current, &
                                              z_current, jac_current, pi_current, t_next, x_next, z_next, &
                                              jac_next, pi_next, residual_norm, iterations, bounced, step_error, &
                                              status, flow_workspace, intode_diagnostics, constraint_tol, &
                                              constraint_max_iter, solver_stop_reason, adaptive_stop_enabled, &
                                              trace_context, potential)

      call state_scalars(t_next, z_next, jac_next, pi_next, h_after, h_after_error, kinetic_after, &
                         action_after_re, action_after_im, action_after_error, w_after, wp_after, alpha2_after, &
                         alpha_after_error)
      x_jump = norm2(x_next - x_current)
      z_jump = sqrt(sum(abs(z_next - z_current)**2))
      pi_jump = norm2(pi_next - pi_current)
      write (step_unit, '(*(g0,:,","))') record_index, base_seed, momentum_cycle, attempt_index, momentum_sign, &
         local_step, t_current, t_next, t_next - t_current, &
         logical_to_int(step_error), status, logical_to_int(bounced), solver_stop_reason, iterations, residual_norm, &
         h_before, h_after, h_after - h_before, &
         kinetic_before, kinetic_after, kinetic_after - kinetic_before, &
         action_before_re, action_after_re, action_after_re - action_before_re, &
         action_before_im, action_after_im, action_after_im - action_before_im, &
         w_before, w_after, w_after - w_before, wp_before, wp_after, &
         safe_sqrt(alpha2_before, alpha_before_error), safe_sqrt(alpha2_after, alpha_after_error), &
         x_jump, z_jump, pi_jump, norm2(x_current), norm2(x_next), sqrt(sum(abs(z_current)**2)), &
         sqrt(sum(abs(z_next)**2)), norm2(pi_current), norm2(pi_next), &
         logical_to_int(h_before_error), logical_to_int(h_after_error), &
         logical_to_int(action_before_error), logical_to_int(action_after_error), &
         logical_to_int(alpha_before_error), logical_to_int(alpha_after_error)
   end subroutine run_one_step

   subroutine state_scalars(flow_time_value, z_state, jac_state, pi_state, h_value, h_error, kinetic, &
                            action_re, action_im, action_error, w_value, wprime, alpha2, alpha_error)
      real(dp), intent(in) :: flow_time_value, pi_state(:)
      complex(dp), intent(in) :: z_state(:), jac_state(:, :)
      real(dp), intent(out) :: h_value, kinetic, action_re, action_im, w_value, wprime, alpha2
      logical, intent(out) :: h_error, action_error, alpha_error
      complex(dp) :: action_value

      h_value = huge(1.0_dp)
      kinetic = huge(1.0_dp)
      action_re = huge(1.0_dp)
      action_im = huge(1.0_dp)
      w_value = huge(1.0_dp)
      wprime = huge(1.0_dp)
      alpha2 = huge(1.0_dp)
      action_error = .true.
      call calculate_action(z_state, action_value)
      if (all(ieee_is_finite([real(action_value, dp), aimag(action_value)]))) then
         action_re = real(action_value, dp)
         action_im = aimag(action_value)
         action_error = .false.
      end if
      call wv_potential_value_and_derivative(potential, flow_time_value, w_value, wprime, h_error)
      if (.not. h_error) then
         call wv_calculate_hamiltonian(z_state, pi_state, w_value, h_value, h_error)
      end if
      if (all(ieee_is_finite(pi_state))) then
         kinetic = 0.5_dp*dot_product(pi_state, pi_state)
      end if
      call wv_dense_alpha2(z_state, jac_state, alpha2, alpha_error)
   end subroutine state_scalars

   subroutine write_step_header(unit_id)
      integer, intent(in) :: unit_id
      write (unit_id, '(A)') "record,base_seed,momentum_cycle,attempt,momentum_sign,step,"// &
         "t_before,t_after,dt,error,status,bounced,solver_stop_reason,solver_iterations,residual_norm,"// &
         "h_before,h_after,delta_h_step,kinetic_before,kinetic_after,delta_kinetic,"// &
         "action_re_before,action_re_after,delta_action_re,action_im_before,action_im_after,delta_action_im,"// &
         "w_before,w_after,delta_w,wprime_before,wprime_after,alpha_before,alpha_after,"// &
         "x_jump,z_jump,pi_jump,x_norm_before,x_norm_after,z_norm_before,z_norm_after,pi_norm_before,pi_norm_after,"// &
         "h_before_error,h_after_error,action_before_error,action_after_error,alpha_before_error,alpha_after_error"
   end subroutine write_step_header

   real(dp) function safe_sqrt(value, failed)
      real(dp), intent(in) :: value
      logical, intent(in) :: failed

      if (failed .or. value < 0.0_dp) then
         safe_sqrt = -1.0_dp
      else
         safe_sqrt = sqrt(value)
      end if
   end function safe_sqrt

   integer function logical_to_int(value)
      logical, intent(in) :: value

      if (value) then
         logical_to_int = 1
      else
         logical_to_int = 0
      end if
   end function logical_to_int
end program probe_wv_hmc_step_trace

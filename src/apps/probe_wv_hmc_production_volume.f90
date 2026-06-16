program probe_wv_hmc_production_volume
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use, intrinsic :: iso_fortran_env, only: int64
   use model, only: calculate_action, ds
   use param_mod, only: config, read_parameters, set_derivative_mode
   use runtime_env_mod, only: parse_int_env, parse_real_env, read_string_env, to_lower_ascii
   use solve_flow, only: flow_at, flow_workspace_t, intode_diagnostics_context_t
   use tltm_rng, only: tltm_rng_domain_wv_hmc_momentum, tltm_rng_fill_normal
   use utils, only: complex_to_real, dp, real_to_complex
   use wv_hmc_constraints, only: wv_set_boundary_policy
   use wv_hmc_kernels, only: wv_force_dense_with_jacobian, wv_project_dense_with_jacobian, wv_xi_from_action_gradient
   use wv_hmc_potential, only: wv_potential_paper_wall, wv_potential_profile_t, wv_potential_zero
   use wv_hmc_potential, only: wv_potential_value_and_derivative
   use wv_hmc_trajectory, only: wv_trajectory_dense, wv_trajectory_diagnostics_t
   implicit none

   character(len=512) :: state_bank_file, output_csv, w_profile_name, boundary_policy_name, momentum_mode_name
   logical :: has_state_bank_file, has_output_csv, has_w_profile, has_boundary_policy, has_momentum_mode, error
   logical :: volume_error, force_probe_error
   integer :: n, state_size, record_count, record_start, record_stride, record_limit
   integer :: record_slot, record_index, state_unit, csv_unit, status, volume_status, force_status, row_status
   integer :: num_steps, constraint_max_iter, volume_base_seed, volume_attempt_index, volume_momentum_sign
   integer(int64) :: file_size, record_bytes
   real(dp) :: step_size, t0, t1, d0, d1, w_gamma, w_c0, w_c1
   real(dp) :: constraint_tol, fd_eps, momentum_scale
   real(dp) :: flow_time, logdet_map, expected_logdet, induced_error, coordinate_error
   real(dp) :: force_fd, force_directional, force_error
   real(dp) :: logdet_g_initial, logdet_g_final
   real(dp), allocatable :: x(:), y0(:), y_out(:)
   type(wv_potential_profile_t) :: potential

   call read_parameters()
   call set_derivative_mode("manual")

   n = config%state%physical_size
   state_size = n
   if (state_size <= 0) then
      write (*, '(A)') "ERROR invalid_physical_state_size"
      stop 2
   end if

   state_bank_file = ""
   output_csv = "output/wv_hmc_production_volume_probe.csv"
   w_profile_name = "paper_wall"
   boundary_policy_name = "normal_reflect"
   momentum_mode_name = "deterministic"
   step_size = 0.008_dp
   num_steps = 1
   t0 = 1.0e-4_dp
   t1 = 0.03_dp
   d0 = 1.0e-4_dp
   d1 = 0.005_dp
   w_gamma = 55.0_dp
   w_c0 = 1.0_dp
   w_c1 = 1.0_dp
   constraint_tol = 1.0e-10_dp
   constraint_max_iter = 192
   fd_eps = 2.0e-7_dp
   momentum_scale = 0.03_dp
   volume_base_seed = 20260604
   volume_attempt_index = 1
   volume_momentum_sign = 1
   record_start = 0
   record_stride = 1
   record_limit = 4

   call read_string_env("WV_VOLUME_STATE_BANK_FILE", state_bank_file, has_state_bank_file)
   call read_string_env("WV_VOLUME_OUTPUT_CSV", output_csv, has_output_csv)
   call read_string_env("WV_VOLUME_W_PROFILE", w_profile_name, has_w_profile)
   call read_string_env("WV_VOLUME_BOUNDARY_POLICY", boundary_policy_name, has_boundary_policy)
   call read_string_env("WV_VOLUME_MOMENTUM_MODE", momentum_mode_name, has_momentum_mode)
   w_profile_name = to_lower_ascii(adjustl(w_profile_name))
   boundary_policy_name = to_lower_ascii(adjustl(boundary_policy_name))
   momentum_mode_name = to_lower_ascii(adjustl(momentum_mode_name))
   call parse_real_env("WV_VOLUME_STEP_SIZE", step_size)
   call parse_int_env("WV_VOLUME_NUM_STEPS", num_steps)
   call parse_real_env("WV_VOLUME_T0", t0)
   call parse_real_env("WV_VOLUME_T1", t1)
   call parse_real_env("WV_VOLUME_D0", d0)
   call parse_real_env("WV_VOLUME_D1", d1)
   call parse_real_env("WV_VOLUME_W_GAMMA", w_gamma)
   call parse_real_env("WV_VOLUME_W_C0", w_c0)
   call parse_real_env("WV_VOLUME_W_C1", w_c1)
   call parse_real_env("WV_VOLUME_CONSTRAINT_TOL", constraint_tol)
   call parse_int_env("WV_VOLUME_CONSTRAINT_MAX_ITER", constraint_max_iter)
   call parse_real_env("WV_VOLUME_FD_EPS", fd_eps)
   call parse_real_env("WV_VOLUME_MOMENTUM_SCALE", momentum_scale)
   call parse_int_env("WV_VOLUME_BASE_SEED", volume_base_seed)
   call parse_int_env("WV_VOLUME_ATTEMPT_INDEX", volume_attempt_index)
   call parse_int_env("WV_VOLUME_MOMENTUM_SIGN", volume_momentum_sign)
   call parse_int_env("WV_VOLUME_RECORD_START", record_start)
   call parse_int_env("WV_VOLUME_RECORD_STRIDE", record_stride)
   call parse_int_env("WV_VOLUME_RECORD_LIMIT", record_limit)

   if (.not. has_state_bank_file .or. len_trim(state_bank_file) <= 0) then
      write (*, '(A)') "ERROR WV_VOLUME_STATE_BANK_FILE is required"
      stop 2
   end if
   if (record_start < 0 .or. record_stride < 1 .or. record_limit < 1) then
      write (*, '(A)') "ERROR invalid_record_controls"
      stop 2
   end if
   if (step_size <= 0.0_dp .or. num_steps < 1 .or. t1 <= t0 .or. constraint_tol <= 0.0_dp .or. fd_eps <= 0.0_dp) then
      write (*, '(A)') "ERROR invalid_volume_probe_controls"
      stop 2
   end if
   select case (trim(momentum_mode_name))
   case ("deterministic", "rng")
      continue
   case default
      write (*, '(A,1X,A)') "ERROR invalid_momentum_mode", trim(momentum_mode_name)
      stop 2
   end select
   if (volume_attempt_index < 1) then
      write (*, '(A)') "ERROR invalid_volume_attempt_index"
      stop 2
   end if
   if (volume_momentum_sign /= 1 .and. volume_momentum_sign /= -1) then
      write (*, '(A)') "ERROR invalid_volume_momentum_sign"
      stop 2
   end if

   call wv_set_boundary_policy(trim(boundary_policy_name), error)
   if (error) then
      write (*, '(A,1X,A)') "ERROR invalid_boundary_policy", trim(boundary_policy_name)
      stop 2
   end if
   select case (trim(w_profile_name))
   case ("zero")
      potential = wv_potential_zero()
   case ("paper_wall")
      potential = wv_potential_paper_wall(t0, t1, d0, d1, w_gamma, w_c0, w_c1)
   case default
      write (*, '(A,1X,A)') "ERROR invalid_w_profile", trim(w_profile_name)
      stop 2
   end select

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
   record_limit = min(record_limit, (record_count - record_start + record_stride - 1)/record_stride)

   allocate (x(n), y0(2*(n + 1)), y_out(2*(n + 1)))

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
   write (csv_unit, '(A)') "record,flow_time,status,skipped,logdet_map,expected_logdet,induced_error," // &
      "coordinate_error,force_fd,force_directional,force_error"

   do record_slot = 1, record_limit
      record_index = record_start + (record_slot - 1)*record_stride
      call read_state_record(state_unit, record_index, record_bytes, flow_time, x, status)
      if (status /= 0) then
         write (csv_unit, '(*(g0,:,","))') record_index, flow_time, status, 1, huge(1.0_dp), huge(1.0_dp), &
            huge(1.0_dp), huge(1.0_dp)
         cycle
      end if
      call build_probe_coordinate(flow_time, x, record_index, y0, error, status)
      if (error) then
         write (csv_unit, '(*(g0,:,","))') record_index, flow_time, status, 1, huge(1.0_dp), huge(1.0_dp), &
            huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), huge(1.0_dp)
         cycle
      end if
      call volume_contract_for_coordinate(y0, y_out, logdet_map, expected_logdet, induced_error, coordinate_error, &
                                          volume_error, volume_status, logdet_g_initial, logdet_g_final)
      call force_fd_for_coordinate(y0, force_fd, force_directional, force_error, force_probe_error, force_status)
      row_status = volume_status
      if (row_status == 0 .and. force_status /= 0) row_status = force_status
      error = volume_error .or. force_probe_error
      write (csv_unit, '(*(g0,:,","))') record_index, flow_time, row_status, logical_to_int(error), logdet_map, &
         expected_logdet, induced_error, coordinate_error, force_fd, force_directional, force_error
   end do

   close (state_unit)
   close (csv_unit)
   write (*, '(*(g0,1X))') "WV_HMC_PRODUCTION_VOLUME_PROBE_COMPLETE", "state_bank", trim(state_bank_file), &
      "output_csv", trim(output_csv), "record_count", record_count, "record_limit", record_limit

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

   subroutine build_probe_coordinate(flow_time, x_state, record_index, y, error, status)
      real(dp), intent(in) :: flow_time, x_state(:)
      integer, intent(in) :: record_index
      real(dp), intent(out) :: y(:)
      logical, intent(out) :: error
      integer, intent(out) :: status

      integer :: m_dim, j
      real(dp) :: norm_v
      real(dp) :: c, alpha2
      real(dp), allocatable :: e_basis(:, :), raw_pi(:), projected_pi(:), rejected_pi(:), xi_real(:), velocity(:)
      complex(dp), allocatable :: z_local(:), jac_local(:, :), grad(:), xi(:)
      logical :: local_error

      m_dim = size(x_state) + 1
      y = 0.0_dp
      y(1) = flow_time
      y(2:m_dim) = x_state
      error = .true.
      status = 0
      select case (trim(momentum_mode_name))
      case ("deterministic")
         do j = 1, m_dim
            y(m_dim + j) = sin(0.731_dp*real(j + 3*record_index, dp)) + &
                           0.5_dp*cos(0.317_dp*real(2*j + record_index, dp))
         end do
         norm_v = norm2(y(m_dim + 1:2*m_dim))
         if (norm_v > 0.0_dp) y(m_dim + 1:2*m_dim) = momentum_scale*y(m_dim + 1:2*m_dim)/norm_v
      case ("rng")
         allocate (e_basis(2*size(x_state), m_dim), raw_pi(2*size(x_state)), projected_pi(2*size(x_state)), &
                   rejected_pi(2*size(x_state)), xi_real(2*size(x_state)), velocity(m_dim), z_local(size(x_state)), &
                   jac_local(size(x_state), size(x_state)), grad(size(x_state)), xi(size(x_state)))
         call flow_at(flow_time, x_state, z_local, jac_local, local_error, status)
         if (local_error) return
         call worldvolume_tangent_basis(z_local, jac_local, e_basis, local_error)
         if (local_error) then
            status = -20
            return
         end if
         call tltm_rng_fill_normal(raw_pi, tltm_rng_domain_wv_hmc_momentum, volume_base_seed, record_index + 1, &
                                   volume_attempt_index, 1)
         if (volume_momentum_sign < 0) raw_pi = -raw_pi
         call ds(z_local, grad)
         call wv_xi_from_action_gradient(grad, xi, local_error)
         if (local_error) then
            status = -21
            return
         end if
         call complex_to_real(xi, xi_real)
         call wv_project_dense_with_jacobian(raw_pi, xi_real, jac_local, projected_pi, rejected_pi, c, alpha2, &
                                             local_error)
         if (local_error) then
            status = -22
            return
         end if
         call tangent_velocity_coordinates(e_basis, projected_pi, velocity, local_error)
         if (local_error) then
            status = -23
            return
         end if
         y(m_dim + 1:2*m_dim) = velocity
      end select
      error = .not. all(ieee_is_finite(y))
      if (error) status = -24
   end subroutine build_probe_coordinate

   subroutine volume_contract_for_coordinate(y_in, y_base_out, logdet_map, expected_logdet, induced_error, &
                                             coordinate_error, error, status, logdet_g_initial, logdet_g_final)
      real(dp), intent(in) :: y_in(:)
      real(dp), intent(out) :: y_base_out(:), logdet_map, expected_logdet, induced_error, coordinate_error
      logical, intent(out) :: error
      integer, intent(out) :: status
      real(dp), intent(out) :: logdet_g_initial, logdet_g_final

      integer :: j, y_dim
      real(dp) :: eps_j, logdet_g_initial_fd, logdet_g_final_fd
      real(dp), allocatable :: y_plus(:), y_minus(:), y_plus_out(:), y_minus_out(:), jacobian_fd(:, :)
      logical :: local_error, det_error

      y_dim = size(y_in)
      allocate (y_plus(y_dim), y_minus(y_dim), y_plus_out(y_dim), y_minus_out(y_dim), jacobian_fd(y_dim, y_dim))
      logdet_map = huge(1.0_dp)
      expected_logdet = huge(1.0_dp)
      induced_error = huge(1.0_dp)
      coordinate_error = huge(1.0_dp)
      logdet_g_initial = huge(1.0_dp)
      logdet_g_final = huge(1.0_dp)
      error = .true.
      status = 0

      call phase_space_map_for_volume(y_in, y_base_out, logdet_g_initial, logdet_g_final, local_error, status)
      if (local_error) return

      do j = 1, y_dim
         eps_j = fd_eps*max(1.0_dp, abs(y_in(j)))
         y_plus = y_in
         y_minus = y_in
         y_plus(j) = y_plus(j) + eps_j
         y_minus(j) = y_minus(j) - eps_j
         call phase_space_map_for_volume(y_plus, y_plus_out, logdet_g_initial_fd, logdet_g_final_fd, local_error, status)
         if (local_error) return
         call phase_space_map_for_volume(y_minus, y_minus_out, logdet_g_initial_fd, logdet_g_final_fd, local_error, status)
         if (local_error) return
         jacobian_fd(:, j) = (y_plus_out - y_minus_out)/(2.0_dp*eps_j)
      end do

      call log_abs_det_real_square(jacobian_fd, logdet_map, det_error)
      if (det_error) then
         status = -200
         return
      end if
      expected_logdet = logdet_g_initial - logdet_g_final
      induced_error = abs(logdet_map - expected_logdet)
      coordinate_error = abs(logdet_map)
      error = .false.
   end subroutine volume_contract_for_coordinate

   subroutine force_fd_for_coordinate(y_in, directional_fd, force_directional, force_error, error, status)
      real(dp), intent(in) :: y_in(:)
      real(dp), intent(out) :: directional_fd, force_directional, force_error
      logical, intent(out) :: error
      integer, intent(out) :: status

      integer :: m_dim, n_state
      real(dp) :: flow_time, w_value, wprime, alpha2, eps_local
      real(dp) :: tangent_real(size(y_in)/2*2 - 2)
      real(dp), allocatable :: x_state(:), e_basis(:, :), force(:), v_coords(:)
      complex(dp), allocatable :: z(:), jac(:, :), grad(:), xi(:), tangent_complex(:)
      logical :: local_error

      directional_fd = huge(1.0_dp)
      force_directional = huge(1.0_dp)
      force_error = huge(1.0_dp)
      error = .true.
      status = 0
      if (mod(size(y_in), 2) /= 0) return
      m_dim = size(y_in)/2
      n_state = m_dim - 1
      if (n_state <= 0) return
      allocate (x_state(n_state), e_basis(2*n_state, m_dim), force(2*n_state), v_coords(m_dim), &
                z(n_state), jac(n_state, n_state), grad(n_state), xi(n_state), tangent_complex(n_state))

      flow_time = y_in(1)
      x_state = y_in(2:m_dim)
      v_coords = y_in(m_dim + 1:2*m_dim)
      call flow_at(flow_time, x_state, z, jac, local_error, status)
      if (local_error) return
      call worldvolume_tangent_basis(z, jac, e_basis, local_error)
      if (local_error) then
         status = -300
         return
      end if
      tangent_real = matmul(e_basis, v_coords)
      call real_to_complex(tangent_real, tangent_complex)
      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, local_error)
      if (local_error) then
         status = -301
         return
      end if
      call complex_to_real(xi, tangent_real)
      call wv_potential_value_and_derivative(potential, flow_time, w_value, wprime, local_error)
      if (local_error) then
         status = -302
         return
      end if
      call wv_force_dense_with_jacobian(tangent_real, jac, wprime, force, alpha2, local_error)
      if (local_error) then
         status = -303
         return
      end if
      tangent_real = matmul(e_basis, v_coords)
      force_directional = 2.0_dp*dot_product(force, tangent_real)
      eps_local = max(1.0e-5_dp, min(1.0e-4_dp, 0.1_dp/max(1.0_dp, norm2(tangent_real))))
      call finite_difference_potential_along_tangent(flow_time, z, tangent_complex, v_coords(1), eps_local, &
                                                     directional_fd, local_error, status)
      if (local_error) return
      force_error = abs(directional_fd - force_directional)
      error = .not. (ieee_is_finite(force_error) .and. force_error <= 1.0e-6_dp*max(1.0_dp, abs(directional_fd)))
      if (error) status = -304
   end subroutine force_fd_for_coordinate

   subroutine finite_difference_potential_along_tangent(flow_time, z, tangent, direction_t, eps_local, directional_fd, &
                                                        error, status)
      real(dp), intent(in) :: flow_time, direction_t, eps_local
      complex(dp), intent(in) :: z(:), tangent(:)
      real(dp), intent(out) :: directional_fd
      logical, intent(out) :: error
      integer, intent(out) :: status

      real(dp) :: value_p2, value_p1, value_m1, value_m2
      logical :: err_p2, err_p1, err_m1, err_m2
      integer :: status_p2, status_p1, status_m1, status_m2

      directional_fd = huge(1.0_dp)
      error = .true.
      status = 0
      call evaluate_shifted_potential(flow_time, z, tangent, direction_t, 2.0_dp*eps_local, value_p2, err_p2, status_p2)
      call evaluate_shifted_potential(flow_time, z, tangent, direction_t, eps_local, value_p1, err_p1, status_p1)
      call evaluate_shifted_potential(flow_time, z, tangent, direction_t, -eps_local, value_m1, err_m1, status_m1)
      call evaluate_shifted_potential(flow_time, z, tangent, direction_t, -2.0_dp*eps_local, value_m2, err_m2, status_m2)
      if (err_p2 .or. err_p1 .or. err_m1 .or. err_m2) then
         status = -4000000 - max(max(status_p2, status_p1), max(status_m1, status_m2))
         return
      end if
      directional_fd = (-value_p2 + 8.0_dp*value_p1 - 8.0_dp*value_m1 + value_m2)/(12.0_dp*eps_local)
      error = .not. ieee_is_finite(directional_fd)
      if (error) status = -401
   end subroutine finite_difference_potential_along_tangent

   subroutine evaluate_shifted_potential(flow_time, z, tangent, direction_t, offset, value, error, status)
      real(dp), intent(in) :: flow_time, direction_t, offset
      complex(dp), intent(in) :: z(:), tangent(:)
      real(dp), intent(out) :: value
      logical, intent(out) :: error
      integer, intent(out) :: status

      real(dp) :: shifted_time, w_shifted, wprime_shifted
      complex(dp) :: z_shifted(size(z)), action_shifted

      value = huge(1.0_dp)
      error = .true.
      status = 0
      shifted_time = flow_time + offset*direction_t
      z_shifted = z + offset*tangent
      call calculate_action(z_shifted, action_shifted)
      if ((.not. ieee_is_finite(real(action_shifted, dp))) .or. (.not. ieee_is_finite(aimag(action_shifted)))) then
         status = -1
         return
      end if
      call wv_potential_value_and_derivative(potential, shifted_time, w_shifted, wprime_shifted, error)
      if (error) then
         status = -2
         return
      end if
      value = real(action_shifted, dp) + w_shifted
      error = .not. ieee_is_finite(value)
      if (error) status = -3
   end subroutine evaluate_shifted_potential

   subroutine phase_space_map_for_volume(y_in, y_out, logdet_g_initial, logdet_g_final, error, status)
      real(dp), intent(in) :: y_in(:)
      real(dp), intent(out) :: y_out(:), logdet_g_initial, logdet_g_final
      logical, intent(out) :: error
      integer, intent(out) :: status

      integer :: m_dim, n_state
      real(dp) :: flow_time, flow_time_out, residual_norm
      real(dp), allocatable :: x_state(:), x_out(:), pi(:), pi_out(:), e_basis(:, :), v_out(:)
      complex(dp), allocatable :: z(:), jac(:, :), z_out(:), jac_out(:, :)
      type(wv_trajectory_diagnostics_t) :: diagnostics
      type(flow_workspace_t) :: flow_workspace
      type(intode_diagnostics_context_t), target :: intode_diagnostics

      y_out = 0.0_dp
      logdet_g_initial = huge(1.0_dp)
      logdet_g_final = huge(1.0_dp)
      error = .true.
      status = 0
      if (mod(size(y_in), 2) /= 0) return
      if (size(y_out) /= size(y_in)) return
      m_dim = size(y_in)/2
      n_state = m_dim - 1
      if (n_state <= 0) return
      allocate (x_state(n_state), x_out(n_state), pi(2*n_state), pi_out(2*n_state), e_basis(2*n_state, m_dim), &
                v_out(m_dim), z(n_state), jac(n_state, n_state), z_out(n_state), jac_out(n_state, n_state))

      flow_time = y_in(1)
      x_state = y_in(2:m_dim)
      call flow_at(flow_time, x_state, z, jac, error, status)
      if (error) return
      call worldvolume_tangent_basis(z, jac, e_basis, error)
      if (error) then
         status = -10
         return
      end if
      call log_gram_from_basis(e_basis, logdet_g_initial, error)
      if (error) then
         status = -11
         return
      end if
      pi = matmul(e_basis, y_in(m_dim + 1:2*m_dim))

      call wv_trajectory_dense(step_size, num_steps, potential, t0, t1, d0, d1, flow_time, x_state, z, jac, pi, &
                               flow_time_out, x_out, z_out, jac_out, pi_out, diagnostics, error, status, &
                               flow_workspace, intode_diagnostics, constraint_tol, constraint_max_iter, &
                               adaptive_stop_enabled=.false.)
      if (error) return
      if (diagnostics%bounced_steps /= 0) then
         error = .true.
         status = -100
         return
      end if
      residual_norm = diagnostics%max_constraint_residual
      if ((.not. ieee_is_finite(residual_norm)) .or. residual_norm > 1.0e-8_dp) then
         error = .true.
         status = -101
         return
      end if

      call worldvolume_tangent_basis(z_out, jac_out, e_basis, error)
      if (error) then
         status = -12
         return
      end if
      call log_gram_from_basis(e_basis, logdet_g_final, error)
      if (error) then
         status = -13
         return
      end if
      call tangent_velocity_coordinates(e_basis, pi_out, v_out, error)
      if (error) then
         status = -14
         return
      end if

      y_out(1) = flow_time_out
      y_out(2:m_dim) = x_out
      y_out(m_dim + 1:2*m_dim) = v_out
      error = .false.
   end subroutine phase_space_map_for_volume

   subroutine worldvolume_tangent_basis(z, jac, e_basis, error)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: e_basis(:, :)
      logical, intent(out) :: error

      integer :: n_local, i, j
      real(dp) :: xi_real(2*size(z))
      complex(dp) :: grad(size(z)), xi(size(z))

      error = .true.
      n_local = size(z)
      if (size(jac, 1) /= n_local .or. size(jac, 2) /= n_local) return
      if (size(e_basis, 1) /= 2*n_local .or. size(e_basis, 2) /= n_local + 1) return
      call ds(z, grad)
      call wv_xi_from_action_gradient(grad, xi, error)
      if (error) return
      call complex_to_real(xi, xi_real)
      e_basis(:, 1) = xi_real
      do j = 1, n_local
         do i = 1, n_local
            e_basis(2*i - 1, j + 1) = real(jac(i, j), dp)
            e_basis(2*i, j + 1) = aimag(jac(i, j))
         end do
      end do
      error = .not. all(ieee_is_finite(e_basis))
   end subroutine worldvolume_tangent_basis

   subroutine log_gram_from_basis(e_basis, logdet_g, error)
      real(dp), intent(in) :: e_basis(:, :)
      real(dp), intent(out) :: logdet_g
      logical, intent(out) :: error

      real(dp) :: gram(size(e_basis, 2), size(e_basis, 2))

      gram = matmul(transpose(e_basis), e_basis)
      call log_abs_det_real_square(gram, logdet_g, error)
   end subroutine log_gram_from_basis

   subroutine tangent_velocity_coordinates(e_basis, pi, velocity, error)
      real(dp), intent(in) :: e_basis(:, :), pi(:)
      real(dp), intent(out) :: velocity(:)
      logical, intent(out) :: error

      real(dp) :: gram(size(e_basis, 2), size(e_basis, 2)), rhs(size(e_basis, 2))

      velocity = 0.0_dp
      error = .true.
      if (size(pi) /= size(e_basis, 1) .or. size(velocity) /= size(e_basis, 2)) return
      gram = matmul(transpose(e_basis), e_basis)
      rhs = matmul(transpose(e_basis), pi)
      call solve_real_square(gram, rhs, velocity, error)
   end subroutine tangent_velocity_coordinates

   subroutine log_abs_det_real_square(matrix, log_abs_det, error)
      real(dp), intent(in) :: matrix(:, :)
      real(dp), intent(out) :: log_abs_det
      logical, intent(out) :: error

      integer :: n_local, info, i
      integer, allocatable :: ipiv(:)
      real(dp), allocatable :: lu(:, :)
      external :: dgetrf

      log_abs_det = 0.0_dp
      error = .true.
      n_local = size(matrix, 1)
      if (n_local <= 0 .or. size(matrix, 2) /= n_local) return
      if (.not. all(ieee_is_finite(matrix))) return
      allocate (lu(n_local, n_local), ipiv(n_local))
      lu = matrix
      call dgetrf(n_local, n_local, lu, n_local, ipiv, info)
      if (info /= 0) return
      do i = 1, n_local
         if ((.not. ieee_is_finite(lu(i, i))) .or. abs(lu(i, i)) <= 0.0_dp) return
         log_abs_det = log_abs_det + log(abs(lu(i, i)))
      end do
      error = .false.
   end subroutine log_abs_det_real_square

   subroutine solve_real_square(matrix, rhs, solution, error)
      real(dp), intent(in) :: matrix(:, :), rhs(:)
      real(dp), intent(out) :: solution(:)
      logical, intent(out) :: error

      integer :: n_local, info
      integer, allocatable :: ipiv(:)
      real(dp), allocatable :: lu(:, :), work_rhs(:, :)
      external :: dgesv

      solution = 0.0_dp
      error = .true.
      n_local = size(matrix, 1)
      if (n_local <= 0 .or. size(matrix, 2) /= n_local) return
      if (size(rhs) /= n_local .or. size(solution) /= n_local) return
      if (.not. all(ieee_is_finite(matrix)) .or. .not. all(ieee_is_finite(rhs))) return
      allocate (lu(n_local, n_local), work_rhs(n_local, 1), ipiv(n_local))
      lu = matrix
      work_rhs(:, 1) = rhs
      call dgesv(n_local, 1, lu, n_local, ipiv, work_rhs, n_local, info)
      if (info /= 0) return
      solution = work_rhs(:, 1)
      error = .not. all(ieee_is_finite(solution))
   end subroutine solve_real_square

   integer function logical_to_int(value)
      logical, intent(in) :: value

      if (value) then
         logical_to_int = 1
      else
         logical_to_int = 0
      end if
   end function logical_to_int

end program probe_wv_hmc_production_volume

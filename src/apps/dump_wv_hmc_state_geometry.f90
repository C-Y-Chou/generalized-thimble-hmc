program dump_wv_hmc_state_geometry
   use, intrinsic :: iso_fortran_env, only: int64
   use model, only: calculate_action, ds
   use param_mod, only: config, read_parameters, set_derivative_mode
   use runtime_env_mod, only: parse_int_env, parse_real_env, read_string_env, to_lower_ascii
   use solve_flow, only: flow_at
   use tltm_rng, only: tltm_rng_domain_wv_hmc_momentum, tltm_rng_fill_normal
   use utils, only: complex_to_real, dp
   use wv_hmc_kernels, only: wv_project_dense_with_jacobian, wv_xi_from_action_gradient
   use wv_hmc_measurement, only: wv_dense_alpha2, wv_dense_measurement_factor, wv_measurement_factor_t
   use wv_hmc_potential, only: wv_potential_paper_wall, wv_potential_profile_t, &
                               wv_potential_value_and_derivative, wv_potential_zero
   implicit none

   character(len=512) :: state_bank_file, output_prefix, w_profile_name
   logical :: has_state_bank_file, has_output_prefix, has_w_profile
   logical :: error, measurement_error, projection_error, alpha_error
   integer :: n, state_unit, status, record_index, base_seed, momentum_cycle, attempt_index, momentum_sign
   integer(int64) :: file_size, record_bytes, pos
   real(dp) :: flow_time, t0, t1, d0, d1, w_gamma, w_c0, w_c1
   real(dp) :: w_value, wprime, alpha2, projection_c, projected_alpha2
   real(dp), allocatable :: x(:), raw_pi(:), projected_pi(:), rejected_pi(:), xi_real(:)
   complex(dp), allocatable :: z(:), jac(:, :), grad(:), xi(:)
   complex(dp) :: action_value
   type(wv_potential_profile_t) :: potential
   type(wv_measurement_factor_t) :: factor

   call read_parameters()
   call set_derivative_mode("manual")

   n = config%state%physical_size
   if (n <= 0) then
      write (*, '(A)') "ERROR invalid_physical_state_size"
      stop 2
   end if

   state_bank_file = ""
   output_prefix = "output/wv_hmc_state_geometry"
   w_profile_name = "paper_wall"
   record_index = 0
   base_seed = 9440026
   momentum_cycle = 10950
   attempt_index = 1
   momentum_sign = 1
   t0 = 1.0e-4_dp
   t1 = 0.03_dp
   d0 = 1.0e-4_dp
   d1 = 0.005_dp
   w_gamma = 55.0_dp
   w_c0 = 1.0_dp
   w_c1 = 1.0_dp

   call read_string_env("WV_DUMP_STATE_BANK_FILE", state_bank_file, has_state_bank_file)
   call read_string_env("WV_DUMP_OUTPUT_PREFIX", output_prefix, has_output_prefix)
   call read_string_env("WV_DUMP_W_PROFILE", w_profile_name, has_w_profile)
   w_profile_name = to_lower_ascii(adjustl(w_profile_name))
   call parse_int_env("WV_DUMP_RECORD_INDEX", record_index)
   call parse_int_env("WV_DUMP_BASE_SEED", base_seed)
   call parse_int_env("WV_DUMP_MOMENTUM_CYCLE", momentum_cycle)
   call parse_int_env("WV_DUMP_ATTEMPT_INDEX", attempt_index)
   call parse_int_env("WV_DUMP_MOMENTUM_SIGN", momentum_sign)
   call parse_real_env("WV_DUMP_T0", t0)
   call parse_real_env("WV_DUMP_T1", t1)
   call parse_real_env("WV_DUMP_D0", d0)
   call parse_real_env("WV_DUMP_D1", d1)
   call parse_real_env("WV_DUMP_W_GAMMA", w_gamma)
   call parse_real_env("WV_DUMP_W_C0", w_c0)
   call parse_real_env("WV_DUMP_W_C1", w_c1)

   if (.not. has_state_bank_file .or. len_trim(state_bank_file) <= 0) then
      write (*, '(A)') "ERROR WV_DUMP_STATE_BANK_FILE is required"
      stop 2
   end if
   if (record_index < 0 .or. attempt_index < 1 .or. momentum_cycle < 1) then
      write (*, '(A)') "ERROR invalid_dump_indices"
      stop 2
   end if
   if (momentum_sign /= 1 .and. momentum_sign /= -1) then
      write (*, '(A)') "ERROR invalid_momentum_sign"
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

   record_bytes = int(n + 1, int64)*8_int64
   inquire (file=trim(state_bank_file), size=file_size)
   if (file_size <= 0_int64 .or. mod(file_size, record_bytes) /= 0_int64) then
      write (*, '(*(g0,1X))') "ERROR invalid_state_bank_size", trim(state_bank_file), file_size, record_bytes
      stop 2
   end if
   if (int(record_index, int64) >= file_size/record_bytes) then
      write (*, '(*(g0,1X))') "ERROR record_index_out_of_range", record_index, file_size/record_bytes
      stop 2
   end if

   allocate (x(n), raw_pi(2*n), projected_pi(2*n), rejected_pi(2*n), xi_real(2*n))
   allocate (z(n), jac(n, n), grad(n), xi(n))

   open (newunit=state_unit, file=trim(state_bank_file), status='old', access='stream', form='unformatted', &
         action='read', iostat=status)
   if (status /= 0) then
      write (*, '(A,1X,A)') "ERROR cannot_open_state_bank", trim(state_bank_file)
      stop 2
   end if
   pos = int(record_index, int64)*record_bytes + 1_int64
   read (state_unit, pos=pos, iostat=status) flow_time, x
   close (state_unit)
   if (status /= 0) then
      write (*, '(*(g0,1X))') "ERROR cannot_read_state_record", record_index, status
      stop 2
   end if

   call flow_at(flow_time, x, z, jac, error, status)
   if (error) then
      write (*, '(*(g0,1X))') "ERROR flow_at_failed", flow_time, status
      stop 2
   end if
   call calculate_action(z, action_value)
   call ds(z, grad)
   call wv_xi_from_action_gradient(grad, xi, error)
   if (error) then
      write (*, '(A)') "ERROR xi_from_action_gradient_failed"
      stop 2
   end if
   call complex_to_real(xi, xi_real)
   call wv_potential_value_and_derivative(potential, flow_time, w_value, wprime, error)
   if (error) then
      write (*, '(A)') "ERROR w_potential_failed"
      stop 2
   end if
   call wv_dense_alpha2(z, jac, alpha2, alpha_error)
   call wv_dense_measurement_factor(z, jac, factor, measurement_error, w_value)

   call tltm_rng_fill_normal(raw_pi, tltm_rng_domain_wv_hmc_momentum, base_seed, momentum_cycle, attempt_index, 1)
   if (momentum_sign < 0) raw_pi = -raw_pi
   call wv_project_dense_with_jacobian(raw_pi, xi_real, jac, projected_pi, rejected_pi, projection_c, &
                                       projected_alpha2, projection_error)

   call write_summary(trim(output_prefix)//"_summary.csv")
   call write_x(trim(output_prefix)//"_x.csv")
   call write_complex_vectors(trim(output_prefix)//"_complex_vectors.csv")
   call write_jacobian(trim(output_prefix)//"_jacobian.csv")
   call write_momenta(trim(output_prefix)//"_momenta.csv")
   write (*, '(*(g0,1X))') "WV_HMC_STATE_GEOMETRY_DUMP_COMPLETE", "prefix", trim(output_prefix), &
      "flow_time", flow_time, "momentum_cycle", momentum_cycle

contains

   subroutine write_summary(path)
      character(len=*), intent(in) :: path
      integer :: unit_id, ios

      open (newunit=unit_id, file=trim(path), status='replace', action='write', iostat=ios)
      if (ios /= 0) stop 2
      write (unit_id, '(A)') "record_index,flow_time,n,base_seed,momentum_cycle,attempt_index,momentum_sign,"// &
         "x_norm,z_norm,jac_fro_norm,grad_norm,xi_norm,raw_pi_norm,projected_pi_norm,rejected_pi_norm,"// &
         "projection_error,projection_c,projection_alpha2,alpha_error,alpha,alpha2,w_value,wprime,"// &
         "action_re,action_im,measurement_error,wv_factor_re,wv_factor_im,phase_re,phase_im"
      write (unit_id, '(*(g0,:,","))') record_index, flow_time, n, base_seed, momentum_cycle, attempt_index, &
         momentum_sign, norm2(x), sqrt(sum(abs(z)**2)), sqrt(sum(abs(jac)**2)), sqrt(sum(abs(grad)**2)), &
         sqrt(sum(abs(xi)**2)), norm2(raw_pi), norm2(projected_pi), norm2(rejected_pi), &
         logical_to_int(projection_error), projection_c, projected_alpha2, logical_to_int(alpha_error), &
         safe_sqrt(alpha2, alpha_error), alpha2, w_value, wprime, real(action_value, dp), aimag(action_value), &
         logical_to_int(measurement_error), real(factor%wv_factor, dp), aimag(factor%wv_factor), &
         real(factor%phase_factor, dp), aimag(factor%phase_factor)
      close (unit_id)
   end subroutine write_summary

   subroutine write_x(path)
      character(len=*), intent(in) :: path
      integer :: unit_id, ios, i

      open (newunit=unit_id, file=trim(path), status='replace', action='write', iostat=ios)
      if (ios /= 0) stop 2
      write (unit_id, '(A)') "index,value"
      do i = 1, n
         write (unit_id, '(*(g0,:,","))') i, x(i)
      end do
      close (unit_id)
   end subroutine write_x

   subroutine write_complex_vectors(path)
      character(len=*), intent(in) :: path
      integer :: unit_id, ios, i

      open (newunit=unit_id, file=trim(path), status='replace', action='write', iostat=ios)
      if (ios /= 0) stop 2
      write (unit_id, '(A)') "kind,index,re,im"
      do i = 1, n
         write (unit_id, '(*(g0,:,","))') "z", i, real(z(i), dp), aimag(z(i))
         write (unit_id, '(*(g0,:,","))') "grad", i, real(grad(i), dp), aimag(grad(i))
         write (unit_id, '(*(g0,:,","))') "xi", i, real(xi(i), dp), aimag(xi(i))
      end do
      close (unit_id)
   end subroutine write_complex_vectors

   subroutine write_jacobian(path)
      character(len=*), intent(in) :: path
      integer :: unit_id, ios, i, j

      open (newunit=unit_id, file=trim(path), status='replace', action='write', iostat=ios)
      if (ios /= 0) stop 2
      write (unit_id, '(A)') "row,col,re,im"
      do j = 1, n
         do i = 1, n
            write (unit_id, '(*(g0,:,","))') i, j, real(jac(i, j), dp), aimag(jac(i, j))
         end do
      end do
      close (unit_id)
   end subroutine write_jacobian

   subroutine write_momenta(path)
      character(len=*), intent(in) :: path
      integer :: unit_id, ios, i

      open (newunit=unit_id, file=trim(path), status='replace', action='write', iostat=ios)
      if (ios /= 0) stop 2
      write (unit_id, '(A)') "kind,index,value"
      do i = 1, 2*n
         write (unit_id, '(*(g0,:,","))') "raw_pi", i, raw_pi(i)
         write (unit_id, '(*(g0,:,","))') "projected_pi", i, projected_pi(i)
         write (unit_id, '(*(g0,:,","))') "rejected_pi", i, rejected_pi(i)
      end do
      close (unit_id)
   end subroutine write_momenta

   real(dp) function safe_sqrt(value, failed)
      real(dp), intent(in) :: value
      logical, intent(in) :: failed

      if (failed .or. value <= 0.0_dp) then
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

end program dump_wv_hmc_state_geometry

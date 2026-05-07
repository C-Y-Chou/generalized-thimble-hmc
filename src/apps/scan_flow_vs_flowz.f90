program scan_flow_vs_flowz_app
   use param_mod
   use solve_flow, only: flowz, flow, set_intode_strict_mode
   use utils, only: dp
   use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_quiet_nan
   implicit none

   character(len=256) :: output_file, arg_text
   real(dp) :: seed_min, seed_max, flow_time, imag0, u, frac
   real(dp) :: z_flowz_re, z_flowz_im, z_flow_re, z_flow_im, j_re, j_im, j_abs
   real(dp) :: bad_u_min, bad_u_max, bad_abs_re_min, bad_abs_re_max
   real(dp) :: nanv
   real(dp), allocatable :: x(:)
   complex(dp), allocatable :: z0(:), z_flowz(:), z_flow(:), jac(:, :)
   logical :: err_flowz, err_flow, has_bad_range
   logical :: has_flow_time_arg, has_imag0_arg
   integer :: n_samples, i, unit_out, ios
   integer :: n_flowz_ok, n_flow_ok, n_flowz_only

   if (command_argument_count() < 4) then
      call print_usage_and_stop()
   end if

   call get_command_argument(1, output_file)
   call get_required_real_arg(2, seed_min, "seed_min")
   call get_required_real_arg(3, seed_max, "seed_max")
   call get_required_int_arg(4, n_samples, "n_samples")
   has_flow_time_arg = (command_argument_count() >= 5)
   has_imag0_arg = (command_argument_count() >= 6)

   if (n_samples < 2) then
      write (*, '(A)') "[ERROR] n_samples must be >= 2."
      error stop 1
   end if

   imag0 = 0.0_dp
   if (has_imag0_arg) then
      call get_command_argument(6, arg_text)
      read (arg_text, *, iostat=ios) imag0
      if (ios /= 0) then
         write (*, '(A,A,A)') "[ERROR] Failed to parse imag0='", trim(arg_text), "'."
         error stop 1
      end if
   end if

   call set_intode_strict_mode(.true.)
   call read_parameters()
   flow_time = config%integrator%initial_flow_time

   if (state_seed_size_cfg() /= 1) then
      write (*, '(A,I0,A)') "[ERROR] scan_flow_vs_flowz supports only R->C (seed size = 1). Got ", &
         state_seed_size_cfg(), "."
      error stop 1
   end if

   if (has_flow_time_arg) then
      call get_command_argument(5, arg_text)
      read (arg_text, *, iostat=ios) flow_time
      if (ios /= 0) then
         write (*, '(A,A,A)') "[ERROR] Failed to parse flow_time='", trim(arg_text), "'."
         error stop 1
      end if
   end if

   allocate (x(2), z0(1), z_flowz(1), z_flow(1), jac(1, 1))
   x(1) = flow_time
   nanv = ieee_value(0.0_dp, ieee_quiet_nan)

   open (newunit=unit_out, file=trim(output_file), status='replace', action='write', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "[ERROR] Failed to open output file:", trim(output_file)
      error stop 1
   end if
   write (unit_out, '(A)') "seed_u,flowz_ok,flow_ok,z_flowz_re,z_flowz_im,z_flow_re,z_flow_im,j_re,j_im,j_abs"

   n_flowz_ok = 0
   n_flow_ok = 0
   n_flowz_only = 0
   has_bad_range = .false.
   bad_u_min = huge(1.0_dp)
   bad_u_max = -huge(1.0_dp)
   bad_abs_re_min = huge(1.0_dp)
   bad_abs_re_max = -huge(1.0_dp)

   do i = 1, n_samples
      frac = real(i - 1, dp)/real(n_samples - 1, dp)
      u = seed_min + (seed_max - seed_min)*frac
      x(2) = u

      z0(1) = cmplx(0.0_dp, imag0, dp)
      z_flowz = z0
      call flowz(x, z_flowz, err_flowz)

      z_flow = z0
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      call flow(x, z_flow, jac, err_flow)

      if (.not. err_flowz) then
         n_flowz_ok = n_flowz_ok + 1
         z_flowz_re = real(z_flowz(1), dp)
         z_flowz_im = aimag(z_flowz(1))
      else
         z_flowz_re = nanv
         z_flowz_im = nanv
      end if

      if (.not. err_flow) then
         n_flow_ok = n_flow_ok + 1
         z_flow_re = real(z_flow(1), dp)
         z_flow_im = aimag(z_flow(1))
         j_re = real(jac(1, 1), dp)
         j_im = aimag(jac(1, 1))
         j_abs = abs(jac(1, 1))
      else
         z_flow_re = nanv
         z_flow_im = nanv
         j_re = nanv
         j_im = nanv
         j_abs = nanv
      end if

      if ((.not. err_flowz) .and. err_flow) then
         n_flowz_only = n_flowz_only + 1
         has_bad_range = .true.
         bad_u_min = min(bad_u_min, u)
         bad_u_max = max(bad_u_max, u)
         bad_abs_re_min = min(bad_abs_re_min, abs(z_flowz_re))
         bad_abs_re_max = max(bad_abs_re_max, abs(z_flowz_re))
      end if

      write (unit_out, '(ES24.16,",",I1,",",I1,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16)') &
         u, merge(1, 0, (.not. err_flowz)), merge(1, 0, (.not. err_flow)), &
         z_flowz_re, z_flowz_im, z_flow_re, z_flow_im, j_re, j_im, j_abs
   end do

   close (unit_out)

   write (*, '(A,1X,A)') "[DONE] Wrote scan:", trim(output_file)
   write (*, '(A,ES12.4,A,ES12.4,A,I0,A,ES12.4,A,ES12.4)') "[INFO] seed range=[", seed_min, ", ", seed_max, &
      "] n=", n_samples, " flow_time=", flow_time, " imag0=", imag0
   write (*, '(A,I0,A,I0,A,I0)') "[INFO] flowz_ok=", n_flowz_ok, " flow_ok=", n_flow_ok, " flowz_ok_flow_fail=", n_flowz_only
   if (has_bad_range) then
      write (*, '(A,ES12.4,A,ES12.4)') "[INFO] flowz_ok_flow_fail seed range=[", bad_u_min, ", ", bad_u_max, "]"
      write (*, '(A,ES12.4,A,ES12.4)') "[INFO] flowz_ok_flow_fail |Re(z_flowz)| range=[", bad_abs_re_min, ", ", bad_abs_re_max, "]"
   else
      write (*, '(A)') "[INFO] No points with flowz_ok and flow_fail."
   end if

contains

   subroutine print_usage_and_stop()
      implicit none
      write (*, '(A)') "Usage: scan_flow_vs_flowz <output_csv> <seed_min> <seed_max> <n_samples> [flow_time] [imag0]"
      write (*, '(A)') "Example: scan_flow_vs_flowz ../output/flow_vs_flowz.csv -2.0 2.0 5000 0.4 0.0"
      error stop 1
   end subroutine print_usage_and_stop

   subroutine get_required_real_arg(arg_idx, value, label)
      implicit none
      integer, intent(in) :: arg_idx
      real(dp), intent(out) :: value
      character(len=*), intent(in) :: label
      integer :: ios_local
      character(len=256) :: arg

      call get_command_argument(arg_idx, arg)
      read (arg, *, iostat=ios_local) value
      if (ios_local /= 0) then
         write (*, '(A,A,A,A,A)') "[ERROR] Failed to parse ", trim(label), "='", trim(arg), "'."
         error stop 1
      end if
   end subroutine get_required_real_arg

   subroutine get_required_int_arg(arg_idx, value, label)
      implicit none
      integer, intent(in) :: arg_idx
      integer, intent(out) :: value
      character(len=*), intent(in) :: label
      integer :: ios_local
      character(len=256) :: arg

      call get_command_argument(arg_idx, arg)
      read (arg, *, iostat=ios_local) value
      if (ios_local /= 0) then
         write (*, '(A,A,A,A,A)') "[ERROR] Failed to parse ", trim(label), "='", trim(arg), "'."
         error stop 1
      end if
   end subroutine get_required_int_arg

end program scan_flow_vs_flowz_app

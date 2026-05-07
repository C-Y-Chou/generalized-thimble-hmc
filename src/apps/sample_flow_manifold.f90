program sample_flow_manifold_app
   use param_mod
   use solve_flow, only: flowz, set_intode_strict_mode
   use utils, only: dp
   implicit none

   character(len=256) :: output_file, arg_text
   real(dp) :: seed_min, seed_max, flow_time, imag0, u, frac, z_re, z_im
   real(dp), allocatable :: x(:)
   complex(dp), allocatable :: z(:)
   logical :: failed
   integer :: n_samples, i, unit_out
   logical :: has_flow_time_arg, has_imag0_arg

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
      read (arg_text, *, iostat=i) imag0
      if (i /= 0) then
         write (*, '(A,A,A)') "[ERROR] Failed to parse imag0='", trim(arg_text), "'."
         error stop 1
      end if
   end if

   call set_intode_strict_mode(.true.)
   call read_parameters()
   flow_time = config%integrator%initial_flow_time

   if (state_seed_size_cfg() /= 1) then
      write (*, '(A,I0,A)') "[ERROR] sample_flow_manifold supports only R->C (seed size = 1). Got ", &
         state_seed_size_cfg(), "."
      error stop 1
   end if

   if (has_flow_time_arg) then
      call get_command_argument(5, arg_text)
      read (arg_text, *, iostat=i) flow_time
      if (i /= 0) then
         write (*, '(A,A,A)') "[ERROR] Failed to parse flow_time='", trim(arg_text), "'."
         error stop 1
      end if
   end if

   allocate (x(2), z(1))
   x(1) = flow_time

   open (newunit=unit_out, file=trim(output_file), status='replace', action='write', iostat=i)
   if (i /= 0) then
      write (*, '(A,1X,A)') "[ERROR] Failed to open output file:", trim(output_file)
      error stop 1
   end if

   write (unit_out, '(A)') "# seed_u  z_real  z_imag  ok"
   do i = 1, n_samples
      frac = real(i - 1, dp)/real(n_samples - 1, dp)
      u = seed_min + (seed_max - seed_min)*frac
      x(2) = u
      z(1) = cmplx(0.0_dp, imag0, dp)
      call flowz(x, z, failed)
      if (failed) then
         write (unit_out, '(ES24.16,1X,A,1X,A,1X,I1)') u, "nan", "nan", 0
      else
         z_re = real(z(1), dp)
         z_im = aimag(z(1))
         write (unit_out, '(ES24.16,1X,ES24.16,1X,ES24.16,1X,I1)') u, z_re, z_im, 1
      end if
   end do

   close (unit_out)
   write (*, '(A,1X,A)') "[DONE] Wrote manifold samples:", trim(output_file)
   write (*, '(A,ES12.4,A,ES12.4,A,I0,A,ES12.4,A,ES12.4)') "[INFO] seed range=[", seed_min, ", ", seed_max, &
      "] n=", n_samples, " flow_time=", flow_time, " imag0=", imag0

contains

   subroutine print_usage_and_stop()
      implicit none
      write (*, '(A)') "Usage: sample_flow_manifold <output_file> <seed_min> <seed_max> <n_samples> [flow_time] [imag0]"
      write (*, '(A)') "Example: sample_flow_manifold ../output/manifold.dat -2.0 2.0 2000 0.4 0.0"
      error stop 1
   end subroutine print_usage_and_stop

   subroutine get_required_real_arg(arg_idx, value, label)
      implicit none
      integer, intent(in) :: arg_idx
      real(dp), intent(out) :: value
      character(len=*), intent(in) :: label
      integer :: ios
      character(len=256) :: arg

      call get_command_argument(arg_idx, arg)
      read (arg, *, iostat=ios) value
      if (ios /= 0) then
         write (*, '(A,A,A,A,A)') "[ERROR] Failed to parse ", trim(label), "='", trim(arg), "'."
         error stop 1
      end if
   end subroutine get_required_real_arg

   subroutine get_required_int_arg(arg_idx, value, label)
      implicit none
      integer, intent(in) :: arg_idx
      integer, intent(out) :: value
      character(len=*), intent(in) :: label
      integer :: ios
      character(len=256) :: arg

      call get_command_argument(arg_idx, arg)
      read (arg, *, iostat=ios) value
      if (ios /= 0) then
         write (*, '(A,A,A,A,A)') "[ERROR] Failed to parse ", trim(label), "='", trim(arg), "'."
         error stop 1
      end if
   end subroutine get_required_int_arg

end program sample_flow_manifold_app

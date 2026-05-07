program scan_flowzr_stability_app
   use param_mod
   use solve_flow, only: flowz, flowzr, set_intode_strict_mode, &
                         reset_intode_fallback_stats, get_intode_fallback_context_stats, &
                         get_intode_radau_diag_stats
   use utils, only: dp
   use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_quiet_nan
   implicit none

   character(len=256) :: output_file, arg_text
   real(dp) :: re_min, re_max, im_min, im_max, flow_time, sens_delta
   real(dp) :: frac_re, frac_im, re0, im0, nanv
   real(dp) :: roundtrip_abs, kappa_re, kappa_im, kappa_max, z_flow_re, z_flow_im
   real(dp), allocatable :: x_fwd(:), x_back(:)
   complex(dp) :: z0(1), z_work(1), z_back(1), z_plus_re(1), z_plus_im(1)
   logical :: err_flowzr, err_back, err_sens_re, err_sens_im
   logical :: has_flow_time_arg, has_sens_delta_arg, has_roundtrip_arg
   logical :: do_sensitivity, do_roundtrip
   integer :: n_re, n_im, i_re, i_im, i, ios, unit_out
   integer :: attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown
   integer :: fail_flowz, fail_flowzr, fail_flow, fail_unknown
   integer :: radau_newton_fail, radau_linear_fail, radau_error_reject, radau_hmin_hit
   integer :: total_points, done_points, progress_stride
   integer :: count_flowzr_ok, count_flowzr_fail, count_back_ok, count_back_fail

   if (command_argument_count() < 7) then
      call print_usage_and_stop()
   end if

   call get_command_argument(1, output_file)
   call get_required_real_arg(2, re_min, "re_min")
   call get_required_real_arg(3, re_max, "re_max")
   call get_required_int_arg(4, n_re, "n_re")
   call get_required_real_arg(5, im_min, "im_min")
   call get_required_real_arg(6, im_max, "im_max")
   call get_required_int_arg(7, n_im, "n_im")
   has_flow_time_arg = (command_argument_count() >= 8)
   has_sens_delta_arg = (command_argument_count() >= 9)
   has_roundtrip_arg = (command_argument_count() >= 10)

   if (n_re < 2 .or. n_im < 2) then
      write (*, '(A)') "[ERROR] n_re and n_im must be >= 2."
      error stop 1
   end if
   if (re_max < re_min .or. im_max < im_min) then
      write (*, '(A)') "[ERROR] invalid range: require re_max>=re_min and im_max>=im_min."
      error stop 1
   end if

   sens_delta = 0.0_dp
   if (has_sens_delta_arg) then
      call get_command_argument(9, arg_text)
      read (arg_text, *, iostat=ios) sens_delta
      if (ios /= 0) then
         write (*, '(A,A,A)') "[ERROR] Failed to parse sens_delta='", trim(arg_text), "'."
         error stop 1
      end if
   end if
   do_sensitivity = (sens_delta > 0.0_dp)
   do_roundtrip = .false.
   if (has_roundtrip_arg) then
      call get_command_argument(10, arg_text)
      read (arg_text, *, iostat=ios) i
      if (ios /= 0 .or. (i /= 0 .and. i /= 1)) then
         write (*, '(A,A,A)') "[ERROR] roundtrip flag must be 0/1; got '", trim(arg_text), "'."
         error stop 1
      end if
      do_roundtrip = (i == 1)
   end if

   call set_intode_strict_mode(.true.)
   call read_parameters()
   flow_time = config%integrator%initial_flow_time

   if (state_seed_size_cfg() /= 1) then
      write (*, '(A,I0,A)') "[ERROR] scan_flowzr_stability supports only R->C (seed size = 1). Got ", &
         state_seed_size_cfg(), "."
      error stop 1
   end if

   if (has_flow_time_arg) then
      call get_command_argument(8, arg_text)
      read (arg_text, *, iostat=ios) flow_time
      if (ios /= 0) then
         write (*, '(A,A,A)') "[ERROR] Failed to parse flow_time='", trim(arg_text), "'."
         error stop 1
      end if
   end if

   allocate (x_fwd(2), x_back(2))
   x_fwd(1) = flow_time
   x_fwd(2) = 0.0_dp
   x_back(1) = -flow_time
   x_back(2) = 0.0_dp
   nanv = ieee_value(0.0_dp, ieee_quiet_nan)

   open (newunit=unit_out, file=trim(output_file), status='replace', action='write', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "[ERROR] Failed to open output file:", trim(output_file)
      error stop 1
   end if
   write (unit_out, '(A)') &
      "re0,im0,flowzr_ok,flowzr_back_ok,roundtrip_abs,kappa_re,kappa_im,kappa_max,flowzr_re,flowzr_im,"// &
      "flowzr_fb_attempt,flowzr_fb_fail,flowzr_radau_newton_fail,flowzr_radau_linear_fail,flowzr_radau_error_reject,flowzr_radau_hmin_hit"

   total_points = n_re*n_im
   progress_stride = max(1, total_points/20)
   done_points = 0
   count_flowzr_ok = 0
   count_flowzr_fail = 0
   count_back_ok = 0
   count_back_fail = 0

   do i_im = 1, n_im
      frac_im = real(i_im - 1, dp)/real(n_im - 1, dp)
      im0 = im_min + (im_max - im_min)*frac_im
      do i_re = 1, n_re
         frac_re = real(i_re - 1, dp)/real(n_re - 1, dp)
         re0 = re_min + (re_max - re_min)*frac_re
         z0(1) = cmplx(re0, im0, dp)

         call reset_intode_fallback_stats()
         z_work = z0
         call flowzr(x_fwd, z_work, err_flowzr)
         call get_intode_fallback_context_stats(attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                                fail_flowz, fail_flowzr, fail_flow, fail_unknown)
         call get_intode_radau_diag_stats(radau_newton_fail, radau_linear_fail, radau_error_reject, radau_hmin_hit)

         if (err_flowzr) then
            count_flowzr_fail = count_flowzr_fail + 1
            roundtrip_abs = nanv
            z_flow_re = nanv
            z_flow_im = nanv
            err_back = .true.
            kappa_re = nanv
            kappa_im = nanv
            kappa_max = nanv
         else
            count_flowzr_ok = count_flowzr_ok + 1
            z_flow_re = real(z_work(1), dp)
            z_flow_im = aimag(z_work(1))

            if (do_roundtrip) then
               z_back = z_work
               call flowzr(x_back, z_back, err_back)
               if (err_back) then
                  count_back_fail = count_back_fail + 1
                  roundtrip_abs = nanv
               else
                  count_back_ok = count_back_ok + 1
                  roundtrip_abs = abs(z_back(1) - z0(1))
               end if
            else
               err_back = .true.
               roundtrip_abs = nanv
            end if

            if (do_sensitivity) then
               z_plus_re(1) = z0(1) + cmplx(sens_delta, 0.0_dp, dp)
               call flowzr(x_fwd, z_plus_re, err_sens_re)
               if (err_sens_re) then
                  kappa_re = nanv
               else
                  kappa_re = abs(z_plus_re(1) - z_work(1))/sens_delta
               end if

               z_plus_im(1) = z0(1) + cmplx(0.0_dp, sens_delta, dp)
               call flowzr(x_fwd, z_plus_im, err_sens_im)
               if (err_sens_im) then
                  kappa_im = nanv
               else
                  kappa_im = abs(z_plus_im(1) - z_work(1))/sens_delta
               end if

               if (kappa_re == kappa_re .and. kappa_im == kappa_im) then
                  kappa_max = max(kappa_re, kappa_im)
               elseif (kappa_re == kappa_re) then
                  kappa_max = kappa_re
               elseif (kappa_im == kappa_im) then
                  kappa_max = kappa_im
               else
                  kappa_max = nanv
               end if
            else
               kappa_re = nanv
               kappa_im = nanv
               kappa_max = nanv
            end if
         end if

         write (unit_out, '(ES24.16,",",ES24.16,",",I1,",",I1,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",I0,",",I0,",",I0,",",I0,",",I0,",",I0)') &
            re0, im0, merge(1, 0, (.not. err_flowzr)), merge(1, 0, (.not. err_back)), &
            roundtrip_abs, kappa_re, kappa_im, kappa_max, z_flow_re, z_flow_im, &
            attempt_flowzr, fail_flowzr, radau_newton_fail, radau_linear_fail, radau_error_reject, radau_hmin_hit

         done_points = done_points + 1
         if (mod(done_points, progress_stride) == 0 .or. done_points == total_points) then
            write (*, '(A,I0,A,I0,A,F6.2,A)') "[PROGRESS] ", done_points, "/", total_points, &
               " (", 100.0_dp*real(done_points, dp)/real(total_points, dp), "%)"
         end if
      end do
   end do

   close (unit_out)

   write (*, '(A,1X,A)') "[DONE] Wrote stability scan:", trim(output_file)
   write (*, '(A,ES12.4,A,ES12.4,A,I0)') "[INFO] Re range=[", re_min, ", ", re_max, "] n_re=", n_re
   write (*, '(A,ES12.4,A,ES12.4,A,I0)') "[INFO] Im range=[", im_min, ", ", im_max, "] n_im=", n_im
   write (*, '(A,ES12.4,A,L1,A,ES12.4,A,L1)') "[INFO] flow_time=", flow_time, " sensitivity=", do_sensitivity, &
      " sens_delta=", sens_delta, " roundtrip=", do_roundtrip
   write (*, '(A,I0,A,I0,A,I0,A,I0)') "[INFO] flowzr_ok=", count_flowzr_ok, " flowzr_fail=", count_flowzr_fail, &
      " roundtrip_ok=", count_back_ok, " roundtrip_fail=", count_back_fail

contains

   subroutine print_usage_and_stop()
      implicit none
      write (*, '(A)') "Usage: scan_flowzr_stability <output_csv> <re_min> <re_max> <n_re> <im_min> <im_max> <n_im> [flow_time] [sens_delta] [roundtrip0or1]"
      write (*, '(A)') "Example: scan_flowzr_stability ../output/flowzr_stability.csv 0.0 0.05 161 0.90 1.00 161 0.4 1e-6 0"
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

end program scan_flowzr_stability_app

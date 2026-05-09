module hmc_reversibility_checks
   use runtime_env_mod, only: to_lower_ascii
   use utils
   implicit none

   logical, save :: probe_config_loaded = .false.
   logical, save :: probe_enabled = .false.
   logical, save :: probe_fallback_only = .true.
   integer, save :: probe_limit = 0
   integer, save :: probe_count = 0
   logical, save :: progress_diag_config_loaded = .false.
   logical, save :: progress_diag_enabled = .false.
   integer, save :: progress_diag_limit = 0
   integer, save :: progress_diag_count = 0

contains

   subroutine report_state_progress_diagnostic(context, x_before, x_after)
      character(len=*), intent(in) :: context
      real(dp), intent(in) :: x_before(:), x_after(:)
      integer :: n_seed
      real(dp) :: dx_inf, scale, tol

      call load_state_progress_diagnostic_config()
      if (.not. progress_diag_enabled) return
      if (progress_diag_count >= progress_diag_limit) return

      n_seed = min(size(x_before), size(x_after)) - 1
      if (n_seed < 1) return

      dx_inf = maxval(abs(x_after(2:n_seed + 1) - x_before(2:n_seed + 1)))
      scale = max(1.0_dp, maxval(abs(x_before(2:n_seed + 1))), maxval(abs(x_after(2:n_seed + 1))))
      tol = 16.0_dp*epsilon(1.0_dp)*scale
      if (dx_inf > tol) return

      progress_diag_count = progress_diag_count + 1
      write (*, '(A,I0,1X,A,A,1X,A,ES13.6,1X,A,ES13.6)') &
         "[HMC][PROGRESS_DIAG] no physical-coordinate progress: event=", progress_diag_count, &
         "context=", trim(context), "dx_inf=", dx_inf, "tol=", tol
   end subroutine report_state_progress_diagnostic

   subroutine load_state_progress_diagnostic_config()
      character(len=64) :: env_value
      integer :: env_len, env_stat, ios, parsed_value

      if (progress_diag_config_loaded) return
      progress_diag_config_loaded = .true.

      call get_environment_variable("HMC_STATE_PROGRESS_DIAGNOSTIC_LIMIT", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         read (env_value(1:env_len), *, iostat=ios) parsed_value
         if (ios == 0) progress_diag_limit = max(0, parsed_value)
      end if

      progress_diag_enabled = (progress_diag_limit > 0)
      if (progress_diag_enabled) then
         write (*, '(A,I0)') "[INFO] hmc state-progress diagnostic limit=", progress_diag_limit
      end if
   end subroutine load_state_progress_diagnostic_config

   logical function reversibility_probe_should_run(fallback_used)
      logical, intent(in) :: fallback_used

      call load_reversibility_probe_config()
      if (.not. probe_enabled) then
         reversibility_probe_should_run = .false.
         return
      end if
      if (probe_count >= probe_limit) then
         reversibility_probe_should_run = .false.
         return
      end if
      if (probe_fallback_only .and. (.not. fallback_used)) then
         reversibility_probe_should_run = .false.
         return
      end if
      reversibility_probe_should_run = .true.
   end function reversibility_probe_should_run

   subroutine report_reversibility_probe(fallback_used, forward_ok, reverse_ok, &
                                         forward_fb_attempts, forward_fb_success, forward_fb_failure, &
                                         reverse_fb_attempts, reverse_fb_success, reverse_fb_failure, &
                                         dH_forward, dH_reverse, dx_inf, dz_inf, dj_inf, dp_inf)
      logical, intent(in) :: fallback_used, forward_ok, reverse_ok
      integer, intent(in) :: forward_fb_attempts, forward_fb_success, forward_fb_failure
      integer, intent(in) :: reverse_fb_attempts, reverse_fb_success, reverse_fb_failure
      real(dp), intent(in) :: dH_forward, dH_reverse, dx_inf, dz_inf, dj_inf, dp_inf

      call load_reversibility_probe_config()
      if (.not. probe_enabled) return
      if (probe_count >= probe_limit) return

      probe_count = probe_count + 1
      write (*, '(A,I0,1X,A,L1,1X,A,L1,1X,A,L1,1X,A,I0,1X,A,I0,1X,A,I0,1X,A,I0,1X,A,I0,1X,A,I0,1X,A,ES13.6,1X,A,ES13.6,1X,A,ES13.6,1X,A,ES13.6,1X,A,ES13.6,1X,A,ES13.6)') &
         "[REVCHK] probe=", probe_count, &
         "fallback_used=", fallback_used, &
         "forward_ok=", forward_ok, &
         "reverse_ok=", reverse_ok, &
         "forward_fb_attempts=", forward_fb_attempts, &
         "forward_fb_success=", forward_fb_success, &
         "forward_fb_failure=", forward_fb_failure, &
         "reverse_fb_attempts=", reverse_fb_attempts, &
         "reverse_fb_success=", reverse_fb_success, &
         "reverse_fb_failure=", reverse_fb_failure, &
         "dH_forward=", dH_forward, &
         "dH_reverse=", dH_reverse, &
         "dx_inf=", dx_inf, &
         "dz_inf=", dz_inf, &
         "dj_inf=", dj_inf, &
         "dp_inf=", dp_inf
   end subroutine report_reversibility_probe

   subroutine load_reversibility_probe_config()
      character(len=64) :: env_value
      integer :: env_len, env_stat, ios, parsed_value

      if (probe_config_loaded) return
      probe_config_loaded = .true.

      call get_environment_variable("HMC_REVERSIBILITY_PROBE_LIMIT", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         read (env_value(1:env_len), *, iostat=ios) parsed_value
         if (ios == 0) probe_limit = max(0, parsed_value)
      end if
      if (probe_limit > 0) probe_enabled = .true.

      call get_environment_variable("HMC_REVERSIBILITY_PROBE_FALLBACK_ONLY", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         select case (to_lower_ascii(trim(env_value(1:env_len))))
         case ("0", "false", "f", "no", "n", "off")
            probe_fallback_only = .false.
         case default
            probe_fallback_only = .true.
         end select
      end if

      if (probe_enabled) then
         write (*, '(A,I0,1X,A,L1)') "[INFO] hmc reversibility probe limit=", probe_limit, &
            " fallback_only=", probe_fallback_only
      end if
   end subroutine load_reversibility_probe_config

end module hmc_reversibility_checks

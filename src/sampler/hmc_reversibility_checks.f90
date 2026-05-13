module hmc_reversibility_checks
   use runtime_env_mod, only: parse_int_env, read_string_env, to_lower_ascii
   use utils, only: dp
   implicit none

   type :: hmc_reversibility_context_t
      logical :: probe_config_loaded = .false.
      logical :: probe_enabled = .false.
      logical :: probe_fallback_only = .true.
      integer :: probe_limit = 0
      integer :: probe_count = 0
      logical :: progress_diag_config_loaded = .false.
      logical :: progress_diag_enabled = .false.
      integer :: progress_diag_limit = 0
      integer :: progress_diag_count = 0
   end type hmc_reversibility_context_t

   type(hmc_reversibility_context_t), target, save :: module_hmc_reversibility_context

contains

   subroutine resolve_hmc_reversibility_context(context, active_context)
      type(hmc_reversibility_context_t), intent(inout), optional, target :: context
      type(hmc_reversibility_context_t), pointer :: active_context

      if (present(context)) then
         active_context => context
      else
         active_context => module_hmc_reversibility_context
      end if
   end subroutine resolve_hmc_reversibility_context

   subroutine report_state_progress_diagnostic(context_label, x_before, x_after, context)
      character(len=*), intent(in) :: context_label
      real(dp), intent(in) :: x_before(:), x_after(:)
      type(hmc_reversibility_context_t), intent(inout), optional, target :: context

      integer :: n_seed
      real(dp) :: dx_inf, scale, tol
      type(hmc_reversibility_context_t), pointer :: active_context

      call load_state_progress_diagnostic_config(context)
      call resolve_hmc_reversibility_context(context, active_context)
      if (.not. active_context%progress_diag_enabled) return
      if (active_context%progress_diag_count >= active_context%progress_diag_limit) return

      n_seed = min(size(x_before), size(x_after)) - 1
      if (n_seed < 1) return

      dx_inf = maxval(abs(x_after(2:n_seed + 1) - x_before(2:n_seed + 1)))
      scale = max(1.0_dp, maxval(abs(x_before(2:n_seed + 1))), maxval(abs(x_after(2:n_seed + 1))))
      tol = 16.0_dp*epsilon(1.0_dp)*scale
      if (dx_inf > tol) return

      active_context%progress_diag_count = active_context%progress_diag_count + 1
      write (*, '(A,I0,1X,A,A,1X,A,ES13.6,1X,A,ES13.6)') &
         "[HMC][PROGRESS_DIAG] no physical-coordinate progress: event=", active_context%progress_diag_count, &
         "context=", trim(context_label), "dx_inf=", dx_inf, "tol=", tol
   end subroutine report_state_progress_diagnostic

   subroutine load_state_progress_diagnostic_config(context)
      type(hmc_reversibility_context_t), intent(inout), optional, target :: context
      type(hmc_reversibility_context_t), pointer :: active_context

      call resolve_hmc_reversibility_context(context, active_context)
      if (active_context%progress_diag_config_loaded) return
      active_context%progress_diag_config_loaded = .true.

      call parse_int_env("HMC_STATE_PROGRESS_DIAGNOSTIC_LIMIT", active_context%progress_diag_limit)
      active_context%progress_diag_limit = max(0, active_context%progress_diag_limit)

      active_context%progress_diag_enabled = (active_context%progress_diag_limit > 0)
      if (active_context%progress_diag_enabled) then
         write (*, '(A,I0)') "[INFO] hmc state-progress diagnostic limit=", active_context%progress_diag_limit
      end if
   end subroutine load_state_progress_diagnostic_config

   logical function reversibility_probe_should_run(fallback_used, context)
      logical, intent(in) :: fallback_used
      type(hmc_reversibility_context_t), intent(inout), optional, target :: context

      type(hmc_reversibility_context_t), pointer :: active_context

      call load_reversibility_probe_config(context)
      call resolve_hmc_reversibility_context(context, active_context)
      if (.not. active_context%probe_enabled) then
         reversibility_probe_should_run = .false.
         return
      end if
      if (active_context%probe_count >= active_context%probe_limit) then
         reversibility_probe_should_run = .false.
         return
      end if
      if (active_context%probe_fallback_only .and. (.not. fallback_used)) then
         reversibility_probe_should_run = .false.
         return
      end if
      reversibility_probe_should_run = .true.
   end function reversibility_probe_should_run

   subroutine report_reversibility_probe(fallback_used, forward_ok, reverse_ok, &
                                         forward_fb_attempts, forward_fb_success, forward_fb_failure, &
                                         reverse_fb_attempts, reverse_fb_success, reverse_fb_failure, &
                                         dH_forward, dH_reverse, dx_inf, dz_inf, dj_inf, dp_inf, context)
      logical, intent(in) :: fallback_used, forward_ok, reverse_ok
      integer, intent(in) :: forward_fb_attempts, forward_fb_success, forward_fb_failure
      integer, intent(in) :: reverse_fb_attempts, reverse_fb_success, reverse_fb_failure
      real(dp), intent(in) :: dH_forward, dH_reverse, dx_inf, dz_inf, dj_inf, dp_inf
      type(hmc_reversibility_context_t), intent(inout), optional, target :: context

      type(hmc_reversibility_context_t), pointer :: active_context

      call load_reversibility_probe_config(context)
      call resolve_hmc_reversibility_context(context, active_context)
      if (.not. active_context%probe_enabled) return
      if (active_context%probe_count >= active_context%probe_limit) return

      active_context%probe_count = active_context%probe_count + 1
      write (*, '(A,I0,1X,A,L1,1X,A,L1,1X,A,L1,1X,A,I0,1X,A,I0,1X,A,I0,1X,A,I0,1X,A,I0,1X,A,I0,1X,A,ES13.6,1X,A,ES13.6,1X,A,ES13.6,1X,A,ES13.6,1X,A,ES13.6,1X,A,ES13.6)') &
         "[REVCHK] probe=", active_context%probe_count, &
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

   subroutine load_reversibility_probe_config(context)
      type(hmc_reversibility_context_t), intent(inout), optional, target :: context

      character(len=64) :: env_value
      logical :: env_present
      type(hmc_reversibility_context_t), pointer :: active_context

      call resolve_hmc_reversibility_context(context, active_context)
      if (active_context%probe_config_loaded) return
      active_context%probe_config_loaded = .true.

      call parse_int_env("HMC_REVERSIBILITY_PROBE_LIMIT", active_context%probe_limit)
      active_context%probe_limit = max(0, active_context%probe_limit)
      if (active_context%probe_limit > 0) active_context%probe_enabled = .true.

      call read_string_env("HMC_REVERSIBILITY_PROBE_FALLBACK_ONLY", env_value, env_present)
      if (env_present) then
         select case (to_lower_ascii(trim(env_value)))
         case ("0", "false", "f", "no", "n", "off")
            active_context%probe_fallback_only = .false.
         case default
            active_context%probe_fallback_only = .true.
         end select
      end if

      if (active_context%probe_enabled) then
         write (*, '(A,I0,1X,A,L1)') "[INFO] hmc reversibility probe limit=", active_context%probe_limit, &
            " fallback_only=", active_context%probe_fallback_only
      end if
   end subroutine load_reversibility_probe_config

   subroutine release_hmc_reversibility_context(context)
      type(hmc_reversibility_context_t), intent(inout) :: context

      context%probe_config_loaded = .false.
      context%probe_enabled = .false.
      context%probe_fallback_only = .true.
      context%probe_limit = 0
      context%probe_count = 0
      context%progress_diag_config_loaded = .false.
      context%progress_diag_enabled = .false.
      context%progress_diag_limit = 0
      context%progress_diag_count = 0
   end subroutine release_hmc_reversibility_context

end module hmc_reversibility_checks

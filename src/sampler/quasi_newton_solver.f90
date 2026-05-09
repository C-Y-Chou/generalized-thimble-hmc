module quasi_newton_solver_mod
   use utils
   use, intrinsic :: iso_fortran_env, only: int64
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite, ieee_value, ieee_quiet_nan
   use solve_flow, only: flowzr, flowz, set_intode_stage_trace, set_intode_quasi_iter_trace, intode_stage_quasi, &
                         get_intode_rescue_stats, intode_status_unknown, intode_status_success, intode_status_success_zero_time, &
                         intode_status_success_stiff_rescue, intode_status_success_solver_assist, &
                         intode_status_failure_max_steps, intode_status_failure_invalid, intode_status_failure_h_min
   use quasi_newton_linear_solver_mod, only: solve_linear_direction, initial_guess_from_jacobian
   use quasi_newton_line_search_mod, only: accept_full_step, accept_backtracking, update_merit_from_ndls
   use quasi_newton_jacobian_update_mod, only: broyden_rank1_update
   implicit none

   complex(dp), allocatable, save :: residual_jlc(:), residual_z_trial(:), residual_z_flowed(:)
   real(dp), allocatable, save :: residual_xtu(:)
   integer, save :: quasi_trace_iter = 0
   integer, save :: quasi_last_trace_count = 0
   integer, save :: quasi_last_trace_capacity = 0
   integer, save :: quasi_last_trace_dim = 0
   complex(dp), allocatable, save :: quasi_last_trace_z_proposed(:, :), quasi_last_trace_z_flowed(:, :)
   real(dp), allocatable, save :: quasi_last_trace_res_norm(:), quasi_last_trace_alpha(:)
   integer, allocatable, save :: quasi_last_trace_iter(:), quasi_last_trace_backtrack(:), quasi_last_trace_attempt(:)
   integer, allocatable, save :: quasi_last_trace_route(:)
   logical, allocatable, save :: quasi_last_trace_accepted(:), quasi_last_trace_eval_ok(:)
   complex(dp), allocatable, save :: quasi_eval_z_proposed(:), quasi_eval_z_flowed(:)
   logical, save :: quasi_eval_has_flowed = .false.
   logical, save :: quasi_eval_flowed_is_inverse = .false.
   integer, save :: quasi_trace_route_code = 0
   integer, parameter :: quasi_final_resort_budget_default = 20000
   integer, save :: quasi_final_resort_budget = quasi_final_resort_budget_default
   integer, parameter :: quasi_accepted_iter_budget_default = 0
   integer, save :: quasi_accepted_iter_budget = quasi_accepted_iter_budget_default
   logical, save :: quasi_global_fallback_enabled = .false.
   logical, save :: qn_force_best_proposal_enabled = .false.
   real(dp), save :: qn_force_best_proposal_tol = -1.0_dp
   integer(int64), save :: quasi_global_filter_candidate_count = 0_int64
   integer(int64), save :: quasi_global_filter_pass_count = 0_int64
   integer(int64), save :: quasi_global_filter_reject_count = 0_int64
   integer(int64), save :: quasi_eval_flow_status_success = 0_int64
   integer(int64), save :: quasi_eval_flow_status_zero_time = 0_int64
   integer(int64), save :: quasi_eval_flow_status_stiff_rescue = 0_int64
   integer(int64), save :: quasi_eval_flow_status_solver_assist = 0_int64
   integer(int64), save :: quasi_eval_flow_status_failure_max_steps = 0_int64
   integer(int64), save :: quasi_eval_flow_status_failure_invalid = 0_int64
   integer(int64), save :: quasi_eval_flow_status_failure_h_min = 0_int64
   integer(int64), save :: quasi_eval_flow_status_unknown = 0_int64
   logical, save :: quasi_final_resort_budget_loaded = .false.
   logical, save :: quasi_watchdog_scope_active = .false.
   integer, save :: quasi_watchdog_start_success_final_resort = 0
   integer, save :: quasi_watchdog_used_success_final_resort = 0
    integer, save :: quasi_watchdog_used_accepted_iter = 0
   logical, save :: quasi_watchdog_hit = .false.
   logical, save :: quasi_watchdog_last_hit = .false.
   integer, save :: quasi_watchdog_last_used = 0
   integer, save :: quasi_watchdog_last_used_accepted_iter = 0
   integer, save :: quasi_watchdog_hit_total = 0

contains

   subroutine solve_constraint_quasi_newton(f, tol, max_iter, xt, z, del_z, ierr, Jl, x_new, jac, x_seed_override, x_best_solution)
      implicit none

      integer, intent(in) :: max_iter
      real(dp), intent(in) :: tol
      logical, intent(out) :: ierr
      real(dp), intent(in) :: xt(:), del_z(:)
      complex(dp), intent(in) :: z(:)
      real(dp), intent(out) :: Jl(:)
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: x_new(:)
      real(dp), intent(in), optional :: x_seed_override(:)
      real(dp), intent(out), optional :: x_best_solution(:)

      interface
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac)
            use, intrinsic :: iso_fortran_env, only: real64
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
         end subroutine f
      end interface

      integer, parameter :: continuation_stage_count = 3
      integer, parameter :: restart_attempt_count = 3
      real(dp), parameter :: continuation_scale(continuation_stage_count) = [0.35_dp, 0.70_dp, 1.0_dp]
      integer, parameter :: fine_stage_count = 5
      real(dp), parameter :: fine_scale(fine_stage_count) = [0.20_dp, 0.40_dp, 0.60_dp, 0.80_dp, 1.0_dp]
      integer, parameter :: sweep_seed_count = 5
      real(dp), parameter :: restart_gain_reset = 0.98_dp
      integer, parameter :: max_poor_restarts = 2
      real(dp), parameter :: promising_first_pass_res = 1.0e-2_dp
      real(dp), parameter :: probe_priority_pass_trigger_res = 1.0e-3_dp
      real(dp), parameter :: probe_global_rescue_trigger_res = 4.3e-3_dp
      real(dp), parameter :: fine_cont_trigger_res = 5.0e-2_dp
      real(dp), parameter :: sweep_trigger_res = 1.0e-1_dp

      integer :: n, attempt_idx, stage_idx, fine_idx, sweep_idx, restart_idx, stage_iter, retry_iter
      integer :: poor_restart_count
      logical :: converged, stage_converged, enable_global_fallback_sequence, run_priority_pass
      logical :: global_filter_candidate
      real(dp) :: best_res_first, best_res_try, best_res_global, stage_tol, best_before_restart
      real(dp) :: best_accept_tol
      real(dp), allocatable :: x0_guess(:), x_best_first(:), x_stage_best(:), x_stage_seed(:), x_retry(:), x_best_global(:)
      real(dp), allocatable :: x_try(:), del_stage(:), Jl_try(:), Jl_best_global(:)

      n = 2*size(z)
      allocate (x0_guess(n), x_best_first(n), x_stage_best(n), x_stage_seed(n), x_retry(n), x_try(n), x_best_global(n), &
                del_stage(n), Jl_try(n), Jl_best_global(n))
      call reset_quasi_last_trace(size(z))
      call reset_quasi_watchdog_last_status()
      call begin_quasi_watchdog_scope()

      call initial_guess_from_jacobian(jac, del_z, x0_guess)
      if (present(x_seed_override)) then
         if (size(x_seed_override) == n) then
            if (real_vector_is_finite(x_seed_override)) x0_guess = x_seed_override
         end if
      end if
      converged = .false.
      global_filter_candidate = .false.
      best_res_first = huge(1.0_dp)
      best_res_global = huge(1.0_dp)
      x_best_first = x0_guess
      x_stage_seed = x0_guess
      x_best_global = x0_guess
      enable_global_fallback_sequence = (quasi_global_fallback_enabled .and. max_iter > 32)
      if ((.not. quasi_global_fallback_enabled) .and. max_iter > 32) global_filter_candidate = .true.
      Jl = 0.0_dp
      Jl_try = 0.0_dp
      Jl_best_global = 0.0_dp
      x_new = xt
      x_try = xt

      attempt_idx = 1
      quasi_trace_route_code = 1
      call run_dfo_ls_attempt(f, tol, max_iter, attempt_idx, xt, z, del_z, jac, x0_guess, stage_converged, Jl, x_new, &
                              x_best_out=x_best_first, best_res_out=best_res_first)
      if (best_res_first < best_res_global) then
         best_res_global = best_res_first
         Jl_best_global = Jl
         x_best_global = x_best_first
      end if
      x_stage_seed = x_best_first
      converged = stage_converged

      ! Priority pass for near-solution stalls: if the first pass gets close,
      ! spend one longer local DFO-LS run from the first-pass best state.
      run_priority_pass = (.not. converged) .and. (best_res_first <= promising_first_pass_res)
      if (run_priority_pass .and. max_iter <= 32) then
         run_priority_pass = (best_res_first <= probe_priority_pass_trigger_res)
      end if
      if (run_priority_pass) then
         best_res_try = huge(1.0_dp)
         x_stage_best = x_stage_seed
         x_try = xt
         Jl_try = Jl
         attempt_idx = attempt_idx + 1
         quasi_trace_route_code = 2
         call run_dfo_ls_attempt(f, tol, 2*max_iter, attempt_idx, xt, z, del_z, jac, x_stage_seed, stage_converged, &
                                 Jl_try, x_try, x_best_out=x_stage_best, best_res_out=best_res_try)
         if (best_res_try < best_res_global) then
            best_res_global = best_res_try
            Jl_best_global = Jl_try
            x_best_global = x_stage_best
         end if
         x_stage_seed = x_stage_best
         Jl = Jl_try
         x_new = x_try
         if (stage_converged) converged = .true.
      end if

      ! Global rescue is research-only. If explicitly enabled, a failed probe
      ! near a small residual basin may enter the global continuation/restart path.
      if ((.not. converged) .and. (.not. enable_global_fallback_sequence)) then
         if (ieee_is_finite(best_res_global) .and. best_res_global <= probe_global_rescue_trigger_res) then
            if (quasi_global_fallback_enabled) then
               enable_global_fallback_sequence = .true.
            else
               global_filter_candidate = .true.
            end if
         end if
      end if

      ! Generic fallback sequence for stagnation: scaled-target continuation
      ! followed by diversified restarts on the full target.
      if (.not. converged .and. enable_global_fallback_sequence) then
         do stage_idx = 1, continuation_stage_count
            del_stage = continuation_scale(stage_idx)*del_z
            if (stage_idx == continuation_stage_count) then
               stage_iter = max_iter
            else
               stage_iter = max(18, max_iter/4)
            end if
            stage_tol = continuation_stage_tol(tol, continuation_scale(stage_idx), .false.)
            best_res_try = huge(1.0_dp)
            x_stage_best = x_stage_seed
            x_try = xt
            Jl_try = Jl
            attempt_idx = attempt_idx + 1
            quasi_trace_route_code = 10 + stage_idx
            call run_dfo_ls_attempt(f, stage_tol, stage_iter, attempt_idx, xt, z, del_stage, jac, x_stage_seed, stage_converged, &
                                    Jl_try, x_try, x_best_out=x_stage_best, best_res_out=best_res_try)
            if (best_res_try < best_res_global) then
               best_res_global = best_res_try
               Jl_best_global = Jl_try
               x_best_global = x_stage_best
            end if
            x_stage_seed = x_stage_best
            Jl = Jl_try
            x_new = x_try
            if (stage_converged .and. stage_idx == continuation_stage_count) then
               converged = .true.
               exit
            end if
         end do
      end if

      ! Fine continuation for unresolved but promising cases.
      if ((.not. converged) .and. enable_global_fallback_sequence .and. best_res_global <= fine_cont_trigger_res) then
         do fine_idx = 1, fine_stage_count
            del_stage = fine_scale(fine_idx)*del_z
            if (fine_idx == fine_stage_count) then
               stage_iter = max_iter
            else
               stage_iter = max(20, max_iter/3)
            end if
            stage_tol = continuation_stage_tol(tol, fine_scale(fine_idx), .true.)
            best_res_try = huge(1.0_dp)
            x_stage_best = x_stage_seed
            x_try = xt
            Jl_try = Jl
            attempt_idx = attempt_idx + 1
            quasi_trace_route_code = 20 + fine_idx
            call run_dfo_ls_attempt(f, stage_tol, stage_iter, attempt_idx, xt, z, del_stage, jac, x_stage_seed, stage_converged, &
                                    Jl_try, x_try, x_best_out=x_stage_best, best_res_out=best_res_try)
            if (best_res_try < best_res_global) then
               best_res_global = best_res_try
               Jl_best_global = Jl_try
               x_best_global = x_stage_best
            end if
            x_stage_seed = x_stage_best
            Jl = Jl_try
            x_new = x_try
            if (stage_converged .and. fine_idx == fine_stage_count) then
               converged = .true.
               exit
            end if
         end do
      end if

      if (.not. converged .and. enable_global_fallback_sequence) then
         poor_restart_count = 0
         do restart_idx = 1, restart_attempt_count
            best_before_restart = best_res_global
            select case (restart_idx)
            case (1)
               call build_scaled_restart_guess(x_stage_seed, x_retry, 0.50_dp)
            case (2)
               call build_diversified_restart_guess(x0_guess, x_stage_seed, x_retry, kick_sign=1.0_dp, kick_scale=1.05_dp)
            case default
               call build_diversified_restart_guess(x0_guess, x_stage_seed, x_retry, kick_sign=-1.0_dp, kick_scale=1.05_dp)
            end select

            retry_iter = max(20, max_iter/3)
            best_res_try = huge(1.0_dp)
            x_stage_best = x_stage_seed
            x_try = xt
            Jl_try = Jl
            attempt_idx = attempt_idx + 1
            quasi_trace_route_code = 30 + restart_idx
            call run_dfo_ls_attempt(f, tol, retry_iter, attempt_idx, xt, z, del_z, jac, x_retry, stage_converged, Jl_try, x_try, &
                                    x_best_out=x_stage_best, best_res_out=best_res_try)
            if (best_res_try < best_res_global) then
               best_res_global = best_res_try
               Jl_best_global = Jl_try
               x_best_global = x_stage_best
            end if
            x_stage_seed = x_stage_best
            Jl = Jl_try
            x_new = x_try
            if (stage_converged) then
               converged = .true.
               exit
            end if

            if (best_res_global <= best_before_restart*restart_gain_reset) then
               poor_restart_count = 0
            else
               poor_restart_count = poor_restart_count + 1
               if (poor_restart_count >= max_poor_restarts) exit
            end if
         end do
      end if

      ! Seed sweep for unresolved moderate-residual cases.
      if ((.not. converged) .and. enable_global_fallback_sequence .and. best_res_global <= sweep_trigger_res) then
         do sweep_idx = 1, sweep_seed_count
            select case (sweep_idx)
            case (1)
               x_retry = 0.0_dp
            case (2)
               x_retry = x0_guess
            case (3)
               x_retry = 0.5_dp*x0_guess
            case (4)
               x_retry = -0.5_dp*x_stage_seed
            case default
               call build_diversified_restart_guess(x0_guess, x_stage_seed, x_retry, kick_sign=-1.0_dp, kick_scale=1.30_dp)
            end select
            retry_iter = max(20, max_iter/2)
            best_res_try = huge(1.0_dp)
            x_stage_best = x_stage_seed
            x_try = xt
            Jl_try = Jl
            attempt_idx = attempt_idx + 1
            quasi_trace_route_code = 40 + sweep_idx
            call run_dfo_ls_attempt(f, tol, retry_iter, attempt_idx, xt, z, del_z, jac, x_retry, stage_converged, Jl_try, x_try, &
                                    x_best_out=x_stage_best, best_res_out=best_res_try)
            if (best_res_try < best_res_global) then
               best_res_global = best_res_try
               Jl_best_global = Jl_try
               x_best_global = x_stage_best
            end if
            x_stage_seed = x_stage_best
            Jl = Jl_try
            x_new = x_try
            if (stage_converged) then
               converged = .true.
               exit
            end if
         end do
      end if

      if ((.not. converged) .and. residual_within_accept_tolerance(best_res_global, tol)) then
         quasi_trace_route_code = 90
         call rescue_attempt_from_best(xt, z, del_z, tol, Jl_best_global, best_res_global, x_new, Jl, converged)
      end if
      if (.not. converged) then
         best_accept_tol = tol
         if (qn_force_best_proposal_enabled .and. qn_force_best_proposal_tol > 0.0_dp) then
            best_accept_tol = qn_force_best_proposal_tol
         end if
         if (ieee_is_finite(best_res_global) .and. best_res_global < best_accept_tol) then
            quasi_trace_route_code = 91
            call rescue_attempt_from_best(xt, z, del_z, best_accept_tol, Jl_best_global, best_res_global, x_new, Jl, converged)
         end if
      end if
      if (global_filter_candidate) then
         call record_quasi_global_filter(converged)
      end if
      if (.not. converged) then
         x_new = xt
         Jl = Jl_best_global
      end if

      ierr = .not. converged
      if (present(x_best_solution)) then
         if (size(x_best_solution) == n) x_best_solution = x_best_global
      end if
      call end_quasi_watchdog_scope()
      deallocate (x0_guess, x_best_first, x_stage_best, x_stage_seed, x_retry, x_try, x_best_global, del_stage, Jl_try, Jl_best_global)
   end subroutine solve_constraint_quasi_newton

   subroutine record_quasi_global_filter(local_success)
      implicit none
      logical, intent(in) :: local_success

      quasi_global_filter_candidate_count = quasi_global_filter_candidate_count + 1_int64
      if (local_success) then
         quasi_global_filter_pass_count = quasi_global_filter_pass_count + 1_int64
      else
         quasi_global_filter_reject_count = quasi_global_filter_reject_count + 1_int64
      end if
   end subroutine record_quasi_global_filter

   subroutine solve_constraint_quasi_newton_strict_continuation(f, tol, max_iter, xt, z, del_z, ierr, Jl, x_new, jac, x_seed_hint)
      implicit none

      integer, intent(in) :: max_iter
      real(dp), intent(in) :: tol
      logical, intent(out) :: ierr
      real(dp), intent(in) :: xt(:), del_z(:)
      complex(dp), intent(in) :: z(:)
      real(dp), intent(out) :: Jl(:)
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: x_new(:)
      real(dp), intent(in), optional :: x_seed_hint(:)

      interface
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac)
            use, intrinsic :: iso_fortran_env, only: real64
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
         end subroutine f
      end interface

      integer :: n, seed_idx, split_idx, promote_idx
      integer :: final_paper_iter, final_hard_iter
      logical :: converged, converged_split, converged_promote, converged_paper, converged_paper_hard
      real(dp) :: split_factor
      real(dp) :: tol_near
      real(dp), parameter :: split_factor_list(6) = (/1.0_dp, 2.0_dp, 4.0_dp, 8.0_dp, 16.0_dp, 32.0_dp/)
      integer, parameter :: terminal_paper_iter_cap = 800
      integer, parameter :: terminal_hard_iter_cap = 2000
      real(dp), parameter :: near_tol_factor = 4.0_dp
      real(dp), allocatable :: x_seed(:), x_seed_base(:), del_z_split(:), Jl_split(:), x_split(:), x_promote(:)

      call reset_quasi_watchdog_last_status()
      if (size(x_new) /= size(xt) .or. size(Jl) /= size(del_z)) then
         ierr = .true.
         return
      end if

      n = 2*size(z)
      allocate (x_seed(n), x_seed_base(n), del_z_split(size(del_z)), Jl_split(size(del_z)), x_split(size(xt)), x_promote(n))
      call reset_quasi_last_trace(size(z))
      call initial_guess_from_jacobian(jac, del_z, x_seed)
      x_seed_base = x_seed
      if (present(x_seed_hint)) then
         if (size(x_seed_hint) == size(x_seed_base)) then
            if (all(ieee_is_finite(x_seed_hint))) then
               if (sum(abs(x_seed_hint)) > 0.0_dp) then
                  x_seed_base = x_seed_hint
               end if
            end if
         end if
      end if
      tol_near = max(tol, near_tol_factor*tol)

      Jl = 0.0_dp
      x_new = xt
      converged = .false.

      ! Consistency-first rescue ladder:
      ! try full step first, then promote from smaller split solves.
      do split_idx = 1, size(split_factor_list)
         split_factor = split_factor_list(split_idx)
         if (split_idx == 1) then
            del_z_split = del_z
         else
            del_z_split = del_z/split_factor
         end if

         do seed_idx = 1, 3
            select case (seed_idx)
            case (1)
               x_seed = x_seed_base
            case (2)
               x_seed = -x_seed_base
            case default
               x_seed = 0.35_dp*x_seed_base
            end select

            if (split_idx == 1) then
               Jl = 0.0_dp
               x_new = xt
               call run_delz_continuation(f, tol_near, max_iter, 0, xt, z, del_z, jac, x_seed, converged, Jl, x_new, &
                                          strict_controls=.true., near_escape_mode=.true.)
            else
               Jl_split = 0.0_dp
               x_split = xt
               call run_delz_continuation(f, tol_near, max_iter, 0, xt, z, del_z_split, jac, x_seed, converged_split, Jl_split, x_split, &
                                          strict_controls=.true., near_escape_mode=.true.)
               if (.not. converged_split) cycle

               converged = .false.
               do promote_idx = 1, 3
                  select case (promote_idx)
                  case (1)
                     x_promote = x_split
                  case (2)
                     x_promote = -x_split
                  case default
                     x_promote = 0.35_dp*x_split
                  end select

                  Jl = 0.0_dp
                  x_new = xt
                  call run_delz_continuation(f, tol_near, max_iter, 0, xt, z, del_z, jac, x_promote, converged_promote, Jl, x_new, &
                                             strict_controls=.true., near_escape_mode=.true.)
                  if (converged_promote) then
                     converged = .true.
                     exit
                  end if
               end do
            end if

            if (converged) exit
         end do

         if (converged) exit
      end do

      ! Near-only terminal rescue:
      ! strict continuation is only invoked from near branch in the integrator, so this
      ! extra paper-exact pass is rare and targets the final few stubborn near cases.
      if (.not. converged) then
         final_paper_iter = max(64, min(max_iter, terminal_paper_iter_cap))
         do seed_idx = 1, 3
            select case (seed_idx)
            case (1)
               x_seed = x_seed_base
            case (2)
               x_seed = -x_seed_base
            case default
               x_seed = 0.35_dp*x_seed_base
            end select

            Jl = 0.0_dp
            x_new = xt
            call run_quasi_newton_attempt(f, tol_near, final_paper_iter, 0, xt, z, del_z, jac, x_seed, converged_paper, Jl, x_new, &
                                          paper_exact=.true., near_escape_mode=.true.)
            if (converged_paper) then
               converged = .true.
               exit
            end if
         end do
      end if

      ! Terminal hard pass (near-only):
      ! if near-escape shaping still cannot converge, do a paper-exact solve
      ! with conservative step guards to prioritize final consistency.
      if (.not. converged) then
         final_hard_iter = max(128, min(max_iter, terminal_hard_iter_cap))
         do seed_idx = 1, 3
            select case (seed_idx)
            case (1)
               x_seed = x_seed_base
            case (2)
               x_seed = -x_seed_base
            case default
               x_seed = 0.35_dp*x_seed_base
            end select

            Jl = 0.0_dp
            x_new = xt
            call run_quasi_newton_attempt(f, tol_near, final_hard_iter, 0, xt, z, del_z, jac, x_seed, converged_paper_hard, Jl, x_new, &
                                          paper_exact=.true., near_escape_mode=.false.)
            if (converged_paper_hard) then
               converged = .true.
               exit
            end if
         end do
      end if

      if (.not. converged) then
         x_new = xt
         Jl = 0.0_dp
      end if

      ierr = .not. converged
      deallocate (x_seed, x_seed_base, del_z_split, Jl_split, x_split, x_promote)
   end subroutine solve_constraint_quasi_newton_strict_continuation

   subroutine run_dfo_ls_attempt(f, tol, max_iter, attempt_idx, xt, z, del_z, jac, x_init, converged, Jl, x_new, &
                                 x_best_out, best_res_out)
      implicit none
      integer, intent(in) :: max_iter
      integer, intent(in) :: attempt_idx
      real(dp), intent(in) :: tol
      real(dp), intent(in) :: xt(:), del_z(:), x_init(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      logical, intent(out) :: converged
      real(dp), intent(out) :: Jl(:), x_new(:)
      real(dp), intent(out), optional :: x_best_out(:)
      real(dp), intent(out), optional :: best_res_out

      interface
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac)
            use, intrinsic :: iso_fortran_env, only: real64
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
         end subroutine f
      end interface

      real(dp), parameter :: trust_radius_min = 1.0e-6_dp
      real(dp), parameter :: trust_radius_max = 5.0_dp
      real(dp), parameter :: eta_accept = 1.0e-2_dp
      real(dp), parameter :: eta_expand = 0.80_dp
      real(dp), parameter :: eta_shrink = 0.20_dp
      real(dp), parameter :: lambda_min = 1.0e-10_dp
      real(dp), parameter :: lambda_max = 1.0e12_dp
      real(dp), parameter :: stagnation_rel = 2.0e-3_dp
      real(dp), parameter :: weak_progress_rel = 5.0e-4_dp
      real(dp), parameter :: escape_len_floor = 5.0e-3_dp
      real(dp), parameter :: escape_len_scale = 5.0e-3_dp
      real(dp), parameter :: escape_improve_rel = 2.0e-3_dp
      integer, parameter :: escape_trigger_score = 6

      integer :: n, iter_idx, i, solve_try, stagnation_limit, no_improve_count
      integer :: stall_score, escape_try, axis_idx
      real(dp) :: trust_radius, lambda, lambda_trial, step_norm
      real(dp) :: r_norm, r_trial_norm, best_r_norm, prev_best_r_norm
      real(dp) :: f_obj, f_obj_trial, ared, pred, ratio, alpha_ratio
      real(dp) :: prev_r_norm, g_norm, escape_len, escape_len_base, x_norm
      logical :: eval_error, lin_error, accepted, escaped, escape_accept

      real(dp), allocatable :: x(:), x_trial(:), r(:), r_trial(:)
      real(dp), allocatable :: Jm(:, :), Hm(:, :), Bm(:, :), g(:), step(:), hs(:)
      real(dp), allocatable :: Jl_trial(:), x_best(:), Jl_best(:)

      n = 2*size(z)
      converged = .false.
      x_new = xt
      if (size(x_new) /= size(xt) .or. size(Jl) /= size(del_z)) return

      allocate (x(n), x_trial(n), r(n), r_trial(n), Jm(n, n), Hm(n, n), Bm(n, n), g(n), step(n), hs(n), &
                Jl_trial(n), x_best(n), Jl_best(n))

      if (size(x_init) == n) then
         x = x_init
      else
         x = 0.0_dp
      end if

      quasi_trace_iter = 0
      call f(xt, z, x, r, del_z, eval_error, Jl, jac)
      if (eval_error .or. .not. real_vector_is_finite(r)) then
         x = 0.0_dp
         quasi_trace_iter = 0
         call f(xt, z, x, r, del_z, eval_error, Jl, jac)
      end if
      if (eval_error .or. .not. real_vector_is_finite(r)) then
         call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, huge(1.0_dp), .false., .false.)
         deallocate (x, x_trial, r, r_trial, Jm, Hm, Bm, g, step, hs, Jl_trial, x_best, Jl_best)
         return
      end if

      r_norm = norm2(r)
      if (.not. ieee_is_finite(r_norm)) then
         call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, huge(1.0_dp), .false., .false.)
         deallocate (x, x_trial, r, r_trial, Jm, Hm, Bm, g, step, hs, Jl_trial, x_best, Jl_best)
         return
      end if

      call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, r_norm, .false., .true.)
      best_r_norm = r_norm
      prev_best_r_norm = best_r_norm
      x_best = x
      Jl_best = Jl
      trust_radius = max(trust_radius_min, min(trust_radius_max, max(0.25_dp, norm2(x))))
      lambda = max(lambda_min, 1.0e-4_dp*max(1.0_dp, r_norm))
      if (r_norm <= 1.0e-4_dp) then
         trust_radius = min(trust_radius, 8.0e-2_dp)
         lambda = max(lambda, 5.0e-3_dp)
      end if
      if (r_norm <= 1.0e-6_dp) then
         trust_radius = min(trust_radius, 3.0e-2_dp)
         lambda = max(lambda, 2.0e-2_dp)
      end if
      no_improve_count = 0
      stall_score = 0
      stagnation_limit = max(16, min(40, max_iter/2))

      do iter_idx = 1, max_iter
         if (quasi_watchdog_scope_active .and. quasi_watchdog_hit) exit
         if (residual_within_accept_tolerance(r_norm, tol)) exit
         prev_r_norm = r_norm

         call build_dfo_gn_jacobian(f, xt, z, del_z, jac, x, r, trust_radius, iter_idx, Jm)
         Hm = matmul(transpose(Jm), Jm)
         g = matmul(transpose(Jm), r)
         if (.not. real_vector_is_finite(g)) then
            call append_quasi_trace_sample(0.0_dp, iter_idx, 0, attempt_idx, huge(1.0_dp), .false., .false.)
            trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
            lambda = min(lambda_max, max(10.0_dp*lambda, 1.0e-6_dp))
            cycle
         end if

         accepted = .false.
         lambda_trial = lambda
         do solve_try = 1, 8
            Bm = Hm
            do i = 1, n
               Bm(i, i) = Bm(i, i) + lambda_trial*max(1.0_dp, Hm(i, i))
            end do
            call solve_linear_direction(g, Bm, step, lin_error)
            if (lin_error .or. .not. real_vector_is_finite(step)) then
               lambda_trial = min(lambda_max, 10.0_dp*lambda_trial)
               cycle
            end if

            step_norm = norm2(step)
            if (.not. ieee_is_finite(step_norm) .or. step_norm <= tiny(1.0_dp)) then
               lin_error = .true.
               lambda_trial = min(lambda_max, 10.0_dp*lambda_trial)
               cycle
            end if
            if (step_norm > trust_radius) then
               step = step*(trust_radius/step_norm)
               step_norm = trust_radius
            end if

            x_trial = x + step
            quasi_trace_iter = iter_idx
            call f(xt, z, x_trial, r_trial, del_z, eval_error, Jl_trial, jac)
            if (eval_error .or. .not. real_vector_is_finite(r_trial)) then
               call append_quasi_trace_sample(0.0_dp, iter_idx, 0, attempt_idx, huge(1.0_dp), .false., .false.)
               trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
               lambda_trial = min(lambda_max, 4.0_dp*lambda_trial)
               cycle
            end if

            r_trial_norm = norm2(r_trial)
            if (.not. ieee_is_finite(r_trial_norm)) then
               call append_quasi_trace_sample(0.0_dp, iter_idx, 0, attempt_idx, huge(1.0_dp), .false., .false.)
               trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
               lambda_trial = min(lambda_max, 4.0_dp*lambda_trial)
               cycle
            end if

            hs = matmul(Hm, step)
            f_obj = 0.5_dp*r_norm*r_norm
            f_obj_trial = 0.5_dp*r_trial_norm*r_trial_norm
            ared = f_obj - f_obj_trial
            pred = -(dot_product(g, step) + 0.5_dp*dot_product(step, hs))
            if ((.not. ieee_is_finite(pred)) .or. pred <= tiny(1.0_dp)) then
               pred = max(1.0e-16_dp, 0.5_dp*lambda_trial*dot_product(step, step))
            end if
            ratio = ared/max(pred, tiny(1.0_dp))
            accepted = residual_within_accept_tolerance(r_trial_norm, tol) .or. &
                       (ieee_is_finite(ared) .and. ared > 0.0_dp .and. ieee_is_finite(ratio) .and. ratio >= eta_accept)

            alpha_ratio = min(1.0_dp, step_norm/max(trust_radius, tiny(1.0_dp)))
            call append_quasi_trace_sample(alpha_ratio, iter_idx, 0, attempt_idx, r_trial_norm, accepted, .true.)

            if (accepted) then
               x = x_trial
               r = r_trial
               r_norm = r_trial_norm
               Jl = Jl_trial
               if (r_norm < best_r_norm) then
                  best_r_norm = r_norm
                  x_best = x
                  Jl_best = Jl
               end if

               if (ieee_is_finite(ratio)) then
                  if (ratio >= eta_expand .and. step_norm >= 0.8_dp*trust_radius) then
                     trust_radius = min(trust_radius_max, 1.8_dp*trust_radius)
                  elseif (ratio < eta_shrink) then
                     trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
                  end if
               end if
               if (.not. ieee_is_finite(ratio)) then
                  lambda = min(lambda_max, max(lambda_trial, 2.5_dp*lambda))
               else if (ratio >= 0.90_dp) then
                  lambda = max(lambda_min, 0.35_dp*lambda_trial)
               else if (ratio >= 0.50_dp) then
                  lambda = max(lambda_min, 0.65_dp*lambda_trial)
               else if (ratio < 0.10_dp) then
                  lambda = min(lambda_max, max(2.5_dp*lambda_trial, lambda))
               else
                  lambda = min(lambda_max, max(1.2_dp*lambda_trial, lambda_min))
               end if
               if (r_norm <= prev_r_norm*(1.0_dp - weak_progress_rel)) then
                  stall_score = max(0, stall_score - 1)
               else
                  stall_score = stall_score + 1
               end if
               exit
            else
               trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
               lambda_trial = min(lambda_max, 4.0_dp*lambda_trial)
            end if
         end do

         if (.not. accepted) then
            lambda = min(lambda_max, max(lambda_trial, 4.0_dp*lambda))
            stall_score = stall_score + 2
         end if

         escaped = .false.
         if (iter_idx >= 5 .and. stall_score >= escape_trigger_score) then
            g_norm = norm2(g)
            x_norm = norm2(x)
            escape_len_base = min(trust_radius_max, max(6.0_dp*trust_radius, escape_len_floor, escape_len_scale*max(1.0_dp, x_norm)))
            do escape_try = 1, 4
               step = 0.0_dp
               select case (escape_try)
               case (1)
                  if (ieee_is_finite(g_norm) .and. g_norm > tiny(1.0_dp)) then
                     step = -g/g_norm
                  else
                     axis_idx = 1 + mod(iter_idx + attempt_idx - 1, n)
                     step(axis_idx) = 1.0_dp
                  end if
               case (2)
                  if (ieee_is_finite(g_norm) .and. g_norm > tiny(1.0_dp)) then
                     step = g/g_norm
                  else
                     axis_idx = 1 + mod(iter_idx + attempt_idx - 1, n)
                     step(axis_idx) = -1.0_dp
                  end if
               case (3)
                  axis_idx = 1 + mod(2*iter_idx + attempt_idx - 1, n)
                  step(axis_idx) = 1.0_dp
               case default
                  axis_idx = 1 + mod(2*iter_idx + attempt_idx - 1, n)
                  step(axis_idx) = -1.0_dp
               end select
               select case (escape_try)
               case (1)
                  escape_len = escape_len_base
               case (2)
                  escape_len = min(trust_radius_max, 2.5_dp*escape_len_base)
               case (3)
                  escape_len = min(trust_radius_max, 7.0_dp*escape_len_base)
               case default
                  escape_len = min(trust_radius_max, max(18.0_dp*escape_len_base, 0.15_dp + 0.08_dp*x_norm))
               end select

               x_trial = x + escape_len*step
               quasi_trace_iter = iter_idx
               call f(xt, z, x_trial, r_trial, del_z, eval_error, Jl_trial, jac)
               if (eval_error .or. .not. real_vector_is_finite(r_trial)) then
                  call append_quasi_trace_sample(0.0_dp, iter_idx, 100 + escape_try, attempt_idx, huge(1.0_dp), .false., .false.)
                  cycle
               end if

               r_trial_norm = norm2(r_trial)
               if (.not. ieee_is_finite(r_trial_norm)) then
                  call append_quasi_trace_sample(0.0_dp, iter_idx, 100 + escape_try, attempt_idx, huge(1.0_dp), .false., .false.)
                  cycle
               end if

               escape_accept = residual_within_accept_tolerance(r_trial_norm, tol) .or. &
                               (r_trial_norm <= r_norm*(1.0_dp - escape_improve_rel))
               alpha_ratio = min(1.0_dp, escape_len/max(trust_radius, tiny(1.0_dp)))
               call append_quasi_trace_sample(alpha_ratio, iter_idx, 100 + escape_try, attempt_idx, r_trial_norm, escape_accept, .true.)
               if (.not. escape_accept) cycle

               x = x_trial
               r = r_trial
               r_norm = r_trial_norm
               Jl = Jl_trial
               if (r_norm < best_r_norm) then
                  best_r_norm = r_norm
                  x_best = x
                  Jl_best = Jl
               end if
               trust_radius = min(trust_radius_max, max(trust_radius, 0.75_dp*escape_len))
               lambda = max(lambda_min, 0.60_dp*lambda)
               stall_score = 0
               accepted = .true.
               escaped = .true.
               exit
            end do
         end if

         if (.not. accepted) then
            if (trust_radius <= 1.05_dp*trust_radius_min .and. .not. escaped) exit
         end if

         if (best_r_norm <= prev_best_r_norm*(1.0_dp - stagnation_rel)) then
            no_improve_count = 0
         else
            no_improve_count = no_improve_count + 1
         end if
         prev_best_r_norm = min(prev_best_r_norm, best_r_norm)
         if (iter_idx >= 8 .and. no_improve_count >= stagnation_limit) exit
      end do

      call rescue_attempt_from_best(xt, z, del_z, tol, Jl_best, best_r_norm, x_new, Jl, converged)
      if (.not. converged) then
         x_new = xt
         if (size(Jl_best) == size(Jl)) Jl = Jl_best
      end if
      if (present(x_best_out)) then
         if (size(x_best_out) == size(x_best)) x_best_out = x_best
      end if
      if (present(best_res_out)) best_res_out = best_r_norm

      deallocate (x, x_trial, r, r_trial, Jm, Hm, Bm, g, step, hs, Jl_trial, x_best, Jl_best)
   end subroutine run_dfo_ls_attempt

   subroutine run_dfo_gn_attempt(f, tol, max_iter, attempt_idx, xt, z, del_z, jac, x_init, converged, Jl, x_new, &
                                 x_best_out, best_res_out)
      implicit none
      integer, intent(in) :: max_iter
      integer, intent(in) :: attempt_idx
      real(dp), intent(in) :: tol
      real(dp), intent(in) :: xt(:), del_z(:), x_init(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      logical, intent(out) :: converged
      real(dp), intent(out) :: Jl(:), x_new(:)
      real(dp), intent(out), optional :: x_best_out(:)
      real(dp), intent(out), optional :: best_res_out

      interface
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac)
            use, intrinsic :: iso_fortran_env, only: real64
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
         end subroutine f
      end interface

      real(dp), parameter :: trust_radius_min = 1.0e-6_dp
      real(dp), parameter :: trust_radius_max = 5.0_dp
      real(dp), parameter :: eta_accept = 1.0e-2_dp
      real(dp), parameter :: eta_expand = 0.80_dp
      real(dp), parameter :: eta_shrink = 0.20_dp
      real(dp), parameter :: lambda_min = 1.0e-10_dp
      real(dp), parameter :: lambda_max = 1.0e12_dp
      real(dp), parameter :: stagnation_rel = 2.0e-3_dp

      integer :: n, iter_idx, i, solve_try, stagnation_limit, no_improve_count, refresh_stride
      real(dp) :: trust_radius, lambda, lambda_trial, step_norm
      real(dp) :: r_norm, r_trial_norm, best_r_norm, prev_best_r_norm
      real(dp) :: f_obj, f_obj_trial, ared, pred, ratio, alpha_ratio
      logical :: eval_error, lin_error, accepted, rebuild_model

      real(dp), allocatable :: x(:), x_trial(:), r(:), r_trial(:)
      real(dp), allocatable :: Jm(:, :), Hm(:, :), Bm(:, :), g(:), step(:), hs(:)
      real(dp), allocatable :: Jl_trial(:), x_best(:), Jl_best(:), y(:)

      n = 2*size(z)
      converged = .false.
      x_new = xt
      if (size(x_new) /= size(xt) .or. size(Jl) /= size(del_z)) return

      allocate (x(n), x_trial(n), r(n), r_trial(n), Jm(n, n), Hm(n, n), Bm(n, n), g(n), step(n), hs(n), &
                Jl_trial(n), x_best(n), Jl_best(n), y(n))

      if (size(x_init) == n) then
         x = x_init
      else
         x = 0.0_dp
      end if

      quasi_trace_iter = 0
      call f(xt, z, x, r, del_z, eval_error, Jl, jac)
      if (eval_error .or. .not. real_vector_is_finite(r)) then
         x = 0.0_dp
         quasi_trace_iter = 0
         call f(xt, z, x, r, del_z, eval_error, Jl, jac)
      end if
      if (eval_error .or. .not. real_vector_is_finite(r)) then
         call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, huge(1.0_dp), .false., .false.)
         deallocate (x, x_trial, r, r_trial, Jm, Hm, Bm, g, step, hs, Jl_trial, x_best, Jl_best)
         return
      end if

      r_norm = norm2(r)
      if (.not. ieee_is_finite(r_norm)) then
         call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, huge(1.0_dp), .false., .false.)
         deallocate (x, x_trial, r, r_trial, Jm, Hm, Bm, g, step, hs, Jl_trial, x_best, Jl_best)
         return
      end if

      call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, r_norm, .false., .true.)
      best_r_norm = r_norm
      prev_best_r_norm = best_r_norm
      x_best = x
      Jl_best = Jl
      trust_radius = max(trust_radius_min, min(trust_radius_max, max(0.25_dp, norm2(x))))
      lambda = max(lambda_min, 1.0e-4_dp*max(1.0_dp, r_norm))
      no_improve_count = 0
      stagnation_limit = max(16, min(40, max_iter/2))
      refresh_stride = max(6, min(16, n/2 + 4))

      ! Build one local interpolation/FD Jacobian, then update it cheaply with Broyden.
      call build_dfo_gn_jacobian(f, xt, z, del_z, jac, x, r, trust_radius, 0, Jm)
      if (maxval(abs(Jm)) <= tiny(1.0_dp)) call set_identity_matrix(Jm)

      do iter_idx = 1, max_iter
         if (quasi_watchdog_scope_active .and. quasi_watchdog_hit) exit
         if (residual_within_accept_tolerance(r_norm, tol)) exit

         Hm = matmul(transpose(Jm), Jm)
         g = matmul(transpose(Jm), r)
         if (.not. real_vector_is_finite(g)) then
            call append_quasi_trace_sample(0.0_dp, iter_idx, 0, attempt_idx, huge(1.0_dp), .false., .false.)
            trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
            lambda = min(lambda_max, max(10.0_dp*lambda, 1.0e-6_dp))
            call build_dfo_gn_jacobian(f, xt, z, del_z, jac, x, r, trust_radius, iter_idx, Jm)
            cycle
         end if

         accepted = .false.
         lambda_trial = lambda
         do solve_try = 1, 8
            Bm = Hm
            do i = 1, n
               Bm(i, i) = Bm(i, i) + lambda_trial*max(1.0_dp, Hm(i, i))
            end do
            call solve_linear_direction(g, Bm, step, lin_error)
            if (lin_error .or. .not. real_vector_is_finite(step)) then
               lambda_trial = min(lambda_max, 10.0_dp*lambda_trial)
               cycle
            end if

            step_norm = norm2(step)
            if (.not. ieee_is_finite(step_norm) .or. step_norm <= tiny(1.0_dp)) then
               lin_error = .true.
               lambda_trial = min(lambda_max, 10.0_dp*lambda_trial)
               cycle
            end if
            if (step_norm > trust_radius) then
               step = step*(trust_radius/step_norm)
               step_norm = trust_radius
            end if

            x_trial = x + step
            quasi_trace_iter = iter_idx
            call f(xt, z, x_trial, r_trial, del_z, eval_error, Jl_trial, jac)
            if (eval_error .or. .not. real_vector_is_finite(r_trial)) then
               call append_quasi_trace_sample(0.0_dp, iter_idx, 0, attempt_idx, huge(1.0_dp), .false., .false.)
               trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
               lambda_trial = min(lambda_max, 4.0_dp*lambda_trial)
               cycle
            end if

            r_trial_norm = norm2(r_trial)
            if (.not. ieee_is_finite(r_trial_norm)) then
               call append_quasi_trace_sample(0.0_dp, iter_idx, 0, attempt_idx, huge(1.0_dp), .false., .false.)
               trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
               lambda_trial = min(lambda_max, 4.0_dp*lambda_trial)
               cycle
            end if

            hs = matmul(Hm, step)
            f_obj = 0.5_dp*r_norm*r_norm
            f_obj_trial = 0.5_dp*r_trial_norm*r_trial_norm
            ared = f_obj - f_obj_trial
            pred = -(dot_product(g, step) + 0.5_dp*dot_product(step, hs))
            if ((.not. ieee_is_finite(pred)) .or. pred <= tiny(1.0_dp)) then
               pred = max(1.0e-16_dp, 0.5_dp*lambda_trial*dot_product(step, step))
            end if
            ratio = ared/max(pred, tiny(1.0_dp))
            accepted = residual_within_accept_tolerance(r_trial_norm, tol) .or. &
                       (ieee_is_finite(ared) .and. ared > 0.0_dp .and. ieee_is_finite(ratio) .and. ratio >= eta_accept)

            alpha_ratio = min(1.0_dp, step_norm/max(trust_radius, tiny(1.0_dp)))
            call append_quasi_trace_sample(alpha_ratio, iter_idx, 0, attempt_idx, r_trial_norm, accepted, .true.)

            if (accepted) then
               y = r_trial - r
               if (step_norm > sqrt(epsilon(1.0_dp))*max(1.0_dp, norm2(x))) call broyden_rank1_update(Jm, step, y)
               x = x_trial
               r = r_trial
               r_norm = r_trial_norm
               Jl = Jl_trial
               if (r_norm < best_r_norm) then
                  best_r_norm = r_norm
                  x_best = x
                  Jl_best = Jl
               end if

               if (ieee_is_finite(ratio)) then
                  if (ratio >= eta_expand .and. step_norm >= 0.8_dp*trust_radius) then
                     trust_radius = min(trust_radius_max, 1.8_dp*trust_radius)
                  elseif (ratio < eta_shrink) then
                     trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
                  end if
               end if
               if (.not. ieee_is_finite(ratio)) then
                  lambda = min(lambda_max, max(lambda_trial, 2.5_dp*lambda))
               else if (ratio >= 0.90_dp) then
                  lambda = max(lambda_min, 0.35_dp*lambda_trial)
               else if (ratio >= 0.50_dp) then
                  lambda = max(lambda_min, 0.65_dp*lambda_trial)
               else if (ratio < 0.10_dp) then
                  lambda = min(lambda_max, max(2.5_dp*lambda_trial, lambda))
               else
                  lambda = min(lambda_max, max(1.2_dp*lambda_trial, lambda_min))
               end if

               rebuild_model = (mod(iter_idx, refresh_stride) == 0) .or. &
                               (.not. ieee_is_finite(ratio)) .or. &
                               (ratio < 2.0e-2_dp .and. r_norm > max(1.0e3_dp*tol, 1.0e-6_dp))
               if (rebuild_model) then
                  call build_dfo_gn_jacobian(f, xt, z, del_z, jac, x, r, trust_radius, iter_idx, Jm)
               end if
               exit
            else
               trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
               lambda_trial = min(lambda_max, 4.0_dp*lambda_trial)
            end if
         end do

         if (.not. accepted) then
            lambda = min(lambda_max, max(lambda_trial, 4.0_dp*lambda))
            if (mod(iter_idx, 4) == 0) then
               call build_dfo_gn_jacobian(f, xt, z, del_z, jac, x, r, trust_radius, iter_idx, Jm)
            end if
            if (trust_radius <= 1.05_dp*trust_radius_min) exit
         end if

         if (best_r_norm <= prev_best_r_norm*(1.0_dp - stagnation_rel)) then
            no_improve_count = 0
         else
            no_improve_count = no_improve_count + 1
         end if
         prev_best_r_norm = min(prev_best_r_norm, best_r_norm)
         if (iter_idx >= 8 .and. no_improve_count >= stagnation_limit) exit
      end do

      call rescue_attempt_from_best(xt, z, del_z, tol, Jl_best, best_r_norm, x_new, Jl, converged)
      if (.not. converged) then
         x_new = xt
         if (size(Jl_best) == size(Jl)) Jl = Jl_best
      end if
      if (present(x_best_out)) then
         if (size(x_best_out) == size(x_best)) x_best_out = x_best
      end if
      if (present(best_res_out)) best_res_out = best_r_norm

      deallocate (x, x_trial, r, r_trial, Jm, Hm, Bm, g, step, hs, Jl_trial, x_best, Jl_best, y)
   end subroutine run_dfo_gn_attempt

   subroutine run_dfo_gn_paper_attempt(f, tol, max_iter, attempt_idx, xt, z, del_z, jac, x_init, converged, Jl, x_new, &
                                       x_best_out, best_res_out, paper_exact)
      implicit none
      integer, intent(in) :: max_iter
      integer, intent(in) :: attempt_idx
      real(dp), intent(in) :: tol
      real(dp), intent(in) :: xt(:), del_z(:), x_init(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      logical, intent(out) :: converged
      real(dp), intent(out) :: Jl(:), x_new(:)
      real(dp), intent(out), optional :: x_best_out(:)
      real(dp), intent(out), optional :: best_res_out
      logical, intent(in), optional :: paper_exact

      interface
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac)
            use, intrinsic :: iso_fortran_env, only: real64
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
         end subroutine f
      end interface

      real(dp), parameter :: eps_crit_floor = 1.0e-8_dp
      real(dp), parameter :: mu_crit = 10.0_dp
      real(dp), parameter :: lambda_poised = 10.0_dp
      real(dp), parameter :: lambda_reg_min = 1.0e-10_dp
      real(dp), parameter :: lambda_reg_max = 1.0e12_dp
      real(dp), parameter :: delta_eps = 1.0e-12_dp
      real(dp), parameter :: stagnation_rel = 2.0e-3_dp

      integer :: n, iter_idx, stagnation_limit, no_improve_count, max_geom_iter, worst_idx
      real(dp) :: delta_k, rho_k, delta_next, lambda_reg, step_norm
      real(dp) :: r_norm, r_trial_norm, best_r_norm, prev_best_r_norm
      real(dp) :: f_obj, f_obj_trial, ared, pred, ratio, alpha_ratio, grad_norm, worst_poise
      real(dp) :: delta_min_local, delta_max_local
      real(dp) :: eta1_local, eta2_local, gamma_dec_local, gamma_inc_local, gamma_inc_bar_local
      real(dp) :: alpha1_local, alpha2_local, omega_s_local, gamma_s_local
      logical :: eval_error, lin_error, accepted, model_ok, set_ok, poised_ok, geom_ok, use_paper_exact

      real(dp), allocatable :: x(:), x_trial(:), r(:), r_trial(:)
      real(dp), allocatable :: Jm(:, :), Hm(:, :), g(:), step(:), hs(:)
      real(dp), allocatable :: Jl_trial(:), x_best(:), Jl_best(:)
      real(dp), allocatable :: Y(:, :), RY(:, :)
      complex(dp) :: z_new(size(z))

      n = 2*size(z)
      converged = .false.
      x_new = xt
      if (size(x_new) /= size(xt) .or. size(Jl) /= size(del_z)) return

      allocate (x(n), x_trial(n), r(n), r_trial(n), Jm(n, n), Hm(n, n), g(n), step(n), hs(n), &
                Jl_trial(n), x_best(n), Jl_best(n), Y(n, n + 1), RY(n, n + 1))

      use_paper_exact = .false.
      if (present(paper_exact)) use_paper_exact = paper_exact
      if (use_paper_exact) then
         delta_min_local = 1.0e-10_dp
         delta_max_local = 1.0e10_dp
         eta1_local = 1.0e-1_dp
         eta2_local = 7.0e-1_dp
         gamma_dec_local = 0.5_dp
         gamma_inc_local = 2.0_dp
         gamma_inc_bar_local = 4.0_dp
         alpha1_local = 0.1_dp
         alpha2_local = 0.5_dp
         omega_s_local = 0.1_dp
         gamma_s_local = 0.5_dp
      else
         delta_min_local = 1.0e-6_dp
         delta_max_local = 5.0_dp
         eta1_local = 1.0e-1_dp
         eta2_local = 7.0e-1_dp
         gamma_dec_local = 0.5_dp
         gamma_inc_local = 1.8_dp
         gamma_inc_bar_local = 3.0_dp
         alpha1_local = 0.5_dp
         alpha2_local = 0.9_dp
         omega_s_local = 0.5_dp
         gamma_s_local = 0.1_dp
      end if

      if (size(x_init) == n) then
         x = x_init
      else
         x = 0.0_dp
      end if

      quasi_trace_iter = 0
      call f(xt, z, x, r, del_z, eval_error, Jl, jac)
      if ((.not. use_paper_exact) .and. (eval_error .or. .not. real_vector_is_finite(r))) then
         x = 0.0_dp
         quasi_trace_iter = 0
         call f(xt, z, x, r, del_z, eval_error, Jl, jac)
      end if
      if (eval_error .or. .not. real_vector_is_finite(r)) then
         call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, huge(1.0_dp), .false., .false.)
         deallocate (x, x_trial, r, r_trial, Jm, Hm, g, step, hs, Jl_trial, x_best, Jl_best, Y, RY)
         return
      end if

      r_norm = norm2(r)
      if (.not. ieee_is_finite(r_norm)) then
         call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, huge(1.0_dp), .false., .false.)
         deallocate (x, x_trial, r, r_trial, Jm, Hm, g, step, hs, Jl_trial, x_best, Jl_best, Y, RY)
         return
      end if

      call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, r_norm, .false., .true.)
      best_r_norm = r_norm
      prev_best_r_norm = best_r_norm
      x_best = x
      Jl_best = Jl
      if (use_paper_exact) then
         delta_k = max(delta_min_local, min(delta_max_local, 0.1_dp*max(maxval(abs(x)), 1.0_dp)))
      else
         delta_k = max(delta_min_local, min(delta_max_local, max(0.25_dp, norm2(x))))
      end if
      rho_k = delta_k
      lambda_reg = max(lambda_reg_min, 1.0e-4_dp*max(1.0_dp, r_norm))
      no_improve_count = 0
      if (use_paper_exact) then
         stagnation_limit = max_iter + 1
      else
         stagnation_limit = max(16, min(40, max_iter/2))
      end if
      max_geom_iter = max(6, min(24, n + 4))

      call rebuild_linear_interp_set(f, xt, z, del_z, jac, x, r, delta_k, Y, RY, set_ok)
      if (.not. set_ok) then
         deallocate (x, x_trial, r, r_trial, Jm, Hm, g, step, hs, Jl_trial, x_best, Jl_best, Y, RY)
         return
      end if
      call improve_linear_interp_geometry(f, xt, z, del_z, jac, x, delta_k, lambda_poised, max_geom_iter, Y, RY, geom_ok)

      do iter_idx = 1, max_iter
         if (residual_within_accept_tolerance(r_norm, tol)) exit

         call build_linear_interp_jacobian(Y, RY, Jm, model_ok)
         if (.not. model_ok) then
            call rebuild_linear_interp_set(f, xt, z, del_z, jac, x, r, delta_k, Y, RY, set_ok)
            if (set_ok) call build_linear_interp_jacobian(Y, RY, Jm, model_ok)
         end if
         if (.not. model_ok) then
            call set_identity_matrix(Jm)
         end if

         call linear_interp_set_is_poised(Y, delta_k, lambda_poised, poised_ok, worst_idx, worst_poise)
         if (.not. poised_ok) then
            call improve_linear_interp_geometry(f, xt, z, del_z, jac, x, delta_k, lambda_poised, max_geom_iter, Y, RY, geom_ok)
            call build_linear_interp_jacobian(Y, RY, Jm, model_ok)
            if (.not. model_ok) call set_identity_matrix(Jm)
         end if

         Hm = matmul(transpose(Jm), Jm)
         g = matmul(transpose(Jm), r)
         if (.not. real_vector_is_finite(g)) then
            call append_quasi_trace_sample(0.0_dp, iter_idx, 0, attempt_idx, huge(1.0_dp), .false., .false.)
            delta_k = max(rho_k, gamma_dec_local*delta_k)
            lambda_reg = min(lambda_reg_max, max(10.0_dp*lambda_reg, 1.0e-6_dp))
            call rebuild_linear_interp_set(f, xt, z, del_z, jac, x, r, delta_k, Y, RY, set_ok)
            cycle
         end if

         grad_norm = norm2(g)
         if (grad_norm <= max(eps_crit_floor, sqrt(max(tol, 1.0e-18_dp)))) then
            delta_k = min(delta_k, max(rho_k, mu_crit*max(grad_norm, eps_crit_floor)))
            call improve_linear_interp_geometry(f, xt, z, del_z, jac, x, delta_k, lambda_poised, max_geom_iter, Y, RY, geom_ok)
            call build_linear_interp_jacobian(Y, RY, Jm, model_ok)
            if (model_ok) then
               Hm = matmul(transpose(Jm), Jm)
               g = matmul(transpose(Jm), r)
               grad_norm = norm2(g)
            end if
         end if

         call paper_trust_region_step(Hm, g, delta_k, lambda_reg, step, step_norm, lin_error)
         if (lin_error .or. .not. ieee_is_finite(step_norm) .or. step_norm <= tiny(1.0_dp)) then
            delta_k = max(rho_k, gamma_dec_local*delta_k)
            lambda_reg = min(lambda_reg_max, max(2.0_dp*lambda_reg, lambda_reg_min))
            call append_quasi_trace_sample(0.0_dp, iter_idx, 0, attempt_idx, r_norm, .false., .false.)
            cycle
         end if

         if (step_norm < gamma_s_local*rho_k) then
            delta_next = max(rho_k, omega_s_local*delta_k)
            call improve_linear_interp_geometry(f, xt, z, del_z, jac, x, delta_next, lambda_poised, max_geom_iter, Y, RY, geom_ok)
            if (abs(delta_next - rho_k) <= delta_eps) then
               rho_k = max(delta_min_local, alpha1_local*rho_k)
               delta_k = max(rho_k, alpha2_local*rho_k)
            else
               delta_k = delta_next
            end if
            alpha_ratio = min(1.0_dp, step_norm/max(delta_k, tiny(1.0_dp)))
            call append_quasi_trace_sample(alpha_ratio, iter_idx, 0, attempt_idx, r_norm, .false., .true.)
            cycle
         end if

         x_trial = x + step
         quasi_trace_iter = iter_idx
         call f(xt, z, x_trial, r_trial, del_z, eval_error, Jl_trial, jac)
         if (eval_error .or. .not. real_vector_is_finite(r_trial)) then
            ratio = -huge(1.0_dp)
            accepted = .false.
            delta_next = max(min(gamma_dec_local*delta_k, step_norm), rho_k)
            call append_quasi_trace_sample(min(1.0_dp, step_norm/max(delta_k, tiny(1.0_dp))), iter_idx, 0, attempt_idx, &
                                           huge(1.0_dp), .false., .false.)
         else
            r_trial_norm = norm2(r_trial)
            if (.not. ieee_is_finite(r_trial_norm)) then
               ratio = -huge(1.0_dp)
               accepted = .false.
               delta_next = max(min(gamma_dec_local*delta_k, step_norm), rho_k)
               call append_quasi_trace_sample(min(1.0_dp, step_norm/max(delta_k, tiny(1.0_dp))), iter_idx, 0, attempt_idx, &
                                              huge(1.0_dp), .false., .false.)
            else
               hs = matmul(Hm, step)
               f_obj = 0.5_dp*r_norm*r_norm
               f_obj_trial = 0.5_dp*r_trial_norm*r_trial_norm
               ared = f_obj - f_obj_trial
               pred = -(dot_product(g, step) + 0.5_dp*dot_product(step, hs))
               if ((.not. ieee_is_finite(pred)) .or. pred <= tiny(1.0_dp)) then
                  pred = max(1.0e-16_dp, 0.5_dp*lambda_reg*dot_product(step, step))
               end if
               ratio = ared/max(pred, tiny(1.0_dp))
               accepted = ((use_paper_exact .and. residual_within_tolerance(r_trial_norm, tol)) .or. &
                           ((.not. use_paper_exact) .and. residual_within_accept_tolerance(r_trial_norm, tol)) .or. &
                           (ieee_is_finite(ared) .and. ared > 0.0_dp .and. ieee_is_finite(ratio) .and. ratio >= eta1_local))
               if (ratio >= eta2_local) then
                  delta_next = min(max(gamma_inc_local*delta_k, gamma_inc_bar_local*step_norm), delta_max_local)
               else if (ratio >= eta1_local) then
                  delta_next = max(max(gamma_dec_local*delta_k, step_norm), rho_k)
               else
                  delta_next = max(min(gamma_dec_local*delta_k, step_norm), rho_k)
               end if
               alpha_ratio = min(1.0_dp, step_norm/max(delta_k, tiny(1.0_dp)))
               call append_quasi_trace_sample(alpha_ratio, iter_idx, 0, attempt_idx, r_trial_norm, accepted, .true.)
               call update_linear_interp_set(Y, RY, x_trial, r_trial, delta_k)
               if (accepted) then
                  x = x_trial
                  r = r_trial
                  r_norm = r_trial_norm
                  Jl = Jl_trial
                  call promote_linear_interp_center(Y, RY, x, r)
                  if (r_norm < best_r_norm) then
                     best_r_norm = r_norm
                     x_best = x
                     Jl_best = Jl
                  end if
                  delta_k = delta_next
                  if (ratio >= eta2_local) then
                     lambda_reg = max(lambda_reg_min, 0.5_dp*lambda_reg)
                  else if (ratio < eta1_local) then
                     lambda_reg = min(lambda_reg_max, 2.0_dp*lambda_reg)
                  end if
               else
                  call linear_interp_set_is_poised(Y, delta_k, lambda_poised, poised_ok, worst_idx, worst_poise)
                  if (.not. poised_ok) then
                     call improve_linear_interp_geometry(f, xt, z, del_z, jac, x, delta_next, lambda_poised, &
                                                        max_geom_iter, Y, RY, geom_ok)
                  end if
                  if (abs(delta_next - rho_k) <= delta_eps) then
                     rho_k = max(delta_min_local, alpha1_local*rho_k)
                     delta_k = max(rho_k, alpha2_local*rho_k)
                  else
                     delta_k = delta_next
                  end if
                  lambda_reg = min(lambda_reg_max, max(2.0_dp*lambda_reg, lambda_reg_min))
               end if
            end if
         end if

         if (best_r_norm <= prev_best_r_norm*(1.0_dp - stagnation_rel)) then
            no_improve_count = 0
         else
            no_improve_count = no_improve_count + 1
         end if
         prev_best_r_norm = min(prev_best_r_norm, best_r_norm)
         if (iter_idx >= 8 .and. no_improve_count >= stagnation_limit) exit
      end do

      call rescue_attempt_from_best(xt, z, del_z, tol, Jl_best, best_r_norm, x_new, Jl, converged)
      if (.not. converged) then
         x_new = xt
         if (size(Jl_best) == size(Jl)) Jl = Jl_best
      end if
      if (present(x_best_out)) then
         if (size(x_best_out) == size(x_best)) x_best_out = x_best
      end if
      if (present(best_res_out)) best_res_out = best_r_norm

      deallocate (x, x_trial, r, r_trial, Jm, Hm, g, step, hs, Jl_trial, x_best, Jl_best, Y, RY)
   end subroutine run_dfo_gn_paper_attempt

   subroutine rebuild_linear_interp_set(f, xt, z, del_z, jac, x_center, r_center, trust_radius, Y, RY, ok)
      implicit none
      real(dp), intent(in) :: xt(:), del_z(:), x_center(:), r_center(:), trust_radius
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: Y(:, :), RY(:, :)
      logical, intent(out) :: ok

      interface
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac)
            use, intrinsic :: iso_fortran_env, only: real64
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
         end subroutine f
      end interface

      integer :: n, i, shrink_try
      real(dp) :: h_base, h_i, trust_scale
      logical :: eval_error, eval_ok
      real(dp), allocatable :: x_probe(:), r_probe(:), Jl_probe(:)

      ok = .false.
      n = size(x_center)
      if (size(r_center) /= n .or. size(Y, 1) /= n .or. size(RY, 1) /= n) return
      if (size(Y, 2) /= n + 1 .or. size(RY, 2) /= n + 1) return

      allocate (x_probe(n), r_probe(n), Jl_probe(n))
      Y(:, 1) = x_center
      RY(:, 1) = r_center

      trust_scale = max(trust_radius, 1.0e-6_dp)
      h_base = max(1.0e-5_dp, min(0.12_dp, 0.25_dp*trust_scale))

      do i = 1, n
         h_i = max(h_base, 1.0e-3_dp*max(1.0_dp, abs(x_center(i))))
         h_i = min(h_i, max(5.0e-5_dp, 0.45_dp*trust_scale))
         eval_ok = .false.
         do shrink_try = 1, 5
            x_probe = x_center
            x_probe(i) = x_probe(i) + h_i
            quasi_trace_iter = 0
            call f(xt, z, x_probe, r_probe, del_z, eval_error, Jl_probe, jac)
            if (.not. eval_error .and. real_vector_is_finite(r_probe)) then
               eval_ok = .true.
               exit
            end if

            x_probe = x_center
            x_probe(i) = x_probe(i) - h_i
            quasi_trace_iter = 0
            call f(xt, z, x_probe, r_probe, del_z, eval_error, Jl_probe, jac)
            if (.not. eval_error .and. real_vector_is_finite(r_probe)) then
               eval_ok = .true.
               exit
            end if

            h_i = 0.5_dp*h_i
            if (h_i < 5.0e-8_dp) exit
         end do

         if (.not. eval_ok) then
            deallocate (x_probe, r_probe, Jl_probe)
            return
         end if
         Y(:, i + 1) = x_probe
         RY(:, i + 1) = r_probe
      end do

      ok = .true.
      deallocate (x_probe, r_probe, Jl_probe)
   end subroutine rebuild_linear_interp_set

   subroutine build_linear_interp_jacobian(Y, RY, Jm, model_ok)
      implicit none
      real(dp), intent(in) :: Y(:, :), RY(:, :)
      real(dp), intent(out) :: Jm(:, :)
      logical, intent(out) :: model_ok

      integer :: n, i, t
      logical :: lin_error
      real(dp), allocatable :: W(:, :), rhs(:), sol(:)

      model_ok = .false.
      n = size(Jm, 1)
      if (size(Jm, 2) /= n) return
      if (size(Y, 1) /= n .or. size(RY, 1) /= n) return
      if (size(Y, 2) /= n + 1 .or. size(RY, 2) /= n + 1) return

      allocate (W(n, n), rhs(n), sol(n))
      do t = 1, n
         W(t, :) = Y(:, t + 1) - Y(:, 1)
      end do

      do i = 1, n
         do t = 1, n
            rhs(t) = RY(i, t + 1) - RY(i, 1)
         end do
         call solve_linear_direction(-rhs, W, sol, lin_error)
         if (lin_error .or. .not. real_vector_is_finite(sol)) then
            deallocate (W, rhs, sol)
            return
         end if
         Jm(i, :) = sol
      end do

      model_ok = real_matrix_is_finite(Jm)
      deallocate (W, rhs, sol)
   end subroutine build_linear_interp_jacobian

   subroutine update_linear_interp_set(Y, RY, x_trial, r_trial, trust_radius)
      implicit none
      real(dp), intent(inout) :: Y(:, :), RY(:, :)
      real(dp), intent(in) :: x_trial(:), r_trial(:), trust_radius

      integer :: n, replace_idx

      n = size(x_trial)
      if (size(r_trial) /= n .or. size(Y, 1) /= n .or. size(RY, 1) /= n) return
      if (size(Y, 2) /= n + 1 .or. size(RY, 2) /= n + 1) return

      call select_interp_replacement_index(Y, x_trial, trust_radius, replace_idx)
      if (replace_idx < 2 .or. replace_idx > n + 1) replace_idx = 2

      Y(:, replace_idx) = x_trial
      RY(:, replace_idx) = r_trial
   end subroutine update_linear_interp_set

   subroutine select_interp_replacement_index(Y, y_new, trust_radius, replace_idx)
      implicit none
      real(dp), intent(in) :: Y(:, :), y_new(:), trust_radius
      integer, intent(out) :: replace_idx

      integer :: n, i, j
      logical :: lin_error
      real(dp) :: delta_model, dist_j, dist_scale, score_j, best_score, sigma_floor
      real(dp), allocatable :: Wc(:, :), rhs(:), alpha(:), sigma_vals(:), center(:)

      replace_idx = 2
      n = size(y_new)
      if (size(Y, 1) /= n .or. size(Y, 2) /= n + 1) return

      call farthest_interp_index(Y, replace_idx)

      allocate (Wc(n, n), rhs(n), alpha(n), sigma_vals(n + 1), center(n))
      center = Y(:, 1)
      rhs = y_new - center
      do i = 1, n
         Wc(:, i) = Y(:, i + 1) - center
      end do

      call solve_linear_direction(-rhs, Wc, alpha, lin_error)
      if (lin_error .or. .not. real_vector_is_finite(alpha)) then
         deallocate (Wc, rhs, alpha, sigma_vals, center)
         return
      end if

      sigma_vals = 0.0_dp
      do i = 1, n
         ! For replacing column i of W with rhs, Sherman-Morrison denominator is sigma_i = alpha(i).
         sigma_vals(i + 1) = alpha(i)
      end do

      delta_model = max(trust_radius, 1.0e-8_dp)
      sigma_floor = 1.0e-10_dp
      best_score = -1.0_dp
      do j = 2, n + 1
         dist_j = norm2(Y(:, j) - center)
         dist_scale = max((dist_j/delta_model)**4, 1.0_dp)
         score_j = abs(sigma_vals(j))*dist_scale
         if (ieee_is_finite(score_j) .and. score_j > best_score) then
            best_score = score_j
            replace_idx = j
         end if
      end do

      if (best_score <= sigma_floor) call farthest_interp_index(Y, replace_idx)
      deallocate (Wc, rhs, alpha, sigma_vals, center)
   end subroutine select_interp_replacement_index

   subroutine farthest_interp_index(Y, idx)
      implicit none
      real(dp), intent(in) :: Y(:, :)
      integer, intent(out) :: idx

      integer :: n, j
      real(dp) :: dist_j, best_dist
      real(dp), allocatable :: center(:)

      n = size(Y, 1)
      idx = 2
      if (n <= 0 .or. size(Y, 2) /= n + 1) return

      allocate (center(n))
      center = Y(:, 1)
      best_dist = -1.0_dp
      do j = 2, n + 1
         dist_j = norm2(Y(:, j) - center)
         if (dist_j > best_dist) then
            best_dist = dist_j
            idx = j
         end if
      end do
      deallocate (center)
   end subroutine farthest_interp_index

   subroutine promote_linear_interp_center(Y, RY, x_center, r_center)
      implicit none
      real(dp), intent(inout) :: Y(:, :), RY(:, :)
      real(dp), intent(in) :: x_center(:), r_center(:)

      integer :: n, j, center_idx
      real(dp) :: dist_j, best_dist
      real(dp), allocatable :: tmp(:)

      n = size(x_center)
      if (size(r_center) /= n .or. size(Y, 1) /= n .or. size(RY, 1) /= n) return
      if (size(Y, 2) /= n + 1 .or. size(RY, 2) /= n + 1) return

      center_idx = 1
      best_dist = huge(1.0_dp)
      do j = 1, n + 1
         dist_j = norm2(Y(:, j) - x_center)
         if (dist_j < best_dist) then
            best_dist = dist_j
            center_idx = j
         end if
      end do

      if (center_idx /= 1) then
         allocate (tmp(n))
         tmp = Y(:, 1)
         Y(:, 1) = Y(:, center_idx)
         Y(:, center_idx) = tmp
         tmp = RY(:, 1)
         RY(:, 1) = RY(:, center_idx)
         RY(:, center_idx) = tmp
         deallocate (tmp)
      end if

      Y(:, 1) = x_center
      RY(:, 1) = r_center
   end subroutine promote_linear_interp_center

   logical function should_refresh_linear_interp_set(Y, trust_radius, iter_idx, refresh_stride) result(do_refresh)
      implicit none
      real(dp), intent(in) :: Y(:, :), trust_radius
      integer, intent(in) :: iter_idx, refresh_stride

      integer :: n, j
      real(dp) :: dmin, dmax, dj, trust_scale

      do_refresh = .false.
      n = size(Y, 1)
      if (size(Y, 2) /= n + 1 .or. n <= 0) return

      trust_scale = max(trust_radius, 1.0e-6_dp)
      dmin = huge(1.0_dp)
      dmax = 0.0_dp
      do j = 2, n + 1
         dj = norm2(Y(:, j) - Y(:, 1))
         dmin = min(dmin, dj)
         dmax = max(dmax, dj)
      end do

      if (refresh_stride > 0 .and. mod(iter_idx, refresh_stride) == 0) do_refresh = .true.
      if (dmax > 2.5_dp*trust_scale) do_refresh = .true.
      if (dmin < 5.0e-2_dp*trust_scale) do_refresh = .true.
   end function should_refresh_linear_interp_set

   subroutine paper_trust_region_step(Hm, g, delta, lambda_reg, step, step_norm, lin_error)
      implicit none
      real(dp), intent(in) :: Hm(:, :), g(:), delta
      real(dp), intent(inout) :: lambda_reg
      real(dp), intent(out) :: step(:), step_norm
      logical, intent(out) :: lin_error

      integer :: n, i, solve_try
      real(dp) :: lambda_trial
      logical :: local_error
      real(dp), allocatable :: Bm(:, :), step_try(:)

      n = size(g)
      step = 0.0_dp
      step_norm = 0.0_dp
      lin_error = .true.
      if (size(step) /= n .or. size(Hm, 1) /= n .or. size(Hm, 2) /= n) return

      allocate (Bm(n, n), step_try(n))
      lambda_trial = max(1.0e-10_dp, lambda_reg)
      do solve_try = 1, 8
         Bm = Hm
         do i = 1, n
            Bm(i, i) = Bm(i, i) + lambda_trial*max(1.0_dp, Hm(i, i))
         end do
         call solve_linear_direction(g, Bm, step_try, local_error)
         if (local_error .or. .not. real_vector_is_finite(step_try)) then
            lambda_trial = min(1.0e12_dp, 10.0_dp*lambda_trial)
            cycle
         end if
         step_norm = norm2(step_try)
         if (.not. ieee_is_finite(step_norm) .or. step_norm <= tiny(1.0_dp)) then
            lambda_trial = min(1.0e12_dp, 10.0_dp*lambda_trial)
            cycle
         end if
         if (step_norm > delta) then
            step_try = step_try*(delta/step_norm)
            step_norm = delta
         end if
         step = step_try
         lambda_reg = lambda_trial
         lin_error = .false.
         exit
      end do

      deallocate (Bm, step_try)
   end subroutine paper_trust_region_step

   subroutine compute_interp_inverse(Y, invD, ok)
      implicit none
      real(dp), intent(in) :: Y(:, :)
      real(dp), intent(out) :: invD(:, :)
      logical, intent(out) :: ok

      integer :: n, i
      logical :: lin_error
      real(dp), allocatable :: D(:, :), rhs(:), col(:), center(:)

      ok = .false.
      n = size(Y, 1)
      if (size(invD, 1) /= n .or. size(invD, 2) /= n) return
      if (size(Y, 2) /= n + 1) return

      allocate (D(n, n), rhs(n), col(n), center(n))
      center = Y(:, 1)
      do i = 1, n
         D(:, i) = Y(:, i + 1) - center
      end do

      do i = 1, n
         rhs = 0.0_dp
         rhs(i) = 1.0_dp
         call solve_linear_direction(-rhs, D, col, lin_error)
         if (lin_error .or. .not. real_vector_is_finite(col)) then
            deallocate (D, rhs, col, center)
            return
         end if
         invD(:, i) = col
      end do

      ok = real_matrix_is_finite(invD)
      deallocate (D, rhs, col, center)
   end subroutine compute_interp_inverse

   subroutine linear_interp_set_is_poised(Y, delta, lambda_target, poised_ok, worst_idx, worst_value)
      implicit none
      real(dp), intent(in) :: Y(:, :), delta, lambda_target
      logical, intent(out) :: poised_ok
      integer, intent(out) :: worst_idx
      real(dp), intent(out) :: worst_value

      integer :: n, i, j, far_idx
      real(dp) :: dist_j, dmax, lambda_j, lambda0, delta_safe
      logical :: inv_ok
      real(dp), allocatable :: invD(:, :), center(:), q0(:)

      poised_ok = .false.
      worst_idx = 2
      worst_value = huge(1.0_dp)
      n = size(Y, 1)
      if (n <= 0 .or. size(Y, 2) /= n + 1) return

      allocate (invD(n, n), center(n), q0(n))
      call compute_interp_inverse(Y, invD, inv_ok)
      if (.not. inv_ok) then
         deallocate (invD, center, q0)
         return
      end if

      center = Y(:, 1)
      delta_safe = max(delta, 1.0e-8_dp)
      dmax = 0.0_dp
      far_idx = 2
      do j = 2, n + 1
         dist_j = norm2(Y(:, j) - center)
         if (dist_j > dmax) then
            dmax = dist_j
            far_idx = j
         end if
      end do

      worst_value = -1.0_dp
      worst_idx = 2
      do j = 2, n + 1
         lambda_j = delta_safe*norm2(invD(j - 1, :))
         if (lambda_j > worst_value) then
            worst_value = lambda_j
            worst_idx = j
         end if
      end do

      q0 = 0.0_dp
      do i = 1, n
         q0 = q0 + invD(i, :)
      end do
      lambda0 = 1.0_dp + delta_safe*norm2(q0)
      if (lambda0 > worst_value) worst_value = lambda0

      if (dmax > (1.0_dp + 1.0e-6_dp)*delta_safe) then
         poised_ok = .false.
         worst_idx = far_idx
         worst_value = max(worst_value, dmax/delta_safe)
      else
         poised_ok = (worst_value <= lambda_target)
      end if

      deallocate (invD, center, q0)
   end subroutine linear_interp_set_is_poised

   subroutine propose_geometry_replacement(Y, delta, worst_idx, y_new, flip_sign)
      implicit none
      real(dp), intent(in) :: Y(:, :), delta
      integer, intent(in) :: worst_idx
      real(dp), intent(out) :: y_new(:)
      logical, intent(in), optional :: flip_sign

      integer :: n, row_idx
      logical :: inv_ok
      real(dp) :: dir_norm, sign_val
      real(dp), allocatable :: invD(:, :), center(:), dir(:)

      n = size(y_new)
      if (size(Y, 1) /= n .or. size(Y, 2) /= n + 1) return
      if (worst_idx < 2 .or. worst_idx > n + 1) then
         y_new = Y(:, 1)
         return
      end if

      allocate (invD(n, n), center(n), dir(n))
      center = Y(:, 1)
      call compute_interp_inverse(Y, invD, inv_ok)
      if (.not. inv_ok) then
         y_new = center
         deallocate (invD, center, dir)
         return
      end if

      row_idx = max(1, min(n, worst_idx - 1))
      dir = invD(row_idx, :)
      dir_norm = norm2(dir)
      if (dir_norm <= tiny(1.0_dp)) then
         dir = 0.0_dp
         dir(row_idx) = 1.0_dp
         dir_norm = 1.0_dp
      end if
      sign_val = 1.0_dp
      if (present(flip_sign)) then
         if (flip_sign) sign_val = -1.0_dp
      end if
      y_new = center + sign_val*max(delta, 1.0e-8_dp)*(dir/dir_norm)
      deallocate (invD, center, dir)
   end subroutine propose_geometry_replacement

   subroutine improve_linear_interp_geometry(f, xt, z, del_z, jac, x_center, delta, lambda_target, max_improve_iter, Y, RY, ok)
      implicit none
      real(dp), intent(in) :: xt(:), del_z(:), x_center(:), delta, lambda_target
      complex(dp), intent(in) :: z(:), jac(:, :)
      integer, intent(in) :: max_improve_iter
      real(dp), intent(inout) :: Y(:, :), RY(:, :)
      logical, intent(out) :: ok

      interface
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac)
            use, intrinsic :: iso_fortran_env, only: real64
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
         end subroutine f
      end interface

      integer :: n, improve_iter, worst_idx
      logical :: poised_ok, eval_error
      real(dp) :: worst_value
      real(dp), allocatable :: y_new(:), r_new(:), Jl_probe(:)

      ok = .false.
      n = size(x_center)
      if (size(Y, 1) /= n .or. size(RY, 1) /= n) return
      if (size(Y, 2) /= n + 1 .or. size(RY, 2) /= n + 1) return

      allocate (y_new(n), r_new(n), Jl_probe(n))
      do improve_iter = 1, max(1, max_improve_iter)
         call linear_interp_set_is_poised(Y, delta, lambda_target, poised_ok, worst_idx, worst_value)
         if (poised_ok) then
            ok = .true.
            deallocate (y_new, r_new, Jl_probe)
            return
         end if

         call propose_geometry_replacement(Y, delta, worst_idx, y_new)
         quasi_trace_iter = 0
         call f(xt, z, y_new, r_new, del_z, eval_error, Jl_probe, jac)
         if (eval_error .or. .not. real_vector_is_finite(r_new)) then
            call propose_geometry_replacement(Y, delta, worst_idx, y_new, flip_sign=.true.)
            quasi_trace_iter = 0
            call f(xt, z, y_new, r_new, del_z, eval_error, Jl_probe, jac)
         end if
         if (eval_error .or. .not. real_vector_is_finite(r_new)) then
            call farthest_interp_index(Y, worst_idx)
            call propose_geometry_replacement(Y, 0.5_dp*delta, worst_idx, y_new)
            quasi_trace_iter = 0
            call f(xt, z, y_new, r_new, del_z, eval_error, Jl_probe, jac)
         end if
         if (eval_error .or. .not. real_vector_is_finite(r_new)) exit

         if (worst_idx < 2 .or. worst_idx > n + 1) call farthest_interp_index(Y, worst_idx)
         Y(:, worst_idx) = y_new
         RY(:, worst_idx) = r_new
      end do

      call linear_interp_set_is_poised(Y, delta, lambda_target, poised_ok, worst_idx, worst_value)
      ok = poised_ok
      deallocate (y_new, r_new, Jl_probe)
   end subroutine improve_linear_interp_geometry

   subroutine build_dfo_gn_jacobian(f, xt, z, del_z, jac, x, r, trust_radius, iter_idx, Jm)
      implicit none
      real(dp), intent(in) :: xt(:), del_z(:), x(:), r(:), trust_radius
      complex(dp), intent(in) :: z(:), jac(:, :)
      integer, intent(in) :: iter_idx
      real(dp), intent(out) :: Jm(:, :)

      interface
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac)
            use, intrinsic :: iso_fortran_env, only: real64
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
         end subroutine f
      end interface

      integer :: n, i
      real(dp) :: h, h_floor, h_ceil, denom
      logical :: eval_error, eval_plus_ok, eval_minus_ok
      real(dp), allocatable :: x_probe(:), r_plus(:), r_minus(:), Jl_probe(:)

      n = size(x)
      Jm = 0.0_dp
      if (size(r) /= n .or. size(Jm, 1) /= n .or. size(Jm, 2) /= n) return

      allocate (x_probe(n), r_plus(n), r_minus(n), Jl_probe(n))

      do i = 1, n
         h_floor = max(1.0e-8_dp, sqrt(epsilon(1.0_dp))*max(1.0_dp, abs(x(i))))
         h_floor = max(h_floor, 0.02_dp*max(trust_radius, 1.0e-6_dp))
         h_ceil = max(1.0e-5_dp, 0.30_dp*max(trust_radius, 1.0e-6_dp))
         h = min(max(h_floor, 1.0e-7_dp), h_ceil)

         eval_plus_ok = .false.
         x_probe = x
         x_probe(i) = x_probe(i) + h
         quasi_trace_iter = iter_idx
         call f(xt, z, x_probe, r_plus, del_z, eval_error, Jl_probe, jac)
         if (.not. eval_error .and. real_vector_is_finite(r_plus)) eval_plus_ok = .true.

         eval_minus_ok = .false.
         x_probe = x
         x_probe(i) = x_probe(i) - h
         quasi_trace_iter = iter_idx
         call f(xt, z, x_probe, r_minus, del_z, eval_error, Jl_probe, jac)
         if (.not. eval_error .and. real_vector_is_finite(r_minus)) eval_minus_ok = .true.

         if (eval_plus_ok .and. eval_minus_ok) then
            denom = 2.0_dp*h
            Jm(:, i) = (r_plus - r_minus)/denom
         else if (eval_plus_ok) then
            denom = h
            Jm(:, i) = (r_plus - r)/denom
         else if (eval_minus_ok) then
            denom = h
            Jm(:, i) = (r - r_minus)/denom
         else
            Jm(:, i) = 0.0_dp
            cycle
         end if

         if (.not. real_vector_is_finite(Jm(:, i))) Jm(:, i) = 0.0_dp
      end do

      deallocate (x_probe, r_plus, r_minus, Jl_probe)
   end subroutine build_dfo_gn_jacobian

   subroutine run_quasi_newton_attempt(f, tol, max_iter, attempt_idx, xt, z, del_z, jac, x_init, converged, Jl, x_new, &
                                       x_best_out, best_res_out, initial_trust_cap, paper_exact, near_escape_mode)
      implicit none
      integer, intent(in) :: max_iter
      integer, intent(in) :: attempt_idx
      real(dp), intent(in) :: tol
      real(dp), intent(in) :: xt(:), del_z(:), x_init(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: Jl(:), x_new(:)
      logical, intent(out) :: converged
      real(dp), intent(out), optional :: x_best_out(:)
      real(dp), intent(out), optional :: best_res_out
      real(dp), intent(in), optional :: initial_trust_cap
      logical, intent(in), optional :: paper_exact
      logical, intent(in), optional :: near_escape_mode

      interface
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac)
            use, intrinsic :: iso_fortran_env, only: real64
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
         end subroutine f
      end interface

      integer, parameter :: max_backtrack_primary = 60
      integer, parameter :: max_backtrack_retry = 24
      real(dp), parameter :: gamma = 0.95_dp
      real(dp), parameter :: rho = 1.0e-4_dp
      real(dp), parameter :: sigma = 1.0e-4_dp
      real(dp), parameter :: delta = 0.5_dp
      real(dp), parameter :: tau = 0.3_dp
      real(dp), parameter :: min_alpha = 1.0e-12_dp
      real(dp), parameter :: growth_clip_alpha_min = 0.15_dp
      real(dp), parameter :: growth_clip_alpha_max = 0.85_dp
      real(dp), parameter :: trust_shrink = 0.5_dp
      real(dp), parameter :: trust_expand = 1.35_dp
      real(dp), parameter :: trust_good_reduction = 0.25_dp
      real(dp), parameter :: trust_radius_min = 1.0e-6_dp
      real(dp), parameter :: trust_radius_max = 5.0_dp
      real(dp), parameter :: ndfls_paper_gamma = 0.9_dp
      real(dp), parameter :: ndfls_paper_rho = 1.0e-3_dp
      real(dp), parameter :: ndfls_paper_sigma = 1.0e-3_dp
      real(dp), parameter :: ndfls_paper_delta = 1.0e-2_dp
      real(dp), parameter :: ndfls_paper_tau = 0.3_dp

      integer :: n, nz, iter_idx, backtrack_idx
      integer :: max_backtrack_local, stagnation_patience, no_improve_count
      integer :: iter_growth_guard_rejects
      real(dp) :: etak, alpha, phi_k, phi_next, t_next
      real(dp) :: trust_radius, reduction_ratio
      real(dp) :: y_norm, fx_norm, d_norm, step_norm, step_tol, best_fx_norm
      real(dp) :: prev_best_fx_norm
      real(dp) :: z_corr_scale, z_corr_trial, del_z_scale
      real(dp) :: backtrack_shrink
      real(dp) :: delta_local, tau_local
      real(dp) :: gamma_local, rho_local, sigma_local
      real(dp) :: gamma_eff, rho_eff, sigma_eff, near_phase_threshold
      real(dp) :: stagnation_floor
      logical :: eval_error, is_accepted, had_eval_error
      logical :: rejected_by_growth_guard
      logical :: use_custom_shrink, use_paper_exact, near_escape_local
      real(dp), allocatable :: x(:), dx(:), d(:), y(:), fx_val(:), x_trial(:), Bm(:, :)
      real(dp), allocatable :: x_best(:), fx_best(:), Jl_best(:)
      complex(dp), allocatable :: z_base(:), z_del(:)
      complex(dp) :: z_new(size(z))

      nz = size(z)
      n = 2*nz
      if (size(x_init) /= n .or. size(Jl) /= n) then
         converged = .false.
         call set_attempt_outputs(x_init, huge(1.0_dp), x_best_out, best_res_out)
         return
      end if

      allocate (x(n), dx(n), d(n), y(n), fx_val(n), x_trial(n), Bm(n, n), x_best(n), fx_best(n), Jl_best(n), z_base(nz), z_del(nz))
      call real_to_complex(del_z, z_del)
      z_base = z + z_del
      del_z_scale = max(norm2(del_z), 1.0_dp)
      x = x_init
      use_paper_exact = .false.
      if (present(paper_exact)) use_paper_exact = paper_exact
      near_escape_local = .false.
      if (present(near_escape_mode)) near_escape_local = near_escape_mode
      if (use_paper_exact) then
         delta_local = ndfls_paper_delta
         tau_local = ndfls_paper_tau
         max_backtrack_local = max_backtrack_primary
         stagnation_patience = max_iter + 1
         gamma_local = ndfls_paper_gamma
         rho_local = ndfls_paper_rho
         sigma_local = ndfls_paper_sigma
         trust_radius = max(1.0_dp, 8.0_dp*max(1.0_dp, norm2(x_init)))
      else
         delta_local = delta
         tau_local = tau
         trust_radius = max(trust_radius_min, min(trust_radius_max, max(0.25_dp, norm2(x_init))))
         if (present(initial_trust_cap)) then
            trust_radius = min(trust_radius, max(trust_radius_min, initial_trust_cap))
         end if
         if (attempt_idx <= 1) then
            max_backtrack_local = max_backtrack_primary
            stagnation_patience = max_iter + 1
            gamma_local = gamma
            rho_local = rho
            sigma_local = sigma
         else
            max_backtrack_local = max_backtrack_retry
            stagnation_patience = max(8, min(16, max_iter/2))
            gamma_local = 0.99_dp
            rho_local = 1.0e-6_dp
            sigma_local = 5.0e-6_dp
         end if
      end if
      stagnation_floor = max(1.0e4_dp*tol, 1.0e-7_dp)

      quasi_trace_iter = 0
         call f(xt, z, x, fx_val, del_z, eval_error, Jl, jac)
         if (eval_error) then
            call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, huge(1.0_dp), .false., .false.)
            converged = .false.
            call set_attempt_outputs(x, huge(1.0_dp), x_best_out, best_res_out)
            deallocate (x, dx, d, y, fx_val, x_trial, Bm, x_best, fx_best, Jl_best, z_base, z_del)
            return
         end if

         fx_norm = norm2(fx_val)
         if (.not. ieee_is_finite(fx_norm)) then
            call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, fx_norm, .false., .false.)
            converged = .false.
            call set_attempt_outputs(x, fx_norm, x_best_out, best_res_out)
            deallocate (x, dx, d, y, fx_val, x_trial, Bm, x_best, fx_best, Jl_best, z_base, z_del)
            return
         end if

      call append_quasi_trace_sample(0.0_dp, 0, 0, attempt_idx, fx_norm, .false., .true.)
      phi_k = fx_norm
      x_best = x
      fx_best = fx_val
      Jl_best = Jl
      best_fx_norm = fx_norm
      prev_best_fx_norm = best_fx_norm
      no_improve_count = 0
      z_corr_scale = proposal_correction_norm(quasi_eval_z_proposed, z_base, nz)
      if (.not. ieee_is_finite(z_corr_scale)) z_corr_scale = del_z_scale
      call set_identity_matrix(Bm)

      iter_idx = 0
      do while (iter_idx < max_iter)
         iter_idx = iter_idx + 1
         if (quasi_watchdog_scope_active .and. quasi_watchdog_hit) exit
         if ((use_paper_exact .and. residual_within_tolerance(fx_norm, tol)) .or. &
             ((.not. use_paper_exact) .and. residual_within_accept_tolerance(fx_norm, tol))) then
            call recover_converged_flowed_state(xt, z, del_z, Jl, z_new, eval_error)
            if (eval_error) then
               converged = .false.
            else
               x_new = xt
               x_new(2:) = real(z_new, dp)
               converged = .true.
            end if
            call set_attempt_outputs(x_best, best_fx_norm, x_best_out, best_res_out)
            deallocate (x, dx, d, y, fx_val, x_trial, Bm, x_best, fx_best, Jl_best, z_base, z_del)
            return
         end if

         y = fx_val
         y_norm = fx_norm
         near_phase_threshold = max(2.0e2_dp*tol, 5.0e-9_dp)
         if (y_norm <= near_phase_threshold) then
            gamma_eff = 0.9999_dp
            rho_eff = 0.0_dp
            sigma_eff = 0.0_dp
         else
            gamma_eff = gamma_local
            rho_eff = rho_local
            sigma_eff = sigma_local
         end if
         etak = 1.0_dp/real(iter_idx + 1, dp)**2
         had_eval_error = .false.
         alpha = 1.0_dp
         d_norm = 0.0_dp
         step_norm = 0.0_dp
         iter_growth_guard_rejects = 0
         use_custom_shrink = .false.
         backtrack_shrink = delta_local

         call solve_linear_direction(fx_val, Bm, d, eval_error)
         is_accepted = .false.
         if (.not. eval_error) then
            d_norm = norm2(d)
            if (.not. ieee_is_finite(d_norm) .or. d_norm <= tiny(1.0_dp)) then
               eval_error = .true.
            else
               if (d_norm > trust_radius) then
                  d = d*(trust_radius/d_norm)
                  d_norm = trust_radius
               end if
               alpha = 1.0_dp
               step_norm = alpha*d_norm
               x_trial = x + alpha*d
               quasi_trace_iter = iter_idx
               call f(xt, z, x_trial, fx_val, del_z, eval_error, Jl, jac)
            end if
         end if

         if (eval_error) then
            had_eval_error = .true.
            call append_quasi_trace_sample(0.0_dp, iter_idx, 0, attempt_idx, huge(1.0_dp), .false., .false.)
            eval_error = .false.
         else
            fx_norm = norm2(fx_val)
            if (ieee_is_finite(fx_norm)) then
               call update_best_quasi_state(fx_norm, x_trial, fx_val, Jl, x_best, fx_best, Jl_best, best_fx_norm)
            end if
            if ((use_paper_exact .and. residual_within_tolerance(fx_norm, tol)) .or. &
                ((.not. use_paper_exact) .and. residual_within_accept_tolerance(fx_norm, tol))) then
               is_accepted = .true.
            else
               if (.not. use_paper_exact) then
                  z_corr_trial = proposal_correction_norm(quasi_eval_z_proposed, z_base, nz)
                  rejected_by_growth_guard = reject_growth_step(z_corr_trial, z_corr_scale, del_z_scale, fx_norm, y_norm, best_fx_norm, tol, &
                                                                attempt_idx, near_escape_mode=near_escape_local)
               else
                  rejected_by_growth_guard = .false.
               end if
               if (rejected_by_growth_guard) then
                  iter_growth_guard_rejects = iter_growth_guard_rejects + 1
                  backtrack_shrink = growth_clip_factor(z_corr_trial, z_corr_scale, del_z_scale, y_norm, tol, attempt_idx, &
                                                        growth_clip_alpha_min, growth_clip_alpha_max, delta_local, &
                                                        near_escape_mode=near_escape_local)
                  use_custom_shrink = (backtrack_shrink < delta_local*(1.0_dp - 1.0e-12_dp))
               else
                  is_accepted = accept_full_step(fx_norm, y_norm, d_norm, gamma_eff, rho_eff)
                  if (.not. is_accepted) is_accepted = accept_backtracking(fx_norm, phi_k, etak, sigma_eff, step_norm)
               end if
            end if
            call append_quasi_trace_sample(alpha, iter_idx, 0, attempt_idx, fx_norm, is_accepted, .true.)
         end if

         backtrack_idx = 0
         do while (.not. is_accepted .and. .not. had_eval_error)
            backtrack_idx = backtrack_idx + 1
            if (use_custom_shrink) then
               alpha = alpha*backtrack_shrink
               use_custom_shrink = .false.
            else
               alpha = alpha*delta_local
            end if
            if (backtrack_idx > max_backtrack_local .or. alpha < min_alpha) exit

            step_norm = alpha*d_norm
            x_trial = x + alpha*d
            quasi_trace_iter = iter_idx
            call f(xt, z, x_trial, fx_val, del_z, eval_error, Jl, jac)
            if (eval_error) then
               had_eval_error = .true.
               call append_quasi_trace_sample(alpha, iter_idx, backtrack_idx, attempt_idx, huge(1.0_dp), .false., .false.)
            else
               fx_norm = norm2(fx_val)
               if (ieee_is_finite(fx_norm)) then
                  call update_best_quasi_state(fx_norm, x_trial, fx_val, Jl, x_best, fx_best, Jl_best, best_fx_norm)
               end if
               if ((use_paper_exact .and. residual_within_tolerance(fx_norm, tol)) .or. &
                   ((.not. use_paper_exact) .and. residual_within_accept_tolerance(fx_norm, tol))) then
                  is_accepted = .true.
               else
                  if (.not. use_paper_exact) then
                     z_corr_trial = proposal_correction_norm(quasi_eval_z_proposed, z_base, nz)
                     rejected_by_growth_guard = reject_growth_step(z_corr_trial, z_corr_scale, del_z_scale, fx_norm, y_norm, best_fx_norm, tol, &
                                                                   attempt_idx, near_escape_mode=near_escape_local)
                  else
                     rejected_by_growth_guard = .false.
                  end if
                  if (rejected_by_growth_guard) then
                     iter_growth_guard_rejects = iter_growth_guard_rejects + 1
                     is_accepted = .false.
                     backtrack_shrink = growth_clip_factor(z_corr_trial, z_corr_scale, del_z_scale, y_norm, tol, attempt_idx, &
                                                           growth_clip_alpha_min, growth_clip_alpha_max, delta_local, &
                                                           near_escape_mode=near_escape_local)
                     use_custom_shrink = (backtrack_shrink < delta_local*(1.0_dp - 1.0e-12_dp))
                  else
                     is_accepted = accept_backtracking(fx_norm, phi_k, etak, sigma_eff, step_norm)
                  end if
               end if
               call append_quasi_trace_sample(alpha, iter_idx, backtrack_idx, attempt_idx, fx_norm, is_accepted, .true.)
            end if
         end do

         if (.not. is_accepted) then
            if (.not. use_paper_exact) then
               if (iter_growth_guard_rejects >= 3) then
                  trust_radius = max(trust_radius_min, 0.5_dp*trust_radius)
               end if
               call rescue_attempt_from_best(xt, z, del_z, tol, Jl_best, best_fx_norm, x_new, Jl, converged)
               if (converged) then
                  call set_attempt_outputs(x_best, best_fx_norm, x_best_out, best_res_out)
                  deallocate (x, dx, d, y, fx_val, x_trial, Bm, x_best, fx_best, Jl_best, z_base, z_del)
                  return
               end if
            end if
            converged = .false.
            call set_attempt_outputs(x_best, best_fx_norm, x_best_out, best_res_out)
            deallocate (x, dx, d, y, fx_val, x_trial, Bm, x_best, fx_best, Jl_best, z_base, z_del)
            return
         end if

         dx = alpha*d
         x = x + dx
         y = fx_val - y
         if (ieee_is_finite(fx_norm)) then
            call update_best_quasi_state(fx_norm, x, fx_val, Jl, x_best, fx_best, Jl_best, best_fx_norm)
         end if
         if (.not. use_paper_exact) then
            reduction_ratio = fx_norm/max(y_norm, tiny(1.0_dp))
            if (had_eval_error .or. backtrack_idx >= 12) then
               trust_radius = max(trust_radius_min, trust_radius*trust_shrink)
            else if (reduction_ratio < trust_good_reduction .and. step_norm > 0.8_dp*trust_radius) then
               trust_radius = min(trust_radius_max, trust_radius*trust_expand)
            else if (backtrack_idx > 4) then
               trust_radius = max(trust_radius_min, 0.8_dp*trust_radius)
            end if
            if (iter_growth_guard_rejects >= 2) then
               trust_radius = max(trust_radius_min, 0.7_dp*trust_radius)
               if (iter_growth_guard_rejects >= 4) call set_identity_matrix(Bm)
            end if
         end if
         z_corr_scale = proposal_correction_norm(quasi_eval_z_proposed, z_base, nz)
         if (.not. ieee_is_finite(z_corr_scale)) z_corr_scale = del_z_scale

         if ((use_paper_exact .and. residual_within_tolerance(fx_norm, tol)) .or. &
             ((.not. use_paper_exact) .and. residual_within_accept_tolerance(fx_norm, tol))) then
            call recover_converged_flowed_state(xt, z, del_z, Jl, z_new, eval_error)
            if (eval_error) then
               converged = .false.
            else
               x_new = xt
               x_new(2:) = real(z_new, dp)
               converged = .true.
            end if
            call set_attempt_outputs(x_best, best_fx_norm, x_best_out, best_res_out)
            deallocate (x, dx, d, y, fx_val, x_trial, Bm, x_best, fx_best, Jl_best, z_base, z_del)
            return
         end if

         if ((.not. use_paper_exact) .and. attempt_idx > 1 .and. best_fx_norm > stagnation_floor) then
            if (best_fx_norm <= prev_best_fx_norm*(1.0_dp - 2.0e-3_dp)) then
               no_improve_count = 0
            else
               no_improve_count = no_improve_count + 1
            end if
            prev_best_fx_norm = min(prev_best_fx_norm, best_fx_norm)
            if (iter_idx >= 8 .and. no_improve_count >= stagnation_patience) then
               exit
            end if
         end if

         step_tol = sqrt(epsilon(1.0_dp))*max(1.0_dp, norm2(x))
         if (step_norm > step_tol) call broyden_rank1_update(Bm, dx, y)

         call update_merit_from_ndls(phi_k, etak, fx_norm, tau_local, t_next, phi_next)
         phi_k = phi_next
         if (.not. ieee_is_finite(phi_k) .or. .not. ieee_is_finite(t_next)) then
            if (.not. use_paper_exact) then
               call rescue_attempt_from_best(xt, z, del_z, tol, Jl_best, best_fx_norm, x_new, Jl, converged)
               if (converged) then
                  call set_attempt_outputs(x_best, best_fx_norm, x_best_out, best_res_out)
                  deallocate (x, dx, d, y, fx_val, x_trial, Bm, x_best, fx_best, Jl_best, z_base, z_del)
                  return
               end if
            end if
            converged = .false.
            call set_attempt_outputs(x_best, best_fx_norm, x_best_out, best_res_out)
            deallocate (x, dx, d, y, fx_val, x_trial, Bm, x_best, fx_best, Jl_best, z_base, z_del)
            return
         end if
      end do

      if (.not. use_paper_exact) then
         call rescue_attempt_from_best(xt, z, del_z, tol, Jl_best, best_fx_norm, x_new, Jl, converged)
         if (converged) then
            call set_attempt_outputs(x_best, best_fx_norm, x_best_out, best_res_out)
            deallocate (x, dx, d, y, fx_val, x_trial, Bm, x_best, fx_best, Jl_best, z_base, z_del)
            return
         end if
      end if
      converged = .false.
      call set_attempt_outputs(x_best, best_fx_norm, x_best_out, best_res_out)
      deallocate (x, dx, d, y, fx_val, x_trial, Bm, x_best, fx_best, Jl_best, z_base, z_del)
   end subroutine run_quasi_newton_attempt

   subroutine recover_converged_flowed_state(xt, z, del_z, Jl, z_flowed, eval_error)
      implicit none
      real(dp), intent(in) :: xt(:), del_z(:), Jl(:)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(out) :: z_flowed(:)
      logical, intent(out) :: eval_error
      complex(dp) :: z_trial(size(z))

      if (size(z_flowed) /= size(z) .or. size(del_z) /= size(Jl)) then
         eval_error = .true.
         return
      end if

      if (quasi_eval_has_flowed .and. quasi_eval_flowed_is_inverse) then
         if (allocated(quasi_eval_z_flowed)) then
            if (size(quasi_eval_z_flowed) >= size(z)) then
               z_flowed = quasi_eval_z_flowed(1:size(z))
               eval_error = .false.
               return
            end if
         end if
      end if

      call real_to_complex(del_z + Jl, z_trial)
      z_trial = z + z_trial
      call update_quasi_watchdog_scope()
      if (quasi_watchdog_scope_active .and. quasi_watchdog_hit) then
         eval_error = .true.
         return
      end if
      call flowzr(xt, z_trial, eval_error)
      call update_quasi_watchdog_scope()
      if (quasi_watchdog_scope_active .and. quasi_watchdog_hit) then
         eval_error = .true.
         return
      end if
      if (.not. eval_error) z_flowed = z_trial
   end subroutine recover_converged_flowed_state

   integer function constrained_retry_iter_budget(max_iter) result(n_retry)
      implicit none
      integer, intent(in) :: max_iter

      n_retry = max(16, max_iter/4)
      n_retry = min(n_retry, 30)
   end function constrained_retry_iter_budget

   integer function constrained_retry2_iter_budget(max_iter) result(n_retry)
      implicit none
      integer, intent(in) :: max_iter

      n_retry = max(12, max_iter/5)
      n_retry = min(n_retry, 20)
   end function constrained_retry2_iter_budget

   integer function constrained_continuation_iter_budget(max_iter, stage_idx, lambda_target, use_fine_controls) result(n_retry)
      implicit none
      integer, intent(in) :: max_iter, stage_idx
      real(dp), intent(in) :: lambda_target
      logical, intent(in) :: use_fine_controls

      n_retry = max(12, max_iter/7 + 2*max(1, stage_idx))
      if (stage_idx >= 4) n_retry = n_retry + 8
      if (use_fine_controls) then
         if (lambda_target >= 0.90_dp) n_retry = n_retry + 16
         if (lambda_target >= 0.97_dp) n_retry = n_retry + 20
         n_retry = min(n_retry, 80)
      else
         n_retry = min(n_retry, 40)
      end if
   end function constrained_continuation_iter_budget

   subroutine run_delz_continuation(f, tol, max_iter, attempt_start, xt, z, del_z, jac, x_seed, converged, Jl, x_new, &
                                    strict_controls, near_escape_mode)
      implicit none
      integer, intent(in) :: max_iter, attempt_start
      real(dp), intent(in) :: tol
      real(dp), intent(in) :: xt(:), del_z(:), x_seed(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      logical, intent(out) :: converged
      real(dp), intent(out) :: Jl(:), x_new(:)
      logical, intent(in), optional :: strict_controls
      logical, intent(in), optional :: near_escape_mode

      interface
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac)
            use, intrinsic :: iso_fortran_env, only: real64
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
         end subroutine f
      end interface

      integer :: attempt_idx, stage_iter, stage_idx
      integer :: max_stage_attempts
      integer :: success_stage_count
      integer :: stage_fail_streak
      integer :: ms_try, ms_iter
      integer :: rs_try, rs_iter
      logical :: stage_ok, accepted_stage, final_stage_ok, has_high_quality_stage, enable_fine_bisection
      logical :: strict_mode, near_escape_local
      logical :: ms_ok, rs_ok
      real(dp) :: stage_best_res, stage_tol, lambda_min_step_active
      real(dp) :: lambda_init_local, lambda_max_step_local, stage_accept_floor_local
      real(dp) :: best_accepted_res, endpoint_jump_ratio, near_terminal_window
      real(dp) :: lambda_now, lambda_next, delta_lambda
      real(dp) :: restart_sign, restart_scale, ms_sign, ms_scale, ms_best_res
      real(dp) :: rs_sign, rs_scale, rs_best_res
      real(dp), allocatable :: x_stage(:), x_stage_best(:), x_stage_retry(:), x_stage_try_best(:), &
                               del_stage(:), Jl_stage(:), Jl_stage_try(:), x_new_stage(:), x_new_stage_try(:)
      real(dp), parameter :: lambda_init = 0.30_dp
      real(dp), parameter :: lambda_min_step_base = 0.025_dp
      real(dp), parameter :: lambda_min_step_fine = 5.0e-4_dp
      real(dp), parameter :: lambda_max_step = 0.45_dp
      real(dp), parameter :: lambda_fine_start = 0.85_dp
      real(dp), parameter :: stage_multistart_min_lambda = 0.55_dp
      integer, parameter :: stage_multistart_trials = 3
      integer, parameter :: stage_multistart_max_iter = 28
      real(dp), parameter :: stage_reset_min_lambda = 0.85_dp
      integer, parameter :: stage_reset_trials = 2
      integer, parameter :: stage_reset_max_iter = 30
      real(dp), parameter :: stage_reset_trust_cap = 0.35_dp
      real(dp), parameter :: class2_plateau_trigger = 1.0e-4_dp
      real(dp), parameter :: class2_jump_trigger = 1.0e3_dp
      real(dp), parameter :: quality_stage_res = 1.0e-8_dp
      real(dp), parameter :: stage_accept_floor = 5.0e-5_dp

      if (size(x_seed) <= 0) then
         converged = .false.
         return
      end if
      if (size(Jl) /= size(del_z)) then
         converged = .false.
         return
      end if
      strict_mode = .false.
      if (present(strict_controls)) strict_mode = strict_controls
      near_escape_local = .false.
      if (present(near_escape_mode)) near_escape_local = near_escape_mode
      if (strict_mode) then
         lambda_init_local = 0.20_dp
         lambda_max_step_local = 0.30_dp
         stage_accept_floor_local = 1.0e-6_dp
      else
         lambda_init_local = lambda_init
         lambda_max_step_local = lambda_max_step
         stage_accept_floor_local = stage_accept_floor
      end if

      allocate (x_stage(size(x_seed)), x_stage_best(size(x_seed)), x_stage_retry(size(x_seed)), x_stage_try_best(size(x_seed)), &
                del_stage(size(del_z)), Jl_stage(size(Jl)), Jl_stage_try(size(Jl)), x_new_stage(size(x_new)), x_new_stage_try(size(x_new)))
      x_stage = x_seed
      attempt_idx = attempt_start
      converged = .false.
      final_stage_ok = .false.
      has_high_quality_stage = .false.
      enable_fine_bisection = .false.
      success_stage_count = 0
      lambda_now = 0.0_dp
      delta_lambda = lambda_init_local
      best_accepted_res = huge(1.0_dp)
      lambda_min_step_active = lambda_min_step_base
      max_stage_attempts = 24
      stage_idx = 0
      stage_fail_streak = 0

      do while (lambda_now < 1.0_dp - 1.0e-12_dp .and. stage_idx < max_stage_attempts)
         lambda_next = min(1.0_dp, lambda_now + delta_lambda)
         stage_idx = stage_idx + 1
         if (enable_fine_bisection .and. has_high_quality_stage .and. lambda_now >= lambda_fine_start) then
            lambda_min_step_active = lambda_min_step_fine
         else
            lambda_min_step_active = lambda_min_step_base
         end if
         stage_iter = constrained_continuation_iter_budget(max_iter, stage_idx, lambda_next, enable_fine_bisection)
         stage_tol = continuation_stage_tol(tol, lambda_next, enable_fine_bisection)
         del_stage = lambda_next*del_z
         attempt_idx = attempt_idx + 1
         stage_best_res = huge(1.0_dp)
         call run_quasi_newton_attempt(f, stage_tol, stage_iter, attempt_idx, xt, z, del_stage, jac, x_stage, stage_ok, &
                                       Jl_stage, x_new_stage, &
                                       x_best_out=x_stage_best, best_res_out=stage_best_res, &
                                       near_escape_mode=near_escape_local)

         accepted_stage = continuation_stage_accepts(stage_ok, lambda_next, stage_best_res, stage_tol, &
                                                     enable_fine_bisection, stage_accept_floor_local, strict_mode)
         if ((.not. accepted_stage) .and. stage_idx >= 2 .and. lambda_next >= stage_multistart_min_lambda .and. &
             ieee_is_finite(stage_best_res) .and. stage_best_res >= class2_plateau_trigger) then
            ms_iter = max(10, min(stage_iter, stage_multistart_max_iter))
            do ms_try = 1, stage_multistart_trials
               ms_sign = merge(1.0_dp, -1.0_dp, mod(ms_try, 2) == 1)
               select case (ms_try)
               case (1)
                  ms_scale = 1.05_dp
               case (2)
                  ms_scale = 1.15_dp
               case default
                  ms_scale = 1.30_dp
               end select

               call build_diversified_restart_guess(x_stage, x_stage_best, x_stage_retry, kick_sign=ms_sign, kick_scale=ms_scale)
               attempt_idx = attempt_idx + 1
               ms_best_res = huge(1.0_dp)
               call run_quasi_newton_attempt(f, stage_tol, ms_iter, attempt_idx, xt, z, del_stage, jac, x_stage_retry, ms_ok, &
                                             Jl_stage_try, x_new_stage_try, x_best_out=x_stage_try_best, best_res_out=ms_best_res, &
                                             near_escape_mode=near_escape_local)
               if (ieee_is_finite(ms_best_res) .and. ms_best_res > 0.0_dp) then
                  if (ms_best_res < stage_best_res) then
                     stage_best_res = ms_best_res
                     stage_ok = ms_ok
                     x_stage_best = x_stage_try_best
                     Jl_stage = Jl_stage_try
                     x_new_stage = x_new_stage_try
                  end if
               end if
            end do
            accepted_stage = continuation_stage_accepts(stage_ok, lambda_next, stage_best_res, stage_tol, &
                                                        enable_fine_bisection, stage_accept_floor_local, strict_mode)
         end if
         if ((.not. accepted_stage) .and. lambda_next >= stage_reset_min_lambda .and. &
             ieee_is_finite(stage_best_res) .and. stage_best_res >= class2_plateau_trigger) then
            rs_iter = max(14, min(stage_iter, stage_reset_max_iter))
            do rs_try = 1, stage_reset_trials
               rs_sign = merge(1.0_dp, -1.0_dp, mod(rs_try, 2) == 1)
               rs_scale = 0.90_dp + 0.10_dp*real(rs_try, dp)
               call build_diversified_restart_guess(x_stage, x_stage_best, x_stage_retry, &
                                                    kick_sign=rs_sign, kick_scale=rs_scale)
               attempt_idx = attempt_idx + 1
               rs_best_res = huge(1.0_dp)
               call run_quasi_newton_attempt(f, stage_tol, rs_iter, attempt_idx, xt, z, del_stage, jac, x_stage_retry, rs_ok, &
                                             Jl_stage_try, x_new_stage_try, x_best_out=x_stage_try_best, best_res_out=rs_best_res, &
                                             initial_trust_cap=stage_reset_trust_cap, near_escape_mode=near_escape_local)
               if (ieee_is_finite(rs_best_res) .and. rs_best_res > 0.0_dp) then
                  if (rs_best_res < stage_best_res) then
                     stage_best_res = rs_best_res
                     stage_ok = rs_ok
                     x_stage_best = x_stage_try_best
                     Jl_stage = Jl_stage_try
                     x_new_stage = x_new_stage_try
                  end if
               end if
            end do
            accepted_stage = continuation_stage_accepts(stage_ok, lambda_next, stage_best_res, stage_tol, &
                                                        enable_fine_bisection, stage_accept_floor_local, strict_mode)
         end if

         if (accepted_stage) then
            x_stage = x_stage_best
            lambda_now = lambda_next
            success_stage_count = success_stage_count + 1
            stage_fail_streak = 0
            if (ieee_is_finite(stage_best_res) .and. stage_best_res > 0.0_dp) then
               best_accepted_res = min(best_accepted_res, stage_best_res)
            end if
            if (stage_best_res <= max(5.0e4_dp*tol, quality_stage_res)) has_high_quality_stage = .true.
            if (lambda_next >= 1.0_dp - 1.0e-12_dp) then
               final_stage_ok = stage_ok
            else
               if (enable_fine_bisection .and. has_high_quality_stage .and. lambda_now >= lambda_fine_start) then
                  delta_lambda = min(0.25_dp, 1.20_dp*delta_lambda)
               else
                  delta_lambda = min(lambda_max_step_local, 1.35_dp*delta_lambda)
               end if
            end if
         else
            if ((.not. enable_fine_bisection) .and. has_high_quality_stage .and. &
                ieee_is_finite(stage_best_res) .and. stage_best_res >= class2_plateau_trigger) then
               near_terminal_window = max(0.10_dp, 3.0_dp*delta_lambda)
               if ((1.0_dp - lambda_next) <= near_terminal_window) then
                  endpoint_jump_ratio = stage_best_res/max(best_accepted_res, tiny(1.0_dp))
                  if (endpoint_jump_ratio >= class2_jump_trigger) then
                     enable_fine_bisection = .true.
                     max_stage_attempts = 96
                  end if
               end if
            end if
            stage_fail_streak = stage_fail_streak + 1
            if (ieee_is_finite(stage_best_res) .and. stage_best_res > 0.0_dp) then
               if (stage_best_res < 0.75_dp*best_accepted_res) then
                  x_stage = x_stage_best
               end if
            end if
            if (stage_fail_streak >= 2 .and. ieee_is_finite(stage_best_res) .and. stage_best_res >= stage_accept_floor) then
               restart_sign = merge(1.0_dp, -1.0_dp, mod(stage_fail_streak, 2) == 0)
               restart_scale = min(1.35_dp, 1.0_dp + 0.08_dp*real(min(stage_fail_streak, 4), dp))
               call build_diversified_restart_guess(x_stage, x_stage_best, x_stage_retry, &
                                                    kick_sign=restart_sign, kick_scale=restart_scale)
               x_stage = x_stage_retry
            end if
            delta_lambda = 0.5_dp*delta_lambda
            if (delta_lambda < lambda_min_step_active) then
               converged = .false.
               deallocate (x_stage, x_stage_best, x_stage_retry, x_stage_try_best, del_stage, Jl_stage, Jl_stage_try, x_new_stage, x_new_stage_try)
               return
            end if
            if (.not. has_high_quality_stage .and. success_stage_count <= 0 .and. delta_lambda < 0.010_dp) then
               converged = .false.
               deallocate (x_stage, x_stage_best, x_stage_retry, x_stage_try_best, del_stage, Jl_stage, Jl_stage_try, x_new_stage, x_new_stage_try)
               return
            end if
         end if
      end do

      if (lambda_now >= 1.0_dp - 1.0e-12_dp .and. final_stage_ok) then
         Jl = Jl_stage
         x_new = x_new_stage
         converged = .true.
      else
         converged = .false.
      end if
      deallocate (x_stage, x_stage_best, x_stage_retry, x_stage_try_best, del_stage, Jl_stage, Jl_stage_try, x_new_stage, x_new_stage_try)
   end subroutine run_delz_continuation

   pure logical function continuation_stage_accepts(stage_ok, lambda_target, stage_best_res, stage_tol, use_fine_controls, &
                                                    stage_accept_floor, strict_controls) result(accepted_stage)
      implicit none
      logical, intent(in) :: stage_ok, use_fine_controls, strict_controls
      real(dp), intent(in) :: lambda_target, stage_best_res, stage_tol, stage_accept_floor
      real(dp) :: stage_accept_threshold

      accepted_stage = .false.
      if (lambda_target >= 1.0_dp - 1.0e-12_dp) then
         accepted_stage = stage_ok
         return
      end if
      if (stage_ok) then
         accepted_stage = .true.
         return
      end if
      if (.not. ieee_is_finite(stage_best_res) .or. stage_best_res <= 0.0_dp) return

      if (strict_controls) then
         ! In strict continuation we still require stage_ok at lambda=1,
         ! but allowing controlled coarse-stage acceptance can keep the
         ! continuation trajectory alive through near-singular transitions.
         if (use_fine_controls) then
            stage_accept_threshold = max(20.0_dp*stage_tol, stage_accept_floor)
            if (lambda_target >= 0.90_dp) stage_accept_threshold = max(8.0_dp*stage_tol, 5.0e-10_dp)
            if (lambda_target >= 0.97_dp) stage_accept_threshold = max(4.0_dp*stage_tol, 2.0e-11_dp)
         else
            stage_accept_threshold = max(2.0e4_dp*stage_tol, 1.0e-2_dp)
            if (lambda_target >= 0.90_dp) stage_accept_threshold = max(4.0e3_dp*stage_tol, 2.0e-3_dp)
            if (lambda_target >= 0.97_dp) stage_accept_threshold = max(5.0e2_dp*stage_tol, 2.0e-4_dp)
         end if
      else
         stage_accept_threshold = max(50.0_dp*stage_tol, stage_accept_floor)
         if (use_fine_controls) then
            if (lambda_target >= 0.90_dp) stage_accept_threshold = max(20.0_dp*stage_tol, 1.0e-8_dp)
            if (lambda_target >= 0.97_dp) stage_accept_threshold = max(10.0_dp*stage_tol, 5.0e-10_dp)
         end if
      end if
      accepted_stage = (stage_best_res <= stage_accept_threshold)
   end function continuation_stage_accepts

   pure real(dp) function continuation_stage_tol(base_tol, lambda_target, use_fine_controls) result(stage_tol)
      implicit none
      real(dp), intent(in) :: base_tol
      real(dp), intent(in) :: lambda_target
      logical, intent(in) :: use_fine_controls

      if (lambda_target >= 1.0_dp - 1.0e-12_dp) then
         stage_tol = base_tol
      else if (.not. use_fine_controls) then
         stage_tol = max(5.0e2_dp*base_tol, 5.0e-7_dp)
      else if (lambda_target >= 0.985_dp) then
         stage_tol = max(20.0_dp*base_tol, 5.0e-12_dp)
      else if (lambda_target >= 0.95_dp) then
         stage_tol = max(80.0_dp*base_tol, 5.0e-11_dp)
      else if (lambda_target >= 0.85_dp) then
         stage_tol = max(2.0e2_dp*base_tol, 5.0e-10_dp)
      else
         stage_tol = max(5.0e2_dp*base_tol, 5.0e-7_dp)
      end if
   end function continuation_stage_tol

   logical function should_run_diversified_retry(tol, max_iter, attempt_idx, best_res_hint) result(do_retry)
      implicit none
      real(dp), intent(in) :: tol, best_res_hint
      integer, intent(in) :: max_iter, attempt_idx

      integer :: i, n_acc, n_valid, n_heavy, n_tiny, iter_best
      real(dp) :: r, first_res, best_res, last_res
      real(dp) :: improve_frac, regress_ratio, heavy_frac, tiny_frac
      logical :: all_eval_ok
      real(dp), parameter :: tiny_alpha_threshold = 1.0e-3_dp
      integer, parameter :: heavy_backtrack_threshold = 8

      do_retry = .false.
      if (quasi_last_trace_count <= 0) return
      if (attempt_idx <= 1) then
         if (max_iter < 30) return
      else
         if (max_iter < 12) return
      end if

      n_acc = 0
      n_valid = 0
      n_heavy = 0
      n_tiny = 0
      iter_best = 0
      first_res = huge(1.0_dp)
      best_res = huge(1.0_dp)
      last_res = huge(1.0_dp)
      all_eval_ok = .true.

      do i = 1, quasi_last_trace_count
         if (quasi_last_trace_attempt(i) /= attempt_idx) cycle
         if (quasi_last_trace_iter(i) <= 0) cycle
         if (.not. quasi_last_trace_accepted(i)) cycle
         n_acc = n_acc + 1
         if (.not. quasi_last_trace_eval_ok(i)) then
            all_eval_ok = .false.
            cycle
         end if
         r = quasi_last_trace_res_norm(i)
         if (.not. ieee_is_finite(r) .or. r <= 0.0_dp) then
            all_eval_ok = .false.
            cycle
         end if
         n_valid = n_valid + 1
         if (n_valid == 1) first_res = r
         last_res = r
         if (r < best_res) then
            best_res = r
            iter_best = quasi_last_trace_iter(i)
         end if
         if (quasi_last_trace_backtrack(i) >= heavy_backtrack_threshold) n_heavy = n_heavy + 1
         if (quasi_last_trace_alpha(i) <= tiny_alpha_threshold) n_tiny = n_tiny + 1
      end do

      if (.not. all_eval_ok) return
      if (n_valid < 12) return
      if (best_res_hint < best_res) best_res = best_res_hint
      if (best_res <= max(2.0e4_dp*tol, 5.0e-3_dp)) return
      if (.not. ieee_is_finite(first_res) .or. .not. ieee_is_finite(last_res)) return
      if (iter_best <= 0) return

      improve_frac = (first_res - best_res)/max(first_res, tiny(1.0_dp))
      regress_ratio = last_res/max(best_res, tiny(1.0_dp))
      heavy_frac = real(n_heavy, dp)/real(n_valid, dp)
      tiny_frac = real(n_tiny, dp)/real(n_valid, dp)

      do_retry = (heavy_frac >= 0.30_dp) .and. (tiny_frac >= 0.20_dp) .and. &
                 (improve_frac <= 0.80_dp .or. regress_ratio > 1.03_dp) .and. &
                 (iter_best < max_iter - 3)
   end function should_run_diversified_retry

   logical function should_force_retry_attempt(tol, max_iter, best_res_hint, attempt_idx) result(do_retry)
      implicit none
      real(dp), intent(in) :: tol, best_res_hint
      integer, intent(in) :: max_iter, attempt_idx

      real(dp) :: near_tol, mid_tol

      do_retry = .false.
      if (max_iter < 40) return
      if (.not. ieee_is_finite(best_res_hint)) return
      if (best_res_hint <= tol) return
      if (attempt_idx >= 3) return

      near_tol = max(200.0_dp*tol, 1.0e-8_dp)
      mid_tol = max(2.0e4_dp*tol, 5.0e-4_dp)

      if (best_res_hint <= near_tol) return
      do_retry = (best_res_hint >= mid_tol)
   end function should_force_retry_attempt

   logical function should_force_continuation_attempt(tol, max_iter, best_res_hint, attempt_idx) result(do_retry)
      implicit none
      real(dp), intent(in) :: tol, best_res_hint
      integer, intent(in) :: max_iter, attempt_idx

      do_retry = .false.
      if (max_iter < 40) return
      if (attempt_idx <= 0 .or. attempt_idx > 6) return
      if (.not. ieee_is_finite(best_res_hint)) return
      if (best_res_hint <= max(50.0_dp*tol, 1.0e-8_dp)) return
      do_retry = .true.
   end function should_force_continuation_attempt

   pure logical function should_use_scaled_retry_seed(tol, best_res_hint) result(use_scaled)
      implicit none
      real(dp), intent(in) :: tol, best_res_hint
      real(dp) :: plateau_trigger

      use_scaled = .false.
      if (.not. ieee_is_finite(best_res_hint)) return
      plateau_trigger = max(5.0e4_dp*tol, 1.0e-3_dp)
      use_scaled = (best_res_hint >= plateau_trigger)
   end function should_use_scaled_retry_seed

   subroutine build_diversified_restart_guess(x0_guess, x_best, x_retry, kick_sign, kick_scale)
      implicit none
      real(dp), intent(in) :: x0_guess(:), x_best(:)
      real(dp), intent(out) :: x_retry(:)
      real(dp), intent(in), optional :: kick_sign, kick_scale

      integer :: i, n
      real(dp) :: proj, delta2, p_norm, base_scale, anchor_norm, sign_val, scale_val
      real(dp) :: p(size(x_best)), delta(size(x_best))

      n = size(x_best)
      if (size(x0_guess) /= n .or. size(x_retry) /= n) then
         if (size(x_retry) == size(x0_guess)) x_retry = x0_guess
         return
      end if

      sign_val = 1.0_dp
      scale_val = 1.0_dp
      if (present(kick_sign)) sign_val = merge(1.0_dp, -1.0_dp, kick_sign >= 0.0_dp)
      if (present(kick_scale)) scale_val = max(0.5_dp, min(1.5_dp, kick_scale))

      ! Blend towards the first-attempt best point, then add an orthogonal kick.
      x_retry = 0.55_dp*x_best + 0.45_dp*x0_guess
      delta = x_best - x0_guess
      do i = 1, n
         if (mod(i, 2) == 0) then
            p(i) = -max(1.0_dp, abs(x_best(i)))
         else
            p(i) = max(1.0_dp, abs(x_best(i)))
         end if
      end do

      delta2 = dot_product(delta, delta)
      if (delta2 > tiny(1.0_dp)) then
         proj = dot_product(p, delta)/delta2
         p = p - proj*delta
      end if

      p_norm = norm2(p)
      if (p_norm <= tiny(1.0_dp)) then
         p = 0.0_dp
         p(1) = 1.0_dp
         p_norm = 1.0_dp
      end if

      anchor_norm = max(norm2(x_retry), 1.0_dp)
      base_scale = min(1.0_dp, max(0.25_dp, 0.30_dp*anchor_norm))*scale_val
      x_retry = x_retry + sign_val*base_scale*(p/p_norm)
   end subroutine build_diversified_restart_guess

   subroutine build_scaled_restart_guess(x_best, x_retry, scale_factor)
      implicit none
      real(dp), intent(in) :: x_best(:)
      real(dp), intent(out) :: x_retry(:)
      real(dp), intent(in), optional :: scale_factor

      real(dp) :: factor

      factor = 0.35_dp
      if (present(scale_factor)) factor = max(0.10_dp, min(0.80_dp, scale_factor))
      if (size(x_best) /= size(x_retry)) then
         if (size(x_retry) > 0) x_retry = 0.0_dp
         return
      end if
      x_retry = factor*x_best
   end subroutine build_scaled_restart_guess

   subroutine set_attempt_outputs(x_state, res_norm, x_best_out, best_res_out)
      implicit none
      real(dp), intent(in) :: x_state(:), res_norm
      real(dp), intent(out), optional :: x_best_out(:)
      real(dp), intent(out), optional :: best_res_out

      if (present(x_best_out)) then
         if (size(x_best_out) == size(x_state)) x_best_out = x_state
      end if
      if (present(best_res_out)) best_res_out = res_norm
   end subroutine set_attempt_outputs

   pure logical function residual_within_tolerance(res_norm, tol)
      implicit none
      real(dp), intent(in) :: res_norm, tol

      residual_within_tolerance = ieee_is_finite(res_norm) .and. res_norm <= tol
   end function residual_within_tolerance

   pure logical function residual_within_accept_tolerance(res_norm, tol)
      implicit none
      real(dp), intent(in) :: res_norm, tol

      ! Bias-priority mode: treat "accept" exactly as convergence tolerance.
      ! This removes the previous absolute floor (1e-6) that could accept
      ! quasi results far above cttol in strict production runs.
      residual_within_accept_tolerance = ieee_is_finite(res_norm) .and. &
                                         res_norm <= tol
   end function residual_within_accept_tolerance

   pure logical function real_vector_is_finite(v) result(ok)
      implicit none
      real(dp), intent(in) :: v(:)
      integer :: i

      ok = .true.
      do i = 1, size(v)
         if (.not. ieee_is_finite(v(i))) then
            ok = .false.
            return
         end if
      end do
   end function real_vector_is_finite

   pure logical function real_matrix_is_finite(mat) result(ok)
      implicit none
      real(dp), intent(in) :: mat(:, :)
      integer :: i, j

      ok = .true.
      do j = 1, size(mat, 2)
         do i = 1, size(mat, 1)
            if (.not. ieee_is_finite(mat(i, j))) then
               ok = .false.
               return
            end if
         end do
      end do
   end function real_matrix_is_finite

   pure function lower_ascii(text) result(lowered)
      implicit none
      character(len=*), intent(in) :: text
      character(len=len(text)) :: lowered
      integer :: i, code

      lowered = text
      do i = 1, len(text)
         code = iachar(lowered(i:i))
         if (code >= iachar('A') .and. code <= iachar('Z')) lowered(i:i) = achar(code + 32)
      end do
   end function lower_ascii

   subroutine rescue_attempt_from_best(xt, z, del_z, tol, Jl_best, best_fx_norm, x_new, Jl, converged)
      implicit none
      real(dp), intent(in) :: xt(:), del_z(:), tol, Jl_best(:), best_fx_norm
      complex(dp), intent(in) :: z(:)
      real(dp), intent(inout) :: x_new(:), Jl(:)
      logical, intent(out) :: converged

      logical :: eval_error
      complex(dp) :: z_new(size(z))

      converged = .false.
      if (.not. residual_within_accept_tolerance(best_fx_norm, tol)) return
      if (size(Jl_best) /= size(Jl)) return

      Jl = Jl_best
      call recover_converged_flowed_state(xt, z, del_z, Jl, z_new, eval_error)
      if (eval_error) then
         converged = .false.
         return
      end if
      x_new = xt
      x_new(2:) = real(z_new, dp)
      converged = .true.
   end subroutine rescue_attempt_from_best

   pure real(dp) function proposal_correction_norm(zv, z_base, n_use) result(val)
      implicit none
      complex(dp), intent(in) :: zv(:), z_base(:)
      integer, intent(in) :: n_use

      integer :: i, n_lim
      real(dp) :: acc

      n_lim = min(n_use, min(size(zv), size(z_base)))
      if (n_lim <= 0) then
         val = 0.0_dp
         return
      end if
      acc = 0.0_dp
      do i = 1, n_lim
         acc = acc + abs(zv(i) - z_base(i))**2
      end do
      val = sqrt(max(0.0_dp, acc))
   end function proposal_correction_norm

   pure logical function reject_growth_step(z_corr_trial, z_corr_ref, del_scale, fx_norm, y_norm, best_fx_norm, tol, attempt_idx, &
                                            near_escape_mode) result(reject_step)
      implicit none
      real(dp), intent(in) :: z_corr_trial, z_corr_ref, del_scale, fx_norm, y_norm, best_fx_norm, tol
      integer, intent(in) :: attempt_idx
      logical, intent(in), optional :: near_escape_mode

      real(dp) :: corr_guard, improve_gate
      logical :: near_escape

      reject_step = .false.
      if (.not. ieee_is_finite(z_corr_trial)) return
      if (.not. ieee_is_finite(z_corr_ref)) return
      if (.not. ieee_is_finite(del_scale)) return

      near_escape = .false.
      if (present(near_escape_mode)) near_escape = near_escape_mode

      corr_guard = growth_guard_threshold(z_corr_ref, del_scale, y_norm, tol, attempt_idx, near_escape_mode=near_escape)

      if (z_corr_trial <= corr_guard) return

      if (near_escape) then
         improve_gate = max(5.0e2_dp*tol, max(0.75_dp*y_norm, 1.50_dp*best_fx_norm))
      else
         improve_gate = max(1.0e3_dp*tol, min(0.45_dp*y_norm, 0.65_dp*best_fx_norm))
      end if
      reject_step = (.not. ieee_is_finite(fx_norm)) .or. (fx_norm > improve_gate)
   end function reject_growth_step

   pure real(dp) function growth_guard_threshold(z_corr_ref, del_scale, y_norm, tol, attempt_idx, near_escape_mode) result(corr_guard)
      implicit none
      real(dp), intent(in) :: z_corr_ref, del_scale, y_norm, tol
      integer, intent(in) :: attempt_idx
      real(dp) :: growth_limit
      logical, intent(in), optional :: near_escape_mode
      logical :: near_escape

      near_escape = .false.
      if (present(near_escape_mode)) near_escape = near_escape_mode

      if (near_escape) then
         if (attempt_idx <= 1) then
            growth_limit = 26.0_dp
         else
            growth_limit = 20.0_dp
         end if
         if (y_norm > max(2.0e4_dp*tol, 1.0e-3_dp)) growth_limit = 0.95_dp*growth_limit
         corr_guard = max(2.0_dp*del_scale, growth_limit*max(z_corr_ref, 0.15_dp*del_scale))
      else
         if (attempt_idx <= 1) then
            growth_limit = 14.0_dp
         else
            growth_limit = 10.0_dp
         end if
         if (y_norm > max(2.0e4_dp*tol, 1.0e-3_dp)) growth_limit = 0.9_dp*growth_limit
         corr_guard = max(3.0_dp*del_scale, growth_limit*max(z_corr_ref, 0.30_dp*del_scale))
      end if
   end function growth_guard_threshold

   pure real(dp) function growth_clip_factor(z_corr_trial, z_corr_ref, del_scale, y_norm, tol, attempt_idx, &
                                             clip_min, clip_max, default_shrink, near_escape_mode) result(shrink)
      implicit none
      real(dp), intent(in) :: z_corr_trial, z_corr_ref, del_scale, y_norm, tol
      real(dp), intent(in) :: clip_min, clip_max, default_shrink
      integer, intent(in) :: attempt_idx
      real(dp) :: corr_guard
      logical, intent(in), optional :: near_escape_mode
      logical :: near_escape
      real(dp) :: clip_max_local

      shrink = default_shrink
      if (.not. ieee_is_finite(z_corr_trial) .or. z_corr_trial <= tiny(1.0_dp)) return
      near_escape = .false.
      if (present(near_escape_mode)) near_escape = near_escape_mode
      corr_guard = growth_guard_threshold(z_corr_ref, del_scale, y_norm, tol, attempt_idx, near_escape_mode=near_escape)
      if (.not. ieee_is_finite(corr_guard)) return
      shrink = 0.9_dp*corr_guard/max(z_corr_trial, tiny(1.0_dp))
      clip_max_local = clip_max
      if (near_escape) clip_max_local = max(clip_max_local, 0.95_dp)
      shrink = min(max(shrink, clip_min), clip_max_local)
   end function growth_clip_factor

   subroutine set_identity_matrix(mat)
      implicit none
      real(dp), intent(inout) :: mat(:, :)
      integer :: i, n_diag

      mat = 0.0_dp
      n_diag = min(size(mat, 1), size(mat, 2))
      do i = 1, n_diag
         mat(i, i) = 1.0_dp
      end do
   end subroutine set_identity_matrix

   subroutine update_best_quasi_state(fx_norm, x_val, fx_val, Jl_val, x_best, fx_best, Jl_best, best_fx_norm)
      implicit none
      real(dp), intent(in) :: fx_norm
      real(dp), intent(in) :: x_val(:), fx_val(:), Jl_val(:)
      real(dp), intent(inout) :: x_best(:), fx_best(:), Jl_best(:), best_fx_norm

      if (.not. ieee_is_finite(fx_norm)) return
      if (fx_norm >= best_fx_norm) return
      if (size(x_val) /= size(x_best)) return
      if (size(fx_val) /= size(fx_best) .or. size(Jl_val) /= size(Jl_best)) return

      best_fx_norm = fx_norm
      x_best = x_val
      fx_best = fx_val
      Jl_best = Jl_val
   end subroutine update_best_quasi_state

   subroutine mark_constraint_eval_invalid(fq, Jl, ierr)
      implicit none
      real(dp), intent(out) :: fq(:), Jl(:)
      logical, intent(out) :: ierr

      ! Invalid flow evaluations are signaled by ierr, not by an artificial
      ! large residual that could pollute trust-region or line-search state.
      fq = 0.0_dp
      Jl = 0.0_dp
      ierr = .true.
      quasi_eval_has_flowed = .false.
      quasi_eval_flowed_is_inverse = .false.
   end subroutine mark_constraint_eval_invalid

   subroutine reset_quasi_eval_flow_status_counts()
      implicit none

      quasi_eval_flow_status_success = 0_int64
      quasi_eval_flow_status_zero_time = 0_int64
      quasi_eval_flow_status_stiff_rescue = 0_int64
      quasi_eval_flow_status_solver_assist = 0_int64
      quasi_eval_flow_status_failure_max_steps = 0_int64
      quasi_eval_flow_status_failure_invalid = 0_int64
      quasi_eval_flow_status_failure_h_min = 0_int64
      quasi_eval_flow_status_unknown = 0_int64
   end subroutine reset_quasi_eval_flow_status_counts

   subroutine get_quasi_eval_flow_status_counts(success, zero_time, stiff_rescue, solver_assist, &
                                                failure_max_steps, failure_invalid, failure_h_min, unknown)
      implicit none
      integer(int64), intent(out) :: success, zero_time, stiff_rescue, solver_assist
      integer(int64), intent(out) :: failure_max_steps, failure_invalid, failure_h_min, unknown

      success = quasi_eval_flow_status_success
      zero_time = quasi_eval_flow_status_zero_time
      stiff_rescue = quasi_eval_flow_status_stiff_rescue
      solver_assist = quasi_eval_flow_status_solver_assist
      failure_max_steps = quasi_eval_flow_status_failure_max_steps
      failure_invalid = quasi_eval_flow_status_failure_invalid
      failure_h_min = quasi_eval_flow_status_failure_h_min
      unknown = quasi_eval_flow_status_unknown
   end subroutine get_quasi_eval_flow_status_counts

   subroutine record_quasi_eval_flow_status(flow_status)
      implicit none
      integer, intent(in) :: flow_status

      select case (flow_status)
      case (intode_status_success)
         quasi_eval_flow_status_success = quasi_eval_flow_status_success + 1_int64
      case (intode_status_success_zero_time)
         quasi_eval_flow_status_zero_time = quasi_eval_flow_status_zero_time + 1_int64
      case (intode_status_success_stiff_rescue)
         quasi_eval_flow_status_stiff_rescue = quasi_eval_flow_status_stiff_rescue + 1_int64
      case (intode_status_success_solver_assist)
         quasi_eval_flow_status_solver_assist = quasi_eval_flow_status_solver_assist + 1_int64
      case (intode_status_failure_max_steps)
         quasi_eval_flow_status_failure_max_steps = quasi_eval_flow_status_failure_max_steps + 1_int64
      case (intode_status_failure_invalid)
         quasi_eval_flow_status_failure_invalid = quasi_eval_flow_status_failure_invalid + 1_int64
      case (intode_status_failure_h_min)
         quasi_eval_flow_status_failure_h_min = quasi_eval_flow_status_failure_h_min + 1_int64
      case default
         quasi_eval_flow_status_unknown = quasi_eval_flow_status_unknown + 1_int64
      end select
   end subroutine record_quasi_eval_flow_status

   subroutine evaluate_constraint_residual(xt, z, xi, fq, del_z, ierr, Jl, jac)
      implicit none
      real(dp), intent(in) :: xt(:), xi(:), del_z(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: fq(:), Jl(:)
      logical, intent(out) :: ierr

      integer :: flow_status, n

      n = size(z)
      if (size(xt) /= n + 1 .or. size(xi) /= 2*n .or. size(del_z) /= 2*n .or. size(fq) /= 2*n .or. size(Jl) /= 2*n) then
         call mark_constraint_eval_invalid(fq, Jl, ierr)
         return
      end if

      call ensure_complex_workspace(residual_jlc, n)
      call ensure_complex_workspace(residual_z_trial, n)

      ! BTN paper variables: xi(1:n)=b, xi(n+1:2*n)=a, ztrial = ztilde - J*(a+i*b).
      residual_jlc = -matmul(jac, xi(n + 1:) + cmplx(0.0_dp, 1.0_dp, dp)*xi(1:n))
      call complex_to_real(residual_jlc, Jl)

      call real_to_complex(del_z, residual_z_trial)
      residual_z_trial = z + residual_z_trial + residual_jlc
      call ensure_complex_workspace(quasi_eval_z_proposed, n)
      call ensure_complex_workspace(quasi_eval_z_flowed, n)
      quasi_eval_z_proposed(1:n) = residual_z_trial(1:n)
      quasi_eval_has_flowed = .false.
      quasi_eval_flowed_is_inverse = .false.
      call update_quasi_watchdog_scope()
      if (quasi_watchdog_scope_active .and. quasi_watchdog_hit) then
         call mark_constraint_eval_invalid(fq, Jl, ierr)
         return
      end if

      call set_intode_stage_trace(intode_stage_quasi)
      call set_intode_quasi_iter_trace(quasi_trace_iter)
      flow_status = intode_status_unknown
      call flowzr(xt, residual_z_trial, ierr, flow_status)
      call record_quasi_eval_flow_status(flow_status)
      if (ierr) then
         call mark_constraint_eval_invalid(fq, Jl, ierr)
         return
      end if
      call update_quasi_watchdog_scope()
      if (quasi_watchdog_scope_active .and. quasi_watchdog_hit) then
         call mark_constraint_eval_invalid(fq, Jl, ierr)
         return
      end if
      quasi_eval_z_flowed(1:n) = residual_z_trial(1:n)
      quasi_eval_has_flowed = .true.
      quasi_eval_flowed_is_inverse = .true.

      fq(1:n) = aimag(residual_z_trial)
      fq(n + 1:) = xi(n + 1:)
   end subroutine evaluate_constraint_residual

   subroutine evaluate_constraint_residual_newton_loss(xt, z, xi, fq, del_z, ierr, Jl, jac)
      implicit none
      real(dp), intent(in) :: xt(:), xi(:), del_z(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: fq(:), Jl(:)
      logical, intent(out) :: ierr

      integer :: flow_status, n

      n = size(z)
      if (size(xt) /= n + 1 .or. size(xi) /= 2*n .or. size(del_z) /= 2*n .or. size(fq) /= 2*n .or. size(Jl) /= 2*n) then
         call mark_constraint_eval_invalid(fq, Jl, ierr)
         return
      end if

      call ensure_complex_workspace(residual_jlc, n)
      call ensure_complex_workspace(residual_z_trial, n)
      call ensure_complex_workspace(residual_z_flowed, n)
      call ensure_real_workspace(residual_xtu, n + 1)

      ! Post-refine loss (independent 2n variables xi=[u;ld]):
      !   r = z - flowz(x0 + u) - i*J*ld + del_z
      ! Jl stores the proposal correction jlc = -i*J*ld.
      residual_jlc = matmul(jac, cmplx(0.0_dp, -1.0_dp, dp)*xi(n + 1:))
      call complex_to_real(residual_jlc, Jl)

      call real_to_complex(del_z, residual_z_trial)
      residual_z_trial = z + residual_z_trial + residual_jlc
      call ensure_complex_workspace(quasi_eval_z_proposed, n)
      call ensure_complex_workspace(quasi_eval_z_flowed, n)
      quasi_eval_z_proposed(1:n) = residual_z_trial(1:n)
      quasi_eval_has_flowed = .false.
      quasi_eval_flowed_is_inverse = .false.
      call update_quasi_watchdog_scope()
      if (quasi_watchdog_scope_active .and. quasi_watchdog_hit) then
         call mark_constraint_eval_invalid(fq, Jl, ierr)
         return
      end if

      residual_xtu = xt
      residual_xtu(2:) = xt(2:) + xi(1:n)
      call set_intode_stage_trace(intode_stage_quasi)
      call set_intode_quasi_iter_trace(quasi_trace_iter)
      flow_status = intode_status_unknown
      call flowz(residual_xtu, residual_z_flowed, ierr, flow_status)
      call record_quasi_eval_flow_status(flow_status)
      if (ierr) then
         call mark_constraint_eval_invalid(fq, Jl, ierr)
         return
      end if
      call update_quasi_watchdog_scope()
      if (quasi_watchdog_scope_active .and. quasi_watchdog_hit) then
         call mark_constraint_eval_invalid(fq, Jl, ierr)
         return
      end if
      quasi_eval_z_flowed(1:n) = residual_z_flowed(1:n)
      quasi_eval_has_flowed = .true.
      quasi_eval_flowed_is_inverse = .false.

      residual_z_trial = residual_z_trial - residual_z_flowed
      call complex_to_real(residual_z_trial, fq)
   end subroutine evaluate_constraint_residual_newton_loss

   subroutine get_quasi_newton_last_trace_r2c(available, proposal_count, z_proposed, z_flowed, residual_norm, alpha, &
                                              iter_idx, backtrack_idx, attempt_idx, accepted, eval_ok, route_code)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: proposal_count
      complex(dp), allocatable, intent(out) :: z_proposed(:), z_flowed(:)
      real(dp), allocatable, intent(out) :: residual_norm(:), alpha(:)
      integer, allocatable, intent(out) :: iter_idx(:), backtrack_idx(:), attempt_idx(:)
      integer, allocatable, intent(out), optional :: route_code(:)
      logical, allocatable, intent(out) :: accepted(:), eval_ok(:)

      available = (quasi_last_trace_dim == 1 .and. quasi_last_trace_count > 0)
      proposal_count = quasi_last_trace_count
      if (.not. available) return

      allocate (z_proposed(proposal_count), z_flowed(proposal_count), residual_norm(proposal_count), alpha(proposal_count), &
                iter_idx(proposal_count), backtrack_idx(proposal_count), attempt_idx(proposal_count), &
                accepted(proposal_count), eval_ok(proposal_count))
      z_proposed = quasi_last_trace_z_proposed(1, 1:proposal_count)
      z_flowed = quasi_last_trace_z_flowed(1, 1:proposal_count)
      residual_norm = quasi_last_trace_res_norm(1:proposal_count)
      alpha = quasi_last_trace_alpha(1:proposal_count)
      iter_idx = quasi_last_trace_iter(1:proposal_count)
      backtrack_idx = quasi_last_trace_backtrack(1:proposal_count)
      attempt_idx = quasi_last_trace_attempt(1:proposal_count)
      if (present(route_code)) then
         allocate (route_code(proposal_count))
         route_code = quasi_last_trace_route(1:proposal_count)
      end if
      accepted = quasi_last_trace_accepted(1:proposal_count)
      eval_ok = quasi_last_trace_eval_ok(1:proposal_count)
   end subroutine get_quasi_newton_last_trace_r2c

   subroutine get_quasi_newton_last_trace_stats(available, proposal_count, first_res_norm, best_res_norm, last_res_norm, all_eval_ok, &
                                                valid_eval_count, valid_eval_fraction)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: proposal_count
      real(dp), intent(out) :: first_res_norm, best_res_norm, last_res_norm
      logical, intent(out) :: all_eval_ok
      integer, intent(out) :: valid_eval_count
      real(dp), intent(out) :: valid_eval_fraction

      integer :: i, last_attempt, n_used
      real(dp) :: r

      available = (quasi_last_trace_count > 0)
      proposal_count = 0
      first_res_norm = huge(1.0_dp)
      best_res_norm = huge(1.0_dp)
      last_res_norm = huge(1.0_dp)
      all_eval_ok = .true.
      valid_eval_count = 0
      valid_eval_fraction = 0.0_dp
      if (.not. available) return
      last_attempt = quasi_last_trace_attempt(quasi_last_trace_count)
      n_used = 0

      do i = 1, quasi_last_trace_count
         if (quasi_last_trace_attempt(i) /= last_attempt) cycle
         n_used = n_used + 1
         if (.not. quasi_last_trace_eval_ok(i)) then
            all_eval_ok = .false.
            cycle
         end if
         valid_eval_count = valid_eval_count + 1
         r = quasi_last_trace_res_norm(i)
         if (ieee_is_finite(r) .and. r > 0.0_dp) then
            if (first_res_norm >= huge(1.0_dp)*0.5_dp) first_res_norm = r
            if (r < best_res_norm) best_res_norm = r
            last_res_norm = r
         end if
      end do

      proposal_count = n_used
      if (n_used > 0) then
         valid_eval_fraction = real(valid_eval_count, dp)/real(n_used, dp)
      end if
      if (n_used <= 0) available = .false.
      if (first_res_norm >= huge(1.0_dp)*0.5_dp) available = .false.
      if (best_res_norm >= huge(1.0_dp)*0.5_dp) available = .false.
      if (last_res_norm >= huge(1.0_dp)*0.5_dp) available = .false.
      if (.not. ieee_is_finite(first_res_norm)) available = .false.
      if (.not. ieee_is_finite(best_res_norm)) available = .false.
      if (.not. ieee_is_finite(last_res_norm)) available = .false.
   end subroutine get_quasi_newton_last_trace_stats

   subroutine ensure_complex_workspace(buf, n_need)
      implicit none
      complex(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_complex_workspace

   subroutine ensure_real_workspace(buf, n_need)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_real_workspace

   subroutine ensure_int_workspace(buf, n_need)
      implicit none
      integer, allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_int_workspace

   subroutine ensure_logical_workspace(buf, n_need)
      implicit none
      logical, allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_logical_workspace

   subroutine ensure_trace_capacity(n_need)
      implicit none
      integer, intent(in) :: n_need
      integer :: new_cap

      if (quasi_last_trace_dim <= 0) return
      if (allocated(quasi_last_trace_z_proposed)) then
         if (size(quasi_last_trace_z_proposed, 1) /= quasi_last_trace_dim) then
            deallocate (quasi_last_trace_z_proposed, quasi_last_trace_z_flowed, quasi_last_trace_res_norm, quasi_last_trace_alpha, &
                        quasi_last_trace_iter, quasi_last_trace_backtrack, quasi_last_trace_attempt, quasi_last_trace_route, &
                        quasi_last_trace_accepted, quasi_last_trace_eval_ok)
            quasi_last_trace_capacity = 0
            quasi_last_trace_count = 0
         end if
      end if

      if (n_need <= quasi_last_trace_capacity .and. allocated(quasi_last_trace_z_proposed)) return

      new_cap = max(64, max(n_need, 2*quasi_last_trace_capacity))
      call grow_complex_trace(quasi_last_trace_z_proposed, quasi_last_trace_dim, quasi_last_trace_count, new_cap)
      call grow_complex_trace(quasi_last_trace_z_flowed, quasi_last_trace_dim, quasi_last_trace_count, new_cap)
      call grow_real_trace(quasi_last_trace_res_norm, quasi_last_trace_count, new_cap)
      call grow_real_trace(quasi_last_trace_alpha, quasi_last_trace_count, new_cap)
      call grow_int_trace(quasi_last_trace_iter, quasi_last_trace_count, new_cap)
      call grow_int_trace(quasi_last_trace_backtrack, quasi_last_trace_count, new_cap)
      call grow_int_trace(quasi_last_trace_attempt, quasi_last_trace_count, new_cap)
      call grow_int_trace(quasi_last_trace_route, quasi_last_trace_count, new_cap)
      call grow_logical_trace(quasi_last_trace_accepted, quasi_last_trace_count, new_cap)
      call grow_logical_trace(quasi_last_trace_eval_ok, quasi_last_trace_count, new_cap)
      quasi_last_trace_capacity = new_cap
   end subroutine ensure_trace_capacity

   subroutine reset_quasi_last_trace(n_dim)
      implicit none
      integer, intent(in) :: n_dim

      quasi_last_trace_count = 0
      quasi_last_trace_dim = n_dim
      quasi_trace_route_code = 0
      call ensure_complex_workspace(quasi_eval_z_proposed, n_dim)
      call ensure_complex_workspace(quasi_eval_z_flowed, n_dim)
      quasi_eval_has_flowed = .false.
      quasi_eval_flowed_is_inverse = .false.
      call ensure_trace_capacity(1)
   end subroutine reset_quasi_last_trace

   subroutine append_quasi_trace_sample(alpha, iter_idx, backtrack_idx, attempt_idx, res_norm, accepted, eval_ok)
      implicit none
      real(dp), intent(in) :: alpha, res_norm
      integer, intent(in) :: iter_idx, backtrack_idx, attempt_idx
      logical, intent(in) :: accepted, eval_ok
      integer :: k, n_dim, i
      real(dp) :: nanv

      n_dim = quasi_last_trace_dim
      if (n_dim <= 0) return
      call ensure_trace_capacity(quasi_last_trace_count + 1)
      if (.not. allocated(quasi_last_trace_z_proposed)) return

      k = quasi_last_trace_count + 1
      quasi_last_trace_z_proposed(1:n_dim, k) = quasi_eval_z_proposed(1:n_dim)
      if (quasi_eval_has_flowed) then
         quasi_last_trace_z_flowed(1:n_dim, k) = quasi_eval_z_flowed(1:n_dim)
      else
         nanv = ieee_value(0.0_dp, ieee_quiet_nan)
         do i = 1, n_dim
            quasi_last_trace_z_flowed(i, k) = cmplx(nanv, nanv, dp)
         end do
      end if
      quasi_last_trace_res_norm(k) = res_norm
      quasi_last_trace_alpha(k) = alpha
      quasi_last_trace_iter(k) = iter_idx
      quasi_last_trace_backtrack(k) = backtrack_idx
      quasi_last_trace_attempt(k) = attempt_idx
      quasi_last_trace_route(k) = quasi_trace_route_code
      quasi_last_trace_accepted(k) = accepted
      quasi_last_trace_eval_ok(k) = eval_ok
      quasi_last_trace_count = k

      if (quasi_watchdog_scope_active .and. accepted .and. eval_ok) then
         quasi_watchdog_used_accepted_iter = quasi_watchdog_used_accepted_iter + 1
         if ((.not. quasi_watchdog_hit) .and. quasi_accepted_iter_budget > 0) then
            if (quasi_watchdog_used_accepted_iter > quasi_accepted_iter_budget) then
               quasi_watchdog_hit = .true.
               quasi_watchdog_hit_total = quasi_watchdog_hit_total + 1
            end if
         end if
      end if
   end subroutine append_quasi_trace_sample

   subroutine grow_complex_trace(buf, n_dim, n_keep, n_new)
      implicit none
      complex(dp), allocatable, intent(inout) :: buf(:, :)
      integer, intent(in) :: n_dim, n_keep, n_new
      complex(dp), allocatable :: tmp(:, :)

      allocate (tmp(n_dim, n_new))
      if (allocated(buf) .and. n_keep > 0) then
         tmp(1:n_dim, 1:n_keep) = buf(1:n_dim, 1:n_keep)
      end if
      call move_alloc(tmp, buf)
   end subroutine grow_complex_trace

   subroutine grow_real_trace(buf, n_keep, n_new)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_keep, n_new
      real(dp), allocatable :: tmp(:)

      allocate (tmp(n_new))
      if (allocated(buf) .and. n_keep > 0) tmp(1:n_keep) = buf(1:n_keep)
      call move_alloc(tmp, buf)
   end subroutine grow_real_trace

   subroutine grow_int_trace(buf, n_keep, n_new)
      implicit none
      integer, allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_keep, n_new
      integer, allocatable :: tmp(:)

      allocate (tmp(n_new))
      if (allocated(buf) .and. n_keep > 0) tmp(1:n_keep) = buf(1:n_keep)
      call move_alloc(tmp, buf)
   end subroutine grow_int_trace

   subroutine grow_logical_trace(buf, n_keep, n_new)
      implicit none
      logical, allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_keep, n_new
      logical, allocatable :: tmp(:)

      allocate (tmp(n_new))
      if (allocated(buf) .and. n_keep > 0) tmp(1:n_keep) = buf(1:n_keep)
      call move_alloc(tmp, buf)
   end subroutine grow_logical_trace

   subroutine reset_quasi_watchdog_last_status()
      implicit none
      quasi_watchdog_last_hit = .false.
      quasi_watchdog_last_used = 0
      quasi_watchdog_last_used_accepted_iter = 0
   end subroutine reset_quasi_watchdog_last_status

   subroutine begin_quasi_watchdog_scope()
      implicit none

      call load_quasi_watchdog_policy()
      quasi_watchdog_scope_active = (quasi_final_resort_budget > 0 .or. quasi_accepted_iter_budget > 0)
      quasi_watchdog_hit = .false.
      quasi_watchdog_used_success_final_resort = 0
      quasi_watchdog_used_accepted_iter = 0
      quasi_watchdog_start_success_final_resort = current_success_final_resort_count()
      call reset_quasi_watchdog_last_status()
   end subroutine begin_quasi_watchdog_scope

   subroutine end_quasi_watchdog_scope()
      implicit none

      call update_quasi_watchdog_scope()
      quasi_watchdog_last_hit = quasi_watchdog_hit
      quasi_watchdog_last_used = quasi_watchdog_used_success_final_resort
      quasi_watchdog_last_used_accepted_iter = quasi_watchdog_used_accepted_iter
      quasi_watchdog_scope_active = .false.
   end subroutine end_quasi_watchdog_scope

   subroutine update_quasi_watchdog_scope()
      implicit none
      integer :: current_success_final_resort

      if (.not. quasi_watchdog_scope_active) return
      current_success_final_resort = current_success_final_resort_count()
      quasi_watchdog_used_success_final_resort = max(0, current_success_final_resort - quasi_watchdog_start_success_final_resort)
      if ((.not. quasi_watchdog_hit) .and. quasi_final_resort_budget > 0) then
         if (quasi_watchdog_used_success_final_resort > quasi_final_resort_budget) then
            quasi_watchdog_hit = .true.
            quasi_watchdog_hit_total = quasi_watchdog_hit_total + 1
         end if
      end if
      if ((.not. quasi_watchdog_hit) .and. quasi_accepted_iter_budget > 0) then
         if (quasi_watchdog_used_accepted_iter > quasi_accepted_iter_budget) then
            quasi_watchdog_hit = .true.
            quasi_watchdog_hit_total = quasi_watchdog_hit_total + 1
         end if
      end if
   end subroutine update_quasi_watchdog_scope

   subroutine get_quasi_newton_watchdog_status(budget_hit, budget_used, budget_limit)
      implicit none
      logical, intent(out) :: budget_hit
      integer, intent(out) :: budget_used, budget_limit

      call load_quasi_watchdog_policy()
      if (quasi_watchdog_scope_active) call update_quasi_watchdog_scope()
      if (quasi_watchdog_scope_active) then
         budget_hit = quasi_watchdog_hit
         if (quasi_final_resort_budget > 0) then
            budget_used = quasi_watchdog_used_success_final_resort
         else
            budget_used = quasi_watchdog_used_accepted_iter
         end if
      else
         budget_hit = quasi_watchdog_last_hit
         if (quasi_final_resort_budget > 0) then
            budget_used = quasi_watchdog_last_used
         else
            budget_used = quasi_watchdog_last_used_accepted_iter
         end if
      end if
      if (quasi_final_resort_budget > 0) then
         budget_limit = quasi_final_resort_budget
      else
         budget_limit = quasi_accepted_iter_budget
      end if
   end subroutine get_quasi_newton_watchdog_status

   integer function current_success_final_resort_count() result(success_final_resort)
      implicit none
      integer :: success_radau_adaptive, success_radau_adaptive_robust
      integer :: success_radau_fixed_tol, success_radau_chunked
      integer :: fail_radau_adaptive_robust, fail_radau_fixed_tol, fail_radau_chunked, fail_final_resort

      call get_intode_rescue_stats(success_radau_adaptive, success_radau_adaptive_robust, &
                                   success_radau_fixed_tol, success_radau_chunked, success_final_resort, &
                                   fail_radau_adaptive_robust, fail_radau_fixed_tol, fail_radau_chunked, fail_final_resort)
   end function current_success_final_resort_count

   subroutine load_quasi_watchdog_policy()
      implicit none
      character(len=64) :: env_value
      integer :: env_len, env_stat, ios, parsed_value

      if (quasi_final_resort_budget_loaded) return
      quasi_final_resort_budget_loaded = .true.
      quasi_accepted_iter_budget = quasi_accepted_iter_budget_default
      quasi_global_fallback_enabled = .false.
      qn_force_best_proposal_enabled = .false.
      qn_force_best_proposal_tol = -1.0_dp

      call get_environment_variable("QUASI_FINAL_RESORT_BUDGET", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         read (env_value(1:env_len), *, iostat=ios) parsed_value
         if (ios == 0) quasi_final_resort_budget = parsed_value
      end if

      call get_environment_variable("QN_ACCEPTED_ITER_BUDGET", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         read (env_value(1:env_len), *, iostat=ios) parsed_value
         if (ios == 0) quasi_accepted_iter_budget = max(0, parsed_value)
      else
         call get_environment_variable("QUASI_ACCEPTED_ITER_BUDGET", env_value, length=env_len, status=env_stat)
         if (env_stat == 0 .and. env_len > 0) then
            read (env_value(1:env_len), *, iostat=ios) parsed_value
            if (ios == 0) quasi_accepted_iter_budget = max(0, parsed_value)
         end if
      end if

      call get_environment_variable("QN_QUASI_GLOBAL_FALLBACK_ENABLED", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         select case (trim(adjustl(env_value(1:env_len))))
         case ("0", "false", "FALSE", "False", "no", "NO", "No", "off", "OFF", "Off")
            quasi_global_fallback_enabled = .false.
         case default
            quasi_global_fallback_enabled = .true.
         end select
      end if

      call get_environment_variable("QN_FORCE_BEST_PROPOSAL_ENABLED", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         select case (trim(adjustl(env_value(1:env_len))))
         case ("0", "false", "FALSE", "False", "no", "NO", "No", "off", "OFF", "Off")
            qn_force_best_proposal_enabled = .false.
         case default
            qn_force_best_proposal_enabled = .true.
         end select
      end if

      call get_environment_variable("QN_FORCE_BEST_PROPOSAL_TOL", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         read (env_value(1:env_len), *, iostat=ios) qn_force_best_proposal_tol
         if (ios /= 0 .or. qn_force_best_proposal_tol <= 0.0_dp) then
            qn_force_best_proposal_tol = -1.0_dp
            write (*, '(A)') "[WARN] Invalid QN_FORCE_BEST_PROPOSAL_TOL; using quasi tol."
         end if
      end if

      if (quasi_final_resort_budget > 0) then
         write (*, '(A,I0)') "[INFO] quasi final_resort watchdog budget=", quasi_final_resort_budget
      else
         write (*, '(A)') "[INFO] quasi final_resort watchdog budget=disabled"
      end if
      if (quasi_accepted_iter_budget > 0) then
         write (*, '(A,I0)') "[INFO] quasi accepted-iter watchdog budget=", quasi_accepted_iter_budget
      else
         write (*, '(A)') "[INFO] quasi accepted-iter watchdog budget=disabled"
      end if
      write (*, '(A,L1)') "[INFO] quasi global fallback enabled=", quasi_global_fallback_enabled
      write (*, '(A,L1,1X,A,ES10.3)') "[INFO] force best proposal enabled=", qn_force_best_proposal_enabled, &
         "tol=", qn_force_best_proposal_tol
   end subroutine load_quasi_watchdog_policy

   subroutine get_quasi_global_filter_stats(candidate_count, pass_count, reject_count)
      implicit none
      integer(int64), intent(out) :: candidate_count, pass_count, reject_count

      candidate_count = quasi_global_filter_candidate_count
      pass_count = quasi_global_filter_pass_count
      reject_count = quasi_global_filter_reject_count
   end subroutine get_quasi_global_filter_stats

end module quasi_newton_solver_mod

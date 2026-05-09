module quasi_newton_solver_mod
   use utils
   use, intrinsic :: iso_fortran_env, only: int64
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite, ieee_value, ieee_quiet_nan
   use solve_flow, only: flowzr, flowz, set_intode_stage_trace, set_intode_quasi_iter_trace, intode_stage_quasi, &
                         get_intode_rescue_stats, intode_status_unknown, intode_status_success, intode_status_success_zero_time, &
                         intode_status_success_stiff_rescue, intode_status_success_solver_assist, &
                         intode_status_failure_max_steps, intode_status_failure_invalid, intode_status_failure_h_min
   use quasi_newton_linear_solver_mod, only: solve_linear_direction, initial_guess_from_jacobian
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

      real(dp), parameter :: promising_first_pass_res = 1.0e-2_dp
      real(dp), parameter :: probe_priority_pass_trigger_res = 1.0e-3_dp
      real(dp), parameter :: probe_global_rescue_trigger_res = 4.3e-3_dp

      integer :: n, attempt_idx
      logical :: converged, stage_converged, run_priority_pass
      logical :: global_filter_candidate
      real(dp) :: best_res_first, best_res_try, best_res_global
      real(dp) :: best_accept_tol
      real(dp), allocatable :: x0_guess(:), x_best_first(:), x_stage_best(:), x_stage_seed(:), x_best_global(:)
      real(dp), allocatable :: x_try(:), Jl_try(:), Jl_best_global(:)

      n = 2*size(z)
      allocate (x0_guess(n), x_best_first(n), x_stage_best(n), x_stage_seed(n), x_try(n), x_best_global(n), &
                Jl_try(n), Jl_best_global(n))
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
      if (max_iter > 32) global_filter_candidate = .true.
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

      if ((.not. converged) .and. ieee_is_finite(best_res_global) .and. &
          best_res_global <= probe_global_rescue_trigger_res) then
         global_filter_candidate = .true.
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
      deallocate (x0_guess, x_best_first, x_stage_best, x_stage_seed, x_try, x_best_global, Jl_try, Jl_best_global)
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

   pure logical function residual_within_accept_tolerance(res_norm, tol)
      implicit none
      real(dp), intent(in) :: res_norm, tol

      residual_within_accept_tolerance = ieee_is_finite(res_norm) .and. res_norm <= tol
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

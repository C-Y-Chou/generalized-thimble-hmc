module quasi_newton_solver_mod
   use runtime_env_mod, only: parse_int_env, parse_real_env, parse_logical_env, read_string_env, to_lower_ascii
   use utils, only: dp, complex_to_real, real_to_complex
   use, intrinsic :: iso_fortran_env, only: int64
   use, intrinsic :: iso_c_binding, only: c_associated, c_double, c_f_pointer, c_funloc, c_funptr, c_int, c_loc, c_null_ptr, c_ptr
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite, ieee_value, ieee_quiet_nan
   use solve_flow, only: flowzr, flowz, flow_workspace_t, intode_diagnostics_context_t, set_intode_stage_trace, set_intode_quasi_iter_trace, &
                         set_intode_residual_role_trace, get_intode_residual_role_trace, &
                         intode_stage_quasi, intode_role_qn_navigation, intode_role_certification, intode_role_reverse_replay, &
                         intode_status_unknown, intode_status_success, intode_status_success_zero_time, &
                         intode_status_success_stiff_rescue, intode_status_success_solver_assist, &
                         intode_status_failure_max_steps, intode_status_failure_invalid, intode_status_failure_h_min
   use quasi_newton_linear_solver_mod, only: initial_guess_from_jacobian
   implicit none

   type :: qn_context_t
      complex(dp), allocatable :: residual_jlc(:), residual_z_trial(:)
      integer :: trace_iter = 0
      integer :: last_trace_count = 0
      integer :: last_trace_capacity = 0
      integer :: last_trace_dim = 0
      complex(dp), allocatable :: last_trace_z_proposed(:, :), last_trace_z_flowed(:, :)
      real(dp), allocatable :: last_trace_res_norm(:), last_trace_alpha(:)
      integer, allocatable :: last_trace_iter(:), last_trace_backtrack(:), last_trace_attempt(:)
      integer, allocatable :: last_trace_route(:)
      logical, allocatable :: last_trace_accepted(:), last_trace_eval_ok(:)
      complex(dp), allocatable :: eval_z_proposed(:), eval_z_flowed(:)
      logical :: eval_has_flowed = .false.
      logical :: eval_flowed_is_inverse = .false.
      integer :: trace_route_code = 0
      integer(int64) :: current_attempt_eval_count = 0_int64
   end type qn_context_t

   type(qn_context_t), target, save :: module_qn_context

   type :: qn_diagnostics_context_t
      integer(int64) :: global_filter_candidate_count = 0_int64
      integer(int64) :: global_filter_pass_count = 0_int64
      integer(int64) :: global_filter_reject_count = 0_int64
      integer(int64) :: eval_flow_status_success = 0_int64
      integer(int64) :: eval_flow_status_zero_time = 0_int64
      integer(int64) :: eval_flow_status_stiff_rescue = 0_int64
      integer(int64) :: eval_flow_status_solver_assist = 0_int64
      integer(int64) :: eval_flow_status_failure_max_steps = 0_int64
      integer(int64) :: eval_flow_status_failure_invalid = 0_int64
      integer(int64) :: eval_flow_status_failure_h_min = 0_int64
      integer(int64) :: eval_flow_status_unknown = 0_int64
      logical :: attempt_capture_policy_loaded = .false.
      logical :: attempt_capture_enabled = .false.
      logical :: attempt_capture_files_ready = .false.
      logical :: attempt_capture_write_error = .false.
      integer :: attempt_capture_limit = 100
      integer :: attempt_capture_stride = 1
      integer :: attempt_capture_seen = 0
      integer :: attempt_capture_count = 0
      integer :: attempt_capture_z0_unit = -1
      integer :: attempt_capture_delz_unit = -1
      integer :: attempt_capture_x0_unit = -1
      integer :: attempt_capture_xi0_unit = -1
      integer :: attempt_capture_meta_unit = -1
      character(len=512) :: attempt_capture_dir = ""
   end type qn_diagnostics_context_t

   type(qn_diagnostics_context_t), target, save :: module_qn_diagnostics_context

   integer, parameter :: qn_backend_official_dfols = 2

   type :: qn_policy_context_t
      logical :: qn_backend_policy_loaded = .false.
      integer :: qn_solver_backend = qn_backend_official_dfols
      logical :: qn_backend_notice_printed = .false.
      logical :: qn_official_dfols_failure_warned = .false.
      integer :: qn_official_dfols_npt = 4
      integer :: qn_official_dfols_maxfun = 250
      logical :: qn_official_dfols_objfun_has_noise = .true.
      real(dp) :: qn_official_dfols_rhobeg = 1.8e-2_dp
      real(dp) :: qn_official_dfols_rhoend = 1.0e-16_dp
      real(dp) :: qn_official_dfols_model_abs_tol = 1.0e-26_dp
      real(dp) :: qn_official_dfols_model_rel_tol = 0.0_dp
      real(dp) :: qn_official_dfols_tr_alpha1 = -1.0_dp
      real(dp) :: qn_official_dfols_tr_alpha2 = -1.0_dp
      real(dp) :: qn_official_dfols_safety_step_thresh = -1.0_dp
   end type qn_policy_context_t

   type(qn_policy_context_t), target, save :: module_qn_policy_context

   type, bind(C) :: qn_official_callback_context_t
      type(c_ptr) :: xt = c_null_ptr
      type(c_ptr) :: z = c_null_ptr
      type(c_ptr) :: del_z = c_null_ptr
      type(c_ptr) :: jac = c_null_ptr
      type(c_ptr) :: flow_workspace = c_null_ptr
      type(c_ptr) :: intode_diagnostics = c_null_ptr
      type(c_ptr) :: qn_context = c_null_ptr
      type(c_ptr) :: qn_diagnostics = c_null_ptr
      type(c_ptr) :: qn_policy = c_null_ptr
      integer(c_int) :: n = 0_c_int
      integer(c_int) :: n_xt = 0_c_int
      integer(c_int) :: n_z = 0_c_int
      integer(c_int) :: n_del_z = 0_c_int
      integer(c_int) :: jac_rows = 0_c_int
      integer(c_int) :: jac_cols = 0_c_int
      integer(c_int) :: has_flow_workspace = 0_c_int
      integer(c_int) :: has_intode_diagnostics = 0_c_int
      integer(c_int) :: has_qn_context = 0_c_int
      integer(c_int) :: has_qn_diagnostics = 0_c_int
      integer(c_int) :: has_qn_policy = 0_c_int
   end type qn_official_callback_context_t

   interface
      integer(c_int) function tltm_official_dfols_solve_c(n, x0, x_out, package_residual_norm, nf, flag, npt, rhobeg, &
                                                          rhoend, maxfun, objfun_has_noise, model_abs_tol, model_rel_tol, &
                                                          tr_alpha1, tr_alpha2, safety_step_thresh, ctx, objfun) &
                                                          bind(C, name="tltm_official_dfols_solve")
         import :: c_double, c_funptr, c_int, c_ptr
         integer(c_int), value :: n, npt, maxfun, objfun_has_noise
         real(c_double), intent(in) :: x0(*)
         real(c_double), intent(out) :: x_out(*)
         real(c_double), intent(out) :: package_residual_norm
         integer(c_int), intent(out) :: nf, flag
         real(c_double), value :: rhobeg, rhoend, model_abs_tol, model_rel_tol
         real(c_double), value :: tr_alpha1, tr_alpha2, safety_step_thresh
         type(c_ptr), value :: ctx
         type(c_funptr), value :: objfun
      end function tltm_official_dfols_solve_c
   end interface

contains

   subroutine resolve_qn_context(qn_context, active_context)
      implicit none
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_context_t), pointer :: active_context

      if (present(qn_context)) then
         active_context => qn_context
      else
         active_context => module_qn_context
      end if
   end subroutine resolve_qn_context

   subroutine resolve_qn_diagnostics(qn_diagnostics, active_diagnostics)
      implicit none
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_diagnostics_context_t), pointer :: active_diagnostics

      if (present(qn_diagnostics)) then
         active_diagnostics => qn_diagnostics
      else
         active_diagnostics => module_qn_diagnostics_context
      end if
   end subroutine resolve_qn_diagnostics

   subroutine resolve_qn_policy(qn_policy, active_policy)
      implicit none
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      type(qn_policy_context_t), pointer :: active_policy

      if (present(qn_policy)) then
         active_policy => qn_policy
      else
         active_policy => module_qn_policy_context
      end if
   end subroutine resolve_qn_policy

   subroutine release_qn_context(context)
      implicit none
      type(qn_context_t), intent(inout) :: context

      if (allocated(context%residual_jlc)) deallocate (context%residual_jlc)
      if (allocated(context%residual_z_trial)) deallocate (context%residual_z_trial)
      if (allocated(context%last_trace_z_proposed)) deallocate (context%last_trace_z_proposed)
      if (allocated(context%last_trace_z_flowed)) deallocate (context%last_trace_z_flowed)
      if (allocated(context%last_trace_res_norm)) deallocate (context%last_trace_res_norm)
      if (allocated(context%last_trace_alpha)) deallocate (context%last_trace_alpha)
      if (allocated(context%last_trace_iter)) deallocate (context%last_trace_iter)
      if (allocated(context%last_trace_backtrack)) deallocate (context%last_trace_backtrack)
      if (allocated(context%last_trace_attempt)) deallocate (context%last_trace_attempt)
      if (allocated(context%last_trace_route)) deallocate (context%last_trace_route)
      if (allocated(context%last_trace_accepted)) deallocate (context%last_trace_accepted)
      if (allocated(context%last_trace_eval_ok)) deallocate (context%last_trace_eval_ok)
      if (allocated(context%eval_z_proposed)) deallocate (context%eval_z_proposed)
      if (allocated(context%eval_z_flowed)) deallocate (context%eval_z_flowed)
      context%trace_iter = 0
      context%last_trace_count = 0
      context%last_trace_capacity = 0
      context%last_trace_dim = 0
      context%eval_has_flowed = .false.
      context%eval_flowed_is_inverse = .false.
      context%trace_route_code = 0
      context%current_attempt_eval_count = 0_int64
   end subroutine release_qn_context

   subroutine release_qn_diagnostics_context(context)
      implicit none
      type(qn_diagnostics_context_t), intent(inout) :: context

      if (context%attempt_capture_z0_unit /= -1) close (context%attempt_capture_z0_unit)
      if (context%attempt_capture_delz_unit /= -1) close (context%attempt_capture_delz_unit)
      if (context%attempt_capture_x0_unit /= -1) close (context%attempt_capture_x0_unit)
      if (context%attempt_capture_xi0_unit /= -1) close (context%attempt_capture_xi0_unit)
      if (context%attempt_capture_meta_unit /= -1) close (context%attempt_capture_meta_unit)
      context%global_filter_candidate_count = 0_int64
      context%global_filter_pass_count = 0_int64
      context%global_filter_reject_count = 0_int64
      context%eval_flow_status_success = 0_int64
      context%eval_flow_status_zero_time = 0_int64
      context%eval_flow_status_stiff_rescue = 0_int64
      context%eval_flow_status_solver_assist = 0_int64
      context%eval_flow_status_failure_max_steps = 0_int64
      context%eval_flow_status_failure_invalid = 0_int64
      context%eval_flow_status_failure_h_min = 0_int64
      context%eval_flow_status_unknown = 0_int64
      context%attempt_capture_policy_loaded = .false.
      context%attempt_capture_enabled = .false.
      context%attempt_capture_files_ready = .false.
      context%attempt_capture_write_error = .false.
      context%attempt_capture_limit = 100
      context%attempt_capture_stride = 1
      context%attempt_capture_seen = 0
      context%attempt_capture_count = 0
      context%attempt_capture_z0_unit = -1
      context%attempt_capture_delz_unit = -1
      context%attempt_capture_x0_unit = -1
      context%attempt_capture_xi0_unit = -1
      context%attempt_capture_meta_unit = -1
      context%attempt_capture_dir = ""
   end subroutine release_qn_diagnostics_context

   subroutine release_qn_policy_context(context)
      implicit none
      type(qn_policy_context_t), intent(inout) :: context

      context%qn_backend_policy_loaded = .false.
      context%qn_solver_backend = qn_backend_official_dfols
      context%qn_backend_notice_printed = .false.
      context%qn_official_dfols_failure_warned = .false.
      context%qn_official_dfols_npt = 4
      context%qn_official_dfols_maxfun = 250
      context%qn_official_dfols_objfun_has_noise = .true.
      context%qn_official_dfols_rhobeg = 1.8e-2_dp
      context%qn_official_dfols_rhoend = 1.0e-16_dp
      context%qn_official_dfols_model_abs_tol = 1.0e-26_dp
      context%qn_official_dfols_model_rel_tol = 0.0_dp
      context%qn_official_dfols_tr_alpha1 = -1.0_dp
      context%qn_official_dfols_tr_alpha2 = -1.0_dp
      context%qn_official_dfols_safety_step_thresh = -1.0_dp
   end subroutine release_qn_policy_context

   subroutine solve_constraint_quasi_newton(f, tol, max_iter, xt, z, del_z, ierr, Jl, x_new, jac, x_seed_override, x_best_solution, &
                                            flow_workspace, qn_context, qn_diagnostics, qn_policy, intode_diagnostics)
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
         subroutine f(xt, z, xi, fq, del_z, ierr, Jl, jac, flow_workspace, qn_context, qn_diagnostics, qn_policy, &
                      intode_diagnostics)
            use, intrinsic :: iso_fortran_env, only: real64
            use solve_flow, only: flow_workspace_t, intode_diagnostics_context_t
            import :: qn_context_t, qn_diagnostics_context_t, qn_policy_context_t
            integer, parameter :: dp = real64
            real(dp), intent(in) :: xt(:), xi(:), del_z(:)
            complex(dp), intent(in) :: z(:), jac(:, :)
            real(dp), intent(out) :: fq(:), Jl(:)
            logical, intent(out) :: ierr
            type(flow_workspace_t), intent(inout), optional :: flow_workspace
            type(qn_context_t), intent(inout), optional, target :: qn_context
            type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
            type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
            type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
         end subroutine f
      end interface
      type(flow_workspace_t), intent(inout), optional, target :: flow_workspace
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      real(dp), parameter :: official_global_filter_trigger_res = 4.3e-3_dp

      integer :: n, attempt_idx
      logical :: converged, stage_converged
      logical :: global_filter_candidate
      real(dp) :: best_res_first, best_res_global
      real(dp), allocatable :: x0_guess(:), x_best_first(:), x_best_global(:), Jl_best_global(:)
      type(qn_context_t), pointer :: active_context
      type(qn_diagnostics_context_t), pointer :: active_diagnostics
      type(qn_policy_context_t), pointer :: active_policy

      n = 2*size(z)
      ierr = .true.
      Jl = 0.0_dp
      if (size(x_new) == size(xt)) x_new = xt
      if (present(x_best_solution)) then
         if (size(x_best_solution) == n) x_best_solution = 0.0_dp
      end if
      if (size(z) <= 0 .or. size(xt) /= size(z) + 1 .or. size(del_z) /= n .or. &
          size(Jl) /= n .or. size(x_new) /= size(xt) .or. &
          size(jac, 1) /= size(z) .or. size(jac, 2) /= size(z) .or. &
          (.not. ieee_is_finite(tol)) .or. tol <= 0.0_dp) return
      call resolve_qn_context(qn_context, active_context)
      call resolve_qn_diagnostics(qn_diagnostics, active_diagnostics)
      call resolve_qn_policy(qn_policy, active_policy)
      allocate (x0_guess(n), x_best_first(n), x_best_global(n), Jl_best_global(n))
      call reset_quasi_last_trace(active_context, size(z))
      call load_qn_backend_policy(active_policy)

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
      x_best_global = x0_guess
      if (max_iter > 32) global_filter_candidate = .true.
      Jl_best_global = 0.0_dp

      attempt_idx = 1
      active_context%trace_route_code = 10
      call run_official_dfols_attempt(tol, attempt_idx, xt, z, del_z, jac, x0_guess, stage_converged, Jl, x_new, &
                                      x_best_out=x_best_first, best_res_out=best_res_first, flow_workspace=flow_workspace, &
                                      qn_context=active_context, qn_diagnostics=active_diagnostics, qn_policy=active_policy, &
                                      intode_diagnostics=intode_diagnostics)
      best_res_global = best_res_first
      Jl_best_global = Jl
      x_best_global = x_best_first
      converged = stage_converged

      if ((.not. converged) .and. ieee_is_finite(best_res_global) .and. &
          best_res_global <= official_global_filter_trigger_res) then
         global_filter_candidate = .true.
      end if

      if ((.not. converged) .and. residual_within_accept_tolerance(best_res_global, tol)) then
         active_context%trace_route_code = 90
         call certify_candidate_if_within_tol(xt, z, del_z, jac, tol, x_best_global, Jl_best_global, best_res_global, x_new, Jl, &
                                              converged, flow_workspace, active_context, active_diagnostics, active_policy, &
                                              intode_diagnostics)
      end if
      if (global_filter_candidate) then
         call record_quasi_global_filter(active_diagnostics, converged)
      end if
      if (.not. converged) then
         x_new = xt
         Jl = Jl_best_global
      end if

      ierr = .not. converged
      if (present(x_best_solution)) then
         if (size(x_best_solution) == n) x_best_solution = x_best_global
      end if
      deallocate (x0_guess, x_best_first, x_best_global, Jl_best_global)
   end subroutine solve_constraint_quasi_newton

   subroutine record_quasi_global_filter(qn_diagnostics, local_success)
      implicit none
      type(qn_diagnostics_context_t), intent(inout) :: qn_diagnostics
      logical, intent(in) :: local_success

      qn_diagnostics%global_filter_candidate_count = qn_diagnostics%global_filter_candidate_count + 1_int64
      if (local_success) then
         qn_diagnostics%global_filter_pass_count = qn_diagnostics%global_filter_pass_count + 1_int64
      else
         qn_diagnostics%global_filter_reject_count = qn_diagnostics%global_filter_reject_count + 1_int64
      end if
   end subroutine record_quasi_global_filter

   subroutine run_official_dfols_attempt(tol, attempt_idx, xt, z, del_z, jac, x_init, converged, Jl, x_new, &
                                         x_best_out, best_res_out, flow_workspace, qn_context, qn_diagnostics, qn_policy, &
                                         intode_diagnostics)
      implicit none
      integer, intent(in) :: attempt_idx
      real(dp), intent(in) :: tol
      real(dp), intent(in), target :: xt(:), del_z(:)
      real(dp), intent(in) :: x_init(:)
      complex(dp), intent(in), target :: z(:), jac(:, :)
      logical, intent(out) :: converged
      real(dp), intent(out) :: Jl(:), x_new(:)
      real(dp), intent(out), optional :: x_best_out(:)
      real(dp), intent(out), optional :: best_res_out
      type(flow_workspace_t), intent(inout), optional, target :: flow_workspace
      type(qn_context_t), intent(inout), target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), target :: qn_policy
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      integer :: n, i
      integer(c_int) :: c_status, c_n, c_nf, c_flag, c_objfun_has_noise
      real(c_double) :: c_package_residual_norm
      real(dp) :: initial_r_norm, final_r_norm, best_r_norm, attempt_cpu_start, attempt_cpu_seconds
      logical :: eval_error, initial_eval_ok
      real(dp), allocatable :: x_seed(:), x_solution(:), x_best(:), r(:), Jl_eval(:), Jl_best(:)
      real(c_double), allocatable :: x0_c(:), x_solution_c(:)
      type(qn_official_callback_context_t), target :: callback_context

      n = 2*size(z)
      converged = .false.
      Jl = 0.0_dp
      if (size(x_new) == size(xt)) x_new = xt
      if (size(x_new) /= size(xt) .or. size(Jl) /= size(del_z)) return

      allocate (x_seed(n), x_solution(n), x_best(n), r(n), Jl_eval(n), Jl_best(n), x0_c(n), x_solution_c(n))
      if (size(x_init) == n) then
         x_seed = x_init
      else
         x_seed = 0.0_dp
      end if
      x_solution = x_seed
      x_best = x_seed
      Jl = 0.0_dp
      Jl_eval = 0.0_dp
      Jl_best = 0.0_dp
      initial_r_norm = huge(1.0_dp)
      final_r_norm = huge(1.0_dp)
      best_r_norm = huge(1.0_dp)
      initial_eval_ok = .false.
      qn_context%current_attempt_eval_count = 0_int64
      qn_context%trace_iter = 0
      call cpu_time(attempt_cpu_start)

      call count_qn_attempt_eval(qn_context)
      call evaluate_constraint_residual(xt, z, x_seed, r, del_z, eval_error, Jl_eval, jac, flow_workspace, qn_context, &
                                        qn_diagnostics, qn_policy, intode_diagnostics)
      if (eval_error .or. .not. real_vector_is_finite(r)) then
         x_seed = 0.0_dp
         qn_context%trace_iter = 0
         call count_qn_attempt_eval(qn_context)
         call evaluate_constraint_residual(xt, z, x_seed, r, del_z, eval_error, Jl_eval, jac, flow_workspace, qn_context, &
                                           qn_diagnostics, qn_policy, intode_diagnostics)
      end if
      if (eval_error .or. .not. real_vector_is_finite(r)) then
         call append_quasi_trace_sample(qn_context, qn_policy, 0.0_dp, 0, 0, attempt_idx, huge(1.0_dp), .false., .false.)
         attempt_cpu_seconds = qn_attempt_elapsed_seconds(attempt_cpu_start)
         call capture_qn_attempt(xt, z, del_z, x_seed, attempt_idx, qn_policy%qn_official_dfols_maxfun, tol, &
                                 huge(1.0_dp), huge(1.0_dp), .false., .false., &
                                 qn_context%current_attempt_eval_count, attempt_cpu_seconds, qn_diagnostics)
         deallocate (x_seed, x_solution, x_best, r, Jl_eval, Jl_best, x0_c, x_solution_c)
         return
      end if

      initial_eval_ok = .true.
      initial_r_norm = norm2(r)
      if (ieee_is_finite(initial_r_norm)) then
         best_r_norm = initial_r_norm
         x_best = x_seed
         Jl_best = Jl_eval
      end if
      call append_quasi_trace_sample(qn_context, qn_policy, 0.0_dp, 0, 0, attempt_idx, initial_r_norm, &
                                     residual_within_accept_tolerance(initial_r_norm, tol), .true.)

      if (residual_within_accept_tolerance(best_r_norm, tol)) then
         call certify_candidate_if_within_tol(xt, z, del_z, jac, tol, x_best, Jl_best, best_r_norm, x_new, Jl, converged, &
                                              flow_workspace, qn_context, qn_diagnostics, qn_policy, intode_diagnostics)
         if (.not. converged) x_new = xt
         if (present(x_best_out)) then
            if (size(x_best_out) == size(x_best)) x_best_out = x_best
         end if
         if (present(best_res_out)) best_res_out = best_r_norm
         attempt_cpu_seconds = qn_attempt_elapsed_seconds(attempt_cpu_start)
         call capture_qn_attempt(xt, z, del_z, x_seed, attempt_idx, qn_policy%qn_official_dfols_maxfun, tol, &
                                 initial_r_norm, best_r_norm, converged, initial_eval_ok, &
                                 qn_context%current_attempt_eval_count, attempt_cpu_seconds, qn_diagnostics)
         deallocate (x_seed, x_solution, x_best, r, Jl_eval, Jl_best, x0_c, x_solution_c)
         return
      end if

      call initialize_qn_official_callback_context(callback_context, xt, z, del_z, jac, flow_workspace, qn_context, qn_diagnostics, &
                                                  qn_policy, intode_diagnostics)
      do i = 1, n
         x0_c(i) = real(x_seed(i), c_double)
         x_solution_c(i) = real(x_seed(i), c_double)
      end do
      c_n = int(n, c_int)
      if (qn_policy%qn_official_dfols_objfun_has_noise) then
         c_objfun_has_noise = 1_c_int
      else
         c_objfun_has_noise = 0_c_int
      end if
      c_status = tltm_official_dfols_solve_c(c_n, x0_c, x_solution_c, c_package_residual_norm, c_nf, c_flag, &
                                             int(qn_policy%qn_official_dfols_npt, c_int), qn_policy%qn_official_dfols_rhobeg, &
                                             qn_policy%qn_official_dfols_rhoend, int(qn_policy%qn_official_dfols_maxfun, c_int), &
                                             c_objfun_has_noise, qn_policy%qn_official_dfols_model_abs_tol, &
                                             qn_policy%qn_official_dfols_model_rel_tol, qn_policy%qn_official_dfols_tr_alpha1, &
                                             qn_policy%qn_official_dfols_tr_alpha2, &
                                             qn_policy%qn_official_dfols_safety_step_thresh, &
                                             c_loc(callback_context), c_funloc(qn_official_dfols_eval_callback))
      call clear_qn_official_callback_context(callback_context)

      if (c_status /= 0_c_int) then
         call warn_official_dfols_failure(qn_policy, int(c_status), int(c_flag))
         call append_quasi_trace_sample(qn_context, qn_policy, 0.0_dp, 0, int(c_status), attempt_idx, huge(1.0_dp), .false., .false.)
      else
         do i = 1, n
            x_solution(i) = real(x_solution_c(i), dp)
         end do
         if (real_vector_is_finite(x_solution)) then
            qn_context%trace_iter = 0
            call count_qn_attempt_eval(qn_context)
            call evaluate_constraint_residual(xt, z, x_solution, r, del_z, eval_error, Jl_eval, jac, flow_workspace, qn_context, &
                                              qn_diagnostics, qn_policy, intode_diagnostics)
            if (.not. eval_error .and. real_vector_is_finite(r)) then
               final_r_norm = norm2(r)
               call append_quasi_trace_sample(qn_context, qn_policy, 1.0_dp, 0, int(c_nf), attempt_idx, final_r_norm, &
                                              residual_within_accept_tolerance(final_r_norm, tol), .true.)
               if (ieee_is_finite(final_r_norm) .and. final_r_norm < best_r_norm) then
                  best_r_norm = final_r_norm
                  x_best = x_solution
                  Jl_best = Jl_eval
               end if
            else
               call append_quasi_trace_sample(qn_context, qn_policy, 1.0_dp, 0, int(c_nf), attempt_idx, huge(1.0_dp), &
                                              .false., .false.)
            end if
         else
            call append_quasi_trace_sample(qn_context, qn_policy, 1.0_dp, 0, int(c_nf), attempt_idx, huge(1.0_dp), &
                                           .false., .false.)
         end if
      end if

      call certify_candidate_if_within_tol(xt, z, del_z, jac, tol, x_best, Jl_best, best_r_norm, x_new, Jl, converged, flow_workspace, &
                                           qn_context, qn_diagnostics, qn_policy, intode_diagnostics)
      if (.not. converged) then
         x_new = xt
         if (size(Jl_best) == size(Jl)) Jl = Jl_best
      end if
      if (present(x_best_out)) then
         if (size(x_best_out) == size(x_best)) x_best_out = x_best
      end if
      if (present(best_res_out)) best_res_out = best_r_norm
      attempt_cpu_seconds = qn_attempt_elapsed_seconds(attempt_cpu_start)
      call capture_qn_attempt(xt, z, del_z, x_seed, attempt_idx, qn_policy%qn_official_dfols_maxfun, tol, &
                              initial_r_norm, best_r_norm, converged, initial_eval_ok, &
                              qn_context%current_attempt_eval_count, attempt_cpu_seconds, qn_diagnostics)

      deallocate (x_seed, x_solution, x_best, r, Jl_eval, Jl_best, x0_c, x_solution_c)
   end subroutine run_official_dfols_attempt

   integer(c_int) function qn_official_dfols_eval_callback(ctx, n_c, x_c, r_c) bind(C) result(status)
      implicit none
      type(c_ptr), value :: ctx
      integer(c_int), value :: n_c
      real(c_double), intent(in) :: x_c(*)
      real(c_double), intent(out) :: r_c(*)

      type(qn_official_callback_context_t), pointer :: callback_context
      real(dp), pointer :: xt_ptr(:), del_z_ptr(:)
      complex(dp), pointer :: z_ptr(:), jac_ptr(:, :)
      type(flow_workspace_t), pointer :: flow_workspace_ptr
      type(intode_diagnostics_context_t), pointer :: intode_diagnostics_ptr
      type(qn_context_t), pointer :: qn_context_ptr
      type(qn_diagnostics_context_t), pointer :: qn_diagnostics_ptr
      type(qn_policy_context_t), pointer :: qn_policy_ptr
      integer :: n, i
      logical :: eval_error
      real(dp), allocatable :: xi(:), fq(:), jl(:)

      status = 1_c_int
      n = int(n_c)
      if (.not. c_associated(ctx)) return
      if (n <= 0) return
      call c_f_pointer(ctx, callback_context)
      if (.not. associated(callback_context)) return
      if (int(callback_context%n) /= n) return
      if (int(callback_context%n_del_z) /= n) return
      if (.not. c_associated(callback_context%xt)) return
      if (.not. c_associated(callback_context%z)) return
      if (.not. c_associated(callback_context%del_z)) return
      if (.not. c_associated(callback_context%jac)) return
      if (callback_context%n_xt <= 0_c_int .or. callback_context%n_z <= 0_c_int) return
      if (callback_context%jac_rows <= 0_c_int .or. callback_context%jac_cols <= 0_c_int) return
      call c_f_pointer(callback_context%xt, xt_ptr, [int(callback_context%n_xt)])
      call c_f_pointer(callback_context%z, z_ptr, [int(callback_context%n_z)])
      call c_f_pointer(callback_context%del_z, del_z_ptr, [int(callback_context%n_del_z)])
      call c_f_pointer(callback_context%jac, jac_ptr, [int(callback_context%jac_rows), int(callback_context%jac_cols)])
      allocate (xi(n), fq(n), jl(n))

      do i = 1, n
         xi(i) = real(x_c(i), dp)
      end do
      if (.not. real_vector_is_finite(xi)) goto 100

      if (callback_context%has_qn_context /= 0_c_int .and. c_associated(callback_context%qn_context)) then
         call c_f_pointer(callback_context%qn_context, qn_context_ptr)
      else
         qn_context_ptr => module_qn_context
      end if
      if (callback_context%has_qn_diagnostics /= 0_c_int .and. c_associated(callback_context%qn_diagnostics)) then
         call c_f_pointer(callback_context%qn_diagnostics, qn_diagnostics_ptr)
      else
         qn_diagnostics_ptr => module_qn_diagnostics_context
      end if
      if (callback_context%has_qn_policy /= 0_c_int .and. c_associated(callback_context%qn_policy)) then
         call c_f_pointer(callback_context%qn_policy, qn_policy_ptr)
      else
         qn_policy_ptr => module_qn_policy_context
      end if
      nullify (intode_diagnostics_ptr)
      if (callback_context%has_intode_diagnostics /= 0_c_int .and. c_associated(callback_context%intode_diagnostics)) then
         call c_f_pointer(callback_context%intode_diagnostics, intode_diagnostics_ptr)
      end if
      qn_context_ptr%trace_iter = 0
      call count_qn_attempt_eval(qn_context_ptr)
      if (callback_context%has_flow_workspace /= 0_c_int .and. c_associated(callback_context%flow_workspace)) then
         call c_f_pointer(callback_context%flow_workspace, flow_workspace_ptr)
         if (associated(intode_diagnostics_ptr)) then
            call evaluate_constraint_residual(xt_ptr, z_ptr, xi, fq, del_z_ptr, eval_error, jl, jac_ptr, flow_workspace_ptr, &
                                              qn_context_ptr, qn_diagnostics_ptr, qn_policy_ptr, intode_diagnostics_ptr)
         else
            call evaluate_constraint_residual(xt_ptr, z_ptr, xi, fq, del_z_ptr, eval_error, jl, jac_ptr, flow_workspace_ptr, &
                                              qn_context_ptr, qn_diagnostics_ptr, qn_policy_ptr)
         end if
      else
         if (associated(intode_diagnostics_ptr)) then
            call evaluate_constraint_residual(xt_ptr, z_ptr, xi, fq, del_z_ptr, eval_error, jl, jac_ptr, qn_context=qn_context_ptr, &
                                              qn_diagnostics=qn_diagnostics_ptr, qn_policy=qn_policy_ptr, &
                                              intode_diagnostics=intode_diagnostics_ptr)
         else
            call evaluate_constraint_residual(xt_ptr, z_ptr, xi, fq, del_z_ptr, eval_error, jl, jac_ptr, qn_context=qn_context_ptr, &
                                              qn_diagnostics=qn_diagnostics_ptr, qn_policy=qn_policy_ptr)
         end if
      end if
      if (eval_error .or. .not. real_vector_is_finite(fq)) goto 100

      do i = 1, n
         r_c(i) = real(fq(i), c_double)
      end do
      status = 0_c_int

100   continue
      if (allocated(xi)) deallocate (xi)
      if (allocated(fq)) deallocate (fq)
      if (allocated(jl)) deallocate (jl)
   end function qn_official_dfols_eval_callback

   subroutine initialize_qn_official_callback_context(context, xt, z, del_z, jac, flow_workspace, qn_context, qn_diagnostics, &
                                                     qn_policy, intode_diagnostics)
      implicit none
      type(qn_official_callback_context_t), intent(out) :: context
      real(dp), intent(in), target :: xt(:), del_z(:)
      complex(dp), intent(in), target :: z(:), jac(:, :)
      type(flow_workspace_t), intent(inout), optional, target :: flow_workspace
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      context%xt = c_loc(xt(1))
      context%z = c_loc(z(1))
      context%del_z = c_loc(del_z(1))
      context%jac = c_loc(jac(1, 1))
      context%n = int(size(del_z), c_int)
      context%n_xt = int(size(xt), c_int)
      context%n_z = int(size(z), c_int)
      context%n_del_z = int(size(del_z), c_int)
      context%jac_rows = int(size(jac, 1), c_int)
      context%jac_cols = int(size(jac, 2), c_int)
      if (present(flow_workspace)) then
         context%flow_workspace = c_loc(flow_workspace)
         context%has_flow_workspace = 1_c_int
      else
         context%flow_workspace = c_null_ptr
         context%has_flow_workspace = 0_c_int
      end if
      if (present(intode_diagnostics)) then
         context%intode_diagnostics = c_loc(intode_diagnostics)
         context%has_intode_diagnostics = 1_c_int
      else
         context%intode_diagnostics = c_null_ptr
         context%has_intode_diagnostics = 0_c_int
      end if
      if (present(qn_context)) then
         context%qn_context = c_loc(qn_context)
         context%has_qn_context = 1_c_int
      else
         context%qn_context = c_null_ptr
         context%has_qn_context = 0_c_int
      end if
      if (present(qn_diagnostics)) then
         context%qn_diagnostics = c_loc(qn_diagnostics)
         context%has_qn_diagnostics = 1_c_int
      else
         context%qn_diagnostics = c_null_ptr
         context%has_qn_diagnostics = 0_c_int
      end if
      if (present(qn_policy)) then
         context%qn_policy = c_loc(qn_policy)
         context%has_qn_policy = 1_c_int
      else
         context%qn_policy = c_null_ptr
         context%has_qn_policy = 0_c_int
      end if
   end subroutine initialize_qn_official_callback_context

   subroutine clear_qn_official_callback_context(context)
      implicit none
      type(qn_official_callback_context_t), intent(inout) :: context

      context%xt = c_null_ptr
      context%z = c_null_ptr
      context%del_z = c_null_ptr
      context%jac = c_null_ptr
      context%flow_workspace = c_null_ptr
      context%intode_diagnostics = c_null_ptr
      context%qn_context = c_null_ptr
      context%qn_diagnostics = c_null_ptr
      context%qn_policy = c_null_ptr
      context%n = 0_c_int
      context%n_xt = 0_c_int
      context%n_z = 0_c_int
      context%n_del_z = 0_c_int
      context%jac_rows = 0_c_int
      context%jac_cols = 0_c_int
      context%has_flow_workspace = 0_c_int
      context%has_intode_diagnostics = 0_c_int
      context%has_qn_context = 0_c_int
      context%has_qn_diagnostics = 0_c_int
      context%has_qn_policy = 0_c_int
   end subroutine clear_qn_official_callback_context

   subroutine warn_official_dfols_failure(qn_policy, status, flag)
      implicit none
      type(qn_policy_context_t), intent(inout) :: qn_policy
      integer, intent(in) :: status, flag

      if (qn_policy%qn_official_dfols_failure_warned) return
      qn_policy%qn_official_dfols_failure_warned = .true.
      write (*, '(A,I0,A,I0,A)') "[WARN] Official DFO-LS bridge failed: status=", status, &
         " flag=", flag, "; QN attempt will be rejected without internal fallback."
   end subroutine warn_official_dfols_failure

   subroutine recover_converged_flowed_state(xt, z, del_z, Jl, z_flowed, eval_error, flow_workspace, qn_context, qn_policy, &
                                             intode_diagnostics)
      implicit none
      real(dp), intent(in) :: xt(:), del_z(:), Jl(:)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(out) :: z_flowed(:)
      logical, intent(out) :: eval_error
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(qn_context_t), intent(inout), target :: qn_context
      type(qn_policy_context_t), intent(inout), target :: qn_policy
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      complex(dp) :: z_trial(size(z))

      if (size(z_flowed) /= size(z) .or. size(del_z) /= size(Jl)) then
         eval_error = .true.
         return
      end if

      if (qn_context%eval_has_flowed .and. qn_context%eval_flowed_is_inverse) then
         if (allocated(qn_context%eval_z_flowed)) then
            if (size(qn_context%eval_z_flowed) >= size(z)) then
               z_flowed = qn_context%eval_z_flowed(1:size(z))
               eval_error = .false.
               return
            end if
         end if
      end if

      call real_to_complex(del_z + Jl, z_trial)
      z_trial = z + z_trial
      call set_intode_residual_role_trace(intode_role_certification, flow_workspace)
      call flowzr(xt, z_trial, eval_error, workspace=flow_workspace, intode_diagnostics=intode_diagnostics)
      if (.not. eval_error) z_flowed = z_trial
   end subroutine recover_converged_flowed_state

   subroutine certify_candidate_if_within_tol(xt, z, del_z, jac, tol, xi_best, Jl_best, best_fx_norm, x_new, Jl, converged, &
                                              flow_workspace, qn_context, qn_diagnostics, qn_policy, intode_diagnostics)
      implicit none
      real(dp), intent(in) :: xt(:), del_z(:), tol, xi_best(:), Jl_best(:), best_fx_norm
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(inout) :: x_new(:), Jl(:)
      logical, intent(out) :: converged
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(qn_context_t), intent(inout), target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), target :: qn_policy
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      logical :: eval_error
      real(dp) :: cert_norm
      real(dp) :: cert_res(size(del_z)), cert_jl(size(Jl))
      complex(dp) :: z_new(size(z))

      converged = .false.
      if (.not. residual_within_accept_tolerance(best_fx_norm, tol)) return
      if (size(xi_best) /= size(del_z) .or. size(Jl_best) /= size(Jl)) return

      call evaluate_constraint_residual_certification(xt, z, xi_best, cert_res, del_z, eval_error, cert_jl, jac, flow_workspace, &
                                                      qn_context, qn_diagnostics, qn_policy, intode_diagnostics)
      if (eval_error .or. .not. real_vector_is_finite(cert_res)) return
      cert_norm = norm2(cert_res)
      if (.not. residual_within_accept_tolerance(cert_norm, tol)) return

      Jl = cert_jl
      call recover_converged_flowed_state(xt, z, del_z, Jl, z_new, eval_error, flow_workspace, qn_context, qn_policy, &
                                          intode_diagnostics)
      if (eval_error) then
         converged = .false.
         return
      end if
      x_new = xt
      x_new(2:) = real(z_new, dp)
      converged = .true.
   end subroutine certify_candidate_if_within_tol

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

   subroutine mark_constraint_eval_invalid(fq, Jl, ierr, qn_context)
      implicit none
      real(dp), intent(out) :: fq(:), Jl(:)
      logical, intent(out) :: ierr
      type(qn_context_t), intent(inout) :: qn_context

      ! Invalid flow evaluations are signaled by ierr, not by an artificial
      ! large residual that could pollute trust-region or line-search state.
      fq = 0.0_dp
      Jl = 0.0_dp
      ierr = .true.
      qn_context%eval_has_flowed = .false.
      qn_context%eval_flowed_is_inverse = .false.
   end subroutine mark_constraint_eval_invalid

   subroutine reset_quasi_eval_flow_status_counts(qn_diagnostics)
      implicit none
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_qn_diagnostics(qn_diagnostics, active_diagnostics)
      active_diagnostics%eval_flow_status_success = 0_int64
      active_diagnostics%eval_flow_status_zero_time = 0_int64
      active_diagnostics%eval_flow_status_stiff_rescue = 0_int64
      active_diagnostics%eval_flow_status_solver_assist = 0_int64
      active_diagnostics%eval_flow_status_failure_max_steps = 0_int64
      active_diagnostics%eval_flow_status_failure_invalid = 0_int64
      active_diagnostics%eval_flow_status_failure_h_min = 0_int64
      active_diagnostics%eval_flow_status_unknown = 0_int64
   end subroutine reset_quasi_eval_flow_status_counts

   subroutine get_quasi_eval_flow_status_counts(success, zero_time, stiff_rescue, solver_assist, &
                                                failure_max_steps, failure_invalid, failure_h_min, unknown, qn_diagnostics)
      implicit none
      integer(int64), intent(out) :: success, zero_time, stiff_rescue, solver_assist
      integer(int64), intent(out) :: failure_max_steps, failure_invalid, failure_h_min, unknown
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_qn_diagnostics(qn_diagnostics, active_diagnostics)
      success = active_diagnostics%eval_flow_status_success
      zero_time = active_diagnostics%eval_flow_status_zero_time
      stiff_rescue = active_diagnostics%eval_flow_status_stiff_rescue
      solver_assist = active_diagnostics%eval_flow_status_solver_assist
      failure_max_steps = active_diagnostics%eval_flow_status_failure_max_steps
      failure_invalid = active_diagnostics%eval_flow_status_failure_invalid
      failure_h_min = active_diagnostics%eval_flow_status_failure_h_min
      unknown = active_diagnostics%eval_flow_status_unknown
   end subroutine get_quasi_eval_flow_status_counts

   subroutine record_quasi_eval_flow_status(qn_diagnostics, flow_status)
      implicit none
      type(qn_diagnostics_context_t), intent(inout) :: qn_diagnostics
      integer, intent(in) :: flow_status

      select case (flow_status)
      case (intode_status_success)
         qn_diagnostics%eval_flow_status_success = qn_diagnostics%eval_flow_status_success + 1_int64
      case (intode_status_success_zero_time)
         qn_diagnostics%eval_flow_status_zero_time = qn_diagnostics%eval_flow_status_zero_time + 1_int64
      case (intode_status_success_stiff_rescue)
         qn_diagnostics%eval_flow_status_stiff_rescue = qn_diagnostics%eval_flow_status_stiff_rescue + 1_int64
      case (intode_status_success_solver_assist)
         qn_diagnostics%eval_flow_status_solver_assist = qn_diagnostics%eval_flow_status_solver_assist + 1_int64
      case (intode_status_failure_max_steps)
         qn_diagnostics%eval_flow_status_failure_max_steps = qn_diagnostics%eval_flow_status_failure_max_steps + 1_int64
      case (intode_status_failure_invalid)
         qn_diagnostics%eval_flow_status_failure_invalid = qn_diagnostics%eval_flow_status_failure_invalid + 1_int64
      case (intode_status_failure_h_min)
         qn_diagnostics%eval_flow_status_failure_h_min = qn_diagnostics%eval_flow_status_failure_h_min + 1_int64
      case default
         qn_diagnostics%eval_flow_status_unknown = qn_diagnostics%eval_flow_status_unknown + 1_int64
      end select
   end subroutine record_quasi_eval_flow_status

   subroutine evaluate_constraint_residual(xt, z, xi, fq, del_z, ierr, Jl, jac, flow_workspace, qn_context, qn_diagnostics, qn_policy, &
                                           intode_diagnostics)
      implicit none
      real(dp), intent(in) :: xt(:), xi(:), del_z(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: fq(:), Jl(:)
      logical, intent(out) :: ierr
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      call evaluate_constraint_residual_with_role(xt, z, xi, fq, del_z, ierr, Jl, jac, intode_role_qn_navigation, &
                                                  flow_workspace, qn_context, qn_diagnostics, qn_policy, intode_diagnostics)
   end subroutine evaluate_constraint_residual

   subroutine evaluate_constraint_residual_certification(xt, z, xi, fq, del_z, ierr, Jl, jac, flow_workspace, qn_context, &
                                                        qn_diagnostics, qn_policy, intode_diagnostics)
      implicit none
      real(dp), intent(in) :: xt(:), xi(:), del_z(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: fq(:), Jl(:)
      logical, intent(out) :: ierr
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      call evaluate_constraint_residual_with_role(xt, z, xi, fq, del_z, ierr, Jl, jac, intode_role_certification, &
                                                  flow_workspace, qn_context, qn_diagnostics, qn_policy, intode_diagnostics)
   end subroutine evaluate_constraint_residual_certification

   subroutine evaluate_constraint_residual_with_role(xt, z, xi, fq, del_z, ierr, Jl, jac, residual_role, flow_workspace, qn_context, &
                                                     qn_diagnostics, qn_policy, intode_diagnostics)
      implicit none
      real(dp), intent(in) :: xt(:), xi(:), del_z(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(out) :: fq(:), Jl(:)
      logical, intent(out) :: ierr
      integer, intent(in) :: residual_role
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      integer :: flow_status, n, active_role, prior_role
      type(qn_context_t), pointer :: active_context
      type(qn_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_qn_context(qn_context, active_context)
      call resolve_qn_diagnostics(qn_diagnostics, active_diagnostics)
      n = size(z)
      if (size(xt) /= n + 1 .or. size(xi) /= 2*n .or. size(del_z) /= 2*n .or. size(fq) /= 2*n .or. size(Jl) /= 2*n .or. &
          size(jac, 1) /= n .or. size(jac, 2) /= n) then
         call mark_constraint_eval_invalid(fq, Jl, ierr, active_context)
         return
      end if

      call ensure_complex_workspace(active_context%residual_jlc, n)
      call ensure_complex_workspace(active_context%residual_z_trial, n)

      ! BTN paper variables: xi(1:n)=b, xi(n+1:2*n)=a, ztrial = ztilde - J*(a+i*b).
      active_context%residual_jlc(1:n) = -matmul(jac, xi(n + 1:) + cmplx(0.0_dp, 1.0_dp, dp)*xi(1:n))
      call complex_to_real(active_context%residual_jlc(1:n), Jl)

      call real_to_complex(del_z, active_context%residual_z_trial(1:n))
      active_context%residual_z_trial(1:n) = z + active_context%residual_z_trial(1:n) + active_context%residual_jlc(1:n)
      call ensure_complex_workspace(active_context%eval_z_proposed, n)
      call ensure_complex_workspace(active_context%eval_z_flowed, n)
      active_context%eval_z_proposed(1:n) = active_context%residual_z_trial(1:n)
      active_context%eval_has_flowed = .false.
      active_context%eval_flowed_is_inverse = .false.

      active_role = residual_role
      call get_intode_residual_role_trace(prior_role, flow_workspace)
      if (residual_role == intode_role_qn_navigation .and. prior_role == intode_role_reverse_replay) then
         active_role = intode_role_reverse_replay
      end if
      call set_intode_stage_trace(intode_stage_quasi, flow_workspace)
      call set_intode_residual_role_trace(active_role, flow_workspace)
      call set_intode_quasi_iter_trace(active_context%trace_iter, flow_workspace)
      flow_status = intode_status_unknown
      call flowzr(xt, active_context%residual_z_trial, ierr, flow_status, flow_workspace, intode_diagnostics)
      call record_quasi_eval_flow_status(active_diagnostics, flow_status)
      if (ierr) then
         call mark_constraint_eval_invalid(fq, Jl, ierr, active_context)
         return
      end if
      active_context%eval_z_flowed(1:n) = active_context%residual_z_trial(1:n)
      active_context%eval_has_flowed = .true.
      active_context%eval_flowed_is_inverse = .true.

      fq(1:n) = aimag(active_context%residual_z_trial)
      fq(n + 1:) = xi(n + 1:)
   end subroutine evaluate_constraint_residual_with_role

   subroutine get_quasi_newton_last_trace_r2c(available, proposal_count, z_proposed, z_flowed, residual_norm, alpha, &
                                              iter_idx, backtrack_idx, attempt_idx, accepted, eval_ok, route_code, qn_context)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: proposal_count
      complex(dp), allocatable, intent(out) :: z_proposed(:), z_flowed(:)
      real(dp), allocatable, intent(out) :: residual_norm(:), alpha(:)
      integer, allocatable, intent(out) :: iter_idx(:), backtrack_idx(:), attempt_idx(:)
      integer, allocatable, intent(out), optional :: route_code(:)
      logical, allocatable, intent(out) :: accepted(:), eval_ok(:)
      type(qn_context_t), intent(inout), optional, target :: qn_context
      type(qn_context_t), pointer :: active_context

      call resolve_qn_context(qn_context, active_context)
      available = (active_context%last_trace_dim == 1 .and. active_context%last_trace_count > 0)
      proposal_count = active_context%last_trace_count
      if (.not. available) return

      allocate (z_proposed(proposal_count), z_flowed(proposal_count), residual_norm(proposal_count), alpha(proposal_count), &
                iter_idx(proposal_count), backtrack_idx(proposal_count), attempt_idx(proposal_count), &
                accepted(proposal_count), eval_ok(proposal_count))
      z_proposed = active_context%last_trace_z_proposed(1, 1:proposal_count)
      z_flowed = active_context%last_trace_z_flowed(1, 1:proposal_count)
      residual_norm = active_context%last_trace_res_norm(1:proposal_count)
      alpha = active_context%last_trace_alpha(1:proposal_count)
      iter_idx = active_context%last_trace_iter(1:proposal_count)
      backtrack_idx = active_context%last_trace_backtrack(1:proposal_count)
      attempt_idx = active_context%last_trace_attempt(1:proposal_count)
      if (present(route_code)) then
         allocate (route_code(proposal_count))
         route_code = active_context%last_trace_route(1:proposal_count)
      end if
      accepted = active_context%last_trace_accepted(1:proposal_count)
      eval_ok = active_context%last_trace_eval_ok(1:proposal_count)
   end subroutine get_quasi_newton_last_trace_r2c

   subroutine get_quasi_newton_last_trace_meta(available, trace_dim, proposal_count, residual_norm, alpha, iter_idx, backtrack_idx, &
                                               attempt_idx, accepted, eval_ok, route_code, qn_context)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: trace_dim, proposal_count
      real(dp), allocatable, intent(out) :: residual_norm(:), alpha(:)
      integer, allocatable, intent(out) :: iter_idx(:), backtrack_idx(:), attempt_idx(:), route_code(:)
      logical, allocatable, intent(out) :: accepted(:), eval_ok(:)
      type(qn_context_t), intent(inout), optional, target :: qn_context

      type(qn_context_t), pointer :: active_context

      call resolve_qn_context(qn_context, active_context)
      trace_dim = active_context%last_trace_dim
      proposal_count = active_context%last_trace_count
      available = (trace_dim > 0 .and. proposal_count > 0)
      allocate (residual_norm(proposal_count), alpha(proposal_count), iter_idx(proposal_count), &
                backtrack_idx(proposal_count), attempt_idx(proposal_count), route_code(proposal_count), &
                accepted(proposal_count), eval_ok(proposal_count))
      if (proposal_count <= 0) return
      residual_norm = active_context%last_trace_res_norm(1:proposal_count)
      alpha = active_context%last_trace_alpha(1:proposal_count)
      iter_idx = active_context%last_trace_iter(1:proposal_count)
      backtrack_idx = active_context%last_trace_backtrack(1:proposal_count)
      attempt_idx = active_context%last_trace_attempt(1:proposal_count)
      route_code = active_context%last_trace_route(1:proposal_count)
      accepted = active_context%last_trace_accepted(1:proposal_count)
      eval_ok = active_context%last_trace_eval_ok(1:proposal_count)
   end subroutine get_quasi_newton_last_trace_meta

   subroutine get_quasi_newton_last_trace_stats(available, proposal_count, first_res_norm, best_res_norm, last_res_norm, all_eval_ok, &
                                                valid_eval_count, valid_eval_fraction, qn_context)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: proposal_count
      real(dp), intent(out) :: first_res_norm, best_res_norm, last_res_norm
      logical, intent(out) :: all_eval_ok
      integer, intent(out) :: valid_eval_count
      real(dp), intent(out) :: valid_eval_fraction
      type(qn_context_t), intent(inout), optional, target :: qn_context

      integer :: i, last_attempt, n_used
      real(dp) :: r
      type(qn_context_t), pointer :: active_context

      call resolve_qn_context(qn_context, active_context)
      available = (active_context%last_trace_count > 0)
      proposal_count = 0
      first_res_norm = huge(1.0_dp)
      best_res_norm = huge(1.0_dp)
      last_res_norm = huge(1.0_dp)
      all_eval_ok = .true.
      valid_eval_count = 0
      valid_eval_fraction = 0.0_dp
      if (.not. available) return
      last_attempt = active_context%last_trace_attempt(active_context%last_trace_count)
      n_used = 0

      do i = 1, active_context%last_trace_count
         if (active_context%last_trace_attempt(i) /= last_attempt) cycle
         n_used = n_used + 1
         if (.not. active_context%last_trace_eval_ok(i)) then
            all_eval_ok = .false.
            cycle
         end if
         valid_eval_count = valid_eval_count + 1
         r = active_context%last_trace_res_norm(i)
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
      else if (size(buf) < n_need) then
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
      else if (size(buf) < n_need) then
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
      else if (size(buf) < n_need) then
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
      else if (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_logical_workspace

   subroutine ensure_trace_capacity(context, n_need)
      implicit none
      type(qn_context_t), intent(inout) :: context
      integer, intent(in) :: n_need
      integer :: new_cap

      if (context%last_trace_dim <= 0) return
      if (allocated(context%last_trace_z_proposed)) then
         if (size(context%last_trace_z_proposed, 1) /= context%last_trace_dim) then
            deallocate (context%last_trace_z_proposed, context%last_trace_z_flowed, context%last_trace_res_norm, context%last_trace_alpha, &
                        context%last_trace_iter, context%last_trace_backtrack, context%last_trace_attempt, context%last_trace_route, &
                        context%last_trace_accepted, context%last_trace_eval_ok)
            context%last_trace_capacity = 0
            context%last_trace_count = 0
         end if
      end if

      if (n_need <= context%last_trace_capacity .and. allocated(context%last_trace_z_proposed)) return

      new_cap = max(64, max(n_need, 2*context%last_trace_capacity))
      call grow_complex_trace(context%last_trace_z_proposed, context%last_trace_dim, context%last_trace_count, new_cap)
      call grow_complex_trace(context%last_trace_z_flowed, context%last_trace_dim, context%last_trace_count, new_cap)
      call grow_real_trace(context%last_trace_res_norm, context%last_trace_count, new_cap)
      call grow_real_trace(context%last_trace_alpha, context%last_trace_count, new_cap)
      call grow_int_trace(context%last_trace_iter, context%last_trace_count, new_cap)
      call grow_int_trace(context%last_trace_backtrack, context%last_trace_count, new_cap)
      call grow_int_trace(context%last_trace_attempt, context%last_trace_count, new_cap)
      call grow_int_trace(context%last_trace_route, context%last_trace_count, new_cap)
      call grow_logical_trace(context%last_trace_accepted, context%last_trace_count, new_cap)
      call grow_logical_trace(context%last_trace_eval_ok, context%last_trace_count, new_cap)
      context%last_trace_capacity = new_cap
   end subroutine ensure_trace_capacity

   subroutine reset_quasi_last_trace(context, n_dim)
      implicit none
      type(qn_context_t), intent(inout) :: context
      integer, intent(in) :: n_dim

      context%last_trace_count = 0
      context%last_trace_dim = n_dim
      context%trace_route_code = 0
      call ensure_complex_workspace(context%eval_z_proposed, n_dim)
      call ensure_complex_workspace(context%eval_z_flowed, n_dim)
      context%eval_has_flowed = .false.
      context%eval_flowed_is_inverse = .false.
      call ensure_trace_capacity(context, 1)
   end subroutine reset_quasi_last_trace

   subroutine append_quasi_trace_sample(context, qn_policy, alpha, iter_idx, backtrack_idx, attempt_idx, res_norm, accepted, eval_ok)
      implicit none
      type(qn_context_t), intent(inout) :: context
      type(qn_policy_context_t), intent(inout) :: qn_policy
      real(dp), intent(in) :: alpha, res_norm
      integer, intent(in) :: iter_idx, backtrack_idx, attempt_idx
      logical, intent(in) :: accepted, eval_ok
      integer :: k, n_dim, i
      real(dp) :: nanv

      n_dim = context%last_trace_dim
      if (n_dim <= 0) return
      call ensure_trace_capacity(context, context%last_trace_count + 1)
      if (.not. allocated(context%last_trace_z_proposed)) return

      k = context%last_trace_count + 1
      context%last_trace_z_proposed(1:n_dim, k) = context%eval_z_proposed(1:n_dim)
      if (context%eval_has_flowed) then
         context%last_trace_z_flowed(1:n_dim, k) = context%eval_z_flowed(1:n_dim)
      else
         nanv = ieee_value(0.0_dp, ieee_quiet_nan)
         do i = 1, n_dim
            context%last_trace_z_flowed(i, k) = cmplx(nanv, nanv, dp)
         end do
      end if
      context%last_trace_res_norm(k) = res_norm
      context%last_trace_alpha(k) = alpha
      context%last_trace_iter(k) = iter_idx
      context%last_trace_backtrack(k) = backtrack_idx
      context%last_trace_attempt(k) = attempt_idx
      context%last_trace_route(k) = context%trace_route_code
      context%last_trace_accepted(k) = accepted
      context%last_trace_eval_ok(k) = eval_ok
      context%last_trace_count = k
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

   subroutine load_qn_backend_policy(qn_policy)
      implicit none
      type(qn_policy_context_t), intent(inout) :: qn_policy
      character(len=128) :: env_value, token
      logical :: env_present

      if (qn_policy%qn_backend_policy_loaded) return
      qn_policy%qn_backend_policy_loaded = .true.
      qn_policy%qn_solver_backend = qn_backend_official_dfols
      call apply_qn_official_dfols_preset("stable_gate77", qn_policy)

      call read_string_env("QN_SOLVER_BACKEND", env_value, env_present)
      if (env_present) then
         token = trim(to_lower_ascii(adjustl(env_value)))
         select case (token)
         case ("official", "official_dfols", "official-dfols", "dfols", "external_dfols")
            qn_policy%qn_solver_backend = qn_backend_official_dfols
         case ("internal", "inhouse", "in_house", "legacy")
            write (*, '(A,A,A)') "[WARN] QN_SOLVER_BACKEND='", trim(env_value), &
               "' is no longer supported; using official_dfols."
            qn_policy%qn_solver_backend = qn_backend_official_dfols
         case default
            write (*, '(A,A,A)') "[WARN] Unknown QN_SOLVER_BACKEND='", trim(env_value), "'; using official_dfols."
            qn_policy%qn_solver_backend = qn_backend_official_dfols
         end select
      end if

      call read_string_env("QN_OFFICIAL_DFOLS_PRESET", env_value, env_present)
      if (env_present) then
         token = trim(to_lower_ascii(adjustl(env_value)))
         call apply_qn_official_dfols_preset(token, qn_policy)
      end if

      call parse_int_env("QN_OFFICIAL_DFOLS_NPT", qn_policy%qn_official_dfols_npt)
      call parse_int_env("QN_OFFICIAL_DFOLS_MAXFUN", qn_policy%qn_official_dfols_maxfun)
      call parse_logical_env("QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE", qn_policy%qn_official_dfols_objfun_has_noise)
      call parse_real_env("QN_OFFICIAL_DFOLS_RHOBEG", qn_policy%qn_official_dfols_rhobeg)
      call parse_real_env("QN_OFFICIAL_DFOLS_RHOEND", qn_policy%qn_official_dfols_rhoend)
      call parse_real_env("QN_OFFICIAL_DFOLS_MODEL_ABS_TOL", qn_policy%qn_official_dfols_model_abs_tol)
      call parse_real_env("QN_OFFICIAL_DFOLS_MODEL_REL_TOL", qn_policy%qn_official_dfols_model_rel_tol)
      call parse_real_env("QN_OFFICIAL_DFOLS_TR_ALPHA1", qn_policy%qn_official_dfols_tr_alpha1)
      call parse_real_env("QN_OFFICIAL_DFOLS_TR_ALPHA2", qn_policy%qn_official_dfols_tr_alpha2)
      call parse_real_env("QN_OFFICIAL_DFOLS_SAFETY_STEP_THRESH", qn_policy%qn_official_dfols_safety_step_thresh)

      qn_policy%qn_official_dfols_npt = max(0, qn_policy%qn_official_dfols_npt)
      qn_policy%qn_official_dfols_maxfun = max(1, qn_policy%qn_official_dfols_maxfun)
      if (.not. ieee_is_finite(qn_policy%qn_official_dfols_rhobeg)) qn_policy%qn_official_dfols_rhobeg = 1.8e-2_dp
      if (.not. ieee_is_finite(qn_policy%qn_official_dfols_rhoend) .or. qn_policy%qn_official_dfols_rhoend <= 0.0_dp) then
         qn_policy%qn_official_dfols_rhoend = 1.0e-16_dp
      end if
      if (.not. ieee_is_finite(qn_policy%qn_official_dfols_model_abs_tol) .or. &
          qn_policy%qn_official_dfols_model_abs_tol < 0.0_dp) then
         qn_policy%qn_official_dfols_model_abs_tol = 1.0e-26_dp
      end if
      if (.not. ieee_is_finite(qn_policy%qn_official_dfols_model_rel_tol) .or. &
          qn_policy%qn_official_dfols_model_rel_tol < 0.0_dp) then
         qn_policy%qn_official_dfols_model_rel_tol = 0.0_dp
      end if
      if (.not. ieee_is_finite(qn_policy%qn_official_dfols_tr_alpha1) .or. &
          qn_policy%qn_official_dfols_tr_alpha1 < 0.0_dp .or. qn_policy%qn_official_dfols_tr_alpha1 > 1.0_dp) then
         qn_policy%qn_official_dfols_tr_alpha1 = -1.0_dp
      end if
      if (.not. ieee_is_finite(qn_policy%qn_official_dfols_tr_alpha2) .or. &
          qn_policy%qn_official_dfols_tr_alpha2 < 0.0_dp .or. qn_policy%qn_official_dfols_tr_alpha2 > 1.0_dp) then
         qn_policy%qn_official_dfols_tr_alpha2 = -1.0_dp
      end if
      if (.not. ieee_is_finite(qn_policy%qn_official_dfols_safety_step_thresh) .or. &
          qn_policy%qn_official_dfols_safety_step_thresh < 0.0_dp) then
         qn_policy%qn_official_dfols_safety_step_thresh = -1.0_dp
      end if

      call print_qn_backend_policy_once(qn_policy)
   end subroutine load_qn_backend_policy

   subroutine apply_qn_official_dfols_preset(preset_name, qn_policy)
      implicit none
      character(len=*), intent(in) :: preset_name
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      character(len=128) :: token
      type(qn_policy_context_t), pointer :: active_policy

      call resolve_qn_policy(qn_policy, active_policy)
      token = trim(to_lower_ascii(adjustl(preset_name)))
      select case (token)
      case ("", "stable", "stable_gate77", "gate77", "production", "official_alone", &
            "f20f", "f20f_most_conservative_double")
         active_policy%qn_official_dfols_npt = 4
         active_policy%qn_official_dfols_maxfun = 250
         active_policy%qn_official_dfols_objfun_has_noise = .true.
         active_policy%qn_official_dfols_rhobeg = 1.8e-2_dp
         active_policy%qn_official_dfols_rhoend = 1.0e-16_dp
         active_policy%qn_official_dfols_model_abs_tol = 1.0e-26_dp
         active_policy%qn_official_dfols_model_rel_tol = 0.0_dp
         active_policy%qn_official_dfols_tr_alpha1 = -1.0_dp
         active_policy%qn_official_dfols_tr_alpha2 = -1.0_dp
         active_policy%qn_official_dfols_safety_step_thresh = -1.0_dp
      case ("legacy", "legacy69", "r005", "gate69")
         active_policy%qn_official_dfols_npt = 0
         active_policy%qn_official_dfols_maxfun = 250
         active_policy%qn_official_dfols_objfun_has_noise = .true.
         active_policy%qn_official_dfols_rhobeg = 5.0e-2_dp
         active_policy%qn_official_dfols_rhoend = 1.0e-16_dp
         active_policy%qn_official_dfols_model_abs_tol = 1.0e-30_dp
         active_policy%qn_official_dfols_model_rel_tol = 0.0_dp
         active_policy%qn_official_dfols_tr_alpha1 = -1.0_dp
         active_policy%qn_official_dfols_tr_alpha2 = -1.0_dp
         active_policy%qn_official_dfols_safety_step_thresh = -1.0_dp
      case default
         write (*, '(A,A,A)') "[WARN] Unknown QN_OFFICIAL_DFOLS_PRESET='", trim(preset_name), "'; using stable_gate77."
         active_policy%qn_official_dfols_npt = 4
         active_policy%qn_official_dfols_maxfun = 250
         active_policy%qn_official_dfols_objfun_has_noise = .true.
         active_policy%qn_official_dfols_rhobeg = 1.8e-2_dp
         active_policy%qn_official_dfols_rhoend = 1.0e-16_dp
         active_policy%qn_official_dfols_model_abs_tol = 1.0e-26_dp
         active_policy%qn_official_dfols_model_rel_tol = 0.0_dp
         active_policy%qn_official_dfols_tr_alpha1 = -1.0_dp
         active_policy%qn_official_dfols_tr_alpha2 = -1.0_dp
         active_policy%qn_official_dfols_safety_step_thresh = -1.0_dp
      end select
   end subroutine apply_qn_official_dfols_preset

   subroutine get_qn_official_dfols_policy(backend_code, npt, maxfun, objfun_has_noise, rhobeg, rhoend, &
                                           model_abs_tol, model_rel_tol, qn_policy)
      implicit none
      integer, intent(out) :: backend_code, npt, maxfun
      logical, intent(out) :: objfun_has_noise
      real(dp), intent(out) :: rhobeg, rhoend, model_abs_tol, model_rel_tol
      type(qn_policy_context_t), intent(inout), optional, target :: qn_policy
      type(qn_policy_context_t), pointer :: active_policy

      call resolve_qn_policy(qn_policy, active_policy)
      call load_qn_backend_policy(active_policy)
      backend_code = active_policy%qn_solver_backend
      npt = active_policy%qn_official_dfols_npt
      maxfun = active_policy%qn_official_dfols_maxfun
      objfun_has_noise = active_policy%qn_official_dfols_objfun_has_noise
      rhobeg = active_policy%qn_official_dfols_rhobeg
      rhoend = active_policy%qn_official_dfols_rhoend
      model_abs_tol = active_policy%qn_official_dfols_model_abs_tol
      model_rel_tol = active_policy%qn_official_dfols_model_rel_tol
   end subroutine get_qn_official_dfols_policy

   subroutine print_qn_backend_policy_once(qn_policy)
      implicit none
      type(qn_policy_context_t), intent(inout) :: qn_policy

      if (qn_policy%qn_backend_notice_printed) return
      qn_policy%qn_backend_notice_printed = .true.
      write (*, '(A)') "[INFO] QN solver backend=official_dfols"
      write (*, '(A,I0,1X,A,I0,1X,A,L1,1X,A,ES10.3,1X,A,ES10.3)') &
         "[INFO] official DFO-LS preset npt=", qn_policy%qn_official_dfols_npt, &
         "maxfun=", qn_policy%qn_official_dfols_maxfun, &
         "noise=", qn_policy%qn_official_dfols_objfun_has_noise, &
         "rhobeg=", qn_policy%qn_official_dfols_rhobeg, "rhoend=", qn_policy%qn_official_dfols_rhoend
      write (*, '(A,ES10.3,1X,A,ES10.3)') &
         "[INFO] official DFO-LS model.abs_tol=", qn_policy%qn_official_dfols_model_abs_tol, &
         "model.rel_tol=", qn_policy%qn_official_dfols_model_rel_tol
      if (qn_policy%qn_official_dfols_tr_alpha1 >= 0.0_dp .or. qn_policy%qn_official_dfols_tr_alpha2 >= 0.0_dp .or. &
          qn_policy%qn_official_dfols_safety_step_thresh >= 0.0_dp) then
         write (*, '(A,ES10.3,1X,A,ES10.3,1X,A,ES10.3)') &
            "[INFO] official DFO-LS user_params tr_radius.alpha1=", qn_policy%qn_official_dfols_tr_alpha1, &
            "tr_radius.alpha2=", qn_policy%qn_official_dfols_tr_alpha2, &
            "general.safety_step_thresh=", qn_policy%qn_official_dfols_safety_step_thresh
      end if
   end subroutine print_qn_backend_policy_once

   subroutine get_quasi_global_filter_stats(candidate_count, pass_count, reject_count, qn_diagnostics)
      implicit none
      integer(int64), intent(out) :: candidate_count, pass_count, reject_count
      type(qn_diagnostics_context_t), intent(inout), optional, target :: qn_diagnostics
      type(qn_diagnostics_context_t), pointer :: active_diagnostics

      call resolve_qn_diagnostics(qn_diagnostics, active_diagnostics)
      candidate_count = active_diagnostics%global_filter_candidate_count
      pass_count = active_diagnostics%global_filter_pass_count
      reject_count = active_diagnostics%global_filter_reject_count
   end subroutine get_quasi_global_filter_stats

   subroutine count_qn_attempt_eval(qn_context)
      implicit none
      type(qn_context_t), intent(inout) :: qn_context

      qn_context%current_attempt_eval_count = qn_context%current_attempt_eval_count + 1_int64
   end subroutine count_qn_attempt_eval

   real(dp) function qn_attempt_elapsed_seconds(start_seconds) result(elapsed)
      implicit none
      real(dp), intent(in) :: start_seconds
      real(dp) :: stop_seconds

      call cpu_time(stop_seconds)
      elapsed = max(0.0_dp, stop_seconds - start_seconds)
   end function qn_attempt_elapsed_seconds

   subroutine capture_qn_attempt(xt, z, del_z, xi0, attempt_idx, max_iter, tol, initial_residual_norm, best_residual_norm, &
                                 converged, initial_eval_ok, residual_eval_count, cpu_seconds, qn_diagnostics)
      implicit none
      real(dp), intent(in) :: xt(:), del_z(:), xi0(:)
      complex(dp), intent(in) :: z(:)
      integer, intent(in) :: attempt_idx, max_iter
      real(dp), intent(in) :: tol, initial_residual_norm, best_residual_norm
      logical, intent(in) :: converged, initial_eval_ok
      integer(int64), intent(in) :: residual_eval_count
      real(dp), intent(in) :: cpu_seconds
      type(qn_diagnostics_context_t), intent(inout) :: qn_diagnostics

      integer :: sample_idx, n_z, n_delz, n_x, n_xi, ios
      logical :: io_ok

      call load_qn_attempt_capture_policy(qn_diagnostics)
      if (.not. qn_diagnostics%attempt_capture_enabled) return

      qn_diagnostics%attempt_capture_seen = qn_diagnostics%attempt_capture_seen + 1
      if (qn_diagnostics%attempt_capture_stride > 1) then
         if (mod(qn_diagnostics%attempt_capture_seen - 1, qn_diagnostics%attempt_capture_stride) /= 0) return
      end if
      if (qn_diagnostics%attempt_capture_limit > 0 .and. &
          qn_diagnostics%attempt_capture_count >= qn_diagnostics%attempt_capture_limit) return

      call ensure_qn_attempt_capture_files(qn_diagnostics, io_ok)
      if (.not. io_ok) return

      sample_idx = qn_diagnostics%attempt_capture_count + 1
      n_z = size(z)
      n_delz = size(del_z)
      n_x = size(xt)
      n_xi = size(xi0)

      write (qn_diagnostics%attempt_capture_z0_unit, iostat=ios) sample_idx, n_z, z
      if (ios /= 0) then
         call handle_qn_attempt_capture_error(qn_diagnostics, "[WARN] Failed writing QN attempt z0 snapshot.")
         return
      end if
      write (qn_diagnostics%attempt_capture_delz_unit, iostat=ios) sample_idx, n_delz, del_z
      if (ios /= 0) then
         call handle_qn_attempt_capture_error(qn_diagnostics, "[WARN] Failed writing QN attempt delz snapshot.")
         return
      end if
      write (qn_diagnostics%attempt_capture_x0_unit, iostat=ios) sample_idx, n_x, xt
      if (ios /= 0) then
         call handle_qn_attempt_capture_error(qn_diagnostics, "[WARN] Failed writing QN attempt x0 snapshot.")
         return
      end if
      write (qn_diagnostics%attempt_capture_xi0_unit, iostat=ios) sample_idx, n_xi, xi0
      if (ios /= 0) then
         call handle_qn_attempt_capture_error(qn_diagnostics, "[WARN] Failed writing QN attempt xi0 snapshot.")
         return
      end if
      write (qn_diagnostics%attempt_capture_meta_unit, '(*(g0,:,","))', iostat=ios) sample_idx, attempt_idx, max_iter, n_z, n_x, &
         n_xi, tol, initial_residual_norm, best_residual_norm, norm2(xi0), logical_to_int(converged), &
         logical_to_int(initial_eval_ok), residual_eval_count, cpu_seconds
      if (ios /= 0) then
         call handle_qn_attempt_capture_error(qn_diagnostics, "[WARN] Failed writing QN attempt meta row.")
         return
      end if

      flush (qn_diagnostics%attempt_capture_z0_unit)
      flush (qn_diagnostics%attempt_capture_delz_unit)
      flush (qn_diagnostics%attempt_capture_x0_unit)
      flush (qn_diagnostics%attempt_capture_xi0_unit)
      flush (qn_diagnostics%attempt_capture_meta_unit)
      qn_diagnostics%attempt_capture_count = sample_idx
   end subroutine capture_qn_attempt

   subroutine load_qn_attempt_capture_policy(qn_diagnostics)
      implicit none
      type(qn_diagnostics_context_t), intent(inout) :: qn_diagnostics
      logical :: env_present

      if (qn_diagnostics%attempt_capture_policy_loaded) return
      qn_diagnostics%attempt_capture_policy_loaded = .true.

      qn_diagnostics%attempt_capture_dir = ""
      call read_string_env("QN_ATTEMPT_CAPTURE_DIR", qn_diagnostics%attempt_capture_dir, env_present)
      qn_diagnostics%attempt_capture_enabled = env_present .and. len_trim(qn_diagnostics%attempt_capture_dir) > 0
      if (.not. qn_diagnostics%attempt_capture_enabled) return

      qn_diagnostics%attempt_capture_limit = 100
      qn_diagnostics%attempt_capture_stride = 1
      call parse_int_env("QN_ATTEMPT_CAPTURE_LIMIT", qn_diagnostics%attempt_capture_limit)
      call parse_int_env("QN_ATTEMPT_CAPTURE_STRIDE", qn_diagnostics%attempt_capture_stride)
      qn_diagnostics%attempt_capture_stride = max(1, qn_diagnostics%attempt_capture_stride)

      if (qn_diagnostics%attempt_capture_limit > 0) then
         write (*, '(A,I0)') "[INFO] QN attempt capture limit=", qn_diagnostics%attempt_capture_limit
      else
         write (*, '(A)') "[INFO] QN attempt capture limit=unlimited"
      end if
      write (*, '(A,I0)') "[INFO] QN attempt capture stride=", qn_diagnostics%attempt_capture_stride
      write (*, '(A,1X,A)') "[INFO] QN attempt capture dir=", trim(qn_diagnostics%attempt_capture_dir)
   end subroutine load_qn_attempt_capture_policy

   subroutine ensure_qn_attempt_capture_files(qn_diagnostics, io_ok)
      implicit none
      type(qn_diagnostics_context_t), intent(inout) :: qn_diagnostics
      logical, intent(out) :: io_ok
      integer :: ios

      io_ok = .true.
      if (qn_diagnostics%attempt_capture_files_ready) return
      if (qn_diagnostics%attempt_capture_write_error) then
         io_ok = .false.
         return
      end if

      open (newunit=qn_diagnostics%attempt_capture_z0_unit, file=trim(join_capture_path(qn_diagnostics, "qn_attempt_z0.dat")), &
            status='replace', &
            access='stream', form='unformatted', action='write', iostat=ios)
      if (ios /= 0) then
         call handle_qn_attempt_capture_error(qn_diagnostics, "[WARN] Failed opening QN attempt z0 output.")
         io_ok = .false.
         return
      end if
      open (newunit=qn_diagnostics%attempt_capture_delz_unit, file=trim(join_capture_path(qn_diagnostics, "qn_attempt_delz.dat")), &
            status='replace', &
            access='stream', form='unformatted', action='write', iostat=ios)
      if (ios /= 0) then
         call handle_qn_attempt_capture_error(qn_diagnostics, "[WARN] Failed opening QN attempt delz output.")
         io_ok = .false.
         return
      end if
      open (newunit=qn_diagnostics%attempt_capture_x0_unit, file=trim(join_capture_path(qn_diagnostics, "qn_attempt_x0.dat")), &
            status='replace', &
            access='stream', form='unformatted', action='write', iostat=ios)
      if (ios /= 0) then
         call handle_qn_attempt_capture_error(qn_diagnostics, "[WARN] Failed opening QN attempt x0 output.")
         io_ok = .false.
         return
      end if
      open (newunit=qn_diagnostics%attempt_capture_xi0_unit, file=trim(join_capture_path(qn_diagnostics, "qn_attempt_xi0.dat")), &
            status='replace', &
            access='stream', form='unformatted', action='write', iostat=ios)
      if (ios /= 0) then
         call handle_qn_attempt_capture_error(qn_diagnostics, "[WARN] Failed opening QN attempt xi0 output.")
         io_ok = .false.
         return
      end if
      open (newunit=qn_diagnostics%attempt_capture_meta_unit, file=trim(join_capture_path(qn_diagnostics, "qn_attempt_meta.csv")), &
            status='replace', &
            action='write', iostat=ios)
      if (ios /= 0) then
         call handle_qn_attempt_capture_error(qn_diagnostics, "[WARN] Failed opening QN attempt meta output.")
         io_ok = .false.
         return
      end if
      write (qn_diagnostics%attempt_capture_meta_unit, '(A)') &
         "sample_idx,attempt_idx,max_iter,n_z,n_x,n_xi,tol,initial_residual_norm,best_residual_norm,xi0_norm,converged,"// &
         "initial_eval_ok,residual_eval_count,cpu_seconds"

      qn_diagnostics%attempt_capture_files_ready = .true.
   end subroutine ensure_qn_attempt_capture_files

   function join_capture_path(qn_diagnostics, file_name) result(path)
      implicit none
      type(qn_diagnostics_context_t), intent(in) :: qn_diagnostics
      character(len=*), intent(in) :: file_name
      character(len=1024) :: path
      integer :: n_dir

      n_dir = len_trim(qn_diagnostics%attempt_capture_dir)
      if (n_dir <= 0) then
         path = trim(file_name)
      else if (qn_diagnostics%attempt_capture_dir(n_dir:n_dir) == "/") then
         path = trim(qn_diagnostics%attempt_capture_dir)//trim(file_name)
      else
         path = trim(qn_diagnostics%attempt_capture_dir)//"/"//trim(file_name)
      end if
   end function join_capture_path

   subroutine handle_qn_attempt_capture_error(qn_diagnostics, message)
      implicit none
      type(qn_diagnostics_context_t), intent(inout) :: qn_diagnostics
      character(len=*), intent(in) :: message

      if (.not. qn_diagnostics%attempt_capture_write_error) write (*, '(A)') trim(message)
      qn_diagnostics%attempt_capture_write_error = .true.
   end subroutine handle_qn_attempt_capture_error

   integer function logical_to_int(value) result(out)
      implicit none
      logical, intent(in) :: value

      out = merge(1, 0, value)
   end function logical_to_int

end module quasi_newton_solver_mod

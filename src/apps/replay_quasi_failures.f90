program replay_quasi_failures_app
   use utils, only: dp, complex_to_real, real_to_complex
   use param_mod, only: read_parameters, x_history_file, config, quasi_fallback_enabled, &
                        model_alpha => alpha, model_beta => beta
   use solve_flow, only: flow, flowz, flowzr, set_intode_strict_mode
   use quasi_newton_solver_mod, only: solve_constraint_quasi_newton, evaluate_constraint_residual, &
                                      get_quasi_newton_last_trace_r2c
   use hmc_integrator_core, only: rattle_step_core
   use hmc_kernels, only: calculate_dV
   use hmc_state_buffers, only: rattle_step_workspace_t, release_rattle_step_workspace
   use model, only: ds
   use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_quiet_nan, ieee_is_finite
   implicit none

   character(len=256) :: arg_text
   character(len=256) :: z0_file, delz_file, x0_file, out_csv
   real(dp) :: tol, min_res, last_res, z_replay_error, nanv
   real(dp) :: first_dist_z0, first_dist_z1
   real(dp) :: min_z_prop_re, min_z_prop_im, min_z_flow_re, min_z_flow_im
   real(dp) :: min_virial_flow_re, min_virial_flow_im
   real(dp) :: fd_eps, fd_det, fd_logabsdet
   real(dp) :: rev_dx, rev_dz, rev_dp
   real(dp) :: rev_x2, rev_z_re, rev_z_im, rev_flow_res
   real(dp) :: nt_loss_norm
   real(dp) :: btn_flow_im_norm, btn_a_norm
   integer :: max_iter
   integer :: unit_z0, unit_delz, unit_x0, unit_out, unit_trace
   integer :: ios, sid_z, sid_d, sid_x, nz, nd, nx
   integer :: sample_count, success_count
   integer :: proposal_count, nprop, min_iter, min_backtrack, min_attempt
   integer :: min_route_code, converged_attempt_count, accepted_eval_count
   integer :: min_idx(1)
   logical :: has_z0_arg, has_delz_arg, has_x0_arg, has_out_arg
   logical :: flow_error, solver_error, size_ok, trace_available, has_quasi
   logical :: fd_enabled, fd_ok, fd_route_stable
   logical :: rev_enabled, rev_ok
   logical :: nt_loss_ok
   logical :: btn_contract_ok
   logical :: trace_out_enabled
   character(len=512) :: trace_out_csv

   complex(dp), allocatable :: z0(:), z_flow(:), jac(:, :)
   real(dp), allocatable :: delz(:), x0(:), Jl(:), x_new(:), x_best_solution(:)
   complex(dp), allocatable :: quasi_z_proposed(:), quasi_z_flowed(:)
   real(dp), allocatable :: quasi_res_norm(:), quasi_alpha(:)
   integer, allocatable :: quasi_iter(:), quasi_backtrack(:), quasi_attempt(:), quasi_route_code(:)
   logical, allocatable :: quasi_accepted(:), quasi_eval_ok(:)

   if (command_argument_count() < 2) then
      call print_usage_and_stop()
   end if

   call get_command_argument(1, arg_text)
   read (arg_text, *, iostat=ios) tol
   if (ios /= 0 .or. tol <= 0.0_dp) then
      write (*, '(A,A,A)') "[ERROR] Invalid tol='", trim(arg_text), "'."
      error stop 1
   end if

   call get_command_argument(2, arg_text)
   read (arg_text, *, iostat=ios) max_iter
   if (ios /= 0 .or. max_iter <= 0) then
      write (*, '(A,A,A)') "[ERROR] Invalid max_iter='", trim(arg_text), "'."
      error stop 1
   end if

   has_z0_arg = (command_argument_count() >= 3)
   has_delz_arg = (command_argument_count() >= 4)
   has_x0_arg = (command_argument_count() >= 5)
   has_out_arg = (command_argument_count() >= 6)

   z0_file = ""
   delz_file = ""
   x0_file = ""
   out_csv = "quasi_replay_results.csv"
   if (has_z0_arg) call get_command_argument(3, z0_file)
   if (has_delz_arg) call get_command_argument(4, delz_file)
   if (has_x0_arg) call get_command_argument(5, x0_file)
   if (has_out_arg) call get_command_argument(6, out_csv)

   call set_intode_strict_mode(.true.)
   call read_parameters()
   call load_fd_options(fd_enabled, fd_eps)
   call load_logical_option("QN_REPLAY_REV_ENABLED", rev_enabled)
   if (rev_enabled) then
      config%solver%enable_quasi_fallback = .true.
      quasi_fallback_enabled = .true.
   end if
   call open_trace_output(trace_out_enabled, unit_trace, trace_out_csv)
   if (.not. has_z0_arg) z0_file = default_failure_path(x_history_file, "constraint_solver_fail_z0.dat")
   if (.not. has_delz_arg) delz_file = default_failure_path(x_history_file, "constraint_solver_fail_delz.dat")
   if (.not. has_x0_arg) x0_file = default_failure_path(x_history_file, "constraint_solver_fail_x0.dat")

   open (newunit=unit_z0, file=trim(z0_file), status='old', access='stream', form='unformatted', action='read', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "[ERROR] Failed to open z0 file:", trim(z0_file)
      error stop 1
   end if
   open (newunit=unit_delz, file=trim(delz_file), status='old', access='stream', form='unformatted', action='read', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "[ERROR] Failed to open delz file:", trim(delz_file)
      error stop 1
   end if
   open (newunit=unit_x0, file=trim(x0_file), status='old', access='stream', form='unformatted', action='read', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "[ERROR] Failed to open x0 file:", trim(x0_file)
      error stop 1
   end if

   open (newunit=unit_out, file=trim(out_csv), status='replace', action='write', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "[ERROR] Failed to open output CSV:", trim(out_csv)
      error stop 1
   end if

   write (unit_out, '(A)') &
      "sample_idx,size_ok,flow_error,success,proposal_count,min_res,last_res,min_iter,min_backtrack,min_attempt,min_route_code," // &
      "converged_attempt_count,accepted_eval_count," // &
      "z_replay_error,first_dist_z0,first_dist_z1,min_z_prop_re,min_z_prop_im,min_z_flow_re,min_z_flow_im," // &
      "min_virial_flow_re,min_virial_flow_im,fd_ok,fd_det,fd_logabsdet,fd_route_stable,rev_ok,rev_dx,rev_dz,rev_dp," // &
      "rev_x2,rev_z_re,rev_z_im,rev_flow_res,btn_contract_ok,btn_flow_im_norm,btn_a_norm,nt_loss_ok,nt_loss_norm"

   sample_count = 0
   success_count = 0
   do
      read (unit_z0, iostat=ios) sid_z, nz
      if (ios /= 0) exit
      if (allocated(z0)) deallocate (z0)
      allocate (z0(nz))
      read (unit_z0, iostat=ios) z0
      if (ios /= 0) exit

      read (unit_delz, iostat=ios) sid_d, nd
      if (ios /= 0) exit
      if (allocated(delz)) deallocate (delz)
      allocate (delz(nd))
      read (unit_delz, iostat=ios) delz
      if (ios /= 0) exit

      read (unit_x0, iostat=ios) sid_x, nx
      if (ios /= 0) exit
      if (allocated(x0)) deallocate (x0)
      allocate (x0(nx))
      read (unit_x0, iostat=ios) x0
      if (ios /= 0) exit

      if (sid_z /= sid_d .or. sid_z /= sid_x) then
         write (*, '(A,3(I0,1X))') "[WARN] Sample id mismatch:", sid_z, sid_d, sid_x
      end if

      size_ok = (nd == 2*nz)
      flow_error = .false.
      solver_error = .true.
      nprop = 0
      min_iter = -1
      min_backtrack = -1
      min_attempt = -1
      min_route_code = -1
      converged_attempt_count = 0
      accepted_eval_count = 0
      nanv = ieee_value(0.0_dp, ieee_quiet_nan)
      min_res = nanv
      last_res = nanv
      z_replay_error = nanv
      first_dist_z0 = nanv
      first_dist_z1 = nanv
      min_z_prop_re = nanv
      min_z_prop_im = nanv
      min_z_flow_re = nanv
      min_z_flow_im = nanv
      min_virial_flow_re = nanv
      min_virial_flow_im = nanv
      fd_ok = .false.
      fd_route_stable = .false.
      fd_det = nanv
      fd_logabsdet = nanv
      rev_ok = .false.
      rev_dx = nanv
      rev_dz = nanv
      rev_dp = nanv
      rev_x2 = nanv
      rev_z_re = nanv
      rev_z_im = nanv
      rev_flow_res = nanv
      nt_loss_ok = .false.
      nt_loss_norm = nanv
      btn_contract_ok = .false.
      btn_flow_im_norm = nanv
      btn_a_norm = nanv

      if (size_ok) then
         if (allocated(jac)) deallocate (jac)
         if (allocated(z_flow)) deallocate (z_flow)
         if (allocated(Jl)) deallocate (Jl)
         if (allocated(x_new)) deallocate (x_new)
         if (allocated(x_best_solution)) deallocate (x_best_solution)
         allocate (jac(nz, nz), z_flow(nz), Jl(nd), x_new(nx), x_best_solution(nd))
         z_flow = z0
         call flow(x0, z_flow, jac, flow_error)
         if (.not. flow_error) then
            if (nz == 1) z_replay_error = abs(z_flow(1) - z0(1))
            call solve_constraint_quasi_newton(evaluate_constraint_residual, tol, max_iter, x0, z0, delz, solver_error, Jl, x_new, jac, &
                                             x_best_solution=x_best_solution)
            call get_quasi_newton_last_trace_r2c(trace_available, proposal_count, quasi_z_proposed, quasi_z_flowed, quasi_res_norm, &
                                                 quasi_alpha, quasi_iter, quasi_backtrack, quasi_attempt, quasi_accepted, quasi_eval_ok, &
                                                 quasi_route_code)
            has_quasi = trace_available .and. proposal_count > 0
            if (has_quasi) then
               if (trace_out_enabled) then
                  call write_replay_trace_rows(unit_trace, sid_z, quasi_z_proposed, quasi_z_flowed, quasi_res_norm, &
                                               quasi_alpha, quasi_iter, quasi_backtrack, quasi_attempt, quasi_route_code, &
                                               quasi_accepted, quasi_eval_ok)
               end if
               nprop = proposal_count
               min_idx = minloc(quasi_res_norm)
               min_res = quasi_res_norm(min_idx(1))
               last_res = quasi_res_norm(proposal_count)
               min_iter = quasi_iter(min_idx(1))
               min_backtrack = quasi_backtrack(min_idx(1))
               min_attempt = quasi_attempt(min_idx(1))
               if (allocated(quasi_route_code)) min_route_code = quasi_route_code(min_idx(1))
               converged_attempt_count = count_converged_attempts(quasi_attempt, quasi_res_norm, quasi_eval_ok, tol)
               accepted_eval_count = count_accepted_eval(quasi_accepted, quasi_eval_ok)
               if (nz == 1 .and. size(quasi_z_proposed) >= 1) then
                  first_dist_z0 = abs(quasi_z_proposed(1) - z0(1))
                  first_dist_z1 = abs(quasi_z_proposed(1) - (z0(1) + cmplx(delz(1), delz(2), dp)))
                  min_z_prop_re = real(quasi_z_proposed(min_idx(1)), dp)
                  min_z_prop_im = aimag(quasi_z_proposed(min_idx(1)))
                  min_z_flow_re = real(quasi_z_flowed(min_idx(1)), dp)
                  min_z_flow_im = aimag(quasi_z_flowed(min_idx(1)))
                  call virial_re_im(quasi_z_flowed(min_idx(1)), min_virial_flow_re, min_virial_flow_im)
               end if
            end if
            if (.not. solver_error) then
               call evaluate_btn_contract(x0, z0, delz, Jl, x_best_solution, btn_flow_im_norm, btn_a_norm, btn_contract_ok)
            end if
            if (fd_enabled .and. nz == 1 .and. nd == 2 .and. (.not. solver_error)) then
               call finite_difference_delz_map(tol, max_iter, x0, z0, delz, fd_eps, min_route_code, &
                                               fd_ok, fd_det, fd_logabsdet, fd_route_stable)
            end if
            if (rev_enabled .and. nz == 1 .and. nd == 2 .and. (.not. solver_error)) then
               call local_step_reverse_audit(x0, z0, delz, rev_ok, rev_dx, rev_dz, rev_dp, &
                                             rev_x2, rev_z_re, rev_z_im, rev_flow_res)
            end if
            if (has_quasi) then
               ! Prefer the best-residual proposal in the replay trace.
               ! This avoids using a non-converged final return state when
               ! tol is extremely strict (e.g., 1e-99) and solver_success=0.
               call evaluate_nt_loss_from_trace_best(x0, z0, delz, &
                                                     [quasi_z_proposed(min_idx(1))], &
                                                     [quasi_z_flowed(min_idx(1))], &
                                                     nt_loss_norm, nt_loss_ok)
            else
               call evaluate_nt_loss_from_solution(x0, z0, delz, x_new, Jl, nt_loss_norm, nt_loss_ok)
            end if
         end if
      end if

      sample_count = sample_count + 1
      if (.not. flow_error .and. .not. solver_error) success_count = success_count + 1
      write (unit_out, '(I0,",",I0,",",I0,",",I0,",",I0,",",ES24.16,",",ES24.16,",",I0,",",I0,",",I0,",",I0,",",I0,",",I0,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",I0,",",ES24.16,",",ES24.16,",",I0,",",I0,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",I0,",",ES24.16,",",ES24.16,",",I0,",",ES24.16)') &
         sid_z, merge(1, 0, size_ok), merge(1, 0, flow_error), merge(1, 0, (.not. solver_error)), nprop, min_res, last_res, &
         min_iter, min_backtrack, min_attempt, min_route_code, converged_attempt_count, accepted_eval_count, &
         z_replay_error, first_dist_z0, first_dist_z1, &
         min_z_prop_re, min_z_prop_im, min_z_flow_re, min_z_flow_im, min_virial_flow_re, min_virial_flow_im, &
         merge(1, 0, fd_ok), fd_det, fd_logabsdet, merge(1, 0, fd_route_stable), &
         merge(1, 0, rev_ok), rev_dx, rev_dz, rev_dp, rev_x2, rev_z_re, rev_z_im, rev_flow_res, &
         merge(1, 0, btn_contract_ok), btn_flow_im_norm, btn_a_norm, merge(1, 0, nt_loss_ok), nt_loss_norm
   end do

   close (unit_z0)
   close (unit_delz)
   close (unit_x0)
   close (unit_out)
   if (trace_out_enabled) close (unit_trace)

   write (*, '(A,1X,ES12.4,1X,A,I0)') "[DONE] replayed quasi failures for tol=", tol, "max_iter=", max_iter
   write (*, '(A,I0,A,I0)') "[DONE] samples=", sample_count, " success=", success_count
   write (*, '(A,1X,A)') "[DONE] wrote:", trim(out_csv)
   if (trace_out_enabled) write (*, '(A,1X,A)') "[DONE] wrote trace:", trim(trace_out_csv)

contains


   subroutine evaluate_btn_contract(x0_in, z0_in, delz_in, jl_in, xi_solution, flow_im_norm, a_norm, ok)
      implicit none
      real(dp), intent(in) :: x0_in(:), delz_in(:), jl_in(:), xi_solution(:)
      complex(dp), intent(in) :: z0_in(:)
      real(dp), intent(out) :: flow_im_norm, a_norm
      logical, intent(out) :: ok

      integer :: n, n2
      logical :: flow_err
      complex(dp), allocatable :: z_trial(:)

      flow_im_norm = ieee_value(0.0_dp, ieee_quiet_nan)
      a_norm = ieee_value(0.0_dp, ieee_quiet_nan)
      ok = .false.

      n = size(z0_in)
      n2 = 2*n
      if (n <= 0) return
      if (size(x0_in) /= n + 1) return
      if (size(delz_in) /= n2 .or. size(jl_in) /= n2 .or. size(xi_solution) /= n2) return

      allocate (z_trial(n))
      call real_to_complex(delz_in + jl_in, z_trial)
      z_trial = z0_in + z_trial
      call flowzr(x0_in, z_trial, flow_err)
      if (flow_err) then
         deallocate (z_trial)
         return
      end if

      flow_im_norm = maxval(abs(aimag(z_trial)))
      a_norm = max_abs_real(xi_solution(n + 1:n2))
      ok = ieee_is_finite(flow_im_norm) .and. ieee_is_finite(a_norm)
      deallocate (z_trial)
   end subroutine evaluate_btn_contract

   subroutine evaluate_nt_loss_from_solution(x0_in, z0_in, delz_in, x_new_in, jl_in, loss_norm, ok)
      implicit none
      real(dp), intent(in) :: x0_in(:), delz_in(:), x_new_in(:), jl_in(:)
      complex(dp), intent(in) :: z0_in(:)
      real(dp), intent(out) :: loss_norm
      logical, intent(out) :: ok

      integer :: n, n2
      integer :: env_len, env_stat, ios_env
      logical :: flow_err
      character(len=64) :: env_value
      real(dp) :: ld_sign
      real(dp), allocatable :: xtu(:), breal(:)
      complex(dp), allocatable :: z_flow_local(:), ld_local(:), r_local(:)

      loss_norm = ieee_value(0.0_dp, ieee_quiet_nan)
      ok = .false.

      n = size(z0_in)
      n2 = 2*n
      if (size(delz_in) /= n2 .or. size(jl_in) /= n2) return
      if (size(x0_in) /= n + 1 .or. size(x_new_in) /= n + 1) return

      allocate (xtu(size(x0_in)), breal(n2), z_flow_local(n), ld_local(n), r_local(n))
      xtu = x_new_in

      call flowz(xtu, z_flow_local, flow_err)
      if (flow_err) then
         deallocate (xtu, breal, z_flow_local, ld_local, r_local)
         return
      end if

      ! In quasi-newton outputs for Newton-loss refine, Jl stores -ld in real form.
      ! For diagnostics, QN_REPLAY_NT_LD_SIGN can override this sign (+1 or -1).
      ld_sign = -1.0_dp
      call get_environment_variable("QN_REPLAY_NT_LD_SIGN", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         read (env_value(1:env_len), *, iostat=ios_env) ld_sign
         if (ios_env /= 0) ld_sign = -1.0_dp
         if (ld_sign >= 0.0_dp) then
            ld_sign = 1.0_dp
         else
            ld_sign = -1.0_dp
         end if
      end if
      call real_to_complex(ld_sign*jl_in, ld_local)
      r_local = z0_in - z_flow_local - ld_local
      call complex_to_real(r_local, breal)
      breal = breal + delz_in
      loss_norm = norm2(breal)
      ok = ieee_is_finite(loss_norm)
      deallocate (xtu, breal, z_flow_local, ld_local, r_local)
   end subroutine evaluate_nt_loss_from_solution

   subroutine evaluate_nt_loss_from_trace_best(x0_in, z0_in, delz_in, z_prop_best, z_flow_best, loss_norm, ok)
      implicit none
      real(dp), intent(in) :: x0_in(:), delz_in(:)
      complex(dp), intent(in) :: z0_in(:), z_prop_best(:), z_flow_best(:)
      real(dp), intent(out) :: loss_norm
      logical, intent(out) :: ok

      integer :: n, n2
      real(dp), allocatable :: x_best(:), jl_best(:)
      complex(dp), allocatable :: delz_complex(:), jlc_best(:)

      loss_norm = ieee_value(0.0_dp, ieee_quiet_nan)
      ok = .false.

      n = size(z0_in)
      n2 = 2*n
      if (size(x0_in) /= n + 1) return
      if (size(delz_in) /= n2) return
      if (size(z_prop_best) /= n .or. size(z_flow_best) /= n) return

      allocate (x_best(size(x0_in)), jl_best(n2), delz_complex(n), jlc_best(n))
      x_best = x0_in
      x_best(2:) = real(z_flow_best, dp)
      call real_to_complex(delz_in, delz_complex)
      jlc_best = z_prop_best - z0_in - delz_complex
      call complex_to_real(jlc_best, jl_best)
      call evaluate_nt_loss_from_solution(x0_in, z0_in, delz_in, x_best, jl_best, loss_norm, ok)
      deallocate (x_best, jl_best, delz_complex, jlc_best)
   end subroutine evaluate_nt_loss_from_trace_best


   subroutine print_usage_and_stop()
      implicit none
      write (*, '(A)') "Usage: replay_quasi_failures <tol> <max_iter> [z0_file] [delz_file] [x0_file] [out_csv]"
      write (*, '(A)') "Example: replay_quasi_failures 1e-10 200 constraint_solver_fail_z0.dat constraint_solver_fail_delz.dat constraint_solver_fail_x0.dat replay.csv"
      error stop 1
   end subroutine print_usage_and_stop

   function default_failure_path(history_path, file_name) result(path_out)
      implicit none
      character(len=*), intent(in) :: history_path, file_name
      character(len=256) :: path_out
      integer :: slash_pos, backslash_pos, split_pos

      path_out = trim(file_name)
      if (len_trim(history_path) == 0) return

      slash_pos = index(trim(history_path), '/', back=.true.)
      backslash_pos = index(trim(history_path), char(92), back=.true.)
      split_pos = max(slash_pos, backslash_pos)
      if (split_pos <= 1) return

      if (history_path(split_pos:split_pos) == '/' .or. history_path(split_pos:split_pos) == char(92)) then
         path_out = trim(history_path(:split_pos))//trim(file_name)
      else
         path_out = trim(history_path(:split_pos - 1))//"/"//trim(file_name)
      end if
   end function default_failure_path

   integer function count_converged_attempts(attempt_idx, res_norm, eval_ok, tol_in) result(n_conv)
      implicit none
      integer, intent(in) :: attempt_idx(:)
      real(dp), intent(in) :: res_norm(:), tol_in
      logical, intent(in) :: eval_ok(:)
      integer :: i, j
      logical :: seen

      n_conv = 0
      do i = 1, size(attempt_idx)
         if (.not. residual_replay_success(res_norm(i), tol_in)) cycle
         seen = .false.
         do j = 1, i - 1
            if (attempt_idx(j) == attempt_idx(i)) then
               seen = .true.
               exit
            end if
         end do
         if (.not. seen) n_conv = n_conv + 1
      end do
   end function count_converged_attempts

   integer function count_accepted_eval(accepted, eval_ok) result(n_acc)
      implicit none
      logical, intent(in) :: accepted(:), eval_ok(:)
      integer :: i

      n_acc = 0
      do i = 1, size(accepted)
         if (accepted(i) .and. eval_ok(i)) n_acc = n_acc + 1
      end do
   end function count_accepted_eval

   logical function residual_replay_success(res_norm, tol_in) result(ok)
      implicit none
      real(dp), intent(in) :: res_norm, tol_in
      real(dp) :: tol_floor

      tol_floor = max(tol_in, tiny(1.0_dp))
      ok = (res_norm <= max(tol_floor, 4.0_dp*tol_floor))
   end function residual_replay_success

   subroutine load_fd_options(enabled, eps)
      implicit none
      logical, intent(out) :: enabled
      real(dp), intent(out) :: eps
      character(len=64) :: env_value
      integer :: env_len, env_stat, ios
      real(dp) :: parsed_eps

      enabled = .false.
      eps = 1.0e-6_dp
      call get_environment_variable("QN_REPLAY_FD_ENABLED", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         select case (trim(adjustl(env_value(1:env_len))))
         case ("1", "true", "TRUE", "True", "on", "ON", "On", "yes", "YES", "Yes")
            enabled = .true.
         case default
            enabled = .false.
         end select
      end if

      call get_environment_variable("QN_REPLAY_FD_EPS", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         read (env_value(1:env_len), *, iostat=ios) parsed_eps
         if (ios == 0 .and. parsed_eps > 0.0_dp) eps = parsed_eps
      end if
      if (enabled) write (*, '(A,ES12.4)') "[INFO] replay finite-difference audit eps=", eps
   end subroutine load_fd_options

   subroutine load_logical_option(env_name, enabled)
      implicit none
      character(len=*), intent(in) :: env_name
      logical, intent(out) :: enabled
      character(len=64) :: env_value
      integer :: env_len, env_stat

      enabled = .false.
      call get_environment_variable(env_name, env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         select case (trim(adjustl(env_value(1:env_len))))
         case ("1", "true", "TRUE", "True", "on", "ON", "On", "yes", "YES", "Yes")
            enabled = .true.
         case default
            enabled = .false.
         end select
      end if
      if (enabled) write (*, '(A,A)') "[INFO] enabled option ", trim(env_name)
   end subroutine load_logical_option

   subroutine open_trace_output(enabled, unit_id, path)
      implicit none
      logical, intent(out) :: enabled
      integer, intent(out) :: unit_id
      character(len=*), intent(out) :: path
      character(len=512) :: env_value
      integer :: env_len, env_stat, ios

      enabled = .false.
      unit_id = -1
      path = ""
      call get_environment_variable("QN_REPLAY_TRACE_CSV", env_value, length=env_len, status=env_stat)
      if (env_stat /= 0 .or. env_len <= 0) return
      path = trim(env_value(1:env_len))
      open (newunit=unit_id, file=trim(path), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[WARN] Failed to open replay trace CSV:", trim(path)
         unit_id = -1
         return
      end if
      enabled = .true.
      write (unit_id, '(A)') &
         "sample_idx,proposal_idx,attempt_idx,route_code,iter_idx,backtrack_idx,alpha,res_norm,accepted,eval_ok," // &
         "z_prop_re,z_prop_im,z_flow_re,z_flow_im,virial_flow_re,virial_flow_im"
      write (*, '(A,1X,A)') "[INFO] replay trace CSV:", trim(path)
   end subroutine open_trace_output

   subroutine write_replay_trace_rows(unit_id, sample_idx, z_prop, z_flow_local, res_norm, alpha_local, &
                                      iter_idx, backtrack_idx, attempt_idx, route_code, accepted, eval_ok)
      implicit none
      integer, intent(in) :: unit_id, sample_idx
      complex(dp), intent(in) :: z_prop(:), z_flow_local(:)
      real(dp), intent(in) :: res_norm(:), alpha_local(:)
      integer, intent(in) :: iter_idx(:), backtrack_idx(:), attempt_idx(:), route_code(:)
      logical, intent(in) :: accepted(:), eval_ok(:)
      integer :: i, accepted_flag, eval_ok_flag
      real(dp) :: vir_re, vir_im

      do i = 1, size(res_norm)
         accepted_flag = merge(1, 0, accepted(i))
         eval_ok_flag = merge(1, 0, eval_ok(i))
         call virial_re_im(z_flow_local(i), vir_re, vir_im)
         write (unit_id, &
                '(I0,",",I0,",",I0,",",I0,",",I0,",",I0,",",ES24.16,",",ES24.16,",",I0,",",I0,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16)') &
            sample_idx, i, attempt_idx(i), route_code(i), iter_idx(i), backtrack_idx(i), alpha_local(i), res_norm(i), &
            accepted_flag, eval_ok_flag, real(z_prop(i), dp), aimag(z_prop(i)), real(z_flow_local(i), dp), aimag(z_flow_local(i)), &
            vir_re, vir_im
      end do
   end subroutine write_replay_trace_rows

   subroutine finite_difference_delz_map(tol_in, max_iter_in, x0_in, z0_in, delz_in, eps_base, central_route, &
                                         ok, det_out, logabsdet_out, route_stable)
      implicit none
      real(dp), intent(in) :: tol_in, x0_in(:), delz_in(:), eps_base
      integer, intent(in) :: max_iter_in, central_route
      complex(dp), intent(in) :: z0_in(:)
      logical, intent(out) :: ok, route_stable
      real(dp), intent(out) :: det_out, logabsdet_out

      real(dp) :: eps1, eps2
      real(dp), allocatable :: delp(:), delm(:)
      complex(dp) :: zp1, zm1, zp2, zm2
      integer :: route_p1, route_m1, route_p2, route_m2
      logical :: ok_p1, ok_m1, ok_p2, ok_m2
      real(dp) :: d11, d12, d21, d22

      ok = .false.
      route_stable = .false.
      det_out = ieee_value(0.0_dp, ieee_quiet_nan)
      logabsdet_out = ieee_value(0.0_dp, ieee_quiet_nan)
      if (size(delz_in) /= 2 .or. size(z0_in) /= 1) return

      allocate (delp(size(delz_in)), delm(size(delz_in)))
      eps1 = eps_base*max(1.0_dp, abs(delz_in(1)))
      eps2 = eps_base*max(1.0_dp, abs(delz_in(2)))

      delp = delz_in
      delm = delz_in
      delp(1) = delp(1) + eps1
      delm(1) = delm(1) - eps1
      call solve_endpoint_for_delz(tol_in, max_iter_in, x0_in, z0_in, delp, zp1, route_p1, ok_p1)
      call solve_endpoint_for_delz(tol_in, max_iter_in, x0_in, z0_in, delm, zm1, route_m1, ok_m1)

      delp = delz_in
      delm = delz_in
      delp(2) = delp(2) + eps2
      delm(2) = delm(2) - eps2
      call solve_endpoint_for_delz(tol_in, max_iter_in, x0_in, z0_in, delp, zp2, route_p2, ok_p2)
      call solve_endpoint_for_delz(tol_in, max_iter_in, x0_in, z0_in, delm, zm2, route_m2, ok_m2)

      if (.not. (ok_p1 .and. ok_m1 .and. ok_p2 .and. ok_m2)) then
         deallocate (delp, delm)
         return
      end if

      d11 = (real(zp1, dp) - real(zm1, dp))/(2.0_dp*eps1)
      d21 = (aimag(zp1) - aimag(zm1))/(2.0_dp*eps1)
      d12 = (real(zp2, dp) - real(zm2, dp))/(2.0_dp*eps2)
      d22 = (aimag(zp2) - aimag(zm2))/(2.0_dp*eps2)
      det_out = d11*d22 - d12*d21
      if (ieee_is_finite(det_out) .and. abs(det_out) > tiny(1.0_dp)) then
         logabsdet_out = log(abs(det_out))
      end if
      route_stable = (route_p1 == central_route .and. route_m1 == central_route .and. &
                      route_p2 == central_route .and. route_m2 == central_route)
      ok = .true.
      deallocate (delp, delm)
   end subroutine finite_difference_delz_map

   subroutine solve_endpoint_for_delz(tol_in, max_iter_in, x0_in, z0_in, delz_in, z_endpoint, route_code, ok)
      implicit none
      real(dp), intent(in) :: tol_in, x0_in(:), delz_in(:)
      integer, intent(in) :: max_iter_in
      complex(dp), intent(in) :: z0_in(:)
      complex(dp), intent(out) :: z_endpoint
      integer, intent(out) :: route_code
      logical, intent(out) :: ok

      complex(dp), allocatable :: z_work(:), jac_work(:, :)
      real(dp), allocatable :: Jl_work(:), x_new_work(:)
      complex(dp), allocatable :: z_prop(:), z_flow_local(:)
      real(dp), allocatable :: res_norm(:), alpha_local(:)
      integer, allocatable :: iter_local(:), backtrack_local(:), attempt_local(:), route_local(:)
      logical, allocatable :: accepted_local(:), eval_ok_local(:)
      logical :: flow_err, solve_err, trace_avail
      integer :: prop_count, idx(1)

      ok = .false.
      route_code = -1
      z_endpoint = cmplx(ieee_value(0.0_dp, ieee_quiet_nan), ieee_value(0.0_dp, ieee_quiet_nan), dp)
      if (size(z0_in) /= 1) return

      allocate (z_work(size(z0_in)), jac_work(size(z0_in), size(z0_in)), Jl_work(size(delz_in)), x_new_work(size(x0_in)))
      z_work = z0_in
      call flow(x0_in, z_work, jac_work, flow_err)
      if (flow_err) then
         deallocate (z_work, jac_work, Jl_work, x_new_work)
         return
      end if

      call solve_constraint_quasi_newton(evaluate_constraint_residual, tol_in, max_iter_in, x0_in, z0_in, delz_in, &
                                         solve_err, Jl_work, x_new_work, jac_work)
      call get_quasi_newton_last_trace_r2c(trace_avail, prop_count, z_prop, z_flow_local, res_norm, alpha_local, &
                                           iter_local, backtrack_local, attempt_local, accepted_local, eval_ok_local, route_local)
      if (trace_avail .and. prop_count > 0) then
         idx = minloc(res_norm)
         if (allocated(route_local)) route_code = route_local(idx(1))
      end if
      if (solve_err) then
         deallocate (z_work, jac_work, Jl_work, x_new_work)
         return
      end if

      z_work = z0_in
      call flow(x_new_work, z_work, jac_work, flow_err)
      if (flow_err) then
         deallocate (z_work, jac_work, Jl_work, x_new_work)
         return
      end if
      z_endpoint = z_work(1)
      ok = .true.
      deallocate (z_work, jac_work, Jl_work, x_new_work)
   end subroutine solve_endpoint_for_delz

   subroutine local_step_reverse_audit(x0_in, z0_in, delz_in, ok, dx_inf, dz_inf, dp_inf, &
                                       out_x2, out_z_re, out_z_im, out_flow_res)
      implicit none
      real(dp), intent(in) :: x0_in(:), delz_in(:)
      complex(dp), intent(in) :: z0_in(:)
      logical, intent(out) :: ok
      real(dp), intent(out) :: dx_inf, dz_inf, dp_inf
      real(dp), intent(out) :: out_x2, out_z_re, out_z_im, out_flow_res

      integer :: n, n2
      real(dp) :: h
      logical :: err, fwd_ok, rev_ok_local
      complex(dp), allocatable :: ds_val(:)
      complex(dp), allocatable :: z_check(:), jaci(:, :), jacf(:, :), rjac(:, :)
      complex(dp), allocatable :: fz(:), rz(:)
      real(dp), allocatable :: E0_real(:), E0_perp(:), dV(:)
      real(dp), allocatable :: momentum(:), init_momentum(:), rev_momentum(:)
      real(dp), allocatable :: fx(:), rx(:)
      type(rattle_step_workspace_t) :: ws_fwd, ws_rev

      ok = .false.
      dx_inf = ieee_value(0.0_dp, ieee_quiet_nan)
      dz_inf = ieee_value(0.0_dp, ieee_quiet_nan)
      dp_inf = ieee_value(0.0_dp, ieee_quiet_nan)
      out_x2 = ieee_value(0.0_dp, ieee_quiet_nan)
      out_z_re = ieee_value(0.0_dp, ieee_quiet_nan)
      out_z_im = ieee_value(0.0_dp, ieee_quiet_nan)
      out_flow_res = ieee_value(0.0_dp, ieee_quiet_nan)

      n = size(z0_in)
      n2 = 2*n
      if (n /= 1 .or. size(delz_in) /= n2) return
      if (config%integrator%integration_steps <= 0) return
      h = config%integrator%trajectory_length/real(config%integrator%integration_steps, dp)
      if (h <= 0.0_dp) return

      allocate (z_check(n), jaci(n, n), jacf(n, n), rjac(n, n), fz(n), rz(n), ds_val(n))
      allocate (E0_real(n2), E0_perp(n2), dV(n2), momentum(n2), init_momentum(n2), rev_momentum(n2))
      allocate (fx(size(x0_in)), rx(size(x0_in)))

      z_check = z0_in
      call flow(x0_in, z_check, jaci, err)
      if (err) goto 900

      call ds(z0_in, ds_val)
      call complex_to_real(conjg(ds_val), E0_real)
      E0_perp = 0.0_dp
      call calculate_dV(n, E0_real, E0_perp, dV, err)
      if (err) goto 900

      momentum = (delz_in + h*h*dV)/h
      init_momentum = momentum
      call rattle_step_core(x0_in, z0_in, h, fx, fz, jaci, jacf, momentum, fwd_ok, ws_fwd)
      if (.not. fwd_ok) goto 900

      rev_momentum = -momentum
      call rattle_step_core(fx, fz, h, rx, rz, jacf, rjac, rev_momentum, rev_ok_local, ws_rev)
      if (.not. rev_ok_local) goto 900

      dx_inf = max_abs_real(rx - x0_in)
      dz_inf = max_abs_complex(rz - z0_in)
      dp_inf = max_abs_real(rev_momentum + init_momentum)
      if (size(rx) >= 2) out_x2 = rx(2)
      if (size(rz) >= 1) then
         out_z_re = real(rz(1), dp)
         out_z_im = aimag(rz(1))
         z_check = rz
         call flow(rx, z_check, rjac, err)
         if (.not. err) out_flow_res = max_abs_complex(z_check - rz)
      end if
      ok = .true.

900   continue
      call release_rattle_step_workspace(ws_fwd)
      call release_rattle_step_workspace(ws_rev)
      if (allocated(ds_val)) deallocate (ds_val)
      if (allocated(z_check)) deallocate (z_check)
      if (allocated(jaci)) deallocate (jaci)
      if (allocated(jacf)) deallocate (jacf)
      if (allocated(rjac)) deallocate (rjac)
      if (allocated(fz)) deallocate (fz)
      if (allocated(rz)) deallocate (rz)
      if (allocated(E0_real)) deallocate (E0_real)
      if (allocated(E0_perp)) deallocate (E0_perp)
      if (allocated(dV)) deallocate (dV)
      if (allocated(momentum)) deallocate (momentum)
      if (allocated(init_momentum)) deallocate (init_momentum)
      if (allocated(rev_momentum)) deallocate (rev_momentum)
      if (allocated(fx)) deallocate (fx)
      if (allocated(rx)) deallocate (rx)

   end subroutine local_step_reverse_audit

   real(dp) function max_abs_real(vals) result(out)
      implicit none
      real(dp), intent(in) :: vals(:)

      if (size(vals) <= 0) then
         out = 0.0_dp
      else
         out = maxval(abs(vals))
      end if
   end function max_abs_real

   real(dp) function max_abs_complex(vals) result(out)
      implicit none
      complex(dp), intent(in) :: vals(:)

      if (size(vals) <= 0) then
         out = 0.0_dp
      else
         out = maxval(abs(vals))
      end if
   end function max_abs_complex

   subroutine virial_re_im(z_val, out_re, out_im)
      implicit none
      complex(dp), intent(in) :: z_val
      real(dp), intent(out) :: out_re, out_im
      complex(dp) :: obs
      complex(dp), parameter :: imag_unit = cmplx(0.0_dp, 1.0_dp, dp)

      obs = -imag_unit*(z_val - imag_unit*model_beta)*(z_val**2 + model_alpha) - 2.0_dp
      out_re = real(obs, dp)
      out_im = aimag(obs)
   end subroutine virial_re_im

end program replay_quasi_failures_app

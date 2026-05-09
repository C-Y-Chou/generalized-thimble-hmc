module hmc_constraints
   use utils
   use, intrinsic :: iso_fortran_env, only: int64
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use solve_flow, only: flowz, set_intode_stage_trace, set_intode_newton_iter_trace, intode_stage_newton, &
                         intode_status_unknown, intode_status_success, intode_status_success_zero_time, &
                         intode_status_success_stiff_rescue, intode_status_success_solver_assist, &
                         intode_status_failure_max_steps, intode_status_failure_invalid, intode_status_failure_h_min
   use perf_profile, only: perf_tic, perf_toc, PERF_NEWTON, PERF_PROJECTED_STEP
   implicit none

   integer, save :: post_qn_refine_log_limit = 0
   integer, save :: post_qn_refine_log_count = 0
   logical, save :: post_qn_refine_log_loaded = .false.
   integer(int64), save :: newton_eval_flow_status_success = 0_int64
   integer(int64), save :: newton_eval_flow_status_zero_time = 0_int64
   integer(int64), save :: newton_eval_flow_status_stiff_rescue = 0_int64
   integer(int64), save :: newton_eval_flow_status_solver_assist = 0_int64
   integer(int64), save :: newton_eval_flow_status_failure_max_steps = 0_int64
   integer(int64), save :: newton_eval_flow_status_failure_invalid = 0_int64
   integer(int64), save :: newton_eval_flow_status_failure_h_min = 0_int64
   integer(int64), save :: newton_eval_flow_status_unknown = 0_int64

contains

   subroutine reset_newton_eval_flow_status_counts()
      implicit none

      newton_eval_flow_status_success = 0_int64
      newton_eval_flow_status_zero_time = 0_int64
      newton_eval_flow_status_stiff_rescue = 0_int64
      newton_eval_flow_status_solver_assist = 0_int64
      newton_eval_flow_status_failure_max_steps = 0_int64
      newton_eval_flow_status_failure_invalid = 0_int64
      newton_eval_flow_status_failure_h_min = 0_int64
      newton_eval_flow_status_unknown = 0_int64
   end subroutine reset_newton_eval_flow_status_counts

   subroutine get_newton_eval_flow_status_counts(success, zero_time, stiff_rescue, solver_assist, &
                                                 failure_max_steps, failure_invalid, failure_h_min, unknown)
      implicit none
      integer(int64), intent(out) :: success, zero_time, stiff_rescue, solver_assist
      integer(int64), intent(out) :: failure_max_steps, failure_invalid, failure_h_min, unknown

      success = newton_eval_flow_status_success
      zero_time = newton_eval_flow_status_zero_time
      stiff_rescue = newton_eval_flow_status_stiff_rescue
      solver_assist = newton_eval_flow_status_solver_assist
      failure_max_steps = newton_eval_flow_status_failure_max_steps
      failure_invalid = newton_eval_flow_status_failure_invalid
      failure_h_min = newton_eval_flow_status_failure_h_min
      unknown = newton_eval_flow_status_unknown
   end subroutine get_newton_eval_flow_status_counts

   subroutine record_newton_eval_flow_status(flow_status)
      implicit none
      integer, intent(in) :: flow_status

      select case (flow_status)
      case (intode_status_success)
         newton_eval_flow_status_success = newton_eval_flow_status_success + 1_int64
      case (intode_status_success_zero_time)
         newton_eval_flow_status_zero_time = newton_eval_flow_status_zero_time + 1_int64
      case (intode_status_success_stiff_rescue)
         newton_eval_flow_status_stiff_rescue = newton_eval_flow_status_stiff_rescue + 1_int64
      case (intode_status_success_solver_assist)
         newton_eval_flow_status_solver_assist = newton_eval_flow_status_solver_assist + 1_int64
      case (intode_status_failure_max_steps)
         newton_eval_flow_status_failure_max_steps = newton_eval_flow_status_failure_max_steps + 1_int64
      case (intode_status_failure_invalid)
         newton_eval_flow_status_failure_invalid = newton_eval_flow_status_failure_invalid + 1_int64
      case (intode_status_failure_h_min)
         newton_eval_flow_status_failure_h_min = newton_eval_flow_status_failure_h_min + 1_int64
      case default
         newton_eval_flow_status_unknown = newton_eval_flow_status_unknown + 1_int64
      end select
   end subroutine record_newton_eval_flow_status

   subroutine reset_constraint_newton_warm_start()
      implicit none
      ! Zero-start mode: retained for interface compatibility.
   end subroutine reset_constraint_newton_warm_start

   subroutine solve_constraint_newton(tol, max_iter, xt, z, del_z, step_size, ierr, Jl, x_new, jac, rescue_mode, x_seed, Jl_seed)
      implicit none

      integer, intent(in)          :: max_iter
      real(dp), intent(in)         :: tol
      real(dp), intent(in)         :: step_size
      logical, intent(out)         :: ierr
      real(dp), intent(in) :: xt(:), del_z(:)
      complex(dp), intent(in) :: z(:)
      real(dp), intent(out) :: x_new(:)
      real(dp), intent(out) :: Jl(:)
      complex(dp), intent(in) :: jac(:, :)
      logical, intent(in), optional :: rescue_mode
      real(dp), intent(in), optional :: x_seed(:), Jl_seed(:)

      real(dp), allocatable, save :: B(:), jacr(:, :), jacr_lu(:, :)
      real(dp), allocatable, save :: xtu(:), u(:), dxi(:), au(:), av(:)
      real(dp), allocatable, save :: u_seed(:), x_trial(:)
      complex(dp), allocatable, save :: ld(:), ld_seed(:)
      integer, allocatable, save :: ipiv(:)
      integer :: n, n2, info
      logical :: attempt_ok
      external :: dgetrf
      real(dp) :: t_prof

      call perf_tic(t_prof)
      n = size(z)
      n2 = 2*n

      x_new = xt
      Jl = 0.0_dp
      ierr = .true.
      if (size(del_z) /= n2 .or. size(Jl) /= n2 .or. size(x_new) /= size(xt)) then
         call perf_toc(PERF_NEWTON, t_prof)
         return
      end if
      if (size(xt) /= n + 1) then
         call perf_toc(PERF_NEWTON, t_prof)
         return
      end if

      call ensure_real_vec(B, n2)
      call ensure_real_mat(jacr, n2, n2)
      call ensure_real_mat(jacr_lu, n2, n2)
      call ensure_int_vec(ipiv, n2)
      call ensure_real_vec(xtu, 1 + n)
      call ensure_complex_vec(ld, n)
      call ensure_real_vec(u, n)
      call ensure_real_vec(dxi, n2)
      call ensure_real_vec(au, n2)
      call ensure_real_vec(av, n2)
      call ensure_real_vec(u_seed, n)
      call ensure_complex_vec(ld_seed, n)
      call ensure_real_vec(x_trial, n + 1)

      call map_to_real_mat(jac, jacr)
      jacr_lu = jacr
      call dgetrf(n2, n2, jacr_lu, n2, ipiv, info)
      if (info /= 0) then
         ierr = .true.
         call perf_toc(PERF_NEWTON, t_prof)
         return
      end if

      if (.not. ieee_is_finite(step_size)) then
         call perf_toc(PERF_NEWTON, t_prof)
         return
      end if
      u_seed = 0.0_dp
      ld_seed = cmplx(0.0_dp, 0.0_dp, dp)
      if (present(x_seed)) then
         if (size(x_seed) == size(xt)) then
            u_seed = x_seed(2:) - xt(2:)
            if (.not. all(ieee_is_finite(u_seed))) u_seed = 0.0_dp
         end if
      end if
      if (present(Jl_seed)) then
         if (size(Jl_seed) == n2) then
            call real_to_complex(Jl_seed, ld_seed)
         end if
      end if
      call solve_constraint_newton_seeded(tol, max_iter, xt, z, del_z, jacr, jacr_lu, ipiv, &
                                          u_seed, ld_seed, B, xtu, u, ld, dxi, au, av, attempt_ok, x_trial, &
                                          rescue_mode=rescue_mode)

      if (attempt_ok) then
         x_new = x_trial
         call complex_to_real(ld, Jl)
         ierr = .false.
      else
         ierr = .true.
      end if
      call perf_toc(PERF_NEWTON, t_prof)
   end subroutine solve_constraint_newton

   subroutine solve_constraint_newton_seeded(tol, max_iter, xt, z, del_z, jacr, jacr_lu, ipiv, &
                                             u_seed, ld_seed, B, xtu, u, ld, dxi, au, av, converged, x_new, &
                                             rescue_mode)
      implicit none

      integer, intent(in) :: max_iter
      real(dp), intent(in) :: tol
      real(dp), intent(in) :: xt(:), del_z(:), jacr(:, :), jacr_lu(:, :)
      complex(dp), intent(in) :: z(:), ld_seed(:)
      integer, intent(in) :: ipiv(:)
      real(dp), intent(in) :: u_seed(:)
      real(dp), intent(inout) :: B(:), xtu(:), u(:), dxi(:), au(:), av(:)
      complex(dp), intent(inout) :: ld(:)
      logical, intent(out) :: converged
      real(dp), intent(out) :: x_new(:)
      logical, intent(in), optional :: rescue_mode

      real(dp) :: residual, residual_prev, residual_best, rel_improvement
      real(dp) :: near_tol, stagnation_floor, diverge_floor
      real(dp) :: step_norm, step_floor
      integer :: flow_status, n, iter, diverge_count, severe_diverge_count, stagnation_count, tiny_step_count, i
      integer :: iter_cap, iter_cap_hard, near_extend_chunk
      complex(dp) :: z_new(size(z))
      logical :: solve_failed, seed_is_zero, rescue_local
      integer :: backtrack_idx
      real(dp) :: alpha_ls, alpha_best, residual_trial
      character(len=64) :: env_value
      integer :: env_len, env_stat, ios_env, parsed_log_limit
      logical :: have_trial
      real(dp), allocatable :: u_trial(:), u_best(:), B_trial(:), B_best(:)
      complex(dp), allocatable :: ld_trial(:), ld_best(:)

      n = size(z)
      rescue_local = .false.
      if (present(rescue_mode)) rescue_local = rescue_mode
      if (.not. post_qn_refine_log_loaded) then
         post_qn_refine_log_loaded = .true.
         call get_environment_variable("QN_POST_NEWTON_REFINE_LOG_FIRST", env_value, length=env_len, status=env_stat)
         if (env_stat == 0 .and. env_len > 0) then
            read (env_value(1:env_len), *, iostat=ios_env) parsed_log_limit
            if (ios_env == 0 .and. parsed_log_limit >= 0) then
               post_qn_refine_log_limit = parsed_log_limit
            end if
         end if
      end if
      allocate (u_trial(n), u_best(n), B_trial(size(B)), B_best(size(B)), ld_trial(n), ld_best(n))
      converged = .false.
      x_new = xt
      u = u_seed
      ld = ld_seed
      xtu = xt
      seed_is_zero = .true.
      do i = 1, n
         if (u(i) /= 0.0_dp .or. ld(i) /= cmplx(0.0_dp, 0.0_dp, dp)) then
            seed_is_zero = .false.
            exit
         end if
      end do

      if (seed_is_zero) then
         B = del_z
         residual_prev = norm2(B)
      else
         xtu(2:) = xt(2:) + u
         call set_intode_stage_trace(intode_stage_newton)
         call set_intode_newton_iter_trace(0)
         flow_status = intode_status_unknown
         call flowz(xtu, z_new, solve_failed, flow_status)
         call record_newton_eval_flow_status(flow_status)
         if (solve_failed) then
            return
         end if
         z_new = z - z_new - ld
         call complex_to_real(z_new, B)
         B = B + del_z
         residual_prev = norm2(B)
      end if

      if (.not. ieee_is_finite(residual_prev)) return
      if (rescue_local .and. post_qn_refine_log_count < post_qn_refine_log_limit) then
         post_qn_refine_log_count = post_qn_refine_log_count + 1
         write (*, '(A,I0,A,ES24.16,A,ES24.16,A,ES24.16,A,L1)') &
            "[POST_QN_REFINE_INIT_NORM] idx=", post_qn_refine_log_count, &
            " norm=", residual_prev, " tol=", tol, " norm_over_tol=", residual_prev/max(tol, tiny(1.0_dp)), &
            " seed_is_zero=", seed_is_zero
      end if
      if (residual_prev < tol) then
         x_new = xtu
         converged = .true.
         return
      end if

      if (rescue_local) then
         near_tol = max(1.0e4_dp*tol, 1.0e-11_dp)
         stagnation_floor = max(1.0e6_dp*tol, 1.0e-8_dp)
         diverge_floor = max(1.0e7_dp*tol, 1.0e-6_dp)
         near_extend_chunk = max(32, max_iter/2)
      else
         near_tol = max(2.0e2_dp*tol, 1.0e-11_dp)
         stagnation_floor = max(1.0e4_dp*tol, 1.0e-8_dp)
         diverge_floor = max(1.0e5_dp*tol, 1.0e-6_dp)
         near_extend_chunk = max(12, max_iter/4)
      end if
      iter_cap = max_iter
      if (rescue_local) then
         iter_cap_hard = max_iter + max(400, 4*max_iter)
      else
         iter_cap_hard = max_iter + max(80, max_iter)
      end if
      residual_best = residual_prev
      diverge_count = 0
      severe_diverge_count = 0
      stagnation_count = 0
      tiny_step_count = 0

      iter = 0
      do while (iter < iter_cap)
         iter = iter + 1
         call solve_projected_step(B, jacr, jacr_lu, ipiv, dxi, au, av, solve_failed)
         if (solve_failed) return

         if (rescue_local) then
            have_trial = .false.
            alpha_ls = 1.0_dp
            alpha_best = 0.0_dp
            residual = huge(1.0_dp)
            do backtrack_idx = 0, 10
               do i = 1, n
                  u_trial(i) = u(i) + alpha_ls*dxi(2*i - 1)
                  ld_trial(i) = ld(i) + alpha_ls*cmplx(av(2*i - 1), av(2*i), dp)
               end do
               xtu(2:) = xt(2:) + u_trial
               call set_intode_stage_trace(intode_stage_newton)
               call set_intode_newton_iter_trace(iter)
               flow_status = intode_status_unknown
               call flowz(xtu, z_new, solve_failed, flow_status)
               call record_newton_eval_flow_status(flow_status)
               if (.not. solve_failed) then
                  z_new = z - z_new - ld_trial
                  call complex_to_real(z_new, B_trial)
                  B_trial = B_trial + del_z
                  residual_trial = norm2(B_trial)
                  if (ieee_is_finite(residual_trial)) then
                     if ((.not. have_trial) .or. residual_trial < residual) then
                        residual = residual_trial
                        alpha_best = alpha_ls
                        u_best = u_trial
                        ld_best = ld_trial
                        B_best = B_trial
                        have_trial = .true.
                     end if
                     if (residual_trial <= residual_prev) exit
                  end if
               end if
               alpha_ls = 0.5_dp*alpha_ls
            end do
            if (.not. have_trial) return
            u = u_best
            ld = ld_best
            B = B_best
            step_norm = alpha_best*norm2(dxi)
            xtu(2:) = xt(2:) + u
         else
            step_norm = norm2(dxi)
            do i = 1, n
               u(i) = u(i) + dxi(2*i - 1)
               ld(i) = ld(i) + cmplx(av(2*i - 1), av(2*i), dp)
            end do

            xtu(2:) = xt(2:) + u
            call set_intode_stage_trace(intode_stage_newton)
            call set_intode_newton_iter_trace(iter)
            flow_status = intode_status_unknown
            call flowz(xtu, z_new, solve_failed, flow_status)
            call record_newton_eval_flow_status(flow_status)
            if (solve_failed) return

            z_new = z - z_new - ld
            call complex_to_real(z_new, B)
            B = B + del_z
            residual = norm2(B)
         end if
         if (.not. ieee_is_finite(residual)) return
         if (residual < tol) then
            x_new = xtu
            converged = .true.
            return
         end if

         if (residual < residual_best) residual_best = residual
         if (residual <= near_tol .and. iter_cap < iter_cap_hard) then
            iter_cap = min(iter_cap_hard, iter_cap + near_extend_chunk)
         end if

         if (residual > 1.20_dp*residual_prev) then
            diverge_count = diverge_count + 1
         else
            diverge_count = max(0, diverge_count - 1)
         end if
         if (residual > 1.50_dp*residual_prev .and. residual > diverge_floor) then
            severe_diverge_count = severe_diverge_count + 1
         else
            severe_diverge_count = max(0, severe_diverge_count - 1)
         end if

         rel_improvement = abs(residual_prev - residual)/max(1.0_dp, residual_prev)
         if (rel_improvement < 5.0e-4_dp) then
            stagnation_count = stagnation_count + 1
         else
            stagnation_count = 0
         end if

         step_floor = sqrt(epsilon(1.0_dp))*max(1.0_dp, norm2(u))
         if (step_norm <= 10.0_dp*step_floor) then
            tiny_step_count = tiny_step_count + 1
         else
            tiny_step_count = max(0, tiny_step_count - 1)
         end if

         if (rescue_local) then
            if (severe_diverge_count >= 10 .or. diverge_count >= 30) return
            if (iter >= min(80, max_iter) .and. stagnation_count >= 80 .and. tiny_step_count >= 40 .and. &
                residual > stagnation_floor .and. residual_best > max(20.0_dp*tol, 5.0e-11_dp)) return
         else
            if (severe_diverge_count >= 4 .or. diverge_count >= 10) return
            if (iter >= min(30, max_iter) .and. stagnation_count >= 24 .and. tiny_step_count >= 12 .and. &
                residual > stagnation_floor .and. residual_best > max(20.0_dp*tol, 5.0e-11_dp)) return
         end if

         residual_prev = residual
      end do

      deallocate (u_trial, u_best, B_trial, B_best, ld_trial, ld_best)
   end subroutine solve_constraint_newton_seeded

   subroutine solve_projected_step(B, jacr, jacr_lu, ipiv, dxi, au, av, ierr)
      implicit none
      real(dp), intent(in) :: B(:), jacr(:, :), jacr_lu(:, :)
      integer, intent(in) :: ipiv(:)
      real(dp), intent(out) :: dxi(:), au(:), av(:)
      logical, intent(out) :: ierr

      integer :: n2, info
      real(dp) :: t_prof
      external :: dgetrs, dgemv

      call perf_tic(t_prof)
      n2 = size(B)
      ierr = .false.

      if (size(dxi) /= n2 .or. size(au) /= n2 .or. size(av) /= n2) then
         ierr = .true.
         call perf_toc(PERF_PROJECTED_STEP, t_prof)
         return
      end if
      if (size(jacr, 1) /= n2 .or. size(jacr, 2) /= n2) then
         ierr = .true.
         call perf_toc(PERF_PROJECTED_STEP, t_prof)
         return
      end if
      if (size(jacr_lu, 1) /= n2 .or. size(jacr_lu, 2) /= n2 .or. size(ipiv) /= n2) then
         ierr = .true.
         call perf_toc(PERF_PROJECTED_STEP, t_prof)
         return
      end if

      dxi = B
      call dgetrs('N', n2, 1, jacr_lu, n2, ipiv, dxi, n2, info)
      if (info /= 0) then
         ierr = .true.
         call perf_toc(PERF_PROJECTED_STEP, t_prof)
         return
      end if

      au = dxi
      call real_vec(au)
      call dgemv('N', n2, n2, 1.0_dp, jacr, n2, au, 1, 0.0_dp, av, 1)
      au = av
      av = B - au
      call perf_toc(PERF_PROJECTED_STEP, t_prof)
   end subroutine solve_projected_step

   subroutine ensure_real_vec(buf, n_need)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) /= n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_real_vec

   subroutine ensure_int_vec(buf, n_need)
      implicit none
      integer, allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) /= n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_int_vec

   subroutine ensure_complex_vec(buf, n_need)
      implicit none
      complex(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) /= n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_complex_vec

   subroutine ensure_real_mat(buf, nr, nc)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:, :)
      integer, intent(in) :: nr, nc

      if (.not. allocated(buf)) then
         allocate (buf(nr, nc))
      elseif (size(buf, 1) /= nr .or. size(buf, 2) /= nc) then
         deallocate (buf)
         allocate (buf(nr, nc))
      end if
   end subroutine ensure_real_mat

end module hmc_constraints

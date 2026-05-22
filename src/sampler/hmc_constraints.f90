module hmc_constraints
   use utils, only: dp, complex_to_real, real_to_complex, real_vec
   use, intrinsic :: iso_fortran_env, only: int64
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use solve_flow, only: flowz, flow_workspace_t, intode_diagnostics_context_t, set_intode_stage_trace, set_intode_newton_iter_trace, &
                         intode_stage_newton, &
                         intode_status_unknown, intode_status_success, intode_status_success_zero_time, &
                         intode_status_success_stiff_rescue, intode_status_success_solver_assist, &
                         intode_status_failure_max_steps, intode_status_failure_invalid, intode_status_failure_h_min
   use hmc_kernels, only: real_jacobian_cache_t, prepare_real_jacobian_cache, release_real_jacobian_cache
   use perf_profile, only: perf_tic, perf_toc, PERF_NEWTON, PERF_PROJECTED_STEP
   implicit none

   type :: newton_eval_flow_status_context_t
      integer(int64) :: success = 0_int64
      integer(int64) :: zero_time = 0_int64
      integer(int64) :: stiff_rescue = 0_int64
      integer(int64) :: solver_assist = 0_int64
      integer(int64) :: failure_max_steps = 0_int64
      integer(int64) :: failure_invalid = 0_int64
      integer(int64) :: failure_h_min = 0_int64
      integer(int64) :: unknown = 0_int64
   end type newton_eval_flow_status_context_t

   type(newton_eval_flow_status_context_t), target, save :: module_newton_eval_flow_status_context

   type :: newton_constraint_workspace_t
      real(dp), allocatable :: B(:)
      real(dp), allocatable :: xtu(:), u(:), dxi(:), au(:), av(:)
      real(dp), allocatable :: u_seed(:), x_trial(:)
      complex(dp), allocatable :: ld(:), ld_seed(:)
      type(real_jacobian_cache_t) :: jac_cache
   end type newton_constraint_workspace_t

contains

   subroutine resolve_newton_eval_flow_status_context(context, active_context)
      implicit none
      type(newton_eval_flow_status_context_t), intent(inout), optional, target :: context
      type(newton_eval_flow_status_context_t), pointer :: active_context

      if (present(context)) then
         active_context => context
      else
         active_context => module_newton_eval_flow_status_context
      end if
   end subroutine resolve_newton_eval_flow_status_context

   subroutine reset_newton_eval_flow_status_counts(context)
      implicit none
      type(newton_eval_flow_status_context_t), intent(inout), optional, target :: context
      type(newton_eval_flow_status_context_t), pointer :: active_context

      call resolve_newton_eval_flow_status_context(context, active_context)
      active_context%success = 0_int64
      active_context%zero_time = 0_int64
      active_context%stiff_rescue = 0_int64
      active_context%solver_assist = 0_int64
      active_context%failure_max_steps = 0_int64
      active_context%failure_invalid = 0_int64
      active_context%failure_h_min = 0_int64
      active_context%unknown = 0_int64
   end subroutine reset_newton_eval_flow_status_counts

   subroutine get_newton_eval_flow_status_counts(success, zero_time, stiff_rescue, solver_assist, &
                                                 failure_max_steps, failure_invalid, failure_h_min, unknown, context)
      implicit none
      integer(int64), intent(out) :: success, zero_time, stiff_rescue, solver_assist
      integer(int64), intent(out) :: failure_max_steps, failure_invalid, failure_h_min, unknown
      type(newton_eval_flow_status_context_t), intent(inout), optional, target :: context
      type(newton_eval_flow_status_context_t), pointer :: active_context

      call resolve_newton_eval_flow_status_context(context, active_context)
      success = active_context%success
      zero_time = active_context%zero_time
      stiff_rescue = active_context%stiff_rescue
      solver_assist = active_context%solver_assist
      failure_max_steps = active_context%failure_max_steps
      failure_invalid = active_context%failure_invalid
      failure_h_min = active_context%failure_h_min
      unknown = active_context%unknown
   end subroutine get_newton_eval_flow_status_counts

   subroutine record_newton_eval_flow_status(flow_status, context)
      implicit none
      integer, intent(in) :: flow_status
      type(newton_eval_flow_status_context_t), intent(inout), optional, target :: context
      type(newton_eval_flow_status_context_t), pointer :: active_context

      call resolve_newton_eval_flow_status_context(context, active_context)
      select case (flow_status)
      case (intode_status_success)
         active_context%success = active_context%success + 1_int64
      case (intode_status_success_zero_time)
         active_context%zero_time = active_context%zero_time + 1_int64
      case (intode_status_success_stiff_rescue)
         active_context%stiff_rescue = active_context%stiff_rescue + 1_int64
      case (intode_status_success_solver_assist)
         active_context%solver_assist = active_context%solver_assist + 1_int64
      case (intode_status_failure_max_steps)
         active_context%failure_max_steps = active_context%failure_max_steps + 1_int64
      case (intode_status_failure_invalid)
         active_context%failure_invalid = active_context%failure_invalid + 1_int64
      case (intode_status_failure_h_min)
         active_context%failure_h_min = active_context%failure_h_min + 1_int64
      case default
         active_context%unknown = active_context%unknown + 1_int64
      end select
   end subroutine record_newton_eval_flow_status

   subroutine release_newton_eval_flow_status_context(context)
      implicit none
      type(newton_eval_flow_status_context_t), intent(inout) :: context

      call reset_newton_eval_flow_status_counts(context)
   end subroutine release_newton_eval_flow_status_context

   subroutine reset_constraint_newton_warm_start()
      implicit none
      ! Zero-start mode: retained for interface compatibility.
   end subroutine reset_constraint_newton_warm_start

   subroutine solve_constraint_newton(tol, max_iter, xt, z, del_z, step_size, ierr, Jl, x_new, jac, x_seed, Jl_seed, workspace, &
                                      flow_workspace, newton_flow_status, intode_diagnostics, jac_cache)
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
      real(dp), intent(in), optional :: x_seed(:), Jl_seed(:)
      type(newton_constraint_workspace_t), intent(inout), optional, target :: workspace
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(newton_eval_flow_status_context_t), intent(inout), optional, target :: newton_flow_status
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(real_jacobian_cache_t), intent(inout), optional, target :: jac_cache

      type(newton_constraint_workspace_t), target :: local_workspace

      if (present(workspace)) then
         call solve_constraint_newton_with_workspace(tol, max_iter, xt, z, del_z, step_size, ierr, Jl, x_new, jac, &
                                                     x_seed, Jl_seed, workspace, flow_workspace, newton_flow_status, intode_diagnostics, &
                                                     jac_cache)
      else
         call solve_constraint_newton_with_workspace(tol, max_iter, xt, z, del_z, step_size, ierr, Jl, x_new, jac, &
                                                     x_seed, Jl_seed, local_workspace, flow_workspace, newton_flow_status, intode_diagnostics, &
                                                     jac_cache)
      end if
   end subroutine solve_constraint_newton

   subroutine solve_constraint_newton_with_workspace(tol, max_iter, xt, z, del_z, step_size, ierr, Jl, x_new, jac, &
                                                     x_seed, Jl_seed, workspace, flow_workspace, newton_flow_status, intode_diagnostics, &
                                                     jac_cache)
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
      real(dp), intent(in), optional :: x_seed(:), Jl_seed(:)
      type(newton_constraint_workspace_t), intent(inout), target :: workspace
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(newton_eval_flow_status_context_t), intent(inout), optional, target :: newton_flow_status
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics
      type(real_jacobian_cache_t), intent(inout), optional, target :: jac_cache

      integer :: n, n2
      logical :: attempt_ok
      type(real_jacobian_cache_t), pointer :: active_cache
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
      if (size(jac, 1) /= n .or. size(jac, 2) /= n) then
         call perf_toc(PERF_NEWTON, t_prof)
         return
      end if
      if ((.not. ieee_is_finite(tol)) .or. tol <= 0.0_dp) then
         call perf_toc(PERF_NEWTON, t_prof)
         return
      end if
      if (.not. ieee_is_finite(step_size)) then
         call perf_toc(PERF_NEWTON, t_prof)
         return
      end if

      call ensure_real_vec(workspace%B, n2)
      call ensure_real_vec(workspace%xtu, 1 + n)
      call ensure_complex_vec(workspace%ld, n)
      call ensure_real_vec(workspace%u, n)
      call ensure_real_vec(workspace%dxi, n2)
      call ensure_real_vec(workspace%au, n2)
      call ensure_real_vec(workspace%av, n2)
      call ensure_real_vec(workspace%u_seed, n)
      call ensure_complex_vec(workspace%ld_seed, n)
      call ensure_real_vec(workspace%x_trial, n + 1)

      if (present(jac_cache)) then
         active_cache => jac_cache
      else
         active_cache => workspace%jac_cache
      end if
      call prepare_real_jacobian_cache(jac, active_cache, ierr)
      if (ierr) then
         call perf_toc(PERF_NEWTON, t_prof)
         return
      end if

      workspace%u_seed = 0.0_dp
      workspace%ld_seed = cmplx(0.0_dp, 0.0_dp, dp)
      if (present(x_seed)) then
         if (size(x_seed) == size(xt)) then
            workspace%u_seed = x_seed(2:) - xt(2:)
            if (.not. all(ieee_is_finite(workspace%u_seed))) workspace%u_seed = 0.0_dp
         end if
      end if
      if (present(Jl_seed)) then
         if (size(Jl_seed) == n2) then
            call real_to_complex(Jl_seed, workspace%ld_seed)
         end if
      end if
      call solve_constraint_newton_seeded(tol, max_iter, xt, z, del_z, active_cache%jacr, active_cache%jacr_lu, active_cache%ipiv, &
                                          workspace%u_seed, workspace%ld_seed, workspace%B, workspace%xtu, workspace%u, &
                                          workspace%ld, workspace%dxi, workspace%au, workspace%av, attempt_ok, &
                                          workspace%x_trial, flow_workspace, newton_flow_status, intode_diagnostics)

      if (attempt_ok) then
         x_new = workspace%x_trial
         call complex_to_real(workspace%ld, Jl)
         ierr = .false.
      else
         ierr = .true.
      end if
      call perf_toc(PERF_NEWTON, t_prof)
   end subroutine solve_constraint_newton_with_workspace

   subroutine solve_constraint_newton_seeded(tol, max_iter, xt, z, del_z, jacr, jacr_lu, ipiv, &
                                             u_seed, ld_seed, B, xtu, u, ld, dxi, au, av, converged, x_new, flow_workspace, &
                                             newton_flow_status, intode_diagnostics)
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
      type(flow_workspace_t), intent(inout), optional :: flow_workspace
      type(newton_eval_flow_status_context_t), intent(inout), optional, target :: newton_flow_status
      type(intode_diagnostics_context_t), intent(inout), optional, target :: intode_diagnostics

      real(dp) :: residual, residual_prev, residual_best, rel_improvement
      real(dp) :: near_tol, stagnation_floor, diverge_floor
      real(dp) :: step_norm, step_floor
      integer :: flow_status, n, iter, diverge_count, severe_diverge_count, stagnation_count, tiny_step_count, i
      integer :: iter_cap, iter_cap_hard, near_extend_chunk
      complex(dp) :: z_new(size(z))
      logical :: solve_failed, seed_is_zero

      n = size(z)
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
         call set_intode_stage_trace(intode_stage_newton, flow_workspace)
         call set_intode_newton_iter_trace(0, flow_workspace)
         flow_status = intode_status_unknown
         call flowz(xtu, z_new, solve_failed, flow_status, flow_workspace, intode_diagnostics)
         call record_newton_eval_flow_status(flow_status, newton_flow_status)
         if (solve_failed) then
            return
         end if
         z_new = z - z_new - ld
         call complex_to_real(z_new, B)
         B = B + del_z
         residual_prev = norm2(B)
      end if

      if (.not. ieee_is_finite(residual_prev)) return
      if (residual_prev < tol) then
         x_new = xtu
         converged = .true.
         return
      end if

      near_tol = max(2.0e2_dp*tol, 1.0e-11_dp)
      stagnation_floor = max(1.0e4_dp*tol, 1.0e-8_dp)
      diverge_floor = max(1.0e5_dp*tol, 1.0e-6_dp)
      near_extend_chunk = max(12, max_iter/4)
      iter_cap = max_iter
      iter_cap_hard = max_iter + max(80, max_iter)
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

         step_norm = norm2(dxi)
         do i = 1, n
            u(i) = u(i) + dxi(2*i - 1)
            ld(i) = ld(i) + cmplx(av(2*i - 1), av(2*i), dp)
         end do

         xtu(2:) = xt(2:) + u
         call set_intode_stage_trace(intode_stage_newton, flow_workspace)
         call set_intode_newton_iter_trace(iter, flow_workspace)
         flow_status = intode_status_unknown
         call flowz(xtu, z_new, solve_failed, flow_status, flow_workspace, intode_diagnostics)
         call record_newton_eval_flow_status(flow_status, newton_flow_status)
         if (solve_failed) return

         z_new = z - z_new - ld
         call complex_to_real(z_new, B)
         B = B + del_z
         residual = norm2(B)
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

         if (severe_diverge_count >= 4 .or. diverge_count >= 10) return
         if (iter >= min(30, max_iter) .and. stagnation_count >= 24 .and. tiny_step_count >= 12 .and. &
             residual > stagnation_floor .and. residual_best > max(20.0_dp*tol, 5.0e-11_dp)) return

         residual_prev = residual
      end do

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

   subroutine release_newton_constraint_workspace(workspace)
      implicit none
      type(newton_constraint_workspace_t), intent(inout) :: workspace

      if (allocated(workspace%B)) deallocate (workspace%B)
      if (allocated(workspace%xtu)) deallocate (workspace%xtu)
      if (allocated(workspace%u)) deallocate (workspace%u)
      if (allocated(workspace%dxi)) deallocate (workspace%dxi)
      if (allocated(workspace%au)) deallocate (workspace%au)
      if (allocated(workspace%av)) deallocate (workspace%av)
      if (allocated(workspace%u_seed)) deallocate (workspace%u_seed)
      if (allocated(workspace%x_trial)) deallocate (workspace%x_trial)
      if (allocated(workspace%ld)) deallocate (workspace%ld)
      if (allocated(workspace%ld_seed)) deallocate (workspace%ld_seed)
      call release_real_jacobian_cache(workspace%jac_cache)
   end subroutine release_newton_constraint_workspace

end module hmc_constraints

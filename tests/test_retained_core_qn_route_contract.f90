program test_retained_core_qn_route_contract
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use hmc_kernels, only: calculate_dV
   use model, only: ds
   use param_mod, only: cttol, read_parameters, state_seed_size_cfg
   use quasi_newton_linear_solver_mod, only: initial_guess_from_jacobian
   use quasi_newton_solver_mod, only: evaluate_constraint_residual, get_qn_official_dfols_policy, &
                                      get_quasi_newton_last_trace_r2c, qn_backend_official_dfols, &
                                      solve_constraint_quasi_newton
   use solve_flow, only: flow, flowzr, intode_status_is_strict_success, intode_status_unknown
   use utils, only: complex_to_real, dp, real_to_complex, x_set_flow_time, x_set_seed_real
   implicit none

   integer :: failures, n_seed, x_size, flow_status
   real(dp), allocatable :: seed(:), x(:), del_z(:), dV(:), E0_real(:), E0_perp(:)
   real(dp), allocatable :: xi(:), fq(:), Jl(:), Jl_solver(:), x_new(:), x_best(:)
   complex(dp), allocatable :: z(:), jac(:, :)
   logical :: flow_failed

   failures = 0
   call read_parameters()
   n_seed = state_seed_size_cfg()
   x_size = 1 + n_seed

   allocate (seed(n_seed), x(x_size), z(n_seed), jac(n_seed, n_seed))
   allocate (del_z(2*n_seed), dV(2*n_seed), E0_real(2*n_seed), E0_perp(2*n_seed))
   allocate (xi(2*n_seed), fq(2*n_seed), Jl(2*n_seed), Jl_solver(2*n_seed), x_new(x_size), x_best(2*n_seed))

   call fill_seed(seed)
   call x_set_flow_time(x, 0.08_dp)
   call x_set_seed_real(x, seed)
   flow_status = intode_status_unknown
   call flow(x, z, jac, flow_failed, flow_status)
   if (flow_failed .or. (.not. intode_status_is_strict_success(flow_status))) then
      write (*, '(A,I0)') "[ERROR] initial flow failed. status=", flow_status
      error stop 1
   end if

   call build_rattle_force_vector(z, dV, E0_real, E0_perp)
   del_z = -0.004_dp**2*dV
   call initial_guess_from_jacobian(jac, del_z, xi)

   call check_btn_paper_residual(x, z, jac, del_z, xi, fq, Jl, failures)
   call check_official_route_contract(x, z, jac, del_z, Jl_solver, x_new, x_best, failures)

   deallocate (seed, x, z, jac)
   deallocate (del_z, dV, E0_real, E0_perp)
   deallocate (xi, fq, Jl, Jl_solver, x_new, x_best)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] retained-core QN route contract failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] retained-core QN route contract complete."

contains

   subroutine fill_seed(seed)
      real(dp), intent(out) :: seed(:)
      integer :: i

      do i = 1, size(seed)
         seed(i) = 0.12_dp + 0.04_dp*real(i - 1, dp)
      end do
   end subroutine fill_seed

   subroutine build_rattle_force_vector(z, dV, E0_real, E0_perp)
      complex(dp), intent(in) :: z(:)
      real(dp), intent(out) :: dV(:), E0_real(:), E0_perp(:)

      complex(dp), allocatable :: ds_val(:), E0(:)
      logical :: has_error

      allocate (ds_val(size(z)), E0(size(z)))
      call ds(z, ds_val)
      E0 = conjg(ds_val)
      call complex_to_real(E0, E0_real)
      E0_perp = 0.0_dp
      call calculate_dV(size(z), E0_real, E0_perp, dV, has_error)
      if (has_error) then
         write (*, '(A)') "[ERROR] calculate_dV failed in QN contract setup."
         error stop 1
      end if
      deallocate (ds_val, E0)
   end subroutine build_rattle_force_vector

   subroutine check_btn_paper_residual(x, z, jac, del_z, xi, fq, Jl, failures)
      real(dp), intent(in) :: x(:), del_z(:), xi(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(inout) :: fq(:), Jl(:)
      integer, intent(inout) :: failures

      complex(dp), allocatable :: jlc_expected(:), del_z_complex(:), ztrial(:)
      real(dp), allocatable :: Jl_expected(:), fq_expected(:)
      logical :: eval_failed, replay_failed, ok
      integer :: n, replay_status
      real(dp) :: jl_err, fq_err
      real(dp), parameter :: tolerance = 5.0e-11_dp

      n = size(z)
      allocate (jlc_expected(n), del_z_complex(n), ztrial(n))
      allocate (Jl_expected(2*n), fq_expected(2*n))

      call evaluate_constraint_residual(x, z, xi, fq, del_z, eval_failed, Jl, jac)
      jlc_expected = -matmul(jac, xi(n + 1:) + cmplx(0.0_dp, 1.0_dp, dp)*xi(1:n))
      call complex_to_real(jlc_expected, Jl_expected)
      call real_to_complex(del_z, del_z_complex)
      ztrial = z + del_z_complex + jlc_expected
      replay_status = intode_status_unknown
      call flowzr(x, ztrial, replay_failed, replay_status)
      fq_expected(1:n) = aimag(ztrial)
      fq_expected(n + 1:) = xi(n + 1:)

      jl_err = norm2(Jl - Jl_expected)
      fq_err = norm2(fq - fq_expected)
      ok = (.not. eval_failed) .and. (.not. replay_failed) .and. &
           intode_status_is_strict_success(replay_status) .and. &
           ieee_is_finite(jl_err) .and. ieee_is_finite(fq_err) .and. &
           jl_err <= tolerance .and. fq_err <= tolerance

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] btn_paper_residual ok=", ok, &
         " jl_err=", jl_err, " fq_err=", fq_err, " tol=", tolerance
      if (.not. ok) failures = failures + 1

      deallocate (jlc_expected, del_z_complex, ztrial)
      deallocate (Jl_expected, fq_expected)
   end subroutine check_btn_paper_residual

   subroutine check_official_route_contract(x, z, jac, del_z, Jl, x_new, x_best, failures)
      real(dp), intent(in) :: x(:), del_z(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      real(dp), intent(inout) :: Jl(:), x_new(:), x_best(:)
      integer, intent(inout) :: failures

      logical :: ierr, available, ok_policy, ok_trace, has_eval_ok
      integer :: backend_code, npt, maxfun, proposal_count, idx
      logical :: objfun_has_noise
      real(dp) :: rhobeg, rhoend, model_abs_tol, model_rel_tol
      complex(dp), allocatable :: z_proposed(:), z_flowed(:)
      real(dp), allocatable :: residual_norm(:), alpha(:)
      integer, allocatable :: iter_idx(:), backtrack_idx(:), attempt_idx(:), route_code(:)
      logical, allocatable :: accepted(:), eval_ok(:)

      call get_qn_official_dfols_policy(backend_code, npt, maxfun, objfun_has_noise, &
                                        rhobeg, rhoend, model_abs_tol, model_rel_tol)
      ok_policy = backend_code == qn_backend_official_dfols .and. npt == 4 .and. maxfun == 250 .and. objfun_has_noise

      call solve_constraint_quasi_newton(evaluate_constraint_residual, cttol, 28, x, z, del_z, ierr, Jl, x_new, jac, &
                                         x_best_solution=x_best)
      call get_quasi_newton_last_trace_r2c(available, proposal_count, z_proposed, z_flowed, residual_norm, alpha, &
                                           iter_idx, backtrack_idx, attempt_idx, accepted, eval_ok, route_code)

      has_eval_ok = .false.
      ok_trace = available .and. proposal_count >= 1
      if (ok_trace) then
         do idx = 1, proposal_count
            ok_trace = ok_trace .and. route_code(idx) == 10 .and. attempt_idx(idx) == 1
            has_eval_ok = has_eval_ok .or. eval_ok(idx)
         end do
      end if
      ok_trace = ok_trace .and. has_eval_ok

      write (*, '(A,L1,A,I0,A,I0,A,L1,A,L1)') "[CHECK] official_qn_route_policy ok=", ok_policy, &
         " npt=", npt, " maxfun=", maxfun, " noise=", objfun_has_noise, " ierr=", ierr
      write (*, '(A,L1,A,L1,A,I0,A,L1)') "[CHECK] official_qn_route_trace ok=", ok_trace, &
         " available=", available, " proposal_count=", proposal_count, " has_eval_ok=", has_eval_ok
      if (.not. ok_policy) failures = failures + 1
      if (.not. ok_trace) failures = failures + 1

      if (allocated(z_proposed)) deallocate (z_proposed)
      if (allocated(z_flowed)) deallocate (z_flowed)
      if (allocated(residual_norm)) deallocate (residual_norm)
      if (allocated(alpha)) deallocate (alpha)
      if (allocated(iter_idx)) deallocate (iter_idx)
      if (allocated(backtrack_idx)) deallocate (backtrack_idx)
      if (allocated(attempt_idx)) deallocate (attempt_idx)
      if (allocated(route_code)) deallocate (route_code)
      if (allocated(accepted)) deallocate (accepted)
      if (allocated(eval_ok)) deallocate (eval_ok)
   end subroutine check_official_route_contract

end program test_retained_core_qn_route_contract

program test_retained_core_newton_contract
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite, ieee_quiet_nan, ieee_value
   use hmc_constraints, only: reset_newton_eval_flow_status_counts, solve_constraint_newton, solve_projected_step
   use hmc_kernels, only: calculate_dV
   use model, only: ds
   use param_mod, only: cttol, read_parameters, state_seed_size_cfg
   use solve_flow, only: flow, flowz, intode_status_is_strict_success, intode_status_unknown
   use utils, only: complex_to_real, dp, real_to_complex, x_set_flow_time, x_set_seed_real
   implicit none

   integer, parameter :: n_steps = 3
   real(dp), parameter :: step_sizes(n_steps) = [0.001_dp, 0.0015_dp, 0.002_dp]
   real(dp), parameter :: contract_flow_time = 1.0e-4_dp

   integer :: failures, n_seed, x_size, idx
   real(dp), allocatable :: seed(:), x(:), del_z(:), dV(:), E0_real(:), E0_perp(:), Jl(:)
   complex(dp), allocatable :: z(:), jac(:, :)
   real(dp) :: force_scale
   logical :: flow_failed
   integer :: flow_status

   failures = 0
   call read_parameters()
   n_seed = state_seed_size_cfg()
   x_size = 1 + n_seed

   allocate (seed(n_seed), x(x_size))
   allocate (z(n_seed), jac(n_seed, n_seed))
   allocate (del_z(2*n_seed), dV(2*n_seed), E0_real(2*n_seed), E0_perp(2*n_seed), Jl(2*n_seed))

   call fill_seed(seed)
   call x_set_flow_time(x, contract_flow_time)
   call x_set_seed_real(x, seed)

   flow_status = intode_status_unknown
   call flow(x, z, jac, flow_failed, flow_status)
   if (flow_failed .or. (.not. intode_status_is_strict_success(flow_status))) then
      write (*, '(A,I0)') "[ERROR] initial flow failed. status=", flow_status
      error stop 1
   end if

   call build_rattle_force_vector(z, dV, E0_real, E0_perp)
   force_scale = max(1.0_dp, norm2(dV))
   call reset_newton_eval_flow_status_counts()

   write (*, '(A,I0,A,ES12.4)') "[INIT] retained-core Newton contract starts. n_seed=", n_seed, &
      " cttol=", cttol

   do idx = 1, n_steps
      del_z = -step_sizes(idx)**2*dV
      call check_newton_replay(idx, step_sizes(idx), force_scale, x, z, jac, del_z, failures)
   end do
   del_z = -step_sizes(1)**2*dV
   call check_projected_step_identity(failures)
   call check_newton_failure_output_reset("nan_step", x, z, jac, del_z, failures)
   call check_newton_invalid_tol_reset(x, z, jac, del_z, failures)
   call check_newton_jac_shape_guard(x, z, del_z, failures)
   call check_newton_iteration_exhaustion_reset(x, z, jac, del_z, failures)

   deallocate (seed, x)
   deallocate (z, jac)
   deallocate (del_z, dV, E0_real, E0_perp, Jl)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] retained-core Newton contract failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] retained-core Newton contract complete."

contains

   subroutine fill_seed(seed)
      real(dp), intent(out) :: seed(:)
      integer :: i

      do i = 1, size(seed)
         seed(i) = 0.02_dp + 0.001_dp*real(i, dp)
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
         write (*, '(A)') "[ERROR] calculate_dV failed in Newton contract setup."
         error stop 1
      end if
      deallocate (ds_val, E0)
   end subroutine build_rattle_force_vector

   subroutine check_newton_replay(case_id, step_size, force_scale, x, z, jac, del_z, failures)
      integer, intent(in) :: case_id
      real(dp), intent(in) :: step_size, force_scale
      real(dp), intent(in) :: x(:), del_z(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      integer, intent(inout) :: failures

      real(dp), allocatable :: x_new(:), Jl(:), residual_vec(:)
      complex(dp), allocatable :: lambda(:), z_new(:), residual_complex(:)
      logical :: newton_failed, replay_failed, ok
      integer :: replay_status
      real(dp) :: residual_norm, lambda_norm, lambda_scale, residual_tol, lambda_scale_limit

      allocate (x_new(size(x)), Jl(size(del_z)), residual_vec(size(del_z)))
      allocate (lambda(size(z)), z_new(size(z)), residual_complex(size(z)))

      call solve_constraint_newton(cttol, 100, x, z, del_z, step_size, newton_failed, Jl, x_new, jac)
      replay_status = intode_status_unknown
      call flowz(x_new, z_new, replay_failed, replay_status)
      call real_to_complex(Jl, lambda)
      residual_complex = z - z_new - lambda
      call complex_to_real(residual_complex, residual_vec)
      residual_vec = residual_vec + del_z

      residual_norm = norm2(residual_vec)
      lambda_norm = norm2(Jl)
      lambda_scale = lambda_norm/(step_size**2*force_scale)
      residual_tol = max(50.0_dp*cttol, 5.0e-11_dp)
      lambda_scale_limit = 20.0_dp
      ok = (.not. newton_failed) .and. (.not. replay_failed) .and. &
           intode_status_is_strict_success(replay_status) .and. &
           ieee_is_finite(residual_norm) .and. ieee_is_finite(lambda_scale) .and. &
           residual_norm <= residual_tol .and. lambda_scale <= lambda_scale_limit .and. &
           abs(x_new(1) - x(1)) <= 0.0_dp

      write (*, '(A,I0,A,L1,A,I0,A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] newton_replay case=", case_id, " ok=", ok, " status=", replay_status, &
         " residual=", residual_norm, " residual_tol=", residual_tol, &
         " lambda_scale=", lambda_scale, " lambda_scale_limit=", lambda_scale_limit

      if (.not. ok) then
         failures = failures + 1
         write (*, '(A,L1,A,L1,A,ES24.16,A,ES24.16)') &
            "[FAIL] Newton replay contract failed. newton_failed=", newton_failed, &
            " replay_failed=", replay_failed, " residual=", residual_norm, &
            " lambda_scale=", lambda_scale
      end if

      deallocate (x_new, Jl, residual_vec)
      deallocate (lambda, z_new, residual_complex)
   end subroutine check_newton_replay

   subroutine check_projected_step_identity(failures)
      integer, intent(inout) :: failures

      real(dp) :: B(4), jacr(4, 4), jacr_lu(4, 4)
      real(dp) :: dxi(4), au(4), av(4)
      real(dp) :: expected_au(4), expected_av(4)
      integer :: ipiv(4), i
      logical :: ierr, ok

      B = [1.0_dp, 2.0_dp, -3.0_dp, 4.0_dp]
      jacr = 0.0_dp
      do i = 1, 4
         jacr(i, i) = 1.0_dp
         ipiv(i) = i
      end do
      jacr_lu = jacr
      expected_au = [1.0_dp, 0.0_dp, -3.0_dp, 0.0_dp]
      expected_av = [0.0_dp, 2.0_dp, 0.0_dp, 4.0_dp]

      call solve_projected_step(B, jacr, jacr_lu, ipiv, dxi, au, av, ierr)
      ok = (.not. ierr) .and. maxval(abs(dxi - B)) <= 1.0e-14_dp .and. &
           maxval(abs(au - expected_au)) <= 1.0e-14_dp .and. &
           maxval(abs(av - expected_av)) <= 1.0e-14_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') &
         "[CHECK] newton_projected_step_identity ok=", ok, &
         " dxi_err=", maxval(abs(dxi - B)), &
         " tangent_err=", maxval(abs(au - expected_au)), &
         " normal_err=", maxval(abs(av - expected_av))

      if (.not. ok) then
         failures = failures + 1
         write (*, '(A,L1)') "[FAIL] projected-step identity split failed. ierr=", ierr
      end if
   end subroutine check_projected_step_identity

   subroutine check_newton_failure_output_reset(label, x, z, jac, del_z, failures)
      character(len=*), intent(in) :: label
      real(dp), intent(in) :: x(:), del_z(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      integer, intent(inout) :: failures

      real(dp), allocatable :: x_new(:), Jl(:)
      real(dp) :: bad_step
      logical :: newton_failed, ok

      allocate (x_new(size(x)), Jl(size(del_z)))
      x_new = -huge(1.0_dp)
      Jl = huge(1.0_dp)
      bad_step = ieee_value(1.0_dp, ieee_quiet_nan)

      call solve_constraint_newton(cttol, 100, x, z, del_z, bad_step, newton_failed, Jl, x_new, jac)
      ok = newton_failed .and. maxval(abs(x_new - x)) <= 0.0_dp .and. maxval(abs(Jl)) <= 0.0_dp

      write (*, '(A,A,A,L1,A,ES12.4,A,ES12.4)') &
         "[CHECK] newton_failure_output_reset label=", trim(label), " ok=", ok, &
         " dx=", maxval(abs(x_new - x)), " djl=", maxval(abs(Jl))

      if (.not. ok) then
         failures = failures + 1
         write (*, '(A,A,A,L1)') "[FAIL] Newton failure output reset failed. label=", trim(label), &
            " ierr=", newton_failed
      end if
      deallocate (x_new, Jl)
   end subroutine check_newton_failure_output_reset

   subroutine check_newton_invalid_tol_reset(x, z, jac, del_z, failures)
      real(dp), intent(in) :: x(:), del_z(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      integer, intent(inout) :: failures

      real(dp), allocatable :: x_new(:), Jl(:)
      real(dp) :: bad_tol
      logical :: newton_failed, ok

      allocate (x_new(size(x)), Jl(size(del_z)))
      x_new = -huge(1.0_dp)
      Jl = huge(1.0_dp)
      bad_tol = ieee_value(1.0_dp, ieee_quiet_nan)

      call solve_constraint_newton(bad_tol, 100, x, z, del_z, step_sizes(1), newton_failed, Jl, x_new, jac)
      ok = newton_failed .and. maxval(abs(x_new - x)) <= 0.0_dp .and. maxval(abs(Jl)) <= 0.0_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4)') &
         "[CHECK] newton_invalid_tol_reset ok=", ok, &
         " dx=", maxval(abs(x_new - x)), " djl=", maxval(abs(Jl))

      if (.not. ok) then
         failures = failures + 1
         write (*, '(A,L1)') "[FAIL] Newton invalid-tol reset failed. ierr=", newton_failed
      end if
      deallocate (x_new, Jl)
   end subroutine check_newton_invalid_tol_reset

   subroutine check_newton_jac_shape_guard(x, z, del_z, failures)
      real(dp), intent(in) :: x(:), del_z(:)
      complex(dp), intent(in) :: z(:)
      integer, intent(inout) :: failures

      real(dp), allocatable :: x_new(:), Jl(:)
      complex(dp), allocatable :: jac_bad(:, :)
      logical :: newton_failed, ok

      allocate (x_new(size(x)), Jl(size(del_z)))
      allocate (jac_bad(size(z) + 1, size(z) + 1))
      x_new = -huge(1.0_dp)
      Jl = huge(1.0_dp)
      jac_bad = cmplx(0.0_dp, 0.0_dp, dp)

      call solve_constraint_newton(cttol, 100, x, z, del_z, step_sizes(1), newton_failed, Jl, x_new, jac_bad)
      ok = newton_failed .and. maxval(abs(x_new - x)) <= 0.0_dp .and. maxval(abs(Jl)) <= 0.0_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4)') &
         "[CHECK] newton_jac_shape_guard ok=", ok, &
         " dx=", maxval(abs(x_new - x)), " djl=", maxval(abs(Jl))

      if (.not. ok) then
         failures = failures + 1
         write (*, '(A,L1)') "[FAIL] Newton jac-shape guard failed. ierr=", newton_failed
      end if
      deallocate (x_new, Jl, jac_bad)
   end subroutine check_newton_jac_shape_guard

   subroutine check_newton_iteration_exhaustion_reset(x, z, jac, del_z, failures)
      real(dp), intent(in) :: x(:), del_z(:)
      complex(dp), intent(in) :: z(:), jac(:, :)
      integer, intent(inout) :: failures

      real(dp), allocatable :: x_new(:), Jl(:)
      logical :: newton_failed, ok

      allocate (x_new(size(x)), Jl(size(del_z)))
      x_new = -huge(1.0_dp)
      Jl = huge(1.0_dp)

      call solve_constraint_newton(cttol, 0, x, z, del_z, step_sizes(1), newton_failed, Jl, x_new, jac)
      ok = newton_failed .and. maxval(abs(x_new - x)) <= 0.0_dp .and. maxval(abs(Jl)) <= 0.0_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4)') &
         "[CHECK] newton_iteration_exhaustion_reset ok=", ok, &
         " dx=", maxval(abs(x_new - x)), " djl=", maxval(abs(Jl))

      if (.not. ok) then
         failures = failures + 1
         write (*, '(A,L1)') "[FAIL] Newton iteration-exhaustion reset failed. ierr=", newton_failed
      end if
      deallocate (x_new, Jl)
   end subroutine check_newton_iteration_exhaustion_reset

end program test_retained_core_newton_contract

program test_odex_flow_jacobian_contract
   use param_mod, only: read_parameters, state_seed_size_cfg
   use solve_flow, only: flow, flowz, flowzr, flow_workspace_t, get_intode_fallback_stats, &
                         intode_status_failure_invalid, intode_status_is_strict_success, intode_status_unknown, release_flow_workspace, &
                         reset_intode_fallback_stats
   use utils, only: dp, x_set_flow_time, x_set_seed_real
   use, intrinsic :: ieee_arithmetic, only: ieee_quiet_nan, ieee_value
   implicit none

   real(dp), parameter :: contract_flow_time = 1.0e-4_dp

   integer :: failures
   integer :: n_seed, x_size
   real(dp), allocatable :: seed(:), x(:)

   failures = 0
   call read_parameters()
   n_seed = state_seed_size_cfg()
   x_size = 1 + n_seed
   allocate (seed(n_seed), x(x_size))

   call fill_seed(seed)
   call reset_intode_fallback_stats()

   write (*, '(A,I0)') "[INIT] ODEX flow/Jacobian contract starts. n_seed=", n_seed

   call check_zero_flow_identity(seed, x, failures)
   call check_flow_endpoint_consistency(seed, x, failures)
   call check_explicit_flow_context(seed, x, failures)
   call check_flowzr_inverse(seed, x, failures)
   call check_jacobian_finite_difference(seed, x, failures)
   call check_flow_failure_output_contract(seed, x, failures)
   call check_no_fallbacks(failures)

   deallocate (seed, x)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] ODEX flow/Jacobian contract failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] ODEX flow/Jacobian contract complete."

contains

   subroutine fill_seed(seed)
      real(dp), intent(out) :: seed(:)
      integer :: idx

      do idx = 1, size(seed)
         seed(idx) = 0.02_dp + 0.001_dp*real(idx, dp)
      end do
   end subroutine fill_seed

   subroutine set_x_from_seed(x, flow_time, seed)
      real(dp), intent(out) :: x(:)
      real(dp), intent(in) :: flow_time
      real(dp), intent(in) :: seed(:)

      call x_set_flow_time(x, flow_time)
      call x_set_seed_real(x, seed)
   end subroutine set_x_from_seed

   subroutine check_zero_flow_identity(seed, x, failures)
      real(dp), intent(in) :: seed(:)
      real(dp), intent(inout) :: x(:)
      integer, intent(inout) :: failures
      complex(dp), allocatable :: z(:), jac(:, :)
      logical :: failed, ok
      integer :: status

      allocate (z(size(seed)), jac(size(seed), size(seed)))
      call set_x_from_seed(x, 0.0_dp, seed)
      z = cmplx(0.0_dp, 0.0_dp, dp)
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      status = intode_status_unknown
      call flow(x, z, jac, failed, status)
      ok = (.not. failed) .and. intode_status_is_strict_success(status) .and. &
           maxval(abs(z - cmplx(seed, 0.0_dp, dp))) == 0.0_dp .and. is_identity(jac, 0.0_dp)
      write (*, '(A,L1,A,I0)') "[CHECK] zero_flow_identity ok=", ok, " status=", status
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] zero-flow endpoint/Jacobian identity changed."
      end if
      deallocate (z, jac)
   end subroutine check_zero_flow_identity

   subroutine check_flow_endpoint_consistency(seed, x, failures)
      real(dp), intent(in) :: seed(:)
      real(dp), intent(inout) :: x(:)
      integer, intent(inout) :: failures
      complex(dp), allocatable :: z_flow(:), z_vec(:), jac(:, :)
      logical :: failed_flow, failed_vec, ok
      integer :: status_flow, status_vec
      real(dp), parameter :: tolerance = 1.0e-11_dp

      allocate (z_flow(size(seed)), z_vec(size(seed)), jac(size(seed), size(seed)))
      call set_x_from_seed(x, contract_flow_time, seed)
      z_flow = cmplx(0.0_dp, 0.0_dp, dp)
      z_vec = cmplx(0.0_dp, 0.0_dp, dp)
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      status_flow = intode_status_unknown
      status_vec = intode_status_unknown
      call flow(x, z_flow, jac, failed_flow, status_flow)
      call flowz(x, z_vec, failed_vec, status_vec)
      ok = (.not. failed_flow) .and. (.not. failed_vec) .and. &
           intode_status_is_strict_success(status_flow) .and. intode_status_is_strict_success(status_vec) .and. &
           maxval(abs(z_flow - z_vec)) <= tolerance
      write (*, '(A,L1,A,I0,A,I0,A,ES12.4)') "[CHECK] flow_endpoint_consistency ok=", ok, &
         " status_flow=", status_flow, " status_flowz=", status_vec, " max_diff=", maxval(abs(z_flow - z_vec))
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] flow and flowz endpoints diverged."
      end if
      deallocate (z_flow, z_vec, jac)
   end subroutine check_flow_endpoint_consistency

   subroutine check_explicit_flow_context(seed, x, failures)
      real(dp), intent(in) :: seed(:)
      real(dp), intent(inout) :: x(:)
      integer, intent(inout) :: failures
      type(flow_workspace_t) :: workspace
      complex(dp), allocatable :: z_legacy(:), z_context(:), jac_legacy(:, :), jac_context(:, :)
      logical :: failed_legacy, failed_context, ok
      integer :: status_legacy, status_context
      real(dp) :: z_diff, jac_diff
      real(dp), parameter :: tolerance = 1.0e-13_dp

      allocate (z_legacy(size(seed)), z_context(size(seed)), jac_legacy(size(seed), size(seed)), &
                jac_context(size(seed), size(seed)))
      call set_x_from_seed(x, contract_flow_time, seed)
      z_legacy = cmplx(0.0_dp, 0.0_dp, dp)
      z_context = cmplx(0.0_dp, 0.0_dp, dp)
      jac_legacy = cmplx(0.0_dp, 0.0_dp, dp)
      jac_context = cmplx(0.0_dp, 0.0_dp, dp)
      status_legacy = intode_status_unknown
      status_context = intode_status_unknown

      call flow(x, z_legacy, jac_legacy, failed_legacy, status_legacy)
      call flow(x, z_context, jac_context, failed_context, status_context, workspace)

      z_diff = maxval(abs(z_legacy - z_context))
      jac_diff = maxval(abs(jac_legacy - jac_context))
      ok = (.not. failed_legacy) .and. (.not. failed_context) .and. &
           intode_status_is_strict_success(status_legacy) .and. intode_status_is_strict_success(status_context) .and. &
           z_diff <= tolerance .and. jac_diff <= tolerance
      write (*, '(A,L1,A,I0,A,I0,A,ES12.4,A,ES12.4)') "[CHECK] explicit_flow_context ok=", ok, &
         " status_legacy=", status_legacy, " status_context=", status_context, " z_diff=", z_diff, &
         " jac_diff=", jac_diff
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] explicit flow context path diverged from legacy local-workspace path."
      end if

      call release_flow_workspace(workspace)
      deallocate (z_legacy, z_context, jac_legacy, jac_context)
   end subroutine check_explicit_flow_context

   subroutine check_flowzr_inverse(seed, x, failures)
      real(dp), intent(in) :: seed(:)
      real(dp), intent(inout) :: x(:)
      integer, intent(inout) :: failures
      complex(dp), allocatable :: z(:), jac(:, :)
      logical :: failed, failed_reverse, ok
      integer :: status, status_reverse
      real(dp), parameter :: tolerance = 5.0e-10_dp

      allocate (z(size(seed)), jac(size(seed), size(seed)))
      call set_x_from_seed(x, contract_flow_time, seed)
      z = cmplx(0.0_dp, 0.0_dp, dp)
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      status = intode_status_unknown
      status_reverse = intode_status_unknown
      failed_reverse = .true.
      call flow(x, z, jac, failed, status)
      if (.not. failed) call flowzr(x, z, failed_reverse, status_reverse)
      ok = (.not. failed) .and. (.not. failed_reverse) .and. &
           intode_status_is_strict_success(status) .and. intode_status_is_strict_success(status_reverse) .and. &
           maxval(abs(z - cmplx(seed, 0.0_dp, dp))) <= tolerance
      write (*, '(A,L1,A,I0,A,I0,A,ES12.4)') "[CHECK] flowzr_inverse ok=", ok, &
         " status_flow=", status, " status_flowzr=", status_reverse, " max_err=", &
         maxval(abs(z - cmplx(seed, 0.0_dp, dp)))
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] flowzr no longer inverts the deterministic flow endpoint."
      end if
      deallocate (z, jac)
   end subroutine check_flowzr_inverse

   subroutine check_jacobian_finite_difference(seed, x, failures)
      real(dp), intent(in) :: seed(:)
      real(dp), intent(inout) :: x(:)
      integer, intent(inout) :: failures
      complex(dp), allocatable :: z(:), jac(:, :), z_plus(:), z_minus(:), fd_col(:)
      real(dp), allocatable :: seed_plus(:), seed_minus(:), x_plus(:), x_minus(:)
      logical :: failed, failed_plus, failed_minus, ok
      integer :: status, status_plus, status_minus
      integer :: col
      real(dp) :: max_diff
      real(dp), parameter :: flow_time = contract_flow_time
      real(dp), parameter :: epsilon_fd = 1.0e-6_dp
      real(dp), parameter :: tolerance = 5.0e-7_dp

      allocate (z(size(seed)), jac(size(seed), size(seed)), z_plus(size(seed)), z_minus(size(seed)), fd_col(size(seed)))
      allocate (seed_plus(size(seed)), seed_minus(size(seed)), x_plus(size(x)), x_minus(size(x)))

      call set_x_from_seed(x, flow_time, seed)
      z = cmplx(0.0_dp, 0.0_dp, dp)
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      status = intode_status_unknown
      call flow(x, z, jac, failed, status)

      ok = (.not. failed) .and. intode_status_is_strict_success(status)
      max_diff = 0.0_dp
      do col = 1, size(seed)
         seed_plus = seed
         seed_minus = seed
         seed_plus(col) = seed_plus(col) + epsilon_fd
         seed_minus(col) = seed_minus(col) - epsilon_fd
         call set_x_from_seed(x_plus, flow_time, seed_plus)
         call set_x_from_seed(x_minus, flow_time, seed_minus)
         z_plus = cmplx(0.0_dp, 0.0_dp, dp)
         z_minus = cmplx(0.0_dp, 0.0_dp, dp)
         status_plus = intode_status_unknown
         status_minus = intode_status_unknown
         call flowz(x_plus, z_plus, failed_plus, status_plus)
         call flowz(x_minus, z_minus, failed_minus, status_minus)
         ok = ok .and. (.not. failed_plus) .and. (.not. failed_minus) .and. &
              intode_status_is_strict_success(status_plus) .and. intode_status_is_strict_success(status_minus)
         fd_col = (z_plus - z_minus)/(2.0_dp*epsilon_fd)
         max_diff = max(max_diff, maxval(abs(fd_col - jac(:, col))))
      end do
      ok = ok .and. max_diff <= tolerance
      write (*, '(A,L1,A,I0,A,ES12.4,A,ES12.4)') "[CHECK] jacobian_finite_difference ok=", ok, &
         " status=", status, " max_diff=", max_diff, " tol=", tolerance
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] flow Jacobian no longer matches flowz finite differences."
      end if

      deallocate (z, jac, z_plus, z_minus, fd_col)
      deallocate (seed_plus, seed_minus, x_plus, x_minus)
   end subroutine check_jacobian_finite_difference

   subroutine check_flow_failure_output_contract(seed, x, failures)
      real(dp), intent(in) :: seed(:)
      real(dp), intent(inout) :: x(:)
      integer, intent(inout) :: failures
      complex(dp), allocatable :: z(:), z_before(:), z_rev(:), z_rev_before(:), jac(:, :), jac_before(:, :), jac_bad(:, :)
      real(dp), allocatable :: x_bad(:)
      logical :: failed, ok_shape, ok_flow, ok_flowz, ok_flowzr, ok
      integer :: status
      real(dp) :: nan_value

      allocate (z(size(seed)), z_before(size(seed)), z_rev(size(seed)), z_rev_before(size(seed)))
      allocate (jac(size(seed), size(seed)), jac_before(size(seed), size(seed)), jac_bad(size(seed) + 1, size(seed)))
      allocate (x_bad(size(x)))

      call set_x_from_seed(x, contract_flow_time, seed)
      z_before = cmplx(9.0_dp, -3.0_dp, dp)
      jac_before = cmplx(-7.0_dp, 2.0_dp, dp)
      z = z_before
      jac_bad = cmplx(-7.0_dp, 2.0_dp, dp)
      status = intode_status_unknown
      call flow(x, z, jac_bad, failed, status)
      ok_shape = failed .and. status == intode_status_failure_invalid .and. maxval(abs(z - z_before)) == 0.0_dp .and. &
                 maxval(abs(jac_bad - cmplx(-7.0_dp, 2.0_dp, dp))) == 0.0_dp

      nan_value = ieee_value(0.0_dp, ieee_quiet_nan)
      x_bad = x
      x_bad(1) = nan_value

      z = z_before
      jac = jac_before
      status = intode_status_unknown
      call flow(x_bad, z, jac, failed, status)
      ok_flow = failed .and. status == intode_status_failure_invalid .and. &
                maxval(abs(z - cmplx(seed, 0.0_dp, dp))) == 0.0_dp .and. is_identity(jac, 0.0_dp)

      z = z_before
      status = intode_status_unknown
      call flowz(x_bad, z, failed, status)
      ok_flowz = failed .and. status == intode_status_failure_invalid .and. &
                 maxval(abs(z - cmplx(seed, 0.0_dp, dp))) == 0.0_dp

      z_rev_before = cmplx(seed, 0.125_dp, dp)
      z_rev = z_rev_before
      status = intode_status_unknown
      call flowzr(x_bad, z_rev, failed, status)
      ok_flowzr = failed .and. status == intode_status_failure_invalid .and. &
                  maxval(abs(z_rev - z_rev_before)) == 0.0_dp

      ok = ok_shape .and. ok_flow .and. ok_flowz .and. ok_flowzr
      write (*, '(A,L1,A,L1,A,L1,A,L1,A,L1)') "[CHECK] flow_failure_output_contract ok=", ok, &
         " shape=", ok_shape, " flow=", ok_flow, " flowz=", ok_flowz, " flowzr=", ok_flowzr
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] flow APIs no longer fail closed on invalid direct inputs."
      end if

      deallocate (z, z_before, z_rev, z_rev_before, jac, jac_before, jac_bad, x_bad)
   end subroutine check_flow_failure_output_contract

   subroutine check_no_fallbacks(failures)
      integer, intent(inout) :: failures
      integer :: calls_total, calls_integrating
      integer :: fallback_attempts, fallback_success, fallback_failure
      integer :: fallback_max_steps, fallback_invalid, fallback_h_min
      logical :: ok

      call get_intode_fallback_stats(calls_total, calls_integrating, fallback_attempts, fallback_success, &
                                     fallback_failure, fallback_max_steps, fallback_invalid, fallback_h_min)
      ok = fallback_attempts == 0 .and. fallback_success == 0 .and. fallback_failure == 0 .and. &
           fallback_max_steps == 0 .and. fallback_invalid == 0 .and. fallback_h_min == 0
      write (*, '(A,L1,A,I0,A,I0,A,I0)') "[CHECK] no_fallbacks ok=", ok, &
         " calls=", calls_total, " integrating=", calls_integrating, " attempts=", fallback_attempts
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] deterministic flow/Jacobian contract used fallback/assist unexpectedly."
      end if
   end subroutine check_no_fallbacks

   logical function is_identity(mat, tolerance) result(ok)
      complex(dp), intent(in) :: mat(:, :)
      real(dp), intent(in) :: tolerance
      integer :: row, col
      complex(dp) :: expected

      ok = size(mat, 1) == size(mat, 2)
      if (.not. ok) return
      do row = 1, size(mat, 1)
         do col = 1, size(mat, 2)
            if (row == col) then
               expected = cmplx(1.0_dp, 0.0_dp, dp)
            else
               expected = cmplx(0.0_dp, 0.0_dp, dp)
            end if
            if (abs(mat(row, col) - expected) > tolerance) then
               ok = .false.
               return
            end if
         end do
      end do
   end function is_identity

end program test_odex_flow_jacobian_contract

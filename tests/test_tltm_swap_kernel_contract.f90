program test_tltm_swap_kernel_contract
   use param_mod, only: read_parameters, state_seed_size_cfg
   use mt95, only: mt95_seed_state, mt95_state_t
   use solve_flow, only: flow, intode_status_is_strict_success, intode_status_unknown
   use tltm_stage2_driver, only: attempt_adjacent_swap, compute_effective_energy
   use tltm_run_context_mod, only: release_tltm_run_context, tltm_run_context_t
   use tltm_types_mod, only: allocate_tltm_slot, release_tltm_slot, tltm_pair_stats_t, tltm_slot_t
   use utils, only: dp, x_set_flow_time, x_set_seed_real
   implicit none

   integer, parameter :: rng_seed = 13579
   real(dp), parameter :: flow_a = 0.0_dp
   real(dp), parameter :: flow_b = 0.1_dp
   real(dp), parameter :: tol = 1.0e-10_dp

   type(tltm_slot_t) :: slot_a, slot_b
   type(tltm_pair_stats_t) :: stats
   type(mt95_state_t) :: swap_rng_state
   type(tltm_run_context_t) :: run_context_a, run_context_b
   integer :: n_seed, x_size
   real(dp), allocatable :: seed_a(:), seed_b(:)
   real(dp), allocatable :: x_a0(:), x_b0(:), x_ap(:), x_bp(:)
   complex(dp), allocatable :: z_a0(:), z_b0(:), z_ap(:), z_bp(:)
   complex(dp), allocatable :: j_a0(:, :), j_b0(:, :), j_ap(:, :), j_bp(:, :)
   real(dp) :: e_a, e_b, e_ap, e_bp, delta, expected_probability
   logical :: ok_a, ok_b, ok_ap, ok_bp

   call read_parameters()
   n_seed = state_seed_size_cfg()
   x_size = 1 + n_seed

   allocate (seed_a(n_seed), seed_b(n_seed))
   allocate (x_a0(x_size), x_b0(x_size), x_ap(x_size), x_bp(x_size))
   allocate (z_a0(n_seed), z_b0(n_seed), z_ap(n_seed), z_bp(n_seed))
   allocate (j_a0(n_seed, n_seed), j_b0(n_seed, n_seed), j_ap(n_seed, n_seed), j_bp(n_seed, n_seed))

   call allocate_tltm_slot(slot_a, x_size)
   call allocate_tltm_slot(slot_b, x_size)

   seed_a = 0.12_dp
   seed_b = -0.21_dp

   call initialize_slot(slot_a, 0, 0, flow_a, seed_a)
   call initialize_slot(slot_b, 1, 1, flow_b, seed_b)

   x_a0 = slot_a%x
   x_b0 = slot_b%x
   z_a0 = slot_a%z
   z_b0 = slot_b%z
   j_a0 = slot_a%jac
   j_b0 = slot_b%jac

   call compute_effective_energy(slot_a%z, slot_a%jac, e_a, ok_a)
   call compute_effective_energy(slot_b%z, slot_b%jac, e_b, ok_b)
   call assert_true(ok_a .and. ok_b, "current swap energies are computable")

   x_ap = slot_b%x
   call x_set_flow_time(x_ap, slot_a%flow_time)
   call strict_flow(x_ap, z_ap, j_ap, ok_ap, "proposed a<-b reflow")
   call compute_effective_energy(z_ap, j_ap, e_ap, ok_ap)
   call assert_true(ok_ap, "proposed a<-b energy is computable")

   x_bp = slot_a%x
   call x_set_flow_time(x_bp, slot_b%flow_time)
   call strict_flow(x_bp, z_bp, j_bp, ok_bp, "proposed b<-a reflow")
   call compute_effective_energy(z_bp, j_bp, e_bp, ok_bp)
   call assert_true(ok_bp, "proposed b<-a energy is computable")

   delta = (e_ap + e_bp) - (e_a + e_b)
   if (delta <= 0.0_dp) then
      expected_probability = 1.0_dp
   else
      expected_probability = exp(-delta)
   end if

   call reset_pair_stats(stats)
   call mt95_seed_state(swap_rng_state, rng_seed)
   call attempt_adjacent_swap(slot_a, slot_b, stats, swap_rng_state, run_context_a, run_context_b)

   call assert_equal_int(stats%proposal_count, 1, "valid swap increments proposal count")
   call assert_equal_int(stats%accept_count + stats%reject_count, 1, "valid swap records one terminal outcome")
   call assert_close(stats%last_accept_probability, expected_probability, tol, "swap probability matches TLTM energy delta")

   if (stats%accept_count == 1) then
      call assert_equal_int(slot_a%label_id, 1, "accepted swap moves label b into slot a")
      call assert_equal_int(slot_b%label_id, 0, "accepted swap moves label a into slot b")
      call assert_close_vec(slot_a%x, x_ap, tol, "accepted slot a stores reflowed b seed")
      call assert_close_vec(slot_b%x, x_bp, tol, "accepted slot b stores reflowed a seed")
   else
      call assert_equal_int(slot_a%label_id, 0, "rejected swap keeps label a")
      call assert_equal_int(slot_b%label_id, 1, "rejected swap keeps label b")
      call assert_close_vec(slot_a%x, x_a0, tol, "rejected slot a keeps x")
      call assert_close_vec(slot_b%x, x_b0, tol, "rejected slot b keeps x")
      call assert_close_cvec(slot_a%z, z_a0, tol, "rejected slot a keeps z")
      call assert_close_cvec(slot_b%z, z_b0, tol, "rejected slot b keeps z")
      call assert_close_cmat(slot_a%jac, j_a0, tol, "rejected slot a keeps jac")
      call assert_close_cmat(slot_b%jac, j_b0, tol, "rejected slot b keeps jac")
   end if

   call initialize_slot(slot_a, 0, 0, flow_a, seed_a)
   call initialize_slot(slot_b, 1, 1, flow_b, seed_b)
   x_a0 = slot_a%x
   x_b0 = slot_b%x
   write (*, '(A)') "[INFO] Expecting one log_determinant failure from a deliberate singular-Jacobian rejection test."
   slot_a%jac = cmplx(0.0_dp, 0.0_dp, dp)

   call reset_pair_stats(stats)
   call attempt_adjacent_swap(slot_a, slot_b, stats, swap_rng_state, run_context_a, run_context_b)
   call assert_equal_int(stats%proposal_count, 1, "invalid current energy still records swap proposal")
   call assert_equal_int(stats%accept_count, 0, "invalid current energy cannot accept")
   call assert_equal_int(stats%reject_count, 1, "invalid current energy rejects")
   call assert_close(stats%last_accept_probability, 0.0_dp, tol, "invalid current energy has zero acceptance probability")
   call assert_equal_int(slot_a%label_id, 0, "invalid current energy keeps label a")
   call assert_equal_int(slot_b%label_id, 1, "invalid current energy keeps label b")
   call assert_close_vec(slot_a%x, x_a0, tol, "invalid current energy keeps slot a x")
   call assert_close_vec(slot_b%x, x_b0, tol, "invalid current energy keeps slot b x")

   call release_tltm_slot(slot_a)
   call release_tltm_slot(slot_b)
   call release_tltm_run_context(run_context_a)
   call release_tltm_run_context(run_context_b)
   deallocate (seed_a, seed_b)
   deallocate (x_a0, x_b0, x_ap, x_bp)
   deallocate (z_a0, z_b0, z_ap, z_bp)
   deallocate (j_a0, j_b0, j_ap, j_bp)

   write (*, '(A)') "[PASS] TLTM swap kernel contract"

contains

   subroutine initialize_slot(slot, slot_id, label_id, flow_time, seed)
      type(tltm_slot_t), intent(inout) :: slot
      integer, intent(in) :: slot_id, label_id
      real(dp), intent(in) :: flow_time
      real(dp), intent(in) :: seed(:)
      logical :: ok

      slot%slot_id = slot_id
      slot%label_id = label_id
      slot%flow_time = flow_time
      call x_set_flow_time(slot%x, flow_time)
      call x_set_seed_real(slot%x, seed)
      call strict_flow(slot%x, slot%z, slot%jac, ok, "initialize slot")
      call assert_true(ok, "slot initialization strict flow")
   end subroutine initialize_slot

   subroutine strict_flow(x, z, jac, ok, context)
      real(dp), intent(in) :: x(:)
      complex(dp), intent(out) :: z(:)
      complex(dp), intent(out) :: jac(:, :)
      logical, intent(out) :: ok
      character(len=*), intent(in) :: context
      integer :: status
      logical :: failed

      status = intode_status_unknown
      call flow(x, z, jac, failed, status)
      ok = (.not. failed) .and. intode_status_is_strict_success(status)
      if (.not. ok) then
         write (*, '(A,A,A,I0)') "[ERROR] ", trim(context), " failed with status=", status
      end if
   end subroutine strict_flow

   subroutine reset_pair_stats(stats)
      type(tltm_pair_stats_t), intent(out) :: stats

      stats%pair_id = 0
      stats%slot_a = 0
      stats%slot_b = 1
      stats%proposal_count = 0
      stats%accept_count = 0
      stats%reject_count = 0
      stats%last_accept_probability = 0.0_dp
   end subroutine reset_pair_stats

   subroutine assert_true(condition, message)
      logical, intent(in) :: condition
      character(len=*), intent(in) :: message

      if (.not. condition) then
         write (*, '(A,A)') "[FAIL] ", trim(message)
         error stop 1
      end if
   end subroutine assert_true

   subroutine assert_equal_int(observed, expected, message)
      integer, intent(in) :: observed, expected
      character(len=*), intent(in) :: message

      if (observed /= expected) then
         write (*, '(A,A,A,I0,A,I0)') "[FAIL] ", trim(message), " observed=", observed, " expected=", expected
         error stop 1
      end if
   end subroutine assert_equal_int

   subroutine assert_close(observed, expected, tolerance, message)
      real(dp), intent(in) :: observed, expected, tolerance
      character(len=*), intent(in) :: message

      if (abs(observed - expected) > tolerance) then
         write (*, '(A,A,A,ES24.16,A,ES24.16)') "[FAIL] ", trim(message), " observed=", observed, " expected=", expected
         error stop 1
      end if
   end subroutine assert_close

   subroutine assert_close_vec(observed, expected, tolerance, message)
      real(dp), intent(in) :: observed(:), expected(:), tolerance
      character(len=*), intent(in) :: message

      if (size(observed) /= size(expected)) then
         write (*, '(A,A)') "[FAIL] size mismatch: ", trim(message)
         error stop 1
      end if
      if (maxval(abs(observed - expected)) > tolerance) then
         write (*, '(A,A)') "[FAIL] vector mismatch: ", trim(message)
         error stop 1
      end if
   end subroutine assert_close_vec

   subroutine assert_close_cvec(observed, expected, tolerance, message)
      complex(dp), intent(in) :: observed(:), expected(:)
      real(dp), intent(in) :: tolerance
      character(len=*), intent(in) :: message

      if (size(observed) /= size(expected)) then
         write (*, '(A,A)') "[FAIL] size mismatch: ", trim(message)
         error stop 1
      end if
      if (maxval(abs(observed - expected)) > tolerance) then
         write (*, '(A,A)') "[FAIL] complex vector mismatch: ", trim(message)
         error stop 1
      end if
   end subroutine assert_close_cvec

   subroutine assert_close_cmat(observed, expected, tolerance, message)
      complex(dp), intent(in) :: observed(:, :), expected(:, :)
      real(dp), intent(in) :: tolerance
      character(len=*), intent(in) :: message

      if (any(shape(observed) /= shape(expected))) then
         write (*, '(A,A)') "[FAIL] size mismatch: ", trim(message)
         error stop 1
      end if
      if (maxval(abs(observed - expected)) > tolerance) then
         write (*, '(A,A)') "[FAIL] complex matrix mismatch: ", trim(message)
         error stop 1
      end if
   end subroutine assert_close_cmat

end program test_tltm_swap_kernel_contract

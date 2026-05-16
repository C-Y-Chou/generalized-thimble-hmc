program test_odex_controller_alignment_spec
   use odex_backend, only: build_nsteps, ensure_odex_workspace_object, odex_default_options, &
                           odex_observe_controller_estimate, odex_observe_h_min, &
                           odex_hairer_controller_action_accept, odex_hairer_controller_action_continue, &
                           odex_hairer_controller_action_endpoint, odex_hairer_controller_action_reject, &
                           odex_hairer_controller_action_retry, odex_hairer_controller_decision, &
                           odex_hairer_controller_phase_basic, odex_hairer_controller_phase_first_last, &
                           odex_hairer_controller_state, odex_hairer_controller_state_reset, &
                           odex_hairer_errold_initial, odex_hairer_row_lifecycle, &
                           odex_observe_hairer_controller_accept_update, &
                           odex_observe_hairer_controller_initial_state, &
                           odex_observe_hairer_controller_reject_update, &
                           odex_observe_hairer_controller_row_action, &
                           odex_observe_hairer_controller_step_entry, &
                           odex_observe_hairer_initial_state, odex_observe_hairer_kopt, &
                           odex_observe_hairer_midex_lifecycle_row, &
                           odex_observe_hairer_midex_row, odex_observe_hairer_promotion_step, &
                           odex_observe_hairer_reject_update, odex_observe_hairer_step_entry, &
                           odex_hairer_row_lifecycle_reset, &
                           odex_observe_hairer_row_lifecycle_begin, &
                           odex_observe_initial_step, odex_observe_order_transition, &
                           odex_observe_stability_reject, odex_options, odex_row_result, &
                           odex_controller_policy_hairer_experimental, odex_controller_policy_tltm_endpoint, &
                           odex_order_transition_demote, odex_order_transition_keep, &
                           odex_order_transition_promote, odex_stability_control_conservative, &
                           odex_workspace
   use utils, only: dp
   implicit none

   integer, parameter :: expected_gap_count = 2
   integer :: failures, gaps
   real(dp) :: row_lambda

   failures = 0
   gaps = 0
   write (*, '(A)') "[INIT] ODEX controller alignment spec starts."

   call check_iwork3_and_signed_work_alignment(failures)
   call check_initial_step_gap(gaps, failures)
   call check_growth_bound_alignment(failures)
   call check_order_threshold_alignment(failures)
   call check_hairer_route_policy_gate(failures)
   call check_hairer_route_skeleton_reference(failures)
   call check_midex_row_primitive(failures)
   call check_midex_row_lifecycle(failures)
   call check_hairer_outer_controller_decisions(failures)
   call check_stability_policy_gap(gaps, failures)

   call count_failure(gaps == expected_gap_count, "[FAIL] F18b.4 expected-gap count changed.", failures)
   write (*, '(A,I0,A,I0)') "[CHECK] expected controller gaps=", gaps, " expected=", expected_gap_count

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] ODEX controller alignment spec failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] ODEX controller alignment spec complete."

contains

   subroutine check_iwork3_and_signed_work_alignment(failures)
      integer, intent(inout) :: failures
      type(odex_workspace) :: workspace
      integer :: actual(8), expected(8)
      real(dp) :: h_candidate, work_estimate
      logical :: ok

      expected = [2, 4, 6, 8, 12, 16, 24, 32]
      call build_nsteps(size(actual), actual)
      call ensure_odex_workspace_object(workspace, 8, 1)
      call odex_observe_controller_estimate(workspace, -0.125_dp, 0.25_dp, 4, h_candidate, work_estimate)

      ok = all(actual == expected) .and. h_candidate < 0.0_dp .and. work_estimate > 0.0_dp
      write (*, '(A,L1,A,ES12.4,A,ES12.4)') "[CHECK] iwork3_signed_work_aligned ok=", ok, &
         " h_candidate=", h_candidate, " work=", work_estimate
      call count_failure(ok, "[FAIL] matched IWORK(3), signed h, or positive work estimate changed.", failures)
   end subroutine check_iwork3_and_signed_work_alignment

   subroutine check_initial_step_gap(gaps, failures)
      integer, intent(inout) :: gaps, failures
      type(odex_options) :: loose_options, tight_options
      real(dp) :: h_loose, h_tight, h_min
      logical :: current_gap

      call odex_default_options(loose_options, 1.0e-6_dp, 1.0e-6_dp)
      call odex_default_options(tight_options, 1.0e-12_dp, 1.0e-12_dp)
      h_loose = odex_observe_initial_step(loose_options, 1.0_dp)
      h_tight = odex_observe_initial_step(tight_options, 1.0_dp)
      call odex_observe_h_min(tight_options, 1.0_dp, h_min)

      current_gap = nearly_equal(h_loose, 0.01_dp, 1.0e-14_dp) .and. &
                    nearly_equal(h_tight, 0.01_dp, 1.0e-14_dp) .and. h_tight > h_min
      write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[GAP] h0_fraction_policy gap=", &
         current_gap, " h_loose=", h_loose, " h_tight=", h_tight, " h_min=", h_min
      call count_gap(current_gap, "[FAIL] expected current h0 gap was not observed.", gaps, failures)
   end subroutine check_initial_step_gap

   subroutine check_growth_bound_alignment(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      real(dp) :: h, h_candidate, work_estimate, growth_ratio, shrink_ratio
      real(dp) :: facmin, lower_bound, upper_bound
      logical :: ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      call ensure_odex_workspace_object(workspace, 8, 1)
      h = 0.125_dp
      facmin = options%step_size_bound_fac1**(1.0_dp/(2.0_dp*4.0_dp - 1.0_dp))
      lower_bound = facmin/options%step_size_bound_fac2
      upper_bound = 1.0_dp/facmin

      call odex_observe_controller_estimate(workspace, h, 0.0_dp, 4, h_candidate, work_estimate, options)
      growth_ratio = abs(h_candidate/h)
      ok = nearly_equal(growth_ratio, upper_bound, 1.0e-12_dp) .and. work_estimate > 0.0_dp

      call odex_observe_controller_estimate(workspace, h, 1.0e12_dp, 4, h_candidate, work_estimate, options)
      shrink_ratio = abs(h_candidate/h)
      ok = ok .and. nearly_equal(shrink_ratio, lower_bound, 1.0e-12_dp) .and. work_estimate > 0.0_dp

      write (*, '(A,L1,A,ES12.4,A,ES12.4)') "[CHECK] growth_shrink_bounds_aligned ok=", ok, &
         " growth_ratio=", growth_ratio, " shrink_ratio=", shrink_ratio
      call count_failure(ok, "[FAIL] Hairer-style growth/shrink controller bounds changed.", failures)
   end subroutine check_growth_bound_alignment

   subroutine check_order_threshold_alignment(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      integer :: transition, next_k
      logical :: demote_ok, promote_ok, keep_ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)

      call odex_observe_order_transition(0.85_dp, 1.0_dp, 5, options, transition, next_k)
      keep_ok = transition == odex_order_transition_keep .and. next_k == 5

      call odex_observe_order_transition(0.75_dp, 1.0_dp, 5, options, transition, next_k)
      demote_ok = transition == odex_order_transition_demote .and. next_k == 4

      call odex_observe_order_transition(1.0_dp, 0.85_dp, 5, options, transition, next_k)
      promote_ok = transition == odex_order_transition_promote .and. next_k == 6

      write (*, '(A,L1,A,L1,A,L1)') "[CHECK] order_thresholds_aligned keep=", keep_ok, &
         " demote=", demote_ok, " promote=", promote_ok
      call count_failure(keep_ok .and. demote_ok .and. promote_ok, &
         "[FAIL] Hairer-style order promotion/demotion thresholds changed.", failures)
   end subroutine check_order_threshold_alignment

   subroutine check_hairer_route_policy_gate(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      logical :: ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      ok = options%controller_policy == odex_controller_policy_tltm_endpoint
      options%controller_policy = odex_controller_policy_hairer_experimental
      ok = ok .and. options%controller_policy == odex_controller_policy_hairer_experimental

      write (*, '(A,L1,A,I0)') "[CHECK] hairer_route_policy_gate ok=", ok, &
         " policy=", options%controller_policy
      call count_failure(ok, "[FAIL] Hairer-route policy gate changed.", failures)
   end subroutine check_hairer_route_policy_gate

   subroutine check_hairer_route_skeleton_reference(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      real(dp) :: h_initial, hmax_abs, h_step, next_h
      real(dp) :: promoted_h
      real(dp) :: hh_values(6), work_values(6)
      integer :: k_initial, kopt, next_k
      logical :: last_step, endpoint_reached
      logical :: init_ok, step_ok, kopt_ok, reject_ok, promote_ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      call ensure_odex_workspace_object(workspace, 8, 1)

      call odex_observe_hairer_initial_state(options, 1.0_dp, 0.0_dp, 0.0_dp, &
                                             h_initial, k_initial, hmax_abs)
      init_ok = nearly_equal(h_initial, 1.0e-4_dp, 1.0e-14_dp) .and. &
                k_initial == 8 .and. nearly_equal(hmax_abs, 1.0_dp, 1.0e-14_dp)

      call odex_observe_hairer_initial_state(options, -1.0_dp, 10.0_dp, 0.0_dp, &
                                             h_initial, k_initial, hmax_abs)
      init_ok = init_ok .and. nearly_equal(h_initial, -0.5_dp, 1.0e-14_dp)

      call odex_observe_hairer_step_entry(0.2_dp, 1.0_dp, 1.0_dp, 10.0_dp, 10.0_dp, &
                                          epsilon(1.0_dp), h_step, last_step, endpoint_reached)
      step_ok = nearly_equal(h_step, 0.8_dp, 1.0e-14_dp) .and. last_step .and. &
                (.not. endpoint_reached)

      call odex_observe_hairer_kopt(2, 4, options%k_max, .false., 0.0_dp, 0.0_dp, 1.0_dp, options, kopt)
      kopt_ok = kopt == 3

      call odex_observe_hairer_kopt(5, 5, options%k_max, .false., 0.0_dp, 0.75_dp, 1.0_dp, options, kopt)
      kopt_ok = kopt_ok .and. kopt == 4

      call odex_observe_hairer_kopt(5, 5, options%k_max, .false., 0.0_dp, 1.0_dp, 0.85_dp, options, kopt)
      kopt_ok = kopt_ok .and. kopt == 6

      call odex_observe_hairer_kopt(6, 5, options%k_max, .false., 0.5_dp, 1.0_dp, 0.95_dp, options, kopt)
      kopt_ok = kopt_ok .and. kopt == 4

      call odex_observe_hairer_kopt(5, 5, options%k_max, .false., 0.0_dp, 0.8_dp, 1.0_dp, options, kopt)
      kopt_ok = kopt_ok .and. kopt == 5

      work_values = [1.2_dp, 1.1_dp, 1.0_dp, 0.95_dp, 1.0_dp, 1.2_dp]
      hh_values = [0.40_dp, 0.30_dp, 0.20_dp, 0.10_dp, 0.05_dp, 0.025_dp]
      call odex_observe_hairer_reject_update(6, 6, options%k_max, work_values, hh_values, &
                                             options, -1.0_dp, next_k, next_h)
      reject_ok = next_k == 6 .and. nearly_equal(next_h, -0.025_dp, 1.0e-14_dp)

      work_values = [1.2_dp, 1.1_dp, 1.0_dp, 0.50_dp, 1.0_dp, 1.2_dp]
      call odex_observe_hairer_reject_update(5, 6, options%k_max, work_values, hh_values, &
                                             options, -1.0_dp, next_k, next_h)
      reject_ok = reject_ok .and. next_k == 4 .and. nearly_equal(next_h, -0.10_dp, 1.0e-14_dp)

      call odex_observe_hairer_promotion_step(workspace, 0.25_dp, 4, 5, promoted_h)
      promote_ok = nearly_equal(promoted_h, 0.25_dp*workspace%ak(5)/workspace%ak(4), 1.0e-14_dp)

      write (*, '(A,L1,A,L1,A,L1,A,L1,A,L1)') "[CHECK] hairer_route_skeleton init=", init_ok, &
         " step=", step_ok, " kopt=", kopt_ok, " reject=", reject_ok, " promote=", promote_ok
      call count_failure(init_ok .and. step_ok .and. kopt_ok .and. reject_ok .and. promote_ok, &
                         "[FAIL] Hairer-route controller skeleton reference changed.", failures)
   end subroutine check_hairer_route_skeleton_reference

   subroutine check_midex_row_primitive(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_row_result) :: row1, row2, row3, row3_atov
      real(dp) :: y(1), fbase(1), scal(1), errold, h, h_before
      integer :: nsteps(3)
      logical :: row1_ok, row2_ok, signed_ok, row3_ok, atov_ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      row_lambda = -2.0_dp
      y(1) = 1.0_dp
      fbase = rhs_exp(y)
      scal(1) = options%abs_tol + options%rel_tol*abs(y(1))
      errold = huge(1.0_dp)
      h = 0.125_dp
      call build_nsteps(size(nsteps), nsteps)

      call odex_observe_hairer_midex_row(rhs_exp, 1, y, h, 1.0_dp, fbase, scal, errold, workspace, options, row1)
      row1_ok = row1%row_index == 1 .and. row1%rhs_evals == nsteps(1) .and. &
                (.not. row1%err_available) .and. (.not. row1%atov) .and. &
                (.not. row1%invalid_rhs) .and. nearly_equal(h, 0.125_dp, 1.0e-14_dp)

      call odex_observe_hairer_midex_row(rhs_exp, 2, y, h, 1.0_dp, fbase, scal, errold, workspace, options, row2)
      row2_ok = row2%row_index == 2 .and. row2%rhs_evals == nsteps(2) .and. &
                row2%err_available .and. (.not. row2%atov) .and. row2%err >= 0.0_dp .and. &
                row2%hh > 0.0_dp .and. row2%work > 0.0_dp .and. row2%errold_after >= 1.0_dp .and. &
                all(scal > 0.0_dp)

      h = -0.125_dp
      errold = huge(1.0_dp)
      scal(1) = options%abs_tol + options%rel_tol*abs(y(1))
      call odex_observe_hairer_midex_row(rhs_exp, 1, y, h, 1.0_dp, fbase, scal, errold, workspace, options, row1)
      call odex_observe_hairer_midex_row(rhs_exp, 2, y, h, 1.0_dp, fbase, scal, errold, workspace, options, row2)
      signed_ok = row2%err_available .and. row2%hh > 0.0_dp .and. row2%work > 0.0_dp .and. h < 0.0_dp

      h = 0.125_dp
      errold = huge(1.0_dp)
      scal(1) = options%abs_tol + options%rel_tol*abs(y(1))
      call odex_observe_hairer_midex_row(rhs_exp, 1, y, h, 1.0_dp, fbase, scal, errold, workspace, options, row1)
      call odex_observe_hairer_midex_row(rhs_exp, 2, y, h, 1.0_dp, fbase, scal, errold, workspace, options, row2)
      errold = huge(1.0_dp)
      call odex_observe_hairer_midex_row(rhs_exp, 3, y, h, 1.0_dp, fbase, scal, errold, workspace, options, row3)
      row3_ok = row3%row_index == 3 .and. row3%rhs_evals == nsteps(3) .and. &
                row3%err_available .and. (.not. row3%atov) .and. row3%hh > 0.0_dp .and. &
                row3%work > 0.0_dp .and. row3%errold_after >= 1.0_dp

      h = 0.125_dp
      errold = huge(1.0_dp)
      scal(1) = options%abs_tol + options%rel_tol*abs(y(1))
      call odex_observe_hairer_midex_row(rhs_exp, 1, y, h, 1.0_dp, fbase, scal, errold, workspace, options, row1)
      call odex_observe_hairer_midex_row(rhs_exp, 2, y, h, 1.0_dp, fbase, scal, errold, workspace, options, row2)
      errold = 0.0_dp
      h_before = h
      call odex_observe_hairer_midex_row(rhs_exp, 3, y, h, 1.0_dp, fbase, scal, errold, workspace, options, row3_atov)
      atov_ok = row3_atov%err_available .and. row3_atov%atov .and. nearly_equal(h, 0.5_dp*h_before, 1.0e-14_dp)

      write (*, '(A,L1,A,L1,A,L1,A,L1,A,L1)') "[CHECK] midex_row_primitive j1=", row1_ok, &
         " j2=", row2_ok, " signed=", signed_ok, " j3=", row3_ok, " atov=", atov_ok
      if (.not. row3_ok) then
         write (*, '(A,L1,A,ES12.4,A,ES12.4,A,ES12.4)') "[DETAIL] midex_row_j3 atov=", row3%atov, &
            " err=", row3%err, " hh=", row3%hh, " errold=", row3%errold_after
      end if
      call count_failure(row1_ok .and. row2_ok .and. signed_ok .and. row3_ok .and. atov_ok, &
                         "[FAIL] Hairer MIDEX row primitive contract changed.", failures)
   end subroutine check_midex_row_primitive

   subroutine check_midex_row_lifecycle(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_hairer_row_lifecycle) :: row_lifecycle
      type(odex_row_result) :: row1, row2, row3_atov
      real(dp) :: y(1), fbase(1), h, h_before, expected_scale
      integer :: nsteps(3)
      logical :: init_ok, row1_ok, row2_ok, atov_ok, reset_ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      row_lambda = -2.0_dp
      y(1) = 1.0_dp
      fbase = rhs_exp(y)
      h = 0.125_dp
      call build_nsteps(size(nsteps), nsteps)

      call odex_observe_hairer_row_lifecycle_begin(y, options, 4, row_lifecycle)
      expected_scale = options%abs_tol + options%rel_tol*abs(y(1))
      init_ok = row_lifecycle%initialized .and. row_lifecycle%dimension == 1 .and. &
                row_lifecycle%max_rows == 4 .and. allocated(row_lifecycle%scal) .and. &
                allocated(row_lifecycle%hh) .and. allocated(row_lifecycle%work) .and. &
                nearly_equal(row_lifecycle%scal(1), expected_scale, 1.0e-14_dp) .and. &
                nearly_equal(row_lifecycle%errold, odex_hairer_errold_initial, 1.0e-14_dp) .and. &
                (.not. row_lifecycle%atov)

      call odex_observe_hairer_midex_lifecycle_row(rhs_exp, 1, y, h, 1.0_dp, fbase, workspace, &
                                                   options, row_lifecycle, row1)
      row1_ok = row_lifecycle%rows_attempted == 1 .and. row_lifecycle%last_row == 1 .and. &
                row_lifecycle%rhs_evals == nsteps(1) .and. row_lifecycle%error_rows == 0 .and. &
                row1%rhs_evals == nsteps(1) .and. (.not. row1%err_available) .and. &
                nearly_equal(row_lifecycle%hh(1), 0.0_dp, 1.0e-14_dp) .and. &
                row_lifecycle%work(1) > 1.0e100_dp

      call odex_observe_hairer_midex_lifecycle_row(rhs_exp, 2, y, h, 1.0_dp, fbase, workspace, &
                                                   options, row_lifecycle, row2)
      expected_scale = options%abs_tol + options%rel_tol* &
         max(abs(y(1)), abs(workspace%tableau(2, 2, 1)))
      row2_ok = row_lifecycle%rows_attempted == 2 .and. row_lifecycle%error_rows == 1 .and. &
                row_lifecycle%rhs_evals == nsteps(1) + nsteps(2) .and. row2%err_available .and. &
                (.not. row2%atov) .and. nearly_equal(row_lifecycle%errold, row2%errold_after, 1.0e-14_dp) .and. &
                nearly_equal(row_lifecycle%scal(1), expected_scale, 1.0e-14_dp) .and. &
                nearly_equal(row_lifecycle%hh(2), row2%hh, 1.0e-14_dp) .and. &
                nearly_equal(row_lifecycle%work(2), row2%work, 1.0e-14_dp)

      row_lifecycle%errold = 0.0_dp
      h_before = h
      call odex_observe_hairer_midex_lifecycle_row(rhs_exp, 3, y, h, 1.0_dp, fbase, workspace, &
                                                   options, row_lifecycle, row3_atov)
      atov_ok = row3_atov%err_available .and. row3_atov%atov .and. row_lifecycle%atov .and. &
                row_lifecycle%atov_events == 1 .and. row_lifecycle%error_rows == 2 .and. &
                nearly_equal(h, 0.5_dp*h_before, 1.0e-14_dp) .and. &
                nearly_equal(row_lifecycle%h_after, h, 1.0e-14_dp) .and. &
                nearly_equal(row_lifecycle%hh(3), 0.0_dp, 1.0e-14_dp) .and. &
                row_lifecycle%work(3) > 1.0e100_dp

      call odex_hairer_row_lifecycle_reset(row_lifecycle)
      reset_ok = (.not. row_lifecycle%initialized) .and. (.not. allocated(row_lifecycle%scal)) .and. &
                 (.not. allocated(row_lifecycle%hh)) .and. (.not. allocated(row_lifecycle%work)) .and. &
                 nearly_equal(row_lifecycle%errold, odex_hairer_errold_initial, 1.0e-14_dp)

      write (*, '(A,L1,A,L1,A,L1,A,L1,A,L1)') "[CHECK] midex_row_lifecycle init=", init_ok, &
         " j1=", row1_ok, " j2=", row2_ok, " atov=", atov_ok, " reset=", reset_ok
      call count_failure(init_ok .and. row1_ok .and. row2_ok .and. atov_ok .and. reset_ok, &
                         "[FAIL] Hairer MIDEX row lifecycle contract changed.", failures)
   end subroutine check_midex_row_lifecycle

   subroutine check_hairer_outer_controller_decisions(failures)
      integer, intent(inout) :: failures
      type(odex_options) :: options
      type(odex_workspace) :: workspace
      type(odex_hairer_row_lifecycle) :: row_lifecycle
      type(odex_hairer_controller_state) :: controller_state
      type(odex_hairer_controller_decision) :: decision
      type(odex_row_result) :: row_state
      real(dp) :: y(1), expected_h
      logical :: entry_ok, first_last_ok, basic_ok, accept_ok, reject_ok, atov_ok

      call odex_default_options(options, 1.0e-12_dp, 1.0e-12_dp)
      call ensure_odex_workspace_object(workspace, 8, 1)
      y(1) = 1.0_dp
      call odex_observe_hairer_row_lifecycle_begin(y, options, 8, row_lifecycle)
      row_lifecycle%hh = [0.0_dp, 0.30_dp, 0.20_dp, 0.10_dp, 0.05_dp, 0.025_dp, 0.0125_dp, 0.00625_dp]
      row_lifecycle%work = [huge(1.0_dp), 5.0_dp, 2.0_dp, 1.0_dp, 2.0_dp, 1.0_dp, 1.0_dp, 1.0_dp]

      call odex_observe_hairer_controller_initial_state(options, 1.0_dp, 0.25_dp, 0.0_dp, controller_state)
      call odex_observe_hairer_controller_step_entry(0.2_dp, 1.0_dp, epsilon(1.0_dp), controller_state, decision)
      entry_ok = controller_state%initialized .and. controller_state%k == 8 .and. &
                 nearly_equal(decision%next_h, 0.25_dp, 1.0e-14_dp) .and. decision%next_row == 1 .and. &
                 decision%action == odex_hairer_controller_action_continue .and. (.not. decision%last_step)
      controller_state%h = 1.0_dp
      call odex_observe_hairer_controller_step_entry(0.2_dp, 1.0_dp, epsilon(1.0_dp), controller_state, decision)
      entry_ok = entry_ok .and. decision%last_step .and. nearly_equal(decision%next_h, 0.8_dp, 1.0e-14_dp)
      call odex_observe_hairer_controller_step_entry(1.0_dp, 1.0_dp + epsilon(1.0_dp), epsilon(1.0_dp), &
                                                     controller_state, decision)
      entry_ok = entry_ok .and. decision%action == odex_hairer_controller_action_endpoint .and. &
                 decision%endpoint_reached

      call seed_controller(controller_state, k=4, kc=0, h=0.25_dp, posneg=1.0_dp)
      call make_row(row_state, 1, .false., 0.0_dp, .false., controller_state%h)
      call odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                     options, odex_hairer_controller_phase_first_last, decision)
      first_last_ok = decision%action == odex_hairer_controller_action_continue .and. decision%next_row == 2
      call make_row(row_state, 2, .true., 0.5_dp, .false., controller_state%h)
      call odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                     options, odex_hairer_controller_phase_first_last, decision)
      first_last_ok = first_last_ok .and. decision%action == odex_hairer_controller_action_accept .and. &
                      decision%accepted_row == 2

      call seed_controller(controller_state, k=4, kc=0, h=0.25_dp, posneg=1.0_dp)
      call make_row(row_state, 4, .true., 10.0_dp, .false., controller_state%h)
      call odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                     options, odex_hairer_controller_phase_first_last, decision)
      first_last_ok = first_last_ok .and. decision%action == odex_hairer_controller_action_continue .and. &
                      decision%next_row == 5
      call make_row(row_state, 5, .true., 1.2_dp, .false., controller_state%h)
      call odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                     options, odex_hairer_controller_phase_first_last, decision)
      first_last_ok = first_last_ok .and. decision%action == odex_hairer_controller_action_reject .and. &
                      decision%rejected_after .and. decision%next_k == 4 .and. &
                      nearly_equal(decision%next_h, row_lifecycle%hh(4), 1.0e-14_dp)

      call seed_controller(controller_state, k=5, kc=0, h=0.25_dp, posneg=1.0_dp)
      call make_row(row_state, 4, .true., 0.5_dp, .false., controller_state%h)
      call odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                     options, odex_hairer_controller_phase_basic, decision)
      basic_ok = decision%action == odex_hairer_controller_action_accept .and. decision%accepted_row == 4
      call seed_controller(controller_state, k=5, kc=0, h=0.25_dp, posneg=1.0_dp)
      call make_row(row_state, 4, .true., 3000.0_dp, .false., controller_state%h)
      call odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                     options, odex_hairer_controller_phase_basic, decision)
      basic_ok = basic_ok .and. decision%action == odex_hairer_controller_action_reject .and. decision%next_k == 4
      call seed_controller(controller_state, k=5, kc=0, h=0.25_dp, posneg=1.0_dp)
      controller_state%rejected = .true.
      call make_row(row_state, 4, .true., 0.5_dp, .false., controller_state%h)
      call odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                     options, odex_hairer_controller_phase_basic, decision)
      basic_ok = basic_ok .and. decision%action == odex_hairer_controller_action_continue .and. decision%next_row == 5

      call seed_controller(controller_state, k=5, kc=4, h=0.25_dp, posneg=1.0_dp)
      call odex_observe_hairer_controller_accept_update(controller_state, row_lifecycle, workspace, options, decision)
      expected_h = row_lifecycle%hh(4)*workspace%ak(6)/workspace%ak(4)
      accept_ok = decision%action == odex_hairer_controller_action_continue .and. decision%next_k == 5 .and. &
                  nearly_equal(decision%next_h, expected_h, 1.0e-14_dp)
      call seed_controller(controller_state, k=6, kc=5, h=0.08_dp, posneg=1.0_dp)
      controller_state%rejected = .true.
      call odex_observe_hairer_controller_accept_update(controller_state, row_lifecycle, workspace, options, decision)
      accept_ok = accept_ok .and. decision%action == odex_hairer_controller_action_continue .and. &
                  decision%next_k == 4 .and. nearly_equal(decision%next_h, 0.08_dp, 1.0e-14_dp) .and. &
                  (.not. decision%rejected_after)

      call seed_controller(controller_state, k=6, kc=6, h=0.25_dp, posneg=-1.0_dp)
      row_lifecycle%work(5) = 0.5_dp
      row_lifecycle%work(6) = 1.0_dp
      call odex_observe_hairer_controller_reject_update(controller_state, row_lifecycle, options, decision)
      reject_ok = decision%action == odex_hairer_controller_action_reject .and. decision%next_k == 5 .and. &
                  decision%rejected_after .and. nearly_equal(decision%next_h, -row_lifecycle%hh(5), 1.0e-14_dp)

      call seed_controller(controller_state, k=4, kc=0, h=0.25_dp, posneg=1.0_dp)
      call make_row(row_state, 3, .true., 2.0_dp, .true., 0.125_dp)
      call odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                     options, odex_hairer_controller_phase_basic, decision)
      atov_ok = decision%action == odex_hairer_controller_action_retry .and. decision%rejected_after .and. &
                nearly_equal(decision%next_h, 0.125_dp, 1.0e-14_dp)

      write (*, '(A,L1,A,L1,A,L1,A,L1,A,L1,A,L1)') "[CHECK] hairer_outer_controller entry=", entry_ok, &
         " first_last=", first_last_ok, " basic=", basic_ok, " accept=", accept_ok, &
         " reject=", reject_ok, " atov=", atov_ok
      call count_failure(entry_ok .and. first_last_ok .and. basic_ok .and. accept_ok .and. reject_ok .and. atov_ok, &
                         "[FAIL] Hairer outer-controller decision contract changed.", failures)
   end subroutine check_hairer_outer_controller_decisions

   subroutine check_stability_policy_gap(gaps, failures)
      integer, intent(inout) :: gaps, failures
      type(odex_options) :: options
      real(dp) :: values(1)
      logical :: reject_default, reject_conservative, current_gap

      call odex_default_options(options, 1.0e-10_dp, 1.0e-10_dp)
      values(1) = 20.0_dp
      reject_default = odex_observe_stability_reject(values, 1.0_dp, 0.1_dp, options)

      options%stability_control = odex_stability_control_conservative
      options%stability_growth_limit = 4.0_dp
      reject_conservative = odex_observe_stability_reject(values, 1.0_dp, 0.1_dp, options)

      current_gap = (.not. reject_default) .and. reject_conservative
      write (*, '(A,L1,A,L1,A,L1)') "[GAP] default_stability_policy gap=", current_gap, &
         " default=", reject_default, " conservative=", reject_conservative
      call count_gap(current_gap, "[FAIL] expected default-stability-policy gap was not observed.", gaps, failures)
   end subroutine check_stability_policy_gap

   logical function nearly_equal(actual, expected, tol) result(ok)
      real(dp), intent(in) :: actual, expected, tol

      ok = abs(actual - expected) <= tol*max(1.0_dp, abs(expected))
   end function nearly_equal

   subroutine count_gap(ok, message, gaps, failures)
      logical, intent(in) :: ok
      character(len=*), intent(in) :: message
      integer, intent(inout) :: gaps, failures

      if (ok) then
         gaps = gaps + 1
      else
         failures = failures + 1
         write (*, '(A)') message
      end if
   end subroutine count_gap

   subroutine count_failure(ok, message, failures)
      logical, intent(in) :: ok
      character(len=*), intent(in) :: message
      integer, intent(inout) :: failures

      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') message
      end if
   end subroutine count_failure

   subroutine seed_controller(controller_state, k, kc, h, posneg)
      type(odex_hairer_controller_state), intent(out) :: controller_state
      integer, intent(in) :: k, kc
      real(dp), intent(in) :: h, posneg

      call odex_hairer_controller_state_reset(controller_state)
      controller_state%initialized = .true.
      controller_state%k = k
      controller_state%kc = kc
      controller_state%km = 8
      controller_state%h = h
      controller_state%hmax_abs = 1.0_dp
      controller_state%hoptde = posneg
      controller_state%posneg = posneg
   end subroutine seed_controller

   subroutine make_row(row_state, row_index, err_available, err, atov, h_after)
      type(odex_row_result), intent(out) :: row_state
      integer, intent(in) :: row_index
      logical, intent(in) :: err_available, atov
      real(dp), intent(in) :: err, h_after

      row_state%row_index = row_index
      row_state%rhs_evals = 0
      row_state%err_available = err_available
      row_state%atov = atov
      row_state%invalid_rhs = .false.
      row_state%stability_rejected = .false.
      row_state%err = err
      row_state%hh = 0.0_dp
      row_state%work = huge(1.0_dp)
      row_state%h_after = h_after
      row_state%errold_after = 0.0_dp
   end subroutine make_row

   function rhs_exp(y) result(dy)
      real(dp), intent(in) :: y(:)
      real(dp) :: dy(size(y))

      dy = row_lambda*y
   end function rhs_exp

end program test_odex_controller_alignment_spec

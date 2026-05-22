module constraint_solver_stats_mod
   use runtime_env_mod, only: parse_int_env
   use utils, only: dp
   use param_mod, only: x_history_file
   use, intrinsic :: iso_fortran_env, only: int64
   implicit none

   ! Failure capture policy:
   ! - limit <= 0 means unlimited capture.
   ! - default values can be overridden by environment variables:
   !   CONSTRAINT_FAIL_CAPTURE_LIMIT, CONSTRAINT_FAIL_CAPTURE_START_SAMPLE
   integer, parameter :: failure_capture_limit_default = 100
   character(len=*), parameter :: failure_capture_z0_name = "constraint_solver_fail_z0.dat"
   character(len=*), parameter :: failure_capture_delz_name = "constraint_solver_fail_delz.dat"
   character(len=*), parameter :: failure_capture_x0_name = "constraint_solver_fail_x0.dat"
   character(len=*), parameter :: failure_capture_quasi_name = "constraint_solver_fail_quasi_trace.csv"
   character(len=*), parameter :: failure_capture_meta_name = "constraint_solver_fail_meta.csv"
   integer, parameter :: constraint_quasi_stage_probe = 1
   integer, parameter :: constraint_quasi_stage_full = 2
   integer, parameter :: constraint_quasi_class_local = 1
   integer, parameter :: constraint_quasi_class_mid = 2
   integer, parameter :: constraint_quasi_class_global = 3
   integer, parameter :: constraint_quasi_far_route_skip = 0
   integer, parameter :: constraint_quasi_far_route_light = 1
   integer, parameter :: constraint_quasi_far_route_anchor = 2
   integer, parameter :: constraint_reverse_gate_path_count = 11
   integer, parameter :: constraint_reverse_gate_path_total = 1
   integer, parameter :: constraint_reverse_gate_path_probe_only = 2
   integer, parameter :: constraint_reverse_gate_path_full_stage = 3
   integer, parameter :: constraint_reverse_gate_path_near_rescue = 4
   integer, parameter :: constraint_reverse_gate_path_nonnear_route = 5
   integer, parameter :: constraint_reverse_gate_path_class_local = 6
   integer, parameter :: constraint_reverse_gate_path_class_mid = 7
   integer, parameter :: constraint_reverse_gate_path_class_global = 8
   integer, parameter :: constraint_reverse_gate_path_far_skip = 9
   integer, parameter :: constraint_reverse_gate_path_far_light = 10
   integer, parameter :: constraint_reverse_gate_path_far_anchor = 11
   type :: constraint_solver_stats_context_t
      integer(int64) :: newton_success_count = 0_int64
      integer(int64) :: quasi_success_count = 0_int64
      integer(int64) :: quasi_probe_attempt_count = 0_int64
      integer(int64) :: quasi_probe_success_count = 0_int64
      integer(int64) :: quasi_full_attempt_count = 0_int64
      integer(int64) :: quasi_full_success_count = 0_int64
      integer(int64) :: quasi_class_local_count = 0_int64
      integer(int64) :: quasi_class_mid_count = 0_int64
      integer(int64) :: quasi_class_global_count = 0_int64
      integer(int64) :: quasi_far_route_skip_count = 0_int64
      integer(int64) :: quasi_far_route_light_count = 0_int64
      integer(int64) :: quasi_far_route_anchor_count = 0_int64
      integer(int64) :: fail_count = 0_int64
      integer(int64) :: near_fail_candidate_count = 0_int64
      integer(int64) :: far_fail_count = 0_int64
      integer(int64) :: near_rescue_attempt_count = 0_int64
      integer(int64) :: near_rescue_success_count = 0_int64
      integer(int64) :: near_unusable_count = 0_int64
      integer(int64) :: near_fail_fast_count = 0_int64
      integer(int64) :: far_fail_fast_count = 0_int64
      integer(int64) :: far_rescue_scope_count = 0_int64
      integer(int64) :: far_rescue_success_count = 0_int64
      integer(int64) :: far_rescue_fail_count = 0_int64
      integer(int64) :: far_rescue_fail_fast_case_count = 0_int64
      integer(int64) :: far_rescue_spent_success_count = 0_int64
      integer(int64) :: far_rescue_spent_fail_count = 0_int64
      integer(int64) :: far_rescue_flowzr_used_sum = 0_int64
      integer(int64) :: far_rescue_final_resort_used_sum = 0_int64
      integer(int64) :: far_rescue_flowzr_used_success_sum = 0_int64
      integer(int64) :: far_rescue_final_resort_used_success_sum = 0_int64
      integer(int64) :: far_rescue_flowzr_used_fail_sum = 0_int64
      integer(int64) :: far_rescue_final_resort_used_fail_sum = 0_int64
      integer(int64) :: quasi_budget_hit_count = 0_int64
      integer(int64) :: quasi_budget_used_sum = 0_int64
      integer :: quasi_budget_used_max = 0
      integer :: quasi_budget_limit_last = 0
      integer(int64) :: quasi_global_filter_candidate_count = 0_int64
      integer(int64) :: quasi_global_filter_pass_count = 0_int64
      integer(int64) :: quasi_global_filter_reject_count = 0_int64
      integer :: failure_capture_limit_runtime = failure_capture_limit_default
      integer :: failure_capture_start_sample = 0
      logical :: failure_capture_policy_ready = .false.
      integer :: failure_capture_count = 0
      integer :: failure_capture_z0_unit = -1
      integer :: failure_capture_delz_unit = -1
      integer :: failure_capture_x0_unit = -1
      integer :: failure_capture_quasi_unit = -1
      integer :: failure_capture_meta_unit = -1
      logical :: failure_capture_files_ready = .false.
      logical :: failure_capture_write_error = .false.
      character(len=512) :: failure_capture_z0_file = ""
      character(len=512) :: failure_capture_delz_file = ""
      character(len=512) :: failure_capture_x0_file = ""
      character(len=512) :: failure_capture_quasi_file = ""
      character(len=512) :: failure_capture_meta_file = ""
      integer :: context_chain_sample_idx = 0
      integer :: context_hmc_repeat_idx = 0
      integer :: prev_meta_attempt_flowz = 0
      integer :: prev_meta_attempt_flowzr = 0
      integer :: prev_meta_attempt_flow = 0
      integer :: prev_meta_attempt_unknown = 0
      integer :: prev_meta_fail_flowz = 0
      integer :: prev_meta_fail_flowzr = 0
      integer :: prev_meta_fail_flow = 0
      integer :: prev_meta_fail_unknown = 0
      integer :: prev_meta_success_final_resort = 0
      integer :: prev_meta_fail_final_resort = 0
      integer(int64) :: reverse_gate_candidate_count(constraint_reverse_gate_path_count) = 0_int64
      integer(int64) :: reverse_gate_pass_count(constraint_reverse_gate_path_count) = 0_int64
      integer(int64) :: reverse_gate_reject_count(constraint_reverse_gate_path_count) = 0_int64
      integer :: constraint_solver_stats_suppression_depth = 0
   end type constraint_solver_stats_context_t

   type(constraint_solver_stats_context_t), target, save :: module_constraint_solver_stats_context
   integer(int64), pointer, save :: newton_success_count => null()
   integer(int64), pointer, save :: quasi_success_count => null()
   integer(int64), pointer, save :: quasi_probe_attempt_count => null()
   integer(int64), pointer, save :: quasi_probe_success_count => null()
   integer(int64), pointer, save :: quasi_full_attempt_count => null()
   integer(int64), pointer, save :: quasi_full_success_count => null()
   integer(int64), pointer, save :: quasi_class_local_count => null()
   integer(int64), pointer, save :: quasi_class_mid_count => null()
   integer(int64), pointer, save :: quasi_class_global_count => null()
   integer(int64), pointer, save :: quasi_far_route_skip_count => null()
   integer(int64), pointer, save :: quasi_far_route_light_count => null()
   integer(int64), pointer, save :: quasi_far_route_anchor_count => null()
   integer(int64), pointer, save :: fail_count => null()
   integer(int64), pointer, save :: near_fail_candidate_count => null()
   integer(int64), pointer, save :: far_fail_count => null()
   integer(int64), pointer, save :: near_rescue_attempt_count => null()
   integer(int64), pointer, save :: near_rescue_success_count => null()
   integer(int64), pointer, save :: near_unusable_count => null()
   integer(int64), pointer, save :: near_fail_fast_count => null()
   integer(int64), pointer, save :: far_fail_fast_count => null()
   integer(int64), pointer, save :: far_rescue_scope_count => null()
   integer(int64), pointer, save :: far_rescue_success_count => null()
   integer(int64), pointer, save :: far_rescue_fail_count => null()
   integer(int64), pointer, save :: far_rescue_fail_fast_case_count => null()
   integer(int64), pointer, save :: far_rescue_spent_success_count => null()
   integer(int64), pointer, save :: far_rescue_spent_fail_count => null()
   integer(int64), pointer, save :: far_rescue_flowzr_used_sum => null()
   integer(int64), pointer, save :: far_rescue_final_resort_used_sum => null()
   integer(int64), pointer, save :: far_rescue_flowzr_used_success_sum => null()
   integer(int64), pointer, save :: far_rescue_final_resort_used_success_sum => null()
   integer(int64), pointer, save :: far_rescue_flowzr_used_fail_sum => null()
   integer(int64), pointer, save :: far_rescue_final_resort_used_fail_sum => null()
   integer(int64), pointer, save :: quasi_budget_hit_count => null()
   integer(int64), pointer, save :: quasi_budget_used_sum => null()
   integer, pointer, save :: quasi_budget_used_max => null()
   integer, pointer, save :: quasi_budget_limit_last => null()
   integer(int64), pointer, save :: quasi_global_filter_candidate_count => null()
   integer(int64), pointer, save :: quasi_global_filter_pass_count => null()
   integer(int64), pointer, save :: quasi_global_filter_reject_count => null()
   integer, pointer, save :: failure_capture_limit_runtime => null()
   integer, pointer, save :: failure_capture_start_sample => null()
   logical, pointer, save :: failure_capture_policy_ready => null()
   integer, pointer, save :: failure_capture_count => null()
   integer, pointer, save :: failure_capture_z0_unit => null()
   integer, pointer, save :: failure_capture_delz_unit => null()
   integer, pointer, save :: failure_capture_x0_unit => null()
   integer, pointer, save :: failure_capture_quasi_unit => null()
   integer, pointer, save :: failure_capture_meta_unit => null()
   logical, pointer, save :: failure_capture_files_ready => null()
   logical, pointer, save :: failure_capture_write_error => null()
   character(len=512), pointer, save :: failure_capture_z0_file => null()
   character(len=512), pointer, save :: failure_capture_delz_file => null()
   character(len=512), pointer, save :: failure_capture_x0_file => null()
   character(len=512), pointer, save :: failure_capture_quasi_file => null()
   character(len=512), pointer, save :: failure_capture_meta_file => null()
   integer, pointer, save :: context_chain_sample_idx => null()
   integer, pointer, save :: context_hmc_repeat_idx => null()
   integer, pointer, save :: prev_meta_attempt_flowz => null()
   integer, pointer, save :: prev_meta_attempt_flowzr => null()
   integer, pointer, save :: prev_meta_attempt_flow => null()
   integer, pointer, save :: prev_meta_attempt_unknown => null()
   integer, pointer, save :: prev_meta_fail_flowz => null()
   integer, pointer, save :: prev_meta_fail_flowzr => null()
   integer, pointer, save :: prev_meta_fail_flow => null()
   integer, pointer, save :: prev_meta_fail_unknown => null()
   integer, pointer, save :: prev_meta_success_final_resort => null()
   integer, pointer, save :: prev_meta_fail_final_resort => null()
   integer(int64), pointer, save :: reverse_gate_candidate_count(:) => null()
   integer(int64), pointer, save :: reverse_gate_pass_count(:) => null()
   integer(int64), pointer, save :: reverse_gate_reject_count(:) => null()
   integer, pointer, save :: constraint_solver_stats_suppression_depth => null()
   logical, save :: constraint_solver_stats_aliases_bound = .false.
!$omp threadprivate(constraint_solver_stats_aliases_bound)
!$omp threadprivate(newton_success_count, quasi_success_count, quasi_probe_attempt_count, quasi_probe_success_count)
!$omp threadprivate(quasi_full_attempt_count, quasi_full_success_count, quasi_class_local_count, quasi_class_mid_count)
!$omp threadprivate(quasi_class_global_count, quasi_far_route_skip_count, quasi_far_route_light_count)
!$omp threadprivate(quasi_far_route_anchor_count, fail_count, near_fail_candidate_count, far_fail_count)
!$omp threadprivate(near_rescue_attempt_count, near_rescue_success_count, near_unusable_count, near_fail_fast_count)
!$omp threadprivate(far_fail_fast_count, far_rescue_scope_count, far_rescue_success_count, far_rescue_fail_count)
!$omp threadprivate(far_rescue_fail_fast_case_count, far_rescue_spent_success_count, far_rescue_spent_fail_count)
!$omp threadprivate(far_rescue_flowzr_used_sum, far_rescue_final_resort_used_sum)
!$omp threadprivate(far_rescue_flowzr_used_success_sum, far_rescue_final_resort_used_success_sum)
!$omp threadprivate(far_rescue_flowzr_used_fail_sum, far_rescue_final_resort_used_fail_sum)
!$omp threadprivate(quasi_budget_hit_count, quasi_budget_used_sum, quasi_budget_used_max, quasi_budget_limit_last)
!$omp threadprivate(quasi_global_filter_candidate_count, quasi_global_filter_pass_count, quasi_global_filter_reject_count)
!$omp threadprivate(failure_capture_limit_runtime, failure_capture_start_sample, failure_capture_policy_ready)
!$omp threadprivate(failure_capture_count, failure_capture_z0_unit, failure_capture_delz_unit, failure_capture_x0_unit)
!$omp threadprivate(failure_capture_quasi_unit, failure_capture_meta_unit, failure_capture_files_ready)
!$omp threadprivate(failure_capture_write_error, failure_capture_z0_file, failure_capture_delz_file)
!$omp threadprivate(failure_capture_x0_file, failure_capture_quasi_file, failure_capture_meta_file)
!$omp threadprivate(context_chain_sample_idx, context_hmc_repeat_idx, prev_meta_attempt_flowz, prev_meta_attempt_flowzr)
!$omp threadprivate(prev_meta_attempt_flow, prev_meta_attempt_unknown, prev_meta_fail_flowz, prev_meta_fail_flowzr)
!$omp threadprivate(prev_meta_fail_flow, prev_meta_fail_unknown, prev_meta_success_final_resort, prev_meta_fail_final_resort)
!$omp threadprivate(reverse_gate_candidate_count, reverse_gate_pass_count, reverse_gate_reject_count)
!$omp threadprivate(constraint_solver_stats_suppression_depth)

contains

   subroutine ensure_constraint_solver_stats_aliases_bound()
      implicit none

      if (.not. constraint_solver_stats_aliases_bound) call bind_module_constraint_solver_stats_context()
   end subroutine ensure_constraint_solver_stats_aliases_bound

   subroutine bind_constraint_solver_stats_context(context)
      implicit none
      type(constraint_solver_stats_context_t), intent(inout), target :: context

      call bind_constraint_solver_stats_aliases(context)
   end subroutine bind_constraint_solver_stats_context

   subroutine bind_module_constraint_solver_stats_context()
      implicit none

      call bind_constraint_solver_stats_aliases(module_constraint_solver_stats_context)
   end subroutine bind_module_constraint_solver_stats_context

   subroutine release_constraint_solver_stats_context(context)
      implicit none
      type(constraint_solver_stats_context_t), intent(inout), target :: context
      logical :: was_active

      was_active = .false.
      if (constraint_solver_stats_aliases_bound) was_active = associated(newton_success_count, context%newton_success_count)
      if (.not. was_active) call bind_constraint_solver_stats_aliases(context)
      call reset_constraint_failure_capture()
      context = constraint_solver_stats_context_t()
      call bind_module_constraint_solver_stats_context()
   end subroutine release_constraint_solver_stats_context

   subroutine bind_constraint_solver_stats_aliases(context)
      implicit none
      type(constraint_solver_stats_context_t), intent(inout), target :: context

      newton_success_count => context%newton_success_count
      quasi_success_count => context%quasi_success_count
      quasi_probe_attempt_count => context%quasi_probe_attempt_count
      quasi_probe_success_count => context%quasi_probe_success_count
      quasi_full_attempt_count => context%quasi_full_attempt_count
      quasi_full_success_count => context%quasi_full_success_count
      quasi_class_local_count => context%quasi_class_local_count
      quasi_class_mid_count => context%quasi_class_mid_count
      quasi_class_global_count => context%quasi_class_global_count
      quasi_far_route_skip_count => context%quasi_far_route_skip_count
      quasi_far_route_light_count => context%quasi_far_route_light_count
      quasi_far_route_anchor_count => context%quasi_far_route_anchor_count
      fail_count => context%fail_count
      near_fail_candidate_count => context%near_fail_candidate_count
      far_fail_count => context%far_fail_count
      near_rescue_attempt_count => context%near_rescue_attempt_count
      near_rescue_success_count => context%near_rescue_success_count
      near_unusable_count => context%near_unusable_count
      near_fail_fast_count => context%near_fail_fast_count
      far_fail_fast_count => context%far_fail_fast_count
      far_rescue_scope_count => context%far_rescue_scope_count
      far_rescue_success_count => context%far_rescue_success_count
      far_rescue_fail_count => context%far_rescue_fail_count
      far_rescue_fail_fast_case_count => context%far_rescue_fail_fast_case_count
      far_rescue_spent_success_count => context%far_rescue_spent_success_count
      far_rescue_spent_fail_count => context%far_rescue_spent_fail_count
      far_rescue_flowzr_used_sum => context%far_rescue_flowzr_used_sum
      far_rescue_final_resort_used_sum => context%far_rescue_final_resort_used_sum
      far_rescue_flowzr_used_success_sum => context%far_rescue_flowzr_used_success_sum
      far_rescue_final_resort_used_success_sum => context%far_rescue_final_resort_used_success_sum
      far_rescue_flowzr_used_fail_sum => context%far_rescue_flowzr_used_fail_sum
      far_rescue_final_resort_used_fail_sum => context%far_rescue_final_resort_used_fail_sum
      quasi_budget_hit_count => context%quasi_budget_hit_count
      quasi_budget_used_sum => context%quasi_budget_used_sum
      quasi_budget_used_max => context%quasi_budget_used_max
      quasi_budget_limit_last => context%quasi_budget_limit_last
      quasi_global_filter_candidate_count => context%quasi_global_filter_candidate_count
      quasi_global_filter_pass_count => context%quasi_global_filter_pass_count
      quasi_global_filter_reject_count => context%quasi_global_filter_reject_count
      failure_capture_limit_runtime => context%failure_capture_limit_runtime
      failure_capture_start_sample => context%failure_capture_start_sample
      failure_capture_policy_ready => context%failure_capture_policy_ready
      failure_capture_count => context%failure_capture_count
      failure_capture_z0_unit => context%failure_capture_z0_unit
      failure_capture_delz_unit => context%failure_capture_delz_unit
      failure_capture_x0_unit => context%failure_capture_x0_unit
      failure_capture_quasi_unit => context%failure_capture_quasi_unit
      failure_capture_meta_unit => context%failure_capture_meta_unit
      failure_capture_files_ready => context%failure_capture_files_ready
      failure_capture_write_error => context%failure_capture_write_error
      failure_capture_z0_file => context%failure_capture_z0_file
      failure_capture_delz_file => context%failure_capture_delz_file
      failure_capture_x0_file => context%failure_capture_x0_file
      failure_capture_quasi_file => context%failure_capture_quasi_file
      failure_capture_meta_file => context%failure_capture_meta_file
      context_chain_sample_idx => context%context_chain_sample_idx
      context_hmc_repeat_idx => context%context_hmc_repeat_idx
      prev_meta_attempt_flowz => context%prev_meta_attempt_flowz
      prev_meta_attempt_flowzr => context%prev_meta_attempt_flowzr
      prev_meta_attempt_flow => context%prev_meta_attempt_flow
      prev_meta_attempt_unknown => context%prev_meta_attempt_unknown
      prev_meta_fail_flowz => context%prev_meta_fail_flowz
      prev_meta_fail_flowzr => context%prev_meta_fail_flowzr
      prev_meta_fail_flow => context%prev_meta_fail_flow
      prev_meta_fail_unknown => context%prev_meta_fail_unknown
      prev_meta_success_final_resort => context%prev_meta_success_final_resort
      prev_meta_fail_final_resort => context%prev_meta_fail_final_resort
      reverse_gate_candidate_count => context%reverse_gate_candidate_count
      reverse_gate_pass_count => context%reverse_gate_pass_count
      reverse_gate_reject_count => context%reverse_gate_reject_count
      constraint_solver_stats_suppression_depth => context%constraint_solver_stats_suppression_depth
      constraint_solver_stats_aliases_bound = .true.
   end subroutine bind_constraint_solver_stats_aliases

   subroutine push_constraint_solver_stats_suppression()
      implicit none
      call ensure_constraint_solver_stats_aliases_bound()
      constraint_solver_stats_suppression_depth = constraint_solver_stats_suppression_depth + 1
   end subroutine push_constraint_solver_stats_suppression

   subroutine pop_constraint_solver_stats_suppression()
      implicit none
      call ensure_constraint_solver_stats_aliases_bound()
      if (constraint_solver_stats_suppression_depth > 0) then
         constraint_solver_stats_suppression_depth = constraint_solver_stats_suppression_depth - 1
      end if
   end subroutine pop_constraint_solver_stats_suppression

   logical function constraint_solver_stats_are_suppressed() result(is_suppressed)
      implicit none
      call ensure_constraint_solver_stats_aliases_bound()
      is_suppressed = (constraint_solver_stats_suppression_depth > 0)
   end function constraint_solver_stats_are_suppressed

   subroutine reset_constraint_solver_stats()
      implicit none
      call ensure_constraint_solver_stats_aliases_bound()
      newton_success_count = 0_int64
      quasi_success_count = 0_int64
      quasi_probe_attempt_count = 0_int64
      quasi_probe_success_count = 0_int64
      quasi_full_attempt_count = 0_int64
      quasi_full_success_count = 0_int64
      quasi_class_local_count = 0_int64
      quasi_class_mid_count = 0_int64
      quasi_class_global_count = 0_int64
      quasi_far_route_skip_count = 0_int64
      quasi_far_route_light_count = 0_int64
      quasi_far_route_anchor_count = 0_int64
      fail_count = 0_int64
      near_fail_candidate_count = 0_int64
      far_fail_count = 0_int64
      near_rescue_attempt_count = 0_int64
      near_rescue_success_count = 0_int64
      near_unusable_count = 0_int64
      near_fail_fast_count = 0_int64
      far_fail_fast_count = 0_int64
      far_rescue_scope_count = 0_int64
      far_rescue_success_count = 0_int64
      far_rescue_fail_count = 0_int64
      far_rescue_fail_fast_case_count = 0_int64
      far_rescue_spent_success_count = 0_int64
      far_rescue_spent_fail_count = 0_int64
      far_rescue_flowzr_used_sum = 0_int64
      far_rescue_final_resort_used_sum = 0_int64
      far_rescue_flowzr_used_success_sum = 0_int64
      far_rescue_final_resort_used_success_sum = 0_int64
      far_rescue_flowzr_used_fail_sum = 0_int64
      far_rescue_final_resort_used_fail_sum = 0_int64
      quasi_budget_hit_count = 0_int64
      quasi_budget_used_sum = 0_int64
      quasi_budget_used_max = 0
      quasi_budget_limit_last = 0
      quasi_global_filter_candidate_count = 0_int64
      quasi_global_filter_pass_count = 0_int64
      quasi_global_filter_reject_count = 0_int64
      reverse_gate_candidate_count = 0_int64
      reverse_gate_pass_count = 0_int64
      reverse_gate_reject_count = 0_int64
      call reset_constraint_failure_capture()
   end subroutine reset_constraint_solver_stats

   subroutine set_constraint_solver_runtime_context(chain_sample_idx, hmc_repeat_idx)
      implicit none
      integer, intent(in) :: chain_sample_idx, hmc_repeat_idx

      call ensure_constraint_solver_stats_aliases_bound()
      context_chain_sample_idx = chain_sample_idx
      context_hmc_repeat_idx = hmc_repeat_idx
   end subroutine set_constraint_solver_runtime_context

   subroutine record_constraint_solver_newton_success()
      implicit none
      if (constraint_solver_stats_are_suppressed()) return
      newton_success_count = newton_success_count + 1_int64
   end subroutine record_constraint_solver_newton_success

   subroutine record_constraint_solver_quasi_success()
      implicit none
      if (constraint_solver_stats_are_suppressed()) return
      quasi_success_count = quasi_success_count + 1_int64
   end subroutine record_constraint_solver_quasi_success

   subroutine record_constraint_solver_quasi_stage_attempt(stage_code)
      implicit none
      integer, intent(in) :: stage_code

      if (constraint_solver_stats_are_suppressed()) return
      select case (stage_code)
      case (constraint_quasi_stage_probe)
         quasi_probe_attempt_count = quasi_probe_attempt_count + 1_int64
      case (constraint_quasi_stage_full)
         quasi_full_attempt_count = quasi_full_attempt_count + 1_int64
      end select
   end subroutine record_constraint_solver_quasi_stage_attempt

   subroutine record_constraint_solver_quasi_stage_success(stage_code)
      implicit none
      integer, intent(in) :: stage_code

      if (constraint_solver_stats_are_suppressed()) return
      select case (stage_code)
      case (constraint_quasi_stage_probe)
         quasi_probe_success_count = quasi_probe_success_count + 1_int64
      case (constraint_quasi_stage_full)
         quasi_full_success_count = quasi_full_success_count + 1_int64
      end select
   end subroutine record_constraint_solver_quasi_stage_success

   subroutine record_constraint_solver_quasi_class(class_code)
      implicit none
      integer, intent(in) :: class_code

      if (constraint_solver_stats_are_suppressed()) return
      select case (class_code)
      case (constraint_quasi_class_local)
         quasi_class_local_count = quasi_class_local_count + 1_int64
      case (constraint_quasi_class_mid)
         quasi_class_mid_count = quasi_class_mid_count + 1_int64
      case (constraint_quasi_class_global)
         quasi_class_global_count = quasi_class_global_count + 1_int64
      end select
   end subroutine record_constraint_solver_quasi_class

   subroutine record_constraint_solver_far_route(route_code)
      implicit none
      integer, intent(in) :: route_code

      if (constraint_solver_stats_are_suppressed()) return
      select case (route_code)
      case (constraint_quasi_far_route_skip)
         quasi_far_route_skip_count = quasi_far_route_skip_count + 1_int64
      case (constraint_quasi_far_route_light)
         quasi_far_route_light_count = quasi_far_route_light_count + 1_int64
      case (constraint_quasi_far_route_anchor)
         quasi_far_route_anchor_count = quasi_far_route_anchor_count + 1_int64
      end select
   end subroutine record_constraint_solver_far_route

   subroutine record_constraint_solver_fail(z0, del_z, x0, quasi_z_proposed, quasi_z_flowed, quasi_res_norm, quasi_alpha, &
                                            quasi_iter, quasi_backtrack, quasi_attempt, quasi_accepted, quasi_eval_ok, &
                                            quasi_case, online_class, trace_valid_fraction, trace_progress_ratio, &
                                            trace_regress_ratio, trace_best_over_tol, is_near_case, near_rescue_started, &
                                            near_rescue_done, near_fail_fast, near_fail_fast_reason, &
                                            far_fail_fast, far_fail_fast_reason, &
                                            attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                            fail_flowz, fail_flowzr, fail_flow, fail_unknown, success_final_resort, &
                                            fail_final_resort, radau_rescue_ok, radau_rescue_fail, &
                                            final_resort_budget_hit, final_resort_budget_used, final_resort_budget_limit)
      implicit none
      complex(dp), intent(in), optional :: z0(:)
      real(dp), intent(in), optional :: del_z(:)
      real(dp), intent(in), optional :: x0(:)
      complex(dp), intent(in), optional :: quasi_z_proposed(:), quasi_z_flowed(:)
      real(dp), intent(in), optional :: quasi_res_norm(:), quasi_alpha(:)
      integer, intent(in), optional :: quasi_iter(:), quasi_backtrack(:), quasi_attempt(:)
      logical, intent(in), optional :: quasi_accepted(:), quasi_eval_ok(:)
      integer, intent(in), optional :: quasi_case, online_class
      real(dp), intent(in), optional :: trace_valid_fraction, trace_progress_ratio, trace_regress_ratio, trace_best_over_tol
      logical, intent(in), optional :: is_near_case, near_rescue_started, near_rescue_done
      logical, intent(in), optional :: near_fail_fast
      integer, intent(in), optional :: near_fail_fast_reason
      logical, intent(in), optional :: far_fail_fast
      integer, intent(in), optional :: far_fail_fast_reason
      integer, intent(in), optional :: attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown
      integer, intent(in), optional :: fail_flowz, fail_flowzr, fail_flow, fail_unknown
      integer, intent(in), optional :: success_final_resort, fail_final_resort
      integer, intent(in), optional :: radau_rescue_ok, radau_rescue_fail
      logical, intent(in), optional :: final_resort_budget_hit
      integer, intent(in), optional :: final_resort_budget_used, final_resort_budget_limit

      if (constraint_solver_stats_are_suppressed()) return
      fail_count = fail_count + 1_int64
      if (present(z0) .and. present(del_z) .and. present(x0)) then
         if (has_complete_quasi_trace(quasi_z_proposed, quasi_z_flowed, quasi_res_norm, quasi_alpha, &
                                      quasi_iter, quasi_backtrack, quasi_attempt, quasi_accepted, quasi_eval_ok)) then
            call capture_constraint_failure_sample(z0, del_z, x0, quasi_z_proposed, quasi_z_flowed, quasi_res_norm, quasi_alpha, &
                                                   quasi_iter, quasi_backtrack, quasi_attempt, quasi_accepted, quasi_eval_ok, &
                                                   quasi_case, online_class, trace_valid_fraction, trace_progress_ratio, &
                                                   trace_regress_ratio, trace_best_over_tol, is_near_case, near_rescue_started, &
                                                   near_rescue_done, near_fail_fast, near_fail_fast_reason, &
                                                   far_fail_fast, far_fail_fast_reason, &
                                                   attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                                   fail_flowz, fail_flowzr, fail_flow, fail_unknown, success_final_resort, &
                                                   fail_final_resort, radau_rescue_ok, radau_rescue_fail, &
                                                   final_resort_budget_hit, final_resort_budget_used, final_resort_budget_limit)
         else
            call capture_constraint_failure_sample(z0, del_z, x0, quasi_case=quasi_case, online_class=online_class, &
                                                   trace_valid_fraction=trace_valid_fraction, trace_progress_ratio=trace_progress_ratio, &
                                                   trace_regress_ratio=trace_regress_ratio, trace_best_over_tol=trace_best_over_tol, &
                                                   is_near_case=is_near_case, near_rescue_started=near_rescue_started, &
                                                   near_rescue_done=near_rescue_done, near_fail_fast=near_fail_fast, &
                                                   near_fail_fast_reason=near_fail_fast_reason, &
                                                   far_fail_fast=far_fail_fast, far_fail_fast_reason=far_fail_fast_reason, &
                                                   attempt_flowz=attempt_flowz, &
                                                   attempt_flowzr=attempt_flowzr, attempt_flow=attempt_flow, &
                                                   attempt_unknown=attempt_unknown, fail_flowz=fail_flowz, fail_flowzr=fail_flowzr, &
                                                   fail_flow=fail_flow, fail_unknown=fail_unknown, &
                                                   success_final_resort=success_final_resort, fail_final_resort=fail_final_resort, &
                                                   radau_rescue_ok=radau_rescue_ok, radau_rescue_fail=radau_rescue_fail, &
                                                   final_resort_budget_hit=final_resort_budget_hit, &
                                                   final_resort_budget_used=final_resort_budget_used, &
                                                   final_resort_budget_limit=final_resort_budget_limit)
         end if
      end if
   end subroutine record_constraint_solver_fail

   subroutine record_constraint_near_fail_candidate()
      implicit none
      if (constraint_solver_stats_are_suppressed()) return
      near_fail_candidate_count = near_fail_candidate_count + 1_int64
   end subroutine record_constraint_near_fail_candidate

   subroutine record_constraint_far_fail()
      implicit none
      if (constraint_solver_stats_are_suppressed()) return
      far_fail_count = far_fail_count + 1_int64
   end subroutine record_constraint_far_fail

   subroutine record_constraint_near_rescue_attempt()
      implicit none
      if (constraint_solver_stats_are_suppressed()) return
      near_rescue_attempt_count = near_rescue_attempt_count + 1_int64
   end subroutine record_constraint_near_rescue_attempt

   subroutine record_constraint_near_rescue_success()
      implicit none
      if (constraint_solver_stats_are_suppressed()) return
      near_rescue_success_count = near_rescue_success_count + 1_int64
   end subroutine record_constraint_near_rescue_success

   subroutine record_constraint_near_unusable()
      implicit none
      if (constraint_solver_stats_are_suppressed()) return
      near_unusable_count = near_unusable_count + 1_int64
   end subroutine record_constraint_near_unusable

   subroutine record_constraint_near_fail_fast()
      implicit none
      if (constraint_solver_stats_are_suppressed()) return
      near_fail_fast_count = near_fail_fast_count + 1_int64
   end subroutine record_constraint_near_fail_fast

   subroutine record_constraint_far_fail_fast()
      implicit none
      if (constraint_solver_stats_are_suppressed()) return
      far_fail_fast_count = far_fail_fast_count + 1_int64
   end subroutine record_constraint_far_fail_fast

   subroutine record_constraint_solver_far_investment(solved, fail_fast, flowzr_used, final_resort_used)
      implicit none
      logical, intent(in) :: solved, fail_fast
      integer, intent(in) :: flowzr_used, final_resort_used
      integer :: flow_use, final_use

      if (constraint_solver_stats_are_suppressed()) return
      flow_use = max(0, flowzr_used)
      final_use = max(0, final_resort_used)

      far_rescue_scope_count = far_rescue_scope_count + 1_int64
      far_rescue_flowzr_used_sum = far_rescue_flowzr_used_sum + int(flow_use, int64)
      far_rescue_final_resort_used_sum = far_rescue_final_resort_used_sum + int(final_use, int64)

      if (solved) then
         far_rescue_success_count = far_rescue_success_count + 1_int64
         far_rescue_flowzr_used_success_sum = far_rescue_flowzr_used_success_sum + int(flow_use, int64)
         far_rescue_final_resort_used_success_sum = far_rescue_final_resort_used_success_sum + int(final_use, int64)
         if (flow_use > 0 .or. final_use > 0) far_rescue_spent_success_count = far_rescue_spent_success_count + 1_int64
      else
         far_rescue_fail_count = far_rescue_fail_count + 1_int64
         far_rescue_flowzr_used_fail_sum = far_rescue_flowzr_used_fail_sum + int(flow_use, int64)
         far_rescue_final_resort_used_fail_sum = far_rescue_final_resort_used_fail_sum + int(final_use, int64)
         if (flow_use > 0 .or. final_use > 0) far_rescue_spent_fail_count = far_rescue_spent_fail_count + 1_int64
         if (fail_fast) far_rescue_fail_fast_case_count = far_rescue_fail_fast_case_count + 1_int64
      end if
   end subroutine record_constraint_solver_far_investment

   subroutine record_constraint_solver_global_filter(local_success)
      implicit none
      logical, intent(in) :: local_success

      call ensure_constraint_solver_stats_aliases_bound()
      if (constraint_solver_stats_are_suppressed()) return
      quasi_global_filter_candidate_count = quasi_global_filter_candidate_count + 1_int64
      if (local_success) then
         quasi_global_filter_pass_count = quasi_global_filter_pass_count + 1_int64
      else
         quasi_global_filter_reject_count = quasi_global_filter_reject_count + 1_int64
      end if
   end subroutine record_constraint_solver_global_filter

   subroutine record_constraint_solver_reverse_gate(local_success, used_probe_only, used_full_stage, &
                                                    used_near_rescue, used_nonnear_route, used_class_local, &
                                                    used_class_mid, used_class_global, used_far_skip, &
                                                    used_far_light, used_far_anchor)
      implicit none
      logical, intent(in) :: local_success
      logical, intent(in) :: used_probe_only, used_full_stage
      logical, intent(in) :: used_near_rescue, used_nonnear_route
      logical, intent(in) :: used_class_local, used_class_mid, used_class_global
      logical, intent(in) :: used_far_skip, used_far_light, used_far_anchor

      if (constraint_solver_stats_are_suppressed()) return
      call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_total, local_success)
      if (used_probe_only) then
         call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_probe_only, local_success)
      end if
      if (used_full_stage) then
         call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_full_stage, local_success)
      end if
      if (used_near_rescue) then
         call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_near_rescue, local_success)
      end if
      if (used_nonnear_route) then
         call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_nonnear_route, local_success)
      end if
      if (used_class_local) then
         call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_class_local, local_success)
      end if
      if (used_class_mid) then
         call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_class_mid, local_success)
      end if
      if (used_class_global) then
         call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_class_global, local_success)
      end if
      if (used_far_skip) then
         call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_far_skip, local_success)
      end if
      if (used_far_light) then
         call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_far_light, local_success)
      end if
      if (used_far_anchor) then
         call record_constraint_solver_reverse_gate_path(constraint_reverse_gate_path_far_anchor, local_success)
      end if
   end subroutine record_constraint_solver_reverse_gate

   subroutine record_constraint_solver_reverse_gate_path(path_code, local_success)
      implicit none
      integer, intent(in) :: path_code
      logical, intent(in) :: local_success

      if (constraint_solver_stats_are_suppressed()) return
      if (path_code < 1 .or. path_code > constraint_reverse_gate_path_count) return
      reverse_gate_candidate_count(path_code) = reverse_gate_candidate_count(path_code) + 1_int64
      if (local_success) then
         reverse_gate_pass_count(path_code) = reverse_gate_pass_count(path_code) + 1_int64
      else
         reverse_gate_reject_count(path_code) = reverse_gate_reject_count(path_code) + 1_int64
      end if
   end subroutine record_constraint_solver_reverse_gate_path

   subroutine get_constraint_solver_reverse_gate_stats(candidate_count, pass_count, reject_count)
      implicit none
      integer(int64), intent(out) :: candidate_count(:), pass_count(:), reject_count(:)
      integer :: n_candidate, n_pass, n_reject

      call ensure_constraint_solver_stats_aliases_bound()
      candidate_count = 0_int64
      pass_count = 0_int64
      reject_count = 0_int64
      n_candidate = min(size(candidate_count), constraint_reverse_gate_path_count)
      n_pass = min(size(pass_count), constraint_reverse_gate_path_count)
      n_reject = min(size(reject_count), constraint_reverse_gate_path_count)
      if (n_candidate > 0) candidate_count(1:n_candidate) = reverse_gate_candidate_count(1:n_candidate)
      if (n_pass > 0) pass_count(1:n_pass) = reverse_gate_pass_count(1:n_pass)
      if (n_reject > 0) reject_count(1:n_reject) = reverse_gate_reject_count(1:n_reject)
   end subroutine get_constraint_solver_reverse_gate_stats

   subroutine get_constraint_solver_global_filter_stats(candidate_count, pass_count, reject_count)
      implicit none
      integer(int64), intent(out) :: candidate_count, pass_count, reject_count

      call ensure_constraint_solver_stats_aliases_bound()
      candidate_count = quasi_global_filter_candidate_count
      pass_count = quasi_global_filter_pass_count
      reject_count = quasi_global_filter_reject_count
   end subroutine get_constraint_solver_global_filter_stats

   subroutine get_constraint_near_rescue_stats(near_candidate_count, far_count, near_attempt_count, near_success_count, &
                                               near_unusable_cert_count, near_fail_fast_unsolvable_count, &
                                               far_fail_fast_unsolvable_count)
      implicit none
      integer(int64), intent(out) :: near_candidate_count, far_count
      integer(int64), intent(out) :: near_attempt_count, near_success_count, near_unusable_cert_count
      integer(int64), intent(out), optional :: near_fail_fast_unsolvable_count
      integer(int64), intent(out), optional :: far_fail_fast_unsolvable_count

      call ensure_constraint_solver_stats_aliases_bound()
      near_candidate_count = near_fail_candidate_count
      far_count = far_fail_count
      near_attempt_count = near_rescue_attempt_count
      near_success_count = near_rescue_success_count
      near_unusable_cert_count = near_unusable_count
      if (present(near_fail_fast_unsolvable_count)) near_fail_fast_unsolvable_count = near_fail_fast_count
      if (present(far_fail_fast_unsolvable_count)) far_fail_fast_unsolvable_count = far_fail_fast_count
   end subroutine get_constraint_near_rescue_stats

   subroutine get_constraint_solver_failure_capture_status(captured_count, capture_limit, reached_limit)
      implicit none
      integer, intent(out) :: captured_count, capture_limit
      logical, intent(out) :: reached_limit

      call ensure_constraint_solver_stats_aliases_bound()
      call load_failure_capture_policy()
      captured_count = failure_capture_count
      capture_limit = failure_capture_limit_runtime
      reached_limit = (failure_capture_limit_runtime > 0 .and. failure_capture_count >= failure_capture_limit_runtime)
   end subroutine get_constraint_solver_failure_capture_status

   subroutine get_constraint_solver_stats(total_count, newton_count, quasi_count, failed_count, &
                                          newton_ratio, quasi_ratio, fail_ratio)
      implicit none
      integer(int64), intent(out) :: total_count, newton_count, quasi_count, failed_count
      real(dp), intent(out) :: newton_ratio, quasi_ratio, fail_ratio
      real(dp) :: denom

      call ensure_constraint_solver_stats_aliases_bound()
      newton_count = newton_success_count
      quasi_count = quasi_success_count
      failed_count = fail_count
      total_count = newton_count + quasi_count + failed_count

      if (total_count > 0_int64) then
         denom = real(total_count, dp)
         newton_ratio = real(newton_count, dp)/denom
         quasi_ratio = real(quasi_count, dp)/denom
         fail_ratio = real(failed_count, dp)/denom
      else
         newton_ratio = 0.0_dp
         quasi_ratio = 0.0_dp
         fail_ratio = 0.0_dp
      end if
   end subroutine get_constraint_solver_stats

   subroutine get_constraint_solver_quasi_stage_stats(probe_attempt_count, probe_success_count, &
                                                      full_attempt_count, full_success_count)
      implicit none
      integer(int64), intent(out) :: probe_attempt_count, probe_success_count
      integer(int64), intent(out) :: full_attempt_count, full_success_count

      call ensure_constraint_solver_stats_aliases_bound()
      probe_attempt_count = quasi_probe_attempt_count
      probe_success_count = quasi_probe_success_count
      full_attempt_count = quasi_full_attempt_count
      full_success_count = quasi_full_success_count
   end subroutine get_constraint_solver_quasi_stage_stats

   subroutine get_constraint_solver_quasi_class_stats(local_count, mid_count, global_count)
      implicit none
      integer(int64), intent(out) :: local_count, mid_count, global_count

      call ensure_constraint_solver_stats_aliases_bound()
      local_count = quasi_class_local_count
      mid_count = quasi_class_mid_count
      global_count = quasi_class_global_count
   end subroutine get_constraint_solver_quasi_class_stats

   subroutine get_constraint_solver_far_route_stats(skip_count, light_count, anchor_count)
      implicit none
      integer(int64), intent(out) :: skip_count, light_count, anchor_count

      call ensure_constraint_solver_stats_aliases_bound()
      skip_count = quasi_far_route_skip_count
      light_count = quasi_far_route_light_count
      anchor_count = quasi_far_route_anchor_count
   end subroutine get_constraint_solver_far_route_stats

   subroutine get_constraint_solver_quasi_watchdog_stats(hit_count, used_sum, used_max, budget_last)
      implicit none
      integer(int64), intent(out) :: hit_count, used_sum
      integer, intent(out) :: used_max, budget_last

      call ensure_constraint_solver_stats_aliases_bound()
      hit_count = quasi_budget_hit_count
      used_sum = quasi_budget_used_sum
      used_max = quasi_budget_used_max
      budget_last = quasi_budget_limit_last
   end subroutine get_constraint_solver_quasi_watchdog_stats

   subroutine get_constraint_solver_far_investment_stats(scope_count, success_count, fail_count, fail_fast_case_count, &
                                                         spent_success_count, spent_fail_count, &
                                                         flowzr_used_sum, final_resort_used_sum, &
                                                         flowzr_used_success_sum, final_resort_used_success_sum, &
                                                         flowzr_used_fail_sum, final_resort_used_fail_sum)
      implicit none
      integer(int64), intent(out) :: scope_count, success_count, fail_count, fail_fast_case_count
      integer(int64), intent(out) :: spent_success_count, spent_fail_count
      integer(int64), intent(out) :: flowzr_used_sum, final_resort_used_sum
      integer(int64), intent(out) :: flowzr_used_success_sum, final_resort_used_success_sum
      integer(int64), intent(out) :: flowzr_used_fail_sum, final_resort_used_fail_sum

      call ensure_constraint_solver_stats_aliases_bound()
      scope_count = far_rescue_scope_count
      success_count = far_rescue_success_count
      fail_count = far_rescue_fail_count
      fail_fast_case_count = far_rescue_fail_fast_case_count
      spent_success_count = far_rescue_spent_success_count
      spent_fail_count = far_rescue_spent_fail_count
      flowzr_used_sum = far_rescue_flowzr_used_sum
      final_resort_used_sum = far_rescue_final_resort_used_sum
      flowzr_used_success_sum = far_rescue_flowzr_used_success_sum
      final_resort_used_success_sum = far_rescue_final_resort_used_success_sum
      flowzr_used_fail_sum = far_rescue_flowzr_used_fail_sum
      final_resort_used_fail_sum = far_rescue_final_resort_used_fail_sum
   end subroutine get_constraint_solver_far_investment_stats

   subroutine report_constraint_solver_stats(summary_tag)
      implicit none
      character(len=*), intent(in), optional :: summary_tag
      integer(int64) :: total_count, newton_count, quasi_count, failed_count
      integer(int64) :: probe_attempt_count, probe_success_count
      integer(int64) :: full_attempt_count, full_success_count
      integer(int64) :: class_local_count, class_mid_count, class_global_count
      integer(int64) :: far_route_skip_count, far_route_light_count, far_route_anchor_count
      integer(int64) :: far_scope_count, far_success_count, far_fail_case_count, far_fail_fast_case_count
      integer(int64) :: far_spent_success_count, far_spent_fail_count
      integer(int64) :: far_flowzr_used_sum, far_final_resort_used_sum
      integer(int64) :: far_flowzr_used_success_sum, far_final_resort_used_success_sum
      integer(int64) :: far_flowzr_used_fail_sum, far_final_resort_used_fail_sum
      real(dp) :: newton_ratio, quasi_ratio, fail_ratio, budget_used_avg
      real(dp) :: far_unit_success_share, far_case_success_share
      real(dp) :: far_units_total, far_units_success

      call get_constraint_solver_stats(total_count, newton_count, quasi_count, failed_count, &
                                       newton_ratio, quasi_ratio, fail_ratio)
      call get_constraint_solver_quasi_stage_stats(probe_attempt_count, probe_success_count, &
                                                   full_attempt_count, full_success_count)
      call get_constraint_solver_quasi_class_stats(class_local_count, class_mid_count, class_global_count)
      call get_constraint_solver_far_route_stats(far_route_skip_count, far_route_light_count, far_route_anchor_count)
      call get_constraint_solver_far_investment_stats(far_scope_count, far_success_count, far_fail_case_count, &
                                                      far_fail_fast_case_count, far_spent_success_count, far_spent_fail_count, &
                                                      far_flowzr_used_sum, far_final_resort_used_sum, &
                                                      far_flowzr_used_success_sum, far_final_resort_used_success_sum, &
                                                      far_flowzr_used_fail_sum, far_final_resort_used_fail_sum)
      call load_failure_capture_policy()
      if (quasi_budget_hit_count > 0_int64) then
         budget_used_avg = real(quasi_budget_used_sum, dp)/real(quasi_budget_hit_count, dp)
      else
         budget_used_avg = 0.0_dp
      end if
      far_units_total = real(far_flowzr_used_sum + far_final_resort_used_sum, dp)
      far_units_success = real(far_flowzr_used_success_sum + far_final_resort_used_success_sum, dp)
      if (far_units_total > 0.0_dp) then
         far_unit_success_share = far_units_success/far_units_total
      else
         far_unit_success_share = 0.0_dp
      end if
      if (far_scope_count > 0_int64) then
         far_case_success_share = real(far_success_count, dp)/real(far_scope_count, dp)
      else
         far_case_success_share = 0.0_dp
      end if

      if (present(summary_tag)) then
         write (*, '(A,1X,A,I0)') trim(summary_tag), "constraint_solver_attempts=", total_count
         write (*, '(A,1X,A,I0,A,F8.5)') trim(summary_tag), "simplified_newton_success=", &
            newton_count, " ratio=", newton_ratio
         write (*, '(A,1X,A,I0,A,F8.5)') trim(summary_tag), "switch_to_quasi_newton_success=", &
            quasi_count, " ratio=", quasi_ratio
         write (*, '(A,1X,A,I0,A,F8.5)') trim(summary_tag), "constraint_solver_fail=", &
            failed_count, " ratio=", fail_ratio
         write (*, '(A,1X,A,I0,A,I0,A,I0,A,I0)') trim(summary_tag), "quasi_stage probe=", &
            probe_success_count, "/", probe_attempt_count, " full=", full_success_count, "/", full_attempt_count
         write (*, '(A,1X,A,I0,A,I0,A,I0)') trim(summary_tag), "quasi_class local=", class_local_count, &
            " mid=", class_mid_count, " global=", class_global_count
         write (*, '(A,1X,A,I0,A,I0,A,I0)') trim(summary_tag), "quasi_far_route skip=", far_route_skip_count, &
            " light=", far_route_light_count, " anchor=", far_route_anchor_count
         write (*, '(A,1X,A,I0,A,I0,A,F10.2,A,I0)') trim(summary_tag), "quasi_watchdog hits=", quasi_budget_hit_count, &
            " max_used=", quasi_budget_used_max, " avg_used=", budget_used_avg, " budget_last=", quasi_budget_limit_last
         write (*, '(A,1X,A,I0,A,I0)') trim(summary_tag), "near_fail_fast=", near_fail_fast_count, &
            " far_fail_fast=", far_fail_fast_count
         write (*, '(A,1X,A,I0,A,I0,A,I0,A,I0,A,F7.4)') trim(summary_tag), "far_invest cases=", far_scope_count, &
            " success=", far_success_count, " fail=", far_fail_case_count, " fail_fast=", far_fail_fast_case_count, &
            " success_share=", far_case_success_share
         write (*, '(A,1X,A,I0,A,I0,A,I0,A,I0,A,F7.4)') trim(summary_tag), "far_invest spent_success=", &
            far_spent_success_count, " spent_fail=", far_spent_fail_count, " flowzr_units=", far_flowzr_used_sum, &
            " final_units=", far_final_resort_used_sum, " unit_success_share=", far_unit_success_share
         write (*, '(A,1X,A,I0,A,I0,A,I0,A,I0)') trim(summary_tag), "far_invest success_units flowzr=", &
            far_flowzr_used_success_sum, " final=", far_final_resort_used_success_sum, &
            " fail_units flowzr=", far_flowzr_used_fail_sum, " final=", far_final_resort_used_fail_sum
         if (failure_capture_limit_runtime > 0) then
            write (*, '(A,1X,A,I0,A,I0)') trim(summary_tag), "constraint_failure_samples=", &
               failure_capture_count, " limit=", failure_capture_limit_runtime
         else
            write (*, '(A,1X,A,I0,A)') trim(summary_tag), "constraint_failure_samples=", &
               failure_capture_count, " limit=unlimited"
         end if
      else
         write (*, '(A,I0)') "[SUMMARY] constraint_solver_attempts=", total_count
         write (*, '(A,I0,A,F8.5)') "[SUMMARY] simplified_newton_success=", &
            newton_count, " ratio=", newton_ratio
         write (*, '(A,I0,A,F8.5)') "[SUMMARY] switch_to_quasi_newton_success=", &
            quasi_count, " ratio=", quasi_ratio
         write (*, '(A,I0,A,F8.5)') "[SUMMARY] constraint_solver_fail=", &
            failed_count, " ratio=", fail_ratio
         write (*, '(A,I0,A,I0,A,I0,A,I0)') "[SUMMARY] quasi_stage probe=", &
            probe_success_count, "/", probe_attempt_count, " full=", full_success_count, "/", full_attempt_count
         write (*, '(A,I0,A,I0,A,I0)') "[SUMMARY] quasi_class local=", class_local_count, &
            " mid=", class_mid_count, " global=", class_global_count
         write (*, '(A,I0,A,I0,A,I0)') "[SUMMARY] quasi_far_route skip=", far_route_skip_count, &
            " light=", far_route_light_count, " anchor=", far_route_anchor_count
         write (*, '(A,I0,A,I0,A,F10.2,A,I0)') "[SUMMARY] quasi_watchdog hits=", quasi_budget_hit_count, &
            " max_used=", quasi_budget_used_max, " avg_used=", budget_used_avg, " budget_last=", quasi_budget_limit_last
         write (*, '(A,I0,A,I0)') "[SUMMARY] near_fail_fast=", near_fail_fast_count, &
            " far_fail_fast=", far_fail_fast_count
         write (*, '(A,I0,A,I0,A,I0,A,I0,A,F7.4)') "[SUMMARY] far_invest cases=", far_scope_count, &
            " success=", far_success_count, " fail=", far_fail_case_count, " fail_fast=", far_fail_fast_case_count, &
            " success_share=", far_case_success_share
         write (*, '(A,I0,A,I0,A,I0,A,I0,A,F7.4)') "[SUMMARY] far_invest spent_success=", &
            far_spent_success_count, " spent_fail=", far_spent_fail_count, " flowzr_units=", far_flowzr_used_sum, &
            " final_units=", far_final_resort_used_sum, " unit_success_share=", far_unit_success_share
         write (*, '(A,I0,A,I0,A,I0,A,I0)') "[SUMMARY] far_invest success_units flowzr=", &
            far_flowzr_used_success_sum, " final=", far_final_resort_used_success_sum, &
            " fail_units flowzr=", far_flowzr_used_fail_sum, " final=", far_final_resort_used_fail_sum
         if (failure_capture_limit_runtime > 0) then
            write (*, '(A,I0,A,I0)') "[SUMMARY] constraint_failure_samples=", &
               failure_capture_count, " limit=", failure_capture_limit_runtime
         else
            write (*, '(A,I0,A)') "[SUMMARY] constraint_failure_samples=", &
               failure_capture_count, " limit=unlimited"
         end if
      end if
   end subroutine report_constraint_solver_stats

   subroutine reset_constraint_failure_capture()
      implicit none

      call ensure_constraint_solver_stats_aliases_bound()
      if (failure_capture_z0_unit /= -1) close (unit=failure_capture_z0_unit)
      if (failure_capture_delz_unit /= -1) close (unit=failure_capture_delz_unit)
      if (failure_capture_x0_unit /= -1) close (unit=failure_capture_x0_unit)
      if (failure_capture_quasi_unit /= -1) close (unit=failure_capture_quasi_unit)
      if (failure_capture_meta_unit /= -1) close (unit=failure_capture_meta_unit)
      failure_capture_z0_unit = -1
      failure_capture_delz_unit = -1
      failure_capture_x0_unit = -1
      failure_capture_quasi_unit = -1
      failure_capture_meta_unit = -1
      failure_capture_files_ready = .false.
      failure_capture_write_error = .false.
      failure_capture_count = 0
      failure_capture_limit_runtime = failure_capture_limit_default
      failure_capture_start_sample = 0
      failure_capture_policy_ready = .false.
      failure_capture_z0_file = ""
      failure_capture_delz_file = ""
      failure_capture_x0_file = ""
      failure_capture_quasi_file = ""
      failure_capture_meta_file = ""
      context_chain_sample_idx = 0
      context_hmc_repeat_idx = 0
      prev_meta_attempt_flowz = 0
      prev_meta_attempt_flowzr = 0
      prev_meta_attempt_flow = 0
      prev_meta_attempt_unknown = 0
      prev_meta_fail_flowz = 0
      prev_meta_fail_flowzr = 0
      prev_meta_fail_flow = 0
      prev_meta_fail_unknown = 0
      prev_meta_success_final_resort = 0
      prev_meta_fail_final_resort = 0
   end subroutine reset_constraint_failure_capture

   subroutine load_failure_capture_policy()
      implicit none

      call ensure_constraint_solver_stats_aliases_bound()
      if (failure_capture_policy_ready) return
      failure_capture_policy_ready = .true.

      call parse_int_env("CONSTRAINT_FAIL_CAPTURE_LIMIT", failure_capture_limit_runtime)

      call parse_int_env("CONSTRAINT_FAIL_CAPTURE_START_SAMPLE", failure_capture_start_sample)
      failure_capture_start_sample = max(0, failure_capture_start_sample)

      if (failure_capture_limit_runtime > 0) then
         write (*, '(A,I0)') "[INFO] constraint fail capture limit=", failure_capture_limit_runtime
      else
         write (*, '(A)') "[INFO] constraint fail capture limit=unlimited"
      end if
      if (failure_capture_start_sample > 0) then
         write (*, '(A,I0)') "[INFO] constraint fail capture start sample=", failure_capture_start_sample
      end if
   end subroutine load_failure_capture_policy

   subroutine ensure_failure_capture_files(io_ok)
      implicit none
      logical, intent(out) :: io_ok
      integer :: ios

      call ensure_constraint_solver_stats_aliases_bound()
      call load_failure_capture_policy()
      io_ok = .true.
      if (failure_capture_files_ready) return
      if (failure_capture_write_error) then
         io_ok = .false.
         return
      end if

      call resolve_failure_capture_paths()

      open (newunit=failure_capture_z0_unit, file=failure_capture_z0_file, status='replace', &
            access='stream', form='unformatted', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[WARN] Failed to open constraint failure z0 output:", trim(failure_capture_z0_file)
         failure_capture_write_error = .true.
         io_ok = .false.
         return
      end if

      open (newunit=failure_capture_delz_unit, file=failure_capture_delz_file, status='replace', &
            access='stream', form='unformatted', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[WARN] Failed to open constraint failure delz output:", trim(failure_capture_delz_file)
         close (unit=failure_capture_z0_unit)
         failure_capture_z0_unit = -1
         failure_capture_write_error = .true.
         io_ok = .false.
         return
      end if

      open (newunit=failure_capture_x0_unit, file=failure_capture_x0_file, status='replace', &
            access='stream', form='unformatted', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[WARN] Failed to open constraint failure x0 output:", trim(failure_capture_x0_file)
         close (unit=failure_capture_z0_unit)
         close (unit=failure_capture_delz_unit)
         failure_capture_z0_unit = -1
         failure_capture_delz_unit = -1
         failure_capture_write_error = .true.
         io_ok = .false.
         return
      end if

      open (newunit=failure_capture_quasi_unit, file=failure_capture_quasi_file, status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[WARN] Failed to open quasi-trace output:", trim(failure_capture_quasi_file)
         close (unit=failure_capture_z0_unit)
         close (unit=failure_capture_delz_unit)
         close (unit=failure_capture_x0_unit)
         failure_capture_z0_unit = -1
         failure_capture_delz_unit = -1
         failure_capture_x0_unit = -1
         failure_capture_write_error = .true.
         io_ok = .false.
         return
      end if
      write (failure_capture_quasi_unit, '(A)') &
         "sample_idx,proposal_idx,attempt_idx,iter_idx,backtrack_idx,alpha,res_norm,accepted,eval_ok,z_prop_re,z_prop_im,z_flow_re,z_flow_im"

      open (newunit=failure_capture_meta_unit, file=failure_capture_meta_file, status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[WARN] Failed to open failure-meta output:", trim(failure_capture_meta_file)
         close (unit=failure_capture_z0_unit)
         close (unit=failure_capture_delz_unit)
         close (unit=failure_capture_x0_unit)
         close (unit=failure_capture_quasi_unit)
         failure_capture_z0_unit = -1
         failure_capture_delz_unit = -1
         failure_capture_x0_unit = -1
         failure_capture_quasi_unit = -1
         failure_capture_write_error = .true.
         io_ok = .false.
         return
      end if
      write (failure_capture_meta_unit, '(A)') &
         "sample_idx,chain_sample_idx,hmc_repeat_idx,quasi_case,online_class,is_near_case,near_rescue_started,near_rescue_done,near_fail_fast,near_fail_fast_reason,far_fail_fast,far_fail_fast_reason," // &
         "trace_valid_fraction,trace_progress_ratio,trace_regress_ratio,trace_best_over_tol," // &
         "attempt_flowz,attempt_flowzr,attempt_flow,attempt_unknown,fail_flowz,fail_flowzr,fail_flow,fail_unknown," // &
         "success_final_resort,fail_final_resort,radau_rescue_ok,radau_rescue_fail," // &
         "final_resort_budget_hit,final_resort_budget_used,final_resort_budget_limit," // &
         "d_attempt_flowz,d_attempt_flowzr,d_attempt_flow,d_attempt_unknown,d_fail_flowz,d_fail_flowzr,d_fail_flow,d_fail_unknown," // &
         "d_success_final_resort,d_fail_final_resort"

      failure_capture_files_ready = .true.
      write (*, '(A,1X,A)') "[INFO] Capturing failing z0 snapshots in", trim(failure_capture_z0_file)
      if (failure_capture_limit_runtime > 0) then
         write (*, '(A,1X,A,1X,A,I0)') "[INFO] Capturing failing delz snapshots in", trim(failure_capture_delz_file), &
            "limit=", failure_capture_limit_runtime
      else
         write (*, '(A,1X,A,1X,A)') "[INFO] Capturing failing delz snapshots in", trim(failure_capture_delz_file), &
            "limit=unlimited"
      end if
      write (*, '(A,1X,A)') "[INFO] Capturing failing x0 snapshots in", trim(failure_capture_x0_file)
      write (*, '(A,1X,A)') "[INFO] Capturing failing quasi traces in", trim(failure_capture_quasi_file)
      write (*, '(A,1X,A)') "[INFO] Capturing failing meta rows in", trim(failure_capture_meta_file)
   end subroutine ensure_failure_capture_files

   subroutine resolve_failure_capture_paths()
      implicit none
      character(len=512) :: out_dir

      call ensure_constraint_solver_stats_aliases_bound()
      call extract_parent_dir(trim(x_history_file), out_dir)
      if (len_trim(out_dir) > 0) then
         failure_capture_z0_file = join_path(out_dir, failure_capture_z0_name)
         failure_capture_delz_file = join_path(out_dir, failure_capture_delz_name)
         failure_capture_x0_file = join_path(out_dir, failure_capture_x0_name)
         failure_capture_quasi_file = join_path(out_dir, failure_capture_quasi_name)
         failure_capture_meta_file = join_path(out_dir, failure_capture_meta_name)
      else
         failure_capture_z0_file = failure_capture_z0_name
         failure_capture_delz_file = failure_capture_delz_name
         failure_capture_x0_file = failure_capture_x0_name
         failure_capture_quasi_file = failure_capture_quasi_name
         failure_capture_meta_file = failure_capture_meta_name
      end if
   end subroutine resolve_failure_capture_paths

   subroutine extract_parent_dir(path, parent_dir)
      implicit none
      character(len=*), intent(in) :: path
      character(len=*), intent(out) :: parent_dir
      integer :: slash_pos, backslash_pos, split_pos

      parent_dir = ""
      if (len_trim(path) == 0) return

      slash_pos = index(trim(path), '/', back=.true.)
      backslash_pos = index(trim(path), char(92), back=.true.)
      split_pos = max(slash_pos, backslash_pos)
      if (split_pos > 1) parent_dir = trim(path(:split_pos - 1))
   end subroutine extract_parent_dir

   function join_path(dir_path, file_name) result(full_path)
      implicit none
      character(len=*), intent(in) :: dir_path, file_name
      character(len=512) :: full_path
      integer :: n

      full_path = ""
      if (len_trim(dir_path) == 0) then
         full_path = trim(file_name)
         return
      end if

      n = len_trim(dir_path)
      if (dir_path(n:n) == '/' .or. dir_path(n:n) == char(92)) then
         full_path = trim(dir_path)//trim(file_name)
      else
         full_path = trim(dir_path)//"/"//trim(file_name)
      end if
   end function join_path

   subroutine capture_constraint_failure_sample(z0, del_z, x0, quasi_z_proposed, quasi_z_flowed, quasi_res_norm, quasi_alpha, &
                                                quasi_iter, quasi_backtrack, quasi_attempt, quasi_accepted, quasi_eval_ok, &
                                                quasi_case, online_class, trace_valid_fraction, trace_progress_ratio, &
                                                trace_regress_ratio, trace_best_over_tol, is_near_case, near_rescue_started, &
                                                near_rescue_done, near_fail_fast, near_fail_fast_reason, &
                                                far_fail_fast, far_fail_fast_reason, &
                                                attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                                fail_flowz, fail_flowzr, fail_flow, fail_unknown, success_final_resort, &
                                                fail_final_resort, radau_rescue_ok, radau_rescue_fail, &
                                                final_resort_budget_hit, final_resort_budget_used, final_resort_budget_limit, force_capture)
      implicit none
      complex(dp), intent(in) :: z0(:)
      real(dp), intent(in) :: del_z(:)
      real(dp), intent(in) :: x0(:)
      complex(dp), intent(in), optional :: quasi_z_proposed(:), quasi_z_flowed(:)
      real(dp), intent(in), optional :: quasi_res_norm(:), quasi_alpha(:)
      integer, intent(in), optional :: quasi_iter(:), quasi_backtrack(:), quasi_attempt(:)
      logical, intent(in), optional :: quasi_accepted(:), quasi_eval_ok(:)
      integer, intent(in), optional :: quasi_case, online_class
      real(dp), intent(in), optional :: trace_valid_fraction, trace_progress_ratio, trace_regress_ratio, trace_best_over_tol
      logical, intent(in), optional :: is_near_case, near_rescue_started, near_rescue_done
      logical, intent(in), optional :: near_fail_fast
      integer, intent(in), optional :: near_fail_fast_reason
      logical, intent(in), optional :: far_fail_fast
      integer, intent(in), optional :: far_fail_fast_reason
      integer, intent(in), optional :: attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown
      integer, intent(in), optional :: fail_flowz, fail_flowzr, fail_flow, fail_unknown
      integer, intent(in), optional :: success_final_resort, fail_final_resort
      integer, intent(in), optional :: radau_rescue_ok, radau_rescue_fail
      logical, intent(in), optional :: final_resort_budget_hit
      integer, intent(in), optional :: final_resort_budget_used, final_resort_budget_limit
      logical, intent(in), optional :: force_capture
      integer :: sample_idx, n_z, n_delz, n_x, ios
      logical :: io_ok, force_capture_local

      call ensure_constraint_solver_stats_aliases_bound()
      call load_failure_capture_policy()
      force_capture_local = .false.
      if (present(force_capture)) force_capture_local = force_capture
      if (.not. force_capture_local) then
         if (failure_capture_start_sample > 0 .and. context_chain_sample_idx < failure_capture_start_sample) return
         if (failure_capture_limit_runtime > 0 .and. failure_capture_count >= failure_capture_limit_runtime) return
      end if

      call ensure_failure_capture_files(io_ok)
      if (.not. io_ok) return

      sample_idx = failure_capture_count + 1
      n_z = size(z0)
      n_delz = size(del_z)
      n_x = size(x0)

      write (failure_capture_z0_unit, iostat=ios) sample_idx, n_z, z0
      if (ios /= 0) then
         call handle_failure_capture_error("[WARN] Failed writing constraint failure z0 snapshot.")
         return
      end if

      write (failure_capture_delz_unit, iostat=ios) sample_idx, n_delz, del_z
      if (ios /= 0) then
         call handle_failure_capture_error("[WARN] Failed writing constraint failure delz snapshot.")
         return
      end if

      write (failure_capture_x0_unit, iostat=ios) sample_idx, n_x, x0
      if (ios /= 0) then
         call handle_failure_capture_error("[WARN] Failed writing constraint failure x0 snapshot.")
         return
      end if

      if (has_complete_quasi_trace(quasi_z_proposed, quasi_z_flowed, quasi_res_norm, quasi_alpha, &
                                   quasi_iter, quasi_backtrack, quasi_attempt, quasi_accepted, quasi_eval_ok)) then
         call write_quasi_trace_rows(sample_idx, quasi_z_proposed, quasi_z_flowed, quasi_res_norm, quasi_alpha, &
                                     quasi_iter, quasi_backtrack, quasi_attempt, quasi_accepted, quasi_eval_ok, io_ok)
         if (.not. io_ok) then
            call handle_failure_capture_error("[WARN] Failed writing quasi-trace rows.")
            return
         end if
      end if

      call write_failure_meta_row(sample_idx, quasi_case, online_class, trace_valid_fraction, trace_progress_ratio, &
                                  trace_regress_ratio, trace_best_over_tol, is_near_case, near_rescue_started, &
                                  near_rescue_done, near_fail_fast, near_fail_fast_reason, &
                                  far_fail_fast, far_fail_fast_reason, &
                                  attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                  fail_flowz, fail_flowzr, fail_flow, fail_unknown, success_final_resort, &
                                  fail_final_resort, radau_rescue_ok, radau_rescue_fail, &
                                  final_resort_budget_hit, final_resort_budget_used, final_resort_budget_limit, io_ok)
      if (.not. io_ok) then
         call handle_failure_capture_error("[WARN] Failed writing failure-meta row.")
         return
      end if

      flush (failure_capture_z0_unit)
      flush (failure_capture_delz_unit)
      flush (failure_capture_x0_unit)
      flush (failure_capture_quasi_unit)
      flush (failure_capture_meta_unit)
      failure_capture_count = sample_idx

      if (failure_capture_limit_runtime > 0 .and. failure_capture_count == failure_capture_limit_runtime) then
         write (*, '(A,I0,A)') "[INFO] Reached constraint failure capture target: ", failure_capture_limit_runtime, "."
      end if
   end subroutine capture_constraint_failure_sample

   logical function has_complete_quasi_trace(quasi_z_proposed, quasi_z_flowed, quasi_res_norm, quasi_alpha, &
                                             quasi_iter, quasi_backtrack, quasi_attempt, quasi_accepted, quasi_eval_ok) result(ok)
      implicit none
      complex(dp), intent(in), optional :: quasi_z_proposed(:), quasi_z_flowed(:)
      real(dp), intent(in), optional :: quasi_res_norm(:), quasi_alpha(:)
      integer, intent(in), optional :: quasi_iter(:), quasi_backtrack(:), quasi_attempt(:)
      logical, intent(in), optional :: quasi_accepted(:), quasi_eval_ok(:)
      integer :: n_trace

      ok = .false.
      if (.not. present(quasi_z_proposed)) return
      if (.not. present(quasi_z_flowed)) return
      if (.not. present(quasi_res_norm)) return
      if (.not. present(quasi_alpha)) return
      if (.not. present(quasi_iter)) return
      if (.not. present(quasi_backtrack)) return
      if (.not. present(quasi_attempt)) return
      if (.not. present(quasi_accepted)) return
      if (.not. present(quasi_eval_ok)) return

      n_trace = size(quasi_z_proposed)
      if (n_trace <= 0) return
      ok = (size(quasi_z_flowed) == n_trace .and. size(quasi_res_norm) == n_trace .and. size(quasi_alpha) == n_trace .and. &
            size(quasi_iter) == n_trace .and. size(quasi_backtrack) == n_trace .and. size(quasi_attempt) == n_trace .and. &
            size(quasi_accepted) == n_trace .and. size(quasi_eval_ok) == n_trace)
   end function has_complete_quasi_trace

   subroutine write_quasi_trace_rows(sample_idx, quasi_z_proposed, quasi_z_flowed, quasi_res_norm, quasi_alpha, &
                                     quasi_iter, quasi_backtrack, quasi_attempt, quasi_accepted, quasi_eval_ok, io_ok)
      implicit none
      integer, intent(in) :: sample_idx
      complex(dp), intent(in) :: quasi_z_proposed(:), quasi_z_flowed(:)
      real(dp), intent(in) :: quasi_res_norm(:), quasi_alpha(:)
      integer, intent(in) :: quasi_iter(:), quasi_backtrack(:), quasi_attempt(:)
      logical, intent(in) :: quasi_accepted(:), quasi_eval_ok(:)
      logical, intent(out) :: io_ok
      integer :: i, ios, n_trace, accepted_flag, eval_ok_flag

      call ensure_constraint_solver_stats_aliases_bound()
      io_ok = .true.
      n_trace = size(quasi_res_norm)
      do i = 1, n_trace
         accepted_flag = merge(1, 0, quasi_accepted(i))
         eval_ok_flag = merge(1, 0, quasi_eval_ok(i))
         write (failure_capture_quasi_unit, &
                '(I0,",",I0,",",I0,",",I0,",",I0,",",ES24.16,",",ES24.16,",",I0,",",I0,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16)', &
                iostat=ios) sample_idx, i, quasi_attempt(i), quasi_iter(i), quasi_backtrack(i), quasi_alpha(i), &
            quasi_res_norm(i), accepted_flag, eval_ok_flag, real(quasi_z_proposed(i), dp), aimag(quasi_z_proposed(i)), &
            real(quasi_z_flowed(i), dp), aimag(quasi_z_flowed(i))
         if (ios /= 0) then
            io_ok = .false.
            return
         end if
      end do
   end subroutine write_quasi_trace_rows

   subroutine write_failure_meta_row(sample_idx, quasi_case, online_class, trace_valid_fraction, trace_progress_ratio, &
                                     trace_regress_ratio, trace_best_over_tol, is_near_case, near_rescue_started, &
                                     near_rescue_done, near_fail_fast, near_fail_fast_reason, &
                                     far_fail_fast, far_fail_fast_reason, &
                                     attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                     fail_flowz, fail_flowzr, fail_flow, fail_unknown, success_final_resort, &
                                     fail_final_resort, radau_rescue_ok, radau_rescue_fail, &
                                     final_resort_budget_hit, final_resort_budget_used, final_resort_budget_limit, io_ok)
      implicit none
      integer, intent(in) :: sample_idx
      integer, intent(in), optional :: quasi_case, online_class
      real(dp), intent(in), optional :: trace_valid_fraction, trace_progress_ratio, trace_regress_ratio, trace_best_over_tol
      logical, intent(in), optional :: is_near_case, near_rescue_started, near_rescue_done
      logical, intent(in), optional :: near_fail_fast
      integer, intent(in), optional :: near_fail_fast_reason
      logical, intent(in), optional :: far_fail_fast
      integer, intent(in), optional :: far_fail_fast_reason
      integer, intent(in), optional :: attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown
      integer, intent(in), optional :: fail_flowz, fail_flowzr, fail_flow, fail_unknown
      integer, intent(in), optional :: success_final_resort, fail_final_resort
      integer, intent(in), optional :: radau_rescue_ok, radau_rescue_fail
      logical, intent(in), optional :: final_resort_budget_hit
      integer, intent(in), optional :: final_resort_budget_used, final_resort_budget_limit
      logical, intent(out) :: io_ok
      integer :: ios
      integer :: v_quasi_case, v_online_class
      integer :: v_is_near_case, v_near_rescue_started, v_near_rescue_done
      integer :: v_near_fail_fast, v_near_fail_fast_reason
      integer :: v_far_fail_fast, v_far_fail_fast_reason
      integer :: v_attempt_flowz, v_attempt_flowzr, v_attempt_flow, v_attempt_unknown
      integer :: v_fail_flowz, v_fail_flowzr, v_fail_flow, v_fail_unknown
      integer :: v_success_final_resort, v_fail_final_resort
      integer :: v_radau_rescue_ok, v_radau_rescue_fail
      integer :: v_final_resort_budget_hit, v_final_resort_budget_used, v_final_resort_budget_limit
      real(dp) :: v_trace_valid_fraction, v_trace_progress_ratio, v_trace_regress_ratio, v_trace_best_over_tol
      integer :: d_attempt_flowz, d_attempt_flowzr, d_attempt_flow, d_attempt_unknown
      integer :: d_fail_flowz, d_fail_flowzr, d_fail_flow, d_fail_unknown
      integer :: d_success_final_resort, d_fail_final_resort

      call ensure_constraint_solver_stats_aliases_bound()
      io_ok = .true.
      v_quasi_case = optional_int(quasi_case, -1)
      v_online_class = optional_int(online_class, -1)
      v_is_near_case = optional_logical_int(is_near_case, -1)
      v_near_rescue_started = optional_logical_int(near_rescue_started, -1)
      v_near_rescue_done = optional_logical_int(near_rescue_done, -1)
      v_near_fail_fast = optional_logical_int(near_fail_fast, 0)
      v_near_fail_fast_reason = optional_int(near_fail_fast_reason, 0)
      v_far_fail_fast = optional_logical_int(far_fail_fast, 0)
      v_far_fail_fast_reason = optional_int(far_fail_fast_reason, 0)
      v_trace_valid_fraction = optional_real(trace_valid_fraction, -1.0_dp)
      v_trace_progress_ratio = optional_real(trace_progress_ratio, -1.0_dp)
      v_trace_regress_ratio = optional_real(trace_regress_ratio, -1.0_dp)
      v_trace_best_over_tol = optional_real(trace_best_over_tol, -1.0_dp)

      v_attempt_flowz = optional_int(attempt_flowz, -1)
      v_attempt_flowzr = optional_int(attempt_flowzr, -1)
      v_attempt_flow = optional_int(attempt_flow, -1)
      v_attempt_unknown = optional_int(attempt_unknown, -1)
      v_fail_flowz = optional_int(fail_flowz, -1)
      v_fail_flowzr = optional_int(fail_flowzr, -1)
      v_fail_flow = optional_int(fail_flow, -1)
      v_fail_unknown = optional_int(fail_unknown, -1)
      v_success_final_resort = optional_int(success_final_resort, -1)
      v_fail_final_resort = optional_int(fail_final_resort, -1)
      v_radau_rescue_ok = optional_int(radau_rescue_ok, -1)
      v_radau_rescue_fail = optional_int(radau_rescue_fail, -1)
      v_final_resort_budget_hit = optional_logical_int(final_resort_budget_hit, -1)
      v_final_resort_budget_used = optional_int(final_resort_budget_used, -1)
      v_final_resort_budget_limit = optional_int(final_resort_budget_limit, -1)

      if (v_final_resort_budget_limit >= 0) quasi_budget_limit_last = v_final_resort_budget_limit
      if (v_final_resort_budget_used >= 0) then
         quasi_budget_used_max = max(quasi_budget_used_max, v_final_resort_budget_used)
         quasi_budget_used_sum = quasi_budget_used_sum + int(v_final_resort_budget_used, int64)
      end if
      if (v_final_resort_budget_hit == 1) quasi_budget_hit_count = quasi_budget_hit_count + 1_int64

      if (v_attempt_flowz >= 0) then
         d_attempt_flowz = v_attempt_flowz - prev_meta_attempt_flowz
         prev_meta_attempt_flowz = v_attempt_flowz
      else
         d_attempt_flowz = 0
      end if
      if (v_attempt_flowzr >= 0) then
         d_attempt_flowzr = v_attempt_flowzr - prev_meta_attempt_flowzr
         prev_meta_attempt_flowzr = v_attempt_flowzr
      else
         d_attempt_flowzr = 0
      end if
      if (v_attempt_flow >= 0) then
         d_attempt_flow = v_attempt_flow - prev_meta_attempt_flow
         prev_meta_attempt_flow = v_attempt_flow
      else
         d_attempt_flow = 0
      end if
      if (v_attempt_unknown >= 0) then
         d_attempt_unknown = v_attempt_unknown - prev_meta_attempt_unknown
         prev_meta_attempt_unknown = v_attempt_unknown
      else
         d_attempt_unknown = 0
      end if
      if (v_fail_flowz >= 0) then
         d_fail_flowz = v_fail_flowz - prev_meta_fail_flowz
         prev_meta_fail_flowz = v_fail_flowz
      else
         d_fail_flowz = 0
      end if
      if (v_fail_flowzr >= 0) then
         d_fail_flowzr = v_fail_flowzr - prev_meta_fail_flowzr
         prev_meta_fail_flowzr = v_fail_flowzr
      else
         d_fail_flowzr = 0
      end if
      if (v_fail_flow >= 0) then
         d_fail_flow = v_fail_flow - prev_meta_fail_flow
         prev_meta_fail_flow = v_fail_flow
      else
         d_fail_flow = 0
      end if
      if (v_fail_unknown >= 0) then
         d_fail_unknown = v_fail_unknown - prev_meta_fail_unknown
         prev_meta_fail_unknown = v_fail_unknown
      else
         d_fail_unknown = 0
      end if
      if (v_success_final_resort >= 0) then
         d_success_final_resort = v_success_final_resort - prev_meta_success_final_resort
         prev_meta_success_final_resort = v_success_final_resort
      else
         d_success_final_resort = 0
      end if
      if (v_fail_final_resort >= 0) then
         d_fail_final_resort = v_fail_final_resort - prev_meta_fail_final_resort
         prev_meta_fail_final_resort = v_fail_final_resort
      else
         d_fail_final_resort = 0
      end if

      write (failure_capture_meta_unit, '(*(g0,:,","))', iostat=ios) &
         sample_idx, context_chain_sample_idx, context_hmc_repeat_idx, v_quasi_case, v_online_class, &
         v_is_near_case, v_near_rescue_started, v_near_rescue_done, v_near_fail_fast, v_near_fail_fast_reason, &
         v_far_fail_fast, v_far_fail_fast_reason, &
         v_trace_valid_fraction, v_trace_progress_ratio, v_trace_regress_ratio, v_trace_best_over_tol, &
         v_attempt_flowz, v_attempt_flowzr, v_attempt_flow, v_attempt_unknown, &
         v_fail_flowz, v_fail_flowzr, v_fail_flow, v_fail_unknown, &
         v_success_final_resort, v_fail_final_resort, v_radau_rescue_ok, v_radau_rescue_fail, &
         v_final_resort_budget_hit, v_final_resort_budget_used, v_final_resort_budget_limit, &
         d_attempt_flowz, d_attempt_flowzr, d_attempt_flow, d_attempt_unknown, &
         d_fail_flowz, d_fail_flowzr, d_fail_flow, d_fail_unknown, &
         d_success_final_resort, d_fail_final_resort
      if (ios /= 0) then
         io_ok = .false.
      end if
   end subroutine write_failure_meta_row

   integer function optional_int(value, fallback) result(out)
      implicit none
      integer, intent(in), optional :: value
      integer, intent(in) :: fallback
      if (present(value)) then
         out = value
      else
         out = fallback
      end if
   end function optional_int

   integer function optional_logical_int(value, fallback) result(out)
      implicit none
      logical, intent(in), optional :: value
      integer, intent(in) :: fallback
      if (present(value)) then
         out = merge(1, 0, value)
      else
         out = fallback
      end if
   end function optional_logical_int

   real(dp) function optional_real(value, fallback) result(out)
      implicit none
      real(dp), intent(in), optional :: value
      real(dp), intent(in) :: fallback
      if (present(value)) then
         out = value
      else
         out = fallback
      end if
   end function optional_real

   subroutine handle_failure_capture_error(message)
      implicit none
      character(len=*), intent(in) :: message

      call ensure_constraint_solver_stats_aliases_bound()
      write (*, '(A)') trim(message)
      if (failure_capture_z0_unit /= -1) close (unit=failure_capture_z0_unit)
      if (failure_capture_delz_unit /= -1) close (unit=failure_capture_delz_unit)
      if (failure_capture_x0_unit /= -1) close (unit=failure_capture_x0_unit)
      if (failure_capture_quasi_unit /= -1) close (unit=failure_capture_quasi_unit)
      if (failure_capture_meta_unit /= -1) close (unit=failure_capture_meta_unit)
      failure_capture_z0_unit = -1
      failure_capture_delz_unit = -1
      failure_capture_x0_unit = -1
      failure_capture_quasi_unit = -1
      failure_capture_meta_unit = -1
      failure_capture_files_ready = .false.
      failure_capture_write_error = .true.
   end subroutine handle_failure_capture_error

end module constraint_solver_stats_mod

module tltm_stage2_driver
   use, intrinsic :: iso_fortran_env, only: int64
   use param_mod, only: config, read_parameters
   use runtime_env_mod, only: parse_int_env, parse_real_env, parse_logical_env, parse_real_list, to_lower_ascii
   use utils
   use solve_flow, only: flow, reset_intode_fallback_stats, get_intode_fallback_stats, &
                         intode_status_unknown, intode_status_is_strict_success
   use model, only: grand, calculate_action
   use mt95, only: getseed, sgrnd, grnd
   use markovchain_mod, only: adaptive_preflow_to_target
   use markovchain_metropolis, only: metropolis_step
   use markovchain_phase, only: compute_phase_factor
   use hmc_constraints, only: reset_newton_eval_flow_status_counts, get_newton_eval_flow_status_counts
   use hmc_integrator_core, only: reset_reverse_gate_replay_status_counts, get_reverse_gate_replay_status_counts
   use quasi_newton_solver_mod, only: get_quasi_global_filter_stats, reset_quasi_eval_flow_status_counts, &
                                      get_quasi_eval_flow_status_counts
   use constraint_solver_stats_mod, only: reset_constraint_solver_stats, get_constraint_solver_stats, &
                                          get_constraint_solver_quasi_stage_stats, &
                                          get_constraint_solver_quasi_class_stats, &
                                          get_constraint_solver_far_route_stats, &
                                          get_constraint_near_rescue_stats, &
                                          get_constraint_solver_quasi_watchdog_stats, &
                                          get_constraint_solver_far_investment_stats, &
                                          get_constraint_solver_reverse_gate_stats, &
                                          constraint_reverse_gate_path_count, &
                                          constraint_reverse_gate_path_total, &
                                          constraint_reverse_gate_path_probe_only, &
                                          constraint_reverse_gate_path_full_stage, &
                                          constraint_reverse_gate_path_near_rescue, &
                                          constraint_reverse_gate_path_nonnear_route, &
                                          constraint_reverse_gate_path_class_local, &
                                          constraint_reverse_gate_path_class_mid, &
                                          constraint_reverse_gate_path_class_global, &
                                          constraint_reverse_gate_path_far_skip, &
                                          constraint_reverse_gate_path_far_light, &
                                          constraint_reverse_gate_path_far_anchor
   use tltm_types_mod, only: tltm_slot_t, tltm_pair_stats_t, tltm_label_track_t, allocate_tltm_slot, release_tltm_slot, &
                             record_tltm_local_transition
   implicit none

   integer, parameter :: stage2_cycle_cap_default = 200
   integer, parameter :: stage2_init_attempts_default = 200
   real(dp), parameter :: stage2_init_sigma_default = 0.10_dp

   type :: solver_counter_snapshot_t
      integer(int64) :: newton_count = 0_int64
      integer(int64) :: quasi_count = 0_int64
      integer(int64) :: probe_attempt_count = 0_int64
      integer(int64) :: probe_success_count = 0_int64
      integer(int64) :: full_attempt_count = 0_int64
      integer(int64) :: full_success_count = 0_int64
      integer(int64) :: class_local_count = 0_int64
      integer(int64) :: class_mid_count = 0_int64
      integer(int64) :: class_global_count = 0_int64
      integer(int64) :: far_route_skip_count = 0_int64
      integer(int64) :: far_route_light_count = 0_int64
      integer(int64) :: far_route_anchor_count = 0_int64
      integer(int64) :: near_attempt_count = 0_int64
      integer(int64) :: near_success_count = 0_int64
      integer(int64) :: reverse_gate_candidate_total = 0_int64
      integer(int64) :: reverse_gate_pass_total = 0_int64
      integer(int64) :: reverse_gate_reject_total = 0_int64
   end type solver_counter_snapshot_t

   logical, save :: rg_reject_audit_loaded = .false.
   logical, save :: rg_reject_audit_enabled = .false.
   integer, save :: rg_reject_audit_unit = -1
   character(len=512), save :: rg_reject_audit_file = ""

   type :: local_accept_census_t
      integer(int64) :: accepted_total = 0_int64
      integer(int64) :: accepted_newton_only = 0_int64
      integer(int64) :: accepted_quasi = 0_int64
      integer(int64) :: accepted_rescue = 0_int64
      integer(int64) :: accepted_probe_only = 0_int64
      integer(int64) :: accepted_full_stage = 0_int64
      integer(int64) :: accepted_near_rescue = 0_int64
      integer(int64) :: accepted_nonnear_route = 0_int64
      integer(int64) :: accepted_class_local = 0_int64
      integer(int64) :: accepted_class_mid = 0_int64
      integer(int64) :: accepted_class_global = 0_int64
      integer(int64) :: accepted_far_skip = 0_int64
      integer(int64) :: accepted_far_light = 0_int64
      integer(int64) :: accepted_far_anchor = 0_int64
      integer(int64) :: accepted_uncategorized = 0_int64
   end type local_accept_census_t

contains

   subroutine execute_tltm_stage2()
      type(tltm_slot_t), allocatable :: slots(:)
      type(tltm_pair_stats_t), allocatable :: pair_stats(:)
      type(tltm_label_track_t), allocatable :: label_tracks(:)
      type(local_accept_census_t), allocatable :: local_accept_census(:)
      real(dp), allocatable :: flow_ladder(:)
      character(len=512) :: summary_file, label_trace_file
      character(len=512) :: cold_z_history_file, cold_phi_history_file
      character(len=512) :: all_history_dir
      character(len=32) :: init_mode
      integer :: n_slots, base_seed, cycle_count, local_updates, x_size
      real(dp) :: max_flow_time, init_sigma
      logical :: swap_enabled, ok
      integer :: i, cycle_idx, hot_slot, history_slot_index
      real(dp) :: run_t0, elapsed, slot_t0
      integer, parameter :: unit_trace = 78
      integer, parameter :: unit_cold_z = 79, unit_cold_phi = 80
      integer, allocatable :: all_z_units(:), all_phi_units(:)
      integer :: io_status
      logical :: write_cold_history, cold_sample_ok
      logical :: write_all_history, all_sample_ok
      logical :: path_ok
      integer :: calls_total, calls_integrating
      integer :: fallback_attempts, fallback_success, fallback_failure
      integer :: fallback_max_steps, fallback_invalid, fallback_h_min
      integer(int64) :: solver_total_count, solver_newton_count, solver_quasi_count, solver_failed_count
      real(dp) :: solver_newton_ratio, solver_quasi_ratio, solver_fail_ratio
      integer(int64) :: quasi_probe_attempt_count, quasi_probe_success_count
      integer(int64) :: quasi_full_attempt_count, quasi_full_success_count
      integer(int64) :: quasi_class_local_count, quasi_class_mid_count, quasi_class_global_count
      integer(int64) :: far_route_skip_count, far_route_light_count, far_route_anchor_count
      integer(int64) :: near_candidate_count, near_attempt_count, near_success_count, near_unusable_count
      integer(int64) :: quasi_watchdog_hit_count, quasi_watchdog_used_sum
      integer :: quasi_watchdog_used_max, quasi_watchdog_budget_last
      integer(int64) :: far_scope_count, far_success_count, far_fail_count, far_fail_fast_count
      integer(int64) :: far_spent_success_count, far_spent_fail_count
      integer(int64) :: far_flowzr_used_sum, far_final_resort_used_sum
      integer(int64) :: far_flowzr_used_success_sum, far_final_resort_used_success_sum
      integer(int64) :: far_flowzr_used_fail_sum, far_final_resort_used_fail_sum
      integer(int64) :: global_filter_candidate_count, global_filter_pass_count, global_filter_reject_count
      integer(int64) :: reverse_gate_candidate_counts(constraint_reverse_gate_path_count)
      integer(int64) :: reverse_gate_pass_counts(constraint_reverse_gate_path_count)
      integer(int64) :: reverse_gate_reject_counts(constraint_reverse_gate_path_count)

      call read_parameters()
      call reset_intode_fallback_stats()
      call reset_constraint_solver_stats()
      call reset_newton_eval_flow_status_counts()
      call reset_quasi_eval_flow_status_counts()
      call reset_reverse_gate_replay_status_counts()

      x_size = config%state%x_size
      call resolve_base_seed(base_seed)
      call resolve_stage2_controls(config%integrator%initial_flow_time, config%chain%length, config%chain%hmc_repeat, &
                                   n_slots, flow_ladder, max_flow_time, cycle_count, local_updates, init_sigma, init_mode, &
                                   swap_enabled)
      call resolve_stage2_output_paths(summary_file, label_trace_file)
      call resolve_stage2_cold_history_paths(cold_z_history_file, cold_phi_history_file, write_cold_history)
      call resolve_stage2_all_history_dir(all_history_dir, write_all_history)

      write (*, '(A,I0,A,F8.4,A,I0,A,I0,A,F8.4,A,L1)') "[TLTM-S2] slots=", n_slots, &
         " max_flow=", max_flow_time, " cycles=", cycle_count, " local_updates=", local_updates, &
         " init_sigma=", init_sigma, " swap_enabled=", swap_enabled
      write (*, '(A,A)') "[TLTM-S2] init_mode=", trim(init_mode)
      write (*, '(A,F8.4,A,I0,A,F8.4)') "[TLTM-S2] local params: L=", config%integrator%trajectory_length, &
         " nstep=", config%integrator%integration_steps, " max_flow(test)=", max_flow_time

      hot_slot = n_slots - 1

      allocate (slots(n_slots), label_tracks(n_slots), local_accept_census(n_slots))
      if (n_slots > 1) then
         allocate (pair_stats(n_slots - 1))
      else
         allocate (pair_stats(0))
      end if

      do i = 1, n_slots
         slots(i)%slot_id = i - 1
         slots(i)%label_id = i - 1
         slots(i)%flow_time = flow_ladder(i)
         slots(i)%rng_seed = derive_seed(base_seed, i)
         call allocate_tltm_slot(slots(i), x_size)
         call initialize_slot(slots(i), init_sigma, stage2_init_attempts_default, init_mode, ok)
         if (.not. ok) then
            write (*, '(A,I0,A,F8.4,A)') "[ERROR][TLTM-S2] Slot ", slots(i)%slot_id, &
               " initialization failed at flow_time=", slots(i)%flow_time, "."
            call release_all_slots(slots)
            if (allocated(flow_ladder)) deallocate (flow_ladder)
            if (allocated(pair_stats)) deallocate (pair_stats)
            if (allocated(label_tracks)) deallocate (label_tracks)
            error stop 1
         end if
      end do

      call initialize_pair_stats(pair_stats)
      call initialize_label_tracks(label_tracks, n_slots)

      if (write_cold_history) then
         history_slot_index = find_max_flow_slot_index(slots)
         write (*, '(A,I0,A,F10.6)') "[TLTM-S2] history slot index=", history_slot_index - 1, &
            " flow_time=", slots(history_slot_index)%flow_time
         call ensure_parent_directory_exists(cold_z_history_file, path_ok)
         if (.not. path_ok) then
            write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot prepare directory for cold z-history file:", trim(cold_z_history_file)
            call release_all_slots(slots)
            if (allocated(flow_ladder)) deallocate (flow_ladder)
            if (allocated(pair_stats)) deallocate (pair_stats)
            if (allocated(label_tracks)) deallocate (label_tracks)
            error stop 1
         end if
         call ensure_parent_directory_exists(cold_phi_history_file, path_ok)
         if (.not. path_ok) then
            write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot prepare directory for cold phi-history file:", trim(cold_phi_history_file)
            call release_all_slots(slots)
            if (allocated(flow_ladder)) deallocate (flow_ladder)
            if (allocated(pair_stats)) deallocate (pair_stats)
            if (allocated(label_tracks)) deallocate (label_tracks)
            error stop 1
         end if
         open (unit=unit_cold_z, file=trim(cold_z_history_file), status='replace', access='stream', &
               form='unformatted', action='write', iostat=io_status)
         if (io_status /= 0) then
            write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open cold z-history file:", trim(cold_z_history_file)
            call release_all_slots(slots)
            if (allocated(flow_ladder)) deallocate (flow_ladder)
            if (allocated(pair_stats)) deallocate (pair_stats)
            if (allocated(label_tracks)) deallocate (label_tracks)
            error stop 1
         end if
         open (unit=unit_cold_phi, file=trim(cold_phi_history_file), status='replace', access='stream', &
               form='unformatted', action='write', iostat=io_status)
         if (io_status /= 0) then
            write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open cold phi-history file:", trim(cold_phi_history_file)
            close (unit=unit_cold_z)
            call release_all_slots(slots)
            if (allocated(flow_ladder)) deallocate (flow_ladder)
            if (allocated(pair_stats)) deallocate (pair_stats)
            if (allocated(label_tracks)) deallocate (label_tracks)
            error stop 1
         end if
         call write_cold_history_sample(slots(history_slot_index), unit_cold_z, unit_cold_phi, cold_sample_ok)
         if (.not. cold_sample_ok) then
            close (unit=unit_cold_z)
            close (unit=unit_cold_phi)
            call release_all_slots(slots)
            if (allocated(flow_ladder)) deallocate (flow_ladder)
            if (allocated(pair_stats)) deallocate (pair_stats)
            if (allocated(label_tracks)) deallocate (label_tracks)
            error stop 1
         end if
      end if

      if (write_all_history) then
         write (*, '(A,1X,A)') "[TLTM-S2] all-replica history dir=", trim(all_history_dir)
         call open_all_replica_history_files(slots, all_history_dir, all_z_units, all_phi_units, ok)
         if (.not. ok) then
            if (write_cold_history) then
               close (unit_cold_z)
               close (unit_cold_phi)
            end if
            call release_all_slots(slots)
            if (allocated(flow_ladder)) deallocate (flow_ladder)
            if (allocated(pair_stats)) deallocate (pair_stats)
            if (allocated(label_tracks)) deallocate (label_tracks)
            error stop 1
         end if
         call write_all_replica_history_samples(slots, all_z_units, all_phi_units, all_sample_ok)
         if (.not. all_sample_ok) then
            call close_all_replica_history_files(all_z_units, all_phi_units)
            if (write_cold_history) then
               close (unit_cold_z)
               close (unit_cold_phi)
            end if
            call release_all_slots(slots)
            if (allocated(flow_ladder)) deallocate (flow_ladder)
            if (allocated(pair_stats)) deallocate (pair_stats)
            if (allocated(label_tracks)) deallocate (label_tracks)
            error stop 1
         end if
      end if

      open (unit=unit_trace, file=trim(label_trace_file), status='replace', action='write', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open label trace file:", trim(label_trace_file)
         if (write_cold_history) then
            close (unit=unit_cold_z)
            close (unit=unit_cold_phi)
         end if
         if (write_all_history) call close_all_replica_history_files(all_z_units, all_phi_units)
         call release_all_slots(slots)
         if (allocated(flow_ladder)) deallocate (flow_ladder)
         if (allocated(pair_stats)) deallocate (pair_stats)
         if (allocated(label_tracks)) deallocate (label_tracks)
         error stop 1
      end if
      write (unit_trace, '(A)') "# cycle label_id slot_id round_trip_count"
      call refresh_label_positions(slots, label_tracks)
      call update_round_trip_bookkeeping(label_tracks, 0, hot_slot)
      call write_label_trace(unit_trace, 0, label_tracks)

      call sgrnd(base_seed)
      run_t0 = wall_time_seconds()
      do cycle_idx = 1, cycle_count
         do i = 1, n_slots
            slot_t0 = wall_time_seconds()
            call run_local_updates(slots(i), local_updates, local_accept_census(i), cycle_idx)
            slots(i)%local_runtime = slots(i)%local_runtime + (wall_time_seconds() - slot_t0)
            call measure_slot(slots(i))
         end do
         if (write_cold_history) then
            call write_cold_history_sample(slots(history_slot_index), unit_cold_z, unit_cold_phi, cold_sample_ok)
            if (.not. cold_sample_ok) then
               close (unit_trace)
               close (unit_cold_z)
               close (unit_cold_phi)
               if (write_all_history) call close_all_replica_history_files(all_z_units, all_phi_units)
               call release_all_slots(slots)
               if (allocated(flow_ladder)) deallocate (flow_ladder)
               if (allocated(pair_stats)) deallocate (pair_stats)
               if (allocated(label_tracks)) deallocate (label_tracks)
               error stop 1
            end if
         end if
         if (write_all_history) then
            call write_all_replica_history_samples(slots, all_z_units, all_phi_units, all_sample_ok)
            if (.not. all_sample_ok) then
               close (unit_trace)
               if (write_cold_history) then
                  close (unit_cold_z)
                  close (unit_cold_phi)
               end if
               call close_all_replica_history_files(all_z_units, all_phi_units)
               call release_all_slots(slots)
               if (allocated(flow_ladder)) deallocate (flow_ladder)
               if (allocated(pair_stats)) deallocate (pair_stats)
               if (allocated(label_tracks)) deallocate (label_tracks)
               error stop 1
            end if
         end if

         if (swap_enabled .and. n_slots > 1) then
            call perform_swap_sweep(slots, pair_stats, cycle_idx)
         end if

         call refresh_label_positions(slots, label_tracks)
         call update_round_trip_bookkeeping(label_tracks, cycle_idx, hot_slot)
         call write_label_trace(unit_trace, cycle_idx, label_tracks)

         if (cycle_idx == 1 .or. mod(cycle_idx, 10) == 0 .or. cycle_idx == cycle_count) then
            write (*, '(A,I0,A,I0)') "[TLTM-S2] cycle ", cycle_idx, "/", cycle_count
         end if
      end do
      elapsed = wall_time_seconds() - run_t0

      close (unit_trace)
      if (write_cold_history) then
         close (unit_cold_z)
         close (unit_cold_phi)
      end if
      if (write_all_history) call close_all_replica_history_files(all_z_units, all_phi_units)
      call get_intode_fallback_stats(calls_total, calls_integrating, fallback_attempts, fallback_success, fallback_failure, &
                                     fallback_max_steps, fallback_invalid, fallback_h_min)
      call get_constraint_solver_stats(solver_total_count, solver_newton_count, solver_quasi_count, solver_failed_count, &
                                       solver_newton_ratio, solver_quasi_ratio, solver_fail_ratio)
      call get_constraint_solver_quasi_stage_stats(quasi_probe_attempt_count, quasi_probe_success_count, &
                                                   quasi_full_attempt_count, quasi_full_success_count)
      call get_constraint_solver_quasi_class_stats(quasi_class_local_count, quasi_class_mid_count, &
                                                   quasi_class_global_count)
      call get_constraint_solver_far_route_stats(far_route_skip_count, far_route_light_count, &
                                                 far_route_anchor_count)
      call get_constraint_near_rescue_stats(near_candidate_count, far_fail_count, near_attempt_count, &
                                            near_success_count, near_unusable_count)
      call get_constraint_solver_quasi_watchdog_stats(quasi_watchdog_hit_count, quasi_watchdog_used_sum, &
                                                      quasi_watchdog_used_max, quasi_watchdog_budget_last)
      call get_constraint_solver_far_investment_stats(far_scope_count, far_success_count, far_fail_count, &
                                                      far_fail_fast_count, far_spent_success_count, far_spent_fail_count, &
                                                      far_flowzr_used_sum, far_final_resort_used_sum, &
                                                      far_flowzr_used_success_sum, far_final_resort_used_success_sum, &
                                                      far_flowzr_used_fail_sum, far_final_resort_used_fail_sum)
      call get_quasi_global_filter_stats(global_filter_candidate_count, global_filter_pass_count, &
                                         global_filter_reject_count)
      call get_constraint_solver_reverse_gate_stats(reverse_gate_candidate_counts, reverse_gate_pass_counts, &
                                                    reverse_gate_reject_counts)
      call write_stage2_summary(summary_file, slots, pair_stats, label_tracks, local_accept_census, cycle_count, local_updates, elapsed, swap_enabled, &
                                calls_total, calls_integrating, fallback_attempts, fallback_success, fallback_failure, &
                                fallback_max_steps, fallback_invalid, fallback_h_min, &
                                solver_total_count, solver_newton_count, solver_quasi_count, solver_failed_count, &
                                solver_newton_ratio, solver_quasi_ratio, solver_fail_ratio, &
                                quasi_probe_attempt_count, quasi_probe_success_count, quasi_full_attempt_count, quasi_full_success_count, &
                                quasi_class_local_count, quasi_class_mid_count, quasi_class_global_count, &
                                far_route_skip_count, far_route_light_count, far_route_anchor_count, &
                                near_candidate_count, near_attempt_count, near_success_count, near_unusable_count, &
                                quasi_watchdog_hit_count, quasi_watchdog_used_sum, quasi_watchdog_used_max, quasi_watchdog_budget_last, &
                                far_scope_count, far_success_count, far_fail_count, far_fail_fast_count, &
                                far_spent_success_count, far_spent_fail_count, &
                                far_flowzr_used_sum, far_final_resort_used_sum, &
                                far_flowzr_used_success_sum, far_final_resort_used_success_sum, &
                                far_flowzr_used_fail_sum, far_final_resort_used_fail_sum, &
                                global_filter_candidate_count, global_filter_pass_count, global_filter_reject_count, &
                                reverse_gate_candidate_counts, reverse_gate_pass_counts, reverse_gate_reject_counts)
      call release_all_slots(slots)
      if (allocated(flow_ladder)) deallocate (flow_ladder)
      if (allocated(pair_stats)) deallocate (pair_stats)
      if (allocated(label_tracks)) deallocate (label_tracks)
      if (allocated(local_accept_census)) deallocate (local_accept_census)

      write (*, '(A,1X,A)') "[DONE][TLTM-S2] Summary written to", trim(summary_file)
      write (*, '(A,1X,A)') "[DONE][TLTM-S2] Label trace written to", trim(label_trace_file)
      if (write_cold_history) then
         write (*, '(A,1X,A)') "[DONE][TLTM-S2] Max-flow z-history written to", trim(cold_z_history_file)
         write (*, '(A,1X,A)') "[DONE][TLTM-S2] Max-flow phi-history written to", trim(cold_phi_history_file)
      end if
      if (write_all_history) then
         write (*, '(A,1X,A)') "[DONE][TLTM-S2] All-replica histories written under", trim(all_history_dir)
      end if
      call close_rg_reject_audit()
   end subroutine execute_tltm_stage2

   subroutine initialize_slot(slot, init_sigma, max_attempts, init_mode, ok)
      type(tltm_slot_t), intent(inout) :: slot
      real(dp), intent(in) :: init_sigma
      integer, intent(in) :: max_attempts
      character(len=*), intent(in) :: init_mode
      logical, intent(out) :: ok

      real(dp), allocatable :: x_seed(:)
      logical :: flow_failed
      logical :: preflow_success
      integer :: attempt, flow_status, stage_count

      ok = .false.
      allocate (x_seed(max(1, size(slot%x) - 1)))
      call sgrnd(slot%rng_seed)

      do attempt = 1, max_attempts
         call grand(x_seed)
         x_seed = init_sigma*x_seed
         if (trim(init_mode) == "direct" .or. trim(init_mode) == "legacy") then
            call x_set_flow_time(slot%x, slot%flow_time)
         else
            call x_set_flow_time(slot%x, 0.0_dp)
         end if
         call x_set_seed_real(slot%x, x_seed)

         if (trim(init_mode) /= "direct" .and. trim(init_mode) /= "legacy") then
            call adaptive_preflow_to_target(slot%x, slot%flow_time, config%integrator%trajectory_length, &
                                            config%integrator%integration_steps, attempt - 1, preflow_success, stage_count)
            if (.not. preflow_success) cycle
            write (*, '(A,I0,A,F10.6,A,I0,A,I0)') "[TLTM-S2][INIT] slot=", slot%slot_id, &
               " adaptive preflow ready at t=", slot%flow_time, " attempt=", attempt, " stages=", stage_count
         end if

         flow_status = intode_status_unknown
         call flow(slot%x, slot%z, slot%jac, flow_failed, flow_status)
         if ((.not. flow_failed) .and. intode_status_is_strict_success(flow_status)) then
            ok = .true.
            if (trim(init_mode) == "direct" .or. trim(init_mode) == "legacy") then
               write (*, '(A,I0,A,F10.6,A,I0)') "[TLTM-S2][INIT] slot=", slot%slot_id, &
                  " direct flow ready at t=", slot%flow_time, " attempt=", attempt
            end if
            exit
         end if
      end do

      if (ok) call measure_slot(slot)
      if (allocated(x_seed)) deallocate (x_seed)
   end subroutine initialize_slot

   subroutine run_local_updates(slot, local_updates, accept_census, cycle_idx)
      type(tltm_slot_t), intent(inout) :: slot
      integer, intent(in) :: local_updates
      type(local_accept_census_t), intent(inout) :: accept_census
      integer, intent(in) :: cycle_idx

      integer :: update_idx, z_size
      real(dp), allocatable :: x_new(:), x_before(:)
      complex(dp), allocatable :: z_new(:), j_new(:, :), z_before(:), j_before(:, :)
      logical :: accepted, proposal_failed
      integer :: transition_status
      type(solver_counter_snapshot_t) :: solver_before, solver_after

      z_size = size(slot%z)
      allocate (x_new(size(slot%x)), x_before(size(slot%x)))
      allocate (z_new(z_size), z_before(z_size), j_new(z_size, z_size), j_before(z_size, z_size))

      do update_idx = 1, local_updates
         x_before = slot%x
         z_before = slot%z
         j_before = slot%jac
         call snapshot_solver_counters(solver_before)
         call metropolis_step(slot%x, slot%z, slot%jac, config%integrator%trajectory_length, &
                              config%integrator%integration_steps, x_new, z_new, j_new, accepted, proposal_failed, transition_status)
         call snapshot_solver_counters(solver_after)
         if (accepted) then
            slot%x = x_new
            slot%z = z_new
            slot%jac = j_new
            call accumulate_accepted_local_census(accept_census, solver_before, solver_after)
         end if
         call record_tltm_local_transition(slot, accepted, proposal_failed, transition_status)
         call record_rg_reject_audit(cycle_idx, slot%slot_id, update_idx, x_before, z_before, j_before, &
                                     slot%x, slot%z, slot%jac, x_new, z_new, j_new, accepted, proposal_failed, &
                                     transition_status, solver_before, solver_after)
      end do

      if (allocated(x_new)) deallocate (x_new)
      if (allocated(x_before)) deallocate (x_before)
      if (allocated(z_new)) deallocate (z_new)
      if (allocated(z_before)) deallocate (z_before)
      if (allocated(j_new)) deallocate (j_new)
      if (allocated(j_before)) deallocate (j_before)
   end subroutine run_local_updates

   subroutine record_rg_reject_audit(cycle_idx, slot_id, update_idx, x_before, z_before, j_before, &
                                     x_after, z_after, j_after, x_proposal, z_proposal, j_proposal, &
                                     accepted, proposal_failed, transition_status, solver_before, solver_after)
      integer, intent(in) :: cycle_idx, slot_id, update_idx
      real(dp), intent(in) :: x_before(:), x_after(:), x_proposal(:)
      complex(dp), intent(in) :: z_before(:), z_after(:), z_proposal(:)
      complex(dp), intent(in) :: j_before(:, :), j_after(:, :), j_proposal(:, :)
      logical, intent(in) :: accepted, proposal_failed
      integer, intent(in) :: transition_status
      type(solver_counter_snapshot_t), intent(in) :: solver_before, solver_after

      integer(int64) :: rg_candidate_delta, rg_pass_delta, rg_reject_delta
      real(dp) :: slot_dx, slot_dz, slot_dj
      real(dp) :: proposal_dx, proposal_dz, proposal_dj

      call load_rg_reject_audit_config()
      if (.not. rg_reject_audit_enabled) return

      rg_candidate_delta = solver_after%reverse_gate_candidate_total - solver_before%reverse_gate_candidate_total
      rg_pass_delta = solver_after%reverse_gate_pass_total - solver_before%reverse_gate_pass_total
      rg_reject_delta = solver_after%reverse_gate_reject_total - solver_before%reverse_gate_reject_total
      if ((.not. proposal_failed) .and. rg_reject_delta <= 0_int64) return

      slot_dx = maxabs_real_stage2(x_after - x_before)
      slot_dz = maxabs_complex_vec_stage2(z_after - z_before)
      slot_dj = maxabs_complex_mat_stage2(j_after - j_before)
      proposal_dx = maxabs_real_stage2(x_proposal - x_before)
      proposal_dz = maxabs_complex_vec_stage2(z_proposal - z_before)
      proposal_dj = maxabs_complex_mat_stage2(j_proposal - j_before)

      write (rg_reject_audit_unit, &
             '(I0,",",I0,",",I0,",",L1,",",L1,",",I0,",",I0,",",I0,",",I0,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16)') &
         cycle_idx, slot_id, update_idx, accepted, proposal_failed, transition_status, rg_candidate_delta, rg_pass_delta, rg_reject_delta, &
         slot_dx, slot_dz, slot_dj, proposal_dx, proposal_dz, proposal_dj
      flush (rg_reject_audit_unit)
   end subroutine record_rg_reject_audit

   subroutine load_rg_reject_audit_config()
      character(len=512) :: env_value
      integer :: env_len, env_status, io_status

      if (rg_reject_audit_loaded) return
      rg_reject_audit_loaded = .true.

      call get_environment_variable("TLTM_RG_REJECT_AUDIT_FILE", env_value, length=env_len, status=env_status)
      if (env_status /= 0 .or. env_len <= 0) return

      rg_reject_audit_file = env_value(1:env_len)
      open (newunit=rg_reject_audit_unit, file=trim(rg_reject_audit_file), status='replace', action='write', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[WARN][TLTM-S2] Cannot open RG reject audit file:", trim(rg_reject_audit_file)
         rg_reject_audit_enabled = .false.
         rg_reject_audit_unit = -1
         return
      end if

      rg_reject_audit_enabled = .true.
      write (rg_reject_audit_unit, '(A)') &
         "cycle,slot_id,update_idx,accepted,proposal_failed,transition_status,rg_candidate_delta,rg_pass_delta,rg_reject_delta,"// &
         "slot_dx,slot_dz,slot_dj,proposal_dx,proposal_dz,proposal_dj"
      flush (rg_reject_audit_unit)
      write (*, '(A,1X,A)') "[INFO][TLTM-S2] RG reject audit file:", trim(rg_reject_audit_file)
   end subroutine load_rg_reject_audit_config

   subroutine close_rg_reject_audit()
      if (rg_reject_audit_enabled .and. rg_reject_audit_unit > 0) then
         close (rg_reject_audit_unit)
      end if
      rg_reject_audit_enabled = .false.
      rg_reject_audit_unit = -1
   end subroutine close_rg_reject_audit

   pure real(dp) function maxabs_real_stage2(vec)
      real(dp), intent(in) :: vec(:)
      if (size(vec) <= 0) then
         maxabs_real_stage2 = 0.0_dp
      else
         maxabs_real_stage2 = maxval(abs(vec))
      end if
   end function maxabs_real_stage2

   pure real(dp) function maxabs_complex_vec_stage2(vec)
      complex(dp), intent(in) :: vec(:)
      if (size(vec) <= 0) then
         maxabs_complex_vec_stage2 = 0.0_dp
      else
         maxabs_complex_vec_stage2 = maxval(abs(vec))
      end if
   end function maxabs_complex_vec_stage2

   pure real(dp) function maxabs_complex_mat_stage2(mat)
      complex(dp), intent(in) :: mat(:, :)
      if (size(mat) <= 0) then
         maxabs_complex_mat_stage2 = 0.0_dp
      else
         maxabs_complex_mat_stage2 = maxval(abs(mat))
      end if
   end function maxabs_complex_mat_stage2

   subroutine snapshot_solver_counters(snapshot)
      type(solver_counter_snapshot_t), intent(out) :: snapshot

      integer(int64) :: total_count, failed_count
      integer(int64) :: near_candidate_count, far_count, near_unusable_count
      integer(int64) :: rg_candidate_counts(constraint_reverse_gate_path_count)
      integer(int64) :: rg_pass_counts(constraint_reverse_gate_path_count)
      integer(int64) :: rg_reject_counts(constraint_reverse_gate_path_count)
      real(dp) :: ratio_newton, ratio_quasi, ratio_fail

      call get_constraint_solver_stats(total_count, snapshot%newton_count, snapshot%quasi_count, failed_count, &
                                       ratio_newton, ratio_quasi, ratio_fail)
      call get_constraint_solver_quasi_stage_stats(snapshot%probe_attempt_count, snapshot%probe_success_count, &
                                                   snapshot%full_attempt_count, snapshot%full_success_count)
      call get_constraint_solver_quasi_class_stats(snapshot%class_local_count, snapshot%class_mid_count, &
                                                   snapshot%class_global_count)
      call get_constraint_solver_far_route_stats(snapshot%far_route_skip_count, snapshot%far_route_light_count, &
                                                 snapshot%far_route_anchor_count)
      call get_constraint_near_rescue_stats(near_candidate_count, far_count, snapshot%near_attempt_count, &
                                            snapshot%near_success_count, near_unusable_count)
      call get_constraint_solver_reverse_gate_stats(rg_candidate_counts, rg_pass_counts, rg_reject_counts)
      snapshot%reverse_gate_candidate_total = rg_candidate_counts(constraint_reverse_gate_path_total)
      snapshot%reverse_gate_pass_total = rg_pass_counts(constraint_reverse_gate_path_total)
      snapshot%reverse_gate_reject_total = rg_reject_counts(constraint_reverse_gate_path_total)
   end subroutine snapshot_solver_counters

   subroutine accumulate_accepted_local_census(census, before, after)
      type(local_accept_census_t), intent(inout) :: census
      type(solver_counter_snapshot_t), intent(in) :: before, after

      logical :: used_newton, used_quasi, used_rescue
      logical :: used_full_stage, used_near_rescue, used_nonnear_route

      census%accepted_total = census%accepted_total + 1_int64

      used_newton = (after%newton_count > before%newton_count)
      used_quasi = (after%quasi_count > before%quasi_count)
      used_full_stage = (after%full_attempt_count > before%full_attempt_count)
      used_near_rescue = (after%near_attempt_count > before%near_attempt_count)
      used_nonnear_route = (after%far_route_skip_count > before%far_route_skip_count) .or. &
                           (after%far_route_light_count > before%far_route_light_count) .or. &
                           (after%far_route_anchor_count > before%far_route_anchor_count)
      used_rescue = used_full_stage .or. used_near_rescue .or. used_nonnear_route

      if (used_newton .and. .not. used_quasi) census%accepted_newton_only = census%accepted_newton_only + 1_int64
      if (used_quasi) census%accepted_quasi = census%accepted_quasi + 1_int64
      if (used_rescue) census%accepted_rescue = census%accepted_rescue + 1_int64
      if (used_quasi .and. .not. used_rescue) census%accepted_probe_only = census%accepted_probe_only + 1_int64
      if (used_full_stage) census%accepted_full_stage = census%accepted_full_stage + 1_int64
      if (used_near_rescue) census%accepted_near_rescue = census%accepted_near_rescue + 1_int64
      if (used_nonnear_route) census%accepted_nonnear_route = census%accepted_nonnear_route + 1_int64
      if (after%class_local_count > before%class_local_count) census%accepted_class_local = census%accepted_class_local + 1_int64
      if (after%class_mid_count > before%class_mid_count) census%accepted_class_mid = census%accepted_class_mid + 1_int64
      if (after%class_global_count > before%class_global_count) census%accepted_class_global = census%accepted_class_global + 1_int64
      if (after%far_route_skip_count > before%far_route_skip_count) census%accepted_far_skip = census%accepted_far_skip + 1_int64
      if (after%far_route_light_count > before%far_route_light_count) census%accepted_far_light = census%accepted_far_light + 1_int64
      if (after%far_route_anchor_count > before%far_route_anchor_count) census%accepted_far_anchor = census%accepted_far_anchor + 1_int64
      if (.not. used_newton .and. .not. used_quasi) census%accepted_uncategorized = census%accepted_uncategorized + 1_int64
   end subroutine accumulate_accepted_local_census

   subroutine measure_slot(slot)
      type(tltm_slot_t), intent(inout) :: slot
      complex(dp) :: phi
      logical :: error

      call compute_phase_factor(slot%z, slot%jac, phi, error)
      if (.not. error) then
         slot%phi_sum = slot%phi_sum + phi
         slot%observable_samples = slot%observable_samples + 1
      end if
   end subroutine measure_slot

   subroutine perform_swap_sweep(slots, pair_stats, cycle_idx)
      type(tltm_slot_t), intent(inout) :: slots(:)
      type(tltm_pair_stats_t), intent(inout) :: pair_stats(:)
      integer, intent(in) :: cycle_idx
      integer :: start_idx, idx

      if (size(slots) <= 1) return

      if (mod(cycle_idx, 2) == 1) then
         start_idx = 1
      else
         start_idx = 2
      end if

      do idx = start_idx, size(slots) - 1, 2
         call attempt_adjacent_swap(slots(idx), slots(idx + 1), pair_stats(idx))
      end do
   end subroutine perform_swap_sweep

   subroutine attempt_adjacent_swap(slot_a, slot_b, stats)
      type(tltm_slot_t), intent(inout) :: slot_a, slot_b
      type(tltm_pair_stats_t), intent(inout) :: stats

      real(dp) :: e_a, e_b, e_ap, e_bp, delta, acc_prob
      logical :: ok_a, ok_b, ok_ap, ok_bp, accept
      integer :: flow_status_ap, flow_status_bp, label_tmp
      real(dp), allocatable :: x_ap(:), x_bp(:)
      complex(dp), allocatable :: z_ap(:), z_bp(:), j_ap(:, :), j_bp(:, :)

      stats%proposal_count = stats%proposal_count + 1

      call compute_effective_energy(slot_a%z, slot_a%jac, e_a, ok_a)
      call compute_effective_energy(slot_b%z, slot_b%jac, e_b, ok_b)
      if (.not. ok_a .or. .not. ok_b) then
         stats%last_accept_probability = 0.0_dp
         stats%reject_count = stats%reject_count + 1
         return
      end if

      allocate (x_ap(size(slot_a%x)), x_bp(size(slot_b%x)))
      allocate (z_ap(size(slot_a%z)), z_bp(size(slot_b%z)))
      allocate (j_ap(size(slot_a%jac, 1), size(slot_a%jac, 2)))
      allocate (j_bp(size(slot_b%jac, 1), size(slot_b%jac, 2)))

      x_ap = slot_b%x
      call x_set_flow_time(x_ap, slot_a%flow_time)
      flow_status_ap = intode_status_unknown
      call flow(x_ap, z_ap, j_ap, ok_ap, flow_status_ap)
      ok_ap = (.not. ok_ap) .and. intode_status_is_strict_success(flow_status_ap)
      if (ok_ap) call compute_effective_energy(z_ap, j_ap, e_ap, ok_ap)

      x_bp = slot_a%x
      call x_set_flow_time(x_bp, slot_b%flow_time)
      flow_status_bp = intode_status_unknown
      call flow(x_bp, z_bp, j_bp, ok_bp, flow_status_bp)
      ok_bp = (.not. ok_bp) .and. intode_status_is_strict_success(flow_status_bp)
      if (ok_bp) call compute_effective_energy(z_bp, j_bp, e_bp, ok_bp)

      if (.not. ok_ap .or. .not. ok_bp) then
         stats%last_accept_probability = 0.0_dp
         stats%reject_count = stats%reject_count + 1
         call free_swap_buffers(x_ap, x_bp, z_ap, z_bp, j_ap, j_bp)
         return
      end if

      delta = (e_ap + e_bp) - (e_a + e_b)
      if (delta <= 0.0_dp) then
         acc_prob = 1.0_dp
      else
         acc_prob = exp(-delta)
      end if
      stats%last_accept_probability = acc_prob

      accept = (grnd() <= acc_prob)
      if (accept) then
         label_tmp = slot_a%label_id
         slot_a%x = x_ap
         slot_a%z = z_ap
         slot_a%jac = j_ap
         slot_a%label_id = slot_b%label_id

         slot_b%x = x_bp
         slot_b%z = z_bp
         slot_b%jac = j_bp
         slot_b%label_id = label_tmp
         stats%accept_count = stats%accept_count + 1
      else
         stats%reject_count = stats%reject_count + 1
      end if

      call free_swap_buffers(x_ap, x_bp, z_ap, z_bp, j_ap, j_bp)
   end subroutine attempt_adjacent_swap

   subroutine compute_effective_energy(z, jac, energy, ok)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(out) :: energy
      logical, intent(out) :: ok

      complex(dp) :: s_val, log_det_j
      logical :: det_error

      call calculate_action(z, s_val)
      call log_determinant(jac, log_det_j, det_error)
      if (det_error) then
         energy = 0.0_dp
         ok = .false.
         return
      end if

      energy = real(s_val, dp) - real(log_det_j, dp)
      ok = .true.
   end subroutine compute_effective_energy

   subroutine free_swap_buffers(x_ap, x_bp, z_ap, z_bp, j_ap, j_bp)
      real(dp), allocatable, intent(inout) :: x_ap(:), x_bp(:)
      complex(dp), allocatable, intent(inout) :: z_ap(:), z_bp(:), j_ap(:, :), j_bp(:, :)

      if (allocated(x_ap)) deallocate (x_ap)
      if (allocated(x_bp)) deallocate (x_bp)
      if (allocated(z_ap)) deallocate (z_ap)
      if (allocated(z_bp)) deallocate (z_bp)
      if (allocated(j_ap)) deallocate (j_ap)
      if (allocated(j_bp)) deallocate (j_bp)
   end subroutine free_swap_buffers

   integer function find_max_flow_slot_index(slots) result(idx_max)
      type(tltm_slot_t), intent(in) :: slots(:)
      integer :: i
      real(dp) :: best_flow

      idx_max = 1
      if (size(slots) <= 0) return
      best_flow = slots(1)%flow_time
      do i = 2, size(slots)
         if (slots(i)%flow_time > best_flow) then
            best_flow = slots(i)%flow_time
            idx_max = i
         end if
      end do
   end function find_max_flow_slot_index

   subroutine initialize_pair_stats(pair_stats)
      type(tltm_pair_stats_t), intent(inout) :: pair_stats(:)
      integer :: i

      do i = 1, size(pair_stats)
         pair_stats(i)%pair_id = i - 1
         pair_stats(i)%slot_a = i - 1
         pair_stats(i)%slot_b = i
      end do
   end subroutine initialize_pair_stats

   subroutine initialize_label_tracks(label_tracks, n_slots)
      type(tltm_label_track_t), intent(inout) :: label_tracks(:)
      integer, intent(in) :: n_slots
      integer :: i, hot_slot

      hot_slot = n_slots - 1
      do i = 1, size(label_tracks)
         label_tracks(i)%label_id = i - 1
         label_tracks(i)%current_slot = i - 1
         label_tracks(i)%farthest_slot_reached = i - 1
         label_tracks(i)%last_extreme_visited = -1
         label_tracks(i)%round_trip_count = 0
         label_tracks(i)%last_round_trip_start_cycle = -1
         label_tracks(i)%round_trip_time_sum = 0.0_dp
         label_tracks(i)%hot_reached_after_cold = .false.
         if (label_tracks(i)%current_slot == 0) then
            label_tracks(i)%last_extreme_visited = 0
            label_tracks(i)%last_round_trip_start_cycle = 0
         else if (label_tracks(i)%current_slot == hot_slot) then
            label_tracks(i)%last_extreme_visited = 1
         end if
      end do
   end subroutine initialize_label_tracks

   subroutine refresh_label_positions(slots, label_tracks)
      type(tltm_slot_t), intent(in) :: slots(:)
      type(tltm_label_track_t), intent(inout) :: label_tracks(:)
      integer :: i, lid

      do i = 1, size(slots)
         lid = slots(i)%label_id + 1
         if (lid >= 1 .and. lid <= size(label_tracks)) then
            label_tracks(lid)%current_slot = slots(i)%slot_id
            if (label_tracks(lid)%current_slot > label_tracks(lid)%farthest_slot_reached) then
               label_tracks(lid)%farthest_slot_reached = label_tracks(lid)%current_slot
            end if
         end if
      end do
   end subroutine refresh_label_positions

   subroutine update_round_trip_bookkeeping(label_tracks, cycle_idx, hot_slot)
      type(tltm_label_track_t), intent(inout) :: label_tracks(:)
      integer, intent(in) :: cycle_idx, hot_slot
      integer :: i, slot_id

      do i = 1, size(label_tracks)
         slot_id = label_tracks(i)%current_slot
         if (slot_id == 0) then
            if (label_tracks(i)%hot_reached_after_cold .and. label_tracks(i)%last_round_trip_start_cycle >= 0) then
               label_tracks(i)%round_trip_count = label_tracks(i)%round_trip_count + 1
               label_tracks(i)%round_trip_time_sum = label_tracks(i)%round_trip_time_sum + &
                  real(cycle_idx - label_tracks(i)%last_round_trip_start_cycle, dp)
               label_tracks(i)%hot_reached_after_cold = .false.
            end if
            label_tracks(i)%last_extreme_visited = 0
            label_tracks(i)%last_round_trip_start_cycle = cycle_idx
         else if (slot_id == hot_slot) then
            if (label_tracks(i)%last_extreme_visited == 0) then
               label_tracks(i)%hot_reached_after_cold = .true.
            end if
            label_tracks(i)%last_extreme_visited = 1
         end if
      end do
   end subroutine update_round_trip_bookkeeping

   subroutine write_label_trace(unit_trace, cycle_idx, label_tracks)
      integer, intent(in) :: unit_trace, cycle_idx
      type(tltm_label_track_t), intent(in) :: label_tracks(:)
      integer :: i

      do i = 1, size(label_tracks)
         write (unit_trace, '(I8,1X,I8,1X,I8,1X,I8)') cycle_idx, label_tracks(i)%label_id, &
            label_tracks(i)%current_slot, label_tracks(i)%round_trip_count
      end do
   end subroutine write_label_trace

   subroutine write_reverse_gate_route_counts(unit_summary, line_prefix, counts)
      integer, intent(in) :: unit_summary
      character(len=*), intent(in) :: line_prefix
      integer(int64), intent(in) :: counts(:)

      write (unit_summary, '(A,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         trim(line_prefix), " total=", reverse_gate_count_at(counts, constraint_reverse_gate_path_total), &
         " probe_only=", reverse_gate_count_at(counts, constraint_reverse_gate_path_probe_only), &
         " full_stage=", reverse_gate_count_at(counts, constraint_reverse_gate_path_full_stage), &
         " near_rescue=", reverse_gate_count_at(counts, constraint_reverse_gate_path_near_rescue), &
         " nonnear_route=", reverse_gate_count_at(counts, constraint_reverse_gate_path_nonnear_route), &
         " class_local=", reverse_gate_count_at(counts, constraint_reverse_gate_path_class_local), &
         " class_mid=", reverse_gate_count_at(counts, constraint_reverse_gate_path_class_mid), &
         " class_global=", reverse_gate_count_at(counts, constraint_reverse_gate_path_class_global), &
         " far_skip=", reverse_gate_count_at(counts, constraint_reverse_gate_path_far_skip), &
         " far_light=", reverse_gate_count_at(counts, constraint_reverse_gate_path_far_light), &
         " far_anchor=", reverse_gate_count_at(counts, constraint_reverse_gate_path_far_anchor)
   end subroutine write_reverse_gate_route_counts

   integer(int64) function reverse_gate_count_at(counts, idx) result(count_value)
      integer(int64), intent(in) :: counts(:)
      integer, intent(in) :: idx

      if (idx >= 1 .and. idx <= size(counts)) then
         count_value = counts(idx)
      else
         count_value = 0_int64
      end if
   end function reverse_gate_count_at

   subroutine write_stage2_summary(summary_file, slots, pair_stats, label_tracks, local_accept_census, cycle_count, local_updates, elapsed, swap_enabled, &
                                   calls_total, calls_integrating, fallback_attempts, fallback_success, fallback_failure, &
                                   fallback_max_steps, fallback_invalid, fallback_h_min, &
                                   solver_total_count, solver_newton_count, solver_quasi_count, solver_failed_count, &
                                   solver_newton_ratio, solver_quasi_ratio, solver_fail_ratio, &
                                   quasi_probe_attempt_count, quasi_probe_success_count, quasi_full_attempt_count, quasi_full_success_count, &
                                   quasi_class_local_count, quasi_class_mid_count, quasi_class_global_count, &
                                   far_route_skip_count, far_route_light_count, far_route_anchor_count, &
                                   near_candidate_count, near_attempt_count, near_success_count, near_unusable_count, &
                                   quasi_watchdog_hit_count, quasi_watchdog_used_sum, quasi_watchdog_used_max, quasi_watchdog_budget_last, &
                                   far_scope_count, far_success_count, far_fail_count, far_fail_fast_count, &
                                   far_spent_success_count, far_spent_fail_count, &
                                   far_flowzr_used_sum, far_final_resort_used_sum, &
                                   far_flowzr_used_success_sum, far_final_resort_used_success_sum, &
                                   far_flowzr_used_fail_sum, far_final_resort_used_fail_sum, &
                                   global_filter_candidate_count, global_filter_pass_count, global_filter_reject_count, &
                                   reverse_gate_candidate_counts, reverse_gate_pass_counts, reverse_gate_reject_counts)
      character(len=*), intent(in) :: summary_file
      type(tltm_slot_t), intent(in) :: slots(:)
      type(tltm_pair_stats_t), intent(in) :: pair_stats(:)
      type(tltm_label_track_t), intent(in) :: label_tracks(:)
      type(local_accept_census_t), intent(in) :: local_accept_census(:)
      integer, intent(in) :: cycle_count, local_updates
      real(dp), intent(in) :: elapsed
      logical, intent(in) :: swap_enabled
      integer, intent(in) :: calls_total, calls_integrating
      integer, intent(in) :: fallback_attempts, fallback_success, fallback_failure
      integer, intent(in) :: fallback_max_steps, fallback_invalid, fallback_h_min
      integer(int64), intent(in) :: solver_total_count, solver_newton_count, solver_quasi_count, solver_failed_count
      real(dp), intent(in) :: solver_newton_ratio, solver_quasi_ratio, solver_fail_ratio
      integer(int64), intent(in) :: quasi_probe_attempt_count, quasi_probe_success_count
      integer(int64), intent(in) :: quasi_full_attempt_count, quasi_full_success_count
      integer(int64), intent(in) :: quasi_class_local_count, quasi_class_mid_count, quasi_class_global_count
      integer(int64), intent(in) :: far_route_skip_count, far_route_light_count, far_route_anchor_count
      integer(int64), intent(in) :: near_candidate_count, near_attempt_count, near_success_count, near_unusable_count
      integer(int64), intent(in) :: quasi_watchdog_hit_count, quasi_watchdog_used_sum
      integer, intent(in) :: quasi_watchdog_used_max, quasi_watchdog_budget_last
      integer(int64), intent(in) :: far_scope_count, far_success_count, far_fail_count, far_fail_fast_count
      integer(int64), intent(in) :: far_spent_success_count, far_spent_fail_count
      integer(int64), intent(in) :: far_flowzr_used_sum, far_final_resort_used_sum
      integer(int64), intent(in) :: far_flowzr_used_success_sum, far_final_resort_used_success_sum
      integer(int64), intent(in) :: far_flowzr_used_fail_sum, far_final_resort_used_fail_sum
      integer(int64), intent(in) :: global_filter_candidate_count, global_filter_pass_count, global_filter_reject_count
      integer(int64), intent(in) :: reverse_gate_candidate_counts(:)
      integer(int64), intent(in) :: reverse_gate_pass_counts(:)
      integer(int64), intent(in) :: reverse_gate_reject_counts(:)

      integer, parameter :: unit_summary = 79
      integer :: ios, i, total_count
      integer :: metropolis_reject_total, reverse_gate_reject_total, proposal_failure_total
      integer :: hamiltonian_invalid_total, delta_h_invalid_total, output_size_mismatch_total
      real(dp) :: accept_rate, abs_mean_phi, pair_accept_rate, avg_round_trip
      integer :: total_round_trip
      type(local_accept_census_t) :: total_accept_census
      integer(int64) :: newton_flow_success_count, newton_flow_zero_time_count, newton_flow_stiff_rescue_count
      integer(int64) :: newton_flow_solver_assist_count, newton_flow_failure_max_steps_count, newton_flow_failure_invalid_count
      integer(int64) :: newton_flow_failure_h_min_count, newton_flow_unknown_count
      integer(int64) :: rg_replay_success_count, rg_replay_output_size_mismatch_count, rg_replay_momentum_size_mismatch_count
      integer(int64) :: rg_replay_initial_force_failed_count, rg_replay_constraint_failed_count, rg_replay_final_flow_failed_count
      integer(int64) :: rg_replay_final_force_failed_count, rg_replay_final_projection_failed_count, rg_replay_reverse_gate_rejected_count
      integer(int64) :: rg_replay_final_flow_max_steps_count, rg_replay_final_flow_invalid_count, rg_replay_final_flow_h_min_count
      integer(int64) :: rg_replay_final_flow_non_strict_success_count, rg_replay_unknown_count
      integer(int64) :: qn_flow_success_count, qn_flow_zero_time_count, qn_flow_stiff_rescue_count
      integer(int64) :: qn_flow_solver_assist_count, qn_flow_failure_max_steps_count, qn_flow_failure_invalid_count
      integer(int64) :: qn_flow_failure_h_min_count, qn_flow_unknown_count

      open (unit=unit_summary, file=trim(summary_file), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open summary file:", trim(summary_file)
         error stop 1
      end if

      write (unit_summary, '(A)') "# TLTM stage-2 summary"
      write (unit_summary, '(A,I0)') "# slots=", size(slots)
      write (unit_summary, '(A,I0)') "# cycles=", cycle_count
      write (unit_summary, '(A,I0)') "# local_updates=", local_updates
      write (unit_summary, '(A,L1)') "# swap_enabled=", swap_enabled
      write (unit_summary, '(A,F12.6)') "# elapsed_sec=", elapsed
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# fallback_stats calls_total=", calls_total, " calls_integrating=", calls_integrating, &
         " attempts=", fallback_attempts, " success=", fallback_success, " failure=", fallback_failure, &
         " max_steps=", fallback_max_steps, " invalid=", fallback_invalid, " h_min=", fallback_h_min
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,F9.5,A,F9.5,A,F9.5)') &
         "# constraint_stats total=", solver_total_count, " newton=", solver_newton_count, " quasi=", solver_quasi_count, &
         " failed=", solver_failed_count, " ratio_newton=", solver_newton_ratio, " ratio_quasi=", solver_quasi_ratio, &
         " ratio_failed=", solver_fail_ratio
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0)') &
         "# quasi_stage_stats probe_attempt=", quasi_probe_attempt_count, " probe_success=", quasi_probe_success_count, &
         " full_attempt=", quasi_full_attempt_count, " full_success=", quasi_full_success_count
      write (unit_summary, '(A,I0,A,I0,A,I0)') &
         "# quasi_class_stats local=", quasi_class_local_count, " mid=", quasi_class_mid_count, &
         " global=", quasi_class_global_count
      write (unit_summary, '(A,I0,A,I0,A,I0)') &
         "# far_route_stats skip=", far_route_skip_count, " light=", far_route_light_count, &
         " anchor=", far_route_anchor_count
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0)') &
         "# near_rescue_stats candidate=", near_candidate_count, " attempt=", near_attempt_count, &
         " success=", near_success_count, " unusable=", near_unusable_count
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0)') &
         "# quasi_watchdog_stats hit=", quasi_watchdog_hit_count, " used_sum=", quasi_watchdog_used_sum, &
         " used_max=", quasi_watchdog_used_max, " budget_last=", quasi_watchdog_budget_last
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# far_investment_stats scope=", far_scope_count, " success=", far_success_count, &
         " fail=", far_fail_count, " fail_fast=", far_fail_fast_count, &
         " spent_success=", far_spent_success_count, " spent_fail=", far_spent_fail_count
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# far_investment_units flowzr=", far_flowzr_used_sum, " final=", far_final_resort_used_sum, &
         " success_flowzr=", far_flowzr_used_success_sum, " success_final=", far_final_resort_used_success_sum, &
         " fail_flowzr=", far_flowzr_used_fail_sum, " fail_final=", far_final_resort_used_fail_sum
      write (unit_summary, '(A,I0,A,I0,A,I0)') &
         "# quasi_global_filter_stats candidate=", global_filter_candidate_count, " pass=", global_filter_pass_count, &
         " reject=", global_filter_reject_count
      call get_newton_eval_flow_status_counts(newton_flow_success_count, newton_flow_zero_time_count, newton_flow_stiff_rescue_count, &
                                              newton_flow_solver_assist_count, newton_flow_failure_max_steps_count, &
                                              newton_flow_failure_invalid_count, newton_flow_failure_h_min_count, newton_flow_unknown_count)
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# newton_eval_flow_status success=", newton_flow_success_count, " zero_time=", newton_flow_zero_time_count, &
         " stiff_rescue=", newton_flow_stiff_rescue_count, " solver_assist=", newton_flow_solver_assist_count, &
         " failure_max_steps=", newton_flow_failure_max_steps_count, " failure_invalid=", newton_flow_failure_invalid_count, &
         " failure_h_min=", newton_flow_failure_h_min_count, " unknown=", newton_flow_unknown_count
      call get_reverse_gate_replay_status_counts(rg_replay_success_count, rg_replay_output_size_mismatch_count, &
                                                 rg_replay_momentum_size_mismatch_count, rg_replay_initial_force_failed_count, &
                                                 rg_replay_constraint_failed_count, rg_replay_final_flow_failed_count, &
                                                 rg_replay_final_force_failed_count, rg_replay_final_projection_failed_count, &
                                                 rg_replay_reverse_gate_rejected_count, rg_replay_final_flow_max_steps_count, &
                                                 rg_replay_final_flow_invalid_count, rg_replay_final_flow_h_min_count, &
                                                 rg_replay_final_flow_non_strict_success_count, rg_replay_unknown_count)
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# reverse_gate_replay_status success=", rg_replay_success_count, &
         " output_size_mismatch=", rg_replay_output_size_mismatch_count, &
         " momentum_size_mismatch=", rg_replay_momentum_size_mismatch_count, &
         " initial_force_failed=", rg_replay_initial_force_failed_count, " constraint_failed=", rg_replay_constraint_failed_count, &
         " final_flow_failed=", rg_replay_final_flow_failed_count, " final_force_failed=", rg_replay_final_force_failed_count, &
         " final_projection_failed=", rg_replay_final_projection_failed_count, &
         " reverse_gate_rejected=", rg_replay_reverse_gate_rejected_count, &
         " final_flow_max_steps=", rg_replay_final_flow_max_steps_count, " final_flow_invalid=", rg_replay_final_flow_invalid_count, &
         " final_flow_h_min=", rg_replay_final_flow_h_min_count, &
         " final_flow_non_strict_success=", rg_replay_final_flow_non_strict_success_count, " unknown=", rg_replay_unknown_count
      call get_quasi_eval_flow_status_counts(qn_flow_success_count, qn_flow_zero_time_count, qn_flow_stiff_rescue_count, &
                                             qn_flow_solver_assist_count, qn_flow_failure_max_steps_count, &
                                             qn_flow_failure_invalid_count, qn_flow_failure_h_min_count, qn_flow_unknown_count)
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# qn_eval_flow_status success=", qn_flow_success_count, " zero_time=", qn_flow_zero_time_count, &
         " stiff_rescue=", qn_flow_stiff_rescue_count, " solver_assist=", qn_flow_solver_assist_count, &
         " failure_max_steps=", qn_flow_failure_max_steps_count, " failure_invalid=", qn_flow_failure_invalid_count, &
         " failure_h_min=", qn_flow_failure_h_min_count, " unknown=", qn_flow_unknown_count
      call write_reverse_gate_route_counts(unit_summary, "# reverse_gate_route_candidates", reverse_gate_candidate_counts)
      call write_reverse_gate_route_counts(unit_summary, "# reverse_gate_route_pass", reverse_gate_pass_counts)
      call write_reverse_gate_route_counts(unit_summary, "# reverse_gate_route_reject", reverse_gate_reject_counts)
      metropolis_reject_total = 0
      reverse_gate_reject_total = 0
      proposal_failure_total = 0
      hamiltonian_invalid_total = 0
      delta_h_invalid_total = 0
      output_size_mismatch_total = 0
      do i = 1, size(slots)
         metropolis_reject_total = metropolis_reject_total + slots(i)%metropolis_reject_count
         reverse_gate_reject_total = reverse_gate_reject_total + slots(i)%reverse_gate_reject_count
         proposal_failure_total = proposal_failure_total + slots(i)%proposal_failure_count
         hamiltonian_invalid_total = hamiltonian_invalid_total + slots(i)%hamiltonian_invalid_count
         delta_h_invalid_total = delta_h_invalid_total + slots(i)%delta_h_invalid_count
         output_size_mismatch_total = output_size_mismatch_total + slots(i)%output_size_mismatch_count
      end do
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# local_transition_totals metropolis_reject=", metropolis_reject_total, &
         " reverse_gate_reject=", reverse_gate_reject_total, " proposal_failure=", proposal_failure_total, &
         " hamiltonian_invalid=", hamiltonian_invalid_total, " delta_h_invalid=", delta_h_invalid_total, &
         " output_size_mismatch=", output_size_mismatch_total
      do i = 1, size(local_accept_census)
         total_accept_census%accepted_total = total_accept_census%accepted_total + local_accept_census(i)%accepted_total
         total_accept_census%accepted_newton_only = total_accept_census%accepted_newton_only + local_accept_census(i)%accepted_newton_only
         total_accept_census%accepted_quasi = total_accept_census%accepted_quasi + local_accept_census(i)%accepted_quasi
         total_accept_census%accepted_rescue = total_accept_census%accepted_rescue + local_accept_census(i)%accepted_rescue
         total_accept_census%accepted_probe_only = total_accept_census%accepted_probe_only + local_accept_census(i)%accepted_probe_only
         total_accept_census%accepted_full_stage = total_accept_census%accepted_full_stage + local_accept_census(i)%accepted_full_stage
         total_accept_census%accepted_near_rescue = total_accept_census%accepted_near_rescue + local_accept_census(i)%accepted_near_rescue
         total_accept_census%accepted_nonnear_route = total_accept_census%accepted_nonnear_route + local_accept_census(i)%accepted_nonnear_route
         total_accept_census%accepted_class_local = total_accept_census%accepted_class_local + local_accept_census(i)%accepted_class_local
         total_accept_census%accepted_class_mid = total_accept_census%accepted_class_mid + local_accept_census(i)%accepted_class_mid
         total_accept_census%accepted_class_global = total_accept_census%accepted_class_global + local_accept_census(i)%accepted_class_global
         total_accept_census%accepted_far_skip = total_accept_census%accepted_far_skip + local_accept_census(i)%accepted_far_skip
         total_accept_census%accepted_far_light = total_accept_census%accepted_far_light + local_accept_census(i)%accepted_far_light
         total_accept_census%accepted_far_anchor = total_accept_census%accepted_far_anchor + local_accept_census(i)%accepted_far_anchor
         total_accept_census%accepted_uncategorized = total_accept_census%accepted_uncategorized + local_accept_census(i)%accepted_uncategorized
      end do
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# accepted_local_census_totals accepted_total=", total_accept_census%accepted_total, &
         " newton_only=", total_accept_census%accepted_newton_only, " quasi=", total_accept_census%accepted_quasi, &
         " rescue=", total_accept_census%accepted_rescue, " probe_only=", total_accept_census%accepted_probe_only, &
         " full_stage=", total_accept_census%accepted_full_stage, " near_rescue=", total_accept_census%accepted_near_rescue, &
         " nonnear_route=", total_accept_census%accepted_nonnear_route, " uncategorized=", total_accept_census%accepted_uncategorized
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# accepted_local_route_totals class_local=", total_accept_census%accepted_class_local, &
         " class_mid=", total_accept_census%accepted_class_mid, " class_global=", total_accept_census%accepted_class_global, &
         " far_skip=", total_accept_census%accepted_far_skip, " far_light=", total_accept_census%accepted_far_light, &
         " far_anchor=", total_accept_census%accepted_far_anchor
      write (unit_summary, '(A)') &
         "# [accepted_local_census] slot_id accepted_total newton_only quasi rescue probe_only full_stage near_rescue nonnear_route " // &
         "class_local class_mid class_global far_skip far_light far_anchor uncategorized"
      do i = 1, size(local_accept_census)
         write (unit_summary, '(I4,15(1X,I12))') i - 1, local_accept_census(i)%accepted_total, &
            local_accept_census(i)%accepted_newton_only, local_accept_census(i)%accepted_quasi, &
            local_accept_census(i)%accepted_rescue, local_accept_census(i)%accepted_probe_only, &
            local_accept_census(i)%accepted_full_stage, local_accept_census(i)%accepted_near_rescue, &
            local_accept_census(i)%accepted_nonnear_route, local_accept_census(i)%accepted_class_local, &
            local_accept_census(i)%accepted_class_mid, local_accept_census(i)%accepted_class_global, &
            local_accept_census(i)%accepted_far_skip, local_accept_census(i)%accepted_far_light, &
            local_accept_census(i)%accepted_far_anchor, local_accept_census(i)%accepted_uncategorized
      end do
      write (unit_summary, '(A)') &
         "# [slots] slot_id label_id flow_time accepts rejects accept_rate projection_fail samples abs_mean_phi runtime_sec " // &
         "metropolis_reject reverse_gate_reject proposal_failure hamiltonian_invalid delta_h_invalid output_size_mismatch"
      do i = 1, size(slots)
         total_count = slots(i)%local_accept_count + slots(i)%local_reject_count
         if (total_count > 0) then
            accept_rate = real(slots(i)%local_accept_count, dp)/real(total_count, dp)
         else
            accept_rate = 0.0_dp
         end if
         if (slots(i)%observable_samples > 0) then
            abs_mean_phi = abs(slots(i)%phi_sum/real(slots(i)%observable_samples, dp))
         else
            abs_mean_phi = 0.0_dp
         end if
         write (unit_summary, '(I4,1X,I4,1X,F10.6,1X,I8,1X,I8,1X,F9.5,1X,I8,1X,I8,1X,ES16.8,1X,F12.6,6(1X,I8))') &
            slots(i)%slot_id, slots(i)%label_id, slots(i)%flow_time, &
            slots(i)%local_accept_count, slots(i)%local_reject_count, accept_rate, &
            slots(i)%projection_failure_count, slots(i)%observable_samples, abs_mean_phi, slots(i)%local_runtime, &
            slots(i)%metropolis_reject_count, slots(i)%reverse_gate_reject_count, slots(i)%proposal_failure_count, &
            slots(i)%hamiltonian_invalid_count, slots(i)%delta_h_invalid_count, slots(i)%output_size_mismatch_count
      end do

      write (unit_summary, '(A)') "# [pairs] pair_id slot_a slot_b proposals accepts rejects accept_rate last_accept_prob"
      do i = 1, size(pair_stats)
         if (pair_stats(i)%proposal_count > 0) then
            pair_accept_rate = real(pair_stats(i)%accept_count, dp)/real(pair_stats(i)%proposal_count, dp)
         else
            pair_accept_rate = 0.0_dp
         end if
         write (unit_summary, '(I4,1X,I4,1X,I4,1X,I8,1X,I8,1X,I8,1X,F9.5,1X,ES23.15E3)') &
            pair_stats(i)%pair_id, pair_stats(i)%slot_a, pair_stats(i)%slot_b, &
            pair_stats(i)%proposal_count, pair_stats(i)%accept_count, pair_stats(i)%reject_count, &
            pair_accept_rate, pair_stats(i)%last_accept_probability
      end do

      total_round_trip = 0
      do i = 1, size(label_tracks)
         total_round_trip = total_round_trip + label_tracks(i)%round_trip_count
      end do
      write (unit_summary, '(A,I0)') "# total_round_trip=", total_round_trip
      write (unit_summary, '(A)') "# [labels] label_id current_slot farthest_slot_reached round_trip_count avg_round_trip_cycles last_extreme"
      do i = 1, size(label_tracks)
         if (label_tracks(i)%round_trip_count > 0) then
            avg_round_trip = label_tracks(i)%round_trip_time_sum/real(label_tracks(i)%round_trip_count, dp)
         else
            avg_round_trip = 0.0_dp
         end if
         write (unit_summary, '(I4,1X,I4,1X,I4,1X,I8,1X,F12.6,1X,I4)') &
            label_tracks(i)%label_id, label_tracks(i)%current_slot, label_tracks(i)%farthest_slot_reached, &
            label_tracks(i)%round_trip_count, &
            avg_round_trip, label_tracks(i)%last_extreme_visited
      end do

      close (unit_summary)
   end subroutine write_stage2_summary

   subroutine resolve_base_seed(base_seed)
      integer, intent(out) :: base_seed
      character(len=64) :: seed_env
      integer :: env_len, env_status, ios

      seed_env = ""
      call get_environment_variable("CHAIN_RNG_SEED", seed_env, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         read (seed_env(1:env_len), *, iostat=ios) base_seed
         if (ios /= 0 .or. base_seed <= 0) base_seed = getseed()
      else
         base_seed = getseed()
      end if
      write (*, '(A,I0)') "[TLTM-S2] CHAIN_RNG_SEED=", base_seed
   end subroutine resolve_base_seed

   subroutine resolve_stage2_controls(default_max_flow, config_chain_length, config_hmc_repeat, n_slots, flow_ladder, &
                                      max_flow_time, cycle_count, local_updates, init_sigma, init_mode, swap_enabled)
      real(dp), intent(in) :: default_max_flow
      integer, intent(in) :: config_chain_length, config_hmc_repeat
      integer, intent(out) :: n_slots, cycle_count, local_updates
      real(dp), allocatable, intent(out) :: flow_ladder(:)
      real(dp), intent(out) :: max_flow_time, init_sigma
      character(len=*), intent(out) :: init_mode
      logical, intent(out) :: swap_enabled

      character(len=1024) :: ladder_text
      character(len=64) :: env_value
      integer :: env_len, env_status
      logical :: ok
      real(dp), allocatable :: parsed(:)

      n_slots = 4
      call parse_int_env("TLTM_STAGE2_NUM_REPLICAS", n_slots)
      if (n_slots < 1) then
         write (*, '(A)') "[ERROR][TLTM-S2] TLTM_STAGE2_NUM_REPLICAS must be >= 1."
         error stop 1
      end if

      max_flow_time = max(0.0_dp, default_max_flow)
      call parse_real_env("TLTM_STAGE2_MAX_FLOW_TIME", max_flow_time)
      if (max_flow_time < 0.0_dp) then
         write (*, '(A)') "[ERROR][TLTM-S2] TLTM_STAGE2_MAX_FLOW_TIME must be >= 0."
         error stop 1
      end if

      ladder_text = ""
      call get_environment_variable("TLTM_STAGE2_FLOW_TIME_LADDER", ladder_text, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         call parse_real_list(ladder_text(1:env_len), parsed, ok)
         if (.not. ok .or. .not. allocated(parsed)) then
            write (*, '(A)') "[ERROR][TLTM-S2] Failed to parse TLTM_STAGE2_FLOW_TIME_LADDER."
            error stop 1
         end if
         n_slots = size(parsed)
         allocate (flow_ladder(n_slots))
         flow_ladder = parsed
         max_flow_time = maxval(flow_ladder)
         if (allocated(parsed)) deallocate (parsed)
      else
         call build_linear_ladder(n_slots, max_flow_time, flow_ladder)
      end if

      cycle_count = max(1, min(max(1, config_chain_length), stage2_cycle_cap_default))
      call parse_int_env("TLTM_STAGE2_CYCLES", cycle_count)
      if (cycle_count < 1) then
         write (*, '(A)') "[ERROR][TLTM-S2] TLTM_STAGE2_CYCLES must be >= 1."
         error stop 1
      end if

      local_updates = max(1, config_hmc_repeat)
      call parse_int_env("TLTM_STAGE2_LOCAL_UPDATES", local_updates)
      if (local_updates < 1) then
         write (*, '(A)') "[ERROR][TLTM-S2] TLTM_STAGE2_LOCAL_UPDATES must be >= 1."
         error stop 1
      end if

      init_sigma = stage2_init_sigma_default
      call parse_real_env("TLTM_STAGE2_INIT_SIGMA", init_sigma)
      if (init_sigma <= 0.0_dp) then
         write (*, '(A)') "[ERROR][TLTM-S2] TLTM_STAGE2_INIT_SIGMA must be > 0."
         error stop 1
      end if

      init_mode = "adaptive"
      env_value = ""
      call get_environment_variable("TLTM_STAGE2_INIT_MODE", env_value, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         init_mode = trim(to_lower_ascii(adjustl(env_value(1:env_len))))
      end if
      select case (trim(init_mode))
      case ("adaptive", "preflow")
         init_mode = "adaptive"
      case ("direct", "legacy")
         init_mode = "direct"
      case default
         write (*, '(A,A,A)') "[ERROR][TLTM-S2] Unsupported TLTM_STAGE2_INIT_MODE='", trim(init_mode), "'."
         write (*, '(A)') "[ERROR][TLTM-S2] Use adaptive/preflow or direct/legacy."
         error stop 1
      end select

      swap_enabled = .true.
      call parse_logical_env("TLTM_STAGE2_SWAP_ENABLED", swap_enabled)
   end subroutine resolve_stage2_controls

   subroutine resolve_stage2_output_paths(summary_file, label_trace_file)
      character(len=*), intent(out) :: summary_file, label_trace_file
      integer :: env_len, env_status

      summary_file = "../output/tests/tltm_stage2_summary.dat"
      call get_environment_variable("TLTM_STAGE2_SUMMARY_FILE", summary_file, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         summary_file = trim(summary_file(1:env_len))
      else
         summary_file = "../output/tests/tltm_stage2_summary.dat"
      end if

      label_trace_file = "../output/tests/tltm_stage2_label_trace.dat"
      call get_environment_variable("TLTM_STAGE2_LABEL_TRACE_FILE", label_trace_file, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         label_trace_file = trim(label_trace_file(1:env_len))
      else
         label_trace_file = "../output/tests/tltm_stage2_label_trace.dat"
      end if
   end subroutine resolve_stage2_output_paths

   subroutine resolve_stage2_cold_history_paths(cold_z_history_file, cold_phi_history_file, write_cold_history)
      character(len=*), intent(out) :: cold_z_history_file, cold_phi_history_file
      logical, intent(out) :: write_cold_history
      integer :: env_len, env_status
      logical :: has_z_path, has_phi_path

      cold_z_history_file = ""
      cold_phi_history_file = ""

      call get_environment_variable("TLTM_STAGE2_COLD_Z_HISTORY_FILE", cold_z_history_file, length=env_len, status=env_status)
      has_z_path = (env_status == 0 .and. env_len > 0)
      if (has_z_path) cold_z_history_file = trim(cold_z_history_file(1:env_len))

      call get_environment_variable("TLTM_STAGE2_COLD_PHI_HISTORY_FILE", cold_phi_history_file, length=env_len, status=env_status)
      has_phi_path = (env_status == 0 .and. env_len > 0)
      if (has_phi_path) cold_phi_history_file = trim(cold_phi_history_file(1:env_len))

      if (has_z_path .neqv. has_phi_path) then
         write (*, '(A)') "[ERROR][TLTM-S2] Both TLTM_STAGE2_COLD_Z_HISTORY_FILE and TLTM_STAGE2_COLD_PHI_HISTORY_FILE are required."
         error stop 1
      end if
      write_cold_history = has_z_path .and. has_phi_path
   end subroutine resolve_stage2_cold_history_paths

   subroutine resolve_stage2_all_history_dir(all_history_dir, write_all_history)
      character(len=*), intent(out) :: all_history_dir
      logical, intent(out) :: write_all_history
      integer :: env_len, env_status

      all_history_dir = ""
      call get_environment_variable("TLTM_STAGE2_ALL_REPLICA_HISTORY_DIR", all_history_dir, length=env_len, status=env_status)
      write_all_history = (env_status == 0 .and. env_len > 0)
      if (write_all_history) all_history_dir = trim(all_history_dir(1:env_len))
   end subroutine resolve_stage2_all_history_dir

   subroutine open_all_replica_history_files(slots, all_history_dir, z_units, phi_units, ok)
      type(tltm_slot_t), intent(in) :: slots(:)
      character(len=*), intent(in) :: all_history_dir
      integer, allocatable, intent(out) :: z_units(:), phi_units(:)
      logical, intent(out) :: ok

      character(len=512) :: z_file, phi_file
      integer :: i, ios
      logical :: path_ok

      ok = .false.
      if (allocated(z_units)) deallocate (z_units)
      if (allocated(phi_units)) deallocate (phi_units)
      allocate (z_units(size(slots)), phi_units(size(slots)))
      z_units = 0
      phi_units = 0

      do i = 1, size(slots)
         call replica_history_paths(all_history_dir, slots(i)%slot_id, z_file, phi_file)
         call ensure_parent_directory_exists(z_file, path_ok)
         if (.not. path_ok) then
            write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot prepare all-replica z-history path:", trim(z_file)
            call close_all_replica_history_files(z_units, phi_units)
            return
         end if
         call ensure_parent_directory_exists(phi_file, path_ok)
         if (.not. path_ok) then
            write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot prepare all-replica phi-history path:", trim(phi_file)
            call close_all_replica_history_files(z_units, phi_units)
            return
         end if

         open (newunit=z_units(i), file=trim(z_file), status='replace', access='stream', &
               form='unformatted', action='write', iostat=ios)
         if (ios /= 0) then
            write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open all-replica z-history file:", trim(z_file)
            call close_all_replica_history_files(z_units, phi_units)
            return
         end if
         open (newunit=phi_units(i), file=trim(phi_file), status='replace', access='stream', &
               form='unformatted', action='write', iostat=ios)
         if (ios /= 0) then
            write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open all-replica phi-history file:", trim(phi_file)
            call close_all_replica_history_files(z_units, phi_units)
            return
         end if
      end do
      ok = .true.
   end subroutine open_all_replica_history_files

   subroutine replica_history_paths(all_history_dir, slot_id, z_file, phi_file)
      character(len=*), intent(in) :: all_history_dir
      integer, intent(in) :: slot_id
      character(len=*), intent(out) :: z_file, phi_file
      character(len=32) :: replica_dir

      write (replica_dir, '("replica_",I3.3)') slot_id
      z_file = trim(all_history_dir)//"/"//trim(replica_dir)//"/output/z_history.dat"
      phi_file = trim(all_history_dir)//"/"//trim(replica_dir)//"/output/phi_history.dat"
   end subroutine replica_history_paths

   subroutine write_all_replica_history_samples(slots, z_units, phi_units, ok)
      type(tltm_slot_t), intent(in) :: slots(:)
      integer, intent(in) :: z_units(:), phi_units(:)
      logical, intent(out) :: ok
      integer :: i

      ok = .true.
      if (size(z_units) /= size(slots) .or. size(phi_units) /= size(slots)) then
         write (*, '(A)') "[ERROR][TLTM-S2] All-replica history unit count does not match slot count."
         ok = .false.
         return
      end if
      do i = 1, size(slots)
         call write_history_sample(slots(i), z_units(i), phi_units(i), "all-replica", ok)
         if (.not. ok) return
      end do
   end subroutine write_all_replica_history_samples

   subroutine close_all_replica_history_files(z_units, phi_units)
      integer, allocatable, intent(inout) :: z_units(:), phi_units(:)
      integer :: i

      if (allocated(z_units)) then
         do i = 1, size(z_units)
            if (z_units(i) /= 0) close (unit=z_units(i))
         end do
         deallocate (z_units)
      end if
      if (allocated(phi_units)) then
         do i = 1, size(phi_units)
            if (phi_units(i) /= 0) close (unit=phi_units(i))
         end do
         deallocate (phi_units)
      end if
   end subroutine close_all_replica_history_files

   subroutine write_cold_history_sample(slot, unit_z, unit_phi, ok)
      type(tltm_slot_t), intent(in) :: slot
      integer, intent(in) :: unit_z, unit_phi
      logical, intent(out) :: ok

      call write_history_sample(slot, unit_z, unit_phi, "cold-slot", ok)
   end subroutine write_cold_history_sample

   subroutine write_history_sample(slot, unit_z, unit_phi, context, ok)
      type(tltm_slot_t), intent(in) :: slot
      integer, intent(in) :: unit_z, unit_phi
      character(len=*), intent(in) :: context
      logical, intent(out) :: ok
      complex(dp) :: phi
      logical :: phase_error

      call compute_phase_factor(slot%z, slot%jac, phi, phase_error)
      if (phase_error) then
         write (*, '(A,1X,A,A)') "[ERROR][TLTM-S2] Failed to compute", trim(context), " phase for history sample."
         ok = .false.
         return
      end if

      write (unit_z) slot%z
      write (unit_phi) phi
      ok = .true.
   end subroutine write_history_sample

   subroutine ensure_parent_directory_exists(file_path, ok)
      character(len=*), intent(in) :: file_path
      logical, intent(out) :: ok
      character(len=512) :: path_local, parent_dir
      integer :: slash_idx, cmd_status, exit_status

      ok = .true.
      path_local = trim(file_path)
      slash_idx = scan(path_local, "/", back=.true.)
      if (slash_idx <= 1) return

      parent_dir = adjustl(path_local(1:slash_idx - 1))
      if (len_trim(parent_dir) == 0) return

      call execute_command_line("mkdir -p "//trim(parent_dir), exitstat=exit_status, cmdstat=cmd_status)
      if (cmd_status /= 0 .or. exit_status /= 0) ok = .false.
   end subroutine ensure_parent_directory_exists

   integer function derive_seed(base_seed, offset) result(seed_value)
      integer, intent(in) :: base_seed, offset
      integer(int64) :: temp_seed

      temp_seed = int(abs(base_seed), int64) + 130363_int64*int(offset, int64)
      seed_value = int(modulo(temp_seed, 2147483646_int64) + 1_int64)
   end function derive_seed

   subroutine build_linear_ladder(n_slots, max_flow_time, flow_ladder)
      integer, intent(in) :: n_slots
      real(dp), intent(in) :: max_flow_time
      real(dp), allocatable, intent(out) :: flow_ladder(:)
      integer :: i

      allocate (flow_ladder(n_slots))
      if (n_slots == 1) then
         flow_ladder(1) = max_flow_time
      else
         do i = 1, n_slots
            flow_ladder(i) = max_flow_time*real(i - 1, dp)/real(n_slots - 1, dp)
         end do
      end if
   end subroutine build_linear_ladder

   subroutine release_all_slots(slots)
      type(tltm_slot_t), allocatable, intent(inout) :: slots(:)
      integer :: i

      if (.not. allocated(slots)) return
      do i = 1, size(slots)
         call release_tltm_slot(slots(i))
      end do
      deallocate (slots)
   end subroutine release_all_slots

end module tltm_stage2_driver

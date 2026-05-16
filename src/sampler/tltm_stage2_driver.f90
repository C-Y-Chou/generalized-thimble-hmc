module tltm_stage2_driver
   use, intrinsic :: iso_fortran_env, only: int64
   use param_mod, only: config, read_parameters
   use runtime_env_mod, only: parse_int_env, parse_real_env, parse_logical_env, read_string_env, parse_real_list, to_lower_ascii
   use utils, only: dp, log_determinant, wall_time_seconds, x_set_flow_time, x_set_seed_real
   use solve_flow, only: flow, reset_intode_fallback_stats, get_intode_fallback_stats, &
                         intode_diagnostics_context_t, get_intode_cvode_stats, get_intode_cvode_context_stats, &
                         get_intode_odex_stats, get_intode_odex_context_stats, &
                         intode_ctx_unknown, intode_ctx_flowz, intode_ctx_flowzr, intode_ctx_flow, &
                         intode_status_unknown, intode_status_is_strict_success
   use model, only: grand, calculate_action
   use mt95, only: getseed, grnd, mt95_get_state, mt95_seed_state, mt95_set_state, mt95_state_t, sgrnd
   use tltm_rng, only: tltm_rng_domain_stage2_init, tltm_rng_domain_stage2_local_accept, &
                       tltm_rng_domain_stage2_local_momentum, tltm_rng_domain_stage2_swap_accept, &
                       tltm_rng_fill_normal, tltm_rng_uniform
   use markovchain_mod, only: adaptive_preflow_to_target
   use markovchain_metropolis, only: metropolis_step
   use markovchain_phase, only: compute_phase_factor
   use hmc_constraints, only: reset_newton_eval_flow_status_counts, get_newton_eval_flow_status_counts, &
                              newton_eval_flow_status_context_t
   use hmc_integrator_core, only: reset_reverse_gate_replay_status_counts, get_reverse_gate_replay_status_counts, &
                                  hmc_policy_context_t, hmc_replay_diagnostics_context_t
   use quasi_newton_solver_mod, only: get_quasi_global_filter_stats, reset_quasi_eval_flow_status_counts, &
                                      get_quasi_eval_flow_status_counts, qn_diagnostics_context_t, &
                                      release_qn_diagnostics_context, qn_policy_context_t, release_qn_policy_context
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
   use tltm_run_context_mod, only: tltm_run_context_t, release_tltm_run_context
   implicit none

   integer, parameter :: stage2_cycle_cap_default = 200
   integer, parameter :: stage2_init_attempts_default = 200
   real(dp), parameter :: stage2_init_sigma_default = 0.10_dp
   character(len=*), parameter :: stage2_rng_legacy_global_v0 = "legacy_global_v0"
   character(len=*), parameter :: stage2_rng_per_replica_v1 = "per_replica_rng_v1"
   character(len=*), parameter :: stage2_rng_kernel_v2 = "stage2_kernel_rng_v2"

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

   type :: stage2_audit_context_t
      logical :: rg_reject_audit_loaded = .false.
      logical :: rg_reject_audit_enabled = .false.
      integer :: rg_reject_audit_unit = -1
      character(len=512) :: rg_reject_audit_file = ""
      logical :: local_transition_audit_loaded = .false.
      logical :: local_transition_audit_enabled = .false.
      integer :: local_transition_audit_unit = -1
      integer :: local_transition_audit_max_rows = 200000
      integer(int64) :: local_transition_audit_rows = 0_int64
      character(len=512) :: local_transition_audit_file = ""
   end type stage2_audit_context_t

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
      type(tltm_run_context_t), allocatable :: run_contexts(:)
      type(stage2_audit_context_t) :: audit_context
      type(qn_diagnostics_context_t) :: qn_diagnostics_context
      type(qn_policy_context_t) :: qn_policy_context
      type(hmc_policy_context_t) :: hmc_policy_context
      type(hmc_replay_diagnostics_context_t) :: hmc_replay_diagnostics_context
      type(newton_eval_flow_status_context_t) :: newton_flow_status_context
      type(intode_diagnostics_context_t) :: intode_diagnostics_summary
      type(mt95_state_t) :: swap_rng_state
      real(dp), allocatable :: flow_ladder(:)
      character(len=512) :: summary_file, label_trace_file
      character(len=512) :: cold_z_history_file, cold_phi_history_file
      character(len=512) :: all_history_dir
      character(len=512) :: v1_output_dir, v1_manifest_file, v1_protocol_file
      character(len=32) :: init_mode, rng_stream_contract
      integer :: n_slots, base_seed, swap_rng_seed, cycle_count, local_updates, x_size
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
      logical :: write_v1_manifest, write_v1_protocol, write_v1_package
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
      call reset_newton_eval_flow_status_counts(newton_flow_status_context)
      call reset_quasi_eval_flow_status_counts(qn_diagnostics_context)
      call reset_reverse_gate_replay_status_counts(hmc_replay_diagnostics_context)

      x_size = config%state%x_size
      call resolve_base_seed(base_seed)
      call resolve_stage2_controls(config%integrator%initial_flow_time, config%chain%length, config%chain%hmc_repeat, &
                                   n_slots, flow_ladder, max_flow_time, cycle_count, local_updates, init_sigma, init_mode, &
                                   swap_enabled)
      call resolve_stage2_output_paths(summary_file, label_trace_file)
      call resolve_stage2_cold_history_paths(cold_z_history_file, cold_phi_history_file, write_cold_history)
      call resolve_stage2_all_history_dir(all_history_dir, write_all_history)
      call resolve_stage2_v1_sidecar_paths(v1_output_dir, v1_manifest_file, v1_protocol_file, &
                                           write_v1_manifest, write_v1_protocol, write_v1_package)
      call resolve_stage2_rng_stream_contract(rng_stream_contract)
      swap_rng_seed = derive_swap_seed(base_seed)
      if (trim(rng_stream_contract) == stage2_rng_per_replica_v1) call mt95_seed_state(swap_rng_state, swap_rng_seed)

      write (*, '(A,I0,A,F8.4,A,I0,A,I0,A,F8.4,A,L1)') "[TLTM-S2] slots=", n_slots, &
         " max_flow=", max_flow_time, " cycles=", cycle_count, " local_updates=", local_updates, &
         " init_sigma=", init_sigma, " swap_enabled=", swap_enabled
      write (*, '(A,A)') "[TLTM-S2] init_mode=", trim(init_mode)
      write (*, '(A,F8.4,A,I0,A,F8.4)') "[TLTM-S2] local params: L=", config%integrator%trajectory_length, &
         " nstep=", config%integrator%integration_steps, " max_flow(test)=", max_flow_time
      write (*, '(A,A,A,I0)') "[TLTM-S2] rng_stream_contract=", trim(rng_stream_contract), " swap_rng_seed=", swap_rng_seed

      hot_slot = n_slots - 1

      allocate (slots(n_slots), label_tracks(n_slots), local_accept_census(n_slots), run_contexts(n_slots))
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
         call initialize_slot(slots(i), init_sigma, stage2_init_attempts_default, init_mode, rng_stream_contract, base_seed, ok, run_contexts(i), &
                              newton_flow_status_context)
         if (.not. ok) then
            write (*, '(A,I0,A,F8.4,A)') "[ERROR][TLTM-S2] Slot ", slots(i)%slot_id, &
               " initialization failed at flow_time=", slots(i)%flow_time, "."
            call release_all_run_contexts(run_contexts)
            call release_all_slots(slots)
            if (allocated(flow_ladder)) deallocate (flow_ladder)
            if (allocated(pair_stats)) deallocate (pair_stats)
            if (allocated(label_tracks)) deallocate (label_tracks)
            error stop 1
         end if
      end do

      if (trim(rng_stream_contract) == stage2_rng_legacy_global_v0) call sgrnd(base_seed)

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

      run_t0 = wall_time_seconds()
      do cycle_idx = 1, cycle_count
         do i = 1, n_slots
            slot_t0 = wall_time_seconds()
            call run_local_updates(slots(i), local_updates, local_accept_census(i), cycle_idx, run_contexts(i), audit_context, &
                                   qn_diagnostics_context, qn_policy_context, hmc_policy_context, hmc_replay_diagnostics_context, &
                                   newton_flow_status_context, rng_stream_contract, base_seed)
            slots(i)%local_runtime = slots(i)%local_runtime + (wall_time_seconds() - slot_t0)
         end do

         if (swap_enabled .and. n_slots > 1) then
            call perform_swap_sweep(slots, pair_stats, cycle_idx, swap_rng_state, run_contexts, rng_stream_contract, base_seed)
         end if

         call refresh_label_positions(slots, label_tracks)
         call update_round_trip_bookkeeping(label_tracks, cycle_idx, hot_slot)

         do i = 1, n_slots
            call measure_slot(slots(i))
         end do
         if (write_cold_history) then
            call write_cold_history_sample(slots(history_slot_index), unit_cold_z, unit_cold_phi, cold_sample_ok)
            if (.not. cold_sample_ok) then
               close (unit_trace)
               close (unit_cold_z)
               close (unit_cold_phi)
               if (write_all_history) call close_all_replica_history_files(all_z_units, all_phi_units)
               call close_stage2_audit_context(audit_context)
               call release_qn_diagnostics_context(qn_diagnostics_context)
               call release_qn_policy_context(qn_policy_context)
               call release_all_run_contexts(run_contexts)
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
               call close_stage2_audit_context(audit_context)
               call release_qn_diagnostics_context(qn_diagnostics_context)
               call release_qn_policy_context(qn_policy_context)
               call release_all_run_contexts(run_contexts)
               call release_all_slots(slots)
               if (allocated(flow_ladder)) deallocate (flow_ladder)
               if (allocated(pair_stats)) deallocate (pair_stats)
               if (allocated(label_tracks)) deallocate (label_tracks)
               error stop 1
            end if
         end if
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
      call aggregate_intode_diagnostics_from_run_contexts(run_contexts, intode_diagnostics_summary)
      call get_intode_fallback_stats(calls_total, calls_integrating, fallback_attempts, fallback_success, fallback_failure, &
                                     fallback_max_steps, fallback_invalid, fallback_h_min, intode_diagnostics_summary)
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
                                         global_filter_reject_count, qn_diagnostics_context)
      call get_constraint_solver_reverse_gate_stats(reverse_gate_candidate_counts, reverse_gate_pass_counts, &
                                                    reverse_gate_reject_counts)
      call write_stage2_summary(summary_file, slots, pair_stats, label_tracks, local_accept_census, cycle_count, local_updates, elapsed, &
                                swap_enabled, base_seed, swap_rng_seed, rng_stream_contract, &
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
	                                reverse_gate_candidate_counts, reverse_gate_pass_counts, reverse_gate_reject_counts, &
	                                newton_flow_status_context, qn_diagnostics_context, hmc_replay_diagnostics_context, &
	                                intode_diagnostics_summary)
      call write_stage2_v1_sidecars(v1_manifest_file, v1_protocol_file, write_v1_manifest, write_v1_protocol, &
                                    v1_output_dir, write_v1_package, &
                                    summary_file, label_trace_file, cold_z_history_file, cold_phi_history_file, all_history_dir, &
                                    write_cold_history, write_all_history, base_seed, swap_rng_seed, flow_ladder, max_flow_time, cycle_count, &
                                    local_updates, init_sigma, init_mode, rng_stream_contract, swap_enabled, elapsed, slots, pair_stats, label_tracks)
      call release_qn_diagnostics_context(qn_diagnostics_context)
      call release_qn_policy_context(qn_policy_context)
      call release_all_run_contexts(run_contexts)
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
      if (write_v1_manifest) then
         write (*, '(A,1X,A)') "[DONE][TLTM-S2] v1alpha manifest written to", trim(v1_manifest_file)
      end if
      if (write_v1_protocol) then
         write (*, '(A,1X,A)') "[DONE][TLTM-S2] v1alpha protocol written to", trim(v1_protocol_file)
      end if
      if (write_v1_package) then
         write (*, '(A,1X,A)') "[DONE][TLTM-S2] v1alpha diagnostics package written under", trim(v1_output_dir)
      end if
      call close_stage2_audit_context(audit_context)
   end subroutine execute_tltm_stage2

   subroutine initialize_slot(slot, init_sigma, max_attempts, init_mode, rng_stream_contract, base_seed, ok, run_context, newton_flow_status_context)
      type(tltm_slot_t), intent(inout) :: slot
      real(dp), intent(in) :: init_sigma
      integer, intent(in) :: max_attempts
      character(len=*), intent(in) :: init_mode
      character(len=*), intent(in) :: rng_stream_contract
      integer, intent(in) :: base_seed
      logical, intent(out) :: ok
      type(tltm_run_context_t), intent(inout) :: run_context
      type(newton_eval_flow_status_context_t), intent(inout), target :: newton_flow_status_context

      real(dp), allocatable :: x_seed(:)
      logical :: flow_failed
      logical :: preflow_success
      integer :: attempt, flow_status, stage_count

      ok = .false.
      allocate (x_seed(max(1, size(slot%x) - 1)))
      select case (trim(rng_stream_contract))
      case (stage2_rng_per_replica_v1)
         call mt95_seed_state(slot%rng_state, slot%rng_seed)
         call mt95_set_state(slot%rng_state)
      case (stage2_rng_legacy_global_v0)
         call sgrnd(slot%rng_seed)
      end select

      do attempt = 1, max_attempts
         if (trim(rng_stream_contract) == stage2_rng_kernel_v2) then
            call tltm_rng_fill_normal(x_seed, tltm_rng_domain_stage2_init, base_seed, 0, slot%slot_id, attempt)
         else
            call grand(x_seed)
         end if
         x_seed = init_sigma*x_seed
         if (trim(init_mode) == "direct" .or. trim(init_mode) == "legacy") then
            call x_set_flow_time(slot%x, slot%flow_time)
         else
            call x_set_flow_time(slot%x, 0.0_dp)
         end if
         call x_set_seed_real(slot%x, x_seed)

         if (trim(init_mode) /= "direct" .and. trim(init_mode) /= "legacy") then
            call adaptive_preflow_to_target(slot%x, slot%flow_time, config%integrator%trajectory_length, &
                                            config%integrator%integration_steps, attempt - 1, preflow_success, stage_count, &
                                            newton_flow_status=newton_flow_status_context, flow_workspace=run_context%flow%workspace, &
                                            intode_diagnostics=run_context%diagnostics%intode)
            if (.not. preflow_success) cycle
            write (*, '(A,I0,A,F10.6,A,I0,A,I0)') "[TLTM-S2][INIT] slot=", slot%slot_id, &
               " adaptive preflow ready at t=", slot%flow_time, " attempt=", attempt, " stages=", stage_count
         end if

         flow_status = intode_status_unknown
         call flow(slot%x, slot%z, slot%jac, flow_failed, flow_status, run_context%flow%workspace, &
                   run_context%diagnostics%intode)
         if ((.not. flow_failed) .and. intode_status_is_strict_success(flow_status)) then
            ok = .true.
            if (trim(init_mode) == "direct" .or. trim(init_mode) == "legacy") then
               write (*, '(A,I0,A,F10.6,A,I0)') "[TLTM-S2][INIT] slot=", slot%slot_id, &
                  " direct flow ready at t=", slot%flow_time, " attempt=", attempt
            end if
            exit
         end if
      end do

      if (ok .and. trim(rng_stream_contract) == stage2_rng_per_replica_v1) then
         call mt95_get_state(slot%rng_state)
         call measure_slot(slot)
      else if (ok) then
         call measure_slot(slot)
      end if
      if (allocated(x_seed)) deallocate (x_seed)
   end subroutine initialize_slot

   subroutine run_local_updates(slot, local_updates, accept_census, cycle_idx, run_context, audit_context, qn_diagnostics_context, &
                                qn_policy_context, hmc_policy_context, hmc_replay_diagnostics_context, newton_flow_status_context, &
                                rng_stream_contract, base_seed)
      type(tltm_slot_t), intent(inout) :: slot
      integer, intent(in) :: local_updates
      type(local_accept_census_t), intent(inout) :: accept_census
      integer, intent(in) :: cycle_idx
      type(tltm_run_context_t), intent(inout) :: run_context
      type(stage2_audit_context_t), intent(inout) :: audit_context
      type(qn_diagnostics_context_t), intent(inout), target :: qn_diagnostics_context
      type(qn_policy_context_t), intent(inout), target :: qn_policy_context
      type(hmc_policy_context_t), intent(inout), target :: hmc_policy_context
      type(hmc_replay_diagnostics_context_t), intent(inout), target :: hmc_replay_diagnostics_context
      type(newton_eval_flow_status_context_t), intent(inout), target :: newton_flow_status_context
      character(len=*), intent(in) :: rng_stream_contract
      integer, intent(in) :: base_seed

      integer :: update_idx, z_size
      real(dp), allocatable :: x_new(:), x_before(:), initial_momentum(:), final_momentum(:), kernel_momentum(:)
      complex(dp), allocatable :: z_new(:), j_new(:, :), z_before(:), j_before(:, :)
      logical :: accepted, proposal_failed
      integer :: transition_status
      type(solver_counter_snapshot_t) :: solver_before, solver_after
      real(dp) :: h_initial, h_final, delta_h, accept_probability, accept_uniform
      logical :: capture_local_transition_audit

      z_size = size(slot%z)
      call load_local_transition_audit_config(audit_context)
      capture_local_transition_audit = audit_context%local_transition_audit_enabled
      allocate (x_new(size(slot%x)), x_before(size(slot%x)))
      if (capture_local_transition_audit) allocate (initial_momentum(2*z_size), final_momentum(2*z_size))
      if (trim(rng_stream_contract) == stage2_rng_kernel_v2) allocate (kernel_momentum(2*z_size))
      allocate (z_new(z_size), z_before(z_size), j_new(z_size, z_size), j_before(z_size, z_size))

      if (trim(rng_stream_contract) == stage2_rng_per_replica_v1) call mt95_set_state(slot%rng_state)
      do update_idx = 1, local_updates
         x_before = slot%x
         z_before = slot%z
         j_before = slot%jac
         call snapshot_solver_counters(solver_before)
         if (trim(rng_stream_contract) == stage2_rng_kernel_v2) then
            call tltm_rng_fill_normal(kernel_momentum, tltm_rng_domain_stage2_local_momentum, &
                                      base_seed, cycle_idx, slot%slot_id, update_idx)
            accept_uniform = tltm_rng_uniform(tltm_rng_domain_stage2_local_accept, base_seed, cycle_idx, slot%slot_id, update_idx, 1)
            if (capture_local_transition_audit) then
               call metropolis_step(slot%x, slot%z, slot%jac, config%integrator%trajectory_length, &
                                    config%integrator%integration_steps, x_new, z_new, j_new, accepted, proposal_failed, transition_status, &
                                    h_initial_out=h_initial, h_final_out=h_final, delta_h_out=delta_h, &
                                    accept_probability_out=accept_probability, initial_momentum_out=initial_momentum, &
                                    final_momentum_out=final_momentum, context=run_context%hmc, flow_workspace=run_context%flow%workspace, &
                                    qn_context=run_context%qn%workspace, qn_diagnostics=qn_diagnostics_context, qn_policy=qn_policy_context, &
	                                    hmc_policy=hmc_policy_context, hmc_replay_diagnostics=hmc_replay_diagnostics_context, &
	                                    hmc_reversibility=run_context%diagnostics%hmc_reversibility, &
	                                    newton_flow_status=newton_flow_status_context, intode_diagnostics=run_context%diagnostics%intode, &
	                                    momentum_in=kernel_momentum, &
	                                    accept_uniform=accept_uniform)
            else
               call metropolis_step(slot%x, slot%z, slot%jac, config%integrator%trajectory_length, &
                                    config%integrator%integration_steps, x_new, z_new, j_new, accepted, proposal_failed, transition_status, &
                                    context=run_context%hmc, flow_workspace=run_context%flow%workspace, &
	                                    qn_context=run_context%qn%workspace, qn_diagnostics=qn_diagnostics_context, qn_policy=qn_policy_context, &
	                                    hmc_policy=hmc_policy_context, hmc_replay_diagnostics=hmc_replay_diagnostics_context, &
	                                    hmc_reversibility=run_context%diagnostics%hmc_reversibility, &
	                                    newton_flow_status=newton_flow_status_context, intode_diagnostics=run_context%diagnostics%intode, &
	                                    momentum_in=kernel_momentum, &
	                                    accept_uniform=accept_uniform)
            end if
         else
            if (capture_local_transition_audit) then
               call metropolis_step(slot%x, slot%z, slot%jac, config%integrator%trajectory_length, &
                                    config%integrator%integration_steps, x_new, z_new, j_new, accepted, proposal_failed, transition_status, &
                                    h_initial_out=h_initial, h_final_out=h_final, delta_h_out=delta_h, &
                                    accept_probability_out=accept_probability, initial_momentum_out=initial_momentum, &
                                    final_momentum_out=final_momentum, context=run_context%hmc, flow_workspace=run_context%flow%workspace, &
                                    qn_context=run_context%qn%workspace, qn_diagnostics=qn_diagnostics_context, qn_policy=qn_policy_context, &
	                                    hmc_policy=hmc_policy_context, hmc_replay_diagnostics=hmc_replay_diagnostics_context, &
	                                    hmc_reversibility=run_context%diagnostics%hmc_reversibility, &
	                                    newton_flow_status=newton_flow_status_context, intode_diagnostics=run_context%diagnostics%intode)
            else
               call metropolis_step(slot%x, slot%z, slot%jac, config%integrator%trajectory_length, &
                                    config%integrator%integration_steps, x_new, z_new, j_new, accepted, proposal_failed, transition_status, &
                                    context=run_context%hmc, flow_workspace=run_context%flow%workspace, &
	                                    qn_context=run_context%qn%workspace, qn_diagnostics=qn_diagnostics_context, qn_policy=qn_policy_context, &
	                                    hmc_policy=hmc_policy_context, hmc_replay_diagnostics=hmc_replay_diagnostics_context, &
	                                    hmc_reversibility=run_context%diagnostics%hmc_reversibility, &
	                                    newton_flow_status=newton_flow_status_context, intode_diagnostics=run_context%diagnostics%intode)
            end if
         end if
         call snapshot_solver_counters(solver_after)
         if (accepted) then
            slot%x = x_new
            slot%z = z_new
            slot%jac = j_new
            call accumulate_accepted_local_census(accept_census, solver_before, solver_after)
         end if
         call record_tltm_local_transition(slot, accepted, proposal_failed, transition_status)
         call record_rg_reject_audit(audit_context, cycle_idx, slot%slot_id, update_idx, x_before, z_before, j_before, &
                                     slot%x, slot%z, slot%jac, x_new, z_new, j_new, accepted, proposal_failed, &
                                     transition_status, solver_before, solver_after)
         if (capture_local_transition_audit) then
            call record_local_transition_audit(audit_context, cycle_idx, slot%slot_id, update_idx, accepted, proposal_failed, transition_status, &
                                               h_initial, h_final, delta_h, accept_probability, x_before, x_new, slot%x, &
                                               j_before, j_new, initial_momentum, final_momentum, solver_before, solver_after)
         end if
      end do
      if (trim(rng_stream_contract) == stage2_rng_per_replica_v1) call mt95_get_state(slot%rng_state)

      if (allocated(x_new)) deallocate (x_new)
      if (allocated(x_before)) deallocate (x_before)
      if (allocated(initial_momentum)) deallocate (initial_momentum)
      if (allocated(final_momentum)) deallocate (final_momentum)
      if (allocated(kernel_momentum)) deallocate (kernel_momentum)
      if (allocated(z_new)) deallocate (z_new)
      if (allocated(z_before)) deallocate (z_before)
      if (allocated(j_new)) deallocate (j_new)
      if (allocated(j_before)) deallocate (j_before)
   end subroutine run_local_updates

   subroutine record_rg_reject_audit(audit_context, cycle_idx, slot_id, update_idx, x_before, z_before, j_before, &
                                     x_after, z_after, j_after, x_proposal, z_proposal, j_proposal, &
                                     accepted, proposal_failed, transition_status, solver_before, solver_after)
      type(stage2_audit_context_t), intent(inout) :: audit_context
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

      call load_rg_reject_audit_config(audit_context)
      if (.not. audit_context%rg_reject_audit_enabled) return

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

      write (audit_context%rg_reject_audit_unit, &
             '(I0,",",I0,",",I0,",",L1,",",L1,",",I0,",",I0,",",I0,",",I0,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16,",",ES24.16)') &
         cycle_idx, slot_id, update_idx, accepted, proposal_failed, transition_status, rg_candidate_delta, rg_pass_delta, rg_reject_delta, &
         slot_dx, slot_dz, slot_dj, proposal_dx, proposal_dz, proposal_dj
      flush (audit_context%rg_reject_audit_unit)
   end subroutine record_rg_reject_audit

   subroutine load_rg_reject_audit_config(audit_context)
      type(stage2_audit_context_t), intent(inout) :: audit_context
      character(len=512) :: env_value
      integer :: io_status
      logical :: has_audit_file

      if (audit_context%rg_reject_audit_loaded) return
      audit_context%rg_reject_audit_loaded = .true.

      env_value = ""
      call read_string_env("TLTM_RG_REJECT_AUDIT_FILE", env_value, has_audit_file)
      if (.not. has_audit_file) return

      audit_context%rg_reject_audit_file = trim(env_value)
      open (newunit=audit_context%rg_reject_audit_unit, file=trim(audit_context%rg_reject_audit_file), status='replace', action='write', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[WARN][TLTM-S2] Cannot open RG reject audit file:", trim(audit_context%rg_reject_audit_file)
         audit_context%rg_reject_audit_enabled = .false.
         audit_context%rg_reject_audit_unit = -1
         return
      end if

      audit_context%rg_reject_audit_enabled = .true.
      write (audit_context%rg_reject_audit_unit, '(A)') &
         "cycle,slot_id,update_idx,accepted,proposal_failed,transition_status,rg_candidate_delta,rg_pass_delta,rg_reject_delta,"// &
         "slot_dx,slot_dz,slot_dj,proposal_dx,proposal_dz,proposal_dj"
      flush (audit_context%rg_reject_audit_unit)
      write (*, '(A,1X,A)') "[INFO][TLTM-S2] RG reject audit file:", trim(audit_context%rg_reject_audit_file)
   end subroutine load_rg_reject_audit_config

   subroutine close_rg_reject_audit(audit_context)
      type(stage2_audit_context_t), intent(inout) :: audit_context

      if (audit_context%rg_reject_audit_enabled .and. audit_context%rg_reject_audit_unit > 0) then
         close (audit_context%rg_reject_audit_unit)
      end if
      audit_context%rg_reject_audit_enabled = .false.
      audit_context%rg_reject_audit_unit = -1
   end subroutine close_rg_reject_audit

   subroutine record_local_transition_audit(audit_context, cycle_idx, slot_id, update_idx, accepted, proposal_failed, transition_status, &
                                           h_initial, h_final, delta_h, accept_probability, x_before, x_proposal, x_after, &
                                           j_before, j_proposal, initial_momentum, final_momentum, solver_before, solver_after)
      type(stage2_audit_context_t), intent(inout) :: audit_context
      integer, intent(in) :: cycle_idx, slot_id, update_idx
      logical, intent(in) :: accepted, proposal_failed
      integer, intent(in) :: transition_status
      real(dp), intent(in) :: h_initial, h_final, delta_h, accept_probability
      real(dp), intent(in) :: x_before(:), x_proposal(:), x_after(:)
      complex(dp), intent(in) :: j_before(:, :), j_proposal(:, :)
      real(dp), intent(in) :: initial_momentum(:), final_momentum(:)
      type(solver_counter_snapshot_t), intent(in) :: solver_before, solver_after
      real(dp) :: q_initial, q_proposal, q_after, c_initial, c_proposal

      call load_local_transition_audit_config(audit_context)
      if (.not. audit_context%local_transition_audit_enabled) return
      if (audit_context%local_transition_audit_max_rows >= 0) then
         if (audit_context%local_transition_audit_rows >= int(audit_context%local_transition_audit_max_rows, int64)) return
      end if

      q_initial = seed_coord_stage2(x_before)
      q_proposal = seed_coord_stage2(x_proposal)
      q_after = seed_coord_stage2(x_after)
      c_initial = tangent_coeff_stage2(initial_momentum, j_before)
      c_proposal = tangent_coeff_stage2(final_momentum, j_proposal)

      audit_context%local_transition_audit_rows = audit_context%local_transition_audit_rows + 1_int64
      write (audit_context%local_transition_audit_unit, &
             '(I0,",",I0,",",I0,",",L1,",",L1,",",I0,9(",",ES24.16),18(",",I0))') &
         cycle_idx, slot_id, update_idx, accepted, proposal_failed, transition_status, &
         h_initial, h_final, delta_h, accept_probability, q_initial, c_initial, q_proposal, c_proposal, q_after, &
         solver_after%newton_count - solver_before%newton_count, &
         solver_after%quasi_count - solver_before%quasi_count, &
         solver_after%probe_attempt_count - solver_before%probe_attempt_count, &
         solver_after%probe_success_count - solver_before%probe_success_count, &
         solver_after%full_attempt_count - solver_before%full_attempt_count, &
         solver_after%full_success_count - solver_before%full_success_count, &
         solver_after%class_local_count - solver_before%class_local_count, &
         solver_after%class_mid_count - solver_before%class_mid_count, &
         solver_after%class_global_count - solver_before%class_global_count, &
         solver_after%far_route_skip_count - solver_before%far_route_skip_count, &
         solver_after%far_route_light_count - solver_before%far_route_light_count, &
         solver_after%far_route_anchor_count - solver_before%far_route_anchor_count, &
         solver_after%near_attempt_count - solver_before%near_attempt_count, &
         solver_after%near_success_count - solver_before%near_success_count, &
         solver_after%reverse_gate_candidate_total - solver_before%reverse_gate_candidate_total, &
         solver_after%reverse_gate_pass_total - solver_before%reverse_gate_pass_total, &
         solver_after%reverse_gate_reject_total - solver_before%reverse_gate_reject_total, &
         audit_context%local_transition_audit_rows
      flush (audit_context%local_transition_audit_unit)
   end subroutine record_local_transition_audit

   subroutine load_local_transition_audit_config(audit_context)
      type(stage2_audit_context_t), intent(inout) :: audit_context
      character(len=512) :: env_value
      integer :: io_status
      logical :: has_audit_file

      if (audit_context%local_transition_audit_loaded) return
      audit_context%local_transition_audit_loaded = .true.

      env_value = ""
      call read_string_env("TLTM_LOCAL_TRANSITION_AUDIT_FILE", env_value, has_audit_file)
      if (.not. has_audit_file) return

      call parse_int_env("TLTM_LOCAL_TRANSITION_AUDIT_MAX_ROWS", audit_context%local_transition_audit_max_rows)
      audit_context%local_transition_audit_file = trim(env_value)
      open (newunit=audit_context%local_transition_audit_unit, file=trim(audit_context%local_transition_audit_file), status='replace', action='write', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[WARN][TLTM-S2] Cannot open local transition audit file:", trim(audit_context%local_transition_audit_file)
         audit_context%local_transition_audit_enabled = .false.
         audit_context%local_transition_audit_unit = -1
         return
      end if

      audit_context%local_transition_audit_enabled = .true.
      audit_context%local_transition_audit_rows = 0_int64
      write (audit_context%local_transition_audit_unit, '(A)') &
         "cycle,slot_id,update_idx,accepted,proposal_failed,transition_status,h_initial,h_final,delta_h,accept_probability,"// &
         "q_initial,c_initial,q_proposal,c_proposal,q_after,"// &
         "newton_delta,quasi_delta,probe_attempt_delta,probe_success_delta,full_attempt_delta,full_success_delta,"// &
         "class_local_delta,class_mid_delta,class_global_delta,far_skip_delta,far_light_delta,far_anchor_delta,"// &
         "near_attempt_delta,near_success_delta,rg_candidate_delta,rg_pass_delta,rg_reject_delta,row_index"
      flush (audit_context%local_transition_audit_unit)
      write (*, '(A,1X,A,A,I0)') "[INFO][TLTM-S2] Local transition audit file:", trim(audit_context%local_transition_audit_file), &
         " max_rows=", audit_context%local_transition_audit_max_rows
   end subroutine load_local_transition_audit_config

   subroutine close_local_transition_audit(audit_context)
      type(stage2_audit_context_t), intent(inout) :: audit_context

      if (audit_context%local_transition_audit_enabled .and. audit_context%local_transition_audit_unit > 0) then
         close (audit_context%local_transition_audit_unit)
      end if
      audit_context%local_transition_audit_enabled = .false.
      audit_context%local_transition_audit_unit = -1
   end subroutine close_local_transition_audit

   subroutine close_stage2_audit_context(audit_context)
      type(stage2_audit_context_t), intent(inout) :: audit_context

      call close_rg_reject_audit(audit_context)
      call close_local_transition_audit(audit_context)
   end subroutine close_stage2_audit_context

   pure real(dp) function seed_coord_stage2(x_val) result(q_val)
      real(dp), intent(in) :: x_val(:)

      if (size(x_val) >= 2) then
         q_val = x_val(2)
      else
         q_val = huge(1.0_dp)
      end if
   end function seed_coord_stage2

   pure real(dp) function tangent_coeff_stage2(momentum, jac) result(coeff)
      real(dp), intent(in) :: momentum(:)
      complex(dp), intent(in) :: jac(:, :)
      complex(dp) :: mom_c, coeff_c

      if (size(momentum) < 2 .or. size(jac, 1) < 1 .or. abs(jac(1, 1)) <= 0.0_dp) then
         coeff = huge(1.0_dp)
         return
      end if
      mom_c = cmplx(momentum(1), momentum(2), dp)
      coeff_c = mom_c/jac(1, 1)
      coeff = real(coeff_c, dp)
   end function tangent_coeff_stage2

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

   subroutine perform_swap_sweep(slots, pair_stats, cycle_idx, swap_rng_state, run_contexts, rng_stream_contract, base_seed)
      type(tltm_slot_t), intent(inout) :: slots(:)
      type(tltm_pair_stats_t), intent(inout) :: pair_stats(:)
      integer, intent(in) :: cycle_idx
      type(mt95_state_t), intent(inout) :: swap_rng_state
      type(tltm_run_context_t), intent(inout) :: run_contexts(:)
      character(len=*), intent(in) :: rng_stream_contract
      integer, intent(in) :: base_seed
      integer :: start_idx, idx

      if (size(slots) <= 1) return

      if (mod(cycle_idx, 2) == 1) then
         start_idx = 1
      else
         start_idx = 2
      end if

      do idx = start_idx, size(slots) - 1, 2
         call attempt_adjacent_swap(slots(idx), slots(idx + 1), pair_stats(idx), swap_rng_state, run_contexts(idx), &
                                    run_contexts(idx + 1), rng_stream_contract, base_seed, cycle_idx)
      end do
   end subroutine perform_swap_sweep

   subroutine attempt_adjacent_swap(slot_a, slot_b, stats, swap_rng_state, run_context_a, run_context_b, &
                                    rng_stream_contract, base_seed, cycle_idx)
      type(tltm_slot_t), intent(inout) :: slot_a, slot_b
      type(tltm_pair_stats_t), intent(inout) :: stats
      type(mt95_state_t), intent(inout) :: swap_rng_state
      type(tltm_run_context_t), intent(inout) :: run_context_a, run_context_b
      character(len=*), intent(in), optional :: rng_stream_contract
      integer, intent(in), optional :: base_seed, cycle_idx

      real(dp) :: e_a, e_b, e_ap, e_bp, delta, acc_prob
      logical :: ok_a, ok_b, ok_ap, ok_bp, accept
      integer :: flow_status_ap, flow_status_bp, label_tmp
      character(len=32) :: rng_contract_local
      real(dp), allocatable :: x_ap(:), x_bp(:)
      complex(dp), allocatable :: z_ap(:), z_bp(:), j_ap(:, :), j_bp(:, :)

      rng_contract_local = stage2_rng_per_replica_v1
      if (present(rng_stream_contract)) rng_contract_local = trim(rng_stream_contract)

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
      call flow(x_ap, z_ap, j_ap, ok_ap, flow_status_ap, run_context_a%flow%workspace, &
                run_context_a%diagnostics%intode)
      ok_ap = (.not. ok_ap) .and. intode_status_is_strict_success(flow_status_ap)
      if (ok_ap) call compute_effective_energy(z_ap, j_ap, e_ap, ok_ap)

      x_bp = slot_a%x
      call x_set_flow_time(x_bp, slot_b%flow_time)
      flow_status_bp = intode_status_unknown
      call flow(x_bp, z_bp, j_bp, ok_bp, flow_status_bp, run_context_b%flow%workspace, &
                run_context_b%diagnostics%intode)
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

      select case (trim(rng_contract_local))
      case (stage2_rng_kernel_v2)
         if (.not. present(base_seed) .or. .not. present(cycle_idx)) then
            write (*, '(A)') "[ERROR][TLTM-S2] stage2_kernel_rng_v2 swap requires base_seed and cycle_idx."
            error stop 1
         end if
         accept = (tltm_rng_uniform(tltm_rng_domain_stage2_swap_accept, base_seed, cycle_idx, stats%pair_id, 0, 1) <= acc_prob)
      case (stage2_rng_legacy_global_v0)
         accept = (grnd() <= acc_prob)
      case default
         call mt95_set_state(swap_rng_state)
         accept = (grnd() <= acc_prob)
         call mt95_get_state(swap_rng_state)
      end select
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

   subroutine aggregate_intode_diagnostics_from_run_contexts(run_contexts, aggregate)
      type(tltm_run_context_t), intent(in) :: run_contexts(:)
      type(intode_diagnostics_context_t), intent(inout), target :: aggregate
      integer :: idx

      call reset_intode_fallback_stats(aggregate)
      do idx = 1, size(run_contexts)
         call add_intode_diagnostics(aggregate, run_contexts(idx)%diagnostics%intode)
      end do
   end subroutine aggregate_intode_diagnostics_from_run_contexts

   subroutine add_intode_diagnostics(total, part)
      type(intode_diagnostics_context_t), intent(inout) :: total
      type(intode_diagnostics_context_t), intent(in) :: part

      total%calls_total = total%calls_total + part%calls_total
      total%calls_integrating = total%calls_integrating + part%calls_integrating
      total%fallback_attempts = total%fallback_attempts + part%fallback_attempts
      total%fallback_success = total%fallback_success + part%fallback_success
      total%fallback_failure = total%fallback_failure + part%fallback_failure
      total%fallback_max_steps = total%fallback_max_steps + part%fallback_max_steps
      total%fallback_invalid = total%fallback_invalid + part%fallback_invalid
      total%fallback_h_min = total%fallback_h_min + part%fallback_h_min
      total%fallback_attempts_ctx = total%fallback_attempts_ctx + part%fallback_attempts_ctx
      total%fallback_failures_ctx = total%fallback_failures_ctx + part%fallback_failures_ctx
      total%cvode_calls = total%cvode_calls + part%cvode_calls
      total%cvode_success = total%cvode_success + part%cvode_success
      total%cvode_failure = total%cvode_failure + part%cvode_failure
      total%cvode_steps_sum = total%cvode_steps_sum + part%cvode_steps_sum
      total%cvode_rhs_evals_sum = total%cvode_rhs_evals_sum + part%cvode_rhs_evals_sum
      total%cvode_error_test_fails_sum = total%cvode_error_test_fails_sum + part%cvode_error_test_fails_sum
      total%cvode_nonlinear_iters_sum = total%cvode_nonlinear_iters_sum + part%cvode_nonlinear_iters_sum
      total%cvode_nonlinear_conv_fails_sum = total%cvode_nonlinear_conv_fails_sum + part%cvode_nonlinear_conv_fails_sum
      total%cvode_step_solve_fails_sum = total%cvode_step_solve_fails_sum + part%cvode_step_solve_fails_sum
      total%cvode_final_order_sum = total%cvode_final_order_sum + part%cvode_final_order_sum
      total%cvode_max_final_order = max(total%cvode_max_final_order, part%cvode_max_final_order)
      total%cvode_calls_ctx = total%cvode_calls_ctx + part%cvode_calls_ctx
      total%cvode_steps_ctx = total%cvode_steps_ctx + part%cvode_steps_ctx
      total%cvode_rhs_evals_ctx = total%cvode_rhs_evals_ctx + part%cvode_rhs_evals_ctx
      total%cvode_error_test_fails_ctx = total%cvode_error_test_fails_ctx + part%cvode_error_test_fails_ctx
      total%cvode_nonlinear_iters_ctx = total%cvode_nonlinear_iters_ctx + part%cvode_nonlinear_iters_ctx
      total%cvode_nonlinear_conv_fails_ctx = total%cvode_nonlinear_conv_fails_ctx + part%cvode_nonlinear_conv_fails_ctx
      total%cvode_step_solve_fails_ctx = total%cvode_step_solve_fails_ctx + part%cvode_step_solve_fails_ctx
      total%odex_calls = total%odex_calls + part%odex_calls
      total%odex_success = total%odex_success + part%odex_success
      total%odex_failure = total%odex_failure + part%odex_failure
      total%odex_accepted_steps_sum = total%odex_accepted_steps_sum + part%odex_accepted_steps_sum
      total%odex_rejected_steps_sum = total%odex_rejected_steps_sum + part%odex_rejected_steps_sum
      total%odex_stability_rejects_sum = total%odex_stability_rejects_sum + part%odex_stability_rejects_sum
      total%odex_rhs_evals_sum = total%odex_rhs_evals_sum + part%odex_rhs_evals_sum
      total%odex_midpoint_rows_sum = total%odex_midpoint_rows_sum + part%odex_midpoint_rows_sum
      total%odex_kplus1_attempts_sum = total%odex_kplus1_attempts_sum + part%odex_kplus1_attempts_sum
      total%odex_accept_k_minus_1_sum = total%odex_accept_k_minus_1_sum + part%odex_accept_k_minus_1_sum
      total%odex_accept_k_sum = total%odex_accept_k_sum + part%odex_accept_k_sum
      total%odex_accept_k_plus_1_sum = total%odex_accept_k_plus_1_sum + part%odex_accept_k_plus_1_sum
      total%odex_large_error_rejects_sum = total%odex_large_error_rejects_sum + part%odex_large_error_rejects_sum
      total%odex_kplus1_rejects_sum = total%odex_kplus1_rejects_sum + part%odex_kplus1_rejects_sum
      total%odex_hairer_policy_steps_sum = total%odex_hairer_policy_steps_sum + part%odex_hairer_policy_steps_sum
      total%odex_tltm_policy_steps_sum = total%odex_tltm_policy_steps_sum + part%odex_tltm_policy_steps_sum
      total%odex_first_step_entries_sum = total%odex_first_step_entries_sum + part%odex_first_step_entries_sum
      total%odex_last_step_entries_sum = total%odex_last_step_entries_sum + part%odex_last_step_entries_sum
      total%odex_basic_step_entries_sum = total%odex_basic_step_entries_sum + part%odex_basic_step_entries_sum
      total%odex_row_j1_calls_sum = total%odex_row_j1_calls_sum + part%odex_row_j1_calls_sum
      total%odex_row_j2_calls_sum = total%odex_row_j2_calls_sum + part%odex_row_j2_calls_sum
      total%odex_row_jge3_calls_sum = total%odex_row_jge3_calls_sum + part%odex_row_jge3_calls_sum
      total%odex_row_j1_no_error_returns_sum = total%odex_row_j1_no_error_returns_sum + part%odex_row_j1_no_error_returns_sum
      total%odex_error_estimates_sum = total%odex_error_estimates_sum + part%odex_error_estimates_sum
      total%odex_hairer_scal_estimates_sum = total%odex_hairer_scal_estimates_sum + part%odex_hairer_scal_estimates_sum
      total%odex_default_scal_estimates_sum = total%odex_default_scal_estimates_sum + part%odex_default_scal_estimates_sum
      total%odex_errold_checks_sum = total%odex_errold_checks_sum + part%odex_errold_checks_sum
      total%odex_atov_events_sum = total%odex_atov_events_sum + part%odex_atov_events_sum
      total%odex_convergence_rejects_sum = total%odex_convergence_rejects_sum + part%odex_convergence_rejects_sum
      total%odex_kplus1_hope_rejects_sum = total%odex_kplus1_hope_rejects_sum + part%odex_kplus1_hope_rejects_sum
      total%odex_reject_kc_k_minus_1_sum = total%odex_reject_kc_k_minus_1_sum + part%odex_reject_kc_k_minus_1_sum
      total%odex_reject_kc_k_sum = total%odex_reject_kc_k_sum + part%odex_reject_kc_k_sum
      total%odex_reject_kc_k_plus_1_sum = total%odex_reject_kc_k_plus_1_sum + part%odex_reject_kc_k_plus_1_sum
      total%odex_kopt_accept_updates_sum = total%odex_kopt_accept_updates_sum + part%odex_kopt_accept_updates_sum
      total%odex_kopt_demotions_sum = total%odex_kopt_demotions_sum + part%odex_kopt_demotions_sum
      total%odex_kopt_keeps_sum = total%odex_kopt_keeps_sum + part%odex_kopt_keeps_sum
      total%odex_kopt_promotions_sum = total%odex_kopt_promotions_sum + part%odex_kopt_promotions_sum
      total%odex_after_reject_clamps_sum = total%odex_after_reject_clamps_sum + part%odex_after_reject_clamps_sum
      total%odex_reject_updates_sum = total%odex_reject_updates_sum + part%odex_reject_updates_sum
      total%odex_final_order_sum = total%odex_final_order_sum + part%odex_final_order_sum
      total%odex_max_final_order = max(total%odex_max_final_order, part%odex_max_final_order)
      total%odex_calls_ctx = total%odex_calls_ctx + part%odex_calls_ctx
      total%odex_accepted_steps_ctx = total%odex_accepted_steps_ctx + part%odex_accepted_steps_ctx
      total%odex_rejected_steps_ctx = total%odex_rejected_steps_ctx + part%odex_rejected_steps_ctx
      total%odex_rhs_evals_ctx = total%odex_rhs_evals_ctx + part%odex_rhs_evals_ctx
      total%odex_midpoint_rows_ctx = total%odex_midpoint_rows_ctx + part%odex_midpoint_rows_ctx
      total%odex_kplus1_attempts_ctx = total%odex_kplus1_attempts_ctx + part%odex_kplus1_attempts_ctx
      if (part%last_failure_available) then
         total%last_failure_available = part%last_failure_available
         total%last_failure_reason = part%last_failure_reason
         total%last_failure_context = part%last_failure_context
         total%last_failure_rattle_step = part%last_failure_rattle_step
         total%last_failure_rattle_substep = part%last_failure_rattle_substep
         total%last_failure_stage = part%last_failure_stage
         total%last_failure_newton_iter = part%last_failure_newton_iter
         total%last_failure_quasi_iter = part%last_failure_quasi_iter
         total%last_failure_t = part%last_failure_t
         if (allocated(part%last_failure_y)) total%last_failure_y = part%last_failure_y
      end if
   end subroutine add_intode_diagnostics

   subroutine write_cvode_context_stats(unit_summary, line_prefix, context_code, intode_diagnostics)
      integer, intent(in) :: unit_summary, context_code
      character(len=*), intent(in) :: line_prefix
      type(intode_diagnostics_context_t), intent(inout), target :: intode_diagnostics
      integer(int64) :: calls, steps_sum, rhs_evals_sum, error_test_fails_sum
      integer(int64) :: nonlinear_iters_sum, nonlinear_conv_fails_sum, step_solve_fails_sum

      call get_intode_cvode_context_stats(context_code, calls, steps_sum, rhs_evals_sum, error_test_fails_sum, &
                                          nonlinear_iters_sum, nonlinear_conv_fails_sum, step_solve_fails_sum, intode_diagnostics)
      write (unit_summary, '(A,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         trim(line_prefix), " calls=", calls, " steps=", steps_sum, " rhs_evals=", rhs_evals_sum, &
         " error_test_fails=", error_test_fails_sum, " nonlinear_iters=", nonlinear_iters_sum, &
         " nonlinear_conv_fails=", nonlinear_conv_fails_sum, " step_solve_fails=", step_solve_fails_sum
   end subroutine write_cvode_context_stats

   subroutine write_odex_context_stats(unit_summary, line_prefix, context_code, intode_diagnostics)
      integer, intent(in) :: unit_summary, context_code
      character(len=*), intent(in) :: line_prefix
      type(intode_diagnostics_context_t), intent(inout), target :: intode_diagnostics
      integer(int64) :: calls, accepted_steps_sum, rejected_steps_sum
      integer(int64) :: rhs_evals_sum, midpoint_rows_sum, kplus1_attempts_sum

      call get_intode_odex_context_stats(context_code, calls, accepted_steps_sum, rejected_steps_sum, rhs_evals_sum, &
                                         midpoint_rows_sum, kplus1_attempts_sum, intode_diagnostics)
      write (unit_summary, '(A,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         trim(line_prefix), " calls=", calls, " accepted_steps=", accepted_steps_sum, &
         " rejected_steps=", rejected_steps_sum, " rhs_evals=", rhs_evals_sum, &
         " midpoint_rows=", midpoint_rows_sum, " kplus1_attempts=", kplus1_attempts_sum
   end subroutine write_odex_context_stats

   integer(int64) function reverse_gate_count_at(counts, idx) result(count_value)
      integer(int64), intent(in) :: counts(:)
      integer, intent(in) :: idx

      if (idx >= 1 .and. idx <= size(counts)) then
         count_value = counts(idx)
      else
         count_value = 0_int64
      end if
   end function reverse_gate_count_at

   subroutine write_stage2_summary(summary_file, slots, pair_stats, label_tracks, local_accept_census, cycle_count, local_updates, elapsed, &
                                   swap_enabled, base_seed, swap_rng_seed, rng_stream_contract, &
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
	                                   reverse_gate_candidate_counts, reverse_gate_pass_counts, reverse_gate_reject_counts, &
	                                   newton_flow_status_context, qn_diagnostics_context, hmc_replay_diagnostics_context, &
	                                   intode_diagnostics)
      character(len=*), intent(in) :: summary_file
      type(tltm_slot_t), intent(in) :: slots(:)
      type(tltm_pair_stats_t), intent(in) :: pair_stats(:)
      type(tltm_label_track_t), intent(in) :: label_tracks(:)
      type(local_accept_census_t), intent(in) :: local_accept_census(:)
      integer, intent(in) :: cycle_count, local_updates, base_seed, swap_rng_seed
      character(len=*), intent(in) :: rng_stream_contract
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
      type(newton_eval_flow_status_context_t), intent(inout), target :: newton_flow_status_context
      type(qn_diagnostics_context_t), intent(inout), target :: qn_diagnostics_context
      type(hmc_replay_diagnostics_context_t), intent(inout), target :: hmc_replay_diagnostics_context
      type(intode_diagnostics_context_t), intent(inout), target :: intode_diagnostics

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
      integer(int64) :: cvode_call_count, cvode_success_count, cvode_failure_count
      integer(int64) :: cvode_steps_sum, cvode_rhs_evals_sum, cvode_error_test_fails_sum
      integer(int64) :: cvode_nonlinear_iters_sum, cvode_nonlinear_conv_fails_sum, cvode_step_solve_fails_sum
      integer(int64) :: cvode_final_order_sum, cvode_max_final_order
      integer(int64) :: odex_call_count, odex_success_count, odex_failure_count
      integer(int64) :: odex_accepted_steps_sum, odex_rejected_steps_sum, odex_stability_rejects_sum
      integer(int64) :: odex_rhs_evals_sum, odex_midpoint_rows_sum, odex_kplus1_attempts_sum
      integer(int64) :: odex_accept_k_minus_1_sum, odex_accept_k_sum, odex_accept_k_plus_1_sum
      integer(int64) :: odex_large_error_rejects_sum, odex_kplus1_rejects_sum
      integer(int64) :: odex_hairer_policy_steps_sum, odex_tltm_policy_steps_sum
      integer(int64) :: odex_first_step_entries_sum, odex_last_step_entries_sum, odex_basic_step_entries_sum
      integer(int64) :: odex_row_j1_calls_sum, odex_row_j2_calls_sum, odex_row_jge3_calls_sum
      integer(int64) :: odex_row_j1_no_error_returns_sum
      integer(int64) :: odex_error_estimates_sum, odex_hairer_scal_estimates_sum, odex_default_scal_estimates_sum
      integer(int64) :: odex_errold_checks_sum, odex_atov_events_sum
      integer(int64) :: odex_convergence_rejects_sum, odex_kplus1_hope_rejects_sum
      integer(int64) :: odex_reject_kc_k_minus_1_sum, odex_reject_kc_k_sum, odex_reject_kc_k_plus_1_sum
      integer(int64) :: odex_kopt_accept_updates_sum, odex_reject_updates_sum
      integer(int64) :: odex_kopt_demotions_sum, odex_kopt_keeps_sum, odex_kopt_promotions_sum
      integer(int64) :: odex_after_reject_clamps_sum
      integer(int64) :: odex_final_order_sum, odex_max_final_order

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
      write (unit_summary, '(A,A)') "# rng_stream_contract=", trim(rng_stream_contract)
      write (unit_summary, '(A,A)') "# seed_policy=", trim(stage2_seed_policy_text(rng_stream_contract))
      write (unit_summary, '(A,I0)') "# base_seed=", base_seed
      write (unit_summary, '(A,I0)') "# swap_rng_seed=", swap_rng_seed
      write (unit_summary, '(A,F12.6)') "# elapsed_sec=", elapsed
      write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
         "# fallback_stats calls_total=", calls_total, " calls_integrating=", calls_integrating, &
         " attempts=", fallback_attempts, " success=", fallback_success, " failure=", fallback_failure, &
         " max_steps=", fallback_max_steps, " invalid=", fallback_invalid, " h_min=", fallback_h_min
      call get_intode_cvode_stats(cvode_call_count, cvode_success_count, cvode_failure_count, cvode_steps_sum, &
                                  cvode_rhs_evals_sum, cvode_error_test_fails_sum, cvode_nonlinear_iters_sum, &
                                  cvode_nonlinear_conv_fails_sum, cvode_step_solve_fails_sum, cvode_final_order_sum, &
                                  cvode_max_final_order, intode_diagnostics)
      if (cvode_call_count > 0_int64) then
         write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
            "# cvode_stats calls=", cvode_call_count, " success=", cvode_success_count, " failure=", cvode_failure_count, &
            " steps=", cvode_steps_sum, " rhs_evals=", cvode_rhs_evals_sum, &
            " error_test_fails=", cvode_error_test_fails_sum, " nonlinear_iters=", cvode_nonlinear_iters_sum, &
            " nonlinear_conv_fails=", cvode_nonlinear_conv_fails_sum, " step_solve_fails=", cvode_step_solve_fails_sum, &
            " final_order_sum=", cvode_final_order_sum, " max_final_order=", cvode_max_final_order
         call write_cvode_context_stats(unit_summary, "# cvode_context_unknown", intode_ctx_unknown, intode_diagnostics)
         call write_cvode_context_stats(unit_summary, "# cvode_context_flowz", intode_ctx_flowz, intode_diagnostics)
         call write_cvode_context_stats(unit_summary, "# cvode_context_flowzr", intode_ctx_flowzr, intode_diagnostics)
         call write_cvode_context_stats(unit_summary, "# cvode_context_flow", intode_ctx_flow, intode_diagnostics)
      end if
      call get_intode_odex_stats(odex_call_count, odex_success_count, odex_failure_count, odex_accepted_steps_sum, &
                                 odex_rejected_steps_sum, odex_stability_rejects_sum, odex_rhs_evals_sum, &
                                 odex_midpoint_rows_sum, odex_kplus1_attempts_sum, odex_accept_k_minus_1_sum, &
                                 odex_accept_k_sum, odex_accept_k_plus_1_sum, odex_large_error_rejects_sum, &
                                 odex_kplus1_rejects_sum, odex_hairer_policy_steps_sum, odex_tltm_policy_steps_sum, &
                                 odex_first_step_entries_sum, odex_last_step_entries_sum, odex_basic_step_entries_sum, &
                                 odex_row_j1_calls_sum, odex_row_j2_calls_sum, odex_row_jge3_calls_sum, &
                                 odex_row_j1_no_error_returns_sum, odex_error_estimates_sum, &
                                 odex_hairer_scal_estimates_sum, odex_default_scal_estimates_sum, &
                                 odex_errold_checks_sum, odex_atov_events_sum, odex_convergence_rejects_sum, &
                                 odex_kplus1_hope_rejects_sum, odex_reject_kc_k_minus_1_sum, odex_reject_kc_k_sum, &
                                 odex_reject_kc_k_plus_1_sum, odex_kopt_accept_updates_sum, odex_kopt_demotions_sum, &
                                 odex_kopt_keeps_sum, odex_kopt_promotions_sum, odex_after_reject_clamps_sum, &
                                 odex_reject_updates_sum, odex_final_order_sum, odex_max_final_order, intode_diagnostics)
      if (odex_call_count > 0_int64) then
         write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
            "# odex_stats calls=", odex_call_count, " success=", odex_success_count, " failure=", odex_failure_count, &
            " accepted_steps=", odex_accepted_steps_sum, " rejected_steps=", odex_rejected_steps_sum, &
            " stability_rejects=", odex_stability_rejects_sum, " rhs_evals=", odex_rhs_evals_sum, &
            " midpoint_rows=", odex_midpoint_rows_sum, " kplus1_attempts=", odex_kplus1_attempts_sum, &
            " accept_k_minus_1=", odex_accept_k_minus_1_sum, " accept_k=", odex_accept_k_sum, &
            " accept_k_plus_1=", odex_accept_k_plus_1_sum, " large_error_rejects=", odex_large_error_rejects_sum, &
            " kplus1_rejects=", odex_kplus1_rejects_sum, " final_order_sum=", odex_final_order_sum, &
            " max_final_order=", odex_max_final_order
         write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
            "# odex_stats hairer_policy_steps=", odex_hairer_policy_steps_sum, &
            " tltm_policy_steps=", odex_tltm_policy_steps_sum, &
            " first_step_entries=", odex_first_step_entries_sum, &
            " last_step_entries=", odex_last_step_entries_sum, &
            " basic_step_entries=", odex_basic_step_entries_sum, &
            " row_j1_calls=", odex_row_j1_calls_sum, " row_j2_calls=", odex_row_j2_calls_sum, &
            " row_jge3_calls=", odex_row_jge3_calls_sum, " error_estimates=", odex_error_estimates_sum, &
            " hairer_scal_estimates=", odex_hairer_scal_estimates_sum, &
            " default_scal_estimates=", odex_default_scal_estimates_sum, &
            " convergence_rejects=", odex_convergence_rejects_sum, &
            " kplus1_hope_rejects=", odex_kplus1_hope_rejects_sum, &
            " kopt_accept_updates=", odex_kopt_accept_updates_sum, &
            " reject_updates=", odex_reject_updates_sum
         write (unit_summary, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') &
            "# odex_stats row_j1_no_error_returns=", odex_row_j1_no_error_returns_sum, &
            " errold_checks=", odex_errold_checks_sum, " atov_events=", odex_atov_events_sum, &
            " reject_kc_k_minus_1=", odex_reject_kc_k_minus_1_sum, &
            " reject_kc_k=", odex_reject_kc_k_sum, &
            " reject_kc_k_plus_1=", odex_reject_kc_k_plus_1_sum, &
            " kopt_demotions=", odex_kopt_demotions_sum, " kopt_keeps=", odex_kopt_keeps_sum, &
            " kopt_promotions=", odex_kopt_promotions_sum, &
            " after_reject_clamps=", odex_after_reject_clamps_sum, &
            " reject_updates=", odex_reject_updates_sum
         call write_odex_context_stats(unit_summary, "# odex_context_unknown", intode_ctx_unknown, intode_diagnostics)
         call write_odex_context_stats(unit_summary, "# odex_context_flowz", intode_ctx_flowz, intode_diagnostics)
         call write_odex_context_stats(unit_summary, "# odex_context_flowzr", intode_ctx_flowzr, intode_diagnostics)
         call write_odex_context_stats(unit_summary, "# odex_context_flow", intode_ctx_flow, intode_diagnostics)
      end if
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
                                              newton_flow_failure_invalid_count, newton_flow_failure_h_min_count, newton_flow_unknown_count, &
                                              newton_flow_status_context)
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
                                                 rg_replay_final_flow_non_strict_success_count, rg_replay_unknown_count, &
                                                 hmc_replay_diagnostics_context)
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
                                             qn_flow_failure_invalid_count, qn_flow_failure_h_min_count, qn_flow_unknown_count, &
                                             qn_diagnostics_context)
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
      integer :: ios
      logical :: has_seed_env

      seed_env = ""
      call read_string_env("CHAIN_RNG_SEED", seed_env, has_seed_env)
      if (has_seed_env) then
         read (seed_env, *, iostat=ios) base_seed
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
      logical :: ok
      logical :: has_ladder_env, has_init_mode
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
      call read_string_env("TLTM_STAGE2_FLOW_TIME_LADDER", ladder_text, has_ladder_env)
      if (has_ladder_env) then
         call parse_real_list(ladder_text, parsed, ok)
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
      call read_string_env("TLTM_STAGE2_INIT_MODE", env_value, has_init_mode)
      if (has_init_mode) init_mode = trim(to_lower_ascii(adjustl(env_value)))
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

      summary_file = "../output/tests/tltm_stage2_summary.dat"
      call read_string_env("TLTM_STAGE2_SUMMARY_FILE", summary_file)

      label_trace_file = "../output/tests/tltm_stage2_label_trace.dat"
      call read_string_env("TLTM_STAGE2_LABEL_TRACE_FILE", label_trace_file)
   end subroutine resolve_stage2_output_paths

   subroutine resolve_stage2_rng_stream_contract(rng_stream_contract)
      character(len=*), intent(out) :: rng_stream_contract
      character(len=128) :: env_value
      logical :: has_contract

      rng_stream_contract = stage2_rng_kernel_v2
      env_value = ""
      call read_string_env("TLTM_STAGE2_RNG_STREAM_CONTRACT", env_value, has_contract)
      if (has_contract) rng_stream_contract = trim(to_lower_ascii(adjustl(env_value)))

      select case (trim(rng_stream_contract))
      case (stage2_rng_legacy_global_v0, stage2_rng_per_replica_v1, stage2_rng_kernel_v2)
         return
      case default
         write (*, '(A,A,A)') "[ERROR][TLTM-S2] Unsupported TLTM_STAGE2_RNG_STREAM_CONTRACT='", &
            trim(rng_stream_contract), "'."
         write (*, '(A)') "[ERROR][TLTM-S2] Use legacy_global_v0, per_replica_rng_v1, or stage2_kernel_rng_v2."
         error stop 1
      end select
   end subroutine resolve_stage2_rng_stream_contract

   subroutine resolve_stage2_cold_history_paths(cold_z_history_file, cold_phi_history_file, write_cold_history)
      character(len=*), intent(out) :: cold_z_history_file, cold_phi_history_file
      logical, intent(out) :: write_cold_history
      logical :: has_z_path, has_phi_path

      cold_z_history_file = ""
      cold_phi_history_file = ""

      call read_string_env("TLTM_STAGE2_COLD_Z_HISTORY_FILE", cold_z_history_file, has_z_path)

      call read_string_env("TLTM_STAGE2_COLD_PHI_HISTORY_FILE", cold_phi_history_file, has_phi_path)

      if (has_z_path .neqv. has_phi_path) then
         write (*, '(A)') "[ERROR][TLTM-S2] Both TLTM_STAGE2_COLD_Z_HISTORY_FILE and TLTM_STAGE2_COLD_PHI_HISTORY_FILE are required."
         error stop 1
      end if
      write_cold_history = has_z_path .and. has_phi_path
   end subroutine resolve_stage2_cold_history_paths

   subroutine resolve_stage2_all_history_dir(all_history_dir, write_all_history)
      character(len=*), intent(out) :: all_history_dir
      logical, intent(out) :: write_all_history

      all_history_dir = ""
      call read_string_env("TLTM_STAGE2_ALL_REPLICA_HISTORY_DIR", all_history_dir, write_all_history)
   end subroutine resolve_stage2_all_history_dir

   subroutine resolve_stage2_v1_sidecar_paths(output_dir, manifest_file, protocol_file, write_manifest, write_protocol, write_package)
      character(len=*), intent(out) :: output_dir, manifest_file, protocol_file
      logical, intent(out) :: write_manifest, write_protocol, write_package
      character(len=512) :: env_value
      logical :: has_output_dir, has_manifest_file, has_protocol_file

      output_dir = ""
      manifest_file = ""
      protocol_file = ""
      write_manifest = .false.
      write_protocol = .false.
      write_package = .false.

      call read_string_env("TLTM_STAGE2_V1_OUTPUT_DIR", output_dir, has_output_dir)
      if (has_output_dir) then
         manifest_file = trim(output_dir)//"/manifest.json"
         protocol_file = trim(output_dir)//"/protocol.json"
         write_manifest = .true.
         write_protocol = .true.
         write_package = .true.
      end if

      env_value = ""
      call read_string_env("TLTM_STAGE2_V1_MANIFEST_FILE", env_value, has_manifest_file)
      if (has_manifest_file) then
         manifest_file = trim(env_value)
         write_manifest = .true.
      end if

      env_value = ""
      call read_string_env("TLTM_STAGE2_V1_PROTOCOL_FILE", env_value, has_protocol_file)
      if (has_protocol_file) then
         protocol_file = trim(env_value)
         write_protocol = .true.
      end if
   end subroutine resolve_stage2_v1_sidecar_paths

   subroutine write_stage2_v1_sidecars(manifest_file, protocol_file, write_manifest, write_protocol, output_dir, write_package, &
                                       summary_file, label_trace_file, cold_z_history_file, cold_phi_history_file, all_history_dir, &
                                       write_cold_history, write_all_history, base_seed, swap_rng_seed, flow_ladder, max_flow_time, cycle_count, &
                                       local_updates, init_sigma, init_mode, rng_stream_contract, swap_enabled, elapsed, slots, pair_stats, label_tracks)
      character(len=*), intent(in) :: manifest_file, protocol_file
      logical, intent(in) :: write_manifest, write_protocol
      character(len=*), intent(in) :: output_dir
      logical, intent(in) :: write_package
      character(len=*), intent(in) :: summary_file, label_trace_file
      character(len=*), intent(in) :: cold_z_history_file, cold_phi_history_file, all_history_dir
      logical, intent(in) :: write_cold_history, write_all_history
      integer, intent(in) :: base_seed, swap_rng_seed, cycle_count, local_updates
      real(dp), intent(in) :: flow_ladder(:), max_flow_time, init_sigma, elapsed
      character(len=*), intent(in) :: init_mode, rng_stream_contract
      logical, intent(in) :: swap_enabled
      type(tltm_slot_t), intent(in) :: slots(:)
      type(tltm_pair_stats_t), intent(in) :: pair_stats(:)
      type(tltm_label_track_t), intent(in) :: label_tracks(:)

      if (write_protocol) call write_stage2_v1_protocol(protocol_file)
      if (write_package) call write_stage2_v1_diagnostics_package(output_dir, slots, pair_stats, label_tracks)
      if (write_manifest) call write_stage2_v1_manifest(manifest_file, protocol_file, write_protocol, &
                                                        summary_file, label_trace_file, cold_z_history_file, cold_phi_history_file, &
                                                        all_history_dir, write_cold_history, write_all_history, base_seed, swap_rng_seed, flow_ladder, &
                                                        max_flow_time, cycle_count, local_updates, init_sigma, init_mode, rng_stream_contract, swap_enabled, &
                                                        elapsed, output_dir, write_package)
   end subroutine write_stage2_v1_sidecars

   subroutine write_stage2_v1_manifest(manifest_file, protocol_file, write_protocol, &
                                       summary_file, label_trace_file, cold_z_history_file, cold_phi_history_file, all_history_dir, &
                                       write_cold_history, write_all_history, base_seed, swap_rng_seed, flow_ladder, max_flow_time, cycle_count, &
                                       local_updates, init_sigma, init_mode, rng_stream_contract, swap_enabled, elapsed, output_dir, write_package)
      character(len=*), intent(in) :: manifest_file, protocol_file
      logical, intent(in) :: write_protocol
      character(len=*), intent(in) :: summary_file, label_trace_file
      character(len=*), intent(in) :: cold_z_history_file, cold_phi_history_file, all_history_dir
      logical, intent(in) :: write_cold_history, write_all_history
      integer, intent(in) :: base_seed, swap_rng_seed, cycle_count, local_updates
      real(dp), intent(in) :: flow_ladder(:), max_flow_time, init_sigma, elapsed
      character(len=*), intent(in) :: init_mode, rng_stream_contract
      logical, intent(in) :: swap_enabled
      character(len=*), intent(in) :: output_dir
      logical, intent(in) :: write_package

      integer :: unit_manifest, ios
      logical :: path_ok
      character(len=128) :: git_commit
      character(len=512) :: local_csv, swap_csv, label_csv, phase_csv

      call ensure_parent_directory_exists(manifest_file, path_ok)
      if (.not. path_ok) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot prepare v1 manifest path:", trim(manifest_file)
         error stop 1
      end if

      open (newunit=unit_manifest, file=trim(manifest_file), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open v1 manifest file:", trim(manifest_file)
         error stop 1
      end if

      call resolve_git_commit(git_commit)

      write (unit_manifest, '(A)') "{"
      call write_json_string_field(unit_manifest, "schema_version", "tltm.stage2.manifest.v1alpha1", .true.)
      call write_json_string_field(unit_manifest, "writer_version", "stage2_sidecar_2026-05-10", .true.)
      call write_json_string_field(unit_manifest, "git_commit", trim(git_commit), .true.)
      call write_json_string_field(unit_manifest, "algorithm_id", "TLTM-HMC", .true.)
      call write_json_string_field(unit_manifest, "canonical_route_id", "newton_p28_btn_reverse_gate_metropolis", .true.)
      call write_json_string_field(unit_manifest, "flow_policy_id", "nt_strict_qn_navassist_cert_strict_rg_metropolis_v1", .true.)
      call write_json_string_field(unit_manifest, "reverse_gate_policy_id", "required_for_canonical_p28_route", .true.)
      call write_json_string_field(unit_manifest, "tempering_protocol_id", "stage2_replica_exchange_local_swap_measure", .true.)
      call write_json_string_field(unit_manifest, "sweep_order", "local_update_swap_measure_history_label_trace", .true.)
      call write_json_string_field(unit_manifest, "measurement_boundary", "post_swap", .true.)
      call write_json_string_field(unit_manifest, "history_boundary", "post_swap", .true.)
      call write_json_string_field(unit_manifest, "label_trace_boundary", "post_swap", .true.)
      call write_json_real_array_field(unit_manifest, "flow_ladder", flow_ladder, .true.)
      call write_json_string_field(unit_manifest, "rng_stream_contract", trim(rng_stream_contract), .true.)
      call write_json_string_field(unit_manifest, "seed_policy", trim(stage2_seed_policy_text(rng_stream_contract)), .true.)

      write (unit_manifest, '(A)') '  "resolved_stage2_controls": {'
      call write_json_int_field(unit_manifest, "base_seed", base_seed, .true., 4)
      call write_json_int_field(unit_manifest, "swap_rng_seed", swap_rng_seed, .true., 4)
      call write_json_int_field(unit_manifest, "num_replicas", size(flow_ladder), .true., 4)
      call write_json_real_field(unit_manifest, "max_flow_time", max_flow_time, .true., 4)
      call write_json_int_field(unit_manifest, "cycles", cycle_count, .true., 4)
      call write_json_int_field(unit_manifest, "local_updates", local_updates, .true., 4)
      call write_json_real_field(unit_manifest, "init_sigma", init_sigma, .true., 4)
      call write_json_string_field(unit_manifest, "init_mode", trim(init_mode), .true., 4)
      call write_json_logical_field(unit_manifest, "swap_enabled", swap_enabled, .false., 4)
      write (unit_manifest, '(A)') '  },'

      write (unit_manifest, '(A)') '  "resolved_config": {'
      call write_json_int_field(unit_manifest, "x_size", config%state%x_size, .true., 4)
      call write_json_int_field(unit_manifest, "z_size", config%state%z_size, .true., 4)
      call write_json_real_field(unit_manifest, "trajectory_length", config%integrator%trajectory_length, .true., 4)
      call write_json_int_field(unit_manifest, "integration_steps", config%integrator%integration_steps, .true., 4)
      call write_json_string_field(unit_manifest, "integrator_method", trim(config%integrator%method), .true., 4)
      call write_json_real_field(unit_manifest, "abs_tol", config%solver%abs_tol, .true., 4)
      call write_json_real_field(unit_manifest, "rel_tol", config%solver%rel_tol, .true., 4)
      call write_json_real_field(unit_manifest, "constraint_tol", config%solver%constraint_tol, .true., 4)
      call write_json_logical_field(unit_manifest, "enable_quasi_fallback", config%solver%enable_quasi_fallback, .true., 4)
      call write_json_string_field(unit_manifest, "derivative_mode", trim(config%model%derivative_mode), .false., 4)
      write (unit_manifest, '(A)') '  },'

      write (unit_manifest, '(A)') '  "env_overrides": {'
      call write_json_env_field(unit_manifest, "CHAIN_RNG_SEED", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_FLOW_TIME_LADDER", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_NUM_REPLICAS", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_MAX_FLOW_TIME", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_CYCLES", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_LOCAL_UPDATES", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_SWAP_ENABLED", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_INIT_SIGMA", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_INIT_MODE", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_RNG_STREAM_CONTRACT", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_SUMMARY_FILE", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_LABEL_TRACE_FILE", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_COLD_Z_HISTORY_FILE", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_COLD_PHI_HISTORY_FILE", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_ALL_REPLICA_HISTORY_DIR", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_V1_OUTPUT_DIR", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_V1_MANIFEST_FILE", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_STAGE2_V1_PROTOCOL_FILE", .true., 4)
      call write_json_env_field(unit_manifest, "INTODE_SOLVER_ASSIST_POLICY", .true., 4)
      call write_json_env_field(unit_manifest, "INTODE_SOLVER_ASSIST_ENABLED", .true., 4)
      call write_json_env_field(unit_manifest, "QN_SOLVER_BACKEND", .true., 4)
      call write_json_env_field(unit_manifest, "QN_OFFICIAL_DFOLS_PRESET", .true., 4)
      call write_json_env_field(unit_manifest, "QN_OFFICIAL_DFOLS_NPT", .true., 4)
      call write_json_env_field(unit_manifest, "QN_OFFICIAL_DFOLS_MAXFUN", .true., 4)
      call write_json_env_field(unit_manifest, "QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE", .true., 4)
      call write_json_env_field(unit_manifest, "QN_OFFICIAL_DFOLS_RHOBEG", .true., 4)
      call write_json_env_field(unit_manifest, "QN_OFFICIAL_DFOLS_RHOEND", .true., 4)
      call write_json_env_field(unit_manifest, "QN_OFFICIAL_DFOLS_MODEL_ABS_TOL", .true., 4)
      call write_json_env_field(unit_manifest, "QN_OFFICIAL_DFOLS_MODEL_REL_TOL", .true., 4)
      call write_json_env_field(unit_manifest, "TLTM_OFFICIAL_DFOLS_PYTHONPATH", .false., 4)
      write (unit_manifest, '(A)') '  },'

      write (unit_manifest, '(A)') '  "outputs": {'
      call write_json_string_field(unit_manifest, "stage2_summary_v0", trim(summary_file), .true., 4)
      call write_json_string_field(unit_manifest, "label_trace_v0", trim(label_trace_file), .true., 4)
      call write_json_logical_field(unit_manifest, "cold_history_written", write_cold_history, .true., 4)
      call write_json_string_or_null_field(unit_manifest, "cold_z_history_file", cold_z_history_file, write_cold_history, .true., 4)
      call write_json_string_or_null_field(unit_manifest, "cold_phi_history_file", cold_phi_history_file, write_cold_history, .true., 4)
      call write_json_logical_field(unit_manifest, "all_replica_history_written", write_all_history, .true., 4)
      call write_json_string_or_null_field(unit_manifest, "all_replica_history_dir", all_history_dir, write_all_history, .true., 4)
      call write_json_logical_field(unit_manifest, "v1_protocol_written", write_protocol, .true., 4)
      call write_json_string_or_null_field(unit_manifest, "v1_protocol_file", protocol_file, write_protocol, .false., 4)
      write (unit_manifest, '(A)') '  },'

      write (unit_manifest, '(A)') '  "diagnostics": {'
      call write_json_logical_field(unit_manifest, "v1_diagnostics_written", write_package, .true., 4)
      if (write_package) then
         call stage2_v1_package_path(output_dir, "diagnostics/local_transition_summary.csv", local_csv)
         call stage2_v1_package_path(output_dir, "diagnostics/swap_summary.csv", swap_csv)
         call stage2_v1_package_path(output_dir, "diagnostics/label_summary.csv", label_csv)
         call stage2_v1_package_path(output_dir, "observables/per_slot_phase_summary.csv", phase_csv)
      else
         local_csv = ""
         swap_csv = ""
         label_csv = ""
         phase_csv = ""
      end if
      call write_json_string_or_null_field(unit_manifest, "local_transition_summary_csv", local_csv, write_package, .true., 4)
      call write_json_string_or_null_field(unit_manifest, "swap_summary_csv", swap_csv, write_package, .true., 4)
      call write_json_string_or_null_field(unit_manifest, "label_summary_csv", label_csv, write_package, .true., 4)
      call write_json_string_or_null_field(unit_manifest, "per_slot_phase_summary_csv", phase_csv, write_package, .false., 4)
      write (unit_manifest, '(A)') '  },'

      write (unit_manifest, '(A)') '  "compatibility": {'
      call write_json_string_field(unit_manifest, "v0_output_contract", "field_names_preserved_timing_changed", .true., 4)
      call write_json_string_field(unit_manifest, "v1_sidecar_default", "opt_in_only", .true., 4)
      call write_json_string_field(unit_manifest, "sample_boundary_note", "Stage2 samples, histories, and label trace are written after the swap sweep.", .false., 4)
      write (unit_manifest, '(A)') '  },'

      call write_json_real_field(unit_manifest, "elapsed_sec", elapsed, .false.)
      write (unit_manifest, '(A)') "}"

      close (unit_manifest)
   end subroutine write_stage2_v1_manifest

   subroutine write_stage2_v1_diagnostics_package(output_dir, slots, pair_stats, label_tracks)
      character(len=*), intent(in) :: output_dir
      type(tltm_slot_t), intent(in) :: slots(:)
      type(tltm_pair_stats_t), intent(in) :: pair_stats(:)
      type(tltm_label_track_t), intent(in) :: label_tracks(:)

      call write_stage2_v1_local_transition_csv(output_dir, slots)
      call write_stage2_v1_swap_summary_csv(output_dir, slots, pair_stats)
      call write_stage2_v1_label_summary_csv(output_dir, label_tracks)
      call write_stage2_v1_phase_summary_csv(output_dir, slots)
   end subroutine write_stage2_v1_diagnostics_package

   subroutine write_stage2_v1_local_transition_csv(output_dir, slots)
      character(len=*), intent(in) :: output_dir
      type(tltm_slot_t), intent(in) :: slots(:)
      character(len=512) :: csv_file
      integer :: unit_csv, ios, i, attempts
      logical :: path_ok

      call stage2_v1_package_path(output_dir, "diagnostics/local_transition_summary.csv", csv_file)
      call open_v1_csv(csv_file, unit_csv, path_ok, ios)
      if (.not. path_ok .or. ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open v1 local-transition CSV:", trim(csv_file)
         error stop 1
      end if

      write (unit_csv, '(A)') "slot_id,flow_time,attempt_count,accepted_count,metropolis_rejected_count," // &
         "proposal_construction_failed_count,reverse_gate_rejected_count,hamiltonian_invalid_count,delta_h_invalid_count," // &
         "output_size_mismatch_count,legacy_projection_failure_count,sample_count,runtime_sec"
      do i = 1, size(slots)
         attempts = slots(i)%local_accept_count + slots(i)%local_reject_count
         write (unit_csv, '(I0,A,ES23.15E3,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,ES23.15E3)') &
            slots(i)%slot_id, ",", slots(i)%flow_time, ",", attempts, ",", slots(i)%local_accept_count, ",", &
            slots(i)%metropolis_reject_count, ",", slots(i)%proposal_failure_count, ",", slots(i)%reverse_gate_reject_count, ",", &
            slots(i)%hamiltonian_invalid_count, ",", slots(i)%delta_h_invalid_count, ",", slots(i)%output_size_mismatch_count, ",", &
            slots(i)%projection_failure_count, ",", slots(i)%observable_samples, ",", slots(i)%local_runtime
      end do
      close (unit_csv)
   end subroutine write_stage2_v1_local_transition_csv

   subroutine write_stage2_v1_swap_summary_csv(output_dir, slots, pair_stats)
      character(len=*), intent(in) :: output_dir
      type(tltm_slot_t), intent(in) :: slots(:)
      type(tltm_pair_stats_t), intent(in) :: pair_stats(:)
      character(len=512) :: csv_file
      integer :: unit_csv, ios, i, idx_a, idx_b
      real(dp) :: accept_rate, flow_a, flow_b
      logical :: path_ok

      call stage2_v1_package_path(output_dir, "diagnostics/swap_summary.csv", csv_file)
      call open_v1_csv(csv_file, unit_csv, path_ok, ios)
      if (.not. path_ok .or. ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open v1 swap-summary CSV:", trim(csv_file)
         error stop 1
      end if

      write (unit_csv, '(A)') "pair_id,slot_a,slot_b,flow_time_a,flow_time_b,attempt_count,accepted_count,rejected_count," // &
         "accept_rate,last_accept_probability,invalid_current_energy_count,invalid_reflow_count,invalid_proposed_energy_count," // &
         "sweep_parity_policy"
      do i = 1, size(pair_stats)
         idx_a = pair_stats(i)%slot_a + 1
         idx_b = pair_stats(i)%slot_b + 1
         flow_a = 0.0_dp
         flow_b = 0.0_dp
         if (idx_a >= 1 .and. idx_a <= size(slots)) flow_a = slots(idx_a)%flow_time
         if (idx_b >= 1 .and. idx_b <= size(slots)) flow_b = slots(idx_b)%flow_time
         if (pair_stats(i)%proposal_count > 0) then
            accept_rate = real(pair_stats(i)%accept_count, dp)/real(pair_stats(i)%proposal_count, dp)
         else
            accept_rate = 0.0_dp
         end if
         write (unit_csv, '(I0,A,I0,A,I0,A,ES23.15E3,A,ES23.15E3,A,I0,A,I0,A,I0,A,ES23.15E3,A,ES23.15E3,A,A)') &
            pair_stats(i)%pair_id, ",", pair_stats(i)%slot_a, ",", pair_stats(i)%slot_b, ",", flow_a, ",", flow_b, ",", &
            pair_stats(i)%proposal_count, ",", pair_stats(i)%accept_count, ",", pair_stats(i)%reject_count, ",", &
            accept_rate, ",", pair_stats(i)%last_accept_probability, ",,,,v0_alternating_one_parity_per_cycle"
      end do
      close (unit_csv)
   end subroutine write_stage2_v1_swap_summary_csv

   subroutine write_stage2_v1_label_summary_csv(output_dir, label_tracks)
      character(len=*), intent(in) :: output_dir
      type(tltm_label_track_t), intent(in) :: label_tracks(:)
      character(len=512) :: csv_file
      integer :: unit_csv, ios, i
      real(dp) :: avg_round_trip
      logical :: path_ok

      call stage2_v1_package_path(output_dir, "diagnostics/label_summary.csv", csv_file)
      call open_v1_csv(csv_file, unit_csv, path_ok, ios)
      if (.not. path_ok .or. ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open v1 label-summary CSV:", trim(csv_file)
         error stop 1
      end if

      write (unit_csv, '(A)') "label_id,current_slot,farthest_slot_reached,round_trip_count,avg_round_trip_cycles,last_extreme"
      do i = 1, size(label_tracks)
         if (label_tracks(i)%round_trip_count > 0) then
            avg_round_trip = label_tracks(i)%round_trip_time_sum/real(label_tracks(i)%round_trip_count, dp)
         else
            avg_round_trip = 0.0_dp
         end if
         write (unit_csv, '(I0,A,I0,A,I0,A,I0,A,ES23.15E3,A,I0)') label_tracks(i)%label_id, ",", &
            label_tracks(i)%current_slot, ",", label_tracks(i)%farthest_slot_reached, ",", &
            label_tracks(i)%round_trip_count, ",", avg_round_trip, ",", label_tracks(i)%last_extreme_visited
      end do
      close (unit_csv)
   end subroutine write_stage2_v1_label_summary_csv

   subroutine write_stage2_v1_phase_summary_csv(output_dir, slots)
      character(len=*), intent(in) :: output_dir
      type(tltm_slot_t), intent(in) :: slots(:)
      character(len=512) :: csv_file
      integer :: unit_csv, ios, i
      complex(dp) :: mean_phi
      logical :: path_ok

      call stage2_v1_package_path(output_dir, "observables/per_slot_phase_summary.csv", csv_file)
      call open_v1_csv(csv_file, unit_csv, path_ok, ios)
      if (.not. path_ok .or. ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open v1 phase-summary CSV:", trim(csv_file)
         error stop 1
      end if

      write (unit_csv, '(A)') "slot_id,flow_time,n_samples,phase_mean_re,phase_mean_im,phase_abs_mean,sample_boundary"
      do i = 1, size(slots)
         if (slots(i)%observable_samples > 0) then
            mean_phi = slots(i)%phi_sum/real(slots(i)%observable_samples, dp)
         else
            mean_phi = cmplx(0.0_dp, 0.0_dp, dp)
         end if
         write (unit_csv, '(I0,A,ES23.15E3,A,I0,A,ES23.15E3,A,ES23.15E3,A,ES23.15E3,A,A)') &
            slots(i)%slot_id, ",", slots(i)%flow_time, ",", slots(i)%observable_samples, ",", &
            real(mean_phi, dp), ",", aimag(mean_phi), ",", abs(mean_phi), ",post_swap"
      end do
      close (unit_csv)
   end subroutine write_stage2_v1_phase_summary_csv

   subroutine stage2_v1_package_path(output_dir, relative_path, file_path)
      character(len=*), intent(in) :: output_dir, relative_path
      character(len=*), intent(out) :: file_path

      file_path = trim(output_dir)//"/"//trim(relative_path)
   end subroutine stage2_v1_package_path

   subroutine open_v1_csv(csv_file, unit_csv, path_ok, ios)
      character(len=*), intent(in) :: csv_file
      integer, intent(out) :: unit_csv, ios
      logical, intent(out) :: path_ok

      call ensure_parent_directory_exists(csv_file, path_ok)
      if (.not. path_ok) then
         ios = 1
         unit_csv = -1
         return
      end if
      open (newunit=unit_csv, file=trim(csv_file), status='replace', action='write', iostat=ios)
   end subroutine open_v1_csv

   subroutine write_stage2_v1_protocol(protocol_file)
      character(len=*), intent(in) :: protocol_file
      integer :: unit_protocol, ios
      logical :: path_ok

      call ensure_parent_directory_exists(protocol_file, path_ok)
      if (.not. path_ok) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot prepare v1 protocol path:", trim(protocol_file)
         error stop 1
      end if

      open (newunit=unit_protocol, file=trim(protocol_file), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][TLTM-S2] Cannot open v1 protocol file:", trim(protocol_file)
         error stop 1
      end if

      write (unit_protocol, '(A)') "{"
      call write_json_string_field(unit_protocol, "schema_version", "tltm.stage2.protocol.v1alpha1", .true.)
      call write_json_string_field(unit_protocol, "protocol_id", "stage2_replica_exchange_local_swap_measure", .true.)
      call write_json_string_field(unit_protocol, "tempering_parameter", "flow_time", .true.)
      call write_json_string_field(unit_protocol, "fixed_zone_identifier", "slot_id", .true.)
      call write_json_string_field(unit_protocol, "mobile_walker_identifier", "label_id", .true.)

      write (unit_protocol, '(A)') '  "target_density": {'
      call write_json_string_field(unit_protocol, "base_coordinate_density", "|det J_t(x)| * exp(-Re S(z_t(x)))", .true., 4)
      call write_json_string_field(unit_protocol, "effective_energy", "Re S(z_t(x)) - log |det J_t(x)|", .false., 4)
      write (unit_protocol, '(A)') '  },'

      write (unit_protocol, '(A)') '  "local_kernel": {'
      call write_json_string_field(unit_protocol, "kernel", "HMC/RATTLE on each fixed flowed surface", .true., 4)
      call write_json_string_field(unit_protocol, "rng_stream", "contract-selected; see manifest rng_stream_contract and seed_policy", .true., 4)
      call write_json_string_field(unit_protocol, "proposal_failure_semantics", "legal rejection; live slot state unchanged", .true., 4)
      call write_json_string_field(unit_protocol, "reverse_gate", "required for canonical p28 proposal validity", .true., 4)
      call write_json_string_field(unit_protocol, "final_flow_policy", "strict final flow constructs accepted proposal states", .false., 4)
      write (unit_protocol, '(A)') '  },'

      write (unit_protocol, '(A)') '  "swap_kernel": {'
      call write_json_string_field(unit_protocol, "proposal", "exchange base configurations between adjacent fixed flow-time slots", .true., 4)
      call write_json_string_field(unit_protocol, "acceptance_probability", "min(1, exp(-[(E_a(y)+E_b(x))-(E_a(x)+E_b(y))]))", .true., 4)
      call write_json_string_field(unit_protocol, "invalid_reflow_semantics", "reject swap; live slot states and labels unchanged", .true., 4)
      call write_json_string_field(unit_protocol, "rng_stream", "contract-selected; stage2_kernel_rng_v2 uses counter-based swap_accept keys", .true., 4)
      call write_json_string_field(unit_protocol, "rng_draw_boundary", "draw from swap stream only after finite current and proposed swap energies are available", .false., 4)
      write (unit_protocol, '(A)') '  },'

      write (unit_protocol, '(A)') '  "sweep_schedule": {'
      call write_json_string_field(unit_protocol, "cycle_order", "local_update_swap_measure_history_label_trace", .true., 4)
      call write_json_string_field(unit_protocol, "pairing", "one alternating adjacent-pair parity sub-sweep per cycle", .true., 4)
      call write_json_string_field(unit_protocol, "odd_cycles", "(0,1),(2,3),...", .true., 4)
      call write_json_string_field(unit_protocol, "even_cycles", "(1,2),(3,4),...", .false., 4)
      write (unit_protocol, '(A)') '  },'

      write (unit_protocol, '(A)') '  "measurement_policy": {'
      call write_json_string_field(unit_protocol, "sample_boundary", "post_swap", .true., 4)
      call write_json_string_field(unit_protocol, "label_trace_boundary", "post_swap", .true., 4)
      call write_json_string_field(unit_protocol, "status", "replica-exchange convention selected for regenerated datasets", .false., 4)
      write (unit_protocol, '(A)') '  },'

      write (unit_protocol, '(A)') '  "history_policy": {'
      call write_json_string_field(unit_protocol, "cold_history", "fixed max-flow slot sampled post-swap when enabled", .true., 4)
      call write_json_string_field(unit_protocol, "all_replica_history", "fixed slots sampled post-swap when enabled", .false., 4)
      write (unit_protocol, '(A)') '  },'

      write (unit_protocol, '(A)') '  "compatibility": {'
      call write_json_string_field(unit_protocol, "v0_summary", "field_names_preserved_timing_changed", .true., 4)
      call write_json_string_field(unit_protocol, "v0_label_trace", "field_names_preserved_timing_changed", .true., 4)
      call write_json_string_field(unit_protocol, "sidecar_default", "opt_in_only", .false., 4)
      write (unit_protocol, '(A)') '  }'
      write (unit_protocol, '(A)') "}"

      close (unit_protocol)
   end subroutine write_stage2_v1_protocol

   subroutine resolve_git_commit(git_commit)
      character(len=*), intent(out) :: git_commit

      git_commit = "unknown"
      call read_string_env("TLTM_GIT_COMMIT", git_commit)
   end subroutine resolve_git_commit

   subroutine write_json_string_field(unit_json, key, value, trailing_comma, indent)
      integer, intent(in) :: unit_json
      character(len=*), intent(in) :: key, value
      logical, intent(in) :: trailing_comma
      integer, intent(in), optional :: indent

      call write_json_indent(unit_json, indent)
      write (unit_json, '(A)', advance='no') '"'//json_escape(trim(key))//'": "'//json_escape(trim(value))//'"'
      call write_json_line_end(unit_json, trailing_comma)
   end subroutine write_json_string_field

   subroutine write_json_string_or_null_field(unit_json, key, value, has_value, trailing_comma, indent)
      integer, intent(in) :: unit_json
      character(len=*), intent(in) :: key, value
      logical, intent(in) :: has_value, trailing_comma
      integer, intent(in), optional :: indent

      call write_json_indent(unit_json, indent)
      if (has_value) then
         write (unit_json, '(A)', advance='no') '"'//json_escape(trim(key))//'": "'//json_escape(trim(value))//'"'
      else
         write (unit_json, '(A)', advance='no') '"'//json_escape(trim(key))//'": null'
      end if
      call write_json_line_end(unit_json, trailing_comma)
   end subroutine write_json_string_or_null_field

   subroutine write_json_env_field(unit_json, env_name, trailing_comma, indent)
      integer, intent(in) :: unit_json
      character(len=*), intent(in) :: env_name
      logical, intent(in) :: trailing_comma
      integer, intent(in), optional :: indent

      character(len=1024) :: env_value
      logical :: has_env_value

      env_value = ""
      call read_string_env(trim(env_name), env_value, has_env_value)
      call write_json_indent(unit_json, indent)
      if (has_env_value) then
         write (unit_json, '(A)', advance='no') '"'//json_escape(trim(env_name))//'": "'// &
            json_escape(trim(env_value))//'"'
      else
         write (unit_json, '(A)', advance='no') '"'//json_escape(trim(env_name))//'": null'
      end if
      call write_json_line_end(unit_json, trailing_comma)
   end subroutine write_json_env_field

   subroutine write_json_int_field(unit_json, key, value, trailing_comma, indent)
      integer, intent(in) :: unit_json
      character(len=*), intent(in) :: key
      integer, intent(in) :: value
      logical, intent(in) :: trailing_comma
      integer, intent(in), optional :: indent

      call write_json_indent(unit_json, indent)
      write (unit_json, '(A,I0)', advance='no') '"'//json_escape(trim(key))//'": ', value
      call write_json_line_end(unit_json, trailing_comma)
   end subroutine write_json_int_field

   subroutine write_json_real_field(unit_json, key, value, trailing_comma, indent)
      integer, intent(in) :: unit_json
      character(len=*), intent(in) :: key
      real(dp), intent(in) :: value
      logical, intent(in) :: trailing_comma
      integer, intent(in), optional :: indent

      character(len=64) :: number_text

      write (number_text, '(ES23.15E3)') value
      call write_json_indent(unit_json, indent)
      write (unit_json, '(A)', advance='no') '"'//json_escape(trim(key))//'": '//trim(adjustl(number_text))
      call write_json_line_end(unit_json, trailing_comma)
   end subroutine write_json_real_field

   subroutine write_json_logical_field(unit_json, key, value, trailing_comma, indent)
      integer, intent(in) :: unit_json
      character(len=*), intent(in) :: key
      logical, intent(in) :: value, trailing_comma
      integer, intent(in), optional :: indent

      call write_json_indent(unit_json, indent)
      if (value) then
         write (unit_json, '(A)', advance='no') '"'//json_escape(trim(key))//'": true'
      else
         write (unit_json, '(A)', advance='no') '"'//json_escape(trim(key))//'": false'
      end if
      call write_json_line_end(unit_json, trailing_comma)
   end subroutine write_json_logical_field

   subroutine write_json_real_array_field(unit_json, key, values, trailing_comma, indent)
      integer, intent(in) :: unit_json
      character(len=*), intent(in) :: key
      real(dp), intent(in) :: values(:)
      logical, intent(in) :: trailing_comma
      integer, intent(in), optional :: indent

      character(len=64) :: number_text
      integer :: i

      call write_json_indent(unit_json, indent)
      write (unit_json, '(A)', advance='no') '"'//json_escape(trim(key))//'": ['
      do i = 1, size(values)
         if (i > 1) write (unit_json, '(A)', advance='no') ', '
         write (number_text, '(ES23.15E3)') values(i)
         write (unit_json, '(A)', advance='no') trim(adjustl(number_text))
      end do
      write (unit_json, '(A)', advance='no') ']'
      call write_json_line_end(unit_json, trailing_comma)
   end subroutine write_json_real_array_field

   subroutine write_json_indent(unit_json, indent)
      integer, intent(in) :: unit_json
      integer, intent(in), optional :: indent
      integer :: indent_value

      indent_value = 2
      if (present(indent)) indent_value = indent
      if (indent_value > 0) write (unit_json, '(A)', advance='no') repeat(" ", indent_value)
   end subroutine write_json_indent

   subroutine write_json_line_end(unit_json, trailing_comma)
      integer, intent(in) :: unit_json
      logical, intent(in) :: trailing_comma

      if (trailing_comma) then
         write (unit_json, '(A)') ","
      else
         write (unit_json, '(A)') ""
      end if
   end subroutine write_json_line_end

   function json_escape(value) result(escaped)
      character(len=*), intent(in) :: value
      character(len=:), allocatable :: escaped
      character(len=1), parameter :: backslash = achar(92)
      integer :: i, out_len, pos

      out_len = 0
      do i = 1, len_trim(value)
         select case (value(i:i))
         case ('"', backslash)
            out_len = out_len + 2
         case default
            out_len = out_len + 1
         end select
      end do

      allocate (character(len=out_len) :: escaped)
      pos = 1
      do i = 1, len_trim(value)
         select case (value(i:i))
         case ('"')
            escaped(pos:pos) = backslash
            escaped(pos + 1:pos + 1) = '"'
            pos = pos + 2
         case (backslash)
            escaped(pos:pos) = backslash
            escaped(pos + 1:pos + 1) = backslash
            pos = pos + 2
         case default
            escaped(pos:pos) = value(i:i)
            pos = pos + 1
         end select
      end do
   end function json_escape

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

   integer function derive_swap_seed(base_seed) result(seed_value)
      integer, intent(in) :: base_seed

      seed_value = derive_seed(base_seed, 1000003)
   end function derive_swap_seed

   pure function stage2_seed_policy_text(rng_stream_contract) result(policy_text)
      character(len=*), intent(in) :: rng_stream_contract
      character(len=192) :: policy_text

      select case (trim(rng_stream_contract))
      case (stage2_rng_kernel_v2)
         policy_text = "CHAIN_RNG_SEED base seed plus Philox4x32-10 counter keys for each Stage2 draw"
      case (stage2_rng_legacy_global_v0)
         policy_text = "CHAIN_RNG_SEED base seed restored after initialization; local updates and swaps use shared serial MT95 stream"
      case default
         policy_text = "CHAIN_RNG_SEED base seed plus deterministic per-slot local-update streams and one swap stream"
      end select
   end function stage2_seed_policy_text

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

   subroutine release_all_run_contexts(run_contexts)
      type(tltm_run_context_t), allocatable, intent(inout) :: run_contexts(:)
      integer :: i

      if (.not. allocated(run_contexts)) return
      do i = 1, size(run_contexts)
         call release_tltm_run_context(run_contexts(i))
      end do
      deallocate (run_contexts)
   end subroutine release_all_run_contexts

end module tltm_stage2_driver

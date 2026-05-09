module markovchain_mod
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use runtime_env_mod, only: runtime_to_lower_ascii => to_lower_ascii
   use solve_flow, only: flow, &
                         get_intode_fallback_stats, &
                         get_intode_fallback_context_stats, &
                         get_intode_rescue_stats, &
                         intode_status_unknown, intode_status_is_strict_success
   use param_mod
   use, intrinsic :: iso_fortran_env, only: int64
   use hmc, only: integrate_hmc_warmup
   use model, only: grand
   use hmc_kernels, only: calculate_hamiltonian
   use markovchain_metropolis, only: metropolis_step
   use markovchain_phase, only: compute_phase_factor
   use markovchain_io, only: write_chain_snapshot
   use constraint_solver_stats_mod, only: reset_constraint_solver_stats, get_constraint_solver_stats, &
                                          get_constraint_near_rescue_stats, &
                                          get_constraint_solver_quasi_stage_stats, &
                                          get_constraint_solver_quasi_class_stats, &
                                          get_constraint_solver_far_route_stats, &
                                          get_constraint_solver_quasi_watchdog_stats, &
                                          get_constraint_solver_far_investment_stats, &
                                          set_constraint_solver_runtime_context
   use utils
   implicit none

contains

   subroutine run_markov_chain(chain_length, x_initial, total_step_size, num_steps, &
                               x_history_file, z_history_file, phi_history_file)
      implicit none

      integer, intent(in) :: chain_length
      real(dp), intent(in) :: x_initial(:)
      real(dp), intent(in) :: total_step_size
      integer, intent(in) :: num_steps
      character(len=*), intent(in) :: x_history_file, z_history_file, phi_history_file

      real(dp), allocatable :: x_state(:), x_trial(:), p_zero(:)
      complex(dp), allocatable :: z_state(:), z_trial(:)
      complex(dp), allocatable :: jac_state(:, :), jac_trial(:, :)
      real(dp) :: h_initial, h_proposed
      logical :: is_accepted, flow_failed, phase_error
      integer :: chain_idx, flow_status, state_size, hmc_repeat_idx
      integer :: accepted_trials, total_trials, warmup_iter
      integer :: io_status
      integer, parameter :: unit_x = 10, unit_z = 20, unit_phi = 30
      complex(dp) :: phase
      real(dp) :: start_time, now_time, elapsed_time
      real(dp) :: seconds_per_sample, eta_seconds, progress_percent, acceptance_rate

      state_size = size(x_initial)
      allocate (x_state(state_size), x_trial(state_size))
      allocate (z_state(state_size - 1), z_trial(state_size - 1))
      allocate (jac_state(state_size - 1, state_size - 1), jac_trial(state_size - 1, state_size - 1))
      allocate (p_zero(2*(state_size - 1)))
      accepted_trials = 0
      warmup_iter = 0
      call reset_constraint_solver_stats()

      open (unit=unit_x, file=x_history_file, status='replace', access='stream', form='unformatted', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Failed to open x-history output:", trim(x_history_file)
         error stop 1
      end if
      open (unit=unit_z, file=z_history_file, status='replace', access='stream', form='unformatted', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Failed to open z-history output:", trim(z_history_file)
         error stop 1
      end if
      open (unit=unit_phi, file=phi_history_file, status='replace', access='stream', form='unformatted', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Failed to open phi-history output:", trim(phi_history_file)
         error stop 1
      end if

      call print_chain_header(chain_length, total_step_size, num_steps)
      start_time = wall_time_seconds()

      x_state = x_initial
      flow_status = intode_status_unknown
      call flow(x_state, z_state, jac_state, flow_failed, flow_status)
      if (flow_failed .or. (.not. intode_status_is_strict_success(flow_status))) then
         write (*, '(A)') "[ERROR] Initial flow calculation failed."
         error stop 1
      end if

      p_zero = 0.0_dp
      call calculate_hamiltonian(z_state, p_zero, h_initial)
      h_proposed = h_initial*2.0_dp

      do while ((h_proposed < h_initial .or. warmup_iter < 5) .and. warmup_iter < n_warm)
         warmup_iter = warmup_iter + 1
         call integrate_hmc_warmup(x_state, z_state, total_step_size, num_steps, x_trial, z_trial, h_initial, h_proposed, jac_state, jac_trial)
         x_state = x_trial
         flow_status = intode_status_unknown
         call flow(x_state, z_state, jac_state, flow_failed, flow_status)
         if (flow_failed .or. (.not. intode_status_is_strict_success(flow_status))) then
            write (*, '(A,I0)') "[ERROR] Warmup flow failed at iteration ", warmup_iter
            error stop 1
         end if
         call print_warmup_status(warmup_iter, h_proposed)
      end do

      call compute_phase_factor(z_state, jac_state, phase, phase_error)
      if (phase_error) then
         write (*, '(A)') "[ERROR] Phase-factor computation failed at initial state."
         error stop 1
      end if
      call write_chain_snapshot(unit_x, unit_z, unit_phi, x_get_flow_time(x_state), z_state, phase, .false.)

      do chain_idx = 2, chain_length
         do hmc_repeat_idx = 1, hmc_step
            call set_constraint_solver_runtime_context(chain_idx, hmc_repeat_idx)
            call metropolis_step(x_state, z_state, jac_state, total_step_size, num_steps, &
                                 x_trial, z_trial, jac_trial, is_accepted)

            if (is_accepted) then
               x_state = x_trial
               z_state = z_trial
               jac_state = jac_trial
               accepted_trials = accepted_trials + 1
            end if
         end do

         call compute_phase_factor(z_state, jac_state, phase, phase_error)
         if (phase_error) then
            write (*, '(A,I0)') "[ERROR] Phase-factor computation failed at chain index ", chain_idx
            error stop 1
         end if
         call write_chain_snapshot(unit_x, unit_z, unit_phi, x_get_flow_time(x_state), z_state, phase, .true.)

         if (mod(chain_idx, 10) == 0) then
            now_time = wall_time_seconds()
            elapsed_time = now_time - start_time
            seconds_per_sample = elapsed_time/real(chain_idx, dp)
            eta_seconds = seconds_per_sample*real(chain_length - chain_idx, dp)
            progress_percent = 100.0_dp*real(chain_idx, dp)/real(chain_length, dp)
            total_trials = (chain_idx - 1)*hmc_step
            if (total_trials > 0) then
               acceptance_rate = real(accepted_trials, dp)/real(total_trials, dp)
            else
               acceptance_rate = 0.0_dp
            end if
            call print_chain_progress(chain_idx, chain_length, progress_percent, elapsed_time, eta_seconds, acceptance_rate, cttol)
            ckrv = .true.
         end if
      end do

      close (unit_x)
      close (unit_z)
      close (unit_phi)

      total_trials = (chain_length - 1)*hmc_step
      if (total_trials > 0) then
         acceptance_rate = real(accepted_trials, dp)/real(total_trials, dp)
      else
         acceptance_rate = 0.0_dp
      end if
      call print_chain_summary(acceptance_rate)
   end subroutine run_markov_chain

   ! Backward-compatible name kept for existing call sites.
   subroutine generate_markov_chain(chain_length, x_initial, total_step_size, num_steps, &
                                    x_history_file, z_history_file, phi_history_file)
      implicit none
      integer, intent(in) :: chain_length
      real(dp), intent(in) :: x_initial(:)
      real(dp), intent(in) :: total_step_size
      integer, intent(in) :: num_steps
      character(len=*), intent(in) :: x_history_file, z_history_file, phi_history_file

      call run_markov_chain(chain_length, x_initial, total_step_size, num_steps, &
                            x_history_file, z_history_file, phi_history_file)
   end subroutine generate_markov_chain

   subroutine execute_generate_markov_chain()
      implicit none
      real(dp), allocatable :: x_initial(:)

      if (state_total_size() < 2) then
         write (*, '(A,I0)') "[ERROR] Invalid configured state size: ", state_total_size()
         error stop 1
      end if

      if (config%integrator%initial_flow_time < 0.0_dp) then
         write (*, '(A,ES12.4)') "[ERROR] initial_flow_time must be >= 0. Got ", config%integrator%initial_flow_time
         error stop 1
      end if

      allocate (x_initial(state_total_size()))
      call initialize_random_start(x_initial)
      call set_initial_flow_time(x_get_flow_time(x_initial))

      call run_markov_chain(config%chain%length, x_initial, config%integrator%trajectory_length, &
                            config%integrator%integration_steps, config%io%x_history_file, &
                            config%io%z_history_file, config%io%phi_history_file)
      write (*, '(A,1X,A,1X,A,1X,A)') "[DONE] Markov chain generation complete. outputs:", &
         trim(x_history_file), trim(z_history_file), trim(phi_history_file)

      if (allocated(x_initial)) deallocate (x_initial)
   end subroutine execute_generate_markov_chain

   subroutine initialize_random_start(x_initial)
      implicit none
      real(dp), intent(out) :: x_initial(:)

      real(dp), parameter :: random_seed_sigma = 0.10_dp
      integer, parameter :: max_start_attempts = 200
      integer :: attempt, n_seed, stage_count
      real(dp), allocatable :: x_seed(:), x_state(:)
      logical :: success
      real(dp) :: target_flow_time_base
      integer :: relax_level
      logical :: fixed_retry_target
      real(dp) :: retry_shrink
      character(len=64) :: env_value, token
      integer :: env_len, env_stat, ios

      if (size(x_initial) < 2) then
         write (*, '(A)') "[ERROR] initialize_random_start requires x size >= 2."
         error stop 1
      end if

      n_seed = size(x_initial) - 1
      target_flow_time_base = config%integrator%initial_flow_time
      fixed_retry_target = .true.
      retry_shrink = 0.85_dp

      call get_environment_variable("RANDOM_START_FIXED_TARGET", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         token = runtime_to_lower_ascii(adjustl(env_value(1:env_len)))
         select case (trim(token))
         case ("0", "off", "false", "no")
            fixed_retry_target = .false.
         case default
            fixed_retry_target = .true.
         end select
      end if

      call get_environment_variable("RANDOM_START_RETRY_SHRINK", env_value, length=env_len, status=env_stat)
      if (env_stat == 0 .and. env_len > 0) then
         read (env_value(1:env_len), *, iostat=ios) retry_shrink
         if (ios /= 0 .or. retry_shrink <= 0.0_dp .or. retry_shrink >= 1.0_dp) retry_shrink = 0.85_dp
      end if

      allocate (x_seed(n_seed), x_state(size(x_initial)))

      attempt = 0
      relax_level = 0
      do
         attempt = attempt + 1
         call grand(x_seed)
         x_seed = random_seed_sigma*x_seed
         call x_set_flow_time(x_state, 0.0_dp)
         call x_set_seed_real(x_state, x_seed)

         if (target_flow_time_base <= 0.0_dp) then
            x_initial = x_state
            write (*, '(A,I0,A,ES12.4)') "[INIT] Random start ready without pre-flow: attempt=", attempt, &
               " target_flow_time=", target_flow_time_base
            deallocate (x_seed, x_state)
            return
         end if

         call adaptive_preflow_to_target(x_state, target_flow_time_base, config%integrator%trajectory_length, &
                                         config%integrator%integration_steps, relax_level, success, stage_count)
         if (success) then
            x_initial = x_state
            write (*, '(A,I0,A,I0,A,F10.6)') "[INIT] Adaptive random start succeeded: attempt=", attempt, &
               " stages=", stage_count, " flow_time=", x_get_flow_time(x_initial)
            deallocate (x_seed, x_state)
            return
         end if

         if (attempt >= max_start_attempts) then
            write (*, '(A,I0,A,F10.6)') "[ERROR] Random start failed after attempts=", attempt, &
               " at fixed target_flow_time=", target_flow_time_base
            error stop 1
         end if
         relax_level = relax_level + 1
         if (.not. fixed_retry_target) target_flow_time_base = retry_shrink*target_flow_time_base
         if (fixed_retry_target) then
            write (*, '(A,I0,A,F10.6,A,I0)') "[WARN] Random start attempt ", attempt, &
               " failed. Retrying with fixed flow_time=", target_flow_time_base, " relax_level=", relax_level
         else
            write (*, '(A,I0,A,F10.6,A,I0)') "[WARN] Random start attempt ", attempt, &
               " failed. Retrying with flow_time=", target_flow_time_base, " relax_level=", relax_level
         end if
      end do
   end subroutine initialize_random_start

   subroutine adaptive_preflow_to_target(x_state, target_flow_time, trajectory_length, integration_steps, relax_level, success, stage_count)
      implicit none
      real(dp), intent(inout) :: x_state(:)
      real(dp), intent(in) :: target_flow_time, trajectory_length
      integer, intent(in) :: integration_steps, relax_level
      logical, intent(out) :: success
      integer, intent(out) :: stage_count

      real(dp), parameter :: near_zero_tol = 1.0e-12_dp
      real(dp), parameter :: min_dt_floor = 1.0e-8_dp
      real(dp), parameter :: action_rel_tol_base = 5.0e-3_dp
      real(dp), parameter :: action_rel_tol_cap = 5.0e-2_dp
      integer, parameter :: max_relax_iter_base = 24
      integer, parameter :: max_relax_iter_cap = 96
      real(dp), parameter :: step_shrink = 0.5_dp
      real(dp), parameter :: step_grow_base = 1.25_dp

      integer :: flow_status, n_seed, relax_steps, relax_iter, relax_level_local, max_relax_iter
      real(dp) :: t_current, t_next, dt_try, dt_min, dt_max
      real(dp) :: relax_step_size, action_delta, action_rel_tol, step_grow, relax_scale
      real(dp), allocatable :: x_candidate(:)
      complex(dp), allocatable :: z_candidate(:), jac_candidate(:, :)
      logical :: flow_failed, relax_ok

      success = .false.
      stage_count = 0

      if (target_flow_time <= near_zero_tol) then
         call x_set_flow_time(x_state, 0.0_dp)
         success = .true.
         return
      end if

      n_seed = size(x_state) - 1
      allocate (x_candidate(size(x_state)))
      allocate (z_candidate(n_seed), jac_candidate(n_seed, n_seed))

      relax_level_local = max(0, relax_level)
      relax_scale = 1.0_dp + 0.20_dp*real(relax_level_local, dp)
      action_rel_tol = min(action_rel_tol_cap, action_rel_tol_base*relax_scale)
      max_relax_iter = min(max_relax_iter_cap, max_relax_iter_base + 4*relax_level_local)
      step_grow = max(1.05_dp, step_grow_base - 0.02_dp*real(relax_level_local, dp))

      relax_step_size = max(0.005_dp, min(0.20_dp, 0.10_dp*trajectory_length/relax_scale))
      relax_steps = max(2, min(48, integration_steps + 2*relax_level_local))

      dt_max = max(0.01_dp, 0.25_dp*target_flow_time/relax_scale)
      dt_try = min(dt_max, max(2.5e-5_dp, target_flow_time/(16.0_dp*relax_scale)))
      dt_min = max(min_dt_floor, 1.0e-6_dp*target_flow_time)

      t_current = 0.0_dp
      do while (t_current < target_flow_time - near_zero_tol)
         do
            if (dt_try < dt_min) then
               deallocate (x_candidate, z_candidate, jac_candidate)
               return
            end if

            t_next = min(target_flow_time, t_current + dt_try)
            x_candidate = x_state
            call x_set_flow_time(x_candidate, t_next)
            flow_status = intode_status_unknown
            call flow(x_candidate, z_candidate, jac_candidate, flow_failed, flow_status)
            if (flow_failed .or. (.not. intode_status_is_strict_success(flow_status))) then
               dt_try = dt_try*step_shrink
               cycle
            end if

            call relax_with_zero_momentum(x_candidate, z_candidate, jac_candidate, relax_step_size, relax_steps, &
                                          action_rel_tol, max_relax_iter, relax_ok, action_delta, relax_iter)
            if (.not. relax_ok) then
               dt_try = dt_try*step_shrink
               cycle
            end if

            exit
         end do

         x_state = x_candidate
         t_current = t_next
         stage_count = stage_count + 1
         write (*, '(A,I0,A,F10.6,A,F10.6,A,ES11.3,A,I0)') "[INIT] preflow stage=", stage_count, &
            " t=", t_current, " dt=", dt_try, " dS=", action_delta, " relax=", relax_iter

         if (relax_iter <= 2) then
            dt_try = min(dt_try*step_grow, dt_max)
         else if (relax_iter >= max_relax_iter - 1) then
            dt_try = max(0.8_dp*dt_try, dt_min)
         end if
      end do

      call x_set_flow_time(x_state, target_flow_time)
      success = .true.
      deallocate (x_candidate, z_candidate, jac_candidate)
   end subroutine adaptive_preflow_to_target

   subroutine relax_with_zero_momentum(x_state, z_state, jac_state, step_size, num_steps, action_rel_tol, max_iter, &
                                       success, action_delta, iter_used)
      implicit none
      real(dp), intent(inout) :: x_state(:)
      complex(dp), intent(inout) :: z_state(:), jac_state(:, :)
      real(dp), intent(in) :: step_size, action_rel_tol
      integer, intent(in) :: num_steps, max_iter
      logical, intent(out) :: success
      real(dp), intent(out) :: action_delta
      integer, intent(out) :: iter_used

      real(dp), allocatable :: x_trial(:)
      complex(dp), allocatable :: z_trial(:), jac_trial(:, :)
      real(dp) :: h_initial, h_proposed, action_scale
      integer :: iter

      allocate (x_trial(size(x_state)))
      allocate (z_trial(size(z_state)))
      allocate (jac_trial(size(jac_state, 1), size(jac_state, 2)))

      success = .false.
      action_delta = huge(1.0_dp)
      iter_used = 0

      do iter = 1, max_iter
         call integrate_hmc_warmup(x_state, z_state, step_size, num_steps, x_trial, z_trial, h_initial, h_proposed, jac_state, jac_trial)
         if ((.not. ieee_is_finite(h_initial)) .or. (.not. ieee_is_finite(h_proposed))) exit

         action_delta = abs(h_proposed - h_initial)
         action_scale = max(1.0_dp, abs(h_initial))

         x_state = x_trial
         z_state = z_trial
         jac_state = jac_trial
         iter_used = iter

         if (action_delta <= action_rel_tol*action_scale) then
            success = .true.
            exit
         end if
      end do

      deallocate (x_trial, z_trial, jac_trial)
   end subroutine relax_with_zero_momentum

   subroutine print_chain_header(chain_length, step_size, num_steps)
      implicit none
      integer, intent(in) :: chain_length, num_steps
      real(dp), intent(in) :: step_size

      write (*, '(A,I0,A,F8.3,A,I0,A,A)') "[CHAIN] length=", chain_length, " traj=", step_size, &
         " steps=", num_steps, " integrator=", trim(integrator_method)
      write (*, '(A,L1)') "[CHAIN] enable_quasi_fallback=", quasi_fallback_enabled
   end subroutine print_chain_header

   subroutine print_warmup_status(iter_idx, h_proposed)
      implicit none
      integer, intent(in) :: iter_idx
      real(dp), intent(in) :: h_proposed

      write (*, '(A,I0,A,ES14.6)') "[WARMUP] iter=", iter_idx, " proposed_H=", h_proposed
   end subroutine print_warmup_status

   subroutine print_chain_progress(chain_idx, chain_length, progress_percent, elapsed_time, eta_seconds, acceptance_rate, constraint_tol)
      implicit none
      integer, intent(in) :: chain_idx, chain_length
      real(dp), intent(in) :: progress_percent, elapsed_time, eta_seconds, acceptance_rate, constraint_tol
      integer(int64) :: total_count, newton_count, quasi_count, failed_count
      integer(int64) :: near_candidate_count, far_count
      integer(int64) :: near_attempt_count, near_success_count, near_unusable_cert_count
      integer(int64) :: near_fail_fast_unsolvable_count
      integer(int64) :: far_fail_fast_unsolvable_count
      integer(int64) :: class_local_count, class_mid_count, class_global_count
      integer(int64) :: far_route_skip_count, far_route_light_count, far_route_anchor_count
      integer(int64) :: watchdog_hit_count, watchdog_used_sum
      integer(int64) :: far_scope_count, far_success_count, far_fail_case_count, far_fail_fast_case_count
      integer(int64) :: far_spent_success_count, far_spent_fail_count
      integer(int64) :: far_flowzr_used_sum, far_final_resort_used_sum
      integer(int64) :: far_flowzr_used_success_sum, far_final_resort_used_success_sum
      integer(int64) :: far_flowzr_used_fail_sum, far_final_resort_used_fail_sum
      integer :: intode_calls_total, intode_calls_integrating
      integer :: intode_fallback_attempts, intode_fallback_success, intode_fallback_failure
      integer :: intode_fallback_max_steps, intode_fallback_invalid, intode_fallback_h_min
      integer :: intode_success_radau_adaptive, intode_success_radau_adaptive_robust
      integer :: intode_success_radau_fixed_tol, intode_success_radau_chunked, intode_success_final_resort
      integer :: intode_fail_radau_adaptive_robust, intode_fail_radau_fixed_tol, intode_fail_radau_chunked, intode_fail_final_resort
      integer :: attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown
      integer :: fail_flowz, fail_flowzr, fail_flow, fail_unknown
      integer :: watchdog_used_max, watchdog_budget_last
      integer :: flow_fallback, inner_fallback, inner_hard_fail
      integer :: radau_rescue_ok, radau_rescue_fail, radau_rescue_fail_only, resort_reject
      real(dp) :: newton_ratio, quasi_ratio, fail_ratio, fallback_rate
      real(dp) :: flow_hard_fail_rate, inner_hard_fail_rate, watchdog_used_avg
      real(dp) :: far_case_success_share, far_unit_success_share
      real(dp) :: far_units_total, far_units_success

      call get_constraint_solver_stats(total_count, newton_count, quasi_count, failed_count, &
                                       newton_ratio, quasi_ratio, fail_ratio)
      call get_constraint_near_rescue_stats(near_candidate_count, far_count, near_attempt_count, near_success_count, &
                                            near_unusable_cert_count, near_fail_fast_unsolvable_count, &
                                            far_fail_fast_unsolvable_count)
      call get_constraint_solver_quasi_class_stats(class_local_count, class_mid_count, class_global_count)
      call get_constraint_solver_far_route_stats(far_route_skip_count, far_route_light_count, far_route_anchor_count)
      call get_constraint_solver_quasi_watchdog_stats(watchdog_hit_count, watchdog_used_sum, watchdog_used_max, watchdog_budget_last)
      call get_constraint_solver_far_investment_stats(far_scope_count, far_success_count, far_fail_case_count, &
                                                      far_fail_fast_case_count, far_spent_success_count, far_spent_fail_count, &
                                                      far_flowzr_used_sum, far_final_resort_used_sum, &
                                                      far_flowzr_used_success_sum, far_final_resort_used_success_sum, &
                                                      far_flowzr_used_fail_sum, far_final_resort_used_fail_sum)
      call get_intode_fallback_stats(intode_calls_total, intode_calls_integrating, intode_fallback_attempts, &
                                     intode_fallback_success, intode_fallback_failure, intode_fallback_max_steps, &
                                     intode_fallback_invalid, intode_fallback_h_min)
      call get_intode_rescue_stats(intode_success_radau_adaptive, intode_success_radau_adaptive_robust, &
                                   intode_success_radau_fixed_tol, intode_success_radau_chunked, &
                                   intode_success_final_resort, intode_fail_radau_adaptive_robust, &
                                   intode_fail_radau_fixed_tol, intode_fail_radau_chunked, intode_fail_final_resort)
      call get_intode_fallback_context_stats(attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                             fail_flowz, fail_flowzr, fail_flow, fail_unknown)
      if (intode_calls_integrating > 0) then
         fallback_rate = 100.0_dp*real(intode_fallback_attempts, dp)/real(intode_calls_integrating, dp)
      else
         fallback_rate = 0.0_dp
      end if
      flow_fallback = attempt_flow
      inner_fallback = attempt_flowz + attempt_flowzr
      inner_hard_fail = fail_flowz + fail_flowzr
      radau_rescue_ok = intode_success_radau_adaptive + intode_success_radau_adaptive_robust + &
                        intode_success_radau_fixed_tol + intode_success_radau_chunked
      radau_rescue_fail_only = intode_fail_radau_adaptive_robust + intode_fail_radau_fixed_tol + intode_fail_radau_chunked
      resort_reject = intode_fail_final_resort
      radau_rescue_fail = intode_fail_radau_adaptive_robust + intode_fail_radau_fixed_tol + &
                          intode_fail_radau_chunked + intode_fail_final_resort
      if (flow_fallback > 0) then
         flow_hard_fail_rate = 100.0_dp*real(fail_flow, dp)/real(flow_fallback, dp)
      else
         flow_hard_fail_rate = 0.0_dp
      end if
      if (inner_fallback > 0) then
         inner_hard_fail_rate = 100.0_dp*real(inner_hard_fail, dp)/real(inner_fallback, dp)
      else
         inner_hard_fail_rate = 0.0_dp
      end if
      if (watchdog_hit_count > 0_int64) then
         watchdog_used_avg = real(watchdog_used_sum, dp)/real(watchdog_hit_count, dp)
      else
         watchdog_used_avg = 0.0_dp
      end if
      if (far_scope_count > 0_int64) then
         far_case_success_share = real(far_success_count, dp)/real(far_scope_count, dp)
      else
         far_case_success_share = 0.0_dp
      end if
      far_units_total = real(far_flowzr_used_sum + far_final_resort_used_sum, dp)
      far_units_success = real(far_flowzr_used_success_sum + far_final_resort_used_success_sum, dp)
      if (far_units_total > 0.0_dp) then
         far_unit_success_share = far_units_success/far_units_total
      else
         far_unit_success_share = 0.0_dp
      end if
      write (*, '(A,I0,A,I0,A,F6.2,A,F8.5,A,F9.2,A,F9.2,A)') "[PROGRESS] ", chain_idx, "/", chain_length, &
         " (", progress_percent, "%) acc=", acceptance_rate, " elapsed=", elapsed_time, "s eta=", eta_seconds, "s"
      write (*, '(A,I0,A,I0,A,F6.2,A,A,I0,A,I0,A,F6.2,A,A,I0,A,I0,A,F6.2,A,A,F6.2,A,I0,A,I0,A,I0,A,I0,A,ES9.2)') &
         "           newton=", newton_count, "/", total_count, " (", 100.0_dp*newton_ratio, "%)", &
         " quasi=", quasi_count, "/", total_count, " (", 100.0_dp*quasi_ratio, "%)", &
         " fail=", failed_count, "/", total_count, " (", 100.0_dp*fail_ratio, "%)", &
         " fb=", fallback_rate, "% inner_resort=", intode_success_final_resort, " radau_ok=", radau_rescue_ok, &
         " radau_ng=", radau_rescue_fail, " hard_fail=", intode_fallback_failure, " cttol=", constraint_tol
      write (*, '(A,I0,A,I0,A,F6.2,A,A,I0,A,I0,A,F6.2,A,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') "           flow_hard_fail=", fail_flow, &
         "/", flow_fallback, " (", flow_hard_fail_rate, "%)", " inner_hard_fail=", inner_hard_fail, "/", inner_fallback, &
         " (", inner_hard_fail_rate, "%)", " inner_fb=", inner_fallback, " flowz_fb=", attempt_flowz, &
         " flowzr_fb=", attempt_flowzr, " unknown_fb=", attempt_unknown, " unknown_hard_fail=", fail_unknown
      write (*, '(A,I0,A,I0,A,I0)') "           radau_fail=", radau_rescue_fail_only, " resort_reject=", resort_reject, &
         " flow_fb=", flow_fallback
      write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') "           near_fail=", near_candidate_count, " near_try=", near_attempt_count, &
         " near_ok=", near_success_count, " near_unusable=", near_unusable_cert_count, &
         " near_fail_fast=", near_fail_fast_unsolvable_count, &
         " far_fail_fast=", far_fail_fast_unsolvable_count, " far_fail=", far_count
      write (*, '(A,I0,A,I0,A,I0)') "           quasi_class local=", class_local_count, " mid=", class_mid_count, &
         " global=", class_global_count
      write (*, '(A,I0,A,I0,A,I0)') "           quasi_far_route skip=", far_route_skip_count, &
         " light=", far_route_light_count, " anchor=", far_route_anchor_count
      write (*, '(A,I0,A,I0,A,F10.2,A,I0)') "           quasi_watchdog hits=", watchdog_hit_count, &
         " max_used=", watchdog_used_max, " avg_used=", watchdog_used_avg, " budget_last=", watchdog_budget_last
      write (*, '(A,I0,A,I0,A,I0,A,I0,A,F7.4,A,F7.4)') "           far_invest cases=", far_scope_count, &
         " success=", far_success_count, " fail=", far_fail_case_count, " fail_fast=", far_fail_fast_case_count, &
         " case_share=", far_case_success_share, " unit_share=", far_unit_success_share
      write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') "           far_units flowzr=", far_flowzr_used_sum, &
         " final=", far_final_resort_used_sum, " success_flowzr=", far_flowzr_used_success_sum, &
         " success_final=", far_final_resort_used_success_sum, " fail_flowzr=", far_flowzr_used_fail_sum, &
         " fail_final=", far_final_resort_used_fail_sum
      write (*, '(A,I0,A,I0)') "           far_spent_cases success=", far_spent_success_count, &
         " fail=", far_spent_fail_count
   end subroutine print_chain_progress

   subroutine print_chain_summary(acceptance_rate)
      implicit none
      real(dp), intent(in) :: acceptance_rate
      integer(int64) :: total_count, newton_count, quasi_count, failed_count
      integer(int64) :: quasi_probe_attempt_count, quasi_probe_success_count
      integer(int64) :: quasi_full_attempt_count, quasi_full_success_count
      integer(int64) :: quasi_class_local_count, quasi_class_mid_count, quasi_class_global_count
      integer(int64) :: far_route_skip_count, far_route_light_count, far_route_anchor_count
      integer(int64) :: watchdog_hit_count, watchdog_used_sum
      integer(int64) :: far_scope_count, far_success_count, far_fail_case_count, far_fail_fast_case_count
      integer(int64) :: far_spent_success_count, far_spent_fail_count
      integer(int64) :: far_flowzr_used_sum, far_final_resort_used_sum
      integer(int64) :: far_flowzr_used_success_sum, far_final_resort_used_success_sum
      integer(int64) :: far_flowzr_used_fail_sum, far_final_resort_used_fail_sum
      integer :: watchdog_used_max, watchdog_budget_last
      real(dp) :: newton_ratio, quasi_ratio, fail_ratio, watchdog_used_avg
      real(dp) :: far_case_success_share, far_unit_success_share
      real(dp) :: far_units_total, far_units_success

      write (*, '(A,F8.5)') "[SUMMARY] acceptance=", acceptance_rate
      call get_constraint_solver_stats(total_count, newton_count, quasi_count, failed_count, &
                                       newton_ratio, quasi_ratio, fail_ratio)
      write (*, '(A,I0,A,I0,A,I0,A,I0)') "[SUMMARY] solver attempts=", total_count, " newton=", newton_count, &
         " quasi=", quasi_count, " fail=", failed_count
      call get_constraint_solver_quasi_stage_stats(quasi_probe_attempt_count, quasi_probe_success_count, &
                                                   quasi_full_attempt_count, quasi_full_success_count)
      call get_constraint_solver_quasi_class_stats(quasi_class_local_count, quasi_class_mid_count, quasi_class_global_count)
      call get_constraint_solver_far_route_stats(far_route_skip_count, far_route_light_count, far_route_anchor_count)
      call get_constraint_solver_quasi_watchdog_stats(watchdog_hit_count, watchdog_used_sum, watchdog_used_max, watchdog_budget_last)
      call get_constraint_solver_far_investment_stats(far_scope_count, far_success_count, far_fail_case_count, &
                                                      far_fail_fast_case_count, far_spent_success_count, far_spent_fail_count, &
                                                      far_flowzr_used_sum, far_final_resort_used_sum, &
                                                      far_flowzr_used_success_sum, far_final_resort_used_success_sum, &
                                                      far_flowzr_used_fail_sum, far_final_resort_used_fail_sum)
      if (watchdog_hit_count > 0_int64) then
         watchdog_used_avg = real(watchdog_used_sum, dp)/real(watchdog_hit_count, dp)
      else
         watchdog_used_avg = 0.0_dp
      end if
      if (far_scope_count > 0_int64) then
         far_case_success_share = real(far_success_count, dp)/real(far_scope_count, dp)
      else
         far_case_success_share = 0.0_dp
      end if
      far_units_total = real(far_flowzr_used_sum + far_final_resort_used_sum, dp)
      far_units_success = real(far_flowzr_used_success_sum + far_final_resort_used_success_sum, dp)
      if (far_units_total > 0.0_dp) then
         far_unit_success_share = far_units_success/far_units_total
      else
         far_unit_success_share = 0.0_dp
      end if
      write (*, '(A,I0,A,I0,A,I0,A,I0)') "[SUMMARY] quasi stage probe=", &
         quasi_probe_success_count, "/", quasi_probe_attempt_count, " full=", quasi_full_success_count, "/", quasi_full_attempt_count
      write (*, '(A,I0,A,I0,A,I0)') "[SUMMARY] quasi class local=", quasi_class_local_count, &
         " mid=", quasi_class_mid_count, " global=", quasi_class_global_count
      write (*, '(A,I0,A,I0,A,I0)') "[SUMMARY] quasi far_route skip=", far_route_skip_count, &
         " light=", far_route_light_count, " anchor=", far_route_anchor_count
      write (*, '(A,I0,A,I0,A,F10.2,A,I0)') "[SUMMARY] quasi_watchdog hits=", watchdog_hit_count, &
         " max_used=", watchdog_used_max, " avg_used=", watchdog_used_avg, " budget_last=", watchdog_budget_last
      write (*, '(A,I0,A,I0,A,I0,A,I0,A,F7.4,A,F7.4)') "[SUMMARY] far_invest cases=", far_scope_count, &
         " success=", far_success_count, " fail=", far_fail_case_count, " fail_fast=", far_fail_fast_case_count, &
         " case_share=", far_case_success_share, " unit_share=", far_unit_success_share
      write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)') "[SUMMARY] far_units flowzr=", far_flowzr_used_sum, &
         " final=", far_final_resort_used_sum, " success_flowzr=", far_flowzr_used_success_sum, &
         " success_final=", far_final_resort_used_success_sum, " fail_flowzr=", far_flowzr_used_fail_sum, &
         " fail_final=", far_final_resort_used_fail_sum
      write (*, '(A,I0,A,I0)') "[SUMMARY] far_spent_cases success=", far_spent_success_count, &
         " fail=", far_spent_fail_count
   end subroutine print_chain_summary

end module markovchain_mod

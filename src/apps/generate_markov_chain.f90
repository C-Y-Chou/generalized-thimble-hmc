program generate_markov_chain_app
   use param_mod, only: read_parameters
   use runtime_env_mod, only: read_string_env
   use utils, only: dp
   use markovchain_mod, only: execute_generate_markov_chain
   use mt95, only: getseed, sgrnd
   use solve_flow, only: get_intode_solver_assist_policy, &
                         reset_intode_fallback_stats, get_intode_fallback_stats, &
                         get_intode_rescue_stats
   implicit none

   integer :: rng_seed
   integer :: io_status
   integer :: calls_total, calls_integrating
   integer :: fallback_attempts, fallback_success, fallback_failure
   integer :: fallback_max_steps, fallback_invalid, fallback_h_min
   integer :: success_radau_adaptive, success_radau_adaptive_robust
   integer :: success_radau_fixed_tol, success_radau_chunked, success_solver_assist
   integer :: fail_radau_adaptive_robust, fail_radau_fixed_tol, fail_radau_chunked, fail_solver_assist
   integer :: rescue_fail_total
   logical :: solver_assist_enabled, fast_hmin_assist, solver_assist_unlimited
   integer :: solver_assist_max_uses
   logical :: has_seed_env
   character(len=64) :: seed_env
   real(dp) :: fallback_rate

   seed_env = ""
   call read_string_env("CHAIN_RNG_SEED", seed_env, has_seed_env)
   if (has_seed_env) then
      read (seed_env, *, iostat=io_status) rng_seed
      if (io_status /= 0 .or. rng_seed == 0) then
         rng_seed = getseed()
         write (*, '(A,A,A,I0)') "[RNG] Invalid CHAIN_RNG_SEED='", trim(seed_env), "'. Using random seed=", rng_seed
      else
         write (*, '(A,I0)') "[RNG] Using fixed CHAIN_RNG_SEED=", rng_seed
      end if
   else
      rng_seed = getseed()
      write (*, '(A,I0)') "[RNG] Using random seed=", rng_seed
   end if
   call sgrnd(rng_seed)

   call read_parameters()
   call get_intode_solver_assist_policy(solver_assist_enabled, solver_assist_max_uses, fast_hmin_assist)
   solver_assist_unlimited = (solver_assist_max_uses <= 0)
   write (*, '(A,L1,A,L1,A,L1)') "[INTODE] final_flow_strict=", .true., " solver_assist=", solver_assist_enabled, &
      " solver_assist_unlimited=", solver_assist_unlimited
   call reset_intode_fallback_stats()
   call execute_generate_markov_chain()

   call get_intode_fallback_stats(calls_total, calls_integrating, fallback_attempts, fallback_success, fallback_failure, &
                                  fallback_max_steps, fallback_invalid, fallback_h_min)
   call get_intode_rescue_stats(success_radau_adaptive, success_radau_adaptive_robust, success_radau_fixed_tol, &
                                success_radau_chunked, success_solver_assist, fail_radau_adaptive_robust, &
                                fail_radau_fixed_tol, fail_radau_chunked, fail_solver_assist)
   rescue_fail_total = fail_radau_adaptive_robust + fail_radau_fixed_tol + fail_radau_chunked + fail_solver_assist
   if (calls_integrating > 0) then
      fallback_rate = 100.0_dp*real(fallback_attempts, dp)/real(calls_integrating, dp)
   else
      fallback_rate = 0.0_dp
   end if
   write (*, '(A,I0,A,I0,A,F7.3,A,I0,A,I0,A,I0)') "[INTODE] fallback=", fallback_attempts, "/", calls_integrating, &
      " (", fallback_rate, "%) success=", fallback_success, " fail=", fallback_failure, " calls=", calls_total
   write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0)') "[INTODE] rescue_ok: adapt=", success_radau_adaptive, &
      " adapt_rb=", success_radau_adaptive_robust, " fixed=", success_radau_fixed_tol, &
      " chunked=", success_radau_chunked, " solver_assist=", success_solver_assist
   write (*, '(A,I0,A,I0,A,I0,A,I0,A,L1,A,I0,A,L1)') "[INTODE] reasons: h_min=", fallback_h_min, " invalid=", fallback_invalid, &
      " max_steps=", fallback_max_steps, " rescue_ng=", rescue_fail_total, &
      " fast_hmin_assist=", fast_hmin_assist, " assist_max=", solver_assist_max_uses, &
      " assist_unlimited=", solver_assist_unlimited

   write (*, '(A)') "[DONE] Chain application finished."

end program generate_markov_chain_app

program generate_markov_chain_app
   use param_mod
   use markovchain_mod, only: execute_generate_markov_chain
   use mt95, only: getseed, sgrnd
   use solve_flow, only: set_intode_strict_mode, &
                         get_intode_final_resort_policy, &
                         reset_intode_fallback_stats, get_intode_fallback_stats, &
                         get_intode_rescue_stats
   implicit none

   integer :: rng_seed
   integer :: env_status, env_len, io_status
   integer :: calls_total, calls_integrating
   integer :: fallback_attempts, fallback_success, fallback_failure
   integer :: fallback_max_steps, fallback_invalid, fallback_h_min
   integer :: success_radau_adaptive, success_radau_adaptive_robust
   integer :: success_radau_fixed_tol, success_radau_chunked, success_final_resort
   integer :: fail_radau_adaptive_robust, fail_radau_fixed_tol, fail_radau_chunked, fail_final_resort
   integer :: rescue_fail_total
   logical :: final_resort_enabled, fast_hmin_bypass, final_unlimited
   integer :: final_resort_max_uses
   character(len=64) :: seed_env
   real(dp) :: fallback_rate

   seed_env = ""
   call get_environment_variable("CHAIN_RNG_SEED", seed_env, length=env_len, status=env_status)
   if (env_status == 0 .and. env_len > 0) then
      read (seed_env(1:env_len), *, iostat=io_status) rng_seed
      if (io_status /= 0 .or. rng_seed == 0) then
         rng_seed = getseed()
         write (*, '(A,A,A,I0)') "[RNG] Invalid CHAIN_RNG_SEED='", trim(seed_env(1:env_len)), "'. Using random seed=", rng_seed
      else
         write (*, '(A,I0)') "[RNG] Using fixed CHAIN_RNG_SEED=", rng_seed
      end if
   else
      rng_seed = getseed()
      write (*, '(A,I0)') "[RNG] Using random seed=", rng_seed
   end if
   call sgrnd(rng_seed)

   call set_intode_strict_mode(.true.)
   call read_parameters()
   call get_intode_final_resort_policy(final_resort_enabled, final_resort_max_uses, fast_hmin_bypass)
   final_unlimited = (final_resort_max_uses <= 0)
   write (*, '(A,L1,A,L1,A,L1)') "[INTODE] strict=", .true., " final_resort=", final_resort_enabled, &
      " inner_resort_unlimited=", final_unlimited
   call reset_intode_fallback_stats()
   call execute_generate_markov_chain()

   call get_intode_fallback_stats(calls_total, calls_integrating, fallback_attempts, fallback_success, fallback_failure, &
                                  fallback_max_steps, fallback_invalid, fallback_h_min)
   call get_intode_rescue_stats(success_radau_adaptive, success_radau_adaptive_robust, success_radau_fixed_tol, &
                                success_radau_chunked, success_final_resort, fail_radau_adaptive_robust, &
                                fail_radau_fixed_tol, fail_radau_chunked, fail_final_resort)
   rescue_fail_total = fail_radau_adaptive_robust + fail_radau_fixed_tol + fail_radau_chunked + fail_final_resort
   if (calls_integrating > 0) then
      fallback_rate = 100.0_dp*real(fallback_attempts, dp)/real(calls_integrating, dp)
   else
      fallback_rate = 0.0_dp
   end if
   write (*, '(A,I0,A,I0,A,F7.3,A,I0,A,I0,A,I0)') "[INTODE] fallback=", fallback_attempts, "/", calls_integrating, &
      " (", fallback_rate, "%) success=", fallback_success, " fail=", fallback_failure, " calls=", calls_total
   write (*, '(A,I0,A,I0,A,I0,A,I0,A,I0)') "[INTODE] rescue_ok: adapt=", success_radau_adaptive, &
      " adapt_rb=", success_radau_adaptive_robust, " fixed=", success_radau_fixed_tol, &
      " chunked=", success_radau_chunked, " final=", success_final_resort
   write (*, '(A,I0,A,I0,A,I0,A,I0,A,L1,A,I0,A,L1)') "[INTODE] reasons: h_min=", fallback_h_min, " invalid=", fallback_invalid, &
      " max_steps=", fallback_max_steps, " rescue_ng=", rescue_fail_total, &
      " fast_hmin_bypass=", fast_hmin_bypass, " final_max=", final_resort_max_uses, " final_unlimited=", final_unlimited

   write (*, '(A)') "[DONE] Chain application finished."

end program generate_markov_chain_app

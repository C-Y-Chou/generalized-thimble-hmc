module solve_flow
   use param_mod
   use utils
   use model, only: ds, hessian_vec
   use perf_profile, only: perf_tic, perf_toc, PERF_INTODE, PERF_FLOW, PERF_FLOWZ, PERF_FLOWZR
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   implicit none

   real(dp), allocatable, save :: odex_T(:, :, :)
   real(dp), allocatable, save :: odex_yprev(:), odex_ycurr(:), odex_ynext(:), odex_fval(:)
   real(dp), allocatable, save :: odex_fbase(:)

   real(dp), allocatable, save :: intode_yc(:), intode_yf(:)
   real(dp), allocatable, save :: flow_vec_y(:), flow_vec_yf(:)
   real(dp), allocatable, save :: flow_jac_y(:), flow_jac_yf(:)
   complex(dp), allocatable, save :: flow_vec_z(:), flow_vec_ds(:)
   complex(dp), allocatable, save :: flow_jac_z(:), flow_jac_ds(:)
   complex(dp), allocatable, save :: flow_jac_j(:,:), flow_jac_jprod(:,:)
   real(dp), save :: flow_vec_rhs_scale = 1.0_dp

   integer, parameter :: intode_max_steps = 200000
   integer, parameter :: odex_k_min = 4
   integer, parameter :: odex_k_max = 10
   integer, parameter :: odex_cache_size = odex_k_max + 1
   integer, parameter :: intode_reason_none = 0
   integer, parameter :: intode_reason_max_steps = 1
   integer, parameter :: intode_reason_invalid = 2
   integer, parameter :: intode_reason_h_min = 3
   integer, parameter :: intode_ctx_unknown = 0
   integer, parameter :: intode_ctx_flowz = 1
   integer, parameter :: intode_ctx_flowzr = 2
   integer, parameter :: intode_ctx_flow = 3
   integer, parameter :: intode_stage_unknown = 0
   integer, parameter :: intode_stage_newton = 1
   integer, parameter :: intode_stage_quasi = 2
   integer, parameter :: intode_stage_quasi_retry = 3
   integer, parameter :: intode_stage_rattle_flow = 4
   integer, parameter :: intode_stage_external = 5
   integer, save :: odex_nsteps_cache(odex_cache_size) = 0
   real(dp), save :: odex_ak_cache(odex_cache_size) = 0.0_dp
   real(dp), save :: odex_invexp_cache(odex_cache_size) = 0.0_dp
   real(dp), save :: odex_ratio_cache(odex_cache_size, odex_cache_size) = 0.0_dp
   logical, save :: odex_tables_ready = .false.
   integer, save :: intode_calls_total = 0
   integer, save :: intode_calls_integrating = 0
   integer, save :: intode_fallback_attempts = 0
   integer, save :: intode_fallback_success = 0
   integer, save :: intode_fallback_failure = 0
   integer, save :: intode_fallback_max_steps = 0
   integer, save :: intode_fallback_invalid = 0
   integer, save :: intode_fallback_h_min = 0
   integer, save :: intode_fallback_attempts_ctx(intode_ctx_unknown:intode_ctx_flow) = 0
   integer, save :: intode_fallback_failures_ctx(intode_ctx_unknown:intode_ctx_flow) = 0
   logical, save :: intode_strict_mode = .true.
   integer, parameter :: radau_step_ok = 0
   integer, parameter :: radau_step_fail_newton = 1
   integer, parameter :: radau_step_fail_linear = 2
   integer, save :: intode_rescue_success_radau_adaptive = 0
   integer, save :: intode_rescue_success_radau_adaptive_robust = 0
   integer, save :: intode_rescue_success_radau_fixed_tol = 0
   integer, save :: intode_rescue_success_radau_chunked = 0
   integer, save :: intode_rescue_success_final_resort = 0
   integer, save :: intode_radau_adapt_newton_fail = 0
   integer, save :: intode_radau_adapt_linear_fail = 0
   integer, save :: intode_radau_adapt_error_reject = 0
   integer, save :: intode_radau_adapt_hmin_hit = 0
   integer, save :: intode_radau_adapt_robust_fail = 0
   integer, save :: intode_radau_fixed_tol_fail = 0
   integer, save :: intode_radau_chunked_fail = 0
   integer, save :: intode_final_resort_fail = 0
   logical, parameter :: intode_enable_final_resort = .true.
   logical, parameter :: intode_fast_hmin_bypass = .true.
   logical, parameter :: intode_verbose_logs = .false.
   ! <= 0 means unlimited final-resort uses (still context-gated).
   integer, parameter :: intode_final_resort_max_uses = 0
   integer, save :: intode_final_resort_log_count = 0
   integer, parameter :: intode_final_resort_log_limit = 20
   integer, save :: intode_trace_rattle_step = 0
   integer, save :: intode_trace_rattle_substep = 0
   integer, save :: intode_trace_stage = intode_stage_unknown
   integer, save :: intode_trace_newton_iter = 0
   integer, save :: intode_trace_quasi_iter = 0
   integer, save :: intode_current_context = intode_ctx_unknown
   logical, save :: intode_capture_failures = .true.
   logical, save :: intode_last_failure_available = .false.
   integer, save :: intode_last_failure_reason = intode_reason_none
   integer, save :: intode_last_failure_context = intode_ctx_unknown
   integer, save :: intode_last_failure_rattle_step = 0
   integer, save :: intode_last_failure_rattle_substep = 0
   integer, save :: intode_last_failure_stage = intode_stage_unknown
   integer, save :: intode_last_failure_newton_iter = 0
   integer, save :: intode_last_failure_quasi_iter = 0
   integer, save :: intode_failure_log_count = 0
   integer, parameter :: intode_failure_log_limit = 20
   real(dp), save :: intode_last_failure_t = 0.0_dp
   real(dp), allocatable, save :: intode_last_failure_y(:)

   abstract interface
      function ode_rhs(y) result(dy)
         import :: dp
         real(dp), intent(in) :: y(:)
         real(dp) :: dy(size(y))
      end function ode_rhs
   end interface
contains

   subroutine odex_step(f, y, h, k, res, err)
      implicit none
      procedure(ode_rhs) :: f

      integer, intent(inout) :: k
      real(dp), intent(inout) :: h
      real(dp), intent(in) :: y(:)
      real(dp), intent(out) :: res(:), err

      integer :: i, j, l, n, ni, k_prev
      real(dp) :: dt, scale, errsum, wk1, wk2, hk1, hk2

      n = size(y)
      res = y
      wk1 = 0.0_dp
      wk2 = 0.0_dp
      hk1 = h
      hk2 = h

      odex_fbase(1:n) = f(y)

      if (vector_has_invalid(odex_fbase(1:n))) then
         err = huge(1.0_dp)
         res = y
         h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
         k = max(odex_k_min, k - 1)
         return
      end if

      do i = 1, k
         ni = odex_nsteps_cache(i)
         dt = h/real(ni, dp)

         odex_yprev(1:n) = y
         odex_ycurr(1:n) = y + dt*odex_fbase(1:n)

         do l = 2, ni
            odex_fval(1:n) = f(odex_ycurr(1:n))
            odex_ynext(1:n) = odex_yprev(1:n) + 2.0_dp*dt*odex_fval(1:n)
            odex_yprev(1:n) = odex_ycurr(1:n)
            odex_ycurr(1:n) = odex_ynext(1:n)
         end do

         odex_fval(1:n) = f(odex_ycurr(1:n))
         odex_T(i, 1, 1:n) = 0.5_dp*(odex_yprev(1:n) + odex_ycurr(1:n) + dt*odex_fval(1:n))
      end do

      do j = 2, k
         do i = j, k
            odex_T(i, j, 1:n) = odex_T(i, j - 1, 1:n) + (odex_T(i, j - 1, 1:n) - odex_T(i - 1, j - 1, 1:n))/ &
                                odex_ratio_cache(i, i - j + 1)

            if (i == k - 1 .and. j == k - 1) then
               errsum = 0.0_dp
               do l = 1, n
                  scale = at + rt*max(abs(odex_T(k - 2, k - 2, l)), abs(odex_T(k - 2, k - 3, l)))
                  scale = max(scale, tiny(1.0_dp))
                  errsum = errsum + ((odex_T(k - 2, k - 2, l) - odex_T(k - 2, k - 3, l))/scale)**2
               end do
               err = sqrt(errsum/real(n, dp))
               wk2 = calculate_wk(h, err, k - 2)

               errsum = 0.0_dp
               do l = 1, n
                  scale = at + rt*max(abs(odex_T(k - 1, k - 1, l)), abs(odex_T(k - 1, k - 2, l)))
                  scale = max(scale, tiny(1.0_dp))
                  errsum = errsum + ((odex_T(k - 1, k - 1, l) - odex_T(k - 1, k - 2, l))/scale)**2
               end do
               err = sqrt(errsum/real(n, dp))
               wk1 = calculate_wk(h, err, k - 1)
               hk1 = calculate_hk(h, err, k - 1)

               if (err < 1.0_dp) then
                  res = odex_T(k - 1, k - 1, 1:n)
                  if (wk1 > 0.9_dp*wk2) then
                     k = max(odex_k_min, k - 1)
                     h = hk1
                  else
                     h = hk1*odex_ak_cache(k)/odex_ak_cache(k - 1)
                  end if
                  return
               else if (err > real((k*k + 1)**2, dp)) then
                  k = max(odex_k_min, k - 1)
                  h = hk1
                  res = y
                  return
               end if
            end if
         end do
      end do

      errsum = 0.0_dp
      do i = 1, n
         scale = at + rt*max(abs(odex_T(k, k, i)), abs(odex_T(k, k - 1, i)))
         scale = max(scale, tiny(1.0_dp))
         errsum = errsum + ((odex_T(k, k, i) - odex_T(k, k - 1, i))/scale)**2
      end do
      err = sqrt(errsum/real(n, dp))

      hk2 = calculate_hk(h, err, k)
      wk2 = calculate_wk(h, err, k)
      if (err < 1.0_dp) then
         res = odex_T(k, k, 1:n)
         if (wk1 < 0.9_dp*wk2) then
            k = max(odex_k_min, k - 1)
            h = hk1
         else if (wk2 < 0.9_dp*wk1) then
            k_prev = k
            k = min(odex_k_max, k + 1)
            if (k > k_prev) then
               h = hk2*odex_ak_cache(k + 1)/odex_ak_cache(k)
            else
               h = hk2
            end if
         else
            h = hk2
         end if
         return
      end if

      ni = odex_nsteps_cache(k + 1)
      dt = h/real(ni, dp)
      odex_yprev(1:n) = y
      odex_ycurr(1:n) = y + dt*odex_fbase(1:n)

      do l = 2, ni
         odex_fval(1:n) = f(odex_ycurr(1:n))
         odex_ynext(1:n) = odex_yprev(1:n) + 2.0_dp*dt*odex_fval(1:n)
         odex_yprev(1:n) = odex_ycurr(1:n)
         odex_ycurr(1:n) = odex_ynext(1:n)
      end do

      odex_fval(1:n) = f(odex_ycurr(1:n))
      odex_T(k + 1, 1, 1:n) = 0.5_dp*(odex_yprev(1:n) + odex_ycurr(1:n) + dt*odex_fval(1:n))

      do j = 2, k + 1
         odex_T(k + 1, j, 1:n) = odex_T(k + 1, j - 1, 1:n) + (odex_T(k + 1, j - 1, 1:n) - odex_T(k, j - 1, 1:n))/ &
                                 odex_ratio_cache(k + 1, k - j + 2)
      end do

      errsum = 0.0_dp
      do i = 1, n
         scale = at + rt*max(abs(odex_T(k + 1, k + 1, i)), abs(odex_T(k + 1, k, i)))
         scale = max(scale, tiny(1.0_dp))
         errsum = errsum + ((odex_T(k + 1, k + 1, i) - odex_T(k + 1, k, i))/scale)**2
      end do
      err = sqrt(errsum/real(n, dp))

      if (err < 1.0_dp) then
         res = odex_T(k + 1, k + 1, 1:n)
         if (wk1 < 0.9_dp*wk2) then
            k = max(odex_k_min, k - 1)
            h = hk1
         else if (wk2 < 0.9_dp*wk1) then
            hk1 = calculate_hk(h, err, k + 1)
            k = min(odex_k_max, k + 1)
            h = hk1
         else
            h = hk2
         end if
      else
         res = y
         k = max(odex_k_min, k - 1)
         h = hk1
      end if
   end subroutine odex_step

   function calculate_wk(h, er1, k) result(wk)
      implicit none
      real(dp), intent(in) :: h, er1
      integer, intent(in) :: k
      integer :: kc
      real(dp) :: hk, wk

      kc = max(1, k)
      hk = h*0.94_dp*(0.65_dp/max(er1, 1.0e-14_dp))**odex_invexp_cache(kc)
      wk = odex_ak_cache(kc)/hk
   end function calculate_wk

   function calculate_hk(h, er1, k) result(hk)
      implicit none
      real(dp), intent(in) :: h, er1
      integer, intent(in) :: k
      integer :: kc
      real(dp) :: hk

      kc = max(1, k)
      hk = h*0.94_dp*(0.65_dp/max(er1, 1.0e-14_dp))**odex_invexp_cache(kc)
   end function calculate_hk

   function calculate_ak(k) result(ak)
      implicit none
      integer, intent(in) :: k
      integer :: kc, i
      integer :: wi_prev, wi_curr, wi_next, w_sum
      real(dp) :: ak

      kc = max(1, k)
      wi_prev = 2
      w_sum = wi_prev
      if (kc == 1) then
         ak = 1.0_dp + real(w_sum, dp)
         return
      end if

      i = 2
      do while (i <= kc)
         wi_curr = wi_prev*2
         w_sum = w_sum + wi_curr
         if (i == kc) exit

         wi_next = wi_prev*3
         w_sum = w_sum + wi_next
         if (i + 1 == kc) exit

         wi_prev = wi_next
         i = i + 2
      end do

      ak = 1.0_dp + real(w_sum, dp)
   end function calculate_ak

   subroutine build_nsteps(max_k, nsteps)
      implicit none
      integer, intent(in) :: max_k
      integer, intent(out) :: nsteps(max_k)
      integer :: i

      if (max_k < 1) return
      nsteps = 0
      nsteps(1) = 2
      if (max_k == 1) return

      i = 2
      do
         nsteps(i) = nsteps(i - 1)*2
         if (i == max_k) exit
         nsteps(i + 1) = nsteps(i - 1)*3
         if (i + 1 == max_k) exit
         i = i + 2
      end do
   end subroutine build_nsteps

   subroutine ensure_odex_tables()
      implicit none
      integer :: idx, jdx

      if (odex_tables_ready) return

      call build_nsteps(odex_cache_size, odex_nsteps_cache)
      do idx = 1, odex_cache_size
         odex_ak_cache(idx) = calculate_ak(idx)
         odex_invexp_cache(idx) = 1.0_dp/(2.0_dp*real(idx, dp) - 1.0_dp)
      end do
      do idx = 1, odex_cache_size
         do jdx = 1, odex_cache_size
            odex_ratio_cache(idx, jdx) = (real(odex_nsteps_cache(idx), dp)/real(odex_nsteps_cache(jdx), dp))**2 - 1.0_dp
         end do
      end do
      odex_tables_ready = .true.
   end subroutine ensure_odex_tables

   subroutine intode(f, y, t, res, error_flag)
      implicit none
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag

      real(dp) :: h, tc, er1, h_min, t_new
      integer :: state_size, k, step_count
      real(dp) :: h_min_fp, h_min_tol, h_min_span
      logical :: is_last_step, rescue_failed, final_resort_ok
      real(dp), parameter :: c_fp = 16.0_dp
      real(dp), parameter :: c_tol = 0.01_dp
      real(dp), parameter :: c_span = 1.0e-12_dp
      real(dp) :: t_prof

      call perf_tic(t_prof)
      intode_calls_total = intode_calls_total + 1
      if (t == 0.0_dp) then
         res = y
         error_flag = .false.
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if
      intode_calls_integrating = intode_calls_integrating + 1

      state_size = size(y)
      call ensure_odex_tables()
      call ensure_odex_workspace(odex_cache_size, state_size)
      call ensure_real_workspace(intode_yc, state_size)
      call ensure_real_workspace(intode_yf, state_size)

      h_min_fp = c_fp*epsilon(1.0_dp)*max(1.0_dp, abs(t))
      h_min_tol = c_tol*max(at, rt, epsilon(1.0_dp))
      h_min_span = c_span*abs(t)
      h_min = max(h_min_fp, min(h_min_tol, h_min_span))

      tc = 0.0_dp
      intode_yc(1:state_size) = y
      h = t/100.0_dp
      if (h == 0.0_dp) h = sign(h_min, t)
      k = odex_k_min
      step_count = 0
      error_flag = .true.

      do
         step_count = step_count + 1
         if (step_count > intode_max_steps) then
            intode_fallback_attempts = intode_fallback_attempts + 1
            intode_fallback_max_steps = intode_fallback_max_steps + 1
            call record_intode_fallback_attempt_context(intode_current_context)
            call intode_stiff_rescue(f, intode_yc(1:state_size), t - tc, intode_yf(1:state_size), rescue_failed)
            if (.not. rescue_failed) then
               intode_fallback_success = intode_fallback_success + 1
               res = intode_yf(1:state_size)
               error_flag = .false.
            else
               call intode_try_final_resort(intode_yc(1:state_size), t - tc, intode_reason_max_steps, &
                                            intode_yf(1:state_size), final_resort_ok)
               if (final_resort_ok) then
                  intode_fallback_success = intode_fallback_success + 1
                  res = intode_yf(1:state_size)
                  error_flag = .false.
               else
                  intode_fallback_failure = intode_fallback_failure + 1
                  call record_intode_fallback_failure_context(intode_current_context)
                  call record_intode_last_failure(intode_yc(1:state_size), t - tc, intode_reason_max_steps)
                  res = intode_yc(1:state_size)
               end if
            end if
            call perf_toc(PERF_INTODE, t_prof)
            return
         end if

         if ((t >= 0.0_dp .and. tc + h >= t) .or. (t < 0.0_dp .and. tc + h <= t)) then
            is_last_step = .true.
            h = t - tc
         else
            is_last_step = .false.
         end if

         t_new = tc + h
         call odex_step(f, intode_yc(1:state_size), h, k, intode_yf(1:state_size), er1)

         if (vector_has_invalid(intode_yf(1:state_size)) .or. .not. ieee_is_finite(h)) then
            intode_fallback_attempts = intode_fallback_attempts + 1
            intode_fallback_invalid = intode_fallback_invalid + 1
            call record_intode_fallback_attempt_context(intode_current_context)
            call intode_stiff_rescue(f, intode_yc(1:state_size), t - tc, intode_yf(1:state_size), rescue_failed)
            if (.not. rescue_failed) then
               intode_fallback_success = intode_fallback_success + 1
               res = intode_yf(1:state_size)
               error_flag = .false.
            else
               call intode_try_final_resort(intode_yc(1:state_size), t - tc, intode_reason_invalid, &
                                            intode_yf(1:state_size), final_resort_ok)
               if (final_resort_ok) then
                  intode_fallback_success = intode_fallback_success + 1
                  res = intode_yf(1:state_size)
                  error_flag = .false.
               else
                  intode_fallback_failure = intode_fallback_failure + 1
                  call record_intode_fallback_failure_context(intode_current_context)
                  call record_intode_last_failure(intode_yc(1:state_size), t - tc, intode_reason_invalid)
                  res = intode_yc(1:state_size)
               end if
            end if
            call perf_toc(PERF_INTODE, t_prof)
            return
         end if

         if (er1 < 1.0_dp) then
            tc = t_new
            intode_yc(1:state_size) = intode_yf(1:state_size)
            if (is_last_step) exit
         end if

         if (abs(h) < h_min) then
            intode_fallback_attempts = intode_fallback_attempts + 1
            intode_fallback_h_min = intode_fallback_h_min + 1
            call record_intode_fallback_attempt_context(intode_current_context)
            if (intode_fast_hmin_bypass) then
               call intode_try_final_resort(intode_yc(1:state_size), t - tc, intode_reason_h_min, &
                                            intode_yf(1:state_size), final_resort_ok)
               if (final_resort_ok) then
                  intode_fallback_success = intode_fallback_success + 1
                  res = intode_yf(1:state_size)
                  error_flag = .false.
                  call perf_toc(PERF_INTODE, t_prof)
                  return
               end if
            end if
            call intode_stiff_rescue(f, intode_yc(1:state_size), t - tc, intode_yf(1:state_size), rescue_failed)
            if (.not. rescue_failed) then
               intode_fallback_success = intode_fallback_success + 1
               res = intode_yf(1:state_size)
               error_flag = .false.
            else
               call intode_try_final_resort(intode_yc(1:state_size), t - tc, intode_reason_h_min, &
                                            intode_yf(1:state_size), final_resort_ok)
               if (final_resort_ok) then
                  intode_fallback_success = intode_fallback_success + 1
                  res = intode_yf(1:state_size)
                  error_flag = .false.
               else
                  intode_fallback_failure = intode_fallback_failure + 1
                  call record_intode_fallback_failure_context(intode_current_context)
                  call record_intode_last_failure(intode_yc(1:state_size), t - tc, intode_reason_h_min)
                  res = intode_yc(1:state_size)
               end if
            end if
            call perf_toc(PERF_INTODE, t_prof)
            return
         end if
      end do

      res = intode_yc(1:state_size)
      error_flag = .false.
      call perf_toc(PERF_INTODE, t_prof)
   end subroutine intode

   subroutine intode_try_final_resort(y_curr, t_remaining, reason_code, y_out, accepted)
      implicit none
      real(dp), intent(in) :: y_curr(:), t_remaining
      integer, intent(in) :: reason_code
      real(dp), intent(out) :: y_out(:)
      logical, intent(out) :: accepted
      logical :: allow_context

      accepted = .false.
      y_out = y_curr

      if (.not. intode_enable_final_resort) then
         intode_final_resort_fail = intode_final_resort_fail + 1
         return
      end if
      if (reason_code /= intode_reason_h_min) then
         intode_final_resort_fail = intode_final_resort_fail + 1
         return
      end if
      allow_context = (intode_current_context == intode_ctx_flowz .or. intode_current_context == intode_ctx_flowzr)
      if (.not. allow_context) then
         intode_final_resort_fail = intode_final_resort_fail + 1
         return
      end if
      if (intode_final_resort_max_uses > 0) then
         if (intode_rescue_success_final_resort >= intode_final_resort_max_uses) then
            intode_final_resort_fail = intode_final_resort_fail + 1
            return
         end if
      end if

      accepted = .true.
      intode_rescue_success_final_resort = intode_rescue_success_final_resort + 1

      if (intode_verbose_logs) then
         if (intode_final_resort_log_count < intode_final_resort_log_limit) then
            write (*, '(A,I0,A,I0,A,ES12.4,A,I0,A,I0,A,I0)') "[INTODE][RESCUE] final_resort_accept context=", &
               intode_current_context, " reason=", reason_code, " t_remaining=", t_remaining, &
               " rattle_step=", intode_trace_rattle_step, " substep=", intode_trace_rattle_substep, &
               " stage=", intode_trace_stage
         else if (intode_final_resort_log_count == intode_final_resort_log_limit) then
            write (*, '(A)') "[INTODE][RESCUE] additional final_resort logs suppressed."
         end if
         intode_final_resort_log_count = intode_final_resort_log_count + 1
      end if
   end subroutine intode_try_final_resort

   subroutine record_intode_fallback_attempt_context(ctx_code)
      implicit none
      integer, intent(in) :: ctx_code
      integer :: idx

      idx = normalize_context_code(ctx_code)
      intode_fallback_attempts_ctx(idx) = intode_fallback_attempts_ctx(idx) + 1
   end subroutine record_intode_fallback_attempt_context

   subroutine record_intode_fallback_failure_context(ctx_code)
      implicit none
      integer, intent(in) :: ctx_code
      integer :: idx

      idx = normalize_context_code(ctx_code)
      intode_fallback_failures_ctx(idx) = intode_fallback_failures_ctx(idx) + 1
   end subroutine record_intode_fallback_failure_context

   integer function normalize_context_code(ctx_code) result(ctx_norm)
      implicit none
      integer, intent(in) :: ctx_code

      if (ctx_code >= intode_ctx_flowz .and. ctx_code <= intode_ctx_flow) then
         ctx_norm = ctx_code
      else
         ctx_norm = intode_ctx_unknown
      end if
   end function normalize_context_code

   subroutine record_intode_last_failure(y, t_remaining, reason_code)
      implicit none
      real(dp), intent(in) :: y(:), t_remaining
      integer, intent(in) :: reason_code

      if (.not. intode_capture_failures) return

      intode_last_failure_available = .true.
      intode_last_failure_reason = reason_code
      intode_last_failure_context = intode_current_context
      intode_last_failure_rattle_step = intode_trace_rattle_step
      intode_last_failure_rattle_substep = intode_trace_rattle_substep
      intode_last_failure_stage = intode_trace_stage
      intode_last_failure_newton_iter = intode_trace_newton_iter
      intode_last_failure_quasi_iter = intode_trace_quasi_iter
      intode_last_failure_t = t_remaining
      if (allocated(intode_last_failure_y)) then
         if (size(intode_last_failure_y) /= size(y)) then
            deallocate (intode_last_failure_y)
            allocate (intode_last_failure_y(size(y)))
         end if
      else
         allocate (intode_last_failure_y(size(y)))
      end if
      intode_last_failure_y = y

      if (intode_verbose_logs) then
         if (intode_failure_log_count < intode_failure_log_limit) then
            write (*, '(A,A,A,A,A,I0,A,I0,A,I0,A,I0,A,ES12.4)') "[INTODE][FAIL] context=", trim(context_name(intode_last_failure_context)), &
               " reason=", trim(reason_name(reason_code)), " rattle_step=", intode_last_failure_rattle_step, &
               " substep=", intode_last_failure_rattle_substep, " newton_iter=", intode_last_failure_newton_iter, &
               " quasi_iter=", intode_last_failure_quasi_iter, " t_remaining=", t_remaining
            write (*, '(A,A)') "               stage=", trim(stage_name(intode_last_failure_stage))
         else if (intode_failure_log_count == intode_failure_log_limit) then
            write (*, '(A)') "[INTODE][FAIL] additional failure logs suppressed."
         end if
         intode_failure_log_count = intode_failure_log_count + 1
      end if

   contains

      function reason_name(reason) result(name)
         implicit none
         integer, intent(in) :: reason
         character(len=20) :: name

         select case (reason)
         case (intode_reason_max_steps)
            name = "max_steps"
         case (intode_reason_invalid)
            name = "invalid"
         case (intode_reason_h_min)
            name = "h_min"
         case default
            name = "unknown"
         end select
      end function reason_name

      function context_name(ctx_code) result(name)
         implicit none
         integer, intent(in) :: ctx_code
         character(len=20) :: name

         select case (ctx_code)
         case (intode_ctx_flowz)
            name = "flowz"
         case (intode_ctx_flowzr)
            name = "flowzr"
         case (intode_ctx_flow)
            name = "flow"
         case default
            name = "unknown"
         end select
      end function context_name

      function stage_name(stage_code) result(name)
         implicit none
         integer, intent(in) :: stage_code
         character(len=20) :: name

         select case (stage_code)
         case (intode_stage_newton)
            name = "newton"
         case (intode_stage_quasi)
            name = "quasi"
         case (intode_stage_quasi_retry)
            name = "quasi_retry"
         case (intode_stage_rattle_flow)
            name = "rattle_flow"
         case (intode_stage_external)
            name = "external"
         case default
            name = "unknown"
         end select
      end function stage_name

   end subroutine record_intode_last_failure

   subroutine intode_stiff_rescue(f, y, t, res, error_flag)
      implicit none
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag

      logical :: failed_local

      call intode_radau5(f, y, t, res, failed_local)
      if (.not. failed_local) then
         intode_rescue_success_radau_adaptive = intode_rescue_success_radau_adaptive + 1
         error_flag = .false.
         return
      end if

      call intode_radau5(f, y, t, res, failed_local, robust_mode=1)
      if (.not. failed_local) then
         intode_rescue_success_radau_adaptive_robust = intode_rescue_success_radau_adaptive_robust + 1
         error_flag = .false.
         return
      end if
      intode_radau_adapt_robust_fail = intode_radau_adapt_robust_fail + 1

      call intode_radau5_fixed_tolerance(f, y, t, res, failed_local, 64, robust_mode=1, max_refine=8, max_n_steps=16384)
      if (.not. failed_local) then
         intode_rescue_success_radau_fixed_tol = intode_rescue_success_radau_fixed_tol + 1
         error_flag = .false.
         return
      end if
      intode_radau_fixed_tol_fail = intode_radau_fixed_tol_fail + 1

      call intode_radau5_chunked_tolerance(f, y, t, res, failed_local, robust_mode=1)
      if (.not. failed_local) then
         intode_rescue_success_radau_chunked = intode_rescue_success_radau_chunked + 1
         error_flag = .false.
         return
      end if
      intode_radau_chunked_fail = intode_radau_chunked_fail + 1

      res = y
      error_flag = .true.
   end subroutine intode_stiff_rescue

   subroutine intode_radau5_fixed_tolerance(f, y, t, res, error_flag, n_steps_seed, robust_mode, max_refine, max_n_steps)
      implicit none
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      integer, intent(in) :: n_steps_seed
      integer, intent(in), optional :: robust_mode, max_refine, max_n_steps

      integer :: n_steps, refine_idx, robust_mode_use, max_refine_use, max_n_steps_use
      logical :: failed_n, failed_2n
      real(dp) :: err_est
      real(dp), allocatable :: y_n(:), y_2n(:)

      if (present(robust_mode)) then
         robust_mode_use = max(0, robust_mode)
      else
         robust_mode_use = 0
      end if
      if (present(max_refine)) then
         max_refine_use = max(1, max_refine)
      else
         max_refine_use = 16
      end if
      if (present(max_n_steps)) then
         max_n_steps_use = max(2, max_n_steps)
      else
         max_n_steps_use = 65536
      end if

      if (t == 0.0_dp) then
         res = y
         error_flag = .false.
         return
      end if

      allocate (y_n(size(y)), y_2n(size(y)))
      n_steps = max(1, n_steps_seed)
      error_flag = .true.

      do refine_idx = 1, max_refine_use
         call intode_radau5(f, y, t, y_n, failed_n, n_steps=n_steps, robust_mode=robust_mode_use)
         if (failed_n .or. vector_has_invalid(y_n)) then
            if (n_steps >= max_n_steps_use/2) exit
            n_steps = min(2*n_steps, max_n_steps_use/2)
            cycle
         end if

         call intode_radau5(f, y, t, y_2n, failed_2n, n_steps=2*n_steps, robust_mode=robust_mode_use)
         if (failed_2n .or. vector_has_invalid(y_2n)) then
            if (n_steps >= max_n_steps_use/2) exit
            n_steps = min(2*n_steps, max_n_steps_use/2)
            cycle
         end if

         call estimate_radau_pair_error(y_n, y_2n, err_est)
         if (ieee_is_finite(err_est) .and. err_est <= 1.0_dp) then
            res = y_2n
            error_flag = .false.
            deallocate (y_n, y_2n)
            return
         end if

         if (n_steps >= max_n_steps_use/2) exit
         n_steps = min(2*n_steps, max_n_steps_use/2)
      end do

      res = y
      error_flag = .true.
      deallocate (y_n, y_2n)

   contains

      subroutine estimate_radau_pair_error(y_coarse, y_fine, err_local)
         implicit none
         real(dp), intent(in) :: y_coarse(:), y_fine(:)
         real(dp), intent(out) :: err_local
         integer :: i_local, n_local
         real(dp) :: scale_local, diff_local, errsum_local

         n_local = size(y_coarse)
         errsum_local = 0.0_dp
         do i_local = 1, n_local
            scale_local = at + rt*max(abs(y_fine(i_local)), abs(y_coarse(i_local)))
            scale_local = max(scale_local, tiny(1.0_dp))
            diff_local = (y_fine(i_local) - y_coarse(i_local))/31.0_dp
            errsum_local = errsum_local + (diff_local/scale_local)**2
         end do
         err_local = sqrt(errsum_local/real(n_local, dp))
      end subroutine estimate_radau_pair_error

   end subroutine intode_radau5_fixed_tolerance

   subroutine intode_radau5_chunked_tolerance(f, y, t, res, error_flag, robust_mode)
      implicit none
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      integer, intent(in), optional :: robust_mode

      integer, parameter :: n_chunk_levels = 2
      integer, parameter :: chunk_levels(n_chunk_levels) = [2, 4]
      integer :: robust_mode_use, i_level, n_chunks, chunk_idx
      real(dp) :: dt_chunk
      logical :: failed_local
      real(dp), allocatable :: y_curr(:), y_next(:)

      if (present(robust_mode)) then
         robust_mode_use = max(0, robust_mode)
      else
         robust_mode_use = 0
      end if

      if (t == 0.0_dp) then
         res = y
         error_flag = .false.
         return
      end if

      allocate (y_curr(size(y)), y_next(size(y)))
      error_flag = .true.

      do i_level = 1, n_chunk_levels
         n_chunks = chunk_levels(i_level)
         dt_chunk = t/real(n_chunks, dp)
         y_curr = y
         failed_local = .false.

         do chunk_idx = 1, n_chunks
            call intode_radau5_fixed_tolerance(f, y_curr, dt_chunk, y_next, failed_local, 64, robust_mode=robust_mode_use, &
                                               max_refine=4, max_n_steps=8192)
            if (failed_local .or. vector_has_invalid(y_next)) then
               failed_local = .true.
               exit
            end if
            y_curr = y_next
         end do

         if (.not. failed_local) then
            res = y_curr
            error_flag = .false.
            deallocate (y_curr, y_next)
            return
         end if
      end do

      res = y
      error_flag = .true.
      deallocate (y_curr, y_next)
   end subroutine intode_radau5_chunked_tolerance

   subroutine intode_jfnk(f, y, t, res, error_flag, n_steps)
      implicit none
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      integer, intent(in), optional :: n_steps

      integer :: state_size, step_idx, n_steps_use, step_count
      real(dp) :: h, tc, t_new, err_est, h_min
      real(dp) :: h_min_fp, h_min_tol, h_min_span, t_prof, fac
      logical :: step_ok, step_ok_full, step_ok_half, is_last_step
      logical :: fixed_step_mode
      real(dp), parameter :: c_fp = 16.0_dp
      real(dp), parameter :: c_tol = 0.01_dp
      real(dp), parameter :: c_span = 1.0e-12_dp
      real(dp), parameter :: safety = 0.90_dp
      real(dp), allocatable :: y_curr(:), y_full(:), y_half(:), y_half2(:)

      call perf_tic(t_prof)
      state_size = size(y)
      if (size(res) /= state_size) then
         error_flag = .true.
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if

      if (t == 0.0_dp) then
         res = y
         error_flag = .false.
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if

      allocate (y_curr(state_size), y_full(state_size), y_half(state_size), y_half2(state_size))
      y_curr = y
      error_flag = .true.

      fixed_step_mode = present(n_steps)
      if (fixed_step_mode) then
         n_steps_use = max(1, n_steps)
         h = t/real(n_steps_use, dp)
         do step_idx = 1, n_steps_use
            call implicit_euler_step_jfnk(y_curr, h, y_full, step_ok)
            if (.not. step_ok .or. vector_has_invalid(y_full)) then
               res = y_curr
               deallocate (y_curr, y_full, y_half, y_half2)
               call perf_toc(PERF_INTODE, t_prof)
               return
            end if
            y_curr = y_full
         end do

         res = y_curr
         error_flag = .false.
         deallocate (y_curr, y_full, y_half, y_half2)
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if

      h_min_fp = c_fp*epsilon(1.0_dp)*max(1.0_dp, abs(t))
      h_min_tol = c_tol*max(at, rt, epsilon(1.0_dp))
      h_min_span = c_span*abs(t)
      h_min = max(h_min_fp, min(h_min_tol, h_min_span))

      tc = 0.0_dp
      h = t/100.0_dp
      if (h == 0.0_dp) h = sign(h_min, t)
      step_count = 0

      do
         step_count = step_count + 1
         if (step_count > 20*intode_max_steps) then
            res = y_curr
            if ((.not. intode_strict_mode) .and. abs(t - tc) <= h_min) error_flag = .false.
            deallocate (y_curr, y_full, y_half, y_half2)
            call perf_toc(PERF_INTODE, t_prof)
            return
         end if

         if ((t >= 0.0_dp .and. tc + h >= t) .or. (t < 0.0_dp .and. tc + h <= t)) then
            is_last_step = .true.
            h = t - tc
         else
            is_last_step = .false.
         end if
         t_new = tc + h

         call implicit_euler_step_jfnk(y_curr, h, y_full, step_ok_full)
         if (.not. step_ok_full .or. vector_has_invalid(y_full)) then
            if (abs(h) <= h_min) then
               res = y_curr
               if (.not. intode_strict_mode) error_flag = .false.
               deallocate (y_curr, y_full, y_half, y_half2)
               call perf_toc(PERF_INTODE, t_prof)
               return
            end if
            h = sign(max(0.5_dp*abs(h), h_min), h)
            cycle
         end if

         call implicit_euler_step_jfnk(y_curr, 0.5_dp*h, y_half, step_ok_half)
         if (.not. step_ok_half .or. vector_has_invalid(y_half)) then
            if (abs(h) <= h_min) then
               res = y_curr
               if (.not. intode_strict_mode) error_flag = .false.
               deallocate (y_curr, y_full, y_half, y_half2)
               call perf_toc(PERF_INTODE, t_prof)
               return
            end if
            h = sign(max(0.5_dp*abs(h), h_min), h)
            cycle
         end if

         call implicit_euler_step_jfnk(y_half, 0.5_dp*h, y_half2, step_ok_half)
         if (.not. step_ok_half .or. vector_has_invalid(y_half2)) then
            if (abs(h) <= h_min) then
               res = y_curr
               if (.not. intode_strict_mode) error_flag = .false.
               deallocate (y_curr, y_full, y_half, y_half2)
               call perf_toc(PERF_INTODE, t_prof)
               return
            end if
            h = sign(max(0.5_dp*abs(h), h_min), h)
            cycle
         end if

         call estimate_step_error(y_full, y_half2, err_est)
         if (.not. ieee_is_finite(err_est)) then
            res = y_curr
            deallocate (y_curr, y_full, y_half, y_half2)
            call perf_toc(PERF_INTODE, t_prof)
            return
         end if

         if (err_est <= 1.0_dp) then
            y_curr = y_half2
            tc = t_new
            if (is_last_step) exit

            fac = 2.0_dp
            if (err_est > 1.0e-14_dp) fac = min(2.0_dp, max(0.2_dp, safety*(1.0_dp/err_est)**0.5_dp))
            h = sign(abs(h)*fac, t)
            if (abs(h) < h_min) h = sign(h_min, t)
         else
            if (abs(h) <= h_min) then
               res = y_curr
               if (.not. intode_strict_mode) error_flag = .false.
               deallocate (y_curr, y_full, y_half, y_half2)
               call perf_toc(PERF_INTODE, t_prof)
               return
            end if
            fac = max(0.1_dp, safety*(1.0_dp/err_est)**0.5_dp)
            h = sign(max(abs(h)*fac, h_min), h)
         end if
      end do

      res = y_curr
      error_flag = .false.
      deallocate (y_curr, y_full, y_half, y_half2)
      call perf_toc(PERF_INTODE, t_prof)

   contains

      subroutine implicit_euler_step_jfnk(y_prev, h_local, y_out, ok)
         implicit none
         real(dp), intent(in) :: y_prev(:), h_local
         real(dp), intent(out) :: y_out(:)
         logical, intent(out) :: ok

         integer, parameter :: newton_max_iter = 16
         real(dp), parameter :: min_tol_abs = 1.0e-12_dp
         real(dp), parameter :: min_tol_rel = 1.0e-10_dp
         integer :: n_local, iter
         real(dp) :: residual_norm, state_norm, tol_newton, step_norm
         logical :: residual_ok, linear_ok
         real(dp), allocatable :: x(:), fx(:), residual(:), rhs(:), dx(:)

         n_local = size(y_prev)
         allocate (x(n_local), fx(n_local), residual(n_local), rhs(n_local), dx(n_local))

         fx = f(y_prev)
         if (vector_has_invalid(fx)) then
            ok = .false.
            y_out = y_prev
            deallocate (x, fx, residual, rhs, dx)
            return
         end if

         x = y_prev + h_local*fx

         do iter = 1, newton_max_iter
            call compute_implicit_residual(x, y_prev, h_local, residual, fx, residual_ok)
            if (.not. residual_ok) then
               ok = .false.
               y_out = y_prev
               deallocate (x, fx, residual, rhs, dx)
               return
            end if

            residual_norm = sqrt(sum(residual*residual)/real(n_local, dp))
            state_norm = sqrt(sum(x*x)/real(n_local, dp))
            tol_newton = max(at, min_tol_abs) + max(rt, min_tol_rel)*max(1.0_dp, state_norm)
            tol_newton = max(tol_newton, 10.0_dp*epsilon(1.0_dp))
            if (residual_norm <= tol_newton) then
               ok = .true.
               y_out = x
               deallocate (x, fx, residual, rhs, dx)
               return
            end if

            rhs = -residual
            call solve_linear_gmres_jfnk(x, h_local, fx, rhs, dx, linear_ok)
            if (.not. linear_ok .or. vector_has_invalid(dx)) then
               ok = .false.
               y_out = y_prev
               deallocate (x, fx, residual, rhs, dx)
               return
            end if

            step_norm = sqrt(sum(dx*dx)/real(n_local, dp))
            x = x + dx
            if (vector_has_invalid(x)) then
               ok = .false.
               y_out = y_prev
               deallocate (x, fx, residual, rhs, dx)
               return
            end if

            if (step_norm <= 0.5_dp*tol_newton) then
               call compute_implicit_residual(x, y_prev, h_local, residual, fx, residual_ok)
               if (.not. residual_ok) then
                  ok = .false.
                  y_out = y_prev
                  deallocate (x, fx, residual, rhs, dx)
                  return
               end if
               residual_norm = sqrt(sum(residual*residual)/real(n_local, dp))
               if (residual_norm <= tol_newton) then
                  ok = .true.
                  y_out = x
                  deallocate (x, fx, residual, rhs, dx)
                  return
               end if
            end if
         end do

         call compute_implicit_residual(x, y_prev, h_local, residual, fx, residual_ok)
         if (residual_ok) then
            residual_norm = sqrt(sum(residual*residual)/real(n_local, dp))
            state_norm = sqrt(sum(x*x)/real(n_local, dp))
            tol_newton = max(at, min_tol_abs) + max(rt, min_tol_rel)*max(1.0_dp, state_norm)
            if (residual_norm <= 10.0_dp*tol_newton) then
               ok = .true.
               y_out = x
            else
               ok = .false.
               y_out = y_prev
            end if
         else
            ok = .false.
            y_out = y_prev
         end if

         deallocate (x, fx, residual, rhs, dx)
      end subroutine implicit_euler_step_jfnk

      subroutine compute_implicit_residual(x, y_prev, h_local, residual, fx, ok)
         implicit none
         real(dp), intent(in) :: x(:), y_prev(:), h_local
         real(dp), intent(out) :: residual(:), fx(:)
         logical, intent(out) :: ok

         fx = f(x)
         if (vector_has_invalid(fx)) then
            ok = .false.
            residual = 0.0_dp
            return
         end if

         residual = x - y_prev - h_local*fx
         if (vector_has_invalid(residual)) then
            ok = .false.
            return
         end if
         ok = .true.
      end subroutine compute_implicit_residual

      subroutine solve_linear_gmres_jfnk(x, h_local, fx_base, b, dx, ok)
         implicit none
         real(dp), intent(in) :: x(:), h_local, fx_base(:), b(:)
         real(dp), intent(out) :: dx(:)
         logical, intent(out) :: ok

         integer, parameter :: krylov_max = 40
         real(dp), parameter :: min_linear_tol = 1.0e-12_dp
         integer :: n_local, m, i, j, k
         real(dp) :: beta, linear_tol, residual_lin
         real(dp) :: tmp1, tmp2
         logical :: jv_ok
         real(dp), allocatable :: v(:,:), hess(:,:), cs(:), sn(:), g(:)
         real(dp), allocatable :: w(:), yk(:), rhs_upper(:), x_fd(:), fx_fd(:)

         n_local = size(x)
         m = min(krylov_max, n_local)
         dx = 0.0_dp

         beta = sqrt(sum(b*b))
         if (.not. ieee_is_finite(beta)) then
            ok = .false.
            return
         end if
         if (beta <= min_linear_tol) then
            ok = .true.
            return
         end if

         linear_tol = max(min_linear_tol, 0.05_dp*beta)

         allocate (v(n_local, m + 1), hess(m + 1, m), cs(m), sn(m), g(m + 1))
         allocate (w(n_local), yk(m), rhs_upper(m), x_fd(n_local), fx_fd(n_local))
         v = 0.0_dp
         hess = 0.0_dp
         cs = 0.0_dp
         sn = 0.0_dp
         g = 0.0_dp

         v(:, 1) = b/beta
         g(1) = beta
         k = m

         do j = 1, m
            call apply_jacobian_vec_fd(x, h_local, fx_base, v(:, j), w, x_fd, fx_fd, jv_ok)
            if (.not. jv_ok) then
               ok = .false.
               deallocate (v, hess, cs, sn, g, w, yk, rhs_upper, x_fd, fx_fd)
               return
            end if

            do i = 1, j
               hess(i, j) = dot_product(v(:, i), w)
               w = w - hess(i, j)*v(:, i)
            end do
            hess(j + 1, j) = sqrt(sum(w*w))
            if (hess(j + 1, j) > tiny(1.0_dp)) v(:, j + 1) = w/hess(j + 1, j)

            do i = 1, j - 1
               tmp1 = cs(i)*hess(i, j) + sn(i)*hess(i + 1, j)
               tmp2 = -sn(i)*hess(i, j) + cs(i)*hess(i + 1, j)
               hess(i, j) = tmp1
               hess(i + 1, j) = tmp2
            end do

            call build_givens_rotation(hess(j, j), hess(j + 1, j), cs(j), sn(j))
            tmp1 = cs(j)*hess(j, j) + sn(j)*hess(j + 1, j)
            tmp2 = -sn(j)*hess(j, j) + cs(j)*hess(j + 1, j)
            hess(j, j) = tmp1
            hess(j + 1, j) = tmp2

            tmp1 = cs(j)*g(j) + sn(j)*g(j + 1)
            tmp2 = -sn(j)*g(j) + cs(j)*g(j + 1)
            g(j) = tmp1
            g(j + 1) = tmp2

            residual_lin = abs(g(j + 1))
            if (residual_lin <= linear_tol) then
               k = j
               exit
            end if
         end do

         rhs_upper(1:k) = g(1:k)
         do i = k, 1, -1
            if (abs(hess(i, i)) <= tiny(1.0_dp)) then
               ok = .false.
               deallocate (v, hess, cs, sn, g, w, yk, rhs_upper, x_fd, fx_fd)
               return
            end if

            if (i < k) then
               rhs_upper(i) = rhs_upper(i) - dot_product(hess(i, i + 1:k), rhs_upper(i + 1:k))
            end if
            rhs_upper(i) = rhs_upper(i)/hess(i, i)
         end do

         yk(1:k) = rhs_upper(1:k)
         dx = 0.0_dp
         do i = 1, k
            dx = dx + yk(i)*v(:, i)
         end do

         ok = .not. vector_has_invalid(dx)
         deallocate (v, hess, cs, sn, g, w, yk, rhs_upper, x_fd, fx_fd)
      end subroutine solve_linear_gmres_jfnk

      subroutine apply_jacobian_vec_fd(x, h_local, fx_base, v, jv, x_fd, fx_fd, ok)
         implicit none
         real(dp), intent(in) :: x(:), h_local, fx_base(:), v(:)
         real(dp), intent(out) :: jv(:), x_fd(:), fx_fd(:)
         logical, intent(out) :: ok

         real(dp) :: v_norm, x_norm, eps_fd

         v_norm = sqrt(sum(v*v))
         if (v_norm <= tiny(1.0_dp)) then
            jv = 0.0_dp
            ok = .true.
            return
         end if

         x_norm = sqrt(sum(x*x))
         eps_fd = sqrt(epsilon(1.0_dp))*max(1.0_dp, x_norm)/max(v_norm, 1.0e-14_dp)
         x_fd = x + eps_fd*v
         fx_fd = f(x_fd)
         if (vector_has_invalid(fx_fd)) then
            ok = .false.
            jv = 0.0_dp
            return
         end if

         jv = v - h_local*(fx_fd - fx_base)/eps_fd
         ok = .not. vector_has_invalid(jv)
      end subroutine apply_jacobian_vec_fd

      subroutine build_givens_rotation(a, b, c, s)
         implicit none
         real(dp), intent(in) :: a, b
         real(dp), intent(out) :: c, s
         real(dp) :: t

         if (abs(b) <= tiny(1.0_dp)) then
            c = 1.0_dp
            s = 0.0_dp
         else if (abs(a) <= tiny(1.0_dp)) then
            c = 0.0_dp
            s = 1.0_dp
         else if (abs(b) > abs(a)) then
            t = a/b
            s = sign(1.0_dp/sqrt(1.0_dp + t*t), b)
            c = t*s
         else
            t = b/a
            c = sign(1.0_dp/sqrt(1.0_dp + t*t), a)
            s = t*c
         end if
      end subroutine build_givens_rotation

      subroutine estimate_step_error(y_full_local, y_half_local, err_local)
         implicit none
         real(dp), intent(in) :: y_full_local(:), y_half_local(:)
         real(dp), intent(out) :: err_local
         integer :: i_local, n_local
         real(dp) :: errsum_local, scale_local

         n_local = size(y_full_local)
         errsum_local = 0.0_dp
         do i_local = 1, n_local
            scale_local = at + rt*max(abs(y_half_local(i_local)), abs(y_full_local(i_local)))
            scale_local = max(scale_local, tiny(1.0_dp))
            errsum_local = errsum_local + ((y_half_local(i_local) - y_full_local(i_local))/scale_local)**2
         end do
         err_local = sqrt(errsum_local/real(n_local, dp))
      end subroutine estimate_step_error

   end subroutine intode_jfnk

   subroutine intode_radau5(f, y, t, res, error_flag, n_steps, robust_mode)
      implicit none
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      integer, intent(in), optional :: n_steps
      integer, intent(in), optional :: robust_mode

      real(dp), parameter :: sqrt6 = 2.449489742783178098_dp
      real(dp), parameter :: c_radau(3) = [(4.0_dp - sqrt6)/10.0_dp, (4.0_dp + sqrt6)/10.0_dp, 1.0_dp]
      real(dp), parameter :: a_radau(3, 3) = reshape([ &
                                                       (88.0_dp - 7.0_dp*sqrt6)/360.0_dp, (296.0_dp + 169.0_dp*sqrt6)/1800.0_dp, (16.0_dp - sqrt6)/36.0_dp, &
                                                       (296.0_dp - 169.0_dp*sqrt6)/1800.0_dp, (88.0_dp + 7.0_dp*sqrt6)/360.0_dp, (16.0_dp + sqrt6)/36.0_dp, &
                                                       (-2.0_dp + 3.0_dp*sqrt6)/225.0_dp, (-2.0_dp - 3.0_dp*sqrt6)/225.0_dp, 1.0_dp/9.0_dp], [3, 3])

      integer :: state_size, step_idx, n_steps_use, step_count
      integer :: robust_mode_use, step_limit, step_split_limit
      real(dp) :: h, tc, t_new, err_est, h_min
      real(dp) :: h_min_fp, h_min_tol, h_min_span, t_prof, fac
      real(dp) :: safety_use, fail_shrink_use, grow_min, grow_max, reject_min
      real(dp) :: hmin_relax, start_div
      logical :: step_ok_full, step_ok_half, is_last_step, fixed_step_mode
      integer :: step_fail_full, step_fail_half
      real(dp), parameter :: c_fp = 16.0_dp
      real(dp), parameter :: c_tol = 0.01_dp
      real(dp), parameter :: c_span = 1.0e-12_dp
      real(dp), allocatable :: y_curr(:), y_full(:), y_half(:), y_half2(:)

      call perf_tic(t_prof)
      state_size = size(y)
      if (size(res) /= state_size) then
         error_flag = .true.
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if

      if (t == 0.0_dp) then
         res = y
         error_flag = .false.
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if

      allocate (y_curr(state_size), y_full(state_size), y_half(state_size), y_half2(state_size))
      y_curr = y
      error_flag = .true.

      if (present(robust_mode)) then
         robust_mode_use = max(0, robust_mode)
      else
         robust_mode_use = 0
      end if
      if (robust_mode_use > 0) then
         safety_use = 0.82_dp
         fail_shrink_use = 0.10_dp
         grow_min = 0.10_dp
         grow_max = 1.60_dp
         reject_min = 0.05_dp
         hmin_relax = 0.20_dp
         start_div = 400.0_dp
         step_limit = 60*intode_max_steps
         step_split_limit = 2
      else
         safety_use = 0.90_dp
         fail_shrink_use = 0.20_dp
         grow_min = 0.20_dp
         grow_max = 2.50_dp
         reject_min = 0.10_dp
         hmin_relax = 1.0_dp
         start_div = 100.0_dp
         step_limit = 20*intode_max_steps
         step_split_limit = 0
      end if

      fixed_step_mode = present(n_steps)
      if (fixed_step_mode) then
         n_steps_use = max(1, n_steps)
         h = t/real(n_steps_use, dp)
         do step_idx = 1, n_steps_use
            call try_radau_step(y_curr, h, y_full, step_ok_full, step_fail_full, 0, step_split_limit)
            if (.not. step_ok_full .or. vector_has_invalid(y_full)) then
               res = y_curr
               deallocate (y_curr, y_full, y_half, y_half2)
               call perf_toc(PERF_INTODE, t_prof)
               return
            end if
            y_curr = y_full
         end do

         res = y_curr
         error_flag = .false.
         deallocate (y_curr, y_full, y_half, y_half2)
         call perf_toc(PERF_INTODE, t_prof)
         return
      end if

      h_min_fp = c_fp*epsilon(1.0_dp)*max(1.0_dp, abs(t))
      h_min_tol = c_tol*max(at, rt, epsilon(1.0_dp))
      h_min_span = c_span*abs(t)
      h_min = max(h_min_fp, min(h_min_tol, h_min_span))
      h_min = max(h_min*max(0.01_dp, min(1.0_dp, hmin_relax)), tiny(1.0_dp)*max(1.0_dp, abs(t)))

      tc = 0.0_dp
      h = t/start_div
      if (h == 0.0_dp) h = sign(h_min, t)
      step_count = 0

      do
         step_count = step_count + 1
         if (step_count > step_limit) then
            res = y_curr
            if ((.not. intode_strict_mode) .and. abs(t - tc) <= h_min) error_flag = .false.
            deallocate (y_curr, y_full, y_half, y_half2)
            call perf_toc(PERF_INTODE, t_prof)
            return
         end if

         if ((t >= 0.0_dp .and. tc + h >= t) .or. (t < 0.0_dp .and. tc + h <= t)) then
            is_last_step = .true.
            h = t - tc
         else
            is_last_step = .false.
         end if
         t_new = tc + h

         call try_radau_step(y_curr, h, y_full, step_ok_full, step_fail_full, 0, step_split_limit)
         if (.not. step_ok_full .or. vector_has_invalid(y_full)) then
            call record_radau_adaptive_failure(step_fail_full)
            if (abs(h) <= h_min) then
               intode_radau_adapt_hmin_hit = intode_radau_adapt_hmin_hit + 1
               res = y_curr
               if (.not. intode_strict_mode) error_flag = .false.
               deallocate (y_curr, y_full, y_half, y_half2)
               call perf_toc(PERF_INTODE, t_prof)
               return
            end if
            h = sign(max(fail_shrink_use*abs(h), h_min), h)
            cycle
         end if

         call try_radau_step(y_curr, 0.5_dp*h, y_half, step_ok_half, step_fail_half, 0, step_split_limit)
         if (.not. step_ok_half .or. vector_has_invalid(y_half)) then
            call record_radau_adaptive_failure(step_fail_half)
            if (abs(h) <= h_min) then
               intode_radau_adapt_hmin_hit = intode_radau_adapt_hmin_hit + 1
               res = y_curr
               if (.not. intode_strict_mode) error_flag = .false.
               deallocate (y_curr, y_full, y_half, y_half2)
               call perf_toc(PERF_INTODE, t_prof)
               return
            end if
            h = sign(max(fail_shrink_use*abs(h), h_min), h)
            cycle
         end if

         call try_radau_step(y_half, 0.5_dp*h, y_half2, step_ok_half, step_fail_half, 0, step_split_limit)
         if (.not. step_ok_half .or. vector_has_invalid(y_half2)) then
            call record_radau_adaptive_failure(step_fail_half)
            if (abs(h) <= h_min) then
               intode_radau_adapt_hmin_hit = intode_radau_adapt_hmin_hit + 1
               res = y_curr
               if (.not. intode_strict_mode) error_flag = .false.
               deallocate (y_curr, y_full, y_half, y_half2)
               call perf_toc(PERF_INTODE, t_prof)
               return
            end if
            h = sign(max(fail_shrink_use*abs(h), h_min), h)
            cycle
         end if

         call estimate_step_error_radau(y_full, y_half2, err_est)
         if (.not. ieee_is_finite(err_est)) then
            res = y_curr
            deallocate (y_curr, y_full, y_half, y_half2)
            call perf_toc(PERF_INTODE, t_prof)
            return
         end if

         if (err_est <= 1.0_dp) then
            y_curr = y_half2
            tc = t_new
            if (is_last_step) exit

            fac = grow_max
            if (err_est > 1.0e-14_dp) fac = min(grow_max, max(grow_min, safety_use*(1.0_dp/err_est)**(1.0_dp/6.0_dp)))
            h = sign(abs(h)*fac, t)
            if (abs(h) < h_min) h = sign(h_min, t)
         else
            intode_radau_adapt_error_reject = intode_radau_adapt_error_reject + 1
            if (abs(h) <= h_min) then
               intode_radau_adapt_hmin_hit = intode_radau_adapt_hmin_hit + 1
               res = y_curr
               if (.not. intode_strict_mode) error_flag = .false.
               deallocate (y_curr, y_full, y_half, y_half2)
               call perf_toc(PERF_INTODE, t_prof)
               return
            end if
            fac = max(reject_min, safety_use*(1.0_dp/err_est)**(1.0_dp/6.0_dp))
            h = sign(max(abs(h)*fac, h_min), h)
         end if
      end do

      res = y_curr
      error_flag = .false.
      deallocate (y_curr, y_full, y_half, y_half2)
      call perf_toc(PERF_INTODE, t_prof)

   contains

      subroutine record_radau_adaptive_failure(fail_code)
         implicit none
         integer, intent(in) :: fail_code

         if (fail_code == radau_step_fail_linear) then
            intode_radau_adapt_linear_fail = intode_radau_adapt_linear_fail + 1
         else
            intode_radau_adapt_newton_fail = intode_radau_adapt_newton_fail + 1
         end if
      end subroutine record_radau_adaptive_failure

      recursive subroutine try_radau_step(y_prev_local, h_local, y_out_local, ok_local, fail_code_local, depth, max_depth)
         implicit none
         real(dp), intent(in) :: y_prev_local(:), h_local
         real(dp), intent(out) :: y_out_local(:)
         logical, intent(out) :: ok_local
         integer, intent(out) :: fail_code_local
         integer, intent(in) :: depth, max_depth

         real(dp), allocatable :: y_mid(:)
         logical :: ok_first, ok_second
         integer :: fail_first, fail_second

         call radau5_step(y_prev_local, h_local, y_out_local, ok_local, fail_code_local)
         if (ok_local .and. (.not. vector_has_invalid(y_out_local))) return

         if (depth >= max_depth) then
            y_out_local = y_prev_local
            ok_local = .false.
            return
         end if

         allocate (y_mid(size(y_prev_local)))
         call try_radau_step(y_prev_local, 0.5_dp*h_local, y_mid, ok_first, fail_first, depth + 1, max_depth)
         if (.not. ok_first .or. vector_has_invalid(y_mid)) then
            y_out_local = y_prev_local
            ok_local = .false.
            fail_code_local = fail_first
            deallocate (y_mid)
            return
         end if

         call try_radau_step(y_mid, 0.5_dp*h_local, y_out_local, ok_second, fail_second, depth + 1, max_depth)
         if (.not. ok_second .or. vector_has_invalid(y_out_local)) then
            y_out_local = y_prev_local
            ok_local = .false.
            fail_code_local = fail_second
            deallocate (y_mid)
            return
         end if

         ok_local = .true.
         fail_code_local = radau_step_ok
         deallocate (y_mid)
      end subroutine try_radau_step

      subroutine radau5_step(y_prev, h_local, y_out, ok, fail_code)
         implicit none
         real(dp), intent(in) :: y_prev(:), h_local
         real(dp), intent(out) :: y_out(:)
         logical, intent(out) :: ok
         integer, intent(out) :: fail_code

         integer, parameter :: newton_max_iter_base = 28
         integer, parameter :: max_attempts_base = 2
         integer, parameter :: max_damp_base = 20
         real(dp), parameter :: min_tol_abs_base = 5.0e-12_dp
         real(dp), parameter :: min_tol_rel_base = 5.0e-10_dp
         integer :: n_local, i_stage, i_iter, i_damp, off, i_attempt
         integer :: newton_max_iter, max_attempts, max_damp
         integer :: last_fail_code
         real(dp) :: res_norm, res_trial_norm, state_norm, tol_newton, alpha
         real(dp) :: delta_norm, step_trial_norm, tol_scale
         real(dp) :: min_tol_abs_use, min_tol_rel_use
         logical :: residual_ok, linear_ok, accepted, step_converged
         real(dp), allocatable :: f0(:), y_stage(:, :), y_trial(:, :)
         real(dp), allocatable :: f_stage(:, :), f_trial(:, :)
         real(dp), allocatable :: residual(:), residual_trial(:), delta(:)

         n_local = size(y_prev)
         if (robust_mode_use > 0) then
            newton_max_iter = 48
            max_attempts = 3
            max_damp = 24
            tol_scale = 10.0_dp
         else
            newton_max_iter = newton_max_iter_base
            max_attempts = max_attempts_base
            max_damp = max_damp_base
            tol_scale = 1.0_dp
         end if
         min_tol_abs_use = min_tol_abs_base*tol_scale
         min_tol_rel_use = min_tol_rel_base*tol_scale

         fail_code = radau_step_ok
         allocate (f0(n_local), y_stage(n_local, 3), y_trial(n_local, 3))
         allocate (f_stage(n_local, 3), f_trial(n_local, 3))
         allocate (residual(3*n_local), residual_trial(3*n_local), delta(3*n_local))

         f0 = f(y_prev)
         if (vector_has_invalid(f0)) then
            ok = .false.
            fail_code = radau_step_fail_newton
            y_out = y_prev
            deallocate (f0, y_stage, y_trial, f_stage, f_trial, residual, residual_trial, delta)
            return
         end if

         last_fail_code = radau_step_fail_newton
         step_converged = .false.

         do i_attempt = 1, max_attempts
            if (i_attempt == 1) then
               do i_stage = 1, 3
                  y_stage(:, i_stage) = y_prev + c_radau(i_stage)*h_local*f0
               end do
            else if (i_attempt == 2) then
               do i_stage = 1, 3
                  y_stage(:, i_stage) = y_prev
               end do
            else
               do i_stage = 1, 3
                  y_stage(:, i_stage) = y_prev + 0.5_dp*c_radau(i_stage)*h_local*f0
               end do
            end if

            do i_iter = 1, newton_max_iter
               call evaluate_stage_residual(y_prev, h_local, y_stage, residual, f_stage, residual_ok)
               if (.not. residual_ok) exit

               res_norm = sqrt(sum(residual*residual)/real(3*n_local, dp))
               state_norm = sqrt(sum(y_stage*y_stage)/real(3*n_local, dp))
               tol_newton = max(at, min_tol_abs_use) + max(rt, min_tol_rel_use)*max(1.0_dp, state_norm)
               tol_newton = max(tol_newton, 10.0_dp*epsilon(1.0_dp))
               if (res_norm <= tol_newton) then
                  step_converged = .true.
                  exit
               end if

               call solve_linear_gmres_radau(y_prev, h_local, y_stage, f_stage, -residual, delta, linear_ok)
               if (.not. linear_ok .or. vector_has_invalid(delta)) then
                  last_fail_code = radau_step_fail_linear
                  exit
               end if
               delta_norm = sqrt(sum(delta*delta)/real(3*n_local, dp))

               accepted = .false.
               alpha = 1.0_dp
               do i_damp = 1, max_damp
                  do i_stage = 1, 3
                     off = (i_stage - 1)*n_local
                     y_trial(:, i_stage) = y_stage(:, i_stage) + alpha*delta(off + 1:off + n_local)
                  end do
                  call evaluate_stage_residual(y_prev, h_local, y_trial, residual_trial, f_trial, residual_ok)
                  if (residual_ok) then
                     res_trial_norm = sqrt(sum(residual_trial*residual_trial)/real(3*n_local, dp))
                     step_trial_norm = alpha*delta_norm
                     if (res_trial_norm <= (1.0_dp - 1.0e-4_dp*alpha)*res_norm .or. &
                         (res_trial_norm <= (1.0_dp + 1.0e-3_dp)*res_norm .and. step_trial_norm <= 0.5_dp*tol_newton)) then
                        y_stage = y_trial
                        accepted = .true.
                        exit
                     end if
                  end if
                  alpha = 0.5_dp*alpha
               end do

               if (.not. accepted) exit
            end do

            if (.not. step_converged) then
               call evaluate_stage_residual(y_prev, h_local, y_stage, residual, f_stage, residual_ok)
               if (residual_ok) then
                  res_norm = sqrt(sum(residual*residual)/real(3*n_local, dp))
                  state_norm = sqrt(sum(y_stage*y_stage)/real(3*n_local, dp))
                  tol_newton = max(at, min_tol_abs_use) + max(rt, min_tol_rel_use)*max(1.0_dp, state_norm)
                  if (robust_mode_use > 0) then
                     if (res_norm <= 100.0_dp*tol_newton) step_converged = .true.
                  else
                     if (res_norm <= 10.0_dp*tol_newton) step_converged = .true.
                  end if
               end if
            end if

            if (step_converged) exit
         end do

         if (step_converged) then
            ok = .true.
            fail_code = radau_step_ok
            y_out = y_stage(:, 3)
         else
            ok = .false.
            fail_code = last_fail_code
            y_out = y_prev
         end if

         deallocate (f0, y_stage, y_trial, f_stage, f_trial, residual, residual_trial, delta)
      end subroutine radau5_step

      subroutine evaluate_stage_residual(y_prev, h_local, y_stage, residual, f_stage, ok)
         implicit none
         real(dp), intent(in) :: y_prev(:), h_local, y_stage(:, :)
         real(dp), intent(out) :: residual(:), f_stage(:, :)
         logical, intent(out) :: ok

         integer :: n_local, i_stage, j_stage, off

         n_local = size(y_prev)
         do j_stage = 1, 3
            f_stage(:, j_stage) = f(y_stage(:, j_stage))
            if (vector_has_invalid(f_stage(:, j_stage))) then
               ok = .false.
               residual = 0.0_dp
               return
            end if
         end do

         do i_stage = 1, 3
            off = (i_stage - 1)*n_local
            residual(off + 1:off + n_local) = y_stage(:, i_stage) - y_prev
            do j_stage = 1, 3
               residual(off + 1:off + n_local) = residual(off + 1:off + n_local) - h_local*a_radau(i_stage, j_stage)*f_stage(:, j_stage)
            end do
         end do

         ok = .not. vector_has_invalid(residual)
      end subroutine evaluate_stage_residual

      subroutine solve_linear_gmres_radau(y_prev, h_local, y_stage, f_stage, b, delta, ok)
         implicit none
         real(dp), intent(in) :: y_prev(:), h_local, y_stage(:, :), f_stage(:, :), b(:)
         real(dp), intent(out) :: delta(:)
         logical, intent(out) :: ok

         integer, parameter :: krylov_max_base = 120
         real(dp), parameter :: min_linear_tol_base = 1.0e-12_dp
         integer :: n_local, n_sys, m, i, j, k, m_max
         real(dp) :: beta, linear_tol, residual_lin, tmp1, tmp2
         real(dp) :: min_linear_tol_use, rel_linear_factor
         logical :: jv_ok
         real(dp), allocatable :: v(:, :), hess(:, :), cs(:), sn(:), g(:)
         real(dp), allocatable :: w(:), rhs_upper(:), yk(:), y_pert(:, :), f_pert(:, :)

         n_local = size(y_prev)
         n_sys = 3*n_local
         if (robust_mode_use > 0) then
            m_max = 220
            min_linear_tol_use = 1.0e-13_dp
            rel_linear_factor = 2.0e-3_dp
         else
            m_max = krylov_max_base
            min_linear_tol_use = min_linear_tol_base
            rel_linear_factor = 1.0e-2_dp
         end if
         m = min(m_max, n_sys)
         delta = 0.0_dp

         beta = sqrt(sum(b*b))
         if (.not. ieee_is_finite(beta)) then
            ok = .false.
            return
         end if
         if (beta <= min_linear_tol_use) then
            ok = .true.
            return
         end if

         linear_tol = max(min_linear_tol_use, rel_linear_factor*beta)

         allocate (v(n_sys, m + 1), hess(m + 1, m), cs(m), sn(m), g(m + 1))
         allocate (w(n_sys), rhs_upper(m), yk(m), y_pert(n_local, 3), f_pert(n_local, 3))
         v = 0.0_dp
         hess = 0.0_dp
         cs = 0.0_dp
         sn = 0.0_dp
         g = 0.0_dp

         v(:, 1) = b/beta
         g(1) = beta
         k = m

         do j = 1, m
            call apply_jacobian_vec_fd_radau(y_prev, h_local, y_stage, f_stage, v(:, j), w, y_pert, f_pert, jv_ok)
            if (.not. jv_ok) then
               ok = .false.
               deallocate (v, hess, cs, sn, g, w, rhs_upper, yk, y_pert, f_pert)
               return
            end if

            do i = 1, j
               hess(i, j) = dot_product(v(:, i), w)
               w = w - hess(i, j)*v(:, i)
            end do
            hess(j + 1, j) = sqrt(sum(w*w))
            if (hess(j + 1, j) > tiny(1.0_dp)) v(:, j + 1) = w/hess(j + 1, j)

            do i = 1, j - 1
               tmp1 = cs(i)*hess(i, j) + sn(i)*hess(i + 1, j)
               tmp2 = -sn(i)*hess(i, j) + cs(i)*hess(i + 1, j)
               hess(i, j) = tmp1
               hess(i + 1, j) = tmp2
            end do

            call build_givens_rotation_radau(hess(j, j), hess(j + 1, j), cs(j), sn(j))
            tmp1 = cs(j)*hess(j, j) + sn(j)*hess(j + 1, j)
            tmp2 = -sn(j)*hess(j, j) + cs(j)*hess(j + 1, j)
            hess(j, j) = tmp1
            hess(j + 1, j) = tmp2

            tmp1 = cs(j)*g(j) + sn(j)*g(j + 1)
            tmp2 = -sn(j)*g(j) + cs(j)*g(j + 1)
            g(j) = tmp1
            g(j + 1) = tmp2

            residual_lin = abs(g(j + 1))
            if (residual_lin <= linear_tol) then
               k = j
               exit
            end if
         end do

         rhs_upper(1:k) = g(1:k)
         do i = k, 1, -1
            if (abs(hess(i, i)) <= tiny(1.0_dp)) then
               ok = .false.
               deallocate (v, hess, cs, sn, g, w, rhs_upper, yk, y_pert, f_pert)
               return
            end if
            if (i < k) rhs_upper(i) = rhs_upper(i) - dot_product(hess(i, i + 1:k), rhs_upper(i + 1:k))
            rhs_upper(i) = rhs_upper(i)/hess(i, i)
         end do

         yk(1:k) = rhs_upper(1:k)
         delta = 0.0_dp
         do i = 1, k
            delta = delta + yk(i)*v(:, i)
         end do

         ok = .not. vector_has_invalid(delta)
         deallocate (v, hess, cs, sn, g, w, rhs_upper, yk, y_pert, f_pert)
      end subroutine solve_linear_gmres_radau

      subroutine apply_jacobian_vec_fd_radau(y_prev, h_local, y_stage, f_stage, v, jv, y_pert, f_pert, ok)
         implicit none
         real(dp), intent(in) :: y_prev(:), h_local, y_stage(:, :), f_stage(:, :), v(:)
         real(dp), intent(out) :: jv(:), y_pert(:, :), f_pert(:, :)
         logical, intent(out) :: ok

         integer :: n_local, i_stage, j_stage, off_i, off_j
         real(dp) :: v_norm, stage_norm, eps_fd
         logical :: used_exact, exact_ok

         n_local = size(y_prev)
         v_norm = sqrt(sum(v*v))
         if (v_norm <= tiny(1.0_dp)) then
            jv = 0.0_dp
            ok = .true.
            return
         end if

         call apply_jacobian_vec_exact_flowz(h_local, y_stage, v, jv, used_exact, exact_ok)
         if (used_exact .and. exact_ok) then
            ok = .true.
            return
         end if

         stage_norm = sqrt(sum(y_stage*y_stage)/real(3*n_local, dp))
         eps_fd = sqrt(epsilon(1.0_dp))*max(1.0_dp, stage_norm)/max(v_norm, 1.0e-14_dp)

         do j_stage = 1, 3
            off_j = (j_stage - 1)*n_local
            y_pert(:, j_stage) = y_stage(:, j_stage) + eps_fd*v(off_j + 1:off_j + n_local)
            f_pert(:, j_stage) = f(y_pert(:, j_stage))
            if (vector_has_invalid(f_pert(:, j_stage))) then
               ok = .false.
               jv = 0.0_dp
               return
            end if
         end do

         do i_stage = 1, 3
            off_i = (i_stage - 1)*n_local
            jv(off_i + 1:off_i + n_local) = v(off_i + 1:off_i + n_local)
            do j_stage = 1, 3
               jv(off_i + 1:off_i + n_local) = jv(off_i + 1:off_i + n_local) - &
                                               h_local*a_radau(i_stage, j_stage)*(f_pert(:, j_stage) - f_stage(:, j_stage))/eps_fd
            end do
         end do

         ok = .not. vector_has_invalid(jv)
      end subroutine apply_jacobian_vec_fd_radau

      subroutine apply_jacobian_vec_exact_flowz(h_local, y_stage, v, jv, used_exact, ok)
         implicit none
         real(dp), intent(in) :: h_local, y_stage(:, :), v(:)
         real(dp), intent(out) :: jv(:)
         logical, intent(out) :: used_exact, ok

         integer :: n_local, n_complex
         integer :: i, i_stage, j_stage, off_i, off_j
         real(dp) :: sign_scale
         complex(dp), allocatable :: z_stage(:), dz(:), hv(:)
         real(dp), allocatable :: dfv(:, :)

         used_exact = .false.
         ok = .false.
         if (intode_current_context /= intode_ctx_flowz .and. intode_current_context /= intode_ctx_flowzr) return

         n_local = size(y_stage, 1)
         if (size(y_stage, 2) /= 3) return
         if (size(v) /= 3*n_local .or. size(jv) /= 3*n_local) return
         if (mod(n_local, 2) /= 0) return
         n_complex = n_local/2
         if (n_complex <= 0) return

         used_exact = .true.
         if (intode_current_context == intode_ctx_flowz) then
            sign_scale = 1.0_dp
         else
            sign_scale = -1.0_dp
         end if

         allocate (z_stage(n_complex), dz(n_complex), hv(n_complex), dfv(n_local, 3))
         do j_stage = 1, 3
            off_j = (j_stage - 1)*n_local
            call real_to_complex_vec_fast(y_stage(:, j_stage), z_stage)
            call real_to_complex_vec_fast(v(off_j + 1:off_j + n_local), dz)
            call hessian_vec(z_stage, dz, hv)

            do i = 1, n_complex
               dfv(2*i - 1, j_stage) = sign_scale*real(hv(i), dp)
               dfv(2*i, j_stage) = sign_scale*aimag(hv(i))
            end do
            if (vector_has_invalid(dfv(:, j_stage))) then
               deallocate (z_stage, dz, hv, dfv)
               return
            end if
         end do

         do i_stage = 1, 3
            off_i = (i_stage - 1)*n_local
            jv(off_i + 1:off_i + n_local) = v(off_i + 1:off_i + n_local)
            do j_stage = 1, 3
               jv(off_i + 1:off_i + n_local) = jv(off_i + 1:off_i + n_local) - h_local*a_radau(i_stage, j_stage)*dfv(:, j_stage)
            end do
         end do

         ok = .not. vector_has_invalid(jv)
         deallocate (z_stage, dz, hv, dfv)
      end subroutine apply_jacobian_vec_exact_flowz

      subroutine build_givens_rotation_radau(a, b, c, s)
         implicit none
         real(dp), intent(in) :: a, b
         real(dp), intent(out) :: c, s
         real(dp) :: t

         if (abs(b) <= tiny(1.0_dp)) then
            c = 1.0_dp
            s = 0.0_dp
         else if (abs(a) <= tiny(1.0_dp)) then
            c = 0.0_dp
            s = 1.0_dp
         else if (abs(b) > abs(a)) then
            t = a/b
            s = sign(1.0_dp/sqrt(1.0_dp + t*t), b)
            c = t*s
         else
            t = b/a
            c = sign(1.0_dp/sqrt(1.0_dp + t*t), a)
            s = t*c
         end if
      end subroutine build_givens_rotation_radau

      subroutine estimate_step_error_radau(y_full_local, y_half_local, err_local)
         implicit none
         real(dp), intent(in) :: y_full_local(:), y_half_local(:)
         real(dp), intent(out) :: err_local
         integer :: i_local, n_local
         real(dp) :: errsum_local, scale_local, diff_local

         n_local = size(y_full_local)
         errsum_local = 0.0_dp
         do i_local = 1, n_local
            scale_local = at + rt*max(abs(y_half_local(i_local)), abs(y_full_local(i_local)))
            scale_local = max(scale_local, tiny(1.0_dp))
            diff_local = (y_half_local(i_local) - y_full_local(i_local))/31.0_dp
            errsum_local = errsum_local + (diff_local/scale_local)**2
         end do
         err_local = sqrt(errsum_local/real(n_local, dp))
      end subroutine estimate_step_error_radau

   end subroutine intode_radau5

   subroutine set_intode_strict_mode(enabled)
      implicit none
      logical, intent(in) :: enabled

      intode_strict_mode = enabled
   end subroutine set_intode_strict_mode

   subroutine get_intode_final_resort_policy(enabled, max_uses, fast_hmin_bypass)
      implicit none
      logical, intent(out) :: enabled
      integer, intent(out) :: max_uses
      logical, intent(out) :: fast_hmin_bypass

      enabled = intode_enable_final_resort
      max_uses = intode_final_resort_max_uses
      fast_hmin_bypass = intode_fast_hmin_bypass
   end subroutine get_intode_final_resort_policy

   subroutine set_intode_rattle_trace(rattle_step, rattle_substep)
      implicit none
      integer, intent(in) :: rattle_step, rattle_substep

      intode_trace_rattle_step = max(0, rattle_step)
      intode_trace_rattle_substep = max(0, rattle_substep)
   end subroutine set_intode_rattle_trace

   subroutine set_intode_stage_trace(stage_code)
      implicit none
      integer, intent(in) :: stage_code

      if (stage_code >= intode_stage_unknown .and. stage_code <= intode_stage_external) then
         intode_trace_stage = stage_code
      else
         intode_trace_stage = intode_stage_unknown
      end if
   end subroutine set_intode_stage_trace

   subroutine set_intode_newton_iter_trace(iter_idx)
      implicit none
      integer, intent(in) :: iter_idx

      intode_trace_newton_iter = max(0, iter_idx)
   end subroutine set_intode_newton_iter_trace

   subroutine set_intode_quasi_iter_trace(iter_idx)
      implicit none
      integer, intent(in) :: iter_idx

      intode_trace_quasi_iter = max(0, iter_idx)
   end subroutine set_intode_quasi_iter_trace

   subroutine clear_intode_runtime_trace()
      implicit none

      intode_trace_rattle_step = 0
      intode_trace_rattle_substep = 0
      intode_trace_stage = intode_stage_unknown
      intode_trace_newton_iter = 0
      intode_trace_quasi_iter = 0
   end subroutine clear_intode_runtime_trace

   subroutine reset_intode_fallback_stats()
      implicit none

      intode_calls_total = 0
      intode_calls_integrating = 0
      intode_fallback_attempts = 0
      intode_fallback_success = 0
      intode_fallback_failure = 0
      intode_fallback_max_steps = 0
      intode_fallback_invalid = 0
      intode_fallback_h_min = 0
      intode_fallback_attempts_ctx = 0
      intode_fallback_failures_ctx = 0
      intode_rescue_success_radau_adaptive = 0
      intode_rescue_success_radau_adaptive_robust = 0
      intode_rescue_success_radau_fixed_tol = 0
      intode_rescue_success_radau_chunked = 0
      intode_rescue_success_final_resort = 0
      intode_radau_adapt_newton_fail = 0
      intode_radau_adapt_linear_fail = 0
      intode_radau_adapt_error_reject = 0
      intode_radau_adapt_hmin_hit = 0
      intode_radau_adapt_robust_fail = 0
      intode_radau_fixed_tol_fail = 0
      intode_radau_chunked_fail = 0
      intode_final_resort_fail = 0
      intode_final_resort_log_count = 0
      intode_trace_rattle_step = 0
      intode_trace_rattle_substep = 0
      intode_trace_stage = intode_stage_unknown
      intode_trace_newton_iter = 0
      intode_trace_quasi_iter = 0
      intode_last_failure_available = .false.
      intode_last_failure_reason = intode_reason_none
      intode_last_failure_context = intode_ctx_unknown
      intode_last_failure_rattle_step = 0
      intode_last_failure_rattle_substep = 0
      intode_last_failure_stage = intode_stage_unknown
      intode_last_failure_newton_iter = 0
      intode_last_failure_quasi_iter = 0
      intode_failure_log_count = 0
      intode_last_failure_t = 0.0_dp
      if (allocated(intode_last_failure_y)) deallocate (intode_last_failure_y)
   end subroutine reset_intode_fallback_stats

   subroutine get_intode_fallback_stats(calls_total, calls_integrating, fallback_attempts, fallback_success, fallback_failure, &
                                        fallback_max_steps, fallback_invalid, fallback_h_min)
      implicit none
      integer, intent(out) :: calls_total, calls_integrating
      integer, intent(out) :: fallback_attempts, fallback_success, fallback_failure
      integer, intent(out) :: fallback_max_steps, fallback_invalid, fallback_h_min

      calls_total = intode_calls_total
      calls_integrating = intode_calls_integrating
      fallback_attempts = intode_fallback_attempts
      fallback_success = intode_fallback_success
      fallback_failure = intode_fallback_failure
      fallback_max_steps = intode_fallback_max_steps
      fallback_invalid = intode_fallback_invalid
      fallback_h_min = intode_fallback_h_min
   end subroutine get_intode_fallback_stats

   subroutine get_intode_fallback_context_stats(attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown, &
                                                fail_flowz, fail_flowzr, fail_flow, fail_unknown)
      implicit none
      integer, intent(out) :: attempt_flowz, attempt_flowzr, attempt_flow, attempt_unknown
      integer, intent(out) :: fail_flowz, fail_flowzr, fail_flow, fail_unknown

      attempt_flowz = intode_fallback_attempts_ctx(intode_ctx_flowz)
      attempt_flowzr = intode_fallback_attempts_ctx(intode_ctx_flowzr)
      attempt_flow = intode_fallback_attempts_ctx(intode_ctx_flow)
      attempt_unknown = intode_fallback_attempts_ctx(intode_ctx_unknown)
      fail_flowz = intode_fallback_failures_ctx(intode_ctx_flowz)
      fail_flowzr = intode_fallback_failures_ctx(intode_ctx_flowzr)
      fail_flow = intode_fallback_failures_ctx(intode_ctx_flow)
      fail_unknown = intode_fallback_failures_ctx(intode_ctx_unknown)
   end subroutine get_intode_fallback_context_stats

   subroutine get_intode_rescue_stats(success_radau_adaptive, success_radau_adaptive_robust, success_radau_fixed_tol, &
                                      success_radau_chunked, success_final_resort, fail_radau_adaptive_robust, &
                                      fail_radau_fixed_tol, fail_radau_chunked, fail_final_resort)
      implicit none
      integer, intent(out) :: success_radau_adaptive, success_radau_adaptive_robust
      integer, intent(out) :: success_radau_fixed_tol, success_radau_chunked, success_final_resort
      integer, intent(out) :: fail_radau_adaptive_robust, fail_radau_fixed_tol, fail_radau_chunked, fail_final_resort

      success_radau_adaptive = intode_rescue_success_radau_adaptive
      success_radau_adaptive_robust = intode_rescue_success_radau_adaptive_robust
      success_radau_fixed_tol = intode_rescue_success_radau_fixed_tol
      success_radau_chunked = intode_rescue_success_radau_chunked
      success_final_resort = intode_rescue_success_final_resort
      fail_radau_adaptive_robust = intode_radau_adapt_robust_fail
      fail_radau_fixed_tol = intode_radau_fixed_tol_fail
      fail_radau_chunked = intode_radau_chunked_fail
      fail_final_resort = intode_final_resort_fail
   end subroutine get_intode_rescue_stats

   subroutine get_intode_radau_diag_stats(adapt_newton_fail, adapt_linear_fail, adapt_error_reject, adapt_hmin_hit)
      implicit none
      integer, intent(out) :: adapt_newton_fail, adapt_linear_fail, adapt_error_reject, adapt_hmin_hit

      adapt_newton_fail = intode_radau_adapt_newton_fail
      adapt_linear_fail = intode_radau_adapt_linear_fail
      adapt_error_reject = intode_radau_adapt_error_reject
      adapt_hmin_hit = intode_radau_adapt_hmin_hit
   end subroutine get_intode_radau_diag_stats

   subroutine get_intode_last_failure_meta(available, reason_code, context_code, state_dim, t_remaining)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: reason_code, context_code, state_dim
      real(dp), intent(out) :: t_remaining

      available = intode_last_failure_available .and. allocated(intode_last_failure_y)
      reason_code = intode_last_failure_reason
      context_code = intode_last_failure_context
      t_remaining = intode_last_failure_t
      if (allocated(intode_last_failure_y)) then
         state_dim = size(intode_last_failure_y)
      else
         state_dim = 0
      end if
   end subroutine get_intode_last_failure_meta

   subroutine get_intode_last_failure_trace(available, rattle_step, rattle_substep, stage_code, newton_iter, quasi_iter)
      implicit none
      logical, intent(out) :: available
      integer, intent(out) :: rattle_step, rattle_substep, stage_code, newton_iter, quasi_iter

      available = intode_last_failure_available
      rattle_step = intode_last_failure_rattle_step
      rattle_substep = intode_last_failure_rattle_substep
      stage_code = intode_last_failure_stage
      newton_iter = intode_last_failure_newton_iter
      quasi_iter = intode_last_failure_quasi_iter
   end subroutine get_intode_last_failure_trace

   subroutine run_intode_last_failure_radau_sweep()
      implicit none
      integer, parameter :: n_cases = 10
      integer, parameter :: nsteps_cases(n_cases) = [64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768]
      integer :: i, n_steps, n_dim
      integer :: reason_code, context_code
      integer :: n_complex_local, n_jac_local
      integer :: prev_context
      logical :: available, dims_ok
      logical :: fail_n, fail_2n, ok_n, ok_2n, accepted
      logical :: prev_capture
      real(dp) :: t_local, err_est
      character(len=16) :: err_label
      real(dp), allocatable :: y0(:), y_n(:), y_2n(:)

      call get_intode_last_failure_meta(available, reason_code, context_code, n_dim, t_local)
      if (.not. available) then
         write (*, '(A)') "[SWEEP] No stored intode failure snapshot."
         return
      end if
      if (context_code == intode_ctx_unknown) then
         write (*, '(A)') "[SWEEP] Last failure context is unknown; replay sweep skipped."
         return
      end if

      call infer_context_dimensions(context_code, n_dim, n_complex_local, n_jac_local, dims_ok)
      if (.not. dims_ok) then
         write (*, '(A,I0,A,I0)') "[SWEEP] Snapshot dimension/context mismatch: dim=", n_dim, " context=", context_code
         return
      end if

      allocate (y0(n_dim), y_n(n_dim), y_2n(n_dim))
      y0 = intode_last_failure_y(1:n_dim)
      err_est = huge(1.0_dp)

      write (*, '(A,A,A,A,A,ES12.4)') "[SWEEP] Replaying last failure: reason=", trim(reason_name(reason_code)), &
         " context=", trim(context_name(context_code)), " t_remaining=", t_local
      write (*, '(A)') "[SWEEP] n_steps  ok(N)  ok(2N)  err_est          accept(tol)"

      prev_context = intode_current_context
      prev_capture = intode_capture_failures
      intode_current_context = context_code
      intode_capture_failures = .false.

      do i = 1, n_cases
         n_steps = nsteps_cases(i)

         call intode_radau5(rhs_snapshot, y0, t_local, y_n, fail_n, n_steps=n_steps)
         ok_n = (.not. fail_n) .and. (.not. vector_has_invalid(y_n))

         call intode_radau5(rhs_snapshot, y0, t_local, y_2n, fail_2n, n_steps=2*n_steps)
         ok_2n = (.not. fail_2n) .and. (.not. vector_has_invalid(y_2n))

         err_est = huge(1.0_dp)
         accepted = .false.
         if (ok_n .and. ok_2n) then
            call estimate_pair_error(y_n, y_2n, err_est)
            accepted = ieee_is_finite(err_est) .and. (err_est <= 1.0_dp)
         end if

         if (ok_n .and. ok_2n .and. ieee_is_finite(err_est)) then
            write (err_label, '(ES16.6)') err_est
         else
            err_label = "n/a"
         end if
         write (*, '(1X,I7,2X,L1,5X,L1,2X,A16,2X,L1)') n_steps, ok_n, ok_2n, adjustl(err_label), accepted
      end do

      intode_capture_failures = prev_capture
      intode_current_context = prev_context
      deallocate (y0, y_n, y_2n)

   contains

      function rhs_snapshot(y) result(f)
         implicit none
         real(dp), intent(in) :: y(:)
         real(dp) :: f(size(y))
         integer :: col
         real(dp) :: sign_scale

         select case (context_code)
         case (intode_ctx_flowz, intode_ctx_flowzr)
            if (context_code == intode_ctx_flowz) then
               sign_scale = 1.0_dp
            else
               sign_scale = -1.0_dp
            end if

            call ensure_complex_workspace(flow_vec_z, n_complex_local)
            call ensure_complex_workspace(flow_vec_ds, n_complex_local)
            call real_to_complex_vec_fast(y, flow_vec_z(1:n_complex_local))
            call ds(flow_vec_z(1:n_complex_local), flow_vec_ds(1:n_complex_local))
            call complex_to_real_vec_conjg_scaled_fast(flow_vec_ds(1:n_complex_local), f, sign_scale)

         case (intode_ctx_flow)
            sign_scale = 1.0_dp

            call ensure_complex_workspace(flow_jac_z, n_complex_local)
            call ensure_complex_workspace(flow_jac_ds, n_complex_local)
            call ensure_complex_workspace_mat(flow_jac_j, n_jac_local, n_jac_local)
            call ensure_complex_workspace_mat(flow_jac_jprod, n_jac_local, n_jac_local)

            call real_to_complex_vec_fast(y(1:2*n_complex_local), flow_jac_z(1:n_complex_local))
            call real_to_complex_mat_rowmajor_fast(y(2*n_complex_local + 1:), flow_jac_j(1:n_jac_local, 1:n_jac_local))
            call ds(flow_jac_z(1:n_complex_local), flow_jac_ds(1:n_complex_local))
            call complex_to_real_vec_conjg_scaled_fast(flow_jac_ds(1:n_complex_local), f(1:2*n_complex_local), sign_scale)
            do col = 1, n_jac_local
               call hessian_vec(flow_jac_z(1:n_complex_local), flow_jac_j(1:n_jac_local, col), flow_jac_jprod(1:n_jac_local, col))
            end do
            call map_to_real_conjg_scaled(flow_jac_jprod(1:n_jac_local, 1:n_jac_local), f(2*n_complex_local + 1:), sign_scale)

         case default
            f = 0.0_dp
         end select
      end function rhs_snapshot

      subroutine estimate_pair_error(y_coarse, y_fine, err_local)
         implicit none
         real(dp), intent(in) :: y_coarse(:), y_fine(:)
         real(dp), intent(out) :: err_local
         integer :: i_local
         real(dp) :: scale_local, diff_local, errsum_local

         errsum_local = 0.0_dp
         do i_local = 1, size(y_coarse)
            scale_local = at + rt*max(abs(y_fine(i_local)), abs(y_coarse(i_local)))
            scale_local = max(scale_local, tiny(1.0_dp))
            diff_local = (y_fine(i_local) - y_coarse(i_local))/31.0_dp
            errsum_local = errsum_local + (diff_local/scale_local)**2
         end do
         err_local = sqrt(errsum_local/real(size(y_coarse), dp))
      end subroutine estimate_pair_error

      subroutine infer_context_dimensions(ctx_code, dim_total, n_complex, n_jac, ok)
         implicit none
         integer, intent(in) :: ctx_code, dim_total
         integer, intent(out) :: n_complex, n_jac
         logical, intent(out) :: ok
         integer :: disc, n_try

         n_complex = 0
         n_jac = 0
         ok = .false.

         select case (ctx_code)
         case (intode_ctx_flowz, intode_ctx_flowzr)
            if (mod(dim_total, 2) /= 0) return
            n_complex = dim_total/2
            n_jac = n_complex
            ok = (n_complex > 0)

         case (intode_ctx_flow)
            disc = 1 + 2*dim_total
            n_try = int(0.5_dp*(sqrt(real(disc, dp)) - 1.0_dp) + 0.5_dp)
            if (n_try <= 0) return
            if (2*n_try*(n_try + 1) /= dim_total) return
            n_complex = n_try
            n_jac = n_try
            ok = .true.

         case default
            ok = .false.
         end select
      end subroutine infer_context_dimensions

      function reason_name(reason) result(name)
         implicit none
         integer, intent(in) :: reason
         character(len=20) :: name

         select case (reason)
         case (intode_reason_max_steps)
            name = "max_steps"
         case (intode_reason_invalid)
            name = "invalid"
         case (intode_reason_h_min)
            name = "h_min"
         case default
            name = "unknown"
         end select
      end function reason_name

      function context_name(ctx_code) result(name)
         implicit none
         integer, intent(in) :: ctx_code
         character(len=20) :: name

         select case (ctx_code)
         case (intode_ctx_flowz)
            name = "flowz"
         case (intode_ctx_flowzr)
            name = "flowzr"
         case (intode_ctx_flow)
            name = "flow"
         case default
            name = "unknown"
         end select
      end function context_name

   end subroutine run_intode_last_failure_radau_sweep

   function vector_has_invalid(values) result(has_invalid)
      implicit none
      real(dp), intent(in) :: values(:)
      logical :: has_invalid
      integer :: idx

      has_invalid = .false.
      do idx = 1, size(values)
         if (.not. ieee_is_finite(values(idx))) then
            has_invalid = .true.
            return
         end if
      end do
   end function vector_has_invalid

   subroutine flowz(x, z, error)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer::n, n_complex
      real(dp)::t1
      real(dp) :: t_prof

      call perf_tic(t_prof)
      n = size(z)*2
      n_complex = size(z)
      t1 = x(1)
      error = .false.

      call ensure_real_workspace(flow_vec_y, n)
      call ensure_real_workspace(flow_vec_yf, n)
      call ensure_complex_workspace(flow_vec_z, n_complex)
      call ensure_complex_workspace(flow_vec_ds, n_complex)

      flow_vec_y(1:n:2) = x(2:)
      flow_vec_y(2:n:2) = 0.0_dp
      intode_current_context = intode_ctx_flowz
      flow_vec_rhs_scale = 1.0_dp
      call intode(rhs_flow_vec, flow_vec_y(1:n), t1, flow_vec_yf(1:n), error)
      intode_current_context = intode_ctx_unknown
      if (error) then
         call perf_toc(PERF_FLOWZ, t_prof)
         return
      end if
      call real_to_complex(flow_vec_yf(1:n), z)
      call perf_toc(PERF_FLOWZ, t_prof)
   end subroutine flowz

   subroutine flowzr(x, z, error)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      logical, intent(out)::error
      integer::n, n_complex
      real(dp)::t1
      real(dp) :: t_prof

      call perf_tic(t_prof)
      n = size(z)*2
      n_complex = size(z)
      t1 = x(1)
      error = .false.

      call ensure_real_workspace(flow_vec_y, n)
      call ensure_real_workspace(flow_vec_yf, n)
      call ensure_complex_workspace(flow_vec_z, n_complex)
      call ensure_complex_workspace(flow_vec_ds, n_complex)

      call complex_to_real(z, flow_vec_y(1:n))
      intode_current_context = intode_ctx_flowzr
      flow_vec_rhs_scale = -1.0_dp
      call intode(rhs_flow_vec, flow_vec_y(1:n), t1, flow_vec_yf(1:n), error)
      intode_current_context = intode_ctx_unknown
      flow_vec_rhs_scale = 1.0_dp
      if (error) then
         call perf_toc(PERF_FLOWZR, t_prof)
         return
      end if
      call real_to_complex(flow_vec_yf(1:n), z)
      call perf_toc(PERF_FLOWZR, t_prof)
   end subroutine flowzr

   subroutine flow(x, z, j, error)
      real(dp), intent(in)::x(:)
      complex(dp), intent(inout)::z(:)
      complex(dp), dimension(:, :), intent(inout)::j
      logical, intent(out)::error
      integer::n, m, n_complex, n_jac
      integer :: total_n
      real(dp)::t1
      real(dp) :: t_prof

      call perf_tic(t_prof)
      n = size(z)*2
      n_complex = size(z)
      n_jac = size(j, 1)
      m = size(j, 1)*size(j, 2)*2
      total_n = n + m
      t1 = x(1)
      error = .false.

      call ensure_real_workspace(flow_jac_y, total_n)
      call ensure_real_workspace(flow_jac_yf, total_n)
      call ensure_complex_workspace(flow_jac_z, n_complex)
      call ensure_complex_workspace(flow_jac_ds, n_complex)
      call ensure_complex_workspace_mat(flow_jac_j, n_jac, n_jac)
      call ensure_complex_workspace_mat(flow_jac_jprod, n_jac, n_jac)

      flow_jac_y(1:n:2) = x(2:)
      flow_jac_y(2:n:2) = 0.0_dp
      call fill_identity_real_map(flow_jac_y(n + 1:total_n), n_jac)
      intode_current_context = intode_ctx_flow
      call intode(rhs_flow_jac, flow_jac_y(1:total_n), t1, flow_jac_yf(1:total_n), error)
      intode_current_context = intode_ctx_unknown
      if (error) then
         call perf_toc(PERF_FLOW, t_prof)
         return
      end if
      call real_to_complex(flow_jac_yf(1:n), z)
      call map_to_complex(flow_jac_yf(n + 1:total_n), j)
      call perf_toc(PERF_FLOW, t_prof)
   end subroutine flow

   function rhs_flow_vec(y) result(f)
      implicit none
      real(dp), intent(in) :: y(:)
      real(dp) :: f(size(y))
      integer :: n_complex

      f = 0.0_dp
      if (.not. allocated(flow_vec_z) .or. .not. allocated(flow_vec_ds)) return
      n_complex = size(flow_vec_z)
      if (size(y) /= 2*n_complex) return

      call real_to_complex_vec_fast(y, flow_vec_z(1:n_complex))
      call ds(flow_vec_z(1:n_complex), flow_vec_ds(1:n_complex))
      call complex_to_real_vec_conjg_scaled_fast(flow_vec_ds(1:n_complex), f, flow_vec_rhs_scale)
   end function rhs_flow_vec

   function rhs_flow_jac(y) result(f)
      implicit none
      real(dp), intent(in) :: y(:)
      real(dp) :: f(size(y))
      integer :: col
      integer :: n_complex, n_jac, n

      f = 0.0_dp
      if (.not. allocated(flow_jac_z) .or. .not. allocated(flow_jac_ds)) return
      if (.not. allocated(flow_jac_j) .or. .not. allocated(flow_jac_jprod)) return

      n_complex = size(flow_jac_z)
      n_jac = size(flow_jac_j, 1)
      n = 2*n_complex
      if (size(flow_jac_j, 2) /= n_jac .or. size(flow_jac_jprod, 1) /= n_jac .or. size(flow_jac_jprod, 2) /= n_jac) return
      if (size(y) /= n + 2*n_jac*n_jac) return

      call real_to_complex_vec_fast(y(1:n), flow_jac_z(1:n_complex))
      call real_to_complex_mat_rowmajor_fast(y(n + 1:), flow_jac_j(1:n_jac, 1:n_jac))
      call ds(flow_jac_z(1:n_complex), flow_jac_ds(1:n_complex))
      call complex_to_real_vec_conjg_scaled_fast(flow_jac_ds(1:n_complex), f(1:n), 1.0_dp)
      do col = 1, n_jac
         call hessian_vec(flow_jac_z(1:n_complex), flow_jac_j(1:n_jac, col), flow_jac_jprod(1:n_jac, col))
      end do
      call map_to_real_conjg_scaled(flow_jac_jprod(1:n_jac, 1:n_jac), f(n + 1:), 1.0_dp)
   end function rhs_flow_jac

   subroutine map_to_real_conjg_scaled(mat, vec, scale)
      implicit none
      complex(dp), intent(in) :: mat(:, :)
      real(dp), intent(out) :: vec(:)
      real(dp), intent(in) :: scale
      integer :: i, j, n

      n = size(mat, 1)
      if (size(mat, 2) /= n) then
         write (*, *) "Error(map_to_real_conjg_scaled): mat is not square."
         return
      end if
      if (size(vec) /= 2*n*n) then
         write (*, *) "Error(map_to_real_conjg_scaled): vec must have length=2*n*n."
         return
      end if

      do i = 1, n
         do j = 1, n
            vec(2*((i - 1)*n + j) - 1) = scale*real(mat(i, j), dp)
            vec(2*((i - 1)*n + j)) = -scale*aimag(mat(i, j))
         end do
      end do
   end subroutine map_to_real_conjg_scaled

   subroutine real_to_complex_vec_fast(r, c)
      implicit none
      real(dp), intent(in) :: r(:)
      complex(dp), intent(out) :: c(:)
      integer :: i

      do i = 1, size(c)
         c(i) = cmplx(r(2*i - 1), r(2*i), dp)
      end do
   end subroutine real_to_complex_vec_fast

   subroutine complex_to_real_vec_conjg_scaled_fast(c, r, scale)
      implicit none
      complex(dp), intent(in) :: c(:)
      real(dp), intent(out) :: r(:)
      real(dp), intent(in) :: scale
      integer :: i

      do i = 1, size(c)
         r(2*i - 1) = scale*real(c(i), dp)
         r(2*i) = -scale*aimag(c(i))
      end do
   end subroutine complex_to_real_vec_conjg_scaled_fast

   subroutine real_to_complex_mat_rowmajor_fast(vec, mat)
      implicit none
      real(dp), intent(in) :: vec(:)
      complex(dp), intent(out) :: mat(:, :)
      integer :: i, j, n, idx

      n = size(mat, 1)
      idx = 1
      do i = 1, n
         do j = 1, n
            mat(i, j) = cmplx(vec(idx), vec(idx + 1), dp)
            idx = idx + 2
         end do
      end do
   end subroutine real_to_complex_mat_rowmajor_fast

   subroutine ensure_odex_workspace(k_need, n_need)
      implicit none
      integer, intent(in) :: k_need, n_need

      if (.not. allocated(odex_T)) then
         allocate (odex_T(k_need, k_need, n_need))
      elseif (size(odex_T, 1) < k_need .or. size(odex_T, 2) < k_need .or. size(odex_T, 3) < n_need) then
         deallocate (odex_T)
         allocate (odex_T(k_need, k_need, n_need))
      end if

      call ensure_real_workspace(odex_yprev, n_need)
      call ensure_real_workspace(odex_ycurr, n_need)
      call ensure_real_workspace(odex_ynext, n_need)
      call ensure_real_workspace(odex_fval, n_need)
      call ensure_real_workspace(odex_fbase, n_need)
   end subroutine ensure_odex_workspace

   subroutine ensure_real_workspace(buf, n_need)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_real_workspace

   subroutine ensure_complex_workspace(buf, n_need)
      implicit none
      complex(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_complex_workspace

   subroutine ensure_complex_workspace_mat(buf, nr_need, nc_need)
      implicit none
      complex(dp), allocatable, intent(inout) :: buf(:, :)
      integer, intent(in) :: nr_need, nc_need

      if (.not. allocated(buf)) then
         allocate (buf(nr_need, nc_need))
      elseif (size(buf, 1) < nr_need .or. size(buf, 2) < nc_need) then
         deallocate (buf)
         allocate (buf(nr_need, nc_need))
      end if
   end subroutine ensure_complex_workspace_mat

   subroutine fill_identity_real_map(vec, n)
      implicit none
      real(dp), intent(out) :: vec(:)
      integer, intent(in) :: n
      integer :: i, idx

      if (size(vec) /= 2*n*n) then
         write (*, '(A)') "[ERROR] fill_identity_real_map: vec must have size 2*n*n."
         return
      end if

      vec = 0.0_dp
      do i = 1, n
         idx = 2*((i - 1)*n + i) - 1
         vec(idx) = 1.0_dp
      end do
   end subroutine fill_identity_real_map
end module solve_flow

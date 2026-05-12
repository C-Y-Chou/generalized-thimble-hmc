module odex_backend
   use utils, only: dp
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   implicit none
   private

   integer, parameter, public :: odex_max_steps_default = 200000
   integer, parameter, public :: odex_k_min = 4
   integer, parameter, public :: odex_k_max = 10
   integer, parameter, public :: odex_cache_size = odex_k_max + 1
   integer, parameter, public :: odex_reason_none = 0
   integer, parameter, public :: odex_reason_max_steps = 1
   integer, parameter, public :: odex_reason_invalid = 2
   integer, parameter, public :: odex_reason_h_min = 3
   integer, parameter, public :: odex_status_unknown = -1
   integer, parameter, public :: odex_status_success = 0
   integer, parameter, public :: odex_status_success_zero_time = 1
   integer, parameter, public :: odex_status_failure_max_steps = 101
   integer, parameter, public :: odex_status_failure_invalid = 102
   integer, parameter, public :: odex_status_failure_h_min = 103
   integer, parameter, public :: odex_step_sequence_iwork3 = 3
   integer, parameter, public :: odex_stability_control_none = 0
   integer, parameter, public :: odex_stability_control_conservative = 1

   type, public :: odex_options
      real(dp) :: abs_tol = 0.0_dp
      real(dp) :: rel_tol = 0.0_dp
      integer :: k_min = odex_k_min
      integer :: k_max = odex_k_max
      integer :: max_steps = odex_max_steps_default
      integer :: step_sequence = odex_step_sequence_iwork3
      integer :: stability_control = odex_stability_control_none
      logical :: endpoint_only = .true.
      real(dp) :: h_min_c_fp = 16.0_dp
      real(dp) :: h_min_c_tol = 0.01_dp
      real(dp) :: h_min_c_span = 1.0e-12_dp
      real(dp) :: initial_step_fraction = 0.01_dp
      real(dp) :: stability_growth_limit = 4.0_dp
   end type odex_options

   type, public :: odex_workspace
      real(dp), allocatable :: tableau(:, :, :)
      real(dp), allocatable :: ystate(:), yprev(:), ycurr(:), ynext(:), fval(:), fbase(:)
      integer, allocatable :: nsteps(:)
      real(dp), allocatable :: ak(:), invexp(:), ratio(:, :)
      logical :: tables_ready = .false.
      integer :: table_k = 0
   end type odex_workspace

   type, public :: odex_result
      integer :: status = odex_status_unknown
      integer :: failure_reason = odex_reason_none
      integer :: accepted_steps = 0
      integer :: rejected_steps = 0
      integer :: stability_rejects = 0
      integer :: final_order = 0
      real(dp) :: final_step_size = 0.0_dp
      real(dp) :: t_remaining = 0.0_dp
      logical :: endpoint_available = .false.
   end type odex_result

   abstract interface
      function ode_rhs(y) result(dy)
         import :: dp
         real(dp), intent(in) :: y(:)
         real(dp) :: dy(size(y))
      end function ode_rhs
   end interface
   public :: ode_rhs

   public :: build_nsteps
   public :: odex_default_options
   public :: ensure_odex_workspace_object
   public :: odex_integrate_endpoint
   public :: odex_result_reset
   public :: odex_result_mark_success
   public :: odex_result_mark_failure
   public :: odex_result_to_intode_status
   public :: odex_status_from_failure_reason
   public :: odex_status_is_failure
   public :: odex_status_is_mechanism_status

contains

   subroutine odex_default_options(options, abs_tol, rel_tol)
      type(odex_options), intent(out) :: options
      real(dp), intent(in), optional :: abs_tol, rel_tol

      options%abs_tol = 0.0_dp
      options%rel_tol = 0.0_dp
      if (present(abs_tol)) options%abs_tol = abs_tol
      if (present(rel_tol)) options%rel_tol = rel_tol
      options%k_min = odex_k_min
      options%k_max = odex_k_max
      options%max_steps = odex_max_steps_default
      options%step_sequence = odex_step_sequence_iwork3
      options%stability_control = odex_stability_control_none
      options%endpoint_only = .true.
      options%h_min_c_fp = 16.0_dp
      options%h_min_c_tol = 0.01_dp
      options%h_min_c_span = 1.0e-12_dp
      options%initial_step_fraction = 0.01_dp
      options%stability_growth_limit = 4.0_dp
   end subroutine odex_default_options

   subroutine odex_integrate_endpoint(f, y, t, res, error_flag, result_state, workspace, options)
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      type(odex_result), intent(out) :: result_state
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in), optional :: options

      type(odex_options) :: opts
      real(dp) :: h, tc, er1, h_min, t_new, h_step
      real(dp) :: h_min_fp, h_min_tol, h_min_span
      integer :: state_size, k, step_count, rejected_steps, stability_rejects
      logical :: is_last_step, stability_rejected

      call odex_default_options(opts)
      if (present(options)) opts = options
      call odex_normalize_options(opts)
      call odex_result_reset(result_state)

      state_size = size(y)
      res = y
      error_flag = .true.

      if (size(res) /= state_size .or. state_size <= 0) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if

      if (opts%step_sequence /= odex_step_sequence_iwork3 .or. opts%max_steps <= 0) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if

      if (t == 0.0_dp) then
         error_flag = .false.
         call odex_result_mark_success(result_state, odex_status_success_zero_time, 0, 0, 0.0_dp)
         return
      end if

      call ensure_odex_workspace_object(workspace, opts%k_max + 1, state_size)

      h_min_fp = opts%h_min_c_fp*epsilon(1.0_dp)*max(1.0_dp, abs(t))
      h_min_tol = opts%h_min_c_tol*max(opts%abs_tol, opts%rel_tol, epsilon(1.0_dp))
      h_min_span = opts%h_min_c_span*abs(t)
      h_min = max(h_min_fp, min(h_min_tol, h_min_span))

      tc = 0.0_dp
      workspace%ystate(1:state_size) = y
      h = t*opts%initial_step_fraction
      if (h == 0.0_dp) h = sign(h_min, t)
      k = opts%k_min
      step_count = 0
      rejected_steps = 0
      stability_rejects = 0

      do
         step_count = step_count + 1
         if (step_count > opts%max_steps) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_max_steps, max(0, step_count - 1), &
                                          1 + rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if

         if ((t >= 0.0_dp .and. tc + h >= t) .or. (t < 0.0_dp .and. tc + h <= t)) then
            is_last_step = .true.
            h = t - tc
         else
            is_last_step = .false.
         end if

         t_new = tc + h
         h_step = h
         call odex_step(f, workspace%ystate(1:state_size), h, k, res, er1, workspace, opts, stability_rejected)

         if (vector_has_invalid(res(1:state_size)) .or. .not. ieee_is_finite(h)) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_invalid, max(0, step_count - 1), &
                                          1 + rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if

         if (er1 < 1.0_dp) then
            tc = t_new
            workspace%ystate(1:state_size) = res(1:state_size)
            if (is_last_step) exit
         else
            rejected_steps = rejected_steps + 1
            if (stability_rejected) stability_rejects = stability_rejects + 1
         end if

         if (abs(h) < h_min) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_h_min, max(0, step_count - 1), &
                                          1 + rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if
      end do

      res = workspace%ystate(1:state_size)
      error_flag = .false.
      call odex_result_mark_success(result_state, odex_status_success, step_count, k, h_step)
      result_state%rejected_steps = rejected_steps
      result_state%stability_rejects = stability_rejects
   end subroutine odex_integrate_endpoint

   subroutine odex_step(f, y, h, k, res, err, workspace, opts, stability_rejected)
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:)
      real(dp), intent(inout) :: h
      integer, intent(inout) :: k
      real(dp), intent(out) :: res(:), err
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      logical, intent(out) :: stability_rejected

      integer :: i, j, l, n, ni, k_prev
      real(dp) :: dt, scale, errsum, wk1, wk2, hk1, hk2
      real(dp) :: prev_norm, curr_norm

      n = size(y)
      res = y
      stability_rejected = .false.
      wk1 = 0.0_dp
      wk2 = 0.0_dp
      hk1 = h
      hk2 = h

      workspace%fbase(1:n) = f(y)

      if (vector_has_invalid(workspace%fbase(1:n))) then
         err = huge(1.0_dp)
         res = y
         h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
         k = max(opts%k_min, k - 1)
         return
      end if

      do i = 1, k
         ni = workspace%nsteps(i)
         dt = h/real(ni, dp)

         workspace%yprev(1:n) = y
         workspace%ycurr(1:n) = y + dt*workspace%fbase(1:n)
         prev_norm = vector_rms(workspace%fbase(1:n))

         do l = 2, ni
            workspace%fval(1:n) = f(workspace%ycurr(1:n))
            if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
               stability_rejected = .true.
               err = huge(1.0_dp)
               res = y
               h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
               k = max(opts%k_min, k - 1)
               return
            end if
            curr_norm = vector_rms(workspace%fval(1:n))
            workspace%ynext(1:n) = workspace%yprev(1:n) + 2.0_dp*dt*workspace%fval(1:n)
            workspace%yprev(1:n) = workspace%ycurr(1:n)
            workspace%ycurr(1:n) = workspace%ynext(1:n)
            prev_norm = max(prev_norm, curr_norm)
         end do

         workspace%fval(1:n) = f(workspace%ycurr(1:n))
         if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
            stability_rejected = .true.
            err = huge(1.0_dp)
            res = y
            h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
            k = max(opts%k_min, k - 1)
            return
         end if
         workspace%tableau(i, 1, 1:n) = 0.5_dp*(workspace%yprev(1:n) + workspace%ycurr(1:n) + dt*workspace%fval(1:n))
      end do

      do j = 2, k
         do i = j, k
            workspace%tableau(i, j, 1:n) = workspace%tableau(i, j - 1, 1:n) + &
                                           (workspace%tableau(i, j - 1, 1:n) - workspace%tableau(i - 1, j - 1, 1:n))/ &
                                           workspace%ratio(i, i - j + 1)

            if (i == k - 1 .and. j == k - 1) then
               errsum = 0.0_dp
               do l = 1, n
                  scale = opts%abs_tol + opts%rel_tol*max(abs(workspace%tableau(k - 2, k - 2, l)), &
                                                          abs(workspace%tableau(k - 2, k - 3, l)))
                  scale = max(scale, tiny(1.0_dp))
                  errsum = errsum + ((workspace%tableau(k - 2, k - 2, l) - workspace%tableau(k - 2, k - 3, l))/scale)**2
               end do
               err = sqrt(errsum/real(n, dp))
               wk2 = calculate_wk(h, err, k - 2, workspace)

               errsum = 0.0_dp
               do l = 1, n
                  scale = opts%abs_tol + opts%rel_tol*max(abs(workspace%tableau(k - 1, k - 1, l)), &
                                                          abs(workspace%tableau(k - 1, k - 2, l)))
                  scale = max(scale, tiny(1.0_dp))
                  errsum = errsum + ((workspace%tableau(k - 1, k - 1, l) - workspace%tableau(k - 1, k - 2, l))/scale)**2
               end do
               err = sqrt(errsum/real(n, dp))
               wk1 = calculate_wk(h, err, k - 1, workspace)
               hk1 = calculate_hk(h, err, k - 1, workspace)

               if (err < 1.0_dp) then
                  res = workspace%tableau(k - 1, k - 1, 1:n)
                  if (wk1 > 0.9_dp*wk2) then
                     k = max(opts%k_min, k - 1)
                     h = hk1
                  else
                     h = hk1*workspace%ak(k)/workspace%ak(k - 1)
                  end if
                  return
               else if (err > real((k*k + 1)**2, dp)) then
                  k = max(opts%k_min, k - 1)
                  h = hk1
                  res = y
                  return
               end if
            end if
         end do
      end do

      errsum = 0.0_dp
      do i = 1, n
         scale = opts%abs_tol + opts%rel_tol*max(abs(workspace%tableau(k, k, i)), abs(workspace%tableau(k, k - 1, i)))
         scale = max(scale, tiny(1.0_dp))
         errsum = errsum + ((workspace%tableau(k, k, i) - workspace%tableau(k, k - 1, i))/scale)**2
      end do
      err = sqrt(errsum/real(n, dp))

      hk2 = calculate_hk(h, err, k, workspace)
      wk2 = calculate_wk(h, err, k, workspace)
      if (err < 1.0_dp) then
         res = workspace%tableau(k, k, 1:n)
         if (wk1 < 0.9_dp*wk2) then
            k = max(opts%k_min, k - 1)
            h = hk1
         else if (wk2 < 0.9_dp*wk1) then
            k_prev = k
            k = min(opts%k_max, k + 1)
            if (k > k_prev) then
               h = hk2*workspace%ak(k + 1)/workspace%ak(k)
            else
               h = hk2
            end if
         else
            h = hk2
         end if
         return
      end if

      ni = workspace%nsteps(k + 1)
      dt = h/real(ni, dp)
      workspace%yprev(1:n) = y
      workspace%ycurr(1:n) = y + dt*workspace%fbase(1:n)
      prev_norm = vector_rms(workspace%fbase(1:n))

      do l = 2, ni
         workspace%fval(1:n) = f(workspace%ycurr(1:n))
         if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
            stability_rejected = .true.
            err = huge(1.0_dp)
            res = y
            h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
            k = max(opts%k_min, k - 1)
            return
         end if
         curr_norm = vector_rms(workspace%fval(1:n))
         workspace%ynext(1:n) = workspace%yprev(1:n) + 2.0_dp*dt*workspace%fval(1:n)
         workspace%yprev(1:n) = workspace%ycurr(1:n)
         workspace%ycurr(1:n) = workspace%ynext(1:n)
         prev_norm = max(prev_norm, curr_norm)
      end do

      workspace%fval(1:n) = f(workspace%ycurr(1:n))
      if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
         stability_rejected = .true.
         err = huge(1.0_dp)
         res = y
         h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
         k = max(opts%k_min, k - 1)
         return
      end if
      workspace%tableau(k + 1, 1, 1:n) = 0.5_dp*(workspace%yprev(1:n) + workspace%ycurr(1:n) + dt*workspace%fval(1:n))

      do j = 2, k + 1
         workspace%tableau(k + 1, j, 1:n) = workspace%tableau(k + 1, j - 1, 1:n) + &
                                            (workspace%tableau(k + 1, j - 1, 1:n) - workspace%tableau(k, j - 1, 1:n))/ &
                                            workspace%ratio(k + 1, k - j + 2)
      end do

      errsum = 0.0_dp
      do i = 1, n
         scale = opts%abs_tol + opts%rel_tol*max(abs(workspace%tableau(k + 1, k + 1, i)), &
                                                 abs(workspace%tableau(k + 1, k, i)))
         scale = max(scale, tiny(1.0_dp))
         errsum = errsum + ((workspace%tableau(k + 1, k + 1, i) - workspace%tableau(k + 1, k, i))/scale)**2
      end do
      err = sqrt(errsum/real(n, dp))

      if (err < 1.0_dp) then
         res = workspace%tableau(k + 1, k + 1, 1:n)
         if (wk1 < 0.9_dp*wk2) then
            k = max(opts%k_min, k - 1)
            h = hk1
         else if (wk2 < 0.9_dp*wk1) then
            hk1 = calculate_hk(h, err, k + 1, workspace)
            k = min(opts%k_max, k + 1)
            h = hk1
         else
            h = hk2
         end if
      else
         res = y
         k = max(opts%k_min, k - 1)
         h = hk1
      end if
   end subroutine odex_step

   function calculate_wk(h, er1, k, workspace) result(wk)
      real(dp), intent(in) :: h, er1
      integer, intent(in) :: k
      type(odex_workspace), intent(in) :: workspace
      integer :: kc
      real(dp) :: hk_abs, scale, wk

      kc = max(1, k)
      scale = 0.94_dp*(0.65_dp/max(er1, 1.0e-14_dp))**workspace%invexp(kc)
      hk_abs = abs(h)*scale
      if (.not. ieee_is_finite(hk_abs) .or. hk_abs <= tiny(1.0_dp)) then
         wk = huge(1.0_dp)
      else
         wk = workspace%ak(kc)/hk_abs
      end if
   end function calculate_wk

   function calculate_hk(h, er1, k, workspace) result(hk)
      real(dp), intent(in) :: h, er1
      integer, intent(in) :: k
      type(odex_workspace), intent(in) :: workspace
      integer :: kc
      real(dp) :: hk

      kc = max(1, k)
      hk = h*0.94_dp*(0.65_dp/max(er1, 1.0e-14_dp))**workspace%invexp(kc)
   end function calculate_hk

   function calculate_ak(k) result(ak)
      integer, intent(in) :: k
      integer :: kc, i, w_sum
      real(dp) :: ak

      kc = max(1, k)
      w_sum = 0
      do i = 1, kc
         w_sum = w_sum + odex_iwork3_nstep(i)
      end do
      ak = 1.0_dp + real(w_sum, dp)
   end function calculate_ak

   subroutine build_nsteps(max_k, nsteps)
      integer, intent(in) :: max_k
      integer, intent(out) :: nsteps(max_k)
      integer :: i

      if (max_k < 1) return
      nsteps = 0
      do i = 1, max_k
         nsteps(i) = odex_iwork3_nstep(i)
      end do
   end subroutine build_nsteps

   integer function odex_iwork3_nstep(idx) result(nstep)
      integer, intent(in) :: idx

      if (idx <= 1) then
         nstep = 2
      else if (mod(idx, 2) == 0) then
         nstep = 2**(idx/2 + 1)
      else
         nstep = 3*2**((idx - 1)/2)
      end if
   end function odex_iwork3_nstep

   subroutine ensure_odex_workspace_object(workspace, k_need, n_need)
      type(odex_workspace), intent(inout) :: workspace
      integer, intent(in) :: k_need, n_need
      integer :: k_safe, n_safe

      k_safe = max(1, k_need)
      n_safe = max(1, n_need)
      if (.not. allocated(workspace%tableau) .or. size(workspace%tableau, 1) < k_safe .or. &
          size(workspace%tableau, 2) < k_safe .or. size(workspace%tableau, 3) < n_safe) then
         if (allocated(workspace%tableau)) deallocate(workspace%tableau)
         allocate (workspace%tableau(k_safe, k_safe, n_safe))
      end if
      call ensure_odex_workspace_vector(workspace%yprev, n_safe)
      call ensure_odex_workspace_vector(workspace%ystate, n_safe)
      call ensure_odex_workspace_vector(workspace%ycurr, n_safe)
      call ensure_odex_workspace_vector(workspace%ynext, n_safe)
      call ensure_odex_workspace_vector(workspace%fval, n_safe)
      call ensure_odex_workspace_vector(workspace%fbase, n_safe)
      call ensure_odex_tables(workspace, k_safe)
   end subroutine ensure_odex_workspace_object

   subroutine ensure_odex_workspace_vector(vec, n_need)
      real(dp), allocatable, intent(inout) :: vec(:)
      integer, intent(in) :: n_need

      if (.not. allocated(vec) .or. size(vec) < n_need) then
         if (allocated(vec)) deallocate(vec)
         allocate (vec(n_need))
      end if
   end subroutine ensure_odex_workspace_vector

   subroutine ensure_odex_tables(workspace, k_need)
      type(odex_workspace), intent(inout) :: workspace
      integer, intent(in) :: k_need
      integer :: idx, jdx

      if (workspace%tables_ready .and. workspace%table_k >= k_need) return

      if (allocated(workspace%nsteps)) deallocate(workspace%nsteps)
      if (allocated(workspace%ak)) deallocate(workspace%ak)
      if (allocated(workspace%invexp)) deallocate(workspace%invexp)
      if (allocated(workspace%ratio)) deallocate(workspace%ratio)
      allocate (workspace%nsteps(k_need), workspace%ak(k_need), workspace%invexp(k_need), workspace%ratio(k_need, k_need))

      call build_nsteps(k_need, workspace%nsteps)
      do idx = 1, k_need
         workspace%ak(idx) = calculate_ak(idx)
         workspace%invexp(idx) = 1.0_dp/(2.0_dp*real(idx, dp) - 1.0_dp)
      end do
      do idx = 1, k_need
         do jdx = 1, k_need
            workspace%ratio(idx, jdx) = (real(workspace%nsteps(idx), dp)/real(workspace%nsteps(jdx), dp))**2 - 1.0_dp
         end do
      end do
      workspace%table_k = k_need
      workspace%tables_ready = .true.
   end subroutine ensure_odex_tables

   subroutine odex_result_reset(result_state)
      type(odex_result), intent(out) :: result_state

      result_state%status = odex_status_unknown
      result_state%failure_reason = odex_reason_none
      result_state%accepted_steps = 0
      result_state%rejected_steps = 0
      result_state%stability_rejects = 0
      result_state%final_order = 0
      result_state%final_step_size = 0.0_dp
      result_state%t_remaining = 0.0_dp
      result_state%endpoint_available = .false.
   end subroutine odex_result_reset

   subroutine odex_result_mark_success(result_state, status_code, accepted_steps, final_order, final_step_size)
      type(odex_result), intent(inout) :: result_state
      integer, intent(in) :: status_code, accepted_steps, final_order
      real(dp), intent(in) :: final_step_size

      result_state%status = status_code
      result_state%failure_reason = odex_reason_none
      result_state%accepted_steps = accepted_steps
      result_state%rejected_steps = 0
      result_state%stability_rejects = 0
      result_state%final_order = final_order
      result_state%final_step_size = final_step_size
      result_state%t_remaining = 0.0_dp
      result_state%endpoint_available = .true.
   end subroutine odex_result_mark_success

   subroutine odex_result_mark_failure(result_state, reason_code, accepted_steps, rejected_steps, &
                                       final_order, final_step_size, t_remaining)
      type(odex_result), intent(inout) :: result_state
      integer, intent(in) :: reason_code, accepted_steps, rejected_steps, final_order
      real(dp), intent(in) :: final_step_size, t_remaining

      result_state%status = odex_status_from_failure_reason(reason_code)
      result_state%failure_reason = reason_code
      result_state%accepted_steps = accepted_steps
      result_state%rejected_steps = rejected_steps
      result_state%stability_rejects = 0
      result_state%final_order = final_order
      result_state%final_step_size = final_step_size
      result_state%t_remaining = t_remaining
      result_state%endpoint_available = .false.
   end subroutine odex_result_mark_failure

   pure integer function odex_status_from_failure_reason(reason_code) result(status_code)
      integer, intent(in) :: reason_code

      select case (reason_code)
      case (odex_reason_max_steps)
         status_code = odex_status_failure_max_steps
      case (odex_reason_invalid)
         status_code = odex_status_failure_invalid
      case (odex_reason_h_min)
         status_code = odex_status_failure_h_min
      case default
         status_code = odex_status_unknown
      end select
   end function odex_status_from_failure_reason

   pure integer function odex_result_to_intode_status(result_state) result(status_code)
      type(odex_result), intent(in) :: result_state

      if (odex_status_is_mechanism_status(result_state%status)) then
         status_code = result_state%status
      else
         status_code = odex_status_unknown
      end if
   end function odex_result_to_intode_status

   pure logical function odex_status_is_failure(status_code) result(is_failure)
      integer, intent(in) :: status_code

      select case (status_code)
      case (odex_status_failure_max_steps, odex_status_failure_invalid, odex_status_failure_h_min)
         is_failure = .true.
      case default
         is_failure = .false.
      end select
   end function odex_status_is_failure

   pure logical function odex_status_is_mechanism_status(status_code) result(is_mechanism)
      integer, intent(in) :: status_code

      select case (status_code)
      case (odex_status_unknown, odex_status_success, odex_status_success_zero_time, &
            odex_status_failure_max_steps, odex_status_failure_invalid, odex_status_failure_h_min)
         is_mechanism = .true.
      case default
         is_mechanism = .false.
      end select
   end function odex_status_is_mechanism_status

   subroutine odex_normalize_options(options)
      type(odex_options), intent(inout) :: options

      options%abs_tol = max(options%abs_tol, 0.0_dp)
      options%rel_tol = max(options%rel_tol, 0.0_dp)
      options%k_min = max(odex_k_min, options%k_min)
      options%k_max = max(options%k_min, options%k_max)
      options%max_steps = max(0, options%max_steps)
      options%h_min_c_fp = max(options%h_min_c_fp, 0.0_dp)
      options%h_min_c_tol = max(options%h_min_c_tol, 0.0_dp)
      options%h_min_c_span = max(options%h_min_c_span, 0.0_dp)
      options%initial_step_fraction = max(options%initial_step_fraction, epsilon(1.0_dp))
      options%stability_growth_limit = max(options%stability_growth_limit, 1.0_dp)
   end subroutine odex_normalize_options

   logical function odex_stability_reject(values, prev_norm, dt, opts) result(reject)
      real(dp), intent(in) :: values(:), prev_norm, dt
      type(odex_options), intent(in) :: opts
      real(dp) :: curr_norm, base_norm

      reject = .false.
      if (opts%stability_control /= odex_stability_control_conservative) return
      if (vector_has_invalid(values)) then
         reject = .true.
         return
      end if

      curr_norm = vector_rms(values)
      base_norm = max(prev_norm, tiny(1.0_dp))
      if (abs(dt)*curr_norm > 1.0_dp .and. curr_norm > opts%stability_growth_limit*base_norm) reject = .true.
   end function odex_stability_reject

   real(dp) function vector_rms(values) result(norm)
      real(dp), intent(in) :: values(:)

      if (size(values) <= 0) then
         norm = 0.0_dp
      else
         norm = sqrt(sum(values*values)/real(size(values), dp))
      end if
   end function vector_rms

   logical function vector_has_invalid(values) result(has_invalid)
      real(dp), intent(in) :: values(:)
      integer :: idx

      has_invalid = .false.
      do idx = 1, size(values)
         if (.not. ieee_is_finite(values(idx))) then
            has_invalid = .true.
            return
         end if
      end do
   end function vector_has_invalid

end module odex_backend

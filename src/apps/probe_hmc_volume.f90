program probe_hmc_volume_app
   use utils, only: dp
   use param_mod, only: read_parameters, config
   use solve_flow, only: flow, clear_intode_runtime_trace, set_intode_rattle_trace, set_intode_strict_mode
   use hmc_integrator_core, only: rattle_step_core
   use hmc_kernels, only: decompose2
   use hmc_state_buffers, only: rattle_step_workspace_t, release_rattle_step_workspace
   use hmc_reversibility_checks, only: state_has_progress
   use hmc_constraints, only: reset_constraint_newton_warm_start
   use constraint_solver_stats_mod, only: get_constraint_solver_stats, get_constraint_solver_post_refine_stats, &
                                          get_constraint_solver_reverse_gate_stats, &
                                          constraint_reverse_gate_path_count, constraint_reverse_gate_path_total
   use, intrinsic :: iso_fortran_env, only: int64
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   implicit none

   type :: solver_snapshot_t
      integer(int64) :: newton_count = 0_int64
      integer(int64) :: quasi_count = 0_int64
      integer(int64) :: failed_count = 0_int64
      integer(int64) :: post_refine_attempt_count = 0_int64
      integer(int64) :: post_refine_skip_count = 0_int64
      integer(int64) :: post_refine_success_count = 0_int64
      integer(int64) :: post_refine_fail_count = 0_int64
      integer(int64) :: rg_candidate_total = 0_int64
      integer(int64) :: rg_pass_total = 0_int64
      integer(int64) :: rg_reject_total = 0_int64
   end type solver_snapshot_t

   type :: map_result_t
      logical :: ok = .false.
      logical :: flow_error = .false.
      logical :: used_quasi = .false.
      real(dp) :: q_out = 0.0_dp
      real(dp) :: c_out = 0.0_dp
      real(dp) :: jac_in_abs = 0.0_dp
      real(dp) :: jac_out_abs = 0.0_dp
      integer(int64) :: rg_candidate_delta = 0_int64
      integer(int64) :: rg_pass_delta = 0_int64
      integer(int64) :: rg_reject_delta = 0_int64
      integer(int64) :: newton_delta = 0_int64
      integer(int64) :: quasi_delta = 0_int64
      integer(int64) :: failed_delta = 0_int64
      integer(int64) :: post_refine_attempt_delta = 0_int64
      integer(int64) :: post_refine_skip_delta = 0_int64
      integer(int64) :: post_refine_success_delta = 0_int64
      integer(int64) :: post_refine_fail_delta = 0_int64
   end type map_result_t

   character(len=512) :: out_csv, detail_csv
   integer :: unit_out, unit_detail, ios
   integer :: sample_limit, candidate_limit
   integer :: attempt, kept_count
   real(dp) :: fd_eps, flow_time, q_span, c_span
   real(dp) :: q0, c0
   type(map_result_t) :: base, q_plus, q_minus, c_plus, c_minus
   logical :: fd_ok, branch_stable, strong_branch_stable, require_quasi_stable
   real(dp) :: dq_dq, dq_dc, dc_dq, dc_dc
   real(dp) :: raw_det, raw_logabsdet, metric_logvol
   logical :: detail_enabled, detail_all

   call read_parameters()
   call set_intode_strict_mode(.true.)
   call load_options(out_csv, detail_csv, sample_limit, candidate_limit, fd_eps, flow_time, q_span, c_span, &
                     require_quasi_stable, detail_all)

   if (config%state%x_size /= 2) then
      write (*, '(A,I0)') "[ERROR] probe_hmc_volume currently expects x_size=2, got ", config%state%x_size
      error stop 1
   end if

   open (newunit=unit_out, file=trim(out_csv), status='replace', action='write', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "[ERROR] Cannot open volume CSV:", trim(out_csv)
      error stop 1
   end if

   write (unit_out, '(A)') &
      "case_idx,attempt,q0,c0,base_ok,fd_ok,branch_stable,strong_branch_stable,base_used_quasi,"// &
      "raw_det,raw_logabsdet,metric_logvol,jac_in_abs,jac_out_abs,q_out,c_out,"// &
      "rg_candidate_delta,rg_pass_delta,rg_reject_delta,"// &
      "newton_delta,quasi_delta,failed_delta,"// &
      "post_refine_attempt_delta,post_refine_skip_delta,post_refine_success_delta,post_refine_fail_delta"

   detail_enabled = len_trim(detail_csv) > 0
   unit_detail = -1
   if (detail_enabled) then
      open (newunit=unit_detail, file=trim(detail_csv), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Cannot open detail CSV:", trim(detail_csv)
         error stop 1
      end if
      write (unit_detail, '(A)') &
         "case_idx,attempt,point_label,q_in,c_in,ok,used_quasi,same_as_base,"// &
         "raw_det,metric_logvol,"// &
         "newton_delta,quasi_delta,failed_delta,"// &
         "post_refine_attempt_delta,post_refine_skip_delta,post_refine_success_delta,post_refine_fail_delta,"// &
         "rg_candidate_delta,rg_pass_delta,rg_reject_delta,q_out,c_out,jac_out_abs"
   end if

   kept_count = 0
   do attempt = 1, candidate_limit
      call candidate_point(attempt, q_span, c_span, q0, c0)
      call evaluate_map(q0, c0, flow_time, base)
      if (.not. base%ok) cycle

      call evaluate_map(q0 + fd_eps, c0, flow_time, q_plus)
      call evaluate_map(q0 - fd_eps, c0, flow_time, q_minus)
      call evaluate_map(q0, c0 + fd_eps, flow_time, c_plus)
      call evaluate_map(q0, c0 - fd_eps, flow_time, c_minus)

      fd_ok = q_plus%ok .and. q_minus%ok .and. c_plus%ok .and. c_minus%ok
      branch_stable = fd_ok .and. &
                      (q_plus%used_quasi .eqv. base%used_quasi) .and. &
                      (q_minus%used_quasi .eqv. base%used_quasi) .and. &
                      (c_plus%used_quasi .eqv. base%used_quasi) .and. &
                      (c_minus%used_quasi .eqv. base%used_quasi)
      strong_branch_stable = fd_ok .and. same_branch_signature(base, q_plus) .and. &
                             same_branch_signature(base, q_minus) .and. &
                             same_branch_signature(base, c_plus) .and. &
                             same_branch_signature(base, c_minus)

      raw_det = 0.0_dp
      raw_logabsdet = huge(1.0_dp)
      metric_logvol = huge(1.0_dp)
      if (fd_ok) then
         dq_dq = (q_plus%q_out - q_minus%q_out)/(2.0_dp*fd_eps)
         dc_dq = (q_plus%c_out - q_minus%c_out)/(2.0_dp*fd_eps)
         dq_dc = (c_plus%q_out - c_minus%q_out)/(2.0_dp*fd_eps)
         dc_dc = (c_plus%c_out - c_minus%c_out)/(2.0_dp*fd_eps)
         raw_det = dq_dq*dc_dc - dq_dc*dc_dq
         if (raw_det /= 0.0_dp .and. base%jac_in_abs > 0.0_dp .and. base%jac_out_abs > 0.0_dp) then
            raw_logabsdet = log(abs(raw_det))
            metric_logvol = raw_logabsdet + 2.0_dp*log(base%jac_out_abs) - 2.0_dp*log(base%jac_in_abs)
         end if
      end if

      if (require_quasi_stable .and. (.not. (base%used_quasi .and. branch_stable))) cycle

      kept_count = kept_count + 1
      write (unit_out, '(I0,",",I0,2(",",ES24.16),5(",",L1),7(",",ES24.16),10(",",I0))') &
         kept_count, attempt, q0, c0, base%ok, fd_ok, branch_stable, strong_branch_stable, base%used_quasi, &
         raw_det, raw_logabsdet, metric_logvol, base%jac_in_abs, base%jac_out_abs, base%q_out, base%c_out, &
         base%rg_candidate_delta, base%rg_pass_delta, base%rg_reject_delta, &
         base%newton_delta, base%quasi_delta, base%failed_delta, &
         base%post_refine_attempt_delta, base%post_refine_skip_delta, &
         base%post_refine_success_delta, base%post_refine_fail_delta

      if (detail_enabled .and. (detail_all .or. (fd_ok .and. base%used_quasi .and. branch_stable .and. &
          (.not. strong_branch_stable)))) then
         call write_detail_row(unit_detail, kept_count, attempt, "base", q0, c0, base, base, &
                               raw_det, metric_logvol)
         call write_detail_row(unit_detail, kept_count, attempt, "q_plus", q0 + fd_eps, c0, base, q_plus, &
                               raw_det, metric_logvol)
         call write_detail_row(unit_detail, kept_count, attempt, "q_minus", q0 - fd_eps, c0, base, q_minus, &
                               raw_det, metric_logvol)
         call write_detail_row(unit_detail, kept_count, attempt, "c_plus", q0, c0 + fd_eps, base, c_plus, &
                               raw_det, metric_logvol)
         call write_detail_row(unit_detail, kept_count, attempt, "c_minus", q0, c0 - fd_eps, base, c_minus, &
                               raw_det, metric_logvol)
      end if

      if (kept_count >= sample_limit) exit
   end do

   close (unit_out)
   if (detail_enabled) close (unit_detail)
   write (*, '(A,I0,A,I0,A,ES12.4,A,L1,A,A)') "[DONE] volume probe kept ", kept_count, " / ", attempt, &
      " candidates at eps=", fd_eps, " require_quasi_stable=", require_quasi_stable, " csv=", trim(out_csv)
contains

   subroutine load_options(out_path, detail_path, n_keep, n_candidates, eps, t_flow, q_lim, c_lim, require_qn_stable, &
                           detail_all_points)
      character(len=*), intent(out) :: out_path, detail_path
      integer, intent(out) :: n_keep, n_candidates
      real(dp), intent(out) :: eps, t_flow, q_lim, c_lim
      logical, intent(out) :: require_qn_stable, detail_all_points

      out_path = "hmc_volume_probe.csv"
      detail_path = ""
      n_keep = 12
      n_candidates = 300
      eps = 1.0e-5_dp
      t_flow = config%integrator%initial_flow_time
      q_lim = 1.5_dp
      c_lim = 1.0_dp
      require_qn_stable = .false.
      detail_all_points = .false.

      call read_env_string("HMC_VOLUME_OUT_CSV", out_path)
      call read_env_string("HMC_VOLUME_DETAIL_CSV", detail_path)
      call read_env_int("HMC_VOLUME_SAMPLE_LIMIT", n_keep)
      call read_env_int("HMC_VOLUME_CANDIDATE_LIMIT", n_candidates)
      call read_env_real("HMC_VOLUME_FD_EPS", eps)
      call read_env_real("HMC_VOLUME_FLOW_TIME", t_flow)
      call read_env_real("HMC_VOLUME_Q_SPAN", q_lim)
      call read_env_real("HMC_VOLUME_C_SPAN", c_lim)
      call read_env_logical("HMC_VOLUME_REQUIRE_QUASI_STABLE", require_qn_stable)
      call read_env_logical("HMC_VOLUME_DETAIL_ALL", detail_all_points)
   end subroutine load_options

   subroutine evaluate_map(q_in, c_in, t_flow, result)
      real(dp), intent(in) :: q_in, c_in, t_flow
      type(map_result_t), intent(out) :: result

      real(dp), allocatable :: x0(:), x1(:), p0(:), p1(:)
      complex(dp), allocatable :: z0(:), z1(:), jac0(:, :), jac1(:, :)
      type(solver_snapshot_t) :: before, after
      logical :: err

      result = map_result_t()
      allocate (x0(2), x1(2), p0(2), p1(2))
      allocate (z0(1), z1(1), jac0(1, 1), jac1(1, 1))

      x0(1) = t_flow
      x0(2) = q_in
      call flow(x0, z0, jac0, err)
      result%flow_error = err
      if (err) then
         if (allocated(x0)) deallocate (x0)
         if (allocated(x1)) deallocate (x1)
         if (allocated(p0)) deallocate (p0)
         if (allocated(p1)) deallocate (p1)
         if (allocated(z0)) deallocate (z0)
         if (allocated(z1)) deallocate (z1)
         if (allocated(jac0)) deallocate (jac0)
         if (allocated(jac1)) deallocate (jac1)
         return
      end if

      result%jac_in_abs = abs(jac0(1, 1))
      p0(1) = real(jac0(1, 1), dp)*c_in
      p0(2) = aimag(jac0(1, 1))*c_in

      call snapshot_solver(before)
      call propagate_with_momentum(x0, z0, jac0, p0, x1, z1, jac1, p1, result%ok)
      call snapshot_solver(after)

      result%rg_candidate_delta = after%rg_candidate_total - before%rg_candidate_total
      result%rg_pass_delta = after%rg_pass_total - before%rg_pass_total
      result%rg_reject_delta = after%rg_reject_total - before%rg_reject_total
      result%newton_delta = after%newton_count - before%newton_count
      result%quasi_delta = after%quasi_count - before%quasi_count
      result%failed_delta = after%failed_count - before%failed_count
      result%post_refine_attempt_delta = after%post_refine_attempt_count - before%post_refine_attempt_count
      result%post_refine_skip_delta = after%post_refine_skip_count - before%post_refine_skip_count
      result%post_refine_success_delta = after%post_refine_success_count - before%post_refine_success_count
      result%post_refine_fail_delta = after%post_refine_fail_count - before%post_refine_fail_count
      result%used_quasi = (after%quasi_count > before%quasi_count)

      if (result%ok) then
         result%q_out = x1(2)
         result%c_out = tangent_coeff(p1, jac1)
         result%jac_out_abs = abs(jac1(1, 1))
      end if

      if (allocated(x0)) deallocate (x0)
      if (allocated(x1)) deallocate (x1)
      if (allocated(p0)) deallocate (p0)
      if (allocated(p1)) deallocate (p1)
      if (allocated(z0)) deallocate (z0)
      if (allocated(z1)) deallocate (z1)
      if (allocated(jac0)) deallocate (jac0)
      if (allocated(jac1)) deallocate (jac1)
   end subroutine evaluate_map

   subroutine propagate_with_momentum(start_x, start_z, start_jac, start_momentum, out_x, out_z, out_jac, out_momentum, ok)
      real(dp), intent(in) :: start_x(:), start_momentum(:)
      complex(dp), intent(in) :: start_z(:), start_jac(:, :)
      real(dp), intent(out) :: out_x(:), out_momentum(:)
      complex(dp), intent(out) :: out_z(:), out_jac(:, :)
      logical, intent(out) :: ok

      integer :: step_idx
      logical :: method_converged, local_error
      real(dp) :: step_size
      real(dp), allocatable :: local_momentum(:), momentumuv(:), momentumu(:), momentumv(:)
      real(dp), allocatable :: prev_x(:)
      complex(dp), allocatable :: prev_z(:), local_jac(:, :)
      type(rattle_step_workspace_t) :: ws

      ok = .false.
      allocate (local_momentum(2), momentumuv(2), momentumu(2), momentumv(2))
      allocate (prev_x(size(start_x)), prev_z(size(start_z)))
      allocate (local_jac(size(start_jac, 1), size(start_jac, 2)))

      out_x = start_x
      out_z = start_z
      out_jac = start_jac
      local_jac = start_jac
      local_momentum = start_momentum

      call clear_intode_runtime_trace()
      call reset_constraint_newton_warm_start()
      do step_idx = 1, config%integrator%integration_steps
         step_size = config%integrator%trajectory_length/real(config%integrator%integration_steps, dp)
         prev_x = out_x
         prev_z = out_z
         call set_intode_rattle_trace(step_idx, 1)
         call rattle_step_core(prev_x, prev_z, step_size, out_x, out_z, local_jac, out_jac, local_momentum, &
                               method_converged, ws)
         if (.not. method_converged) then
            go to 900
         end if
         local_jac = out_jac
      end do

      if (.not. state_has_progress(prev_x, out_x)) then
         go to 900
      end if

      call decompose2(local_momentum, momentumuv, momentumu, momentumv, local_jac, local_error)
      if (local_error) then
         go to 900
      end if

      out_momentum = momentumu
      ok = .true.
900   continue
      call release_rattle_step_workspace(ws)
      if (allocated(local_momentum)) deallocate (local_momentum)
      if (allocated(momentumuv)) deallocate (momentumuv)
      if (allocated(momentumu)) deallocate (momentumu)
      if (allocated(momentumv)) deallocate (momentumv)
      if (allocated(prev_x)) deallocate (prev_x)
      if (allocated(prev_z)) deallocate (prev_z)
      if (allocated(local_jac)) deallocate (local_jac)
      call clear_intode_runtime_trace()
   end subroutine propagate_with_momentum

   real(dp) function tangent_coeff(momentum, jac) result(coeff)
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
   end function tangent_coeff

   logical function same_branch_signature(lhs, rhs) result(same)
      type(map_result_t), intent(in) :: lhs, rhs

      same = lhs%used_quasi .eqv. rhs%used_quasi
      same = same .and. lhs%newton_delta == rhs%newton_delta
      same = same .and. lhs%quasi_delta == rhs%quasi_delta
      same = same .and. lhs%failed_delta == rhs%failed_delta
      same = same .and. lhs%post_refine_attempt_delta == rhs%post_refine_attempt_delta
      same = same .and. lhs%post_refine_skip_delta == rhs%post_refine_skip_delta
      same = same .and. lhs%post_refine_success_delta == rhs%post_refine_success_delta
      same = same .and. lhs%post_refine_fail_delta == rhs%post_refine_fail_delta
      same = same .and. lhs%rg_candidate_delta == rhs%rg_candidate_delta
      same = same .and. lhs%rg_pass_delta == rhs%rg_pass_delta
      same = same .and. lhs%rg_reject_delta == rhs%rg_reject_delta
   end function same_branch_signature

   subroutine write_detail_row(unit_id, case_idx, attempt_idx, point_label, q_in, c_in, base_result, point_result, &
                               raw_det_value, metric_logvol_value)
      integer, intent(in) :: unit_id, case_idx, attempt_idx
      character(len=*), intent(in) :: point_label
      real(dp), intent(in) :: q_in, c_in, raw_det_value, metric_logvol_value
      type(map_result_t), intent(in) :: base_result, point_result

      write (unit_id, &
             '(I0,",",I0,",",A,",",2(ES24.16,","),3(L1,","),2(ES24.16,","),10(I0,","),2(ES24.16,","),ES24.16)') &
         case_idx, attempt_idx, trim(point_label), q_in, c_in, point_result%ok, point_result%used_quasi, &
         same_branch_signature(base_result, point_result), raw_det_value, metric_logvol_value, &
         point_result%newton_delta, point_result%quasi_delta, point_result%failed_delta, &
         point_result%post_refine_attempt_delta, point_result%post_refine_skip_delta, &
         point_result%post_refine_success_delta, point_result%post_refine_fail_delta, &
         point_result%rg_candidate_delta, point_result%rg_pass_delta, point_result%rg_reject_delta, &
         point_result%q_out, point_result%c_out, point_result%jac_out_abs
   end subroutine write_detail_row

   subroutine snapshot_solver(snapshot)
      type(solver_snapshot_t), intent(out) :: snapshot
      integer(int64) :: total_count, failed_count
      integer(int64) :: rg_candidate_counts(constraint_reverse_gate_path_count)
      integer(int64) :: rg_pass_counts(constraint_reverse_gate_path_count)
      integer(int64) :: rg_reject_counts(constraint_reverse_gate_path_count)
      real(dp) :: ratio_newton, ratio_quasi, ratio_fail, post_refine_success_ratio

      call get_constraint_solver_stats(total_count, snapshot%newton_count, snapshot%quasi_count, failed_count, &
                                       ratio_newton, ratio_quasi, ratio_fail)
      snapshot%failed_count = failed_count
      call get_constraint_solver_post_refine_stats(snapshot%post_refine_attempt_count, &
                                                   snapshot%post_refine_skip_count, &
                                                   snapshot%post_refine_success_count, &
                                                   snapshot%post_refine_fail_count, &
                                                   post_refine_success_ratio)
      call get_constraint_solver_reverse_gate_stats(rg_candidate_counts, rg_pass_counts, rg_reject_counts)
      snapshot%rg_candidate_total = rg_candidate_counts(constraint_reverse_gate_path_total)
      snapshot%rg_pass_total = rg_pass_counts(constraint_reverse_gate_path_total)
      snapshot%rg_reject_total = rg_reject_counts(constraint_reverse_gate_path_total)
   end subroutine snapshot_solver

   subroutine candidate_point(idx, q_lim, c_lim, q_val, c_val)
      integer, intent(in) :: idx
      real(dp), intent(in) :: q_lim, c_lim
      real(dp), intent(out) :: q_val, c_val

      q_val = q_lim*sin(0.7548776662466927_dp*real(idx, dp))
      c_val = c_lim*cos(1.3247179572447460_dp*real(idx, dp))
      if (abs(c_val) < 0.05_dp*c_lim) c_val = sign(0.05_dp*c_lim, c_val + 1.0e-12_dp)
   end subroutine candidate_point

   subroutine read_env_string(name, value)
      character(len=*), intent(in) :: name
      character(len=*), intent(inout) :: value
      character(len=512) :: env_value
      integer :: env_len, env_status

      call get_environment_variable(name, env_value, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) value = env_value(1:env_len)
   end subroutine read_env_string

   subroutine read_env_int(name, value)
      character(len=*), intent(in) :: name
      integer, intent(inout) :: value
      character(len=64) :: env_value
      integer :: env_len, env_status, ios, parsed

      call get_environment_variable(name, env_value, length=env_len, status=env_status)
      if (env_status /= 0 .or. env_len <= 0) return
      read (env_value(1:env_len), *, iostat=ios) parsed
      if (ios == 0 .and. parsed > 0) value = parsed
   end subroutine read_env_int

   subroutine read_env_real(name, value)
      character(len=*), intent(in) :: name
      real(dp), intent(inout) :: value
      character(len=64) :: env_value
      integer :: env_len, env_status, ios
      real(dp) :: parsed

      call get_environment_variable(name, env_value, length=env_len, status=env_status)
      if (env_status /= 0 .or. env_len <= 0) return
      read (env_value(1:env_len), *, iostat=ios) parsed
      if (ios == 0 .and. ieee_is_finite(parsed) .and. parsed > 0.0_dp) value = parsed
   end subroutine read_env_real

   subroutine read_env_logical(name, value)
      character(len=*), intent(in) :: name
      logical, intent(inout) :: value
      character(len=64) :: env_value
      integer :: env_len, env_status

      call get_environment_variable(name, env_value, length=env_len, status=env_status)
      if (env_status /= 0 .or. env_len <= 0) return
      select case (trim(adjustl(env_value(1:env_len))))
      case ("0", "false", "FALSE", "False", "off", "OFF", "Off", "no", "NO", "No")
         value = .false.
      case default
         value = .true.
      end select
   end subroutine read_env_logical
end program probe_hmc_volume_app

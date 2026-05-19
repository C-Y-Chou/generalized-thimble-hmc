program replay_flowz_cases
   use utils, only: dp
   use param_mod, only: read_parameters, at, rt
   use solve_flow, only: flowz, flow_workspace_t, intode_diagnostics_context_t, reset_intode_fallback_stats
   implicit none

   character(len=512) :: capture_file, output_csv
   character(len=128) :: capture_label, replay_label
   character(len=131072) :: line
   integer :: argc, in_unit, out_unit, ios, line_no, case_idx, max_cases
   integer :: observed, stage, newton_iter, quasi_iter, role, x_size
   integer :: flow_status
   real(dp) :: abs_tol, rel_tol, t0, t1, runtime_sec, z_abs_sum, z_abs_max
   real(dp), allocatable :: x(:)
   complex(dp), allocatable :: z(:)
   logical :: flow_error
   type(flow_workspace_t) :: workspace
   type(intode_diagnostics_context_t) :: diagnostics

   argc = command_argument_count()
   if (argc < 6 .or. argc > 7) call usage_and_stop()
   call get_command_argument(1, capture_file)
   call get_command_argument(2, output_csv)
   call get_command_argument(3, capture_label)
   call get_command_argument(4, replay_label)
   call read_real_arg(5, abs_tol)
   call read_real_arg(6, rel_tol)
   max_cases = 0
   if (argc >= 7) call read_integer_arg(7, max_cases)

   call read_parameters()
   at = abs_tol
   rt = rel_tol

   open (newunit=in_unit, file=trim(capture_file), status='old', action='read', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "ERROR cannot_open_capture", trim(capture_file)
      stop 2
   end if
   open (newunit=out_unit, file=trim(output_csv), status='replace', action='write', iostat=ios)
   if (ios /= 0) then
      write (*, '(A,1X,A)') "ERROR cannot_open_output", trim(output_csv)
      stop 2
   end if

   call write_header(out_unit)
   line_no = 0
   case_idx = 0
   do
      read (in_unit, '(A)', iostat=ios) line
      if (ios /= 0) exit
      line_no = line_no + 1
      if (len_trim(line) == 0) cycle
      if (line(1:1) == "#") cycle

      read (line, *, iostat=ios) observed, stage, newton_iter, quasi_iter, role, x_size
      if (ios /= 0 .or. x_size < 2) cycle
      if (allocated(x)) deallocate (x)
      if (allocated(z)) deallocate (z)
      allocate (x(x_size), z(x_size - 1))
      read (line, *, iostat=ios) observed, stage, newton_iter, quasi_iter, role, x_size, x
      if (ios /= 0) then
         call read_x_values(in_unit, line_no, x, ios)
         if (ios /= 0) cycle
      end if

      case_idx = case_idx + 1
      z = cmplx(0.0_dp, 0.0_dp, dp)
      flow_status = 0
      call reset_intode_fallback_stats(diagnostics)
      call cpu_time(t0)
      call flowz(x, z, flow_error, flow_status, workspace, diagnostics)
      call cpu_time(t1)
      runtime_sec = max(0.0_dp, t1 - t0)
      z_abs_sum = sum(abs(z))
      z_abs_max = maxval(abs(z))
      call write_case(out_unit, case_idx, observed, stage, newton_iter, quasi_iter, role, x_size, &
                      flow_status, flow_error, runtime_sec, z_abs_sum, z_abs_max, diagnostics)
      if (max_cases > 0 .and. case_idx >= max_cases) exit
   end do

   close (in_unit)
   close (out_unit)
   write (*, '(A,1X,A,1X,A,1X,I0)') "replay_flowz_cases_done", trim(capture_label), trim(replay_label), case_idx

contains

   subroutine usage_and_stop()
      implicit none
      write (*, '(A)') "Usage: replay_flowz_cases CAPTURE_FILE OUTPUT_CSV CAPTURE_LABEL REPLAY_LABEL ABS_TOL REL_TOL [MAX_CASES]"
      stop 2
   end subroutine usage_and_stop

   subroutine read_integer_arg(index, value)
      implicit none
      integer, intent(in) :: index
      integer, intent(out) :: value
      character(len=128) :: text
      integer :: read_status

      call get_command_argument(index, text)
      read (text, *, iostat=read_status) value
      if (read_status /= 0) call usage_and_stop()
   end subroutine read_integer_arg

   subroutine read_real_arg(index, value)
      implicit none
      integer, intent(in) :: index
      real(dp), intent(out) :: value
      character(len=128) :: text
      integer :: read_status

      call get_command_argument(index, text)
      read (text, *, iostat=read_status) value
      if (read_status /= 0) call usage_and_stop()
   end subroutine read_real_arg

   subroutine read_x_values(unit_id, local_line_no, values, read_status)
      implicit none
      integer, intent(in) :: unit_id
      integer, intent(inout) :: local_line_no
      real(dp), intent(out) :: values(:)
      integer, intent(out) :: read_status
      character(len=131072) :: values_line

      do
         read (unit_id, '(A)', iostat=read_status) values_line
         if (read_status /= 0) return
         local_line_no = local_line_no + 1
         if (len_trim(values_line) == 0) cycle
         if (values_line(1:1) == "#") cycle
         read (values_line, *, iostat=read_status) values
         return
      end do
   end subroutine read_x_values

   subroutine write_header(unit_id)
      implicit none
      integer, intent(in) :: unit_id

      write (unit_id, '(A)') "capture_label,replay_label,case_idx,capture_observed,stage,newton_iter,quasi_iter,role,x_size,"// &
         "flow_status,flow_error,runtime_sec,odex_calls,odex_success,odex_failure,odex_accepted_steps,"// &
         "odex_rejected_steps,odex_stability_rejects,odex_rhs_evals,odex_midpoint_rows,odex_kplus1_attempts,"// &
         "odex_large_error_rejects,odex_kplus1_rejects,odex_convergence_rejects,odex_kplus1_hope_rejects,"// &
         "odex_reject_updates,odex_final_order_sum,odex_max_final_order,z_abs_sum,z_abs_max"
   end subroutine write_header

   subroutine write_case(unit_id, local_case_idx, local_observed, local_stage, local_newton_iter, local_quasi_iter, &
                         local_role, local_x_size, local_flow_status, local_flow_error, local_runtime_sec, &
                         local_z_abs_sum, local_z_abs_max, local_diagnostics)
      implicit none
      integer, intent(in) :: unit_id, local_case_idx, local_observed, local_stage, local_newton_iter
      integer, intent(in) :: local_quasi_iter, local_role, local_x_size, local_flow_status
      logical, intent(in) :: local_flow_error
      real(dp), intent(in) :: local_runtime_sec, local_z_abs_sum, local_z_abs_max
      type(intode_diagnostics_context_t), intent(in) :: local_diagnostics

      write (unit_id, '(*(g0,:,","))') trim(capture_label), trim(replay_label), local_case_idx, local_observed, &
         local_stage, local_newton_iter, local_quasi_iter, local_role, local_x_size, local_flow_status, &
         merge(1, 0, local_flow_error), local_runtime_sec, local_diagnostics%odex_calls, &
         local_diagnostics%odex_success, local_diagnostics%odex_failure, local_diagnostics%odex_accepted_steps_sum, &
         local_diagnostics%odex_rejected_steps_sum, local_diagnostics%odex_stability_rejects_sum, &
         local_diagnostics%odex_rhs_evals_sum, local_diagnostics%odex_midpoint_rows_sum, &
         local_diagnostics%odex_kplus1_attempts_sum, local_diagnostics%odex_large_error_rejects_sum, &
         local_diagnostics%odex_kplus1_rejects_sum, local_diagnostics%odex_convergence_rejects_sum, &
         local_diagnostics%odex_kplus1_hope_rejects_sum, local_diagnostics%odex_reject_updates_sum, &
         local_diagnostics%odex_final_order_sum, local_diagnostics%odex_max_final_order, local_z_abs_sum, local_z_abs_max
   end subroutine write_case
end program replay_flowz_cases

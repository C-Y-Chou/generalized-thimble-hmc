program build_flow_bank_dense
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use, intrinsic :: iso_fortran_env, only: int64
   use param_mod, only: config, read_parameters
   use runtime_env_mod, only: parse_logical_env, parse_real_list
   use utils, only: dp, log_determinant
   use model, only: calculate_action
   use odex_backend, only: odex_result
   use solve_flow, only: flow_at, flow_at_dense_targets, flow_workspace_t, intode_status_is_strict_success
   implicit none

   integer, parameter :: flow_bank_magic = 23170524
   integer, parameter :: flow_bank_version = 1

   character(len=512) :: input_x_file, output_dir, target_text
   integer :: argc, record_start, record_count, record_stride, physical_state_size
   real(dp), allocatable :: target_times(:)
   logical :: ok, validate_endpoints

   argc = command_argument_count()
   if (argc < 5 .or. argc > 6) call usage_and_stop()
   call get_command_argument(1, input_x_file)
   call get_command_argument(2, output_dir)
   call get_command_argument(3, target_text)
   call read_integer_arg(4, record_start)
   call read_integer_arg(5, record_count)
   record_stride = 1
   if (argc >= 6) call read_integer_arg(6, record_stride)
   if (record_start < 0 .or. record_count < 1 .or. record_stride < 1) call usage_and_stop()

   call parse_real_list(trim(target_text), target_times, ok)
   if ((.not. ok) .or. size(target_times) < 1) then
      write (*, '(A)') "[ERROR][FLOW-BANK] target times must be a nonempty comma-separated real list."
      stop 2
   end if
   if (.not. target_times_are_valid(target_times)) then
      write (*, '(A)') "[ERROR][FLOW-BANK] target times must be finite, nonnegative, and nondecreasing."
      stop 2
   end if

   validate_endpoints = .false.
   call parse_logical_env("TLTM_FLOW_BANK_VALIDATE_ENDPOINTS", validate_endpoints)

   call read_parameters()
   physical_state_size = config%state%z_size
   if (physical_state_size < 1) then
      write (*, '(A)') "[ERROR][FLOW-BANK] invalid physical state size."
      stop 2
   end if

   call ensure_directory(trim(output_dir), ok)
   if (.not. ok) then
      write (*, '(A,1X,A)') "[ERROR][FLOW-BANK] cannot create output directory:", trim(output_dir)
      stop 2
   end if
   call write_manifest(trim(output_dir), trim(input_x_file), target_times, record_start, record_count, record_stride, &
                       physical_state_size, validate_endpoints)
   call build_bank(trim(input_x_file), trim(output_dir), target_times, record_start, record_count, record_stride, &
                   physical_state_size, validate_endpoints)
contains

   subroutine usage_and_stop()
      write (*, '(A)') "Usage: build_flow_bank_dense INPUT_X_BANK OUTPUT_DIR TARGET_TIMES RECORD_START RECORD_COUNT [RECORD_STRIDE]"
      write (*, '(A)') "Example: TLTM_PARAMETERS_FILE=data/parameters_stephanov_n2_smoke.dat bin/build_flow_bank_dense x.dat cache 0,0.01 0 4"
      stop 2
   end subroutine usage_and_stop

   subroutine read_integer_arg(arg_idx, value)
      integer, intent(in) :: arg_idx
      integer, intent(out) :: value
      character(len=128) :: text
      integer :: ios

      call get_command_argument(arg_idx, text)
      read (text, *, iostat=ios) value
      if (ios /= 0) call usage_and_stop()
   end subroutine read_integer_arg

   pure logical function target_times_are_valid(target_times_local) result(valid)
      real(dp), intent(in) :: target_times_local(:)
      integer :: i

      valid = .true.
      do i = 1, size(target_times_local)
         if ((.not. ieee_is_finite(target_times_local(i))) .or. target_times_local(i) < 0.0_dp) then
            valid = .false.
            return
         end if
         if (i > 1 .and. target_times_local(i) < target_times_local(i - 1)) then
            valid = .false.
            return
         end if
      end do
   end function target_times_are_valid

   subroutine build_bank(input_file, bank_dir, target_times_local, record_start_local, record_count_local, &
                         record_stride_local, state_size, validate_endpoints_local)
      character(len=*), intent(in) :: input_file, bank_dir
      real(dp), intent(in) :: target_times_local(:)
      integer, intent(in) :: record_start_local, record_count_local, record_stride_local, state_size
      logical, intent(in) :: validate_endpoints_local

      character(len=512) :: diagnostics_file, record_dir, slot_file
      integer :: unit_x, unit_diag, ios, rec_idx, source_record, target_idx
      integer(int64) :: pos_bytes, record_bytes
      real(dp), allocatable :: x_state(:)
      complex(dp), allocatable :: z_targets(:, :), jac_targets(:, :, :)
      logical, allocatable :: target_available(:)
      logical :: dense_failed
      integer :: dense_status
      type(odex_result) :: dense_result
      type(flow_workspace_t) :: workspace, validate_workspace

      allocate (x_state(state_size), z_targets(state_size, size(target_times_local)), &
                jac_targets(state_size, state_size, size(target_times_local)), target_available(size(target_times_local)))

      open (newunit=unit_x, file=trim(input_file), status='old', access='stream', form='unformatted', action='read', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][FLOW-BANK] cannot open input x bank:", trim(input_file)
         stop 2
      end if
      diagnostics_file = trim(bank_dir)//"/diagnostics.csv"
      open (newunit=unit_diag, file=trim(diagnostics_file), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][FLOW-BANK] cannot open diagnostics:", trim(diagnostics_file)
         stop 2
      end if
      write (unit_diag, '(A)') "source_record,slot_id,target_flow_time,available,status,failure_reason,accepted_steps,rejected_steps,rhs_evals,phase_re,phase_im,log_abs_jacobian,direct_validate_enabled,direct_status,direct_max_abs_z,direct_max_abs_jac,slot_file"

      record_bytes = int(state_size, int64)*8_int64
      do rec_idx = 0, record_count_local - 1
         source_record = record_start_local + rec_idx*record_stride_local
         pos_bytes = 1_int64 + int(source_record, int64)*record_bytes
         read (unit_x, pos=pos_bytes, iostat=ios) x_state
         if (ios /= 0) then
            write (*, '(A,I0,A,1X,A)') "[ERROR][FLOW-BANK] cannot read source_record=", source_record, " file=", trim(input_file)
            stop 2
         end if
         if (any(.not. ieee_is_finite(x_state))) then
            write (*, '(A,I0)') "[ERROR][FLOW-BANK] nonfinite x source_record=", source_record
            stop 2
         end if

         call flow_at_dense_targets(target_times_local, x_state, z_targets, jac_targets, target_available, &
                                    dense_failed, dense_status, workspace, result_state=dense_result)
         call flow_bank_record_dir(bank_dir, source_record, record_dir)
         call ensure_directory(trim(record_dir), ok)
         if (.not. ok) then
            write (*, '(A,1X,A)') "[ERROR][FLOW-BANK] cannot create record directory:", trim(record_dir)
            stop 2
         end if
         do target_idx = 1, size(target_times_local)
            call flow_bank_slot_file(bank_dir, source_record, target_idx - 1, slot_file)
            call write_flow_bank_slot(slot_file, state_size, target_idx - 1, source_record, dense_status, &
                                      target_available(target_idx), dense_result, target_times_local(target_idx), &
                                      x_state, z_targets(:, target_idx), jac_targets(:, :, target_idx))
            call write_diagnostics_row(unit_diag, source_record, target_idx - 1, target_times_local(target_idx), &
                                       target_available(target_idx), dense_status, dense_result, &
                                       z_targets(:, target_idx), jac_targets(:, :, target_idx), trim(slot_file), &
                                       validate_endpoints_local, x_state, validate_workspace)
         end do
         write (*, '(A,I0,A,I0,A,I0,A,I0)') "[FLOW-BANK] source_record=", source_record, " targets=", &
            count(target_available), "/", size(target_times_local), " status=", dense_status
      end do
      close (unit_diag)
      close (unit_x)
      write (*, '(A,1X,A)') "[DONE][FLOW-BANK] cache written under", trim(bank_dir)
   end subroutine build_bank

   subroutine write_flow_bank_slot(slot_file, state_size, slot_id, source_record, dense_status, available, &
                                   dense_result, target_time, x_state, z_state, jac_state)
      character(len=*), intent(in) :: slot_file
      integer, intent(in) :: state_size, slot_id, source_record, dense_status
      logical, intent(in) :: available
      type(odex_result), intent(in) :: dense_result
      real(dp), intent(in) :: target_time, x_state(:)
      complex(dp), intent(in) :: z_state(:), jac_state(:, :)

      integer :: unit_slot, ios, available_int

      available_int = merge(1, 0, available)
      open (newunit=unit_slot, file=trim(slot_file), status='replace', access='stream', form='unformatted', &
            action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][FLOW-BANK] cannot open slot file:", trim(slot_file)
         stop 2
      end if
      write (unit_slot, iostat=ios) flow_bank_magic, flow_bank_version, state_size, slot_id, source_record, dense_status, &
         available_int, dense_result%accepted_steps, dense_result%rejected_steps, dense_result%odex_rhs_evals, &
         dense_result%failure_reason, target_time
      if (ios == 0) write (unit_slot, iostat=ios) x_state
      if (ios == 0) write (unit_slot, iostat=ios) z_state
      if (ios == 0) write (unit_slot, iostat=ios) jac_state
      close (unit_slot)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][FLOW-BANK] failed writing slot file:", trim(slot_file)
         stop 2
      end if
   end subroutine write_flow_bank_slot

   subroutine write_diagnostics_row(unit_diag, source_record, slot_id, target_time, available, dense_status, dense_result, &
                                    z_state, jac_state, slot_file, validate_endpoints_local, x_state, validate_workspace)
      integer, intent(in) :: unit_diag, source_record, slot_id, dense_status
      real(dp), intent(in) :: target_time
      logical, intent(in) :: available, validate_endpoints_local
      type(odex_result), intent(in) :: dense_result
      complex(dp), intent(in) :: z_state(:), jac_state(:, :)
      character(len=*), intent(in) :: slot_file
      real(dp), intent(in) :: x_state(:)
      type(flow_workspace_t), intent(inout) :: validate_workspace

      complex(dp) :: phase_factor, action_value, log_det_j
      complex(dp), allocatable :: z_direct(:), jac_direct(:, :)
      logical :: det_error, direct_failed
      integer :: available_int, direct_status
      real(dp) :: log_abs_jacobian, direct_max_abs_z, direct_max_abs_jac

      available_int = merge(1, 0, available)
      phase_factor = cmplx(0.0_dp, 0.0_dp, dp)
      log_abs_jacobian = 0.0_dp
      if (available) then
         call log_determinant(jac_state, log_det_j, det_error)
         if (.not. det_error) then
            call calculate_action(z_state, action_value)
            log_abs_jacobian = real(log_det_j, dp)
            phase_factor = exp(cmplx(0.0_dp, -1.0_dp, dp)*aimag(action_value) + &
                               cmplx(0.0_dp, 1.0_dp, dp)*aimag(log_det_j))
         end if
      end if

      direct_status = 0
      direct_max_abs_z = -1.0_dp
      direct_max_abs_jac = -1.0_dp
      if (validate_endpoints_local .and. available) then
         allocate (z_direct(size(z_state)), jac_direct(size(jac_state, 1), size(jac_state, 2)))
         call flow_at(target_time, x_state, z_direct, jac_direct, direct_failed, direct_status, validate_workspace)
         if ((.not. direct_failed) .and. intode_status_is_strict_success(direct_status)) then
            direct_max_abs_z = max_complex_vector_abs_diff(z_state, z_direct)
            direct_max_abs_jac = max_complex_matrix_abs_diff(jac_state, jac_direct)
         end if
         deallocate (z_direct, jac_direct)
      end if

      write (unit_diag, '(I0,A,I0,A,ES24.16E3,A,I0,A,I0,A,I0,A,I0,A,I0,A,I0,A,ES24.16E3,A,ES24.16E3,A,ES24.16E3,A,L1,A,I0,A,ES24.16E3,A,ES24.16E3,A,A)') &
         source_record, ",", slot_id, ",", target_time, ",", available_int, ",", dense_status, ",", &
         dense_result%failure_reason, ",", dense_result%accepted_steps, ",", dense_result%rejected_steps, ",", &
         dense_result%odex_rhs_evals, ",", real(phase_factor, dp), ",", aimag(phase_factor), ",", &
         log_abs_jacobian, ",", validate_endpoints_local, ",", direct_status, ",", direct_max_abs_z, ",", &
         direct_max_abs_jac, ",", trim(slot_file)
   end subroutine write_diagnostics_row

   real(dp) function max_complex_vector_abs_diff(a, b) result(max_diff)
      complex(dp), intent(in) :: a(:), b(:)
      integer :: i

      max_diff = 0.0_dp
      do i = 1, size(a)
         max_diff = max(max_diff, abs(a(i) - b(i)))
      end do
   end function max_complex_vector_abs_diff

   real(dp) function max_complex_matrix_abs_diff(a, b) result(max_diff)
      complex(dp), intent(in) :: a(:, :), b(:, :)
      integer :: i, j

      max_diff = 0.0_dp
      do j = 1, size(a, 2)
         do i = 1, size(a, 1)
            max_diff = max(max_diff, abs(a(i, j) - b(i, j)))
         end do
      end do
   end function max_complex_matrix_abs_diff

   subroutine write_manifest(bank_dir, input_file, target_times_local, record_start_local, record_count_local, &
                             record_stride_local, state_size, validate_endpoints_local)
      character(len=*), intent(in) :: bank_dir, input_file
      real(dp), intent(in) :: target_times_local(:)
      integer, intent(in) :: record_start_local, record_count_local, record_stride_local, state_size
      logical, intent(in) :: validate_endpoints_local

      character(len=512) :: manifest_file
      integer :: unit_manifest, ios, i

      manifest_file = trim(bank_dir)//"/manifest.txt"
      open (newunit=unit_manifest, file=trim(manifest_file), status='replace', action='write', iostat=ios)
      if (ios /= 0) then
         write (*, '(A,1X,A)') "[ERROR][FLOW-BANK] cannot write manifest:", trim(manifest_file)
         stop 2
      end if
      write (unit_manifest, '(A)') "schema=tltm_flow_bank_dense_targets"
      write (unit_manifest, '(A,I0)') "version=", flow_bank_version
      write (unit_manifest, '(A)') "backend=dop853_dense_targets"
      write (unit_manifest, '(A)') "binary_format=fortran_unformatted_stream_local"
      write (unit_manifest, '(A,I0)') "physical_state_size=", state_size
      write (unit_manifest, '(A,I0)') "target_count=", size(target_times_local)
      write (unit_manifest, '(A)', advance='no') "target_times="
      do i = 1, size(target_times_local)
         if (i > 1) write (unit_manifest, '(A)', advance='no') ","
         write (unit_manifest, '(ES24.16E3)', advance='no') target_times_local(i)
      end do
      write (unit_manifest, *)
      write (unit_manifest, '(A,A)') "input_x_file=", trim(input_file)
      write (unit_manifest, '(A,I0)') "record_start=", record_start_local
      write (unit_manifest, '(A,I0)') "record_count=", record_count_local
      write (unit_manifest, '(A,I0)') "record_stride=", record_stride_local
      write (unit_manifest, '(A,L1)') "direct_endpoint_validation=", validate_endpoints_local
      close (unit_manifest)
   end subroutine write_manifest

   subroutine flow_bank_record_dir(bank_dir, source_record, record_dir)
      character(len=*), intent(in) :: bank_dir
      integer, intent(in) :: source_record
      character(len=*), intent(out) :: record_dir
      character(len=64) :: record_name

      write (record_name, '("record_",I6.6)') source_record
      record_dir = trim(bank_dir)//"/records/"//trim(record_name)
   end subroutine flow_bank_record_dir

   subroutine flow_bank_slot_file(bank_dir, source_record, slot_id, slot_file)
      character(len=*), intent(in) :: bank_dir
      integer, intent(in) :: source_record, slot_id
      character(len=*), intent(out) :: slot_file
      character(len=512) :: record_dir
      character(len=64) :: slot_name

      call flow_bank_record_dir(bank_dir, source_record, record_dir)
      write (slot_name, '("slot_",I6.6,".bin")') slot_id
      slot_file = trim(record_dir)//"/"//trim(slot_name)
   end subroutine flow_bank_slot_file

   subroutine ensure_directory(path, ok)
      character(len=*), intent(in) :: path
      logical, intent(out) :: ok
      integer :: cmd_status, exit_status

      call execute_command_line("mkdir -p "//trim(path), exitstat=exit_status, cmdstat=cmd_status)
      ok = (cmd_status == 0 .and. exit_status == 0)
   end subroutine ensure_directory
end program build_flow_bank_dense

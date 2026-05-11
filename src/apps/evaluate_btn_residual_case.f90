program evaluate_btn_residual_case
   use utils, only: dp
   use runtime_env_mod, only: read_string_env
   use param_mod, only: read_parameters
   use solve_flow, only: flow
   use quasi_newton_linear_solver_mod, only: initial_guess_from_jacobian
   use quasi_newton_solver_mod, only: evaluate_constraint_residual
   implicit none

   character(len=32) :: mode
   character(len=512) :: case_dir
   character(len=128) :: capture_prefix
   integer :: argc, sample_idx, n, n2
   logical :: ok
   complex(dp), allocatable :: z0(:), z_flow(:), jac(:, :)
   real(dp), allocatable :: del_z(:), x0(:), xi(:), fq(:), jl(:)
   logical :: flow_error, residual_error
   real(dp) :: z_recompute_inf, seed_norm, residual_norm, flow_im_norm, a_norm, jl_norm

   argc = command_argument_count()
   if (argc < 3) call usage_and_stop()

   call get_command_argument(1, mode)
   call get_command_argument(2, case_dir)
   call read_integer_arg(3, sample_idx)
   capture_prefix = "constraint_solver_fail"
   call read_string_env("BTN_CAPTURE_PREFIX", capture_prefix)

   call read_parameters()
   call read_capture_case(trim(case_dir), sample_idx, z0, del_z, x0, ok)
   if (.not. ok) then
      write (*, '(A,1X,A,1X,I0)') "ERROR", "case_not_found", sample_idx
      stop 2
   end if

   n = size(z0)
   n2 = 2*n
   if (size(del_z) /= n2 .or. size(x0) /= n + 1) then
      write (*, '(A,1X,A,3(1X,I0))') "ERROR", "shape_mismatch", n, size(del_z), size(x0)
      stop 2
   end if

   allocate (z_flow(n), jac(n, n))
   z_flow = cmplx(0.0_dp, 0.0_dp, dp)
   jac = cmplx(0.0_dp, 0.0_dp, dp)
   call flow(x0, z_flow, jac, flow_error)
   z_recompute_inf = max_complex_abs_diff(z0, z_flow)
   if (flow_error) then
      write (*, '(A,1X,A,1X,I0,1X,I0,1X,ES24.16)') "ERROR", "flow_recompute_failed", sample_idx, n, z_recompute_inf
      stop 3
   end if

   select case (trim(mode))
   case ("seed")
      allocate (xi(n2))
      call initial_guess_from_jacobian(jac, del_z, xi)
      seed_norm = norm2(xi)
      call write_seed_result(sample_idx, n, z_recompute_inf, seed_norm, xi)
   case ("residual")
      if (argc /= 3 + n2) then
         write (*, '(A,1X,A,2(1X,I0))') "ERROR", "wrong_xi_arg_count", argc - 3, n2
         stop 2
      end if
      allocate (xi(n2), fq(n2), jl(n2))
      call read_xi_args(4, xi)
      call evaluate_constraint_residual(x0, z0, xi, fq, del_z, residual_error, jl, jac)
      if (residual_error) then
         write (*, '(A,1X,A,1X,I0,1X,I0,1X,ES24.16)') "ERROR", "residual_eval_failed", sample_idx, n, z_recompute_inf
         stop 4
      end if
      residual_norm = norm2(fq)
      flow_im_norm = norm2(fq(1:n))
      a_norm = norm2(xi(n + 1:n2))
      jl_norm = norm2(jl)
      call write_residual_result(sample_idx, n, z_recompute_inf, residual_norm, flow_im_norm, a_norm, jl_norm, fq)
   case default
      call usage_and_stop()
   end select

contains

   subroutine usage_and_stop()
      implicit none
      write (*, '(A)') "Usage:"
      write (*, '(A)') "  evaluate_btn_residual_case seed CASE_DIR SAMPLE_IDX"
      write (*, '(A)') "  evaluate_btn_residual_case residual CASE_DIR SAMPLE_IDX XI_1 ... XI_2N"
      write (*, '(A)') "CASE_DIR must contain ${BTN_CAPTURE_PREFIX}_{z0,delz,x0}.dat; default prefix is constraint_solver_fail."
      stop 2
   end subroutine usage_and_stop

   subroutine read_integer_arg(arg_idx, value)
      implicit none
      integer, intent(in) :: arg_idx
      integer, intent(out) :: value
      character(len=128) :: text
      integer :: ios

      call get_command_argument(arg_idx, text)
      read (text, *, iostat=ios) value
      if (ios /= 0) then
         write (*, '(A,1X,I0)') "ERROR bad_integer_arg", arg_idx
         stop 2
      end if
   end subroutine read_integer_arg

   subroutine read_xi_args(start_idx, xi_out)
      implicit none
      integer, intent(in) :: start_idx
      real(dp), intent(out) :: xi_out(:)
      character(len=128) :: text
      integer :: i, ios

      do i = 1, size(xi_out)
         call get_command_argument(start_idx + i - 1, text)
         read (text, *, iostat=ios) xi_out(i)
         if (ios /= 0) then
            write (*, '(A,1X,I0)') "ERROR bad_xi_arg", i
            stop 2
         end if
      end do
   end subroutine read_xi_args

   subroutine read_capture_case(dir_path, target_sample_idx, z_out, delz_out, x_out, found)
      implicit none
      character(len=*), intent(in) :: dir_path
      integer, intent(in) :: target_sample_idx
      complex(dp), allocatable, intent(out) :: z_out(:)
      real(dp), allocatable, intent(out) :: delz_out(:), x_out(:)
      logical, intent(out) :: found
      logical :: has_z, has_delz, has_x

      call read_complex_record(join_path(dir_path, trim(capture_prefix)//"_z0.dat"), target_sample_idx, z_out, has_z)
      call read_real_record(join_path(dir_path, trim(capture_prefix)//"_delz.dat"), target_sample_idx, delz_out, has_delz)
      call read_real_record(join_path(dir_path, trim(capture_prefix)//"_x0.dat"), target_sample_idx, x_out, has_x)
      found = has_z .and. has_delz .and. has_x
   end subroutine read_capture_case

   subroutine read_complex_record(path, target_sample_idx, values, found)
      implicit none
      character(len=*), intent(in) :: path
      integer, intent(in) :: target_sample_idx
      complex(dp), allocatable, intent(out) :: values(:)
      logical, intent(out) :: found
      integer :: unit_id, ios, record_sample_idx, record_n
      complex(dp), allocatable :: tmp(:)

      found = .false.
      open (newunit=unit_id, file=trim(path), status='old', access='stream', form='unformatted', action='read', iostat=ios)
      if (ios /= 0) return
      do
         read (unit_id, iostat=ios) record_sample_idx, record_n
         if (ios /= 0) exit
         if (record_n < 0) exit
         allocate (tmp(record_n))
         read (unit_id, iostat=ios) tmp
         if (ios /= 0) then
            deallocate (tmp)
            exit
         end if
         if (record_sample_idx == target_sample_idx) then
            allocate (values(record_n))
            values = tmp
            found = .true.
            deallocate (tmp)
            exit
         end if
         deallocate (tmp)
      end do
      close (unit_id)
   end subroutine read_complex_record

   subroutine read_real_record(path, target_sample_idx, values, found)
      implicit none
      character(len=*), intent(in) :: path
      integer, intent(in) :: target_sample_idx
      real(dp), allocatable, intent(out) :: values(:)
      logical, intent(out) :: found
      integer :: unit_id, ios, record_sample_idx, record_n
      real(dp), allocatable :: tmp(:)

      found = .false.
      open (newunit=unit_id, file=trim(path), status='old', access='stream', form='unformatted', action='read', iostat=ios)
      if (ios /= 0) return
      do
         read (unit_id, iostat=ios) record_sample_idx, record_n
         if (ios /= 0) exit
         if (record_n < 0) exit
         allocate (tmp(record_n))
         read (unit_id, iostat=ios) tmp
         if (ios /= 0) then
            deallocate (tmp)
            exit
         end if
         if (record_sample_idx == target_sample_idx) then
            allocate (values(record_n))
            values = tmp
            found = .true.
            deallocate (tmp)
            exit
         end if
         deallocate (tmp)
      end do
      close (unit_id)
   end subroutine read_real_record

   function join_path(dir_path, file_name) result(path)
      implicit none
      character(len=*), intent(in) :: dir_path, file_name
      character(len=1024) :: path
      integer :: n_dir

      n_dir = len_trim(dir_path)
      if (n_dir <= 0) then
         path = trim(file_name)
      else if (dir_path(n_dir:n_dir) == "/") then
         path = trim(dir_path)//trim(file_name)
      else
         path = trim(dir_path)//"/"//trim(file_name)
      end if
   end function join_path

   real(dp) function max_complex_abs_diff(lhs, rhs) result(max_diff)
      implicit none
      complex(dp), intent(in) :: lhs(:), rhs(:)
      integer :: i, n_local

      max_diff = 0.0_dp
      n_local = min(size(lhs), size(rhs))
      do i = 1, n_local
         max_diff = max(max_diff, abs(lhs(i) - rhs(i)))
      end do
      if (size(lhs) /= size(rhs)) max_diff = huge(1.0_dp)
   end function max_complex_abs_diff

   subroutine write_seed_result(sample_idx_local, n_local, z_diff, x_norm, xi_local)
      implicit none
      integer, intent(in) :: sample_idx_local, n_local
      real(dp), intent(in) :: z_diff, x_norm
      real(dp), intent(in) :: xi_local(:)
      integer :: i

      write (*, '(A,1X,A,1X,I0,1X,I0,1X,ES24.16,1X,ES24.16)', advance='no') &
         "OK", "seed", sample_idx_local, n_local, z_diff, x_norm
      do i = 1, size(xi_local)
         write (*, '(1X,ES24.16)', advance='no') xi_local(i)
      end do
      write (*, *)
   end subroutine write_seed_result

   subroutine write_residual_result(sample_idx_local, n_local, z_diff, r_norm, im_norm, lambda_norm, jl_norm_local, fq_local)
      implicit none
      integer, intent(in) :: sample_idx_local, n_local
      real(dp), intent(in) :: z_diff, r_norm, im_norm, lambda_norm, jl_norm_local
      real(dp), intent(in) :: fq_local(:)
      integer :: i

      write (*, '(A,1X,A,1X,I0,1X,I0,5(1X,ES24.16))', advance='no') &
         "OK", "residual", sample_idx_local, n_local, z_diff, r_norm, im_norm, lambda_norm, jl_norm_local
      do i = 1, size(fq_local)
         write (*, '(1X,ES24.16)', advance='no') fq_local(i)
      end do
      write (*, *)
   end subroutine write_residual_result
end program evaluate_btn_residual_case

module param_mod
   use utils   ! Ensure utils module is properly implemented for any auxiliary functions
   implicit none

   type :: runtime_flags_t
      logical :: istest = .false.
      logical :: tra2 = .false.
      logical :: eo = .false.
      logical :: wv = .false.
      logical :: ckrv = .false.
   end type runtime_flags_t

   type :: chain_control_t
      integer :: length = 0
      integer :: warmup = 0
      integer :: hmc_repeat = 0
   end type chain_control_t

   type :: integrator_control_t
      real(dp) :: trajectory_length = 0.0_dp
      integer :: integration_steps = 0
      real(dp) :: initial_flow_time = 0.0_dp
      character(len=32) :: method = "rattle"
   end type integrator_control_t

   type :: state_layout_t
      ! x_size must be explicitly provided in parameters.dat.
      integer :: x_size = 0
      integer :: z_size = 0
   end type state_layout_t

   type :: solver_control_t
      real(dp) :: abs_tol = 0.0_dp
      real(dp) :: rel_tol = 0.0_dp
      real(dp) :: constraint_tol = 0.0_dp
      logical :: enable_quasi_fallback = .true.
   end type solver_control_t

   type :: analysis_control_t
      integer :: bootstrap_samples = 0
   end type analysis_control_t

   type :: model_control_t
      complex(dp) :: alpha = cmplx(0.0_dp, 0.0_dp, dp)
      complex(dp) :: beta = cmplx(0.0_dp, 0.0_dp, dp)
      character(len=32) :: derivative_mode = "generated"
   end type model_control_t

   type :: io_paths_t
      character(len=256) :: x_history_file = ""
      character(len=256) :: z_history_file = ""
      character(len=256) :: phi_history_file = ""
   end type io_paths_t

   type :: simulation_config_t
      type(runtime_flags_t) :: flags
      type(chain_control_t) :: chain
      type(integrator_control_t) :: integrator
      type(state_layout_t) :: state
      type(solver_control_t) :: solver
      type(analysis_control_t) :: analysis
      type(model_control_t) :: model
      type(io_paths_t) :: io
      real(dp) :: delta = 0.0_dp
   end type simulation_config_t

   type(simulation_config_t), save :: config

   ! Legacy globals kept for compatibility with existing modules
   real(dp) :: T0
   logical  :: istest, wv, ckrv, tra2, eo             ! Test mode flag
   real(dp), allocatable :: testmom(:)

   ! Markov Chain Parameters
   integer  :: chain_length
   integer  :: hmc_step
   real(dp) :: total_step_size
   integer  :: num_steps
   real(dp) :: cttol
   real(dp) :: at, rt
   logical :: quasi_fallback_enabled
   integer  :: expect_bootstrap_samples

   ! Update parameters
   integer  :: n_size, n_warm
   real(dp) :: delta

   complex(dp) :: alpha, beta
   character(len=32) :: derivative_mode = "generated"
   character(len=32) :: integrator_method = "rattle"

   ! File names
   character(len=256) :: x_history_file
   character(len=256) :: z_history_file
   character(len=256) :: phi_history_file

contains

   subroutine validate_config()
      implicit none
      character(len=32) :: mode

      if (config%state%x_size < 2) then
         write (*, *) "Invalid config: state size must be >= 2."
         error stop 1
      end if
      if (config%integrator%integration_steps < 1) then
         write (*, *) "Invalid config: integration_steps must be >= 1."
         error stop 1
      end if
      if (config%chain%length < 1) then
         write (*, *) "Invalid config: chain length must be >= 1."
         error stop 1
      end if
      if (config%chain%hmc_repeat < 1) then
         write (*, *) "Invalid config: hmc_repeat must be >= 1."
         error stop 1
      end if
      if (config%chain%warmup < 0) then
         write (*, *) "Invalid config: warmup must be >= 0."
         error stop 1
      end if
      if (config%analysis%bootstrap_samples < 0) then
         write (*, *) "Invalid config: bootstrap_samples must be >= 0 (0 means auto)."
         error stop 1
      end if
      mode = trim(to_lower_ascii(config%model%derivative_mode))
      if (mode /= "generated") then
         write (*, '(A,A,A)') "Invalid config: derivative_mode must be generated. Got '", &
            trim(config%model%derivative_mode), "'."
         error stop 1
      end if
      call set_integrator_method(config%integrator%method)
   end subroutine validate_config

   subroutine sync_legacy_from_config()
      implicit none
      integer :: z_sz

      istest = config%flags%istest
      tra2 = config%flags%tra2
      eo = config%flags%eo
      wv = config%flags%wv
      ckrv = config%flags%ckrv

      chain_length = config%chain%length
      hmc_step = config%chain%hmc_repeat
      n_warm = config%chain%warmup

      total_step_size = config%integrator%trajectory_length
      num_steps = config%integrator%integration_steps
      T0 = config%integrator%initial_flow_time
      call set_integrator_method(config%integrator%method)

      n_size = config%state%x_size

      alpha = config%model%alpha
      beta = config%model%beta
      call set_derivative_mode(config%model%derivative_mode)

      at = config%solver%abs_tol
      rt = config%solver%rel_tol
      cttol = config%solver%constraint_tol
      quasi_fallback_enabled = config%solver%enable_quasi_fallback
      expect_bootstrap_samples = config%analysis%bootstrap_samples

      x_history_file = config%io%x_history_file
      z_history_file = config%io%z_history_file
      phi_history_file = config%io%phi_history_file
      delta = config%delta

      z_sz = max(1, n_size - 1)
      if (allocated(testmom)) then
         if (size(testmom) /= 2*z_sz) deallocate (testmom)
      end if
      if (.not. allocated(testmom)) allocate (testmom(2*z_sz))
   end subroutine sync_legacy_from_config

   subroutine set_initial_flow_time(flow_time)
      implicit none
      real(dp), intent(in) :: flow_time

      config%integrator%initial_flow_time = flow_time
      T0 = flow_time
   end subroutine set_initial_flow_time

   subroutine set_derivative_mode(mode_in)
      implicit none
      character(len=*), intent(in) :: mode_in
      character(len=32) :: mode_norm

      mode_norm = trim(to_lower_ascii(mode_in))
      select case (mode_norm)
      case ("generated")
         mode_norm = "generated"
      case default
         write (*, '(A,A,A)') "Invalid derivative mode: only 'generated' is supported; got '", trim(mode_in), "'."
         error stop 1
      end select

      config%model%derivative_mode = mode_norm
      derivative_mode = mode_norm
   end subroutine set_derivative_mode

   subroutine set_integrator_method(method_in)
      implicit none
      character(len=*), intent(in) :: method_in
      character(len=32) :: method_norm

      method_norm = trim(to_lower_ascii(unquote(method_in)))
      select case (method_norm)
      case ("rattle")
         method_norm = "rattle"
      case default
         write (*, '(A,A,A)') "Invalid integrator method: supported value is 'rattle'; got '", &
            trim(method_in), "'."
         error stop 1
      end select

      config%integrator%method = method_norm
      integrator_method = method_norm
   end subroutine set_integrator_method

   function state_total_size() result(n_total)
      implicit none
      integer :: n_total
      n_total = config%state%x_size
   end function state_total_size

   function state_seed_size_cfg() result(n_seed)
      implicit none
      integer :: n_seed
      n_seed = config%state%z_size
   end function state_seed_size_cfg

   subroutine read_parameters_key_value(unit_id)
      implicit none
      integer, intent(in) :: unit_id

      character(len=1024) :: raw_line, line, key, value
      integer :: ios, eq_pos, line_no

      line_no = 0
      do
         read (unit_id, '(A)', iostat=ios) raw_line
         if (ios /= 0) exit
         line_no = line_no + 1

         line = strip_comment(raw_line)
         if (len_trim(line) == 0) cycle

         eq_pos = index(line, '=')
         if (eq_pos <= 1) then
            write (*, '(A,I0,A)') "Error(parameters.dat): malformed key=value at line ", line_no, "."
            write (*, '(A)') "Error(parameters.dat): legacy positional parameters.dat is no longer supported."
            error stop 1
         end if

         key = to_lower_ascii(trim(adjustl(line(:eq_pos - 1))))
         value = trim(adjustl(line(eq_pos + 1:)))
         call apply_kv_parameter(key, value, line_no)
      end do
   end subroutine read_parameters_key_value

   subroutine apply_kv_parameter(key, value, line_no)
      implicit none
      character(len=*), intent(in) :: key, value
      integer, intent(in) :: line_no

      integer :: ios
      logical :: ltmp, ok
      character(len=256) :: text

      select case (trim(key))
      case ("istest")
         call parse_logical_value(value, ltmp, ok)
         if (.not. ok) call kv_parse_error(line_no, key, value)
         config%flags%istest = ltmp
      case ("tra2")
         call parse_logical_value(value, ltmp, ok)
         if (.not. ok) call kv_parse_error(line_no, key, value)
         config%flags%tra2 = ltmp
      case ("eo")
         call parse_logical_value(value, ltmp, ok)
         if (.not. ok) call kv_parse_error(line_no, key, value)
         config%flags%eo = ltmp
      case ("wv")
         call parse_logical_value(value, ltmp, ok)
         if (.not. ok) call kv_parse_error(line_no, key, value)
         config%flags%wv = ltmp
      case ("ckrv")
         call parse_logical_value(value, ltmp, ok)
         if (.not. ok) call kv_parse_error(line_no, key, value)
         config%flags%ckrv = ltmp
      case ("chain_length")
         read (value, *, iostat=ios) config%chain%length
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("hmc_repeat", "hmc_step")
         read (value, *, iostat=ios) config%chain%hmc_repeat
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("warmup", "n_warm")
         read (value, *, iostat=ios) config%chain%warmup
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("trajectory_length", "total_step_size")
         read (value, *, iostat=ios) config%integrator%trajectory_length
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("integration_steps", "num_steps")
         read (value, *, iostat=ios) config%integrator%integration_steps
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("initial_flow_time", "flow_time", "t0")
         read (value, *, iostat=ios) config%integrator%initial_flow_time
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("integrator_method", "integrator", "hmc_integrator")
         text = to_lower_ascii(trim(unquote(value)))
         config%integrator%method = trim(text)
      case ("x_size", "n_size")
         read (value, *, iostat=ios) config%state%x_size
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("alpha")
         read (value, *, iostat=ios) config%model%alpha
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("beta")
         read (value, *, iostat=ios) config%model%beta
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("derivative_mode", "model_derivative_mode")
         text = to_lower_ascii(trim(unquote(value)))
         config%model%derivative_mode = trim(text)
      case ("abs_tol", "at")
         read (value, *, iostat=ios) config%solver%abs_tol
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("rel_tol", "rt")
         read (value, *, iostat=ios) config%solver%rel_tol
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("constraint_tol", "cttol")
         read (value, *, iostat=ios) config%solver%constraint_tol
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("enable_quasi_fallback", "quasi_fallback", "use_quasi_fallback")
         call parse_logical_value(value, ltmp, ok)
         if (.not. ok) call kv_parse_error(line_no, key, value)
         config%solver%enable_quasi_fallback = ltmp
      case ("expect_bootstrap_samples", "bootstrap_samples")
         read (value, *, iostat=ios) config%analysis%bootstrap_samples
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("delta")
         read (value, *, iostat=ios) config%delta
         if (ios /= 0) call kv_parse_error(line_no, key, value)
      case ("x_history_file")
         text = unquote(value)
         config%io%x_history_file = trim(text)
      case ("z_history_file")
         text = unquote(value)
         config%io%z_history_file = trim(text)
      case ("phi_history_file")
         text = unquote(value)
         config%io%phi_history_file = trim(text)
      case default
         write (*, '(A,A,A,I0,A)') "[WARN] Unknown parameter key '", trim(key), "' at line ", line_no, ". Ignored."
      end select
   end subroutine apply_kv_parameter

   subroutine kv_parse_error(line_no, key, value)
      implicit none
      integer, intent(in) :: line_no
      character(len=*), intent(in) :: key, value

      write (*, '(A,I0,A,A,A,A)') "Error(parameters.dat): cannot parse line ", line_no, &
         " for key '", trim(key), "' with value '", trim(value), "'."
      error stop 1
   end subroutine kv_parse_error

   subroutine parse_logical_value(text, value, ok)
      implicit none
      character(len=*), intent(in) :: text
      logical, intent(out) :: value, ok

      character(len=1024) :: lower
      integer :: ios

      lower = to_lower_ascii(trim(adjustl(text)))
      select case (trim(lower))
      case (".true.", "true", "t", "yes", "y", "on", "1")
         value = .true.
         ok = .true.
      case (".false.", "false", "f", "no", "n", "off", "0")
         value = .false.
         ok = .true.
      case default
         read (text, *, iostat=ios) value
         ok = (ios == 0)
      end select
   end subroutine parse_logical_value

   function strip_comment(raw_line) result(line)
      implicit none
      character(len=*), intent(in) :: raw_line
      character(len=len(raw_line)) :: line
      integer :: hash_pos, bang_pos, cut_pos

      hash_pos = index(raw_line, '#')
      bang_pos = index(raw_line, '!')

      if (hash_pos > 0 .and. bang_pos > 0) then
         cut_pos = min(hash_pos, bang_pos)
      else if (hash_pos > 0) then
         cut_pos = hash_pos
      else if (bang_pos > 0) then
         cut_pos = bang_pos
      else
         cut_pos = 0
      end if

      if (cut_pos > 0) then
         if (cut_pos > 1) then
            line = adjustl(raw_line(:cut_pos - 1))
         else
            line = ""
         end if
      else
         line = adjustl(raw_line)
      end if
   end function strip_comment

   function to_lower_ascii(text) result(lower)
      implicit none
      character(len=*), intent(in) :: text
      character(len=len(text)) :: lower
      integer :: i, code

      lower = text
      do i = 1, len(text)
         code = iachar(lower(i:i))
         if (code >= iachar('A') .and. code <= iachar('Z')) then
            lower(i:i) = achar(code + 32)
         end if
      end do
   end function to_lower_ascii

   function unquote(text) result(stripped)
      implicit none
      character(len=*), intent(in) :: text
      character(len=len(text)) :: stripped
      integer :: n

      stripped = trim(adjustl(text))
      n = len_trim(stripped)
      if (n >= 2) then
         if ((stripped(1:1) == '"' .and. stripped(n:n) == '"') .or. &
             (stripped(1:1) == "'" .and. stripped(n:n) == "'")) then
            stripped = stripped(2:n - 1)
         end if
      end if
   end function unquote

   subroutine read_parameters()
      implicit none
      integer :: ios
      integer :: candidate_idx
      character(len=256) :: filename
      logical :: opened
      character(len=256), parameter :: candidates(2) = [character(len=256) :: "../data/parameters.dat", "data/parameters.dat"]

      opened = .false.
      do candidate_idx = 1, size(candidates)
         filename = candidates(candidate_idx)
         open (unit=10, file=trim(filename), status='old', action='read', iostat=ios)
         if (ios == 0) then
            opened = .true.
            exit
         end if
      end do
      if (.not. opened) then
         write (*, '(A)') "Error: Unable to open parameters.dat (tried ../data/parameters.dat and data/parameters.dat)."
         error stop 1
      end if

      config%integrator%initial_flow_time = 0.0_dp
      config%solver%enable_quasi_fallback = .true.
      call read_parameters_key_value(10)

      close (10)

      if (config%state%x_size <= 0) then
         write (*, '(A)') "Error(parameters.dat): x_size must be set to a positive value (>=2)."
         error stop 1
      end if

      config%state%z_size = max(1, config%state%x_size - 1)

      call validate_config()
      call sync_legacy_from_config()
   end subroutine read_parameters
end module param_mod

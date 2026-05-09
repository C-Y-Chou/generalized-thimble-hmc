module runtime_env_mod
   use utils, only: dp
   implicit none
   private

   public :: parse_int_env
   public :: parse_real_env
   public :: parse_logical_env
   public :: parse_real_list
   public :: to_lower_ascii

contains

   ! Keep defaults in the caller; parsers only overwrite on valid env input.
   subroutine parse_int_env(name, value)
      character(len=*), intent(in) :: name
      integer, intent(inout) :: value
      character(len=128) :: env_text
      integer :: env_len, env_status, ios, parsed_value

      env_text = ""
      call get_environment_variable(name, env_text, length=env_len, status=env_status)
      if (env_status /= 0 .or. env_len <= 0) return

      read (env_text(1:env_len), *, iostat=ios) parsed_value
      if (ios == 0) value = parsed_value
   end subroutine parse_int_env

   subroutine parse_real_env(name, value)
      character(len=*), intent(in) :: name
      real(dp), intent(inout) :: value
      character(len=128) :: env_text
      integer :: env_len, env_status, ios
      real(dp) :: parsed_value

      env_text = ""
      call get_environment_variable(name, env_text, length=env_len, status=env_status)
      if (env_status /= 0 .or. env_len <= 0) return

      read (env_text(1:env_len), *, iostat=ios) parsed_value
      if (ios == 0) value = parsed_value
   end subroutine parse_real_env

   subroutine parse_logical_env(name, value)
      character(len=*), intent(in) :: name
      logical, intent(inout) :: value
      character(len=128) :: env_text
      character(len=128) :: token
      integer :: env_len, env_status

      env_text = ""
      call get_environment_variable(name, env_text, length=env_len, status=env_status)
      if (env_status /= 0 .or. env_len <= 0) return

      token = to_lower_ascii(adjustl(env_text(1:env_len)))
      select case (trim(token))
      case ("1", "true", "t", "yes", "y", "on")
         value = .true.
      case ("0", "false", "f", "no", "n", "off")
         value = .false.
      end select
   end subroutine parse_logical_env

   subroutine parse_real_list(text, values, ok)
      character(len=*), intent(in) :: text
      real(dp), allocatable, intent(out) :: values(:)
      logical, intent(out) :: ok

      character(len=1024) :: cleaned
      character(len=128) :: token
      integer :: i, n, pos, count, ios
      logical :: has_token

      ok = .false.
      if (allocated(values)) deallocate (values)

      cleaned = adjustl(trim(text))
      n = len_trim(cleaned)
      if (n <= 0) return

      do i = 1, n
         if (cleaned(i:i) == ',' .or. cleaned(i:i) == ';') cleaned(i:i) = ' '
      end do

      count = 0
      pos = 1
      do
         call next_token(cleaned, pos, token, has_token)
         if (.not. has_token) exit
         count = count + 1
      end do
      if (count <= 0) return

      allocate (values(count))
      pos = 1
      i = 0
      do
         call next_token(cleaned, pos, token, has_token)
         if (.not. has_token) exit
         i = i + 1
         read (token, *, iostat=ios) values(i)
         if (ios /= 0) then
            deallocate (values)
            return
         end if
      end do

      ok = .true.
   end subroutine parse_real_list

   subroutine next_token(line, pos, token, found)
      character(len=*), intent(in) :: line
      integer, intent(inout) :: pos
      character(len=*), intent(out) :: token
      logical, intent(out) :: found
      integer :: n, start

      token = ""
      found = .false.
      n = len_trim(line)
      if (pos < 1) pos = 1

      do while (pos <= n .and. line(pos:pos) == ' ')
         pos = pos + 1
      end do
      if (pos > n) return

      start = pos
      do while (pos <= n .and. line(pos:pos) /= ' ')
         pos = pos + 1
      end do
      token = adjustl(line(start:pos - 1))
      found = .true.
   end subroutine next_token

   pure function to_lower_ascii(text) result(lower)
      character(len=*), intent(in) :: text
      character(len=len(text)) :: lower
      integer :: i, code

      lower = text
      do i = 1, len(text)
         code = iachar(text(i:i))
         if (code >= iachar('A') .and. code <= iachar('Z')) then
            lower(i:i) = achar(code + iachar('a') - iachar('A'))
         end if
      end do
   end function to_lower_ascii

end module runtime_env_mod

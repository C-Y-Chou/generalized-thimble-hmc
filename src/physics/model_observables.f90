module model_observables
   use param_mod, only: alpha, beta
   use utils, only: dp
   implicit none

   integer, parameter, public :: model_observable_name_len = 64

   include "model_observable_registry.inc"

   public :: model_observable_count, get_model_observable_name, find_model_observable
   public :: evaluate_model_observables, evaluate_model_observable_by_index

contains

   integer function model_observable_count() result(count)
      count = model_observable_count_value
   end function model_observable_count

   subroutine get_model_observable_name(index, name)
      integer, intent(in) :: index
      character(len=*), intent(out) :: name

      if (index < 1 .or. index > model_observable_count_value) then
         name = ""
      else
         name = trim(model_observable_names(index))
      end if
   end subroutine get_model_observable_name

   integer function find_model_observable(name) result(index)
      character(len=*), intent(in) :: name
      character(len=model_observable_name_len) :: requested, candidate
      integer :: i

      requested = lower_ascii(trim(name))
      if (trim(requested) == "tra2" .or. trim(requested) == "z") requested = "z_sum"

      index = 0
      do i = 1, model_observable_count_value
         candidate = lower_ascii(trim(model_observable_names(i)))
         if (trim(candidate) == trim(requested)) then
            index = i
            return
         end if
      end do
   end function find_model_observable

   subroutine evaluate_model_observables(z, observables)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(out) :: observables(:)
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp) :: z_val
      integer :: i

      if (size(observables) /= model_observable_count_value) then
         write (*, '(A,I0,A,I0,A)') "[ERROR] evaluate_model_observables: expected ", &
            model_observable_count_value, " values, got ", size(observables), "."
         error stop 1
      end if

      include "model_observable_body.inc"
   end subroutine evaluate_model_observables

   subroutine evaluate_model_observable_by_index(z, index, observable)
      complex(dp), intent(in) :: z(:)
      integer, intent(in) :: index
      complex(dp), intent(out) :: observable
      complex(dp) :: values(model_observable_count_value)

      if (index < 1 .or. index > model_observable_count_value) then
         write (*, '(A,I0)') "[ERROR] evaluate_model_observable_by_index: invalid observable index=", index
         error stop 1
      end if

      call evaluate_model_observables(z, values)
      observable = values(index)
   end subroutine evaluate_model_observable_by_index

   pure function lower_ascii(text) result(lowered)
      character(len=*), intent(in) :: text
      character(len=len(text)) :: lowered
      integer :: i, code

      lowered = text
      do i = 1, len(text)
         code = iachar(text(i:i))
         if (code >= iachar("A") .and. code <= iachar("Z")) lowered(i:i) = achar(code + 32)
      end do
   end function lower_ascii

end module model_observables

module model_observables
   use utils, only: dp
   use model_stephanov, only: get_stephanov_observable_name, stephanov_evaluate_observables, &
                              stephanov_observable_count
   implicit none

   integer, parameter, public :: model_observable_name_len = 64

   public :: model_observable_count, get_model_observable_name, find_model_observable
   public :: evaluate_model_observables, evaluate_model_observable_by_index

contains

   integer function model_observable_count() result(count)
      count = stephanov_observable_count()
   end function model_observable_count

   subroutine get_model_observable_name(index, name)
      integer, intent(in) :: index
      character(len=*), intent(out) :: name

      call get_stephanov_observable_name(index, name)
   end subroutine get_model_observable_name

   integer function find_model_observable(name) result(index)
      character(len=*), intent(in) :: name
      character(len=model_observable_name_len) :: requested, candidate
      integer :: i

      requested = lower_ascii(trim(name))
      if (trim(requested) == "chiral" .or. trim(requested) == "chiral_cond") requested = "chiral_condensate"
      if (trim(requested) == "density" .or. trim(requested) == "number") requested = "number_density"

      index = 0
      do i = 1, model_observable_count()
         call get_model_observable_name(i, candidate)
         candidate = lower_ascii(trim(candidate))
         if (trim(candidate) == trim(requested)) then
            index = i
            return
         end if
      end do
   end function find_model_observable

   subroutine evaluate_model_observables(z, observables)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(out) :: observables(:)
      integer :: expected_count

      expected_count = model_observable_count()
      if (size(observables) /= expected_count) then
         write (*, '(A,I0,A,I0,A)') "[ERROR] evaluate_model_observables: expected ", &
            expected_count, " values, got ", size(observables), "."
         error stop 1
      end if

      call stephanov_evaluate_observables(z, observables)
   end subroutine evaluate_model_observables

   subroutine evaluate_model_observable_by_index(z, index, observable)
      complex(dp), intent(in) :: z(:)
      integer, intent(in) :: index
      complex(dp), intent(out) :: observable
      complex(dp), allocatable :: values(:)
      integer :: count

      count = model_observable_count()
      if (index < 1 .or. index > count) then
         write (*, '(A,I0)') "[ERROR] evaluate_model_observable_by_index: invalid observable index=", index
         error stop 1
      end if

      allocate (values(count))
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

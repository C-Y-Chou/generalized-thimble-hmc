module markovchain_io
   use utils
   implicit none

contains

   subroutine write_chain_snapshot(unit_x, unit_z, unit_phi, x, z, phi, flush_io)
      implicit none

      integer, intent(in) :: unit_x, unit_z, unit_phi
      real(dp), intent(in) :: x
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: phi
      logical, intent(in) :: flush_io

      write (unit_x) x
      write (unit_z) z
      write (unit_phi) phi

      if (flush_io) then
         flush (unit_x)
         flush (unit_z)
         flush (unit_phi)
      end if
   end subroutine write_chain_snapshot

   subroutine save_initial_state_from_x(filename, x, x_seed)
      implicit none
      character(len=*), intent(in) :: filename
      real(dp), intent(in) :: x(:)
      real(dp), intent(inout) :: x_seed(:)

      if (size(x_seed) /= size(x) - 1) then
         write (*, *) "Error(save_initial_state_from_x): x_seed size mismatch."
         error stop 1
      end if

      call x_get_seed_real(x, x_seed)
      call save_initial_state(filename, x_get_flow_time(x), x_seed)
   end subroutine save_initial_state_from_x

end module markovchain_io

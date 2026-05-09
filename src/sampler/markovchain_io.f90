module markovchain_io
   use utils, only: dp
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

end module markovchain_io

module hmc_state_buffers
   use utils, only: dp
   implicit none

   type :: rattle_step_workspace_t
      real(dp), allocatable :: dV(:), del_z(:), E0_real(:), E0_perp(:), temp_x(:), Jl(:)
      complex(dp), allocatable :: ds_val(:), E0(:), temp_z(:), temp_jac(:, :)
   end type rattle_step_workspace_t

contains

   subroutine ensure_rattle_step_workspace(ws, n_x, n_z, n_jr, n_jc)
      type(rattle_step_workspace_t), intent(inout) :: ws
      integer, intent(in) :: n_x, n_z, n_jr, n_jc

      call ensure_real_1d(ws%dV, 2*n_z)
      call ensure_real_1d(ws%del_z, 2*n_z)
      call ensure_real_1d(ws%E0_real, 2*n_z)
      call ensure_real_1d(ws%E0_perp, 2*n_z)
      call ensure_real_1d(ws%temp_x, n_x)
      call ensure_real_1d(ws%Jl, 2*n_z)

      call ensure_complex_1d(ws%ds_val, n_z)
      call ensure_complex_1d(ws%E0, n_z)
      call ensure_complex_1d(ws%temp_z, n_z)
      call ensure_complex_2d(ws%temp_jac, n_jr, n_jc)
   end subroutine ensure_rattle_step_workspace

   subroutine release_rattle_step_workspace(ws)
      type(rattle_step_workspace_t), intent(inout) :: ws

      if (allocated(ws%dV)) deallocate (ws%dV)
      if (allocated(ws%del_z)) deallocate (ws%del_z)
      if (allocated(ws%E0_real)) deallocate (ws%E0_real)
      if (allocated(ws%E0_perp)) deallocate (ws%E0_perp)
      if (allocated(ws%temp_x)) deallocate (ws%temp_x)
      if (allocated(ws%Jl)) deallocate (ws%Jl)

      if (allocated(ws%ds_val)) deallocate (ws%ds_val)
      if (allocated(ws%E0)) deallocate (ws%E0)
      if (allocated(ws%temp_z)) deallocate (ws%temp_z)
      if (allocated(ws%temp_jac)) deallocate (ws%temp_jac)
   end subroutine release_rattle_step_workspace

   subroutine ensure_real_1d(vec, n)
      real(dp), allocatable, intent(inout) :: vec(:)
      integer, intent(in) :: n

      if (allocated(vec)) then
         if (size(vec) /= n) deallocate (vec)
      end if
      if (.not. allocated(vec)) allocate (vec(n))
   end subroutine ensure_real_1d

   subroutine ensure_complex_1d(vec, n)
      complex(dp), allocatable, intent(inout) :: vec(:)
      integer, intent(in) :: n

      if (allocated(vec)) then
         if (size(vec) /= n) deallocate (vec)
      end if
      if (.not. allocated(vec)) allocate (vec(n))
   end subroutine ensure_complex_1d

   subroutine ensure_complex_2d(mat, nr, nc)
      complex(dp), allocatable, intent(inout) :: mat(:, :)
      integer, intent(in) :: nr, nc

      if (allocated(mat)) then
         if (size(mat, 1) /= nr .or. size(mat, 2) /= nc) deallocate (mat)
      end if
      if (.not. allocated(mat)) allocate (mat(nr, nc))
   end subroutine ensure_complex_2d

end module hmc_state_buffers

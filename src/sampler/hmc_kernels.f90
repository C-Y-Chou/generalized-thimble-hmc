module hmc_kernels
   use utils, only: dp, map_to_real_mat, real_vec
   use model, only: calculate_action
   use perf_profile, only: perf_tic, perf_toc, PERF_DECOMPOSE2
   implicit none

   type :: decompose2_workspace_t
      real(dp), allocatable :: jacr(:, :), jacr_lu(:, :)
      integer, allocatable :: ipiv(:)
   end type decompose2_workspace_t

contains

   subroutine calculate_dV(n_seed, E0_real, E0_perp, dV, error)
      implicit none

      integer, intent(in) :: n_seed
      real(dp), intent(in) :: E0_real(:), E0_perp(:)
      real(dp), intent(out) :: dV(:)
      logical, intent(out) :: error
      integer :: n2

      n2 = 2*n_seed
      error = .false.
      if (size(E0_real) /= n2 .or. size(E0_perp) /= n2 .or. size(dV) /= n2) then
         write (*, *) "Error(calculate_dV): E0_real, E0_perp, dV must all have length 2*n_seed."
         error = .true.
         return
      end if

      dV = E0_real/2.0_dp
   end subroutine calculate_dV

   subroutine decompose2(b, x, au, av, jac, ierr, workspace)
      implicit none
      real(dp), intent(in)    :: b(:)
      real(dp), intent(inout) :: x(:)
      real(dp), intent(out)   :: au(:), av(:)
      complex(dp), intent(in) :: jac(:, :)
      logical, intent(out)    :: ierr
      type(decompose2_workspace_t), intent(inout), optional :: workspace

      type(decompose2_workspace_t) :: local_workspace

      if (present(workspace)) then
         call decompose2_with_workspace(b, x, au, av, jac, ierr, workspace)
      else
         call decompose2_with_workspace(b, x, au, av, jac, ierr, local_workspace)
      end if
   end subroutine decompose2

   subroutine decompose2_with_workspace(b, x, au, av, jac, ierr, workspace)
      implicit none
      real(dp), intent(in)    :: b(:)
      real(dp), intent(inout) :: x(:)
      real(dp), intent(out)   :: au(:), av(:)
      complex(dp), intent(in) :: jac(:, :)
      logical, intent(out)    :: ierr
      type(decompose2_workspace_t), intent(inout) :: workspace

      integer :: n, info
      real(dp) :: t_prof
      external :: dgetrf, dgetrs, dgemv

      call perf_tic(t_prof)
      call ensure_real_mat(workspace%jacr, 2*size(jac, 1), 2*size(jac, 2))
      call ensure_real_mat(workspace%jacr_lu, 2*size(jac, 1), 2*size(jac, 2))
      call map_to_real_mat(jac, workspace%jacr)
      ierr = .false.

      n = size(b)
      call ensure_int_vec(workspace%ipiv, n)
      workspace%jacr_lu = workspace%jacr
      x = b
      call dgetrf(n, n, workspace%jacr_lu, n, workspace%ipiv, info)
      if (info /= 0) then
         ierr = .true.
         call perf_toc(PERF_DECOMPOSE2, t_prof)
         return
      end if

      call dgetrs('N', n, 1, workspace%jacr_lu, n, workspace%ipiv, x, n, info)
      if (info /= 0) then
         ierr = .true.
         call perf_toc(PERF_DECOMPOSE2, t_prof)
         return
      end if

      au = x
      call real_vec(au)
      call dgemv('N', n, n, 1.0_dp, workspace%jacr, n, au, 1, 0.0_dp, av, 1)
      au = av
      av = b - au
      call perf_toc(PERF_DECOMPOSE2, t_prof)
   end subroutine decompose2_with_workspace

   subroutine calculate_hamiltonian(z, p, h)
      implicit none

      complex(dp), intent(in) :: z(:)
      real(dp), intent(in) :: p(:)
      real(dp), intent(out) :: h
      complex(dp)  :: s

      if (2*size(z) /= size(p)) then
         write (*, *) "Warning: z and p differ in length in calculate_hamiltonian."
      end if

      call calculate_action(z, s)
      h = 0.5_dp*norm2(p)**2 + real(s, dp)
   end subroutine calculate_hamiltonian

   subroutine ensure_real_mat(buf, nr, nc)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:, :)
      integer, intent(in) :: nr, nc

      if (.not. allocated(buf)) then
         allocate (buf(nr, nc))
      elseif (size(buf, 1) /= nr .or. size(buf, 2) /= nc) then
         deallocate (buf)
         allocate (buf(nr, nc))
      end if
   end subroutine ensure_real_mat

   subroutine ensure_int_vec(buf, n_need)
      implicit none
      integer, allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) /= n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_int_vec

   subroutine release_decompose2_workspace(workspace)
      implicit none
      type(decompose2_workspace_t), intent(inout) :: workspace

      if (allocated(workspace%jacr)) deallocate (workspace%jacr)
      if (allocated(workspace%jacr_lu)) deallocate (workspace%jacr_lu)
      if (allocated(workspace%ipiv)) deallocate (workspace%ipiv)
   end subroutine release_decompose2_workspace

end module hmc_kernels

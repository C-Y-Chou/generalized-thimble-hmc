module hmc_kernels
   use, intrinsic :: iso_fortran_env, only: int64
   use utils, only: dp, map_to_real_mat, real_vec
   use model, only: calculate_action
   use perf_profile, only: perf_tic, perf_toc, PERF_DECOMPOSE2
   implicit none

   type :: real_jacobian_cache_t
      logical :: valid = .false.
      complex(dp), allocatable :: jac(:, :)
      real(dp), allocatable :: jacr(:, :), jacr_lu(:, :)
      integer, allocatable :: ipiv(:)
      integer(int64) :: hits = 0_int64
      integer(int64) :: misses = 0_int64
      integer(int64) :: factor_failures = 0_int64
   end type real_jacobian_cache_t

   type :: decompose2_workspace_t
      type(real_jacobian_cache_t) :: jac_cache
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

   subroutine decompose_tangent_projection(b, x, tangent, normal, jac, ierr, workspace, jac_cache)
      implicit none
      real(dp), intent(in)    :: b(:)
      real(dp), intent(inout) :: x(:)
      real(dp), intent(out)   :: tangent(:), normal(:)
      complex(dp), intent(in) :: jac(:, :)
      logical, intent(out)    :: ierr
      type(decompose2_workspace_t), intent(inout), optional :: workspace
      type(real_jacobian_cache_t), intent(inout), optional, target :: jac_cache

      type(decompose2_workspace_t) :: local_workspace

      if (present(workspace)) then
         call decompose_tangent_projection_with_workspace(b, x, tangent, normal, jac, ierr, workspace, jac_cache)
      else
         call decompose_tangent_projection_with_workspace(b, x, tangent, normal, jac, ierr, local_workspace, jac_cache)
      end if
   end subroutine decompose_tangent_projection

   subroutine decompose2(b, x, au, av, jac, ierr, workspace, jac_cache)
      implicit none
      real(dp), intent(in)    :: b(:)
      real(dp), intent(inout) :: x(:)
      real(dp), intent(out)   :: au(:), av(:)
      complex(dp), intent(in) :: jac(:, :)
      logical, intent(out)    :: ierr
      type(decompose2_workspace_t), intent(inout), optional :: workspace
      type(real_jacobian_cache_t), intent(inout), optional, target :: jac_cache

      call decompose_tangent_projection(b, x, au, av, jac, ierr, workspace, jac_cache)
   end subroutine decompose2

   subroutine decompose_tangent_projection_with_workspace(b, x, tangent, normal, jac, ierr, workspace, jac_cache)
      implicit none
      real(dp), intent(in)    :: b(:)
      real(dp), intent(inout) :: x(:)
      real(dp), intent(out)   :: tangent(:), normal(:)
      complex(dp), intent(in) :: jac(:, :)
      logical, intent(out)    :: ierr
      type(decompose2_workspace_t), intent(inout), target :: workspace
      type(real_jacobian_cache_t), intent(inout), optional, target :: jac_cache

      integer :: n, info
      real(dp) :: t_prof
      type(real_jacobian_cache_t), pointer :: active_cache
      external :: dgetrs, dgemv

      call perf_tic(t_prof)
      n = size(b)
      ierr = .true.
      x = 0.0_dp
      tangent = 0.0_dp
      normal = 0.0_dp
      if (size(x) /= n .or. size(tangent) /= n .or. size(normal) /= n) then
         write (*, *) "Error(decompose_tangent_projection): b, x, tangent, normal must have the same length."
         call perf_toc(PERF_DECOMPOSE2, t_prof)
         return
      end if
      if (size(jac, 1) /= size(jac, 2) .or. n /= 2*size(jac, 1)) then
         write (*, *) "Error(decompose_tangent_projection): jac must be square and match the 2n real momentum dimension."
         call perf_toc(PERF_DECOMPOSE2, t_prof)
         return
      end if

      if (present(jac_cache)) then
         active_cache => jac_cache
      else
         active_cache => workspace%jac_cache
      end if
      call prepare_real_jacobian_cache(jac, active_cache, ierr)
      if (ierr) then
         call perf_toc(PERF_DECOMPOSE2, t_prof)
         return
      end if

      x = b
      call dgetrs('N', n, 1, active_cache%jacr_lu, n, active_cache%ipiv, x, n, info)
      if (info /= 0) then
         ierr = .true.
         call perf_toc(PERF_DECOMPOSE2, t_prof)
         return
      end if

      tangent = x
      call real_vec(tangent)
      call dgemv('N', n, n, 1.0_dp, active_cache%jacr, n, tangent, 1, 0.0_dp, normal, 1)
      tangent = normal
      normal = b - tangent
      call perf_toc(PERF_DECOMPOSE2, t_prof)
   end subroutine decompose_tangent_projection_with_workspace

   subroutine calculate_hamiltonian(z, p, h)
      implicit none

      complex(dp), intent(in) :: z(:)
      real(dp), intent(in) :: p(:)
      real(dp), intent(out) :: h
      complex(dp)  :: s

      if (2*size(z) /= size(p)) then
         write (*, *) "Warning: z and p differ in length in calculate_hamiltonian."
         h = huge(1.0_dp)
         return
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

   subroutine ensure_complex_mat(buf, nr, nc)
      implicit none
      complex(dp), allocatable, intent(inout) :: buf(:, :)
      integer, intent(in) :: nr, nc

      if (.not. allocated(buf)) then
         allocate (buf(nr, nc))
      elseif (size(buf, 1) /= nr .or. size(buf, 2) /= nc) then
         deallocate (buf)
         allocate (buf(nr, nc))
      end if
   end subroutine ensure_complex_mat

   subroutine prepare_real_jacobian_cache(jac, cache, ierr)
      implicit none
      complex(dp), intent(in) :: jac(:, :)
      type(real_jacobian_cache_t), intent(inout) :: cache
      logical, intent(out) :: ierr

      integer :: n_complex, n_real, info
      external :: dgetrf

      ierr = .true.
      n_complex = size(jac, 1)
      if (size(jac, 2) /= n_complex) return
      n_real = 2*n_complex
      if (.not. allocated(cache%jac)) then
         cache%valid = .false.
      elseif (size(cache%jac, 1) /= n_complex .or. size(cache%jac, 2) /= n_complex) then
         cache%valid = .false.
      end if
      call ensure_complex_mat(cache%jac, n_complex, n_complex)
      call ensure_real_mat(cache%jacr, n_real, n_real)
      call ensure_real_mat(cache%jacr_lu, n_real, n_real)
      call ensure_int_vec(cache%ipiv, n_real)

      if (cache%valid .and. all(cache%jac == jac)) then
         cache%hits = cache%hits + 1_int64
         ierr = .false.
         return
      end if

      cache%misses = cache%misses + 1_int64
      cache%valid = .false.
      call map_to_real_mat(jac, cache%jacr)
      cache%jacr_lu = cache%jacr
      call dgetrf(n_real, n_real, cache%jacr_lu, n_real, cache%ipiv, info)
      if (info /= 0) then
         cache%factor_failures = cache%factor_failures + 1_int64
         return
      end if

      cache%jac = jac
      cache%valid = .true.
      ierr = .false.
   end subroutine prepare_real_jacobian_cache

   subroutine invalidate_real_jacobian_cache(cache)
      implicit none
      type(real_jacobian_cache_t), intent(inout) :: cache

      cache%valid = .false.
   end subroutine invalidate_real_jacobian_cache

   subroutine reset_real_jacobian_cache_stats(cache)
      implicit none
      type(real_jacobian_cache_t), intent(inout) :: cache

      cache%hits = 0_int64
      cache%misses = 0_int64
      cache%factor_failures = 0_int64
   end subroutine reset_real_jacobian_cache_stats

   subroutine get_real_jacobian_cache_stats(cache, hits, misses, factor_failures)
      implicit none
      type(real_jacobian_cache_t), intent(in) :: cache
      integer(int64), intent(out) :: hits, misses, factor_failures

      hits = cache%hits
      misses = cache%misses
      factor_failures = cache%factor_failures
   end subroutine get_real_jacobian_cache_stats

   subroutine release_real_jacobian_cache(cache)
      implicit none
      type(real_jacobian_cache_t), intent(inout) :: cache

      if (allocated(cache%jac)) deallocate (cache%jac)
      if (allocated(cache%jacr)) deallocate (cache%jacr)
      if (allocated(cache%jacr_lu)) deallocate (cache%jacr_lu)
      if (allocated(cache%ipiv)) deallocate (cache%ipiv)
      cache%valid = .false.
      call reset_real_jacobian_cache_stats(cache)
   end subroutine release_real_jacobian_cache

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

      call release_real_jacobian_cache(workspace%jac_cache)
   end subroutine release_decompose2_workspace

end module hmc_kernels

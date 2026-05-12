module quasi_newton_linear_solver_mod
   use utils, only: dp, complex_to_real, map_to_real_mat, real_to_complex, real_vec
   implicit none
   external :: dgesv, zgesv, dgemv

   type :: qn_linear_workspace_t
      integer, allocatable :: linear_ipiv(:), guess_ipiv(:)
      real(dp), allocatable :: linear_jac_fact(:, :)
      real(dp), allocatable :: guess_jacr(:, :), guess_rhs_r(:), guess_sol_r(:), guess_proj_r(:)
      complex(dp), allocatable :: guess_jac_fact(:, :), guess_z(:), guess_rhs_c(:)
   end type qn_linear_workspace_t

contains

   subroutine solve_linear_direction(f_val, jac_approx, direction, ierr, workspace)
      implicit none
      real(dp), intent(in) :: f_val(:)
      real(dp), intent(in) :: jac_approx(:, :)
      real(dp), intent(out) :: direction(:)
      logical, intent(out) :: ierr
      type(qn_linear_workspace_t), intent(inout), optional :: workspace

      type(qn_linear_workspace_t) :: local_workspace

      if (present(workspace)) then
         call solve_linear_direction_with_workspace(f_val, jac_approx, direction, ierr, workspace)
      else
         call solve_linear_direction_with_workspace(f_val, jac_approx, direction, ierr, local_workspace)
      end if
   end subroutine solve_linear_direction

   subroutine solve_linear_direction_with_workspace(f_val, jac_approx, direction, ierr, workspace)
      implicit none
      real(dp), intent(in) :: f_val(:)
      real(dp), intent(in) :: jac_approx(:, :)
      real(dp), intent(out) :: direction(:)
      logical, intent(out) :: ierr
      type(qn_linear_workspace_t), intent(inout) :: workspace

      integer :: n, info, ridge_idx, row_idx
      real(dp) :: base_shift, ridge

      n = size(f_val)
      ierr = .false.

      if (size(direction) /= n .or. size(jac_approx, 1) /= n .or. size(jac_approx, 2) /= n) then
         ierr = .true.
         return
      end if

      call ensure_real_mat_workspace(workspace%linear_jac_fact, n, n)
      call ensure_int_workspace(workspace%linear_ipiv, n)

      workspace%linear_jac_fact = jac_approx
      direction = -f_val
      call dgesv(n, 1, workspace%linear_jac_fact, n, workspace%linear_ipiv, direction, n, info)
      if (info == 0) return

      base_shift = max(1.0e-12_dp, sqrt(epsilon(1.0_dp))*maxval(abs(jac_approx)))
      do ridge_idx = 1, 3
         ridge = base_shift*10.0_dp**real(ridge_idx - 1, dp)
         workspace%linear_jac_fact = jac_approx
         do row_idx = 1, n
            workspace%linear_jac_fact(row_idx, row_idx) = workspace%linear_jac_fact(row_idx, row_idx) + ridge
         end do
         direction = -f_val
         call dgesv(n, 1, workspace%linear_jac_fact, n, workspace%linear_ipiv, direction, n, info)
         if (info == 0) return
      end do

      ierr = .true.
   end subroutine solve_linear_direction_with_workspace

   subroutine initial_guess_from_jacobian(jac, del_z, x, workspace)
      implicit none
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(in) :: del_z(:)
      real(dp), intent(out) :: x(:)
      type(qn_linear_workspace_t), intent(inout), optional :: workspace

      type(qn_linear_workspace_t) :: local_workspace

      if (present(workspace)) then
         call initial_guess_from_jacobian_with_workspace(jac, del_z, x, workspace)
      else
         call initial_guess_from_jacobian_with_workspace(jac, del_z, x, local_workspace)
      end if
   end subroutine initial_guess_from_jacobian

   subroutine initial_guess_from_jacobian_with_workspace(jac, del_z, x, workspace)
      implicit none
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(in) :: del_z(:)
      real(dp), intent(out) :: x(:)
      type(qn_linear_workspace_t), intent(inout) :: workspace

      integer :: n, info, i, ridge_idx
      real(dp) :: base_shift, ridge, max_abs_jac

      n = size(jac, 1)
      if (size(jac, 2) /= n .or. size(del_z) /= 2*n .or. size(x) /= 2*n) then
         x = 0.0_dp
         return
      end if

      call ensure_complex_mat_workspace(workspace%guess_jac_fact, n, n)
      call ensure_int_workspace(workspace%guess_ipiv, n)
      call ensure_complex_vec_workspace(workspace%guess_z, n)

      workspace%guess_jac_fact = jac
      call real_to_complex(del_z, workspace%guess_z)
      call zgesv(n, 1, workspace%guess_jac_fact, n, workspace%guess_ipiv, workspace%guess_z, n, info)

      if (info /= 0) then
         ! If J is singular/ill-conditioned, solve a lightly regularized system
         ! (J + lambda*I) * dz = del_z, matching the BTN paper-variable seed.
         max_abs_jac = max(1.0_dp, maxval(abs(jac)))
         base_shift = max(1.0e-14_dp, sqrt(epsilon(1.0_dp))*max_abs_jac)
         ridge = base_shift
         do ridge_idx = 1, 8
            workspace%guess_jac_fact = jac
            do i = 1, n
               workspace%guess_jac_fact(i, i) = workspace%guess_jac_fact(i, i) + cmplx(ridge, 0.0_dp, dp)
            end do
            call real_to_complex(del_z, workspace%guess_z)
            call zgesv(n, 1, workspace%guess_jac_fact, n, workspace%guess_ipiv, workspace%guess_z, n, info)
            if (info == 0) exit
            ridge = ridge*10.0_dp
         end do
      end if

      if (info /= 0) then
         x = 0.0_dp
      else
         x(1:n) = aimag(workspace%guess_z)
         x(n + 1:) = real(workspace%guess_z, dp)
      end if
   end subroutine initial_guess_from_jacobian_with_workspace

   subroutine initial_guess_from_projection_target(jac, z_base, del_z, z_target, x, workspace)
      implicit none
      complex(dp), intent(in) :: jac(:, :), z_base(:), z_target(:)
      real(dp), intent(in) :: del_z(:)
      real(dp), intent(out) :: x(:)
      type(qn_linear_workspace_t), intent(inout), optional :: workspace

      type(qn_linear_workspace_t) :: local_workspace

      if (present(workspace)) then
         call initial_guess_from_projection_target_with_workspace(jac, z_base, del_z, z_target, x, workspace)
      else
         call initial_guess_from_projection_target_with_workspace(jac, z_base, del_z, z_target, x, local_workspace)
      end if
   end subroutine initial_guess_from_projection_target

   subroutine initial_guess_from_projection_target_with_workspace(jac, z_base, del_z, z_target, x, workspace)
      implicit none
      complex(dp), intent(in) :: jac(:, :), z_base(:), z_target(:)
      real(dp), intent(in) :: del_z(:)
      real(dp), intent(out) :: x(:)
      type(qn_linear_workspace_t), intent(inout) :: workspace

      integer :: n, n2, info, i

      n = size(jac, 1)
      n2 = 2*n
      if (size(jac, 2) /= n .or. size(z_base) /= n .or. size(z_target) /= n .or. size(del_z) /= n2 .or. size(x) /= n2) then
         x = 0.0_dp
         return
      end if

      call ensure_complex_vec_workspace(workspace%guess_rhs_c, n)
      call ensure_real_mat_workspace(workspace%guess_jacr, n2, n2)
      call ensure_real_vec_workspace(workspace%guess_rhs_r, n2)
      call ensure_real_vec_workspace(workspace%guess_sol_r, n2)
      call ensure_real_vec_workspace(workspace%guess_proj_r, n2)
      call ensure_real_mat_workspace(workspace%linear_jac_fact, n2, n2)
      call ensure_int_workspace(workspace%guess_ipiv, n2)

      call real_to_complex(del_z, workspace%guess_rhs_c)
      workspace%guess_rhs_c = z_target - z_base - workspace%guess_rhs_c
      call complex_to_real(workspace%guess_rhs_c, workspace%guess_rhs_r)

      call map_to_real_mat(jac, workspace%guess_jacr)

      workspace%linear_jac_fact = workspace%guess_jacr
      workspace%guess_sol_r = workspace%guess_rhs_r
      call dgesv(n2, 1, workspace%linear_jac_fact, n2, workspace%guess_ipiv, workspace%guess_sol_r, n2, info)
      if (info /= 0) then
         x = 0.0_dp
         return
      end if

      ! Projection split:
      ! - real slots (lambda_prime) come from projected real solve
      ! - imaginary slots (lambda) come from the complementary component
      workspace%guess_proj_r = workspace%guess_sol_r
      call real_vec(workspace%guess_proj_r)
      call dgemv('N', n2, n2, 1.0_dp, workspace%guess_jacr, n2, workspace%guess_proj_r, 1, 0.0_dp, &
                 workspace%guess_sol_r, 1)
      workspace%guess_sol_r = workspace%guess_rhs_r - workspace%guess_sol_r

      workspace%linear_jac_fact = workspace%guess_jacr
      call dgesv(n2, 1, workspace%linear_jac_fact, n2, workspace%guess_ipiv, workspace%guess_sol_r, n2, info)
      if (info /= 0) then
         x = 0.0_dp
         return
      end if

      do i = 1, n
         x(i) = workspace%guess_sol_r(2*i)
         x(n + i) = workspace%guess_proj_r(2*i - 1)
      end do
   end subroutine initial_guess_from_projection_target_with_workspace

   subroutine ensure_int_workspace(buf, n_need)
      implicit none
      integer, allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_int_workspace

   subroutine ensure_real_mat_workspace(buf, nr, nc)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:, :)
      integer, intent(in) :: nr, nc

      if (.not. allocated(buf)) then
         allocate (buf(nr, nc))
      elseif (size(buf, 1) < nr .or. size(buf, 2) < nc) then
         deallocate (buf)
         allocate (buf(nr, nc))
      end if
   end subroutine ensure_real_mat_workspace

   subroutine ensure_real_vec_workspace(buf, n_need)
      implicit none
      real(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_real_vec_workspace

   subroutine ensure_complex_mat_workspace(buf, nr, nc)
      implicit none
      complex(dp), allocatable, intent(inout) :: buf(:, :)
      integer, intent(in) :: nr, nc

      if (.not. allocated(buf)) then
         allocate (buf(nr, nc))
      elseif (size(buf, 1) < nr .or. size(buf, 2) < nc) then
         deallocate (buf)
         allocate (buf(nr, nc))
      end if
   end subroutine ensure_complex_mat_workspace

   subroutine ensure_complex_vec_workspace(buf, n_need)
      implicit none
      complex(dp), allocatable, intent(inout) :: buf(:)
      integer, intent(in) :: n_need

      if (.not. allocated(buf)) then
         allocate (buf(n_need))
      elseif (size(buf) < n_need) then
         deallocate (buf)
         allocate (buf(n_need))
      end if
   end subroutine ensure_complex_vec_workspace

   subroutine release_qn_linear_workspace(workspace)
      implicit none
      type(qn_linear_workspace_t), intent(inout) :: workspace

      if (allocated(workspace%linear_ipiv)) deallocate (workspace%linear_ipiv)
      if (allocated(workspace%guess_ipiv)) deallocate (workspace%guess_ipiv)
      if (allocated(workspace%linear_jac_fact)) deallocate (workspace%linear_jac_fact)
      if (allocated(workspace%guess_jacr)) deallocate (workspace%guess_jacr)
      if (allocated(workspace%guess_rhs_r)) deallocate (workspace%guess_rhs_r)
      if (allocated(workspace%guess_sol_r)) deallocate (workspace%guess_sol_r)
      if (allocated(workspace%guess_proj_r)) deallocate (workspace%guess_proj_r)
      if (allocated(workspace%guess_jac_fact)) deallocate (workspace%guess_jac_fact)
      if (allocated(workspace%guess_z)) deallocate (workspace%guess_z)
      if (allocated(workspace%guess_rhs_c)) deallocate (workspace%guess_rhs_c)
   end subroutine release_qn_linear_workspace

end module quasi_newton_linear_solver_mod

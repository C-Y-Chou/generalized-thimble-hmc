module quasi_newton_linear_solver_mod
   use utils, only: dp, real_to_complex
   implicit none
   external :: zgesv

   type :: qn_linear_workspace_t
      integer, allocatable :: guess_ipiv(:)
      complex(dp), allocatable :: guess_jac_fact(:, :), guess_z(:)
   end type qn_linear_workspace_t

contains

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

      if (allocated(workspace%guess_ipiv)) deallocate (workspace%guess_ipiv)
      if (allocated(workspace%guess_jac_fact)) deallocate (workspace%guess_jac_fact)
      if (allocated(workspace%guess_z)) deallocate (workspace%guess_z)
   end subroutine release_qn_linear_workspace

end module quasi_newton_linear_solver_mod

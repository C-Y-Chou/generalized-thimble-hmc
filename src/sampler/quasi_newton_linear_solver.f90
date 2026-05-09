module quasi_newton_linear_solver_mod
   use utils, only: dp, complex_to_real, map_to_real_mat, real_to_complex, real_vec
   implicit none
   external :: dgesv, zgesv, dgemv

   integer, allocatable, save :: linear_ipiv(:), guess_ipiv(:)
   real(dp), allocatable, save :: linear_jac_fact(:, :)
   real(dp), allocatable, save :: guess_jacr(:, :), guess_rhs_r(:), guess_sol_r(:), guess_proj_r(:)
   complex(dp), allocatable, save :: guess_jac_fact(:, :), guess_z(:), guess_rhs_c(:)

contains

   subroutine solve_linear_direction(f_val, jac_approx, direction, ierr)
      implicit none
      real(dp), intent(in) :: f_val(:)
      real(dp), intent(in) :: jac_approx(:, :)
      real(dp), intent(out) :: direction(:)
      logical, intent(out) :: ierr

      integer :: n, info, ridge_idx, row_idx
      real(dp) :: base_shift, ridge

      n = size(f_val)
      ierr = .false.

      if (size(direction) /= n .or. size(jac_approx, 1) /= n .or. size(jac_approx, 2) /= n) then
         ierr = .true.
         return
      end if

      call ensure_real_mat_workspace(linear_jac_fact, n, n)
      call ensure_int_workspace(linear_ipiv, n)

      linear_jac_fact = jac_approx
      direction = -f_val
      call dgesv(n, 1, linear_jac_fact, n, linear_ipiv, direction, n, info)
      if (info == 0) return

      base_shift = max(1.0e-12_dp, sqrt(epsilon(1.0_dp))*maxval(abs(jac_approx)))
      do ridge_idx = 1, 3
         ridge = base_shift*10.0_dp**real(ridge_idx - 1, dp)
         linear_jac_fact = jac_approx
         do row_idx = 1, n
            linear_jac_fact(row_idx, row_idx) = linear_jac_fact(row_idx, row_idx) + ridge
         end do
         direction = -f_val
         call dgesv(n, 1, linear_jac_fact, n, linear_ipiv, direction, n, info)
         if (info == 0) return
      end do

      ierr = .true.
   end subroutine solve_linear_direction

   subroutine initial_guess_from_jacobian(jac, del_z, x)
      implicit none
      complex(dp), intent(in) :: jac(:, :)
      real(dp), intent(in) :: del_z(:)
      real(dp), intent(out) :: x(:)

      integer :: n, info, i, ridge_idx
      real(dp) :: base_shift, ridge, max_abs_jac

      n = size(jac, 1)
      if (size(jac, 2) /= n .or. size(del_z) /= 2*n .or. size(x) /= 2*n) then
         x = 0.0_dp
         return
      end if

      call ensure_complex_mat_workspace(guess_jac_fact, n, n)
      call ensure_int_workspace(guess_ipiv, n)
      call ensure_complex_vec_workspace(guess_z, n)

      guess_jac_fact = jac
      call real_to_complex(del_z, guess_z)
      call zgesv(n, 1, guess_jac_fact, n, guess_ipiv, guess_z, n, info)

      if (info /= 0) then
         ! If J is singular/ill-conditioned, solve a lightly regularized system
         ! (J + lambda*I) * dz = del_z, matching the BTN paper-variable seed.
         max_abs_jac = max(1.0_dp, maxval(abs(jac)))
         base_shift = max(1.0e-14_dp, sqrt(epsilon(1.0_dp))*max_abs_jac)
         ridge = base_shift
         do ridge_idx = 1, 8
            guess_jac_fact = jac
            do i = 1, n
               guess_jac_fact(i, i) = guess_jac_fact(i, i) + cmplx(ridge, 0.0_dp, dp)
            end do
            call real_to_complex(del_z, guess_z)
            call zgesv(n, 1, guess_jac_fact, n, guess_ipiv, guess_z, n, info)
            if (info == 0) exit
            ridge = ridge*10.0_dp
         end do
      end if

      if (info /= 0) then
         x = 0.0_dp
      else
         x(1:n) = aimag(guess_z)
         x(n + 1:) = real(guess_z, dp)
      end if
   end subroutine initial_guess_from_jacobian

   subroutine initial_guess_from_projection_target(jac, z_base, del_z, z_target, x)
      implicit none
      complex(dp), intent(in) :: jac(:, :), z_base(:), z_target(:)
      real(dp), intent(in) :: del_z(:)
      real(dp), intent(out) :: x(:)

      integer :: n, n2, info, i

      n = size(jac, 1)
      n2 = 2*n
      if (size(jac, 2) /= n .or. size(z_base) /= n .or. size(z_target) /= n .or. size(del_z) /= n2 .or. size(x) /= n2) then
         x = 0.0_dp
         return
      end if

      call ensure_complex_vec_workspace(guess_rhs_c, n)
      call ensure_real_mat_workspace(guess_jacr, n2, n2)
      call ensure_real_vec_workspace(guess_rhs_r, n2)
      call ensure_real_vec_workspace(guess_sol_r, n2)
      call ensure_real_vec_workspace(guess_proj_r, n2)
      call ensure_real_mat_workspace(linear_jac_fact, n2, n2)
      call ensure_int_workspace(guess_ipiv, n2)

      call real_to_complex(del_z, guess_rhs_c)
      guess_rhs_c = z_target - z_base - guess_rhs_c
      call complex_to_real(guess_rhs_c, guess_rhs_r)

      call map_to_real_mat(jac, guess_jacr)

      linear_jac_fact = guess_jacr
      guess_sol_r = guess_rhs_r
      call dgesv(n2, 1, linear_jac_fact, n2, guess_ipiv, guess_sol_r, n2, info)
      if (info /= 0) then
         x = 0.0_dp
         return
      end if

      ! Projection split:
      ! - real slots (lambda_prime) come from projected real solve
      ! - imaginary slots (lambda) come from the complementary component
      guess_proj_r = guess_sol_r
      call real_vec(guess_proj_r)
      call dgemv('N', n2, n2, 1.0_dp, guess_jacr, n2, guess_proj_r, 1, 0.0_dp, guess_sol_r, 1)
      guess_sol_r = guess_rhs_r - guess_sol_r

      linear_jac_fact = guess_jacr
      call dgesv(n2, 1, linear_jac_fact, n2, guess_ipiv, guess_sol_r, n2, info)
      if (info /= 0) then
         x = 0.0_dp
         return
      end if

      do i = 1, n
         x(i) = guess_sol_r(2*i)
         x(n + i) = guess_proj_r(2*i - 1)
      end do
   end subroutine initial_guess_from_projection_target

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

end module quasi_newton_linear_solver_mod

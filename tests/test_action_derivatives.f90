program test_action_derivatives
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use model, only: calculate_action, ds, hessian, hessian_vec
   use model_observables, only: evaluate_model_observables, find_model_observable, get_model_observable_name, model_observable_count
   use param_mod, only: derivative_mode, set_derivative_mode, stephanov_emit_diagnostics, stephanov_include_mu_prefactor, &
                        stephanov_mass, stephanov_mu, stephanov_n, stephanov_nf, stephanov_tau
   use utils, only: dp
   implicit none

   complex(dp), allocatable :: z_state(:), z_work(:), v_dir(:)
   complex(dp), allocatable :: grad_manual(:), grad_numeric(:)
   complex(dp), allocatable :: hv_manual(:), hv_numeric(:)
   complex(dp), allocatable :: grad_p2(:), grad_p1(:), grad_m1(:), grad_m2(:)
   complex(dp), allocatable :: hess_manual(:, :)
   complex(dp), allocatable :: observables(:)
   real(dp), allocatable :: random_real(:), random_imag(:)
   integer, allocatable :: rng_seed(:)
   integer :: seed_size, n_state, i, name_idx
   real(dp) :: h, grad_diff_norm, hv_diff_norm, hess_hv_diff_norm
   complex(dp) :: action_p2, action_p1, action_m1, action_m2
   character(len=64) :: obs_name

   call configure_stephanov_test_model()
   call random_seed(size=seed_size)
   allocate (rng_seed(seed_size))
   rng_seed = [(24681357 + 97*i, i=1, seed_size)]
   call random_seed(put=rng_seed)

   n_state = 2*stephanov_n*stephanov_n
   allocate (z_state(n_state), z_work(n_state), v_dir(n_state))
   allocate (grad_manual(n_state), grad_numeric(n_state), hv_manual(n_state), hv_numeric(n_state))
   allocate (grad_p2(n_state), grad_p1(n_state), grad_m1(n_state), grad_m2(n_state))
   allocate (hess_manual(n_state, n_state), random_real(n_state), random_imag(n_state))

   call random_number(random_real)
   call random_number(random_imag)
   do i = 1, n_state
      z_state(i) = cmplx(0.25_dp*(2.0_dp*random_real(i) - 1.0_dp), &
                         0.20_dp*(2.0_dp*random_imag(i) - 1.0_dp), dp)
   end do
   call random_number(random_real)
   call random_number(random_imag)
   do i = 1, n_state
      v_dir(i) = cmplx(0.30_dp*(2.0_dp*random_real(i) - 1.0_dp), &
                       0.30_dp*(2.0_dp*random_imag(i) - 1.0_dp), dp)
   end do

   h = 2.0e-5_dp
   write (*, '(A,I0,A,I0)') "[INIT] Stephanov derivative test starts. n=", stephanov_n, " n_state=", n_state
   write (*, '(A,ES12.4)') "[INIT] Five-point finite-difference step=", h

   call ds(z_state, grad_manual)
   do i = 1, n_state
      z_work = z_state
      z_work(i) = z_state(i) + 2.0_dp*h
      call calculate_action(z_work, action_p2)
      z_work(i) = z_state(i) + h
      call calculate_action(z_work, action_p1)
      z_work(i) = z_state(i) - h
      call calculate_action(z_work, action_m1)
      z_work(i) = z_state(i) - 2.0_dp*h
      call calculate_action(z_work, action_m2)
      grad_numeric(i) = (-action_p2 + 8.0_dp*action_p1 - 8.0_dp*action_m1 + action_m2)/(12.0_dp*h)
   end do
   grad_diff_norm = sqrt(sum(abs(grad_manual - grad_numeric)**2))
   write (*, '(A,ES12.4)') "[CHECK] Norm of ds(manual-fd)=", grad_diff_norm
   if (grad_diff_norm > 1.0e-7_dp) then
      write (*, '(A)') "[ERROR] Stephanov manual ds does not match finite-difference oracle."
      call print_vector_diffs("ds", grad_manual, grad_numeric)
      error stop 1
   end if

   call hessian_vec(z_state, v_dir, hv_manual)
   z_work = z_state + 2.0_dp*h*v_dir
   call ds(z_work, grad_p2)
   z_work = z_state + h*v_dir
   call ds(z_work, grad_p1)
   z_work = z_state - h*v_dir
   call ds(z_work, grad_m1)
   z_work = z_state - 2.0_dp*h*v_dir
   call ds(z_work, grad_m2)
   hv_numeric = (-grad_p2 + 8.0_dp*grad_p1 - 8.0_dp*grad_m1 + grad_m2)/(12.0_dp*h)
   hv_diff_norm = sqrt(sum(abs(hv_manual - hv_numeric)**2))
   write (*, '(A,ES12.4)') "[CHECK] Norm of Hv(manual-fd)=", hv_diff_norm
   if (hv_diff_norm > 2.0e-6_dp) then
      write (*, '(A)') "[ERROR] Stephanov manual hessian_vec does not match finite-difference oracle."
      call print_vector_diffs("hv", hv_manual, hv_numeric)
      error stop 1
   end if

   call hessian(z_state, hess_manual)
   hess_hv_diff_norm = sqrt(sum(abs(matmul(hess_manual, v_dir) - hv_manual)**2))
   write (*, '(A,ES12.4)') "[CHECK] Norm of hessian*v-Hv=", hess_hv_diff_norm
   if (hess_hv_diff_norm > 1.0e-10_dp) then
      write (*, '(A)') "[ERROR] Stephanov hessian wrapper does not match hessian_vec columns."
      error stop 1
   end if

   call check_observables(z_state)
   write (*, '(A,A)') "[CHECK] derivative_mode=", trim(derivative_mode)
   write (*, '(A)') "[DONE] Stephanov random-complex derivative test complete."

contains

   subroutine configure_stephanov_test_model()
      stephanov_n = 2
      stephanov_nf = 1
      stephanov_mass = 0.2_dp
      stephanov_mu = 0.3_dp
      stephanov_tau = 0.1_dp
      stephanov_include_mu_prefactor = .false.
      stephanov_emit_diagnostics = .true.
      call set_derivative_mode("manual")
   end subroutine configure_stephanov_test_model

   subroutine check_observables(z_state_in)
      complex(dp), intent(in) :: z_state_in(:)
      integer :: obs_count, obs_idx

      obs_count = model_observable_count()
      if (obs_count /= 5) then
         write (*, '(A,I0)') "[ERROR] Expected five Stephanov observables with diagnostics enabled; got ", obs_count
         error stop 1
      end if
      allocate (observables(obs_count))
      call evaluate_model_observables(z_state_in, observables)
      do obs_idx = 1, obs_count
         call get_model_observable_name(obs_idx, obs_name)
         if (len_trim(obs_name) <= 0 .or. find_model_observable(obs_name) /= obs_idx) then
            write (*, '(A,I0,A,A)') "[ERROR] Observable registry mismatch at index ", obs_idx, ": ", trim(obs_name)
            error stop 1
         end if
         if ((.not. ieee_is_finite(real(observables(obs_idx), dp))) .or. &
             (.not. ieee_is_finite(aimag(observables(obs_idx))))) then
            write (*, '(A,A)') "[ERROR] Nonfinite observable: ", trim(obs_name)
            error stop 1
         end if
      end do

      name_idx = find_model_observable("phase_factor")
      if (abs(abs(observables(name_idx)) - 1.0_dp) > 1.0e-12_dp) then
         write (*, '(A,ES12.4)') "[ERROR] phase_factor magnitude is not one: ", abs(observables(name_idx))
         error stop 1
      end if
      name_idx = find_model_observable("min_singular_ba_m2")
      if (real(observables(name_idx), dp) < 0.0_dp .or. abs(aimag(observables(name_idx))) > 1.0e-12_dp) then
         write (*, '(A)') "[ERROR] min_singular_ba_m2 must be a nonnegative real diagnostic."
         error stop 1
      end if
      write (*, '(A,I0)') "[CHECK] Stephanov observable registry/count=", obs_count
   end subroutine check_observables

   subroutine print_vector_diffs(label, actual, expected)
      character(len=*), intent(in) :: label
      complex(dp), intent(in) :: actual(:), expected(:)
      integer :: idx

      write (*, '(A,A)') "[DETAIL] component diffs for ", trim(label)
      write (*, '(A)') " idx              actual                    expected                   |diff|"
      do idx = 1, size(actual)
         write (*, '(I4,2X,2ES14.5,2X,2ES14.5,2X,ES14.5)') idx, real(actual(idx), dp), aimag(actual(idx)), &
            real(expected(idx), dp), aimag(expected(idx)), abs(actual(idx) - expected(idx))
      end do
   end subroutine print_vector_diffs

end program test_action_derivatives

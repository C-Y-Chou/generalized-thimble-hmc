program test_action_derivatives
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use model, only: calculate_action, ds, ds_hessian_vec_batch, hessian, hessian_vec
   use model_observables, only: evaluate_model_observables, find_model_observable, get_model_observable_name, model_observable_count
   use param_mod, only: derivative_mode, set_derivative_mode, stephanov_emit_diagnostics, stephanov_include_mu_prefactor, &
                        stephanov_mass, stephanov_mu, stephanov_n, stephanov_nf, stephanov_tau
   use utils, only: dp
   implicit none

   complex(dp), allocatable :: z_state(:), z_work(:), v_dir(:), v_batch(:, :)
   complex(dp), allocatable :: grad_manual(:), grad_numeric(:)
   complex(dp), allocatable :: hv_manual(:), hv_numeric(:), hv_batch(:, :), hv_reference(:, :)
   complex(dp), allocatable :: grad_batch(:)
   complex(dp), allocatable :: grad_p2(:), grad_p1(:), grad_m1(:), grad_m2(:)
   complex(dp), allocatable :: hess_manual(:, :)
   complex(dp), allocatable :: observables(:)
   real(dp), allocatable :: random_real(:), random_imag(:)
   integer, allocatable :: rng_seed(:)
   integer :: seed_size, n_state, i, name_idx
   real(dp) :: h, grad_diff_norm, hv_diff_norm, hess_hv_diff_norm
   complex(dp) :: action_p2, action_p1, action_m1, action_m2
   character(len=64) :: obs_name

   call run_stephanov_derivative_case("smoke_n2_mu03", 2, 0.2_dp, 0.3_dp, 0.1_dp, 24681357)
   call run_stephanov_derivative_case("benchmark_n4_mu06", 4, 0.004_dp, 0.6_dp, 0.0_dp, 13579246)
   call run_stephanov_derivative_case("working_n6_mu06", 6, 0.004_dp, 0.6_dp, 0.0_dp, 97531864)
   write (*, '(A)') "[DONE] Stephanov random-complex derivative test suite complete."

contains

   subroutine run_stephanov_derivative_case(case_label, n_model, mass, mu, tau, seed_base)
      character(len=*), intent(in) :: case_label
      integer, intent(in) :: n_model, seed_base
      real(dp), intent(in) :: mass, mu, tau

      call configure_stephanov_test_model(n_model, mass, mu, tau)
      call random_seed(size=seed_size)
      if (allocated(rng_seed)) deallocate (rng_seed)
      allocate (rng_seed(seed_size))
      rng_seed = [(seed_base + 97*i, i=1, seed_size)]
      call random_seed(put=rng_seed)

      n_state = 2*stephanov_n*stephanov_n
      call reset_case_allocations()
      allocate (z_state(n_state), z_work(n_state), v_dir(n_state), v_batch(n_state, 4))
      allocate (grad_manual(n_state), grad_numeric(n_state), hv_manual(n_state), hv_numeric(n_state))
      allocate (grad_batch(n_state), hv_batch(n_state, 4), hv_reference(n_state, 4))
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
      write (*, '(A,A,A,I0,A,I0,A,ES10.3,A,ES10.3,A,ES10.3)') "[INIT] Stephanov derivative case=", trim(case_label), &
         " n=", stephanov_n, " n_state=", n_state, " m=", stephanov_mass, " mu=", stephanov_mu, " tau=", stephanov_tau
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

      call fill_batch_directions(n_state)
      call ds_hessian_vec_batch(z_state, v_batch, grad_batch, hv_batch)
      do i = 1, size(v_batch, 2)
         call hessian_vec(z_state, v_batch(:, i), hv_reference(:, i))
      end do
      grad_diff_norm = sqrt(sum(abs(grad_batch - grad_manual)**2))
      hv_diff_norm = sqrt(sum(abs(hv_batch - hv_reference)**2))
      write (*, '(A,ES12.4)') "[CHECK] Norm of batched ds-scalar ds=", grad_diff_norm
      write (*, '(A,ES12.4)') "[CHECK] Norm of batched Hv-scalar Hv=", hv_diff_norm
      if (grad_diff_norm > 1.0e-12_dp .or. hv_diff_norm > 1.0e-11_dp) then
         write (*, '(A)') "[ERROR] Stephanov batched ds/Hv provider does not match scalar reference."
         error stop 1
      end if

      call check_observables(z_state)
      write (*, '(A,A)') "[CHECK] derivative_mode=", trim(derivative_mode)
      write (*, '(A,A)') "[DONE] Stephanov random-complex derivative case complete: ", trim(case_label)
   end subroutine run_stephanov_derivative_case

   subroutine configure_stephanov_test_model(n_model, mass, mu, tau)
      integer, intent(in) :: n_model
      real(dp), intent(in) :: mass, mu, tau

      stephanov_n = n_model
      stephanov_nf = 1
      stephanov_mass = mass
      stephanov_mu = mu
      stephanov_tau = tau
      stephanov_include_mu_prefactor = .false.
      stephanov_emit_diagnostics = .true.
      call set_derivative_mode("manual")
   end subroutine configure_stephanov_test_model

   subroutine reset_case_allocations()
      if (allocated(z_state)) deallocate (z_state)
      if (allocated(z_work)) deallocate (z_work)
      if (allocated(v_dir)) deallocate (v_dir)
      if (allocated(v_batch)) deallocate (v_batch)
      if (allocated(grad_manual)) deallocate (grad_manual)
      if (allocated(grad_numeric)) deallocate (grad_numeric)
      if (allocated(grad_batch)) deallocate (grad_batch)
      if (allocated(hv_manual)) deallocate (hv_manual)
      if (allocated(hv_numeric)) deallocate (hv_numeric)
      if (allocated(hv_batch)) deallocate (hv_batch)
      if (allocated(hv_reference)) deallocate (hv_reference)
      if (allocated(grad_p2)) deallocate (grad_p2)
      if (allocated(grad_p1)) deallocate (grad_p1)
      if (allocated(grad_m1)) deallocate (grad_m1)
      if (allocated(grad_m2)) deallocate (grad_m2)
      if (allocated(hess_manual)) deallocate (hess_manual)
      if (allocated(random_real)) deallocate (random_real)
      if (allocated(random_imag)) deallocate (random_imag)
      if (allocated(observables)) deallocate (observables)
   end subroutine reset_case_allocations

   subroutine fill_batch_directions(n_state_in)
      integer, intent(in) :: n_state_in
      integer :: col

      v_batch(:, 1) = v_dir
      v_batch(:, 2) = cmplx(0.0_dp, 0.0_dp, dp)
      v_batch(1, 2) = cmplx(1.0_dp, 0.0_dp, dp)
      v_batch(:, 3) = cmplx(0.0_dp, 0.0_dp, dp)
      v_batch(n_state_in, 3) = cmplx(0.0_dp, 1.0_dp, dp)
      call random_number(random_real)
      call random_number(random_imag)
      do col = 1, n_state_in
         v_batch(col, 4) = cmplx(0.15_dp*(2.0_dp*random_real(col) - 1.0_dp), &
                                 0.15_dp*(2.0_dp*random_imag(col) - 1.0_dp), dp)
      end do
   end subroutine fill_batch_directions

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

program test_action_derivatives
   use model, only: calculate_action, ds, hessian, hessian_vec, model_context_t, bind_model_context, release_model_context
   use param_mod, only: alpha, beta, read_parameters, set_derivative_mode, state_seed_size_cfg
   use utils, only: dp
   implicit none

   complex(dp), allocatable :: z_state(:)
   complex(dp), allocatable :: ds_generated_mode(:), ds_numeric(:)
   complex(dp), allocatable :: ds_closed(:), hessian_closed(:, :), hv_closed(:)
   complex(dp), allocatable :: action_p2(:), action_p1(:), action_m1(:), action_m2(:)
   complex(dp), allocatable :: ds_p2(:), ds_p1(:), ds_m1(:), ds_m2(:)
   complex(dp), allocatable :: hessian_generated_mode(:, :), hessian_numeric(:, :)
   complex(dp), allocatable :: v_dir(:), hv_generated_mode(:), hv_numeric(:)

   real(dp), allocatable :: random_real(:), random_imag(:)
   real(dp) :: action_closed_diff, ds_closed_diff_norm, hessian_closed_diff_norm, hv_closed_diff_norm
   real(dp) :: ds_diff_norm, hessian_diff_norm, hv_diff_norm
   real(dp) :: step_size_optimal
   real(dp) :: t_start, t_end, ds_time_seconds

   complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
   complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
   complex(dp) :: action_value, action_closed, denom, perturbation
   complex(dp) :: z_original

   integer :: seed_size, state_size
   integer :: i_idx, j_idx
   integer, allocatable :: rng_seed(:)

   call random_seed(size=seed_size)
   allocate (rng_seed(seed_size))
   rng_seed = [(1234567 + 37*j_idx, j_idx=1, seed_size)]
   call random_seed(put=rng_seed)

   call read_parameters()
   call set_derivative_mode("generated")
   state_size = state_seed_size_cfg()

   allocate (z_state(state_size), ds_generated_mode(state_size), ds_numeric(state_size))
   allocate (ds_closed(state_size), hessian_closed(state_size, state_size), hv_closed(state_size))
   allocate (hessian_generated_mode(state_size, state_size), hessian_numeric(state_size, state_size))
   allocate (v_dir(state_size), hv_generated_mode(state_size), hv_numeric(state_size))
   allocate (random_real(state_size), random_imag(state_size))
   allocate (action_p2(state_size), action_p1(state_size), action_m1(state_size), action_m2(state_size))
   allocate (ds_p2(state_size), ds_p1(state_size), ds_m1(state_size), ds_m2(state_size))

   call random_number(random_real)
   call random_number(random_imag)
   z_state = [(cmplx(random_real(i_idx), random_imag(i_idx), dp), i_idx=1, state_size)]
   v_dir = [(cmplx(0.05_dp + 0.01_dp*i_idx, -0.02_dp + 0.015_dp*i_idx, dp), i_idx=1, state_size)]

   step_size_optimal = epsilon(1.0_dp)**(0.2_dp)
   perturbation = cmplx(0.0_dp, step_size_optimal, dp)

   write (*, '(A,I0)') "[INIT] Action-derivative test starts. n_seed=", state_size
   write (*, '(A,ES12.4)') "[INIT] Five-point stencil step size=", step_size_optimal

   action_closed = cmplx(0.0_dp, 0.0_dp, dp)
   ds_closed = cmplx(0.0_dp, 0.0_dp, dp)
   hessian_closed = cmplx(0.0_dp, 0.0_dp, dp)
   do i_idx = 1, state_size
      denom = z_state(i_idx) - ci*beta
      action_closed = action_closed - ci*(z_state(i_idx)**3/three + z_state(i_idx)*alpha) - log(denom)
      ds_closed(i_idx) = -ci*(z_state(i_idx)**2 + alpha) - cmplx(1.0_dp, 0.0_dp, dp)/denom
      hessian_closed(i_idx, i_idx) = -cmplx(2.0_dp, 0.0_dp, dp)*ci*z_state(i_idx) + &
                                     cmplx(1.0_dp, 0.0_dp, dp)/(denom*denom)
   end do
   hv_closed = matmul(hessian_closed, v_dir)

   call calculate_action(z_state, action_value)
   call ds(z_state, ds_generated_mode)
   call hessian(z_state, hessian_generated_mode)
   call hessian_vec(z_state, v_dir, hv_generated_mode)
   action_closed_diff = abs(action_value - action_closed)
   ds_closed_diff_norm = sqrt(sum(abs(ds_generated_mode - ds_closed)**2))
   hessian_closed_diff_norm = sqrt(sum(abs(hessian_generated_mode - hessian_closed)**2))
   hv_closed_diff_norm = sqrt(sum(abs(hv_generated_mode - hv_closed)**2))
   write (*, '(A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] closed_form action=", action_closed_diff, &
      " ds=", ds_closed_diff_norm, " hessian=", hessian_closed_diff_norm, " hv=", hv_closed_diff_norm
   if (action_closed_diff > 1.0e-12_dp .or. ds_closed_diff_norm > 1.0e-12_dp .or. &
       hessian_closed_diff_norm > 1.0e-12_dp .or. hv_closed_diff_norm > 1.0e-12_dp) then
      write (*, '(A)') "[ERROR] Generated action/derivatives do not match the closed-form model."
      error stop 1
   end if

   call cpu_time(t_start)
   call ds(z_state, ds_generated_mode)
   call cpu_time(t_end)
   ds_time_seconds = t_end - t_start
   write (*, '(A,F10.6,A)') "[SUMMARY] Generated ds() runtime=", ds_time_seconds, "s"

   ds_numeric = cmplx(0.0_dp, 0.0_dp, dp)
   ds_diff_norm = 0.0_dp

   do i_idx = 1, state_size
      z_original = z_state(i_idx)

      z_state(i_idx) = z_original + 2.0_dp*perturbation
      call calculate_action(z_state, action_value)
      action_p2(i_idx) = action_value

      z_state(i_idx) = z_original + perturbation
      call calculate_action(z_state, action_value)
      action_p1(i_idx) = action_value

      z_state(i_idx) = z_original - perturbation
      call calculate_action(z_state, action_value)
      action_m1(i_idx) = action_value

      z_state(i_idx) = z_original - 2.0_dp*perturbation
      call calculate_action(z_state, action_value)
      action_m2(i_idx) = action_value

      z_state(i_idx) = z_original

      ds_numeric(i_idx) = (-action_p2(i_idx) + 8.0_dp*action_p1(i_idx) - 8.0_dp*action_m1(i_idx) + action_m2(i_idx))/ &
         (12.0_dp*perturbation)
      ds_diff_norm = ds_diff_norm + abs(ds_generated_mode(i_idx) - ds_numeric(i_idx))**2
   end do
   ds_diff_norm = sqrt(ds_diff_norm)

   write (*, '(A)') "[DETAIL] ds comparison by component"
   write (*, '(A)') " idx            ds_generated                    ds_numeric                   |diff|"
   do i_idx = 1, state_size
      write (*, '(I4,2X,2ES14.5,2X,2ES14.5,2X,ES14.5)') i_idx, real(ds_generated_mode(i_idx), dp), aimag(ds_generated_mode(i_idx)), &
         real(ds_numeric(i_idx), dp), aimag(ds_numeric(i_idx)), abs(ds_generated_mode(i_idx) - ds_numeric(i_idx))
   end do

   call hessian(z_state, hessian_generated_mode)
   hessian_numeric = cmplx(0.0_dp, 0.0_dp, dp)
   hessian_diff_norm = 0.0_dp

   do i_idx = 1, state_size
      z_original = z_state(i_idx)

      z_state(i_idx) = z_original + 2.0_dp*perturbation
      call ds(z_state, ds_p2)
      z_state(i_idx) = z_original + perturbation
      call ds(z_state, ds_p1)
      z_state(i_idx) = z_original - perturbation
      call ds(z_state, ds_m1)
      z_state(i_idx) = z_original - 2.0_dp*perturbation
      call ds(z_state, ds_m2)
      z_state(i_idx) = z_original

      do j_idx = 1, state_size
         hessian_numeric(i_idx, j_idx) = (-ds_p2(j_idx) + 8.0_dp*ds_p1(j_idx) - 8.0_dp*ds_m1(j_idx) + ds_m2(j_idx))/ &
            (12.0_dp*perturbation)
         hessian_diff_norm = hessian_diff_norm + abs(hessian_generated_mode(i_idx, j_idx) - hessian_numeric(i_idx, j_idx))**2
      end do
   end do
   hessian_diff_norm = sqrt(hessian_diff_norm)

   write (*, '(A)') "[DETAIL] Hessian comparison by component"
   write (*, '(A)') " i    j          hessian_generated                hessian_numeric              |diff|"
   do i_idx = 1, state_size
      do j_idx = 1, state_size
         write (*, '(I3,1X,I3,2X,2ES14.5,2X,2ES14.5,2X,ES14.5)') i_idx, j_idx, &
            real(hessian_generated_mode(i_idx, j_idx), dp), aimag(hessian_generated_mode(i_idx, j_idx)), &
            real(hessian_numeric(i_idx, j_idx), dp), aimag(hessian_numeric(i_idx, j_idx)), &
            abs(hessian_generated_mode(i_idx, j_idx) - hessian_numeric(i_idx, j_idx))
      end do
   end do

   call random_number(random_real)
   call random_number(random_imag)
   v_dir = [(cmplx(random_real(i_idx), random_imag(i_idx), dp), i_idx=1, state_size)]

   call hessian_vec(z_state, v_dir, hv_generated_mode)
   hv_numeric = matmul(hessian_numeric, v_dir)
   hv_diff_norm = sqrt(sum(abs(hv_generated_mode - hv_numeric)**2))

   write (*, '(A,ES12.4)') "[SUMMARY] Norm of ds(generated-numeric)=", ds_diff_norm
   write (*, '(A,ES12.4)') "[SUMMARY] Norm of hessian(generated-numeric)=", hessian_diff_norm
   write (*, '(A,ES12.4)') "[SUMMARY] Norm of Hv(generated-numeric)=", hv_diff_norm

   if (ds_diff_norm > 1.0e-8_dp .or. hessian_diff_norm > 1.0e-6_dp .or. hv_diff_norm > 1.0e-6_dp) then
      write (*, '(A)') "[ERROR] Generated derivatives do not match finite-difference references."
      error stop 1
   end if

   call check_model_context_isolation(z_state, v_dir)

   write (*, '(A)') "[DONE] Action-derivative test complete."

contains

   subroutine check_model_context_isolation(z_ref, v_ref)
      complex(dp), intent(in) :: z_ref(:), v_ref(:)

      type(model_context_t), target :: context_a, context_b
      complex(dp), allocatable :: z_a(:), z_b(:)
      complex(dp), allocatable :: ds_a(:), ds_a_after(:), ds_b(:)
      complex(dp), allocatable :: hv_a(:), hv_a_after(:)
      complex(dp) :: action_a, action_a_after, action_b
      real(dp) :: ds_rebind_diff, hv_rebind_diff, action_rebind_diff, distinct_diff
      integer :: n

      n = size(z_ref)
      allocate (z_a(n), z_b(n), ds_a(n), ds_a_after(n), ds_b(n), hv_a(n), hv_a_after(n))
      z_a = z_ref
      z_b = z_ref + cmplx(0.17_dp, -0.11_dp, dp)

      call bind_model_context(context_a)
      call calculate_action(z_a, action_a)
      call ds(z_a, ds_a)
      call hessian_vec(z_a, v_ref, hv_a)

      call bind_model_context(context_b)
      call calculate_action(z_b, action_b)
      call ds(z_b, ds_b)

      call bind_model_context(context_a)
      call calculate_action(z_a, action_a_after)
      call ds(z_a, ds_a_after)
      call hessian_vec(z_a, v_ref, hv_a_after)

      action_rebind_diff = abs(action_a_after - action_a)
      ds_rebind_diff = sqrt(sum(abs(ds_a_after - ds_a)**2))
      hv_rebind_diff = sqrt(sum(abs(hv_a_after - hv_a)**2))
      distinct_diff = abs(action_b - action_a) + sqrt(sum(abs(ds_b - ds_a)**2))
      write (*, '(A,ES12.4,A,ES12.4,A,ES12.4,A,ES12.4)') "[CHECK] model_context_isolation action=", &
         action_rebind_diff, " ds=", ds_rebind_diff, " hv=", hv_rebind_diff, " distinct=", distinct_diff
      if (action_rebind_diff > 1.0e-12_dp .or. ds_rebind_diff > 1.0e-12_dp .or. &
          hv_rebind_diff > 1.0e-12_dp .or. distinct_diff <= 1.0e-10_dp) then
         write (*, '(A)') "[ERROR] Model tape/cache contexts are not isolated across rebinds."
         error stop 1
      end if

      call release_model_context(context_a)
      call release_model_context(context_b)
      if (allocated(z_a)) deallocate (z_a)
      if (allocated(z_b)) deallocate (z_b)
      if (allocated(ds_a)) deallocate (ds_a)
      if (allocated(ds_a_after)) deallocate (ds_a_after)
      if (allocated(ds_b)) deallocate (ds_b)
      if (allocated(hv_a)) deallocate (hv_a)
      if (allocated(hv_a_after)) deallocate (hv_a_after)
   end subroutine check_model_context_isolation

end program test_action_derivatives

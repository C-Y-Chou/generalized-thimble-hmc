program test_retained_core_rattle_rg_contract
   use hmc_integrator_core, only: get_reverse_gate_replay_status_counts, hmc_step_status_success, &
                                  reset_reverse_gate_replay_status_counts, rattle_step_core
   use hmc_kernels, only: decompose2
   use hmc_state_buffers, only: release_rattle_step_workspace, rattle_step_workspace_t
   use param_mod, only: cttol, read_parameters, state_seed_size_cfg
   use solve_flow, only: flow, intode_status_is_strict_success, intode_status_unknown
   use utils, only: dp, x_set_flow_time, x_set_seed_real
   use, intrinsic :: iso_fortran_env, only: int64
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   implicit none

   integer :: failures, n_seed, x_size, flow_status, step_status
   real(dp), allocatable :: seed(:), x(:), final_x(:), momentum(:)
   real(dp), allocatable :: tangent(:), tangent_component(:), normal_component(:)
   complex(dp), allocatable :: z(:), final_z(:), jac(:,:), jacf(:,:), z_check(:), jac_check(:,:)
   logical :: flow_failed, converged
   type(rattle_step_workspace_t) :: ws

   failures = 0
   call read_parameters()
   n_seed = state_seed_size_cfg()
   x_size = 1 + n_seed

   allocate (seed(n_seed), x(x_size), final_x(x_size))
   allocate (momentum(2*n_seed), tangent(2*n_seed), tangent_component(2*n_seed), normal_component(2*n_seed))
   allocate (z(n_seed), final_z(n_seed), jac(n_seed, n_seed), jacf(n_seed, n_seed), z_check(n_seed), jac_check(n_seed, n_seed))

   call fill_seed(seed)
   call x_set_flow_time(x, 0.08_dp)
   call x_set_seed_real(x, seed)
   flow_status = intode_status_unknown
   call flow(x, z, jac, flow_failed, flow_status)
   if (flow_failed .or. (.not. intode_status_is_strict_success(flow_status))) then
      write (*, '(A,I0)') "[ERROR] initial flow failed. status=", flow_status
      error stop 1
   end if

   momentum = 0.0_dp
   call reset_reverse_gate_replay_status_counts()
   step_status = -999
   call rattle_step_core(x, z, 0.002_dp, final_x, final_z, jac, jacf, momentum, converged, ws, step_status)

   call check_forward_endpoint(final_x, final_z, jacf, failures)
   call check_final_momentum_tangent(momentum, jacf, tangent, tangent_component, normal_component, failures)
   call check_reverse_gate_replay(failures)
   call check_step_status(converged, step_status, failures)

   call release_rattle_step_workspace(ws)
   deallocate (seed, x, final_x)
   deallocate (momentum, tangent, tangent_component, normal_component)
   deallocate (z, final_z, jac, jacf, z_check, jac_check)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] retained-core RATTLE/RG contract failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] retained-core RATTLE/RG contract complete."

contains

   subroutine fill_seed(seed)
      real(dp), intent(out) :: seed(:)
      integer :: i

      do i = 1, size(seed)
         seed(i) = 0.12_dp + 0.04_dp*real(i - 1, dp)
      end do
   end subroutine fill_seed

   subroutine check_step_status(converged, step_status, failures)
      logical, intent(in) :: converged
      integer, intent(in) :: step_status
      integer, intent(inout) :: failures
      logical :: ok

      ok = converged .and. step_status == hmc_step_status_success
      write (*, '(A,L1,A,L1,A,I0)') "[CHECK] rattle_step_status ok=", ok, &
         " converged=", converged, " status=", step_status
      if (.not. ok) failures = failures + 1
   end subroutine check_step_status

   subroutine check_forward_endpoint(final_x, final_z, jacf, failures)
      real(dp), intent(in) :: final_x(:)
      complex(dp), intent(in) :: final_z(:), jacf(:, :)
      integer, intent(inout) :: failures
      logical :: failed, ok
      integer :: status
      real(dp) :: z_err, jac_err
      real(dp), parameter :: z_tol = 5.0e-11_dp
      real(dp), parameter :: jac_tol = 5.0e-10_dp

      status = intode_status_unknown
      call flow(final_x, z_check, jac_check, failed, status)
      z_err = maxval(abs(z_check - final_z))
      jac_err = maxval(abs(jac_check - jacf))
      ok = (.not. failed) .and. intode_status_is_strict_success(status) .and. &
           ieee_is_finite(z_err) .and. ieee_is_finite(jac_err) .and. &
           z_err <= z_tol .and. jac_err <= jac_tol
      write (*, '(A,L1,A,I0,A,ES12.4,A,ES12.4)') "[CHECK] rattle_forward_endpoint ok=", ok, &
         " status=", status, " z_err=", z_err, " jac_err=", jac_err
      if (.not. ok) failures = failures + 1
   end subroutine check_forward_endpoint

   subroutine check_final_momentum_tangent(momentum, jacf, tangent, tangent_component, normal_component, failures)
      real(dp), intent(in) :: momentum(:)
      complex(dp), intent(in) :: jacf(:, :)
      real(dp), intent(inout) :: tangent(:), tangent_component(:), normal_component(:)
      integer, intent(inout) :: failures
      logical :: failed, ok
      real(dp) :: normal_norm
      real(dp), parameter :: tolerance = 5.0e-11_dp

      call decompose2(momentum, tangent, tangent_component, normal_component, jacf, failed)
      normal_norm = norm2(normal_component)
      ok = (.not. failed) .and. ieee_is_finite(normal_norm) .and. normal_norm <= tolerance
      write (*, '(A,L1,A,ES12.4,A,ES12.4)') "[CHECK] rattle_final_momentum_tangent ok=", ok, &
         " normal_norm=", normal_norm, " tol=", tolerance
      if (.not. ok) failures = failures + 1
   end subroutine check_final_momentum_tangent

   subroutine check_reverse_gate_replay(failures)
      integer, intent(inout) :: failures
      integer(int64) :: success, output_size_mismatch, momentum_size_mismatch, initial_force_failed
      integer(int64) :: constraint_failed, final_flow_failed, final_force_failed, final_projection_failed
      integer(int64) :: reverse_gate_rejected, final_flow_max_steps, final_flow_invalid, final_flow_h_min
      integer(int64) :: final_flow_non_strict_success, unknown, failure_total
      logical :: ok

      call get_reverse_gate_replay_status_counts(success, output_size_mismatch, momentum_size_mismatch, initial_force_failed, &
                                                 constraint_failed, final_flow_failed, final_force_failed, final_projection_failed, &
                                                 reverse_gate_rejected, final_flow_max_steps, final_flow_invalid, final_flow_h_min, &
                                                 final_flow_non_strict_success, unknown)
      failure_total = output_size_mismatch + momentum_size_mismatch + initial_force_failed + constraint_failed + &
                      final_flow_failed + final_force_failed + final_projection_failed + reverse_gate_rejected + &
                      final_flow_max_steps + final_flow_invalid + final_flow_h_min + final_flow_non_strict_success + unknown
      ok = success == 1_int64 .and. failure_total == 0_int64
      write (*, '(A,L1,A,I0,A,I0)') "[CHECK] reverse_gate_replay_success ok=", ok, &
         " success=", success, " failure_total=", failure_total
      if (.not. ok) failures = failures + 1
   end subroutine check_reverse_gate_replay

end program test_retained_core_rattle_rg_contract

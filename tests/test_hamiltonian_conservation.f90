program test_hamiltonian_conservation
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use param_mod
   use mt95, only: getseed, sgrnd
   use hmc, only: integrate_hmc_proposal
   use model, only: grand
   use solve_flow, only: flow
   use perf_profile, only: perf_reset, perf_report
   use constraint_solver_stats_mod, only: reset_constraint_solver_stats, report_constraint_solver_stats
   use utils, only: dp, wall_time_seconds, x_set_flow_time, x_set_seed_real
   implicit none

   integer, parameter :: max_substeps = 50
   integer, parameter :: method_count = 1
   character(len=32), parameter :: method_names(method_count) = [character(len=32) :: "rattle"]

   integer :: substep_count, n_seed, rng_seed, method_idx
   real(dp), allocatable :: x_state(:), x_state_next(:), x_seed(:)
   complex(dp), allocatable :: z_state(:), z_state_next(:)
   complex(dp), allocatable :: jac_state(:, :), jac_state_next(:, :)
   real(dp) :: h_initial, h_final
   real(dp) :: start_time, elapsed_time, eta_seconds, progress_ratio
   real(dp) :: flow_time
   real(dp) :: order_estimate(method_count)
   real(dp) :: hamiltonian_delta(method_count, max_substeps)
   logical :: flow_failed, order_unavailable(method_count), proposal_ok

   start_time = wall_time_seconds()
   call perf_reset()
   rng_seed = getseed()
   call sgrnd(rng_seed)

   call read_parameters()
   call reset_constraint_solver_stats()
   n_seed = state_seed_size_cfg()

   allocate (x_state(1 + n_seed), x_state_next(1 + n_seed), x_seed(n_seed))
   allocate (z_state(n_seed), z_state_next(n_seed))
   allocate (jac_state(n_seed, n_seed), jac_state_next(n_seed, n_seed))

   call grand(testmom)
   testmom = 1.0_dp

   flow_time = config%integrator%initial_flow_time
   x_seed = 1.0_dp
   call x_set_flow_time(x_state, flow_time)
   call x_set_seed_real(x_state, x_seed)

   write (*, '(A,I0)') "[INIT] Hamiltonian conservation test starts. n_seed=", n_seed
   write (*, '(A,F10.6)') "[INIT] Initial flow time=", flow_time

   istest = .true.

   do method_idx = 1, method_count
      call set_integrator_method(method_names(method_idx))
      call flow(x_state, z_state, jac_state, flow_failed)
      if (flow_failed) then
         write (*, '(A)') "[ERROR] Flow initialization failed."
         error stop 1
      end if

      call reset_constraint_solver_stats()
      write (*, '(A,A)') "[INIT] Running method=", trim(integrator_method)

      do substep_count = 1, max_substeps
         ckrv = .true.
         call integrate_hmc_proposal(x_state, z_state, total_step_size, substep_count, x_state_next, z_state_next, &
                                     h_initial, h_final, jac_state, jac_state_next, proposal_ok)

         if ((.not. proposal_ok) .or. (.not. ieee_is_finite(h_initial)) .or. (.not. ieee_is_finite(h_final))) then
            hamiltonian_delta(method_idx, substep_count) = -1.0_dp
            write (*, '(A,A,A,I0)') "[ERROR] Integrator failed: method=", trim(integrator_method), " substeps=", substep_count
            cycle
         end if

         hamiltonian_delta(method_idx, substep_count) = abs(h_final - h_initial)
         elapsed_time = wall_time_seconds() - start_time
         progress_ratio = real((method_idx - 1)*max_substeps + substep_count, dp)/real(method_count*max_substeps, dp)
         if (progress_ratio > 0.0_dp) then
            eta_seconds = elapsed_time*(1.0_dp/progress_ratio - 1.0_dp)
         else
            eta_seconds = 0.0_dp
         end if

         write (*, '(A,A,A,I0,A,ES12.4,A,F10.2,A)') "[PROGRESS][", trim(integrator_method), "] substeps=", substep_count, &
            " delta_H=", hamiltonian_delta(method_idx, substep_count), " eta=", eta_seconds, "s"
      end do

      call estimate_convergence_order_tail(hamiltonian_delta(method_idx, :), max_substeps, 3, &
                                           order_estimate(method_idx), order_unavailable(method_idx))
      if (order_unavailable(method_idx)) then
         write (*, '(A,A,A)') "[SUMMARY] method=", trim(integrator_method), " convergence order unavailable."
      else
         write (*, '(A,A,A,F8.4,A,I0,A,I0,A)') "[SUMMARY] method=", trim(integrator_method), &
            " estimated_order_tail=", order_estimate(method_idx), " (fit range: n=", max(3, max_substeps/2), "..", max_substeps, ")"
      end if

      call report_constraint_solver_stats("[SUMMARY] "//trim(integrator_method))
   end do

   elapsed_time = wall_time_seconds() - start_time
   write (*, '(A,F10.3,A)') "[SUMMARY] Total time elapsed=", elapsed_time, "s"

   call save_and_plot_hamiltonian_loglog(max_substeps, hamiltonian_delta, method_names)
   call perf_report()

   deallocate (x_state, x_state_next, x_seed)
   deallocate (z_state, z_state_next)
   deallocate (jac_state, jac_state_next)

contains

   subroutine save_and_plot_hamiltonian_loglog(max_entries, h_data, method_labels)
      use iso_fortran_env, only: output_unit
      integer, intent(in) :: max_entries
      real(dp), intent(in) :: h_data(method_count, max_entries)
      character(len=*), intent(in) :: method_labels(method_count)

      integer :: idx, method_idx, data_col, exit_status, env_len, env_status
      character(len=16) :: env_value
      character(len=32) :: col_text
      character(len=4096) :: plot_line
      logical :: skip_plot

      open (unit=20, file="hamiltonian_conservation.dat", status="replace", action="write")
      write (20, '(A)', advance='no') "# num_step"
      do method_idx = 1, method_count
         write (20, '(A)', advance='no') " "//trim(method_labels(method_idx))
      end do
      write (20, *)
      do idx = 1, max_entries
         write (20, '(I6)', advance='no') idx
         do method_idx = 1, method_count
            write (20, '(1X,E22.15)', advance='no') h_data(method_idx, idx)
         end do
         write (20, *)
      end do
      close (20)

      open (unit=30, file="hamiltonian_conservation_loglog.gp", status="replace", action="write")
      write (30, '(A)') "set terminal pngcairo size 1200,800 enhanced font 'Helvetica,14'"
      write (30, '(A)') "set output 'hamiltonian_conservation_loglog.png'"
      write (30, '(A)') "set logscale x"
      write (30, '(A)') "set logscale y"
      write (30, '(A)') "set xlabel 'Number of Steps'"
      write (30, '(A)') "set ylabel 'Hamiltonian |Delta H|'"
      write (30, '(A)') "set title 'Hamiltonian Conservation: RATTLE'"
      write (30, '(A)') "set grid"
      plot_line = "plot"
      do method_idx = 1, method_count
         data_col = method_idx + 1
         write (col_text, '(I0)') data_col
         if (method_idx == 1) then
            plot_line = trim(plot_line)//" 'hamiltonian_conservation.dat' using 1:"//trim(col_text)// &
                        " with linespoints lw 2 title '"//trim(method_labels(method_idx))//"'"
         else
            plot_line = trim(plot_line)//", 'hamiltonian_conservation.dat' using 1:"//trim(col_text)// &
                        " with linespoints lw 2 title '"//trim(method_labels(method_idx))//"'"
         end if
      end do
      write (30, '(A)') trim(plot_line)
      write (30, '(A)') "unset output"
      close (30)

      skip_plot = .false.
      env_value = ""
      call get_environment_variable("HMC_SKIP_PLOT", env_value, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         if (trim(adjustl(env_value(1:env_len))) /= "0") skip_plot = .true.
      end if
      if (skip_plot) then
         write (*, '(A)') "[SUMMARY] HMC_SKIP_PLOT is set; skipped gnuplot rendering."
         return
      end if

      write (*, '(A)') "[INIT] Generating Hamiltonian conservation plot..."
      call execute_command_line("gnuplot hamiltonian_conservation_loglog.gp", exitstat=exit_status)

      if (exit_status /= 0) then
         write (output_unit, '(A,I0)') "[ERROR] gnuplot exited with status ", exit_status
      else
         write (output_unit, '(A)') "[DONE] Plot written to hamiltonian_conservation_loglog.png"
      end if
   end subroutine save_and_plot_hamiltonian_loglog

   subroutine estimate_convergence_order_tail(h_data, max_entries, min_step, order_estimate, unavailable)
      integer, intent(in) :: max_entries, min_step
      real(dp), intent(in) :: h_data(max_entries)
      real(dp), intent(out) :: order_estimate
      logical, intent(out) :: unavailable

      integer :: idx, n_fit, fit_start
      real(dp) :: x, y, sum_x, sum_y, sum_xx, sum_xy, denom

      fit_start = max(min_step, max_entries/2)
      sum_x = 0.0_dp
      sum_y = 0.0_dp
      sum_xx = 0.0_dp
      sum_xy = 0.0_dp
      n_fit = 0

      do idx = fit_start, max_entries
         if (h_data(idx) <= 0.0_dp) cycle
         x = log(real(idx, dp))
         y = log(h_data(idx))
         sum_x = sum_x + x
         sum_y = sum_y + y
         sum_xx = sum_xx + x*x
         sum_xy = sum_xy + x*y
         n_fit = n_fit + 1
      end do

      if (n_fit < 2) then
         unavailable = .true.
         order_estimate = 0.0_dp
         return
      end if

      denom = real(n_fit, dp)*sum_xx - sum_x*sum_x
      if (abs(denom) <= tiny(1.0_dp)) then
         unavailable = .true.
         order_estimate = 0.0_dp
         return
      end if

      order_estimate = -(real(n_fit, dp)*sum_xy - sum_x*sum_y)/denom
      unavailable = .false.
   end subroutine estimate_convergence_order_tail

end program test_hamiltonian_conservation

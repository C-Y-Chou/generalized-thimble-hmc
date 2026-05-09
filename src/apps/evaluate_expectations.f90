program evaluate_expectations_app
   use param_mod, only: alpha, beta, n_size, phi_history_file, read_parameters, tra2, z_history_file
   use utils, only: dp
   implicit none

   complex(dp), allocatable :: z_history(:, :), phi_history(:)
   complex(dp), allocatable :: observable_series(:), numerator_samples(:)
   integer, allocatable :: jk_bin_sizes(:)
   real(dp), allocatable :: jk_err_re(:), jk_err_im(:), jk_err_abs(:)
   real(dp), allocatable :: jk_half1_re(:), jk_half1_im(:), jk_half1_abs(:)
   real(dp), allocatable :: jk_half2_re(:), jk_half2_im(:), jk_half2_abs(:)
   complex(dp) :: denominator_sum, ratio_mean
   real(dp) :: t_start, t_now
   real(dp) :: jk_plateau_re, jk_plateau_im, jk_onset_re, jk_onset_im
   real(dp) :: jk_onset_re_low, jk_onset_re_high, jk_onset_im_low, jk_onset_im_high
   real(dp) :: jk_tau_var_re, jk_tau_var_im
   real(dp) :: jk_tau_onset_re, jk_tau_onset_im
   real(dp) :: jk_tau_eff_re, jk_tau_eff_im
   real(dp) :: jk_split_plateau_rel_re, jk_split_plateau_rel_im
   real(dp) :: jk_split_onset_ratio_re, jk_split_onset_ratio_im
   real(dp) :: half1_plateau_re, half1_plateau_im, half2_plateau_re, half2_plateau_im
   real(dp) :: half1_onset_re, half1_onset_im, half2_onset_re, half2_onset_im
   real(dp) :: half_onset_low, half_onset_high
   real(dp) :: half_tau_var, half_tau_onset, half_tau_eff
   real(dp) :: direct_tau_ips_re, direct_tau_ips_im
   real(dp) :: direct_tau_ics_re, direct_tau_ics_im
   real(dp) :: direct_tau_obm_re, direct_tau_obm_im
   real(dp) :: direct_tau_robust_re, direct_tau_robust_im
   real(dp) :: direct_tau_ratio_re, direct_tau_ratio_im
   real(dp) :: tau_upper_re, tau_upper_im
   real(dp) :: obs_rhat_re, obs_rhat_im
   real(dp) :: obs_ess_bulk_re, obs_ess_bulk_im
   real(dp) :: obs_ess_tail_re, obs_ess_tail_im
   real(dp) :: obs_mcse_mean_re, obs_mcse_mean_im
   real(dp) :: phase_abs_sum, phase_coherence, phase_eff_n, phase_min_effective
   real(dp), allocatable :: direct_series_re(:), direct_series_im(:)
   complex(dp) :: normalized_value
   integer :: sample_idx, n_samples, io_status, n_half, n_half2
   integer :: jk_min_blocks_reliable, jk_min_bin_size_reliable
   integer :: env_status, env_len, required_half_samples
   integer :: direct_n_use, direct_start_idx, direct_lag_cap
   integer :: direct_lag_used_ips_re, direct_lag_used_ips_im
   integer :: direct_lag_used_ics_re, direct_lag_used_ics_im
   integer :: n_samples_z, n_samples_phi
   integer :: jk_n_bins
   integer :: jk_plot_exit_status, jk_plot_cmd_status
   integer :: mkdir_exit_status, mkdir_cmd_status
   integer :: stability_level_re, stability_level_im, stability_level_all
   logical :: jk_split_ok_re, jk_split_ok_im
   character(len=16) :: stability_re_label, stability_im_label, stability_all_label
   character(len=16) :: diag_observable_name
   character(len=64) :: env_value
   character(len=1024) :: multichain_run_dir
   character(len=1024) :: analysis_dir
   character(len=1024) :: virial_file
   character(len=1024) :: jackknife_file, jackknife_plot_script_file, jackknife_plot_image_file, jackknife_plot_cmd
   character(len=1024) :: jackknife_meta_file
   logical :: multichain_mode

   call read_parameters()
   multichain_run_dir = ""
   call get_environment_variable("EVAL_MULTICHAIN_RUN_DIR", multichain_run_dir, length=env_len, status=env_status)
   multichain_mode = (env_status == 0 .and. env_len > 0)
   if (multichain_mode) then
      multichain_run_dir = trim(multichain_run_dir(1:env_len))
      write (*, '(A,1X,A)') "[INIT] Evaluating multichain run:", trim(multichain_run_dir)
      call evaluate_multichain_run(trim(multichain_run_dir))
      stop
   end if
   write (*, '(A)') "[INIT] Evaluating jackknife analysis from saved chain history"

   call read_z_history_matrix(z_history_file, z_history, n_samples_z, io_status)
   if (io_status /= 0) then
      write (*, '(A,1X,A)') "[ERROR] Failed to read z-history:", trim(z_history_file)
      error stop 1
   end if

   call read_phi_history_vector(phi_history_file, phi_history, n_samples_phi, io_status)
   if (io_status /= 0) then
      write (*, '(A,1X,A)') "[ERROR] Failed to read phi-history:", trim(phi_history_file)
      error stop 1
   end if

   n_samples = min(n_samples_z, n_samples_phi)
   if (n_samples < 1) then
      write (*, '(A)') "[ERROR] No shared samples available in z/phi histories."
      error stop 1
   end if

   if (n_samples_z /= n_samples_phi) then
      write (*, '(A,I0,A,I0,A,I0,A)') "[WARN] Sample count mismatch: z=", n_samples_z, " phi=", n_samples_phi, &
         ". Using shortest history with samples=", n_samples, "."
   end if

   write (*, '(A,I0)') "[INFO] Loaded samples=", n_samples
   jk_min_blocks_reliable = 512
   jk_min_bin_size_reliable = 2
   phase_min_effective = 50.0_dp

   env_value = ""
   call get_environment_variable("EVAL_JK_MIN_BLOCKS", env_value, length=env_len, status=env_status)
   if (env_status == 0 .and. env_len > 0) then
      read (env_value(1:env_len), *, iostat=io_status) jk_min_blocks_reliable
      if (io_status /= 0 .or. jk_min_blocks_reliable < 2) then
         write (*, '(A)') "[WARN] Invalid EVAL_JK_MIN_BLOCKS value. Using default 512."
         jk_min_blocks_reliable = 512
      end if
   end if

   env_value = ""
   call get_environment_variable("EVAL_JK_MIN_BIN", env_value, length=env_len, status=env_status)
   if (env_status == 0 .and. env_len > 0) then
      read (env_value(1:env_len), *, iostat=io_status) jk_min_bin_size_reliable
      if (io_status /= 0 .or. jk_min_bin_size_reliable < 1) then
         write (*, '(A)') "[WARN] Invalid EVAL_JK_MIN_BIN value. Using default 2."
         jk_min_bin_size_reliable = 2
      end if
   end if
   write (*, '(A,I0,A,I0)') "[CONFIG] Jackknife reliability filter: n_blocks>=", jk_min_blocks_reliable, &
      " bin>=", jk_min_bin_size_reliable
   env_value = ""
   call get_environment_variable("EVAL_PHASE_MIN_EFFECTIVE", env_value, length=env_len, status=env_status)
   if (env_status == 0 .and. env_len > 0) then
      read (env_value(1:env_len), *, iostat=io_status) phase_min_effective
      if (io_status /= 0 .or. phase_min_effective < 1.0_dp) then
         write (*, '(A)') "[WARN] Invalid EVAL_PHASE_MIN_EFFECTIVE value. Using default 50."
         phase_min_effective = 50.0_dp
      end if
   end if

   allocate (observable_series(n_samples), numerator_samples(n_samples))

   call cpu_time(t_start)
   !$omp parallel do default(shared) private(sample_idx)
   do sample_idx = 1, n_samples
      observable_series(sample_idx) = observable_from_state(z_history(:, sample_idx))
   end do
   !$omp end parallel do
   call cpu_time(t_now)
   write (*, '(A,F10.3,A)') "[TIMING] Observable series build took ", t_now - t_start, " s"
   if (tra2) then
      diag_observable_name = "tra2"
   else
      diag_observable_name = "virial"
   end if

   numerator_samples = observable_series*phi_history(1:n_samples)
   denominator_sum = sum(phi_history(1:n_samples))
   if (abs(denominator_sum) <= tiny(1.0_dp)) then
      write (*, '(A)') "[ERROR] Sum of phase factors is numerically zero."
      error stop 1
   end if
   phase_abs_sum = sum(abs(phi_history(1:n_samples)))
   if (phase_abs_sum > tiny(1.0_dp)) then
      phase_coherence = abs(denominator_sum)/phase_abs_sum
   else
      phase_coherence = 0.0_dp
   end if
   phase_eff_n = real(n_samples, dp)*phase_coherence*phase_coherence
   ratio_mean = sum(numerator_samples)/denominator_sum

   direct_n_use = min(n_samples, 200000)
   direct_lag_cap = 512
   env_value = ""
   call get_environment_variable("EVAL_DIRECT_TAU_SAMPLES_CAP", env_value, length=env_len, status=env_status)
   if (env_status == 0 .and. env_len > 0) then
      read (env_value(1:env_len), *, iostat=io_status) direct_n_use
      if (io_status /= 0 .or. direct_n_use < 4) then
         write (*, '(A)') "[WARN] Invalid EVAL_DIRECT_TAU_SAMPLES_CAP value. Using default 200000."
         direct_n_use = min(n_samples, 200000)
      else
         direct_n_use = min(n_samples, direct_n_use)
      end if
   end if
   env_value = ""
   call get_environment_variable("EVAL_DIRECT_TAU_MAX_LAG", env_value, length=env_len, status=env_status)
   if (env_status == 0 .and. env_len > 0) then
      read (env_value(1:env_len), *, iostat=io_status) direct_lag_cap
      if (io_status /= 0 .or. direct_lag_cap < 1) then
         write (*, '(A)') "[WARN] Invalid EVAL_DIRECT_TAU_MAX_LAG value. Using default 512."
         direct_lag_cap = 512
      end if
   end if
   call compute_observable_mcmc_diagnostics(observable_series, direct_lag_cap, &
                                            obs_rhat_re, obs_rhat_im, &
                                            obs_ess_bulk_re, obs_ess_bulk_im, &
                                            obs_ess_tail_re, obs_ess_tail_im, &
                                            obs_mcse_mean_re, obs_mcse_mean_im)
   write (*, '(A,A)') "[CONFIG] diagnostics_observable=", trim(diag_observable_name)
   direct_start_idx = n_samples - direct_n_use + 1
   allocate (direct_series_re(direct_n_use), direct_series_im(direct_n_use))
   do sample_idx = 1, direct_n_use
      normalized_value = numerator_samples(direct_start_idx + sample_idx - 1)/denominator_sum
      direct_series_re(sample_idx) = real(normalized_value, dp)
      direct_series_im(sample_idx) = aimag(normalized_value)
   end do
   call estimate_tau_int_ips_real(direct_series_re, direct_lag_cap, direct_tau_ips_re, direct_lag_used_ips_re)
   call estimate_tau_int_ips_real(direct_series_im, direct_lag_cap, direct_tau_ips_im, direct_lag_used_ips_im)
   call estimate_tau_int_ics_real(direct_series_re, direct_lag_cap, direct_tau_ics_re, direct_lag_used_ics_re)
   call estimate_tau_int_ics_real(direct_series_im, direct_lag_cap, direct_tau_ics_im, direct_lag_used_ics_im)
   call estimate_tau_int_obm_real(direct_series_re, direct_lag_cap, direct_tau_obm_re)
   call estimate_tau_int_obm_real(direct_series_im, direct_lag_cap, direct_tau_obm_im)
   direct_tau_robust_re = max(direct_tau_ips_re, max(direct_tau_ics_re, direct_tau_obm_re))
   direct_tau_robust_im = max(direct_tau_ips_im, max(direct_tau_ics_im, direct_tau_obm_im))
   deallocate (direct_series_re, direct_series_im)
      analysis_dir = directory_from_path(phi_history_file)
      call ensure_directory_exists(trim(analysis_dir), mkdir_cmd_status, mkdir_exit_status)
      if (mkdir_cmd_status /= 0 .or. mkdir_exit_status /= 0) then
         write (*, '(A,1X,A)') "[WARN] Failed to create analysis output dir:", trim(analysis_dir)
      end if
      virial_file = join_path(trim(analysis_dir), "virial.dat")
      call save_complex_series(trim(virial_file), numerator_samples)
      jackknife_file = join_path(trim(analysis_dir), "jackknife_error.dat")
      jackknife_meta_file = join_path(trim(analysis_dir), "jackknife_meta.dat")
      jackknife_plot_script_file = join_path(trim(analysis_dir), "jackknife_error_plot.gp")
      jackknife_plot_image_file = join_path(trim(analysis_dir), "jackknife_error.png")
   call build_jackknife_bin_sizes(n_samples, jk_bin_sizes)
   jk_n_bins = size(jk_bin_sizes)
   if (jk_n_bins >= 1) then
      allocate (jk_err_re(jk_n_bins), jk_err_im(jk_n_bins), jk_err_abs(jk_n_bins))
      write (*, '(A,I0,A)') "[PROGRESS] Computing binned jackknife error curve with ", jk_n_bins, " bin sizes."
      call cpu_time(t_start)
      call compute_jackknife_error_curve(numerator_samples, phi_history(1:n_samples), jk_bin_sizes, &
                                         jk_err_re, jk_err_im, jk_err_abs)
      call cpu_time(t_now)
      write (*, '(A,F10.3,A)') "[TIMING] Jackknife curve build took ", t_now - t_start, " s"

      call estimate_jackknife_plateau_and_tau(jk_err_re, jk_err_im, jk_bin_sizes, n_samples, &
                                              jk_min_blocks_reliable, jk_min_bin_size_reliable, &
                                              jk_plateau_re, jk_plateau_im, jk_onset_re, jk_onset_im, &
                                              jk_onset_re_low, jk_onset_re_high, jk_onset_im_low, jk_onset_im_high, &
                                              jk_tau_var_re, jk_tau_var_im, jk_tau_onset_re, jk_tau_onset_im, &
                                              jk_tau_eff_re, jk_tau_eff_im)
      direct_tau_ratio_re = direct_tau_robust_re/max(tiny(1.0_dp), jk_tau_eff_re)
      direct_tau_ratio_im = direct_tau_robust_im/max(tiny(1.0_dp), jk_tau_eff_im)
      tau_upper_re = max(jk_tau_eff_re, direct_tau_robust_re)
      tau_upper_im = max(jk_tau_eff_im, direct_tau_robust_im)

      n_half = n_samples/2
      n_half2 = n_samples - n_half
      jk_split_plateau_rel_re = -1.0_dp
      jk_split_plateau_rel_im = -1.0_dp
      jk_split_onset_ratio_re = -1.0_dp
      jk_split_onset_ratio_im = -1.0_dp
      jk_split_ok_re = .false.
      jk_split_ok_im = .false.
      stability_level_re = 1
      stability_level_im = 1
      stability_level_all = 1
      required_half_samples = jk_min_blocks_reliable*max(1, jk_min_bin_size_reliable)
      if (n_half >= required_half_samples .and. n_half2 >= required_half_samples) then
         allocate (jk_half1_re(jk_n_bins), jk_half1_im(jk_n_bins), jk_half1_abs(jk_n_bins))
         allocate (jk_half2_re(jk_n_bins), jk_half2_im(jk_n_bins), jk_half2_abs(jk_n_bins))
         call compute_jackknife_error_curve(numerator_samples(1:n_half), phi_history(1:n_half), jk_bin_sizes, &
                                            jk_half1_re, jk_half1_im, jk_half1_abs)
         call compute_jackknife_error_curve(numerator_samples(n_half + 1:n_samples), phi_history(n_half + 1:n_samples), &
                                            jk_bin_sizes, jk_half2_re, jk_half2_im, jk_half2_abs)

         call analyze_jackknife_component(jk_half1_re, jk_bin_sizes, n_half, jk_min_blocks_reliable, jk_min_bin_size_reliable, &
                                          half1_plateau_re, half1_onset_re, half_onset_low, half_onset_high, &
                                          half_tau_var, half_tau_onset, half_tau_eff)
         call analyze_jackknife_component(jk_half2_re, jk_bin_sizes, n_half2, jk_min_blocks_reliable, jk_min_bin_size_reliable, &
                                          half2_plateau_re, half2_onset_re, half_onset_low, half_onset_high, &
                                          half_tau_var, half_tau_onset, half_tau_eff)
         call analyze_jackknife_component(jk_half1_im, jk_bin_sizes, n_half, jk_min_blocks_reliable, jk_min_bin_size_reliable, &
                                          half1_plateau_im, half1_onset_im, half_onset_low, half_onset_high, &
                                          half_tau_var, half_tau_onset, half_tau_eff)
         call analyze_jackknife_component(jk_half2_im, jk_bin_sizes, n_half2, jk_min_blocks_reliable, jk_min_bin_size_reliable, &
                                          half2_plateau_im, half2_onset_im, half_onset_low, half_onset_high, &
                                          half_tau_var, half_tau_onset, half_tau_eff)

         jk_split_plateau_rel_re = abs(half1_plateau_re - half2_plateau_re)/ &
                                   max(tiny(1.0_dp), 0.5_dp*(abs(half1_plateau_re) + abs(half2_plateau_re)))
         jk_split_plateau_rel_im = abs(half1_plateau_im - half2_plateau_im)/ &
                                   max(tiny(1.0_dp), 0.5_dp*(abs(half1_plateau_im) + abs(half2_plateau_im)))
         if (half1_onset_re > 0.0_dp .and. half2_onset_re > 0.0_dp) then
            jk_split_onset_ratio_re = max(half1_onset_re, half2_onset_re)/min(half1_onset_re, half2_onset_re)
         end if
         if (half1_onset_im > 0.0_dp .and. half2_onset_im > 0.0_dp) then
            jk_split_onset_ratio_im = max(half1_onset_im, half2_onset_im)/min(half1_onset_im, half2_onset_im)
         end if
         jk_split_ok_re = (jk_split_plateau_rel_re <= 0.20_dp) .and. &
                          (jk_split_onset_ratio_re < 0.0_dp .or. jk_split_onset_ratio_re <= 2.0_dp)
         jk_split_ok_im = (jk_split_plateau_rel_im <= 0.20_dp) .and. &
                          (jk_split_onset_ratio_im < 0.0_dp .or. jk_split_onset_ratio_im <= 2.0_dp)
         if (jk_split_ok_re) then
            stability_level_re = 2
         else
            stability_level_re = 0
         end if
         if (jk_split_ok_im) then
            stability_level_im = 2
         else
            stability_level_im = 0
         end if
         deallocate (jk_half1_re, jk_half1_im, jk_half1_abs, jk_half2_re, jk_half2_im, jk_half2_abs)
      else
         write (*, '(A,I0,A)') "[WARN] Split-half jackknife consistency skipped: each half needs at least ", &
            required_half_samples, " samples for the active reliability filter."
      end if
      if (jk_onset_re <= 0.0_dp) stability_level_re = min(stability_level_re, 1)
      if (jk_onset_im <= 0.0_dp) stability_level_im = min(stability_level_im, 1)
      if (phase_eff_n < phase_min_effective) then
         stability_level_re = min(stability_level_re, 1)
         stability_level_im = min(stability_level_im, 1)
      end if
      stability_level_all = min(stability_level_re, stability_level_im)
      stability_re_label = stability_label_from_level(stability_level_re)
      stability_im_label = stability_label_from_level(stability_level_im)
      stability_all_label = stability_label_from_level(stability_level_all)

      write (*, '(A)') "[RESULT] ------------------------------"
      write (*, '(A,2(1X,ES14.6))') "[RESULT] mean (Re, Im)=", real(ratio_mean, dp), aimag(ratio_mean)
      write (*, '(A,2(1X,ES14.6))') "[RESULT] error_bar (Re, Im)=", jk_plateau_re, jk_plateau_im
      write (*, '(A,2(1X,F10.3))') "[RESULT] tau_int_jackknife (Re, Im)=", jk_tau_eff_re, jk_tau_eff_im
      write (*, '(A,2(1X,F10.3))') "[RESULT] tau_int_ips (Re, Im)=", direct_tau_ips_re, direct_tau_ips_im
      write (*, '(A,2(1X,F10.3))') "[RESULT] tau_int_ics (Re, Im)=", direct_tau_ics_re, direct_tau_ics_im
      write (*, '(A,2(1X,F10.3))') "[RESULT] tau_int_obm (Re, Im)=", direct_tau_obm_re, direct_tau_obm_im
      write (*, '(A,2(1X,F10.3))') "[RESULT] tau_int_direct_robust (Re, Im)=", direct_tau_robust_re, direct_tau_robust_im
      write (*, '(A,2(1X,F10.3))') "[RESULT] tau_int_upper=max(jackknife,direct_robust) (Re, Im)=", tau_upper_re, tau_upper_im
      write (*, '(A,2(1X,F10.4))') "[RESULT] split_rhat_obs (Re, Im)=", obs_rhat_re, obs_rhat_im
      write (*, '(A,2(1X,F12.2))') "[RESULT] ess_bulk_obs (Re, Im)=", obs_ess_bulk_re, obs_ess_bulk_im
      write (*, '(A,2(1X,F12.2))') "[RESULT] ess_tail_obs (Re, Im)=", obs_ess_tail_re, obs_ess_tail_im
      write (*, '(A,2(1X,ES14.6))') "[RESULT] mcse_mean_obs (Re, Im)=", obs_mcse_mean_re, obs_mcse_mean_im
      write (*, '(A,1X,A,2X,A,1X,A)') "[RESULT] chain_stability=", "Re="//trim(stability_re_label), &
         "Im="//trim(stability_im_label), "Overall="//trim(stability_all_label)
      write (*, '(A)') "[RESULT] ------------------------------"

      call save_jackknife_curve(trim(jackknife_file), n_samples, jk_bin_sizes, jk_err_re, jk_err_im, jk_err_abs)
      call save_jackknife_metadata(trim(jackknife_meta_file), n_samples, jk_min_blocks_reliable, jk_min_bin_size_reliable, &
                                   jk_plateau_re, jk_plateau_im, &
                                   jk_onset_re, jk_onset_im, jk_onset_re_low, jk_onset_re_high, &
                                   jk_onset_im_low, jk_onset_im_high, jk_tau_var_re, jk_tau_var_im, &
                                   jk_tau_onset_re, jk_tau_onset_im, jk_tau_eff_re, jk_tau_eff_im, &
                                   direct_tau_ips_re, direct_tau_ips_im, direct_tau_ics_re, direct_tau_ics_im, &
                                   direct_tau_obm_re, direct_tau_obm_im, direct_tau_robust_re, direct_tau_robust_im, &
                                   direct_tau_ratio_re, direct_tau_ratio_im, tau_upper_re, tau_upper_im, &
                                   phase_coherence, phase_eff_n, phase_min_effective, &
                                   jk_split_plateau_rel_re, jk_split_plateau_rel_im, &
                                   jk_split_onset_ratio_re, jk_split_onset_ratio_im, jk_split_ok_re, jk_split_ok_im, &
                                   diag_observable_name, obs_rhat_re, obs_rhat_im, obs_ess_bulk_re, obs_ess_bulk_im, &
                                   obs_ess_tail_re, obs_ess_tail_im, obs_mcse_mean_re, obs_mcse_mean_im)
      call write_jackknife_plot_script(trim(jackknife_plot_script_file), trim(jackknife_file), &
                                       trim(jackknife_plot_image_file), jk_plateau_re, jk_plateau_im, jk_onset_re, jk_onset_im, &
                                       jk_onset_re_low, jk_onset_re_high, jk_onset_im_low, jk_onset_im_high, &
                                       jk_tau_eff_re, jk_tau_eff_im, jk_min_blocks_reliable, jk_min_bin_size_reliable)

      write (*, '(A,1X,A)') "[PROGRESS] Rendering jackknife error plot:", trim(jackknife_plot_image_file)
      call cpu_time(t_start)
      jackknife_plot_cmd = "gnuplot "//trim(jackknife_plot_script_file)
      call execute_command_line(trim(jackknife_plot_cmd), exitstat=jk_plot_exit_status, cmdstat=jk_plot_cmd_status)
      call cpu_time(t_now)
      write (*, '(A,F10.3,A)') "[TIMING] Jackknife gnuplot render took ", t_now - t_start, " s"
      if (jk_plot_cmd_status /= 0) then
         write (*, '(A,I0,A)') "[WARN] Failed to invoke jackknife gnuplot (cmdstat=", jk_plot_cmd_status, ")."
      else if (jk_plot_exit_status /= 0) then
         write (*, '(A,I0)') "[WARN] jackknife gnuplot exited with status ", jk_plot_exit_status
      end if

      deallocate (jk_err_re, jk_err_im, jk_err_abs, jk_bin_sizes)
   else
      write (*, '(A)') "[WARN] Skipping jackknife plot: insufficient samples."
   end if

   write (*, '(A,I0,A,A)') "[DONE] Jackknife analysis complete. Samples=", n_samples, &
      " output_dir=", trim(analysis_dir)

contains

   function directory_from_path(path) result(dir)
      character(len=*), intent(in) :: path
      character(len=1024) :: dir
      integer :: idx, n_chars

      dir = "."
      n_chars = len_trim(path)
      do idx = n_chars, 1, -1
         if (path(idx:idx) == "/") then
            if (idx == 1) then
               dir = "/"
            else
               dir = trim(path(1:idx - 1))
            end if
            return
         end if
      end do
   end function directory_from_path

   function join_path(dir, leaf) result(path)
      character(len=*), intent(in) :: dir, leaf
      character(len=1024) :: path
      integer :: n_dir

      n_dir = len_trim(dir)
      if (n_dir <= 0 .or. trim(dir) == ".") then
         path = trim(leaf)
      else if (dir(n_dir:n_dir) == "/") then
         path = trim(dir)//trim(leaf)
      else
         path = trim(dir)//"/"//trim(leaf)
      end if
   end function join_path

   character(len=16) function stability_label_from_level(level) result(label)
      integer, intent(in) :: level

      select case (level)
      case (2)
         label = "STABLE"
      case (1)
         label = "MARGINAL"
      case default
         label = "UNSTABLE"
      end select
   end function stability_label_from_level

   subroutine ensure_directory_exists(dir, cmd_status, exit_status)
      character(len=*), intent(in) :: dir
      integer, intent(out) :: cmd_status, exit_status
      character(len=1200) :: mkdir_cmd

      if (len_trim(dir) <= 0 .or. trim(dir) == ".") then
         cmd_status = 0
         exit_status = 0
         return
      end if

      mkdir_cmd = "mkdir -p "//trim(dir)
      call execute_command_line(trim(mkdir_cmd), exitstat=exit_status, cmdstat=cmd_status)
   end subroutine ensure_directory_exists

   subroutine evaluate_multichain_run(run_dir)
      character(len=*), intent(in) :: run_dir

      integer, parameter :: path_len = 1024
      character(len=path_len), allocatable :: z_paths(:), phi_paths(:)
      character(len=path_len) :: meta_file, obs_name
      complex(dp), allocatable :: z_chain(:, :), phi_chain(:)
      complex(dp), allocatable :: num_o_tail(:, :), num_tra2_tail(:, :)
      complex(dp), allocatable :: weighted_o_tail(:, :), weighted_tra2_tail(:, :)
      complex(dp), allocatable :: num_o_all(:), num_tra2_all(:), phi_all(:)
      complex(dp), allocatable :: sum_num_o_chain(:), sum_num_tra2_chain(:), sum_phi_chain(:)
      integer, allocatable :: chain_sample_counts(:)
      integer :: io_status, n_chains, chain_idx
      integer :: n_samples_z, n_samples_phi, n_samples_chain, n_samples_min, n_total_samples
      integer :: n_use, tail_start, tail_idx, sample_idx, sample_offset
      integer :: env_status_local, env_len_local, diag_window_cap, diag_max_lag
      character(len=64) :: env_value_local
      complex(dp) :: sum_num_o_total, sum_num_tra2_total, sum_phi_total
      complex(dp) :: mean_o, mean_tra2, obs_o, obs_tra2
      real(dp) :: err_o_re, err_o_im, err_tra2_re, err_tra2_im
      real(dp) :: err_o_strat_re, err_o_strat_im, err_tra2_strat_re, err_tra2_strat_im
      real(dp) :: err_o_robust_re, err_o_robust_im, err_tra2_robust_re, err_tra2_robust_im
      logical :: err_o_ok, err_tra2_ok, err_o_strat_ok, err_tra2_strat_ok, err_o_robust_ok, err_tra2_robust_ok
      real(dp) :: phase_abs_sum_total, phase_coherence, phase_eff_n
      real(dp) :: o_rhat_re, o_rhat_im, o_ess_bulk_re, o_ess_bulk_im
      real(dp) :: o_ess_tail_re, o_ess_tail_im, o_mcse_re, o_mcse_im
      real(dp) :: tra2_rhat_re, tra2_rhat_im, tra2_ess_bulk_re, tra2_ess_bulk_im
      real(dp) :: tra2_ess_tail_re, tra2_ess_tail_im, tra2_mcse_re, tra2_mcse_im
      integer, allocatable :: jk_bin_sizes_local(:)
      real(dp), allocatable :: jk_err_re_local(:), jk_err_im_local(:), jk_err_abs_local(:)
      integer, allocatable :: jk_n_blocks_local(:)
      integer :: jk_n_bins_local, jk_min_blocks_local, jk_min_bin_local
      real(dp) :: jk_plateau_re_local, jk_plateau_im_local
      real(dp) :: jk_onset_re_local, jk_onset_im_local
      real(dp) :: jk_onset_re_low_local, jk_onset_re_high_local
      real(dp) :: jk_onset_im_low_local, jk_onset_im_high_local
      real(dp) :: jk_tau_var_re_local, jk_tau_var_im_local
      real(dp) :: jk_tau_onset_re_local, jk_tau_onset_im_local
      real(dp) :: jk_tau_eff_re_local, jk_tau_eff_im_local
      character(len=path_len) :: analysis_dir_local, virial_file_local
      character(len=path_len) :: jackknife_file_local, jackknife_plot_script_local, jackknife_plot_image_local
      character(len=1200) :: jackknife_plot_cmd_local
      integer :: mkdir_cmd_status_local, mkdir_exit_status_local, jk_plot_cmd_status_local, jk_plot_exit_status_local

      call discover_multichain_paths(run_dir, z_paths, phi_paths, n_chains, io_status)
      if (io_status /= 0 .or. n_chains < 1) then
         write (*, '(A,1X,A)') "[ERROR] No valid chain outputs found under:", trim(run_dir)
         error stop 1
      end if
      write (*, '(A,I0)') "[INFO] multichain detected: chains=", n_chains

      allocate (chain_sample_counts(n_chains), sum_num_o_chain(n_chains), sum_num_tra2_chain(n_chains), sum_phi_chain(n_chains))
      n_samples_min = huge(1)
      n_total_samples = 0
      do chain_idx = 1, n_chains
         call infer_history_sample_count(trim(z_paths(chain_idx)), trim(phi_paths(chain_idx)), n_samples_z, n_samples_phi, io_status)
         if (io_status /= 0) then
            write (*, '(A,1X,A)') "[ERROR] Failed to infer sample counts for chain path:", trim(z_paths(chain_idx))
            error stop 1
         end if
         n_samples_chain = min(n_samples_z, n_samples_phi)
         if (n_samples_chain < 1) then
            write (*, '(A,I0)') "[ERROR] Chain has no shared z/phi samples. chain_idx=", chain_idx
            error stop 1
         end if
         chain_sample_counts(chain_idx) = n_samples_chain
         n_samples_min = min(n_samples_min, n_samples_chain)
         n_total_samples = n_total_samples + n_samples_chain
      end do

      diag_window_cap = 20000
      env_value_local = ""
      call get_environment_variable("EVAL_MULTICHAIN_DIAG_WINDOW", env_value_local, length=env_len_local, status=env_status_local)
      if (env_status_local == 0 .and. env_len_local > 0) then
         read (env_value_local(1:env_len_local), *, iostat=io_status) diag_window_cap
         if (io_status /= 0) then
            write (*, '(A)') "[WARN] Invalid EVAL_MULTICHAIN_DIAG_WINDOW value. Using default 20000."
            diag_window_cap = 20000
         end if
      end if
      if (diag_window_cap <= 0) then
         n_use = n_samples_min
      else
         n_use = min(n_samples_min, diag_window_cap)
      end if
      if (n_use < 4) then
         write (*, '(A,I0)') "[ERROR] Multichain diagnostics need >=4 tail samples per chain; got n_use=", n_use
         error stop 1
      end if

      diag_max_lag = 512
      env_value_local = ""
      call get_environment_variable("EVAL_DIRECT_TAU_MAX_LAG", env_value_local, length=env_len_local, status=env_status_local)
      if (env_status_local == 0 .and. env_len_local > 0) then
         read (env_value_local(1:env_len_local), *, iostat=io_status) diag_max_lag
         if (io_status /= 0 .or. diag_max_lag < 1) then
            write (*, '(A)') "[WARN] Invalid EVAL_DIRECT_TAU_MAX_LAG value. Using default 512."
            diag_max_lag = 512
         end if
      end if

      allocate (num_o_tail(n_chains, n_use), num_tra2_tail(n_chains, n_use))
      allocate (num_o_all(n_total_samples), num_tra2_all(n_total_samples), phi_all(n_total_samples))
      sum_num_o_chain = cmplx(0.0_dp, 0.0_dp, dp)
      sum_num_tra2_chain = cmplx(0.0_dp, 0.0_dp, dp)
      sum_phi_chain = cmplx(0.0_dp, 0.0_dp, dp)
      phase_abs_sum_total = 0.0_dp
      sample_offset = 0

      do chain_idx = 1, n_chains
         call read_z_history_matrix(trim(z_paths(chain_idx)), z_chain, n_samples_z, io_status)
         if (io_status /= 0) then
            write (*, '(A,I0,A,1X,A)') "[ERROR] Failed to load z-history for chain ", chain_idx, ":", trim(z_paths(chain_idx))
            error stop 1
         end if
         call read_phi_history_vector(trim(phi_paths(chain_idx)), phi_chain, n_samples_phi, io_status)
         if (io_status /= 0) then
            write (*, '(A,I0,A,1X,A)') "[ERROR] Failed to load phi-history for chain ", chain_idx, ":", trim(phi_paths(chain_idx))
            error stop 1
         end if

         n_samples_chain = min(min(n_samples_z, n_samples_phi), chain_sample_counts(chain_idx))
         if (n_samples_z /= n_samples_phi) then
            write (*, '(A,I0,A,I0,A,I0,A,I0,A)') "[WARN] chain ", chain_idx, " sample mismatch: z=", n_samples_z, &
               " phi=", n_samples_phi, ". using=", n_samples_chain, "."
         end if
         if (n_samples_chain < n_use) then
            write (*, '(A,I0,A)') "[ERROR] chain has fewer samples than diagnostic window. chain=", chain_idx, "."
            error stop 1
         end if

         tail_start = n_samples_chain - n_use + 1
         tail_idx = 0
         do sample_idx = 1, n_samples_chain
            call calculate_virial_observable(z_chain(:, sample_idx), obs_o)
            call calculate_a2_observable(z_chain(:, sample_idx), obs_tra2)
            sum_num_o_chain(chain_idx) = sum_num_o_chain(chain_idx) + obs_o*phi_chain(sample_idx)
            sum_num_tra2_chain(chain_idx) = sum_num_tra2_chain(chain_idx) + obs_tra2*phi_chain(sample_idx)
            sum_phi_chain(chain_idx) = sum_phi_chain(chain_idx) + phi_chain(sample_idx)
            phase_abs_sum_total = phase_abs_sum_total + abs(phi_chain(sample_idx))
            sample_offset = sample_offset + 1
            num_o_all(sample_offset) = obs_o*phi_chain(sample_idx)
            num_tra2_all(sample_offset) = obs_tra2*phi_chain(sample_idx)
            phi_all(sample_offset) = phi_chain(sample_idx)
            if (sample_idx >= tail_start) then
               tail_idx = tail_idx + 1
               num_o_tail(chain_idx, tail_idx) = obs_o*phi_chain(sample_idx)
               num_tra2_tail(chain_idx, tail_idx) = obs_tra2*phi_chain(sample_idx)
            end if
         end do

         if (allocated(z_chain)) deallocate (z_chain)
         if (allocated(phi_chain)) deallocate (phi_chain)
      end do
      if (sample_offset /= n_total_samples) then
         write (*, '(A,I0,A,I0)') "[ERROR] Internal sample packing mismatch: got=", sample_offset, &
            " expected=", n_total_samples
         error stop 1
      end if

      sum_num_o_total = sum(sum_num_o_chain)
      sum_num_tra2_total = sum(sum_num_tra2_chain)
      sum_phi_total = sum(sum_phi_chain)
      if (abs(sum_phi_total) <= tiny(1.0_dp)) then
         write (*, '(A)') "[ERROR] Multichain denominator sum(phi) is numerically zero."
         error stop 1
      end if

      mean_o = sum_num_o_total/sum_phi_total
      mean_tra2 = sum_num_tra2_total/sum_phi_total
      if (phase_abs_sum_total > tiny(1.0_dp)) then
         phase_coherence = abs(sum_phi_total)/phase_abs_sum_total
      else
         phase_coherence = 0.0_dp
      end if
      phase_eff_n = real(n_total_samples, dp)*phase_coherence*phase_coherence

      call compute_chain_jackknife_ratio_error(sum_num_o_chain, sum_phi_chain, sum_num_o_total, sum_phi_total, &
                                               err_o_re, err_o_im, err_o_ok)
      call compute_chain_jackknife_ratio_error(sum_num_tra2_chain, sum_phi_chain, sum_num_tra2_total, sum_phi_total, &
                                               err_tra2_re, err_tra2_im, err_tra2_ok)
      err_o_strat_re = 0.0_dp
      err_o_strat_im = 0.0_dp
      err_tra2_strat_re = 0.0_dp
      err_tra2_strat_im = 0.0_dp
      err_o_strat_ok = .false.
      err_tra2_strat_ok = .false.

      allocate (weighted_o_tail(n_chains, n_use), weighted_tra2_tail(n_chains, n_use))
      weighted_o_tail = num_o_tail/sum_phi_total
      weighted_tra2_tail = num_tra2_tail/sum_phi_total
      call compute_multichain_observable_diagnostics(weighted_o_tail, diag_max_lag, &
                                                     o_rhat_re, o_rhat_im, o_ess_bulk_re, o_ess_bulk_im, &
                                                     o_ess_tail_re, o_ess_tail_im, o_mcse_re, o_mcse_im)
      call compute_multichain_observable_diagnostics(weighted_tra2_tail, diag_max_lag, &
                                                     tra2_rhat_re, tra2_rhat_im, tra2_ess_bulk_re, tra2_ess_bulk_im, &
                                                     tra2_ess_tail_re, tra2_ess_tail_im, tra2_mcse_re, tra2_mcse_im)

      obs_name = "virial"

      write (*, '(A)') "[RESULT] ------------------------------"
      write (*, '(A,1X,A)') "[RESULT] observable_virial=", trim(obs_name)
      write (*, '(A,I0,A,I0,A,I0)') "[RESULT] chains=", n_chains, " samples_total=", n_total_samples, " n_use_diag=", n_use
      write (*, '(A,2(1X,ES14.6))') "[RESULT] <virial> (Re, Im)=", real(mean_o, dp), aimag(mean_o)
      write (*, '(A,2(1X,ES14.6))') "[RESULT] <z> (Re, Im)=", real(mean_tra2, dp), aimag(mean_tra2)
      write (*, '(A,2(1X,ES14.6),1X,A,L1)') "[RESULT] error_chain_jk_<virial> (Re, Im)=", err_o_re, err_o_im, "valid=", err_o_ok
      write (*, '(A,2(1X,ES14.6),1X,A,L1)') "[RESULT] error_chain_jk_<z> (Re, Im)=", err_tra2_re, err_tra2_im, &
         "valid=", err_tra2_ok
      write (*, '(A)') "[RESULT] diagnostics_basis=weighted sample=(observable*phi)/sum(phi)_all_chains"
      write (*, '(A,2(1X,F10.4))') "[RESULT] split_rhat_virial (Re, Im)=", o_rhat_re, o_rhat_im
      write (*, '(A,2(1X,F12.2))') "[RESULT] ess_bulk_virial (Re, Im)=", o_ess_bulk_re, o_ess_bulk_im
      write (*, '(A,2(1X,F12.2))') "[RESULT] ess_tail_virial (Re, Im)=", o_ess_tail_re, o_ess_tail_im
      write (*, '(A,2(1X,ES14.6))') "[RESULT] mcse_mean_virial (Re, Im)=", o_mcse_re, o_mcse_im
      write (*, '(A,2(1X,F10.4))') "[RESULT] split_rhat_z (Re, Im)=", tra2_rhat_re, tra2_rhat_im
      write (*, '(A,2(1X,F12.2))') "[RESULT] ess_bulk_z (Re, Im)=", tra2_ess_bulk_re, tra2_ess_bulk_im
      write (*, '(A,2(1X,F12.2))') "[RESULT] ess_tail_z (Re, Im)=", tra2_ess_tail_re, tra2_ess_tail_im
      write (*, '(A,2(1X,ES14.6))') "[RESULT] mcse_mean_z (Re, Im)=", tra2_mcse_re, tra2_mcse_im
      write (*, '(A,2(1X,ES14.6))') "[RESULT] phase (coherence, eff_n)=", phase_coherence, phase_eff_n
      write (*, '(A)') "[RESULT] ------------------------------"

      jk_min_blocks_local = 512
      jk_min_bin_local = 2
      env_value_local = ""
      call get_environment_variable("EVAL_JK_MIN_BLOCKS", env_value_local, length=env_len_local, status=env_status_local)
      if (env_status_local == 0 .and. env_len_local > 0) then
         read (env_value_local(1:env_len_local), *, iostat=io_status) jk_min_blocks_local
         if (io_status /= 0 .or. jk_min_blocks_local < 2) then
            write (*, '(A)') "[WARN] Invalid EVAL_JK_MIN_BLOCKS value. Using default 512."
            jk_min_blocks_local = 512
         end if
      end if
      env_value_local = ""
      call get_environment_variable("EVAL_JK_MIN_BIN", env_value_local, length=env_len_local, status=env_status_local)
      if (env_status_local == 0 .and. env_len_local > 0) then
         read (env_value_local(1:env_len_local), *, iostat=io_status) jk_min_bin_local
         if (io_status /= 0 .or. jk_min_bin_local < 1) then
            write (*, '(A)') "[WARN] Invalid EVAL_JK_MIN_BIN value. Using default 2."
            jk_min_bin_local = 2
         end if
      end if

      analysis_dir_local = trim(run_dir)
      call ensure_directory_exists(trim(analysis_dir_local), mkdir_cmd_status_local, mkdir_exit_status_local)
      if (mkdir_cmd_status_local /= 0 .or. mkdir_exit_status_local /= 0) then
         write (*, '(A,1X,A)') "[WARN] Failed to create analysis output dir:", trim(analysis_dir_local)
      end if
      virial_file_local = join_path(trim(analysis_dir_local), "virial.dat")
      jackknife_file_local = join_path(trim(analysis_dir_local), "jackknife_error.dat")
      jackknife_plot_script_local = join_path(trim(analysis_dir_local), "jackknife_error_plot.gp")
      jackknife_plot_image_local = join_path(trim(analysis_dir_local), "jackknife_error.png")

      call save_complex_series(trim(virial_file_local), num_o_all)
      call build_jackknife_bin_sizes(n_total_samples, jk_bin_sizes_local)
      jk_n_bins_local = size(jk_bin_sizes_local)
      if (jk_n_bins_local >= 1) then
         allocate (jk_err_re_local(jk_n_bins_local), jk_err_im_local(jk_n_bins_local), jk_err_abs_local(jk_n_bins_local))
         allocate (jk_n_blocks_local(jk_n_bins_local))
         write (*, '(A,I0,A)') "[PROGRESS] Computing multichain binned jackknife curve (virial) with ", &
            jk_n_bins_local, " bin sizes."
         call compute_jackknife_error_curve_stratified(num_o_all, phi_all, chain_sample_counts, jk_bin_sizes_local, &
                                                       jk_err_re_local, jk_err_im_local, jk_err_abs_local, jk_n_blocks_local)

         call analyze_jackknife_component(jk_err_re_local, jk_bin_sizes_local, n_total_samples, &
                                          jk_min_blocks_local, jk_min_bin_local, &
                                          jk_plateau_re_local, jk_onset_re_local, jk_onset_re_low_local, jk_onset_re_high_local, &
                                          jk_tau_var_re_local, jk_tau_onset_re_local, jk_tau_eff_re_local, jk_n_blocks_local)
         call analyze_jackknife_component(jk_err_im_local, jk_bin_sizes_local, n_total_samples, &
                                          jk_min_blocks_local, jk_min_bin_local, &
                                          jk_plateau_im_local, jk_onset_im_local, jk_onset_im_low_local, jk_onset_im_high_local, &
                                          jk_tau_var_im_local, jk_tau_onset_im_local, jk_tau_eff_im_local, jk_n_blocks_local)
         err_o_strat_re = max(0.0_dp, jk_plateau_re_local)
         err_o_strat_im = max(0.0_dp, jk_plateau_im_local)
         err_o_strat_ok = (err_o_strat_re > tiny(1.0_dp)) .and. (err_o_strat_im > tiny(1.0_dp))

         call save_jackknife_curve(trim(jackknife_file_local), n_total_samples, jk_bin_sizes_local, &
                                   jk_err_re_local, jk_err_im_local, jk_err_abs_local, jk_n_blocks_local)
         call write_jackknife_plot_script(trim(jackknife_plot_script_local), trim(jackknife_file_local), &
                                          trim(jackknife_plot_image_local), &
                                          jk_plateau_re_local, jk_plateau_im_local, jk_onset_re_local, jk_onset_im_local, &
                                          jk_onset_re_low_local, jk_onset_re_high_local, jk_onset_im_low_local, jk_onset_im_high_local, &
                                          jk_tau_eff_re_local, jk_tau_eff_im_local, jk_min_blocks_local, jk_min_bin_local)
         write (*, '(A,1X,A)') "[PROGRESS] Rendering jackknife error plot:", trim(jackknife_plot_image_local)
         jackknife_plot_cmd_local = "gnuplot "//trim(jackknife_plot_script_local)
         call execute_command_line(trim(jackknife_plot_cmd_local), exitstat=jk_plot_exit_status_local, cmdstat=jk_plot_cmd_status_local)
         if (jk_plot_cmd_status_local /= 0) then
            write (*, '(A,I0,A)') "[WARN] Failed to invoke jackknife gnuplot (cmdstat=", jk_plot_cmd_status_local, ")."
         else if (jk_plot_exit_status_local /= 0) then
            write (*, '(A,I0)') "[WARN] jackknife gnuplot exited with status ", jk_plot_exit_status_local
         end if

         jackknife_file_local = join_path(trim(analysis_dir_local), "jackknife_error_z.dat")
         jackknife_plot_script_local = join_path(trim(analysis_dir_local), "jackknife_error_z_plot.gp")
         jackknife_plot_image_local = join_path(trim(analysis_dir_local), "jackknife_error_z.png")

         write (*, '(A,I0,A)') "[PROGRESS] Computing multichain binned jackknife curve (z) with ", &
            jk_n_bins_local, " bin sizes."
         call compute_jackknife_error_curve_stratified(num_tra2_all, phi_all, chain_sample_counts, jk_bin_sizes_local, &
                                                       jk_err_re_local, jk_err_im_local, jk_err_abs_local, jk_n_blocks_local)

         call analyze_jackknife_component(jk_err_re_local, jk_bin_sizes_local, n_total_samples, &
                                          jk_min_blocks_local, jk_min_bin_local, &
                                          jk_plateau_re_local, jk_onset_re_local, jk_onset_re_low_local, jk_onset_re_high_local, &
                                          jk_tau_var_re_local, jk_tau_onset_re_local, jk_tau_eff_re_local, jk_n_blocks_local)
         call analyze_jackknife_component(jk_err_im_local, jk_bin_sizes_local, n_total_samples, &
                                          jk_min_blocks_local, jk_min_bin_local, &
                                          jk_plateau_im_local, jk_onset_im_local, jk_onset_im_low_local, jk_onset_im_high_local, &
                                          jk_tau_var_im_local, jk_tau_onset_im_local, jk_tau_eff_im_local, jk_n_blocks_local)
         err_tra2_strat_re = max(0.0_dp, jk_plateau_re_local)
         err_tra2_strat_im = max(0.0_dp, jk_plateau_im_local)
         err_tra2_strat_ok = (err_tra2_strat_re > tiny(1.0_dp)) .and. (err_tra2_strat_im > tiny(1.0_dp))

         call save_jackknife_curve(trim(jackknife_file_local), n_total_samples, jk_bin_sizes_local, &
                                   jk_err_re_local, jk_err_im_local, jk_err_abs_local, jk_n_blocks_local)
         call write_jackknife_plot_script(trim(jackknife_plot_script_local), trim(jackknife_file_local), &
                                          trim(jackknife_plot_image_local), &
                                          jk_plateau_re_local, jk_plateau_im_local, jk_onset_re_local, jk_onset_im_local, &
                                          jk_onset_re_low_local, jk_onset_re_high_local, jk_onset_im_low_local, jk_onset_im_high_local, &
                                          jk_tau_eff_re_local, jk_tau_eff_im_local, jk_min_blocks_local, jk_min_bin_local)
         write (*, '(A,1X,A)') "[PROGRESS] Rendering jackknife error plot:", trim(jackknife_plot_image_local)
         jackknife_plot_cmd_local = "gnuplot "//trim(jackknife_plot_script_local)
         call execute_command_line(trim(jackknife_plot_cmd_local), exitstat=jk_plot_exit_status_local, cmdstat=jk_plot_cmd_status_local)
         if (jk_plot_cmd_status_local /= 0) then
            write (*, '(A,I0,A)') "[WARN] Failed to invoke jackknife gnuplot (cmdstat=", jk_plot_cmd_status_local, ")."
         else if (jk_plot_exit_status_local /= 0) then
            write (*, '(A,I0)') "[WARN] jackknife gnuplot exited with status ", jk_plot_exit_status_local
         end if

         deallocate (jk_err_re_local, jk_err_im_local, jk_err_abs_local, jk_n_blocks_local, jk_bin_sizes_local)
      else
         write (*, '(A)') "[WARN] Skipping jackknife plot: insufficient samples."
      end if

      err_o_robust_re = max(0.0_dp, o_mcse_re)
      err_o_robust_im = max(0.0_dp, o_mcse_im)
      err_tra2_robust_re = max(0.0_dp, tra2_mcse_re)
      err_tra2_robust_im = max(0.0_dp, tra2_mcse_im)
      if (err_o_ok) then
         err_o_robust_re = max(err_o_robust_re, err_o_re)
         err_o_robust_im = max(err_o_robust_im, err_o_im)
      end if
      if (err_o_strat_ok) then
         err_o_robust_re = max(err_o_robust_re, err_o_strat_re)
         err_o_robust_im = max(err_o_robust_im, err_o_strat_im)
      end if
      if (err_tra2_ok) then
         err_tra2_robust_re = max(err_tra2_robust_re, err_tra2_re)
         err_tra2_robust_im = max(err_tra2_robust_im, err_tra2_im)
      end if
      if (err_tra2_strat_ok) then
         err_tra2_robust_re = max(err_tra2_robust_re, err_tra2_strat_re)
         err_tra2_robust_im = max(err_tra2_robust_im, err_tra2_strat_im)
      end if
      err_o_robust_ok = err_o_ok .or. err_o_strat_ok .or. &
                        ((err_o_robust_re > tiny(1.0_dp)) .or. (err_o_robust_im > tiny(1.0_dp)))
      err_tra2_robust_ok = err_tra2_ok .or. err_tra2_strat_ok .or. &
                           ((err_tra2_robust_re > tiny(1.0_dp)) .or. (err_tra2_robust_im > tiny(1.0_dp)))

      write (*, '(A,2(1X,ES14.6),1X,A,L1)') "[RESULT] error_strat_jk_<virial> (Re, Im)=", &
         err_o_strat_re, err_o_strat_im, "valid=", err_o_strat_ok
      write (*, '(A,2(1X,ES14.6),1X,A,L1)') "[RESULT] error_strat_jk_<z> (Re, Im)=", &
         err_tra2_strat_re, err_tra2_strat_im, "valid=", err_tra2_strat_ok
      write (*, '(A,2(1X,ES14.6),1X,A,L1)') "[RESULT] error_robust_<virial> (Re, Im)=", &
         err_o_robust_re, err_o_robust_im, "valid=", err_o_robust_ok
      write (*, '(A,2(1X,ES14.6),1X,A,L1)') "[RESULT] error_robust_<z> (Re, Im)=", &
         err_tra2_robust_re, err_tra2_robust_im, "valid=", err_tra2_robust_ok
      write (*, '(A)') "[RESULT] robust_error_rule=max(chain_jk, stratified_jk_plateau, mcse_mean) per component"

      meta_file = join_path(trim(run_dir), "multichain_expectations.dat")
      call save_multichain_metadata(trim(meta_file), trim(obs_name), n_chains, n_total_samples, n_use, &
                                    mean_o, mean_tra2, err_o_re, err_o_im, err_tra2_re, err_tra2_im, &
                                    err_o_ok, err_tra2_ok, &
                                    err_o_strat_re, err_o_strat_im, err_tra2_strat_re, err_tra2_strat_im, &
                                    err_o_strat_ok, err_tra2_strat_ok, &
                                    err_o_robust_re, err_o_robust_im, err_tra2_robust_re, err_tra2_robust_im, &
                                    err_o_robust_ok, err_tra2_robust_ok, &
                                    o_rhat_re, o_rhat_im, o_ess_bulk_re, o_ess_bulk_im, o_ess_tail_re, o_ess_tail_im, &
                                    o_mcse_re, o_mcse_im, &
                                    tra2_rhat_re, tra2_rhat_im, tra2_ess_bulk_re, tra2_ess_bulk_im, tra2_ess_tail_re, &
                                    tra2_ess_tail_im, tra2_mcse_re, tra2_mcse_im, &
                                    phase_coherence, phase_eff_n, abs(sum_phi_total))
      write (*, '(A,1X,A)') "[DONE] Multichain expectation analysis complete. metadata=", trim(meta_file)

      deallocate (z_paths, phi_paths, chain_sample_counts, sum_num_o_chain, sum_num_tra2_chain, sum_phi_chain)
      deallocate (num_o_tail, num_tra2_tail, weighted_o_tail, weighted_tra2_tail)
      deallocate (num_o_all, num_tra2_all, phi_all)
   end subroutine evaluate_multichain_run

   subroutine discover_multichain_paths(run_dir, z_paths, phi_paths, n_chains, io_status)
      character(len=*), intent(in) :: run_dir
      character(len=1024), allocatable, intent(out) :: z_paths(:), phi_paths(:)
      integer, intent(out) :: n_chains, io_status

      integer, parameter :: max_scan = 999
      character(len=1024), allocatable :: z_tmp(:), phi_tmp(:)
      character(len=64) :: chain_name
      character(len=1024) :: z_candidate, phi_candidate
      logical :: z_exists, phi_exists
      integer :: chain_idx, found_count, alloc_status

      n_chains = 0
      io_status = 0
      allocate (z_tmp(max_scan), phi_tmp(max_scan), stat=alloc_status)
      if (alloc_status /= 0) then
         io_status = 1
         return
      end if

      found_count = 0
      do chain_idx = 1, max_scan
         write (chain_name, '("chain_",I3.3)') chain_idx
         z_candidate = trim(run_dir)//"/"//trim(chain_name)//"/output/z_history.dat"
         phi_candidate = trim(run_dir)//"/"//trim(chain_name)//"/output/phi_history.dat"
         inquire (file=trim(z_candidate), exist=z_exists)
         inquire (file=trim(phi_candidate), exist=phi_exists)
         if (z_exists .and. phi_exists) then
            found_count = found_count + 1
            z_tmp(found_count) = trim(z_candidate)
            phi_tmp(found_count) = trim(phi_candidate)
         end if
      end do

      if (found_count < 1) then
         io_status = 1
         deallocate (z_tmp, phi_tmp)
         return
      end if

      allocate (z_paths(found_count), phi_paths(found_count), stat=alloc_status)
      if (alloc_status /= 0) then
         io_status = 1
         deallocate (z_tmp, phi_tmp)
         return
      end if

      z_paths = z_tmp(1:found_count)
      phi_paths = phi_tmp(1:found_count)
      n_chains = found_count
      deallocate (z_tmp, phi_tmp)
   end subroutine discover_multichain_paths

   subroutine infer_history_sample_count(z_file, phi_file, z_count, phi_count, io_status)
      character(len=*), intent(in) :: z_file, phi_file
      integer, intent(out) :: z_count, phi_count, io_status

      integer :: z_unit, phi_unit, z_size
      integer(kind=8) :: z_bytes, phi_bytes, z_stride
      integer(kind=8), parameter :: complex_bytes = 16_8

      z_count = 0
      phi_count = 0
      io_status = 0
      z_size = n_size - 1
      if (z_size < 1) then
         io_status = 1
         return
      end if

      z_unit = 88
      open (unit=z_unit, file=z_file, access='stream', form='unformatted', status='old', iostat=io_status)
      if (io_status /= 0) return
      inquire (unit=z_unit, size=z_bytes)
      close (z_unit)

      z_stride = int(z_size, kind=8)*complex_bytes
      if (z_stride <= 0_8 .or. mod(z_bytes, z_stride) /= 0_8) then
         io_status = 1
         return
      end if
      z_count = int(z_bytes/z_stride)

      phi_unit = 89
      open (unit=phi_unit, file=phi_file, access='stream', form='unformatted', status='old', iostat=io_status)
      if (io_status /= 0) return
      inquire (unit=phi_unit, size=phi_bytes)
      close (phi_unit)
      if (mod(phi_bytes, complex_bytes) /= 0_8) then
         io_status = 1
         return
      end if
      phi_count = int(phi_bytes/complex_bytes)
   end subroutine infer_history_sample_count

   subroutine compute_chain_jackknife_ratio_error(sum_num_chain, sum_den_chain, total_num, total_den, err_re, err_im, valid)
      complex(dp), intent(in) :: sum_num_chain(:), sum_den_chain(:)
      complex(dp), intent(in) :: total_num, total_den
      real(dp), intent(out) :: err_re, err_im
      logical, intent(out) :: valid

      complex(dp) :: den_loo, ratio_loo
      real(dp), allocatable :: loo_re(:), loo_im(:)
      real(dp) :: mean_re, mean_im, m2_re, m2_im, delta_re, delta_im, prefactor
      integer :: n_chains_local, chain_idx

      n_chains_local = size(sum_num_chain)
      err_re = 0.0_dp
      err_im = 0.0_dp
      valid = .false.
      if (size(sum_den_chain) /= n_chains_local) return
      if (n_chains_local < 2) then
         valid = .true.
         return
      end if

      allocate (loo_re(n_chains_local), loo_im(n_chains_local))
      do chain_idx = 1, n_chains_local
         den_loo = total_den - sum_den_chain(chain_idx)
         if (abs(den_loo) <= tiny(1.0_dp)) then
            deallocate (loo_re, loo_im)
            return
         end if
         ratio_loo = (total_num - sum_num_chain(chain_idx))/den_loo
         loo_re(chain_idx) = real(ratio_loo, dp)
         loo_im(chain_idx) = aimag(ratio_loo)
      end do

      mean_re = 0.0_dp
      mean_im = 0.0_dp
      m2_re = 0.0_dp
      m2_im = 0.0_dp
      do chain_idx = 1, n_chains_local
         delta_re = loo_re(chain_idx) - mean_re
         mean_re = mean_re + delta_re/real(chain_idx, dp)
         m2_re = m2_re + delta_re*(loo_re(chain_idx) - mean_re)
         delta_im = loo_im(chain_idx) - mean_im
         mean_im = mean_im + delta_im/real(chain_idx, dp)
         m2_im = m2_im + delta_im*(loo_im(chain_idx) - mean_im)
      end do

      prefactor = real(n_chains_local - 1, dp)/real(n_chains_local, dp)
      err_re = sqrt(max(0.0_dp, prefactor*m2_re))
      err_im = sqrt(max(0.0_dp, prefactor*m2_im))
      valid = .true.
      deallocate (loo_re, loo_im)
   end subroutine compute_chain_jackknife_ratio_error

   subroutine compute_multichain_observable_diagnostics(observable_matrix, max_lag_cap, &
                                                        rhat_re, rhat_im, ess_bulk_re, ess_bulk_im, &
                                                        ess_tail_re, ess_tail_im, mcse_mean_re, mcse_mean_im)
      complex(dp), intent(in) :: observable_matrix(:, :)
      integer, intent(in) :: max_lag_cap
      real(dp), intent(out) :: rhat_re, rhat_im, ess_bulk_re, ess_bulk_im
      real(dp), intent(out) :: ess_tail_re, ess_tail_im, mcse_mean_re, mcse_mean_im

      real(dp), allocatable :: re_matrix(:, :), im_matrix(:, :)
      integer :: n_chain_local, n_draw_local

      n_chain_local = size(observable_matrix, 1)
      n_draw_local = size(observable_matrix, 2)
      rhat_re = 1.0_dp
      rhat_im = 1.0_dp
      ess_bulk_re = 1.0_dp
      ess_bulk_im = 1.0_dp
      ess_tail_re = 1.0_dp
      ess_tail_im = 1.0_dp
      mcse_mean_re = 0.0_dp
      mcse_mean_im = 0.0_dp
      if (n_chain_local < 1 .or. n_draw_local < 2) return

      allocate (re_matrix(n_chain_local, n_draw_local), im_matrix(n_chain_local, n_draw_local))
      re_matrix = real(observable_matrix, dp)
      im_matrix = aimag(observable_matrix)
      call compute_multichain_component_diagnostics(re_matrix, max_lag_cap, rhat_re, ess_bulk_re, ess_tail_re, mcse_mean_re)
      call compute_multichain_component_diagnostics(im_matrix, max_lag_cap, rhat_im, ess_bulk_im, ess_tail_im, mcse_mean_im)
      deallocate (re_matrix, im_matrix)
   end subroutine compute_multichain_observable_diagnostics

   subroutine compute_multichain_component_diagnostics(values_matrix, max_lag_cap, rhat, ess_bulk, ess_tail, mcse_mean)
      real(dp), intent(in) :: values_matrix(:, :)
      integer, intent(in) :: max_lag_cap
      real(dp), intent(out) :: rhat, ess_bulk, ess_tail, mcse_mean

      integer :: n_chain_local, n_draw_local, n_total, chain_idx, draw_idx
      integer :: lag_used_ips, lag_used_ics, flat_idx
      real(dp) :: tau_ips, tau_ics, tau_obm, tau_chain, tau_bulk
      real(dp) :: tau_low_ips, tau_low_ics, tau_low_obm, tau_low_chain, tau_low
      real(dp) :: tau_high_ips, tau_high_ics, tau_high_obm, tau_high_chain, tau_high
      real(dp) :: q_low, q_high, mean_value, var_value
      real(dp) :: ess_low, ess_high
      real(dp), allocatable :: flat_values(:), indicator_low(:), indicator_high(:)

      n_chain_local = size(values_matrix, 1)
      n_draw_local = size(values_matrix, 2)
      n_total = n_chain_local*n_draw_local
      rhat = 1.0_dp
      ess_bulk = 1.0_dp
      ess_tail = 1.0_dp
      mcse_mean = 0.0_dp
      if (n_chain_local < 1 .or. n_draw_local < 2) return

      call compute_split_rhat_matrix_real(values_matrix, rhat)

      tau_bulk = 1.0_dp
      do chain_idx = 1, n_chain_local
         call estimate_tau_int_ips_real(values_matrix(chain_idx, :), max_lag_cap, tau_ips, lag_used_ips)
         call estimate_tau_int_ics_real(values_matrix(chain_idx, :), max_lag_cap, tau_ics, lag_used_ics)
         call estimate_tau_int_obm_real(values_matrix(chain_idx, :), max_lag_cap, tau_obm)
         tau_chain = max(1.0_dp, max(tau_ips, max(tau_ics, tau_obm)))
         tau_bulk = max(tau_bulk, tau_chain)
      end do
      ess_bulk = real(n_total, dp)/tau_bulk
      ess_bulk = max(1.0_dp, min(real(n_total, dp), ess_bulk))

      allocate (flat_values(n_total))
      flat_idx = 0
      do draw_idx = 1, n_draw_local
         do chain_idx = 1, n_chain_local
            flat_idx = flat_idx + 1
            flat_values(flat_idx) = values_matrix(chain_idx, draw_idx)
         end do
      end do
      call sample_mean_variance_real(flat_values, mean_value, var_value)
      if (var_value > tiny(1.0_dp)) then
         mcse_mean = sqrt(var_value/max(1.0_dp, ess_bulk))
      else
         mcse_mean = 0.0_dp
      end if

      q_low = sample_quantile_real(flat_values, 0.05_dp)
      q_high = sample_quantile_real(flat_values, 0.95_dp)
      allocate (indicator_low(n_draw_local), indicator_high(n_draw_local))
      tau_low = 1.0_dp
      tau_high = 1.0_dp
      do chain_idx = 1, n_chain_local
         do draw_idx = 1, n_draw_local
            if (values_matrix(chain_idx, draw_idx) <= q_low) then
               indicator_low(draw_idx) = 1.0_dp
            else
               indicator_low(draw_idx) = 0.0_dp
            end if
            if (values_matrix(chain_idx, draw_idx) >= q_high) then
               indicator_high(draw_idx) = 1.0_dp
            else
               indicator_high(draw_idx) = 0.0_dp
            end if
         end do

         call estimate_tau_int_ips_real(indicator_low, max_lag_cap, tau_low_ips, lag_used_ips)
         call estimate_tau_int_ics_real(indicator_low, max_lag_cap, tau_low_ics, lag_used_ics)
         call estimate_tau_int_obm_real(indicator_low, max_lag_cap, tau_low_obm)
         tau_low_chain = max(1.0_dp, max(tau_low_ips, max(tau_low_ics, tau_low_obm)))
         tau_low = max(tau_low, tau_low_chain)

         call estimate_tau_int_ips_real(indicator_high, max_lag_cap, tau_high_ips, lag_used_ips)
         call estimate_tau_int_ics_real(indicator_high, max_lag_cap, tau_high_ics, lag_used_ics)
         call estimate_tau_int_obm_real(indicator_high, max_lag_cap, tau_high_obm)
         tau_high_chain = max(1.0_dp, max(tau_high_ips, max(tau_high_ics, tau_high_obm)))
         tau_high = max(tau_high, tau_high_chain)
      end do
      ess_low = real(n_total, dp)/tau_low
      ess_high = real(n_total, dp)/tau_high
      ess_tail = min(ess_low, ess_high)
      ess_tail = max(1.0_dp, min(real(n_total, dp), ess_tail))

      deallocate (indicator_low, indicator_high, flat_values)
   end subroutine compute_multichain_component_diagnostics

   subroutine compute_split_rhat_matrix_real(values_matrix, rhat)
      real(dp), intent(in) :: values_matrix(:, :)
      real(dp), intent(out) :: rhat

      integer :: n_chains_local, n_draws_local, n_draws_even, n_half
      integer :: chain_idx, draw_idx, flat_idx
      real(dp) :: rhat_rank, rhat_folded, center_value
      real(dp), allocatable :: split_matrix(:, :), rank_matrix(:, :), flat_values(:)

      n_chains_local = size(values_matrix, 1)
      n_draws_local = size(values_matrix, 2)
      rhat = 1.0_dp
      n_draws_even = n_draws_local - mod(n_draws_local, 2)
      n_half = n_draws_even/2
      if (n_chains_local < 2 .or. n_half < 2) return

      allocate (split_matrix(2*n_chains_local, n_half), rank_matrix(2*n_chains_local, n_half))
      do chain_idx = 1, n_chains_local
         split_matrix(chain_idx, :) = values_matrix(chain_idx, 1:n_half)
         split_matrix(n_chains_local + chain_idx, :) = values_matrix(chain_idx, n_half + 1:n_draws_even)
      end do

      call rank_normalize_matrix_real(split_matrix, rank_matrix)
      call compute_rhat_basic_matrix_real(rank_matrix, rhat_rank)

      allocate (flat_values(2*n_chains_local*n_half))
      flat_idx = 0
      do chain_idx = 1, 2*n_chains_local
         do draw_idx = 1, n_half
            flat_idx = flat_idx + 1
            flat_values(flat_idx) = split_matrix(chain_idx, draw_idx)
         end do
      end do
      center_value = sample_median_real(flat_values)
      deallocate (flat_values)

      split_matrix = abs(split_matrix - center_value)
      call rank_normalize_matrix_real(split_matrix, rank_matrix)
      call compute_rhat_basic_matrix_real(rank_matrix, rhat_folded)

      rhat = max(rhat_rank, rhat_folded)
      deallocate (split_matrix, rank_matrix)
   end subroutine compute_split_rhat_matrix_real

   subroutine compute_rhat_basic_matrix_real(values_matrix, rhat)
      real(dp), intent(in) :: values_matrix(:, :)
      real(dp), intent(out) :: rhat

      integer :: n_chains_local, n_draws_local, chain_idx
      real(dp) :: w, b, mean_overall, b_acc, var_hat
      real(dp), allocatable :: chain_means(:), chain_vars(:)

      n_chains_local = size(values_matrix, 1)
      n_draws_local = size(values_matrix, 2)
      rhat = 1.0_dp
      if (n_chains_local < 2 .or. n_draws_local < 2) return

      allocate (chain_means(n_chains_local), chain_vars(n_chains_local))
      do chain_idx = 1, n_chains_local
         call sample_mean_variance_real(values_matrix(chain_idx, :), chain_means(chain_idx), chain_vars(chain_idx))
      end do

      w = sum(chain_vars)/real(n_chains_local, dp)
      if (w <= tiny(1.0_dp)) then
         rhat = 1.0_dp
         deallocate (chain_means, chain_vars)
         return
      end if

      mean_overall = sum(chain_means)/real(n_chains_local, dp)
      b_acc = 0.0_dp
      do chain_idx = 1, n_chains_local
         b_acc = b_acc + (chain_means(chain_idx) - mean_overall)**2
      end do
      if (n_chains_local > 1) then
         b = real(n_draws_local, dp)*b_acc/real(n_chains_local - 1, dp)
      else
         b = 0.0_dp
      end if
      var_hat = (real(n_draws_local - 1, dp)/real(n_draws_local, dp))*w + b/real(n_draws_local, dp)
      rhat = sqrt(max(1.0_dp, var_hat/max(w, tiny(1.0_dp))))
      deallocate (chain_means, chain_vars)
   end subroutine compute_rhat_basic_matrix_real

   subroutine rank_normalize_matrix_real(values_matrix, normalized_matrix)
      real(dp), intent(in) :: values_matrix(:, :)
      real(dp), intent(out) :: normalized_matrix(:, :)

      integer :: n_chains_local, n_draws_local, n_total
      integer :: chain_idx, draw_idx, flat_idx
      integer :: start_idx, end_idx, order_idx
      real(dp) :: avg_rank, p_value, eps_prob
      real(dp), allocatable :: flat_values(:), ranks(:)
      integer, allocatable :: sort_order(:)

      n_chains_local = size(values_matrix, 1)
      n_draws_local = size(values_matrix, 2)
      if (size(normalized_matrix, 1) /= n_chains_local .or. size(normalized_matrix, 2) /= n_draws_local) then
         write (*, '(A)') "[ERROR] Rank-normalization output shape mismatch."
         error stop 1
      end if

      n_total = n_chains_local*n_draws_local
      if (n_total <= 0) then
         normalized_matrix = 0.0_dp
         return
      end if

      allocate (flat_values(n_total), ranks(n_total), sort_order(n_total))
      flat_idx = 0
      do chain_idx = 1, n_chains_local
         do draw_idx = 1, n_draws_local
            flat_idx = flat_idx + 1
            flat_values(flat_idx) = values_matrix(chain_idx, draw_idx)
         end do
      end do

      call sort_indices_by_real_values(flat_values, sort_order)
      start_idx = 1
      do while (start_idx <= n_total)
         end_idx = start_idx
         do while (end_idx < n_total)
            if (flat_values(sort_order(end_idx + 1)) /= flat_values(sort_order(start_idx))) exit
            end_idx = end_idx + 1
         end do
         avg_rank = 0.5_dp*real(start_idx + end_idx, dp)
         do order_idx = start_idx, end_idx
            ranks(sort_order(order_idx)) = avg_rank
         end do
         start_idx = end_idx + 1
      end do

      eps_prob = tiny(1.0_dp)
      flat_idx = 0
      do chain_idx = 1, n_chains_local
         do draw_idx = 1, n_draws_local
            flat_idx = flat_idx + 1
            p_value = (ranks(flat_idx) - 0.375_dp)/(real(n_total, dp) + 0.25_dp)
            p_value = min(1.0_dp - eps_prob, max(eps_prob, p_value))
            normalized_matrix(chain_idx, draw_idx) = normal_quantile_approx(p_value)
         end do
      end do
      deallocate (flat_values, ranks, sort_order)
   end subroutine rank_normalize_matrix_real

   subroutine sort_indices_by_real_values(values, sort_order)
      real(dp), intent(in) :: values(:)
      integer, intent(out) :: sort_order(:)

      integer :: n_values, value_idx, root_idx, end_idx, temp_idx

      n_values = size(values)
      if (size(sort_order) /= n_values) then
         write (*, '(A)') "[ERROR] sort_indices_by_real_values: shape mismatch."
         error stop 1
      end if

      do value_idx = 1, n_values
         sort_order(value_idx) = value_idx
      end do
      if (n_values <= 1) return

      do root_idx = n_values/2, 1, -1
         call sift_down_index_heap(values, sort_order, root_idx, n_values)
      end do

      do end_idx = n_values, 2, -1
         temp_idx = sort_order(1)
         sort_order(1) = sort_order(end_idx)
         sort_order(end_idx) = temp_idx
         call sift_down_index_heap(values, sort_order, 1, end_idx - 1)
      end do
   end subroutine sort_indices_by_real_values

   subroutine sift_down_index_heap(values, sort_order, start_idx, end_idx)
      real(dp), intent(in) :: values(:)
      integer, intent(inout) :: sort_order(:)
      integer, intent(in) :: start_idx, end_idx

      integer :: root_idx, child_idx, swap_idx, temp_idx

      root_idx = start_idx
      do while (2*root_idx <= end_idx)
         child_idx = 2*root_idx
         swap_idx = root_idx

         if (values(sort_order(swap_idx)) < values(sort_order(child_idx))) swap_idx = child_idx
         if (child_idx + 1 <= end_idx) then
            if (values(sort_order(swap_idx)) < values(sort_order(child_idx + 1))) swap_idx = child_idx + 1
         end if
         if (swap_idx == root_idx) exit

         temp_idx = sort_order(root_idx)
         sort_order(root_idx) = sort_order(swap_idx)
         sort_order(swap_idx) = temp_idx
         root_idx = swap_idx
      end do
   end subroutine sift_down_index_heap

   real(dp) function normal_quantile_approx(p_value) result(z_value)
      real(dp), intent(in) :: p_value

      real(dp), parameter :: a1 = -3.969683028665376d+01
      real(dp), parameter :: a2 = 2.209460984245205d+02
      real(dp), parameter :: a3 = -2.759285104469687d+02
      real(dp), parameter :: a4 = 1.383577518672690d+02
      real(dp), parameter :: a5 = -3.066479806614716d+01
      real(dp), parameter :: a6 = 2.506628277459239d+00
      real(dp), parameter :: b1 = -5.447609879822406d+01
      real(dp), parameter :: b2 = 1.615858368580409d+02
      real(dp), parameter :: b3 = -1.556989798598866d+02
      real(dp), parameter :: b4 = 6.680131188771972d+01
      real(dp), parameter :: b5 = -1.328068155288572d+01
      real(dp), parameter :: c1 = -7.784894002430293d-03
      real(dp), parameter :: c2 = -3.223964580411365d-01
      real(dp), parameter :: c3 = -2.400758277161838d+00
      real(dp), parameter :: c4 = -2.549732539343734d+00
      real(dp), parameter :: c5 = 4.374664141464968d+00
      real(dp), parameter :: c6 = 2.938163982698783d+00
      real(dp), parameter :: d1 = 7.784695709041462d-03
      real(dp), parameter :: d2 = 3.224671290700398d-01
      real(dp), parameter :: d3 = 2.445134137142996d+00
      real(dp), parameter :: d4 = 3.754408661907416d+00
      real(dp), parameter :: p_low = 0.02425_dp
      real(dp), parameter :: p_high = 1.0_dp - p_low

      real(dp) :: q, r

      if (p_value <= 0.0_dp) then
         z_value = -huge(1.0_dp)
         return
      end if
      if (p_value >= 1.0_dp) then
         z_value = huge(1.0_dp)
         return
      end if

      if (p_value < p_low) then
         q = sqrt(-2.0_dp*log(p_value))
         z_value = (((((c1*q + c2)*q + c3)*q + c4)*q + c5)*q + c6)/ &
                   ((((d1*q + d2)*q + d3)*q + d4)*q + 1.0_dp)
      else if (p_value <= p_high) then
         q = p_value - 0.5_dp
         r = q*q
         z_value = (((((a1*r + a2)*r + a3)*r + a4)*r + a5)*r + a6)*q/ &
                   (((((b1*r + b2)*r + b3)*r + b4)*r + b5)*r + 1.0_dp)
      else
         q = sqrt(-2.0_dp*log(1.0_dp - p_value))
         z_value = -(((((c1*q + c2)*q + c3)*q + c4)*q + c5)*q + c6)/ &
                    ((((d1*q + d2)*q + d3)*q + d4)*q + 1.0_dp)
      end if
   end function normal_quantile_approx

   subroutine save_multichain_metadata(file_path, obs_name, n_chains, n_samples_total, n_use, &
                                       mean_o, mean_tra2, err_o_re, err_o_im, err_tra2_re, err_tra2_im, &
                                       err_o_ok, err_tra2_ok, &
                                       err_o_strat_re, err_o_strat_im, err_tra2_strat_re, err_tra2_strat_im, &
                                       err_o_strat_ok, err_tra2_strat_ok, &
                                       err_o_robust_re, err_o_robust_im, err_tra2_robust_re, err_tra2_robust_im, &
                                       err_o_robust_ok, err_tra2_robust_ok, &
                                       o_rhat_re, o_rhat_im, o_ess_bulk_re, o_ess_bulk_im, o_ess_tail_re, o_ess_tail_im, &
                                       o_mcse_re, o_mcse_im, &
                                       tra2_rhat_re, tra2_rhat_im, tra2_ess_bulk_re, tra2_ess_bulk_im, &
                                       tra2_ess_tail_re, tra2_ess_tail_im, tra2_mcse_re, tra2_mcse_im, &
                                       phase_coherence, phase_eff_n, abs_sum_phi)
      character(len=*), intent(in) :: file_path, obs_name
      integer, intent(in) :: n_chains, n_samples_total, n_use
      complex(dp), intent(in) :: mean_o, mean_tra2
      real(dp), intent(in) :: err_o_re, err_o_im, err_tra2_re, err_tra2_im
      logical, intent(in) :: err_o_ok, err_tra2_ok
      real(dp), intent(in) :: err_o_strat_re, err_o_strat_im, err_tra2_strat_re, err_tra2_strat_im
      logical, intent(in) :: err_o_strat_ok, err_tra2_strat_ok
      real(dp), intent(in) :: err_o_robust_re, err_o_robust_im, err_tra2_robust_re, err_tra2_robust_im
      logical, intent(in) :: err_o_robust_ok, err_tra2_robust_ok
      real(dp), intent(in) :: o_rhat_re, o_rhat_im, o_ess_bulk_re, o_ess_bulk_im, o_ess_tail_re, o_ess_tail_im
      real(dp), intent(in) :: o_mcse_re, o_mcse_im
      real(dp), intent(in) :: tra2_rhat_re, tra2_rhat_im, tra2_ess_bulk_re, tra2_ess_bulk_im
      real(dp), intent(in) :: tra2_ess_tail_re, tra2_ess_tail_im, tra2_mcse_re, tra2_mcse_im
      real(dp), intent(in) :: phase_coherence, phase_eff_n, abs_sum_phi

      integer :: io_unit, io_status

      io_unit = 93
      open (io_unit, file=file_path, status='replace', action='write', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Failed to open multichain metadata file:", trim(file_path)
         error stop 1
      end if

      write (io_unit, '(A)') "# multichain expectation metadata"
      write (io_unit, '(A,A)') "observable_virial=", trim(obs_name)
      write (io_unit, '(A,I0)') "chains=", n_chains
      write (io_unit, '(A,I0)') "samples_total=", n_samples_total
      write (io_unit, '(A,I0)') "diag_n_use=", n_use
      write (io_unit, '(A)') "diagnostics_basis=weighted_sample=(observable*phi)/sum(phi)_all_chains"
      write (io_unit, '(A,2ES24.14)') "mean_virial_re_im=", real(mean_o, dp), aimag(mean_o)
      write (io_unit, '(A,2ES24.14)') "mean_z_re_im=", real(mean_tra2, dp), aimag(mean_tra2)
      write (io_unit, '(A,2ES24.14)') "err_chain_jk_virial_re_im=", err_o_re, err_o_im
      write (io_unit, '(A,2ES24.14)') "err_chain_jk_z_re_im=", err_tra2_re, err_tra2_im
      write (io_unit, '(A,L1)') "err_chain_jk_virial_valid=", err_o_ok
      write (io_unit, '(A,L1)') "err_chain_jk_z_valid=", err_tra2_ok
      write (io_unit, '(A,2ES24.14)') "err_strat_jk_virial_re_im=", err_o_strat_re, err_o_strat_im
      write (io_unit, '(A,2ES24.14)') "err_strat_jk_z_re_im=", err_tra2_strat_re, err_tra2_strat_im
      write (io_unit, '(A,L1)') "err_strat_jk_virial_valid=", err_o_strat_ok
      write (io_unit, '(A,L1)') "err_strat_jk_z_valid=", err_tra2_strat_ok
      write (io_unit, '(A,2ES24.14)') "err_robust_virial_re_im=", err_o_robust_re, err_o_robust_im
      write (io_unit, '(A,2ES24.14)') "err_robust_z_re_im=", err_tra2_robust_re, err_tra2_robust_im
      write (io_unit, '(A,L1)') "err_robust_virial_valid=", err_o_robust_ok
      write (io_unit, '(A,L1)') "err_robust_z_valid=", err_tra2_robust_ok
      write (io_unit, '(A)') "err_robust_rule=max(chain_jk,stratified_jk_plateau,mcse_mean)_per_component"
      write (io_unit, '(A,2F12.6)') "virial_split_rhat_re_im=", o_rhat_re, o_rhat_im
      write (io_unit, '(A,2ES24.14)') "virial_ess_bulk_re_im=", o_ess_bulk_re, o_ess_bulk_im
      write (io_unit, '(A,2ES24.14)') "virial_ess_tail_re_im=", o_ess_tail_re, o_ess_tail_im
      write (io_unit, '(A,2ES24.14)') "virial_mcse_mean_re_im=", o_mcse_re, o_mcse_im
      write (io_unit, '(A,2F12.6)') "z_split_rhat_re_im=", tra2_rhat_re, tra2_rhat_im
      write (io_unit, '(A,2ES24.14)') "z_ess_bulk_re_im=", tra2_ess_bulk_re, tra2_ess_bulk_im
      write (io_unit, '(A,2ES24.14)') "z_ess_tail_re_im=", tra2_ess_tail_re, tra2_ess_tail_im
      write (io_unit, '(A,2ES24.14)') "z_mcse_mean_re_im=", tra2_mcse_re, tra2_mcse_im
      write (io_unit, '(A,ES24.14)') "phase_coherence=", phase_coherence
      write (io_unit, '(A,ES24.14)') "phase_eff_n=", phase_eff_n
      write (io_unit, '(A,ES24.14)') "abs_sum_phi=", abs_sum_phi
      close (io_unit)
   end subroutine save_multichain_metadata

   subroutine write_virial_plot_script(script_file, data_file, image_file, plot_start_idx, plot_end_idx, &
                                       re_min, re_max, im_min, im_max)
      character(len=*), intent(in) :: script_file, data_file, image_file
      integer, intent(in) :: plot_start_idx, plot_end_idx
      real(dp), intent(in) :: re_min, re_max, im_min, im_max
      integer :: io_unit, io_status
      integer :: gnuplot_start, gnuplot_end
      character(len=32) :: start_text, end_text, sample_start_text, sample_end_text
      character(len=32) :: re_min_text, re_max_text, im_min_text, im_max_text

      io_unit = 31
      open (io_unit, file=script_file, status='replace', action='write', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Failed to open plot script output:", trim(script_file)
         error stop 1
      end if

      gnuplot_start = max(0, plot_start_idx - 1)
      gnuplot_end = max(gnuplot_start, plot_end_idx - 1)
      write (start_text, '(I0)') gnuplot_start
      write (end_text, '(I0)') gnuplot_end
      write (sample_start_text, '(I0)') plot_start_idx
      write (sample_end_text, '(I0)') plot_end_idx
      write (re_min_text, '(ES14.6E3)') re_min
      write (re_max_text, '(ES14.6E3)') re_max
      write (im_min_text, '(ES14.6E3)') im_min
      write (im_max_text, '(ES14.6E3)') im_max

      write (io_unit, '(A)') "set terminal pngcairo size 1200,800 enhanced font 'Helvetica,14'"
      write (io_unit, '(A)') "set output '"//trim(image_file)//"'"
      write (io_unit, '(A)') "set xlabel 'Sample index'"
      write (io_unit, '(A)') "set ylabel 'Virial numerator'"
      write (io_unit, '(A)') "set multiplot layout 2,1 rowsfirst title 'Virial Numerator Zoom: samples "// &
         trim(sample_start_text)//".."//trim(sample_end_text)//"'"
      write (io_unit, '(A)') "set grid"
      write (io_unit, '(A)') "set key off"
      write (io_unit, '(A)') "set ylabel 'Re'"
      write (io_unit, '(A)') "set yrange ["//trim(re_min_text)//":"//trim(re_max_text)//"]"
      write (io_unit, '(A)') "plot '"//trim(data_file)//"' every ::"//trim(start_text)//"::"//trim(end_text)// &
         " using 0:1 with lines lw 1 lc rgb '#1f77b4'"
      write (io_unit, '(A)') "set ylabel 'Im'"
      write (io_unit, '(A)') "set yrange ["//trim(im_min_text)//":"//trim(im_max_text)//"]"
      write (io_unit, '(A)') "plot '"//trim(data_file)//"' every ::"//trim(start_text)//"::"//trim(end_text)// &
         " using 0:2 with lines lw 1 lc rgb '#d62728'"
      write (io_unit, '(A)') "unset multiplot"
      write (io_unit, '(A)') "unset output"
      close (io_unit)
   end subroutine write_virial_plot_script

   subroutine compute_plot_window_ranges(values, re_min, re_max, im_min, im_max)
      complex(dp), intent(in) :: values(:)
      real(dp), intent(out) :: re_min, re_max, im_min, im_max

      integer :: n_values, idx_low, idx_high
      real(dp) :: pad
      real(dp), allocatable :: re_values(:), im_values(:)

      n_values = size(values)
      if (n_values < 1) then
         re_min = -1.0_dp
         re_max = 1.0_dp
         im_min = -1.0_dp
         im_max = 1.0_dp
         return
      end if

      allocate (re_values(n_values), im_values(n_values))
      re_values = real(values, dp)
      im_values = aimag(values)
      call sort_real_inplace(re_values)
      call sort_real_inplace(im_values)

      idx_low = max(1, int(0.05_dp*real(n_values - 1, dp)) + 1)
      idx_high = min(n_values, max(idx_low, int(0.95_dp*real(n_values - 1, dp)) + 1))

      re_min = re_values(idx_low)
      re_max = re_values(idx_high)
      im_min = im_values(idx_low)
      im_max = im_values(idx_high)

      if (re_max <= re_min) then
         re_min = minval(re_values)
         re_max = maxval(re_values)
      end if
      if (im_max <= im_min) then
         im_min = minval(im_values)
         im_max = maxval(im_values)
      end if

      if (re_max > re_min) then
         pad = 0.05_dp*(re_max - re_min)
         re_min = re_min - pad
         re_max = re_max + pad
      else
         pad = max(1.0e-12_dp, 0.05_dp*max(abs(re_min), 1.0_dp))
         re_min = re_min - pad
         re_max = re_max + pad
      end if

      if (im_max > im_min) then
         pad = 0.05_dp*(im_max - im_min)
         im_min = im_min - pad
         im_max = im_max + pad
      else
         pad = max(1.0e-12_dp, 0.05_dp*max(abs(im_min), 1.0_dp))
         im_min = im_min - pad
         im_max = im_max + pad
      end if

      deallocate (re_values, im_values)
   end subroutine compute_plot_window_ranges

   subroutine build_jackknife_bin_sizes(n_samples_local, bin_sizes)
      integer, intent(in) :: n_samples_local
      integer, allocatable, intent(out) :: bin_sizes(:)

      integer, parameter :: min_blocks = 8
      real(dp), parameter :: growth = 1.001_dp
      integer :: max_bin, n_dense, n_log, idx, bin_size
      real(dp) :: candidate_real

      if (n_samples_local < 1) then
         allocate (bin_sizes(1))
         bin_sizes(1) = 1
         return
      end if

      max_bin = max(1, n_samples_local/min_blocks)
      n_dense = min(max_bin, 256)
      n_log = 0
      if (max_bin > n_dense) then
         candidate_real = real(n_dense, dp)
         do
            candidate_real = candidate_real*growth
            bin_size = int(candidate_real + 0.5_dp)
            if (bin_size <= n_dense + n_log) bin_size = n_dense + n_log + 1
            if (bin_size > max_bin) exit
            n_log = n_log + 1
         end do
      end if

      allocate (bin_sizes(n_dense + n_log))
      do idx = 1, n_dense
         bin_sizes(idx) = idx
      end do
      if (n_log > 0) then
         candidate_real = real(n_dense, dp)
         do idx = 1, n_log
            candidate_real = candidate_real*growth
            bin_size = int(candidate_real + 0.5_dp)
            if (bin_size <= bin_sizes(n_dense + idx - 1)) bin_size = bin_sizes(n_dense + idx - 1) + 1
            bin_sizes(n_dense + idx) = min(max_bin, bin_size)
         end do
      end if
   end subroutine build_jackknife_bin_sizes

   subroutine compute_jackknife_error_curve(num_data, den_data, bin_sizes, err_re, err_im, err_abs)
      complex(dp), intent(in) :: num_data(:), den_data(:)
      integer, intent(in) :: bin_sizes(:)
      real(dp), intent(out) :: err_re(:), err_im(:), err_abs(:)

      integer :: bin_idx, block_idx, block_size_local, n_data, n_blocks, n_used, sample_idx
      integer :: start_idx, end_idx
      real(dp) :: mean_re, mean_im, jk_prefactor
      real(dp) :: ratio_re, ratio_im, delta_re, delta_im, m2_re, m2_im
      complex(dp) :: total_num, total_den, block_num, block_den, leave_ratio
      complex(dp), allocatable :: prefix_num(:), prefix_den(:)

      if (size(err_re) /= size(bin_sizes) .or. size(err_im) /= size(bin_sizes) .or. size(err_abs) /= size(bin_sizes)) then
         write (*, '(A)') "[ERROR] Jackknife output size mismatch."
         error stop 1
      end if

      n_data = size(num_data)
      if (size(den_data) /= n_data) then
         write (*, '(A)') "[ERROR] Jackknife num/den size mismatch."
         error stop 1
      end if

      allocate (prefix_num(0:n_data), prefix_den(0:n_data))
      prefix_num(0) = cmplx(0.0_dp, 0.0_dp, dp)
      prefix_den(0) = cmplx(0.0_dp, 0.0_dp, dp)
      do sample_idx = 1, n_data
         prefix_num(sample_idx) = prefix_num(sample_idx - 1) + num_data(sample_idx)
         prefix_den(sample_idx) = prefix_den(sample_idx - 1) + den_data(sample_idx)
      end do

      do bin_idx = 1, size(bin_sizes)
         block_size_local = max(1, bin_sizes(bin_idx))
         n_blocks = n_data/block_size_local
         if (n_blocks < 2) then
            err_re(bin_idx) = 0.0_dp
            err_im(bin_idx) = 0.0_dp
            err_abs(bin_idx) = 0.0_dp
            cycle
         end if

         n_used = n_blocks*block_size_local
         total_num = prefix_num(n_used)
         total_den = prefix_den(n_used)
         mean_re = 0.0_dp
         mean_im = 0.0_dp
         m2_re = 0.0_dp
         m2_im = 0.0_dp
         do block_idx = 1, n_blocks
            start_idx = (block_idx - 1)*block_size_local + 1
            end_idx = start_idx + block_size_local - 1
            block_num = prefix_num(end_idx) - prefix_num(start_idx - 1)
            block_den = prefix_den(end_idx) - prefix_den(start_idx - 1)
            if (abs(total_den - block_den) <= tiny(1.0_dp)) then
               leave_ratio = cmplx(0.0_dp, 0.0_dp, dp)
            else
               leave_ratio = (total_num - block_num)/(total_den - block_den)
            end if
            ratio_re = real(leave_ratio, dp)
            ratio_im = aimag(leave_ratio)
            delta_re = ratio_re - mean_re
            mean_re = mean_re + delta_re/real(block_idx, dp)
            m2_re = m2_re + delta_re*(ratio_re - mean_re)
            delta_im = ratio_im - mean_im
            mean_im = mean_im + delta_im/real(block_idx, dp)
            m2_im = m2_im + delta_im*(ratio_im - mean_im)
         end do

         jk_prefactor = real(n_blocks - 1, dp)/real(n_blocks, dp)
         err_re(bin_idx) = sqrt(max(0.0_dp, jk_prefactor*m2_re))
         err_im(bin_idx) = sqrt(max(0.0_dp, jk_prefactor*m2_im))
         err_abs(bin_idx) = sqrt(err_re(bin_idx)*err_re(bin_idx) + err_im(bin_idx)*err_im(bin_idx))
      end do
      deallocate (prefix_num, prefix_den)
   end subroutine compute_jackknife_error_curve

   subroutine compute_jackknife_error_curve_stratified(num_data, den_data, chain_counts, bin_sizes, &
                                                       err_re, err_im, err_abs, n_blocks_by_bin)
      complex(dp), intent(in) :: num_data(:), den_data(:)
      integer, intent(in) :: chain_counts(:), bin_sizes(:)
      real(dp), intent(out) :: err_re(:), err_im(:), err_abs(:)
      integer, intent(out) :: n_blocks_by_bin(:)

      integer :: n_data, n_chains, chain_idx, sample_idx
      integer :: bin_idx, block_size_local, n_blocks_chain, n_blocks_total, block_idx
      integer :: chain_start_idx, block_start_idx, block_end_idx, used_chain_samples, n_seen
      real(dp) :: mean_re, mean_im, ratio_re, ratio_im, delta_re, delta_im
      real(dp) :: m2_re, m2_im, jk_prefactor
      complex(dp) :: total_num, total_den, chain_used_num, chain_used_den
      complex(dp) :: block_num, block_den, leave_ratio
      integer, allocatable :: chain_start_offsets(:)
      complex(dp), allocatable :: prefix_num(:), prefix_den(:)

      if (size(err_re) /= size(bin_sizes) .or. size(err_im) /= size(bin_sizes) .or. size(err_abs) /= size(bin_sizes)) then
         write (*, '(A)') "[ERROR] Stratified jackknife output size mismatch."
         error stop 1
      end if
      if (size(n_blocks_by_bin) /= size(bin_sizes)) then
         write (*, '(A)') "[ERROR] Stratified jackknife n_blocks size mismatch."
         error stop 1
      end if

      n_data = size(num_data)
      if (size(den_data) /= n_data) then
         write (*, '(A)') "[ERROR] Stratified jackknife num/den size mismatch."
         error stop 1
      end if
      n_chains = size(chain_counts)
      if (n_chains < 1) then
         err_re = 0.0_dp
         err_im = 0.0_dp
         err_abs = 0.0_dp
         n_blocks_by_bin = 0
         return
      end if

      allocate (chain_start_offsets(n_chains))
      n_seen = 0
      do chain_idx = 1, n_chains
         chain_start_offsets(chain_idx) = n_seen + 1
         n_seen = n_seen + max(0, chain_counts(chain_idx))
      end do
      if (n_seen /= n_data) then
         write (*, '(A,I0,A,I0)') "[ERROR] Stratified jackknife chain sample mismatch: packed=", n_data, &
            " expected=", n_seen
         error stop 1
      end if

      allocate (prefix_num(0:n_data), prefix_den(0:n_data))
      prefix_num(0) = cmplx(0.0_dp, 0.0_dp, dp)
      prefix_den(0) = cmplx(0.0_dp, 0.0_dp, dp)
      do sample_idx = 1, n_data
         prefix_num(sample_idx) = prefix_num(sample_idx - 1) + num_data(sample_idx)
         prefix_den(sample_idx) = prefix_den(sample_idx - 1) + den_data(sample_idx)
      end do

      do bin_idx = 1, size(bin_sizes)
         block_size_local = max(1, bin_sizes(bin_idx))
         total_num = cmplx(0.0_dp, 0.0_dp, dp)
         total_den = cmplx(0.0_dp, 0.0_dp, dp)
         n_blocks_total = 0

         do chain_idx = 1, n_chains
            n_blocks_chain = max(0, chain_counts(chain_idx))/block_size_local
            n_blocks_total = n_blocks_total + n_blocks_chain
            if (n_blocks_chain < 1) cycle
            chain_start_idx = chain_start_offsets(chain_idx)
            used_chain_samples = n_blocks_chain*block_size_local
            chain_used_num = prefix_num(chain_start_idx + used_chain_samples - 1) - prefix_num(chain_start_idx - 1)
            chain_used_den = prefix_den(chain_start_idx + used_chain_samples - 1) - prefix_den(chain_start_idx - 1)
            total_num = total_num + chain_used_num
            total_den = total_den + chain_used_den
         end do
         n_blocks_by_bin(bin_idx) = n_blocks_total

         if (n_blocks_total < 2) then
            err_re(bin_idx) = 0.0_dp
            err_im(bin_idx) = 0.0_dp
            err_abs(bin_idx) = 0.0_dp
            cycle
         end if

         mean_re = 0.0_dp
         mean_im = 0.0_dp
         m2_re = 0.0_dp
         m2_im = 0.0_dp
         block_idx = 0
         do chain_idx = 1, n_chains
            n_blocks_chain = max(0, chain_counts(chain_idx))/block_size_local
            if (n_blocks_chain < 1) cycle
            chain_start_idx = chain_start_offsets(chain_idx)
            do sample_idx = 1, n_blocks_chain
               block_idx = block_idx + 1
               block_start_idx = chain_start_idx + (sample_idx - 1)*block_size_local
               block_end_idx = block_start_idx + block_size_local - 1
               block_num = prefix_num(block_end_idx) - prefix_num(block_start_idx - 1)
               block_den = prefix_den(block_end_idx) - prefix_den(block_start_idx - 1)
               if (abs(total_den - block_den) <= tiny(1.0_dp)) then
                  leave_ratio = cmplx(0.0_dp, 0.0_dp, dp)
               else
                  leave_ratio = (total_num - block_num)/(total_den - block_den)
               end if
               ratio_re = real(leave_ratio, dp)
               ratio_im = aimag(leave_ratio)
               delta_re = ratio_re - mean_re
               mean_re = mean_re + delta_re/real(block_idx, dp)
               m2_re = m2_re + delta_re*(ratio_re - mean_re)
               delta_im = ratio_im - mean_im
               mean_im = mean_im + delta_im/real(block_idx, dp)
               m2_im = m2_im + delta_im*(ratio_im - mean_im)
            end do
         end do

         jk_prefactor = real(n_blocks_total - 1, dp)/real(n_blocks_total, dp)
         err_re(bin_idx) = sqrt(max(0.0_dp, jk_prefactor*m2_re))
         err_im(bin_idx) = sqrt(max(0.0_dp, jk_prefactor*m2_im))
         err_abs(bin_idx) = sqrt(err_re(bin_idx)*err_re(bin_idx) + err_im(bin_idx)*err_im(bin_idx))
      end do

      deallocate (prefix_num, prefix_den, chain_start_offsets)
   end subroutine compute_jackknife_error_curve_stratified

   subroutine estimate_jackknife_plateau_and_tau(err_re, err_im, bin_sizes, n_samples_local, &
                                                 min_blocks_reliable, min_bin_size_reliable, &
                                                 plateau_re, plateau_im, onset_re, onset_im, &
                                                 onset_re_low, onset_re_high, onset_im_low, onset_im_high, &
                                                 tau_var_re, tau_var_im, tau_onset_re, tau_onset_im, &
                                                 tau_eff_re, tau_eff_im)
      real(dp), intent(in) :: err_re(:), err_im(:)
      integer, intent(in) :: bin_sizes(:), n_samples_local
      integer, intent(in) :: min_blocks_reliable, min_bin_size_reliable
      real(dp), intent(out) :: plateau_re, plateau_im, onset_re, onset_im
      real(dp), intent(out) :: onset_re_low, onset_re_high, onset_im_low, onset_im_high
      real(dp), intent(out) :: tau_var_re, tau_var_im, tau_onset_re, tau_onset_im, tau_eff_re, tau_eff_im

      call analyze_jackknife_component(err_re, bin_sizes, n_samples_local, min_blocks_reliable, min_bin_size_reliable, &
                                       plateau_re, onset_re, onset_re_low, onset_re_high, tau_var_re, tau_onset_re, tau_eff_re)
      call analyze_jackknife_component(err_im, bin_sizes, n_samples_local, min_blocks_reliable, min_bin_size_reliable, &
                                       plateau_im, onset_im, onset_im_low, onset_im_high, tau_var_im, tau_onset_im, tau_eff_im)
   end subroutine estimate_jackknife_plateau_and_tau

   subroutine analyze_jackknife_component(err_values, bin_sizes, n_samples_local, min_blocks_reliable, min_bin_size_reliable, &
                                          plateau_value, onset_value, onset_low, onset_high, tau_var_value, tau_onset_value, &
                                          tau_eff_value, n_blocks_by_bin)
      real(dp), intent(in) :: err_values(:)
      integer, intent(in) :: bin_sizes(:), n_samples_local
      integer, intent(in) :: min_blocks_reliable, min_bin_size_reliable
      real(dp), intent(out) :: plateau_value, onset_value, onset_low, onset_high
      real(dp), intent(out) :: tau_var_value, tau_onset_value, tau_eff_value
      integer, intent(in), optional :: n_blocks_by_bin(:)

      real(dp), parameter :: level_tol_log = 0.08_dp
      real(dp), parameter :: mad_tol = 0.12_dp
      real(dp), parameter :: slope_tol = 0.06_dp

      integer :: n_values, idx, first_valid, last_valid, n_valid, n_tail, tail_start
      integer :: n_blocks_local, window_len, n_windows
      integer :: run_start, run_end, base_count
      real(dp) :: med_seg, rel_mad, slope_seg, baseline_value
      logical, allocatable :: stable_window(:)

      n_values = size(err_values)
      plateau_value = 0.0_dp
      onset_value = -1.0_dp
      onset_low = -1.0_dp
      onset_high = -1.0_dp
      tau_var_value = 1.0_dp
      tau_onset_value = -1.0_dp
      tau_eff_value = 1.0_dp

      if (size(bin_sizes) /= n_values .or. n_values < 1) return
      if (present(n_blocks_by_bin)) then
         if (size(n_blocks_by_bin) /= n_values) then
            write (*, '(A)') "[ERROR] Jackknife n_blocks_by_bin size mismatch."
            error stop 1
         end if
      end if

      first_valid = 0
      last_valid = 0
      do idx = 1, n_values
         if (present(n_blocks_by_bin)) then
            n_blocks_local = n_blocks_by_bin(idx)
         else
            n_blocks_local = n_samples_local/max(1, bin_sizes(idx))
         end if
         if (n_blocks_local >= min_blocks_reliable .and. bin_sizes(idx) >= min_bin_size_reliable) then
            if (first_valid == 0) first_valid = idx
            last_valid = idx
         end if
      end do
      if (first_valid == 0) then
         first_valid = 1
         last_valid = n_values
      end if

      n_valid = last_valid - first_valid + 1
      if (n_valid < 1) return

      n_tail = min(n_valid, max(10, n_valid/8))
      tail_start = last_valid - n_tail + 1
      plateau_value = sample_median_real(err_values(tail_start:last_valid))
      if (plateau_value <= tiny(1.0_dp)) return

      base_count = min(8, max(3, n_valid/16))
      baseline_value = sample_median_real(err_values(first_valid:first_valid + base_count - 1))
      if (baseline_value > tiny(1.0_dp)) then
         tau_var_value = 0.5_dp*(plateau_value/baseline_value)**2
         tau_var_value = max(1.0_dp, tau_var_value)
      end if
      tau_eff_value = tau_var_value

      window_len = min(40, max(12, n_valid/25))
      n_windows = n_valid - window_len + 1
      if (n_windows < 1) return

      allocate (stable_window(n_windows))
      stable_window = .false.
      do idx = 1, n_windows
         call window_median_and_rel_mad(err_values(first_valid + idx - 1:first_valid + idx + window_len - 2), med_seg, rel_mad)
         if (med_seg <= tiny(1.0_dp)) cycle
         slope_seg = theil_sen_loglog_slope(bin_sizes(first_valid + idx - 1:first_valid + idx + window_len - 2), &
                                            err_values(first_valid + idx - 1:first_valid + idx + window_len - 2))
         if (slope_seg >= huge(1.0_dp)/10.0_dp) cycle
         if (abs(log(med_seg/plateau_value)) <= level_tol_log .and. rel_mad <= mad_tol .and. abs(slope_seg) <= slope_tol) then
            stable_window(idx) = .true.
         end if
      end do

      call find_tail_anchored_stable_run(stable_window, max(3, window_len/4), run_start, run_end)
      if (run_start > 0 .and. run_end >= run_start) then
         onset_low = real(bin_sizes(first_valid + run_start - 1), dp)
         onset_high = real(bin_sizes(first_valid + run_end - 1), dp)
         onset_value = onset_low
         tau_onset_value = 0.5_dp*onset_value
         tau_eff_value = max(tau_var_value, tau_onset_value)
      end if
      if (onset_value <= 0.0_dp) then
         do idx = first_valid, last_valid
            if (err_values(idx) <= tiny(1.0_dp)) cycle
            if (abs(log(err_values(idx)/plateau_value)) <= 2.0_dp*level_tol_log) then
               onset_value = real(bin_sizes(idx), dp)
               onset_low = onset_value
               onset_high = onset_value
               tau_onset_value = 0.5_dp*onset_value
               tau_eff_value = max(tau_var_value, tau_onset_value)
               exit
            end if
         end do
      end if
      deallocate (stable_window)
   end subroutine analyze_jackknife_component

   subroutine save_jackknife_curve(file_path, n_samples_local, bin_sizes, err_re, err_im, err_abs, n_blocks_override)
      character(len=*), intent(in) :: file_path
      integer, intent(in) :: n_samples_local
      integer, intent(in) :: bin_sizes(:)
      real(dp), intent(in) :: err_re(:), err_im(:), err_abs(:)
      integer, intent(in), optional :: n_blocks_override(:)
      integer :: io_unit, io_status, idx
      integer :: n_blocks

      if (size(err_re) /= size(bin_sizes) .or. size(err_im) /= size(bin_sizes) .or. size(err_abs) /= size(bin_sizes)) then
         write (*, '(A)') "[ERROR] Jackknife save size mismatch."
         error stop 1
      end if
      if (present(n_blocks_override)) then
         if (size(n_blocks_override) /= size(bin_sizes)) then
            write (*, '(A)') "[ERROR] Jackknife n_blocks override size mismatch."
            error stop 1
         end if
      end if

      io_unit = 32
      open (io_unit, file=file_path, status='replace', action='write', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Failed to open jackknife output file:", trim(file_path)
         error stop 1
      end if

      write (io_unit, '(A)') "# method: delete-1 block jackknife on ratio estimator"
      write (io_unit, '(A)') "# estimator per bin size: theta_(i) = (sum_num - block_num_i)/(sum_den - block_den_i)"
      write (io_unit, '(A)') "# bin_size  err_re  err_im  err_abs  n_blocks"
      do idx = 1, size(bin_sizes)
         if (present(n_blocks_override)) then
            n_blocks = max(0, n_blocks_override(idx))
         else
            n_blocks = max(1, n_samples_local/max(1, bin_sizes(idx)))
         end if
         write (io_unit, '(I10,1X,3ES24.14,1X,I10)') bin_sizes(idx), err_re(idx), err_im(idx), err_abs(idx), n_blocks
      end do
      close (io_unit)
   end subroutine save_jackknife_curve

   subroutine save_jackknife_metadata(file_path, n_samples_local, min_blocks_reliable, min_bin_size_reliable, &
                                      plateau_re, plateau_im, onset_re, onset_im, &
                                      onset_re_low, onset_re_high, onset_im_low, onset_im_high, &
                                      tau_var_re, tau_var_im, tau_onset_re, tau_onset_im, tau_eff_re, tau_eff_im, &
                                      direct_tau_ips_re, direct_tau_ips_im, direct_tau_ics_re, direct_tau_ics_im, &
                                      direct_tau_obm_re, direct_tau_obm_im, direct_tau_robust_re, direct_tau_robust_im, &
                                      tau_ratio_re, tau_ratio_im, tau_upper_re, tau_upper_im, &
                                      phase_coherence, phase_eff_n, phase_min_effective, &
                                      split_plateau_rel_re, split_plateau_rel_im, split_onset_ratio_re, split_onset_ratio_im, &
                                      split_ok_re, split_ok_im, &
                                      diag_observable_name, obs_rhat_re, obs_rhat_im, obs_ess_bulk_re, obs_ess_bulk_im, &
                                      obs_ess_tail_re, obs_ess_tail_im, obs_mcse_mean_re, obs_mcse_mean_im)
      character(len=*), intent(in) :: file_path
      integer, intent(in) :: n_samples_local
      integer, intent(in) :: min_blocks_reliable, min_bin_size_reliable
      real(dp), intent(in) :: plateau_re, plateau_im, onset_re, onset_im
      real(dp), intent(in) :: onset_re_low, onset_re_high, onset_im_low, onset_im_high
      real(dp), intent(in) :: tau_var_re, tau_var_im, tau_onset_re, tau_onset_im, tau_eff_re, tau_eff_im
      real(dp), intent(in) :: direct_tau_ips_re, direct_tau_ips_im
      real(dp), intent(in) :: direct_tau_ics_re, direct_tau_ics_im
      real(dp), intent(in) :: direct_tau_obm_re, direct_tau_obm_im
      real(dp), intent(in) :: direct_tau_robust_re, direct_tau_robust_im
      real(dp), intent(in) :: tau_ratio_re, tau_ratio_im
      real(dp), intent(in) :: tau_upper_re, tau_upper_im
      real(dp), intent(in) :: phase_coherence, phase_eff_n, phase_min_effective
      real(dp), intent(in) :: split_plateau_rel_re, split_plateau_rel_im
      real(dp), intent(in) :: split_onset_ratio_re, split_onset_ratio_im
      logical, intent(in) :: split_ok_re, split_ok_im
      character(len=*), intent(in) :: diag_observable_name
      real(dp), intent(in) :: obs_rhat_re, obs_rhat_im
      real(dp), intent(in) :: obs_ess_bulk_re, obs_ess_bulk_im
      real(dp), intent(in) :: obs_ess_tail_re, obs_ess_tail_im
      real(dp), intent(in) :: obs_mcse_mean_re, obs_mcse_mean_im

      integer :: io_unit, io_status

      io_unit = 34
      open (io_unit, file=file_path, status='replace', action='write', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Failed to open jackknife metadata file:", trim(file_path)
         error stop 1
      end if

      write (io_unit, '(A)') "# jackknife metadata"
      write (io_unit, '(A,I0)') "samples=", n_samples_local
      write (io_unit, '(A,I0)') "min_blocks_reliable=", min_blocks_reliable
      write (io_unit, '(A,I0)') "min_bin_reliable=", min_bin_size_reliable
      write (io_unit, '(A,ES18.10)') "plateau_re=", plateau_re
      write (io_unit, '(A,ES18.10)') "plateau_im=", plateau_im
      write (io_unit, '(A,F10.3)') "onset_re=", onset_re
      write (io_unit, '(A,F10.3)') "onset_im=", onset_im
      write (io_unit, '(A,F10.3)') "onset_re_low=", onset_re_low
      write (io_unit, '(A,F10.3)') "onset_re_high=", onset_re_high
      write (io_unit, '(A,F10.3)') "onset_im_low=", onset_im_low
      write (io_unit, '(A,F10.3)') "onset_im_high=", onset_im_high
      write (io_unit, '(A,ES18.10)') "tau_var_re=", tau_var_re
      write (io_unit, '(A,ES18.10)') "tau_var_im=", tau_var_im
      write (io_unit, '(A,ES18.10)') "tau_onset_re=", tau_onset_re
      write (io_unit, '(A,ES18.10)') "tau_onset_im=", tau_onset_im
      write (io_unit, '(A,ES18.10)') "tau_eff_re=", tau_eff_re
      write (io_unit, '(A,ES18.10)') "tau_eff_im=", tau_eff_im
      write (io_unit, '(A,ES18.10)') "direct_tau_ips_re=", direct_tau_ips_re
      write (io_unit, '(A,ES18.10)') "direct_tau_ips_im=", direct_tau_ips_im
      write (io_unit, '(A,ES18.10)') "direct_tau_ics_re=", direct_tau_ics_re
      write (io_unit, '(A,ES18.10)') "direct_tau_ics_im=", direct_tau_ics_im
      write (io_unit, '(A,ES18.10)') "direct_tau_obm_re=", direct_tau_obm_re
      write (io_unit, '(A,ES18.10)') "direct_tau_obm_im=", direct_tau_obm_im
      write (io_unit, '(A,ES18.10)') "direct_tau_robust_re=", direct_tau_robust_re
      write (io_unit, '(A,ES18.10)') "direct_tau_robust_im=", direct_tau_robust_im
      write (io_unit, '(A,ES18.10)') "tau_ratio_robust_jk_re=", tau_ratio_re
      write (io_unit, '(A,ES18.10)') "tau_ratio_robust_jk_im=", tau_ratio_im
      write (io_unit, '(A,ES18.10)') "tau_upper_re=", tau_upper_re
      write (io_unit, '(A,ES18.10)') "tau_upper_im=", tau_upper_im
      write (io_unit, '(A,ES18.10)') "phase_coherence=", phase_coherence
      write (io_unit, '(A,ES18.10)') "phase_eff_n=", phase_eff_n
      write (io_unit, '(A,ES18.10)') "phase_min_effective=", phase_min_effective
      write (io_unit, '(A,F14.6)') "split_plateau_rel_re=", split_plateau_rel_re
      write (io_unit, '(A,F14.6)') "split_plateau_rel_im=", split_plateau_rel_im
      write (io_unit, '(A,F14.6)') "split_onset_ratio_re=", split_onset_ratio_re
      write (io_unit, '(A,F14.6)') "split_onset_ratio_im=", split_onset_ratio_im
      write (io_unit, '(A,L1)') "split_ok_re=", split_ok_re
      write (io_unit, '(A,L1)') "split_ok_im=", split_ok_im
      write (io_unit, '(A,A)') "diag_observable_name=", trim(diag_observable_name)
      write (io_unit, '(A,F12.6)') "obs_split_rhat_re=", obs_rhat_re
      write (io_unit, '(A,F12.6)') "obs_split_rhat_im=", obs_rhat_im
      write (io_unit, '(A,ES18.10)') "obs_ess_bulk_re=", obs_ess_bulk_re
      write (io_unit, '(A,ES18.10)') "obs_ess_bulk_im=", obs_ess_bulk_im
      write (io_unit, '(A,ES18.10)') "obs_ess_tail_re=", obs_ess_tail_re
      write (io_unit, '(A,ES18.10)') "obs_ess_tail_im=", obs_ess_tail_im
      write (io_unit, '(A,ES18.10)') "obs_mcse_mean_re=", obs_mcse_mean_re
      write (io_unit, '(A,ES18.10)') "obs_mcse_mean_im=", obs_mcse_mean_im
      close (io_unit)
   end subroutine save_jackknife_metadata

   subroutine write_jackknife_plot_script(script_file, data_file, image_file, plateau_re, plateau_im, onset_re, onset_im, &
                                          onset_re_low, onset_re_high, onset_im_low, onset_im_high, tau_re, tau_im, &
                                          min_blocks_reliable, min_bin_size_plot)
      character(len=*), intent(in) :: script_file, data_file, image_file
      real(dp), intent(in) :: plateau_re, plateau_im, onset_re, onset_im
      real(dp), intent(in) :: onset_re_low, onset_re_high, onset_im_low, onset_im_high
      real(dp), intent(in) :: tau_re, tau_im
      integer, intent(in) :: min_blocks_reliable, min_bin_size_plot
      integer :: io_unit, io_status
      character(len=32) :: plateau_re_text, plateau_im_text, onset_re_text, onset_im_text, min_blocks_text, min_bin_text
      character(len=64) :: onset_re_range_text, onset_im_range_text, tau_re_text, tau_im_text
      character(len=16) :: min_blocks_expr, min_bin_expr

      io_unit = 33
      open (io_unit, file=script_file, status='replace', action='write', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Failed to open jackknife plot script output:", trim(script_file)
         error stop 1
      end if

      write (plateau_re_text, '(ES14.6E3)') plateau_re
      write (plateau_im_text, '(ES14.6E3)') plateau_im
      write (tau_re_text, '(F8.2)') tau_re
      write (tau_im_text, '(F8.2)') tau_im
      if (onset_re > 0.0_dp) then
         write (onset_re_text, '(F8.1)') onset_re
         write (onset_re_range_text, '(A,F8.1,A,F8.1,A)') "[", onset_re_low, ",", onset_re_high, "]"
      else
         onset_re_text = "N/A"
         onset_re_range_text = "N/A"
      end if
      if (onset_im > 0.0_dp) then
         write (onset_im_text, '(F8.1)') onset_im
         write (onset_im_range_text, '(A,F8.1,A,F8.1,A)') "[", onset_im_low, ",", onset_im_high, "]"
      else
         onset_im_text = "N/A"
         onset_im_range_text = "N/A"
      end if
      write (min_blocks_text, '(I0)') min_blocks_reliable
      write (min_bin_text, '(I0)') min_bin_size_plot
      min_blocks_expr = trim(min_blocks_text)
      min_bin_expr = trim(min_bin_text)

      write (io_unit, '(A)') "set terminal pngcairo size 3600,2400 enhanced font 'Helvetica,24'"
      write (io_unit, '(A)') "set output '"//trim(image_file)//"'"
      write (io_unit, '(A)') "set logscale x 2"
      write (io_unit, '(A)') "set grid"
      write (io_unit, '(A)') "set key left top"
      write (io_unit, '(A)') "set multiplot layout 2,1 rowsfirst title 'Binned Jackknife Error vs Bin Size (bin>=" // &
         trim(min_bin_expr) // ", n_blocks>=" // trim(min_blocks_expr) // ")'"
      write (io_unit, '(A)') "set xlabel 'Bin size'"
      write (io_unit, '(A)') "set ylabel 'Re error'"
      write (io_unit, '(A)') "set title 'Re: plateau="//trim(plateau_re_text)//"  onset~"//trim(adjustl(onset_re_text))// &
         "  range="//trim(adjustl(onset_re_range_text))//"  tau~"//trim(adjustl(tau_re_text))//"'"
      write (io_unit, '(A)') "plot '" // trim(data_file) // "' using (($1>=" // trim(min_bin_expr) // " && $5>=" // &
         trim(min_blocks_expr) // ")?$1:1/0):" // &
         "(($1>=" // trim(min_bin_expr) // " && $5>=" // trim(min_blocks_expr) // ")?$2:1/0) with linespoints lw 2 pt 7 ps 0.9 lc rgb '#1f77b4' title 'Re error'," // &
         trim(plateau_re_text)//" with lines dt 2 lw 2 lc rgb '#555555' title 'Re plateau'"
      write (io_unit, '(A)') "set ylabel 'Im error'"
      write (io_unit, '(A)') "set title 'Im: plateau="//trim(plateau_im_text)//"  onset~"//trim(adjustl(onset_im_text))// &
         "  range="//trim(adjustl(onset_im_range_text))//"  tau~"//trim(adjustl(tau_im_text))//"'"
      write (io_unit, '(A)') "plot '" // trim(data_file) // "' using (($1>=" // trim(min_bin_expr) // " && $5>=" // &
         trim(min_blocks_expr) // ")?$1:1/0):" // &
         "(($1>=" // trim(min_bin_expr) // " && $5>=" // trim(min_blocks_expr) // ")?$3:1/0) with linespoints lw 2 pt 7 ps 0.9 lc rgb '#d62728' title 'Im error'," // &
         trim(plateau_im_text)//" with lines dt 2 lw 2 lc rgb '#555555' title 'Im plateau'"
      write (io_unit, '(A)') "unset multiplot"
      write (io_unit, '(A)') "unset output"
      close (io_unit)
   end subroutine write_jackknife_plot_script

   function observable_from_state(z_state) result(observable)
      complex(dp), intent(in) :: z_state(:)
      complex(dp) :: observable

      if (tra2) then
         call calculate_a2_observable(z_state, observable)
      else
         call calculate_virial_observable(z_state, observable)
      end if
   end function observable_from_state

   subroutine calculate_a2_observable(z_state, observable)
      complex(dp), intent(in) :: z_state(:)
      complex(dp), intent(out) :: observable
      integer :: state_idx

      observable = cmplx(0.0_dp, 0.0_dp, dp)
      do state_idx = 1, size(z_state)
         observable = observable + z_state(state_idx)
      end do
   end subroutine calculate_a2_observable

   subroutine calculate_virial_observable(z_state, observable)
      complex(dp), intent(in) :: z_state(:)
      complex(dp), intent(out) :: observable
      integer :: state_idx
      complex(dp), parameter :: imag_unit = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp) :: z_val

      observable = cmplx(0.0_dp, 0.0_dp, dp)
      do state_idx = 1, size(z_state)
         z_val = z_state(state_idx)
         ! Pole-free virial identity: < -i*(z-i*beta)*(z^2+alpha) - 2 > = 0
         observable = observable - imag_unit*(z_val - imag_unit*beta)*(z_val**2 + alpha) - 2.0_dp
      end do
   end subroutine calculate_virial_observable

   subroutine read_z_history_matrix(file_path, z_samples, sample_count, io_status)
      character(len=*), intent(in) :: file_path
      complex(dp), allocatable, intent(out) :: z_samples(:, :)
      integer, intent(out) :: sample_count, io_status

      integer :: io_unit, file_size_bytes, z_size
      integer, parameter :: complex_bytes = 2*8

      z_size = n_size - 1
      io_unit = 20
      io_status = 0

      open (unit=io_unit, file=file_path, access='stream', form='unformatted', status='old', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Cannot open z-history file:", trim(file_path)
         return
      end if

      inquire (unit=io_unit, size=file_size_bytes)
      if (mod(file_size_bytes, z_size*complex_bytes) /= 0) then
         write (*, '(A)') "[ERROR] z-history file size is not divisible by z vector size."
         io_status = 1
         close (io_unit)
         return
      end if

      sample_count = file_size_bytes/(z_size*complex_bytes)
      allocate (z_samples(z_size, sample_count), stat=io_status)
      if (io_status /= 0) then
         write (*, '(A)') "[ERROR] Allocation failed for z-history matrix."
         close (io_unit)
         return
      end if

      read (io_unit, iostat=io_status) z_samples
      close (io_unit)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Failed while reading z-history:", trim(file_path)
      end if
   end subroutine read_z_history_matrix

   subroutine read_phi_history_vector(file_path, phi_samples, sample_count, io_status)
      character(len=*), intent(in) :: file_path
      complex(dp), allocatable, intent(out) :: phi_samples(:)
      integer, intent(out) :: sample_count, io_status

      integer :: io_unit, file_size_bytes
      integer, parameter :: complex_bytes = 2*8

      io_unit = 21
      io_status = 0

      open (unit=io_unit, file=file_path, access='stream', form='unformatted', status='old', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Cannot open phi-history file:", trim(file_path)
         return
      end if

      inquire (unit=io_unit, size=file_size_bytes)
      if (mod(file_size_bytes, complex_bytes) /= 0) then
         write (*, '(A)') "[ERROR] phi-history file size is not divisible by element size."
         io_status = 1
         close (io_unit)
         return
      end if

      sample_count = file_size_bytes/complex_bytes
      allocate (phi_samples(sample_count), stat=io_status)
      if (io_status /= 0) then
         write (*, '(A)') "[ERROR] Allocation failed for phi-history vector."
         close (io_unit)
         return
      end if

      read (io_unit, iostat=io_status) phi_samples
      close (io_unit)
      if (io_status /= 0) then
         if (allocated(phi_samples)) deallocate (phi_samples)
         write (*, '(A,1X,A)') "[ERROR] Failed while reading phi-history:", trim(file_path)
      end if
   end subroutine read_phi_history_vector

   subroutine save_complex_series(file_path, values)
      character(len=*), intent(in) :: file_path
      complex(dp), intent(in) :: values(:)
      integer :: io_unit, value_idx, io_status

      io_unit = 30
      open (io_unit, file=file_path, status='replace', action='write', iostat=io_status)
      if (io_status /= 0) then
         write (*, '(A,1X,A)') "[ERROR] Failed to open output file:", trim(file_path)
         error stop 1
      end if
      do value_idx = 1, size(values)
         write (io_unit, '(2ES24.14)') real(values(value_idx), dp), aimag(values(value_idx))
      end do
      close (io_unit)
   end subroutine save_complex_series

   subroutine ratio_block_bootstrap(num_data, den_data, n_boot, block_size, ratio_mean, ratio_err_real, ratio_err_imag, &
                                    ratio_ci_real_low, ratio_ci_real_high, ratio_ci_imag_low, ratio_ci_imag_high)
      integer, intent(in) :: n_boot, block_size
      complex(dp), intent(in) :: num_data(:), den_data(:)
      complex(dp), intent(out) :: ratio_mean
      real(dp), intent(out) :: ratio_err_real, ratio_err_imag
      real(dp), intent(out) :: ratio_ci_real_low, ratio_ci_real_high
      real(dp), intent(out) :: ratio_ci_imag_low, ratio_ci_imag_high

      integer :: block_idx, sample_idx, n_data, n_blocks, start_idx, end_idx
      integer :: idx_low, idx_high
      real(dp) :: random_u
      real(dp) :: mean_real, mean_imag, m2_real, m2_imag, delta_real, delta_imag
      real(dp) :: ratio_real, ratio_imag
      complex(dp) :: sum_num, sum_den, ratio_tmp
      complex(dp), allocatable :: prefix_num(:), prefix_den(:)
      real(dp), allocatable :: real_values(:), imag_values(:)

      n_data = size(num_data)
      n_blocks = n_data/block_size
      if (n_blocks < 1) then
         write (*, '(A)') "[ERROR] block_size is too large for bootstrap resampling."
         error stop 1
      end if

      allocate (real_values(n_boot), imag_values(n_boot), prefix_num(0:n_data), prefix_den(0:n_data))

      prefix_num(0) = cmplx(0.0_dp, 0.0_dp, dp)
      prefix_den(0) = cmplx(0.0_dp, 0.0_dp, dp)
      do sample_idx = 1, n_data
         prefix_num(sample_idx) = prefix_num(sample_idx - 1) + num_data(sample_idx)
         prefix_den(sample_idx) = prefix_den(sample_idx - 1) + den_data(sample_idx)
      end do

      mean_real = 0.0_dp
      mean_imag = 0.0_dp
      m2_real = 0.0_dp
      m2_imag = 0.0_dp

      do sample_idx = 1, n_boot
         sum_num = cmplx(0.0_dp, 0.0_dp, dp)
         sum_den = cmplx(0.0_dp, 0.0_dp, dp)

         do block_idx = 1, n_blocks
            call random_number(random_u)
            start_idx = 1 + int(random_u*real(n_data - block_size + 1, dp))
            end_idx = start_idx + block_size - 1
            sum_num = sum_num + (prefix_num(end_idx) - prefix_num(start_idx - 1))
            sum_den = sum_den + (prefix_den(end_idx) - prefix_den(start_idx - 1))
         end do

         if (abs(sum_den) > 0.0_dp) then
            ratio_tmp = sum_num/sum_den
         else
            ratio_tmp = cmplx(0.0_dp, 0.0_dp, dp)
         end if

         ratio_real = real(ratio_tmp, dp)
         ratio_imag = aimag(ratio_tmp)
         real_values(sample_idx) = ratio_real
         imag_values(sample_idx) = ratio_imag

         delta_real = ratio_real - mean_real
         mean_real = mean_real + delta_real/real(sample_idx, dp)
         m2_real = m2_real + delta_real*(ratio_real - mean_real)

         delta_imag = ratio_imag - mean_imag
         mean_imag = mean_imag + delta_imag/real(sample_idx, dp)
         m2_imag = m2_imag + delta_imag*(ratio_imag - mean_imag)
      end do

      ratio_mean = cmplx(mean_real, mean_imag, dp)

      if (n_boot > 1) then
         ratio_err_real = sqrt(m2_real/real(n_boot - 1, dp))
         ratio_err_imag = sqrt(m2_imag/real(n_boot - 1, dp))
      else
         ratio_err_real = 0.0_dp
         ratio_err_imag = 0.0_dp
      end if

      call sort_real_inplace(real_values)
      call sort_real_inplace(imag_values)

      idx_low = max(1, int(0.16_dp*real(n_boot - 1, dp)) + 1)
      idx_high = min(n_boot, max(idx_low, int(0.84_dp*real(n_boot - 1, dp)) + 1))
      ratio_ci_real_low = real_values(idx_low)
      ratio_ci_real_high = real_values(idx_high)
      ratio_ci_imag_low = imag_values(idx_low)
      ratio_ci_imag_high = imag_values(idx_high)

      deallocate (real_values, imag_values, prefix_num, prefix_den)
   end subroutine ratio_block_bootstrap

   subroutine estimate_autocorrelation_time_auto(observable_samples, tau_int_real, tau_int_imag, tau_int_mode, tau_int_max, &
                                                 poor_mixing_warning)
      complex(dp), intent(in) :: observable_samples(:)
      real(dp), intent(out) :: tau_int_real, tau_int_imag, tau_int_mode, tau_int_max
      logical, intent(out) :: poor_mixing_warning

      integer, parameter :: iat_samples_cap_default = 50000
      integer :: n_samples_local, n_iat_samples, iat_start_idx
      integer :: iat_samples_cap, env_status, env_len, io_status
      real(dp), allocatable :: observable_real(:), observable_imag(:), projected_samples(:)
      real(dp) :: tau_re_acf, tau_re_batch, tau_re_split, tau_re_median
      real(dp) :: tau_im_acf, tau_im_batch, tau_im_split, tau_im_median
      real(dp) :: tau_mode_acf, tau_mode_batch, tau_mode_split, tau_mode_median
      real(dp) :: tau_acf_max, tau_guard_max, t_component_start, t_component_end
      character(len=64) :: env_value

      n_samples_local = size(observable_samples)
      tau_int_real = 1.0_dp
      tau_int_imag = 1.0_dp
      tau_int_mode = 1.0_dp
      tau_int_max = 1.0_dp
      poor_mixing_warning = .false.
      if (n_samples_local < 2) return

      iat_samples_cap = iat_samples_cap_default
      env_value = ""
      call get_environment_variable("EVAL_IAT_SAMPLES_CAP", env_value, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         read (env_value(1:env_len), *, iostat=io_status) iat_samples_cap
         if (io_status /= 0 .or. iat_samples_cap < 2) then
            write (*, '(A)') "[WARN] Invalid EVAL_IAT_SAMPLES_CAP value. Using default 50000."
            iat_samples_cap = iat_samples_cap_default
         end if
      end if

      n_iat_samples = min(n_samples_local, iat_samples_cap)
      iat_start_idx = n_samples_local - n_iat_samples + 1
      if (n_iat_samples < n_samples_local) then
         write (*, '(A,I0,A,I0,A,I0,A,I0,A)') "[INFO] IAT diagnostics capped to tail window: samples ", &
            iat_start_idx, " to ", n_samples_local, " (N_used=", n_iat_samples, ", cap=", iat_samples_cap, ")."
      end if

      allocate (observable_real(n_iat_samples), observable_imag(n_iat_samples), projected_samples(n_iat_samples))
      observable_real = real(observable_samples(iat_start_idx:n_samples_local), dp)
      observable_imag = aimag(observable_samples(iat_start_idx:n_samples_local))
      call compute_principal_projection(observable_real, observable_imag, projected_samples)

      write (*, '(A)') "[PROGRESS] IAT component: Re"
      call cpu_time(t_component_start)
      call estimate_autocorrelation_time_component(observable_real, tau_re_acf, tau_re_batch, tau_re_split, tau_re_median, tau_int_real)
      call cpu_time(t_component_end)
      write (*, '(A,F10.3,A)') "[TIMING] IAT component Re took ", t_component_end - t_component_start, " s"
      write (*, '(A)') "[PROGRESS] IAT component: Im"
      call cpu_time(t_component_start)
      call estimate_autocorrelation_time_component(observable_imag, tau_im_acf, tau_im_batch, tau_im_split, tau_im_median, tau_int_imag)
      call cpu_time(t_component_end)
      write (*, '(A,F10.3,A)') "[TIMING] IAT component Im took ", t_component_end - t_component_start, " s"
      write (*, '(A)') "[PROGRESS] IAT component: Mode projection"
      call cpu_time(t_component_start)
      call estimate_autocorrelation_time_component(projected_samples, tau_mode_acf, tau_mode_batch, tau_mode_split, tau_mode_median, tau_int_mode)
      call cpu_time(t_component_end)
      write (*, '(A,F10.3,A)') "[TIMING] IAT component Mode took ", t_component_end - t_component_start, " s"
      tau_int_max = max(tau_int_mode, max(tau_int_real, tau_int_imag))

      write (*, '(A,5F10.4)') "[IAT] Re(acf,batch,split,median,used) =", &
         tau_re_acf, tau_re_batch, tau_re_split, tau_re_median, tau_int_real
      write (*, '(A,5F10.4)') "[IAT] Im(acf,batch,split,median,used) =", &
         tau_im_acf, tau_im_batch, tau_im_split, tau_im_median, tau_int_imag
      write (*, '(A,5F10.4)') "[IAT] ModeProj(acf,batch,split,median,used) =", &
         tau_mode_acf, tau_mode_batch, tau_mode_split, tau_mode_median, tau_int_mode

      tau_acf_max = max(tau_mode_acf, max(tau_re_acf, tau_im_acf))
      tau_guard_max = max(tau_mode_median, max(tau_mode_split, max(tau_mode_batch, &
         max(tau_re_median, max(tau_re_split, max(tau_re_batch, max(tau_im_median, max(tau_im_split, tau_im_batch))))))))
      poor_mixing_warning = (tau_guard_max > 1.5_dp*max(1.0_dp, tau_acf_max)) .or. &
                            (tau_int_max > 0.10_dp*real(n_iat_samples, dp))

      deallocate (observable_real, observable_imag, projected_samples)
   end subroutine estimate_autocorrelation_time_auto

   subroutine estimate_autocorrelation_time_component(observable_samples, tau_acf, tau_batch, tau_split, tau_median, tau_used)
      real(dp), intent(in) :: observable_samples(:)
      real(dp), intent(out) :: tau_acf, tau_batch, tau_split, tau_median, tau_used

      integer :: n_samples_local
      real(dp), allocatable :: median_indicator(:)

      n_samples_local = size(observable_samples)
      tau_acf = 1.0_dp
      tau_batch = 1.0_dp
      tau_split = 1.0_dp
      tau_median = 1.0_dp
      tau_used = 1.0_dp
      if (n_samples_local < 2) return

      call estimate_autocorrelation_time_windowed(observable_samples, tau_acf)
      call estimate_tau_batchmeans(observable_samples, tau_batch)
      call estimate_tau_split_guard(observable_samples, tau_split)
      allocate (median_indicator(n_samples_local))
      call build_median_indicator(observable_samples, median_indicator)
      if (n_samples_local > 200000) then
         ! For very long chains, use split-guard on the median indicator to avoid a second O(N*lag) ACF pass.
         call estimate_tau_split_guard(median_indicator, tau_median)
      else
         call estimate_autocorrelation_time_windowed(median_indicator, tau_median)
      end if
      deallocate (median_indicator)

      tau_used = max(tau_acf, max(tau_batch, max(tau_split, tau_median)))
      tau_used = max(1.0_dp, min(0.5_dp*real(n_samples_local, dp), tau_used))
   end subroutine estimate_autocorrelation_time_component

   subroutine estimate_state_mixing_time(z_samples, tau_state, mixing_mode)
      complex(dp), intent(in) :: z_samples(:, :)
      real(dp), intent(out) :: tau_state
      integer, intent(in) :: mixing_mode

      integer :: n_dims, n_samples_local, dim_idx
      real(dp), allocatable :: real_series(:), imag_series(:)
      real(dp) :: tau_acf, tau_batch, tau_split, tau_median, tau_used

      n_dims = size(z_samples, 1)
      n_samples_local = size(z_samples, 2)
      tau_state = 1.0_dp
      if (n_dims < 1 .or. n_samples_local < 2) return

      allocate (real_series(n_samples_local), imag_series(n_samples_local))
      do dim_idx = 1, n_dims
         select case (mixing_mode)
         case (1)
            real_series = real(z_samples(dim_idx, :), dp)
            imag_series = aimag(z_samples(dim_idx, :))
            call estimate_autocorrelation_time_component(real_series, tau_acf, tau_batch, tau_split, tau_median, tau_used)
            tau_state = max(tau_state, tau_used)
            call estimate_autocorrelation_time_component(imag_series, tau_acf, tau_batch, tau_split, tau_median, tau_used)
            tau_state = max(tau_state, tau_used)
         case (2)
            real_series = abs(z_samples(dim_idx, :))
            call estimate_autocorrelation_time_component(real_series, tau_acf, tau_batch, tau_split, tau_median, tau_used)
            tau_state = max(tau_state, tau_used)
         case default
            write (*, '(A)') "[ERROR] Unsupported state mixing mode."
            error stop 1
         end select
      end do
      deallocate (real_series, imag_series)
   end subroutine estimate_state_mixing_time

   subroutine compute_principal_projection(real_samples, imag_samples, projection_samples)
      real(dp), intent(in) :: real_samples(:), imag_samples(:)
      real(dp), intent(out) :: projection_samples(:)

      integer :: n_samples_local, sample_idx
      real(dp) :: mean_re, mean_im, var_re, var_im, cov_ri
      real(dp) :: d_re, d_im, theta, axis_re, axis_im

      n_samples_local = size(real_samples)
      if (size(imag_samples) /= n_samples_local .or. size(projection_samples) /= n_samples_local) then
         write (*, '(A)') "[ERROR] Principal projection input size mismatch."
         error stop 1
      end if
      if (n_samples_local < 2) then
         projection_samples = real_samples
         return
      end if

      mean_re = sum(real_samples)/real(n_samples_local, dp)
      mean_im = sum(imag_samples)/real(n_samples_local, dp)
      var_re = 0.0_dp
      var_im = 0.0_dp
      cov_ri = 0.0_dp
      do sample_idx = 1, n_samples_local
         d_re = real_samples(sample_idx) - mean_re
         d_im = imag_samples(sample_idx) - mean_im
         var_re = var_re + d_re*d_re
         var_im = var_im + d_im*d_im
         cov_ri = cov_ri + d_re*d_im
      end do
      var_re = var_re/real(n_samples_local - 1, dp)
      var_im = var_im/real(n_samples_local - 1, dp)
      cov_ri = cov_ri/real(n_samples_local - 1, dp)

      if (abs(cov_ri) > tiny(1.0_dp) .or. abs(var_re - var_im) > tiny(1.0_dp)) then
         theta = 0.5_dp*atan2(2.0_dp*cov_ri, var_re - var_im)
         axis_re = cos(theta)
         axis_im = sin(theta)
      else if (var_re >= var_im) then
         axis_re = 1.0_dp
         axis_im = 0.0_dp
      else
         axis_re = 0.0_dp
         axis_im = 1.0_dp
      end if

      projection_samples = axis_re*real_samples + axis_im*imag_samples
   end subroutine compute_principal_projection

   subroutine build_median_indicator(observable_samples, indicator_samples)
      real(dp), intent(in) :: observable_samples(:)
      real(dp), intent(out) :: indicator_samples(:)

      integer :: sample_idx
      real(dp) :: median_value

      if (size(indicator_samples) /= size(observable_samples)) then
         write (*, '(A)') "[ERROR] Median indicator input size mismatch."
         error stop 1
      end if

      median_value = sample_median_real(observable_samples)
      do sample_idx = 1, size(observable_samples)
         if (observable_samples(sample_idx) >= median_value) then
            indicator_samples(sample_idx) = 1.0_dp
         else
            indicator_samples(sample_idx) = -1.0_dp
         end if
      end do
   end subroutine build_median_indicator

   real(dp) function sample_median_real(values) result(median_value)
      real(dp), intent(in) :: values(:)

      integer :: n_values, mid_idx
      real(dp), allocatable :: sorted_values(:)

      n_values = size(values)
      if (n_values <= 0) then
         median_value = 0.0_dp
         return
      end if

      allocate (sorted_values(n_values))
      sorted_values = values
      call sort_real_inplace(sorted_values)
      mid_idx = n_values/2
      if (mod(n_values, 2) == 0) then
         median_value = 0.5_dp*(sorted_values(mid_idx) + sorted_values(mid_idx + 1))
      else
         median_value = sorted_values(mid_idx + 1)
      end if
      deallocate (sorted_values)
   end function sample_median_real

   subroutine compute_observable_mcmc_diagnostics(observable_samples, max_lag_cap, &
                                                  rhat_re, rhat_im, ess_bulk_re, ess_bulk_im, &
                                                  ess_tail_re, ess_tail_im, mcse_mean_re, mcse_mean_im)
      complex(dp), intent(in) :: observable_samples(:)
      integer, intent(in) :: max_lag_cap
      real(dp), intent(out) :: rhat_re, rhat_im, ess_bulk_re, ess_bulk_im
      real(dp), intent(out) :: ess_tail_re, ess_tail_im, mcse_mean_re, mcse_mean_im

      real(dp), allocatable :: re_values(:), im_values(:)
      integer :: n_samples_local

      n_samples_local = size(observable_samples)
      rhat_re = 1.0_dp
      rhat_im = 1.0_dp
      ess_bulk_re = 1.0_dp
      ess_bulk_im = 1.0_dp
      ess_tail_re = 1.0_dp
      ess_tail_im = 1.0_dp
      mcse_mean_re = 0.0_dp
      mcse_mean_im = 0.0_dp
      if (n_samples_local < 2) return

      allocate (re_values(n_samples_local), im_values(n_samples_local))
      re_values = real(observable_samples, dp)
      im_values = aimag(observable_samples)

      call compute_component_mcmc_diagnostics(re_values, max_lag_cap, rhat_re, ess_bulk_re, ess_tail_re, mcse_mean_re)
      call compute_component_mcmc_diagnostics(im_values, max_lag_cap, rhat_im, ess_bulk_im, ess_tail_im, mcse_mean_im)
      deallocate (re_values, im_values)
   end subroutine compute_observable_mcmc_diagnostics

   subroutine compute_component_mcmc_diagnostics(values, max_lag_cap, rhat, ess_bulk, ess_tail, mcse_mean)
      real(dp), intent(in) :: values(:)
      integer, intent(in) :: max_lag_cap
      real(dp), intent(out) :: rhat, ess_bulk, ess_tail, mcse_mean

      integer :: n_values, lag_used_ips, lag_used_ics, idx
      real(dp) :: tau_ips, tau_ics, tau_obm, tau_bulk
      real(dp) :: tau_low_ips, tau_low_ics, tau_low_obm, tau_low
      real(dp) :: tau_high_ips, tau_high_ics, tau_high_obm, tau_high
      real(dp) :: mean_value, var_value, q_low, q_high
      real(dp) :: ess_low, ess_high
      real(dp), allocatable :: indicator_low(:), indicator_high(:)

      n_values = size(values)
      rhat = 1.0_dp
      ess_bulk = 1.0_dp
      ess_tail = 1.0_dp
      mcse_mean = 0.0_dp
      if (n_values < 2) return

      call compute_split_rhat_real(values, rhat)

      call estimate_tau_int_ips_real(values, max_lag_cap, tau_ips, lag_used_ips)
      call estimate_tau_int_ics_real(values, max_lag_cap, tau_ics, lag_used_ics)
      call estimate_tau_int_obm_real(values, max_lag_cap, tau_obm)
      tau_bulk = max(1.0_dp, max(tau_ips, max(tau_ics, tau_obm)))
      ess_bulk = real(n_values, dp)/tau_bulk
      ess_bulk = max(1.0_dp, min(real(n_values, dp), ess_bulk))

      call sample_mean_variance_real(values, mean_value, var_value)
      if (var_value > tiny(1.0_dp)) then
         mcse_mean = sqrt(var_value/max(1.0_dp, ess_bulk))
      else
         mcse_mean = 0.0_dp
      end if

      q_low = sample_quantile_real(values, 0.05_dp)
      q_high = sample_quantile_real(values, 0.95_dp)
      allocate (indicator_low(n_values), indicator_high(n_values))
      do idx = 1, n_values
         if (values(idx) <= q_low) then
            indicator_low(idx) = 1.0_dp
         else
            indicator_low(idx) = 0.0_dp
         end if
         if (values(idx) >= q_high) then
            indicator_high(idx) = 1.0_dp
         else
            indicator_high(idx) = 0.0_dp
         end if
      end do

      call estimate_tau_int_ips_real(indicator_low, max_lag_cap, tau_low_ips, lag_used_ips)
      call estimate_tau_int_ics_real(indicator_low, max_lag_cap, tau_low_ics, lag_used_ics)
      call estimate_tau_int_obm_real(indicator_low, max_lag_cap, tau_low_obm)
      tau_low = max(1.0_dp, max(tau_low_ips, max(tau_low_ics, tau_low_obm)))

      call estimate_tau_int_ips_real(indicator_high, max_lag_cap, tau_high_ips, lag_used_ips)
      call estimate_tau_int_ics_real(indicator_high, max_lag_cap, tau_high_ics, lag_used_ics)
      call estimate_tau_int_obm_real(indicator_high, max_lag_cap, tau_high_obm)
      tau_high = max(1.0_dp, max(tau_high_ips, max(tau_high_ics, tau_high_obm)))

      ess_low = real(n_values, dp)/tau_low
      ess_high = real(n_values, dp)/tau_high
      ess_tail = min(ess_low, ess_high)
      ess_tail = max(1.0_dp, min(real(n_values, dp), ess_tail))
      deallocate (indicator_low, indicator_high)
   end subroutine compute_component_mcmc_diagnostics

   subroutine compute_split_rhat_real(values, rhat)
      real(dp), intent(in) :: values(:)
      real(dp), intent(out) :: rhat

      integer :: n_values, n_chains, n_draws, n_use, start_idx
      integer :: chain_idx, seg_start, seg_end
      real(dp), allocatable :: pseudo_chain_matrix(:, :)

      n_values = size(values)
      rhat = 1.0_dp
      if (n_values < 8) return

      if (n_values >= 80) then
         n_chains = 4
      else
         n_chains = 2
      end if
      n_draws = n_values/n_chains
      if (n_draws < 2) return

      n_use = n_draws*n_chains
      start_idx = n_values - n_use + 1
      allocate (pseudo_chain_matrix(n_chains, n_draws))

      do chain_idx = 1, n_chains
         seg_start = start_idx + (chain_idx - 1)*n_draws
         seg_end = seg_start + n_draws - 1
         pseudo_chain_matrix(chain_idx, :) = values(seg_start:seg_end)
      end do

      call compute_split_rhat_matrix_real(pseudo_chain_matrix, rhat)
      deallocate (pseudo_chain_matrix)
   end subroutine compute_split_rhat_real

   real(dp) function sample_quantile_real(values, prob) result(q_value)
      real(dp), intent(in) :: values(:)
      real(dp), intent(in) :: prob

      integer :: n_values, idx_low, idx_high
      real(dp) :: p_use, pos, frac
      real(dp), allocatable :: sorted_values(:)

      n_values = size(values)
      q_value = 0.0_dp
      if (n_values <= 0) return
      if (n_values == 1) then
         q_value = values(1)
         return
      end if

      p_use = min(1.0_dp, max(0.0_dp, prob))
      allocate (sorted_values(n_values))
      sorted_values = values
      call sort_real_inplace(sorted_values)

      pos = 1.0_dp + p_use*real(n_values - 1, dp)
      idx_low = int(pos)
      idx_low = max(1, min(n_values, idx_low))
      idx_high = min(n_values, idx_low + 1)
      frac = pos - real(idx_low, dp)
      q_value = (1.0_dp - frac)*sorted_values(idx_low) + frac*sorted_values(idx_high)

      deallocate (sorted_values)
   end function sample_quantile_real

   subroutine find_tail_anchored_stable_run(stable_window, min_run_length, run_start, run_end)
      logical, intent(in) :: stable_window(:)
      integer, intent(in) :: min_run_length
      integer, intent(out) :: run_start, run_end

      integer :: idx, n_windows, seg_end, seg_start

      n_windows = size(stable_window)
      run_start = 0
      run_end = 0
      if (n_windows < 1) return

      idx = n_windows
      do while (idx >= 1)
         if (.not. stable_window(idx)) then
            idx = idx - 1
            cycle
         end if
         seg_end = idx
         do while (idx >= 1 .and. stable_window(idx))
            idx = idx - 1
         end do
         seg_start = idx + 1
         if (seg_end - seg_start + 1 >= min_run_length) then
            run_start = seg_start
            run_end = seg_end
            return
         end if
      end do
   end subroutine find_tail_anchored_stable_run

   subroutine estimate_tau_int_ips_real(values, max_lag_cap, tau_int, used_lag)
      real(dp), intent(in) :: values(:)
      integer, intent(in) :: max_lag_cap
      real(dp), intent(out) :: tau_int
      integer, intent(out) :: used_lag

      integer :: n_values, lag_idx, sample_idx, max_lag
      real(dp) :: mean_value, gamma0, gamma_lag, pair_sum
      real(dp), allocatable :: centered(:), rho(:)

      n_values = size(values)
      tau_int = 1.0_dp
      used_lag = 0
      if (n_values < 4 .or. max_lag_cap < 1) return

      mean_value = sum(values)/real(n_values, dp)
      allocate (centered(n_values))
      centered = values - mean_value
      gamma0 = sum(centered*centered)/real(n_values, dp)
      if (gamma0 <= tiny(1.0_dp)) then
         deallocate (centered)
         return
      end if

      max_lag = min(max_lag_cap, n_values - 1)
      allocate (rho(max_lag))
      do lag_idx = 1, max_lag
         gamma_lag = 0.0_dp
         do sample_idx = 1, n_values - lag_idx
            gamma_lag = gamma_lag + centered(sample_idx)*centered(sample_idx + lag_idx)
         end do
         gamma_lag = gamma_lag/real(n_values - lag_idx, dp)
         rho(lag_idx) = gamma_lag/gamma0
      end do

      tau_int = 1.0_dp
      lag_idx = 1
      do while (lag_idx <= max_lag)
         if (lag_idx == max_lag) then
            if (rho(lag_idx) > 0.0_dp) then
               tau_int = tau_int + 2.0_dp*rho(lag_idx)
               used_lag = lag_idx
            end if
            exit
         end if
         pair_sum = rho(lag_idx) + rho(lag_idx + 1)
         if (pair_sum <= 0.0_dp) exit
         tau_int = tau_int + 2.0_dp*(rho(lag_idx) + rho(lag_idx + 1))
         used_lag = lag_idx + 1
         lag_idx = lag_idx + 2
      end do

      tau_int = max(1.0_dp, tau_int)
      deallocate (centered, rho)
   end subroutine estimate_tau_int_ips_real

   subroutine estimate_tau_int_ics_real(values, max_lag_cap, tau_int, used_lag)
      real(dp), intent(in) :: values(:)
      integer, intent(in) :: max_lag_cap
      real(dp), intent(out) :: tau_int
      integer, intent(out) :: used_lag

      integer :: n_values, lag_idx, sample_idx, max_lag
      integer :: n_pairs, n_pairs_pos, n_use_pairs, pair_idx
      real(dp) :: mean_value, gamma0, gamma_lag
      real(dp), allocatable :: centered(:), rho(:)
      real(dp), allocatable :: pair_raw(:), pair_ics(:), slopes(:)

      n_values = size(values)
      tau_int = 1.0_dp
      used_lag = 0
      if (n_values < 6 .or. max_lag_cap < 2) return

      mean_value = sum(values)/real(n_values, dp)
      allocate (centered(n_values))
      centered = values - mean_value
      gamma0 = sum(centered*centered)/real(n_values, dp)
      if (gamma0 <= tiny(1.0_dp)) then
         deallocate (centered)
         return
      end if

      max_lag = min(max_lag_cap, n_values - 1)
      n_pairs = max_lag/2
      if (n_pairs < 1) then
         deallocate (centered)
         return
      end if

      allocate (rho(max_lag))
      do lag_idx = 1, max_lag
         gamma_lag = 0.0_dp
         do sample_idx = 1, n_values - lag_idx
            gamma_lag = gamma_lag + centered(sample_idx)*centered(sample_idx + lag_idx)
         end do
         gamma_lag = gamma_lag/real(n_values - lag_idx, dp)
         rho(lag_idx) = gamma_lag/gamma0
      end do

      allocate (pair_raw(n_pairs))
      do pair_idx = 1, n_pairs
         pair_raw(pair_idx) = rho(2*pair_idx - 1) + rho(2*pair_idx)
      end do

      n_pairs_pos = 0
      do pair_idx = 1, n_pairs
         if (pair_raw(pair_idx) <= 0.0_dp) exit
         n_pairs_pos = pair_idx
      end do
      if (n_pairs_pos < 1) then
         deallocate (centered, rho, pair_raw)
         return
      end if

      allocate (pair_ics(n_pairs_pos))
      pair_ics(1) = max(0.0_dp, pair_raw(1))
      do pair_idx = 2, n_pairs_pos
         pair_ics(pair_idx) = max(0.0_dp, min(pair_ics(pair_idx - 1), pair_raw(pair_idx)))
      end do

      if (n_pairs_pos >= 3) then
         allocate (slopes(n_pairs_pos - 1))
         do pair_idx = 1, n_pairs_pos - 1
            slopes(pair_idx) = pair_ics(pair_idx + 1) - pair_ics(pair_idx)
         end do
         do pair_idx = 2, n_pairs_pos - 1
            slopes(pair_idx) = max(slopes(pair_idx), slopes(pair_idx - 1))
         end do
         do pair_idx = 1, n_pairs_pos - 1
            slopes(pair_idx) = min(0.0_dp, slopes(pair_idx))
         end do
         do pair_idx = 2, n_pairs_pos
            pair_ics(pair_idx) = pair_ics(pair_idx - 1) + slopes(pair_idx - 1)
            if (pair_ics(pair_idx) > pair_ics(pair_idx - 1)) pair_ics(pair_idx) = pair_ics(pair_idx - 1)
            if (pair_ics(pair_idx) < 0.0_dp) pair_ics(pair_idx) = 0.0_dp
         end do
         deallocate (slopes)
      end if

      n_use_pairs = 0
      do pair_idx = 1, n_pairs_pos
         if (pair_ics(pair_idx) <= 0.0_dp) exit
         n_use_pairs = pair_idx
      end do
      if (n_use_pairs >= 1) then
         tau_int = 1.0_dp + 2.0_dp*sum(pair_ics(1:n_use_pairs))
         used_lag = 2*n_use_pairs
      end if

      tau_int = max(1.0_dp, tau_int)
      deallocate (centered, rho, pair_raw, pair_ics)
   end subroutine estimate_tau_int_ics_real

   subroutine estimate_tau_int_obm_real(values, max_lag_cap, tau_int)
      real(dp), intent(in) :: values(:)
      integer, intent(in) :: max_lag_cap
      real(dp), intent(out) :: tau_int

      integer :: n_values, sample_idx, max_block_size, n_windows
      integer :: block_size_center, block_size, idx, n_candidates
      integer :: block_sizes(3), unique_block_sizes(3), n_unique, unique_idx
      logical :: already_present
      real(dp) :: mean_value, var0, sum_sq, batch_centered_mean, sigma2, tau_candidate
      real(dp) :: tau_candidates(3)
      real(dp), allocatable :: centered(:), prefix(:)

      n_values = size(values)
      tau_int = 1.0_dp
      if (n_values < 16) return

      mean_value = sum(values)/real(n_values, dp)
      allocate (centered(n_values))
      centered = values - mean_value
      var0 = sum(centered*centered)/real(n_values, dp)
      if (var0 <= tiny(1.0_dp)) then
         deallocate (centered)
         return
      end if

      allocate (prefix(0:n_values))
      prefix(0) = 0.0_dp
      do sample_idx = 1, n_values
         prefix(sample_idx) = prefix(sample_idx - 1) + centered(sample_idx)
      end do

      max_block_size = min(n_values/32, max(2, 8*max_lag_cap))
      if (max_block_size < 2) max_block_size = max(2, n_values/8)

      block_size_center = min(max_block_size, max(4, max_lag_cap))
      block_sizes(1) = max(2, block_size_center/2)
      block_sizes(2) = block_size_center
      block_sizes(3) = min(max_block_size, 2*block_size_center)

      n_unique = 0
      do idx = 1, 3
         block_size = block_sizes(idx)
         if (block_size < 2) cycle
         already_present = .false.
         do unique_idx = 1, n_unique
            if (unique_block_sizes(unique_idx) == block_size) then
               already_present = .true.
               exit
            end if
         end do
         if (.not. already_present) then
            n_unique = n_unique + 1
            unique_block_sizes(n_unique) = block_size
         end if
      end do

      n_candidates = 0
      do idx = 1, n_unique
         block_size = unique_block_sizes(idx)
         n_windows = n_values - block_size + 1
         if (n_windows >= 32) then
            sum_sq = 0.0_dp
            do sample_idx = 1, n_windows
               batch_centered_mean = (prefix(sample_idx + block_size - 1) - prefix(sample_idx - 1))/real(block_size, dp)
               sum_sq = sum_sq + batch_centered_mean*batch_centered_mean
            end do

            sigma2 = real(n_values*block_size, dp)*sum_sq/ &
                     max(tiny(1.0_dp), real(n_windows*(n_windows - 1), dp))
            tau_candidate = sigma2/max(var0, tiny(1.0_dp))
            if (tau_candidate >= 1.0_dp .and. tau_candidate < huge(1.0_dp)) then
               n_candidates = n_candidates + 1
               tau_candidates(n_candidates) = tau_candidate
            end if
         end if
      end do

      if (n_candidates >= 1) then
         call sort_real_inplace(tau_candidates(1:n_candidates))
         tau_int = tau_candidates((n_candidates + 1)/2)
      end if

      tau_int = max(1.0_dp, min(0.5_dp*real(n_values, dp), tau_int))
      deallocate (centered, prefix)
   end subroutine estimate_tau_int_obm_real

   subroutine window_median_and_rel_mad(values, median_value, rel_mad)
      real(dp), intent(in) :: values(:)
      real(dp), intent(out) :: median_value, rel_mad

      real(dp), allocatable :: deviations(:)
      integer :: n_values

      n_values = size(values)
      if (n_values <= 0) then
         median_value = 0.0_dp
         rel_mad = 0.0_dp
         return
      end if

      median_value = sample_median_real(values)
      allocate (deviations(n_values))
      deviations = abs(values - median_value)
      rel_mad = sample_median_real(deviations)/max(abs(median_value), tiny(1.0_dp))
      deallocate (deviations)
   end subroutine window_median_and_rel_mad

   real(dp) function theil_sen_loglog_slope(bin_sizes_local, err_values) result(slope_value)
      integer, intent(in) :: bin_sizes_local(:)
      real(dp), intent(in) :: err_values(:)

      integer :: n_values, n_pairs, pair_idx, idx_i, idx_j
      real(dp) :: denom
      real(dp), allocatable :: slopes(:)

      n_values = size(err_values)
      slope_value = huge(1.0_dp)
      if (size(bin_sizes_local) /= n_values .or. n_values < 2) return

      n_pairs = n_values*(n_values - 1)/2
      allocate (slopes(n_pairs))
      pair_idx = 0

      do idx_i = 1, n_values - 1
         if (bin_sizes_local(idx_i) <= 0 .or. err_values(idx_i) <= tiny(1.0_dp)) cycle
         do idx_j = idx_i + 1, n_values
            if (bin_sizes_local(idx_j) <= bin_sizes_local(idx_i) .or. err_values(idx_j) <= tiny(1.0_dp)) cycle
            denom = log(real(bin_sizes_local(idx_j), dp)) - log(real(bin_sizes_local(idx_i), dp))
            if (abs(denom) <= tiny(1.0_dp)) cycle
            pair_idx = pair_idx + 1
            slopes(pair_idx) = (log(err_values(idx_j)) - log(err_values(idx_i)))/denom
         end do
      end do

      if (pair_idx >= 1) slope_value = sample_median_real(slopes(1:pair_idx))
      deallocate (slopes)
   end function theil_sen_loglog_slope

   subroutine estimate_autocorrelation_time_windowed(observable_samples, tau_int)
      real(dp), intent(in) :: observable_samples(:)
      real(dp), intent(out) :: tau_int

      integer, parameter :: max_lag_cap_default = 96
      integer :: max_lag_cap, max_lag_use, n_samples_local
      integer :: env_status, env_len, io_status
      character(len=64) :: env_value

      n_samples_local = size(observable_samples)
      tau_int = 1.0_dp
      if (n_samples_local < 2) return

      max_lag_cap = max_lag_cap_default
      env_value = ""
      call get_environment_variable("EVAL_IAT_MAX_LAG", env_value, length=env_len, status=env_status)
      if (env_status == 0 .and. env_len > 0) then
         read (env_value(1:env_len), *, iostat=io_status) max_lag_cap
         if (io_status /= 0 .or. max_lag_cap < 1) then
            write (*, '(A)') "[WARN] Invalid EVAL_IAT_MAX_LAG value. Using default 96."
            max_lag_cap = max_lag_cap_default
         end if
      end if

      max_lag_use = min(n_samples_local - 1, max_lag_cap)
      call autocorr_time_real_series(observable_samples, tau_int, max_lag_use)
   end subroutine estimate_autocorrelation_time_windowed

   subroutine estimate_tau_batchmeans(observable_samples, tau_batch)
      real(dp), intent(in) :: observable_samples(:)
      real(dp), intent(out) :: tau_batch

      integer :: n_samples_local, block_size_local, n_blocks_local
      integer :: block_idx, start_idx, end_idx
      real(dp) :: mean_all, var_all, mean_block, var_block
      real(dp) :: tau_candidate
      real(dp), allocatable :: block_means(:)

      n_samples_local = size(observable_samples)
      tau_batch = 1.0_dp
      if (n_samples_local < 16) return

      call sample_mean_variance_real(observable_samples, mean_all, var_all)
      if (var_all <= tiny(1.0_dp)) return

      block_size_local = 2
      do while (block_size_local <= max(2, n_samples_local/8))
         n_blocks_local = n_samples_local/block_size_local
         if (n_blocks_local < 8) exit

         allocate (block_means(n_blocks_local))
         do block_idx = 1, n_blocks_local
            start_idx = (block_idx - 1)*block_size_local + 1
            end_idx = start_idx + block_size_local - 1
            block_means(block_idx) = sum(observable_samples(start_idx:end_idx))/real(block_size_local, dp)
         end do

         call sample_mean_variance_real(block_means, mean_block, var_block)
         tau_candidate = real(block_size_local, dp)*var_block/max(var_all, tiny(1.0_dp))
         tau_batch = max(tau_batch, tau_candidate)

         deallocate (block_means)
         if (block_size_local > n_samples_local/2) exit
         block_size_local = block_size_local*2
      end do
   end subroutine estimate_tau_batchmeans

   subroutine estimate_tau_split_guard(observable_samples, tau_split)
      real(dp), intent(in) :: observable_samples(:)
      real(dp), intent(out) :: tau_split

      integer :: n_samples_local, n_first, n_second
      real(dp) :: mean_all, var_all
      real(dp) :: mean_first, mean_second, delta_mean

      n_samples_local = size(observable_samples)
      tau_split = 1.0_dp
      if (n_samples_local < 20) return

      call sample_mean_variance_real(observable_samples, mean_all, var_all)
      if (var_all <= tiny(1.0_dp)) return

      n_first = n_samples_local/2
      n_second = n_samples_local - n_first
      if (n_first < 2 .or. n_second < 2) return

      mean_first = sum(observable_samples(1:n_first))/real(n_first, dp)
      mean_second = sum(observable_samples(n_first + 1:n_samples_local))/real(n_second, dp)
      delta_mean = mean_second - mean_first

      tau_split = 0.25_dp*real(n_samples_local, dp)*(delta_mean*delta_mean)/max(var_all, tiny(1.0_dp))
      tau_split = max(1.0_dp, min(0.5_dp*real(n_samples_local, dp), tau_split))
   end subroutine estimate_tau_split_guard

   subroutine sample_mean_variance_real(values, mean_value, variance_value)
      real(dp), intent(in) :: values(:)
      real(dp), intent(out) :: mean_value, variance_value

      integer :: n_values, value_idx
      real(dp) :: delta

      n_values = size(values)
      mean_value = 0.0_dp
      variance_value = 0.0_dp
      if (n_values <= 0) return

      mean_value = sum(values)/real(n_values, dp)
      if (n_values < 2) return

      do value_idx = 1, n_values
         delta = values(value_idx) - mean_value
         variance_value = variance_value + delta*delta
      end do
      variance_value = variance_value/real(n_values - 1, dp)
   end subroutine sample_mean_variance_real

   subroutine autocorr_time_real_series(observable_samples, tau_int, max_lag)
      real(dp), intent(in) :: observable_samples(:)
      integer, intent(in) :: max_lag
      real(dp), intent(out) :: tau_int

      integer :: n_samples_local, max_lag_local, lag_idx, sample_idx
      real(dp) :: mean_value, cov_term
      real(dp), allocatable :: centered_samples(:)
      real(dp), allocatable :: corr(:)
      real(dp) :: corr0

      n_samples_local = size(observable_samples)
      if (n_samples_local < 2 .or. max_lag < 1) then
         tau_int = 1.0_dp
         return
      end if
      max_lag_local = min(max_lag, n_samples_local - 1)
      if (max_lag_local < 1) then
         tau_int = 1.0_dp
         return
      end if

      mean_value = sum(observable_samples)/real(n_samples_local, dp)

      allocate (centered_samples(n_samples_local), corr(0:max_lag_local))
      centered_samples = observable_samples - mean_value

      corr = 0.0_dp
      do sample_idx = 1, n_samples_local
         cov_term = centered_samples(sample_idx)*centered_samples(sample_idx)
         corr(0) = corr(0) + cov_term
      end do
      corr(0) = corr(0)/real(n_samples_local, dp)

      do lag_idx = 1, max_lag_local
         if (lag_idx < n_samples_local) then
            do sample_idx = 1, n_samples_local - lag_idx
               cov_term = centered_samples(sample_idx)*centered_samples(sample_idx + lag_idx)
               corr(lag_idx) = corr(lag_idx) + cov_term
            end do
            corr(lag_idx) = corr(lag_idx)/real(n_samples_local - lag_idx, dp)
         end if
      end do

      corr0 = corr(0)
      if (corr0 <= 0.0_dp) then
         tau_int = 1.0_dp
      else
         tau_int = 1.0_dp
         do lag_idx = 1, max_lag_local
            tau_int = tau_int + 2.0_dp*corr(lag_idx)/corr0
         end do
      end if

      deallocate (centered_samples, corr)
   end subroutine autocorr_time_real_series

   subroutine sort_real_inplace(values)
      real(dp), intent(inout) :: values(:)
      integer :: n_values, root_idx, end_idx
      real(dp) :: temp

      n_values = size(values)
      if (n_values <= 1) return

      do root_idx = n_values/2, 1, -1
         call sift_down_max_heap(values, root_idx, n_values)
      end do

      do end_idx = n_values, 2, -1
         temp = values(1)
         values(1) = values(end_idx)
         values(end_idx) = temp
         call sift_down_max_heap(values, 1, end_idx - 1)
      end do
   end subroutine sort_real_inplace

   subroutine sift_down_max_heap(values, start_idx, end_idx)
      real(dp), intent(inout) :: values(:)
      integer, intent(in) :: start_idx, end_idx

      integer :: root_idx, child_idx, swap_idx
      real(dp) :: temp

      root_idx = start_idx
      do while (2*root_idx <= end_idx)
         child_idx = 2*root_idx
         swap_idx = root_idx

         if (values(swap_idx) < values(child_idx)) swap_idx = child_idx
         if (child_idx + 1 <= end_idx) then
            if (values(swap_idx) < values(child_idx + 1)) swap_idx = child_idx + 1
         end if

         if (swap_idx == root_idx) exit

         temp = values(root_idx)
         values(root_idx) = values(swap_idx)
         values(swap_idx) = temp
         root_idx = swap_idx
      end do
   end subroutine sift_down_max_heap

end program evaluate_expectations_app

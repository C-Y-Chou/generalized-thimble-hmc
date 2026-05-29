program run_wv_hmc
   use utils, only: dp
   use wv_hmc_app_common, only: run_wv_hmc_env_app
   implicit none

   call run_wv_hmc_env_app("WV_HMC", "WV_HMC", 100, 1.0e-5_dp, &
                           "output/production/wv_hmc_summary.csv", &
                           "output/production/wv_hmc_observables.csv", .true.)
end program run_wv_hmc

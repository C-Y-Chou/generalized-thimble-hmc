program run_wv_hmc_smoke
   use utils, only: dp
   use wv_hmc_app_common, only: run_wv_hmc_env_app
   implicit none

   call run_wv_hmc_env_app("WV_HMC_SMOKE", "WV_HMC_SMOKE", 3, 1.0e-5_dp, "", "", .false.)
end program run_wv_hmc_smoke

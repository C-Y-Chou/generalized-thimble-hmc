#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

python3 scripts/run_tltm_product.py wv-hmc \
  --parameters data/parameters_stephanov_n6_mu06_t0.dat \
  --cycles "${WV_HMC_EXAMPLE_CYCLES:-3}" \
  --seed "${WV_HMC_EXAMPLE_SEED:-20260529}" \
  --step-size "${WV_HMC_EXAMPLE_STEP_SIZE:-0.004}" \
  --num-steps "${WV_HMC_EXAMPLE_NUM_STEPS:-10}" \
  --t0 0 \
  --d0 0 \
  --t1 0.03 \
  --d1 0.005 \
  --w-profile zero \
  --w-gamma 0 \
  --boundary-policy normal_reflect \
  --output-dir "${WV_HMC_EXAMPLE_OUTPUT:-output/product/wv_hmc_stephanov_n6_smoke}"

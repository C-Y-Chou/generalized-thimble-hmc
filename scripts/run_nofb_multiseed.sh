#!/usr/bin/env bash
set -uo pipefail

# Run multichain no-fallback (quasi_fallback=off) over multiple seeds.
# Per-seed outputs:
#   - run log:     ${ROOT}/${run_name}.nohup.log
#   - eval log:    ${ROOT}/${run_name}.evaluate.log
#   - run dir:     output/multichain_auto/${run_name}
# Global output:
#   - summary csv: ${ROOT}/summary.csv

ROOT="${ROOT:-output/multichain_auto_nofb_multi_$(date +%m%d_%H%M%S)}"
RUN_PREFIX="${RUN_PREFIX:-s20l2_nofb}"
SEEDS="${SEEDS:-10}"
SEED_START="${SEED_START:-410000001}"
SEED_STEP="${SEED_STEP:-1000003}"
CHAINS="${CHAINS:-24}"
SAMPLES="${SAMPLES:-50000}"
BASE_PARAMETERS="${BASE_PARAMETERS:-data/parameters.dat}"
DIAG_WINDOW="${DIAG_WINDOW:-$SAMPLES}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-43200}"
FORCE="${FORCE:-0}"

mkdir -p "${ROOT}"

summary_csv="${ROOT}/summary.csv"
progress_log="${ROOT}/driver.progress.log"

echo "idx,seed,run_name,status,elapsed_s,rhat_z_re,rhat_z_im,rhat_virial_re,rhat_virial_im,near_fail,near_unusable,far_fail" > "${summary_csv}"

for i in $(seq 1 "${SEEDS}"); do
  seed=$((SEED_START + (i - 1) * SEED_STEP))
  run_name=$(printf "%s_p%02d_%s_nofb" "${RUN_PREFIX}" "${i}" "${SAMPLES}")
  run_dir="output/multichain_auto/${run_name}"
  run_log="${ROOT}/${run_name}.nohup.log"
  eval_log="${ROOT}/${run_name}.evaluate.log"

  echo "[RUN] ${run_name} seed=${seed}" | tee -a "${progress_log}"

  force_args=()
  if [[ "${FORCE}" == "1" ]]; then
    force_args+=(--force)
  fi

  if env \
      OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
      python3 scripts/run_multichain_auto.py \
        "${force_args[@]}" \
        --chains "${CHAINS}" \
        --run-name "${run_name}" \
        --seed-base "${seed}" \
        --base-parameters "${BASE_PARAMETERS}" \
        --chain-length "${SAMPLES}" \
        --target-samples-per-chain "${SAMPLES}" \
        --quasi-fallback off \
        --check-interval "${CHECK_INTERVAL}" \
        --max-wall-seconds "${MAX_WALL_SECONDS}" \
        > "${run_log}" 2>&1; then
    run_status="done"
  else
    run_status="run_failed"
  fi

  eval_status="NA"
  if [[ "${run_status}" == "done" ]]; then
    if EVAL_MULTICHAIN_RUN_DIR="${run_dir}" EVAL_MULTICHAIN_DIAG_WINDOW="${DIAG_WINDOW}" \
      bin/evaluate_expectations > "${eval_log}" 2>&1; then
      eval_status="eval_done"
    else
      eval_status="eval_failed"
    fi
  fi

  status="${run_status}"
  if [[ "${run_status}" == "done" && "${eval_status}" == "eval_failed" ]]; then
    status="eval_failed"
  fi

  elapsed="NA"
  if [[ -f "${run_dir}/summary.json" ]]; then
    elapsed=$(jq -r '.elapsed_seconds // "NA"' "${run_dir}/summary.json" 2>/dev/null || echo "NA")
  fi

  rz_re="NA"; rz_im="NA"; rv_re="NA"; rv_im="NA"
  if [[ -f "${eval_log}" ]]; then
    rz_re=$(rg "\[RESULT\] split_rhat_z" "${eval_log}" | sed -E 's/.*= *([^ ]+) *([^ ]+)$/\1/' | tail -n1)
    rz_im=$(rg "\[RESULT\] split_rhat_z" "${eval_log}" | sed -E 's/.*= *([^ ]+) *([^ ]+)$/\2/' | tail -n1)
    rv_re=$(rg "\[RESULT\] split_rhat_virial" "${eval_log}" | sed -E 's/.*= *([^ ]+) *([^ ]+)$/\1/' | tail -n1)
    rv_im=$(rg "\[RESULT\] split_rhat_virial" "${eval_log}" | sed -E 's/.*= *([^ ]+) *([^ ]+)$/\2/' | tail -n1)
  fi

  near_fail="NA"; near_unusable="NA"; far_fail="NA"
  if ls "${run_dir}"/chain_*/logs/generate_markov_chain.log >/dev/null 2>&1; then
    read -r near_fail near_unusable far_fail < <(
      awk '
        /near_fail=/ {
          nf=nu=ff=0;
          for(i=1;i<=NF;i++){
            if($i ~ /^near_fail=/){split($i,a,"="); nf=a[2]}
            else if($i ~ /^near_unusable=/){split($i,a,"="); nu=a[2]}
            else if($i ~ /^far_fail=/){split($i,a,"="); ff=a[2]}
          }
          last_nf=nf; last_nu=nu; last_ff=ff;
        }
        ENDFILE {
          sum_nf += last_nf+0; sum_nu += last_nu+0; sum_ff += last_ff+0;
          last_nf=last_nu=last_ff=0
        }
        END {print sum_nf, sum_nu, sum_ff}
      ' "${run_dir}"/chain_*/logs/generate_markov_chain.log
    )
  fi

  printf "%d,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
    "${i}" "${seed}" "${run_name}" "${status}" "${elapsed}" \
    "${rz_re}" "${rz_im}" "${rv_re}" "${rv_im}" \
    "${near_fail}" "${near_unusable}" "${far_fail}" >> "${summary_csv}"

  echo "[DONE] ${run_name} status=${status}" | tee -a "${progress_log}"
done

echo "[ALL DONE] summary=${summary_csv}" | tee -a "${progress_log}"

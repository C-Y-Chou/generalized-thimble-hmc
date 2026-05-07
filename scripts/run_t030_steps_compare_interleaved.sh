#!/usr/bin/env bash
set -euo pipefail

# Run t=0.30 scan for one integration-steps setting, interleaving nofb/withfb
# per seed index:
#   p01: nofb -> withfb
#   p02: nofb -> withfb
#   ...
#
# This lets you inspect paired results during the run.
#
# Usage:
#   STEPS=40 SEEDS=90 bash scripts/run_t030_steps_compare_interleaved.sh
#
# Env knobs:
#   STEPS           integration_steps (required)
#   TRAJ_LEN        trajectory_length (default: 2)
#   FLOW_TIME       initial_flow_time (default: 0.30)
#   SAMPLES         per-chain samples (default: 50000)
#   CHAINS          number of chains (default: 24)
#   SEEDS           number of seed pairs (default: 10)
#   SEED_START      default: 410000001
#   SEED_STEP       default: 1000003
#   CHECK_INTERVAL  default: 10
#   MAX_WALL_SECONDS default: 43200
#   FORCE           pass-through to run_multichain_auto.py --force (default: 0)
#   ROOT            output root; default auto timestamped
#   TAG             optional run tag suffix; default timestamp

STEPS="${STEPS:-}"
if [[ -z "${STEPS}" ]]; then
  echo "[ERROR] STEPS is required (e.g., STEPS=40)." >&2
  exit 2
fi
if ! [[ "${STEPS}" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] STEPS must be integer, got: ${STEPS}" >&2
  exit 2
fi

TRAJ_LEN="${TRAJ_LEN:-2}"
FLOW_TIME="${FLOW_TIME:-0.30}"
SAMPLES="${SAMPLES:-50000}"
CHAINS="${CHAINS:-24}"
SEEDS="${SEEDS:-10}"
SEED_START="${SEED_START:-410000001}"
SEED_STEP="${SEED_STEP:-1000003}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-43200}"
FORCE="${FORCE:-0}"

TS="${TAG:-$(date +%m%d_%H%M%S)}"
ROOT="${ROOT:-output/multichain_auto_t030_s${STEPS}l2_compare_interleaved_${TS}}"

mkdir -p "${ROOT}/nofb" "${ROOT}/withfb"
progress_log="${ROOT}/driver.progress.log"
nofb_progress="${ROOT}/nofb/driver.progress.log"
withfb_progress="${ROOT}/withfb/driver.progress.log"

base_template="data/parameters.dat"
param_file="${ROOT}/parameters_t030_s${STEPS}l2.dat"

if [[ ! -f "${base_template}" ]]; then
  echo "[ERROR] Missing template: ${base_template}" | tee -a "${progress_log}" >&2
  exit 2
fi

cp "${base_template}" "${param_file}"
sed -Ei \
  -e "s/^([[:space:]]*initial_flow_time[[:space:]]*=[[:space:]]*).*/\\1${FLOW_TIME}/" \
  -e "s/^([[:space:]]*integration_steps[[:space:]]*=[[:space:]]*).*/\\1${STEPS}/" \
  -e "s/^([[:space:]]*trajectory_length[[:space:]]*=[[:space:]]*).*/\\1${TRAJ_LEN}/" \
  "${param_file}"

run_prefix="s${STEPS}l2_t030_s1_50k_${TS}"

{
  echo "[INIT] ROOT=${ROOT}"
  echo "[INIT] MODE=interleaved (nofb->withfb per seed)"
  echo "[INIT] STEPS=${STEPS} TRAJ_LEN=${TRAJ_LEN} FLOW_TIME=${FLOW_TIME}"
  echo "[INIT] SAMPLES=${SAMPLES} CHAINS=${CHAINS} SEEDS=${SEEDS}"
  echo "[INIT] SEED_START=${SEED_START} SEED_STEP=${SEED_STEP}"
  echo "[INIT] PARAM=${param_file}"
  echo "[INIT] RUN_PREFIX=${run_prefix}"
} | tee -a "${progress_log}"

summary_header="idx,seed,run_name,status,elapsed_s,rhat_z_re,rhat_z_im,rhat_virial_re,rhat_virial_im,near_fail,near_unusable,far_fail"
echo "${summary_header}" > "${ROOT}/nofb/summary.csv"
echo "${summary_header}" > "${ROOT}/withfb/summary.csv"

run_one() {
  local mode="$1"
  local idx="$2"
  local seed="$3"
  local run_name run_dir run_log eval_log mode_root mode_progress
  local run_status eval_status status elapsed rz_re rz_im rv_re rv_im near_fail near_unusable far_fail

  run_name=$(printf "%s_p%02d_%s_%s" "${run_prefix}" "${idx}" "${SAMPLES}" "${mode}")
  run_dir="output/multichain_auto/${run_name}"
  mode_root="${ROOT}/${mode}"
  run_log="${mode_root}/${run_name}.nohup.log"
  eval_log="${mode_root}/${run_name}.evaluate.log"
  mode_progress="${mode_root}/driver.progress.log"

  {
    echo "[RUN] ${run_name} seed=${seed}"
  } | tee -a "${progress_log}" "${mode_progress}"

  local force_args=()
  if [[ "${FORCE}" == "1" ]]; then
    force_args+=(--force)
  fi

  if [[ "${mode}" == "withfb" ]]; then
    if env \
      OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
      QN_ENABLE_LEGACY_RESCUE=0 \
      QN_PROGRESSIVE_RESCUE_STAGE=1 \
      QN_RESCUE_LEVEL=0 \
      QN_FAR_RESCUE_REBUILD=off \
      QN_FAR_LIGHT_MICRO_EXT=off \
      QN_FAR_ANCHOR_FASTTRACK=off \
      QN_FAR_ANCHOR_MIX_RESTART=off \
      QN_NEAR_SEEDED_NEWTON=off \
      python3 scripts/run_multichain_auto.py \
        "${force_args[@]}" \
        --chains "${CHAINS}" \
        --run-name "${run_name}" \
        --seed-base "${seed}" \
        --base-parameters "${param_file}" \
        --chain-length "${SAMPLES}" \
        --target-samples-per-chain "${SAMPLES}" \
        --quasi-fallback on \
        --check-interval "${CHECK_INTERVAL}" \
        --max-wall-seconds "${MAX_WALL_SECONDS}" \
        > "${run_log}" 2>&1; then
      run_status="done"
    else
      run_status="run_failed"
    fi
  else
    if env \
      OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
      python3 scripts/run_multichain_auto.py \
        "${force_args[@]}" \
        --chains "${CHAINS}" \
        --run-name "${run_name}" \
        --seed-base "${seed}" \
        --base-parameters "${param_file}" \
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
  fi

  eval_status="NA"
  if [[ "${run_status}" == "done" ]]; then
    if EVAL_MULTICHAIN_RUN_DIR="${run_dir}" EVAL_MULTICHAIN_DIAG_WINDOW="${SAMPLES}" \
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
    "${idx}" "${seed}" "${run_name}" "${status}" "${elapsed}" \
    "${rz_re}" "${rz_im}" "${rv_re}" "${rv_im}" \
    "${near_fail}" "${near_unusable}" "${far_fail}" \
    >> "${mode_root}/summary.csv"

  {
    echo "[DONE] ${run_name} status=${status}"
  } | tee -a "${progress_log}" "${mode_progress}"
}

for i in $(seq 1 "${SEEDS}"); do
  seed=$((SEED_START + (i - 1) * SEED_STEP))
  run_one "nofb" "${i}" "${seed}"
  run_one "withfb" "${i}" "${seed}"
done

{
  echo "[ALL DONE] ROOT=${ROOT}"
  echo "[ALL DONE] nofb_summary=${ROOT}/nofb/summary.csv"
  echo "[ALL DONE] withfb_summary=${ROOT}/withfb/summary.csv"
} | tee -a "${progress_log}"


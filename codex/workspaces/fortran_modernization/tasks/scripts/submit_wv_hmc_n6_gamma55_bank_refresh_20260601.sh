#!/usr/bin/env bash
set -euo pipefail

SNAPSHOT_ROOT="${SNAPSHOT_ROOT:-/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/wv_hmc_n6_t003_prod15k_gitless_r3_20260601}"
SOURCE_PIN_FILE="${SOURCE_PIN_FILE:-${SNAPSHOT_ROOT}/codex/workspaces/fortran_modernization/state/CLUSTER02_SOURCE_PIN.env}"
PBS_SCRIPT="${PBS_SCRIPT:-${SNAPSHOT_ROOT}/codex/workspaces/fortran_modernization/tasks/pbs/wv_hmc_observable_chunk_nobuild_20260530.pbs}"
QSUB_GATE="${QSUB_GATE:-${SNAPSHOT_ROOT}/codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh}"

REQUEST_ID="${REQUEST_ID:-FMOD-WV-HMC-N6-G55-BANKREFRESH-512X8000-20260601}"
RUN_NAME="${RUN_NAME:-wv_hmc_n6_t003_gamma55_bank_refresh_512x8000_20260601}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_gamma55_bank_refresh_20260601}"
LOG_ROOT="${LOG_ROOT:-/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_n6_gamma55_bank_refresh_20260601/${RUN_NAME}}"

PARAMETERS_FILE="${PARAMETERS_FILE:-data/parameters_stephanov_n6_mu06_t0.dat}"
INIT_BANK="${INIT_BANK:-/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260601/stephanov_n6_tau0_hmc_eps080_n8_64x3000_20260601/state_bank_tau0/x_bank.dat}"

SEED_START="${SEED_START:-9200001}"
CHUNKS="${CHUNKS:-32}"
SEEDS_PER_CHUNK="${SEEDS_PER_CHUNK:-16}"
CYCLES="${CYCLES:-8000}"
MEASUREMENT_START_CYCLE="${MEASUREMENT_START_CYCLE:-1}"
HISTORY_STRIDE="${HISTORY_STRIDE:-20}"
SNAPSHOT_INTERVAL="${SNAPSHOT_INTERVAL:-500}"
SNAPSHOT_SLOTS="${SNAPSHOT_SLOTS:-8}"
TIMEOUT_SEC="${TIMEOUT_SEC:-30000}"
WALLTIME="${WALLTIME:-10:00:00}"
MEM="${MEM:-16gb}"

queues=(
  C17 C17 C17
  C17-LONG C17-LONG C17-LONG C17-LONG
  C12 C12 C12 C12 C12 C12 C12 C12 C12 C12 C12 C12 C12
  C12-LONG C12-LONG C12-LONG C12-LONG C12-LONG C12-LONG
  C8 C8 C8 C8 C8
  C8-LONG
)

if [ "${#queues[@]}" -lt "${CHUNKS}" ]; then
  echo "[ERROR] queue plan has ${#queues[@]} entries but CHUNKS=${CHUNKS}" >&2
  exit 2
fi
if [ ! -x "${QSUB_GATE}" ]; then
  echo "[ERROR] qsub gate not executable: ${QSUB_GATE}" >&2
  exit 2
fi
if [ ! -f "${PBS_SCRIPT}" ]; then
  echo "[ERROR] PBS script missing: ${PBS_SCRIPT}" >&2
  exit 2
fi

mkdir -p "${LOG_ROOT}/submit"

export TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler
export TLTM_SCHEDULER_REQUEST_ID="${REQUEST_ID}"

manifest="${LOG_ROOT}/submit/submitted_jobs.tsv"
printf 'chunk\tqueue\tjob_id\tseed_start\tseed_count\tcycles\thistory_stride\n' > "${manifest}"

for chunk in $(seq 0 $((CHUNKS - 1))); do
  chunk_id="$(printf '%02d' "${chunk}")"
  queue="${queues[${chunk}]}"
  seed_start=$((SEED_START + chunk * SEEDS_PER_CHUNK))
  vars=$(
    printf '%s' \
      "TLTM_WORKTREE=${SNAPSHOT_ROOT}," \
      "TLTM_REQUIRE_SOURCE_PIN=1," \
      "TLTM_SOURCE_PIN_FILE=${SOURCE_PIN_FILE}," \
      "TLTM_RUN_NAME=${RUN_NAME}," \
      "TLTM_OUTPUT_ROOT=${OUTPUT_ROOT}," \
      "TLTM_LOG_ROOT=${LOG_ROOT}," \
      "TLTM_PARAMETERS_FILE=${PARAMETERS_FILE}," \
      "WV_OBS_CHUNK_ID=${chunk_id}," \
      "WV_OBS_SEED_START=${seed_start}," \
      "WV_OBS_SEED_COUNT=${SEEDS_PER_CHUNK}," \
      "WV_OBS_CYCLES=${CYCLES}," \
      "WV_OBS_MEASUREMENT_START_CYCLE=${MEASUREMENT_START_CYCLE}," \
      "WV_OBS_STEP_SIZE=0.010," \
      "WV_OBS_NUM_STEPS=8," \
      "WV_OBS_INIT_MODE=state_bank," \
      "WV_OBS_INIT_BANK_FILE=${INIT_BANK}," \
      "WV_OBS_INIT_BANK_RECORD=-1," \
      "WV_OBS_WRITE_FINAL_STATE=1," \
      "WV_OBS_WRITE_OBSERVABLE_HISTORY=1," \
      "WV_OBS_WRITE_X_HISTORY=0," \
      "WV_OBS_WRITE_STATE_HISTORY=1," \
      "WV_OBS_HISTORY_STRIDE=${HISTORY_STRIDE}," \
      "WV_OBS_WRITE_CYCLIC_SNAPSHOT=1," \
      "WV_OBS_SNAPSHOT_INTERVAL=${SNAPSHOT_INTERVAL}," \
      "WV_OBS_SNAPSHOT_SLOTS=${SNAPSHOT_SLOTS}," \
      "WV_OBS_JOBS=${SEEDS_PER_CHUNK}," \
      "WV_OBS_TIMEOUT_SEC=${TIMEOUT_SEC}," \
      "WV_OBS_CONSTRAINT_TOL=1.0e-10," \
      "WV_OBS_CONSTRAINT_MAX_ITER=192," \
      "WV_OBS_ADAPTIVE_NEWTON_STOP_ENABLED=0," \
      "WV_OBS_LARGE_RESIDUAL_STOP_ENABLED=0," \
      "WV_OBS_T0=0.0," \
      "WV_OBS_T1=0.03," \
      "WV_OBS_D0=0.0001," \
      "WV_OBS_D1=0.005," \
      "WV_OBS_MEASUREMENT_T0=0.0," \
      "WV_OBS_MEASUREMENT_T1=0.03," \
      "WV_OBS_FLOW_TIME=0.0," \
      "WV_OBS_W_PROFILE=paper_wall," \
      "WV_OBS_W_GAMMA=55," \
      "WV_OBS_W_C0=1.0," \
      "WV_OBS_W_C1=1.0," \
      "TLTM_ODE_BACKEND=dop853"
  )
  job_id="$("${QSUB_GATE}" \
    -q "${queue}" \
    -N "wvG55bk${chunk_id}" \
    -l "select=1:ncpus=${SEEDS_PER_CHUNK}:mpiprocs=${SEEDS_PER_CHUNK}:mem=${MEM}" \
    -l "walltime=${WALLTIME}" \
    -v "${vars}" \
    "${PBS_SCRIPT}")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${chunk_id}" "${queue}" "${job_id}" "${seed_start}" \
    "${SEEDS_PER_CHUNK}" "${CYCLES}" "${HISTORY_STRIDE}" | tee -a "${manifest}"
done

echo "manifest=${manifest}"
echo "output_root=${OUTPUT_ROOT}/${RUN_NAME}"
echo "log_root=${LOG_ROOT}"

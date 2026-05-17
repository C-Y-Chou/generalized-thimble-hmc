#!/bin/bash
# Submit the first F20 loose-double 32seed/50k sensitivity gate.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

: "${TLTM_WORKTREE:=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization}"
: "${TLTM_EXPECTED_GIT_BRANCH:=codex/fortran-modernization}"
: "${TLTM_EXPECTED_GIT_COMMIT:=$(git rev-parse HEAD)}"
: "${TLTM_F20_PROFILE:=single_feasible1e6_rg1e4}"
: "${TLTM_CONFIG_JSON:=docs/modernization_reference_t035_r3_32seed_50k.json}"
: "${TLTM_REFERENCE_COMPARISON_ROOT:=output/reference/fortran_modernization/m6/r3_32seed_50k}"
: "${TLTM_RUN_GUARDRAILS:=1}"
: "${TLTM_BUILD_JOBS:=16}"
: "${TLTM_ALLOW_OVERWRITE:=0}"
: "${TLTM_DRY_RUN:=0}"
: "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:=}"
: "${TLTM_SCHEDULER_REQUEST_ID:=}"

# First single-feasible profile: still executed in double precision for this
# sensitivity gate, but the tolerances are deliberately no tighter than a
# plausible future FP32/mixed-precision certification target.
: "${TLTM_STAGE2_ABS_TOL_OVERRIDE:=1e-6}"
: "${TLTM_STAGE2_REL_TOL_OVERRIDE:=1e-6}"
: "${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE:=1e-6}"
: "${QN_QUASI_TOL_OVERRIDE:=1e-6}"
: "${QN_REVERSE_GATE_TOL:=1e-4}"
: "${QN_OFFICIAL_DFOLS_RHOEND:=1e-6}"
: "${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL:=1e-12}"
: "${QN_OFFICIAL_DFOLS_MODEL_REL_TOL:=0}"

stamp="$(date +%Y%m%dT%H%M%S)"
short_commit="$(git rev-parse --short=12 "${TLTM_EXPECTED_GIT_COMMIT}")"
: "${TLTM_REF_LEVEL:=F20}"
: "${TLTM_REF_LABEL:=f20_${TLTM_F20_PROFILE}_r3_32seed_50k_${short_commit}}"
: "${TLTM_ROOT_SUBDIR:=output/tests/f20_loose_double/${TLTM_REF_LABEL}}"
: "${TLTM_ROOT_LOG_SUBDIR:=output/logs/f20_loose_double/${TLTM_REF_LABEL}}"

if [ "${TLTM_DRY_RUN}" != "1" ]; then
  if ! command -v qsub >/dev/null 2>&1; then
    echo "[ERROR] qsub not found. Run this launcher on the PBS login host or set TLTM_DRY_RUN=1." >&2
    exit 2
  fi
  if [ "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY}" != "cluster02_scheduler" ] || [ -z "${TLTM_SCHEDULER_REQUEST_ID}" ]; then
    echo "[ERROR] Actual PBS submission is owned by the cluster02 scheduling agent." >&2
    echo "[ERROR] Modernization agents may use TLTM_DRY_RUN=1, but qsub requires TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler and TLTM_SCHEDULER_REQUEST_ID=<request-id>." >&2
    exit 2
  fi
  if [ -n "$(git status --porcelain)" ]; then
    echo "[ERROR] working tree is dirty; commit/sync before submitting F20 loose-double gate." >&2
    git status --short >&2
    exit 2
  fi
fi

mkdir -p "${TLTM_ROOT_LOG_SUBDIR}/submit"

common_vars="TLTM_WORKTREE=${TLTM_WORKTREE},TLTM_EXPECTED_GIT_BRANCH=${TLTM_EXPECTED_GIT_BRANCH},TLTM_EXPECTED_GIT_COMMIT=${TLTM_EXPECTED_GIT_COMMIT}"
tol_vars="TLTM_TOLERANCE_PROFILE_LABEL=${TLTM_F20_PROFILE},TLTM_STAGE2_ABS_TOL_OVERRIDE=${TLTM_STAGE2_ABS_TOL_OVERRIDE},TLTM_STAGE2_REL_TOL_OVERRIDE=${TLTM_STAGE2_REL_TOL_OVERRIDE},TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE},QN_QUASI_TOL_OVERRIDE=${QN_QUASI_TOL_OVERRIDE},QN_REVERSE_GATE_TOL=${QN_REVERSE_GATE_TOL},QN_OFFICIAL_DFOLS_RHOEND=${QN_OFFICIAL_DFOLS_RHOEND},QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL},QN_OFFICIAL_DFOLS_MODEL_REL_TOL=${QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"

run_qsub() {
  if [ "${TLTM_DRY_RUN}" = "1" ]; then
    {
      printf 'qsub'
      printf ' %q' "$@"
      printf '\n'
    } >&2
    echo "DRYRUN_${stamp}_${RANDOM}"
  else
    codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh "$@"
  fi
}

build_vars="${common_vars},TLTM_RUN_GUARDRAILS=${TLTM_RUN_GUARDRAILS},TLTM_BUILD_JOBS=${TLTM_BUILD_JOBS}"
build_job="$(run_qsub \
  -N f20ldbld \
  -q C8 \
  -l select=1:ncpus=16:mpiprocs=16:mem=16gb \
  -l walltime=02:00:00 \
  -o "${TLTM_ROOT_LOG_SUBDIR}/submit/preflight.pbs.out" \
  -v "${build_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_preflight_build.pbs)"

chunk_jobs=()
queues=(C8 C12 C16 C8 C12 C16 C8 C12)
idx=0
for method in no_fb fb_norefine; do
  mkdir -p "${TLTM_ROOT_LOG_SUBDIR}/${method}"
  for chunk in 0 1 2 3; do
    chunk_id="$(printf '%02d' "${chunk}")"
    seed_offset=$((chunk * 8))
    queue="${queues[$idx]}"
    idx=$((idx + 1))
    vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${TLTM_REF_LABEL},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${TLTM_ROOT_SUBDIR},TLTM_ROOT_LOG_SUBDIR=${TLTM_ROOT_LOG_SUBDIR},TLTM_METHOD=${method},TLTM_CHUNK_ID=${chunk_id},TLTM_SEED_OFFSET=${seed_offset},TLTM_MAX_SEEDS=8,TLTM_JOBS=8,TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE}"
    job="$(run_qsub \
      -N "f20${method//_/}${chunk_id}" \
      -q "${queue}" \
      -l select=1:ncpus=8:mpiprocs=8:mem=16gb \
      -l walltime=08:00:00 \
      -o "${TLTM_ROOT_LOG_SUBDIR}/${method}/chunk_${chunk_id}.pbs.out" \
      -W "depend=afterok:${build_job}" \
      -v "${vars}" \
      codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_chunk.pbs)"
    chunk_jobs+=("${job}")
  done
done

deps="$(IFS=:; echo "${chunk_jobs[*]}")"
mkdir -p "${TLTM_ROOT_LOG_SUBDIR}/merge"
merge_vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${TLTM_REF_LABEL},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${TLTM_ROOT_SUBDIR},TLTM_ROOT_LOG_SUBDIR=${TLTM_ROOT_LOG_SUBDIR},TLTM_EXPECTED_ROWS_PER_METHOD=32,TLTM_REQUESTED_CPUS=64,TLTM_CHUNKS_LABEL=F20_loose_double_chunks,TLTM_REFERENCE_COMPARISON_ROOT=${TLTM_REFERENCE_COMPARISON_ROOT}"
merge_job="$(run_qsub \
  -N f20ldmrg \
  -q C8 \
  -l select=1:ncpus=1:mpiprocs=1:mem=4gb \
  -l walltime=01:00:00 \
  -o "${TLTM_ROOT_LOG_SUBDIR}/merge/merge.pbs.out" \
  -W "depend=afterok:${deps}" \
  -v "${merge_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_merge_level.pbs)"

manifest="${TLTM_ROOT_LOG_SUBDIR}/submit/submit_manifest_${stamp}.env"
{
  echo "submitted_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "scheduler_authority=${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}"
  echo "scheduler_request_id=${TLTM_SCHEDULER_REQUEST_ID:-dry_run}"
  echo "profile=${TLTM_F20_PROFILE}"
  echo "worktree=${TLTM_WORKTREE}"
  echo "expected_branch=${TLTM_EXPECTED_GIT_BRANCH}"
  echo "expected_commit=${TLTM_EXPECTED_GIT_COMMIT}"
  echo "config=${TLTM_CONFIG_JSON}"
  echo "reference_comparison_root=${TLTM_REFERENCE_COMPARISON_ROOT}"
  echo "output_root=${TLTM_ROOT_SUBDIR}"
  echo "log_root=${TLTM_ROOT_LOG_SUBDIR}"
  echo "abs_tol=${TLTM_STAGE2_ABS_TOL_OVERRIDE}"
  echo "rel_tol=${TLTM_STAGE2_REL_TOL_OVERRIDE}"
  echo "constraint_tol=${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE}"
  echo "qn_quasi_tol=${QN_QUASI_TOL_OVERRIDE}"
  echo "reverse_gate_tol=${QN_REVERSE_GATE_TOL}"
  echo "qn_official_dfols_rhoend=${QN_OFFICIAL_DFOLS_RHOEND}"
  echo "qn_official_dfols_model_abs_tol=${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL}"
  echo "build_job=${build_job}"
  i=0
  for job in "${chunk_jobs[@]}"; do
    echo "chunk_job_${i}=${job}"
    i=$((i + 1))
  done
  echo "merge_job=${merge_job}"
} > "${manifest}"

echo "submit_manifest=${manifest}"
echo "build_job=${build_job}"
echo "merge_job=${merge_job}"

#!/bin/bash
# Prepare or submit F20d double-tolerance candidate validation, R3 32seed/50k.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

: "${TLTM_WORKTREE:=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization}"
: "${TLTM_EXPECTED_GIT_BRANCH:=codex/fortran-modernization}"
: "${TLTM_EXPECTED_GIT_COMMIT:=$(git rev-parse HEAD)}"
: "${TLTM_CONFIG_JSON:=docs/modernization_reference_t035_r3_32seed_50k.json}"
: "${TLTM_REFERENCE_COMPARISON_ROOT:=output/reference/fortran_modernization/m6/r3_32seed_50k}"
: "${TLTM_RUN_GUARDRAILS:=1}"
: "${TLTM_BUILD_JOBS:=1}"
: "${TLTM_ALLOW_OVERWRITE:=0}"
: "${TLTM_DRY_RUN:=0}"
: "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:=}"
: "${TLTM_SCHEDULER_REQUEST_ID:=}"

# Queue choice belongs to the cluster02 scheduler. Dry-runs use placeholders;
# real submissions require the scheduler to provide concrete queue names.
: "${TLTM_F20D_BUILD_QUEUE:=SCHEDULER_ASSIGN_BUILD_QUEUE}"
: "${TLTM_F20D_CHUNK_QUEUE:=SCHEDULER_ASSIGN_CHUNK_QUEUE}"
: "${TLTM_F20D_MERGE_QUEUE:=SCHEDULER_ASSIGN_MERGE_QUEUE}"

: "${TLTM_F20D_PROFILE:=double_ode1e12_ntqn1e10_dfols1e13_candidate}"
: "${TLTM_STAGE2_ABS_TOL_OVERRIDE:=1e-12}"
: "${TLTM_STAGE2_REL_TOL_OVERRIDE:=1e-12}"
: "${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE:=1e-10}"
: "${QN_QUASI_TOL_OVERRIDE:=1e-10}"
: "${QN_REVERSE_GATE_TOL:=1e-8}"
: "${QN_OFFICIAL_DFOLS_RHOEND:=1e-13}"
: "${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL:=1e-20}"
: "${QN_OFFICIAL_DFOLS_MODEL_REL_TOL:=0}"

stamp="$(date +%Y%m%dT%H%M%S)"
short_commit="$(git rev-parse --short=12 "${TLTM_EXPECTED_GIT_COMMIT}")"
: "${TLTM_REF_LEVEL:=F20D_R3_DOUBLE_TOLERANCE_VALIDATION}"
: "${TLTM_REF_LABEL:=f20d_${TLTM_F20D_PROFILE}_r3_32seed_50k_${short_commit}}"
: "${TLTM_ROOT_SUBDIR:=output/tests/f20_double_tolerance_validation/${TLTM_REF_LABEL}}"
: "${TLTM_ROOT_LOG_SUBDIR:=output/logs/f20_double_tolerance_validation/${TLTM_REF_LABEL}}"

methods=(no_fb fb_norefine)
chunks=(00 01 02 03)

if [ "${TLTM_DRY_RUN}" != "1" ]; then
  if [ "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY}" != "cluster02_scheduler" ] || [ -z "${TLTM_SCHEDULER_REQUEST_ID}" ]; then
    echo "[ERROR] Actual PBS submission is owned by the cluster02 scheduling agent." >&2
    echo "[ERROR] Use TLTM_DRY_RUN=1 here, or let the scheduler set TLTM_CLUSTER02_SCHEDULER_AUTHORITY and TLTM_SCHEDULER_REQUEST_ID." >&2
    exit 2
  fi
  for queue in "${TLTM_F20D_BUILD_QUEUE}" "${TLTM_F20D_CHUNK_QUEUE}" "${TLTM_F20D_MERGE_QUEUE}"; do
    case "${queue}" in
      ""|SCHEDULER_ASSIGN_*)
        echo "[ERROR] scheduler must provide concrete queue names before real submit." >&2
        exit 2
        ;;
    esac
  done
  if [ -n "$(git status --porcelain)" ]; then
    echo "[ERROR] working tree is dirty; commit/sync before submitting F20d validation." >&2
    git status --short >&2
    exit 2
  fi
fi

mkdir -p "${TLTM_ROOT_LOG_SUBDIR}/submit" "${TLTM_ROOT_LOG_SUBDIR}/merge"
for method in "${methods[@]}"; do
  mkdir -p "${TLTM_ROOT_LOG_SUBDIR}/${method}"
done

common_vars="TLTM_WORKTREE=${TLTM_WORKTREE},TLTM_EXPECTED_GIT_BRANCH=${TLTM_EXPECTED_GIT_BRANCH},TLTM_EXPECTED_GIT_COMMIT=${TLTM_EXPECTED_GIT_COMMIT}"
tol_vars="TLTM_TOLERANCE_PROFILE_LABEL=${TLTM_F20D_PROFILE},TLTM_STAGE2_ABS_TOL_OVERRIDE=${TLTM_STAGE2_ABS_TOL_OVERRIDE},TLTM_STAGE2_REL_TOL_OVERRIDE=${TLTM_STAGE2_REL_TOL_OVERRIDE},TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE},QN_QUASI_TOL_OVERRIDE=${QN_QUASI_TOL_OVERRIDE},QN_REVERSE_GATE_TOL=${QN_REVERSE_GATE_TOL},QN_OFFICIAL_DFOLS_RHOEND=${QN_OFFICIAL_DFOLS_RHOEND},QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL},QN_OFFICIAL_DFOLS_MODEL_REL_TOL=${QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"

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
  -N f20dvalbld \
  -q "${TLTM_F20D_BUILD_QUEUE}" \
  -l select=1:ncpus=16:mpiprocs=16:mem=16gb \
  -l walltime=02:00:00 \
  -o "${TLTM_ROOT_LOG_SUBDIR}/submit/preflight.pbs.out" \
  -v "${build_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_preflight_build.pbs)"

chunk_jobs=()
chunk_methods=()
chunk_ids=()
for method in "${methods[@]}"; do
  method_short="nf"
  if [ "${method}" = "fb_norefine" ]; then
    method_short="fb"
  fi
  for chunk_id in "${chunks[@]}"; do
    seed_offset=$((10#${chunk_id} * 8))
    vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${TLTM_REF_LABEL},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${TLTM_ROOT_SUBDIR},TLTM_ROOT_LOG_SUBDIR=${TLTM_ROOT_LOG_SUBDIR},TLTM_METHOD=${method},TLTM_CHUNK_ID=${chunk_id},TLTM_SEED_OFFSET=${seed_offset},TLTM_MAX_SEEDS=8,TLTM_JOBS=8,TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE}"
    job="$(run_qsub \
      -N "f20dv${method_short}${chunk_id}" \
      -q "${TLTM_F20D_CHUNK_QUEUE}" \
      -l select=1:ncpus=8:mpiprocs=8:mem=16gb \
      -l walltime=08:00:00 \
      -o "${TLTM_ROOT_LOG_SUBDIR}/${method}/chunk_${chunk_id}.pbs.out" \
      -W "depend=afterok:${build_job}" \
      -v "${vars}" \
      codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_chunk.pbs)"
    chunk_jobs+=("${job}")
    chunk_methods+=("${method}")
    chunk_ids+=("${chunk_id}")
  done
done

deps="$(IFS=:; echo "${chunk_jobs[*]}")"
merge_vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${TLTM_REF_LABEL},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${TLTM_ROOT_SUBDIR},TLTM_ROOT_LOG_SUBDIR=${TLTM_ROOT_LOG_SUBDIR},TLTM_EXPECTED_ROWS_PER_METHOD=32,TLTM_REQUESTED_CPUS=64,TLTM_CHUNKS_LABEL=F20D_R3_double_candidate_validation_chunks,TLTM_REFERENCE_COMPARISON_ROOT=${TLTM_REFERENCE_COMPARISON_ROOT}"
merge_job="$(run_qsub \
  -N f20dvalm \
  -q "${TLTM_F20D_MERGE_QUEUE}" \
  -l select=1:ncpus=1:mpiprocs=1:mem=4gb \
  -l walltime=01:00:00 \
  -o "${TLTM_ROOT_LOG_SUBDIR}/merge/merge.pbs.out" \
  -W "depend=afterok:${deps}" \
  -v "${merge_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_merge_level.pbs)"

manifest="${TLTM_ROOT_LOG_SUBDIR}/submit/submit_manifest_${stamp}.env"
queue_plan="${TLTM_ROOT_LOG_SUBDIR}/submit/submit_queue_plan_${stamp}.json"
{
  echo "submitted_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "dry_run=${TLTM_DRY_RUN}"
  echo "launcher=submit_f20d_double_candidate_validation_r3_32seed_50k.sh"
  echo "scheduler_authority=${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}"
  echo "scheduler_request_id=${TLTM_SCHEDULER_REQUEST_ID:-dry_run}"
  echo "profile=${TLTM_F20D_PROFILE}"
  echo "scale=1_profile_x_2_methods_x_32seed_x_50000cycles"
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
  echo "qn_official_dfols_model_rel_tol=${QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"
  echo "build_queue=${TLTM_F20D_BUILD_QUEUE}"
  echo "chunk_queue=${TLTM_F20D_CHUNK_QUEUE}"
  echo "merge_queue=${TLTM_F20D_MERGE_QUEUE}"
  echo "build_job=${build_job}"
  for i in "${!chunk_jobs[@]}"; do
    echo "chunk_${i}_method=${chunk_methods[$i]}"
    echo "chunk_${i}_chunk_id=${chunk_ids[$i]}"
    echo "chunk_${i}_job=${chunk_jobs[$i]}"
  done
  echo "merge_job=${merge_job}"
  echo "queue_plan=${queue_plan}"
} > "${manifest}"

{
  echo "{"
  echo "  \"dry_run\": ${TLTM_DRY_RUN},"
  echo "  \"launcher\": \"submit_f20d_double_candidate_validation_r3_32seed_50k.sh\","
  echo "  \"queue_source\": \"cluster02_scheduler_agent_required\","
  echo "  \"scheduler_authority\": \"${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}\","
  echo "  \"scheduler_request_id\": \"${TLTM_SCHEDULER_REQUEST_ID:-dry_run}\","
  echo "  \"profile\": \"${TLTM_F20D_PROFILE}\","
  echo "  \"scale\": \"1_profile_x_2_methods_x_32seed_x_50000cycles\","
  echo "  \"expected_commit\": \"${TLTM_EXPECTED_GIT_COMMIT}\","
  echo "  \"config\": \"${TLTM_CONFIG_JSON}\","
  echo "  \"output_root\": \"${TLTM_ROOT_SUBDIR}\","
  echo "  \"log_root\": \"${TLTM_ROOT_LOG_SUBDIR}\","
  echo "  \"reference_comparison_root\": \"${TLTM_REFERENCE_COMPARISON_ROOT}\","
  echo "  \"tolerances\": {"
  echo "    \"TLTM_STAGE2_ABS_TOL_OVERRIDE\": \"${TLTM_STAGE2_ABS_TOL_OVERRIDE}\","
  echo "    \"TLTM_STAGE2_REL_TOL_OVERRIDE\": \"${TLTM_STAGE2_REL_TOL_OVERRIDE}\","
  echo "    \"TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE\": \"${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE}\","
  echo "    \"QN_QUASI_TOL_OVERRIDE\": \"${QN_QUASI_TOL_OVERRIDE}\","
  echo "    \"QN_REVERSE_GATE_TOL\": \"${QN_REVERSE_GATE_TOL}\","
  echo "    \"QN_OFFICIAL_DFOLS_RHOEND\": \"${QN_OFFICIAL_DFOLS_RHOEND}\","
  echo "    \"QN_OFFICIAL_DFOLS_MODEL_ABS_TOL\": \"${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL}\","
  echo "    \"QN_OFFICIAL_DFOLS_MODEL_REL_TOL\": \"${QN_OFFICIAL_DFOLS_MODEL_REL_TOL}\""
  echo "  },"
  echo "  \"jobs\": ["
  echo "    {\"role\": \"build\", \"name\": \"f20dvalbld\", \"queue\": \"${TLTM_F20D_BUILD_QUEUE}\", \"ncpus\": 16, \"walltime\": \"02:00:00\", \"job\": \"${build_job}\"},"
  for i in "${!chunk_jobs[@]}"; do
    printf '    {"role": "chunk", "method": "%s", "chunk_id": "%s", "queue": "%s", "ncpus": 8, "walltime": "08:00:00", "job": "%s"}' \
      "${chunk_methods[$i]}" "${chunk_ids[$i]}" "${TLTM_F20D_CHUNK_QUEUE}" "${chunk_jobs[$i]}"
    echo ","
  done
  echo "    {\"role\": \"merge\", \"name\": \"f20dvalm\", \"queue\": \"${TLTM_F20D_MERGE_QUEUE}\", \"ncpus\": 1, \"walltime\": \"01:00:00\", \"reference_comparison_root\": \"${TLTM_REFERENCE_COMPARISON_ROOT}\", \"job\": \"${merge_job}\"}"
  echo "  ],"
  echo "  \"readback_required\": ["
  echo "    \"no_fb/per_seed_summary_table.csv has 32 rows\","
  echo "    \"fb_norefine/per_seed_summary_table.csv has 32 rows\","
  echo "    \"both methods have aggregated_summary_table.csv\","
  echo "    \"protocol audit passes\","
  echo "    \"preflight log has no Python.h/libpython/pyconfig failure\","
  echo "    \"compare against R3 strict/current accepted reference\","
  echo "    \"report mean Ohat Re/Im, seed std, cycle/jackknife error, Z_mean, P68/P95, unresolved/projection failures, RG rejects, ODEX counters, and runtime\""
  echo "  ]"
  echo "}"
} > "${queue_plan}"

echo "submit_manifest=${manifest}"
echo "queue_plan=${queue_plan}"
echo "reference_comparison_root=${TLTM_REFERENCE_COMPARISON_ROOT}"
echo "output_root=${TLTM_ROOT_SUBDIR}"
echo "log_root=${TLTM_ROOT_LOG_SUBDIR}"
echo "build_job=${build_job}"
for i in "${!chunk_jobs[@]}"; do
  echo "chunk_${i}_${chunk_methods[$i]}_${chunk_ids[$i]}_job=${chunk_jobs[$i]}"
done
echo "merge_job=${merge_job}"

#!/bin/bash
# Prepare or submit F20F fixed-flow t=0.5 no_fb single-replica runs.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

: "${TLTM_WORKTREE:=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization}"
: "${TLTM_EXPECTED_GIT_BRANCH:=codex/fortran-modernization}"
: "${TLTM_EXPECTED_GIT_COMMIT:=$(git rev-parse HEAD)}"
: "${TLTM_F20F_FIXED_FLOW_T050_SCALE:=route_smoke}"
: "${TLTM_RUN_GUARDRAILS:=1}"
: "${TLTM_BUILD_JOBS:=1}"
: "${TLTM_ALLOW_OVERWRITE:=0}"
: "${TLTM_DRY_RUN:=0}"
: "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:=}"
: "${TLTM_SCHEDULER_REQUEST_ID:=}"

# Queue choice belongs to the cluster02 scheduler. Dry-runs use placeholders;
# real submissions require the scheduler to provide concrete queue names.
: "${TLTM_F20F_FIXED_FLOW_BUILD_QUEUE:=SCHEDULER_ASSIGN_BUILD_QUEUE}"
: "${TLTM_F20F_FIXED_FLOW_CHUNK_QUEUE:=SCHEDULER_ASSIGN_CHUNK_QUEUE}"
: "${TLTM_F20F_FIXED_FLOW_MERGE_QUEUE:=SCHEDULER_ASSIGN_MERGE_QUEUE}"

: "${TLTM_F20F_PROFILE:=f20f_most_conservative_double}"
: "${TLTM_STAGE2_ABS_TOL_OVERRIDE:=1e-14}"
: "${TLTM_STAGE2_REL_TOL_OVERRIDE:=1e-14}"
: "${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE:=1e-13}"
: "${QN_QUASI_TOL_OVERRIDE:=1e-13}"
: "${QN_REVERSE_GATE_TOL:=1e-8}"
: "${QN_OFFICIAL_DFOLS_RHOEND:=1e-16}"
: "${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL:=1e-26}"
: "${QN_OFFICIAL_DFOLS_MODEL_REL_TOL:=0}"

case "${TLTM_F20F_FIXED_FLOW_T050_SCALE}" in
  route_smoke)
    config_json="docs/f20f_fixed_flow_t050_nofb_route_smoke_2seed_100cyc.json"
    ref_level="F20F_FIXED_FLOW_T050_NOFB_ROUTE_SMOKE"
    scale_text="nofb_2seed_x_100cycles"
    expected_rows=2
    requested_cpus=4
    chunk_ncpus=2
    max_seeds=2
    chunk_walltime="01:00:00"
    chunks=(00)
    ;;
  production_128x200k)
    config_json="docs/f20f_fixed_flow_t050_nofb_128seed_200k.json"
    ref_level="F20F_FIXED_FLOW_T050_NOFB_128SEED_200K"
    scale_text="nofb_128seed_x_200000cycles"
    expected_rows=128
    requested_cpus=128
    chunk_ncpus=8
    max_seeds=8
    chunk_walltime="24:00:00"
    chunks=(00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15)
    ;;
  *)
    echo "[ERROR] unsupported TLTM_F20F_FIXED_FLOW_T050_SCALE=${TLTM_F20F_FIXED_FLOW_T050_SCALE}" >&2
    echo "[ERROR] expected route_smoke or production_128x200k" >&2
    exit 2
    ;;
esac

stamp="$(date +%Y%m%dT%H%M%S)"
short_commit="$(git rev-parse --short=12 "${TLTM_EXPECTED_GIT_COMMIT}")"
: "${TLTM_CONFIG_JSON:=${config_json}}"
: "${TLTM_REF_LEVEL:=${ref_level}}"
: "${TLTM_REF_LABEL:=f20f_fixed_flow_t050_${scale_text}_${short_commit}}"
: "${TLTM_ROOT_SUBDIR:=output/tests/f20f_fixed_flow_t050/${TLTM_REF_LABEL}}"
: "${TLTM_ROOT_LOG_SUBDIR:=output/logs/f20f_fixed_flow_t050/${TLTM_REF_LABEL}}"

methods=(no_fb)
method_list="no_fb"

if [ "${TLTM_DRY_RUN}" != "1" ]; then
  if [ "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY}" != "cluster02_scheduler" ] || [ -z "${TLTM_SCHEDULER_REQUEST_ID}" ]; then
    echo "[ERROR] Actual PBS submission is owned by the cluster02 scheduling agent." >&2
    echo "[ERROR] Use TLTM_DRY_RUN=1 here, or let the scheduler set TLTM_CLUSTER02_SCHEDULER_AUTHORITY and TLTM_SCHEDULER_REQUEST_ID." >&2
    exit 2
  fi
  for queue in "${TLTM_F20F_FIXED_FLOW_BUILD_QUEUE}" "${TLTM_F20F_FIXED_FLOW_CHUNK_QUEUE}" "${TLTM_F20F_FIXED_FLOW_MERGE_QUEUE}"; do
    case "${queue}" in
      ""|SCHEDULER_ASSIGN_*)
        echo "[ERROR] scheduler must provide concrete queue names before real submit." >&2
        exit 2
        ;;
    esac
  done
  if [ -n "$(git status --porcelain)" ]; then
    echo "[ERROR] working tree is dirty; commit/sync before submitting F20F fixed-flow t=0.5 no_fb run." >&2
    git status --short >&2
    exit 2
  fi
fi

mkdir -p "${TLTM_ROOT_LOG_SUBDIR}/submit" "${TLTM_ROOT_LOG_SUBDIR}/merge"
for method in "${methods[@]}"; do
  mkdir -p "${TLTM_ROOT_LOG_SUBDIR}/${method}"
done

common_vars="TLTM_WORKTREE=${TLTM_WORKTREE},TLTM_EXPECTED_GIT_BRANCH=${TLTM_EXPECTED_GIT_BRANCH},TLTM_EXPECTED_GIT_COMMIT=${TLTM_EXPECTED_GIT_COMMIT}"
tol_vars="TLTM_TOLERANCE_PROFILE_LABEL=${TLTM_F20F_PROFILE},TLTM_STAGE2_ABS_TOL_OVERRIDE=${TLTM_STAGE2_ABS_TOL_OVERRIDE},TLTM_STAGE2_REL_TOL_OVERRIDE=${TLTM_STAGE2_REL_TOL_OVERRIDE},TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE},QN_QUASI_TOL_OVERRIDE=${QN_QUASI_TOL_OVERRIDE},QN_REVERSE_GATE_TOL=${QN_REVERSE_GATE_TOL},QN_OFFICIAL_DFOLS_RHOEND=${QN_OFFICIAL_DFOLS_RHOEND},QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL},QN_OFFICIAL_DFOLS_MODEL_REL_TOL=${QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"

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
  -N ff50nbld \
  -q "${TLTM_F20F_FIXED_FLOW_BUILD_QUEUE}" \
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
  for chunk_id in "${chunks[@]}"; do
    seed_offset=$((10#${chunk_id} * max_seeds))
    vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${TLTM_REF_LABEL},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${TLTM_ROOT_SUBDIR},TLTM_ROOT_LOG_SUBDIR=${TLTM_ROOT_LOG_SUBDIR},TLTM_METHOD=${method},TLTM_CHUNK_ID=${chunk_id},TLTM_SEED_OFFSET=${seed_offset},TLTM_MAX_SEEDS=${max_seeds},TLTM_JOBS=${max_seeds},TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE}"
    job="$(run_qsub \
      -N "ff50${method_short}${chunk_id}" \
      -q "${TLTM_F20F_FIXED_FLOW_CHUNK_QUEUE}" \
      -l "select=1:ncpus=${chunk_ncpus}:mpiprocs=${chunk_ncpus}:mem=16gb" \
      -l "walltime=${chunk_walltime}" \
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
merge_vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${TLTM_REF_LABEL},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${TLTM_ROOT_SUBDIR},TLTM_ROOT_LOG_SUBDIR=${TLTM_ROOT_LOG_SUBDIR},TLTM_EXPECTED_ROWS_PER_METHOD=${expected_rows},TLTM_REQUESTED_CPUS=${requested_cpus},TLTM_CHUNKS_LABEL=${TLTM_REF_LEVEL}_chunks,TLTM_METHODS=${method_list}"
merge_job="$(run_qsub \
  -N ff50nmrg \
  -q "${TLTM_F20F_FIXED_FLOW_MERGE_QUEUE}" \
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
  echo "launcher=submit_f20f_fixed_flow_t050_nofb.sh"
  echo "scheduler_authority=${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}"
  echo "scheduler_request_id=${TLTM_SCHEDULER_REQUEST_ID:-dry_run}"
  echo "profile=${TLTM_F20F_PROFILE}"
  echo "scale=${TLTM_F20F_FIXED_FLOW_T050_SCALE}"
  echo "scale_text=${scale_text}"
  echo "methods=${method_list}"
  echo "worktree=${TLTM_WORKTREE}"
  echo "expected_branch=${TLTM_EXPECTED_GIT_BRANCH}"
  echo "expected_commit=${TLTM_EXPECTED_GIT_COMMIT}"
  echo "config=${TLTM_CONFIG_JSON}"
  echo "output_root=${TLTM_ROOT_SUBDIR}"
  echo "log_root=${TLTM_ROOT_LOG_SUBDIR}"
  echo "expected_rows_per_method=${expected_rows}"
  echo "abs_tol=${TLTM_STAGE2_ABS_TOL_OVERRIDE}"
  echo "rel_tol=${TLTM_STAGE2_REL_TOL_OVERRIDE}"
  echo "constraint_tol=${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE}"
  echo "qn_quasi_tol=${QN_QUASI_TOL_OVERRIDE}"
  echo "reverse_gate_tol=${QN_REVERSE_GATE_TOL}"
  echo "qn_official_dfols_rhoend=${QN_OFFICIAL_DFOLS_RHOEND}"
  echo "qn_official_dfols_model_abs_tol=${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL}"
  echo "qn_official_dfols_model_rel_tol=${QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"
  echo "build_queue=${TLTM_F20F_FIXED_FLOW_BUILD_QUEUE}"
  echo "chunk_queue=${TLTM_F20F_FIXED_FLOW_CHUNK_QUEUE}"
  echo "merge_queue=${TLTM_F20F_FIXED_FLOW_MERGE_QUEUE}"
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
  echo "  \"launcher\": \"submit_f20f_fixed_flow_t050_nofb.sh\","
  echo "  \"queue_source\": \"cluster02_scheduler_agent_required\","
  echo "  \"scheduler_authority\": \"${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}\","
  echo "  \"scheduler_request_id\": \"${TLTM_SCHEDULER_REQUEST_ID:-dry_run}\","
  echo "  \"profile\": \"${TLTM_F20F_PROFILE}\","
  echo "  \"scale\": \"${TLTM_F20F_FIXED_FLOW_T050_SCALE}\","
  echo "  \"scale_text\": \"${scale_text}\","
  echo "  \"methods\": [\"no_fb\"],"
  echo "  \"expected_commit\": \"${TLTM_EXPECTED_GIT_COMMIT}\","
  echo "  \"config\": \"${TLTM_CONFIG_JSON}\","
  echo "  \"output_root\": \"${TLTM_ROOT_SUBDIR}\","
  echo "  \"log_root\": \"${TLTM_ROOT_LOG_SUBDIR}\","
  echo "  \"expected_rows_per_method\": ${expected_rows},"
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
  first_job=1
  emit_job() {
    if [ "${first_job}" = "1" ]; then
      first_job=0
    else
      echo ","
    fi
    printf '    %s' "$1"
  }
  emit_job "{\"role\": \"build\", \"name\": \"ff50nbld\", \"queue\": \"${TLTM_F20F_FIXED_FLOW_BUILD_QUEUE}\", \"ncpus\": 16, \"walltime\": \"02:00:00\", \"job\": \"${build_job}\"}"
  for i in "${!chunk_jobs[@]}"; do
    emit_job "{\"role\": \"chunk\", \"method\": \"${chunk_methods[$i]}\", \"chunk_id\": \"${chunk_ids[$i]}\", \"queue\": \"${TLTM_F20F_FIXED_FLOW_CHUNK_QUEUE}\", \"ncpus\": ${chunk_ncpus}, \"walltime\": \"${chunk_walltime}\", \"seed_offset\": $((10#${chunk_ids[$i]} * max_seeds)), \"max_seeds\": ${max_seeds}, \"job\": \"${chunk_jobs[$i]}\"}"
  done
  emit_job "{\"role\": \"merge\", \"name\": \"ff50nmrg\", \"queue\": \"${TLTM_F20F_FIXED_FLOW_MERGE_QUEUE}\", \"ncpus\": 1, \"walltime\": \"01:00:00\", \"methods\": [\"no_fb\"], \"job\": \"${merge_job}\"}"
  echo ""
  echo "  ],"
  echo "  \"readback_required\": ["
  echo "    \"no_fb/per_seed_summary_table.csv has ${expected_rows} rows\","
  echo "    \"no_fb/aggregated_summary_table.csv exists\","
  echo "    \"protocol audit passes for no_fb\","
  echo "    \"stage2 summaries show fixed_flow_mode=T and replica_exchange_active=F\","
  echo "    \"label trace files are header-only for single-replica fixed-flow\","
  echo "    \"preflight log has no Python.h/libpython/pyconfig failure\","
  echo "    \"report no_fb mean Ohat Re/Im, seed std, cycle/jackknife error, Z_mean, P68/P95, unresolved/projection failures, RG rejects, ODEX counters, raw z distribution diagnostics, singularity-distance tails, lag1 autocorrelation, and runtime\""
  echo "  ]"
  echo "}"
} > "${queue_plan}"

echo "submit_manifest=${manifest}"
echo "queue_plan=${queue_plan}"
echo "output_root=${TLTM_ROOT_SUBDIR}"
echo "log_root=${TLTM_ROOT_LOG_SUBDIR}"
echo "build_job=${build_job}"
for i in "${!chunk_jobs[@]}"; do
  echo "chunk_${i}_${chunk_methods[$i]}_${chunk_ids[$i]}_job=${chunk_jobs[$i]}"
done
echo "merge_job=${merge_job}"

#!/bin/bash
# Prepare or submit the F20F t=0.5 no_fb two-replica TLTM ladder short scan.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

: "${TLTM_WORKTREE:=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization}"
: "${TLTM_EXPECTED_GIT_BRANCH:=codex/fortran-modernization}"
: "${TLTM_EXPECTED_GIT_COMMIT:=$(git rev-parse HEAD)}"
: "${TLTM_F20F_TLTM_T050_LADDER_SCAN_SCALE:=short4x5k}"
: "${TLTM_RUN_GUARDRAILS:=1}"
: "${TLTM_BUILD_JOBS:=1}"
: "${TLTM_ALLOW_OVERWRITE:=0}"
: "${TLTM_DRY_RUN:=0}"
: "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:=}"
: "${TLTM_SCHEDULER_REQUEST_ID:=}"

# Queue choice belongs to the cluster02 scheduler. Dry-runs use placeholders;
# real submissions require the scheduler to provide concrete queue names.
: "${TLTM_F20F_TLTM_T050_BUILD_QUEUE:=SCHEDULER_ASSIGN_BUILD_QUEUE}"
: "${TLTM_F20F_TLTM_T050_CHUNK_QUEUE:=SCHEDULER_ASSIGN_CHUNK_QUEUE}"
: "${TLTM_F20F_TLTM_T050_MERGE_QUEUE:=SCHEDULER_ASSIGN_MERGE_QUEUE}"

: "${TLTM_F20F_PROFILE:=f20f_most_conservative_double}"
: "${TLTM_STAGE2_ABS_TOL_OVERRIDE:=1e-14}"
: "${TLTM_STAGE2_REL_TOL_OVERRIDE:=1e-14}"
: "${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE:=1e-13}"
: "${QN_QUASI_TOL_OVERRIDE:=1e-13}"
: "${QN_REVERSE_GATE_TOL:=1e-8}"
: "${QN_OFFICIAL_DFOLS_RHOEND:=1e-16}"
: "${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL:=1e-26}"
: "${QN_OFFICIAL_DFOLS_MODEL_REL_TOL:=0}"

case "${TLTM_F20F_TLTM_T050_LADDER_SCAN_SCALE}" in
  short4x5k)
    scan_level="F20F_TLTM_T050_NOFB_LADDER_SCAN_SHORT4X5K"
    scale_text="4seed_x_5000cycles"
    expected_rows=4
    requested_cpus=16
    chunk_ncpus=4
    max_seeds=4
    chunk_walltime="04:00:00"
    chunks=(00)
    candidates=(low005 low010 low020 low030)
    configs=(
      docs/f20f_tltm_t050_nofb_ladder_low005_4seed_5k.json
      docs/f20f_tltm_t050_nofb_ladder_low010_4seed_5k.json
      docs/f20f_tltm_t050_nofb_ladder_low020_4seed_5k.json
      docs/f20f_tltm_t050_nofb_ladder_low030_4seed_5k.json
    )
    ladders=("0.05,0.5" "0.1,0.5" "0.2,0.5" "0.3,0.5")
    ;;
  *)
    echo "[ERROR] unsupported TLTM_F20F_TLTM_T050_LADDER_SCAN_SCALE=${TLTM_F20F_TLTM_T050_LADDER_SCAN_SCALE}" >&2
    echo "[ERROR] expected short4x5k" >&2
    exit 2
    ;;
esac

stamp="$(date +%Y%m%dT%H%M%S)"
short_commit="$(git rev-parse --short=12 "${TLTM_EXPECTED_GIT_COMMIT}")"
: "${TLTM_SCAN_LABEL:=f20f_tltm_t050_nofb_ladder_scan_${scale_text}_${short_commit}}"
: "${TLTM_ROOT_BASE:=output/tests/f20f_tltm_t050_ladder_scan/${TLTM_SCAN_LABEL}}"
: "${TLTM_ROOT_LOG_BASE:=output/logs/f20f_tltm_t050_ladder_scan/${TLTM_SCAN_LABEL}}"

method="no_fb"
method_list="no_fb"

if [ "${TLTM_DRY_RUN}" != "1" ]; then
  if [ "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY}" != "cluster02_scheduler" ] || [ -z "${TLTM_SCHEDULER_REQUEST_ID}" ]; then
    echo "[ERROR] Actual PBS submission is owned by the cluster02 scheduling agent." >&2
    echo "[ERROR] Use TLTM_DRY_RUN=1 here, or let the scheduler set TLTM_CLUSTER02_SCHEDULER_AUTHORITY and TLTM_SCHEDULER_REQUEST_ID." >&2
    exit 2
  fi
  for queue in "${TLTM_F20F_TLTM_T050_BUILD_QUEUE}" "${TLTM_F20F_TLTM_T050_CHUNK_QUEUE}" "${TLTM_F20F_TLTM_T050_MERGE_QUEUE}"; do
    case "${queue}" in
      ""|SCHEDULER_ASSIGN_*)
        echo "[ERROR] scheduler must provide concrete queue names before real submit." >&2
        exit 2
        ;;
    esac
  done
  if [ -n "$(git status --porcelain)" ]; then
    echo "[ERROR] working tree is dirty; commit/sync before submitting F20F t=0.5 TLTM ladder scan." >&2
    git status --short >&2
    exit 2
  fi
fi

mkdir -p "${TLTM_ROOT_LOG_BASE}/submit"

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
  -N f50tlbld \
  -q "${TLTM_F20F_TLTM_T050_BUILD_QUEUE}" \
  -l select=1:ncpus=16:mpiprocs=16:mem=16gb \
  -l walltime=02:00:00 \
  -o "${TLTM_ROOT_LOG_BASE}/submit/preflight.pbs.out" \
  -v "${build_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_preflight_build.pbs)"

chunk_jobs=()
chunk_candidates=()
chunk_ids=()
merge_jobs=()
for idx in "${!candidates[@]}"; do
  candidate="${candidates[$idx]}"
  config_json="${configs[$idx]}"
  candidate_upper="$(printf '%s' "${candidate}" | tr '[:lower:]' '[:upper:]')"
  ref_level="${scan_level}_${candidate_upper}"
  ref_label="${TLTM_SCAN_LABEL}_${candidate}"
  candidate_root="${TLTM_ROOT_BASE}/${candidate}"
  candidate_log_root="${TLTM_ROOT_LOG_BASE}/${candidate}"
  mkdir -p "${candidate_log_root}/submit" "${candidate_log_root}/merge" "${candidate_log_root}/${method}"

  candidate_chunk_jobs=()
  for chunk_id in "${chunks[@]}"; do
    seed_offset=$((10#${chunk_id} * max_seeds))
    vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${ref_level},TLTM_REF_LABEL=${ref_label},TLTM_CONFIG_JSON=${config_json},TLTM_ROOT_SUBDIR=${candidate_root},TLTM_ROOT_LOG_SUBDIR=${candidate_log_root},TLTM_METHOD=${method},TLTM_CHUNK_ID=${chunk_id},TLTM_SEED_OFFSET=${seed_offset},TLTM_MAX_SEEDS=${max_seeds},TLTM_JOBS=${max_seeds},TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE}"
    job="$(run_qsub \
      -N "f50${candidate}nf${chunk_id}" \
      -q "${TLTM_F20F_TLTM_T050_CHUNK_QUEUE}" \
      -l "select=1:ncpus=${chunk_ncpus}:mpiprocs=${chunk_ncpus}:mem=16gb" \
      -l "walltime=${chunk_walltime}" \
      -o "${candidate_log_root}/${method}/chunk_${chunk_id}.pbs.out" \
      -W "depend=afterok:${build_job}" \
      -v "${vars}" \
      codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_chunk.pbs)"
    chunk_jobs+=("${job}")
    chunk_candidates+=("${candidate}")
    chunk_ids+=("${chunk_id}")
    candidate_chunk_jobs+=("${job}")
  done

  deps="$(IFS=:; echo "${candidate_chunk_jobs[*]}")"
  merge_vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${ref_level},TLTM_REF_LABEL=${ref_label},TLTM_CONFIG_JSON=${config_json},TLTM_ROOT_SUBDIR=${candidate_root},TLTM_ROOT_LOG_SUBDIR=${candidate_log_root},TLTM_EXPECTED_ROWS_PER_METHOD=${expected_rows},TLTM_REQUESTED_CPUS=${requested_cpus},TLTM_CHUNKS_LABEL=${ref_level}_chunks,TLTM_METHODS=${method_list}"
  merge_job="$(run_qsub \
    -N "f50${candidate}mrg" \
    -q "${TLTM_F20F_TLTM_T050_MERGE_QUEUE}" \
    -l select=1:ncpus=1:mpiprocs=1:mem=4gb \
    -l walltime=01:00:00 \
    -o "${candidate_log_root}/merge/merge.pbs.out" \
    -W "depend=afterok:${deps}" \
    -v "${merge_vars}" \
    codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_merge_level.pbs)"
  merge_jobs+=("${merge_job}")
done

manifest="${TLTM_ROOT_LOG_BASE}/submit/submit_manifest_${stamp}.env"
queue_plan="${TLTM_ROOT_LOG_BASE}/submit/submit_queue_plan_${stamp}.json"
{
  echo "submitted_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "dry_run=${TLTM_DRY_RUN}"
  echo "launcher=submit_f20f_tltm_t050_nofb_ladder_scan.sh"
  echo "scheduler_authority=${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}"
  echo "scheduler_request_id=${TLTM_SCHEDULER_REQUEST_ID:-dry_run}"
  echo "profile=${TLTM_F20F_PROFILE}"
  echo "scale=${TLTM_F20F_TLTM_T050_LADDER_SCAN_SCALE}"
  echo "scale_text=${scale_text}"
  echo "methods=${method_list}"
  echo "worktree=${TLTM_WORKTREE}"
  echo "expected_branch=${TLTM_EXPECTED_GIT_BRANCH}"
  echo "expected_commit=${TLTM_EXPECTED_GIT_COMMIT}"
  echo "scan_level=${scan_level}"
  echo "scan_label=${TLTM_SCAN_LABEL}"
  echo "output_root_base=${TLTM_ROOT_BASE}"
  echo "log_root_base=${TLTM_ROOT_LOG_BASE}"
  echo "expected_rows_per_candidate=${expected_rows}"
  echo "abs_tol=${TLTM_STAGE2_ABS_TOL_OVERRIDE}"
  echo "rel_tol=${TLTM_STAGE2_REL_TOL_OVERRIDE}"
  echo "constraint_tol=${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE}"
  echo "qn_quasi_tol=${QN_QUASI_TOL_OVERRIDE}"
  echo "reverse_gate_tol=${QN_REVERSE_GATE_TOL}"
  echo "qn_official_dfols_rhoend=${QN_OFFICIAL_DFOLS_RHOEND}"
  echo "qn_official_dfols_model_abs_tol=${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL}"
  echo "qn_official_dfols_model_rel_tol=${QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"
  echo "build_queue=${TLTM_F20F_TLTM_T050_BUILD_QUEUE}"
  echo "chunk_queue=${TLTM_F20F_TLTM_T050_CHUNK_QUEUE}"
  echo "merge_queue=${TLTM_F20F_TLTM_T050_MERGE_QUEUE}"
  echo "build_job=${build_job}"
  for idx in "${!candidates[@]}"; do
    echo "candidate_${idx}_id=${candidates[$idx]}"
    echo "candidate_${idx}_ladder=${ladders[$idx]}"
    echo "candidate_${idx}_config=${configs[$idx]}"
    echo "candidate_${idx}_output_root=${TLTM_ROOT_BASE}/${candidates[$idx]}"
    echo "candidate_${idx}_log_root=${TLTM_ROOT_LOG_BASE}/${candidates[$idx]}"
    echo "candidate_${idx}_merge_job=${merge_jobs[$idx]}"
  done
  for i in "${!chunk_jobs[@]}"; do
    echo "chunk_${i}_candidate=${chunk_candidates[$i]}"
    echo "chunk_${i}_chunk_id=${chunk_ids[$i]}"
    echo "chunk_${i}_job=${chunk_jobs[$i]}"
  done
  echo "queue_plan=${queue_plan}"
} > "${manifest}"

{
  echo "{"
  echo "  \"dry_run\": ${TLTM_DRY_RUN},"
  echo "  \"launcher\": \"submit_f20f_tltm_t050_nofb_ladder_scan.sh\","
  echo "  \"queue_source\": \"cluster02_scheduler_agent_required\","
  echo "  \"scheduler_authority\": \"${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}\","
  echo "  \"scheduler_request_id\": \"${TLTM_SCHEDULER_REQUEST_ID:-dry_run}\","
  echo "  \"profile\": \"${TLTM_F20F_PROFILE}\","
  echo "  \"scale\": \"${TLTM_F20F_TLTM_T050_LADDER_SCAN_SCALE}\","
  echo "  \"scale_text\": \"${scale_text}\","
  echo "  \"scan_label\": \"${TLTM_SCAN_LABEL}\","
  echo "  \"methods\": [\"no_fb\"],"
  echo "  \"expected_commit\": \"${TLTM_EXPECTED_GIT_COMMIT}\","
  echo "  \"output_root_base\": \"${TLTM_ROOT_BASE}\","
  echo "  \"log_root_base\": \"${TLTM_ROOT_LOG_BASE}\","
  echo "  \"expected_rows_per_candidate\": ${expected_rows},"
  echo "  \"candidate_selection_rule\": \"Prefer 2-slot ladders with pair0_accept_rate >= 0.10, total_round_trip > 0, restored high-flow Re z sign motion, and no high-flow Ohat_re lock near the fixed-flow t=0.5 no_fb pathology.\","
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
  echo "  \"candidates\": ["
  for idx in "${!candidates[@]}"; do
    if [ "${idx}" != "0" ]; then
      echo ","
    fi
    printf '    {"id": "%s", "ladder": "%s", "config": "%s", "output_root": "%s/%s", "log_root": "%s/%s", "merge_job": "%s"}' \
      "${candidates[$idx]}" "${ladders[$idx]}" "${configs[$idx]}" "${TLTM_ROOT_BASE}" "${candidates[$idx]}" "${TLTM_ROOT_LOG_BASE}" "${candidates[$idx]}" "${merge_jobs[$idx]}"
  done
  echo ""
  echo "  ],"
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
  emit_job "{\"role\": \"build\", \"name\": \"f50tlbld\", \"queue\": \"${TLTM_F20F_TLTM_T050_BUILD_QUEUE}\", \"ncpus\": 16, \"walltime\": \"02:00:00\", \"job\": \"${build_job}\"}"
  for i in "${!chunk_jobs[@]}"; do
    emit_job "{\"role\": \"chunk\", \"candidate\": \"${chunk_candidates[$i]}\", \"method\": \"no_fb\", \"chunk_id\": \"${chunk_ids[$i]}\", \"queue\": \"${TLTM_F20F_TLTM_T050_CHUNK_QUEUE}\", \"ncpus\": ${chunk_ncpus}, \"walltime\": \"${chunk_walltime}\", \"seed_offset\": $((10#${chunk_ids[$i]} * max_seeds)), \"max_seeds\": ${max_seeds}, \"job\": \"${chunk_jobs[$i]}\"}"
  done
  for idx in "${!merge_jobs[@]}"; do
    emit_job "{\"role\": \"merge\", \"candidate\": \"${candidates[$idx]}\", \"queue\": \"${TLTM_F20F_TLTM_T050_MERGE_QUEUE}\", \"ncpus\": 1, \"walltime\": \"01:00:00\", \"methods\": [\"no_fb\"], \"job\": \"${merge_jobs[$idx]}\"}"
  done
  echo ""
  echo "  ],"
  echo "  \"readback_required\": ["
  echo "    \"each candidate no_fb/per_seed_summary_table.csv has ${expected_rows} rows\","
  echo "    \"each candidate no_fb/aggregated_summary_table.csv exists\","
  echo "    \"protocol audit passes for every candidate seed\","
  echo "    \"stage2 summaries show fixed_flow_mode=F and replica_exchange_active=T\","
  echo "    \"preflight log has no Python.h/libpython/pyconfig failure\","
  echo "    \"report candidate table: ladder, pair0_accept_rate, total_round_trip, hot_end_hit_count, high-flow Re z sign changes/occupancy, Ohat Re/Im, unresolved/projection failures, RG rejects, ODEX counters, and runtime\""
  echo "  ]"
  echo "}"
} > "${queue_plan}"

echo "submit_manifest=${manifest}"
echo "queue_plan=${queue_plan}"

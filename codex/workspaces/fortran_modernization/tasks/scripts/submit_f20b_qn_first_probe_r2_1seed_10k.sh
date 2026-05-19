#!/bin/bash
# Prepare or submit F20b QN-first loose-ODE probe at R2 1seed/10k scale.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

: "${TLTM_WORKTREE:=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization}"
: "${TLTM_EXPECTED_GIT_BRANCH:=codex/fortran-modernization}"
: "${TLTM_EXPECTED_GIT_COMMIT:=$(git rev-parse HEAD)}"
: "${TLTM_CONFIG_JSON:=docs/modernization_reference_t035_r2_10seed_10k.json}"
: "${TLTM_RUN_GUARDRAILS:=1}"
: "${TLTM_BUILD_JOBS:=1}"
: "${TLTM_ALLOW_OVERWRITE:=0}"
: "${TLTM_DRY_RUN:=0}"
: "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:=}"
: "${TLTM_SCHEDULER_REQUEST_ID:=}"

# Queue choice belongs to the cluster02 scheduler. Dry-runs use placeholders;
# real submissions require the scheduler to provide concrete queue names.
: "${TLTM_F20_QN_BUILD_QUEUE:=SCHEDULER_ASSIGN_BUILD_QUEUE}"
: "${TLTM_F20_QN_CHUNK_QUEUE:=SCHEDULER_ASSIGN_CHUNK_QUEUE}"
: "${TLTM_F20_QN_MERGE_QUEUE:=SCHEDULER_ASSIGN_MERGE_QUEUE}"

: "${TLTM_STRICT_STAGE2_ABS_TOL:=3e-14}"
: "${TLTM_STRICT_STAGE2_REL_TOL:=3e-14}"
: "${TLTM_STRICT_STAGE2_CONSTRAINT_TOL:=1e-13}"
: "${TLTM_STRICT_QN_QUASI_TOL:=1e-13}"
: "${TLTM_STRICT_QN_REVERSE_GATE_TOL:=1e-8}"
: "${TLTM_STRICT_QN_OFFICIAL_DFOLS_RHOEND:=1e-16}"
: "${TLTM_STRICT_QN_OFFICIAL_DFOLS_MODEL_ABS_TOL:=1e-30}"
: "${TLTM_STRICT_QN_OFFICIAL_DFOLS_MODEL_REL_TOL:=0}"

: "${TLTM_LOOSE_STAGE2_ABS_TOL:=1e-6}"
: "${TLTM_LOOSE_STAGE2_REL_TOL:=1e-6}"
: "${TLTM_LOOSE_STAGE2_CONSTRAINT_TOL:=1e-6}"
: "${TLTM_LOOSE_QN_QUASI_TOL:=1e-6}"
: "${TLTM_LOOSE_QN_REVERSE_GATE_TOL:=1e-4}"
: "${TLTM_LOOSE_QN_OFFICIAL_DFOLS_RHOEND:=1e-6}"
: "${TLTM_LOOSE_QN_OFFICIAL_DFOLS_MODEL_ABS_TOL:=1e-12}"
: "${TLTM_LOOSE_QN_OFFICIAL_DFOLS_MODEL_REL_TOL:=0}"

: "${TLTM_FLOWZ_COST_CAPTURE_LIMIT:=1000}"
: "${TLTM_FLOWZ_COST_CAPTURE_MIN_RHS:=1024}"
: "${TLTM_FLOWZ_COST_CAPTURE_MIN_REJECTED:=64}"

stamp="$(date +%Y%m%dT%H%M%S)"
short_commit="$(git rev-parse --short=12 "${TLTM_EXPECTED_GIT_COMMIT}")"
: "${TLTM_REF_LEVEL:=F20B_QN_FIRST_LOOSE_ODE_PROBE}"
: "${TLTM_ROOT_PREFIX:=output/tests/f20_qn_first_probe}"
: "${TLTM_LOG_PREFIX:=output/logs/f20_qn_first_probe}"

profiles=(strict odex_only all_loose)
methods=(no_fb fb_norefine)

profile_label() {
  case "$1" in
    strict) echo "qnfirst_strict_double" ;;
    odex_only) echo "qnfirst_odex_tol_only1e6" ;;
    all_loose) echo "qnfirst_single_feasible1e6_rg1e4" ;;
    *) echo "[ERROR] unknown profile: $1" >&2; return 2 ;;
  esac
}

profile_code() {
  case "$1" in
    strict) echo "st" ;;
    odex_only) echo "od" ;;
    all_loose) echo "al" ;;
    *) echo "[ERROR] unknown profile: $1" >&2; return 2 ;;
  esac
}

profile_tol_vars() {
  case "$1" in
    strict)
      echo "TLTM_TOLERANCE_PROFILE_LABEL=$(profile_label "$1"),TLTM_STAGE2_ABS_TOL_OVERRIDE=${TLTM_STRICT_STAGE2_ABS_TOL},TLTM_STAGE2_REL_TOL_OVERRIDE=${TLTM_STRICT_STAGE2_REL_TOL},TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=${TLTM_STRICT_STAGE2_CONSTRAINT_TOL},QN_QUASI_TOL_OVERRIDE=${TLTM_STRICT_QN_QUASI_TOL},QN_REVERSE_GATE_TOL=${TLTM_STRICT_QN_REVERSE_GATE_TOL},QN_OFFICIAL_DFOLS_RHOEND=${TLTM_STRICT_QN_OFFICIAL_DFOLS_RHOEND},QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=${TLTM_STRICT_QN_OFFICIAL_DFOLS_MODEL_ABS_TOL},QN_OFFICIAL_DFOLS_MODEL_REL_TOL=${TLTM_STRICT_QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"
      ;;
    odex_only)
      echo "TLTM_TOLERANCE_PROFILE_LABEL=$(profile_label "$1"),TLTM_STAGE2_ABS_TOL_OVERRIDE=${TLTM_LOOSE_STAGE2_ABS_TOL},TLTM_STAGE2_REL_TOL_OVERRIDE=${TLTM_LOOSE_STAGE2_REL_TOL},TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=${TLTM_STRICT_STAGE2_CONSTRAINT_TOL},QN_QUASI_TOL_OVERRIDE=${TLTM_STRICT_QN_QUASI_TOL},QN_REVERSE_GATE_TOL=${TLTM_STRICT_QN_REVERSE_GATE_TOL},QN_OFFICIAL_DFOLS_RHOEND=${TLTM_STRICT_QN_OFFICIAL_DFOLS_RHOEND},QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=${TLTM_STRICT_QN_OFFICIAL_DFOLS_MODEL_ABS_TOL},QN_OFFICIAL_DFOLS_MODEL_REL_TOL=${TLTM_STRICT_QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"
      ;;
    all_loose)
      echo "TLTM_TOLERANCE_PROFILE_LABEL=$(profile_label "$1"),TLTM_STAGE2_ABS_TOL_OVERRIDE=${TLTM_LOOSE_STAGE2_ABS_TOL},TLTM_STAGE2_REL_TOL_OVERRIDE=${TLTM_LOOSE_STAGE2_REL_TOL},TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=${TLTM_LOOSE_STAGE2_CONSTRAINT_TOL},QN_QUASI_TOL_OVERRIDE=${TLTM_LOOSE_QN_QUASI_TOL},QN_REVERSE_GATE_TOL=${TLTM_LOOSE_QN_REVERSE_GATE_TOL},QN_OFFICIAL_DFOLS_RHOEND=${TLTM_LOOSE_QN_OFFICIAL_DFOLS_RHOEND},QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=${TLTM_LOOSE_QN_OFFICIAL_DFOLS_MODEL_ABS_TOL},QN_OFFICIAL_DFOLS_MODEL_REL_TOL=${TLTM_LOOSE_QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"
      ;;
    *) echo "[ERROR] unknown profile: $1" >&2; return 2 ;;
  esac
}

profile_root() {
  local profile="$1"
  echo "${TLTM_ROOT_PREFIX}/f20_$(profile_label "${profile}")_r2_1seed_10k_${short_commit}"
}

profile_log_root() {
  local profile="$1"
  echo "${TLTM_LOG_PREFIX}/f20_$(profile_label "${profile}")_r2_1seed_10k_${short_commit}"
}

if [ "${TLTM_DRY_RUN}" != "1" ]; then
  if [ "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY}" != "cluster02_scheduler" ] || [ -z "${TLTM_SCHEDULER_REQUEST_ID}" ]; then
    echo "[ERROR] Actual PBS submission is owned by the cluster02 scheduling agent." >&2
    echo "[ERROR] Use TLTM_DRY_RUN=1 here, or let the scheduler set TLTM_CLUSTER02_SCHEDULER_AUTHORITY and TLTM_SCHEDULER_REQUEST_ID." >&2
    exit 2
  fi
  for queue in "${TLTM_F20_QN_BUILD_QUEUE}" "${TLTM_F20_QN_CHUNK_QUEUE}" "${TLTM_F20_QN_MERGE_QUEUE}"; do
    case "${queue}" in
      ""|SCHEDULER_ASSIGN_*)
        echo "[ERROR] scheduler must provide concrete queue names before real submit." >&2
        exit 2
        ;;
    esac
  done
  if [ -n "$(git status --porcelain)" ]; then
    echo "[ERROR] working tree is dirty; commit/sync before submitting F20b QN-first probe." >&2
    git status --short >&2
    exit 2
  fi
fi

for profile in "${profiles[@]}"; do
  mkdir -p "$(profile_log_root "${profile}")/submit" "$(profile_log_root "${profile}")/merge"
  for method in "${methods[@]}"; do
    mkdir -p "$(profile_log_root "${profile}")/${method}"
  done
done

common_vars="TLTM_WORKTREE=${TLTM_WORKTREE},TLTM_EXPECTED_GIT_BRANCH=${TLTM_EXPECTED_GIT_BRANCH},TLTM_EXPECTED_GIT_COMMIT=${TLTM_EXPECTED_GIT_COMMIT}"
qn_first_vars="TLTM_QN_FIRST_CONSTRAINT_SOLVER=1"

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

set_job_var() {
  local name="$1"
  local value="$2"
  eval "${name}=\"\${value}\""
}

get_job_var() {
  local name="$1"
  eval "printf '%s' \"\${${name}}\""
}

remote_abs_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "${TLTM_WORKTREE}" "$1" ;;
  esac
}

strict_root="$(profile_root strict)"
build_vars="${common_vars},TLTM_RUN_GUARDRAILS=${TLTM_RUN_GUARDRAILS},TLTM_BUILD_JOBS=${TLTM_BUILD_JOBS}"
build_job="$(run_qsub \
  -N f20qnbld \
  -q "${TLTM_F20_QN_BUILD_QUEUE}" \
  -l select=1:ncpus=16:mpiprocs=16:mem=16gb \
  -l walltime=02:00:00 \
  -o "$(profile_log_root strict)/submit/preflight.pbs.out" \
  -v "${build_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_preflight_build.pbs)"

for profile in "${profiles[@]}"; do
  tol_vars="$(profile_tol_vars "${profile}")"
  ref_label="f20_$(profile_label "${profile}")_r2_1seed_10k_${short_commit}"
  root_subdir="$(profile_root "${profile}")"
  root_log_subdir="$(profile_log_root "${profile}")"
  for method in "${methods[@]}"; do
    method_short="nf"
    if [ "${method}" = "fb_norefine" ]; then
      method_short="fb"
    fi
    capture_file="$(remote_abs_path "${root_subdir}/${method}/chunk_00/flowz_cost_cases.dat")"
    capture_vars="TLTM_FLOWZ_COST_CAPTURE_FILE=${capture_file},TLTM_FLOWZ_COST_CAPTURE_LIMIT=${TLTM_FLOWZ_COST_CAPTURE_LIMIT},TLTM_FLOWZ_COST_CAPTURE_MIN_RHS=${TLTM_FLOWZ_COST_CAPTURE_MIN_RHS},TLTM_FLOWZ_COST_CAPTURE_MIN_REJECTED=${TLTM_FLOWZ_COST_CAPTURE_MIN_REJECTED}"
    chunk_vars="${common_vars},${tol_vars},${qn_first_vars},${capture_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${ref_label},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${root_subdir},TLTM_ROOT_LOG_SUBDIR=${root_log_subdir},TLTM_METHOD=${method},TLTM_CHUNK_ID=00,TLTM_SEED_OFFSET=0,TLTM_MAX_SEEDS=1,TLTM_JOBS=1,TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE}"
    job="$(run_qsub \
      -N "f20qn$(profile_code "${profile}")${method_short}" \
      -q "${TLTM_F20_QN_CHUNK_QUEUE}" \
      -l select=1:ncpus=1:mpiprocs=1:mem=8gb \
      -l walltime=06:00:00 \
      -o "${root_log_subdir}/${method}/chunk_00.pbs.out" \
      -W "depend=afterok:${build_job}" \
      -v "${chunk_vars}" \
      codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_chunk.pbs)"
    set_job_var "chunk_job_${profile}_${method}" "${job}"
  done
done

for profile in "${profiles[@]}"; do
  tol_vars="$(profile_tol_vars "${profile}")"
  ref_label="f20_$(profile_label "${profile}")_r2_1seed_10k_${short_commit}"
  root_subdir="$(profile_root "${profile}")"
  root_log_subdir="$(profile_log_root "${profile}")"
  deps="$(get_job_var "chunk_job_${profile}_no_fb"):$(get_job_var "chunk_job_${profile}_fb_norefine")"
  comparison_root=""
  if [ "${profile}" != "strict" ]; then
    deps="${deps}:$(get_job_var "merge_job_strict")"
    comparison_root="${strict_root}"
  fi
  merge_vars="${common_vars},${tol_vars},${qn_first_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${ref_label},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${root_subdir},TLTM_ROOT_LOG_SUBDIR=${root_log_subdir},TLTM_EXPECTED_ROWS_PER_METHOD=1,TLTM_REQUESTED_CPUS=2,TLTM_CHUNKS_LABEL=F20B_QN_first_probe_chunks,TLTM_REFERENCE_COMPARISON_ROOT=${comparison_root}"
  merge_job="$(run_qsub \
    -N "f20qn$(profile_code "${profile}")m" \
    -q "${TLTM_F20_QN_MERGE_QUEUE}" \
    -l select=1:ncpus=1:mpiprocs=1:mem=4gb \
    -l walltime=01:00:00 \
    -o "${root_log_subdir}/merge/merge.pbs.out" \
    -W "depend=afterok:${deps}" \
    -v "${merge_vars}" \
    codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_merge_level.pbs)"
  set_job_var "merge_job_${profile}" "${merge_job}"
done

manifest="$(profile_log_root all_loose)/submit/submit_manifest_${stamp}.env"
queue_plan="$(profile_log_root all_loose)/submit/submit_queue_plan_${stamp}.json"
{
  echo "submitted_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "dry_run=${TLTM_DRY_RUN}"
  echo "launcher=submit_f20b_qn_first_probe_r2_1seed_10k.sh"
  echo "scheduler_authority=${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}"
  echo "scheduler_request_id=${TLTM_SCHEDULER_REQUEST_ID:-dry_run}"
  echo "scale=3_profiles_x_2_methods_x_1seed_x_10000cycles"
  echo "worktree=${TLTM_WORKTREE}"
  echo "expected_branch=${TLTM_EXPECTED_GIT_BRANCH}"
  echo "expected_commit=${TLTM_EXPECTED_GIT_COMMIT}"
  echo "config=${TLTM_CONFIG_JSON}"
  echo "qn_first_constraint_solver=1"
  echo "cost_capture_limit=${TLTM_FLOWZ_COST_CAPTURE_LIMIT}"
  echo "cost_capture_min_rhs=${TLTM_FLOWZ_COST_CAPTURE_MIN_RHS}"
  echo "cost_capture_min_rejected=${TLTM_FLOWZ_COST_CAPTURE_MIN_REJECTED}"
  echo "strict_output_root=${strict_root}"
  echo "build_queue=${TLTM_F20_QN_BUILD_QUEUE}"
  echo "chunk_queue=${TLTM_F20_QN_CHUNK_QUEUE}"
  echo "merge_queue=${TLTM_F20_QN_MERGE_QUEUE}"
  echo "build_job=${build_job}"
  for profile in "${profiles[@]}"; do
    echo "${profile}_output_root=$(profile_root "${profile}")"
    echo "${profile}_log_root=$(profile_log_root "${profile}")"
    for method in "${methods[@]}"; do
      echo "${profile}_${method}_chunk_00=$(get_job_var "chunk_job_${profile}_${method}")"
      echo "${profile}_${method}_cost_capture_file=$(remote_abs_path "$(profile_root "${profile}")/${method}/chunk_00/flowz_cost_cases.dat")"
    done
    echo "${profile}_merge_job=$(get_job_var "merge_job_${profile}")"
  done
  echo "queue_plan=${queue_plan}"
} > "${manifest}"

{
  echo "{"
  echo "  \"dry_run\": ${TLTM_DRY_RUN},"
  echo "  \"launcher\": \"submit_f20b_qn_first_probe_r2_1seed_10k.sh\","
  echo "  \"queue_source\": \"cluster02_scheduler_agent_required\","
  echo "  \"scheduler_authority\": \"${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}\","
  echo "  \"scheduler_request_id\": \"${TLTM_SCHEDULER_REQUEST_ID:-dry_run}\","
  echo "  \"scale\": \"3_profiles_x_2_methods_x_1seed_x_10000cycles\","
  echo "  \"expected_commit\": \"${TLTM_EXPECTED_GIT_COMMIT}\","
  echo "  \"qn_first_constraint_solver\": true,"
  echo "  \"strict_output_root\": \"${strict_root}\","
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
  emit_job "{\"role\": \"build\", \"name\": \"f20qnbld\", \"queue\": \"${TLTM_F20_QN_BUILD_QUEUE}\", \"ncpus\": 16, \"walltime\": \"02:00:00\", \"job\": \"${build_job}\"}"
  for profile in "${profiles[@]}"; do
    for method in "${methods[@]}"; do
      emit_job "{\"role\": \"chunk\", \"profile\": \"${profile}\", \"method\": \"${method}\", \"queue\": \"${TLTM_F20_QN_CHUNK_QUEUE}\", \"ncpus\": 1, \"walltime\": \"06:00:00\", \"job\": \"$(get_job_var "chunk_job_${profile}_${method}")\"}"
    done
    comparison_root=""
    if [ "${profile}" != "strict" ]; then
      comparison_root="${strict_root}"
    fi
    emit_job "{\"role\": \"merge\", \"profile\": \"${profile}\", \"queue\": \"${TLTM_F20_QN_MERGE_QUEUE}\", \"ncpus\": 1, \"walltime\": \"01:00:00\", \"reference_comparison_root\": \"${comparison_root}\", \"job\": \"$(get_job_var "merge_job_${profile}")\"}"
  done
  echo ""
  echo "  ],"
  echo "  \"profiles\": {"
  first_profile=1
  for profile in "${profiles[@]}"; do
    if [ "${first_profile}" = "1" ]; then
      first_profile=0
    else
      echo ","
    fi
    printf '    "%s": {"label": "%s", "output_root": "%s", "tolerances": "%s"}' \
      "${profile}" "$(profile_label "${profile}")" "$(profile_root "${profile}")" "$(profile_tol_vars "${profile}")"
  done
  echo ""
  echo "  },"
  echo "  \"readback_required\": ["
  echo "    \"each profile/method per_seed_summary_table.csv has 1 row\","
  echo "    \"fb_norefine stage2 manifests include TLTM_QN_FIRST_CONSTRAINT_SOLVER=1\","
  echo "    \"fb_norefine newton success/eval counters are suppressed or zero relative to QN counters\","
  echo "    \"aggregates include total_odex_* telemetry and protocol audit passes\","
  echo "    \"cost capture files expose any remaining high-cost flowz stage/role\","
  echo "    \"preflight log has no Python.h/libpython/pyconfig failure\","
  echo "    \"odex_only and all_loose compare against same-run qnfirst strict output\""
  echo "  ]"
  echo "}"
} > "${queue_plan}"

echo "submit_manifest=${manifest}"
echo "queue_plan=${queue_plan}"
echo "strict_output_root=${strict_root}"
for profile in "${profiles[@]}"; do
  echo "${profile}_output_root=$(profile_root "${profile}")"
done
echo "build_job=${build_job}"
for profile in "${profiles[@]}"; do
  for method in "${methods[@]}"; do
    echo "${profile}_${method}_job=$(get_job_var "chunk_job_${profile}_${method}")"
  done
  echo "${profile}_merge_job=$(get_job_var "merge_job_${profile}")"
done

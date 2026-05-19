#!/bin/bash
# Prepare or submit F20c NT/QN/DFO-LS shared tolerance scan, R2 10seed/10k.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

: "${TLTM_WORKTREE:=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization}"
: "${TLTM_EXPECTED_GIT_BRANCH:=codex/fortran-modernization}"
: "${TLTM_EXPECTED_GIT_COMMIT:=$(git rev-parse HEAD)}"
: "${TLTM_CONFIG_JSON:=docs/modernization_reference_t035_r2_10seed_10k.json}"
: "${TLTM_REFERENCE_COMPARISON_ROOT:=output/tests/f20_double_tolerance_calibration/f20b_ode_absrel1e12_strict_newton_r2_10seed_10k_bc3add0fe8e7}"
: "${TLTM_RUN_GUARDRAILS:=1}"
: "${TLTM_BUILD_JOBS:=1}"
: "${TLTM_ALLOW_OVERWRITE:=0}"
: "${TLTM_DRY_RUN:=0}"
: "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:=}"
: "${TLTM_SCHEDULER_REQUEST_ID:=}"

# Queue choice belongs to the cluster02 scheduler. Dry-runs use placeholders;
# real submissions require the scheduler to provide concrete queue names.
: "${TLTM_F20_BUILD_QUEUE:=SCHEDULER_ASSIGN_BUILD_QUEUE}"
: "${TLTM_F20_CHUNK_QUEUE:=SCHEDULER_ASSIGN_CHUNK_QUEUE}"
: "${TLTM_F20_MERGE_QUEUE:=SCHEDULER_ASSIGN_MERGE_QUEUE}"

: "${TLTM_FIXED_STAGE2_ABS_TOL:=1e-12}"
: "${TLTM_FIXED_STAGE2_REL_TOL:=1e-12}"
: "${TLTM_STRICT_QN_REVERSE_GATE_TOL:=1e-8}"
: "${TLTM_QN_OFFICIAL_DFOLS_MODEL_REL_TOL:=0}"

stamp="$(date +%Y%m%dT%H%M%S)"
short_commit="$(git rev-parse --short=12 "${TLTM_EXPECTED_GIT_COMMIT}")"
: "${TLTM_REF_LEVEL:=F20C_R2_NTQN_DFOLS_TOLERANCE_SCAN}"
: "${TLTM_ROOT_PREFIX:=output/tests/f20_double_tolerance_calibration}"
: "${TLTM_LOG_PREFIX:=output/logs/f20_double_tolerance_calibration}"

profiles=(
  tau_1e12
  tau_1e10
  tau_1e8
)
methods=(no_fb fb_norefine)

profile_label() {
  case "$1" in
    tau_1e12) echo "ode1e12_ntqn_dfols_tau1e12" ;;
    tau_1e10) echo "ode1e12_ntqn_dfols_tau1e10" ;;
    tau_1e8) echo "ode1e12_ntqn_dfols_tau1e8" ;;
    *) echo "[ERROR] unknown profile: $1" >&2; return 2 ;;
  esac
}

profile_tau() {
  case "$1" in
    tau_1e12) echo "1e-12" ;;
    tau_1e10) echo "1e-10" ;;
    tau_1e8) echo "1e-8" ;;
    *) echo "[ERROR] unknown profile: $1" >&2; return 2 ;;
  esac
}

profile_dfols_model_abs_tol() {
  case "$1" in
    tau_1e12) echo "1e-24" ;;
    tau_1e10) echo "1e-20" ;;
    tau_1e8) echo "1e-16" ;;
    *) echo "[ERROR] unknown profile: $1" >&2; return 2 ;;
  esac
}

profile_dfols_rhoend() {
  case "$1" in
    tau_1e12) echo "1e-15" ;;
    tau_1e10) echo "1e-13" ;;
    tau_1e8) echo "1e-11" ;;
    *) echo "[ERROR] unknown profile: $1" >&2; return 2 ;;
  esac
}

profile_short() {
  case "$1" in
    tau_1e12) echo "t12" ;;
    tau_1e10) echo "t10" ;;
    tau_1e8) echo "t8" ;;
    *) echo "[ERROR] unknown profile: $1" >&2; return 2 ;;
  esac
}

profile_tol_vars() {
  local profile="$1"
  local label tau model_abs rhoend
  label="$(profile_label "${profile}")"
  tau="$(profile_tau "${profile}")"
  model_abs="$(profile_dfols_model_abs_tol "${profile}")"
  rhoend="$(profile_dfols_rhoend "${profile}")"
  echo "TLTM_TOLERANCE_PROFILE_LABEL=${label},TLTM_STAGE2_ABS_TOL_OVERRIDE=${TLTM_FIXED_STAGE2_ABS_TOL},TLTM_STAGE2_REL_TOL_OVERRIDE=${TLTM_FIXED_STAGE2_REL_TOL},TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=${tau},QN_QUASI_TOL_OVERRIDE=${tau},QN_REVERSE_GATE_TOL=${TLTM_STRICT_QN_REVERSE_GATE_TOL},QN_OFFICIAL_DFOLS_RHOEND=${rhoend},QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=${model_abs},QN_OFFICIAL_DFOLS_MODEL_REL_TOL=${TLTM_QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"
}

profile_root() {
  local profile="$1"
  echo "${TLTM_ROOT_PREFIX}/f20c_$(profile_label "${profile}")_r2_10seed_10k_${short_commit}"
}

profile_log_root() {
  local profile="$1"
  echo "${TLTM_LOG_PREFIX}/f20c_$(profile_label "${profile}")_r2_10seed_10k_${short_commit}"
}

if [ "${TLTM_DRY_RUN}" != "1" ]; then
  if [ "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY}" != "cluster02_scheduler" ] || [ -z "${TLTM_SCHEDULER_REQUEST_ID}" ]; then
    echo "[ERROR] Actual PBS submission is owned by the cluster02 scheduling agent." >&2
    echo "[ERROR] Use TLTM_DRY_RUN=1 here, or let the scheduler set TLTM_CLUSTER02_SCHEDULER_AUTHORITY and TLTM_SCHEDULER_REQUEST_ID." >&2
    exit 2
  fi
  for queue in "${TLTM_F20_BUILD_QUEUE}" "${TLTM_F20_CHUNK_QUEUE}" "${TLTM_F20_MERGE_QUEUE}"; do
    case "${queue}" in
      ""|SCHEDULER_ASSIGN_*)
        echo "[ERROR] scheduler must provide concrete queue names before real submit." >&2
        exit 2
        ;;
    esac
  done
  if [ -n "$(git status --porcelain)" ]; then
    echo "[ERROR] working tree is dirty; commit/sync before submitting F20c NT/QN/DFO-LS tolerance scan." >&2
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
  -N f20cntbld \
  -q "${TLTM_F20_BUILD_QUEUE}" \
  -l select=1:ncpus=16:mpiprocs=16:mem=16gb \
  -l walltime=02:00:00 \
  -o "$(profile_log_root tau_1e12)/submit/preflight.pbs.out" \
  -v "${build_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_preflight_build.pbs)"

set_job_var() {
  local name="$1"
  local value="$2"
  eval "${name}=\"\${value}\""
}

get_job_var() {
  local name="$1"
  eval "printf '%s' \"\${${name}}\""
}

for profile in "${profiles[@]}"; do
  tol_vars="$(profile_tol_vars "${profile}")"
  ref_label="f20c_$(profile_label "${profile}")_r2_10seed_10k_${short_commit}"
  root_subdir="$(profile_root "${profile}")"
  root_log_subdir="$(profile_log_root "${profile}")"
  pshort="$(profile_short "${profile}")"
  for method in "${methods[@]}"; do
    method_short="nf"
    if [ "${method}" = "fb_norefine" ]; then
      method_short="fb"
    fi
    chunk_vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${ref_label},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${root_subdir},TLTM_ROOT_LOG_SUBDIR=${root_log_subdir},TLTM_METHOD=${method},TLTM_CHUNK_ID=00,TLTM_SEED_OFFSET=0,TLTM_MAX_SEEDS=10,TLTM_JOBS=10,TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE}"
    job="$(run_qsub \
      -N "f20c${pshort}${method_short}" \
      -q "${TLTM_F20_CHUNK_QUEUE}" \
      -l select=1:ncpus=10:mpiprocs=10:mem=16gb \
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
  ref_label="f20c_$(profile_label "${profile}")_r2_10seed_10k_${short_commit}"
  root_subdir="$(profile_root "${profile}")"
  root_log_subdir="$(profile_log_root "${profile}")"
  pshort="$(profile_short "${profile}")"
  deps="$(get_job_var "chunk_job_${profile}_no_fb"):$(get_job_var "chunk_job_${profile}_fb_norefine")"
  comparison_root="${TLTM_REFERENCE_COMPARISON_ROOT}"
  merge_vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${ref_label},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${root_subdir},TLTM_ROOT_LOG_SUBDIR=${root_log_subdir},TLTM_EXPECTED_ROWS_PER_METHOD=10,TLTM_REQUESTED_CPUS=20,TLTM_CHUNKS_LABEL=F20C_R2_ntqn_dfols_tolerance_scan_chunks,TLTM_REFERENCE_COMPARISON_ROOT=${comparison_root}"
  merge_job="$(run_qsub \
    -N "f20c${pshort}m" \
    -q "${TLTM_F20_MERGE_QUEUE}" \
    -l select=1:ncpus=1:mpiprocs=1:mem=4gb \
    -l walltime=01:00:00 \
    -o "${root_log_subdir}/merge/merge.pbs.out" \
    -W "depend=afterok:${deps}" \
    -v "${merge_vars}" \
    codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_merge_level.pbs)"
  set_job_var "merge_job_${profile}" "${merge_job}"
done

manifest="$(profile_log_root tau_1e8)/submit/submit_manifest_${stamp}.env"
queue_plan="$(profile_log_root tau_1e8)/submit/submit_queue_plan_${stamp}.json"
{
  echo "submitted_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "dry_run=${TLTM_DRY_RUN}"
  echo "launcher=submit_f20c_ntqn_dfols_tolerance_scan_r2_10seed_10k.sh"
  echo "scheduler_authority=${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}"
  echo "scheduler_request_id=${TLTM_SCHEDULER_REQUEST_ID:-dry_run}"
  echo "scale=3_profiles_x_2_methods_x_10seed_x_10000cycles"
  echo "worktree=${TLTM_WORKTREE}"
  echo "expected_branch=${TLTM_EXPECTED_GIT_BRANCH}"
  echo "expected_commit=${TLTM_EXPECTED_GIT_COMMIT}"
  echo "config=${TLTM_CONFIG_JSON}"
  echo "baseline_reference_comparison_root=${TLTM_REFERENCE_COMPARISON_ROOT}"
  echo "build_queue=${TLTM_F20_BUILD_QUEUE}"
  echo "chunk_queue=${TLTM_F20_CHUNK_QUEUE}"
  echo "merge_queue=${TLTM_F20_MERGE_QUEUE}"
  echo "build_job=${build_job}"
  for profile in "${profiles[@]}"; do
    echo "${profile}_output_root=$(profile_root "${profile}")"
    echo "${profile}_log_root=$(profile_log_root "${profile}")"
    echo "${profile}_ode_abs_tol=${TLTM_FIXED_STAGE2_ABS_TOL}"
    echo "${profile}_ode_rel_tol=${TLTM_FIXED_STAGE2_REL_TOL}"
    echo "${profile}_ntqn_tau=$(profile_tau "${profile}")"
    echo "${profile}_dfols_rhoend=$(profile_dfols_rhoend "${profile}")"
    echo "${profile}_dfols_model_abs_tol=$(profile_dfols_model_abs_tol "${profile}")"
    for method in "${methods[@]}"; do
      echo "${profile}_${method}_chunk_00=$(get_job_var "chunk_job_${profile}_${method}")"
    done
    echo "${profile}_merge_job=$(get_job_var "merge_job_${profile}")"
  done
  echo "queue_plan=${queue_plan}"
} > "${manifest}"

{
  echo "{"
  echo "  \"dry_run\": ${TLTM_DRY_RUN},"
  echo "  \"launcher\": \"submit_f20c_ntqn_dfols_tolerance_scan_r2_10seed_10k.sh\","
  echo "  \"queue_source\": \"cluster02_scheduler_agent_required\","
  echo "  \"scheduler_authority\": \"${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}\","
  echo "  \"scheduler_request_id\": \"${TLTM_SCHEDULER_REQUEST_ID:-dry_run}\","
  echo "  \"scale\": \"3_profiles_x_2_methods_x_10seed_x_10000cycles\","
  echo "  \"expected_commit\": \"${TLTM_EXPECTED_GIT_COMMIT}\","
  echo "  \"baseline_reference_comparison_root\": \"${TLTM_REFERENCE_COMPARISON_ROOT}\","
  echo "  \"jobs\": ["
  echo "    {\"role\": \"build\", \"name\": \"f20cntbld\", \"queue\": \"${TLTM_F20_BUILD_QUEUE}\", \"ncpus\": 16, \"walltime\": \"02:00:00\", \"job\": \"${build_job}\"},"
  first=1
  for profile in "${profiles[@]}"; do
    for method in "${methods[@]}"; do
      if [ "${first}" = "1" ]; then
        first=0
      else
        echo ","
      fi
      printf '    {"role": "chunk", "profile": "%s", "method": "%s", "queue": "%s", "ncpus": 10, "walltime": "06:00:00", "job": "%s"}' \
        "${profile}" "${method}" "${TLTM_F20_CHUNK_QUEUE}" "$(get_job_var "chunk_job_${profile}_${method}")"
    done
  done
  for profile in "${profiles[@]}"; do
    echo ","
    printf '    {"role": "merge", "profile": "%s", "queue": "%s", "ncpus": 1, "walltime": "01:00:00", "reference_comparison_root": "%s", "job": "%s"}' \
      "${profile}" "${TLTM_F20_MERGE_QUEUE}" "${TLTM_REFERENCE_COMPARISON_ROOT}" "$(get_job_var "merge_job_${profile}")"
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
    printf '    "%s": {"label": "%s", "ode_abs_tol": "%s", "ode_rel_tol": "%s", "ntqn_tau": "%s", "dfols_model_abs_tol": "%s", "dfols_rhoend": "%s", "reverse_gate": "%s", "output_root": "%s"}' \
      "${profile}" "$(profile_label "${profile}")" "${TLTM_FIXED_STAGE2_ABS_TOL}" "${TLTM_FIXED_STAGE2_REL_TOL}" "$(profile_tau "${profile}")" "$(profile_dfols_model_abs_tol "${profile}")" "$(profile_dfols_rhoend "${profile}")" "${TLTM_STRICT_QN_REVERSE_GATE_TOL}" "$(profile_root "${profile}")"
  done
  echo ""
  echo "  },"
  echo "  \"readback_required\": ["
  echo "    \"all profile/method per_seed_summary_table.csv files have 10 rows\","
  echo "    \"all aggregate tables include total_odex_* and total_cvode_* columns\","
  echo "    \"protocol audit passes for every profile/method\","
  echo "    \"preflight log has no Python.h/libpython/pyconfig failure\","
  echo "    \"all candidates compare to F20b ODE1e12 strict-NT/QN baseline\","
  echo "    \"report runtime, ODEX counters, RG/projection stress, and paired observable drift\""
  echo "  ]"
  echo "}"
} > "${queue_plan}"

echo "submit_manifest=${manifest}"
echo "queue_plan=${queue_plan}"
echo "baseline_reference_comparison_root=${TLTM_REFERENCE_COMPARISON_ROOT}"
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

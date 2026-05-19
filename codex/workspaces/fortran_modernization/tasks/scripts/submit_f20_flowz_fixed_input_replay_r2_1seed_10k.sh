#!/bin/bash
# Prepare or submit F20 fixed-input flowz ODEX strict-vs-loose replay diagnostic.

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
: "${TLTM_FLOWZ_REPLAY_EXTRA_DEPEND:=}"

# Queue choice belongs to the cluster02 scheduler. Dry-runs use placeholders;
# real submissions require the scheduler to provide concrete queue names.
: "${TLTM_F20_FLOWZ_BUILD_QUEUE:=SCHEDULER_ASSIGN_BUILD_QUEUE}"
: "${TLTM_F20_FLOWZ_CAPTURE_QUEUE:=SCHEDULER_ASSIGN_CAPTURE_QUEUE}"
: "${TLTM_F20_FLOWZ_REPLAY_QUEUE:=SCHEDULER_ASSIGN_REPLAY_QUEUE}"

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

: "${TLTM_FLOWZ_CAPTURE_LIMIT:=5000}"
: "${TLTM_FLOWZ_CAPTURE_START:=1}"
: "${TLTM_FLOWZ_CAPTURE_STRIDE:=1000}"
: "${TLTM_FLOWZ_REPLAY_MAX_CASES:=0}"

stamp="$(date +%Y%m%dT%H%M%S)"
short_commit="$(git rev-parse --short=12 "${TLTM_EXPECTED_GIT_COMMIT}")"
: "${TLTM_REF_LEVEL:=F20_R2_FLOWZ_FIXED_INPUT_REPLAY}"
: "${TLTM_REF_LABEL:=f20_flowz_fixed_input_replay_r2_1seed_10k_${short_commit}}"
: "${TLTM_OUTPUT_ROOT:=output/tests/f20_flowz_replay/${TLTM_REF_LABEL}}"
: "${TLTM_LOG_ROOT:=output/logs/f20_flowz_replay/${TLTM_REF_LABEL}}"

profiles=(strict all_loose)
methods=(no_fb fb_norefine)

profile_tol_vars() {
  case "$1" in
    strict)
      echo "TLTM_TOLERANCE_PROFILE_LABEL=strict_double,TLTM_STAGE2_ABS_TOL_OVERRIDE=${TLTM_STRICT_STAGE2_ABS_TOL},TLTM_STAGE2_REL_TOL_OVERRIDE=${TLTM_STRICT_STAGE2_REL_TOL},TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=${TLTM_STRICT_STAGE2_CONSTRAINT_TOL},QN_QUASI_TOL_OVERRIDE=${TLTM_STRICT_QN_QUASI_TOL},QN_REVERSE_GATE_TOL=${TLTM_STRICT_QN_REVERSE_GATE_TOL},QN_OFFICIAL_DFOLS_RHOEND=${TLTM_STRICT_QN_OFFICIAL_DFOLS_RHOEND},QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=${TLTM_STRICT_QN_OFFICIAL_DFOLS_MODEL_ABS_TOL},QN_OFFICIAL_DFOLS_MODEL_REL_TOL=${TLTM_STRICT_QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"
      ;;
    all_loose)
      echo "TLTM_TOLERANCE_PROFILE_LABEL=single_feasible1e6_rg1e4,TLTM_STAGE2_ABS_TOL_OVERRIDE=${TLTM_LOOSE_STAGE2_ABS_TOL},TLTM_STAGE2_REL_TOL_OVERRIDE=${TLTM_LOOSE_STAGE2_REL_TOL},TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=${TLTM_LOOSE_STAGE2_CONSTRAINT_TOL},QN_QUASI_TOL_OVERRIDE=${TLTM_LOOSE_QN_QUASI_TOL},QN_REVERSE_GATE_TOL=${TLTM_LOOSE_QN_REVERSE_GATE_TOL},QN_OFFICIAL_DFOLS_RHOEND=${TLTM_LOOSE_QN_OFFICIAL_DFOLS_RHOEND},QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=${TLTM_LOOSE_QN_OFFICIAL_DFOLS_MODEL_ABS_TOL},QN_OFFICIAL_DFOLS_MODEL_REL_TOL=${TLTM_LOOSE_QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"
      ;;
    *) echo "[ERROR] unknown profile: $1" >&2; return 2 ;;
  esac
}

if [ "${TLTM_DRY_RUN}" != "1" ]; then
  if [ "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY}" != "cluster02_scheduler" ] || [ -z "${TLTM_SCHEDULER_REQUEST_ID}" ]; then
    echo "[ERROR] Actual PBS submission is owned by the cluster02 scheduling agent." >&2
    echo "[ERROR] Use TLTM_DRY_RUN=1 here, or let the scheduler set TLTM_CLUSTER02_SCHEDULER_AUTHORITY and TLTM_SCHEDULER_REQUEST_ID." >&2
    exit 2
  fi
  for queue in "${TLTM_F20_FLOWZ_BUILD_QUEUE}" "${TLTM_F20_FLOWZ_CAPTURE_QUEUE}" "${TLTM_F20_FLOWZ_REPLAY_QUEUE}"; do
    case "${queue}" in
      ""|SCHEDULER_ASSIGN_*)
        echo "[ERROR] scheduler must provide concrete queue names before real submit." >&2
        exit 2
        ;;
    esac
  done
  if [ -n "$(git status --porcelain)" ]; then
    echo "[ERROR] working tree is dirty; commit/sync before submitting F20 flowz replay diagnostic." >&2
    git status --short >&2
    exit 2
  fi
fi

mkdir -p "${TLTM_LOG_ROOT}/submit" "${TLTM_LOG_ROOT}/preflight" "${TLTM_LOG_ROOT}/replay"

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

build_vars="${common_vars},TLTM_RUN_GUARDRAILS=${TLTM_RUN_GUARDRAILS},TLTM_BUILD_JOBS=${TLTM_BUILD_JOBS},TLTM_LOG_ROOT=${TLTM_LOG_ROOT}/preflight"
if [ -n "${TLTM_FLOWZ_REPLAY_EXTRA_DEPEND}" ]; then
  build_job="$(run_qsub \
    -N f20fzbuild \
    -q "${TLTM_F20_FLOWZ_BUILD_QUEUE}" \
    -l select=1:ncpus=16:mpiprocs=16:mem=16gb \
    -l walltime=02:00:00 \
    -o "${TLTM_LOG_ROOT}/submit/preflight.pbs.out" \
    -W "depend=afterok:${TLTM_FLOWZ_REPLAY_EXTRA_DEPEND}" \
    -v "${build_vars}" \
    codex/workspaces/fortran_modernization/tasks/pbs/f20_flowz_replay_preflight_build.pbs)"
else
  build_job="$(run_qsub \
    -N f20fzbuild \
    -q "${TLTM_F20_FLOWZ_BUILD_QUEUE}" \
    -l select=1:ncpus=16:mpiprocs=16:mem=16gb \
    -l walltime=02:00:00 \
    -o "${TLTM_LOG_ROOT}/submit/preflight.pbs.out" \
    -v "${build_vars}" \
    codex/workspaces/fortran_modernization/tasks/pbs/f20_flowz_replay_preflight_build.pbs)"
fi

for profile in "${profiles[@]}"; do
  tol_vars="$(profile_tol_vars "${profile}")"
  for method in "${methods[@]}"; do
    method_short="nf"
    if [ "${method}" = "fb_norefine" ]; then
      method_short="fb"
    fi
    capture_root="${TLTM_OUTPUT_ROOT}/capture_${profile}"
    capture_log_root="${TLTM_LOG_ROOT}/capture_${profile}"
    capture_file="$(remote_abs_path "${capture_root}/${method}/chunk_00/flowz_inputs.dat")"
    chunk_vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${TLTM_REF_LABEL}_${profile}_${method},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${capture_root},TLTM_ROOT_LOG_SUBDIR=${capture_log_root},TLTM_METHOD=${method},TLTM_CHUNK_ID=00,TLTM_SEED_OFFSET=0,TLTM_MAX_SEEDS=1,TLTM_JOBS=1,TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE},TLTM_FLOWZ_CAPTURE_FILE=${capture_file},TLTM_FLOWZ_CAPTURE_LIMIT=${TLTM_FLOWZ_CAPTURE_LIMIT},TLTM_FLOWZ_CAPTURE_START=${TLTM_FLOWZ_CAPTURE_START},TLTM_FLOWZ_CAPTURE_STRIDE=${TLTM_FLOWZ_CAPTURE_STRIDE}"
    job="$(run_qsub \
      -N "f20fz${profile:0:2}${method_short}" \
      -q "${TLTM_F20_FLOWZ_CAPTURE_QUEUE}" \
      -l select=1:ncpus=1:mpiprocs=1:mem=8gb \
      -l walltime=04:00:00 \
      -o "${TLTM_LOG_ROOT}/submit/capture_${profile}_${method}.pbs.out" \
      -W "depend=afterok:${build_job}" \
      -v "${chunk_vars}" \
      codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_chunk.pbs)"
    set_job_var "capture_job_${profile}_${method}" "${job}"
  done
done

capture_deps=""
for profile in "${profiles[@]}"; do
  for method in "${methods[@]}"; do
    job="$(get_job_var "capture_job_${profile}_${method}")"
    if [ -z "${capture_deps}" ]; then
      capture_deps="${job}"
    else
      capture_deps="${capture_deps}:${job}"
    fi
  done
done

replay_vars="${common_vars},TLTM_OUTPUT_ROOT=${TLTM_OUTPUT_ROOT},TLTM_LOG_ROOT=${TLTM_LOG_ROOT},TLTM_FLOWZ_REPLAY_MAX_CASES=${TLTM_FLOWZ_REPLAY_MAX_CASES},TLTM_STRICT_STAGE2_ABS_TOL=${TLTM_STRICT_STAGE2_ABS_TOL},TLTM_STRICT_STAGE2_REL_TOL=${TLTM_STRICT_STAGE2_REL_TOL},TLTM_LOOSE_STAGE2_ABS_TOL=${TLTM_LOOSE_STAGE2_ABS_TOL},TLTM_LOOSE_STAGE2_REL_TOL=${TLTM_LOOSE_STAGE2_REL_TOL}"
replay_job="$(run_qsub \
  -N f20fzreplay \
  -q "${TLTM_F20_FLOWZ_REPLAY_QUEUE}" \
  -l select=1:ncpus=1:mpiprocs=1:mem=8gb \
  -l walltime=02:00:00 \
  -o "${TLTM_LOG_ROOT}/replay/replay.pbs.out" \
  -W "depend=afterok:${capture_deps}" \
  -v "${replay_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/f20_flowz_fixed_input_replay.pbs)"

manifest="${TLTM_LOG_ROOT}/submit/submit_manifest_${stamp}.env"
queue_plan="${TLTM_LOG_ROOT}/submit/submit_queue_plan_${stamp}.json"
{
  echo "submitted_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "dry_run=${TLTM_DRY_RUN}"
  echo "launcher=submit_f20_flowz_fixed_input_replay_r2_1seed_10k.sh"
  echo "scheduler_authority=${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}"
  echo "scheduler_request_id=${TLTM_SCHEDULER_REQUEST_ID:-dry_run}"
  echo "scale=2_capture_profiles_x_2_methods_x_1seed_x_10000cycles_then_fixed_input_replay"
  echo "worktree=${TLTM_WORKTREE}"
  echo "expected_branch=${TLTM_EXPECTED_GIT_BRANCH}"
  echo "expected_commit=${TLTM_EXPECTED_GIT_COMMIT}"
  echo "config=${TLTM_CONFIG_JSON}"
  echo "output_root=${TLTM_OUTPUT_ROOT}"
  echo "log_root=${TLTM_LOG_ROOT}"
  echo "capture_limit=${TLTM_FLOWZ_CAPTURE_LIMIT}"
  echo "capture_start=${TLTM_FLOWZ_CAPTURE_START}"
  echo "capture_stride=${TLTM_FLOWZ_CAPTURE_STRIDE}"
  echo "replay_max_cases=${TLTM_FLOWZ_REPLAY_MAX_CASES}"
  echo "extra_depend=${TLTM_FLOWZ_REPLAY_EXTRA_DEPEND}"
  echo "build_job=${build_job}"
  for profile in "${profiles[@]}"; do
    for method in "${methods[@]}"; do
      echo "${profile}_${method}_capture_job=$(get_job_var "capture_job_${profile}_${method}")"
      echo "${profile}_${method}_capture_file=${TLTM_OUTPUT_ROOT}/capture_${profile}/${method}/chunk_00/flowz_inputs.dat"
    done
  done
  echo "replay_job=${replay_job}"
  echo "queue_plan=${queue_plan}"
} > "${manifest}"

cat > "${queue_plan}" <<EOF_PLAN
{
  "dry_run": ${TLTM_DRY_RUN},
  "launcher": "submit_f20_flowz_fixed_input_replay_r2_1seed_10k.sh",
  "queue_source": "cluster02_scheduler_agent_required",
  "scheduler_authority": "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}",
  "scheduler_request_id": "${TLTM_SCHEDULER_REQUEST_ID:-dry_run}",
  "scale": "2_capture_profiles_x_2_methods_x_1seed_x_10000cycles_then_fixed_input_replay",
  "expected_commit": "${TLTM_EXPECTED_GIT_COMMIT}",
  "output_root": "${TLTM_OUTPUT_ROOT}",
  "log_root": "${TLTM_LOG_ROOT}",
  "capture_policy": {
    "limit": ${TLTM_FLOWZ_CAPTURE_LIMIT},
    "start": ${TLTM_FLOWZ_CAPTURE_START},
    "stride": ${TLTM_FLOWZ_CAPTURE_STRIDE},
    "replay_max_cases": ${TLTM_FLOWZ_REPLAY_MAX_CASES}
  },
  "extra_depend": "${TLTM_FLOWZ_REPLAY_EXTRA_DEPEND}",
  "jobs": [
    {"role": "build", "name": "f20fzbuild", "queue": "${TLTM_F20_FLOWZ_BUILD_QUEUE}", "ncpus": 16, "walltime": "02:00:00", "job": "${build_job}"},
    {"role": "capture", "profile": "strict", "method": "no_fb", "queue": "${TLTM_F20_FLOWZ_CAPTURE_QUEUE}", "ncpus": 1, "walltime": "04:00:00", "job": "$(get_job_var "capture_job_strict_no_fb")"},
    {"role": "capture", "profile": "strict", "method": "fb_norefine", "queue": "${TLTM_F20_FLOWZ_CAPTURE_QUEUE}", "ncpus": 1, "walltime": "04:00:00", "job": "$(get_job_var "capture_job_strict_fb_norefine")"},
    {"role": "capture", "profile": "all_loose", "method": "no_fb", "queue": "${TLTM_F20_FLOWZ_CAPTURE_QUEUE}", "ncpus": 1, "walltime": "04:00:00", "job": "$(get_job_var "capture_job_all_loose_no_fb")"},
    {"role": "capture", "profile": "all_loose", "method": "fb_norefine", "queue": "${TLTM_F20_FLOWZ_CAPTURE_QUEUE}", "ncpus": 1, "walltime": "04:00:00", "job": "$(get_job_var "capture_job_all_loose_fb_norefine")"},
    {"role": "replay", "name": "f20fzreplay", "queue": "${TLTM_F20_FLOWZ_REPLAY_QUEUE}", "ncpus": 1, "walltime": "02:00:00", "job": "${replay_job}"}
  ],
  "readback_required": [
    "four capture files exist and are non-empty",
    "eight replay CSV files exist",
    "flowz_replay_summary.json and flowz_replay_summary.txt exist",
    "for each captured input set, compare loose vs strict ODEX rhs_evals accepted/rejected midpoint_rows runtime per case",
    "if loose_over_strict explodes on the same input rows, flag ODEX controller/tolerance pathology; if only all_loose captures are hard for both replay tolerances, flag upstream state pathology"
  ]
}
EOF_PLAN

echo "submit_manifest=${manifest}"
echo "queue_plan=${queue_plan}"
echo "output_root=${TLTM_OUTPUT_ROOT}"
echo "log_root=${TLTM_LOG_ROOT}"
echo "build_job=${build_job}"
for profile in "${profiles[@]}"; do
  for method in "${methods[@]}"; do
    echo "${profile}_${method}_capture_job=$(get_job_var "capture_job_${profile}_${method}")"
  done
done
echo "replay_job=${replay_job}"

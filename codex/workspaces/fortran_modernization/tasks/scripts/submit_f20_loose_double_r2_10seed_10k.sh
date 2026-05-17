#!/bin/bash
# Prepare or submit the F20 loose-double R2 10seed/10k sensitivity gate.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

: "${TLTM_WORKTREE:=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization}"
: "${TLTM_EXPECTED_GIT_BRANCH:=codex/fortran-modernization}"
: "${TLTM_EXPECTED_GIT_COMMIT:=$(git rev-parse HEAD)}"
: "${TLTM_F20_PROFILE:=single_feasible1e6_rg1e4}"
: "${TLTM_CONFIG_JSON:=docs/modernization_reference_t035_r2_10seed_10k.json}"
: "${TLTM_REFERENCE_COMPARISON_ROOT:=/home/cychou/TLTM_worktrees/tltm_production_comparison/output/production_comparison/modernization_handoff_20260517_0b2a40c_8ab252e/runs/handoff_smoke_npt5_r0055_20260517_6ad8377_10seed_10000cyc_t035_L2_nstep20_rngv2_nofb_withfb}"
: "${TLTM_RUN_GUARDRAILS:=1}"
: "${TLTM_BUILD_JOBS:=16}"
: "${TLTM_ALLOW_OVERWRITE:=0}"
: "${TLTM_DRY_RUN:=0}"
: "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:=}"
: "${TLTM_SCHEDULER_REQUEST_ID:=}"

# Queue choice belongs to the cluster02 scheduler. Dry-runs use placeholders;
# real submissions require the scheduler to provide concrete queue names.
: "${TLTM_F20_BUILD_QUEUE:=SCHEDULER_ASSIGN_BUILD_QUEUE}"
: "${TLTM_F20_NO_FB_QUEUE:=SCHEDULER_ASSIGN_NO_FB_QUEUE}"
: "${TLTM_F20_FB_NOREFINE_QUEUE:=SCHEDULER_ASSIGN_FB_NOREFINE_QUEUE}"
: "${TLTM_F20_MERGE_QUEUE:=SCHEDULER_ASSIGN_MERGE_QUEUE}"

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
: "${TLTM_REF_LEVEL:=F20_R2}"
: "${TLTM_REF_LABEL:=f20_${TLTM_F20_PROFILE}_r2_10seed_10k_${short_commit}}"
: "${TLTM_ROOT_SUBDIR:=output/tests/f20_loose_double/${TLTM_REF_LABEL}}"
: "${TLTM_ROOT_LOG_SUBDIR:=output/logs/f20_loose_double/${TLTM_REF_LABEL}}"

if [ "${TLTM_DRY_RUN}" != "1" ]; then
  if [ "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY}" != "cluster02_scheduler" ] || [ -z "${TLTM_SCHEDULER_REQUEST_ID}" ]; then
    echo "[ERROR] Actual PBS submission is owned by the cluster02 scheduling agent." >&2
    echo "[ERROR] Use TLTM_DRY_RUN=1 here, or let the scheduler set TLTM_CLUSTER02_SCHEDULER_AUTHORITY and TLTM_SCHEDULER_REQUEST_ID." >&2
    exit 2
  fi
  for queue in "${TLTM_F20_BUILD_QUEUE}" "${TLTM_F20_NO_FB_QUEUE}" "${TLTM_F20_FB_NOREFINE_QUEUE}" "${TLTM_F20_MERGE_QUEUE}"; do
    case "${queue}" in
      ""|SCHEDULER_ASSIGN_*)
        echo "[ERROR] scheduler must provide concrete queue names before real submit." >&2
        exit 2
        ;;
    esac
  done
  if [ -n "$(git status --porcelain)" ]; then
    echo "[ERROR] working tree is dirty; commit/sync before submitting F20 loose-double R2 gate." >&2
    git status --short >&2
    exit 2
  fi
fi

mkdir -p "${TLTM_ROOT_LOG_SUBDIR}/submit" "${TLTM_ROOT_LOG_SUBDIR}/no_fb" "${TLTM_ROOT_LOG_SUBDIR}/fb_norefine" "${TLTM_ROOT_LOG_SUBDIR}/merge"

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
  -N f20r2bld \
  -q "${TLTM_F20_BUILD_QUEUE}" \
  -l select=1:ncpus=16:mpiprocs=16:mem=16gb \
  -l walltime=02:00:00 \
  -o "${TLTM_ROOT_LOG_SUBDIR}/submit/preflight.pbs.out" \
  -v "${build_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_preflight_build.pbs)"

no_fb_vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${TLTM_REF_LABEL},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${TLTM_ROOT_SUBDIR},TLTM_ROOT_LOG_SUBDIR=${TLTM_ROOT_LOG_SUBDIR},TLTM_METHOD=no_fb,TLTM_CHUNK_ID=00,TLTM_SEED_OFFSET=0,TLTM_MAX_SEEDS=10,TLTM_JOBS=10,TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE}"
no_fb_job="$(run_qsub \
  -N f20r2nofb00 \
  -q "${TLTM_F20_NO_FB_QUEUE}" \
  -l select=1:ncpus=10:mpiprocs=10:mem=16gb \
  -l walltime=06:00:00 \
  -o "${TLTM_ROOT_LOG_SUBDIR}/no_fb/chunk_00.pbs.out" \
  -W "depend=afterok:${build_job}" \
  -v "${no_fb_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_chunk.pbs)"

fb_vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${TLTM_REF_LABEL},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${TLTM_ROOT_SUBDIR},TLTM_ROOT_LOG_SUBDIR=${TLTM_ROOT_LOG_SUBDIR},TLTM_METHOD=fb_norefine,TLTM_CHUNK_ID=00,TLTM_SEED_OFFSET=0,TLTM_MAX_SEEDS=10,TLTM_JOBS=10,TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE}"
fb_job="$(run_qsub \
  -N f20r2fbnr00 \
  -q "${TLTM_F20_FB_NOREFINE_QUEUE}" \
  -l select=1:ncpus=10:mpiprocs=10:mem=16gb \
  -l walltime=06:00:00 \
  -o "${TLTM_ROOT_LOG_SUBDIR}/fb_norefine/chunk_00.pbs.out" \
  -W "depend=afterok:${build_job}" \
  -v "${fb_vars}" \
  codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_chunk.pbs)"

deps="${no_fb_job}:${fb_job}"
merge_vars="${common_vars},${tol_vars},TLTM_REF_LEVEL=${TLTM_REF_LEVEL},TLTM_REF_LABEL=${TLTM_REF_LABEL},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_ROOT_SUBDIR=${TLTM_ROOT_SUBDIR},TLTM_ROOT_LOG_SUBDIR=${TLTM_ROOT_LOG_SUBDIR},TLTM_EXPECTED_ROWS_PER_METHOD=10,TLTM_REQUESTED_CPUS=20,TLTM_CHUNKS_LABEL=F20_R2_loose_double_chunks,TLTM_REFERENCE_COMPARISON_ROOT=${TLTM_REFERENCE_COMPARISON_ROOT}"
merge_job="$(run_qsub \
  -N f20r2mrg \
  -q "${TLTM_F20_MERGE_QUEUE}" \
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
  echo "launcher=submit_f20_loose_double_r2_10seed_10k.sh"
  echo "scheduler_authority=${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}"
  echo "scheduler_request_id=${TLTM_SCHEDULER_REQUEST_ID:-dry_run}"
  echo "profile=${TLTM_F20_PROFILE}"
  echo "scale=10seed_x_10000cycles"
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
  echo "build_queue=${TLTM_F20_BUILD_QUEUE}"
  echo "no_fb_queue=${TLTM_F20_NO_FB_QUEUE}"
  echo "fb_norefine_queue=${TLTM_F20_FB_NOREFINE_QUEUE}"
  echo "merge_queue=${TLTM_F20_MERGE_QUEUE}"
  echo "build_job=${build_job}"
  echo "no_fb_chunk_00=${no_fb_job}"
  echo "fb_norefine_chunk_00=${fb_job}"
  echo "merge_job=${merge_job}"
  echo "queue_plan=${queue_plan}"
} > "${manifest}"

cat > "${queue_plan}" <<EOF_PLAN
{
  "dry_run": ${TLTM_DRY_RUN},
  "launcher": "submit_f20_loose_double_r2_10seed_10k.sh",
  "queue_source": "cluster02_scheduler_agent_required",
  "scheduler_authority": "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:-dry_run}",
  "scheduler_request_id": "${TLTM_SCHEDULER_REQUEST_ID:-dry_run}",
  "scale": "10seed_x_10000cycles",
  "profile": "${TLTM_F20_PROFILE}",
  "expected_commit": "${TLTM_EXPECTED_GIT_COMMIT}",
  "output_root": "${TLTM_ROOT_SUBDIR}",
  "log_root": "${TLTM_ROOT_LOG_SUBDIR}",
  "reference_comparison_root": "${TLTM_REFERENCE_COMPARISON_ROOT}",
  "jobs": [
    {"role": "build", "name": "f20r2bld", "queue": "${TLTM_F20_BUILD_QUEUE}", "ncpus": 16, "walltime": "02:00:00", "job": "${build_job}"},
    {"role": "chunk", "method": "no_fb", "chunk_id": "00", "max_seeds": 10, "jobs": 10, "queue": "${TLTM_F20_NO_FB_QUEUE}", "ncpus": 10, "walltime": "06:00:00", "job": "${no_fb_job}"},
    {"role": "chunk", "method": "fb_norefine", "chunk_id": "00", "max_seeds": 10, "jobs": 10, "queue": "${TLTM_F20_FB_NOREFINE_QUEUE}", "ncpus": 10, "walltime": "06:00:00", "job": "${fb_job}"},
    {"role": "merge", "name": "f20r2mrg", "queue": "${TLTM_F20_MERGE_QUEUE}", "ncpus": 1, "walltime": "01:00:00", "expected_rows_per_method": 10, "job": "${merge_job}"}
  ],
  "tolerances": {
    "TLTM_STAGE2_ABS_TOL_OVERRIDE": "${TLTM_STAGE2_ABS_TOL_OVERRIDE}",
    "TLTM_STAGE2_REL_TOL_OVERRIDE": "${TLTM_STAGE2_REL_TOL_OVERRIDE}",
    "TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE": "${TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE}",
    "QN_QUASI_TOL_OVERRIDE": "${QN_QUASI_TOL_OVERRIDE}",
    "QN_REVERSE_GATE_TOL": "${QN_REVERSE_GATE_TOL}",
    "QN_OFFICIAL_DFOLS_RHOEND": "${QN_OFFICIAL_DFOLS_RHOEND}",
    "QN_OFFICIAL_DFOLS_MODEL_ABS_TOL": "${QN_OFFICIAL_DFOLS_MODEL_ABS_TOL}",
    "QN_OFFICIAL_DFOLS_MODEL_REL_TOL": "${QN_OFFICIAL_DFOLS_MODEL_REL_TOL}"
  },
  "readback_required": [
    "no_fb/per_seed_summary_table.csv has 10 rows",
    "fb_norefine/per_seed_summary_table.csv has 10 rows",
    "both methods have aggregated_summary_table.csv",
    "protocol_audit_summary.csv verdicts pass",
    "preflight log has no Python.h or libpython failure",
    "strict/product-handoff reference comparison root is readable"
  ]
}
EOF_PLAN

echo "submit_manifest=${manifest}"
echo "queue_plan=${queue_plan}"
echo "output_root=${TLTM_ROOT_SUBDIR}"
echo "build_job=${build_job}"
echo "no_fb_job=${no_fb_job}"
echo "fb_norefine_job=${fb_job}"
echo "merge_job=${merge_job}"

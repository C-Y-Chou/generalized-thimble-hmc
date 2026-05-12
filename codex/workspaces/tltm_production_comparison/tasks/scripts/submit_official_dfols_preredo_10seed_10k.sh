#!/bin/bash
set -euo pipefail

: "${TLTM_WORKTREE:=/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison}"
: "${TLTM_EXPECTED_GIT_BRANCH:=codex/tltm-production-comparison-official-dfols}"
: "${TLTM_CONFIG_JSON:=docs/production_comparison_official_dfols_preredo_10seed_10k_nofb_withfb.json}"
: "${TLTM_MAX_SEEDS:=10}"
: "${TLTM_CYCLES_PER_SEED:=10000}"
: "${TLTM_RUN_JOBS:=10}"
: "${TLTM_ALLOW_OVERWRITE:=0}"
: "${TLTM_DRY_RUN:=0}"

cd "${TLTM_WORKTREE}"

branch="$(git rev-parse --abbrev-ref HEAD)"
commit="$(git rev-parse HEAD)"
short_commit="$(git rev-parse --short=7 HEAD)"
if [ "${branch}" != "${TLTM_EXPECTED_GIT_BRANCH}" ]; then
  echo "[ERROR] expected branch ${TLTM_EXPECTED_GIT_BRANCH}, got ${branch}" >&2
  exit 2
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "[ERROR] working tree is dirty; refusing pre-redo submission" >&2
  git status --short >&2
  exit 2
fi
if [ ! -f "${TLTM_CONFIG_JSON}" ]; then
  echo "[ERROR] missing config: ${TLTM_CONFIG_JSON}" >&2
  exit 2
fi

stamp="$(TZ=Asia/Tokyo date +%Y%m%d)"
: "${TLTM_CAMPAIGN:=official_dfols_preredo_${stamp}_${short_commit}_${TLTM_MAX_SEEDS}seed_${TLTM_CYCLES_PER_SEED}cyc_t035_L2_nstep20_rg_nofb_withfb}"

out_root="output/production_comparison/pre_redo/${TLTM_CAMPAIGN}"
log_root="output/logs/production_comparison/pre_redo/${TLTM_CAMPAIGN}"
submit_log_dir="${log_root}/submit"
mkdir -p "${out_root}" "${submit_log_dir}"

manifest="${out_root}/submit_manifest.env"
{
  echo "CAMPAIGN=${TLTM_CAMPAIGN}"
  echo "SUBMITTED_AT=$(date -Is)"
  echo "GIT_BRANCH=${branch}"
  echo "GIT_COMMIT=${commit}"
  echo "SOURCE_WORKTREE=${TLTM_WORKTREE}"
  echo "N_SEEDS=${TLTM_MAX_SEEDS}"
  echo "CYCLES_PER_SEED=${TLTM_CYCLES_PER_SEED}"
  echo "METHODS=no_fb fb_norefine"
  echo "FLOW_TIME=0.35"
  echo "L=2"
  echo "NSTEP=20"
  echo "RG_ENABLED=1"
  echo "QN_SOLVER_BACKEND=official_dfols"
  echo "QN_OFFICIAL_DFOLS_PRESET=stable_gate77"
  echo "ASSIST_POLICY=INTODE_SOLVER_ASSIST_ENABLED=0"
  echo "CONFIG_JSON=${TLTM_CONFIG_JSON}"
  echo "OUTPUT_ROOT=${out_root}"
  echo "LOG_ROOT=${log_root}"
  echo "PBS_PREFLIGHT=codex/workspaces/tltm_production_comparison/tasks/pbs/official_dfols_preflight_build.pbs"
  echo "PBS_METHOD=codex/workspaces/tltm_production_comparison/tasks/pbs/official_dfols_preredo_10seed_10k_method.pbs"
  echo "PBS_MERGE=codex/workspaces/tltm_production_comparison/tasks/pbs/official_dfols_preredo_10seed_10k_merge.pbs"
} > "${manifest}"

env_common="TLTM_WORKTREE=${TLTM_WORKTREE},TLTM_EXPECTED_GIT_BRANCH=${TLTM_EXPECTED_GIT_BRANCH},TLTM_EXPECTED_GIT_COMMIT=${commit},TLTM_CAMPAIGN=${TLTM_CAMPAIGN},TLTM_CONFIG_JSON=${TLTM_CONFIG_JSON},TLTM_MAX_SEEDS=${TLTM_MAX_SEEDS},TLTM_CYCLES_PER_SEED=${TLTM_CYCLES_PER_SEED},TLTM_RUN_JOBS=${TLTM_RUN_JOBS},TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE}"

preflight_pbs="codex/workspaces/tltm_production_comparison/tasks/pbs/official_dfols_preflight_build.pbs"
method_pbs="codex/workspaces/tltm_production_comparison/tasks/pbs/official_dfols_preredo_10seed_10k_method.pbs"
merge_pbs="codex/workspaces/tltm_production_comparison/tasks/pbs/official_dfols_preredo_10seed_10k_merge.pbs"

if [ "${TLTM_DRY_RUN}" = "1" ]; then
  echo "campaign=${TLTM_CAMPAIGN}"
  echo "manifest=${manifest}"
  echo "qsub -v TLTM_EXPECTED_GIT_COMMIT=${commit},TLTM_WORKTREE=${TLTM_WORKTREE},TLTM_EXPECTED_GIT_BRANCH=${TLTM_EXPECTED_GIT_BRANCH} -o ${submit_log_dir}/preflight.pbs.out ${preflight_pbs}"
  echo "qsub -W depend=afterok:<preflight> -v ${env_common},TLTM_METHOD=no_fb,TLTM_CANONICAL_METHOD=nofb -o ${submit_log_dir}/nofb.pbs.out ${method_pbs}"
  echo "qsub -W depend=afterok:<preflight> -v ${env_common},TLTM_METHOD=fb_norefine,TLTM_CANONICAL_METHOD=withfb -o ${submit_log_dir}/withfb.pbs.out ${method_pbs}"
  echo "qsub -W depend=afterok:<nofb>:<withfb> -v ${env_common} -o ${submit_log_dir}/merge.pbs.out ${merge_pbs}"
  exit 0
fi

preflight_job="$(qsub -v "TLTM_EXPECTED_GIT_COMMIT=${commit},TLTM_WORKTREE=${TLTM_WORKTREE},TLTM_EXPECTED_GIT_BRANCH=${TLTM_EXPECTED_GIT_BRANCH}" -o "${submit_log_dir}/preflight.pbs.out" "${preflight_pbs}")"
nofb_job="$(qsub -W "depend=afterok:${preflight_job}" -v "${env_common},TLTM_METHOD=no_fb,TLTM_CANONICAL_METHOD=nofb" -o "${submit_log_dir}/nofb.pbs.out" "${method_pbs}")"
withfb_job="$(qsub -W "depend=afterok:${preflight_job}" -v "${env_common},TLTM_METHOD=fb_norefine,TLTM_CANONICAL_METHOD=withfb" -o "${submit_log_dir}/withfb.pbs.out" "${method_pbs}")"
merge_job="$(qsub -W "depend=afterok:${nofb_job}:${withfb_job}" -v "${env_common}" -o "${submit_log_dir}/merge.pbs.out" "${merge_pbs}")"

{
  echo "PREFLIGHT_JOB=${preflight_job}"
  echo "NOFB_JOB=${nofb_job}"
  echo "WITHFB_JOB=${withfb_job}"
  echo "MERGE_JOB=${merge_job}"
} | tee "${out_root}/submitted_jobs.env"

echo "campaign=${TLTM_CAMPAIGN}"
echo "manifest=${manifest}"

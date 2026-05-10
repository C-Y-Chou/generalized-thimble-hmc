#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash codex/workspaces/fortran_modernization/tasks/scripts/submit_m6_reference_datasets.sh [--dry-run]

Submit all M6 modernization reference datasets R1-R4 to PBS with a build/preflight dependency.
Run this from the TLTM repository root on the PBS cluster worktree.

Environment overrides:
  TLTM_WORKTREE=/lustre1/home/cychou/TLTM
  TLTM_EXPECTED_GIT_BRANCH=<current branch>
  TLTM_EXPECTED_GIT_COMMIT=<current commit>
  TLTM_RUN_GUARDRAILS=1
  TLTM_ALLOW_OVERWRITE=0
USAGE
}

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
elif [ "${1:-}" = "--help" ]; then
  usage
  exit 0
elif [ "${1:-}" != "" ]; then
  usage >&2
  exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${REPO_ROOT}" ] || [ "${REPO_ROOT}" != "$(pwd)" ]; then
  echo "[ERROR] run from repository root" >&2
  exit 2
fi

if [ "${DRY_RUN}" = "0" ] && ! command -v qsub >/dev/null 2>&1; then
  echo "[ERROR] qsub not found. Re-run on the PBS cluster or use --dry-run." >&2
  exit 2
fi

TLTM_WORKTREE="${TLTM_WORKTREE:-$(pwd)}"
TLTM_EXPECTED_GIT_BRANCH="${TLTM_EXPECTED_GIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
TLTM_EXPECTED_GIT_COMMIT="${TLTM_EXPECTED_GIT_COMMIT:-$(git rev-parse HEAD)}"
TLTM_RUN_GUARDRAILS="${TLTM_RUN_GUARDRAILS:-1}"
TLTM_ALLOW_OVERWRITE="${TLTM_ALLOW_OVERWRITE:-0}"

if [ "${DRY_RUN}" = "0" ] && [ -n "$(git status --porcelain)" ]; then
  echo "[ERROR] working tree is dirty; commit or stash before submitting reference datasets" >&2
  git status --short >&2
  exit 2
fi

PBS_DIR="codex/workspaces/fortran_modernization/tasks/pbs"
CHUNK_PBS="${PBS_DIR}/m6_reference_chunk.pbs"
MERGE_PBS="${PBS_DIR}/m6_reference_merge_level.pbs"
BUILD_PBS="${PBS_DIR}/m6_reference_preflight_build.pbs"
SUBMIT_LOG_DIR="output/logs/fortran_modernization/reference_datasets/submit"
mkdir -p "${SUBMIT_LOG_DIR}"
SUBMIT_MANIFEST="${SUBMIT_LOG_DIR}/submit_manifest_$(date +%Y%m%dT%H%M%S).env"

run_or_print() {
  if [ "${DRY_RUN}" = "1" ]; then
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

submit_job() {
  local result
  if [ "${DRY_RUN}" = "1" ]; then
    run_or_print "$@" >&2
    result="DRYRUN_job"
    local previous_arg=""
    local arg
    for arg in "$@"; do
      if [ "${previous_arg}" = "-N" ]; then
        result="DRYRUN_${arg}"
        break
      fi
      previous_arg="${arg}"
    done
  else
    result="$("$@")"
  fi
  echo "${result}"
}

join_by_colon() {
  local IFS=":"
  echo "$*"
}

{
  echo "submitted_at=$(timestamp_utc)"
  echo "dry_run=${DRY_RUN}"
  echo "worktree=${TLTM_WORKTREE}"
  echo "expected_branch=${TLTM_EXPECTED_GIT_BRANCH}"
  echo "expected_commit=${TLTM_EXPECTED_GIT_COMMIT}"
  echo "run_guardrails=${TLTM_RUN_GUARDRAILS}"
  echo "allow_overwrite=${TLTM_ALLOW_OVERWRITE}"
} > "${SUBMIT_MANIFEST}"

COMMON_VARS="TLTM_WORKTREE=${TLTM_WORKTREE},TLTM_EXPECTED_GIT_BRANCH=${TLTM_EXPECTED_GIT_BRANCH},TLTM_EXPECTED_GIT_COMMIT=${TLTM_EXPECTED_GIT_COMMIT}"

BUILD_JOB="$(submit_job qsub \
  -N m6refbuild \
  -q C8 \
  -l select=1:ncpus=16:mpiprocs=16:mem=16gb \
  -l walltime=02:00:00 \
  -o "${SUBMIT_LOG_DIR}/m6_reference_preflight_build.pbs.out" \
  -v "${COMMON_VARS},TLTM_RUN_GUARDRAILS=${TLTM_RUN_GUARDRAILS},TLTM_BUILD_JOBS=16" \
  "${BUILD_PBS}")"
echo "build_job=${BUILD_JOB}" | tee -a "${SUBMIT_MANIFEST}"

submit_chunk() {
  local level="$1"
  local label="$2"
  local config="$3"
  local root="$4"
  local log_root="$5"
  local method="$6"
  local chunk_id="$7"
  local seed_offset="$8"
  local max_seeds="$9"
  local jobs="${10}"
  local queue="${11}"
  local walltime="${12}"
  local ncpus="${13}"
  local vars
  local job_method
  job_method="${method//_}"
  mkdir -p "${log_root}/${method}"
  vars="${COMMON_VARS},TLTM_REF_LEVEL=${level},TLTM_REF_LABEL=${label},TLTM_CONFIG_JSON=${config},TLTM_ROOT_SUBDIR=${root},TLTM_ROOT_LOG_SUBDIR=${log_root},TLTM_METHOD=${method},TLTM_CHUNK_ID=${chunk_id},TLTM_SEED_OFFSET=${seed_offset},TLTM_MAX_SEEDS=${max_seeds},TLTM_JOBS=${jobs},TLTM_ALLOW_OVERWRITE=${TLTM_ALLOW_OVERWRITE}"
  submit_job qsub \
    -N "m6${level}${job_method}${chunk_id}" \
    -q "${queue}" \
    -l "select=1:ncpus=${ncpus}:mpiprocs=${ncpus}:mem=16gb" \
    -l "walltime=${walltime}" \
    -o "${log_root}/${method}/chunk_${chunk_id}.pbs.out" \
    -W "depend=afterok:${BUILD_JOB}" \
    -v "${vars}" \
    "${CHUNK_PBS}"
}

submit_merge() {
  local level="$1"
  local label="$2"
  local config="$3"
  local root="$4"
  local log_root="$5"
  local expected_rows="$6"
  local requested_cpus="$7"
  shift 7
  local deps
  deps="$(join_by_colon "$@")"
  mkdir -p "${log_root}/merge"
  submit_job qsub \
    -N "m6${level}merge" \
    -q C8 \
    -l select=1:ncpus=1:mpiprocs=1:mem=4gb \
    -l walltime=01:00:00 \
    -o "${log_root}/merge/merge.pbs.out" \
    -W "depend=afterok:${deps}" \
    -v "${COMMON_VARS},TLTM_REF_LEVEL=${level},TLTM_REF_LABEL=${label},TLTM_CONFIG_JSON=${config},TLTM_ROOT_SUBDIR=${root},TLTM_ROOT_LOG_SUBDIR=${log_root},TLTM_EXPECTED_ROWS_PER_METHOD=${expected_rows},TLTM_REQUESTED_CPUS=${requested_cpus},TLTM_CHUNKS_LABEL=${level}_parallel_chunks" \
    "${MERGE_PBS}"
}

submit_level() {
  local level="$1"
  local label="$2"
  local config="$3"
  local root="$4"
  local log_root="$5"
  local expected_rows="$6"
  local walltime="$7"
  local requested_cpus="$8"
  shift 8
  local -a offsets=("$@")
  local -a queues_no_fb=()
  local -a queues_fb=()
  local n_offsets="${#offsets[@]}"
  local i
  for ((i = 0; i < n_offsets; i++)); do
    queues_no_fb+=("${offsets[$i]%%:*}")
    queues_fb+=("${offsets[$i]#*:}")
  done

  local -a chunk_jobs=()
  local max_seeds
  max_seeds=$(( expected_rows / n_offsets ))
  for ((i = 0; i < n_offsets; i++)); do
    local seed_offset=$(( i * max_seeds ))
    local chunk_id
    chunk_id="$(printf "%02d" "${i}")"
    local job_no_fb
    local job_fb
    job_no_fb="$(submit_chunk "${level}" "${label}" "${config}" "${root}" "${log_root}" "no_fb" "${chunk_id}" "${seed_offset}" "${max_seeds}" "${max_seeds}" "${queues_no_fb[$i]}" "${walltime}" "${max_seeds}")"
    job_fb="$(submit_chunk "${level}" "${label}" "${config}" "${root}" "${log_root}" "fb_norefine" "${chunk_id}" "${seed_offset}" "${max_seeds}" "${max_seeds}" "${queues_fb[$i]}" "${walltime}" "${max_seeds}")"
    chunk_jobs+=("${job_no_fb}" "${job_fb}")
    {
      echo "${level}_no_fb_chunk_${chunk_id}=${job_no_fb}"
      echo "${level}_fb_norefine_chunk_${chunk_id}=${job_fb}"
    } | tee -a "${SUBMIT_MANIFEST}"
  done

  local merge_job
  merge_job="$(submit_merge "${level}" "${label}" "${config}" "${root}" "${log_root}" "${expected_rows}" "${requested_cpus}" "${chunk_jobs[@]}")"
  echo "${level}_merge=${merge_job}" | tee -a "${SUBMIT_MANIFEST}"
}

submit_level R1 r1_4seed_1k \
  docs/modernization_reference_t035_r1_4seed_1k.json \
  output/reference/fortran_modernization/m6/r1_4seed_1k \
  output/logs/fortran_modernization/reference_datasets/r1_4seed_1k \
  4 02:00:00 8 \
  C8:C12

submit_level R2 r2_10seed_10k \
  docs/modernization_reference_t035_r2_10seed_10k.json \
  output/reference/fortran_modernization/m6/r2_10seed_10k \
  output/logs/fortran_modernization/reference_datasets/r2_10seed_10k \
  10 06:00:00 20 \
  C8:C12

submit_level R3 r3_32seed_50k \
  docs/modernization_reference_t035_r3_32seed_50k.json \
  output/reference/fortran_modernization/m6/r3_32seed_50k \
  output/logs/fortran_modernization/reference_datasets/r3_32seed_50k \
  32 08:00:00 64 \
  C8:C8 C12:C12 C16:C16 G:G

submit_level R4 r4_128seed_100k \
  docs/modernization_reference_t035_r4_128seed_100k.json \
  output/reference/fortran_modernization/m6/r4_128seed_100k \
  output/logs/fortran_modernization/reference_datasets/r4_128seed_100k \
  128 10:00:00 256 \
  C8:C8 C8:C8 C12:C12 C12:C12 C16:C16 C16:C16 C17:C17 C17:C17 F:F G:G C8-LONG:C8-LONG C8:C8 C12:C12 C16:C16 C17:C17 G:G

echo "submit_manifest=${SUBMIT_MANIFEST}"

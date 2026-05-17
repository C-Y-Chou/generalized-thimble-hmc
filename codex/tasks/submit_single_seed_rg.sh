#!/usr/bin/env bash
set -euo pipefail

PBS_FILE=/home/cychou/TLTM/codex/tasks/pbs/single_seed_rg_capture_template.pbs

if [ ! -f "$PBS_FILE" ]; then
  echo "missing: $PBS_FILE" >&2
  exit 1
fi

: "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:=}"
: "${TLTM_SCHEDULER_REQUEST_ID:=}"
if [ "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY}" != "cluster02_scheduler" ] || [ -z "${TLTM_SCHEDULER_REQUEST_ID}" ]; then
  echo "[ERROR] Actual PBS submission is owned by the cluster02 scheduling agent." >&2
  echo "[ERROR] Set TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler and TLTM_SCHEDULER_REQUEST_ID=<request-id> only from the scheduler workflow." >&2
  exit 2
fi

jobid=$(qsub "$PBS_FILE")
echo "submitted: $jobid"

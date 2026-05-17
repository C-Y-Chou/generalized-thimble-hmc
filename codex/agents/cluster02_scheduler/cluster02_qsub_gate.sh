#!/usr/bin/env bash
# Minimal authority gate for real iTHEMS cluster02 PBS submissions.

set -euo pipefail

: "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY:=}"
: "${TLTM_SCHEDULER_REQUEST_ID:=}"

if [ "${TLTM_CLUSTER02_SCHEDULER_AUTHORITY}" != "cluster02_scheduler" ] || [ -z "${TLTM_SCHEDULER_REQUEST_ID}" ]; then
  echo "[ERROR] Real qsub is owned by the cluster02 scheduling agent." >&2
  echo "[ERROR] Required: TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler and TLTM_SCHEDULER_REQUEST_ID=<request-id>." >&2
  exit 2
fi

if ! command -v qsub >/dev/null 2>&1; then
  echo "[ERROR] qsub not found. Run from the PBS login host." >&2
  exit 2
fi

exec qsub "$@"

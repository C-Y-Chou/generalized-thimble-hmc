#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/cychou/TLTM/codex
TASK_SLUG=${1:?usage: init_task.sh <task_slug> [task_type]}
TASK_TYPE=${2:-general}
W=$ROOT/workspaces/$TASK_SLUG

mkdir -p "$W/context" "$W/runbooks" "$W/state" "$W/tasks"

if [ ! -f "$W/context/TASK.md" ]; then
  cat > "$W/context/TASK.md" <<EOF
# Task: $TASK_SLUG

- Task type: $TASK_TYPE
- Status: planned
- Owner: unassigned
- Root: $W
- Goal: fill in before execution
- Write scope: define in state/ownership.tsv
EOF
fi

if [ ! -f "$W/runbooks/STATUS.md" ]; then
  cat > "$W/runbooks/STATUS.md" <<EOF
# Task Status: $TASK_SLUG

Updated: $(date "+%Y-%m-%d %H:%M:%S %Z")

## Objective
- Fill in task objective.

## Current state
- Not started.

## Next actions
1. Define config and scope.
2. Record run manifest if execution is needed.
EOF
fi

if [ ! -f "$W/state/run_manifest.env" ]; then
  : > "$W/state/run_manifest.env"
fi

if [ ! -f "$W/state/job_tracker.tsv" ]; then
  printf "timestamp\tjobid\tqueue\tstate\tname\n" > "$W/state/job_tracker.tsv"
fi

if [ ! -f "$W/state/session_log.md" ]; then
  cat > "$W/state/session_log.md" <<EOF
# Session Log: $TASK_SLUG

## Template
- Date:
- Goal:
- Config:
- Env vars:
- Output dir:
- Logs dir:
- Key findings:
- Next action:
EOF
fi

if [ ! -f "$W/state/ownership.tsv" ]; then
  cat > "$W/state/ownership.tsv" <<EOF
kind\tpath\tmode
workspace\t$W\twrite
EOF
fi

echo "updated: $(date "+%Y-%m-%d %H:%M:%S %Z")" > "$W/context/LAST_REFRESH.txt"
echo "initialized task workspace: $W"

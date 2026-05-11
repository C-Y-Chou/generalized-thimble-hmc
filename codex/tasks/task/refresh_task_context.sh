#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TASK_SLUG=${1:?usage: refresh_task_context.sh <task_slug>}
W=$ROOT/workspaces/$TASK_SLUG
NOW=$(date "+%Y-%m-%d %H:%M:%S %Z")

[ -d "$W" ] || { echo "task workspace not found: $W" >&2; exit 1; }

echo "updated: $NOW" > "$W/context/LAST_REFRESH.txt"
echo "[refresh_task_context] task=$TASK_SLUG time=$NOW"

echo "[refresh_task_context] status"
sed -n '1,80p' "$W/runbooks/STATUS.md"

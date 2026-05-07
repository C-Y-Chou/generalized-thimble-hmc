#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/cychou/TLTM
W=$ROOT/codex/workspaces/stage3_3_rg_redo
NOW=$(date "+%Y-%m-%d %H:%M:%S %Z")

bash "$ROOT/codex/tasks/refresh_live_board.sh"

echo "updated: $NOW" > "$W/context/LAST_REFRESH.txt"
echo "[refresh_context] task=stage3_3_rg_redo time=$NOW"

sed -n '1,120p' "$W/runbooks/STATUS.md"

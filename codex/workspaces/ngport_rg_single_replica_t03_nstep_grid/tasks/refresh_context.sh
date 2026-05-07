#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/cychou/TLTM
W=$ROOT/codex/workspaces/ngport_rg_single_replica_t03_nstep_grid
NOW=$(date "+%Y-%m-%d %H:%M:%S %Z")

bash "$ROOT/codex/tasks/refresh_live_board.sh"

echo "updated: $NOW" > "$W/context/LAST_REFRESH.txt"
echo "[refresh_context] task=ngport_rg_single_replica_t03_nstep_grid time=$NOW"

sed -n '1,160p' "$W/runbooks/STATUS.md"

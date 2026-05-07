#!/usr/bin/env bash
set -euo pipefail
W=/home/cychou/TLTM/codex/workspaces/stage3_4

bash /home/cychou/TLTM/codex/tasks/refresh_live_board.sh >/dev/null

echo "=== $(date '+%Y-%m-%d %H:%M:%S %Z') ==="
echo

echo "[tracked stage3_4 jobs]"
sed -n '1,200p' "$W/state/job_tracker.tsv"

echo

echo "[raw qstat user view]"
qstat -u cychou

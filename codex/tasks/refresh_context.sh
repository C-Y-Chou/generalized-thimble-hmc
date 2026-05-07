#!/usr/bin/env bash
set -euo pipefail
NOW=$(date "+%Y-%m-%d %H:%M:%S %Z")

bash /home/cychou/TLTM/codex/tasks/refresh_live_board.sh

echo "updated: $NOW" > /home/cychou/TLTM/codex/context/LAST_REFRESH.txt
echo "[refresh_context] updated $NOW"

sed -n '1,120p' /home/cychou/TLTM/codex/runbooks/LIVE_BOARD.md

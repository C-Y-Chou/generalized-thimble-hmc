#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX="$(cd "$SCRIPT_DIR/.." && pwd)"
NOW=$(date "+%Y-%m-%d %H:%M:%S %Z")

bash "$CODEX/tasks/refresh_live_board.sh"

echo "updated: $NOW" > "$CODEX/context/LAST_REFRESH.txt"
echo "[refresh_context] updated $NOW"

sed -n '1,120p' "$CODEX/runbooks/LIVE_BOARD.md"

#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX="$(cd "$SCRIPT_DIR/.." && pwd)"
NOW=$(date "+%Y-%m-%d %H:%M:%S %Z")
echo "updated: $NOW" > "$CODEX/context/LAST_REFRESH.txt"
echo "[refresh_global_context] updated $NOW"

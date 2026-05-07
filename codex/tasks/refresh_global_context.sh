#!/usr/bin/env bash
set -euo pipefail
NOW=$(date "+%Y-%m-%d %H:%M:%S %Z")
echo "updated: $NOW" > /home/cychou/TLTM/codex/context/LAST_REFRESH.txt
echo "[refresh_global_context] updated $NOW"

#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <stage2_log_path> [top_n]" >&2
  exit 1
fi

LOG=$1
TOPN=${2:-20}

if [ ! -f "$LOG" ]; then
  echo "log not found: $LOG" >&2
  exit 1
fi

grep -n "RG_REJECT_CASE" "$LOG" | head -n "$TOPN"

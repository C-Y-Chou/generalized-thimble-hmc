#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v python3.11 >/dev/null 2>&1; then
  exec python3.11 "${SCRIPT_DIR}/submit_m6_reference_dynamic.py" "$@"
fi
exec python3 "${SCRIPT_DIR}/submit_m6_reference_dynamic.py" "$@"

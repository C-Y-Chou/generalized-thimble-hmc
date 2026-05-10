#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
python3 codex/tasks/refresh_remote_state.py "$@"

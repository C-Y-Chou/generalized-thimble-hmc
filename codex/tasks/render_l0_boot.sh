#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
python3 codex/tasks/render_l0_boot.py "$@"

#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/cychou/TLTM
CODEX_DIR=$ROOT/codex

cd "$ROOT"

if command -v module >/dev/null 2>&1; then
  module purge || true
  module load compiler/2025.3.0
  module load mpi/2021.17
  module load mkl/2025.3
fi

echo "[bootstrap] root=$ROOT"
echo "[bootstrap] codex=$CODEX_DIR"
echo "[bootstrap] date=$(date "+%Y-%m-%d %H:%M:%S %Z")"

echo "[bootstrap] active tasks"
if [ -f "$CODEX_DIR/runbooks/task_registry.tsv" ]; then
  sed -n '1,40p' "$CODEX_DIR/runbooks/task_registry.tsv"
fi

echo "[bootstrap] global status"
if [ -f "$CODEX_DIR/runbooks/GLOBAL_STATUS.md" ]; then
  sed -n '1,120p' "$CODEX_DIR/runbooks/GLOBAL_STATUS.md"
fi

if [ -x "$ROOT/bin/run_tltm_stage2" ]; then
  echo "[bootstrap] found bin/run_tltm_stage2"
else
  echo "[bootstrap][warn] bin/run_tltm_stage2 missing"
fi

echo "[bootstrap] refresh live board"
bash "$CODEX_DIR/tasks/refresh_live_board.sh" || true
if [ -f "$CODEX_DIR/runbooks/LIVE_BOARD.md" ]; then
  sed -n '1,120p' "$CODEX_DIR/runbooks/LIVE_BOARD.md"
fi

bash "$CODEX_DIR/tasks/doctor.sh"

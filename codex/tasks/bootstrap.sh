#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(git -C "$CODEX_DIR" rev-parse --show-toplevel)"

cd "$ROOT"

bash "$CODEX_DIR/tasks/assert_canonical_route.sh"

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

echo "[bootstrap] compact L0 status"
if [ -f "$CODEX_DIR/context/L0_BOOT.md" ]; then
  sed -n '1,160p' "$CODEX_DIR/context/L0_BOOT.md"
fi

if [ -x "$ROOT/bin/run_tltm_stage2" ]; then
  echo "[bootstrap] found bin/run_tltm_stage2"
else
  echo "[bootstrap][warn] bin/run_tltm_stage2 missing"
fi

echo "[bootstrap] refresh remote state and render L0"
bash "$CODEX_DIR/tasks/refresh_remote_state.sh" || true
bash "$CODEX_DIR/tasks/refresh_local_state.sh" || true
bash "$CODEX_DIR/tasks/render_l0_boot.sh" || true
if [ -f "$CODEX_DIR/context/L0_BOOT.md" ]; then
  sed -n '1,160p' "$CODEX_DIR/context/L0_BOOT.md"
fi

bash "$CODEX_DIR/tasks/validate_control_plane.sh"
bash "$CODEX_DIR/tasks/doctor.sh"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(git -C "$CODEX_DIR" rev-parse --show-toplevel)"

echo "[doctor] begin"

echo "[doctor] host=$(hostname)"
echo "[doctor] cwd=$(pwd)"
echo "[doctor] root=$ROOT"

bash "$CODEX_DIR/tasks/assert_canonical_route.sh"

echo "[doctor] tools"
command -v qsub >/dev/null 2>&1 && echo "  qsub: ok" || echo "  qsub: missing"
command -v qstat >/dev/null 2>&1 && echo "  qstat: ok" || echo "  qstat: missing"
command -v python3 >/dev/null 2>&1 && echo "  python3: ok" || echo "  python3: missing"
command -v gnuplot >/dev/null 2>&1 && echo "  gnuplot: ok" || echo "  gnuplot: missing"

echo "[doctor] binaries"
for b in run_tltm_stage2 evaluate_expectations; do
  p="$ROOT/bin/$b"
  if [ -x "$p" ]; then
    echo "  $b: ok"
    if command -v ldd >/dev/null 2>&1; then
      miss=$(ldd "$p" | grep "not found" || true)
      if [ -n "$miss" ]; then
        echo "  $b: ldd missing libs"
        echo "$miss"
      fi
    fi
  else
    echo "  $b: missing"
  fi
done

echo "[doctor] queue snapshot"
if command -v qstat >/dev/null 2>&1; then
  qstat -Q | sed -n 1,12p || true
else
  echo "  qstat: unavailable on this host"
fi

echo "[doctor] control plane"
if [ -x "$CODEX_DIR/tasks/validate_control_plane.sh" ]; then
  bash "$CODEX_DIR/tasks/validate_control_plane.sh"
else
  echo "  validate_control_plane: missing"
  exit 2
fi

echo "[doctor] done"

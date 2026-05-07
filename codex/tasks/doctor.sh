#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/cychou/TLTM

echo "[doctor] begin"

echo "[doctor] host=$(hostname)"
echo "[doctor] cwd=$(pwd)"

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
    miss=$(ldd "$p" | grep "not found" || true)
    if [ -n "$miss" ]; then
      echo "  $b: ldd missing libs"
      echo "$miss"
    fi
  else
    echo "  $b: missing"
  fi
done

echo "[doctor] queue snapshot"
qstat -Q | sed -n 1,12p || true

echo "[doctor] done"

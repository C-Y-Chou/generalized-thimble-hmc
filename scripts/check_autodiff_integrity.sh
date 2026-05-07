#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

must_exist=(
  "scripts/generate_model_generated.py"
  "scripts/st_backends/tapenade_codegen.py"
  "scripts/st_backends/enzyme_codegen.py"
  "src/physics/model_action_body.inc"
  "src/physics/model_generated.f90"
)

for rel in "${must_exist[@]}"; do
  if [[ ! -f "${repo_root}/${rel}" ]]; then
    echo "[ERROR] Missing required autodiff file: ${rel}"
    exit 1
  fi
done

if ! grep -q "GEN_BACKEND" "${repo_root}/build/makefile"; then
  echo "[ERROR] build/makefile no longer exposes GEN_BACKEND."
  exit 1
fi

if ! grep -q "st_tapenade" "${repo_root}/scripts/generate_model_generated.py"; then
  echo "[ERROR] generate_model_generated.py missing st_tapenade path."
  exit 1
fi

if ! grep -q "st_enzyme" "${repo_root}/scripts/generate_model_generated.py"; then
  echo "[ERROR] generate_model_generated.py missing st_enzyme path."
  exit 1
fi

echo "[OK] Autodiff integrity check passed."


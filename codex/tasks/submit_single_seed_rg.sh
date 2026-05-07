#!/usr/bin/env bash
set -euo pipefail

PBS_FILE=/home/cychou/TLTM/codex/tasks/pbs/single_seed_rg_capture_template.pbs

if [ ! -f "$PBS_FILE" ]; then
  echo "missing: $PBS_FILE" >&2
  exit 1
fi

jobid=$(qsub "$PBS_FILE")
echo "submitted: $jobid"

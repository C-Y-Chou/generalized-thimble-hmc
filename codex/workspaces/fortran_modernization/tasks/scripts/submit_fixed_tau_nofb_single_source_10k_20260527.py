#!/usr/bin/env python3
"""Submit fixed-tau nofb chains from one successful high-flow bank source."""

import csv
import shutil
import subprocess
from pathlib import Path


BASE_CONTROL = Path("/lustre1/home/cychou/tltm_job_control")
MAIN = Path("/lustre1/home/cychou/TLTM_worktrees/fortran_modernization")
FIXED = Path("/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_fixedtau_29a")
COMMIT = "29a1a4b901526c4971a3aad49f5e3055a521b7e1"
SOURCE_BANK = MAIN / "output" / "stephanov_flow_banks" / (
    "stephanov_n6_t003_fixed_tau_highonly_from_ladder13_20260527"
) / "flow_bank_fixed_tau_t003"
SOURCE_RECORD = 473
BASE_SEED = 9350000
CYCLES = 10000
TIMEOUT = 30000
QUEUE = "C17"
WALLTIME = "08:30:00"
RUN_GROUP = "stephanov_n6_fixed_tau_t003_nofb_single_source473_512x10000_20260527h"


def write_text_executable(path, text):
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


def chunk_targets(chunk):
    return list(range(chunk * 32, (chunk + 1) * 32))


def pbs_text(output_root, log_root):
    return f"""#!/bin/bash
#PBS -N n6s473
#PBS -q {QUEUE}
#PBS -l select=1:ncpus=32:mpiprocs=32:mem=96gb
#PBS -l walltime={WALLTIME}
#PBS -j oe

set -euo pipefail
if [ -f /etc/profile.d/modules.sh ]; then . /etc/profile.d/modules.sh; fi
if [ -f /usr/share/Modules/init/bash ]; then . /usr/share/Modules/init/bash; fi
module purge
module load compiler/2025.3.0
module load mpi/2021.17
module load mkl/2025.3

: "${{TLTM_WORKTREE:={FIXED}}}"
: "${{TLTM_EXPECTED_GIT_COMMIT:={COMMIT}}}"
: "${{TLTM_RUN_GROUP:={RUN_GROUP}}}"
: "${{TLTM_RUN_NAME:?TLTM_RUN_NAME is required}}"
: "${{TLTM_TARGETS_SPEC:?TLTM_TARGETS_SPEC is required}}"
: "${{TLTM_STAGE_CYCLES:={CYCLES}}}"
: "${{TLTM_STAGE_THREADS:=1}}"
: "${{TLTM_TIMEOUT_SEC:={TIMEOUT}}}"
: "${{TLTM_SEED_BASE:={BASE_SEED}}}"
: "${{TLTM_SOURCE_RECORD:={SOURCE_RECORD}}}"
: "${{TLTM_MAIN_WORKTREE:={MAIN}}}"
: "${{TLTM_INIT_FLOW_BANK_ROOT:={SOURCE_BANK}}}"
: "${{TLTM_OUTPUT_ROOT:={output_root}}}"
: "${{TLTM_LOG_ROOT:={log_root}/${{TLTM_RUN_NAME}}}}"

cd "${{TLTM_WORKTREE}}"
mkdir -p "${{TLTM_LOG_ROOT}}"
exec > "${{TLTM_LOG_ROOT}}/pbs_boot_${{PBS_JOBID:-manual}}.log" 2>&1

echo "RUN_DATE=$(date -Is)"
echo "HOSTNAME=$(hostname)"
echo "PBS_JOBID=${{PBS_JOBID:-manual}}"
echo "PBS_QUEUE=${{PBS_QUEUE:-unknown}}"
echo "TLTM_RUN_GROUP=${{TLTM_RUN_GROUP}}"
echo "TLTM_RUN_NAME=${{TLTM_RUN_NAME}}"
echo "TLTM_TARGETS_SPEC=${{TLTM_TARGETS_SPEC}}"
echo "TLTM_SOURCE_RECORD=${{TLTM_SOURCE_RECORD}}"
echo "TLTM_INIT_FLOW_BANK_ROOT=${{TLTM_INIT_FLOW_BANK_ROOT}}"
echo "TLTM_OUTPUT_ROOT=${{TLTM_OUTPUT_ROOT}}"

if [ -f .git ] && grep -q "^gitdir: " .git; then
  GITDIR=$(sed -n "s/^gitdir: //p" .git)
  CURRENT_COMMIT=$(cat "${{GITDIR}}/HEAD")
elif [ -d .git ]; then
  CURRENT_COMMIT=$(cat .git/HEAD)
else
  echo "[ERROR] cannot resolve fixed-tau worktree HEAD without git command" >&2
  exit 2
fi
echo "GIT_COMMIT=${{CURRENT_COMMIT}}"
echo "EXPECTED_GIT_COMMIT=${{TLTM_EXPECTED_GIT_COMMIT}}"
if [ "${{CURRENT_COMMIT}}" != "${{TLTM_EXPECTED_GIT_COMMIT}}" ]; then
  echo "[ERROR] expected commit ${{TLTM_EXPECTED_GIT_COMMIT}}, got ${{CURRENT_COMMIT}}" >&2
  exit 2
fi
if [ ! -x bin/run_tltm_stage2 ]; then echo "[ERROR] missing bin/run_tltm_stage2" >&2; exit 2; fi
if [ ! -f "${{TLTM_INIT_FLOW_BANK_ROOT}}/records/record_$(printf "%06d" "${{TLTM_SOURCE_RECORD}}")/slot_000000.bin" ]; then
  echo "[ERROR] missing source flow-bank record ${{TLTM_SOURCE_RECORD}}" >&2
  exit 2
fi

export TLTM_PYTHON_DEVEL_ROOT="${{TLTM_MAIN_WORKTREE}}/.deps/python-devel-3.11"
export TLTM_DFOLS_VENV_ROOT="${{TLTM_MAIN_WORKTREE}}/.venv-dfols"
export TLTM_OFFICIAL_DFOLS_PYTHONPATH="${{TLTM_DFOLS_VENV_ROOT}}/lib64/python3.11/site-packages:${{TLTM_DFOLS_VENV_ROOT}}/lib/python3.11/site-packages${{TLTM_OFFICIAL_DFOLS_PYTHONPATH:+:${{TLTM_OFFICIAL_DFOLS_PYTHONPATH}}}}"
. codex/workspaces/fortran_modernization/tasks/scripts/python_embed_env.sh
PYTHONHOME="${{TLTM_PYTHON_DEVEL_ROOT}}/usr"
PYTHON="${{PYTHONHOME}}/bin/python3.11"
export PYTHON PYTHONHOME
export PYTHONPATH="${{TLTM_OFFICIAL_DFOLS_PYTHONPATH}}${{PYTHONPATH:+:${{PYTHONPATH}}}}"

export OMP_NUM_THREADS="${{TLTM_STAGE_THREADS}}"
export OPENBLAS_NUM_THREADS="${{TLTM_STAGE_THREADS}}"
export MKL_NUM_THREADS="${{TLTM_STAGE_THREADS}}"
export VECLIB_MAXIMUM_THREADS="${{TLTM_STAGE_THREADS}}"
export OMP_PROC_BIND=false
export CONSTRAINT_FAIL_CAPTURE_START_SAMPLE=2147483647
export TLTM_ODE_BACKEND=dop853
export TLTM_DOP853_HINIT_ENABLED=1
export TLTM_DOP853_STIFFNESS_CHECK_ENABLED=1
export TLTM_DOP853_STIFFNESS_CHECK_INTERVAL=1000
export TLTM_DOP853_STIFFNESS_MAX_HITS=15
export TLTM_DOP853_STIFFNESS_THRESHOLD=6.1

export QN_SOLVER_BACKEND=official_dfols
export QN_OFFICIAL_DFOLS_PRESET=stable_gate77
export QN_OFFICIAL_DFOLS_NPT=0
export QN_OFFICIAL_DFOLS_MAXFUN=500
export QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE=0
export QN_OFFICIAL_DFOLS_RHOBEG=0.20
export QN_OFFICIAL_DFOLS_RHOEND=1e-13
export QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-26
export QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0

IFS=':' read -r -a TARGETS <<< "${{TLTM_TARGETS_SPEC}}"
status=0
pids=()
for target in "${{TARGETS[@]}}"; do
  chain_run_name="${{TLTM_RUN_NAME}}_target_${{target}}_source_${{TLTM_SOURCE_RECORD}}"
  chain_seed_base=$((TLTM_SEED_BASE + target * 1000 - TLTM_SOURCE_RECORD))
  (
    /usr/bin/time -p "${{PYTHON}}" codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py \\
      --skip-build \\
      --records "${{TLTM_SOURCE_RECORD}}" \\
      --cycles "${{TLTM_STAGE_CYCLES}}" \\
      --jobs 1 \\
      --threads "${{TLTM_STAGE_THREADS}}" \\
      --timeout-sec "${{TLTM_TIMEOUT_SEC}}" \\
      --seed-base "${{chain_seed_base}}" \\
      --ladder 3e-2 \\
      --swap-enabled 0 \\
      --parallel-local-updates 1 \\
      --parallel-swaps 0 \\
      --init-flow-bank-root "${{TLTM_INIT_FLOW_BANK_ROOT}}" \\
      --write-cold-observables \\
      --observable-stride 1 \\
      --write-final-snapshot \\
      --output-root "${{TLTM_OUTPUT_ROOT}}" \\
      --run-name "${{chain_run_name}}" \\
      --force
  ) > "${{TLTM_LOG_ROOT}}/chain_${{target}}_source_${{TLTM_SOURCE_RECORD}}.log" 2>&1 &
  pids+=($!)
done
for pid in "${{pids[@]}}"; do
  if ! wait "$pid"; then
    status=1
  fi
done
exit "$status"
"""


def status_text(control, output_root):
    return f"""#!/bin/bash
set -euo pipefail
control={control}
root={output_root}
echo "RUN_DATE=$(date -Is)"
echo "CONTROL=$control"
echo "OUTPUT_ROOT=$root"
if [ -f "$control/jobs.tsv" ]; then
  echo "[jobs]"
  cat "$control/jobs.tsv"
  echo "[qstat]"
  awk -F"\\t" "NR>1 {{print \\$8}}" "$control/jobs.tsv" | xargs -r qstat 2>/dev/null || true
fi
if [ -d "$root" ]; then
  echo "[sample_counts]"
  python3 - <<PY
from pathlib import Path
import os
root = Path("$root")
counts = []
done = 0
for run in sorted(p for p in root.iterdir() if p.is_dir()):
    files = list(run.glob("records/record_*/observable_history.dat"))
    for f in files:
        counts.append(os.path.getsize(str(f)) // 96)
    if (run / "tltm_ladder_aggregate.csv").exists():
        done += 1
if counts:
    counts.sort()
    print("chains", len(counts), "min", counts[0], "median", counts[len(counts)//2], "max", counts[-1])
print("aggregate_files", done)
PY
fi
"""


def main():
    control = BASE_CONTROL / RUN_GROUP
    output_root = MAIN / "output" / "stephanov_fixed_tau_nofb_init_tests" / RUN_GROUP
    log_root = MAIN / "output" / "logs" / "stephanov_fixed_tau_nofb_init_tests" / RUN_GROUP
    if control.exists():
        backup = control.with_name(control.name + ".bak")
        if backup.exists():
            shutil.rmtree(str(backup))
        control.rename(backup)
    control.mkdir(parents=True)
    mapping_path = control / "draw_mapping.csv"
    with mapping_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["target_chain", "source_record", "draw_label", "source_record_note"])
        for target in range(512):
            writer.writerow([target, SOURCE_RECORD, "single_success_source", "single_draw_source_473_nonconstant_prefix"])
    write_text_executable(control / "fixed_tau_nofb_single_source_chunk.pbs", pbs_text(output_root, log_root))
    write_text_executable(control / "status.sh", status_text(control, output_root))
    with (control / "manifest.txt").open("w", encoding="utf-8") as handle:
        handle.write(f"label=single_success_source473\\n")
        handle.write(f"source_bank={SOURCE_BANK}\\n")
        handle.write(f"source_record={SOURCE_RECORD}\\n")
        handle.write(f"mapping_csv={mapping_path}\\n")
        handle.write(f"output_root={output_root}\\n")
        handle.write(f"log_root={log_root}\\n")
        handle.write(f"cycles={CYCLES}\\n")
        handle.write("mode=nofb\\n")
        handle.write("fallback=disabled\\n")
        handle.write("selection_reason=single_draw_source_473_had_nonconstant_histories_before_qdel\\n")
    jobs = []
    for chunk in range(16):
        targets = ":".join(str(t) for t in chunk_targets(chunk))
        run_name = f"nofb_single_source473_t003_10000_c17_{chunk:02d}"
        env = {
            "TLTM_RUN_NAME": run_name,
            "TLTM_TARGETS_SPEC": targets,
        }
        qsub_vars = ",".join(f"{key}={value}" for key, value in env.items())
        qsub_cmd = ["qsub", "-v", qsub_vars]
        qsub_cmd.append(str(control / "fixed_tau_nofb_single_source_chunk.pbs"))
        job_id = subprocess.check_output(qsub_cmd, universal_newlines=True).strip()
        jobs.append((chunk, run_name, targets, job_id))
    with (control / "jobs.tsv").open("w", encoding="utf-8") as handle:
        handle.write("chunk\trun_name\ttargets\tqueue\twalltime\tcycles\ttimeout_sec\tjob\n")
        for chunk, run_name, targets, job_id in jobs:
            handle.write(f"{chunk:02d}\t{run_name}\t{targets}\t{QUEUE}\t{WALLTIME}\t{CYCLES}\t{TIMEOUT}\t{job_id}\n")
    print(f"CONTROL={control}")
    print(f"OUTPUT_ROOT={output_root}")
    print(f"JOBS={[job[-1] for job in jobs]}")


if __name__ == "__main__":
    main()

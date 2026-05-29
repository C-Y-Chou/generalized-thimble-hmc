#!/usr/bin/env python3
"""Submit fixed-tau nofb bank-draw tests as per-chain runner invocations."""

import csv
import os
import random
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
BASE_SEED = 9250000
CYCLES = 15000
TIMEOUT = 41100
QUEUE = "C17"
WALLTIME = "11:55:00"
DRAW_SEED = 20260527


def source_records():
    records = []
    for path in sorted((SOURCE_BANK / "records").glob("record_*")):
        slot = path / "slot_000000.bin"
        if slot.exists():
            records.append(int(path.name.split("_")[-1]))
    if not records:
        raise RuntimeError("No source bank records found: {}".format(SOURCE_BANK))
    return records


def chunk_targets(chunk):
    return list(range(chunk * 32, (chunk + 1) * 32))


def write_text_executable(path, text):
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


def write_mapping(path, sources, label, single_source=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["target_chain", "source_record", "draw_label", "draw_seed", "single_source"])
        for target, source in enumerate(sources):
            writer.writerow([target, source, label, DRAW_SEED, "" if single_source is None else single_source])


def pbs_text(run_group, output_root, log_root):
    return f"""#!/bin/bash
#PBS -N n6nfbd
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
: "${{TLTM_RUN_GROUP:={run_group}}}"
: "${{TLTM_RUN_NAME:?TLTM_RUN_NAME is required}}"
: "${{TLTM_TARGETS_SPEC:?TLTM_TARGETS_SPEC is required}}"
: "${{TLTM_DRAW_MAPPING_CSV:?TLTM_DRAW_MAPPING_CSV is required}}"
: "${{TLTM_STAGE_CYCLES:={CYCLES}}}"
: "${{TLTM_STAGE_THREADS:=1}}"
: "${{TLTM_TIMEOUT_SEC:={TIMEOUT}}}"
: "${{TLTM_SEED_BASE:={BASE_SEED}}}"
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
echo "TLTM_DRAW_MAPPING_CSV=${{TLTM_DRAW_MAPPING_CSV}}"
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
if [ ! -d "${{TLTM_INIT_FLOW_BANK_ROOT}}/records" ]; then echo "[ERROR] missing source flow bank ${{TLTM_INIT_FLOW_BANK_ROOT}}" >&2; exit 2; fi
if [ ! -f "${{TLTM_DRAW_MAPPING_CSV}}" ]; then echo "[ERROR] missing draw mapping ${{TLTM_DRAW_MAPPING_CSV}}" >&2; exit 2; fi

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
  source_record=$(awk -F, -v t="${{target}}" 'NR>1 && $1 == t {{print $2; exit}}' "${{TLTM_DRAW_MAPPING_CSV}}")
  if [ -z "${{source_record}}" ]; then
    echo "[ERROR] missing source record for target ${{target}}" >&2
    status=1
    continue
  fi
  chain_run_name="${{TLTM_RUN_NAME}}_target_${{target}}_source_${{source_record}}"
  chain_seed_base=$((TLTM_SEED_BASE + target * 1000 - source_record))
  (
    /usr/bin/time -p "${{PYTHON}}" codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py \\
      --skip-build \\
      --records "${{source_record}}" \\
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
  ) > "${{TLTM_LOG_ROOT}}/chain_${{target}}_source_${{source_record}}.log" 2>&1 &
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


def write_manifest(control, label, mapping_path, output_root, log_root, single_source=None):
    manifest = control / "manifest.txt"
    with manifest.open("w", encoding="utf-8") as handle:
        handle.write("label={}\n".format(label))
        handle.write("source_bank={}\n".format(SOURCE_BANK))
        handle.write("draw_seed={}\n".format(DRAW_SEED))
        handle.write("mapping_csv={}\n".format(mapping_path))
        handle.write("output_root={}\n".format(output_root))
        handle.write("log_root={}\n".format(log_root))
        if single_source is not None:
            handle.write("single_source_record={}\n".format(single_source))
        handle.write("cycles={}\n".format(CYCLES))
        handle.write("mode=nofb\n")
        handle.write("fallback=disabled\n")


def submit_run(label, sources, seed_offset, single_source=None):
    run_group = "stephanov_n6_fixed_tau_t003_nofb_{}_perchain_512x15000_20260527f".format(label)
    control = BASE_CONTROL / run_group
    output_root = MAIN / "output" / "stephanov_fixed_tau_nofb_init_tests" / run_group
    log_root = MAIN / "output" / "logs" / "stephanov_fixed_tau_nofb_init_tests" / run_group
    if control.exists():
        backup = control.with_name(control.name + ".bak")
        if backup.exists():
            shutil.rmtree(str(backup))
        control.rename(backup)
    control.mkdir(parents=True)
    mapping_path = control / "draw_mapping.csv"
    write_mapping(mapping_path, sources, label, single_source=single_source)
    write_manifest(control, label, mapping_path, output_root, log_root, single_source=single_source)
    pbs = control / "fixed_tau_nofb_bank_draw_chunk.pbs"
    write_text_executable(pbs, pbs_text(run_group, output_root, log_root))
    write_text_executable(control / "status.sh", status_text(control, output_root))
    jobs_tsv = control / "jobs.tsv"
    with jobs_tsv.open("w", encoding="utf-8") as handle:
        handle.write("chunk\trun_name\ttargets\tqueue\twalltime\tcycles\ttimeout_sec\tjob\n")
    jobs = []
    for chunk in range(16):
        targets = chunk_targets(chunk)
        run_name = "nofb_{}_t003_15000_c17_{:02d}".format(label, chunk)
        env_values = {
            "TLTM_RUN_NAME": run_name,
            "TLTM_TARGETS_SPEC": ":".join(str(target) for target in targets),
            "TLTM_DRAW_MAPPING_CSV": str(mapping_path),
            "TLTM_RUN_GROUP": run_group,
            "TLTM_INIT_FLOW_BANK_ROOT": str(SOURCE_BANK),
            "TLTM_OUTPUT_ROOT": str(output_root),
            "TLTM_LOG_ROOT": str(log_root / run_name),
            "TLTM_STAGE_CYCLES": str(CYCLES),
            "TLTM_TIMEOUT_SEC": str(TIMEOUT),
            "TLTM_SEED_BASE": str(BASE_SEED + seed_offset),
        }
        var_arg = ",".join("{}={}".format(key, value) for key, value in env_values.items())
        proc = subprocess.run(
            ["qsub", "-N", "n6bd{}{:02d}".format(label[0], chunk), "-v", var_arg, str(pbs)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            check=False,
        )
        job = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else "SUBMIT_FAILED:{}".format(proc.returncode)
        with jobs_tsv.open("a", encoding="utf-8") as handle:
            handle.write(
                "{:02d}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n".format(
                    chunk,
                    run_name,
                    ":".join(str(target) for target in targets),
                    QUEUE,
                    WALLTIME,
                    CYCLES,
                    TIMEOUT,
                    job,
                )
            )
        jobs.append(job)
    print(label)
    print("CONTROL={}".format(control))
    print("OUTPUT_ROOT={}".format(output_root))
    print("MAPPING={}".format(mapping_path))
    print("JOBS={}".format(",".join(jobs)))


def main():
    records = source_records()
    rng = random.Random(DRAW_SEED)
    random_sources = [rng.choice(records) for _ in range(512)]
    single_source = rng.choice(records)
    single_sources = [single_source for _ in range(512)]
    submit_run("random_draw", random_sources, 0)
    submit_run("single_draw", single_sources, 100000, single_source=single_source)


if __name__ == "__main__":
    main()

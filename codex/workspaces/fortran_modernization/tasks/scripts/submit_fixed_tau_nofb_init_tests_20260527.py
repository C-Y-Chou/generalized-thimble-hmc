#!/usr/bin/env python3
"""Submit fixed-tau nofb initialization tests on cluster02."""

import os
import shutil
import subprocess
from pathlib import Path


BASE_CONTROL = Path("/lustre1/home/cychou/tltm_job_control")
MAIN = Path("/lustre1/home/cychou/TLTM_worktrees/fortran_modernization")
FIXED = Path("/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_fixedtau_29a")
COMMIT = "29a1a4b901526c4971a3aad49f5e3055a521b7e1"
BASE_SEED = 9250000
CYCLES = 15000
TIMEOUT = 41100
QUEUE = "C17"
WALLTIME = "11:55:00"

RUNS = {
    "random_draw": Path(
        "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/"
        "stephanov_flow_banks/stephanov_n6_t003_bank_draw_init_512_20260527/"
        "flow_bank_fixed_tau_t003_random_draw_512_seed20260527"
    ),
    "single_draw": Path(
        "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/"
        "stephanov_flow_banks/stephanov_n6_t003_bank_draw_init_512_20260527/"
        "flow_bank_fixed_tau_t003_single_draw_512_seed20260527"
    ),
}


def records_for_chunk(chunk):
    return list(range(chunk * 32, (chunk + 1) * 32))


def write_text_executable(path, text):
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


def pbs_text(run_group, output_root, log_root, bank_root, seed_base, label):
    return f"""#!/bin/bash
#PBS -N n6nf{label[:2]}
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
: "${{TLTM_RECORDS_SPEC:?TLTM_RECORDS_SPEC is required}}"
: "${{TLTM_STAGE_CYCLES:={CYCLES}}}"
: "${{TLTM_STAGE_JOBS:=32}}"
: "${{TLTM_STAGE_THREADS:=1}}"
: "${{TLTM_TIMEOUT_SEC:={TIMEOUT}}}"
: "${{TLTM_SEED_BASE:={seed_base}}}"
: "${{TLTM_MAIN_WORKTREE:={MAIN}}}"
: "${{TLTM_INIT_FLOW_BANK_ROOT:={bank_root}}}"
: "${{TLTM_OUTPUT_ROOT:={output_root}}}"
: "${{TLTM_LOG_ROOT:={log_root}/${{TLTM_RUN_NAME}}}}"

cd "${{TLTM_WORKTREE}}"
mkdir -p "${{TLTM_LOG_ROOT}}"
exec > "${{TLTM_LOG_ROOT}}/pbs_boot_${{PBS_JOBID:-manual}}.log" 2>&1

echo "RUN_DATE=$(date -Is)"
echo "HOSTNAME=$(hostname)"
echo "PBS_JOBID=${{PBS_JOBID:-manual}}"
echo "PBS_QUEUE=${{PBS_QUEUE:-unknown}}"
echo "TLTM_WORKTREE=${{TLTM_WORKTREE}}"
echo "TLTM_RUN_GROUP=${{TLTM_RUN_GROUP}}"
echo "TLTM_RUN_NAME=${{TLTM_RUN_NAME}}"
echo "TLTM_RECORDS_SPEC=${{TLTM_RECORDS_SPEC}}"
echo "TLTM_STAGE_CYCLES=${{TLTM_STAGE_CYCLES}}"
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
if [ ! -d "${{TLTM_INIT_FLOW_BANK_ROOT}}/records" ]; then echo "[ERROR] missing flow bank ${{TLTM_INIT_FLOW_BANK_ROOT}}" >&2; exit 2; fi

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

TLTM_RECORDS="${{TLTM_RECORDS_SPEC//:/,}}"
/usr/bin/time -p "${{PYTHON}}" codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py \\
  --skip-build \\
  --records "${{TLTM_RECORDS}}" \\
  --cycles "${{TLTM_STAGE_CYCLES}}" \\
  --jobs "${{TLTM_STAGE_JOBS}}" \\
  --threads "${{TLTM_STAGE_THREADS}}" \\
  --timeout-sec "${{TLTM_TIMEOUT_SEC}}" \\
  --seed-base "${{TLTM_SEED_BASE}}" \\
  --ladder 3e-2 \\
  --swap-enabled 0 \\
  --parallel-local-updates 1 \\
  --parallel-swaps 0 \\
  --init-flow-bank-root "${{TLTM_INIT_FLOW_BANK_ROOT}}" \\
  --write-cold-observables \\
  --observable-stride 1 \\
  --write-final-snapshot \\
  --output-root "${{TLTM_OUTPUT_ROOT}}" \\
  --run-name "${{TLTM_RUN_NAME}}" \\
  --force

SUMMARY="${{TLTM_OUTPUT_ROOT}}/${{TLTM_RUN_NAME}}/tltm_ladder_summary.csv"
AGGREGATE="${{TLTM_OUTPUT_ROOT}}/${{TLTM_RUN_NAME}}/tltm_ladder_aggregate.csv"
echo "SUMMARY=${{SUMMARY}}"
echo "AGGREGATE=${{AGGREGATE}}"
cat "${{AGGREGATE}}"
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
for run in sorted(p for p in root.iterdir() if p.is_dir()):
    counts = []
    for f in run.glob("records/record_*/observable_history.dat"):
        counts.append(os.path.getsize(str(f)) // 96)
    if counts:
        counts.sort()
        print(run.name, "records", len(counts), "min", counts[0], "median", counts[len(counts)//2], "max", counts[-1])
print("aggregate_files", len(list(root.glob("*/tltm_ladder_aggregate.csv"))))
PY
  echo "[done_aggregates]"
  find "$root" -mindepth 2 -maxdepth 2 -name tltm_ladder_aggregate.csv -print | sort
fi
"""


def submit_run(label, bank_root, seed_offset):
    run_group = f"stephanov_n6_fixed_tau_t003_nofb_{label}_512x15000_20260527e"
    control = BASE_CONTROL / run_group
    output_root = MAIN / "output" / "stephanov_fixed_tau_nofb_init_tests" / run_group
    log_root = MAIN / "output" / "logs" / "stephanov_fixed_tau_nofb_init_tests" / run_group
    if control.exists():
        backup = control.with_name(control.name + ".bak")
        if backup.exists():
            shutil.rmtree(str(backup))
        control.rename(backup)
    control.mkdir(parents=True)
    pbs = control / "fixed_tau_nofb_chunk.pbs"
    write_text_executable(pbs, pbs_text(run_group, output_root, log_root, bank_root, BASE_SEED + seed_offset, label))
    write_text_executable(control / "status.sh", status_text(control, output_root))
    jobs_tsv = control / "jobs.tsv"
    with jobs_tsv.open("w", encoding="utf-8") as handle:
        handle.write("chunk\trun_name\trecords\tqueue\twalltime\tcycles\ttimeout_sec\tjob\n")
    jobs = []
    for chunk in range(16):
        records = records_for_chunk(chunk)
        run_name = f"nofb_{label}_t003_15000_c17_{chunk:02d}"
        env = os.environ.copy()
        env.update(
            {
                "TLTM_RUN_NAME": run_name,
                "TLTM_RECORDS_SPEC": ":".join(str(record) for record in records),
                "TLTM_RUN_GROUP": run_group,
                "TLTM_INIT_FLOW_BANK_ROOT": str(bank_root),
                "TLTM_OUTPUT_ROOT": str(output_root),
                "TLTM_LOG_ROOT": str(log_root / run_name),
                "TLTM_STAGE_CYCLES": str(CYCLES),
                "TLTM_TIMEOUT_SEC": str(TIMEOUT),
            }
        )
        var_arg = ",".join(
            "{}={}".format(key, env[key])
            for key in (
                "TLTM_RUN_NAME",
                "TLTM_RECORDS_SPEC",
                "TLTM_RUN_GROUP",
                "TLTM_INIT_FLOW_BANK_ROOT",
                "TLTM_OUTPUT_ROOT",
                "TLTM_LOG_ROOT",
                "TLTM_STAGE_CYCLES",
                "TLTM_TIMEOUT_SEC",
            )
        )
        proc = subprocess.run(
            ["qsub", "-N", f"n6nf{label[0]}{chunk:02d}", "-v", var_arg, str(pbs)],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            check=False,
        )
        job = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else f"SUBMIT_FAILED:{proc.returncode}"
        with jobs_tsv.open("a", encoding="utf-8") as handle:
            handle.write(
                f"{chunk:02d}\t{run_name}\t{':'.join(str(record) for record in records)}"
                f"\t{QUEUE}\t{WALLTIME}\t{CYCLES}\t{TIMEOUT}\t{job}\n"
            )
        jobs.append(job)
    print(label)
    print(f"CONTROL={control}")
    print(f"OUTPUT_ROOT={output_root}")
    print("JOBS=" + ",".join(jobs))


def main():
    submit_run("random_draw", RUNS["random_draw"], 0)
    submit_run("single_draw", RUNS["single_draw"], 100000)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Submit lower fixed-tau TLTM scans for WV-HMC initial-bank construction."""

import argparse
import csv
import os
import shlex
import subprocess
from pathlib import Path
from typing import Dict, List


DEFAULT_REMOTE_ROOT = Path("/lustre1/home/cychou/TLTM_worktrees/fortran_modernization")
DEFAULT_SNAPSHOT_ROOT = Path(
    "/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/lower_tau_fixed_builder_scan_20260601"
)
DEFAULT_OUTPUT_ROOT = Path(
    "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/"
    "lower_tau_fixed_builder_scan_20260601"
)
DEFAULT_LOG_ROOT = Path(
    "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/"
    "lower_tau_fixed_builder_scan_20260601"
)
DEFAULT_T0_BANK = Path(
    "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/"
    "wv_hmc_initial_banks_20260531/"
    "stephanov_n6_wv_hmc_t0_bank_16x5000_t0001_20260531_18328.anode01/"
    "safe_bank_t0p0001/x_bank.dat"
)


PBS_TEMPLATE = r"""#!/usr/bin/env bash
set -euo pipefail

if [ -f /etc/profile.d/modules.sh ]; then
  # shellcheck source=/dev/null
  . /etc/profile.d/modules.sh
fi
if [ -f /usr/share/Modules/init/bash ]; then
  # shellcheck source=/dev/null
  . /usr/share/Modules/init/bash
fi
module purge
module load compiler/2025.3.0
module load mpi/2021.17
module load mkl/2025.3

: "${TLTM_CANDIDATE_ENV:?}"
# shellcheck source=/dev/null
. "${TLTM_CANDIDATE_ENV}"

: "${TLTM_WORKTREE:?}"
: "${TLTM_SOURCE_PIN_FILE:?}"
: "${TLTM_RUN_NAME:?}"
: "${TLTM_OUTPUT_ROOT:?}"
: "${TLTM_BASE_PARAMETERS:?}"
: "${TLTM_BANK_FILE:?}"
: "${TLTM_LADDER:?}"
: "${TLTM_RECORDS:?}"
: "${TLTM_CYCLES:?}"
: "${TLTM_HMC_EPSILON:?}"
: "${TLTM_HMC_NSTEP:?}"
: "${TLTM_JOBS:?}"
: "${TLTM_THREADS:?}"
: "${TLTM_TIMEOUT_SEC:?}"

cd "${TLTM_WORKTREE}"

if [ -f "${TLTM_SOURCE_PIN_FILE}" ]; then
  # shellcheck source=/dev/null
  . "${TLTM_SOURCE_PIN_FILE}"
  echo "SOURCE_PIN_ID=${TLTM_SOURCE_PIN_ID:-}"
  echo "SOURCE_PIN_WORKTREE=${TLTM_SOURCE_PIN_WORKTREE:-}"
  echo "SOURCE_PIN_SNAPSHOT_ROOT=${TLTM_SOURCE_PIN_SNAPSHOT_ROOT:-}"
  echo "SOURCE_PIN_DIRTY_COUNT=${TLTM_SOURCE_PIN_DIRTY_COUNT:-}"
elif [ "${TLTM_REQUIRE_SOURCE_PIN:-1}" = "1" ]; then
  echo "[ERROR] source pin missing: ${TLTM_SOURCE_PIN_FILE}" >&2
  exit 2
else
  echo "SOURCE_PIN_UNAVAILABLE=1"
fi

if [ -f codex/workspaces/fortran_modernization/tasks/scripts/python_embed_env.sh ]; then
  # shellcheck source=/dev/null
  . codex/workspaces/fortran_modernization/tasks/scripts/python_embed_env.sh
fi
if [ -x .venv-dfols/bin/python ]; then
  DFOLS_SITE_PACKAGES="$(.venv-dfols/bin/python - <<'PY'
import sysconfig
print(sysconfig.get_paths()["purelib"])
PY
)"
  export TLTM_OFFICIAL_DFOLS_PYTHONPATH="${DFOLS_SITE_PACKAGES}${TLTM_OFFICIAL_DFOLS_PYTHONPATH:+:${TLTM_OFFICIAL_DFOLS_PYTHONPATH}}"
fi
export PYTHONPATH="${TLTM_OFFICIAL_DFOLS_PYTHONPATH:-}${PYTHONPATH:+:${PYTHONPATH}}"

export TLTM_ODE_BACKEND="${TLTM_ODE_BACKEND:-dop853}"
export OMP_NUM_THREADS="${TLTM_THREADS}"
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export OMP_DYNAMIC=FALSE
export MKL_DYNAMIC=FALSE

if [ ! -x bin/run_tltm_stage2 ]; then
  make -C build ../bin/run_tltm_stage2
fi

echo "PBS_JOBID=${PBS_JOBID:-manual}"
echo "HOSTNAME=$(hostname)"
echo "TLTM_RUN_NAME=${TLTM_RUN_NAME}"
echo "TLTM_LADDER=${TLTM_LADDER}"
echo "TLTM_HMC_EPSILON=${TLTM_HMC_EPSILON}"
echo "TLTM_HMC_NSTEP=${TLTM_HMC_NSTEP}"
echo "TLTM_ODE_BACKEND=${TLTM_ODE_BACKEND}"

python3 codex/workspaces/fortran_modernization/tasks/scripts/run_stephanov_n6_tltm_ladder.py \
  --repo-root "${TLTM_WORKTREE}" \
  --base-parameters "${TLTM_BASE_PARAMETERS}" \
  --bank-file "${TLTM_BANK_FILE}" \
  --output-root "${TLTM_OUTPUT_ROOT}" \
  --run-name "${TLTM_RUN_NAME}" \
  --ladder "${TLTM_LADDER}" \
  --records "${TLTM_RECORDS}" \
  --cycles "${TLTM_CYCLES}" \
  --timeout-sec "${TLTM_TIMEOUT_SEC}" \
  --seed-base "${TLTM_SEED_BASE:-9401000}" \
  --preflow-L "${TLTM_PREFLOW_L:-0.16}" \
  --preflow-nstep "${TLTM_PREFLOW_NSTEP:-2}" \
  --hmc-epsilon "${TLTM_HMC_EPSILON}" \
  --hmc-nstep "${TLTM_HMC_NSTEP}" \
  --jobs "${TLTM_JOBS}" \
  --threads "${TLTM_THREADS}" \
  --blas-threads 1 \
  --parallel-local-updates 1 \
  --parallel-swaps 0 \
  --swap-enabled 0 \
  --write-cold-observables \
  --write-cold-x-history \
  --observable-stride "${TLTM_OBSERVABLE_STRIDE:-1}" \
  --write-final-snapshot \
  --skip-build \
  --force
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot-root", type=Path, default=DEFAULT_SNAPSHOT_ROOT)
    parser.add_argument("--source-root", type=Path, default=DEFAULT_REMOTE_ROOT)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--log-root", type=Path, default=DEFAULT_LOG_ROOT)
    parser.add_argument("--batch-name", default="lower_tau_fixed_builder_eps_scan_20260601")
    parser.add_argument("--base-parameters", default="data/parameters_stephanov_n6_mu06_t0.dat")
    parser.add_argument("--bank-file", type=Path, default=DEFAULT_T0_BANK)
    parser.add_argument("--records", default="0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15")
    parser.add_argument("--tau-list", default="0.001")
    parser.add_argument("--epsilon-list", default="0.010,0.020,0.030,0.040,0.060")
    parser.add_argument("--nstep-list", default="")
    parser.add_argument("--fixed-nstep", type=int, default=4)
    parser.add_argument("--fixed-epsilon", type=float, default=0.02)
    parser.add_argument("--cycles", type=int, default=300)
    parser.add_argument("--jobs", type=int, default=16)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--timeout-sec", type=int, default=3600)
    parser.add_argument("--walltime", default="01:00:00")
    parser.add_argument("--mem", default="16gb")
    parser.add_argument("--seed-base", type=int, default=9401000)
    parser.add_argument(
        "--queue-plan",
        default="C17,C16,C12,C8,C17-LONG,C16-LONG,C12-LONG,C8-LONG",
        help="Comma-separated queues assigned cyclically to candidates.",
    )
    parser.add_argument(
        "--scan",
        choices=("epsilon", "nstep"),
        default="epsilon",
        help="epsilon: vary epsilon at fixed nstep. nstep: vary nstep at fixed epsilon.",
    )
    parser.add_argument("--allow-dirty", action="store_true", default=True)
    parser.add_argument("--no-submit", action="store_true")
    parser.add_argument("--no-snapshot", action="store_true")
    return parser.parse_args()


def parse_float_list(text):
    return [float(item.strip()) for item in text.split(",") if item.strip()]


def parse_int_list(text):
    return [int(item.strip()) for item in text.split(",") if item.strip()]


def run(cmd, cwd, env=None):
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        check=False,
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if proc.returncode != 0:
        raise RuntimeError("command failed ({0}):\n{1}".format(" ".join(cmd), proc.stdout))
    return proc.stdout.strip()


def safe_token(value):
    return str(value).replace("-", "m").replace(".", "p").replace("+", "")


def build_candidates(args):
    taus = parse_float_list(args.tau_list)
    candidates = []  # type: List[Dict[str, object]]
    if args.scan == "epsilon":
        epsilons = parse_float_list(args.epsilon_list)
        for tau in taus:
            for epsilon in epsilons:
                candidates.append({"tau": tau, "epsilon": epsilon, "nstep": args.fixed_nstep})
    else:
        nsteps = parse_int_list(args.nstep_list)
        if not nsteps:
            raise RuntimeError("--nstep-list is required for --scan nstep")
        for tau in taus:
            for nstep in nsteps:
                candidates.append({"tau": tau, "epsilon": args.fixed_epsilon, "nstep": nstep})
    for idx, candidate in enumerate(candidates):
        candidate["candidate_id"] = "c{0:02d}".format(idx)
        candidate["hmc_L"] = float(candidate["epsilon"]) * int(candidate["nstep"])
        candidate["run_name"] = (
            "{batch}_{cid}_tau{tau}_eps{eps}_n{nstep}_c{cycles}_r{records}"
        ).format(
            batch=args.batch_name,
            cid=candidate["candidate_id"],
            tau=safe_token(candidate["tau"]),
            eps=safe_token(candidate["epsilon"]),
            nstep=candidate["nstep"],
            cycles=args.cycles,
            records=len(parse_int_list(args.records)),
        )
    return candidates


def write_manifest(path, candidates, args):
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "candidate_id",
        "scan",
        "tau",
        "epsilon",
        "nstep",
        "hmc_L",
        "cycles",
        "records",
        "run_name",
        "run_dir",
        "output_root",
        "bank_file",
        "base_parameters",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for candidate in candidates:
            row = {
                "scan": args.scan,
                "cycles": args.cycles,
                "records": args.records,
                "run_dir": str(args.output_root / str(candidate["run_name"])),
                "output_root": str(args.output_root),
                "bank_file": str(args.bank_file),
                "base_parameters": args.base_parameters,
                **candidate,
            }
            writer.writerow(row)


def ensure_snapshot(args):
    if args.no_snapshot:
        return
    cmd = [
        "python3",
        "codex/workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py",
        "runtime-snapshot",
        "--snapshot-root",
        str(args.snapshot_root),
        "--allow-dirty",
        "--delete",
    ]
    print(run(cmd, cwd=args.source_root))


def submit_candidates(args, candidates):
    control_root = args.log_root / args.batch_name / "submit"
    control_root.mkdir(parents=True, exist_ok=True)
    pbs_path = control_root / "lower_tau_fixed_builder_candidate.pbs"
    pbs_path.write_text(PBS_TEMPLATE, encoding="utf-8")
    queues = [item.strip() for item in args.queue_plan.split(",") if item.strip()]
    if not queues:
        raise RuntimeError("--queue-plan must contain at least one queue")
    gate = args.snapshot_root / "codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh"
    source_pin = (
        args.snapshot_root
        / "codex/workspaces/fortran_modernization/state/CLUSTER02_SOURCE_PIN.env"
    )
    manifest_path = control_root / "submitted_jobs.tsv"
    env = os.environ.copy()
    env["TLTM_CLUSTER02_SCHEDULER_AUTHORITY"] = "cluster02_scheduler"
    env["TLTM_SCHEDULER_REQUEST_ID"] = "FMOD-LOWER-TAU-FIXED-BUILDER-SCAN-20260601"
    fields = [
        "candidate_id",
        "queue",
        "job_id",
        "tau",
        "epsilon",
        "nstep",
        "hmc_L",
        "cycles",
        "records",
        "run_name",
    ]
    with manifest_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for idx, candidate in enumerate(candidates):
            queue = queues[idx % len(queues)]
            ncpus = max(1, int(args.jobs) * int(args.threads))
            env_path = control_root / "candidate_{0}.env".format(candidate["candidate_id"])
            env_values = {
                "TLTM_WORKTREE": str(args.snapshot_root),
                "TLTM_REQUIRE_SOURCE_PIN": "1",
                "TLTM_SOURCE_PIN_FILE": str(source_pin),
                "TLTM_RUN_NAME": str(candidate["run_name"]),
                "TLTM_OUTPUT_ROOT": str(args.output_root),
                "TLTM_BASE_PARAMETERS": str(args.base_parameters),
                "TLTM_BANK_FILE": str(args.bank_file),
                "TLTM_LADDER": str(candidate["tau"]),
                "TLTM_RECORDS": str(args.records),
                "TLTM_CYCLES": str(args.cycles),
                "TLTM_HMC_EPSILON": str(candidate["epsilon"]),
                "TLTM_HMC_NSTEP": str(candidate["nstep"]),
                "TLTM_JOBS": str(args.jobs),
                "TLTM_THREADS": str(args.threads),
                "TLTM_TIMEOUT_SEC": str(args.timeout_sec),
                "TLTM_SEED_BASE": str(args.seed_base),
                "TLTM_ODE_BACKEND": "dop853",
            }
            env_path.write_text(
                "".join(
                    "export {0}={1}\n".format(key, shlex.quote(env_values[key]))
                    for key in sorted(env_values)
                ),
                encoding="utf-8",
            )
            if args.no_submit:
                job_id = "DRY_RUN"
            else:
                job_name = "ltfb{0}".format(str(candidate["candidate_id"]).replace("c", ""))
                cmd = [
                    str(gate),
                    "-q",
                    queue,
                    "-N",
                    job_name,
                    "-k",
                    "n",
                    "-l",
                    "select=1:ncpus={0}:mpiprocs={0}:mem={1}".format(ncpus, args.mem),
                    "-l",
                    "walltime={}".format(args.walltime),
                    "-v",
                    "TLTM_CANDIDATE_ENV={}".format(env_path),
                    str(pbs_path),
                ]
                job_id = run(cmd, cwd=args.source_root, env=env).splitlines()[-1]
            row = {
                "queue": queue,
                "job_id": job_id,
                "cycles": args.cycles,
                "records": args.records,
                **candidate,
            }
            writer.writerow(row)
            print(
                "{candidate_id}\t{queue}\t{job_id}\ttau={tau}\teps={epsilon}\tnstep={nstep}\tL={hmc_L}".format(
                    **row
                )
            )
    return manifest_path


def main() -> int:
    args = parse_args()
    candidates = build_candidates(args)
    if not candidates:
        raise RuntimeError("no candidates")
    args.output_root.mkdir(parents=True, exist_ok=True)
    args.log_root.mkdir(parents=True, exist_ok=True)
    batch_manifest = args.output_root / args.batch_name / "candidate_manifest.csv"
    write_manifest(batch_manifest, candidates, args)
    ensure_snapshot(args)
    submitted_manifest = submit_candidates(args, candidates)
    print("candidate_manifest={}".format(batch_manifest))
    print("submitted_jobs={}".format(submitted_manifest))
    print("output_root={}".format(args.output_root))
    print("snapshot_root={}".format(args.snapshot_root))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

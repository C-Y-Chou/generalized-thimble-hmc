#!/usr/bin/env python3
"""Submit WV-HMC T0=0 W(t)/HMC retuning scans through cluster02 gate.

This is a submission helper only.  It does not run simulations locally.
"""

import argparse
import subprocess
from pathlib import Path


DEFAULT_SNAPSHOT = Path("/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/wv_hmc_n6_t003_prod15k_gitless_r3_20260601")
DEFAULT_BANK = Path(
    "/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/"
    "output/wv_hmc_initial_banks_20260601/current_stephanov_n6_t0_state_bank/"
    "state_bank_tau0/x_bank.dat"
)


def token(value):
    text = str(value)
    text = text.replace(".", "p").replace("-", "m")
    return text


def parse_float_list(text):
    return [float(part) for part in text.split(",") if part.strip()]


def parse_int_list(text):
    return [int(part) for part in text.split(",") if part.strip()]


def queue_plan(count):
    queues = [
        "C17", "C17", "C17", "C17",
        "C16", "C16", "C16", "C16",
        "C8", "C8", "C8", "C8",
        "C12", "C12",
        "C17-LONG", "C17-LONG",
        "C12-LONG", "C12-LONG",
        "C8-LONG", "C8-LONG",
    ]
    if count <= len(queues):
        return queues[:count]
    out = []
    while len(out) < count:
        out.extend(queues)
    return out[:count]


def build_vars(args, combo, chunk_id, seed_start):
    gamma, step_size, num_steps = combo
    measurement_t1 = args.measurement_t1
    if measurement_t1 is None:
        measurement_t1 = args.t1
    values = {
        "TLTM_WORKTREE": str(args.snapshot_root),
        "TLTM_REQUIRE_SOURCE_PIN": "1",
        "TLTM_SOURCE_PIN_FILE": str(args.source_pin_file),
        "TLTM_RUN_NAME": args.run_name,
        "TLTM_OUTPUT_ROOT": args.output_root,
        "TLTM_LOG_ROOT": args.log_root,
        "TLTM_PARAMETERS_FILE": args.parameters_file,
        "WV_OBS_CHUNK_ID": chunk_id,
        "WV_OBS_SEED_START": str(seed_start),
        "WV_OBS_SEED_COUNT": str(args.seeds_per_job),
        "WV_OBS_CYCLES": str(args.cycles),
        "WV_OBS_MEASUREMENT_START_CYCLE": str(args.measurement_start_cycle),
        "WV_OBS_STEP_SIZE": "{:.12g}".format(step_size),
        "WV_OBS_NUM_STEPS": str(num_steps),
        "WV_OBS_INIT_MODE": "state_bank",
        "WV_OBS_INIT_BANK_FILE": str(args.init_bank),
        "WV_OBS_INIT_BANK_RECORD": "-1",
        "WV_OBS_WRITE_FINAL_STATE": "1" if args.write_final_state else "0",
        "WV_OBS_WRITE_OBSERVABLE_HISTORY": "1",
        "WV_OBS_WRITE_X_HISTORY": "0",
        "WV_OBS_WRITE_STATE_HISTORY": "0",
        "WV_OBS_HISTORY_STRIDE": str(args.history_stride),
        "WV_OBS_WRITE_CYCLIC_SNAPSHOT": "1" if args.write_cyclic_snapshot else "0",
        "WV_OBS_SNAPSHOT_INTERVAL": str(args.snapshot_interval),
        "WV_OBS_SNAPSHOT_SLOTS": str(args.snapshot_slots),
        "WV_OBS_JOBS": str(args.seeds_per_job),
        "WV_OBS_TIMEOUT_SEC": str(args.timeout_sec),
        "WV_OBS_CONSTRAINT_TOL": "1.0e-10",
        "WV_OBS_CONSTRAINT_MAX_ITER": str(args.constraint_max_iter),
        "WV_OBS_ADAPTIVE_NEWTON_STOP_ENABLED": "0",
        "WV_OBS_LARGE_RESIDUAL_STOP_ENABLED": "0",
        "WV_OBS_T0": "0.0",
        "WV_OBS_T1": "{:.12g}".format(args.t1),
        "WV_OBS_D0": "{:.12g}".format(args.d0),
        "WV_OBS_D1": "{:.12g}".format(args.d1),
        "WV_OBS_MEASUREMENT_T0": "{:.12g}".format(args.measurement_t0),
        "WV_OBS_MEASUREMENT_T1": "{:.12g}".format(measurement_t1),
        "WV_OBS_FLOW_TIME": "0.0",
        "WV_OBS_W_PROFILE": "paper_wall",
        "WV_OBS_W_GAMMA": "{:.12g}".format(gamma),
        "WV_OBS_W_C0": "1.0",
        "WV_OBS_W_C1": "1.0",
        "TLTM_ODE_BACKEND": "dop853",
    }
    return ",".join("{}={}".format(key, value) for key, value in values.items())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot-root", type=Path, default=DEFAULT_SNAPSHOT)
    parser.add_argument("--source-pin-file", type=Path, default=None)
    parser.add_argument("--pbs-script", type=Path, default=None)
    parser.add_argument("--qsub-gate", type=Path, default=None)
    parser.add_argument("--init-bank", type=Path, default=DEFAULT_BANK)
    parser.add_argument("--run-name", default="wv_hmc_n6_t0_retune_gamma_eps_20260601")
    parser.add_argument("--output-root", default="/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_retune_20260601")
    parser.add_argument("--log-root", default=None)
    parser.add_argument("--request-id", default="FMOD-WV-HMC-T0-RETUNE-GAMMA-EPS-20260601")
    parser.add_argument("--parameters-file", default="data/parameters_stephanov_n6_mu06_t0.dat")
    parser.add_argument("--gammas", default="0,35,55,75,95,125")
    parser.add_argument("--step-sizes", default="0.004,0.006,0.008,0.010")
    parser.add_argument("--num-steps", default="8")
    parser.add_argument("--seed-start", type=int, default=9600001)
    parser.add_argument("--seeds-per-job", type=int, default=8)
    parser.add_argument("--chunks-per-combo", type=int, default=1)
    parser.add_argument("--cycles", type=int, default=250)
    parser.add_argument("--measurement-start-cycle", type=int, default=1)
    parser.add_argument("--history-stride", type=int, default=1)
    parser.add_argument("--write-final-state", action="store_true")
    parser.add_argument("--write-cyclic-snapshot", action="store_true")
    parser.add_argument("--snapshot-interval", type=int, default=500)
    parser.add_argument("--snapshot-slots", type=int, default=8)
    parser.add_argument("--constraint-max-iter", type=int, default=192)
    parser.add_argument("--timeout-sec", type=int, default=4200)
    parser.add_argument("--walltime", default="01:30:00")
    parser.add_argument("--mem", default="12gb")
    parser.add_argument("--t1", type=float, default=0.03)
    parser.add_argument("--d0", type=float, default=0.0001)
    parser.add_argument("--d1", type=float, default=0.005)
    parser.add_argument("--measurement-t0", type=float, default=0.0)
    parser.add_argument("--measurement-t1", type=float, default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.source_pin_file is None:
        args.source_pin_file = args.snapshot_root / "codex/workspaces/fortran_modernization/state/CLUSTER02_SOURCE_PIN.env"
    if args.pbs_script is None:
        args.pbs_script = args.snapshot_root / "codex/workspaces/fortran_modernization/tasks/pbs/wv_hmc_observable_chunk_nobuild_20260530.pbs"
    if args.qsub_gate is None:
        args.qsub_gate = args.snapshot_root / "codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh"
    if args.log_root is None:
        args.log_root = args.output_root.replace("/output/", "/output/logs/") + "/" + args.run_name

    gammas = parse_float_list(args.gammas)
    step_sizes = parse_float_list(args.step_sizes)
    num_steps_values = parse_int_list(args.num_steps)
    base_combos = [(gamma, step, nstep) for gamma in gammas for step in step_sizes for nstep in num_steps_values]
    combos = []
    for combo in base_combos:
        for repeat in range(args.chunks_per_combo):
            combos.append((combo, repeat))
    queues = queue_plan(len(combos))

    for required in [args.snapshot_root, args.source_pin_file, args.pbs_script, args.qsub_gate, args.init_bank]:
        if not required.exists():
            raise SystemExit("missing required path: {}".format(required))

    log_root = Path(args.log_root)
    submit_dir = log_root / "submit"
    if not args.dry_run:
        submit_dir.mkdir(parents=True, exist_ok=True)
    manifest = submit_dir / "submitted_jobs.tsv"
    header = "chunk\tqueue\tjob_id\tgamma\tstep_size\tnum_steps\tseed_start\tseed_count\tcycles\n"
    if not args.dry_run:
        manifest.write_text(header)

    env_prefix = [
        "TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler",
        "TLTM_SCHEDULER_REQUEST_ID={}".format(args.request_id),
    ]

    for idx, item in enumerate(combos):
        combo, repeat = item
        gamma, step_size, nstep = combo
        chunk_id = "{:02d}".format(idx)
        seed_start = args.seed_start + idx * args.seeds_per_job
        queue = queues[idx]
        name = "wvT0g{}e{}n{}".format(token(int(gamma) if gamma.is_integer() else gamma), token(step_size), nstep)
        name = name[:15]
        vars_text = build_vars(args, combo, chunk_id, seed_start)
        cmd = [
            str(args.qsub_gate),
            "-q", queue,
            "-N", name,
            "-l", "select=1:ncpus={0}:mpiprocs={0}:mem={1}".format(args.seeds_per_job, args.mem),
            "-l", "walltime={}".format(args.walltime),
            "-v", vars_text,
            str(args.pbs_script),
        ]
        print("submit chunk={} repeat={} queue={} gamma={} step={} nstep={} seed_start={}".format(
            chunk_id, repeat, queue, gamma, step_size, nstep, seed_start
        ))
        if args.dry_run:
            print(" ".join(env_prefix + cmd))
            job_id = "DRYRUN"
        else:
            env = None
            shell_cmd = "{} {} {}".format(env_prefix[0], env_prefix[1], " ".join("'{}'".format(part) for part in cmd))
            job_id = subprocess.check_output(shell_cmd, shell=True, universal_newlines=True).strip()
        line = "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n".format(
            chunk_id, queue, job_id, gamma, step_size, nstep, seed_start, args.seeds_per_job, args.cycles
        )
        if args.dry_run:
            print(line.rstrip())
        else:
            with manifest.open("a") as handle:
                handle.write(line)
    print("manifest={}".format(manifest))
    print("output_root={}/{}".format(args.output_root, args.run_name))
    print("jobs={}".format(len(combos)))


if __name__ == "__main__":
    main()

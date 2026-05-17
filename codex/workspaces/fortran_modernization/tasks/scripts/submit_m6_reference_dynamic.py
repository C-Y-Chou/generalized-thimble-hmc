#!/usr/bin/env python3
"""Submit M6 reference datasets with manual-aware dynamic PBS queue selection.

This launcher is intentionally conservative:

- It only uses CPU queues that are valid for one-node TLTM chunks.
- It excludes GPU queues unless explicitly allowed.
- It treats observed production-shape failures as queue blacklists.
- It never repairs jobs with qmove; replacement jobs must be resubmitted.
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
if sys.version_info < (3, 8):
    raise SystemExit("submit_m6_reference_dynamic.py requires Python >= 3.8; use python3.11 or submit_m6_reference_datasets.sh")

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple


@dataclass(frozen=True)
class QueueSpec:
    name: str
    min_nodes: int
    max_nodes: int
    cores_per_node: int
    max_walltime_hours: int
    cpu_only: bool
    base_penalty: int
    note: str


@dataclass(frozen=True)
class LevelSpec:
    level: str
    label: str
    config: str
    root: str
    log_root: str
    expected_rows: int
    chunks_per_method: int
    walltime: str
    requested_cpus: int

    @property
    def seeds_per_chunk(self) -> int:
        return self.expected_rows // self.chunks_per_method


MANUAL_QUEUE_SPECS: Dict[str, QueueSpec] = {
    "C8": QueueSpec("C8", 1, 8, 40, 12, True, 0, "CPU, short"),
    "C8-LONG": QueueSpec("C8-LONG", 1, 8, 40, 48, True, 10, "CPU, long"),
    "C16": QueueSpec("C16", 1, 16, 32, 12, True, 9, "CPU, short; no immediate-start evidence from M6 probe"),
    "C24": QueueSpec("C24", 17, 24, 32, 12, True, 10_000, "CPU, multi-node only"),
    "C12": QueueSpec("C12", 1, 12, 48, 12, True, 2, "CPU, short"),
    "C12-LONG": QueueSpec("C12-LONG", 1, 12, 48, 72, True, 6, "CPU, long; M6 production-shape probe passed"),
    "C12-LONG2": QueueSpec("C12-LONG2", 1, 2, 48, 168, True, 10_000, "CPU, usually stopped"),
    "C36": QueueSpec("C36", 25, 36, 32, 12, True, 10_000, "CPU, multi-node only"),
    "C17": QueueSpec("C17", 1, 17, 48, 12, True, 10_000, "CPU, observed bad for 8-core TLTM chunks"),
    "C17-LONG": QueueSpec("C17-LONG", 1, 17, 48, 72, True, 10_000, "CPU, observed bad for 8-core TLTM chunks"),
    "F": QueueSpec("F", 1, 1, 64, 12, True, 8, "CPU, fat node"),
    "G": QueueSpec("G", 1, 4, 32, 12, False, 10_000, "GPU, not for CPU-only chunks"),
    "G-LONG": QueueSpec("G-LONG", 1, 1, 32, 72, False, 10_000, "GPU, not for CPU-only chunks"),
    "G-A100": QueueSpec("G-A100", 1, 2, 64, 72, False, 10_000, "GPU, not for CPU-only chunks"),
}

POLICY_EXCLUDED_QUEUES: Dict[str, str] = {
    "C24": "manual node range starts at 17 nodes; M6 chunks request one node",
    "C36": "manual node range starts at 25 nodes; M6 chunks request one node",
    "C12-LONG2": "live cluster status observed stopped; keep out of automatic scheduling",
    "C17": "8-core TLTM production-shape chunks observed Exit_status=127",
    "C17-LONG": "8-core TLTM production-shape chunks observed Exit_status=127",
    "G": "GPU queue consumes GPUs by default; not for CPU-only TLTM chunks",
    "G-LONG": "GPU queue consumes GPUs by default; not for CPU-only TLTM chunks",
    "G-A100": "GPU queue consumes GPUs by default; not for CPU-only TLTM chunks",
}

DEFAULT_KNOWLEDGE_PATH = Path(
    "codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_KNOWLEDGE.json"
)
SCHEDULER_AUTHORITY_ENV = "TLTM_CLUSTER02_SCHEDULER_AUTHORITY"
SCHEDULER_REQUEST_ENV = "TLTM_SCHEDULER_REQUEST_ID"
SCHEDULER_AUTHORITY_VALUE = "cluster02_scheduler"

LEVELS: Tuple[LevelSpec, ...] = (
    LevelSpec(
        "R1",
        "r1_4seed_1k",
        "docs/modernization_reference_t035_r1_4seed_1k.json",
        "output/reference/fortran_modernization/m6/r1_4seed_1k",
        "output/logs/fortran_modernization/reference_datasets/r1_4seed_1k",
        4,
        1,
        "02:00:00",
        8,
    ),
    LevelSpec(
        "R2",
        "r2_10seed_10k",
        "docs/modernization_reference_t035_r2_10seed_10k.json",
        "output/reference/fortran_modernization/m6/r2_10seed_10k",
        "output/logs/fortran_modernization/reference_datasets/r2_10seed_10k",
        10,
        1,
        "06:00:00",
        20,
    ),
    LevelSpec(
        "R3",
        "r3_32seed_50k",
        "docs/modernization_reference_t035_r3_32seed_50k.json",
        "output/reference/fortran_modernization/m6/r3_32seed_50k",
        "output/logs/fortran_modernization/reference_datasets/r3_32seed_50k",
        32,
        4,
        "08:00:00",
        64,
    ),
    LevelSpec(
        "R4",
        "r4_128seed_100k",
        "docs/modernization_reference_t035_r4_128seed_100k.json",
        "output/reference/fortran_modernization/m6/r4_128seed_100k",
        "output/logs/fortran_modernization/reference_datasets/r4_128seed_100k",
        128,
        16,
        "10:00:00",
        256,
    ),
)


def run(
    args: List[str],
    *,
    cwd: Path,
    dry_run: bool = False,
    capture: bool = False,
) -> str:
    if dry_run and not capture:
        print(" ".join(shlex.quote(arg) for arg in args), file=sys.stderr)
        return dryrun_job_id(args)
    result = subprocess.run(
        args,
        cwd=str(cwd),
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else ""


def dryrun_job_id(args: List[str]) -> str:
    for idx, arg in enumerate(args[:-1]):
        if arg == "-N":
            return f"DRYRUN_{args[idx + 1]}"
    return "DRYRUN_job"


def repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    return Path(result.stdout.strip()).resolve()


def git_value(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=str(root),
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()


def load_scheduler_knowledge(root: Path, knowledge_path: Optional[str]) -> Dict[str, object]:
    path = Path(knowledge_path) if knowledge_path else root / DEFAULT_KNOWLEDGE_PATH
    if not path.is_absolute():
        path = root / path
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def knowledge_queue_policy(knowledge: Dict[str, object]) -> Dict[str, object]:
    policy = knowledge.get("queue_policy", {})
    return policy if isinstance(policy, dict) else {}


def policy_excluded_queues(knowledge: Dict[str, object]) -> Dict[str, str]:
    excluded = dict(POLICY_EXCLUDED_QUEUES)
    policy = knowledge_queue_policy(knowledge)
    from_knowledge = policy.get("excluded_by_default", {})
    if isinstance(from_knowledge, dict):
        for queue, reason in from_knowledge.items():
            excluded[str(queue)] = str(reason)
    return excluded


def queue_penalty_overrides(knowledge: Dict[str, object]) -> Dict[str, int]:
    policy = knowledge_queue_policy(knowledge)
    raw = policy.get("queue_penalty_overrides", {})
    if not isinstance(raw, dict):
        return {}
    overrides: Dict[str, int] = {}
    for queue, value in raw.items():
        try:
            overrides[str(queue)] = int(value)
        except (TypeError, ValueError):
            continue
    return overrides


def parse_walltime_hours(walltime: str) -> float:
    match = re.fullmatch(r"(\d+):(\d{2}):(\d{2})", walltime)
    if not match:
        raise ValueError(f"unsupported walltime format: {walltime}")
    hours, minutes, seconds = (int(part) for part in match.groups())
    return hours + minutes / 60.0 + seconds / 3600.0


def parse_state_count(value: str) -> Dict[str, int]:
    counts: Dict[str, int] = {}
    for key, raw in re.findall(r"([A-Za-z]+):(\d+)", value):
        counts[key] = int(raw)
    return counts


def parse_qstat_qf(text: str) -> Dict[str, Dict[str, object]]:
    queues: Dict[str, Dict[str, object]] = {}
    current: Optional[Dict[str, object]] = None
    for line in text.splitlines():
        if line.startswith("Queue: "):
            name = line.split(":", 1)[1].strip()
            current = {"name": name, "raw": {}}
            queues[name] = current
            continue
        if current is None or " = " not in line:
            continue
        key, value = (part.strip() for part in line.split(" = ", 1))
        raw = current.get("raw")
        if isinstance(raw, dict):
            raw[key] = value
        if key == "enabled":
            current["enabled"] = value.lower() in {"true", "1", "yes"}
        elif key == "started":
            current["started"] = value.lower() in {"true", "1", "yes"}
        elif key == "state_count":
            current["state_count"] = parse_state_count(value)
        elif key == "total_jobs":
            try:
                current["total_jobs"] = int(value)
            except ValueError:
                pass
    return queues


def load_queue_snapshot(root: Path, *, dry_run: bool, snapshot_file: Optional[str]) -> Dict[str, Dict[str, object]]:
    if snapshot_file:
        return parse_qstat_qf(Path(snapshot_file).read_text(encoding="utf-8"))
    if dry_run and not shutil_which("qstat"):
        return {}
    try:
        text = run(["qstat", "-Qf"], cwd=root, capture=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        if dry_run:
            return {}
        raise
    return parse_qstat_qf(text)


def shutil_which(command: str) -> Optional[str]:
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / command
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def is_queue_eligible(
    queue_name: str,
    *,
    ncpus: int,
    walltime: str,
    live: Dict[str, Dict[str, object]],
    allow_gpu: bool,
    allow_observed_bad: bool,
    excluded_queues: Dict[str, str],
) -> Tuple[bool, str]:
    spec = MANUAL_QUEUE_SPECS[queue_name]
    if spec.min_nodes > 1:
        return False, f"requires at least {spec.min_nodes} nodes"
    if ncpus > spec.cores_per_node:
        return False, f"needs {ncpus} cpus, queue has {spec.cores_per_node}"
    if parse_walltime_hours(walltime) > spec.max_walltime_hours:
        return False, f"walltime {walltime} exceeds queue limit"
    if not spec.cpu_only and not allow_gpu:
        return False, "GPU queue excluded for CPU-only TLTM chunks"
    if queue_name in excluded_queues:
        if "GPU" in excluded_queues[queue_name] and allow_gpu:
            pass
        elif allow_observed_bad and "Exit_status=127" in excluded_queues[queue_name]:
            pass
        else:
            return False, excluded_queues[queue_name]
    live_info = live.get(queue_name)
    if live_info is not None:
        if live_info.get("enabled") is False:
            return False, "live qstat reports disabled"
        if live_info.get("started") is False:
            return False, "live qstat reports stopped"
    return True, "eligible"


def queue_score(
    queue_name: str,
    *,
    live: Dict[str, Dict[str, object]],
    assigned: Dict[str, int],
    penalty_overrides: Dict[str, int],
) -> int:
    spec = MANUAL_QUEUE_SPECS[queue_name]
    score = penalty_overrides.get(queue_name, spec.base_penalty)
    score += assigned.get(queue_name, 0) * 6
    live_info = live.get(queue_name)
    if live_info is None:
        score += 3
        return score
    state_count = live_info.get("state_count", {})
    if isinstance(state_count, dict):
        queued = int(state_count.get("Queued", 0))
        running = int(state_count.get("Running", 0))
        held = int(state_count.get("Held", 0))
        waiting = int(state_count.get("Waiting", 0))
        score += queued * 8 + waiting * 5 + held * 3
        score += min(running, 80) // 8
    total_jobs = live_info.get("total_jobs")
    if isinstance(total_jobs, int):
        score += min(total_jobs, 120) // 12
    return score


def choose_queue(
    *,
    ncpus: int,
    walltime: str,
    live: Dict[str, Dict[str, object]],
    assigned: Dict[str, int],
    allow_gpu: bool,
    allow_observed_bad: bool,
    excluded_queues: Dict[str, str],
    penalty_overrides: Dict[str, int],
) -> str:
    candidates: List[Tuple[int, str]] = []
    rejection_notes: Dict[str, str] = {}
    for queue_name in MANUAL_QUEUE_SPECS:
        ok, reason = is_queue_eligible(
            queue_name,
            ncpus=ncpus,
            walltime=walltime,
            live=live,
            allow_gpu=allow_gpu,
            allow_observed_bad=allow_observed_bad,
            excluded_queues=excluded_queues,
        )
        if ok:
            candidates.append(
                (
                    queue_score(
                        queue_name,
                        live=live,
                        assigned=assigned,
                        penalty_overrides=penalty_overrides,
                    ),
                    queue_name,
                )
            )
        else:
            rejection_notes[queue_name] = reason
    if not candidates:
        details = "; ".join(f"{queue}={reason}" for queue, reason in sorted(rejection_notes.items()))
        raise RuntimeError(f"no eligible PBS queue for ncpus={ncpus}, walltime={walltime}: {details}")
    candidates.sort()
    chosen = candidates[0][1]
    assigned[chosen] = assigned.get(chosen, 0) + 1
    return chosen


def timestamp_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def require_scheduler_authority(*, dry_run: bool) -> int:
    if dry_run:
        return 0
    authority = os.environ.get(SCHEDULER_AUTHORITY_ENV, "")
    request_id = os.environ.get(SCHEDULER_REQUEST_ENV, "")
    if authority == SCHEDULER_AUTHORITY_VALUE and request_id:
        return 0
    print(
        "[ERROR] Actual PBS submission is owned by the cluster02 scheduling agent. "
        "Modernization agents may use --dry-run, but qsub requires "
        "{}={} and {}=<request-id>.".format(
            SCHEDULER_AUTHORITY_ENV,
            SCHEDULER_AUTHORITY_VALUE,
            SCHEDULER_REQUEST_ENV,
        ),
        file=sys.stderr,
    )
    return 2


def qsub(
    root: Path,
    args: List[str],
    *,
    dry_run: bool,
) -> str:
    return run(["qsub", *args], cwd=root, dry_run=dry_run, capture=not dry_run).strip()


def join_deps(job_ids: List[str]) -> str:
    return ":".join(job_ids)


def submit_chunk(
    root: Path,
    *,
    dry_run: bool,
    build_job: str,
    common_vars: str,
    level: LevelSpec,
    method: str,
    chunk_id: str,
    seed_offset: int,
    max_seeds: int,
    queue: str,
    ncpus: int,
    allow_overwrite: str,
) -> str:
    pbs = "codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_chunk.pbs"
    job_method = method.replace("_", "")
    log_root = Path(level.log_root) / method
    log_root.mkdir(parents=True, exist_ok=True)
    vars_arg = ",".join(
        [
            common_vars,
            f"TLTM_REF_LEVEL={level.level}",
            f"TLTM_REF_LABEL={level.label}",
            f"TLTM_CONFIG_JSON={level.config}",
            f"TLTM_ROOT_SUBDIR={level.root}",
            f"TLTM_ROOT_LOG_SUBDIR={level.log_root}",
            f"TLTM_METHOD={method}",
            f"TLTM_CHUNK_ID={chunk_id}",
            f"TLTM_SEED_OFFSET={seed_offset}",
            f"TLTM_MAX_SEEDS={max_seeds}",
            f"TLTM_JOBS={max_seeds}",
            f"TLTM_ALLOW_OVERWRITE={allow_overwrite}",
        ]
    )
    return qsub(
        root,
        [
            "-N",
            f"m6{level.level}{job_method}{chunk_id}",
            "-q",
            queue,
            "-l",
            f"select=1:ncpus={ncpus}:mpiprocs={ncpus}:mem=16gb",
            "-l",
            f"walltime={level.walltime}",
            "-o",
            f"{level.log_root}/{method}/chunk_{chunk_id}.pbs.out",
            "-W",
            f"depend=afterok:{build_job}",
            "-v",
            vars_arg,
            pbs,
        ],
        dry_run=dry_run,
    )


def submit_merge(
    root: Path,
    *,
    dry_run: bool,
    common_vars: str,
    level: LevelSpec,
    chunk_jobs: List[str],
    live: Dict[str, Dict[str, object]],
    assigned: Dict[str, int],
    allow_gpu: bool,
    allow_observed_bad: bool,
    excluded_queues: Dict[str, str],
    penalty_overrides: Dict[str, int],
) -> Tuple[str, str]:
    pbs = "codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_merge_level.pbs"
    queue = choose_queue(
        ncpus=1,
        walltime="01:00:00",
        live=live,
        assigned=assigned,
        allow_gpu=allow_gpu,
        allow_observed_bad=allow_observed_bad,
        excluded_queues=excluded_queues,
        penalty_overrides=penalty_overrides,
    )
    (Path(level.log_root) / "merge").mkdir(parents=True, exist_ok=True)
    vars_arg = ",".join(
        [
            common_vars,
            f"TLTM_REF_LEVEL={level.level}",
            f"TLTM_REF_LABEL={level.label}",
            f"TLTM_CONFIG_JSON={level.config}",
            f"TLTM_ROOT_SUBDIR={level.root}",
            f"TLTM_ROOT_LOG_SUBDIR={level.log_root}",
            f"TLTM_EXPECTED_ROWS_PER_METHOD={level.expected_rows}",
            f"TLTM_REQUESTED_CPUS={level.requested_cpus}",
            f"TLTM_CHUNKS_LABEL={level.level}_parallel_chunks",
        ]
    )
    job = qsub(
        root,
        [
            "-N",
            f"m6{level.level}merge",
            "-q",
            queue,
            "-l",
            "select=1:ncpus=1:mpiprocs=1:mem=4gb",
            "-l",
            "walltime=01:00:00",
            "-o",
            f"{level.log_root}/merge/merge.pbs.out",
            "-W",
            f"depend=afterok:{join_deps(chunk_jobs)}",
            "-v",
            vars_arg,
            pbs,
        ],
        dry_run=dry_run,
    )
    return job, queue


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Submit M6 reference datasets with dynamic manual-aware PBS queue selection.",
    )
    parser.add_argument("--dry-run", action="store_true", help="print qsub commands without submitting")
    parser.add_argument(
        "--levels",
        nargs="+",
        choices=[level.level for level in LEVELS],
        help="reference levels to submit; defaults to all levels",
    )
    parser.add_argument("--queue-snapshot", help="path to saved qstat -Qf output for deterministic dry-runs")
    parser.add_argument(
        "--knowledge",
        help="scheduler knowledge JSON path; defaults to codex/workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_KNOWLEDGE.json",
    )
    parser.add_argument("--allow-gpu", action="store_true", help="allow GPU queues; disabled by default")
    parser.add_argument(
        "--allow-observed-bad-queues",
        action="store_true",
        help="allow queues with observed production-shape Exit_status=127 failures",
    )
    args = parser.parse_args()

    root = repo_root()
    if Path.cwd().resolve() != root:
        print("[ERROR] run from repository root", file=sys.stderr)
        return 2
    if not args.dry_run and shutil_which("qsub") is None:
        print("[ERROR] qsub not found. Re-run on the PBS cluster or use --dry-run.", file=sys.stderr)
        return 2
    authority_error = require_scheduler_authority(dry_run=args.dry_run)
    if authority_error:
        return authority_error
    if not args.dry_run:
        status = git_value(root, "status", "--porcelain")
        if status:
            print("[ERROR] working tree is dirty; commit or stash before submitting reference datasets", file=sys.stderr)
            print(status, file=sys.stderr)
            return 2

    tltm_worktree = os.environ.get("TLTM_WORKTREE", str(root))
    expected_branch = os.environ.get("TLTM_EXPECTED_GIT_BRANCH", git_value(root, "rev-parse", "--abbrev-ref", "HEAD"))
    expected_commit = os.environ.get("TLTM_EXPECTED_GIT_COMMIT", git_value(root, "rev-parse", "HEAD"))
    run_guardrails = os.environ.get("TLTM_RUN_GUARDRAILS", "1")
    allow_overwrite = os.environ.get("TLTM_ALLOW_OVERWRITE", "0")
    common_vars = ",".join(
        [
            f"TLTM_WORKTREE={tltm_worktree}",
            f"TLTM_EXPECTED_GIT_BRANCH={expected_branch}",
            f"TLTM_EXPECTED_GIT_COMMIT={expected_commit}",
        ]
    )

    knowledge = load_scheduler_knowledge(root, args.knowledge)
    excluded_queues = policy_excluded_queues(knowledge)
    penalty_overrides = queue_penalty_overrides(knowledge)
    live = load_queue_snapshot(root, dry_run=args.dry_run, snapshot_file=args.queue_snapshot)
    assigned: Dict[str, int] = {}
    submit_log_dir = Path("output/logs/fortran_modernization/reference_datasets/submit")
    submit_log_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%dT%H%M%S")
    manifest = submit_log_dir / f"submit_manifest_dynamic_{stamp}.env"
    plan_json = submit_log_dir / f"submit_queue_plan_dynamic_{stamp}.json"

    build_queue = choose_queue(
        ncpus=16,
        walltime="02:00:00",
        live=live,
        assigned=assigned,
        allow_gpu=args.allow_gpu,
        allow_observed_bad=args.allow_observed_bad_queues,
        excluded_queues=excluded_queues,
        penalty_overrides=penalty_overrides,
    )
    build_vars = ",".join([common_vars, f"TLTM_RUN_GUARDRAILS={run_guardrails}", "TLTM_BUILD_JOBS=16"])
    build_job = qsub(
        root,
        [
            "-N",
            "m6refbuild",
            "-q",
            build_queue,
            "-l",
            "select=1:ncpus=16:mpiprocs=16:mem=16gb",
            "-l",
            "walltime=02:00:00",
            "-o",
            f"{submit_log_dir}/m6_reference_preflight_build.pbs.out",
            "-v",
            build_vars,
            "codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_preflight_build.pbs",
        ],
        dry_run=args.dry_run,
    )

    manifest_lines = [
        f"submitted_at={timestamp_utc()}",
        f"dry_run={int(args.dry_run)}",
        "launcher=submit_m6_reference_dynamic.py",
        f"worktree={tltm_worktree}",
        f"expected_branch={expected_branch}",
        f"expected_commit={expected_commit}",
        f"scheduler_authority={os.environ.get(SCHEDULER_AUTHORITY_ENV, 'dry_run')}",
        f"scheduler_request_id={os.environ.get(SCHEDULER_REQUEST_ENV, 'dry_run')}",
        f"run_guardrails={run_guardrails}",
        f"allow_overwrite={allow_overwrite}",
        f"build_queue={build_queue}",
        f"build_job={build_job}",
    ]
    plan: Dict[str, object] = {
        "submitted_at": timestamp_utc(),
        "dry_run": args.dry_run,
        "manual_source": "ithems_cluster02_users_guide_rev10.0_en.pdf",
        "knowledge_file": args.knowledge or str(DEFAULT_KNOWLEDGE_PATH),
        "scheduler_authority": os.environ.get(SCHEDULER_AUTHORITY_ENV, "dry_run"),
        "scheduler_request_id": os.environ.get(SCHEDULER_REQUEST_ENV, "dry_run"),
        "policy_excluded_queues": excluded_queues,
        "queue_penalty_overrides": penalty_overrides,
        "build": {"job": build_job, "queue": build_queue},
        "levels": {},
    }

    selected_levels = set(args.levels) if args.levels else {level.level for level in LEVELS}

    for level in LEVELS:
        if level.level not in selected_levels:
            continue
        level_plan: List[Dict[str, object]] = []
        chunk_jobs: List[str] = []
        max_seeds = level.seeds_per_chunk
        ncpus = max_seeds
        for idx in range(level.chunks_per_method):
            seed_offset = idx * max_seeds
            chunk_id = f"{idx:02d}"
            for method in ("no_fb", "fb_norefine"):
                queue = choose_queue(
                    ncpus=ncpus,
                    walltime=level.walltime,
                    live=live,
                    assigned=assigned,
                    allow_gpu=args.allow_gpu,
                    allow_observed_bad=args.allow_observed_bad_queues,
                    excluded_queues=excluded_queues,
                    penalty_overrides=penalty_overrides,
                )
                job = submit_chunk(
                    root,
                    dry_run=args.dry_run,
                    build_job=build_job,
                    common_vars=common_vars,
                    level=level,
                    method=method,
                    chunk_id=chunk_id,
                    seed_offset=seed_offset,
                    max_seeds=max_seeds,
                    queue=queue,
                    ncpus=ncpus,
                    allow_overwrite=allow_overwrite,
                )
                chunk_jobs.append(job)
                key_method = "fb_norefine" if method == "fb_norefine" else "no_fb"
                manifest_lines.append(f"{level.level}_{key_method}_chunk_{chunk_id}={job}")
                manifest_lines.append(f"{level.level}_{key_method}_chunk_{chunk_id}_queue={queue}")
                level_plan.append(
                    {
                        "method": method,
                        "chunk_id": chunk_id,
                        "seed_offset": seed_offset,
                        "max_seeds": max_seeds,
                        "ncpus": ncpus,
                        "walltime": level.walltime,
                        "queue": queue,
                        "job": job,
                    }
                )
        merge_job, merge_queue = submit_merge(
            root,
            dry_run=args.dry_run,
            common_vars=common_vars,
            level=level,
            chunk_jobs=chunk_jobs,
            live=live,
            assigned=assigned,
            allow_gpu=args.allow_gpu,
            allow_observed_bad=args.allow_observed_bad_queues,
            excluded_queues=excluded_queues,
            penalty_overrides=penalty_overrides,
        )
        manifest_lines.append(f"{level.level}_merge={merge_job}")
        manifest_lines.append(f"{level.level}_merge_queue={merge_queue}")
        plan["levels"][level.level] = {  # type: ignore[index]
            "label": level.label,
            "chunks": level_plan,
            "merge": {"job": merge_job, "queue": merge_queue},
        }

    manifest.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    plan_json.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"submit_manifest={manifest}")
    print(f"queue_plan={plan_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

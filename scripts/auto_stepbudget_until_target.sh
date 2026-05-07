#!/usr/bin/env bash
set -euo pipefail

# Unattended step-budget runner:
# - monitor/assess a sequence of runs
# - continue launching next configuration until target is met

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

CHAINS="${CHAINS:-24}"
BASE_PARAMS="${BASE_PARAMS:-data/parameters.dat}"
SEED_BASE="${SEED_BASE:-410000001}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-43200}"
CAP_START="${CAP_START:-8500}"
CAP_LIMIT="${CAP_LIMIT:-3000}"
TARGET_RHAT="${TARGET_RHAT:-1.01}"
POLL_SECONDS="${POLL_SECONDS:-60}"

SUMMARY_CSV="${SUMMARY_CSV:-output/multichain_auto/auto_sleep_stepbudget_summary.csv}"
STATUS_TXT="${STATUS_TXT:-output/multichain_auto/auto_sleep_stepbudget_status.txt}"

mkdir -p "$(dirname "${SUMMARY_CSV}")"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

run_completed_target() {
  local run_name="$1"
  local target_samples="$2"
  local summary="output/multichain_auto/${run_name}/summary.json"
  python3 - "${summary}" "${target_samples}" <<'PY'
import json
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
target = int(sys.argv[2])
if not summary_path.exists():
    sys.exit(1)
try:
    data = json.loads(summary_path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(1)
reason = str(data.get("reason", ""))
chains = data.get("chains", [])
if reason != "target_reached" or not isinstance(chains, list) or len(chains) == 0:
    sys.exit(1)
mins = []
for c in chains:
    try:
        mins.append(int(c.get("samples", 0)))
    except Exception:
        mins.append(0)
if min(mins) < target:
    sys.exit(1)
sys.exit(0)
PY
}

run_in_progress() {
  local run_name="$1"
  local pid cmd
  local pids
  pids="$(pgrep -f "${run_name}" || true)"
  if [[ -z "${pids}" ]]; then
    return 1
  fi
  for pid in ${pids}; do
    cmd="$(ps -p "${pid}" -o cmd= 2>/dev/null || true)"
    if [[ "${cmd}" == *"run_multichain_auto.py"* || "${cmd}" == *"evaluate_expectations"* ]]; then
      return 0
    fi
  done
  return 1
}

wait_for_run_finish() {
  local run_name="$1"
  while run_in_progress "${run_name}"; do
    echo "[$(timestamp)] [WAIT] run=${run_name} still running; sleep ${POLL_SECONDS}s"
    sleep "${POLL_SECONDS}"
  done
}

run_and_evaluate() {
  local run_name="$1"
  local soft1="$2"
  local soft2="$3"
  local hard="$4"
  local samples="$5"

  local run_dir="output/multichain_auto/${run_name}"
  local run_log="output/multichain_auto/${run_name}.nohup.log"
  local eval_log="output/multichain_auto/${run_name}.evaluate.log"

  if [[ -d "${run_dir}" ]]; then
    if run_completed_target "${run_name}" "${samples}"; then
      echo "[$(timestamp)] [SKIP] completed run exists: ${run_dir}"
      return 0
    fi
    local stale="${run_dir}_stale_$(date +%Y%m%d_%H%M%S)"
    echo "[$(timestamp)] [WARN] stale/incomplete run exists; moving ${run_dir} -> ${stale}"
    mv "${run_dir}" "${stale}"
    for f in "output/multichain_auto/${run_name}.nohup.log" \
             "output/multichain_auto/${run_name}.evaluate.log" \
             "output/multichain_auto/${run_name}.wrap.nohup.log"; do
      if [[ -f "${f}" ]]; then
        mv "${f}" "${f}.stale.$(date +%Y%m%d_%H%M%S)"
      fi
    done
  fi

  echo "[$(timestamp)] [RUN] ${run_name} soft1=${soft1} soft2=${soft2} hard=${hard} samples=${samples}"
  env OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    QUASI_FINAL_RESORT_BUDGET=0 \
    QN_STEP_BUDGET_SOFT1="${soft1}" \
    QN_STEP_BUDGET_SOFT2="${soft2}" \
    QN_STEP_BUDGET_HARD="${hard}" \
    CONSTRAINT_FAIL_CAPTURE_START_SAMPLE="${CAP_START}" \
    CONSTRAINT_FAIL_CAPTURE_LIMIT="${CAP_LIMIT}" \
    python3 scripts/run_multichain_auto.py \
      --chains "${CHAINS}" \
      --run-name "${run_name}" \
      --seed-base "${SEED_BASE}" \
      --base-parameters "${BASE_PARAMS}" \
      --chain-length "${samples}" \
      --target-samples-per-chain "${samples}" \
      --quasi-fallback on \
      --check-interval "${CHECK_INTERVAL}" \
      --max-wall-seconds "${MAX_WALL_SECONDS}" \
      > "${run_log}" 2>&1

  echo "[$(timestamp)] [EVAL] ${run_name}"
  EVAL_MULTICHAIN_RUN_DIR="${run_dir}" bin/evaluate_expectations > "${eval_log}" 2>&1
}

ensure_evaluate_log() {
  local run_name="$1"
  local run_dir="output/multichain_auto/${run_name}"
  local eval_log="output/multichain_auto/${run_name}.evaluate.log"

  if [[ -f "${eval_log}" ]]; then
    return 0
  fi
  if run_in_progress "${run_name}"; then
    echo "[$(timestamp)] [WAIT] evaluate deferred; run still active: ${run_name}"
    return 1
  fi
  if [[ ! -d "${run_dir}" ]]; then
    echo "[$(timestamp)] [WARN] missing run_dir for evaluate: ${run_dir}"
    return 1
  fi

  echo "[$(timestamp)] [EVAL] evaluate log missing; running evaluate_expectations for ${run_name}"
  EVAL_MULTICHAIN_RUN_DIR="${run_dir}" bin/evaluate_expectations > "${eval_log}" 2>&1
}

assess_run() {
  local run_name="$1"
  local soft1="$2"
  local soft2="$3"
  local hard="$4"
  local samples="$5"

  python3 - "${run_name}" "${soft1}" "${soft2}" "${hard}" "${samples}" "${TARGET_RHAT}" "${SUMMARY_CSV}" <<'PY'
import csv
import math
import re
import statistics
import sys
from datetime import datetime
from pathlib import Path

run_name = sys.argv[1]
soft1 = int(sys.argv[2])
soft2 = int(sys.argv[3])
hard = int(sys.argv[4])
samples = int(sys.argv[5])
target_rhat = float(sys.argv[6])
summary_csv = Path(sys.argv[7])

run_dir = Path("output/multichain_auto") / run_name
eval_log = Path("output/multichain_auto") / f"{run_name}.evaluate.log"

if not eval_log.exists():
    print(f"[ASSESS] {run_name} evaluate log missing: {eval_log}")
    sys.exit(2)

txt = eval_log.read_text(encoding="utf-8", errors="replace")

def grab(pattern: str, name: str) -> tuple[float, float]:
    m = re.search(pattern, txt)
    if not m:
        raise RuntimeError(f"missing {name}")
    return float(m.group(1)), float(m.group(2))

try:
    virial_re, virial_im = grab(r"\[RESULT\] <virial> \(Re, Im\)=\s*([0-9.E+\-]+)\s*([0-9.E+\-]+)", "<virial>")
    z_re, z_im = grab(r"\[RESULT\] <z> \(Re, Im\)=\s*([0-9.E+\-]+)\s*([0-9.E+\-]+)", "<z>")
    rhat_v_re, rhat_v_im = grab(r"\[RESULT\] split_rhat_virial \(Re, Im\)=\s*([0-9.]+)\s*([0-9.]+)", "rhat_virial")
    rhat_z_re, rhat_z_im = grab(r"\[RESULT\] split_rhat_z \(Re, Im\)=\s*([0-9.]+)\s*([0-9.]+)", "rhat_z")
    err_v_re, err_v_im = grab(r"\[RESULT\] error_robust_<virial> \(Re, Im\)=\s*([0-9.E+\-]+)\s*([0-9.E+\-]+)", "err_virial")
    err_z_re, err_z_im = grab(r"\[RESULT\] error_robust_<z> \(Re, Im\)=\s*([0-9.E+\-]+)\s*([0-9.E+\-]+)", "err_z")
except Exception as exc:
    print(f"[ASSESS] {run_name} parse error: {exc}")
    sys.exit(2)

near_pat = re.compile(r"near_fail=(\d+)\s+near_try=(\d+)\s+near_ok=(\d+)\s+near_unusable=(\d+)\s+far_fail=(\d+)")
prog_pat = re.compile(r"\[PROGRESS\]\s+(\d+)/(\d+).*elapsed=\s*([0-9.]+)s")

near_fail_total = 0
near_try_total = 0
near_ok_total = 0
near_unusable_total = 0
far_fail_total = 0
elapsed = []

for log in sorted(run_dir.glob("chain_*/logs/generate_markov_chain.log")):
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    last_near = None
    last_elapsed = None
    for line in reversed(lines):
        if last_near is None:
            m = near_pat.search(line)
            if m:
                last_near = tuple(int(m.group(i)) for i in range(1, 6))
        if last_elapsed is None:
            m = prog_pat.search(line)
            if m:
                last_elapsed = float(m.group(3))
        if last_near is not None and last_elapsed is not None:
            break
    if last_near is not None:
        near_fail_total += last_near[0]
        near_try_total += last_near[1]
        near_ok_total += last_near[2]
        near_unusable_total += last_near[3]
        far_fail_total += last_near[4]
    if last_elapsed is not None:
        elapsed.append(last_elapsed)

if elapsed:
    elapsed_sorted = sorted(elapsed)
    elapsed_min = elapsed_sorted[0]
    elapsed_med = statistics.median(elapsed_sorted)
    p95_idx = max(0, math.ceil(0.95 * len(elapsed_sorted)) - 1)
    elapsed_p95 = elapsed_sorted[p95_idx]
    elapsed_max = elapsed_sorted[-1]
else:
    elapsed_min = float("nan")
    elapsed_med = float("nan")
    elapsed_p95 = float("nan")
    elapsed_max = float("nan")

pass_rhat = (
    rhat_v_re <= target_rhat and rhat_v_im <= target_rhat and
    rhat_z_re <= target_rhat and rhat_z_im <= target_rhat
)
pass_virial_re = abs(virial_re) <= err_v_re
pass_virial_im = abs(virial_im) <= err_v_im
pass_z_re = abs(z_re) <= err_z_re
pass_z_im = abs(z_im + 1.0) <= err_z_im
pass_consistency = pass_virial_re and pass_virial_im and pass_z_re and pass_z_im
pass_near = (near_fail_total == 0)
pass_all = pass_rhat and pass_consistency and pass_near

summary_csv.parent.mkdir(parents=True, exist_ok=True)
new_file = not summary_csv.exists()
with summary_csv.open("a", newline="", encoding="utf-8") as fobj:
    writer = csv.writer(fobj)
    if new_file:
        writer.writerow([
            "timestamp", "run", "samples", "soft1", "soft2", "hard",
            "rhat_v_re", "rhat_v_im", "rhat_z_re", "rhat_z_im",
            "virial_re", "virial_im", "z_re", "z_im",
            "err_v_re", "err_v_im", "err_z_re", "err_z_im",
            "near_fail_total", "near_try_total", "near_ok_total", "near_unusable_total", "far_fail_total",
            "elapsed_min", "elapsed_med", "elapsed_p95", "elapsed_max",
            "pass_virial_re", "pass_virial_im", "pass_z_re", "pass_z_im",
            "pass_rhat", "pass_consistency", "pass_near", "pass_all",
        ])
    writer.writerow([
        datetime.now().isoformat(timespec="seconds"),
        run_name, samples, soft1, soft2, hard,
        rhat_v_re, rhat_v_im, rhat_z_re, rhat_z_im,
        virial_re, virial_im, z_re, z_im,
        err_v_re, err_v_im, err_z_re, err_z_im,
        near_fail_total, near_try_total, near_ok_total, near_unusable_total, far_fail_total,
        elapsed_min, elapsed_med, elapsed_p95, elapsed_max,
        int(pass_virial_re), int(pass_virial_im), int(pass_z_re), int(pass_z_im),
        int(pass_rhat), int(pass_consistency), int(pass_near), int(pass_all),
    ])

print(
    f"[ASSESS] run={run_name} "
    f"pass_all={int(pass_all)} pass_rhat={int(pass_rhat)} pass_consistency={int(pass_consistency)} pass_near={int(pass_near)} "
    f"cons_parts=(vir_re:{int(pass_virial_re)},vir_im:{int(pass_virial_im)},z_re:{int(pass_z_re)},z_im:{int(pass_z_im)}) "
    f"rhat_z=({rhat_z_re:.4f},{rhat_z_im:.4f}) z_im={z_im:.6f} err_z_im={err_z_im:.6f} "
    f"near_fail={near_fail_total} elapsed_max={elapsed_max:.2f}"
)

sys.exit(0 if pass_all else 1)
PY
}

# Ordered plan:
# - first entry is currently running p05 (monitor only)
# - then continue with increasingly conservative soft-gate settings
# - if still not meeting target, try longer chains on best middle settings
CONFIGS=(
  "s20l2t05_stepbudget50k_softrelax_p05_withfb|900|3000|7000|50000|monitor"
  "s20l2t05_sleepauto_p06_withfb|850|2800|6800|50000|run"
  "s20l2t05_sleepauto_p07_withfb|800|2600|6500|50000|run"
  "s20l2t05_sleepauto_p08_withfb|750|2400|6000|50000|run"
  "s20l2t05_sleepauto_p09_withfb|700|2200|5500|50000|run"
  "s20l2t05_sleepauto_p10_withfb|800|2600|6500|70000|run"
  "s20l2t05_sleepauto_p11_withfb|850|2800|6800|100000|run"
)

echo "[$(timestamp)] [AUTO] started; target_rhat<=${TARGET_RHAT}; summary=${SUMMARY_CSV}"
echo "[$(timestamp)] [AUTO] pass criteria: rhat(all components)<=${TARGET_RHAT}, robust-1sigma consistency, near_fail_total==0"

for cfg in "${CONFIGS[@]}"; do
  IFS='|' read -r run_name soft1 soft2 hard samples mode <<< "${cfg}"

  echo "[$(timestamp)] [AUTO] candidate run=${run_name} mode=${mode} soft1=${soft1} soft2=${soft2} hard=${hard} samples=${samples}"

  if [[ "${mode}" == "monitor" ]]; then
    wait_for_run_finish "${run_name}"
    ensure_evaluate_log "${run_name}" || true
  else
    if run_in_progress "${run_name}"; then
      wait_for_run_finish "${run_name}"
      ensure_evaluate_log "${run_name}" || true
    elif [[ -d "output/multichain_auto/${run_name}" ]]; then
      if run_completed_target "${run_name}" "${samples}"; then
        ensure_evaluate_log "${run_name}" || true
      else
        echo "[$(timestamp)] [WARN] existing run is incomplete; rerunning ${run_name}"
        run_and_evaluate "${run_name}" "${soft1}" "${soft2}" "${hard}" "${samples}"
      fi
    else
      run_and_evaluate "${run_name}" "${soft1}" "${soft2}" "${hard}" "${samples}"
    fi
  fi

  if assess_run "${run_name}" "${soft1}" "${soft2}" "${hard}" "${samples}"; then
    {
      echo "timestamp=$(timestamp)"
      echo "status=PASS"
      echo "run=${run_name}"
      echo "summary_csv=${SUMMARY_CSV}"
    } > "${STATUS_TXT}"
    echo "[$(timestamp)] [AUTO] PASS at run=${run_name}; stop."
    exit 0
  fi

  echo "[$(timestamp)] [AUTO] run=${run_name} not yet passing; continue."
done

{
  echo "timestamp=$(timestamp)"
  echo "status=EXHAUSTED"
  echo "run=none"
  echo "summary_csv=${SUMMARY_CSV}"
} > "${STATUS_TXT}"

echo "[$(timestamp)] [AUTO] exhausted configured candidates without PASS."
exit 2

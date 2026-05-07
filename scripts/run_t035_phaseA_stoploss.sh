#!/usr/bin/env bash
set -euo pipefail

# Phase A: t=0.35, ctrl-structure pilot (3 seeds x 10k) with stop-loss summary.
# Usage:
#   ROOT=output/multichain_auto_t035_stoploss_XXXX scripts/run_t035_phaseA_stoploss.sh

ROOT="${ROOT:-output/multichain_auto_t035_stoploss_$(date +%m%d_%H%M%S)}"
CHAINS="${CHAINS:-24}"
SAMPLES="${SAMPLES:-10000}"
BASE_PARAMETERS="${BASE_PARAMETERS:-data/parameters_t035.dat}"
SEED_START="${SEED_START:-410000001}"
SEED_STEP="${SEED_STEP:-104729}"
RHAT_GATE="${RHAT_GATE:-1.015}"
NEAR_UNUSABLE_MAX="${NEAR_UNUSABLE_MAX:-0}"
RUN_PREFIX="${RUN_PREFIX:-s20l2_t035_ctrlA}"

mkdir -p "${ROOT}"
CSV="${ROOT}/phaseA_summary.csv"
DEC="${ROOT}/phaseA_decision.txt"

echo "run,seed,elapsed_s,rhat_z_re,rhat_z_im,rhat_virial_re,rhat_virial_im,near_fail,near_unusable,far_fail,pass_gate" > "${CSV}"

for i in 1 2 3; do
  seed=$((SEED_START + (i - 1) * SEED_STEP))
  run=$(printf "%s_p%02d_%s_withfb" "${RUN_PREFIX}" "${i}" "${SAMPLES}")
  run_dir="output/multichain_auto/${run}"
  run_log="${ROOT}/${run}.nohup.log"
  eval_log="${ROOT}/${run}.evaluate.log"

  echo "[RUN] ${run} seed=${seed}" | tee -a "${DEC}"
  env OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    QN_FAR_ANCHOR_FASTTRACK=0 \
    QN_FAR_ANCHOR_MIX_RESTART=0 \
    QN_NEAR_SEEDED_NEWTON=1 \
    QN_NEAR_UNSOLVABLE_FAIL_FAST=1 \
    QN_FAR_FAIL_FAST=1 \
    python3 scripts/run_multichain_auto.py \
      --chains "${CHAINS}" \
      --run-name "${run}" \
      --force \
      --seed-base "${seed}" \
      --base-parameters "${BASE_PARAMETERS}" \
      --chain-length "${SAMPLES}" \
      --target-samples-per-chain "${SAMPLES}" \
      --check-interval 10 \
      --max-wall-seconds 43200 \
      --quasi-fallback on \
      > "${run_log}" 2>&1
  echo "[DONE] ${run}" | tee -a "${DEC}"

  EVAL_MULTICHAIN_RUN_DIR="${run_dir}" EVAL_MULTICHAIN_DIAG_WINDOW="${SAMPLES}" \
    bin/evaluate_expectations > "${eval_log}" 2>&1

  elapsed=$(jq -r '.elapsed_seconds' "${run_dir}/summary.json")
  rz_re=$(rg "\[RESULT\] split_rhat_z" "${eval_log}" | sed -E "s/.*= *([^ ]+) *([^ ]+)$/\\1/")
  rz_im=$(rg "\[RESULT\] split_rhat_z" "${eval_log}" | sed -E "s/.*= *([^ ]+) *([^ ]+)$/\\2/")
  rv_re=$(rg "\[RESULT\] split_rhat_virial" "${eval_log}" | sed -E "s/.*= *([^ ]+) *([^ ]+)$/\\1/")
  rv_im=$(rg "\[RESULT\] split_rhat_virial" "${eval_log}" | sed -E "s/.*= *([^ ]+) *([^ ]+)$/\\2/")

  read -r near_fail near_unusable far_fail < <(
    awk '
      /near_fail=/ {
        nf=nu=ff=0;
        for(i=1;i<=NF;i++){
          if($i ~ /^near_fail=/){split($i,a,"="); nf=a[2]}
          else if($i ~ /^near_unusable=/){split($i,a,"="); nu=a[2]}
          else if($i ~ /^far_fail=/){split($i,a,"="); ff=a[2]}
        }
        last_nf=nf; last_nu=nu; last_ff=ff;
      }
      ENDFILE {
        sum_nf += last_nf+0; sum_nu += last_nu+0; sum_ff += last_ff+0;
        last_nf=last_nu=last_ff=0
      }
      END {print sum_nf, sum_nu, sum_ff}
    ' "${run_dir}"/chain_*/logs/generate_markov_chain.log
  )

  pass_gate=$(awk -v r="${rz_re}" -v nf="${near_fail}" -v nu="${near_unusable}" -v nu_max="${NEAR_UNUSABLE_MAX}" -v rg="${RHAT_GATE}" \
    'BEGIN{if((r+0)<=rg && (nf+0)==0 && (nu+0)<=nu_max) print "1"; else print "0"}')

  printf "%s,%d,%.3f,%s,%s,%s,%s,%d,%d,%d,%s\n" \
    "${run}" "${seed}" "${elapsed}" "${rz_re}" "${rz_im}" "${rv_re}" "${rv_im}" \
    "${near_fail}" "${near_unusable}" "${far_fail}" "${pass_gate}" >> "${CSV}"
done

python3 - "${CSV}" "${RHAT_GATE}" "${NEAR_UNUSABLE_MAX}" << 'PY'
import csv
import statistics
import sys

rows = list(csv.DictReader(open(sys.argv[1], "r", encoding="utf-8")))
rg = float(sys.argv[2])
nu_max = int(sys.argv[3])
pass_n = sum(int(r["pass_gate"]) for r in rows)
med_rhat = statistics.median(float(r["rhat_z_re"]) for r in rows)
med_elapsed = statistics.median(float(r["elapsed_s"]) for r in rows)

print(f"gate: rhat_z_re<={rg} near_fail=0 near_unusable<={nu_max}")
print(f"phaseA_rows={len(rows)} pass_gate={pass_n}/{len(rows)} median_rhat_z_re={med_rhat:.4f} median_elapsed_s={med_elapsed:.1f}")
if pass_n >= 2:
    print("DECISION: Phase A PASS (go Phase B targeted budget-routing)")
else:
    print("DECISION: Phase A FAIL (stop structural tuning at t=0.35; go longer-chain ctrl or lower-flow-time)")
PY

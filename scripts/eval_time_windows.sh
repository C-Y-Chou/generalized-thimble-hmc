#!/usr/bin/env bash
set -euo pipefail

# Evaluate equal-length (or custom) windows from one completed multichain run.
#
# Example:
#   RUN_DIR=output/multichain_auto/<run_name> \
#   WINDOWS="0:50000 50000:50000 100000:50000 150000:50000" \
#   OUT_ROOT=output/window_eval_<tag> \
#   bash scripts/eval_time_windows.sh
#
# Window syntax: START:LENGTH (0-based START in samples)

RUN_DIR="${RUN_DIR:-}"
if [[ $# -ge 1 ]]; then
  RUN_DIR="$1"
fi
if [[ -z "${RUN_DIR}" ]]; then
  echo "[ERROR] RUN_DIR is required." >&2
  exit 1
fi

WINDOWS="${WINDOWS:-0:50000 50000:50000 100000:50000 150000:50000}"
OUT_ROOT="${OUT_ROOT:-output/window_eval_$(basename "${RUN_DIR}")_$(date +%m%d_%H%M%S)}"
EVAL_BIN="${EVAL_BIN:-bin/evaluate_expectations}"
KEEP_TMP="${KEEP_TMP:-0}"

if [[ ! -d "${RUN_DIR}" ]]; then
  echo "[ERROR] RUN_DIR not found: ${RUN_DIR}" >&2
  exit 1
fi
if [[ ! -x "${EVAL_BIN}" ]]; then
  echo "[ERROR] evaluate binary not executable: ${EVAL_BIN}" >&2
  exit 1
fi

mkdir -p "${OUT_ROOT}"
progress_log="${OUT_ROOT}/driver.progress.log"
summary_csv="${OUT_ROOT}/window_summary.csv"

mapfile -t chain_dirs < <(find "${RUN_DIR}" -maxdepth 1 -mindepth 1 -type d -name 'chain_*' | sort)
if [[ ${#chain_dirs[@]} -eq 0 ]]; then
  echo "[ERROR] no chain_* directories under ${RUN_DIR}" | tee -a "${progress_log}" >&2
  exit 1
fi

z_size=""
n_samples_min=""
for chain_dir in "${chain_dirs[@]}"; do
  zf="${chain_dir}/output/z_history.dat"
  pf="${chain_dir}/output/phi_history.dat"

  if [[ ! -f "${zf}" || ! -f "${pf}" ]]; then
    echo "[ERROR] missing history files in ${chain_dir}" | tee -a "${progress_log}" >&2
    exit 1
  fi

  z_bytes=$(stat -c '%s' "${zf}")
  p_bytes=$(stat -c '%s' "${pf}")

  if (( p_bytes <= 0 || p_bytes % 16 != 0 )); then
    echo "[ERROR] invalid phi_history size in ${pf}: ${p_bytes}" | tee -a "${progress_log}" >&2
    exit 1
  fi
  if (( z_bytes <= 0 || z_bytes % 16 != 0 )); then
    echo "[ERROR] invalid z_history size in ${zf}: ${z_bytes}" | tee -a "${progress_log}" >&2
    exit 1
  fi
  if (( z_bytes % p_bytes != 0 )); then
    echo "[ERROR] z/phi size ratio not integer in ${chain_dir}: z=${z_bytes}, phi=${p_bytes}" | tee -a "${progress_log}" >&2
    exit 1
  fi

  this_z_size=$(( z_bytes / p_bytes ))
  if (( this_z_size < 1 )); then
    echo "[ERROR] invalid inferred z_size=${this_z_size} from ${chain_dir}" | tee -a "${progress_log}" >&2
    exit 1
  fi

  if [[ -z "${z_size}" ]]; then
    z_size="${this_z_size}"
  elif [[ "${z_size}" != "${this_z_size}" ]]; then
    echo "[ERROR] inconsistent inferred z_size across chains: ${z_size} vs ${this_z_size}" | tee -a "${progress_log}" >&2
    exit 1
  fi

  this_n_samples=$(( p_bytes / 16 ))
  if [[ -z "${n_samples_min}" || ${this_n_samples} -lt ${n_samples_min} ]]; then
    n_samples_min="${this_n_samples}"
  fi
done

parse_eval_metrics() {
  local eval_log="$1"
  python3 - "$eval_log" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8", errors="replace")

def grab2(pat):
    m = re.search(pat, text)
    if not m:
        return None
    return float(m.group(1)), float(m.group(2))

vir = grab2(r"\[RESULT\]\s+<virial>\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
z = grab2(r"\[RESULT\]\s+<z>\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
err_vir = grab2(r"\[RESULT\]\s+error_robust_<virial>\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
err_z = grab2(r"\[RESULT\]\s+error_robust_<z>\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
rhat_vir = grab2(r"\[RESULT\]\s+split_rhat_virial\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
rhat_z = grab2(r"\[RESULT\]\s+split_rhat_z\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
ess_v = grab2(r"\[RESULT\]\s+ess_bulk_virial\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")
ess_z = grab2(r"\[RESULT\]\s+ess_bulk_z\s+\(Re, Im\)=\s*([\-+0-9Ee\.]+)\s+([\-+0-9Ee\.]+)")

if None in (vir, z, err_vir, err_z, rhat_vir, rhat_z, ess_v, ess_z):
    print(",".join(["NA"] * 23))
    raise SystemExit(0)

vir_re, vir_im = vir
z_re, z_im = z
err_v_re, err_v_im = err_vir
err_z_re, err_z_im = err_z
rhat_v_re, rhat_v_im = rhat_vir
rhat_z_re, rhat_z_im = rhat_z
ess_v_re, ess_v_im = ess_v
ess_z_re, ess_z_im = ess_z

dev_v_re = abs(vir_re) / err_v_re if err_v_re > 0 else float("nan")
dev_v_im = abs(vir_im) / err_v_im if err_v_im > 0 else float("nan")
dev_z_re = abs(z_re) / err_z_re if err_z_re > 0 else float("nan")
z_im_bias = z_im + 1.0
dev_z_im = abs(z_im_bias) / err_z_im if err_z_im > 0 else float("nan")
dmax = max(dev_v_re, dev_v_im, dev_z_re, dev_z_im)

vals = [
    rhat_z_re, rhat_z_im, rhat_v_re, rhat_v_im,
    ess_v_re, ess_v_im, ess_z_re, ess_z_im,
    vir_re, vir_im, z_re, z_im,
    err_v_re, err_v_im, err_z_re, err_z_im,
    dev_v_re, dev_v_im, dev_z_re, dev_z_im, dmax,
    z_im_bias, (z_im_bias / err_z_im if err_z_im > 0 else float("nan")),
]
print(",".join(f"{v:.10g}" for v in vals))
PY
}

parse_fail_counters() {
  local run_dir="$1"
  if ! ls "${run_dir}"/chain_*/logs/generate_markov_chain.log >/dev/null 2>&1; then
    echo "NA,NA,NA"
    return 0
  fi

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
    END {printf "%s,%s,%s\n", sum_nf, sum_nu, sum_ff}
  ' "${run_dir}"/chain_*/logs/generate_markov_chain.log
}

run_name=$(basename "${RUN_DIR}")
fail_vals="$(parse_fail_counters "${RUN_DIR}")"

echo "window_id,start,length,status,run_name,source_run_dir,window_run_dir,eval_log,n_samples_min,z_size,rhat_z_re,rhat_z_im,rhat_virial_re,rhat_virial_im,ess_bulk_virial_re,ess_bulk_virial_im,ess_bulk_z_re,ess_bulk_z_im,virial_re,virial_im,z_re,z_im,err_virial_re,err_virial_im,err_z_re,err_z_im,dev_sigma_vir_re,dev_sigma_vir_im,dev_sigma_z_re,dev_sigma_z_im,Dmax,z_im_bias,z_im_bias_over_err,near_fail,near_unusable,far_fail" > "${summary_csv}"

echo "[INIT] RUN_DIR=${RUN_DIR}" | tee -a "${progress_log}"
echo "[INIT] chains=${#chain_dirs[@]} n_samples_min=${n_samples_min} z_size=${z_size}" | tee -a "${progress_log}"
echo "[INIT] WINDOWS=${WINDOWS}" | tee -a "${progress_log}"

wid=0
for win in ${WINDOWS}; do
  wid=$((wid + 1))

  if [[ "${win}" != *:* ]]; then
    echo "[SKIP] invalid window=${win}" | tee -a "${progress_log}"
    continue
  fi
  start="${win%%:*}"
  length="${win##*:}"

  if ! [[ "${start}" =~ ^[0-9]+$ && "${length}" =~ ^[0-9]+$ ]]; then
    echo "[SKIP] invalid numeric window=${win}" | tee -a "${progress_log}"
    continue
  fi
  if (( length <= 0 )); then
    echo "[SKIP] non-positive length window=${win}" | tee -a "${progress_log}"
    continue
  fi
  end=$(( start + length ))
  if (( end > n_samples_min )); then
    echo "[SKIP] window out of range ${win} n_samples_min=${n_samples_min}" | tee -a "${progress_log}"
    echo "${wid},${start},${length},skip_out_of_range,${run_name},${RUN_DIR},NA,NA,${n_samples_min},${z_size},NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,${fail_vals}" >> "${summary_csv}"
    continue
  fi

  window_run_dir="${OUT_ROOT}/window_${wid}_s${start}_l${length}"
  rm -rf "${window_run_dir}"
  mkdir -p "${window_run_dir}"

  z_skip=$(( start * 16 * z_size ))
  z_take=$(( length * 16 * z_size ))
  p_skip=$(( start * 16 ))
  p_take=$(( length * 16 ))

  echo "[RUN] window_id=${wid} start=${start} len=${length}" | tee -a "${progress_log}"

  for chain_dir in "${chain_dirs[@]}"; do
    chain_name=$(basename "${chain_dir}")
    src_out="${chain_dir}/output"
    dst_out="${window_run_dir}/${chain_name}/output"
    mkdir -p "${dst_out}"

    dd if="${src_out}/z_history.dat" of="${dst_out}/z_history.dat" bs=1 skip="${z_skip}" count="${z_take}" status=none
    dd if="${src_out}/phi_history.dat" of="${dst_out}/phi_history.dat" bs=1 skip="${p_skip}" count="${p_take}" status=none
  done

  eval_log="${OUT_ROOT}/window_${wid}_s${start}_l${length}.evaluate.log"
  if EVAL_MULTICHAIN_RUN_DIR="${window_run_dir}" EVAL_MULTICHAIN_DIAG_WINDOW="${length}" "${EVAL_BIN}" > "${eval_log}" 2>&1; then
    status="done"
    eval_vals="$(parse_eval_metrics "${eval_log}")"
  else
    status="eval_failed"
    eval_vals="NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA"
  fi

  echo "${wid},${start},${length},${status},${run_name},${RUN_DIR},${window_run_dir},${eval_log},${n_samples_min},${z_size},${eval_vals},${fail_vals}" >> "${summary_csv}"

  echo "[DONE] window_id=${wid} status=${status}" | tee -a "${progress_log}"

  if [[ "${KEEP_TMP}" != "1" ]]; then
    rm -rf "${window_run_dir}"
  fi
done

echo "[ALL DONE] summary=${summary_csv}" | tee -a "${progress_log}"

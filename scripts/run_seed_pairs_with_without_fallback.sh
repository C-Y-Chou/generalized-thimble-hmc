#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run paired multichain experiments with identical seeds (with/without quasi fallback).

Usage:
  scripts/run_seed_pairs_with_without_fallback.sh [options]

Options:
  --pairs N                 Number of seed pairs (default: 10)
  --chains N                Chains per run (default: 24)
  --samples N               chain_length and target_samples_per_chain (default: 50000)
  --seed-start N            Seed base for pair 1 (default: 410000001)
  --seed-step N             Step between pair seed bases (default: 1000003)
  --prefix NAME             Run name prefix (default: s40l2t04_pair10)
  --output-root PATH        Output root for run_multichain_auto (default: output/multichain_auto)
  --base-parameters PATH    Base parameters.dat (default: data/parameters.dat)
  --bin PATH                generate_markov_chain binary (default: bin/generate_markov_chain)
  --evaluate-bin PATH       evaluate_expectations binary (default: bin/evaluate_expectations)
  --check-interval N        run_multichain_auto --check-interval (default: 10)
  --max-wall-seconds N      run_multichain_auto --max-wall-seconds (default: 43200)
  --force                   Remove existing run directory if present
  --dry-run                 Print commands only
  -h, --help               Show this help
EOF
}

pairs=10
chains=24
samples=50000
seed_start=410000001
seed_step=1000003
prefix="s40l2t04_pair10"
output_root="output/multichain_auto"
base_parameters="data/parameters.dat"
bin_path="bin/generate_markov_chain"
evaluate_bin="bin/evaluate_expectations"
check_interval=10
max_wall_seconds=43200
force=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pairs) pairs="$2"; shift 2 ;;
    --chains) chains="$2"; shift 2 ;;
    --samples) samples="$2"; shift 2 ;;
    --seed-start) seed_start="$2"; shift 2 ;;
    --seed-step) seed_step="$2"; shift 2 ;;
    --prefix) prefix="$2"; shift 2 ;;
    --output-root) output_root="$2"; shift 2 ;;
    --base-parameters) base_parameters="$2"; shift 2 ;;
    --bin) bin_path="$2"; shift 2 ;;
    --evaluate-bin) evaluate_bin="$2"; shift 2 ;;
    --check-interval) check_interval="$2"; shift 2 ;;
    --max-wall-seconds) max_wall_seconds="$2"; shift 2 ;;
    --force) force=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ ! -f "$base_parameters" ]]; then
  echo "[ERROR] Missing base parameters file: $base_parameters" >&2
  exit 2
fi
if [[ ! -x "$bin_path" ]]; then
  echo "[ERROR] Missing executable binary: $bin_path" >&2
  exit 2
fi
if [[ ! -x "$evaluate_bin" ]]; then
  echo "[ERROR] Missing executable evaluator: $evaluate_bin" >&2
  exit 2
fi

mkdir -p "$output_root"
manifest="$output_root/${prefix}_seed_manifest.csv"
if [[ ! -f "$manifest" || "$force" -eq 1 ]]; then
  echo "pair_idx,seed_base,mode,run_name,status,log_file,eval_log_file" > "$manifest"
fi

run_eval() {
  local run_name="$1"
  local run_dir="$2"
  local eval_log="$3"
  local status

  if [[ ! -d "$run_dir" ]]; then
    echo "[ERROR] Cannot evaluate missing run dir: ${run_dir}" >&2
    return 2
  fi

  echo "[EVAL] run=${run_name}"
  set +e
  env EVAL_MULTICHAIN_RUN_DIR="$run_dir" "$evaluate_bin" > "$eval_log" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "[EVAL DONE] ${run_name}"
    return 0
  fi

  echo "[ERROR] Evaluation failed for ${run_name} status=${status}. See ${eval_log}" >&2
  return "$status"
}

run_one() {
  local pair_idx="$1"
  local mode="$2"
  local seed_base="$3"
  local mode_tag fallback_mode run_name run_dir log_file eval_log status

  case "$mode" in
    nofb)
      mode_tag="nofb"
      fallback_mode="off"
      ;;
    withfb)
      mode_tag="withfb"
      fallback_mode="on"
      ;;
    *)
      echo "[ERROR] Invalid mode: $mode" >&2
      return 2
      ;;
  esac

  run_name="${prefix}_p$(printf '%02d' "$pair_idx")_${mode_tag}"
  run_dir="${output_root}/${run_name}"
  log_file="${output_root}/${run_name}.nohup.log"
  eval_log="${output_root}/${run_name}.evaluate.log"

  if [[ -f "${run_dir}/summary.json" ]]; then
    echo "[SKIP] ${run_name} already completed. Running evaluator."
    if [[ "$dry_run" -eq 1 ]]; then
      echo "[DRY] env EVAL_MULTICHAIN_RUN_DIR=${run_dir} ${evaluate_bin} > ${eval_log} 2>&1"
      echo "${pair_idx},${seed_base},${mode_tag},${run_name},skipped_completed_dry_eval,${log_file},${eval_log}" >> "$manifest"
      return 0
    fi
    run_eval "$run_name" "$run_dir" "$eval_log"
    echo "${pair_idx},${seed_base},${mode_tag},${run_name},skipped_completed_eval_done,${log_file},${eval_log}" >> "$manifest"
    return 0
  fi

  if [[ -d "$run_dir" ]]; then
    if [[ "$force" -eq 1 ]]; then
      echo "[INFO] Removing existing run dir: ${run_dir}"
      rm -rf "$run_dir"
    else
      echo "[SKIP] ${run_name} exists without summary.json (use --force to overwrite)."
      echo "${pair_idx},${seed_base},${mode_tag},${run_name},skipped_existing_dir,${log_file},${eval_log}" >> "$manifest"
      return 0
    fi
  fi

  cmd=(
    env OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
    python3 -u scripts/run_multichain_auto.py
    --chains "$chains"
    --bin "$bin_path"
    --base-parameters "$base_parameters"
    --output-root "$output_root"
    --run-name "$run_name"
    --seed-base "$seed_base"
    --chain-length "$samples"
    --quasi-fallback "$fallback_mode"
    --target-samples-per-chain "$samples"
    --check-interval "$check_interval"
    --max-wall-seconds "$max_wall_seconds"
  )

  echo "[RUN] pair=${pair_idx} mode=${mode_tag} seed_base=${seed_base} run=${run_name}"
  if [[ "$dry_run" -eq 1 ]]; then
    printf '[DRY] '
    printf '%q ' "${cmd[@]}"
    printf '\n'
    echo "[DRY] env EVAL_MULTICHAIN_RUN_DIR=${run_dir} ${evaluate_bin} > ${eval_log} 2>&1"
    echo "${pair_idx},${seed_base},${mode_tag},${run_name},dry_run,${log_file},${eval_log}" >> "$manifest"
    return 0
  fi

  set +e
  "${cmd[@]}" > "$log_file" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "[DONE] ${run_name}"
    if run_eval "$run_name" "$run_dir" "$eval_log"; then
      echo "${pair_idx},${seed_base},${mode_tag},${run_name},done_eval_done,${log_file},${eval_log}" >> "$manifest"
      return 0
    fi
    status=$?
    echo "${pair_idx},${seed_base},${mode_tag},${run_name},done_eval_failed_${status},${log_file},${eval_log}" >> "$manifest"
    return "$status"
  fi

  echo "[ERROR] ${run_name} failed with status=${status}. See ${log_file}" >&2
  echo "${pair_idx},${seed_base},${mode_tag},${run_name},failed_${status},${log_file},${eval_log}" >> "$manifest"
  return "$status"
}

echo "[INFO] pairs=${pairs} chains=${chains} samples=${samples}"
echo "[INFO] seed_start=${seed_start} seed_step=${seed_step}"
echo "[INFO] output_root=${output_root}"
echo "[INFO] manifest=${manifest}"

for ((i=1; i<=pairs; i++)); do
  seed_base=$((seed_start + (i - 1) * seed_step))
  # Alternate order by pair index to reduce time-drift bias.
  if (( i % 2 == 1 )); then
    run_one "$i" nofb "$seed_base"
    run_one "$i" withfb "$seed_base"
  else
    run_one "$i" withfb "$seed_base"
    run_one "$i" nofb "$seed_base"
  fi
done

echo "[ALL DONE] Completed paired runs. Manifest: ${manifest}"

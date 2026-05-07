#!/usr/bin/env bash
set -euo pipefail

RUNS="${1:-5}"
if ! [[ "${RUNS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 [runs>=1]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
BIN_PATH="${ROOT_DIR}/bin/test_program"

BENCH_WORK_DIR="${BUILD_DIR}/bench"
BENCH_DATA_DIR="${BUILD_DIR}/data"
BENCH_LOG_DIR="${BENCH_WORK_DIR}/logs"
BENCH_OUT_DIR="${BENCH_WORK_DIR}/output"
SUMMARY_FILE="${BENCH_WORK_DIR}/benchmark_summary.txt"

mkdir -p "${BENCH_WORK_DIR}" "${BENCH_DATA_DIR}" "${BENCH_LOG_DIR}" "${BENCH_OUT_DIR}"

cat > "${BENCH_DATA_DIR}/shift.dat" <<'EOF'
  0.00000000000000000E+00
EOF

cat > "${BENCH_DATA_DIR}/parameters.dat" <<'EOF'
# Runtime flags
istest = true
tra2 = false
eo = false

# Markov chain control
chain_length = 1000000
hmc_repeat = 1
warmup = 0

# Integrator control
trajectory_length = 1.0
integration_steps = 5
initial_flow_time = 0.2
integrator_method = rattle

# State layout
x_size = 2

# Model parameters
alpha = (1.0,0.0)
beta = (1.0,0.0)
derivative_mode = generated

# Solver tolerances
abs_tol = 1.0d-14
rel_tol = 1.0d-14
constraint_tol = 1.0d-13

# Expectation analysis
bootstrap_samples = 0

# Files (paths resolved from build/bench/)
bw_file = ../data/shift.dat
x_history_file = ./output/x_history.dat
z_history_file = ./output/z_history.dat
phi_history_file = ./output/phi_history.dat
EOF

echo "[BENCH] Building test_program..."
(cd "${BUILD_DIR}" && make ../bin/test_program >/dev/null)

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "[ERROR] Missing executable: ${BIN_PATH}"
  exit 1
fi

declare -a elapsed_times
declare -a convergence_orders

echo "[BENCH] Running ${RUNS} repeated trials in ${BENCH_WORK_DIR}"
for run_idx in $(seq 1 "${RUNS}"); do
  run_log="${BENCH_LOG_DIR}/run_${run_idx}.log"
  run_time_log="${BENCH_LOG_DIR}/run_${run_idx}.time"

  (
    cd "${BENCH_WORK_DIR}"
    /usr/bin/time -f "%e" env HMC_SKIP_PLOT=1 "${BIN_PATH}" >"${run_log}" 2>"${run_time_log}"
  )

  elapsed="$(tail -n 1 "${run_time_log}" | tr -d '[:space:]')"
  order="$(rg -N "\\[SUMMARY\\] Estimated convergence order=" "${run_log}" | tail -n 1 | awk -F= '{gsub(/ /,"",$2); print $2}')"
  if [[ -z "${order}" ]]; then
    order="N/A"
  fi

  elapsed_times+=("${elapsed}")
  convergence_orders+=("${order}")

  printf "[BENCH] run=%d elapsed=%ss order=%s\n" "${run_idx}" "${elapsed}" "${order}"
done

stats="$(
  printf "%s\n" "${elapsed_times[@]}" | sort -n | awk '
    {
      a[NR] = $1
      sum += $1
    }
    END {
      if (NR == 0) exit 1
      min = a[1]
      max = a[NR]
      mean = sum / NR
      if (NR % 2 == 1) {
        median = a[(NR + 1) / 2]
      } else {
        median = (a[NR / 2] + a[NR / 2 + 1]) / 2.0
      }
      p95_idx = int((95 * NR + 99) / 100)
      if (p95_idx < 1) p95_idx = 1
      if (p95_idx > NR) p95_idx = NR
      p95 = a[p95_idx]
      printf "%.6f %.6f %.6f %.6f %.6f", min, max, mean, median, p95
    }
  '
)"

read -r t_min t_max t_mean t_median t_p95 <<< "${stats}"
order_set="$(printf "%s\n" "${convergence_orders[@]}" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"

{
  echo "Hamiltonian Benchmark Summary"
  echo "runs=${RUNS}"
  echo "min_seconds=${t_min}"
  echo "max_seconds=${t_max}"
  echo "mean_seconds=${t_mean}"
  echo "median_seconds=${t_median}"
  echo "p95_seconds=${t_p95}"
  echo "convergence_orders=${order_set}"
  echo "logs_dir=${BENCH_LOG_DIR}"
} | tee "${SUMMARY_FILE}"

echo "[BENCH] Summary saved to ${SUMMARY_FILE}"

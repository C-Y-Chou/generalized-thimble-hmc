# Stephanov n=6 HMC Protocol Decision - 2026-05-22

## Scope

This supersedes the earlier Gaussian-initialized local scan in this runbook.
The active `n=6, t=1e-6` nofb protocol decision uses:

```text
initial ensemble = t=0 checkpoint bank
target initialization = adaptive preflow with staged flow and zero-momentum relaxation
HMC scan order = epsilon first, then nstep/L
```

Model point:

```text
n = 6
N_f = 1
m = 0.004
mu = 0.6
tau = 0
flow_time = 1e-6
method = nofb
```

The policy remains
`runbooks/STEPHANOV_HMC_PROTOCOL_TUNING_POLICY_20260522.md`: choose
`epsilon = L/nstep` first, then choose trajectory length through `nstep`.
Do not tune nofb by minimizing proposal failures.

## Initialization Boundary

A `t=0` bank checkpoint is a physical `x(:)` seed.  It is not guaranteed to
flow safely to every nonzero flow time by direct evaluation.  The active
low-flow initialization therefore starts from a selected bank record and runs
`adaptive_preflow_to_target_at`, which advances in flow-time stages and applies
zero-momentum relaxation at intermediate points.

For protocol scans, initialization controls are deliberately separate from the
HMC kernel being tuned:

```text
TLTM_STAGE2_INIT_MODE=adaptive
TLTM_STAGE2_INITIAL_X_FILE=output/stephanov_checkpoint_banks/stephanov_n6_t0_bank_dev_4x1000_s10_b20_20260522/bank/x_bank.dat
TLTM_STAGE2_INIT_PREFLOW_TRAJECTORY_LENGTH=0.16
TLTM_STAGE2_INIT_PREFLOW_INTEGRATION_STEPS=2
```

This prevents the scanned HMC `epsilon,nstep` from also changing the
initialization relaxation step.

## Scan Script

Reproducible local helper:

```text
codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_bank_hmc_protocol.py
```

The helper writes summary/detail CSVs and x-history movement diagnostics.  It
does not write z/phi phase history during protocol tuning; phase readout is a
separate physics diagnostic and can fail for singular determinants even when the
HMC protocol itself is operational.

## Epsilon Scan

Fixed `nstep=5`, `4 bank records x 200 cycles`, adaptive bank preflow fixed at
`L=0.16, nstep=2`.

Command:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_bank_hmc_protocol.py \
  --skip-build \
  --stage epsilon \
  --records 0,81,162,243 \
  --cycles 200 \
  --fixed-nstep 5 \
  --epsilon-values 0.08,0.10,0.12 \
  --run-name stephanov_n6_bank_adaptive_eps_refine4_fixed_preflow_20260522 \
  --force
```

Output:

```text
output/stephanov_hmc_protocol_scans/stephanov_n6_bank_adaptive_eps_refine4_fixed_preflow_20260522/epsilon_summary.csv
```

| epsilon | L | status | acceptance | proposal failures | movement/sec | samples |
|---:|---:|---|---:|---:|---:|---:|
| `0.08` | `0.40` | done | `0.81500` | `0` | `325.58` | `201;201;201;201` |
| `0.10` | `0.50` | done | `0.66625` | `0` | `371.02` | `201;201;201;201` |
| `0.12` | `0.60` | done | `0.56250` | `0` | `406.18` | `201;201;201;201` |

Decision: use `epsilon = 0.10` for the local working protocol.  `epsilon=0.12`
has the highest short-run movement proxy, but one of the four records is already
near `0.51` acceptance; this is too close to the edge for the next nofb physics
check.  `epsilon=0.08` is the conservative fallback.

## Trajectory-Length Scan

Fixed `epsilon=0.10`, `4 bank records x 200 cycles`, adaptive bank preflow fixed
at `L=0.16, nstep=2`.

Command:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_bank_hmc_protocol.py \
  --skip-build \
  --stage nstep \
  --records 0,81,162,243 \
  --cycles 200 \
  --fixed-epsilon 0.10 \
  --nstep-values 2,3,4,5,6,8,9 \
  --run-name stephanov_n6_bank_adaptive_nstep_scan_eps010_20260522 \
  --force
```

Output:

```text
output/stephanov_hmc_protocol_scans/stephanov_n6_bank_adaptive_nstep_scan_eps010_20260522/nstep_summary.csv
```

| nstep | L | status | acceptance | proposal failures | movement/sec | samples |
|---:|---:|---|---:|---:|---:|---:|
| `2` | `0.20` | done | `0.82375` | `0` | `213.67` | `201;201;201;201` |
| `3` | `0.30` | done | `0.76750` | `0` | `293.80` | `201;201;201;201` |
| `4` | `0.40` | done | `0.75500` | `0` | `365.83` | `201;201;201;201` |
| `5` | `0.50` | done | `0.66625` | `0` | `366.92` | `201;201;201;201` |
| `6` | `0.60` | done | `0.66000` | `1` | `393.76` | `201;201;201;201` |
| `8` | `0.80` | done | `0.62875` | `0` | `370.79` | `201;201;201;201` |
| `9` | `0.90` | done | `0.62125` | `0` | `343.59` | `201;201;201;201` |

Decision: use `nstep = 6`, hence `L = 0.60`, for the next local nofb physics
run.  This is the best short-run movement-per-wall-time point in the scan.  The
single proposal failure at `nstep=6` is diagnostic output, not a reason to
retune nofb away from the selected protocol.  `nstep=4` is the conservative
fallback if longer runs show the one failure is systematic or if the movement
proxy overstates decorrelation.

## Selected Development Preset

Use:

```text
data/parameters_stephanov_n6_mu06_t1e6_eps010_nstep6.dat
```

Selected protocol:

```text
epsilon = 0.10
nstep   = 6
L       = 0.60
init    = t=0 bank + adaptive preflow to t=1e-6
```

This is a local development protocol, not production evidence.  The next
physics/sign-problem test should use this protocol, report proposal failures as
diagnostics, and evaluate phase coherence plus observable error bars separately.

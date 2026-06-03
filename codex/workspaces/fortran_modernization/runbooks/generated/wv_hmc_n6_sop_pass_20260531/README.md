# WV-HMC n=6 SOP Pass

Date: 2026-05-31

Scope: execute the repository parameter-tuning SOP for dense explicit-J
WV-HMC on Stephanov `n=6`, before matrix-free/BiCGStab trajectory wiring.

## Fixed Physics Target

```text
model = Stephanov
n = 6
nf = 1
m = 0.004
mu = 0.6
tau = 0
derivatives = manual
exact chiral_condensate = 0.0244771983
exact number_density = 0.5661155667
```

## SOP Inputs

- Repository-wide SOP: `runbooks/PARAMETER_TUNING_SOP_20260531.md`
- Init-bank SOP: `runbooks/INIT_BANK_TUNING_SOP_20260531.md`
- WV-HMC solver SOP: `runbooks/WV_HMC_PARAMETER_TUNING_SOP_20260531.md`
- Existing n=6 t=0 development bank:
  `output/stephanov_checkpoint_banks/stephanov_n6_t0_bank_dev_4x1000_s10_b20_20260522/bank/x_bank.dat`

## Gate Ledger

| Gate | Status | Evidence / Next Action |
|---|---|---|
| model/observable correctness | pass | cluster job `18327.anode01`; WV-HMC math kernels PASS, constraint kernels PASS, `bin/run_wv_hmc` built |
| init bank | pass | cluster job `18328.anode01`; 16 t=0 chains, 6416 selected checkpoints, Rhat max 1.0022, safe-flow bank 4091/4096 records to `t=1e-4` |
| solver trace | pass-truncated | job `18329.anode01` intentionally stopped after 73,137 solves because the trace was sufficient and the remaining seeds were runtime tail; fixed tol `1e-10`, adaptive off, max_iter 96; converged 68,673, boundary_exit 4,462, residual_error 1, unknown 1, no max_iter failures |
| solver fail-fast/cap | pass | adopt `constraint_max_iter=24`, adaptive stop still off: converged q90=4, q99=6, max=17, no converged solve above 24 in trace; short same-seed A/B showed 10 paired seeds bitwise-identical in transition/observable summaries for max_iter 96 vs 24 |
| epsilon | pass | selected `epsilon=0.010` for the movement gate: acceptance 0.817 over 8x200 scan; target bracket is `0.010-0.012`, but `0.010` keeps better flow-time motion and less boundary pressure than higher epsilon |
| nstep/L movement | pass | selected `nstep=8`, `L=0.08`: effective x/z movement largest in same-seed scan and acceptance 0.735 remains usable; `nstep=5` is conservative fallback if validation cost is excessive |
| WV domain `[T0,T1]` / measurement interval | pending | must be fixed from algorithm/physics rationale, not from histogram, movement, acceptance, or boundary diagnostics |
| WV sampling shape `W(t)` | pending | tune only within the fixed `[T0,T1]`; current `paper_wall gamma=0.2` is a starting candidate, not a decision |
| production validation | blocked by WV domain and `W(t)` gates | exact z, seed/block/history, flow histogram, runtime only after solver policy, `[T0,T1]`, and `W(t)` are fixed |

## Initial WV Geometry

First pass starts from the small-interval setting that passed the dense
explicit-J `n=2` production gate:

```text
T0 = 1e-4
T1 = 1e-3
d0 = 1e-4
d1 = 2.5e-4
initial_flow_time = 5.5e-4
W(t) = paper_wall
gamma = 0.2 initial
c0 = c1 = 1
```

This interval is a placeholder domain choice from the small-interval `n=2`
development path.  It must not be selected or justified by acceptance,
movement, boundary-count, or flow-histogram criteria.  Changing this interval
is an upstream domain change and invalidates the downstream solver/HMC/`W(t)`
tuning.  Changing only `W(t)` or wall parameters requires at least a solver
health recheck and local HMC retune/equivalence check.

## Amendments

| Time JST | Issue | SOP / Tooling Update | Invalidation |
|---|---|---|---|
| 2026-05-31 | WV readback scripts hard-coded n=2 exact references, which would corrupt n=6 z-scores. | Added `--exact-chiral` and `--exact-density` CLI parameters to `write_wv_hmc_pilot_readback_20260529.py` and `write_wv_hmc_history_readback_20260531.py`. Added SOP self-update mechanism to `PARAMETER_TUNING_SOP_20260531.md`. | Any n=6 WV-HMC readback must use explicit n=6 exact values; no n=6 readback made before this amendment is decision-grade. |
| 2026-05-31 | Newton trace analyzer only accepted `dense_pilot_scan_summary.csv`, but the SOP solver gate uses the multi-seed observable-validation manifest. | Updated `analyze_wv_hmc_newton_traces_20260530.py` to also accept `wv_hmc_dense_observable_validation_manifest.csv` and normalize seed labels/cycle fields. | Solver trace analysis must use the patched analyzer before choosing any fail-fast rule. |
| 2026-05-31 | Newton trace stop reason `10` is a valid boundary reflection, not a solver failure, and long fixed-tol trace runs can be useful before every seed reaches the full cycle target. | Updated the analyzer to name `boundary_exit`, report it separately, exclude it from failed-solve counts, add `resolved_rate`, and support a `--trace-dir` fallback for partial trace analysis before a manifest exists. | Fail-fast decisions must use resolved-vs-failed classification; boundary reflections cannot be used as evidence of solver failure. |
| 2026-05-31 | The fixed-tol n=6 trace had enough Newton data long before every seed finished, while remaining runtime was a long-tail cost unrelated to max-iter failure. | Updated `WV_HMC_PARAMETER_TUNING_SOP_20260531.md` to allow explicitly recorded trace truncation after enough solves, and to require boundary exits be separated from failed solves. | The `18329.anode01` solver trace is decision-grade for choosing a conservative cap candidate, but not for wall-clock production timing because it was intentionally killed. |
| 2026-05-31 | Movement scan initially reused the epsilon-scan `nstep=5` data, which used a different seed set from the `nstep=2,4,6,8` scan. | Updated `WV_HMC_PARAMETER_TUNING_SOP_20260531.md` to require the current baseline `nstep` be included with the same seed set and initial-bank draw policy. Added same-seed `nstep=5` and `nstep=7` supplemental scans. | Do not choose final `nstep` until the same-seed baseline is included. |
| 2026-05-31 | Pilot readback discovered only immediate `*_summary.csv` files, but validation is chunked under a production root. | Updated `write_wv_hmc_pilot_readback_20260529.py` to discover summary/observable pairs recursively with `rglob`. | Multi-chunk validation readback can now use the production root directly. |
| 2026-05-31 | The n=6 pass was about to label a run as validation before the `W(t)`/interval gate was fixed. | Corrected the ledger: production validation is blocked until `W(t)` and `[T0,T1]` are decided; any run before that is only a geometry smoke and cannot be used as the final correctness gate. | Do not submit production validation chunks before the WV geometry gate is recorded. |
| 2026-05-31 | `[T0,T1]` was incorrectly grouped with sampler diagnostics such as histogram flatness, movement, and boundary pressure. | Corrected the repository and WV-HMC SOPs: `[T0,T1]` is an upstream domain/physics input; diagnostics can reject an interval as unusable but cannot select it. `W(t)` is the tunable sampling-shape layer within fixed `[T0,T1]`. | Re-open the n=6 WV domain gate before final `W(t)`, solver-health, or production validation claims. |

## Passed Gate Artifacts

```text
build/test log:
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_n6_sop_20260531/build_gate/pbs_boot_18327.anode01.log

t=0 bank root:
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260531/stephanov_n6_wv_hmc_t0_bank_16x5000_t0001_20260531_18328.anode01

safe initial bank:
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260531/stephanov_n6_wv_hmc_t0_bank_16x5000_t0001_20260531_18328.anode01/safe_bank_t0p0001/x_bank.dat

truncated Newton trace analysis:
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n6_sop_20260531/solver_trace_tol1e10_16x500_20260531/newton_trace_analysis_truncated/wv_newton_trace_analysis.md
```

## Cluster Rule

All Fortran builds, tests, and simulations in this pass must be scheduler-gated
cluster jobs.  Local inspection and Python syntax checks are allowed; local
Fortran execution is not.

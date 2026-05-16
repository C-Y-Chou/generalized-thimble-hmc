# F18b.4o ODEX Telemetry Policy Compare

Date: 2026-05-16 JST

## Purpose

After the corrected `hairer_experimental` 10seed/10k screen showed a material
runtime cost, add direct ODEX internal-work telemetry and run a remote-only
1k/10seed same-machine comparison between:

- `TLTM_ODE_CONTROLLER_POLICY=tltm_endpoint`
- `TLTM_ODE_CONTROLLER_POLICY=hairer_experimental`

This is not a production baseline.  It is an instrumentation screen to explain
where the partial Hairer route spends work.

## Source Changes

- `odex_result` now carries ODEX-only internal counters:
  `odex_rhs_evals`, `odex_midpoint_rows`, `odex_kplus1_attempts`,
  `odex_accept_k_minus_1`, `odex_accept_k`, `odex_accept_k_plus_1`,
  `odex_large_error_rejects`, and `odex_kplus1_rejects`.
- `solve_flow` aggregates those counters in the explicit
  `intode_diagnostics_context_t` path.
- Stage2 summaries now emit `# odex_stats ...` and context lines.
- `scripts/run_stage3_3_multiseed.py` parses `# odex_stats`, writes per-seed
  columns, and aggregates per-call means.
- A 1k official DFO-LS config and PBS launcher were added:
  `docs/production_comparison_official_dfols_20260511_10seed_1k_nofb_withfb.json`
  and
  `tasks/pbs/f18b4o_odex_telemetry_policy_compare_10seed_1k_20260516.pbs`.

## Local Verification

- `python3 -m py_compile scripts/run_stage3_3_multiseed.py`
- `git diff --check`
- `make -C build test_odex_result_contract test_odex_backend_package_contract`

The focused ODEX tests passed locally.  No TLTM Stage2/Stage3 screen was run
locally.

## Remote PBS

- Job: `15538.anode01`
- Queue/node: `C16`, `cnode01/0*20`
- Exit: `Exit_status=0`
- Walltime: `00:04:22`
- Campaign:
  `f18b4o_odex_telemetry_policy_compare_npt5_r0055_10seed_1k_20260516T175507_243c09ceb99f`
- Output root:
  `output/tests/f18b4o_odex_telemetry_policy_compare_npt5_r0055_10seed_1k_20260516T175507_243c09ceb99f`
- Log root:
  `output/logs/f18b4o_odex_telemetry_policy_compare_npt5_r0055_10seed_1k_20260516T175507_243c09ceb99f`

Both policies ran concurrently inside the same PBS job with
`TLTM_RUN_JOBS_PER_POLICY=10`, `TLTM_METHODS=no_fb_fbnorefine`,
official DFO-LS `npt5_r0055`, assist off, reverse gate on, and Stage2 RNG v2.

## Artifact Repair

The first generated `aggregated_summary_table.csv` files had `odex_*` columns
present but blank because `run_one_seed()` did not include
`odex_stat_columns()` in the row dictionary.  The Fortran summaries already
contained valid `# odex_stats` lines.  The script was patched, synced, and the
existing CSV artifacts were repaired by reparsing the existing
`tltm_stage2_summary.dat` files.  No Stage2/Stage3 rerun was needed for the
repair.

## Aggregate Results

| Method | Policy | mean runtime | unresolved failures | rhs/call | accepted steps/call | rejected steps/call | midpoint rows/call | K+1 attempts/call | K+1 rejects/call |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `no_fb` | `tltm_endpoint` | `57.324` | `877` | `244.639` | `6.366` | `0.207` | `33.380` | `0.222` | `0.00305` |
| `no_fb` | `hairer_experimental` | `62.890` | `878` | `273.335` | `7.158` | `0.155` | `37.421` | `0.176` | `0.00925` |
| `fb_norefine` | `tltm_endpoint` | `102.409` | `18` | `267.814` | `6.649` | `0.279` | `35.763` | `0.252` | `0.00291` |
| `fb_norefine` | `hairer_experimental` | `115.198` | `16` | `328.065` | `11.065` | `0.215` | `49.486` | `2.203` | `0.02581` |

Ratios for `hairer_experimental / tltm_endpoint`:

- `no_fb`: runtime `1.097x`, RHS/call `1.117x`, accepted steps/call `1.124x`,
  midpoint rows/call `1.121x`, K+1 attempts/call `0.794x`, K+1 rejects/call
  `3.036x`.
- `fb_norefine`: runtime `1.125x`, RHS/call `1.225x`, accepted steps/call
  `1.664x`, midpoint rows/call `1.384x`, K+1 attempts/call `8.761x`,
  K+1 rejects/call `8.869x`.

## Interpretation

The partial Hairer route is not simply "more rejected steps".  It often has
fewer rejected steps per ODEX call, but it accepts more internal endpoint work.
For `fb_norefine`, the main signal is the K+1 path: attempts per call increase
from about `0.25` to `2.20`, and K+1 rejects per call increase by about `8.9x`.

This supports the user's concern that the missing coherent Hairer pieces are
likely the key runtime pieces.  The current `hairer_experimental` route mixes
Hairer-like accept/reject order update with the remaining TLTM endpoint loop,
`SCAL` lifecycle, initial `H/K`, and large-error/convergence thresholds.  It
should not be promoted as-is.

## Next ODEX Action

Do not accept the current opt-in route as final.  The next behavior-changing
packet should target the live outer-loop/controller coherence that can explain
K+1 overwork:

1. Wire the live initial `H/K` and signed-interval step-entry state to match the
   observed Hairer route instead of leaving it as `h=t*initial_step_fraction`,
   `k=opts%k_min`.
2. Align the `SCAL`/error-scale lifecycle and large-error/convergence thresholds
   used before the K+1 row.
3. Re-run the same remote 1k/10seed telemetry screen before any 10k promotion.

If those changes do not reduce accepted-step/K+1 work, the route decision should
shift toward removing or keeping `hairer_experimental` as non-default research
evidence only.

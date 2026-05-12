# CV-011 Stage2 Audit Context Slice

Updated: 2026-05-12 JST

## Scope

This slice removes Stage2 audit file state from module-level `save` storage.

## Implemented

- Added `stage2_audit_context_t` inside `tltm_stage2_driver`.
- Moved these former module-global audit fields into the context:
  - RG reject audit loaded/enabled state;
  - RG reject audit unit/file;
  - local-transition audit loaded/enabled state;
  - local-transition audit unit/file;
  - local-transition audit max-row setting;
  - local-transition audit row counter.
- `execute_tltm_stage2` now owns one audit context for the Stage2 run.
- Stage2 local updates pass the audit context into RG-reject and
  local-transition audit writers.
- Audit close is centralized through `close_stage2_audit_context`.

## Behavior Boundary

This is diagnostics state ownership only. It does not change physics,
transition status, Metropolis acceptance, solver routing, output summary
fields, or the route-B RNG contract.

## Verification

- `make -C build ../bin/run_tltm_stage2` passed.
- Tiny Stage2 run with both audit envs enabled passed:
  - `TLTM_RG_REJECT_AUDIT_FILE=output/tests/stage2_audit_context/rg_reject_audit.csv`
  - `TLTM_LOCAL_TRANSITION_AUDIT_FILE=output/tests/stage2_audit_context/local_transition_audit.csv`
  - local-transition audit produced header plus two rows;
  - RG-reject audit produced the expected header-only file for a no-RG-reject tiny run.
- `make -C build FC=gfortran LDFLAGS= post_b_rng_reference_anchor` passed.
- `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going` passed.

## Remaining Diagnostics State

This only removes Stage2 audit file handles/counters. Other diagnostics still
need explicit ownership or aggregation policy:

- constraint-solver/reverse-gate counters in `constraint_solver_stats.f90`;
- Newton/QN eval flow-status counters;
- HMC reverse-probe/progress diagnostic counters;
- broader flow/ODEX fallback and last-failure trace state.

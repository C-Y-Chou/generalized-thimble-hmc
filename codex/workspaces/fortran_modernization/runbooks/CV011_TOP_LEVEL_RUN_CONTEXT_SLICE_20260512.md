# CV-011 Top-Level Run Context Slice

Updated: 2026-05-12 JST

## Decision

User selected route A from the remaining-state decision point: CV-011 proceeds
with a top-level TLTM run context as the product direction, implemented
incrementally rather than by isolated module-by-module contexts.

## Implemented Slice

- Added `tltm_run_context_mod`.
- Introduced `tltm_run_context_t` with placeholder sub-contexts for HMC,
  flow, QN, model, diagnostics, config, and profiling ownership.
- Introduced `tltm_hmc_context_t` with separate reusable workspaces for:
  - forward proposal integration;
  - reverse-probe integration;
  - warmup integration.
- Threaded optional HMC context through:
  - `integrate_hmc_proposal`;
  - `integrate_hmc_warmup`;
  - `metropolis_step`;
  - Stage1 local updates;
  - Stage2 local updates.
- Stage1 now owns one run context per replica.
- Stage2 now owns one run context per slot.
- Legacy/non-context callers still use automatic local workspaces.

## Behavior Boundary

This slice changes workspace ownership only. It does not change the HMC
equations, QN route policy, reverse-gate policy, Metropolis acceptance rule, or
the already accepted route-B RNG stream contract.

The production redo tree remains independent. No production-comparison state,
runbook, output, or remote worktree sync is part of this slice.

## Verification

- `make -C build ../bin/run_tltm_stage1 ../bin/run_tltm_stage2` passed after
  the API migration.
- `make -C build FC=gfortran LDFLAGS= test_retained_core_rattle_rg_contract test_retained_core_rg_reject_identity post_b_rng_reference_anchor` passed.
- `python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going` passed after staging the new source file intentionally, satisfying the source/task boundary guardrail.

## Next CV-011 Work

Continue migrating behavior-bearing hidden state into the top-level context:

1. Flow/ODEX workspaces, trace context, last-failure state, and counters.
2. QN residual/trace/capture/backend callback state.
3. Diagnostics counters and Stage2 audit file handles.
4. Model tape/cache ownership or an explicit non-shared product boundary.
5. Config/profile ownership or an explicit immutable/global diagnostic
   boundary.

Stop for a user decision only if a migration would change physics, output
schema semantics, public run controls, or the production/modernization tree
boundary.

# Handwritten Algorithm Current-Head Audit - 2026-05-15

## Scope

Audit target:

- canonical local tree: `/Users/ccy/Documents/TLTM_qn_error_handling`
- branch: `codex/fortran-modernization`
- committed source head inspected: `3d63d4c`
- current assist-off run-producing source SHA: `71af06f55c240a0c20fc7a38c1353219be805930`
- previous audit inputs:
  - `HANDWRITTEN_ALGORITHM_DETAIL_AUDIT_GAP_REPORT_20260514.md`
  - `ODEX_CONTROLLER_DETAIL_AUDIT_20260514.md`
  - `HANDWRITTEN_ALGORITHM_CURRENT_ANALYSIS_REPORT_20260514.md`

Purpose: re-audit the current post-correction modernization source, instead of
using the 2026-05-14 handwritten-audit reports as final current-version signoff.

Supplement: the stronger all-handwritten-algorithm paper-correctness and
numerical-soundness audit now lives in
`HANDWRITTEN_ALGORITHM_PAPER_CORRECTNESS_AUDIT_20260515.md`.  Use that report
before answering whether all handwritten algorithms are paper-correct.

## Executive Conclusion

The post-correction current-head audit is complete. No new source bug requiring
an immediate Fortran patch was established by this audit.

The correct current claim is narrower than "all handwritten algorithms are
paper-correct":

```text
The current modernization source has a current-head handwritten-algorithm audit
for the active post-correction route. The main retained algorithm blocks remain
reference-mapped or policy-mapped, Stage2 RNG v2 is now the active explicit RNG
contract, and solver assist is no longer canonical. Several controller and
failure-policy details remain open-needs-proof for publication-grade
paper-correctness claims.
```

The 2026-05-14 audit reports should be treated as pre-fix claim-boundary maps.
They remain useful inputs, but this file is the current-head CV-012/F17 audit
packet.

For the stronger universal claim, this file is supplemented by
`HANDWRITTEN_ALGORITHM_PAPER_CORRECTNESS_AUDIT_20260515.md`, which explicitly
blocks "all handwritten algorithms are paper-correct" and records the
numerical-soundness findings.

## Diff Basis

The source-affecting post-audit/correction window inspected is the current
modernization source relative to the pre-RNG-v2 context line at `6abd1e0`.

Source files changed in that window:

- `src/core/tltm_rng.f90`
- `src/sampler/hmc.f90`
- `src/sampler/markovchain_metropolis.f90`
- `src/sampler/tltm_stage2_driver.f90`
- `scripts/run_stage3_3_multiseed.py`
- `tests/test_tltm_rng_contract.f90`
- `build/makefile`
- `scripts/run_m4_guardrails.py`

No `src/physics`, `src/sampler/quasi_newton_solver.f90`,
`src/sampler/quasi_newton_linear_solver.f90`,
`src/sampler/hmc_constraints.f90`, or `src/sampler/hmc_integrator_core.f90`
changes were found in that correction window. No `src/`, `scripts/`, `tests`,
or `build` changes were found after the 2026-05-14 audit consolidation commit
`230107e`.

## Current Classification

| Area | Current status | Current-head audit result |
| --- | --- | --- |
| ODEX controller | `partial/open-needs-proof` | Source is unchanged since the 2026-05-14 ODEX controller audit. The midpoint/extrapolation family and `IWORK(3)=3` sequence remain mapped, while h0, h-min, step-size bounds, order thresholds, rejection, and stability branches remain open-needs-proof. |
| Flow/inverse/Jacobian RHS | `reference-mapped/partial` | Source is unchanged in the correction window. Endpoint-flow and inverse-flow sign handling remain mapped; model derivative/cache and ODEX controller surfaces remain partial. |
| Simplified Newton | `closed-for-current-gate` | Source is unchanged in the correction window. Existing residual/projection/guardrail classification still applies. |
| RATTLE/HMC proposal | `mostly-matched/project-policy-partial` | Mathematical RATTLE core source is unchanged. `hmc.f90` now accepts explicit momentum input or RNG state so Stage2 RNG v2 can own the momentum draw; this does not alter the RATTLE formula but is behavior-relevant RNG plumbing. |
| BTN/QN residual and official DFO-LS route | `matched-core/partial-controller` | QN source is unchanged in the correction window. The active production-facing route is official DFO-LS `stable_gate77` with the npt5_r0055 assist-off policy in run contracts; route budgets/watchdogs remain project controller policy. |
| Solver/navigation assist | `historical-policy/current-assist-off` | F15 fallback-on navigation assist is now historical diagnostic evidence. Current source/run policy schedules assist deletion and uses method-level assist off for the npt5_r0055 baseline. Feedback-kernel correctness remains a separate audit question. |
| Metropolis/live-state mutation | `matched-with-new-rng-input` | The stay-put behavior and `exp(-Delta H)` boundary remain unchanged. `markovchain_metropolis` now accepts explicit `accept_uniform` or `accept_rng_state`, so Stage2 RNG v2 can own the accept draw without changing the Metropolis acceptance rule. |
| Stage2 tempering/swap/RNG | `detail-mapped-project-contract/partial-tests` | Stage2 now defaults to `stage2_kernel_rng_v2`. Init, local momentum, local accept, and swap accept draws are domain-separated; summaries and manifests write the contract. This is the active product RNG contract, not a same-trajectory preservation claim and not a full replica-exchange paper proof. |
| Diagnostics/counters | `active-CV011` | F4 local-transition event accounting remains strong, but broader flow/ODEX/constraint/model/config state and counter surfaces remain active CV-011/CV-012 boundaries. |

## Source Findings

### Stage2 RNG v2

Current source has a new counter-based RNG module with explicit Stage2 domains:

- `stage2:init`
- `stage2:local_momentum`
- `stage2:local_accept`
- `stage2:swap_accept`

`tltm_stage2_driver` defaults `TLTM_STAGE2_RNG_STREAM_CONTRACT` to
`stage2_kernel_rng_v2`, while preserving `legacy_global_v0` and
`per_replica_rng_v1` as explicit compatibility modes.

Local updates now pass:

- explicit Gaussian momentum generated from the `stage2:local_momentum` domain;
- explicit Metropolis accept uniform generated from the `stage2:local_accept`
  domain.

Swap accepts now draw from `stage2:swap_accept` for the active v2 contract.

Audit result:

- This closes the previous ambiguity that the Stage2 RNG stream was an implicit
  long-lived slot/label state.
- This intentionally changes finite same-seed trajectories.
- This is a product RNG-contract correction, not a paper-level proof of the full
  tempering protocol.

Required future evidence before stronger claims:

- first-N-cycle replay signatures for init/local/swap draw boundaries;
- schedule/order-invariance checks for local-update ordering;
- swap isolation tests showing local RNG keys are unaffected by swap decisions;
- longer statistical smoke/benchmark comparisons.

### HMC And Metropolis RNG Plumbing

`hmc.f90` now permits an explicit `momentum_in` or optional momentum RNG state.
`markovchain_metropolis.f90` now permits an explicit `accept_uniform` or optional
accept RNG state.

Audit result:

- The RATTLE proposal formula and Metropolis acceptance formula are not changed
  by this plumbing.
- The random draw ownership is now explicit enough for Stage2 RNG v2.
- Direct legacy callers without explicit RNG inputs still use the historical
  global RNG path, so product/reentrant claims must remain scoped to the active
  Stage2 path unless those callers are migrated or explicitly deprecated.

### Assist-Off Current Route

`ASSIST_DELETION_NPT5_ASSISTOFF_BASELINE_20260515.md` and the PBS wrapper define
the current assist-off start gate:

- `TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2`
- `QN_SOLVER_BACKEND=official_dfols`
- `QN_OFFICIAL_DFOLS_NPT=5`
- `QN_OFFICIAL_DFOLS_RHOBEG=0.055`
- `INTODE_SOLVER_ASSIST_POLICY=off`
- `TLTM_STAGE3_METHOD_ASSIST_POLICY=off`

The recorded current-head start-gate rerun at
`71af06f55c240a0c20fc7a38c1353219be805930` reproduced the 10seed/10k rows:

| method | mean Re | mean Im | failures | RG rejects | QN assist |
| --- | ---: | ---: | ---: | ---: | ---: |
| nofb | -0.002818340294982019 | -0.02465681851224433 | 8340 | 1150 | 0 |
| withfb | 0.02974362444598664 | -0.002988766099182953 | 167 | 1324 | 0 |

Audit result:

- This supports the current assist-deletion starting point.
- It does not prove the `withfb` feedback kernel preserves the target measure.
- It does not close ODEX controller detail gaps.

## Claim Boundary After This Audit

Allowed current wording:

```text
The current post-correction modernization source has been audited at the
handwritten-algorithm claim-boundary level. Stage2 RNG v2 and the assist-off
official DFO-LS npt5_r0055 route are explicitly identified current contracts.
Remaining paper-detail gaps are documented and must be closed before stronger
publication-grade algorithm-correctness claims.
```

Blocked wording:

```text
All handwritten TLTM numerical algorithms are now paper-correct.
```

```text
The 2026-05-14 audit alone certifies the current post-correction source.
```

```text
The withfb failure reduction proves feedback-kernel measure correctness.
```

## Remaining Open CV-012 Work

This audit completes the current-head audit packet, but CV-012 remains active
because some surfaces are not detail-signed:

1. ODEX controller branch closure:
   - h0 policy;
   - h-min floor;
   - step-size growth/shrink bounds;
   - order promotion/demotion thresholds;
   - rejection/stability branches.
2. BTN/QN route controller packet:
   - budgets, watchdogs, near/far classifications, force-best, and official
     bridge edge cases.
3. RATTLE/HMC failure/status packet:
   - every proposal failure status;
   - reverse-gate replay/status/counter boundaries.
4. Stage2 RNG/tempering packet:
   - first-N-cycle replay;
   - schedule/order invariance;
   - swap isolation;
   - explicit publication wording for compatibility modes.
5. Diagnostics/counter continuation:
   - typed flow/ODEX counters;
   - constraint aggregate/failure-capture counters;
   - model tape/cache and config mirror boundaries.

## Reopen Triggers

Reopen or extend this current-head audit if any source patch touches:

- ODEX controller constants, branch predicates, statuses, or failure mapping;
- `flowz`, `flowzr`, final `flow(...)`, or solver assist policy;
- simplified Newton residual/projection logic;
- RATTLE step order, reverse gate, failure-as-rejection, or Metropolis state
  mutation;
- QN residual variables, official DFO-LS callback/preset/gate, budgets, or
  watchdogs;
- Stage2 RNG ownership, swap schedule, acceptance rule, labels/slots, or output
  schema;
- diagnostics/counter denominator, replay/probe inclusion, or public schema
  meaning.

## Bottom Line

The current post-correction source is now audited at the CV-012/F17
current-head level. The audit found no immediate source bug, confirmed that
Stage2 RNG v2 and assist-off npt5_r0055 are the current explicit contracts, and
keeps paper-level controller/detail correctness claims scoped to the surfaces
that are actually detail-mapped. The stronger all-handwritten
paper-correctness/numerical-soundness status is recorded in
`HANDWRITTEN_ALGORITHM_PAPER_CORRECTNESS_AUDIT_20260515.md`.

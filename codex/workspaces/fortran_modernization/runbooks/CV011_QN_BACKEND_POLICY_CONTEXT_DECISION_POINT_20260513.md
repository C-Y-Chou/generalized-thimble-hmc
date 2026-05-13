# CV-011 QN Backend Policy Context Decision Point

Updated: 2026-05-13 JST

## Why This Is A Decision Point

`CV011_QN_DIAGNOSTICS_CONTEXT_SLICE_20260513.md` moved QN attempt-capture files
and aggregate QN counters into a Stage/run-owned diagnostics sink.

The remaining QN module-owned state is now policy/config cache state rather than
scratch or diagnostics output state:

- QN watchdog policy cache and values:
  `quasi_solver_assist_budget`, `quasi_accepted_iter_budget`,
  `qn_force_best_proposal_enabled`, `qn_force_best_proposal_tol`, and
  `quasi_watchdog_policy_loaded`;
- QN backend policy cache and values:
  `qn_backend_policy_loaded`, `qn_solver_backend`,
  `qn_backend_notice_printed`, `qn_official_dfols_failure_warned`,
  `qn_official_dfols_npt`, `qn_official_dfols_maxfun`,
  `qn_official_dfols_objfun_has_noise`, `qn_official_dfols_rhobeg`,
  `qn_official_dfols_rhoend`, `qn_official_dfols_model_abs_tol`, and
  `qn_official_dfols_model_rel_tol`.

Moving this state blindly into the diagnostics sink would mix run output with
solver policy. Moving it into per-replica QN contexts would create room for
accidental per-replica backend divergence. This determines the product shape for
OpenMP/thread-safe backend configuration.

## Options

### A. Driver-Owned QN Policy Context

Introduce an explicit QN policy/config context owned by the Stage/run layer,
loaded once from env/config, then passed read-only or intent-inout for lazy
compatibility through the QN solve path.

Consequence:

- clearest product boundary for backend policy;
- keeps diagnostics sink focused on files/counters;
- prevents accidental per-replica backend divergence;
- requires another explicit API-threading slice.

### B. Fold Policy Into QN Diagnostics Context

Store backend/watchdog policy cache fields inside `qn_diagnostics_context_t`.

Consequence:

- smallest near-term API surface;
- keeps one Stage-owned shared QN object;
- mixes configuration policy with output diagnostics;
- makes later product docs/schema less clean.

### C. Legacy Serial Policy Boundary

Keep QN backend/watchdog policy module-global for serial/debug compatibility,
document it as not yet OpenMP-productized, and continue with non-QN module-state
migration.

Consequence:

- avoids changing backend policy API now;
- leaves QN backend policy thread-safety open;
- may be acceptable only if policy is treated as immutable process-global state
  for the next product boundary.

## Recommendation

Choose A. QN diagnostics and QN policy are different ownership concepts:
diagnostics are run-output sinks, while backend/watchdog settings are product
configuration. A driver-owned policy context keeps that boundary explicit and is
the best shape for OpenMP/thread-safe productization.

## Current Stop Condition

Stop for user decision before migrating QN backend/watchdog policy state.

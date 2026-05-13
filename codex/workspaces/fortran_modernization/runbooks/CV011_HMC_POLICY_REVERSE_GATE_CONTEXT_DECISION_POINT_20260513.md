# CV-011 HMC Policy And Reverse-Gate Context Decision Point

Updated: 2026-05-13 JST

## Why This Is A Decision Point

`CV011_QN_POLICY_CONTEXT_SLICE_20260513.md` moved the remaining QN
backend/watchdog policy cache into an explicit Stage/run-owned QN policy
context.

The next behavior-bearing `save` state cluster is in `hmc_integrator_core`:

- S1 fallback and reverse-gate policy cache:
  `s1_fallback_policy_loaded`, `s1_probe_max_iter`,
  `s1_near_full_max_iter`, `s1_non_near_cheap_full_max_iter`,
  `s1_near_rescue_enabled`, `s1_nonnear_rescue_enabled`,
  `qn_reverse_gate_enabled`, `qn_reverse_gate_tol`, and
  `qn_quasi_tol_override`;
- reverse-gate replay recursion flag:
  `qn_reverse_gate_active`;
- reverse-gate replay status counters:
  `reverse_gate_replay_status_*`.

These are not one kind of state. Policy should be stable for the whole run,
the recursion flag is per active replay/proposal path, and replay counters are
diagnostic summary state. The next implementation shape decides how cleanly
HMC/RATTLE can become OpenMP-safe without changing route behavior.

## Options

### A. Split HMC Policy, Replay Runtime, And Replay Diagnostics

Add explicit HMC/RATTLE control state instead of one catch-all object:

- a Stage/run-owned HMC policy context for S1 fallback/reverse-gate env policy;
- a per-HMC-context replay runtime flag for `qn_reverse_gate_active`;
- a Stage/run-owned replay diagnostics context for reverse replay status counts.

Consequence:

- cleanest OpenMP/thread-safe product boundary;
- avoids accidental per-replica policy divergence;
- keeps counters out of policy objects;
- larger API-threading slice.

### B. Fold Everything Into Existing `tltm_hmc_context_t`

Store S1 fallback policy, reverse-gate active flag, and replay counters inside
the already-threaded per-replica/per-slot HMC context.

Consequence:

- smaller immediate API change;
- uses an object already present in Stage1/Stage2 local updates;
- risks per-replica policy divergence unless policy loading is centralized;
- makes run-level replay summary counters harder to read consistently.

### C. Legacy Serial HMC Policy Boundary

Keep this cluster module-global for now, document it as serial-only
compatibility state, and continue with other module-state clusters such as
`solve_flow`, `constraint_solver_stats`, model tape cache, config mirror, and
perf profiling.

Consequence:

- avoids another HMC API slice now;
- leaves a central OpenMP/thread-safe proposal-path blocker open;
- acceptable only if HMC/RATTLE reentrancy is explicitly not claimed yet.

## Recommendation

Choose A. It is the only option that keeps the three concepts separate:
product policy, per-call replay recursion state, and run diagnostics. It is
also the best fit with the already selected pattern: Stage/run ownership for
shared policy/diagnostics and per-replica/per-slot ownership for active
proposal workspaces.

## Resolution

User selected A on 2026-05-13 JST.

Implementation record:

- `CV011_HMC_POLICY_REVERSE_GATE_CONTEXT_SLICE_20260513.md`

## Current Stop Condition

Superseded. The HMC fallback/reverse-gate policy, replay runtime flag, and
replay status counters have been migrated into explicit contexts for the
Stage1/Stage2 local-update path, with legacy module fallback retained for
direct callers.

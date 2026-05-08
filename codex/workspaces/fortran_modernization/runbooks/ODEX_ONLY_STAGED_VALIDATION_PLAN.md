# ODEX-Only Staged Validation Plan

Updated: 2026-05-08
Scope: the first numerical canonicalization that may change trajectories.

## Goal

Move the flow backend toward the canonical ODEX-only target while preserving the physical content of the TLTM calculation.

This is explicitly different from ordinary modernization refactors: trajectory identity may change because the Radau/JFNK/final-resort rescue stack can currently alter how failed flow integrations are handled. Therefore the validation target is physical-observable stability and understood failure/counter changes, not byte-for-byte trajectory equality.

## Canonical target

Long-term canonical flow backend:

`ODEX only`, using the Hairer ODEX `IWORK(3)=3` sequence with matching work estimates and signed-interval/work-estimate robustness cleaned in the same canonicalization patch.

Legacy/deletion-candidate flow paths:

- Radau rescue.
- Fixed/chunked Radau rescue.
- JFNK support paths tied to rescue behavior.
- ODE final-resort acceptance or rescue acceptance policies.

If ODEX-only reveals unacceptable failure behavior, the preferred fix is to improve ODEX step control, error reporting, or failure classification rather than silently restoring a secondary integrator stack as the default production route.

Legacy Radau/JFNK/final-resort code should be arranged in the easiest later-deletion form: quarantined, explicitly disabled from production entry points, and not interleaved with the canonical ODEX path.


## Pre-validation blocker - retained core correctness audit

Do not submit the 10k -> 50k -> 100k ODEX-only validation jobs until the retained-core implementation correctness audit has at least accepted all five active numerical cores for staged validation:

- ODEX flow integration.
- Simplified Newton constraint solve.
- RATTLE proposal/integrator structure.
- Quasi-Newton p28 projection loss.
- HMC / Metropolis / reverse-gate proposal boundary.

The ODEX-only source gate changes routing, but it does not by itself prove the retained ODEX kernel or the surrounding proposal machinery is correct.

Required ODEX self-consistency checks before long validation:

- Analytic ODE convergence/order sanity for the ODEX kernel.
- Step subdivision consistency for deterministic integrations.
- Forward/backward or inverse-flow round-trip checks where applicable to TLTM flow semantics.
- Signed-interval/work-estimate robustness checks for controller quantities that assume positive work.
- Failure classification sanity: ODEX failure should be reported as failure, not silently rescued by Radau/JFNK/final-resort paths.

## Pre-change baseline

Before changing source behavior, record the current reference point:

- Build identity: branch, commit, compiler flags, and executable path.
- Canonical configs: `no_fb` and `fb_norefine`, RG on, p28 settings, post-refine off.
- Current Stage3_4 characterization anchor: `output/tests/stage3_4/judgment_20260508_128seed_100k_p28_rg_nofb_fbnorefine`.
- Flow counters if available from logs/output: ODEX failures, Radau rescue attempts/successes, JFNK/final-resort counters, solver failure classifications.

If current output does not expose enough flow-rescue counters, add a small diagnostic-only characterization before deletion, without changing acceptance behavior.

## Implementation rule

Implement ODEX-only as a controlled canonicalization step:

- Keep RNG order, observable formulas, p28 solver route, RG, and Metropolis unchanged.
- Make the flow-backend policy explicit and easy to audit.
- Prefer a single clear production default over hidden rescue behavior.
- Preserve enough diagnostics to explain every increased failure/reject class.
- Keep the old rescue stack quarantined until validation passes, unless user explicitly approves immediate deletion.

## Staged comparison sequence

Run stages in order and stop if a stage shows a major physical-observable problem.

1. `10k` validation:
   - Purpose: catch obvious breakage, compile/runtime issues, severe failure spikes, and gross observable drift.
   - Compare canonical `no_fb` and `fb_norefine` if feasible; at minimum compare `fb_norefine` because that is the canonical production route.
   - Required readout: observables, Z means, acceptance/failure counts, RG rejects, projection failures, flow failure/rescue counters, runtime.

2. `50k` validation:
   - Purpose: intermediate statistical and operational check after the 10k stage is clean.
   - Compare against the same pre-change reference family and the 10k trend.
   - Required readout: same as 10k, plus per-seed distribution inspection for outliers.

3. `100k` validation:
   - Purpose: final approval gate before declaring ODEX-only canonical and before deleting legacy rescue source.
   - Compare against the current M1 128seed/100k characterization where applicable.
   - Required readout: aggregate and paired per-seed observables, Z means, unresolved failures, RG rejects, projection failures, flow failure classifications, runtime.

## Acceptance criteria

A stage may pass when:

- Physical observables do not show a major unexplained change relative to statistical uncertainty and known trajectory-policy differences.
- Z means and core TLTM diagnostics remain scientifically plausible and explainable.
- Increased failure/reject counters, if present, are traceable to removal of rescue behavior and do not invalidate the observable result.
- RG and Metropolis semantics are unchanged.
- Output schema remains compatible with the comparison scripts or any schema change is explicitly versioned.

A stage must stop for review when:

- Observables move in a way that cannot be explained by expected trajectory-policy change.
- ODEX-only produces runaway unresolved failures or severe per-seed outliers.
- RG live-slot identity, RNG order outside the intended trajectory policy, or Metropolis acceptance semantics are accidentally changed.
- Logs cannot distinguish ODEX failure from p28 solver/RG failures.

## Post-validation actions

Only after 10k -> 50k -> 100k passes:

- Promote ODEX-only to the official canonical flow backend.
- Mark Radau/JFNK/final-resort rescue source for actual deletion or permanent archival quarantine.
- Regenerate official modernization baselines.
- Start broader repo-wide source modernization against those baselines.

Status: ready for implementation discussion. No ODEX-only source change has been made by this runbook.

## Source implementation note - 2026-05-08

Initial ODEX-only implementation uses explicit policy gates in `src/physics/solve_flow.f90`:

- `intode_enable_stiff_rescue = .false.` disables Radau rescue entry from `intode_stiff_rescue`.
- `intode_enable_final_resort = .false.` disables final-resort acceptance.
- `intode_fast_hmin_bypass = .false.` prevents the h-min path from trying final-resort before the normal failure classification path.

The Radau/JFNK routines are intentionally retained as legacy/quarantine code until 10k -> 50k -> 100k validation decides whether to delete them. During ODEX canonicalization, keep them isolated behind explicit disabled entry points/switches so later deletion is mechanically simple.

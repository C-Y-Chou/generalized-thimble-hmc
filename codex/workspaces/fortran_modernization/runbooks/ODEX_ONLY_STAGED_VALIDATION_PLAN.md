# Flow-Policy Staged Validation Plan

Updated: 2026-05-09
Scope: the first numerical canonicalization that may change trajectories.

Status: revised after the 2026-05-09 solver-internal assist validation. Pure ODEX-only remains a comparison mode, not the final canonical production target.

## Goal

Move the flow backend toward the canonical ODEX-primary target while preserving the physical content of the TLTM calculation.

This is explicitly different from ordinary modernization refactors: trajectory identity may change because the Radau/JFNK/final-resort rescue stack can currently alter how failed flow integrations are handled. Therefore the validation target is physical-observable stability and understood failure/counter changes, not byte-for-byte trajectory equality.

## Canonical target

Current canonical flow-policy candidate:

`ODEX primary + solver-internal ODE assist + strict final proposal`, using the Hairer ODEX `IWORK(3)=3` sequence with matching work estimates and signed-interval/work-estimate robustness.

Assist policy:

- allowed only as a Newton/QN residual-evaluation progress aid
- forbidden in final proposal `flow(...)`
- forbidden in external flow calls that construct physical proposal state

Legacy/deletion-candidate flow paths:

- Radau rescue.
- Fixed/chunked Radau rescue.
- JFNK support paths tied to rescue behavior.
- final-proposal rescue acceptance policies.

Pure ODEX-only revealed avoidable solver robustness loss. The preferred policy is not hidden secondary-integrator proposal acceptance, but explicit solver-internal residual assist plus strict final proposal construction.

Legacy Radau/JFNK/final-resort code should be arranged in the easiest later-deletion form: quarantined, explicitly disabled from production entry points, and not interleaved with the canonical ODEX path.


## Pre-validation blocker - retained core correctness audit

Do not submit long flow-policy validation jobs until the retained-core implementation correctness audit has at least accepted all five active numerical cores for staged validation:

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
   - Purpose: final approval gate before declaring the ODEX-primary solver-assist policy canonical and before deleting or renaming legacy rescue source.
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
- the flow policy produces runaway unresolved failures or severe per-seed outliers.
- RG live-slot identity, RNG order outside the intended trajectory policy, or Metropolis acceptance semantics are accidentally changed.
- Logs cannot distinguish ODEX failure from p28 solver/RG failures.

## Post-validation actions

Only after 10k -> 50k -> 100k passes:

- Promote ODEX-primary solver-internal assist with strict final proposal as the official canonical flow policy.
- Mark Radau/JFNK/final-proposal rescue source for actual deletion or permanent archival quarantine.
- Keep or redesign solver-internal residual assist as an explicit typed status pathway.
- Regenerate official modernization baselines.
- Start broader repo-wide source modernization against those baselines.

Status: pure ODEX-only validation completed and was revised by solver-internal assist validation. See `ODEX_SOLVER_ASSIST_VALIDATION_RESULT_20260509_QNCLEAN.md`.

## Source implementation note - 2026-05-08

Initial ODEX-only implementation uses explicit policy gates in `src/physics/solve_flow.f90`:

- `intode_enable_stiff_rescue = .false.` disables Radau rescue entry from `intode_stiff_rescue`.
- `intode_enable_final_resort = .false.` disables final-resort acceptance.
- `intode_fast_hmin_bypass = .false.` prevents the h-min path from trying final-resort before the normal failure classification path.

The Radau/JFNK routines are intentionally retained as legacy/quarantine code until 10k -> 50k -> 100k validation decides whether to delete them. During ODEX canonicalization, keep them isolated behind explicit disabled entry points/switches so later deletion is mechanically simple.

## Source implementation note - ODEX sequence canonicalization - 2026-05-08

Implemented in `src/physics/solve_flow.f90`:

- Hairer ODEX `IWORK(3)=3` sequence via shared `odex_iwork3_nstep`: `2,4,6,8,12,16,24,32,...`.
- Matching `calculate_ak` cost model derived from the same sequence helper.
- Positive work estimate in `calculate_wk` using `abs(h)` plus non-finite/tiny-step guard.
- Signed `calculate_hk` preserved so step direction remains controlled by the integration interval.

Local pre-validation checks performed after the patch:

- `git diff --check`.
- `make -C build ../bin/scan_flow_vs_flowz ../bin/scan_flowzr_stability`.
- `./bin/scan_flow_vs_flowz output/tests/odex_canonical/flow_vs_flowz_ft0p1.csv -0.5 0.5 21 0.1 0.0`: 21/21 `flowz` OK, 21/21 `flow` OK, max `|flowz-flow| = 5.00e-16`.
- `./bin/scan_flowzr_stability output/tests/odex_canonical/flowzr_roundtrip_ft0p1.csv -0.2 0.2 9 -0.2 0.2 9 0.1 0 1`: 81/81 `flowzr` OK, 81/81 signed roundtrip OK, max roundtrip `4.42e-15`.
- `make -C build test_tltm_stage2 TLTM_STAGE2_CYCLES=2 TLTM_STAGE2_NUM_REPLICAS=2 TLTM_STAGE2_MAX_FLOW_TIME=0.1 TLTM_STAGE2_LOCAL_UPDATES=1`.

These checks are smoke/self-consistency gates only. They do not replace the 10k -> 50k -> 100k physical-observable validation sequence.

Preferred ODE solver-level check before tolerance tuning:

- Run `scripts/run_odex_solver_check.sh`.
- This exercises `intode` directly on analytic IVPs rather than going through TLTM flow wrappers.
- Current coverage: scalar exponential forward/backward, harmonic oscillator forward/backward, full-step vs two-half-step consistency, and zero fallback accounting.
- Current local result at `abs_tol=rel_tol=3.0e-14`: all checks pass; fallback attempts/failures are 0.

Preferred TLTM-specific wrapper check before 10k validation:

- Run `scripts/run_odex_flow_wrapper_check.sh`.
- This exercises `flowz`, `flow`, and `flowzr` on the TLTM flow RHS at flow times 0.1 and 0.3.
- Current local result: `flowz/flow` success 21/21 for both flow times; `flowzr` roundtrip success 81/81 for both flow times; fallback attempts/failures are 0.
- Current max errors: `max|flowz-flow| = 5.00e-16` at t=0.1, `1.31e-13` at t=0.3; max roundtrip `4.42e-15` at t=0.1, `1.39e-14` at t=0.3.

The 10k physical validation protocol is recorded in `runbooks/ODEX_10K_VALIDATION_PROTOCOL.md`.

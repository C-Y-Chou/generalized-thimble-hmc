# WV-HMC Current Code Verification Ledger And Follow-Up Workflow

Date: 2026-06-02

Purpose: make the current WV-HMC code trust boundary explicit before any more
validation or production runs.  This file is the active follow-up workflow for
WV-HMC correctness.  It separates code surfaces that are actually checked from
surfaces that are only partially checked or still unverified.

## Current Decision

WV-HMC production correctness is not closed.

The current code has passed deterministic math/constraint/oracle gates, the
known `W(t)` measurement-factor convention bug has been fixed locally, the
boundary/Newton construction bug found by the exact positive-target gate has
been fixed, and the current-source Stephanov `n=2` medium/long physical ratio
gate now passes.  That is still not the same as proving that the `n=6`
production workflow is correct, and it is not the same as closing the
matrix-free/BiCGStab trajectory.

Important correction to the shorthand status: "constraint fixture rebaseline,
current-source positive-target regression, `n=6` production correctness, and
matrix-free trajectory" are top-level gates, not a complete list of unfinished
work.  The transition-kernel audit subitems below remain blocking and must not
be skipped.

Publication closure update, 2026-06-03:

- the repository is now in a credit-application/productization closure mode, not
  an algorithm-expansion mode;
- the Stephanov `n=6` long dense explicit-J validation readback is recorded in
  `runbooks/generated/wv_hmc_n6_t0001_validation_20260603/N6_LONG_VALIDATION_READBACK_20260603.md`;
- the readback is a bounded startup-transient caveat rather than a stable
  dense-kernel correctness failure: all-cycle chiral Re is borderline, first
  half is biased, and post-burn-in cuts pass the four primary z checks;
- proceed to the productization workflow in
  `runbooks/generated/productization_closure_workflow_20260603/PRODUCTIZATION_CLOSURE_WORKFLOW_20260603.md`;
- do not start matrix-free/BiCGStab wiring, DFO-LS/`withfb` revival, or broad
  source refactor before the publication package is closed.

Canonical next sequence:

1. Completed: rebaseline stale constraint fixtures and make the gitless build
   gate hard-pass on source pin `77ffdb4e4771-f24205a0c2e9`.
2. Completed for the dense explicit-J current gate: close the
   transition-kernel code audit enough to run current-source `n=2` ratio
   validation.  Diagnostic-only boundary fixture downgrades remain recorded.
3. Completed as a current-source physical ratio regression: rerun the
   positive-target/oracle readback machinery on the corrected source.  Direct
   positive-target ensemble moments still warn and remain diagnostic caveats.
4. Completed: run an `n=2` medium/long ratio-correctness gate to determine
   whether the current `|z|~2` ratio signals are finite statistics.
5. Completed enough for launch: fixed-kernel `n=6` tuning, bank-startup, and
   short validation work are recorded in the 2026-06-03 warm-bank runbook.
6. Completed with bounded caveat: finish and read back the current `n=6` long
   validation.
7. Execute productization closure before any new algorithm work.
8. Matrix-free/BiCGStab trajectory wiring is deferred until after the dense
   path is productized and the credit-application-ready package exists.

## Status Legend

- `verified`: tested against an independent or deterministic oracle, with a
  recorded cluster gate or established regression gate.
- `partial`: component-level checks passed, but the check does not prove the
  full production behavior where the component is used.
- `open-blocking`: not yet sufficient for WV-HMC production correctness.
- `open-nonblocking`: useful for productization or performance, but not needed
  to answer the current correctness question.
- `legacy-diagnostic`: old data or old behavior may be useful for comparison,
  but must not be treated as current-source validation.

## Verified Or Closed Surfaces

| Code surface | Status | Evidence | What this proves | What it does not prove |
| --- | --- | --- | --- | --- |
| WV real inner product and `alpha2` primitive | verified | `tests/test_wv_hmc_math_kernels.f90`; cluster job `18806.anode01` | Local real-coordinate convention and positive/fail-closed `alpha2` behavior are covered. | Full-chain invariant measure. |
| Dense fixed-surface decomposition wrapper and WV projection algebra | verified | `wv_projection_contract`, `wv_dense_projection_wrapper`, `wv_nonzero_flow_projection_geometry`; job `18806.anode01` | Projection/reconstruction/orthogonality against dense fixed-surface geometry. | That projected Gaussian momentum gives the correct full stationary measure after all transition gates. |
| Iterative projection/force/Newton small oracle | verified for small oracle cases | `wv_iterative_projection_oracle`, `wv_iterative_force_newton_oracles`; job `18806.anode01` | Iterative algebra agrees with dense oracle in covered fixtures. | Matrix-free production trajectory wiring or high-dimensional performance. |
| Anti-holomorphic flow convention and WV force direction | verified at deterministic/FD level | `wv_random_complex_force_flow`, `wv_worldvolume_force_fd`; job `18806.anode01` | Sign/conjugation/factor conventions for the force are locally checked on random complex seeds. | Whole-kernel sampling correctness. |
| Paper-wall `W(t)` provider | verified as formula/provider | `wv_potential_provider`; `WV_HMC_PARAMETER_TUNING_SOP_20260531.md` | `W(t)` value and derivative are available and tested as a potential. | A selected `gamma` gives correct/efficient flow-time coverage for every model. |
| Dense simplified Newton algebra | verified | `wv_simplified_newton_contract`, `wv_dense_simplified_newton_oracle`; job `18806.anode01` | `(h,u,lambda)` update algebra matches the local linearized contract. | Robustness and correctness of every nonlinear solve in production. |
| First-constraint dense solver mechanics | verified for fixtures | `wv_dense_first_constraint_solver`, stop-reason checks, final momentum projection; job `18806.anode01` | Solver convergence, stop reason, and final projection are covered in deterministic cases. | Production fail-fast policy for every parameter set. |
| Dense RATTLE local reversibility and energy behavior | partial | `wv_dense_rattle_reversibility`, `wv_dense_rattle_energy_scaling`, trajectory energy-order and reverse-energy checks; job `18806.anode01` | Local reversibility/energy-scaling behavior for covered small cases. | Detailed balance of the full Markov kernel across all failure/boundary paths. |
| Dense phase-volume local contract | partial | `wv_dense_trajectory_phase_volume_contract`; job `18806.anode01` | The local RATTLE map has the expected induced-volume Jacobian relation in the tested fixture. | Full invariant measure of the production kernel. |
| Boundary handling default | verified for deterministic gate; partial for production kernel | `wv_boundary_paper_full_flip`, `wv_transition_boundary_bounce_rg`; job `18806.anode01`; `runbooks/generated/wv_hmc_boundary_fix_20260602/BOUNDARY_NEWTON_GATE_READBACK.md` | The default boundary exit uses simplified-paper full momentum flip `pi -> -pi`; the no-boundary Newton solve now guards only the physical flow domain `t >= 0` and applies the measurement/wall interval after a converged no-boundary trial. | All source fixtures are rebaselined; every production boundary/failure category is closed for all parameter settings. |
| Reverse gate accounting in dense transition | partial | `wv_dense_transition_accept`, `wv_transition_boundary_bounce_rg`; job `18806.anode01` | RG pass/reject paths are executed and recorded in deterministic fixtures. | Full detailed balance under all numerical construction failures. |
| Exact positive-target invariant gate, `n=2`, `[0,0.01]`, `gamma=0`, high boundary stress | verified for post-fix source pin `4597ced50bd8-e99b1c4b19b1` | Post-fix high-L/c10 and high-L/c50 readbacks pass; pre-fix A/B runs failed at large z-score. | The fixed dense explicit-J production kernel samples the deterministic positive WV target in the tested small case, and the previous over-accepting boundary/Newton path was a real bug. | `n=6` production correctness, all `W(t)` profiles, all intervals, all fixture cases, or matrix-free trajectory correctness. |
| Metropolis probability helper | verified as helper | `wv_metropolis_accept_probability`; job `18806.anode01` | `min(1, exp(-Delta H))` helper is locally checked. | Correct invariant measure if `Delta H`, base measure, or proposal map are wrong. |
| Dense transition smoke, nonzero `W(t)` transition, and driver accounting | partial | `wv_nonzero_w_transition_gate`, `wv_nonzero_w_energy_scaling`, `wv_dense_chain_driver`; job `18806.anode01` | The dense driver can execute and account for transitions, rejects, measurement skips, and nonzero `W(t)` fixtures. | Production observable correctness. |
| WV measurement factor W convention | verified at source/oracle level | `wv_worldvolume_measure_factor_identity_case` for `n=2` and `n=6`; `wv_dense_measurement_factor`; job `18806.anode01` | `wv_factor = phase / alpha`; `W(t)` is potential metadata and does not multiply the measurement factor. | That the current production ensemble is correct. |
| Dense/operator measurement-factor consistency | verified for fixtures | `wv_operator_measurement_factor_dense_oracle`; job `18806.anode01` | Operator path matches dense measurement factor in covered cases. | Matrix-free production trajectory correctness. |
| Weighted observable accumulator | verified as helper | `wv_weighted_observable_accumulator`; job `18806.anode01` | Ratio accumulator arithmetic is covered in a helper test. | Autocorrelation, seed/block uncertainty, or production estimator correctness. |
| DOP853 as WV/TLTM flow backend | partial | Used in current app path and run metadata; deterministic gates build through current source. | DOP853 is wired and usable in the current source surface. | Solver-controller optimality or every WV production path. |
| Scheduler gitless source-pin gate | verified for deterministic gate | `runbooks/generated/wv_hmc_measure_n6_oracle_gate_20260602/RESULT.md` | Cluster build/test can run without node-local `.git` using the source-pinned snapshot. | Every production launch is automatically scheduler-optimal. |
| Current-source WV-HMC math/constraint build gate | verified for source pin `77ffdb4e4771-f24205a0c2e9` | cluster job `18842.anode01`; `runbooks/generated/wv_hmc_n2_ratio_gate_20260602/N2_MEDIUM_LONG_RATIO_GATE_READBACK.md` | Current source builds in the gitless snapshot and passes WV-HMC math and constraint kernel suites. | `n=6` production correctness or matrix-free trajectory correctness. |
| Current-source `n=2` medium/long physical ratio gate | verified for source pin `77ffdb4e4771-f24205a0c2e9` | medium jobs `18843`/`18845`; long jobs `18844`/`18846`; `runbooks/generated/wv_hmc_n2_ratio_gate_20260602/N2_MEDIUM_LONG_RATIO_GATE_READBACK.md` | The physical complex ratio estimates for chiral condensate and number density are statistically consistent with exact `n=2` references at medium and long statistics. | Direct positive-target ensemble-moment proof, `n=6`, all intervals/`W(t)`, or matrix-free trajectory correctness. |

## Legacy Or Diagnostic Data

| Dataset or behavior | Status | Use | Do not use for |
| --- | --- | --- | --- |
| Old n=6 long dataset `n6_t0_long_old_boundary_sourcepin_8ec6dc0d9b87_86f750bba994` | legacy-diagnostic | Same-history measurement-factor and flow-cut diagnosis. | Current-source WV-HMC validation. |
| Old online `exp(W) * phase / alpha` measurement summaries | legacy-diagnostic | Explaining old output contamination. | Production formula selection. |
| Offline `phase/alpha` recomputation on old long history | legacy-diagnostic | Confirms the old broad-window failure is not fixed by removing `exp(W)` alone. | Proving current-source failure or success. |
| Post-boundary-fix n=2 exact-reference sanity runs | partial | Evidence that the small system can pass after a valid state-bank start. | General proof for n=6 or for all `W(t)`/interval settings. |
| Post-fix n=6 high-flow diagnostic | partial | Evidence against the earlier gross high-flow drift in one diagnostic setting. | Full-window production gate. |

## Open Blocking Items

These items must be resolved before claiming WV-HMC production correctness.

1. Full invariant-measure / detailed-balance gate for the production kernel.
   - Current status: completed for the post-fix `n=2`, `[0,0.01]`, `gamma=0`,
     high-boundary-stress source pin `4597ced50bd8-e99b1c4b19b1`; not yet
     generalized or re-run as a clean current-source fixture gate.
   - Completed test: exact positive-target oracle
     `rho_+(x,t) proportional to exp(-Re S(z_t(x)) - W(t)) * alpha(x,t) * |det J(x,t)|`.
   - Completed evidence: pre-fix high-L gates failed; post-fix high-L/c10 and
     high-L/c50 gates passed after the boundary/Newton fix.
   - Remaining requirement: add this as a reproducible current-source
     scheduler-gated regression, then expand beyond the single `gamma=0`
     small-target stress case as needed.

2. Momentum refresh and projected Gaussian base-measure proof.
   - Current status: local projection algebra checked, full refresh law not
     independently tested.
   - Required test: in the exact positive-target oracle, verify that the
     transition with projected ambient Gaussian momentum samples the intended
     induced worldvolume base measure.  If possible, add a separate fixture for
     tangent momentum covariance in intrinsic coordinates.

3. Hamiltonian/base-measure convention audit.
   - Current status: source uses `H = 1/2*pi^2 + Re(S) + W(t)`.
   - Required decision record: explicitly derive why no `log alpha` belongs in
     the Hamiltonian when the Markov kernel is formulated with respect to the
     induced worldvolume measure.  The derivation must state the base measure,
     momentum measure, and where `alpha` enters the final reweighting factor.
   - Required test: the exact positive-target gate above must fail if the
     Hamiltonian/base-measure convention is wrong.

4. Boundary and construction-failure invariant handling.
   - Current status: full-flip boundary deterministic gate passes; the
     boundary/Newton misuse found by exact positive-target A/B has been fixed;
     full Markov classification is not closed for every path.
   - Required audit: classify each production exit as boundary reflection,
     reverse-gate stay-put rejection, Metropolis rejection, or true numerical
     construction failure.  No hidden sample selection is allowed.
   - Required test: forced boundary and forced construction-failure cases must
     leave state/counters consistent with a stay-put Markov transition.

5. Constraint fixture rebaseline and build-gate closure.
   - Current status: completed for source pin `77ffdb4e4771-f24205a0c2e9`.
   - Required audit: update brittle `test_wv_hmc_constraint_kernels` fixtures
     that still encode old interior/no-boundary assumptions, without weakening
     the deterministic boundary and reverse-gate contracts.
   - Required test: the gitless build gate hard-fails on nonzero constraint
     suite exit, and a clean source pin passes math and constraint suites.
   - Completed evidence: cluster job `18842.anode01`, exit status `0`, passed
     `[PASS] WV-HMC math kernels` and `[PASS] WV-HMC constraint kernels`.

6. Current-source positive-target regression.
   - Current status: current-source readback machinery completed for source pin
     `77ffdb4e4771-f24205a0c2e9`; physical ratio observables pass, while
     direct positive-target ensemble moments remain diagnostic warnings.
   - Required preconditions: items 1-5 pass or have explicit temporary waivers
     recorded in this ledger.
   - Required run: scheduler-gated exact positive-target regression from a clean
     current source pin, not only the earlier `4597ced50bd8-e99b1c4b19b1`
     snapshot.
   - Required analysis: positive-target ensemble metrics, ratio observables,
     transition accounting, acceptance/RG/failure categories, and source pin.
   - Completed evidence: medium and long current-source jobs recorded in
     `runbooks/generated/wv_hmc_n2_ratio_gate_20260602/N2_MEDIUM_LONG_RATIO_GATE_READBACK.md`.
   - Caveat: direct positive-target moment warnings are preserved.  They do not
     fail the physical ratio gate, but they prevent this item from being used as
     a standalone proof of every aspect of the invariant distribution.

7. Current-source `n=2` medium/long ratio-correctness gate.
   - Current status: completed and passed for physical ratio observables.
   - Required preconditions: current-source positive-target regression passes.
   - Required run: enough seeds/cycles and observable history to determine
     whether ratio chiral/density z-scores near `|z|~2` shrink with statistics
     or remain systematic.
   - Required analysis: ratio-preserving uncertainty, seed/block stability,
     cumulative z curves, denominator stability, and exact-reference comparison.
   - Required decision: if `n=2` ratio z-scores remain systematically biased,
     route back to transition-kernel audit; do not proceed to `n=6`.
   - Completed decision: long physical ratio z-scores are chiral Re `-0.366`,
     chiral Im `-1.263`, density Re `0.469`, density Im `1.684`; route forward
     to short predeclared `n=6` validation, with the direct-moment and
     zero-measurement-seed caveats preserved.

8. Current-source n=6 validation after code and n=2 gates.
   - Current status: short/tuning launch gate completed enough to start the
     current long validation; final `n=6` correctness is not closed until that
     long validation readback passes.
   - Required preconditions: items 1-7 pass.
   - Completed launch-gate record:
     `runbooks/generated/wv_hmc_n6_t0001_warm_bank_20260603/README.md`.
   - Required final analysis: exact-reference z-scores, ratio-preserving
     uncertainty, seed/block stability, flow histogram, state movement,
     acceptance/RG/failure accounting, Newton stop table, runtime, source pin,
     and restart/snapshot availability.

9. Promotion from short validation to long production.
   - Current status: completed with bounded caveat.  The all-cycle estimator is
     not clean because of a startup transient, but post-burn-in cuts pass the
     four primary z checks.
   - Required rule: product docs must state the WV-HMC dense validation claim
     with burn-in/thermalization handling; the all-cycle estimator from this run
     is not a production estimate.

10. Matrix-free / BiCGStab trajectory wiring.
   - Current status: deferred until after productization closure.
   - Required preconditions: dense explicit-J production kernel is closed and
     exact positive-target/dense n=6 gates are passed; credit/application-ready
     package exists.
   - Required tests: dense-vs-matrix-free trajectory agreement, solve residual
     taxonomy, and current-source validation on a small shared seed set.

## Open Nonblocking Items

These should stay in the modernization workflow, but they do not replace the
blocking correctness gates above.

1. Archive/index old WV-HMC generated datasets by source pin and method label.
2. Keep old-boundary long data under legacy-diagnostic labels.
3. Finalize product-facing docs after the current `n=6` long validation
   readback, using the productization closure workflow as the publication-order
   authority.
4. Continue scheduler optimization, but do not let queue speed determine
   scientific gates.
5. Expose adaptive Newton fail-fast constants as explicit knobs only if future
   residual traces show they must be varied by model/parameter set.
6. Re-run broad guardrails after any source edit that touches shared TLTM/WV
   modules.

## Follow-Up Workflow

### Phase A. Freeze The Trust Boundary

Status: active.

Completed launch-gate actions:

- Keep this ledger as the entry gate for all further WV-HMC work.
- Label every dataset as current-source validation, legacy diagnostic, or
  helper calibration.
- Do not use old long validation data to prove current-source correctness.

Exit criteria:

- This ledger exists and is linked from the implementation/master workflow.
- Current code status is not summarized as "validated" without a table row.

### Phase B. Add Exact Positive-Target Invariant-Measure Test

Status: completed as a bug-finding A/B gate for the post-fix `n=2`,
`[0,0.01]`, `gamma=0` stress case; convert to a clean current-source regression
after fixture rebaseline.

Actions:

- Implement a small exact WV target oracle using deterministic quadrature over
  `(x,t)`.
- Compute the positive target
  `exp(-Re S - W) * alpha * |det J|` and the complex ratio reference.
- Run a scheduler-gated WV-HMC sample on the same model/interval.
- Compare unweighted sample distribution and ratio estimates against the
  exact oracle.

Exit criteria:

- Positive-target distribution passes with predeclared tolerances.
- Ratio measurement passes exact-reference checks.
- Failure/RG/rejection paths are counted as attempts and do not create hidden
  selection.
- Pre-fix failure and post-fix pass are recorded in
  `runbooks/generated/wv_hmc_boundary_fix_20260602/BOUNDARY_NEWTON_GATE_READBACK.md`.

### Phase C. Complete Transition-Kernel Invariant Audit

Status: completed for the current dense explicit-J `n=2` ratio gate.  This is
not a matrix-free or full-production proof.

Actions:

- Record Hamiltonian/base-measure derivation.
- Audit momentum refresh covariance in tangent/intrinsic coordinates.
- Audit all boundary, RG, Metropolis, and construction-failure paths.
- Add forced-path tests for stay-put semantics.
- Rebaseline `test_wv_hmc_constraint_kernels` so it tests the corrected
  boundary/Newton contract, then require the gitless build gate to pass the full
  suite.

Exit criteria:

- No production path can silently drop or select samples.
- The exact positive-target test and forced-path tests both pass.
- Completed evidence: current-source build/test gate `18842.anode01` and
  current-source medium/long ratio jobs `18843`/`18845`/`18844`/`18846`.

### Phase D. Current-Source Positive-Target Regression

Status: completed as a physical-ratio regression; direct target moments remain
diagnostic warnings.

Actions:

- Use a clean current source pin, not the old post-fix snapshot alone.
- Rerun the exact positive-target regression with the corrected
  boundary/Newton contract.
- Record positive-target direct metrics and physical ratio metrics separately.

Exit criteria:

- Physical ratio metrics are statistically consistent with exact references.
- Direct positive-target ensemble-moment warnings are preserved as diagnostics,
  not erased or reinterpreted as physical-ratio failure.
- Transition accounting contains no hidden sample selection in the recorded
  current-source run.

### Phase E. Current-Source n=2 Medium/Long Ratio Gate

Status: completed and passed for source pin `77ffdb4e4771-f24205a0c2e9`.

Actions:

- Use observable history, not only one final sample per seed.
- Run enough seeds/cycles to test whether ratio chiral and density z-scores near
  `|z|~2` shrink with statistics.
- Analyze cumulative z curves, seed/block stability, denominator stability, and
  exact-reference agreement.

Exit criteria:

- Physical ratio observables show no stable systematic drift under increased
  statistics.
- If ratio drift remains, the workflow returns to Phase C rather than advancing
  to `n=6`.
- Completed evidence: long physical ratio z-scores are chiral Re `-0.366`,
  chiral Im `-1.263`, density Re `0.469`, density Im `1.684`.
- Caveat: direct positive-target moment warnings and zero-measurement seeds
  remain health diagnostics.

### Phase F. Current-Source n=6 Short Validation

Status: completed as the predeclared tuning/launch gate for the current long
validation.  The detailed bank, boundary fix, acceptance/nstep tuning, and
long-run launch record is
`runbooks/generated/wv_hmc_n6_t0001_warm_bank_20260603/README.md`.

Actions:

- Use a current source pin only.
- Use predeclared `[T0,T1]`, measurement window, `W(t)`, bank, solver gate,
  `epsilon`, and `nstep`.
- Run enough seeds/cycles to detect the previous few-sigma drift without
  wasting a 12-hour production allocation.

Exit criteria:

- Four primary z-scores are not systematically drifting.
- Ratio uncertainty, seed/block stability, and flow-time histogram are
  consistent with the predeclared gate.
- Any failure is routed back to Phases B/C, not patched by post-hoc
  measurement cuts.

### Phase G. Long Production Validation

Status: completed with bounded caveat.  The readback is
`runbooks/generated/wv_hmc_n6_t0001_validation_20260603/N6_LONG_VALIDATION_READBACK_20260603.md`.

Completed actions:

- Keep cyclic snapshots and enough history for bank rebuild and window/cut
  audits.
- Save scheduler/runtime metadata for reproducibility.

Exit criteria result:

- Production packet has exact-reference observables, ratio-preserving errors,
  seed/block robustness, flow-time coverage, movement, acceptance/RG/failure
  accounting, Newton stops, runtime, source pin, and data index.

### Phase H. Matrix-Free / High-Dimensional Gate

Status: deferred until after productization closure.

Actions:

- Wire BiCGStab/matrix-free trajectory only after dense explicit-J is closed.
- Compare dense and matrix-free on identical small seeds before any
  high-dimensional run.
- Add model-provider and derivative contracts for high-dimensional models.

Exit criteria:

- Matrix-free path is numerically equivalent to dense oracle where dense is
  feasible.
- Solver failures are categorized separately from physical boundary exits.

## Non-Circular Rule

Do not call WV-HMC correct because a diagnostic failure count is low, because a
long run is expensive, or because one post-hoc measurement window has better
z-scores.  Correctness must come from invariant-measure tests, exact-reference
observables, ratio-stable uncertainty, seed/block robustness, and explicit
transition accounting.

## Immediate Next Task

Move directly to publication/productization closure: DFO-LS license/dependency
cleanup, public docs consolidation with bounded WV-HMC burn-in claim, evidence
packet, guardrails, and OSS/credit application packaging.  Do not start
matrix-free trajectory wiring before this closure.

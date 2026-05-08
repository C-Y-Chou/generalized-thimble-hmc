# Baseline Verification Matrix

Updated: 2026-05-08
Scope: planning-only baseline requirements for behavior-preserving Fortran modernization. No source edits, no jobs.

## Rule

No modernization refactor should be implemented until the affected row below has a baseline artifact and an accepted comparison rule. The comparison can be exact, tolerance-based, or contract-based, but it must be explicit before code changes.

## Baseline Levels

- B0: compile/static contract only. Suitable for comments, docs, and pure file organization plans.
- B1: deterministic unit/micro baseline. Suitable for pure mapping, residual, linear algebra, and helper refactors.
- B2: deterministic integration baseline. Suitable for flow, Newton/RATTLE step, HMC proposal, and swap behavior.
- B3: fixed-seed production smoke baseline. Suitable for Stage2/Stage3 route counters, summaries, and history contracts.
- B4: campaign-level scientific/performance baseline. Required before changing anything that can affect Stage3_4 conclusions.

## Matrix

| Area | Current entry points | Baseline level before refactor | Required preserved outputs | Comparison rule | Stage3_4 block |
|---|---|---:|---|---|---|
| ODEX core | `solve_flow.f90`: `odex_step`, `intode`, table helpers | B2 | endpoint state, error flag, accepted/rejected step metadata if exposed, fallback counters | numeric tolerance plus unchanged route/failure class | yes for constants/sequence/fallback policy |
| Flow wrappers | `flowz`, `flowzr`, `flow`, RHS mapping helpers | B2 | `z`, `jac`, inverse-flow round trip, sign/conjugation convention | tolerance-based; exact error flag behavior | yes for sign, mapping, flow direction |
| Flow rescue policy | Radau/JFNK/final-resort paths in `solve_flow.f90` | B3 | rescue success/failure counters, last-failure metadata, final-resort behavior | contract-based plus counter equality | yes |
| Newton projection | `hmc_constraints.f90`: `solve_constraint_newton*`, `solve_projected_step` | B2 | `x_new`, `Jl`, convergence flag, residual norm path if captured | tolerance-based plus same success/failure | yes for thresholds/route order |
| RATTLE step | `hmc_integrator_core.f90`: `rattle_step_core` | B2/B3 | `final_x`, `final_z`, `jacf`, final momentum, method_converged, route counters | tolerance-based plus route/counter equality | yes |
| Momentum projection | `hmc_kernels.f90`: `decompose2`, `calculate_dV` | B1/B2 | tangent/normal split, projected momentum, Hamiltonian delta trend | tolerance-based; no RNG impact | yes for formula changes |
| Quasi standard residual | `evaluate_constraint_residual` | B1/B2 | residual vector, `Jl`, proposed/flowed trace state, error flag | tolerance-based and sign/order checks | yes |
| Post-refine loss | `evaluate_constraint_residual_newton_loss`, `build_post_refine_seed_from_qn` | B1/B2 | residual vector, `Jl`, seed vector, skip/success/fail outcome | tolerance-based plus branch contract | yes |
| DFO-LS route | `run_dfo_ls_attempt`, `solve_constraint_quasi_newton` | B2/B3 | trace residuals, accepted flags, best residual, final `x_new`, counters | tolerance-based plus route/counter equality | yes |
| DFO-GN/paper route | `run_dfo_gn_attempt`, `run_dfo_gn_paper_attempt` | B2 | convergence, interpolation/geometry status if exposed, final residual | tolerance-based; classify canonical first | depends on production usage |
| Broyden/line search route | `run_quasi_newton_attempt`, Broyden/line-search modules | B2 | residual trace, alpha/backtrack, final residual, success flag | tolerance-based; classify canonical first | depends on production usage |
| Quasi route classification | `classify_quasi_failure_case`, far/near route helpers | B1/B3 | class local/mid/global, near/far, skip/light/anchor, counters | exact classification for fixtures | yes |
| Reverse gate | `qn_reverse_gate_accepts`, RG stats | B3 | candidate/pass/reject, `x/z/jac/p` reverse diffs, live slot identity on reject | exact counters plus tolerance diffs | yes |
| Metropolis acceptance | `markovchain_metropolis.f90` | B2/B3 | proposal_failed, accept flag, RNG draw order, Hamiltonian delta | exact branch sequence for fixed seed | yes |
| Stage2 local updates | `tltm_stage2_driver.run_local_updates` | B3 | slot state after accept/reject, projection failure count, accepted route census | exact counters; tolerance state values | yes |
| Swap path | `attempt_adjacent_swap`, `compute_effective_energy` | B3 | pair accept/reject counts, labels, energies, reflowed states | fixed-seed branch sequence plus tolerance energies | yes |
| Stage2 outputs | `write_stage2_summary`, history writers | B3 | summary fields, history convention, label trace, route-stat fields | contract or byte-for-byte if frozen | yes |
| Stage3 scripts | `scripts/run_stage3_3_multiseed.py`, merge/eval scripts | B4 | per-seed/aggregate reports, manifest, output paths | report schema plus scientific metrics | yes |
| Module state/thread safety | module-level `save` workspaces/counters | B2/B3 | serial output unchanged, counters unchanged | exact route/counter equality | no for docs, yes for code changes |

## Minimum Baseline Set Before First Code Refactor

1. Existing compile/test smoke: build plus `tests/test_action_derivatives.f90` and `tests/test_hamiltonian_conservation.f90` under the current standard config.
2. Flow micro baseline: fixed inputs for `flowz`, `flowzr`, and `flow`, including one round-trip and one Jacobian consistency check.
3. Newton-only HMC proposal baseline: fixed seed, quasi fallback off, record `x/z/jac`, Hamiltonian delta, proposal_ok, and solver counters.
4. QN-used proposal baseline: fixed captured or deterministic case where quasi fallback is used and accepted, including route trace and reverse gate result.
5. Failure-path baseline: at least one Newton fail to quasi, one quasi fail, one post-refine fail or skip, and one reverse-gate reject identity case if available.
6. Stage2 summary baseline: small deterministic run with no-fallback and with-fallback/RG policy, preserving summary field contract and route counters.
7. RNG-order baseline: accept/reject sequence for a tiny deterministic local-update run.

## Existing Assets To Reuse

- `tests/test_action_derivatives.f90` for action/gradient/Hessian/Hessian-vector correctness.
- `tests/test_hamiltonian_conservation.f90` for HMC conservation trend and solver stats.
- `scripts/benchmark_hamiltonian.sh` for performance visibility.
- `scripts/check_autodiff_integrity.sh` for derivative integrity.
- `scripts/check_online_geometry_alignment.py` for geometry/audit support.
- `output/tests/*` existing reports are historical/reference evidence only. They must not become official modernization baselines; fresh baselines will be generated after Stage3_4/TLTM judgment completes.
- `codex/knowledge/FULL_PROGRAM_MAP_CHECK.md` for current proposal symmetry/volume audit status.

## Things Safe Before Stage3_4 Completion

- Documentation, maps, and baseline design.
- Adding tests that do not change production code paths or production outputs.
- Read-only audits of current source and outputs.
- Creating wrappers or scripts only if they are not used by production jobs and do not mutate production outputs.

## Things To Defer Until Stage3_4 Completion

- Any change to solver route order, thresholds, fallbacks, reverse gate, final resort, or Metropolis acceptance.
- Any change that can alter RNG draw order.
- Any change to Stage2 summary schema consumed by Stage3 scripts.
- Any change to flow integration constants, step sequence, tolerances, or rescue policy.
- Large module splits that require touching source code without the baseline set above.

## Discussion Needed Before Implementing Baselines

- Choose the official small deterministic configs for ODEX/flow, Newton-only, QN-used, and Stage2 smoke.
- Decide whether Stage2 summary output must be byte-for-byte frozen or schema-frozen.
- Resolved: fresh official baselines will be generated after Stage3_4/TLTM judgment completes; existing `output/tests` artifacts remain historical/reference evidence only.
- Decide how strict future comparisons should be: bitwise where feasible, tolerance-based for numerical arrays, exact for route counters and branch choices.

## Baseline Source Decision - 2026-05-08
- Existing `output/tests` artifacts are historical/reference evidence only.
- They should not be promoted as the official modernization baseline.
- Official modernization baselines must be regenerated after Stage3_4/TLTM judgment is complete, using clean, explicitly selected configs and comparison rules.
- Until then, modernization remains planning-only or limited to non-production test design.

## Reverse Gate Decision - 2026-05-08
- Reverse gate is a permanent algorithmic requirement for the production/publishable p28 route.
- It is not merely a temporary debug guard or optional diagnostic mode.
- Modernization must preserve reverse-gate semantics, tolerance behavior, Jacobian comparison, replay accounting suppression, and live-slot identity on reject.
- Any future wrapper should expose this as part of the canonical p28 algorithm contract, not as an experimental add-on.

## Flow Backend Direction Decision - 2026-05-08
- Tentative long-term publishable target: ODEX-only flow backend.
- Radau rescue, fixed/chunked Radau rescue, JFNK support paths, and ODE final-resort acceptance are legacy robustness layers/deletion candidates.
- Do not remove or change them before Stage3_4/TLTM judgment completes.
- After judgment, regenerate clean baselines, record current rescue counters, and run an ODEX-only comparison before deletion.
- If ODEX-only failure rate is unacceptable, prefer improving ODEX/step control/failure handling over preserving a hidden secondary integrator stack.

## Thread-Safety / Reentrancy Decision - 2026-05-08
- Long-term modernization target: support in-process parallelism/OpenMP-capable TLTM execution.
- Hidden module-level `save` workspaces, counters, RNG state, traces, and solver policies should be progressively moved behind explicit context/workspace objects.
- Short-term production behavior remains serial/process-level until Stage3_4/TLTM judgment and fresh baselines are complete.
- No source-level context refactor should start until affected baseline rows are covered.
- Final wrapper design should make per-run/per-replica state explicit enough for deterministic parallel execution.

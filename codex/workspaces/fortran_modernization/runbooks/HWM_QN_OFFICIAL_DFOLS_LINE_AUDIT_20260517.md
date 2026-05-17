# HWA-QN Official DFO-LS Wrapper Line Audit

Date: 2026-05-17 JST

Status: implemented and focused-test passed. M4 pending in the current combined
HWA batch.

## Purpose

This packet audits the handwritten QN/BTN wrapper around the official DFO-LS
package. The official package itself is not a handwritten TLTM algorithm; the
audited handwritten surfaces are:

- BTN residual and actual correction `Jl`;
- initial guess from the base Jacobian;
- official DFO-LS callback/context bridge;
- package-success versus TLTM residual/certification gate;
- final inverse-flow recovery and downstream final-flow/reverse-gate boundary;
- trace and failure classification used by HMC diagnostics.

## Claim Boundary

Current active route:

```text
strict Newton -> one official DFO-LS package attempt -> TLTM residual
certification -> final flow -> reverse gate -> Metropolis/stay-put
```

Package success alone is not proposal correctness. A QN candidate is accepted
only if the TLTM residual is finite and within `cttol`, the certification
residual also passes, the final state can be recovered, and the outer RATTLE
step later passes strict final-flow and reverse-gate gates.

## Source Scope

- `src/sampler/quasi_newton_linear_solver.f90`
- `src/sampler/quasi_newton_solver.f90`
- `src/external/official_dfols_c_bridge.c`
- QN block in `src/sampler/hmc_integrator_core.f90`
- `tests/test_retained_core_qn_route_contract.f90`

## Line-Level Map

| Area | Source lines | Classification |
| --- | --- | --- |
| Initial BTN seed | `quasi_newton_linear_solver.f90:13-77` | matched seed convention, with regularized fallback |
| QN contexts/policy | `quasi_newton_solver.f90:16-105`, `125-240` | context/state ownership, not paper proof |
| Official route wrapper | `242-352` | one official package attempt plus TLTM gates |
| Package attempt and best candidate | `367-532` | package mechanism plus strict TLTM certification |
| Python C callback | `534-629` | bridge glue; failure propagates as package failure |
| Callback context setup/clear | `631-714` | context ownership; direct API guard surface |
| Candidate certification | `727-807` | handwritten TLTM acceptance gate |
| BTN residual | `898-994` | matched BTN residual/correction core |
| Trace/stat helpers | `996-1423` | diagnostics and route evidence |
| Attempt capture | `1434-1616` | diagnostics/evidence only |
| Official C bridge | `official_dfols_c_bridge.c:1-279` and following package-call logic | external package bridge; TLTM owns residual and acceptance gate |
| HMC QN boundary | `hmc_integrator_core.f90:358-546` | QN failure is proposal construction failure/stay-put |

## Reference Mapping

BTN variables use the paper convention:

```text
xi(1:n)     = b
xi(n+1:2n) = a
ztrial      = z + Delta z - J*(a + i b)
residual    = [ Imag(flowzr(ztrial)), a ]
Jl          = real_pack(-J*(a+i*b))
```

Source readback:

- `initial_guess_from_jacobian` solves `J dz = Delta z`, then sets
  `xi1 = Im(dz)`, `xi2 = Re(dz)`, matching the BTN paper-variable seed.
- `evaluate_constraint_residual_with_role` forms
  `-matmul(jac, xi(n+1:) + i*xi(1:n))`, packs it into `Jl`, evaluates
  `flowzr`, and returns `[aimag(flowzr(ztrial)), xi(n+1:)]`.
- `certify_candidate_if_within_tol` re-evaluates the residual in certification
  role and only accepts finite residuals within tolerance.
- `recover_converged_flowed_state` reconstructs `z + del_z + Jl`, runs
  `flowzr`, and gives the recovered real seed state to the outer RATTLE final
  flow. The final `flow(...)` and reverse gate remain outside the QN wrapper.

## Source Hardening

Implemented in `src/sampler/quasi_newton_solver.f90`:

- `solve_constraint_quasi_newton` now validates direct API dimensions and
  tolerance before allocating solver arrays or assigning `x_new = xt`;
- `run_official_dfols_attempt` now checks output shape before assigning
  stay-put `x_new`;
- `evaluate_constraint_residual_with_role` now guards `jac` dimensions before
  the BTN `matmul`.

These are direct API hardenings. The normal HMC/RATTLE caller already passes
valid shapes and positive `cttol`.

## Proof-Test Evidence

Focused test passed with the embedded official package:

```text
TLTM_OFFICIAL_DFOLS_PYTHONPATH=<.venv-dfols site-packages> make -C build test_retained_core_qn_route_contract
```

Readback:

```text
btn_paper_residual ok=T jl_err=0 fq_err=0
official_qn_route_policy ok=T npt=4 maxfun=250 noise=T ierr=F
official_qn_route_trace ok=T available=T proposal_count=2 has_eval_ok=T
official_qn_package_success ok=T expect=T ierr=F has_accepted=T
qn_context_trace_isolation ok=T
qn_diagnostics_context_isolation ok=T
qn_api_guard_outputs ok_tol=T ok_jac=T ok_xsize=T ok_residual=T
official_qn_route_census_summary ok=T route10_cases=3 success_cases=3 accepted_cases=3 expect_package_success=T
```

The test covers:

- BTN residual formula and `Jl` reconstruction;
- official-only route policy;
- package-success route census at fixed step sizes;
- run-owned QN trace and diagnostics context isolation;
- direct invalid tolerance, invalid Jacobian shape, output-size mismatch, and
  residual Jacobian-shape guard outputs.

## Findings

| ID | Finding | Classification | Handling |
| --- | --- | --- | --- |
| HWA-QN-CORE-001 | BTN residual, paper-variable seed, and actual correction `Jl` match the selected p28 BTN/backflow formulation. | matched core | Closed with retained-core residual and route tests. |
| HWA-QN-BRIDGE-001 | Active solver route uses the official DFO-LS package only; internal DFO-like helpers are deleted. | selected external package policy | Closed for current route; package version/provenance remains a bridge/product dependency. |
| HWA-QN-GATE-001 | Package result is accepted only through TLTM residual certification; package success alone is not enough. | project certification policy | Keep. Reopen only if certification tolerance, final-flow, reverse-gate, or callback role changes. |
| HWA-QN-API-001 | Direct API output-shape and invalid-input guard surfaces were weaker than the RATTLE/NT contracts. | API hardening | Patched and focused-tested. |
| HWA-QN-DIAG-001 | Near/mid/far failure classification and trace summaries are diagnostics, not retry policy after F19. | diagnostics boundary | Keep in HWA-DIAG/F10/F11; do not cite as paper proof. |
| HWA-QN-CBRIDGE-001 | The C bridge depends on Python C API, package import path, and `dfols.solve` callable behavior. | external bridge/product boundary | Keep official package provenance gates; HWA-BRIDGES should cover threaded/product bridge concerns later. |

## F8 Statement

This is behavior/API relevant for invalid direct QN calls: invalid tolerance,
wrong output shape, and invalid Jacobian shape now fail before deeper package
or residual work and return explicit failed/stay-put-compatible outputs where
shape allows.

The valid official DFO-LS route, BTN residual formula, TLTM certification gate,
final-flow/reverse-gate policy, and Metropolis stay-put semantics are intended
to be unchanged.

No local Stage2/Stage3 screen was run. If this patch is used for
production-comparison sync/regeneration, freeze a clean commit and rerun the
direct `npt5_r0055` PBS wrapper or record a narrower affected-baseline decision.

## Closure

HWA-QN is closed for the current official DFO-LS wrapper scope:

- BTN residual and initial seed match the selected formulation;
- official package bridge is the only active solver backend;
- TLTM certification gates are documented and tested;
- direct API hardening is implemented and focused-tested.

Reopen HWA-QN only if package/preset/callback policy, BTN residual, seed
mapping, TLTM residual gate, final-flow/reverse-gate certification, trace
classification semantics, or public route schema changes.

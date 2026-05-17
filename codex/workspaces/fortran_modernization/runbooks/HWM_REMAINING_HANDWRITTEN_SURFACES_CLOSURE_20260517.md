# Remaining HWA Surfaces Closure Packet

Date: 2026-05-17 JST

Status: implemented and M4-passed for the remaining handwritten
source-contract scope.

## Scope

This packet closes the ODEX-equivalent audit queue for handwritten surfaces not
already covered by the ODEX, RATTLE/HMC, NT, QN, Metropolis, flow/model/action,
and Stage2/RNG packets:

- Stage1 local-update driver and summary path:
  `src/sampler/tltm_stage1_driver.f90`, `src/apps/run_tltm_stage1.f90`.
- Diagnostics/status/counter event normalization:
  `src/sampler/tltm_types.f90`, `src/sampler/constraint_solver_stats.f90`,
  and the Stage1/Stage2 summary/counter writers.
- Config/env/tolerance guardrails:
  `src/config/param_mod.f90`, `src/config/runtime_env_mod.f90`.
- Current I/O/schema surfaces:
  `src/sampler/markovchain_io.f90`, `src/apps/evaluate_expectations.f90`,
  Stage1/Stage2 summaries, and v1alpha sidecars.
- Numerical helpers:
  `src/core/utils.f90`, `src/sampler/hmc_kernels.f90`,
  `src/core/lapack_fallback.f90`, `src/core/perf_profile.f90`.
- Optional C bridges:
  `src/external/official_dfols_c_bridge.c`,
  `src/external/sundials_cvode_bridge.c`.
- Legacy triggers/names:
  `istest`, `testmom`, `eo`, `rattle2`, `decompose2`, and old compatibility
  route labels/envs.

This is a source-contract and audit closure packet. It is not production
dataset regeneration, not final public schema cleanup, and not a single/mixed
precision certification.

## Source Readback

### Stage1

Stage1 is local-update-only TLTM: initialize replicas, run Metropolis/HMC local
updates, measure phase, and write a summary. It has no swap kernel. Its
numerical kernel is the already-audited Metropolis -> HMC/RATTLE -> Newton/QN
-> flow/model path. Stage1 still uses the explicit MT95 per-replica RNG
contract, not Stage2 kernel RNG v2. Therefore Stage1 is closed for current
source correctness as a validation/local-update surface, but it is not promoted
as a production publication surface without a separate Stage1 product decision.

No local TLTM Stage1/Stage2 simulation screen was run for this packet.

### Diagnostics

`tltm_local_transition_event_t` is the typed event source for local transition
counters. Its status schema/version/counter denominator are fixed by F4 for the
pre-redo gate. The broader flow, QN, reverse-gate, and failure-capture counters
remain engineering diagnostics: they are evidence helpers, not mathematical
paper proofs.

### Config And Tolerance

The active correctness baseline remains strict double precision with
`abs_tol=rel_tol=3e-14` and positive constraint tolerance in the canonical PBS
wrappers. Future single/mixed precision or weaker tolerance profiles remain
F20 product modes requiring separate certification. This packet only hardens
invalid config/env inputs so they fail closed or preserve defaults.

### I/O And Schema

The current Markov-chain binary writer is a direct stream writer for
`x`, `z`, and `phi`. Stage1/Stage2 summaries and Stage2 v1alpha sidecars are
current evidence/product scaffolding. The final public API/field cleanup remains
M6/product work; it is not a hidden numerical bug in the current route.

### Helpers

The real/complex packing helpers implement the standard interleaved convention:
complex vector `(a+i b)` maps to `[a,b]`, complex matrix maps to a real block
with `[[Re,-Im],[Im,Re]]`, and flattened complex matrices use row-major
interleaving. `log_determinant` uses LU plus pivot-sign correction and the
principal complex-log branch. `decompose2` solves the real-block Jacobian system
and splits a real momentum into tangent and normal components.

### Bridges

The official DFO-LS C bridge only calls the official Python package and returns
package metadata. TLTM owns the residual, residual gate, final flow, reverse
gate, and Metropolis decision. The SUNDIALS CVODE bridge remains
disabled-by-default comparison-only evidence.

### Legacy

`istest/testmom` are test-only deterministic momentum hooks; production keeps
`istest=false`. `eo` and related old flags are legacy compatibility/analysis
switches. `rattle2` and `decompose2` are compatibility names around audited
current routines. Renaming/deleting these belongs to F9 product hygiene with
exact-output or affected-baseline protection, not to the paper-correctness
claim itself.

## Findings And Handling

### HWA-HELPERS-001: Invalid helper outputs could be undefined

Finding: direct calls to packing/unpacking helpers and `log_determinant` printed
errors for invalid shape/singularity but did not consistently initialize output
buffers on failure.

Handling: implemented source hardening in `src/core/utils.f90`.

- `map_to_real_mat`, `map_to_complex_mat`, `complex_to_real`,
  `real_to_complex`, `map_to_real`, and `map_to_complex` now zero their output
  before invalid-shape returns.
- `log_determinant` now initializes `log_det=0`, rejects non-square and
  nonfinite matrices before LU, and preserves `log_det=0` on LU failure.

### HWA-HELPERS-002: Projection helpers assumed upstream shape correctness

Finding: `decompose2` assumed `b/x/au/av` dimensions matched the real-block
Jacobian dimension. `calculate_hamiltonian` warned on a `z/p` size mismatch but
still computed a value from the wrong momentum length.

Handling: implemented source hardening in `src/sampler/hmc_kernels.f90`.

- `decompose2` now fail-fast guards vector and Jacobian dimensions, returns
  `ierr=.true.`, and zeroes `x/au/av` on invalid direct calls.
- `calculate_hamiltonian` returns `huge(1.0_dp)` on momentum-size mismatch,
  making invalid direct use visibly non-acceptable to callers.

### HWA-CONFIG-001: Nonfinite env/config inputs could silently survive

Finding: real env parsing and flow-ladder parsing could accept nonfinite values
or leave comparisons ineffective against NaN. Top-level parameter validation did
not explicitly require finite tolerances.

Handling: implemented source hardening in `runtime_env_mod`, `param_mod`,
`tltm_stage1_driver`, and `tltm_stage2_driver`.

- Real env overrides only apply when parsed values are finite.
- Real-list env parsing rejects nonfinite entries.
- Parameter validation now requires finite positive trajectory length,
  nonnegative finite initial flow time, finite nonnegative ODE tolerances with
  at least one nonzero component, and finite positive constraint tolerance.
- Stage1/Stage2 flow-ladder and init-sigma controls now require finite,
  physically valid values.

### HWA-DIAG-001: Accepted event plus proposal-failed was contradictory

Finding: the direct typed event constructor accepted contradictory inputs such
as `accepted=.true.` and `proposal_failed=.true.`. Valid route callers do not
produce that combination, but the public helper contract should canonicalize it.

Handling: `make_tltm_local_transition_event` now makes acceptance dominant:
accepted events always have `transition_status=metropolis_status_accepted` and
`proposal_failed=.false.`. Focused RG/accounting tests cover this contract.

### HWA-BRIDGE-001: C bridge failure outputs should be stay-put

Finding: direct C bridge calls initialized scalar metadata on failure, but
failure before package/CVODE completion did not guarantee candidate output
arrays held a safe value.

Handling: both C bridges now copy input state to output after basic pointer and
size validation, so package-unavailable, package-error, invalid-tolerance, and
CVODE-unavailable paths are stay-put at the bridge boundary. The Fortran
wrappers already impose stricter TLTM-level gates.

### HWA-STAGE1/IO/LEGACY-001: No current-route math bug, but product cleanup remains

Finding: Stage1, current I/O/schema, and legacy names/triggers are not hidden
paper-correctness blockers for the active Stage2 production route after the
core kernel audits. They are still product/API hygiene surfaces.

Handling: no behavior-changing source cleanup in this packet. Keep final field
cleanup, wrapper/API cleanup, legacy trigger deletion/renaming, and Stage1
publication promotion as separate F9/M6/F20 work with exact-output or
affected-baseline protection.

## Proof Tests

Passed locally:

```bash
make -C build test_numerical_helper_contracts
make -C build test_tltm_swap_kernel_contract
make -C build test_retained_core_rg_reject_identity
make -C build test_odex_flow_jacobian_contract
make -C build test2
make -C build test_tltm_rng_contract
make -C build test_mt95_state_contract
make -C build test_perf_profile_context_contract
make -C build test_sundials_cvode_backend_contract
make -C build test_retained_core_newton_contract
make -C build test_retained_core_rattle_rg_contract
make -C build test_official_dfols_preset_contract
TLTM_OFFICIAL_DFOLS_PYTHONPATH=.venv-dfols/lib/python3.11/site-packages make -C build test_retained_core_qn_route_contract
make -C build modernization_guardrails
```

Key checks:

- helper pack/unpack roundtrips;
- invalid helper output zeroing;
- log-determinant singular/non-square failure output contract;
- `decompose2` valid tangent/normal split and invalid-shape fail-closed output;
- Hamiltonian momentum-size guard;
- Stage2 effective-energy and phase mismatch guards;
- typed local-transition event canonicalization;
- existing RATTLE/NT/QN/flow/model/Stage2/RNG proof tests still pass.
- full M4 modernization guardrails pass with this combined HWA batch.

## Current Scope Closure

HWA-STAGE1, HWA-DIAG, HWA-CONFIG, HWA-IO, HWA-HELPERS, HWA-BRIDGES, and
HWA-LEGACY are closed for the current source-contract/paper-correctness audit
scope.

Reopen if any of the following change:

- Stage1 is promoted to a publication/product route;
- public status/counter/schema semantics change;
- final wrapper/API/output-field cleanup changes behavior or files;
- precision/tolerance profiles move beyond strict double baseline;
- bridge package versions, callback semantics, or threading assumptions change;
- legacy hooks are deleted or renamed;
- productization claims include OpenMP/thread-safe model/cache/config state.

# HWM-RATTLE/HMC Proof-Test And API Hardening

Date: 2026-05-17 JST

Status: implemented and M4-passed.

## Purpose

This packet implements the source-facing part of the HWM-RATTLE/HMC audit after
the line-audit and derivation packets:

- keep HWM-RATTLE-001 as rejection-as-stay-put project policy;
- harden failed direct `rattle_step_core` outputs after valid shape checks;
- harden failed warmup `rattle2` / `integrate_hmc_warmup` outputs;
- prove the HMC proposal status to Metropolis transition-status mapping;
- preserve the successful RATTLE/RG and Newton/QN retained-core contracts.

This is not a switch to the paper momentum-reflection continuation route.

## Source Changes

`src/sampler/hmc_integrator_core.f90`

- validates `jacf` together with `final_x` and `final_z`;
- initializes `final_x = state_x`, `final_z = state_z`, and `jacf = jaci`
  immediately after valid shape checks;
- routes late failure exits through `abort_failed_step(status)`, which resets
  `final_x/final_z/jacf`, marks `method_converged = .false.`, publishes the
  optional step status, releases the reverse-gate momentum buffer, and closes
  the profiler scope;
- preserves reverse-gate diagnostic printing before the failed output reset.

`src/sampler/hmc.f90`

- initializes warmup `jacf = jaci` with the stay-put output buffers;
- makes the warmup `abort_with_failure()` path reset
  `final_x/final_z/jacf` and mark the final Hamiltonian unavailable.

`tests/test_retained_core_rg_reject_identity.f90`

- adds a direct `rattle_step_core` reverse-gate rejection stay-put test;
- adds a warmup failure-output stay-put test;
- covers every current HMC proposal status in
  `metropolis_status_from_hmc_status`.

## Proof-Test Evidence

Passed locally:

```text
make -C build test_retained_core_rg_reject_identity
make -C build test_retained_core_rattle_rg_contract
make -C build test_retained_core_newton_contract
TLTM_OFFICIAL_DFOLS_PYTHONPATH=<.venv-dfols site-packages> make -C build test_retained_core_qn_route_contract
make -C build modernization_guardrails
git diff --check
```

Key focused readback:

```text
direct_core_rg_reject_stay_put ok=T found_reject=T status=8 dx/dz/dj 0
warmup_failure_output_reset ok=T found_failure=T dx/dz/dj 0
hmc_to_metropolis_status_mapping ok=T output_size=6 reverse_gate=3 success=2 initial_projection=2 step_failed=2 no_progress=2 final_projection=2 constraint=2 final_flow=2 force=2
```

`modernization_guardrails` passed and wrote the usual M4 artifacts under
`output/tests/m4_guardrails`.

## F8 Statement

This is behavior/API relevant for direct failed-output calls to
`rattle_step_core` and warmup `rattle2`: after valid output shapes, failed calls
now return explicit stay-put `x/z/J` buffers instead of leaving candidate
buffers visible on some late failures.

The accepted live Metropolis transition contract is unchanged in intent:
proposal failures, reverse-gate rejection, invalid Hamiltonian, invalid
Delta-H, and ordinary finite Metropolis rejection are stay-put transitions.
Focused tests confirm the live public outputs still obey that policy.

No local Stage2/Stage3 simulation screen was run, following the current rule
that simulation screens go through remote PBS. Before using this patch for
production-comparison sync/regeneration, freeze a clean commit and rerun the
direct `npt5_r0055` PBS wrapper or explicitly record a narrower affected-baseline
decision.

## Remaining Boundaries

Closed for current HWA-RATTLE scope:

- successful-core RATTLE formula/sign/projection readback;
- rejection-as-stay-put project policy;
- direct core failed-output API;
- warmup failed-output API;
- HMC proposal status to Metropolis transition-status mapping.

Still separate HWA rows, not RATTLE closure:

- HWA-NT: simplified Newton controller constants and failure predicates;
- HWA-QN: official DFO-LS bridge wrapper, TLTM residual gate, final-flow and
  reverse-gate certification;
- HWA-MODEL/HWA-FLOW: action, derivative, Hessian/Jacobian, and branch
  provenance;
- HWA-DIAG: broader status/counter/schema semantics;
- HWA-LEGACY: `istest/testmom`, `eo`, `rattle2` naming, and compatibility
  triggers.

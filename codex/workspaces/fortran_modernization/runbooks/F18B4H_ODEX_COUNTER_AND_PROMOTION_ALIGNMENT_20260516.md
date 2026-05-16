# F18b.4h ODEX Counter and Promotion Alignment

Date: 2026-05-16 JST

Status: implemented, focused-tested locally, post-B anchor updated, and M4
passed.

Scope:

- Resolve `HODEX-LB-002`: `odex_result%accepted_steps` now counts accepted
  endpoint steps, not total attempts, for the handwritten ODEX endpoint path.
- Resolve `HODEX-LB-003`: accepted promotion next-step update now uses the
  Hairer-style work ratio `A(new K)/A(old K)` instead of the previously mutated
  index ratio `A(old K + 2)/A(old K + 1)`.

## Source Changes

Files:

- `src/physics/odex_backend.f90`
- `tests/test_odex_controller_alignment_spec.f90`
- `tests/test_odex_backend_package_contract.f90`

Counter handling:

- `odex_integrate_endpoint` and `odex_integrate_endpoint_context` now maintain
  an explicit local `accepted_steps` counter.
- The counter increments only when `er1 < 1.0_dp` and the endpoint step is
  accepted into `workspace%ystate`.
- Success and failure result records now receive this accepted-step count rather
  than `step_count` or `step_count - 1`.
- `rejected_steps` semantics are intentionally left as the existing TLTM result
  surface for this patch.

Promotion handling:

- Added `odex_hairer_promotion_step` and public observer
  `odex_observe_hairer_promotion_step`.
- Both legacy and context-aware `odex_step` promotion branches now compute:

```fortran
h = h_candidate*A(k_next)/A(k_previous)
```

  when `k_next > k_previous`, matching the Hairer `KOPT=KC+1` next-step ratio
  for this endpoint controller family.

## Contract Coverage

Focused readback:

```text
make -C build test_odex_controller_alignment_spec \
  test_odex_controller_observation_contract \
  test_odex_result_contract \
  test_odex_backend_package_contract
```

Observed passing evidence:

- `hairer_route_skeleton ... promote=T`
- `package_stability_surface ok=T status=0 accepted=70 rejects=76 stability=76`
- existing signed endpoint, max-step failure, h-min failure, result mapping, and
  package endpoint accuracy checks still pass.

Full guardrail readback:

```text
make -C build modernization_guardrails
```

Initial M4 correctly tripped the deterministic post-B Stage2 summary anchor:

```text
stage2_summary expected ecd5973ff2f578af962a62b2fb8dd94b183158726b88f0674de4986dfbd668d2
stage2_summary actual   998434b44cdb8e1f7c9eef9638fa19c21a08a94cc6d656ff55a8b1d39594736e
```

The anchor repeat check was stable (`run_a == run_b`), Stage1 summary and
Stage2 label-trace hashes were unchanged, and the available normalized
before/after readback differed only in the final printed digits of the Stage2
summary `last_accept_prob`:

```text
1.067747828730300E-002 -> 1.067747828730291E-002
```

The post-B anchor was updated through:

```text
python3 codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py \
  --repo-root . --fc gfortran --ldflags '' \
  --output-root output/tests/f18b4h_post_b_anchor_update --update-reference
```

Updated reference:

```text
stage2_summary_normalized_sha256=998434b44cdb8e1f7c9eef9638fa19c21a08a94cc6d656ff55a8b1d39594736e
```

Full M4 then passed with artifacts under `output/tests/m4_guardrails`.

## Behavior Boundary

`HODEX-LB-002` is a public diagnostic/API counter correction.  It is not a
trajectory change.

`HODEX-LB-003` is an intentional controller behavior correction on accepted
promotion branches.  It is not a general claim that the live handwritten ODEX
outer loop is now full Hairer ODEX.  Follow-up patch
`F18B4I_ODEX_INVALID_RHS_CLASSIFICATION_20260516.md` resolves invalid-RHS
classification.  Remaining line-audit findings still include minimum-order
policy, first/last-step and `KOPT` state, reject-history coupling,
`SCAL`/`ERROLD`/`ATOV`, `HOPTDE`, h-min/status, and stability policy.

Before using this patch as a production-comparison regeneration source, freeze a
clean commit and run the required F8/M4 plus affected-baseline or explicitly
approved narrower baseline gate.

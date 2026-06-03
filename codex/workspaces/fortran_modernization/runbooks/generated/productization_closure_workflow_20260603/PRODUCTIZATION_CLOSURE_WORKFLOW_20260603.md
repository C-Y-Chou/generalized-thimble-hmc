# Productization Closure Workflow - 2026-06-03

Purpose: freeze the current repository workflow after the dense WV-HMC
debugging/tuning phase.  The immediate objective is no longer to expand the
algorithm surface.  It is to wait for the current Stephanov `n=6` long WV-HMC
validation, analyze it with the predeclared gates, and then close the repository
into a product-ready package suitable for an external OSS/credit application.

## Current State

The current-source Stephanov `n=6` dense WV-HMC long validation completed.  The
readback is recorded in
`runbooks/generated/wv_hmc_n6_t0001_validation_20260603/N6_LONG_VALIDATION_READBACK_20260603.md`.
It is not a clean all-cycle pass because the first half shows an initial-bank
transient, but the post-burn-in cuts are compatible with the exact references.
This is treated as a bounded productization caveat, not as a reason to reopen
algorithm expansion before publication.

Current working expectation:

- no new matrix-free/BiCGStab trajectory work before the dense validation is
  read back;
- no DFO-LS/`withfb` production work; TLTM keeps `nofb` canonical and
  `withfb` is legacy diagnostic only;
- no new broad parameter search unless the long validation exposes a specific
  correctness failure;
- all simulation launches remain cluster/scheduler-gated, not local production
  runs;
- proceed directly to productization closure, with WV-HMC burn-in handling and
  claim boundaries documented in the public sampler status.

## Immediate Gate: n=6 Long Validation

Required readback after the long validation completes:

- exact-reference ratio observables for chiral condensate and number density,
  with Re/Im z-scores;
- ratio-preserving uncertainty, with seed/block stability;
- flow-time histogram and high-flow coverage;
- state movement and acceptance/rejection accounting;
- RG/failure/construction-failure accounting without using failure count as a
  correctness criterion;
- Newton stop/fail-fast diagnostics;
- zero-measurement seed check;
- snapshot/restart availability;
- runtime and source-pin metadata.

Pass condition:

- no stable systematic drift in the four primary observable z-scores;
- no hidden sample-selection or zero-measurement pathology;
- flow-time coverage is compatible with the declared `W(t)`/interval policy;
- movement and transition accounting are non-sticky and reproducible;
- any remaining warnings are documented as nonblocking diagnostics.

Fail condition:

- route back to the dense WV-HMC correctness workflow, specifically the
  transition-kernel, measurement, bank, or parameter gate implicated by the
  readback;
- do not start matrix-free work as a workaround;
- do not revive DFO-LS/`withfb` as a workaround.

## Productization Closure Sequence

After the `n=6` long validation readback, execute the productization closure in
this order.

1. Freeze sampler status.
   - TLTM: canonical `nofb` production path.
   - TLTM `withfb`/DFO-LS: legacy diagnostic, default-off, not product
     dependency.
   - WV-HMC: dense explicit-J sibling sampler status based on the completed
     `n=6` readback.
   - Matrix-free/BiCGStab: deferred optimization/high-dimensional roadmap item.

2. Clean licensing and dependency surface.
   - Remove DFO-LS from active requirements, build/test paths, and product
     docs.
   - Update `THIRD_PARTY_NOTICES.md` and `LICENSE_POLICY.md` so active
     dependencies are separated from historical DFO-LS evidence.
   - Keep historical DFO-LS runbooks/data only as archive/evidence, not as an
     active product dependency.

3. Consolidate product documentation.
   - Create/update root `README.md`.
   - Populate the stable docs set from
     `PRODUCT_DOCS_CONSOLIDATION_DESIGN_20260528.md`:
     `INSTALL.md`, `USER_GUIDE.md`, `MODEL_PROVIDER.md`, `SAMPLERS.md`,
     `CONFIGURATION.md`, `OUTPUTS_AND_RESTART.md`, `DEVELOPMENT.md`,
     `REFERENCES.md`, and `ARCHIVE_INDEX.md`.
   - Keep campaign-specific runbooks internal or archived.
   - Public docs must state sampler status and claim boundaries explicitly.

4. Build the product evidence packet.
   - Include TLTM canonical status and frozen `nofb`/`withfb` criterion closure.
   - Include WV-HMC dense validation readback.
   - Include model-provider and observable contracts.
   - Include guardrail/test commands and source-pin provenance.
   - Include dataset/archive index and reproducibility notes.

5. Run product guardrails.
   - `git diff --check`.
   - Build/test targets needed by the public README.
   - Script/evidence audit if docs or evidence paths move.
   - WV-HMC math/constraint tests only if source or build paths changed.

6. Prepare OSS/credit application package.
   - One-page project summary.
   - What has been implemented and validated.
   - Why compute credits are needed.
   - Current limitations and deferred work.
   - Roadmap: high-dimensional models, matrix-free/BiCGStab, performance
     optimization, and broader validation.

## Pre-Publication Blocking Checklist

These are the only blocking items before the credit/application-ready
publication package.

| Order | Item | Status | Exit artifact |
| ---: | --- | --- | --- |
| 1 | Finish current Stephanov `n=6` long dense WV-HMC validation. | completed with bounded caveat | `runbooks/generated/wv_hmc_n6_t0001_validation_20260603/N6_LONG_VALIDATION_READBACK_20260603.md` |
| 2 | Decide WV-HMC publication claim level from that readback. | pending | sampler-status statement for README and `docs/SAMPLERS.md`; dense explicit-J WV-HMC after burn-in, not high-dimensional/matrix-free readiness |
| 3 | Remove DFO-LS from active dependency/license/install/build/test surface. | pending | updated `THIRD_PARTY_NOTICES.md`, `LICENSE_POLICY.md`, requirements/build/test/docs audit |
| 4 | Consolidate public docs. | pending | root `README.md` plus stable `docs/` set from `PRODUCT_DOCS_CONSOLIDATION_DESIGN_20260528.md` |
| 5 | Build product evidence packet. | pending | compact evidence/index packet linking TLTM closure, WV-HMC validation, model-provider contract, and reproducibility metadata |
| 6 | Run final guardrails. | pending | `git diff --check`, documented build/test commands, script/evidence audit if paths move |
| 7 | Prepare OSS/credit application package. | pending | one-page project summary, compute-need statement, roadmap, limitations |

Anything outside this table is not a pre-publication blocker unless the `n=6`
readback exposes a concrete correctness failure.

## Deferred Until After Productization

These are not blockers for the credit-application-ready package:

- true matrix-free/BiCGStab trajectory wiring;
- high-dimensional production optimization;
- DFO-LS/`withfb` revival;
- aggressive source slimming beyond behavior-preserving hygiene;
- broad public-doc archive relocation that risks breaking scripts before the
  product package is frozen.

## Non-Negotiable Boundaries

- Do not adjust final decision gates after reading the long validation.
- Do not use lower failure count as an algorithmic success criterion.
- Do not use post-hoc flow-time cuts as proof of production correctness.
- Do not mix correctness fixes, docs cleanup, and archive moves in a way that
  hides behavior changes.
- Do not claim WV-HMC high-dimensional readiness until matrix-free/BiCGStab is
  implemented and validated.

## Completion Definition

The repository is ready for the OSS/credit application when:

- the `n=6` long validation readback is complete and passes or has a clearly
  bounded nonblocking caveat;
- public docs present one coherent build/run/validation story;
- DFO-LS is absent from active dependency/license surface;
- historical evidence is indexed but not confused with product docs;
- current sampler status is explicit;
- the remaining roadmap is clearly labeled as future work rather than current
  capability.

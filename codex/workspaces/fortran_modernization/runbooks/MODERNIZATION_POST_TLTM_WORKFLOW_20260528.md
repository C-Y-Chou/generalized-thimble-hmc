# Modernization Post-TLTM Workflow

Date: 2026-05-28

Scope: repository-level workflow after the Stephanov `n=6`, `t_high=0.03`
TLTM campaign established enough information to close the TLTM design direction
and prepare, later, for WV-HMC as a second sampler.

This is a planning and governance document only.  It does not move data, delete
files, change production defaults, or implement WV-HMC.

## Authoritative Inputs

Use these documents as the current source of truth:

- `TLTM_CANONICAL_SOP_20260528.md`: canonical TLTM production workflow.
- `STEPHANOV_N6_DATASET_ARCHIVE_GROUPS_20260528.md`: four dataset groups and
  archive timing.
- `runbooks/generated/withfb_criterion_framework_20260527/interim_criterion_framework_v1.md`:
  frozen interim-to-final `nofb`/`withfb` decision gates.
- `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`: paper-derived WV-HMC
  algorithm contract.
- `WV_HMC_MATH_PHYSICS_REVIEW_20260529.md`: independent convention, typo-risk,
  and validation review for the WV-HMC formulas.
- `WV_LEGACY_RESIDUE_AUDIT_20260528.md`: stale WV residue audit.

## Earlier Handoff TODO Coverage

This section is the explicit crosswalk from earlier modernization handoff,
entry-gate, open-item, and acceleration TODOs into the post-TLTM wrapup.  It is
not enough for an old TODO to be implicitly covered by a broad phase name; each
handoff item must land in a phase or remain intentionally deferred.

| Earlier handoff TODO | Post-TLTM wrapup placement | Required treatment |
| --- | --- | --- |
| External production-comparison regeneration and CV-002 promotion | Phase 0 and Phase 10 | Treat as external evidence dependency.  Do not claim final production regeneration from the modernization tree unless the external redo packet exists. |
| Accepted-scale wrapper handoff and F12/F14 readback path | Phase 7 | Keep wrapper validation/readback path wired into guardrails before raw Stage entry points are deprecated. |
| Raw Stage script/API/schema deprecation | Phase 3 and Phase 7 | Defer deletion or public schema removal until accepted-scale wrapper handoff and production-comparison consumption are recorded. |
| Long-subroutine decomposition, API slimming, product documentation polish | Phase 2 and Phase 3 | Allow only with explicit behavior-preservation statement and guardrail coverage. |
| RNG ownership and seed-stream migration | Phase 5 and Phase 7 | Keep deferred until an accepted reference baseline or narrower approved baseline exists; never mix with physics changes. |
| Large module `save` workspace migration | Phase 5 and Phase 7 | Treat as a separate source slice with replay/RNG guardrails before and after. |
| `param_mod` global mirror replacement | Phase 2 and Phase 5 | Remove the stale `wv` mirror during hygiene; broader config-state replacement requires baseline coverage. |
| Model/tape cache ownership | Phase 4 and Phase 5 | Move only after the provider boundary and cache ownership contract are explicit. |
| Typed flow/solver/RATTLE/HMC/reverse-gate result objects | Phase 3 and Phase 7 | Add structured status objects as a canonical-code contraction task, with old outputs preserved until migration is approved. |
| Structured forward/replay/probe/reject diagnostics accounting | Phase 5 and Phase 7 | Make diagnostics schema explicit; missing optional diagnostics must be unavailable, not inferred. |
| Lossless acceleration TODO #1-#7 | Phase 6 | Preserve completed lossless wins; keep non-beneficial or unproven accelerations opt-in until recertified. |
| Single/mixed precision, weaker tolerance, GPU/threaded productization | Phase 6 and Phase 7 | Future reopen packets only; not part of canonical TLTM wrapup unless selected explicitly. |
| Dense-output/general ODEX reopen work | Phase 6 | Keep as opt-in future work unless trajectory-equivalence and wall-clock benefit are revalidated. |
| Scheduler/PBS provenance and queue policy | Phase 0 and Phase 7 | Keep scheduler environment, queue policy, job provenance, and timing metadata in the production/readback record. |
| Post-modernization correctness sweep | Phase 10 | Run as a separate post-closure correctness lane; do not hide behavior-changing fixes inside hygiene commits. |

## Current Position

The active modernization direction is:

```text
finish TLTM evidence -> freeze canonical TLTM -> clean legacy residue ->
stabilize shared infrastructure -> open WV-HMC sibling sampler gate
```

Closure update, 2026-05-29:

- Final Stephanov `n=6`, `t_high=0.03` criterion packet exists:
  `runbooks/generated/post_tltm_wv_hmc_ready_20260529/FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md`.
- The four dataset groups are registered in
  `state/STEPHANOV_N6_DATASET_GROUPS_20260528.tsv`.
- The frozen gates keep `nofb` as canonical TLTM production mode.
- `withfb` / DFO-LS fallback is default-off legacy diagnostic mode.
- The stale `wv` runtime config residue has been removed from canonical source.
- The pre-WV local guardrail gate passes after high-dimensional fixture cleanup:
  `make -C build modernization_guardrails`.

Primary decisions:

- TLTM canonical production default is `nofb`.
- Lower failure count alone is not a criterion for `withfb`.
- `withfb` / DFO-LS fallback is default-off legacy diagnostic mode.
- Existing TLTM code is fixed-flow GT-HMC/TLTM-style RATTLE, not a complete
  WV-HMC implementation.
- Future WV-HMC must be introduced as a sibling sampler, not as a hidden mode in
  TLTM Stage2 and not by resurrecting old `wv` flag semantics.

## Non-Negotiable Rules

- Preserve physics/output behavior when refactoring canonical TLTM.
- Do not tune `nofb` by minimizing failure count.
- Choose HMC `epsilon` before choosing `L`/`nstep`.
- Keep flow time out of physical `x`; flow time is sampler metadata.
- Production derivatives are manual; AD/FD are validation tools.
- Do not archive or move active production data before final criterion analysis.
- Do not implement WV-HMC before old WV residue is removed or archived.

## Phase 0. Finish Active Evidence And Criterion Closure

Goal: close the current Stephanov `n=6` evidence package before changing the
production workflow underneath it.

Status, 2026-05-29: complete for opening the WV-HMC implementation gate.  Raw
remote outputs remain in place; no archive move/deletion decision has been
made.

Actions:

- Let active or queued production segments finish, or explicitly record why a
  segment is abandoned.  Completed for the closure packet.
- Run the final frozen-criterion `nofb` vs `withfb` analysis after withfb
  summaries, timing, solver/failure, and swap diagnostics are available.
  Completed with the caveat that runtime-excluded repair/outlier jobs are not
  used for runtime or equal-wall-clock claims.
- Use the frozen gates from
  `runbooks/generated/withfb_criterion_framework_20260527/interim_criterion_framework_v1.md`.
- Keep failure counts diagnostic-only.
- Produce compact result packets for:
  - fixed tau nofb;
  - fixed tau withfb;
  - TLTM nofb;
  - TLTM withfb.
- Fill `state/STEPHANOV_N6_DATASET_GROUPS_20260528.tsv` after final criterion
  analysis, not before.  Completed.

Exit criteria:

- final criterion packet exists;
- all four dataset groups have compact inventory rows;
- raw output roots are still in place and are not silently moved;
- the canonical/legacy method decision is recorded without changing thresholds
  after seeing final data.

All exit criteria are satisfied for source hygiene and WV-HMC gate preparation.

## Phase 1. Freeze Canonical TLTM

Goal: stop expanding TLTM experiments and make one canonical path authoritative.

Canonical TLTM path:

- model provider;
- manual derivative/Hessian/Hv provider;
- observable registry;
- DOP853/ODE flow backend;
- flow-bank initialization;
- snapshot restart;
- direct swap reflow;
- `nofb` production mode.

Actions:

- Treat `TLTM_CANONICAL_SOP_20260528.md` as the production workflow anchor.
- Mark `withfb`/DFO-LS fallback as default-off legacy diagnostic mode unless the
  final frozen criterion says otherwise.
- Mark dense-output swap reflow, continuation cache, lower-neighbor cache, and
  tolerance loosening as opt-in experiments unless revalidated.
- Make every script/PBS launcher map to an SOP stage.
- Require HMC-0 and HMC-L decision records for production.

Exit criteria:

- canonical scripts and PBS launchers map to SOP stages;
- `nofb`/`withfb`/experimental acceleration boundaries are explicit;
- no hidden default enables legacy fallback, dense-output swap, or relaxed
  reverse-gate behavior.

## Phase 2. Repo Hygiene And Residue Removal

Goal: remove stale surfaces before deeper modernization, especially surfaces
that would confuse future WV-HMC work.

Inventory categories:

- keep canonical;
- keep as SOP support;
- keep as validation/readback support;
- legacy/archive;
- experimental opt-in;
- delete candidate.

Required targets:

- runbooks and generated reports;
- analysis scripts and PBS scripts;
- Stephanov-specific helper scripts;
- old one-dimensional compatibility surfaces;
- Stage3/Stage3_4 compatibility surfaces;
- failure/withfb diagnostic artifacts;
- old WV-HMC residue.

Known WV residue:

- `src/config/param_mod.f90` contained a dead `wv` runtime flag; this source
  residue was removed on 2026-05-29.
- `docs/readme.md` no longer claims the repo is already a WV-HMC Fortran
  project.
- No executable WV-HMC transition kernel, worldvolume projection, WV force,
  `(h,u,lambda)` solve, boundary bounce, or `alpha^{-1}` measurement path was
  found in current source.

Actions:

- Use `WV_LEGACY_RESIDUE_AUDIT_20260528.md` as the WV cleanup checklist.
- Remove or explicitly archive the stale `wv` config flag.  Completed:
  canonical source no longer has `runtime_flags_t%wv`, a legacy global `wv`, or
  `config%flags%wv`.
- Rewrite stale documentation so it does not claim current WV-HMC
  implementation.
- Do not reuse old `wv` flag semantics for the future WV-HMC sampler.
- Do not delete any artifact without a row explaining why it is not needed for
  canonical TLTM, legacy reproduction, readback, or future model-provider work.

Exit criteria:

- artifact inventory table exists;
- stale `wv` flag and README claim are removed or archived;
- old WV residue cannot be mistaken for future WV-HMC implementation;
- future WV-HMC is gated by
  `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md` and
  `WV_HMC_MATH_PHYSICS_REVIEW_20260529.md`.

## Phase 3. Contract Canonical TLTM Code

Goal: make the canonical TLTM code path narrow, model-general, and maintainable.

Actions:

- Remove model choice from canonical sampler/control code.
- Keep Stephanov as a provider/validation model, not a control-flow special
  case.
- Keep fixed-flow GT-HMC/TLTM RATTLE semantics separate from future WV-HMC
  semantics.
- Turn legacy flags and compatibility aliases into explicit opt-in surfaces or
  delete candidates.
- Preserve output schema unless a schema migration is explicitly planned.
- Keep raw Stage script/API/schema deprecation blocked until accepted-scale
  wrapper handoff and production-comparison consumption are recorded.
- Introduce typed result/status objects for flow, solver, RATTLE, HMC, and
  reverse-gate paths only with compatibility outputs and guardrails.
- Treat long-subroutine decomposition and API slimming as behavior-preserving
  contraction work, not as an opportunity to change proposal semantics.

Exit criteria:

- module boundary inventory identifies canonical TLTM entry points;
- model-specific logic is isolated to provider/observable code;
- legacy fallback and experimental accelerations are named and default-off;
- behavior-preservation checks pass before and after code contraction.

## Phase 4. Model Provider And Derivative Closure

Goal: make the repo ready for arbitrary models specified by action, derivatives,
Hessian/Hv, and analytic observables.

Required provider surface:

- scalar holomorphic action;
- manual gradient;
- manual Hessian or Hessian-vector product;
- observable registry;
- analytic observable definitions;
- parameter schema;
- physical state layout;
- complexification rule for original non-holomorphic notation.

Validation:

- random complex-seed gradient check by AD/FD;
- random complex-seed Hessian/Hv check by AD/FD;
- observable registry consistency;
- small-size exact-reference check when available.

Exit criteria:

- provider interface is documented;
- Stephanov satisfies it;
- next high-dimensional model can be added by provider/parameter files rather
  than by editing TLTM sampler logic.

## Phase 5. State, Config, IO, Snapshot, And Dataset Scaling

Goal: make large high-dimensional runs manageable and restartable.

State/config rules:

- physical `x` contains only physical coordinates;
- flow time is replica/sampler metadata;
- sampler state, model state, config state, and diagnostics are separate;
- RNG ownership, seed streams, model/tape caches, `param_mod` mirrors, and large
  module workspaces are separate state-migration slices;
- snapshot restart boundary policy is explicit;
- protocol changes are not silently mixed in one production campaign.

Required production outputs:

- observable history;
- label trace;
- run summary;
- final snapshot;
- bank/cache manifest;
- timing metadata;
- parameter/config manifest.
- structured diagnostics accounting for forward flow, replay, probe, rejection,
  swap/reflow, and optional fallback paths when those paths are active.

Scaling policy:

- production supports chunked execution;
- snapshot continuation is the default extension mechanism;
- readback supports all-available, common-prefix, equal-cycle, and
  equal-wall-clock cuts;
- bulky raw histories are not committed to source history;
- compact evidence tables and runbooks are source-controlled when useful.

Exit criteria:

- IO manifest schema is documented;
- snapshot loader fails closed on schema/protocol mismatch;
- production and readback scripts agree on required files;
- missing optional diagnostics are reported as unavailable, not inferred.
- deferred state migrations have explicit baseline requirements instead of
  being folded into unrelated cleanup.

## Phase 6. Acceleration And Runtime Closure

Goal: keep only proven or necessary accelerations in canonical TLTM.

Canonical or near-canonical:

- phase/action/logdet cache;
- process-level parallelism for independent records/jobs;
- flow-bank initialization;
- snapshot restart;
- direct swap reflow.

Opt-in until recertified:

- external BLAS/LAPACK;
- Stage2 OpenMP local-update parallelism;
- real-Jacobian cache if production-scale benefit is unclear;
- dense-output swap reflow;
- continuation cache;
- lower-neighbor cache.

Rejected as canonical acceleration:

- tolerance loosening without fixed-target validation;
- reverse-gate relaxation;
- reduced observable sampling;
- failure-minimizing protocol choices.

Exit criteria:

- acceleration inventory records keep/opt-in/legacy/delete-candidate status;
- each opt-in acceleration has a promotion validation plan;
- runtime changes are evaluated by trajectory equivalence, observable equality,
  and wall-clock benefit.

## Phase 7. Regression And Guardrail Matrix

Goal: protect TLTM behavior while cleanup proceeds.

Required gates:

- model derivative/Hessian complex-seed validation;
- observable registry validation;
- small exact-reference smoke when available;
- Stage2 deterministic replay;
- Stage2 RNG v2 anchor;
- accepted reference baseline or explicit narrower baseline for RNG/state/cache
  migrations;
- flow-bank initialization smoke;
- snapshot continuation parity;
- observable readback smoke;
- TLTM nofb production smoke;
- typed result/status compatibility smoke;
- structured diagnostics accounting smoke;
- wrapper/readback compatibility smoke before Stage entry-point deprecation;
- affected-baseline matrix row and patch behavior class for every behavior
  surface touched;
- PBS/scheduler provenance smoke for cluster execution.

Exit criteria:

- one guardrail command or checklist references all required gates;
- failures are classified by layer: model, sampler, IO, snapshot, readback,
  cluster, or optional legacy path;
- physics/output changes are either absent or explicitly justified.

## Phase 8. Two-Way Architecture Preparation

Goal: prepare the repo to support TLTM and WV-HMC as sibling samplers.

Shared layer:

- model provider;
- manual derivatives and Hessian/Hv;
- observables;
- ODE/flow backend;
- fixed-surface projection primitive;
- config and parameter schema foundations;
- IO manifests and compact readback;
- ratio-estimator analysis where applicable;
- cluster scheduler/provenance discipline.

TLTM-specific layer:

- TLTM transition kernel;
- flow-time ladder;
- swap/reflow;
- TLTM label and high-flow diagnostics;
- TLTM nofb/withfb legacy boundary.

WV-HMC-specific layer:

- worldvolume state `(t, x, z, pi)`;
- `W(t)` / `W'(t)` and boundary schema;
- WV projection;
- WV simplified RATTLE solve for `(h,u,lambda)`;
- boundary bounce;
- measurement subinterval;
- `alpha^{-1}` weight;
- WV-specific diagnostics.

Exit criteria:

- directory/module boundary plan exists;
- adding WV-HMC does not require modifying canonical TLTM semantics;
- shared interfaces are stable enough for both samplers.

## Phase 9. WV-HMC Integration Gate

Goal: start WV-HMC only after TLTM closure, hygiene, and shared infrastructure
are stable.

Requirements:

- follow `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`;
- follow `WV_HMC_IMPLEMENTATION_PLAN_20260529.md` for the implementation
  sequence;
- do not start from old `wv` flag or stale handwritten residue;
- implement WV-HMC as a sibling sampler;
- preserve TLTM canonical nofb behavior;
- start with explicit dense projection as small-N validation backend;
- certify matrix-free BiCGStab projection backend before high-dimensional use.

First validation target:

- Stephanov `n=2`;
- explicit dense backend;
- exact-reference observable check;
- projection reconstruction/orthogonality checks;
- WV `(h,u,lambda)` constraint residual check;
- reversibility and energy-error scaling;
- flow-time visitation and boundary bounce diagnostics.

Exit criteria:

- WV-HMC has an independent state and transition kernel;
- WV-HMC outputs are compatible with shared readback where meaningful;
- TLTM guardrails pass unchanged after WV-HMC is added.

## Phase 10. Final Modernization Closure

Modernization can close for this phase when:

- final Stephanov `n=6` criterion packet is complete;
- dataset archive groups are compactly registered;
- external production-comparison obligations are either completed or explicitly
  recorded as out-of-tree follow-up, with no false claim from this source tree;
- canonical TLTM SOP is authoritative and runnable;
- legacy and experimental boundaries are explicit;
- stale WV residue is removed or archived;
- model provider surface is general enough for the next model;
- IO and snapshot/restart support large datasets;
- regression/readback gates are reproducible;
- WV-HMC has a clean implementation gate as a sibling sampler.

Post-closure correctness sweep:

- candidate correctness issues move to a separate sweep packet;
- behavior-changing fixes require explicit approval and comparison evidence;
- nonbehavioral dead-code and documentation cleanup may continue under the
  hygiene rules above.

After this closure, new scientific work should add models or sampler-specific
extensions through shared interfaces rather than expanding TLTM control logic.

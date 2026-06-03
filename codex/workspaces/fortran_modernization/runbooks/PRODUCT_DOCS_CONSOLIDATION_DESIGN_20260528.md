# Product Docs Consolidation Design

Date: 2026-05-28

Scope: target documentation design for a productized TLTM/WV-HMC scientific
software repository.  This is a design document only.  It does not move or
delete current docs, runbooks, JSON evidence, papers, or production outputs.

Status, 2026-05-29: TLTM final criterion closure is complete, but the full
public-docs migration remains deferred until after WV-HMC is added or the
project explicitly enters productization.  The pre-WV gate only corrects stale
WV-HMC claims and records canonical TLTM status.

Status, 2026-06-03: the project is entering productization closure using the
completed Stephanov `n=6` long dense WV-HMC validation readback in
`runbooks/generated/wv_hmc_n6_t0001_validation_20260603/N6_LONG_VALIDATION_READBACK_20260603.md`.
The product docs must follow
`runbooks/generated/productization_closure_workflow_20260603/PRODUCTIZATION_CLOSURE_WORKFLOW_20260603.md`.
DFO-LS/`withfb` is legacy diagnostic only and must not appear in the active
install/build dependency path.  Matrix-free/BiCGStab and high-dimensional
performance optimization are roadmap items, not publication blockers.  Public
WV-HMC claims must include the observed burn-in/startup-transient caveat.

## Goal

Final product documentation should be small, stable, and user-facing.  It should
not expose every historical tuning run, abandoned branch, cluster experiment,
or intermediate readback as first-level documentation.

The final public docs should answer:

- what the package does;
- how to install/build it;
- how to run TLTM;
- how to add a model;
- how to define observables;
- what files are produced;
- how to restart/read back runs;
- how to validate a change;
- where algorithm references and reproducibility records live.

Everything else should move to internal runbooks, archived evidence, or generated
result packets.

## Final Public Documentation Set

Target public files:

| File | Purpose | Current source material |
| --- | --- | --- |
| `README.md` | First-page overview, supported samplers, quick start, minimal example, links to deeper docs. | `docs/readme.md`, `TLTM_CANONICAL_SOP_20260528.md` |
| `docs/INSTALL.md` | Build dependencies, compiler/MKL/Python notes, local and cluster build commands.  No active DFO-LS install path. | `docs/commands.md`, `build/makefile`, third-party notices |
| `docs/USER_GUIDE.md` | Ordinary user workflow: choose model, prepare parameters, build flow bank/snapshot if needed, run TLTM, evaluate observables. | `TLTM_CANONICAL_SOP_20260528.md`, `docs/file_layout.md` |
| `docs/MODEL_PROVIDER.md` | Model API contract: scalar action, manual gradient, Hessian/Hv, complexification, observables, AD/FD validation. | `docs/model_observables.md`, `STEPHANOV_MANUAL_PROVIDER_DECISION_20260522.md`, `model_specs/high_dimensional/` |
| `docs/SAMPLERS.md` | Concise algorithm-level docs for canonical TLTM and future WV-HMC sibling path.  No historical tuning narrative. | `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`, TLTM SOP |
| `docs/CONFIGURATION.md` | Parameter schema, runtime environment variables, defaults, deprecated keys, and compatibility rules. | `docs/state_vector_convention.md`, `param_mod` notes |
| `docs/OUTPUTS_AND_RESTART.md` | Output files, observable streams, label traces, snapshots, bank/cache manifests, readback cuts. | `STAGE2_SNAPSHOT_RESTART_20260523.md`, observable-stream docs |
| `docs/DEVELOPMENT.md` | Architecture, tests, guardrails, behavior-preservation rules, contribution workflow. | `docs/module_architecture.md`, `POST_TLTM_GUARDRAIL_CHECKLIST_20260528.md`, `BEHAVIOR_PRESERVATION_PROTOCOL.md` |
| `docs/REFERENCES.md` | Paper references, algorithm citations, license/third-party pointer. | PDFs currently under `docs/`, `THIRD_PARTY_NOTICES.md` |
| `docs/ARCHIVE_INDEX.md` | Index pointing to internal runbooks and frozen evidence archives.  This is the only public bridge to historical material. | `PLANNING_INDEX.md`, generated readback directories |

Optional only if needed later:

| File | Include only if it stays useful |
| --- | --- |
| `docs/TROUBLESHOOTING.md` | Runtime failures, cluster issues, common schema mismatch, ODE failure interpretation. |
| `docs/CHANGELOG.md` | Release notes after product versioning starts. |
| `CONTRIBUTING.md` | If external contributors become a target. |

## What Should Leave Public Docs

These should not remain as first-level public docs in a productized tree:

| Current material | Target location | Reason |
| --- | --- | --- |
| Historical JSON result descriptors under `docs/*.json` | `archive/evidence/<campaign>/` or `codex/workspaces/.../runbooks/generated/` | They are evidence packets, not product docs. |
| Historical tuning notes under `docs/stage*`, `f20f*`, `qn_*` | `archive/evidence/<campaign>/` | They are campaign provenance. |
| Papers/PDFs under `docs/` | `references/` or `docs/REFERENCES.md` link targets | Product docs should cite them, not mix papers with user docs. |
| Generated readback tables/plots | `runbooks/generated/<packet>/` or archived result package | Generated evidence should be reproducible and indexed, not hand-curated docs. |
| Long modernization runbooks | `codex/workspaces/fortran_modernization/runbooks/` and later `archive/runbooks/` | Internal governance, not user docs. |
| Cluster scheduling state | internal runbooks/state only | Operational provenance, not public user docs except short build/run notes. |
| Abandoned acceleration experiments | archive/internal only | Avoid implying support. |

## Public Docs Philosophy

The public docs should be:

- stable across runs;
- short enough that a new user can read them linearly;
- model-general, not Stephanov-only;
- explicit about supported sampler status;
- explicit about what is experimental or legacy;
- free of campaign-specific decisions unless they are now canonical defaults;
- linked to reproducibility archives without embedding every archive detail.

## Internal Documentation Philosophy

Internal docs remain valuable, but should be separated from the public surface:

- `codex/workspaces/fortran_modernization/runbooks/`: active planning,
  decision packets, guardrails, readbacks.
- `codex/workspaces/fortran_modernization/runbooks/generated/`: generated
  analysis packages.
- `archive/evidence/`: frozen result packets and historical JSON descriptors.
- `archive/runbooks/`: superseded internal planning docs after closure.
- `references/`: papers and external references.

Internal docs may be verbose and campaign-specific.  Public docs should not.

## Target Top-Level Layout

Productized target:

```text
README.md
LICENSE
LICENSE_POLICY.md
THIRD_PARTY_NOTICES.md
build/
data/
docs/
  INSTALL.md
  USER_GUIDE.md
  MODEL_PROVIDER.md
  SAMPLERS.md
  CONFIGURATION.md
  OUTPUTS_AND_RESTART.md
  DEVELOPMENT.md
  REFERENCES.md
  ARCHIVE_INDEX.md
model_specs/
references/
src/
tests/
scripts/
archive/
  evidence/
  runbooks/
codex/
  workspaces/fortran_modernization/
```

During modernization, `codex/workspaces/fortran_modernization/runbooks/` remains
the active internal planning location.  After closure, old runbooks can be
frozen or moved to `archive/runbooks/` only after links and provenance are
preserved.

## Minimal Root README Contract

The final root `README.md` should contain only:

1. Project summary and supported sampler status.
2. Installation/build quick start.
3. Minimal TLTM run example.
4. How to add a model.
5. Where outputs go and how to read them.
6. Validation/guardrail command.
7. Documentation index.
8. Citation/license notes.

It should not contain:

- detailed historical nofb/withfb debate;
- step-by-step cluster campaign records;
- long modernization TODOs;
- obsolete 1D toy-model workflows;
- raw result tables except a link to an archived release/evidence packet.

## Migration Order

Do not perform the file moves before final production closure unless a move is
pure docs-only and no script/readback path depends on it.

Recommended order after production closes:

1. Finish final criterion analysis and four dataset archive groups.
2. Freeze public sampler status: TLTM nofb canonical, withfb legacy or promoted
   only if frozen gates require it.
3. Remove DFO-LS from active public install/build/license/dependency surfaces;
   keep historical DFO-LS evidence archive-only.
4. Create `README.md` at repo root from `docs/readme.md`.
5. Split current `docs/readme.md`, `commands.md`, `file_layout.md`,
   `module_architecture.md`, `state_vector_convention.md`, and
   `model_observables.md` into the target public docs set.
6. Move result JSON files from `docs/` into `archive/evidence/` with an
   `archive/evidence/INDEX.md`.
7. Move papers/PDFs from `docs/` into `references/` and summarize them in
   `docs/REFERENCES.md`.
8. Keep current active runbooks under `codex/.../runbooks/` until WV-HMC gate is
   opened; then archive superseded runbooks with a generated index.
9. Run docs link checks and script evidence audit.
10. Run source guardrails only if source, scripts, or build behavior changed.

## Migration Gates

Docs-only moves require:

```bash
git diff --check
rg -n "WV-HMC Fortran Project|implements a worldvolume-HMC workflow" README.md docs scripts/README.md
make -C build script_evidence_audit_gate
```

If any script path, generated evidence path, or readback path is renamed:

- update `SCRIPT_EVIDENCE_AUDIT_20260512.tsv`;
- update any runbook index that references the old path;
- leave an archive index entry;
- do not delete old data before final archive verification.

If source behavior or output schema changes, this is no longer docs cleanup and
must use the post-TLTM source guardrails.

## Final Public Docs Exit Criteria

- Root `README.md` exists and is the only required starting point.
- `docs/` contains only stable product docs, not campaign evidence.
- `docs/ARCHIVE_INDEX.md` points to historical/internal material.
- `docs/REFERENCES.md` points to papers and citation references.
- `docs/DEVELOPMENT.md` points to guardrails and behavior-preservation rules.
- Generated evidence is outside public docs and indexed.
- No public doc claims WV-HMC is implemented until the sibling sampler exists.
- No public doc presents `withfb` as canonical unless final frozen gates require
  it.
- No public doc lists DFO-LS as an active dependency unless a future explicit
  reopen decision promotes `withfb` again.

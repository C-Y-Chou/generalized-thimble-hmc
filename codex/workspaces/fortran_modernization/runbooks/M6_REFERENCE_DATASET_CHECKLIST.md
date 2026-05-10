# M6 Modernization Reference Dataset Checklist

Updated: 2026-05-10 JST

Scope: the exact preflight checklist that must be satisfied before the modernization workstream builds, registers, or trusts a TLTM reference dataset/package for future behavior-preserving refactors. This document does not start jobs and does not own the Stage3_4 `nofb` vs `withfb` production campaign.

## Hard Preconditions

- User explicitly says to build/register the modernization reference dataset/package.
- Git worktree is clean.
- Branch and commit are recorded.
- No uncommitted source, script, config, or runbook changes are present.
- The intended parameter/config files and seed lists are frozen for the validation ladder.
- v1alpha sidecars are enabled for reference-consumed runs.
- v0 compatibility outputs remain enabled.
- Reference-package output/registration directory is new, intentionally empty, or explicitly archived as a read-only modernization reference.
- The run is not using stale local `bin/` executables.

Production boundary:

- Stage3_4 owns final production scheduling, chunking, workspace naming, and output cleanup.
- Modernization owns only the reference-dataset consumer contract and refactor regression use.
- Local `output/tests` guardrail artifacts are not the final dataset.

## Local Preflight

Run from repository root:

```bash
git status --short
git rev-parse HEAD
make -C build modernization_guardrails
```

Required result:

- `git status --short` prints no tracked or untracked work that belongs to the run.
- `make -C build modernization_guardrails` reports all guardrails passed.
- Guardrail output includes `direct env reads centralized`.

## Source Contract Checks

Confirm:

- `rg -n "get_environment_variable" src tests` reports only `src/config/runtime_env_mod.f90`.
- The canonical route is p28 fallback-enabled/no-post-refine.
- Radau/JFNK and non-p28 QN source paths remain absent.
- The selected tempering timing is `local update -> swap -> measure/history/label trace`.
- The final proposal path uses strict final `flow(...)`.
- Solver-internal assist is limited to Newton/QN residual evaluation.

## Reference Provenance To Record

Record these before submitting jobs:

- branch
- commit
- compiler/modules
- linked BLAS/LAPACK/MKL details
- config file path and digest
- Stage3 config path and digest
- seed list
- flow ladder
- trajectory length and HMC step count
- cycles per seed and warmup policy
- QN budgets/tolerances/env overrides
- reverse-gate tolerance/env overrides
- v1 sidecar output root
- v0 compatibility output root
- audit command
- expected validation scale and Stage3_4 workflow-context assumptions: 10k, 50k, 100k, or larger

## Required Validation Ladder For Modernization-Generated References

Run in order:

1. 10k validation
2. 50k validation
3. 100k validation

Do not skip directly to larger campaigns when modernization itself generates the reference data.

Stage3_4 is used as workflow context, not as a required result source. If the reference is Stage3_4-context-aligned, record the context assumptions instead of treating Stage3_4 outputs as a prerequisite.

At each scale, review:

- physical observables and phase statistics
- acceptance rates
- reverse-gate candidate/pass/reject counts
- proposal construction failure counts
- ODE/final-flow failure status counts
- Newton/QN residual flow-status counters
- solver-assist usage and failures
- protocol-audit verdict
- v1 sidecar/readback consistency
- runtime and failure-rate anomalies

Escalate before larger runs if:

- protocol audit fails
- v1 sidecar readback is inconsistent
- physical observables show a material shift
- acceptance/reverse-gate diagnostics move unexpectedly
- unresolved/projection/final-flow failures jump outside expected ODEX-assist behavior
- any output schema field is missing or renamed

## Reference Dataset Artifacts

Each generated or registered reference package should leave or point to:

- Stage2/Stage3 raw outputs
- v0 compatibility summaries
- v1alpha sidecars
- protocol audit summary
- Stage3 per-seed table
- Stage3 aggregate summary
- evaluation output
- run log
- merge log
- provenance note linking commit/config/seed/output

## Not Allowed During Reference Dataset Construction

- Editing source while a modernization-generated validation ladder is in progress.
- Reusing partial outputs after source/config changes unless the recovery path is explicitly documented.
- Changing seed lists between matched comparisons.
- Renaming output fields.
- Deleting compatibility outputs.
- Mixing old timing-convention outputs with new post-swap references.
- Submitting, deleting, or relocating Stage3_4 production jobs/artifacts from this modernization workspace.

## Completion Criteria

The modernization reference dataset/package is ready for user review when:

- 10k, 50k, and 100k artifacts are complete.
- All protocol audits pass.
- v1 sidecar/readback checks pass.
- A concise result note records physical observables and diagnostic counters at all scales.
- Any deviations from previous characterization or the intended Stage3_4 workflow context are explained before the package is used as a refactor baseline.

# Soft Decoupling And Provisional Production Contract

Updated: 2026-05-10 JST

Scope: define the boundary that lets `fortran_modernization` and `tltm_production_comparison` proceed in parallel without pretending the current production-comparison outputs are final publication datasets.

## Decision

The legacy `stage3_4` workstream is now named `tltm_production_comparison`.

This is a soft decoupling, not a hard freeze:

- Production comparison may run provisional datasets for collaborator discussion, physical trend checks, queue rehearsal, and workflow validation.
- Modernization may continue code design/refactor work against its accepted M6 reference baselines.
- Final publication-grade production datasets should be regenerated after modernization converges on final wrapper/schema/naming/counter conventions.

## Workspace Ownership

| Workstream | Canonical workspace | Remote target | Branch | Remote worktree |
| --- | --- | --- | --- | --- |
| Fortran modernization | `codex/workspaces/fortran_modernization` | `fortran_modernization` | `codex/fortran-modernization` | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization` |
| Production comparison | `codex/workspaces/tltm_production_comparison` | `tltm_production_comparison_provisional` | `codex/tltm-production-comparison-official-dfols` | `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` |

Legacy names:

- `stage3_4` is a historical alias for `tltm_production_comparison`.
- `qn_error_handling_validation` is a historical remote worktree/branch name from the modernization M6 path and should not be the active semantic target for new work.

## Production Comparison Contract

Current provisional comparison:

- Physical point: `t=0.35,L=2,nstep=20`
- Canonical roles: `nofb`, `withfb`
- Legacy raw mapping: `nofb == no_fb`, `withfb == fb_norefine`
- Status: `provisional_discussion`
- Intended use: collaborator discussion, scale/queue rehearsal, and early physics-trend inspection
- Not intended use: final publication dataset

Preferred new output namespace:

```text
output/production_comparison/provisional/<campaign_id>
output/logs/production_comparison/provisional/<campaign_id>
```

Legacy outputs under `output/tests/stage3_4/...` remain readable historical evidence and must not be deleted before dataset registry/archive readback.

Superseding cleanup note, 2026-05-10 JST: legacy Stage1 to Stage3_4 raw outputs/logs were cleared after key readback summary preservation; obsolete ODEX validation raw data was also cleared because M6 modernization reference datasets are accepted. See `LEGACY_STAGE_OUTPUT_CLEANUP_20260510.md`.

## M6 Reference Cross-Use

Accepted M6 reference datasets may be reused as the first production-calibration tier for deciding production seed/cycle scaling.

This is a registry/readback alias, not a transfer of raw-data ownership:

- M6 raw data remains owned by `fortran_modernization`.
- Production comparison may consume M6 R1-R4 aggregate/readback artifacts.
- Derived production-calibration reports should be written under `output/production_comparison/calibration/...`.
- Final publication production still needs regeneration after modernization converges.

Read `M6_REFERENCE_AS_PRODUCTION_CALIBRATION_PLAN.md` before launching the next production-comparison jobs.

## Modernization Contract

Modernization is not blocked on final production-comparison completion.

Current accepted modernization baselines:

- M6 R1-R4 accepted reference packages.
- Readback record: `codex/workspaces/fortran_modernization/runbooks/M6_REFERENCE_DATASET_READBACK_20260510.md`.
- Production-calibration cross-use record: `codex/workspaces/tltm_production_comparison/runbooks/M6_REFERENCE_AS_PRODUCTION_CALIBRATION_PLAN.md`.

Modernization should record any future change that affects production interpretation, especially:

- method naming or raw/canonical mapping
- public output schema
- counter/status semantics
- wrapper behavior
- RNG stream ownership
- proposal construction, solver route order, tolerances, or final-flow policy

If any of those change, provisional production outputs remain useful for discussion but final production must be regenerated.

## Operational Rules

- Always refresh `codex/state/REMOTE_LIVE_CACHE.json`, `WORKTREES.tsv`, and `JOBS.tsv` before SSH/PBS/git cleanup.
- Do not submit production-comparison jobs from `fortran_modernization`.
- Sync production-comparison to the selected official-DFO-LS commit, then build/run inside the production-comparison worktree.
- Do not do Fortran code-refine work inside `tltm_production_comparison` unless the user explicitly opens a production-code-fix task.
- Use the shared cluster02 scheduler agent for both workstreams.
- Do not use the old `stage3_4` queue playbook for queue choice.

## Decoupling Completion Criteria

This pass is complete when:

- `codex/workspaces/tltm_production_comparison` is the canonical workspace.
- The task registry and L1 index route production-comparison work to the new workspace.
- Remote targets include separate semantic targets for modernization and production comparison.
- M6 modernization references remain registered and accepted.
- Legacy `stage3_4` and `qn_error_handling_validation` names are documented as aliases/history, not active semantic targets.

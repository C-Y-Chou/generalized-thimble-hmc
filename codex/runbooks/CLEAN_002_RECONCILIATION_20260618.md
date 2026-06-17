# CLEAN-002 Reconciliation Record

Date: 2026-06-18 JST

## Scope

This record closes `CLEAN-002: Full Modernization Cleanup Sprint`.

The purpose is governance cleanup, not a new scientific result.  It reconciles
the old Codex control-plane registries with the active modernization milestone
queue and removes private scheduler/workspace state from the public commit
path.

## Active Entry Points

The active modernization entrypoints are:

1. `codex/runbooks/MODERNIZATION_WORKFLOW.md`
2. `codex/runbooks/MODERNIZATION_STATUS.md`

Compatibility shims such as `codex/runbooks/STATUS.md` and
`codex/runbooks/WORKFLOW.md` may point to these files, but they are not separate
sources of workflow truth.

## Registry Reconciliation

The old registries:

- `codex/state/OPEN_ITEMS.tsv`
- `codex/state/CAVEATS.tsv`
- `codex/workspaces/*/state/OPEN_ITEMS.tsv`
- `codex/workspaces/*/state/CAVEATS.tsv`

are local control-plane archives.  They contain stale active rows from earlier
solver, production-comparison, queue, and workspace phases and are no longer the
active public modernization ledger.

Current active and deferred work is represented by the milestone queue in
`MODERNIZATION_WORKFLOW.md`:

- completed public milestones: `GHM-001` through `GHM-005`;
- completed cleanup milestones: `CLEAN-001`, `CLEAN-002`;
- next release-facing milestone: `DOC-001`;
- technical deferred work: `TECH-001` through `TECH-005`;
- external workstream boundary: `EXT-001`.

Stale registry rows are therefore classified as one of:

- already closed by the completed `GHM-*` milestones;
- superseded by `CLEAN-002` and the current milestone queue;
- deferred into `TECH-*`;
- externalized into `EXT-001`;
- retained only as local historical context.

## Public Evidence Retained

The compact WV-HMC evidence retained in the public path is:

- `codex/runbooks/WV_HMC_POLICY_BENCHMARK_SUMMARY_20260616.md`
- `codex/runbooks/generated/wv_hmc_n6_4policy_all_available_20260611/wv_hmc_n6_4policy_all_available_summary.csv`
- `codex/runbooks/generated/wv_hmc_n6_4policy_burn_middle_grid_20260616/WV_HMC_N6_4POLICY_BURN_MIDDLE_GRID_20260616.md`
- `codex/runbooks/generated/wv_hmc_n6_4policy_burn_middle_grid_20260616/wv_hmc_n6_4policy_burn_middle_grid_summary.csv`

These files are compact evidence packets.  They are not workflow routers.

## Local-Only Archives

The following paths are local/internal and ignored for future public commits:

- `codex/agents/`
- `codex/state/`
- `codex/workspaces/`
- unpromoted `codex/runbooks/generated/` packets
- `lustre1/`

They may remain in the working tree for operational continuity, but they should
not be treated as GitHub progress or public documentation.

## Completion Decision

`CLEAN-002` is complete when:

- the public workflow/status files identify the active milestone queue;
- old registries are no longer tracked as public state;
- private scheduler and workspace artifacts are outside the public commit path;
- compact evidence remains reachable from the status file;
- the next active step is `DOC-001`.

All conditions are satisfied by this cleanup commit.

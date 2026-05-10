# Control-Plane Memory Compaction Plan

Updated: 2026-05-10 JST

Implementation status: completed for the first control-plane compaction slice.

## Objective

Turn `codex/` from a growing set of long documents into a compact, remote-aware control plane.

This plan includes the already-built `cluster02 scheduling agent` and pulls legacy Stage3_4 / current `tltm_production_comparison` cleanup concerns into a shared memory/cleanup workflow without merging production-comparison work into Fortran modernization.

## Design

Memory layers:

- L0: `context/L0_BOOT.md`, mandatory short boot state.
- L1: `indexes/L1_INDEX.tsv`, routing table for what to read next.
- L2: existing long runbooks and workspace histories, read only when the L1 trigger applies.

Machine-readable registries:

- `state/DECISIONS.tsv`
- `state/OPEN_ITEMS.tsv`
- `state/REMOTE_TARGETS.tsv`
- `state/WORKTREES.tsv`
- `state/JOBS.tsv`
- `state/DATASETS.tsv`
- `state/REFERENCES.tsv`
- `state/OBSERVATIONS.tsv`
- `logs/REMOTE_EVENTS.tsv`
- `logs/SESSION_EVENTS.tsv`

Refresh/render scripts:

- `tasks/refresh_remote_state.sh`
- `tasks/render_l0_boot.sh`
- `tasks/validate_control_plane.sh`

## Agent Boundary

Current operational agent:

- `workspaces/fortran_modernization/runbooks/CLUSTER02_SCHEDULING_AGENT.md`
- `workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py`
- `workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`

Policy:

- Use the cluster02 scheduler for any PBS queue/work-splitting/job-repair decision.
- Do not agentize Fortran modernization itself.
- Treat behavior preservation, algorithm reference maps, and reference datasets as registries/checklists unless they become repeated cross-workspace operations.

## Production-Comparison Cleanup Boundary

Production-comparison output cleanup is included in the shared control-plane cleanup plan, but deletion remains gated:

- First refresh remote state and job state.
- Register outputs/datasets/jobs before moving or deleting anything.
- Mark stale queue runbooks as superseded when they conflict with the scheduler agent.
- Do not delete production evidence until summarized or archived.

## Completion Definition

This control-plane cleanup slice is complete when:

- L0/L1 entrypoints exist and are referenced by handoff/README.
- Remote SSH/PBS/worktree state can be refreshed into `REMOTE_LIVE_CACHE.json`, `WORKTREES.tsv`, and `JOBS.tsv`.
- The cluster02 scheduling agent is part of the standard workflow.
- Superseded legacy Stage3_4 queue guidance is clearly marked.
- A validator checks the control-plane files before future work.

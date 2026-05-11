# TLTM Codex Workspace

This folder is a shared Codex control plane for TLTM work.

## Goal
- Provide one stable entrypoint for new conversations.
- Support multiple parallel tasks without overwriting each other's live state.
- Keep queue status and task state continuously refreshable from one command.

## Workspace model
- Shared layer: `context/`, `knowledge/`, `runbooks/`, `tasks/`, `state/registry/`
- Task layer: `workspaces/<task_slug>/...`
- Live production or investigation work must happen inside a named task workspace.

## First command in any new chat
```bash
cd /home/cychou/TLTM/codex
bash tasks/bootstrap.sh
bash tasks/refresh_remote_state.sh
bash tasks/render_l0_boot.sh
```

## Always-read compact status
- `/home/cychou/TLTM/codex/context/L0_BOOT.md`
- `/home/cychou/TLTM/codex/indexes/L1_INDEX.tsv`

Do not read long runbooks by default. Use `runbooks/READ_POLICY.md` and `indexes/L1_INDEX.tsv`.

## Task entry
1. Read `/home/cychou/TLTM/codex/context/HANDOFF_MIN.txt`
2. Read `/home/cychou/TLTM/codex/context/L0_BOOT.md`
3. Pick the target task from `/home/cychou/TLTM/codex/runbooks/task_registry.tsv`
4. Enter that workspace and read its `context/TASK.md` plus `context/STATE_BRIEF.md` when present

## Current Fortran Modernization Entry
- Workspace: `/home/cychou/TLTM/codex/workspaces/fortran_modernization`
- Current phase: M6 modernization reference-dataset product-readiness planning after M5 direct-env/config ownership consolidation.
- Read next:
  - `runbooks/STATUS.md`
  - `runbooks/OFFICIAL_DFOLS_LICENSE_REPLACEMENT_PLAN.md`
  - `runbooks/EXTERNAL_DFOLS_BACKEND_COMPARISON.md`
  - `runbooks/CLUSTER02_SCHEDULING_AGENT.md`
  - `runbooks/PARALLEL_WORKSTREAM_BOUNDARY_AND_REFERENCE_DATASET_POLICY.md`
  - `runbooks/M6_REFERENCE_DATASET_DESIGN_SPEC.md`
  - `runbooks/M6_REFERENCE_DATASET_READBACK_PLAN.md`
  - `runbooks/M6_REFERENCE_DATASET_GENERATION_AND_COVERAGE_PLAN.md`
  - `runbooks/M6_DYNAMIC_QUEUE_POLICY_20260510.md`
  - `runbooks/M6_TO_CODE_MODERNIZATION_ENTRY_GATE.md`
  - `runbooks/M5_PRE_M6_GATE_ASSESSMENT.md`
  - `runbooks/M6_REFERENCE_DATASET_PRODUCT_READINESS_PLAN.md`
  - `runbooks/M6_REFERENCE_DATASET_CHECKLIST.md`
  - `runbooks/M6_PROVENANCE_READBACK_CHECKLIST.md`
- Local guardrail before source changes or dataset planning: `make -C build modernization_guardrails`
- Cluster/PBS/dataset scheduling authority: use the cluster02 scheduling agent before splitting work, choosing queues, submitting jobs, or repairing failed chunks.
- Shared scheduler pointer:
  - `agents/cluster02_scheduler/README.md`
- Persistent scheduler memory:
  - `workspaces/fortran_modernization/state/CLUSTER02_SCHEDULER_KNOWLEDGE.json`
  - `workspaces/fortran_modernization/state/CLUSTER02_QUEUE_OBSERVATIONS.tsv`
- Agent utility:
  - `python3 workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py show-policy`
  - `python3 workspaces/fortran_modernization/tasks/scripts/cluster02_scheduler_agent.py snapshot`
- `tltm_production_comparison` owns the `nofb` vs `withfb` production-comparison workflow. Legacy alias: `stage3_4`.
- Modernization has accepted M6 R1-R4 reference baselines and may continue behavior-preserving refactors through `fortran_modernization`.
- Official DFO-LS replacement uses GPL-3.0-or-later product direction; Tapenade AD is tracked as an external MIT-licensed code-generation tool.
- Production-comparison outputs before final modernization convergence are provisional-discussion datasets; final publication datasets should be regenerated after wrapper/schema/naming/counter conventions settle.

## Current Production Comparison Entry
- Workspace: `/home/cychou/TLTM/codex/workspaces/tltm_production_comparison`
- Current mode: provisional TLTM `nofb` vs `withfb` production comparison for collaborator discussion and workflow rehearsal.
- Read next:
  - `context/STATE_BRIEF.md`
  - `runbooks/SOFT_DECOUPLING_AND_PROVISIONAL_CONTRACT.md`
  - `runbooks/STATUS.md`
- Preferred new output namespace:
  - `output/production_comparison/provisional/...`

## Policy
- Read `/home/cychou/TLTM/docs/AGENT_GUIDE.md` first.
- Run heavy jobs only via PBS on compute nodes.
- Commit and push production-relevant changes before validation or production submission.
- For cluster02 PBS work, never choose queues ad hoc; consult the persistent scheduling agent first, then live `qstat -Qf`.
- Before remote SSH/PBS/git cleanup work, refresh `codex/state/REMOTE_LIVE_CACHE.json`, `codex/state/WORKTREES.tsv`, and `codex/state/JOBS.tsv`.
- Do not treat top-level `state/` as a single live run state.
- Record task-specific execution in `workspaces/<task_slug>/state/`.

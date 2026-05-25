# M6 Reference Dataset Execution Plan - 2026-05-10

Updated: 2026-05-10 JST

Scope: concrete R1-R4 generation plan for modernization reference datasets. This is separate from Stage3_4 production.

## Execution Boundary

- This plan generates modernization reference datasets, not final production datasets.
- Stage3_4 remains the workflow/design context: `nofb` vs `withfb`, `t=0.35`, `L=2`, `nstep=20`.
- Outputs go under `output/reference/fortran_modernization/m6/`.
- Logs go under `output/logs/fortran_modernization/reference_datasets/`.
- Current local desktop environment has no `qsub`; actual submission must run from the PBS cluster worktree.

## Shared Algorithm/Run Policy

- `nofb == no_fb`
- `withfb == fb_norefine`
- canonical route: Newton -> p28 QN BTN/backflow rescue residual -> reverse gate -> Metropolis
- flow policy: ODEX primary plus solver-internal residual assist; strict final `flow(...)`
- protocol: `local update -> swap -> measure/history/label trace`
- `TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=1e-13`
- `QN_REVERSE_GATE_ENABLED=1`
- `QN_REVERSE_GATE_TOL=1e-8`
- `QN_S1_PROBE_MAX_ITER=28`
- `QN_S1_NEAR_RESCUE_ENABLED=0`
- `QN_S1_NONNEAR_RESCUE_ENABLED=0`
- `QN_QUASI_GLOBAL_FALLBACK_ENABLED=0`
- `QN_QUASI_TOL_OVERRIDE=1e-13`
- Stage2 v1alpha sidecars: on
- Stage2 protocol audit: auto, fail-on error
- Stage2/eval threads: 1/1

## Configs

| Level | Config | Seeds | Cycles | Output root |
| --- | --- | ---: | ---: | --- |
| R1 | `docs/modernization_reference_t035_r1_4seed_1k.json` | 4 | 1,000 | `output/reference/fortran_modernization/m6/r1_4seed_1k` |
| R2 | `docs/modernization_reference_t035_r2_10seed_10k.json` | 10 | 10,000 | `output/reference/fortran_modernization/m6/r2_10seed_10k` |
| R3 | `docs/modernization_reference_t035_r3_32seed_50k.json` | 32 | 50,000 | `output/reference/fortran_modernization/m6/r3_32seed_50k` |
| R4 | `docs/modernization_reference_t035_r4_128seed_100k.json` | 128 | 100,000 | `output/reference/fortran_modernization/m6/r4_128seed_100k` |

## PBS Artifacts

- Preflight/build: `codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_preflight_build.pbs`
- Chunk runner: `codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_chunk.pbs`
- Level merge: `codex/workspaces/fortran_modernization/tasks/pbs/m6_reference_merge_level.pbs`
- Submit launcher wrapper: `codex/workspaces/fortran_modernization/tasks/scripts/submit_m6_reference_datasets.sh`
- Dynamic queue planner: `codex/workspaces/fortran_modernization/tasks/scripts/submit_m6_reference_dynamic.py`
- Queue policy: `codex/workspaces/fortran_modernization/runbooks/M6_DYNAMIC_QUEUE_POLICY_20260510.md`

## Queue/Chunk Strategy

The current launcher uses manual-aware dynamic PBS queue selection rather than a fixed queue table.

Static dataset geometry:

- R1: 1 chunk per method, 4 seeds per chunk, 4 workers per chunk.
- R2: 1 chunk per method, 10 seeds per chunk, 10 workers per chunk.
- R3: 4 chunks per method, 8 seeds per chunk, 8 workers per chunk.
- R4: 16 chunks per method, 8 seeds per chunk, 8 workers per chunk.

Queue policy:

- submit R1-R4 chunks concurrently after a shared build/preflight dependency;
- use more, smaller R4 chunks to reduce long-tail risk and spread across available queues;
- keep one seed per worker to avoid oversubscription and preserve simple timing interpretation;
- submit `no_fb` and `fb_norefine` independently but with matched seed offsets.
- use only CPU queues that are valid for one-node jobs by default: `C8`, `C8-LONG`, `C12`, `C12-LONG`, `C16`, and `F`;
- exclude `G`, `G-LONG`, `G-A100`, `C24`, `C36`, and `C12-LONG2` by default;
- treat `C17`/`C17-LONG` as conditional: cnode37 passed 2026-05-25/26 Stephanov N6 withfb 8-core probes, but cnode38/cnode39 lack node-local `git` and fail the current PBS git guard with `Exit_status=127`; use them only after known-good placement or a gitless guard is available;
- score live `qstat -Qf` queue state at submission time and record the final queue assignment in the submit manifest and JSON queue plan.

## Cluster Submit Command

Remote repository guard for PBS/queue work:

- commit local changes before submission;
- push the target branch to `origin`;
- SSH to `cychou@ithems_fe02.intra.riken.jp`;
- update the remote target worktree by fast-forward only;
- verify the remote branch, commit, clean status, and `qsub`;
- submit only from the verified remote worktree.

Current target worktree for this branch:

Note: this path/branch name is a legacy carryover from the earlier QN error-handling validation slice. The control-plane target id is now `fortran_modernization_m6_active`, but the physical worktree/branch must not be renamed while pinned PBS jobs still depend on it.

```bash
/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation
```

Run from the verified cluster worktree:

```bash
cd /lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation
bash codex/workspaces/fortran_modernization/tasks/scripts/submit_m6_reference_datasets.sh
```

Dry-run command:

```bash
bash codex/workspaces/fortran_modernization/tasks/scripts/submit_m6_reference_datasets.sh --dry-run
```

Expected behavior:

- one preflight/build job is submitted first;
- all R1-R4 chunk jobs depend on the build job;
- each level merge job depends on all chunks for that level;
- a submit manifest is written under `output/logs/fortran_modernization/reference_datasets/submit/`.
- a JSON queue plan is written under `output/logs/fortran_modernization/reference_datasets/submit/`.

## Post-Generation Outputs

Each level should contain:

- `no_fb/per_seed_summary_table.csv`
- `no_fb/aggregated_summary_table.csv`
- `no_fb/protocol_audit_summary.csv`
- `fb_norefine/per_seed_summary_table.csv`
- `fb_norefine/aggregated_summary_table.csv`
- `fb_norefine/protocol_audit_summary.csv`
- `reference_aggregate_comparison.csv`
- `reference_manifest.json`
- `reference_registry_rows.tsv`

## Current Status

- Configs and PBS scripts are prepared.
- The original static submission wave exposed queue-policy errors: GPU queues were used for CPU chunks, `C17/C17-LONG` showed production-shape `Exit_status=127`, and `qmove` was not a reliable repair path.
- The launcher has been replaced with a dynamic manual-aware queue planner.
- The currently active cluster jobs remain pinned to commit `a1028ad`; do not fast-forward that active worktree until those jobs finish or are canceled.
- Future submissions should use the dynamic launcher from a verified cluster worktree after local commit and push.

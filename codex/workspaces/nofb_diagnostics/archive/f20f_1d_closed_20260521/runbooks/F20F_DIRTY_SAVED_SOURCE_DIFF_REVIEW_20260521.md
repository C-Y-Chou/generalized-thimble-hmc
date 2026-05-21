# F20F Dirty Saved Source-Diff Review

Date: 2026-05-21 JST

Status: review complete.  No source patch should be ported from this dirty
worktree into the current canonical branch.

## Reviewed Path

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_dirty_saved_20260517T035700Z
```

Dirty worktree state:

- branch: `codex/fortran-modernization`
- dirty HEAD: `243c09ceb99f`
- dirty entries: `53`
- tracked diffs: `31`
- untracked files: `22`

Current local canonical branch used for comparison:

- path: `/Users/ccy/Documents/TLTM_fortran_modernization`
- branch: `codex/fortran-modernization`
- HEAD at review time: `49861f45c848819b6da77f9627c6429f3bb2b8a8`

The remote execution worktree
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization` was still at
`8c76fdf710ff` during this review, so the final comparison was made against the
local current branch, not only against the remote execution tree.

## Archive Coverage

The dirty content is already preserved in:

```text
/lustre1/home/cychou/TLTM_worktrees/archive/f20f_precleanup_20260521/fortran_modernization_dirty_archive_20260517T034954Z
```

Archive packet contents:

| file | role |
| --- | --- |
| `HEAD.txt` | records `243c09ceb99fd435b83b570db805174e6fa965ef` |
| `branch.txt` | records `codex/fortran-modernization` |
| `git_status_short.txt` | records all 53 dirty entries |
| `git_diff_stat.txt` | records tracked diff size |
| `tracked_dirty.patch` | full tracked patch, `501525` bytes |
| `untracked_files.tar.gz` | untracked payload, `56317` bytes |
| `untracked_files.txt` / `untracked_files.zlist` | untracked file lists |

This means the full dirty worktree is no longer needed as the only copy of the
diff.

## Classification Summary

Compared with local current `49861f4`:

| class | count | disposition |
| --- | ---: | --- |
| identical to current | 20 | already upstreamed; no action |
| differs from current | 31 | current branch is newer; archive-only, do not port |
| missing in current | 2 | top-level scratch copies; archive-only |

By area:

| area | count | disposition |
| --- | ---: | --- |
| docs/runbooks/tasks/docs | 24 | 17 already upstreamed; 7 superseded by newer current docs/state |
| source/test/build/scripts | 22 | 2 already upstreamed, 2 scratch copies, remaining source/test patches superseded |
| state/context | 7 | superseded by newer current state and F20F cleanup records |

## Main Finding

The dirty worktree is an older F18b/Hairer-controller intermediate.  It is not a
missing production patch.

Evidence:

- Dirty `src/physics/odex_backend.f90` keeps
  `odex_controller_policy_tltm_endpoint = 0` and lacks the current live Hairer
  controller state-machine route.
- Current `src/physics/odex_backend.f90` has the later route where
  `odex_controller_policy_tltm_endpoint` is a compatibility alias for
  `odex_controller_policy_hairer_experimental`, plus
  `odex_step_hairer_controller*`, controller action/state types, and the richer
  Hairer branch counters.
- Dirty `F18B5_ODEX_HAIRER_ALIGNMENT_REPLAN_20260516.md` stops around the
  "next actionable F18b.5a" replan stage.
- Current `F18B5_ODEX_HAIRER_ALIGNMENT_REPLAN_20260516.md` records the later
  F18b.5a through F18b.5j sequence, including 1k/10k telemetry, h-min/failure
  floor closure, and default-route adoption.
- Dirty `solve_flow`, `tltm_stage2_driver`, and
  `scripts/run_stage3_3_multiseed.py` contain earlier ODEX diagnostics plumbing;
  current branch has the richer ODEX stats/context columns and later diagnostic
  aggregation route.

Therefore, porting the dirty source patch would move current code backward.

## File-Level Disposition

| disposition | files |
| --- | --- |
| already upstreamed | `F18B3A_ODEX_FLOW_STATE_PRODUCTIZATION_20260516.md`; `F18B3_ODEX_FLOW_STATE_AND_BEHAVIOR_CORRECTION_DECISION_20260516.md`; `F18B4B_ODEX_CONTROLLER_BOUNDS_ORDER_ALIGNMENT_20260516.md`; `F18B4C_ODEX_INITIALIZATION_ALIGNMENT_BLOCKED_20260516.md`; `F18B4D_HAIRER_CONTROLLER_ROUTE_SKELETON_20260516.md`; `F18B4E_HAIRER_DELTA_MAP_AND_OPTIN_GATE_20260516.md`; `F18B4G_ODEX_API_GUARD_HARDENING_20260516.md`; `F18B4H_ODEX_COUNTER_AND_PROMOTION_ALIGNMENT_20260516.md`; `F18B4I_ODEX_INVALID_RHS_CLASSIFICATION_20260516.md`; `F18B4J_HAIRER_OUTER_CONTROLLER_ATTEMPT_BLOCKED_20260516.md`; `F18B4M_HAIRER_OUTER_CONTROLLER_REMOTE_SCREEN_20260516.md`; `F18B4O_ODEX_TELEMETRY_POLICY_COMPARE_10seed_1k_20260516.pbs`; `F18B4O_ODEX_TELEMETRY_POLICY_COMPARE_20260516.md`; `F18B4_ODEX_CONTROLLER_PAPER_ALIGNMENT_PLAN_20260516.md`; `F18B_CONTROLLER_DECISION_PACKET_20260516.md`; `F18B_HANDWRITTEN_ODEX_ENDPOINT_HARDENING_20260516.md`; `docs/production_comparison_official_dfols_20260511_10seed_1k_nofb_withfb.json`; `f18b4m_hairer_outer_npt5_r0055_10seed_10k_20260516.pbs`; `scripts/inventory_fortran_state.py`; `src/sampler/markovchain_mod.f90` |
| superseded source/test patch | `build/makefile`; `scripts/run_m4_guardrails.py`; `scripts/run_stage3_3_multiseed.py`; `src/physics/odex_backend.f90`; `src/physics/solve_flow.f90`; `src/sampler/hmc.f90`; `src/sampler/hmc_constraints.f90`; `src/sampler/hmc_integrator_core.f90`; `src/sampler/markovchain_metropolis.f90`; `src/sampler/quasi_newton_solver.f90`; `src/sampler/tltm_run_context.f90`; `src/sampler/tltm_stage1_driver.f90`; `src/sampler/tltm_stage2_driver.f90`; `tests/test_odex_backend_package_contract.f90`; `tests/test_odex_controller_alignment_spec.f90`; `tests/test_odex_controller_observation_contract.f90`; `tests/test_odex_foundation_contract.f90`; `tests/test_odex_result_contract.f90` |
| superseded docs/state | `ALL_HANDWRITTEN_LINE_AUDIT_REQUIREMENT_20260516.md`; `F18B4F_PRE_IMPLEMENTATION_HANDWRITTEN_ODEX_LINE_AUDIT_20260516.md`; `F18B5_ODEX_HAIRER_ALIGNMENT_REPLAN_20260516.md`; `HANDWRITTEN_MISMATCH_RESOLUTION_TABLE_20260516.md`; `M5_STATE_CONFIG_OWNERSHIP_INVENTORY_SUMMARY.md`; `WORKSTREAM_MATRIX_AND_CURRENT_POSITION.md`; `codex/workspaces/fortran_modernization/context/STATE_BRIEF.md`; `CAVEATS.tsv`; `M5_STATE_CONFIG_OWNERSHIP_INVENTORY.tsv`; `OPEN_ITEMS.tsv`; `POST_B_RNG_REFERENCE_ANCHOR_V1.json`; `SCRIPT_EVIDENCE_AUDIT_20260512.tsv`; `session_log.md` |
| scratch duplicate archive-only | top-level `odex_backend.f90`; top-level `test_odex_backend_package_contract.f90` |

## Git Metadata Caution

Do not remove this dirty worktree with `git worktree remove`.

Its `.git` file points at:

```text
/lustre1/home/cychou/TLTM/.git/worktrees/fortran_modernization
```

That legacy metadata record claims the path:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization
```

but that path is now the standalone canonical execution worktree with its own
self-contained `.git` directory.  Using legacy `git worktree remove` against
that record risks targeting the canonical path.  If the dirty saved tree is
deleted later, use a plain path deletion for the saved copy after confirming the
archive packet exists, and handle the stale legacy metadata separately.

## Decision

No dirty source, test, script, state, or doc change should be ported from
`fortran_modernization_dirty_saved_20260517T035700Z`.

Recommended next cleanup action, only after explicit approval:

1. Delete the dirty saved directory with `rm -rf --` on the dirty saved path.
2. Do not use `git worktree remove` for that path.
3. Leave the archive packet under
   `/lustre1/home/cychou/TLTM_worktrees/archive/f20f_precleanup_20260521/`.
4. Separately review stale legacy metadata in
   `/lustre1/home/cychou/TLTM/.git/worktrees/fortran_modernization` if the old
   `/lustre1/home/cychou/TLTM` control-plane registry still matters.

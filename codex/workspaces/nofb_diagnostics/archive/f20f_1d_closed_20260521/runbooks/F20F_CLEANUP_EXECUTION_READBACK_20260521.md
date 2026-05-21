# F20F Cleanup Execution Readback

Date: 2026-05-21 JST

Status: first approved cleanup pass completed.

## Scope Executed

The approved cleanup command list in
`F20F_CLEANUP_COMMANDS_FOR_APPROVAL_20260521.md` was executed through Phase A-D.

Executed actions:

- moved the old dirty archive packet to:
  `/lustre1/home/cychou/TLTM_worktrees/archive/f20f_precleanup_20260521/fortran_modernization_dirty_archive_20260517T034954Z`
- removed approved canonical F20F linked worktrees:
  - `fortran_modernization_l1_eps_aggressive_cf294e4`
  - `fortran_modernization_l1_eps_scan_6d6f8bd`
  - `fortran_modernization_l1_eps_scan_96595ed`
  - `fortran_modernization_l1_eps_scan_e206903`
  - `fortran_modernization_lscan_eps010_68b829a`
  - `fortran_modernization_tltm_nofb_l1n2_128x200k_2d8e40e`
  - `fortran_modernization_tltm_nofb_l1n2_ba4e8d1`
  - `fortran_modernization_tltm_nofb_l1n2_dd49a13`
- removed old clean worktrees:
  - `fortran_modernization_f12_wrapper_scratch_20260517T032346Z`
  - `fortran_modernization_f18b5f`
- removed compact-only, failed, or superseded F20F output/log roots listed in
  the approval command list.

## Held Out

The following path was not deleted:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_dirty_saved_20260517T035700Z
```

Reason: it is a dirty legacy-linked worktree at `243c09ceb99f` with 53 dirty
entries.  It needs a separate source-diff decision before archive/delete.

The source-diff review was completed after this cleanup pass:

```text
codex/workspaces/nofb_diagnostics/runbooks/F20F_DIRTY_SAVED_SOURCE_DIFF_REVIEW_20260521.md
```

Review conclusion: no source/test/script/state/doc change should be ported.
The dirty tree is an older F18b/Hairer-controller intermediate, and the full
patch/untracked payload is already preserved in the archive packet moved by
this cleanup pass.

## Verification

`qstat -u cychou` was empty before cleanup and empty after cleanup.

The canonical git worktree list under current `fortran_modernization` now
contains only:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization
/lustre1/home/cychou/TLTM_worktrees/stage2_replica_parallelism
```

The stage2 worktree was not modified.

The legacy `/lustre1/home/cychou/TLTM` worktree registry no longer contains
`fortran_modernization_f18b5f`.

## Canonical Evidence Retained

All required keep paths passed existence checks:

- TLTM `t=0.3` F20F preset output/log roots.
- fixed-flow `t=0.3` base128 and extension384 output/log roots.
- fixed-flow `t=0.5` nofb 128seed output/log roots.
- TLTM `t=0.5` low005 base32 and topup96 output/log roots.
- held-out dirty saved worktree.
- archived dirty packet under the new archive namespace.

## Removed Path Checks

The verification pass confirmed these representative approved paths are gone:

- `fortran_modernization_dirty_archive_20260517T034954Z` from active worktree namespace.
- `fortran_modernization_f12_wrapper_scratch_20260517T032346Z`.
- `fortran_modernization_f18b5f`.
- all approved F20F scan/TLTM nofb linked worktrees.
- route-smoke fixed-flow `t=0.3` output/log roots.
- repaired nofb `L=1,nstep=2` 32seed x 50k compact-only output root.
- failed 128seed nofb `L=1,nstep=2` log root.

The full compact-only/failed path list remains preserved in
`F20F_CLEANUP_COMMANDS_FOR_APPROVAL_20260521.md`.

## Dirty Saved Removal Follow-Up

After the source-diff review concluded that no dirty patch should be ported,
`fortran_modernization_dirty_saved_20260517T035700Z` was deleted with plain
path removal, not `git worktree remove`.

Verification:

- archive packet remained present after deletion;
- remote canonical modernization execution tree was clean before sync;
- remote canonical modernization execution tree was fast-forwarded from
  `8c76fdf710ff` to `a104816f5b94`;
- no production PBS jobs were submitted.

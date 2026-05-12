# QN Validation Tree Retirement Protocol

Updated: 2026-05-12 JST

## Target

`qn_error_handling_validation_official_dfols`

- Remote path:
  `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation`
- Branch:
  `codex/qn-error-handling-validation-official-dfols`
- Current classification:
  `retired_deleted_tombstone`

## Decision

The `qn_error_handling_validation` name is misleading and should not remain an
active lane. It is not production, not canonical modernization, and not the
place for future production restart or scale-up.

User accepted the deletion protocol on 2026-05-12 JST:

1. Quarantine the target first.
2. Allow read-only inventory only.
3. Do not run production, modernization, validation, or scale-up from it.
4. Confirm there are no unique unmerged commits, unique unarchived outputs, or
   active/pinned jobs.
5. Delete the remote worktree only after explicit final confirmation.
6. Decide branch deletion separately from worktree deletion.

## Current Rules

- Do not recreate this worktree or branch name.
- Do not submit PBS jobs from this path.
- Use the rehomed M6 reference paths or the retirement archive paths below.
- Keep this runbook as the tombstone for historical references to the old name.

## Step 2 Inventory Checklist

Read-only checks before deletion:

- live remote path exists or not;
- branch and commit;
- dirty state;
- active PBS jobs using this path;
- unpushed commits relative to canonical branches;
- unique output/log directories not already archived;
- references from `codex/state`, runbooks, PBS scripts, and dataset registries;
- whether the branch itself should be retained, archived, renamed, or deleted.

## Step 2 Inventory Readback

Read-only inventory completed on 2026-05-12 JST.

Code/worktree state:

- Live path exists:
  `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation`
- Checked-out branch:
  `codex/qn-error-handling-validation-official-dfols`
- Checked-out commit:
  `ad91c2d2eabcfdfe98acfe77c806f94cec4bca25`
- Dirty state: clean.
- Active PBS jobs using this path: none.
- The checked-out commit is identical to
  `codex/tltm-production-comparison-official-dfols` in the remote control
  mirror.
- There are no commits unique to
  `codex/qn-error-handling-validation-official-dfols` relative to
  `codex/tltm-production-comparison-official-dfols`.
- There are no commits unique to
  `codex/qn-error-handling-validation-official-dfols` relative to
  `codex/fortran-modernization`; instead `codex/fortran-modernization` is one
  commit ahead at `709a7de721b2d03b10be0a87bd60c223124301fd`.
- The old historical branch `codex/qn-error-handling-validation` still exists
  locally in the remote mirror at
  `a1028ad6d68eabfd6c400ec135b3df9cab1e4af2`.
- `origin/codex/qn-error-handling-validation-official-dfols` was not present in
  the remote mirror during this readback; branch cleanup should therefore be
  decided as a local-remote-mirror branch cleanup item, not assumed to be an
  origin branch deletion.

Artifact state:

- `output/` is not disposable yet:
  59G, 11245 files.
- Key material present only under this worktree in the checked targets:
  - `output/reference/fortran_modernization/m6`: 59G, 9964 files.
  - `output/logs/fortran_modernization/reference_datasets`: 188M, 807 files.
  - `output/tests/odex_validation/20260509_10seed_10k_qnclean_fb_norefine_ct1e13_qn1e13`:
    29M, 184 files.
  - `output/tests/qn_error_handling/20260509_10seed_10k_fb_norefine_ct1e13_qn1e13`:
    29M, 183 files.
- The same artifact directories were missing from:
  - `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
  - `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`
  - `/lustre1/home/cychou/TLTM`
  - `/home/cychou/TLTM`

Conclusion:

- The code worktree/branch is safe to keep quarantined as a deletion candidate.
- Remote worktree deletion is blocked until the M6/reference and ODEX/QN-clean
  artifacts are either migrated to an accepted artifact location or explicitly
  abandoned by user decision.
- Do not run new work here while artifacts are being triaged.

## Proposed End State

After inventory passes:

- remove remote worktree path;
- mark target as deleted/retired in control-plane registries;
- keep a short tombstone entry pointing to this runbook;
- decide separately whether to delete the branch
  `codex/qn-error-handling-validation-official-dfols`.

## Deletion Execution Readback

Completed on 2026-05-12 JST after user requested execution through deletion.

Artifact rehome/archive:

- M6 reference packages moved to canonical modernization remote output:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/reference/fortran_modernization/m6`
  - size: 59G
  - files: 9964
- M6 reference logs moved to canonical modernization remote output logs:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/fortran_modernization/reference_datasets`
  - size: 188M
  - files: 807
- Remaining historical output moved to:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/archive/qn_error_handling_validation_retired_20260512/output_remaining_after_m6_rehome`
  - size: 59M
  - files: 474
- Remote retirement manifest:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/archive/qn_error_handling_validation_retired_20260512/RETIREMENT_MANIFEST.txt`

Deletion:

- Removed worktree:
  `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation`
- Pruned remote worktree metadata from `/home/cychou/TLTM`.
- Deleted local remote-mirror branches:
  - `codex/qn-error-handling-validation-official-dfols`
  - `codex/qn-error-handling-validation`
- Deleted origin branch in the remote bare mirror:
  - `origin/codex/qn-error-handling-validation`
- Final ref check found no remaining `qn-error-handling-validation` refs.

Final state:

- The old worktree path no longer exists.
- The old qn validation branch names no longer exist in the remote mirror.
- The control-plane retains only a deleted tombstone target for historical
  lookup.

# F20F Cleanup Commands For Approval

Date: 2026-05-21 JST

Status: executed after explicit approval on 2026-05-21 JST.

Execution readback:

- Phase A-D completed successfully.
- `qstat -u cychou` was empty before and after cleanup.
- Canonical raw evidence roots all passed existence checks.
- Approved F20F linked worktrees and compact-only/failed roots were removed.
- `fortran_modernization_dirty_saved_20260517T035700Z` was held out and remains
  untouched.
- Detailed readback:
  `codex/workspaces/nofb_diagnostics/runbooks/F20F_CLEANUP_EXECUTION_READBACK_20260521.md`

## Safety Readback

- `qstat -u cychou` is empty as of this review.
- `fortran_modernization_l1_eps_scan_96595ed` has one dirty entry:
  untracked `.venv-dfols`; it is safe to remove with `--force` if approved.
- `fortran_modernization_dirty_saved_20260517T035700Z` is not safe to delete in
  this pass.  It is a legacy-linked dirty worktree at `243c09ceb99f` with
  `53` dirty entries.
- `fortran_modernization_dirty_archive_20260517T034954Z` is already a small
  archive packet, not a git worktree.  Move it under an archive namespace rather
  than delete it.

## Hold Out Of This Pass

Do not delete:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_dirty_saved_20260517T035700Z
```

Reason: dirty legacy-linked worktree with source/state edits.  It needs a
separate source-diff decision.

## Phase A: Move Existing Dirty Archive Packet

This only moves an already-created patch/archive packet out of the active
worktree namespace.

```bash
ssh cychou@ithems_fe02.intra.riken.jp 'bash -s' <<'REMOTE'
set -euo pipefail

ARCH=/lustre1/home/cychou/TLTM_worktrees/archive/f20f_precleanup_20260521
mkdir -p "$ARCH"

mv -n \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_dirty_archive_20260517T034954Z \
  "$ARCH"/
REMOTE
```

## Phase B: Remove Linked Canonical F20F Worktrees

These are registered under the current canonical standalone
`fortran_modernization` git repository.  Use `git worktree remove` so git
metadata is cleaned together with the directory.

```bash
ssh cychou@ithems_fe02.intra.riken.jp 'bash -s' <<'REMOTE'
set -euo pipefail

CANON=/lustre1/home/cychou/TLTM_worktrees/fortran_modernization

git -C "$CANON" worktree remove --force /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_l1_eps_aggressive_cf294e4
git -C "$CANON" worktree remove --force /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_l1_eps_scan_6d6f8bd
git -C "$CANON" worktree remove --force /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_l1_eps_scan_96595ed
git -C "$CANON" worktree remove --force /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_l1_eps_scan_e206903
git -C "$CANON" worktree remove --force /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_lscan_eps010_68b829a
git -C "$CANON" worktree remove --force /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_tltm_nofb_l1n2_128x200k_2d8e40e
git -C "$CANON" worktree remove --force /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_tltm_nofb_l1n2_ba4e8d1
git -C "$CANON" worktree remove --force /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_tltm_nofb_l1n2_dd49a13

git -C "$CANON" worktree prune
REMOTE
```

## Phase C: Remove Standalone Or Legacy-Linked Old Worktrees

`fortran_modernization_f12_wrapper_scratch_20260517T032346Z` is a clean
standalone clone.  `fortran_modernization_f18b5f` is a clean detached worktree
registered under the older `/lustre1/home/cychou/TLTM` git metadata; removing it
requires the legacy common directory only to clean git worktree metadata.

```bash
ssh cychou@ithems_fe02.intra.riken.jp 'bash -s' <<'REMOTE'
set -euo pipefail

rm -rf -- /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_f12_wrapper_scratch_20260517T032346Z

git -C /lustre1/home/cychou/TLTM worktree remove --force \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization_f18b5f
git -C /lustre1/home/cychou/TLTM worktree prune
REMOTE
```

## Phase D: Remove Compact-Only And Failed/Superseded Output Roots

These roots are not final raw evidence.  Their compact provenance is already in
`F20F_COMPACT_PACKETS_20260521.md`, `F20F_1D_TOY_FINAL_SUMMARY_20260521.md`,
and the state TSVs.

```bash
ssh cychou@ithems_fe02.intra.riken.jp 'bash -s' <<'REMOTE'
set -euo pipefail

rm -rf -- \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_2seed_x_100cycles_31b5ae632c97 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t030/f20f_fixed_flow_t030_2seed_x_100cycles_31b5ae632c97 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t030/f20f_fixed_flow_t030_2seed_x_100cycles_b7d71bbfa0d5 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_2seed_x_100cycles_63ca31215b43 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_2seed_x_100cycles_63ca31215b43 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_2seed_x_100cycles_dad5c8c7d995 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050_l1_epsilon_scan/f20f_fixed_flow_t050_nofb_l1_epsilon_scan_3cand_4seed_x_5000cycles_cf294e4d3d7d \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050_l1_epsilon_scan/f20f_fixed_flow_t050_nofb_l1_epsilon_scan_3cand_4seed_x_5000cycles_cf294e4d3d7d \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050_l1_epsilon_scan/f20f_fixed_flow_t050_nofb_l1_epsilon_scan_5cand_4seed_x_5000cycles_6d6f8bdf2f33 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050_l1_epsilon_scan/f20f_fixed_flow_t050_nofb_l1_epsilon_scan_5cand_4seed_x_5000cycles_6d6f8bdf2f33 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050_l1_epsilon_scan/f20f_fixed_flow_t050_nofb_l1_epsilon_scan_5cand_4seed_x_5000cycles_96595edfd402 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050_l1_epsilon_scan/f20f_fixed_flow_t050_nofb_l1_epsilon_scan_5cand_4seed_x_5000cycles_e2069034b9e5 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050_l1_epsilon_scan/f20f_fixed_flow_t050_nofb_l1_epsilon_scan_5cand_4seed_x_5000cycles_e2069034b9e5 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050_l_scan/f20f_fixed_flow_t050_nofb_l_scan_eps010_4cand_4seed_x_5000cycles_68b829a5b895 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050_l_scan/f20f_fixed_flow_t050_nofb_l_scan_eps010_4cand_4seed_x_5000cycles_68b829a5b895 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_ladder_scan/f20f_tltm_t050_nofb_ladder_scan_4seed_x_5000cycles_f2a51e712fc1 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_ladder_scan/f20f_tltm_t050_nofb_ladder_scan_4seed_x_5000cycles_f2a51e712fc1 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_50000cycles_d2a365e0a195 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_50000cycles_d2a365e0a195 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_nofb_validation/f20f_tltm_t050_low005_nofb_l1_nstep2_32seed_x_50000cycles_ba4e8d14cead \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_nofb_validation/f20f_tltm_t050_low005_nofb_l1_nstep2_32seed_x_50000cycles_ba4e8d14cead \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_nofb_validation/f20f_tltm_t050_low005_nofb_l1_nstep2_32seed_x_50000cycles_dd49a1315fd8 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_nofb_validation/f20f_tltm_t050_low005_nofb_l1_nstep2_128seed_x_200000cycles_2d8e40e2d7ff
REMOTE
```

## Post-Cleanup Verification

```bash
ssh cychou@ithems_fe02.intra.riken.jp 'bash -s' <<'REMOTE'
set -euo pipefail

qstat -u cychou

git -C /lustre1/home/cychou/TLTM_worktrees/fortran_modernization worktree list --porcelain

for p in \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20_double_tolerance_validation/f20f_double_ode1e14_ntqn1e13_dfols1e16_model1e26_most_conservative_r3_32seed_50k_59e9d10acd35 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_128seed_x_200000cycles_a678d2c0cd1f \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_extension384seed_x_200000cycles_8cfbc0747305 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_128seed_x_200000cycles_704400c15fe1 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8 \
  /lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_topup96_to128_x_200000cycles_8c76fdf710ff
do
  test -d "$p"
done
REMOTE
```

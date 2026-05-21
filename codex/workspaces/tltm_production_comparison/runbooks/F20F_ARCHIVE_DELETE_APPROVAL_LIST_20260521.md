# F20F Archive And Delete Approval List

Date: 2026-05-21 JST

Status: approval list plus cleanup basis.  Remote cleanup readback is recorded
in `runbooks/F20F_REMOTE_CLEANUP_READBACK_20260521.md`.

This list follows the no-rerun F20F production-facing packet.  The goal is to
keep the minimal raw-data set that supports the final 1D conclusions and to
make the remaining cleanup decision explicit before any destructive operation.

## Must Keep

Keep these as canonical production-facing evidence until the data are archived
in a separate immutable store:

| bucket | path kind | path |
| --- | --- | --- |
| `TLTM_t030` | output | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20_double_tolerance_validation/f20f_double_ode1e14_ntqn1e13_dfols1e16_model1e26_most_conservative_r3_32seed_50k_59e9d10acd35` |
| `TLTM_t030` | logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20_double_tolerance_validation/f20f_double_ode1e14_ntqn1e13_dfols1e16_model1e26_most_conservative_r3_32seed_50k_59e9d10acd35` |
| `fixed_flow_t030` | output | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_128seed_x_200000cycles_a678d2c0cd1f` |
| `fixed_flow_t030` | logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t030/f20f_fixed_flow_t030_128seed_x_200000cycles_a678d2c0cd1f` |
| `fixed_flow_t030` | output | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_extension384seed_x_200000cycles_8cfbc0747305` |
| `fixed_flow_t030` | logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t030/f20f_fixed_flow_t030_extension384seed_x_200000cycles_8cfbc0747305` |
| `fixed_flow_t050` | output | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_128seed_x_200000cycles_704400c15fe1` |
| `fixed_flow_t050` | logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_128seed_x_200000cycles_704400c15fe1` |
| `TLTM_t050` | output | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8` |
| `TLTM_t050` | logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8` |
| `TLTM_t050` | output | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_topup96_to128_x_200000cycles_8c76fdf710ff` |
| `TLTM_t050` | logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_topup96_to128_x_200000cycles_8c76fdf710ff` |
| active worktree | source/output owner | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization` |
| dirty archive | provenance archive | `/lustre1/home/cychou/TLTM_worktrees/archive/f20f_precleanup_20260521/fortran_modernization_dirty_archive_20260517T034954Z` |

The previously reviewed dirty saved worktree
`/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_dirty_saved_20260517T035700Z`
has already been removed after archive coverage was verified.

## Compact-Only Candidates

These can be deleted only after the compact packets and registries remain
committed and pushed.  They are not part of the final raw evidence:

| class | representative paths |
| --- | --- |
| fixed-flow `t=0.3` route smoke | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_2seed_x_100cycles_31b5ae632c97`; matching log root |
| fixed-flow `t=0.5` route smoke | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_2seed_x_100cycles_63ca31215b43`; matching log root |
| fixed-flow `t=0.5` L and epsilon scans | `f20f_fixed_flow_t050_l_scan/*68b829a5b895`; `f20f_fixed_flow_t050_l1_epsilon_scan/*cf294e4d3d7d`; `*6d6f8bdf2f33`; `*e2069034b9e5` |
| TLTM `t=0.5` ladder selection | `f20f_tltm_t050_ladder_scan/f20f_tltm_t050_nofb_ladder_scan_4seed_x_5000cycles_f2a51e712fc1` |
| TLTM `t=0.5` early paired validation | `f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_50000cycles_d2a365e0a195` |
| TLTM `t=0.5` L1/nstep2 speed sanity | `f20f_tltm_t050_nofb_validation/f20f_tltm_t050_low005_nofb_l1_nstep2_32seed_x_50000cycles_ba4e8d14cead` |

The exact inventory is already recorded in:

```text
codex/workspaces/nofb_diagnostics/archive/f20f_1d_closed_20260521/state/F20F_CLEANUP_DRY_RUN_INVENTORY_20260521.tsv
codex/workspaces/nofb_diagnostics/archive/f20f_1d_closed_20260521/state/F20F_PHYSICS_DATASET_GROUPS_20260521.tsv
```

## Delete Candidates

These are log-only, failed, duplicate, or superseded roots.  Delete only after
user approval:

| class | path |
| --- | --- |
| fixed-flow `t=0.3` duplicate smoke logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t030/f20f_fixed_flow_t030_2seed_x_100cycles_b7d71bbfa0d5` |
| fixed-flow `t=0.5` duplicate smoke logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_2seed_x_100cycles_dad5c8c7d995` |
| fixed-flow `t=0.5` failed/superseded scan logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050_l1_epsilon_scan/f20f_fixed_flow_t050_nofb_l1_epsilon_scan_5cand_4seed_x_5000cycles_96595edfd402` |
| TLTM L1/nstep2 superseded failed-attempt logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_nofb_validation/f20f_tltm_t050_low005_nofb_l1_nstep2_32seed_x_50000cycles_dd49a1315fd8` |
| TLTM L1/nstep2 failed 128seed submit logs | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_nofb_validation/f20f_tltm_t050_low005_nofb_l1_nstep2_128seed_x_200000cycles_2d8e40e2d7ff` |

## Worktree Delete Candidates

These remote worktrees are not needed for the final evidence packet after the
compact packets have been committed:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_f12_wrapper_scratch_20260517T032346Z
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_f18b5f
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_l1_eps_aggressive_cf294e4
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_l1_eps_scan_6d6f8bd
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_l1_eps_scan_e206903
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_lscan_eps010_68b829a
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_tltm_nofb_l1n2_128x200k_2d8e40e
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_tltm_nofb_l1n2_ba4e8d1
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_tltm_nofb_l1n2_dd49a13
```

Manual-review worktree before deletion:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization_l1_eps_scan_96595ed
```

## Approval Gate

Before any delete command:

1. User explicitly approves the delete list.
2. `git status` is clean locally and in the active remote modernization tree.
3. No PBS jobs are running for the target roots.
4. Canonical keep roots still exist.
5. The delete command is generated from this list and reviewed before execution.

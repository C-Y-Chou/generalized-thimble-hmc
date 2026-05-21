# F20F Compact Packets

Date: 2026-05-21 JST

Status: compact packet index before deletion.  This file records compact
provenance for roots that should not remain primary raw evidence after cleanup.
It does not authorize deleting raw paths by itself.

## Rules

- Keep the canonical raw roots listed in
  `F20F_1D_TOY_FINAL_SUMMARY_20260521.md`.
- For every `compact_only` or `delete_candidate` root, preserve enough
  information here, in runbooks, and in state TSVs to recover why it existed.
- Do not delete a path until the cleanup dry-run inventory has been reviewed.

## Fixed-Flow t=0.3 Compact Items

| dataset | action | compact evidence |
| --- | --- | --- |
| `f20f_fixed_flow_t030_2seed_x_100cycles_31b5ae632c97` | compact-only | route smoke for fixed-flow `t=0.3`; raw physics superseded by 512seed evidence |
| `f20f_fixed_flow_t030_2seed_x_100cycles_b7d71bbfa0d5` logs | delete candidate after review | log-only superseded smoke root; no matching output root in current inventory |

Canonical replacement:

```text
fixed_flow_t030 = 128seed base + 384seed extension = 512seed x 200k paired
```

## Fixed-Flow t=0.5 Compact Items

| dataset | action | compact evidence |
| --- | --- | --- |
| `f20f_fixed_flow_t050_nofb_2seed_x_100cycles_63ca31215b43` | compact-only | route smoke for fixed-flow `t=0.5`; raw physics superseded by 128seed pathology run |
| `f20f_fixed_flow_t050_nofb_2seed_x_100cycles_dad5c8c7d995` logs | delete candidate after review | log-only superseded smoke root |
| `f20f_fixed_flow_t050_nofb_l_scan_eps010_4cand_4seed_x_5000cycles_68b829a5b895` | compact-only | L scan used to reason about shorter HMC trajectories |
| `f20f_fixed_flow_t050_nofb_l1_epsilon_scan_3cand_4seed_x_5000cycles_cf294e4d3d7d` | compact-only | aggressive epsilon scan |
| `f20f_fixed_flow_t050_nofb_l1_epsilon_scan_5cand_4seed_x_5000cycles_6d6f8bdf2f33` | compact-only | env-fix epsilon scan |
| `f20f_fixed_flow_t050_nofb_l1_epsilon_scan_5cand_4seed_x_5000cycles_e2069034b9e5` | compact-only | path-fix epsilon scan |
| `f20f_fixed_flow_t050_nofb_l1_epsilon_scan_5cand_4seed_x_5000cycles_96595edfd402` logs | delete candidate after review | failed/superseded log-only scan; output root absent in current inventory |

Canonical replacement:

```text
fixed_flow_t050 = nofb 128seed x 200k sign-lock pathology
```

The fixed-flow t=0.5 compact scans were parameter-search and stress-test
supporting evidence.  They are not needed as raw publication evidence once the
128seed pathology root and final TLTM t=0.5 repair root are preserved.

## TLTM t=0.5 Compact Items

| dataset | action | compact evidence |
| --- | --- | --- |
| `f20f_tltm_t050_nofb_ladder_scan_4seed_x_5000cycles_f2a51e712fc1` | compact-only | selected `low005 = [0.05, 0.5]`; all 4 seeds restored high-flow sign motion |
| `f20f_tltm_t050_low005_pair_32seed_x_50000cycles_d2a365e0a195` | compact-only | early paired validation; Re shift not significant, cycle-length validation needed |
| `f20f_tltm_t050_low005_nofb_l1_nstep2_32seed_x_50000cycles_ba4e8d14cead` | compact-only | HMC speed/sanity gate; `L=1,nstep=2` was about `4.64x` faster than old nofb 50k at same scale |
| `f20f_tltm_t050_low005_nofb_l1_nstep2_32seed_x_50000cycles_dd49a1315fd8` logs | delete candidate after review | superseded failed/repaired attempt logs |
| `f20f_tltm_t050_low005_nofb_l1_nstep2_128seed_x_200000cycles_2d8e40e2d7ff` logs | delete candidate after review | failed submit due disabled queue; no scientific output root |

Canonical replacement:

```text
TLTM_t050 = low005 base32 x 200k + topup96 x 200k = 128 paired seeds
```

The final TLTM t=0.5 conclusion is based on the 128 paired dataset, not the
short ladder/50k/no-fallback speed gates.

## Remote Worktree Compact/Deletion Candidates

| worktree | action | compact evidence |
| --- | --- | --- |
| `fortran_modernization_f12_wrapper_scratch_20260517T032346Z` | delete candidate | old wrapper scratch worktree |
| `fortran_modernization_f18b5f` | delete candidate | old clean detached worktree |
| `fortran_modernization_l1_eps_aggressive_cf294e4` | delete candidate | scan output/log roots listed in physics grouping |
| `fortran_modernization_l1_eps_scan_6d6f8bd` | delete candidate | scan output/log roots listed in physics grouping |
| `fortran_modernization_l1_eps_scan_e206903` | delete candidate | scan output/log roots listed in physics grouping |
| `fortran_modernization_lscan_eps010_68b829a` | delete candidate | scan output/log roots listed in physics grouping |
| `fortran_modernization_tltm_nofb_l1n2_128x200k_2d8e40e` | delete candidate | disabled-queue failed submit; no scientific output root |
| `fortran_modernization_tltm_nofb_l1n2_ba4e8d1` | delete candidate | 32seed nofb speed/sanity readback registered |
| `fortran_modernization_tltm_nofb_l1n2_dd49a13` | delete candidate | superseded by repaired ba4e8d1 run |
| `fortran_modernization_dirty_archive_20260517T034954Z` | manual review | inspect before archive/delete |
| `fortran_modernization_dirty_saved_20260517T035700Z` | manual review | dirty with 53 porcelain entries; inspect before archive/delete |
| `fortran_modernization_l1_eps_scan_96595ed` | manual review | dirty with 1 porcelain entry; inspect before archive/delete |

The only active remote worktree after cleanup should be:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization
```

## Deletion Boundary

Before deletion:

1. Confirm `qstat -u cychou` is empty or unrelated.
2. Review `F20F_CLEANUP_DRY_RUN_INVENTORY_20260521.tsv`.
3. Inspect all `manual_review` worktrees.
4. Confirm no final summary references a path marked `delete_candidate` as raw
   evidence.
5. Get explicit approval for the deletion command list.

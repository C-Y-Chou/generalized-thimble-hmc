# F20F Remote Cleanup Readback

Date: 2026-05-21 JST

Status: completed readback.  No canonical raw evidence was removed.

## Scope

The user requested cleanup of the completed 1D F20F local and remote workspace
state.  Remote cleanup was checked against:

```text
codex/workspaces/tltm_production_comparison/runbooks/F20F_ARCHIVE_DELETE_APPROVAL_LIST_20260521.md
```

## Remote Result

The approved compact-only / failed / superseded output roots and stale
worktree candidates were already absent on the remote filesystem.

Readback:

| item class | result |
| --- | --- |
| canonical keep output/log roots | 12/12 present |
| compact-only/delete-candidate output/log roots | 0 removed, 23 already absent |
| stale scan/scratch worktree candidates | 0 removed, 10 already absent |
| active remote worktree | present and retained |

Active remote worktree:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization
```

## Canonical Keep Roots Verified

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20_double_tolerance_validation/f20f_double_ode1e14_ntqn1e13_dfols1e16_model1e26_most_conservative_r3_32seed_50k_59e9d10acd35
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20_double_tolerance_validation/f20f_double_ode1e14_ntqn1e13_dfols1e16_model1e26_most_conservative_r3_32seed_50k_59e9d10acd35
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_128seed_x_200000cycles_a678d2c0cd1f
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t030/f20f_fixed_flow_t030_128seed_x_200000cycles_a678d2c0cd1f
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_extension384seed_x_200000cycles_8cfbc0747305
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t030/f20f_fixed_flow_t030_extension384seed_x_200000cycles_8cfbc0747305
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_128seed_x_200000cycles_704400c15fe1
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_128seed_x_200000cycles_704400c15fe1
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_topup96_to128_x_200000cycles_8c76fdf710ff
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_topup96_to128_x_200000cycles_8c76fdf710ff
```

## Conclusion

Remote cleanup is complete for this 1D F20F closeout.  The remaining remote
F20F payloads are the canonical evidence roots only.

# Legacy Stage Output Cleanup - 2026-05-10

Updated: 2026-05-10 JST

Scope: cleanup after renaming the legacy `stage3_4` workstream to `tltm_production_comparison`, and after confirming that `fortran_modernization` has its own accepted M6 reference datasets.

## Decision

The old `stage3_4` production-comparison outputs are provisional/historical and must be regenerated for future discussion or final publication work. They were therefore cleared from the legacy output namespace after preserving the key readback summary in this runbook and `codex/state/DATASETS.tsv`.

After user confirmation that `fortran_modernization` already has its own reference datasets, legacy Stage1 to Stage3_3 raw outputs and obsolete ODEX validation raw outputs were also cleared. This cleanup does not delete accepted M6 modernization reference packages.

## Cleared Remote Paths

Removed from `/home/cychou/TLTM`:

- `output/tests/stage3_4`
- `output/logs/stage3_4_preprod_validation`
- `output/logs/stage3_4_post_refine_fail_replay_capture`
- `output/logs/stage3_4_judgment_20260508_32seed_50k_p28_rg`
- `output/logs/stage3_4_judgment_20260508_128seed_100k_p28_rg_nofb_fbnorefine`
- root-level legacy `run_stage3_4_*.pbs`

Also removed from `/home/cychou/TLTM` after the second cleanup pass:

- `output/tests/tltm_stage1_summary.dat`
- `output/tests/tltm_stage2_summary.dat`
- `output/tests/tltm_stage2_label_trace.dat`
- `output/tests/tltm_stage2_ref_summary.dat`
- `output/tests/tltm_stage2_ref_label_trace.dat`
- `output/tests/stage2p5_scan`
- `output/tests/stage2p5_long`
- `output/tests/stage3_1`
- `output/tests/stage3_2`
- `output/tests/stage3_3_submit`
- `output/tests/stage3_3_with_rg_redo_1024seed_50k`
- `output/tests/stage3_4_single_seed_reversibility`
- `output/tests/odex_validation`
- `output/logs/stage3_3_200k`
- `output/logs/stage3_3_with_rg_redo_1024seed_50k`
- `output/logs/stage3_3_with_rg_redo_200k`
- `output/logs/stage3_3_ladder_adaptive_t030`
- `output/logs/stage3_3_ladder_fast_scan_500`
- `output/logs/stage3_3_ladder_positive_fast_scan_500`
- matching root-level Stage1 to Stage3 log files under `output/logs`

Before cleanup:

- `output/tests/stage3_4`: `7.0G`
- selected `stage3_4*` logs: about `199.6M`

After the first Stage3_4 cleanup:

- `output/tests`: `25G`
- `output/logs`: `1.1G`
- new production-comparison provisional namespace exists and is empty.

After the second legacy Stage1 to Stage3_3 and obsolete ODEX validation cleanup:

- `output/tests`: `52M`
- `output/logs`: `207M`

## New Output Namespace

Prepared in the production-comparison worktree:

```text
/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison/output/production_comparison/provisional
/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison/output/logs/production_comparison/provisional
```

Future provisional production-comparison runs should write there instead of creating new `output/tests/stage3_4/...` folders.

## Preserved Stage3_4 Summary

Legacy 128-seed / 100k provisional comparison:

- Config: `docs/stage_3_4_t035_paired_128seed_100k_rg_nofb_fbnorefine.json`
- Methods: `no_fb`, `fb_norefine`
- Seeds: `128`
- Cycles per seed: `100000`
- Physical point: `t=0.35,L=2,nstep=20`
- RG on, p28, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`
- Merge/report job remembered from prior run: `14295.anode01`
- Clean remote commit remembered from prior run: `2f91236387004c8d95ddcdece19042272cf25e67`

| method | n_seeds | mean Re | mean Im | Zmean Re | Zmean Im | unresolved failures | reverse-gate rejects | mean runtime |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `no_fb` | 128 | -0.0014091949 | -0.0002987754 | -0.2582757386 | -0.1002676589 | 946129 | 136997 | 9725.480457 |
| `fb_norefine` | 128 | -0.0013410966 | 0.0000429799 | -0.3250566536 | 0.0174031348 | 224439 | 200447 | 11405.412791 |

Preserved interpretation:

- `fb_norefine` reduced unresolved failures by `721690`.
- `fb_norefine` increased reverse-gate rejects by `63450`.
- `fb_norefine` greatly improved unresolved-failure robustness and Im bias/scatter, but ran slower and did not improve Re `Zmean` over `no_fb`.
- This dataset remains `historical_provisional`; it is not a final publication dataset.

## Preserved Stage3_3 Summary

Legacy Stage3_3 RG redo output was treated as historical and cleared after preserving the high-level readback.

- Config: `docs/stage_3_3_minimal_ladder_1024seed_50k.json`
- Methods: `no_fb`, `fb`
- Seeds: `1024`
- Cycles per seed: `50000`
- Physical point: ladder `0.1,0.3`, `max_flow_time=0.3`, `L=2,nstep=20`
- Initial condition: adaptive
- Target virial: `Re=0`, `Im=0`

| method | n_seeds | P68 Re | P95 Re | P68 Im | P95 Im | mean Re | mean Im | std Re | std Im | Zmean Re | Zmean Im | unresolved failures | reverse-gate rejects |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `fb` | 1024 | 0.6875 | 0.9600 | 0.6875 | 0.9561 | 0.0000386538 | 0.000190405 | 0.0708602 | 0.0593446 | 0.0174558 | 0.102671 | 0 | 0 |
| `no_fb` | 1024 | 0.6738 | 0.9580 | 0.6670 | 0.9473 | 0.00348558 | -0.0026213 | 0.0754879 | 0.0631378 | 1.47757 | -1.32855 | 2061954 | 1434185 |

Preserved interpretation:

- `fb` shifted Re/Im closer to the target and removed unresolved failures/reverse-gate rejects in this historical Stage3_3 run.
- This dataset is not a current production-comparison baseline and should not be reused as final evidence.
- Future `nofb` vs `withfb` discussion data should be regenerated in the `tltm_production_comparison` namespace.

## Obsolete ODEX Validation Raw Data

The old `output/tests/odex_validation` tree was cleared because it was an intermediate modernization validation area predating the accepted M6 reference datasets. The preserved state is:

- Status: `obsolete_raw_cleared`
- Superseded by: accepted M6 reference datasets `m6_r1_4seed_1k`, `m6_r2_10seed_10k`, `m6_r3_32seed_50k`, and `m6_r4_128seed_100k`
- Examples of cleared subruns included old `10seed_10k`, `32seed_50k`, `128seed_100k`, solver-assist, and p-budget diagnostic ODEX validation runs.

## Remaining Generated Output

After cleanup, remaining top-level `/home/cychou/TLTM/output/tests` entries are small smoke/audit artifacts, not legacy Stage production raw outputs:

```text
16K  _smoke_rescue_diag
20K  btn_contract
20K  ngport_rg_single_replica_t03_nstep_grid
24K  preprod_smoke
32K  odex_canonical
52K  hamiltonian
64K  odex_wrapper_check
216K tmp_qn_only_smoke
316K _smoke_post_qn_dfols_refine_500_rgenv
316K _smoke_post_qn_initnorm_500
316K _smoke_post_qn_initnorm_500_rgenv
316K _smoke_post_qn_newtonloss_dfols_500_rgenv
320K _smoke_post_newton_refine_500
508K cycle_sufficiency
1.1M local_kernel_debug
7.1M kernel_correctness_audit
42M  local_kernel_ablation
```

## Follow-Up

Future cleanup should target the remaining smoke/audit artifacts only after their owning workstream has registered or summarized them. No legacy Stage1 to Stage3_4 raw production dataset remains in `/home/cychou/TLTM/output/tests`.

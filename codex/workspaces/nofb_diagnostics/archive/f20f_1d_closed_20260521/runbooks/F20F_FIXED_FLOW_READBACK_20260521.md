# F20F Fixed-Flow nofb Diagnostics Readback

Date: 2026-05-21 JST

## Scope

This packet canonicalizes the fixed-flow diagnostic evidence that was generated
from the modernization execution tree:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization
```

It stores only compact readback and stable raw-output paths.  Raw histories are
not committed.

## Dataset Registry

The registry for this packet is:

```text
codex/workspaces/nofb_diagnostics/state/F20F_DATASET_REGISTRY.tsv
```

## t=0.3 Main Dataset

Scale and methods:

```text
512 seeds x 200000 cycles
methods: no_fb, fb_norefine
```

Remote output roots:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_128seed_x_200000cycles_a678d2c0cd1f
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_extension384seed_x_200000cycles_8cfbc0747305
```

Readback note:

- The 384-seed extension has root-level `no_fb` and `fb_norefine` tables.
- The initial 128-seed block has root-level `no_fb` tables.
- The initial 128-seed `fb_norefine` root merge table is missing, but all
  `fb_norefine/chunk_00..15/per_seed_summary_table.csv` chunk tables exist and
  give 128 rows.  The canonical 512-row readback therefore uses chunk-level
  128-row `fb_norefine` evidence plus the 384-row extension root.

Aggregate readback from the 512-row reconstructed packet:

| method | rows | mean Ohat_re | mean Ohat_im | std Ohat_re | std Ohat_im | proposal failures | reverse-gate rejects | mean runtime sec |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| no_fb | 512 | -0.0018257699 | -0.0018512135 | 0.0645655103 | 0.0448121595 | 1260068 | 2868692 | 7768.113366 |
| fb_norefine | 512 | -0.0017898159 | 0.0003013731 | 0.0532733386 | 0.0398588748 | 0 | 0 | 8902.782467 |

Raw `Re z` sign diagnostics:

| method | files | only positive | only negative | both signs | sign changes median | positive fraction median |
|---|---:|---:|---:|---:|---:|---:|
| no_fb | 512 | 0 | 0 | 512 | 32821.0 | 0.4997675012 |
| fb_norefine | 512 | 0 | 0 | 512 | 38341.5 | 0.5001324993 |

Interpretation:

- At `t=0.3`, `no_fb` has many failures/rejections, but every seed still visits
  both `Re z` signs and the observable means agree with `fb_norefine` at the
  level relevant for this diagnostic.
- This remains an efficiency/mobility warning, not a demonstrated observable
  bias.

## t=0.5 no_fb Threshold Dataset

Scale and method:

```text
128 seeds x 200000 cycles
method: no_fb
```

Remote output root:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_128seed_x_200000cycles_704400c15fe1
```

Readback:

- `no_fb/per_seed_summary_table.csv`: 128 rows
- `no_fb/aggregated_summary_table.csv`: present
- `reference_manifest.json`: present
- protocol audit: pass for all 128 rows
- preflight grep did not show actual `Python.h`, `libpython`, `pyconfig`,
  `Traceback`, or fatal embedding failure; only queue-plan expectation text
  matched the string search.

Aggregate:

| method | rows | mean Ohat_re | mean Ohat_im | std Ohat_re | std Ohat_im | proposal failures | reverse-gate rejects | mean runtime sec |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| no_fb | 128 | -0.2412559808 | -0.0077456212 | 0.0128809805 | 0.2363283237 | 3149862 | 204408 | 10166.457322 |

Raw `Re z` sign diagnostics:

| method | files | only positive | only negative | both signs | sign changes median | positive fraction median |
|---|---:|---:|---:|---:|---:|---:|
| no_fb | 128 | 66 | 62 | 0 | 0.0 | 1.0 |

Sector-conditioned observable readback:

| sector | seeds | mean Ohat_re | mean Ohat_im |
|---|---:|---:|---:|
| `Re z > 0` only | 66 | -0.241232 | -0.235832 |
| `Re z < 0` only | 62 | -0.241281 | 0.235056 |

Interpretation:

- Every seed is trapped in one `Re z` sign sector at `t=0.5`.
- Equalizing the number of positive-only and negative-only seeds would cancel
  the odd imaginary component, but it would not repair `Ohat_re`: both sectors
  independently give about `-0.241`.
- This is the first clean F20F no-fallback pathological scenario in the current
  fixed-flow line.

## Next Gate

Run the same `t=0.5` scenario with TLTM/fallback repair enabled and require:

1. high-flow `Re z` sign changes are restored;
2. positive/negative occupancy is near balanced;
3. `Ohat_re` no longer sits near `-0.241`;
4. `Ohat_im` remains compatible with zero;
5. failure and reverse-gate rejection counters no longer explain an effective
   support restriction.

# F20F Production Output Plan

Date: 2026-05-21 JST

Status: planning packet only.  No PBS submission is authorized by this file.

## Current Gate State

The modernization and cleanup prerequisites are now satisfied:

- local canonical branch: `codex/fortran-modernization`
- local current commit: `a104816f5b9406fcae49e1c5d02e2ec7b4878149`
- remote canonical execution tree:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
- remote canonical execution tree has been fast-forwarded to:
  `a104816f5b94`
- reviewed dirty saved worktree was removed after archive coverage was verified
- old dirty archive packet remains at:
  `/lustre1/home/cychou/TLTM_worktrees/archive/f20f_precleanup_20260521/fortran_modernization_dirty_archive_20260517T034954Z`

The production-comparison execution tree is clean but still old:

```text
/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison
branch: codex/tltm-production-comparison-official-dfols
HEAD: 6ad837703adc
```

Do not run production from that old HEAD.

## Production Boundary

This production line should not reuse old `official_dfols_*`,
`pre_redo_*`, `formalized_assist_bridge_*`, or F20F diagnostic output roots.

Use a new post-cleanup namespace:

```text
output/production_comparison/f20f_post_cleanup/
output/logs/production_comparison/f20f_post_cleanup/
```

The F20F no-fallback diagnostic raw roots stay owned by
`nofb_diagnostics`.  Production-comparison may cite their readback as
supporting evidence, but should not silently copy or merge those raw outputs
into a new production dataset.

## Source Sync Gate

Before any production job:

1. Confirm `qstat -u cychou` is empty or unrelated.
2. Confirm production tree is clean.
3. Sync the production execution tree to the chosen modernization commit
   `a104816f5b9406fcae49e1c5d02e2ec7b4878149`.
4. Prefer creating or updating a clearly named production branch for this line,
   for example:

```text
codex/tltm-production-comparison-f20f-post-cleanup
```

If the existing production branch is not fast-forward-compatible with
`codex/fortran-modernization`, do not force-reset it silently.  Create the
post-cleanup branch at the chosen commit and record that choice in the request
row.

## Physics Target

Use the F20F double-precision preset as the only active tolerance preset:

```text
docs/f20f_unique_double_precision_preset_20260520.json
```

Core tolerance profile:

| variable | value |
| --- | --- |
| `TLTM_STAGE2_ABS_TOL_OVERRIDE` | `1e-14` |
| `TLTM_STAGE2_REL_TOL_OVERRIDE` | `1e-14` |
| `TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE` | `1e-13` |
| `QN_QUASI_TOL_OVERRIDE` | `1e-13` |
| `QN_REVERSE_GATE_TOL` | `1e-8` |
| `QN_OFFICIAL_DFOLS_RHOEND` | `1e-16` |
| `QN_OFFICIAL_DFOLS_MODEL_ABS_TOL` | `1e-26` |
| `QN_OFFICIAL_DFOLS_MODEL_REL_TOL` | `0` |

Do not reopen single precision, loose ODE, loose Newton/QN, or relaxed DFO-LS
in the production line without a new validation packet.

## Recommended Output Sequence

### P0: Route Smoke

Goal: prove the synced production tree, F20F preset, output namespace, and
scheduler gate are wired correctly.

Scale:

- methods: `no_fb`, `fb_norefine`
- seeds: `4`
- cycles: `1000`
- chunks: one chunk per method

Expected roots:

```text
output/production_comparison/f20f_post_cleanup/f20f_prod_smoke_4seed_1k_<shortcommit>
output/logs/production_comparison/f20f_post_cleanup/f20f_prod_smoke_4seed_1k_<shortcommit>
```

Promotion gate:

- build/preflight pass
- no `Python.h` or libpython embed failure
- per-method row count `4/4`
- aggregate tables present
- protocol audit pass

### P1: First Production Gate

Goal: verify the post-cleanup production tree reproduces sane F20F behavior at
the old calibration scale before spending on the main dataset.

Scale:

- methods: `no_fb`, `fb_norefine`
- seeds: `32`
- cycles: `50000`
- chunks: `4` per method, `8` seeds per chunk

Expected roots:

```text
output/production_comparison/f20f_post_cleanup/f20f_prod_gate_32seed_50k_<shortcommit>
output/logs/production_comparison/f20f_post_cleanup/f20f_prod_gate_32seed_50k_<shortcommit>
```

Promotion gate:

- row count `32/32` per method
- aggregate tables present
- protocol audit pass
- compare against the F20F preset-validation readback, not against old
  pre-F20F production roots
- no large observable drift in `virial`, `z`, or `z_dSdz_minus_1`
- no unexpected failure/counter explosion relative to the F20F diagnostic
  evidence

### P2: Main Production Dataset

Goal: generate the first post-cleanup production-comparison dataset at a scale
large enough to replace old provisional production outputs.

Scale:

- methods: `no_fb`, `fb_norefine`
- seeds: `128`
- cycles: `200000`
- chunks: `16` per method, `8` seeds per chunk
- scheduler shape: build job, 32 chunk jobs, merge job

Expected roots:

```text
output/production_comparison/f20f_post_cleanup/f20f_prod_main_128seed_200k_<shortcommit>
output/logs/production_comparison/f20f_post_cleanup/f20f_prod_main_128seed_200k_<shortcommit>
```

Readback table must include, per method and for paired differences:

- `virial` mean Re/Im, seed standard error, `Z_mean`
- `z` mean Re/Im, seed standard error, `Z_mean`
- `z_dSdz_minus_1` mean Re/Im, seed standard error, `Z_mean`
- unresolved failures
- projection failures
- reverse-gate rejects
- pair0 accept rate
- round trips
- P68/P95 diagnostics
- ODEX/CVODE/QN/DFO-LS counters available in the current summary schema
- runtime

### P3: Optional Top-Up

Do not start at `512 seeds`.

If P2 is clean but one observable is near a decision boundary, top up by
`+384 seeds x 200000 cycles` while preserving paired seed/method controls.
Only do this after the P2 readback specifies which statistic needs more power.

## Scheduler Boundary

Actual PBS submission must still go through the cluster02 scheduler agent and
the qsub gate.  The production-comparison owner can prepare:

- config files
- dry-run launcher output
- scheduler request rows
- readback scripts/checklists

But the production owner should not directly set
`TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler` or bypass
`codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh`.

## Immediate Next Task

Prepare the P0/P1 production launcher and dry-run manifest for
`f20f_post_cleanup`, then hand the request to the scheduler.  Do not submit P2
until P1 readback passes.

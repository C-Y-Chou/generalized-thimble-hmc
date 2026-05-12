# Output Namespace Freeze 2026-05-12

## Purpose

Prevent pre-redo production-comparison evidence from being mixed with the next
modernization-head redo after the code tree is updated.

This file is a naming and ownership gate. It does not delete or move data.

## Current Remote Roots

Remote worktree:

`/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`

Current production-comparison output namespace:

- `output/production_comparison/provisional`
- `output/production_comparison/archive`
- `output/logs/production_comparison/provisional`
- `output/logs/production_comparison/archive`

## Frozen Pre-Redo Provisional Outputs

These outputs are frozen as pre-redo / old-code provisional evidence. They may
be read, summarized, and used for diagnostic comparison, but they must not be
extended in place and must not be merged with modernization-head redo outputs.

| dataset_id | output_root | status | notes |
| --- | --- | --- | --- |
| `prodcomp_official_dfols_small_20260511_10seed_10k` | `output/production_comparison/provisional/official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb` | frozen_pre_redo_provisional | matched `nofb`/`withfb`; 10 seeds x 10k |
| `prodcomp_official_dfols_32seed_50k_20260511` | `output/production_comparison/provisional/official_dfols_gate_20260511_32seed_50k_p28_rg_nofb_withfb` | frozen_pre_redo_provisional | matched `nofb`/`withfb`; 32 seeds x 50k |
| `prodcomp_official_dfols_128seed_100k_withfb_r4_20260511` | `output/production_comparison/provisional/official_dfols_gate_20260511_128seed_100k_p28_rg_withfb_r4` | frozen_pre_redo_provisional | `withfb` only; 128 seeds x 100k |
| `prodcomp_official_dfols_256seed_200k_20260511` | `output/production_comparison/provisional/official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb` | frozen_pre_redo_provisional | matched `nofb`/`withfb`; 256 seeds x 200k; commit recorded as `c0e40218e6abe2706f4b9b4c66067dbcea74eeff` |

Archived legacy output:

- `output/production_comparison/archive/non_official_legacy_20260511/gate_20260511_128seed_200k_p28_rg_nofb_fbnorefine`

## New Redo Naming Rule

The next modernization-head redo must use a new namespace and must include the
code lineage in the campaign name.

Required campaign pattern:

`official_dfols_preredo_YYYYMMDD_<shortsha>_<N>seed_<C>cyc_t035_L2_nstep20_rg_nofb_withfb`

Example:

`official_dfols_preredo_20260512_709a7de_10seed_10k_t035_L2_nstep20_rg_nofb_withfb`

Required roots:

- output: `output/production_comparison/pre_redo/<campaign>`
- logs: `output/logs/production_comparison/pre_redo/<campaign>`

Do not place modernization-head redo outputs in the old `provisional/official_dfols_*`
roots.

## Required Manifest Fields

Every new redo output root must contain `submit_manifest.env` or equivalent
metadata with at least:

- `CAMPAIGN`
- `GIT_BRANCH`
- `GIT_COMMIT`
- `SOURCE_WORKTREE`
- `N_SEEDS`
- `CYCLES_PER_SEED`
- `METHODS`
- `FLOW_TIME`
- `L`
- `NSTEP`
- `RG_ENABLED`
- `QN_SOLVER_BACKEND`
- `ASSIST_POLICY`

## Readback Rule

Before any new redo is called comparable to the frozen pre-redo datasets:

1. The output root and log root must be registered in `codex/state/DATASETS.tsv`.
2. A readback report must exist under `codex/workspaces/tltm_production_comparison/runbooks/`.
3. The report must explicitly say whether it is:
   - `smoke`
   - `pre_redo_gate`
   - `production_candidate`
   - `final_production`
4. No report may combine frozen pre-redo data with modernization-head redo data
   in a single statistical estimator.

## Cleanup Rule

Do not delete or move frozen outputs while their readback paths are still cited
by runbooks or diagnostics. If physical cleanup is needed later, first create a
new archive note and update:

- `codex/state/DATASETS.tsv`
- this file
- `codex/workspaces/tltm_production_comparison/context/STATE_BRIEF.md`

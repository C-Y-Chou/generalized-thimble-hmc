# F20F Production-Facing Output Plan

Date: 2026-05-21 JST

Status: no-rerun consolidation plan, completed by
`runbooks/F20F_PRODUCTION_FACING_EVIDENCE_PACKET_20260521.md`.  No PBS
submission is authorized or needed for this plan.

## Current Gate State

The modernization and cleanup prerequisites are satisfied:

- local canonical branch: `codex/fortran-modernization`
- source cleanup state entering this no-rerun plan:
  `a3a2769a7db4585b02445e199c4364df6eafb823`
- remote canonical execution tree:
  `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
- remote canonical execution tree had been fast-forwarded through that cleanup
  state before this documentation-only correction
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

## User Decision: No Rerun

The 2026-05-21 decision is to avoid a new production-comparison rerun.
The existing canonical F20F datasets are the evidence to promote into a
production-facing packet.

This file is therefore not a P0/P1/P2 job plan.  It is a provenance and
readback packaging plan for already completed data.  Any future PBS work must
come from a new explicit decision and scheduler request.

## Production Boundary

Do not reuse old `official_dfols_*`, `pre_redo_*`,
`formalized_assist_bridge_*`, or pre-F20F production-comparison roots as
current evidence.

The current raw roots stay owned by `nofb_diagnostics` and the canonical
modernization execution tree.  Production-comparison should cite and summarize
them as production-facing evidence, not copy them into a new raw dataset or
pretend they were regenerated from the old production-comparison worktree.

## Existing Evidence To Promote

The production-facing packet should be organized by physics role:

| physics bucket | role | existing roots |
| --- | --- | --- |
| `TLTM_t030` | F20F tolerance validation and active preset evidence | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20_double_tolerance_validation/f20f_double_ode1e14_ntqn1e13_dfols1e16_model1e26_most_conservative_r3_32seed_50k_59e9d10acd35` |
| `fixed_flow_t030` | fixed-flow negative control where failures do not create a visible distribution or observable shift | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_128seed_x_200000cycles_a678d2c0cd1f`; `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t030/f20f_fixed_flow_t030_extension384seed_x_200000cycles_8cfbc0747305` |
| `fixed_flow_t050` | fixed-flow no-fallback pathology threshold evidence | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_fixed_flow_t050/f20f_fixed_flow_t050_nofb_128seed_x_200000cycles_704400c15fe1` |
| `TLTM_t050` | TLTM repair test using low005 base32 plus topup96 paired components | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_32seed_x_200000cycles_d60e7467d7d8`; `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/tests/f20f_tltm_t050_pair_validation/f20f_tltm_t050_low005_pair_topup96_to128_x_200000cycles_8c76fdf710ff` |

`codex/state/DATASETS.tsv` and
`codex/workspaces/nofb_diagnostics/state/F20F_DATASET_REGISTRY.tsv` are the
active registries for these roots.

## Physics Target And Preset Boundary

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

## Production-Facing Output Artifact

Create a compact readback packet from existing outputs only.  The packet should
contain:

- the four physics buckets above
- method-by-method and paired tables where paired data exist
- `virial`, `z`, and `z_dSdz_minus_1` when the raw history supports extraction
- unresolved failures, projection failures, reverse-gate rejects, sign-motion
  diagnostics, P68/P95, and runtime when available
- exact output roots, log roots, config paths, source commits, and row counts
- a claim-boundary section separating:
  - established: F20F is the active double preset; single precision is closed
  - established: fixed-flow `t=0.5` no-fallback has a real sign-lock pathology
  - established: TLTM low005 repairs the fixed-flow `t=0.5` pathology
  - not established in this one-dimensional toy model: a robust observable
    necessity for `fb_norefine` over `no_fb`

## Scheduler Boundary

No scheduler request is needed for this no-rerun plan.

If a future rerun is explicitly reopened, actual PBS submission must still go
through the cluster02 scheduler agent and the qsub gate.  The owner may prepare
configs, dry-run launcher output, request rows, and readback checklists, but
must not directly set `TLTM_CLUSTER02_SCHEDULER_AUTHORITY=cluster02_scheduler`
or bypass `codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh`.

## Completion State

Completed artifacts:

```text
codex/workspaces/tltm_production_comparison/runbooks/F20F_PRODUCTION_FACING_EVIDENCE_PACKET_20260521.md
codex/workspaces/tltm_production_comparison/runbooks/F20F_1D_MANUSCRIPT_CLAIM_BOUNDARY_20260521.md
codex/workspaces/tltm_production_comparison/state/F20F_FINAL_VALIDATION_20260521.tsv
codex/workspaces/tltm_production_comparison/runbooks/F20F_ARCHIVE_DELETE_APPROVAL_LIST_20260521.md
codex/workspaces/tltm_production_comparison/runbooks/F20F_REMOTE_CLEANUP_READBACK_20260521.md
```

`z` was read back from existing `multichain_expectations.dat` metadata, and
`Ohat` was used as the current `z dS/dz - 1` / virial observable.  No new jobs
were submitted and no new production raw-output namespace was created.

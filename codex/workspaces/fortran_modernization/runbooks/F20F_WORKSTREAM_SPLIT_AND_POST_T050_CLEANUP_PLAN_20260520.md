# F20F Workstream Split And Post-T050 Cleanup Plan

Date: 2026-05-20 JST

Status: decided, pending active `t=0.5` fixed-flow readback.

## Decision

TLTM work is now split into three separate lines:

1. `nofb_diagnostics`
2. `fortran_modernization`
3. `tltm_production_comparison`

The split is semantic first. Do not rename or move active remote worktrees while
PBS jobs or merge dependencies are still live.

## Line Ownership

### nofb_diagnostics

Purpose: answer the BTN/fallback physics question.

Owned evidence:

- F20F fixed-flow `t=0.3`, main paired dataset:
  `512 seeds x 200000 cycles`, methods `no_fb` and `fb_norefine`.
- F20F fixed-flow `t=0.5`, current no_fb threshold test:
  `128 seeds x 200000 cycles`, method `no_fb`.
- Follow-up gates, only if `t=0.5` shows a no_fb distribution/observable
  problem: TLTM no_fb correction test, then withfb/fb_norefine repair test.

Interpretation boundary:

- `t=0.3` no_fb failures are currently an efficiency/mobility signal, not a
  demonstrated correctness/support-restriction signal.
- The purpose of `t=0.5` is to test whether larger flow time turns no_fb
  failure/rejection into an effective sampling obstruction.
- If larger flow time shows a real no_fb correctness/sampling issue, that is
  the motivation for larger-dimensional sign-problem tests, because useful
  sign-problem mitigation generally pushes toward larger effective flow time.

### fortran_modernization

Purpose: source correctness, execution contract, and preset governance.

Owned evidence and source:

- F20F unique double preset:
  ODE abs/rel `1e-14`, constraint/QN `1e-13`, reverse gate `1e-8`,
  DFO-LS `rhoend=1e-16`, `model_abs=1e-26`, `model_rel=0`.
- Fixed-flow single-replica execution support.
- PBS launchers, scheduler request rows, scheduler authority boundaries, and
  readback tooling.

Boundary:

- Modernization does not own the nofb scientific narrative.
- Modernization supplies the code and execution contract used by
  nofb_diagnostics and production_comparison.

### tltm_production_comparison

Purpose: production-facing datasets and paper evidence.

Policy:

- Old production-comparison outputs are historical/pre-F20F unless explicitly
  regenerated under the F20F preset and current source contract.
- They must not remain the main evidence line after F20F is selected.
- Future production-facing outputs should be generated from canonical F20F
  packages or from new production runs that explicitly cite the F20F preset.

## Current Paths

Current local canonical source path:

```text
/Users/ccy/Documents/TLTM_qn_error_handling
```

Preferred future local source path:

```text
/Users/ccy/Documents/TLTM_fortran_modernization
```

Preferred future diagnostic line path:

```text
/Users/ccy/Documents/TLTM_nofb_diagnostics
```

Preferred production-comparison line path:

```text
/Users/ccy/Documents/TLTM_production_comparison
```

Current remote execution tree remains pinned until active jobs finish:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization
```

Do not rename or relocate this remote tree while active PBS jobs, held merge
jobs, or pending readback depend on it.

## Canonical Dataset Targets

The first post-cleanup canonical nofb diagnostic packet should be:

```text
output/reference/nofb_diagnostics/f20f/fixed_flow_t030_512seed_200k
```

It should contain small, durable package artifacts only:

- manifest with source commits, configs, output roots, and request ids;
- merged per-seed and aggregate summary tables or links to their remote roots;
- readback report;
- raw-history region/support diagnostic summary;
- no raw `z_history.dat` history payloads committed to git.

The active `t=0.5` threshold run should later become:

```text
output/reference/nofb_diagnostics/f20f/fixed_flow_t050_nofb_128seed_200k
```

only after readback passes.

## Post-T050 Cleanup Checklist

Run this only after the active `t=0.5` fixed-flow no_fb jobs and merge are
finished and read back.

1. Confirm no active PBS jobs depend on
   `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`.
2. Finish `t=0.5` readback:
   row count, aggregate, protocol audit, fixed-flow metadata, failure/rejection
   metrics, ODEX counters, raw z distribution diagnostics, and runtime.
3. Decide whether `t=0.3` initial `128seed x 200k` is repaired with a
   merge-only root package or simply marked superseded by the combined
   `512seed x 200k` diagnostic evidence.
4. Generate the canonical `t=0.3 512seed x 200k` nofb diagnostic packet.
5. Generate or update a `F20F_DATASET_REGISTRY.tsv` that lists:
   dataset id, line owner, status, source commit, config, output root,
   log root, methods, row counts, and readback packet.
6. Mark old production-comparison outputs as archive/pre-F20F in the control
   plane and stop using them as main evidence.
7. Plan local directory renames:
   `TLTM_qn_error_handling` -> `TLTM_fortran_modernization`, plus a separate
   `TLTM_nofb_diagnostics` line if raw diagnostic scripts/results need their
   own working tree.
8. Only after the registry and readback packets exist, decide whether any
   remote output should be copied, archived, or left in place with stable
   manifests.

## Hard Rules

- Do not use legacy `/Users/ccy/Documents/New project/TLTM_repo` as an active
  source tree.
- Do not touch the F23/stage2 worktree while doing this cleanup.
- Do not move active PBS output roots while jobs or merge dependencies are live.
- Do not commit raw large history payloads to git.
- Real PBS submission, cancellation, and merge repair remain owned by the
  cluster02 scheduler agent and must pass through the scheduler qsub gate.

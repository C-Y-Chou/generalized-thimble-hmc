# Assist Deletion And NPT5 Assist-Off Baseline

Updated: 2026-05-15 JST

## Decision

Solver assist is no longer the canonical modernization direction. Keep it as
historical/diagnostic evidence only, and schedule the assist machinery for
deletion after the usual F8/M4 affected-baseline guardrails.

The modernization starting point is now the assist-off official DFO-LS
`npt5_r0055` baseline under the true Stage2 RNG v2 contract.

This does not by itself approve the `withfb` feedback kernel as physically
correct. The 10seed/10k readback shows that reducing failures can still shift
the observable, so feedback-kernel correctness must be audited separately.

## Evidence Baseline And Rerun Contract

Canonical source tree:

- local: `/Users/ccy/Documents/TLTM_qn_error_handling`
- remote: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
- branch: `codex/fortran-modernization`
- evidence commit: `e83892f7744ca197505c283ceaf0db47ff566531`

The evidence commit is the source SHA that produced the readback below. It is
not a silent product pin. The PBS wrapper must be submitted with an explicit
`TLTM_EXPECTED_GIT_COMMIT=$(git rev-parse HEAD)` for the source tree being run,
and it records both the current run SHA and the baseline evidence SHA in
`method_manifest.env`.

Start-readiness rule:

- Governance/doc/entrypoint commits after the evidence SHA may be used as the
  modernization starting point only when `src/`, `scripts/`, `build/`, `tests/`,
  and `docs/` remain unchanged against the evidence SHA, or when the changed
  patch has its own F8/M4 affected-baseline comparison.
- Diagnostic work from `/Users/ccy/Documents/New project/TLTM_repo` is not part
  of this canonical source line unless explicitly promoted by a separate,
  reviewed productization decision.

Run contract:

- `TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2`
- `QN_SOLVER_BACKEND=official_dfols`
- `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`
- `QN_OFFICIAL_DFOLS_NPT=5`
- `QN_OFFICIAL_DFOLS_RHOBEG=0.055`
- `QN_OFFICIAL_DFOLS_MAXFUN=500`
- `QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE=1`
- `QN_OFFICIAL_DFOLS_RHOEND=1e-16`
- `QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-30`
- `QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0`
- `INTODE_SOLVER_ASSIST_POLICY=off`
- `TLTM_STAGE3_METHOD_ASSIST_POLICY=off`
- 10 seeds x 10000 cycles

Readback from 2026-05-15:

| method | mean Re | mean Im | Zmean Re | Zmean Im | failures | RG rejects | QN assist |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nofb | -0.002818340294982019 | -0.02465681851224433 | -0.048084031438805575 | -0.5895676378972808 | 8340 | 1150 | 0 |
| withfb | 0.02974362444598664 | -0.002988766099182953 | 0.5326497008388138 | -0.08040456379425769 | 167 | 1324 | 0 |

Remote evidence:

- `output/production_comparison/observable_regression/observable_regression_true_rngv2_assistoff_dfols_npt5_r0055_10seed_10k_20260515_e83892f/npt5_r0055/no_fb/aggregated_summary_table.csv`
- `output/production_comparison/observable_regression/observable_regression_true_rngv2_assistoff_dfols_npt5_r0055_10seed_10k_20260515_e83892f/npt5_r0055/fb_norefine/aggregated_summary_table.csv`
- compact summary:
  `output/production_comparison/observable_regression/true_rngv2_10seed_10k_backend_candidate_method_summary_20260515.md`

## Direct Rerun

From the remote modernization worktree:

```bash
cd /lustre1/home/cychou/TLTM_worktrees/fortran_modernization
EXPECTED_COMMIT="$(git rev-parse HEAD)"

qsub -q C12 -N n55a0n \
  -v TLTM_EXPECTED_GIT_COMMIT="${EXPECTED_COMMIT}",TLTM_METHOD=no_fb,TLTM_CANONICAL_METHOD=nofb \
  codex/workspaces/fortran_modernization/tasks/pbs/official_dfols_npt5_assistoff_10seed_10k_20260515.pbs

qsub -q C12 -N n55a0w \
  -v TLTM_EXPECTED_GIT_COMMIT="${EXPECTED_COMMIT}",TLTM_METHOD=fb_norefine,TLTM_CANONICAL_METHOD=withfb \
  codex/workspaces/fortran_modernization/tasks/pbs/official_dfols_npt5_assistoff_10seed_10k_20260515.pbs
```

The PBS wrapper refuses to run on the wrong branch/commit or with a dirty
tracked worktree. It writes `method_manifest.env` with the contract above, the
submitted expected SHA, the actual run SHA, the evidence SHA, and whether the
runtime source surface still matches the evidence SHA.

## Closure Rule

Before deleting assist source paths, run a patch-local F8 statement and an
affected-baseline comparison against this baseline. The expected deletion
direction is:

1. Keep `nofb` as the public baseline/control.
2. Keep official DFO-LS `npt5_r0055` as the current assist-off numerical
   starting point.
3. Treat `withfb` failure reduction as numerically interesting but not a
   correctness proof; audit feedback-kernel measure preservation separately.
4. Remove solver-assist policy/machinery only after the deletion patch preserves
   the intended assist-off contract and does not silently reintroduce assist.

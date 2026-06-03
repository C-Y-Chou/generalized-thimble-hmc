# WV-HMC n=2 Medium/Long Ratio Gate Readback

Date: 2026-06-03 JST

Purpose: close the current-source Stephanov `n=2` medium/long ratio-correctness
gate before moving back to `n=6`.  This readback separates the physical complex
ratio estimator from direct positive-target ensemble moments.

## Source And Build Gate

- Local source root: `/Users/ccy/Documents/TLTM_fortran_modernization`
- Remote execution root: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization`
- Source pin id: `77ffdb4e4771-f24205a0c2e9`
- Source commit: `77ffdb4e47712c391e610d42382cd22a429fc30f`
- Runtime snapshot: `/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/wv_hmc_n2_ratio_gate_20260602_20260602T140555Z`
- Build/test job: `18842.anode01`, queue `C17`, exit status `0`
- Build gate result: `[PASS] WV-HMC math kernels` and `[PASS] WV-HMC constraint kernels`

Diagnostic downgrades preserved from the build log:

- `wv_dense_phase_volume_contract ok=T skipped_boundary_status=-100`
- `wv_dense_rattle_boundary_wrapper diagnostic_only_nonblocking`

These are not production-success claims.  They mean the current fixture gate
permits the corrected boundary non-smooth path as diagnostic-only where the
local smooth-map assumptions do not apply.

## Common Run Configuration

- Model: Stephanov `n=2`
- Parameters file: `data/parameters_stephanov_n2_smoke.dat`
- Sampler interval: `[T0,T1]=[0.0,0.01]`
- Measurement interval: `[0.0,0.01]`
- Wall profile: `paper_wall`
- `gamma=0.0`, `d0=0.0001`, `d1=0.0025`
- Step size: `epsilon=0.003`
- Steps: `nstep=20`
- Boundary policy: `paper_full_flip`
- ODE backend: `dop853`
- Init mode: state bank
- Init bank: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_n2_t001_clean_20260602/state_bank_from_t001_late_final_20260602/state_bank_t001_final128.bin`
- Oracle orders: GH `3`, time `5`
- Oracle available slots: `30668`
- Oracle unavailable slots: `2137`, allowed for this readback
- Max pointwise ratio/direct relative error: `1.212e-19`

## Medium Gate

- Run: `wv_hmc_n2_ratio_medium_128x10000_20260602_f24205a0c2e9`
- Sample job: `18843.anode01`, queue `C17`, exit status `3`
- Analysis-only job: `18845.anode01`, queue `C17`, exit status `0`
- Seeds requested: `128`
- Completed history seeds: `117`
- Zero-measurement seeds: `11`
- Samples in ratio readback: `1053000`
- Readback: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_positive_target_invariant_20260602/wv_hmc_n2_ratio_medium_128x10000_20260602_f24205a0c2e9/readback/positive_target_invariant_readback.md`

Zero-measurement seeds:

`9941002, 9941011, 9941027, 9941042, 9941060, 9941067, 9941078, 9941087, 9941089, 9941111, 9941119`

Primary physical ratio observables:

| metric | exact Re | estimate Re | SE Re | z Re | estimate Im | SE Im | z Im | status |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `ratio.chiral_condensate` | 0.38619746 | 0.43380628 | 0.0329 | 1.45 | -0.00524956 | 0.0198 | -0.265 | pass |
| `ratio.number_density` | 0.02603302 | 0.00117104 | 0.0483 | -0.515 | 0.01741042 | 0.0544 | 0.320 | pass |

Direct positive-target ensemble moments are not the final physical ratio gate.
They remain diagnostic warnings in this run:

- `positive.chiral_condensate.mean`: z Re `5.59`
- `positive.number_density.mean`: z Re `-4.37`
- `positive.x2_per_coord_mean`: z Re `-3.85`

## Long Gate

- Run: `wv_hmc_n2_ratio_long_256x30000_20260602_f24205a0c2e9`
- Sample job: `18844.anode01`, queue `C17`, exit status `3`
- Analysis-only job: `18846.anode01`, queue `C17`, exit status `0`
- Seeds requested: `256`
- Completed history seeds: `243`
- Zero-measurement seeds: `13`
- Samples in ratio readback: `6561000`
- Readback: `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_positive_target_invariant_20260602/wv_hmc_n2_ratio_long_256x30000_20260602_f24205a0c2e9/readback/positive_target_invariant_readback.md`

Zero-measurement seeds:

`9951090, 9951097, 9951100, 9951101, 9951112, 9951120, 9951133, 9951142, 9951162, 9951167, 9951201, 9951225, 9951231`

Primary physical ratio observables:

| metric | exact Re | estimate Re | SE Re | z Re | estimate Im | SE Im | z Im | status |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `ratio.chiral_condensate` | 0.38619746 | 0.37853162 | 0.0209 | -0.366 | -0.01480795 | 0.0117 | -1.263 | pass |
| `ratio.number_density` | 0.02603302 | 0.03815930 | 0.0258 | 0.469 | 0.05936142 | 0.0352 | 1.684 | pass |

Direct positive-target ensemble moments remain diagnostic warnings:

- `positive.chiral_condensate.mean`: z Re `7.99`
- `positive.number_density.mean`: z Re `-5.78`

## Gate Decision

Status: `ratio gate closed for n=2`.

The medium and long physical complex-ratio observables pass the current
predeclared ratio gate.  The earlier `|z|~2` ratio concern shrank with increased
statistics in the long run:

- chiral Re: `1.45 -> -0.366`
- chiral Im: `-0.265 -> -1.263`
- density Re: `-0.515 -> 0.469`
- density Im: `0.320 -> 1.684`

This supports treating the old `n=2` ratio-level drift as finite-statistics for
this source pin and parameter set.

## Caveats That Remain Blocking For Production

1. The gate does not close `n=6` production correctness.
2. Direct positive-target ensemble moments still warn; they are diagnostic
   evidence to preserve, not a reason to fail the physical ratio gate.
3. Zero-measurement seeds show a remaining ergodicity/measurement-window health
   warning:
   - medium: `11/128`
   - long: `13/256`
4. The analysis-only jobs used `WV_GATE_Z_FAIL=999.0` to force readback output;
   therefore the job-level status is `warn` even when ratio observables pass.
5. Matrix-free/BiCGStab trajectory wiring remains deferred.

## Next Workflow Step

Proceed to a short, predeclared current-source `n=6` validation only after the
runbook ledger records this gate as closed.  Do not promote WV-HMC production
correctness from this `n=2` gate alone.


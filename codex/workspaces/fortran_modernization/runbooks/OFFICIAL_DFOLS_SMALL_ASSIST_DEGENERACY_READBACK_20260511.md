# Official DFO-LS Small Assist-Degeneracy Readback

Updated: 2026-05-11 JST

Scope: imported readback from `tltm_production_comparison` for the
official DFO-LS 10seed x 10k nofb-vs-withfb provisional comparison.
This is useful for observing whether disabling the production `withfb`
assist/feedback route degenerates robustness under the official backend.

Boundary: this is not an ODEX solver-internal assist-off run. The ODE
solver-internal residual assist counters are still present in both
`no_fb` and `fb_norefine`; the comparison here is the production method
route `no_fb -> nofb` versus `fb_norefine -> withfb`.

## Provenance

- Imported evidence root: `codex/workspaces/fortran_modernization/state/official_dfols_small_20260511_10seed_10k_p28_rg_nofb_withfb`.
- Production-comparison readback: `codex/workspaces/tltm_production_comparison/runbooks/OFFICIAL_DFOLS_SMALL_READBACK_20260511.md`.
- Pinned run commit recorded by production-comparison readback: `81b0784473073a6bc3ec1604f3f2e5930e70e252`.
- Current local HEAD when this report was generated: `ada5f7658d89`.
- Backend/preset: `QN_SOLVER_BACKEND=official_dfols`, `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.
- Physical point: `t=0.35,L=2,nstep=20`; scale: `10 seeds x 10000 cycles`; RG on, p28, `cttol=1e-13`, `QN=1e-13`.

## Aggregate Comparison

| metric | nofb | withfb | withfb - nofb | pct delta | nofb / withfb |
| --- | ---: | ---: | ---: | ---: | ---: |
| mean_Re | 0.0265222881268 | -0.0290740000958 | -0.0555962882226 | NA | NA |
| mean_Im | 0.0247701103072 | 0.0347713205763 | 0.010001210269 | NA | NA |
| Zmean_Re | 0.444520412495 | -0.884739776363 | -1.32926018886 | NA | NA |
| Zmean_Im | 0.84538321011 | 1.13463055101 | 0.289247340902 | NA | NA |
| unresolved_failures | 7502 | 1179 | -6323 | -84.284191 | 6.3630195 |
| projection_failures_mean | 875.1 | 217.5 | -657.6 | -75.145698 | 4.0234483 |
| reverse_gate_rejects | 1252 | 996 | -256 | -20.447284 | 1.2570281 |
| pair0_accept | 0.43862 | 0.4383 | -0.00032 | -0.07295609 | 1.0007301 |
| runtime_seconds_mean | 715.5420136 | 1105.0365717 | 389.4945581 | 54.433499 | 0.6475279 |

Key readback:

- Unresolved failures drop from `7502` to `1179` when `withfb` is enabled: delta `-6323`, `-84.284191%`.
- `nofb` has `6.3630195x` as many unresolved failures as `withfb` at the same 10seed/10k scale.
- Reverse-gate rejects drop from `1252` to `996`: delta `-256`, `-20.447284%`.
- Runtime rises from `715.5420136` s to `1105.0365717` s: delta `+389.4945581` s, `54.433499%`.
- Physical Zmean remains small-sample noisy: nofb Re/Im `0.444520412495` / `0.84538321011`, withfb Re/Im `-0.884739776363` / `1.13463055101`.
- ODE residual-assist counters are nonzero in both routes: Newton solver-assist nofb `432953`, withfb `682682`; QN solver-assist nofb `0`, withfb `1858`.

## Interpretation

At the official DFO-LS 10seed/10k calibration scale, turning off the
production `withfb` route is already a clear robustness degeneracy signal:
`no_fb` produces about `6.36x` as many unresolved failures as `withfb`.
The physical observable readout is too small-sample to make a production
bias claim, but it does not contradict using `withfb` as the provisional
official DFO-LS production-comparison route.

This evidence supports using official DFO-LS 10seed/10k as a real
production-comparison assist-degeneracy observation. It does not make M6
an official DFO-LS dataset and does not close the larger official backend
replacement caveat by itself.

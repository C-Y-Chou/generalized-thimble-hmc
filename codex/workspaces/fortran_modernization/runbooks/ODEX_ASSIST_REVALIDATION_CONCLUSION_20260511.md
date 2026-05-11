# ODEX Assist Revalidation Conclusion

Updated: 2026-05-11 JST

Status: concluded for the current ODEX flow-policy decision. The accepted
policy is ODEX primary integration plus solver-internal residual assist,
with strict final proposal flow. This is not a claim that the standalone
ODEX backend split or stability-control surface is complete.

Important evidence boundary: M6 reference datasets are historical/internal
behavior anchors, not official DFO-LS evidence. They may be used as an
observational degeneracy detector when comparing assist-off/assist-on
behavior, but not to certify the official DFO-LS backend.

## Current Source Readback

- Current local HEAD when this report was generated: `ada5f7658d89`.
- Large-scale evidence source: `codex/workspaces/fortran_modernization/runbooks/ODEX_SOLVER_ASSIST_VALIDATION_RESULT_20260509_QNCLEAN.md`.
- ODEX-only comparison source: `codex/workspaces/fortran_modernization/runbooks/ODEX_50K_100K_VALIDATION_RESULT_20260509_QNCLEAN.md`.
- Deterministic current-code boundary evidence:
- ODX-F1: pass via `make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_foundation_contract`
- ODX-F2: pass via `make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_solver`
- ODX-F3: pass via `ENABLE_OFFICIAL_DFOLS=0 python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags "" --keep-going`
- ODX-F4: pass via `python3 codex/workspaces/fortran_modernization/tasks/scripts/odex_assist_revalidation.py`

## Recomputed Robustness Comparison

| metric | ODEX-only 50k | assist 50k | delta 50k | ODEX-only 100k | assist 100k | delta 100k | pct delta 100k |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| unresolved_failures | 40715 | 28206 | -12509 | 326569 | 224580 | -101989 | -31.23046 |
| mean_projection_failures | 2053.15625 | 1660.40625 | -392.75 | 4133.6015625 | 3321.1875 | -812.4140625 | -19.653904 |
| mean_unresolved_failures | 1272.34375 | 881.4375 | -390.90625 | 2551.3203125 | 1754.53125 | -796.7890625 | -31.23046 |
| rg_rejects | 24986 | 24927 | -59 | 202530 | 200530 | -2000 | -0.98750802 |
| pair0_accept | 0.438705 | 0.438588 | -0.000117 | 0.438907 | 0.438762 | -0.000145 | -0.033036611 |
| mean_runtime | 3605.528 | 4130.746 | 525.218 | 7127.015 | 8170.916 | 1043.901 | 14.6471 |

Key computed readbacks:

- 100k unresolved failures: ODEX-only `326569`, assist `224580`, delta `-101989` (`-31.23046%`).
- Pre-ODEX 100k unresolved level was `224439`; assist 100k differs by `141`.
- Assist ODE counter success rate at 100k was `0.992570` with invalid count `0`.
- Assist 100k physical Zmean Re/Im were `-0.315388` / `0.214810`; ODEX-only 100k physical Zmean Re/Im were `0.385239` / `-0.200998`.
- Pair0 acceptance remained stable: ODEX-only 100k `0.438907`, assist 100k `0.438762`.

## Conclusion

Pure ODEX-only is physically acceptable as a comparison artifact, but it is
not the production policy to promote: it adds a large avoidable robustness
loss. Solver-internal assist recovers the pre-ODEX unresolved-failure level
while keeping aggregate physical observables, reverse-gate rejects, and
pair0 acceptance stable.

The modernization policy from here is therefore:

1. ODEX is the primary endpoint integrator.
2. Solver assist is allowed only for Newton/QN residual evaluation progress.
3. Final proposal/live-state flow remains strict and cannot be completed by assist.
4. The remaining ODEX work is backend completion: result/workspace/status split, endpoint-only/stability-control decision, and flow/Jacobian deterministic tests.

## Boundary

This revalidation closes the ODEX-only-vs-assist policy question for
the current ODEX flow policy. It does not close `CV-007`/`FG-001`: the
standalone backend contract and stability decision remain open. It also
does not by itself close the official DFO-LS-line gate under `CV-008`;
M6 can only help observe whether disabling assist degenerates robustness.

Separate official DFO-LS production-comparison evidence may be read via
`OFFICIAL_DFOLS_SMALL_ASSIST_DEGENERACY_READBACK_20260511.md`. That
comparison is about the production method route `no_fb` versus
`fb_norefine`, not about turning off ODE solver-internal residual assist.

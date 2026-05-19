# F20F Unique Double Production Preset Decision

Date: 2026-05-20 JST

Status: F20F is the only promoted double-precision production preset.

## Decision

Use `f20f_most_conservative_double` as the unique active tolerance profile.
This supersedes the older `strict_double` profile token and the non-promoted
F20D/F20E scan candidates.

```text
TLTM_STAGE2_ABS_TOL_OVERRIDE=1e-14
TLTM_STAGE2_REL_TOL_OVERRIDE=1e-14
TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE=1e-13
QN_QUASI_TOL_OVERRIDE=1e-13
QN_REVERSE_GATE_TOL=1e-8
QN_OFFICIAL_DFOLS_RHOEND=1e-16
QN_OFFICIAL_DFOLS_MODEL_ABS_TOL=1e-26
QN_OFFICIAL_DFOLS_MODEL_REL_TOL=0
```

## Source Defaults

- `data/parameters.dat` now defaults ODE abs/rel to `1.0d-14` and constraint
  tolerance to `1.0d-13`.
- `stable_gate77`, `production`, and `f20f_most_conservative_double` official
  DFO-LS aliases use `rhoend=1.0e-16`, `model_abs_tol=1.0e-26`,
  `model_rel_tol=0`.
- `legacy` official DFO-LS aliases remain historical and keep
  `model_abs_tol=1.0e-30`.
- Stage2 sidecars record `tolerance_profile=f20f_most_conservative_double`
  while preserving `precision_policy_id=double_strict_v1`.
- The post-B RNG anchor reference was updated as an affected baseline: Stage1
  summary and Stage2 label-trace hashes stayed unchanged, while the Stage2
  summary hash changed to
  `c722737c011fe6e8c5ba50fdc017dd9fbc0ba76d00393364b2f96511bab21dc7`
  under the new F20F default tolerances.

## Validation Evidence

F20F R3 32seed/50k validation request:
`FMOD-F20F-R3-MOST-CONSERVATIVE-DOUBLE-VALIDATION-20260519`.

Readback packet:
`codex/workspaces/fortran_modernization/runbooks/F20F_R3_MOST_CONSERVATIVE_DOUBLE_VALIDATION_READBACK_20260520.md`.

Result summary:

| Method | Paired Re drift z | Runtime saving vs strict R3 |
| --- | ---: | ---: |
| `no_fb` | `-0.5070953817` | `29.84%` |
| `fb_norefine` | `0.6979498359` | `11.58%` |

Combined runtime saving vs strict R3 was `19.94%`.

## Rejected Or Non-Promoted Routes

- Single precision remains closed for the active route.
- `single_feasible1e6_rg1e4`, ODE `1e-6`, shared NT/QN `1e-8`, and F20D
  `tau1e10` remain rejected.
- F20E conservative relaxed remains useful evidence only; it is not the active
  production preset.

## Production Use

Production runs should use the repository defaults after this decision. Explicit
environment overrides may still repeat the same values for provenance, but they
should not introduce a second tolerance preset without reopening F20.

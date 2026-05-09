# Fortran Modernization Planning Index

Updated: 2026-05-09
Scope: index of planning artifacts for TLTM repo-wide modernization.

## Start Here

- `CONFIRMED_DECISIONS_AND_NEXT_PLAN.md`
- `PRE_STAGE3_4_COMPLETION_PLAN.md`
- `STATUS.md`

## Governance

- `BEHAVIOR_PRESERVATION_PROTOCOL.md`
- `FORTRAN_MODERNIZATION_MASTER_PLAN.md`
- `SUBROUTINE_API_REDESIGN_GUIDE.md`
- `TEST_AND_BENCHMARK_ROADMAP.md`

## Algorithm Safety Gate

- `ALGORITHM_TO_IMPLEMENTATION_REVIEW_MAP.md`
- `BEHAVIOR_PRESERVING_ALGORITHM_AUDIT_PLAN.md`
- `M2_CORE_NUMERICAL_IMPLEMENTATION_AUDIT_PLAN.md`
- `ODEX_FLOW_REVIEW_NOTES.md`
- `SIMPLIFIED_NEWTON_RATTLE_REVIEW_NOTES.md`
- `QUASI_NEWTON_PROJECTION_REVIEW_NOTES.md`
- `HMC_METROPOLIS_TLTM_REVIEW_NOTES.md`

## Baselines And Future Refactor Gates

- `M1_TEMPORARY_CHARACTERIZATION_BASELINE.md`
- `M2_CORE_CANONICALIZATION_QUEUE.md`
- `M2_NON_ODEX_CANONICAL_CLEANUP_PLAN.md`
- `ODEX_ONLY_STAGED_VALIDATION_PLAN.md`
- `ODEX_SOLVER_ASSIST_VALIDATION_RESULT_20260509_QNCLEAN.md`
- `BASELINE_VERIFICATION_MATRIX.md`
- `LEGACY_DELETION_CANDIDATES.md`

## Repo-Wide Modernization

- `CROSS_CUTTING_INFRASTRUCTURE_AUDIT.md`
- `CODE_HYGIENE_AUDIT.md`
- `STATE_INFORMATION_PROPAGATION_REFACTOR.md`
- `STATE_INFORMATION_PROPAGATION_AUDIT.md`

## References

- `../references/REFERENCES_INDEX.md`
- `../references/ODEX_LOCATION_GUIDE.md`

## Current Position

- Current phase: source-level modernization after M2 canonicalization decisions.
- Completed source wave: ODEX sequence canonicalization, QN BTN sign cleanup, QN invalid-evaluation handling, post-refine/non-p28 QN source deletion, Radau/JFNK source deletion, solver-assist naming cleanup, RATTLE progress guard diagnostic downgrade, and state/status surface patches.
- Current decision gate: whether to delete legacy positional `parameters.dat` parsing and the unused `initial_x.dat` compatibility slot now, or keep them quarantined until config schema versioning.

- `M2_RETAINED_CORE_IMPLEMENTATION_AUDIT_SUMMARY.md`: completed static audit findings and discussion blockers for retained ODEX/Newton/RATTLE/QN/HMC code.
- `M2_REFERENCE_BACKED_CORE_AUDIT.md`: reference-first retained-core audit superseding the earlier source-level risk scan where conclusions differ.

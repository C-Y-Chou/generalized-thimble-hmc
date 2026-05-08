# Fortran Modernization Planning Index

Updated: 2026-05-08
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
- `BASELINE_VERIFICATION_MATRIX.md`
- `LEGACY_DELETION_CANDIDATES.md`

## Repo-Wide Modernization

- `CROSS_CUTTING_INFRASTRUCTURE_AUDIT.md`
- `CODE_HYGIENE_AUDIT.md`

## References

- `../references/REFERENCES_INDEX.md`
- `../references/ODEX_LOCATION_GUIDE.md`

## Current Position

- Current phase: M2 canonicalization planning after Stage3_4 characterization.
- Non-ODEX cleanup is behavior-neutral quarantine/inventory only before ODEX-only.
- Next gate: retained-core implementation correctness audit before ODEX-only 10k -> 50k -> 100k physical checks.

- `M2_RETAINED_CORE_IMPLEMENTATION_AUDIT_SUMMARY.md`: completed static audit findings and discussion blockers for retained ODEX/Newton/RATTLE/QN/HMC code.

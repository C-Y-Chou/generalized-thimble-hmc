# Fortran Modernization Planning Index

Updated: 2026-05-10
Scope: index of planning artifacts for TLTM repo-wide modernization.

## Start Here

- `CONFIRMED_DECISIONS_AND_NEXT_PLAN.md`
- `PRE_STAGE3_4_COMPLETION_PLAN.md`
- `M3_TO_M6_BEFORE_DATASET_PLAN.md`
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

- `M3_ARCHITECTURE_CONTRACT.md`
- `M3_TEMPERING_PROTOCOL_AND_OUTPUT_SCHEMA_DESIGN.md`
- `M3_V0_OUTPUT_INVENTORY_AND_PROTOCOL_AUDIT_PLAN.md`
- `M3_TO_M6_BEFORE_DATASET_PLAN.md`
- `M5_STATE_CONFIG_OWNERSHIP_PLAN.md`
- `M5_STATE_CONFIG_OWNERSHIP_INVENTORY_SUMMARY.md`
- `M5_PRE_M6_GATE_ASSESSMENT.md`
- `M6_PRE_DATASET_PRODUCT_READINESS_PLAN.md`
- `M6_DATASET_REGENERATION_CHECKLIST.md`
- `CROSS_CUTTING_INFRASTRUCTURE_AUDIT.md`
- `CODE_HYGIENE_AUDIT.md`
- `STATE_INFORMATION_PROPAGATION_REFACTOR.md`
- `STATE_INFORMATION_PROPAGATION_AUDIT.md`

## References

- `../references/REFERENCES_INDEX.md`
- `../references/ODEX_LOCATION_GUIDE.md`

## Current Position

- Current phase: entering M6 product-readiness planning after M3/M4 completion and M5 direct-env/config ownership slices.
- Completed source wave: ODEX sequence canonicalization, QN BTN sign cleanup, QN invalid-evaluation handling, post-refine/non-p28 QN source deletion, Radau/JFNK source deletion, solver-assist naming cleanup, RATTLE progress guard diagnostic downgrade, and state/status surface patches.
- Latest completed M3 slice: parser-only TLTM protocol audit, adjacent-swap kernel contract test, opt-in Stage2 v1alpha sidecars, and Stage2 post-swap measurement/history/label-trace boundary.
- Current next area: M6 wrapper/provenance contract and dataset-regeneration checklist; official datasets remain gated.

- `M2_RETAINED_CORE_IMPLEMENTATION_AUDIT_SUMMARY.md`: completed static audit findings and discussion blockers for retained ODEX/Newton/RATTLE/QN/HMC code.
- `M2_REFERENCE_BACKED_CORE_AUDIT.md`: reference-first retained-core audit superseding the earlier source-level risk scan where conclusions differ.

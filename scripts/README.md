# Scripts Guide

This directory currently contains both active utility scripts and historical
experiment scripts. The machine-checked evidence boundary lives in
`codex/workspaces/fortran_modernization/state/SCRIPT_EVIDENCE_AUDIT_20260512.tsv`;
run `make -C build script_evidence_audit_gate` before using any newly added or
reclassified helper as modernization evidence.

Modernization task-local guardrails live under
`codex/workspaces/fortran_modernization/tasks/scripts/`; current M4 includes
the CV-001 official-line kernel gate, CV-005 script/evidence audit, F14
pre-redo gate, and post-B route-B RNG reference anchor.

## Active scripts (current baseline support)

- `fortran_module_deps.py`
  - Generates conservative Make dependencies from Fortran `module`/`use` relationships so incremental builds rebuild module consumers after public module API changes.
- `benchmark_hamiltonian.sh`
  - Reproducible Hamiltonian benchmark helper.

The old generated/autodiff model pipeline has been retired from the active
tree.  Current model changes replace the active provider behind
`src/physics/model.f90`; the Stephanov provider lives in
`src/physics/model_stephanov.f90`.

## Historical scripts (kept for reference)

The following categories are from previous tuning campaigns and are not part of the current single-chain baseline:

- `run_t*.sh`, `run_nofb_multiseed.sh`, `run_seed_pairs_with_without_fallback.sh`
- `run_multichain_auto.py`, `plot_multichain_virial_coverage.py`
- `analyze_*`, `classify_*`, `inspect_*`, `sort_geometry_cases.py`, `summarize_rescue_impact.py`
- `build_*bundle*.py`, `eval_*`

Diagnostic replay/geometry scripts tied to removed standalone binaries have been deleted from the active tree.

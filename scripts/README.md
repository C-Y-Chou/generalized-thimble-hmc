# Scripts Guide

This directory contains active public utility scripts plus historical
experiment scripts. The public guardrail target is now
`make -C build modernization_guardrails`, which covers build/test and wrapper
smoke checks without depending on local Codex workspace archives.

## Active scripts (current baseline support)

- `fortran_module_deps.py`
  - Generates conservative Make dependencies from Fortran `module`/`use` relationships so incremental builds rebuild module consumers after public module API changes.
- `benchmark_hamiltonian.sh`
  - Reproducible Hamiltonian benchmark helper.
- `run_m4_guardrails.py`
  - Public modernization guardrail orchestration used by `make -C build modernization_guardrails`.
- `run_stage3_3_multiseed.py`, `merge_stage3_multiseed_chunks.py`, `run_tltm_product.py`
  - Current Stage3/product-wrapper compatibility helpers.  Raw Stage script
    deprecation is blocked until wrapper handoff and production-comparison
    consumption are recorded.

The old generated/autodiff model pipeline has been retired from the active
tree.  Current model changes replace the active provider behind
`src/physics/model.f90`; the Stephanov provider lives in
`src/physics/model_stephanov.f90`.

## Local-only production and readback scripts

Production-specific submission helpers, queue records, and exploratory readback
scripts are local control-plane archives. They are not part of the public
script surface. Promote only compact, reviewed evidence into `docs/` or
`codex/runbooks/` when a milestone explicitly requires it.

## Historical scripts (kept for reference)

The following categories are from previous tuning campaigns and are not part of
the current canonical TLTM production path:

- `run_t*.sh`, `run_nofb_multiseed.sh`, `run_seed_pairs_with_without_fallback.sh`
- `run_multichain_auto.py`, `plot_multichain_virial_coverage.py`
- `analyze_*`, `classify_*`, `inspect_*`, `sort_geometry_cases.py`, `summarize_rescue_impact.py`
- `build_*bundle*.py`, `eval_*`

Diagnostic replay/geometry scripts tied to removed standalone binaries have been deleted from the active tree.

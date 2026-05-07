# Scripts Guide

This directory currently contains both active utility scripts and historical experiment scripts.

## Active scripts (current baseline support)

- `generate_model_generated.py`
  - Regenerates `src/physics/model_generated.f90` from `src/physics/model_action_body.inc`.
- `st_backends/tapenade_codegen.py`
  - Tapenade source-transformation backend adapter.
- `st_backends/enzyme_codegen.py`
  - Enzyme source-transformation backend adapter.
- `check_autodiff_integrity.sh`
  - Quick guard check that required autodiff files/routes are still present.
- `benchmark_hamiltonian.sh`
  - Reproducible Hamiltonian benchmark helper.

## Historical scripts (kept for reference)

The following categories are from previous tuning campaigns and are not part of the current single-chain baseline:

- `run_t*.sh`, `run_nofb_multiseed.sh`, `run_seed_pairs_with_without_fallback.sh`, `run_plain_benchmark_start.sh`
- `run_multichain_auto.py`, `plot_multichain_virial_coverage.py`
- `analyze_*`, `classify_*`, `inspect_*`, `sort_geometry_cases.py`, `summarize_rescue_impact.py`
- `build_*bundle*.py`, `eval_*`

If we no longer need these for future reference, they can be moved to an archive directory or removed in a later cleanup step.

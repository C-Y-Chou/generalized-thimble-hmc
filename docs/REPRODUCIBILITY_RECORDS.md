# Reproducibility Records

The public entry point is the root README and the stable docs in this directory.
Detailed run records, generated readbacks, and scheduler metadata are kept under:

- `codex/workspaces/fortran_modernization/runbooks/`
- `codex/workspaces/fortran_modernization/runbooks/generated/`
- `codex/workspaces/fortran_modernization/state/`
- `model_specs/`

Use these records when auditing a historical result, reproducing a validation
packet, or preparing a new benchmark report. User-facing build and run commands
should start from `scripts/run_tltm_product.py`.

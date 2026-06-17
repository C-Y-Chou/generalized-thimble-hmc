# Reproducibility Records

The public entry point is the root README and the stable docs in this directory.
Detailed run records, validation readbacks, and benchmark metadata are kept in
the repository provenance tree:

- `codex/workspaces/fortran_modernization/runbooks/`
- `codex/workspaces/fortran_modernization/state/`
- `model_specs/`

Use these records when auditing a historical result, reproducing a validation
packet, or preparing a new benchmark report. User-facing build and run commands
should start from `scripts/run_tltm_product.py`.

## Public Compact Packets

- [WV-HMC Validation Packet 2026-06-16](WV_HMC_VALIDATION_PACKET_20260616.md):
  dense explicit-J WV-HMC Stephanov `n=6` boundary-policy readback, with
  compact seed-jackknife and burn/window summaries.

# Reproducibility Records

The public entry point is the root README and the stable docs in this
directory.  Public reproducibility records are compact packets that can be
reviewed without private cluster state:

- `docs/`
- `codex/runbooks/`
- `model_specs/`

Use these records when auditing a historical result, reproducing a validation
packet, or preparing a new benchmark report. Local scheduler ledgers, source
pins, raw output dumps, and exploratory Codex workspaces are internal archives,
not public reproducibility records. User-facing build and run commands should
start from `scripts/run_tltm_product.py`.

## Public Compact Packets

- [WV-HMC Validation Packet 2026-06-16](WV_HMC_VALIDATION_PACKET_20260616.md):
  dense explicit-J WV-HMC Stephanov `n=6` boundary-policy readback, with
  compact seed-jackknife and burn/window summaries.

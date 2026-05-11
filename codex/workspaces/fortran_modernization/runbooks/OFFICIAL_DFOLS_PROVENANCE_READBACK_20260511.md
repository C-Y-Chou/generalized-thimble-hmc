# Official DFO-LS Provenance Readback

Updated: 2026-05-11 19:07:34 JST

Scope: local/package provenance readback for the embedded official DFO-LS
backend. This is not a solver-performance gate and does not replace
representative captured-attempt or production-scale readback.

## Result

- status: `pass`
- expected package: `DFO-LS==1.6.5`
- expected license: `GPL-3.0-or-later`
- Python executable: `/Users/ccy/Documents/TLTM_qn_error_handling/.venv-dfols/bin/python`
- Python version: `3.11.14`
- module version: `1.6.5`
- distribution version: `1.6.5`
- distribution license: `GPL-3.0-or-later`
- module file: `/Users/ccy/Documents/TLTM_qn_error_handling/.venv-dfols/lib/python3.11/site-packages/dfols/__init__.py`
- state TSV: `codex/workspaces/fortran_modernization/state/OFFICIAL_DFOLS_PROVENANCE.tsv`

## Interpretation

This confirms the official package identity visible to the inspected Python
environment. Production runs still must record `TLTM_OFFICIAL_DFOLS_PYTHONPATH`
and use `ENABLE_OFFICIAL_DFOLS=1`, `QN_SOLVER_BACKEND=official_dfols`, and
`QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.

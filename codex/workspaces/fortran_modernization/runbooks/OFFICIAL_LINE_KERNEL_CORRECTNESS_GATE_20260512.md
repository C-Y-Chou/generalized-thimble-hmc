# Official-Line Kernel Correctness Gate

Updated: 2026-05-12 JST

Scope: closure gate for CV-001. This is a modernization-tree kernel correctness
gate for the embedded official DFO-LS line. It is not a production redo and it
does not submit PBS jobs.

## Canonical Line

- embedded backend: official `DFO-LS==1.6.5`
- preset: `stable_gate77`
- solver assist: default-off for canonical physical route; assist-on remains
  diagnostic opt-in only
- route: Newton -> p28 QN BTN residual -> reverse gate -> Metropolis
- method naming: public `nofb` and `withfb`, with raw aliases preserved through
  `F7_METHOD_ALIASES_V1`

## Gate Entry Point

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/official_line_kernel_correctness_gate.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

M4 also runs this gate.

## Required Evidence

- official package provenance is explicit and importable from `.venv-dfols`
  or the configured Python environment;
- DFO-LS claim/provenance policy validates;
- ODEX endpoint/final-flow guardrails pass with solver assist default-off
  policy checked;
- official DFO-LS preset contract passes for `stable_gate77`;
- retained Newton, RATTLE/reverse-gate, QN route, and reverse-gate rejection
  identity contracts pass;
- F14 F3/F4/F7/F8 pre-redo gate passes without reduced-scope acceptance.

## Closure Statement

When this gate passes, CV-001 is closed for modernization-tree kernel
correctness under the canonical official line. It does not by itself close the
production-output provisional boundary CV-002 or replace production-comparison
redo evidence.

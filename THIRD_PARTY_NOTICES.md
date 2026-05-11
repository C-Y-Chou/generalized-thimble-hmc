# Third-Party Notices

Updated: 2026-05-11 JST

This file tracks external packages and tools that matter for TLTM distribution,
reproducibility, or generated-source provenance. It is an engineering compliance
record, not legal advice.

## Distribution License

TLTM is distributed under GPL-3.0-or-later. See `LICENSE` and
`LICENSE_POLICY.md`.

This policy was selected because the production modernization target is to use
the official DFO-LS package as a solver backend.

## DFO-LS

- Name: DFO-LS, Derivative-Free Optimizer for Least-Squares
- Version currently evaluated: `DFO-LS==1.6.5`
- Upstream: `https://github.com/numericalalgorithmsgroup/dfols`
- Package index: `https://pypi.org/project/DFO-LS/`
- License: GPL-3.0-or-later
- TLTM role: planned official quasi-Newton / BTN residual solver backend after
  behavior-preservation gates pass.

DFO-LS is not currently vendored into this repository. If vendored, embedded,
linked, or otherwise shipped as part of a TLTM distribution, retain the upstream
license notices and ensure the whole conveyed product remains GPL-compatible.

The official package defaults are not accepted as TLTM production defaults.
The accepted candidate must use the tuned TLTM-side residual-gated preset
documented in `codex/workspaces/fortran_modernization/runbooks/EXTERNAL_DFOLS_BACKEND_COMPARISON.md`.

## Tapenade

- Name: Tapenade Algorithmic Differentiation Tool
- Version currently targeted by local makefile default: Tapenade 3.16 path
  convention, `~/tools/tapenade-3.16-v2/bin/tapenade`
- Upstream documentation: `https://tapenade.gitlabpages.inria.fr/tapenade/`
- Upstream license page: `https://tapenade.gitlabpages.inria.fr/tapenade/distrib/LICENSE.html`
- License: MIT License, Copyright INRIA
- TLTM role: optional external source-transformation AD code-generation tool
  used by `GEN_BACKEND=st_tapenade`.

Tapenade is treated as a build/code-generation tool, not as a vendored runtime
dependency. The current checked-in generated model source is not Tapenade output
unless its backend banner says `st-tapenade-experimental`.

Before distributing Tapenade-generated Fortran, review the generated file for
retained Tapenade headers, helper routines, or runtime dependencies. If any are
present, keep the relevant MIT notice in the release artifact. If the generated
file only contains transformed TLTM-owned source plus TLTM wrapper code, record
the exact Tapenade version and generation command in provenance.

## Python Runtime Dependencies

The official DFO-LS backend depends on Python packages such as NumPy, SciPy, and
Pandas through normal Python packaging. A release lockfile or environment file
must enumerate exact versions and their licenses before public distribution.

## Future Additions

Any future source-transformation backend, solver package, MPI helper, numerical
library, or vendored code must be added here before it becomes a production
dependency.

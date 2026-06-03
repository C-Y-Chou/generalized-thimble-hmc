# Third-Party Notices

Updated: 2026-06-03 JST

This file tracks external packages and tools that matter for distribution,
reproducibility, or generated-source provenance. It is an engineering compliance
record, not legal advice.

## Distribution License

This project is distributed under GPL-3.0-or-later. See `LICENSE` and
`LICENSE_POLICY.md`.

## Compilers And Build Tools

The public build uses standard system compilers and GNU make. Supported compiler
families include GNU Fortran and Intel Fortran. Compiler licenses are governed
by the installation used on the build machine.

## Linear Algebra

The public validation targets can use the repository bundled linear algebra
path. Users may optionally link an external BLAS/LAPACK implementation such as
OpenBLAS, Intel oneAPI/MKL, or Apple Accelerate. When distributing binaries,
include the notices required by the selected numerical library.

## Python

Python 3.8 or newer is used for product wrapper and validation scripts. The
public wrapper does not require a Python scientific stack for the documented
build/test/smoke workflow.

## Tapenade

- Name: Tapenade Algorithmic Differentiation Tool
- Upstream documentation: `https://tapenade.gitlabpages.inria.fr/tapenade/`
- Upstream license page: `https://tapenade.gitlabpages.inria.fr/tapenade/distrib/LICENSE.html`
- License: MIT License, Copyright INRIA

Tapenade is treated as an optional external source-transformation tool for
future provider development. Checked-in runtime provider code should state its
own provenance if generated files are added.

## Future Additions

Any future source-transformation backend, solver package, MPI helper, numerical
library, or vendored code must be added here before it becomes a product
dependency.

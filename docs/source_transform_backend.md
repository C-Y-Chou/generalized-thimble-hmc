# Source-Transformation Backend Setup

User-confirmed policy:

- `st_tapenade` and `st_enzyme` are required source-transformation autodiff backends.
- Keep at least one backend path configured in development/production environments.

This project supports source-transformation backend selection via:

- `GEN_BACKEND=st_auto`
- `GEN_BACKEND=st_tapenade`
- `GEN_BACKEND=st_enzyme`

Command entry point:

```bash
cd build
make -B regen_model_derivatives GEN_BACKEND=st_auto
```

## 1) Tapenade Route

Adapter script:

- `scripts/st_backends/tapenade_codegen.py`

License/provenance status:

- Tapenade is an external source-transformation/code-generation tool.
- The official Tapenade distribution license checked on 2026-05-11 is MIT
  License, Copyright INRIA.
- TLTM does not vendor Tapenade. If a release includes Tapenade-generated
  Fortran, record the Tapenade version and generation command, then inspect the
  generated file for retained Tapenade notices, helper routines, or runtime
  dependencies.
- Keep Tapenade listed in repository-root `THIRD_PARTY_NOTICES.md`.

### Prerequisites

1. Install Tapenade command-line tool.
2. Ensure the command is reachable from shell, or export `ST_TAPENADE_CMD`.

Examples:

```bash
export ST_TAPENADE_CMD=/path/to/tapenade
cd build
make -B regen_model_derivatives GEN_BACKEND=st_tapenade
```

### Notes

- The adapter runs Tapenade reverse + tangent passes and assembles wrappers for `ds` and `hessian_vec`.
- Tapenade CLI/signature details can vary by version. If your Tapenade build uses different generated routine signatures, adjust `scripts/st_backends/tapenade_codegen.py` wrapper call sections.

## 2) Enzyme Route (Adapter Contract)

Adapter script:

- `scripts/st_backends/enzyme_codegen.py`

This adapter delegates to an external driver command via `ST_ENZYME_DRIVER`.

### Contract

Set:

```bash
export ST_ENZYME_DRIVER='python3 /abs/path/to/enzyme_codegen_driver.py'
```

The driver must accept:

```bash
--body <model_action_body.inc> --output <model_generated.f90>
```

Then run:

```bash
cd build
make -B regen_model_derivatives GEN_BACKEND=st_enzyme
```

## 3) Fallback Behavior

- `st_auto` tries `st_tapenade` then `st_enzyme`.
- If both are unavailable/fail, generator falls back to `auto` (symbolic/tape) and prints a warning.
- Treat this fallback as a degraded compatibility path, not as the primary backend policy.

## 4) Quick Validation

After regeneration:

```bash
cd build
make test2
```

Check summary lines for derivative consistency:

- `Norm of ds(generated-numeric)`
- `Norm of Hv(generated-numeric)`

# Test and Benchmark Roadmap

## Verification pillars
- unit correctness
- solver-route correctness
- scientific invariants
- fixed-seed regression stability
- performance regression visibility

## Near-term additions
### Unit and kernel checks
- state-vector helper tests
- residual and real/complex mapping checks
- solver acceptance-rule micro tests

### Integration checks
- HMC proposal stability checks
- Metropolis acceptance-path checks
- representative Stage2/Stage3 workflow smoke runs
- `scripts/run_m4_guardrails.py` as the repeatable local modernization guardrail entry point

### Scientific invariants
- action/derivative consistency
- Hessian-vector consistency
- Hamiltonian conservation trend
- reversibility diagnostics

### Regression baselines
- fixed-seed reference runs for representative configs
- solver stats and route census snapshots
- summary metric comparison tables

## M4 Guardrail Entry Point - 2026-05-10

The local M4 guardrail runner is `scripts/run_m4_guardrails.py`.

It is a small-run development check only; it does not submit production jobs and does not create final datasets or modernization reference packages.

Current checks:

- Python compile for Stage3/audit/merge/guardrail scripts.
- `git diff --check`.
- Optional Fortran build plus `test_odex_solver` and `test_tltm_swap_kernel_contract`.
- Stage3 sidecar dry-run.
- Existing Stage2 protocol-audit smoke when a local fixture is present.
- Tiny sidecar-on Stage3 smoke with protocol audit/readback.
- Tiny sidecar-off Stage3 smoke to prove the default remains v0/no-sidecar.
- One-chunk merge smoke proving sidecar/audit metadata survives chunk merge.

Make entry point:

- `make -C build modernization_guardrails`

Local macOS/gfortran note:

- The make target defaults `M4_GUARDRAIL_LDFLAGS` to empty, matching the local gfortran smoke convention.

### Benchmarking
- baseline runtime and allocation profile for flow, Newton, quasi-Newton, and chain driver hot paths
- before/after benchmark table for every major refactor wave

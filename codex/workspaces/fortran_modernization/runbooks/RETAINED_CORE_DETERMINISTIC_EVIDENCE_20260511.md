# Retained-Core Deterministic Evidence Readback

Updated: 2026-05-11 JST

Scope: retained-core deterministic evidence slice for `CV-009` / `F3`. This is local guardrail evidence for the Newton constraint solve, one successful RATTLE/reverse-gate replay, BTN residual paper-variable reconstruction, and current official-line QN route surface. It does not close the full retained-core caveat because fixed-seed route census, RG reject identity, and local-volume/branch-measure coverage remain open.

## Commands

```bash
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_retained_core_newton_contract
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_retained_core_rattle_rg_contract
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_retained_core_qn_route_contract
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_qn_route_contract
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags ''
```

The official DFO-LS bridge is intentionally stubbed for these focused contract tests because the target surface is retained Newton/RATTLE/RG mechanics and the current official-route surface. The QN route test therefore asserts no internal fallback when the official bridge fails; full package-success route coverage remains part of the broader official-line correctness gate.

## Results

| Target | Status | Key readback |
| --- | --- | --- |
| `test_retained_core_newton_contract` | pass | deterministic replay against the simplified Newton residual form passed for step sizes `0.002`, `0.003`, and `0.004`; residuals were `2.9197E-15`, `1.4743E-14`, and `4.6635E-14`; lambda scaling was `9.9817E-01` for all cases |
| `test_retained_core_rattle_rg_contract` | pass | one-step RATTLE pass replay preserved endpoint flow/Jacobian (`z_err=0`, `jac_err=0`), final momentum stayed tangent (`normal_norm=0`), and reverse-gate replay recorded `success=1`, `failure_total=0` |
| `test_retained_core_qn_route_contract` | pass | BTN paper-variable residual reconstruction passed with `jl_err=0`, `fq_err=0`; current official route policy read back `stable_gate77` surface (`npt=4`, `maxfun=250`, `noise=T`); stub official-bridge failure stayed on route code `10` with no internal route fallback |
| `run_m4_guardrails.py` | pass | Python compile, diff hygiene, direct-env scan, Stage2/eval build, ODEX/swap/retained-core tests, Stage3 dry-run, tiny sidecar-on/off smokes, and chunk-merge metadata all passed |

## Interpretation

This converts two retained-core audit findings into deterministic guardrails:

- the simplified Newton contract now has fixed replay coverage for accepted solutions and `lambda = O(step_size**2)` scaling;
- a successful RATTLE proposal now has endpoint/Jacobian replay, tangent final momentum, and reverse-gate success accounting coverage.
- the BTN residual now has a direct paper-variable reconstruction guardrail;
- the current official-line QN route is explicitly a single official DFO-LS route surface under `stable_gate77` (`maxfun=250`), not the legacy internal p28/priority/full-stage fallback machinery.

`CV-009` remains active. The next retained-core evidence slices are:

1. Fixed-seed QN route census against current official-line outputs, including how often the official route is reached after Newton failure.
2. Official package-success route coverage for captured attempts, not just the stub no-fallback surface.
3. RG reject/live-state stay-put identity and failure-as-rejection accounting proof.
4. Local-volume/branch-measure coverage for the official DFO-LS line.

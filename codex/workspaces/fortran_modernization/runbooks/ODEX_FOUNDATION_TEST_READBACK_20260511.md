# ODEX Foundation Test Readback

Updated: 2026-05-11 JST

Scope: readback for the first ODEX backend-completion deterministic evidence slice. This is local deterministic evidence only, not a production dataset and not final ODEX-completeness signoff.

## Commands

```bash
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_foundation_contract
make -C build FC=gfortran ENABLE_OFFICIAL_DFOLS=0 LDFLAGS= test_odex_solver
ENABLE_OFFICIAL_DFOLS=0 python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags "" --keep-going
```

The stub official DFO-LS bridge is intentional for these tests because the target surface is ODEX/intode behavior, not official DFO-LS embedding.

## Results

| Target | Status | Key readback |
| --- | --- | --- |
| `test_odex_foundation_contract` | pass | `iwork3_sequence actual= 2 4 6 8 12 16 24 32 48 64 96`; forward/backward composition error `2.5535E-15`; unknown-context h-min failure status `103`; solver-assist success `0` |
| `test_odex_solver` | pass | analytic exp/oscillator forward/backward checks pass; zero-time status `1`; fallback attempts/failures `0/0` |
| `run_m4_guardrails.py` | pass | Python compile, diff hygiene, direct-env scan, Stage2/eval build, ODEX foundation/smoke tests, swap test, Stage3 dry-run, tiny sidecar-on/off smokes, and chunk-merge metadata all passed |

## Interpretation

This closes the first non-invasive ODEX evidence gap:

- the current step sequence is fixed and tested;
- strict vs non-strict status semantics are tested;
- zero-time and analytic endpoint behavior are tested;
- an invalid-RHS h-min failure in unknown context remains failure and is not silently rescued by solver assist.

This does not close `CV-007`. Remaining ODEX backend-completion work is the source-level mechanism/policy split, explicit backend result/workspace surface, stability-control decision, endpoint-only/dense-output scope decision, and flow-wrapper/Jacobian deterministic tests.

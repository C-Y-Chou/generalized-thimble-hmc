# F18b.4c ODEX Initialization Alignment Screen Invalidated

Date: 2026-05-16 JST

Status: invalid screen, no ODEX initialization conclusion.  The temporary
source patch was backed out to the accepted F18b.4b active behavior, but the
local 1k screens are not valid evidence against the initialization route
because the official DFO-LS Python bridge/env was missing.

## Scope

This was the next HWM-ODEX-001 candidate after F18b.4b.  The attempted source
alignment followed the Hairer ODEX initialization surface:

- caller-supplied absolute initial `H`;
- `H=0 -> 1e-4`;
- signed interval normalization and first-step cap;
- tolerance-derived initial order
  `K=max(2,min(KM-1,int(-log10(RTOL+1e-40)*0.6+1.5)))`.

This is source-level initialization alignment only.  It does not make the local
endpoint ODEX loop a full Hairer `ODEX` controller, because rejection history,
first/last step handling, `KOPT`, dense-output hooks, and stability-control
details are still not full source matches.

## Focused Probe

The temporary patch added deterministic observers for initial `H` and initial
`K`.  Focused tests passed under the experimental source:

```bash
make -C build test_odex_controller_alignment_spec test_odex_controller_observation_contract test_odex_result_contract
```

Key probe values:

- default backend `H=0 -> 1e-4`;
- explicit `H` respected and signed;
- tight `RTOL=3e-14` with `KMAX=10` produced initial `K=9`;
- loose `RTOL=1e-1` produced initial `K=2` in the standalone backend path.

## 1k Behavior Screen

The completed 10seed/1k screen used Hairer fallback `H=0 -> 1e-4` with the
source-derived initial order and default `KMAX=10`:

```text
output/tests/f18b4c_odex_initialization_10seed_1k_20260516T124415
```

Readback:

| method | unresolved | RG rejects | mean Re | mean Im | Zmean Re | Zmean Im | mean runtime |
| --- | ---:| ---:| ---:| ---:| ---:| ---:| ---:|
| no_fb | 882 | 0 | 0.1104544340104003 | 0.05951247887772867 | 0.67926793870233 | 0.46172331901242936 | 26.413063 |
| fb_norefine | 882 | 0 | 0.1104544340104003 | 0.05951247887772867 | 0.67926793870233 | 0.46172331901242936 | 26.3112709 |

Initial interpretation, now invalidated:

- the `no_fb` failure surface stayed close to the F18b.4b 1k screen
  (`890` -> `882`);
- `fb_norefine` regressed from the accepted F18b.4b 1k unresolved count
  `16` to `882`;
- both methods became effectively identical at this scale, and reverse-gate
  rejects dropped to zero;
- no max-step, invalid-state, or reverse-replay failure surface appeared.

This is not valid evidence for or against the next canonical behavior-changing
patch.

## Invalidating Evidence

The `fb_norefine` Stage2 logs for this screen contain the same bridge failure
found later in F18b.4j:

```text
ModuleNotFoundError: No module named 'dfols'
[WARN] Official DFO-LS bridge failed: status=12 flag=-999; QN attempt will be rejected without internal fallback.
```

The run manifest for `fb_norefine/seed_20260421` was missing:

```text
TLTM_OFFICIAL_DFOLS_PYTHONPATH
QN_REVERSE_GATE_ENABLED
QN_REVERSE_GATE_TOL
QN_QUASI_TOL_OVERRIDE
```

It did include `QN_SOLVER_BACKEND=official_dfols` and the intended official
DFO-LS preset fields, but without the Python path the embedded bridge could not
import the package.  Since F19 intentionally removed the internal fallback,
every QN attempt was rejected.  That explains why `fb_norefine` collapsed to
the same accepted trajectory shape as `no_fb`.

## Tuning Attempts

Three additional tuning probes were started and stopped before completion
because the 1k cost was already outside a reasonable extrapolation path:

| attempted setting | output root | stop condition |
| --- | --- | --- |
| caller `H=1e-3`, `KMAX=10` | `output/tests/f18b4c_odex_initialization_h1em3_10seed_1k_20260516T124655` | first 10 `no_fb` stage2 tasks still running after more than 4 minutes |
| caller `H=1e-3`, `KMAX=5` | `output/tests/f18b4c_odex_initialization_h1em3_kmax5_10seed_1k_20260516T125253` | first 10 `no_fb` stage2 tasks still running after more than 2.5 minutes |
| caller `H=0 -> 1e-4`, `KMAX=5` | `output/tests/f18b4c_odex_initialization_h0_kmax5_10seed_1k_20260516T125559` | first 10 `no_fb` stage2 tasks still running after more than 2.5 minutes |

These were not accepted baseline screens and should not be used as production
evidence.

## Corrected Decision

Do not use this run to accept or reject F18b.4c.

The active modernization source was restored to the F18b.4b accepted behavior:

- `h0 = 0.01*t`;
- fixed initial `k = opts%k_min` with default `odex_k_min=4`;
- Hairer-style growth/shrink bounds and order thresholds from F18b.4b remain
  active and accepted.

After the restoration, the focused contract readback passed:

```bash
make -C build test_odex_controller_alignment_spec test_odex_controller_observation_contract test_odex_result_contract
```

The deterministic alignment spec again reports two expected gaps:

- `h0_fraction_policy`;
- default stability policy off.

## Next Required Step

Any retry of F18b.4c must be rerun with the corrected official DFO-LS/QN env
preflight now recorded in F18b.4j:

- `TLTM_OFFICIAL_DFOLS_PYTHONPATH` pointing to `.venv-dfols` site-packages;
- `QN_SOLVER_BACKEND=official_dfols`;
- intended `QN_OFFICIAL_DFOLS_*` policy;
- `QN_REVERSE_GATE_ENABLED=1`, `QN_REVERSE_GATE_TOL=1e-8`, and
  `QN_QUASI_TOL_OVERRIDE`;
- no `ModuleNotFoundError` in the logs before interpreting statistics.

No 10k or M4 anchor update was run for F18b.4c because the 1k screen is now
invalidated.

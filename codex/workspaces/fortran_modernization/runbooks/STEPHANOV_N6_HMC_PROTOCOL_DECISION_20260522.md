# Stephanov n=6 HMC Protocol Decision - 2026-05-22

## Scope

This is a local-only HMC protocol decision for the selected Stephanov working
point:

```text
n = 6
N_f = 1
m = 0.004
mu = 0.6
tau = 0
flow_time = 1e-6
method = nofb
```

The policy is recorded in
`runbooks/STEPHANOV_HMC_PROTOCOL_TUNING_POLICY_20260522.md`: choose
`epsilon = L/nstep` first, then choose trajectory length through `nstep`.
Do not tune by minimizing nofb proposal failures; nofb failures are diagnostic
output for the selected protocol and flow time.

Artifacts:

```text
/tmp/tltm_stephanov_n6_hmc_protocol_decision_20260522/
/tmp/tltm_stephanov_n6_hmc_protocol_decision_20260522/protocol_decision_summary.csv
```

## Epsilon Scan

Fixed `nstep=5`, `2 chains x 500 cycles`, `flow_time=1e-6`.

| epsilon | L | status | acceptance | movement/sec | accepted/sec | samples |
|---:|---:|---|---:|---:|---:|---:|
| `0.025` | `0.125` | done | `0.988` | `78.8` | `70.1` | `501;501` |
| `0.040` | `0.200` | done | `0.968` | `192.7` | `68.6` | `501;501` |
| `0.050` | `0.250` | done | `0.936` | `182.2` | `42.3` | `501;501` |
| `0.065` | `0.325` | done | `0.892` | `177.1` | `25.3` | `501;501` |
| `0.080` | `0.400` | done | `0.815` | `147.8` | `14.7` | `501;501` |
| `0.100` | `0.500` | done | `0.734` | `87.3` | `6.1` | `501;501` |

Decision: use `epsilon = 0.08` for the next local nofb confirmation.  This is
the cleanest Stan-like step-size scale in the scan: acceptance is close to
`0.8`, while `epsilon=0.10` is already slower and has lower acceptance.  Smaller
epsilon values are operationally valid, but their acceptance is too high to be
the primary step-size choice.

## Trajectory-Length Scan

Fixed `epsilon=0.08`, `2 chains x 300 cycles`, `flow_time=1e-6`.

| nstep | L | status | acceptance | movement/sec | accepted/sec | samples |
|---:|---:|---|---:|---:|---:|---:|
| `2` | `0.16` | done | `0.892` | `243.5` | `133.2` | `301;301` |
| `3` | `0.24` | done | `0.867` | `206.5` | `51.7` | `301;301` |
| `4` | `0.32` | done | `0.845` | `136.9` | `20.1` | `301;301` |
| `5` | `0.40` | done | `0.838` | `100.0` | `10.0` | `301;301` |
| `6` | `0.48` | done | `0.808` | `73.7` | `5.3` | `301;301` |
| `8` | `0.64` | timeout | `0` | `0` | `0` | `0;0` |

`nstep=9` was not run to completion because `nstep=8` had already timed out
without producing samples under the same epsilon.

Decision: use `nstep = 2`, hence `L = 0.16`, for the next local nofb
confirmation.  It has the best movement-per-wall-time among operational
`nstep` values.  `nstep=3` is the backup if the longer confirmation shows
autocorrelation/random-walk behavior that the short movement proxy missed.

## Selected Development Preset

Use:

```text
data/parameters_stephanov_n6_mu06_t1e6_eps008_nstep2.dat
```

Selected protocol:

```text
epsilon = 0.08
nstep   = 2
L       = 0.16
```

This is a local development protocol, not a production-tuned endpoint.  The
next physics/sign-problem test should rerun the `t=1e-6` nofb confirmation with
this protocol and report proposal failures as diagnostic output, not as a
tuning target.

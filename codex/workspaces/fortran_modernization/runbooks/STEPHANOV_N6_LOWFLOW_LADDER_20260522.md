# Stephanov n=6 Low-Flow Ladder - 2026-05-22

## Scope

This is a local-only nofb exploratory ladder while the cluster is under
maintenance.  It is not production evidence.  The purpose is to test whether
very small nonzero flow time is immediately useful at the selected Stephanov
working point:

```text
n = 6
N_f = 1
m = 0.004
mu = 0.6
tau = 0
derivative_mode = manual
enable_quasi_fallback = false
```

The baseline runtime preset is:

```text
data/parameters_stephanov_n6_mu06_t0.dat
```

Artifacts:

```text
/tmp/tltm_stephanov_n6_lowflow_ladder_20260522/
/tmp/tltm_stephanov_n6_lowflow_ladder_20260522/summary_analysis.csv
```

The flow-zero comparison row reuses the earlier longer local run:

```text
/tmp/tltm_stephanov_choose_working_n_20260522/stage2_nofb_mu06_n6
```

## Run Shape

The three new nonzero-flow probes used:

```text
method=nofb
TLTM_STAGE2_NUM_REPLICAS=1
TLTM_STAGE2_SWAP_ENABLED=0
TLTM_STAGE2_LOCAL_UPDATES=1
TLTM_STAGE2_INIT_SIGMA=0.8
chains=4
cycles_per_chain=1000
burn_per_chain=100
used_after_burn=3604
```

The earlier `t=0` comparison used:

```text
chains=4
cycles_per_chain=10000
burn_per_chain=1000
used_after_burn=36004
```

## Readback

Errors below are chain-jackknife errors over four chains and are noisy for the
short nonzero-flow rows.

| flow time | used samples | phase coherence | phase JK err | phase eff frac | proposal failures | proposal failure rate | accept rate | max runtime / chain |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `0` | `36004` | `0.03586298` | `0.00729468` | `0.00128615` | `0` | `0` | `0.438125` | `246.2 s` |
| `1e-7` | `3604` | `0.03048586` | `0.01309967` | `0.00092939` | `0` | `0` | `0.442000` | `132.8 s` |
| `1e-6` | `3604` | `0.05678707` | `0.03950545` | `0.00322477` | `9` | `0.00225` | `0.438250` | `156.8 s` |
| `1e-5` | `3604` | `0.03313373` | `0.02574926` | `0.00109784` | `38` | `0.00950` | `0.434750` | `224.5 s` |

Primary observable readback:

| flow time | `chiral_condensate` | error Re | error Im | `number_density` | error Re | error Im |
|---:|---:|---:|---:|---:|---:|---:|
| `0` | `0.02396421 + 0.00266300 i` | `0.004564` | `0.004848` | `0.62413997 - 0.00355258 i` | `0.1701` | `0.1716` |
| `1e-7` | `0.02481148 + 0.02266139 i` | `0.01392` | `0.01743` | `0.64276322 - 0.87240848 i` | `0.5214` | `0.8966` |
| `1e-6` | `0.01743096 - 0.00324638 i` | `0.02673` | `0.01904` | `0.53814585 - 0.09645736 i` | `1.048` | `0.8114` |
| `1e-5` | `0.01994750 + 0.00915763 i` | `0.02046` | `0.03286` | `0.67270972 - 0.48000880 i` | `0.5500` | `1.481` |

## Bank-Adaptive Protocol Addendum

After selecting the bank-started HMC protocol in
`STEPHANOV_N6_HMC_PROTOCOL_DECISION_20260522.md`, the flow-time scan was rerun
with fixed:

```text
initial ensemble = t=0 checkpoint bank
initialization   = adaptive preflow with zero-momentum relaxation
preflow L/nstep  = 0.16/2
HMC epsilon      = 0.10
HMC nstep        = 6
HMC L            = 0.60
```

Reproducible helper:

```text
codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_flowtime_sign_problem.py
```

Short ladder command:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_flowtime_sign_problem.py \
  --skip-build \
  --flow-times 0,1e-7,3e-7,1e-6,3e-6 \
  --records 0,81,162,243 \
  --cycles 1000 \
  --burn 100 \
  --run-name stephanov_n6_bank_adaptive_flowtime_4x1000_20260522 \
  --force
```

Output:

```text
output/stephanov_flowtime_sign_problem/stephanov_n6_bank_adaptive_flowtime_4x1000_20260522/flowtime_summary.csv
```

| flow time | used samples | phase coherence | phase JK err | phase eff frac | proposal failures | proposal failure rate | accept rate | max runtime / chain |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `0` | `3604` | `0.04066557` | `0.01655959` | `0.00165369` | `0` | `0` | `0.69425` | `5.9 s` |
| `1e-7` | `3604` | `0.03219831` | `0.01506495` | `0.00103673` | `1` | `0.00025` | `0.69675` | `28.9 s` |
| `3e-7` | `3604` | `0.03932481` | `0.01378128` | `0.00154644` | `2` | `0.00050` | `0.69425` | `29.5 s` |
| `1e-6` | `3604` | `0.05973060` | `0.01094267` | `0.00356774` | `3` | `0.00075` | `0.69275` | `30.1 s` |
| `3e-6` | `3604` | `0.05297693` | `0.02132342` | `0.00280656` | `4` | `0.00100` | `0.69100` | `32.8 s` |

The short ladder again made `t=1e-6` the only plausible candidate, but its phase
increase over `t=0` was not significant at this sample size.

Focused confirmation command:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_flowtime_sign_problem.py \
  --skip-build \
  --flow-times 0,1e-6 \
  --records 0,40,81,121,162,202,243,283 \
  --cycles 2000 \
  --burn 200 \
  --run-name stephanov_n6_bank_adaptive_t0_t1e6_8x2000_20260522 \
  --force
```

Output:

```text
output/stephanov_flowtime_sign_problem/stephanov_n6_bank_adaptive_t0_t1e6_8x2000_20260522/flowtime_summary.csv
```

| flow time | used samples | phase coherence | phase JK err | phase eff frac | phase eff n | proposal failures | proposal failure rate | accept rate | max runtime / chain |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `0` | `14408` | `0.02831195` | `0.00881781` | `0.00080157` | `11.55` | `0` | `0` | `0.690875` | `12.0 s` |
| `1e-6` | `14408` | `0.03471425` | `0.00744764` | `0.00120508` | `17.36` | `7` | `0.0004375` | `0.690688` | `65.2 s` |

Primary observable readback for the focused confirmation:

| flow time | `chiral_condensate` | error Re | error Im | `number_density` | error Re | error Im |
|---:|---:|---:|---:|---:|---:|---:|
| `0` | `0.02924025 - 0.00053502 i` | `0.00894` | `0.01126` | `0.22242112 + 0.26625924 i` | `0.3284` | `0.3680` |
| `1e-6` | `0.02312418 - 0.00310278 i` | `0.00550` | `0.00677` | `0.43326506 + 0.30629857 i` | `0.2415` | `0.2107` |

The focused confirmation does not support a clear phase-improvement claim.  The
phase-coherence increase from `0.02831` to `0.03471` is only `0.00640`, while the
combined chain-jackknife scale is about `0.01155`.  Runtime at `t=1e-6` is about
`5.4x` the `t=0` baseline for this local run shape, and no primary observable
shift is significant at the quoted errors.

Conclusion for the bank-adaptive nofb protocol: fixed-flow nofb at very low
flow does not show a statistically clear phase gain.  This is not evidence that
larger flow times cannot improve the sign problem; it only says the useful
improvement does not appear in the `t <= 3e-6` very-low-flow window.

## Endpoint-Discovery Correction

The next interpretation is endpoint discovery for TLTM:

1. find a small flow time where fixed-flow nofb remains well behaved;
2. find a larger flow time where the phase/sign problem is visibly improved,
   even if fixed-flow nofb is no longer a usable standalone sampler;
3. build a TLTM ladder between those anchors.

Broad high-flow probe command:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_flowtime_sign_problem.py \
  --skip-build \
  --flow-times 1e-5,3e-5,1e-4,3e-4,1e-3 \
  --records 0,81,162,243 \
  --cycles 200 \
  --burn 20 \
  --timeout-sec 420 \
  --run-name stephanov_n6_endpoint_discovery_highflow_4x200_20260522 \
  --force
```

Output:

```text
output/stephanov_flowtime_sign_problem/stephanov_n6_endpoint_discovery_highflow_4x200_20260522/flowtime_summary.csv
```

| flow time | phase coherence | phase JK err | proposal failure rate | accept rate | max runtime / chain | interpretation |
|---:|---:|---:|---:|---:|---:|---|
| `1e-5` | `0.04201` | `0.02710` | `0.00125` | `0.70625` | `7.3 s` | still low-flow/no clear gain |
| `3e-5` | `0.04940` | `0.02638` | `0.00125` | `0.70875` | `9.9 s` | plausible low-end stable anchor |
| `1e-4` | `0.05224` | `0.02893` | `0.01750` | `0.69625` | `10.5 s` | still no clear gain; failures begin |
| `3e-4` | `0.02363` | `0.02114` | `0.06875` | `0.66500` | `12.4 s` | poor standalone nofb point |
| `1e-3` | `0.08191` | `0.03100` | `0.21875` | `0.60250` | `19.7 s` | possible mid/high endpoint but nofb degraded |

Very-high-flow probe command:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_flowtime_sign_problem.py \
  --skip-build \
  --flow-times 0.003,0.01,0.03 \
  --records 0,162 \
  --cycles 50 \
  --burn 5 \
  --timeout-sec 300 \
  --run-name stephanov_n6_endpoint_discovery_veryhighflow_2x50_20260522 \
  --force
```

Output:

```text
output/stephanov_flowtime_sign_problem/stephanov_n6_endpoint_discovery_veryhighflow_2x50_20260522/flowtime_summary.csv
```

| flow time | phase coherence | proposal failure rate | accept rate | interpretation |
|---:|---:|---:|---:|---|
| `0.003` | `0.06380` | `0.36` | `0.53` | nofb already poor; phase not compelling |
| `0.01` | `0.23941` | `0.77` | `0.20` | phase visibly improves; nofb unusable standalone |
| `0.03` | `0.99811` | `1.00` | `0.00` | apparent phase is frozen samples; no HMC motion |

Historical note: this first short probe suggested `t ~= 0.01` as a possible
high-flow endpoint.  The later high-flow scale scan below supersedes that
interpretation: `t=0.02` is the current high-flow scale candidate.

## High-Flow Scale Check After Literature Anchor

The literature scale for Stephanov `n=6, mu=0.6` is `O(0.02)`, but it is used
only as a scale hint.  The project decision must come from our own fixed-flow
and TLTM checks.

Protocol tuning at `t=0.02`:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_bank_hmc_protocol.py \
  --skip-build \
  --stage epsilon \
  --flow-time 0.02 \
  --records 0,162 \
  --cycles 60 \
  --fixed-nstep 3 \
  --epsilon-values 0.02,0.03,0.04,0.05,0.065,0.08 \
  --timeout-sec 720 \
  --run-name stephanov_n6_t02_eps_scan_nstep3_2x60_20260522 \
  --force
```

The selected high-flow local protocol for the next check is:

```text
epsilon = 0.04
nstep   = 4
L       = 0.16
```

The `nstep` scan used:

```text
output/stephanov_hmc_protocol_scans/stephanov_n6_t02_nstep_scan_eps004_2x60_20260522/nstep_summary.csv
```

| nstep | L | attempt acceptance | valid-proposal Metropolis acceptance | move norm2 / wall sec |
|---:|---:|---:|---:|---:|
| `2` | `0.08` | `0.883` | `0.972` | `0.364` |
| `3` | `0.12` | `0.808` | `0.980` | `0.652` |
| `4` | `0.16` | `0.717` | `0.956` | `0.943` |
| `5` | `0.20` | `0.558` | `1.000` | `0.998` |
| `6` | `0.24` | `0.575` | `0.958` | `1.390` |

High-flow fixed nofb check:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/scan_stephanov_n6_flowtime_sign_problem.py \
  --skip-build \
  --flow-times 0.01,0.015,0.02 \
  --records 0,81,162,243 \
  --cycles 250 \
  --burn 50 \
  --hmc-epsilon 0.04 \
  --hmc-nstep 4 \
  --timeout-sec 1200 \
  --run-name stephanov_n6_highflow_scale_eps004_nstep4_4x250_20260522 \
  --force
```

Output:

```text
output/stephanov_flowtime_sign_problem/stephanov_n6_highflow_scale_eps004_nstep4_4x250_20260522/flowtime_summary.csv
```

| flow time | phase coherence | phase JK err | phase eff n | attempt acceptance | chiral condensate | number density |
|---:|---:|---:|---:|---:|---:|---:|
| `0.01` | `0.04302` | `0.08587` | `1.49` | `0.764` | `0.02557 + 0.00585 i` | `1.33119 - 0.29235 i` |
| `0.015` | `0.01349` | `0.02362` | `0.15` | `0.706` | `0.06391 + 0.04434 i` | `-1.03127 + 0.22584 i` |
| `0.02` | `0.21996` | `0.07150` | `38.90` | `0.640` | `0.00524 + 0.00044 i` | `1.12987 + 0.20866 i` |

Independent exact values for `n=6, m=0.004, mu=0.6, tau=0` from the
one-dimensional `N_f=1` formula:

```text
chiral_condensate = 0.0244771983
number_density    = 0.5661155667
```

Interpretation:

- `t=0.02` is now the only tested high-flow point with a clear phase-coherence
  gain in this scan.
- The fixed-flow nofb observable at `t=0.02` is not consistent with the exact
  finite-`n` values.  This is evidence that fixed-flow nofb at the high-flow
  endpoint is not by itself a reliable physics estimator.
- The correct next test is therefore TLTM coverage, not a standalone
  fixed-flow nofb claim: build a ladder up to `t=0.02`, then judge swap
  acceptance, round trips, label diffusion, and exact-observable consistency.

## Preliminary Conclusion

The sign problem remains severe throughout this very-low-flow ladder.  The
phase effective fraction stays at `O(1e-3)`.

`t=1e-6` is the only row with an apparent phase-coherence increase, but the
chain-jackknife phase error is large (`0.0395`), so this is not yet a
statistically supported improvement.  Treat it as a candidate for the next
longer local/PBS confirmation, not as a conclusion.

`t=1e-5` is not a good immediate target for longer nofb runs: it gives no clear
phase improvement over `t=0`, has nonzero proposal-construction failures
(`0.95%`), and is about `9x` slower per `1000` cycles than the `t=0` local
baseline.

The next focused step should be a longer `t=1e-6` nofb confirmation at `n=6`
before testing higher flow times.  If `t=1e-6` does not show a statistically
meaningful phase or observable-error improvement, the nofb flow ladder should
not be pushed upward without changing the run protocol or using feedback.

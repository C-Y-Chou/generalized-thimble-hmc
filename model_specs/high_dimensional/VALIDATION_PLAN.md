# Stephanov Validation Plan

## Scope

This plan validates the Stephanov model provider before it is promoted from
`model_specs/high_dimensional/` into `src/physics/` and `src/config/`.

The first physics target is

```text
N_f = 1
m   = 0.004
tau = 0
n   = 10
mu  = 0.4, 0.45, 0.5, 0.55, 0.575, 0.6, 0.625, 0.65, 0.7, 0.75, 0.8
```

## Source Consistency

Production Stephanov derivatives must be hand-written analytic code. Generic
AD-generated derivatives are not an allowed production path for this model.

The source-consistency gate therefore compares:

- hand-written `calculate_action`;
- hand-written `ds`;
- hand-written `hessian_vec`;
- AD and finite-difference oracle outputs at small `n`.

Existing generated-model derivative checks still protect the current toy model
until Stephanov is promoted:

```bash
cd build
make regen_model_derivatives
make test2
```

For Stephanov, add explicit AD/finite-difference tests at `n=2` and `n=4`:

- random complexified `z` with independent complex `Zx,Zy` components;
- compare `dS/dz_i` against AD and centered finite differences of the
  holomorphic action;
- compare `hessian_vec(z,v)` against AD HVP or finite-difference directional
  derivative of `ds`;
- repeat near, but not on, small determinant values.

## AD/FD Oracle Contract

AD and finite differences are correctness oracles only. They must not be used
by the production sampler/flow path for Stephanov.

The oracle must evaluate the same holomorphic action as production:

```text
X      = Zx + i Zy
Xsharp = transpose(Zx) - i transpose(Zy)
S(z)   = n sum_ij (Zx_ij^2 + Zy_ij^2) - N_f log det M(z)
```

The required oracle test set is random genuinely complexified seeds:

| Point class | Purpose |
| --- | --- |
| random complex `Zx,Zy` | Holomorphic continuation correctness and derivative/HVP equivalence. |

Real seeds are covered as a lower-dimensional special case and do not need to
be a separate derivative gate. Flowed-like complex seeds and near-singular but
finite `M` points are useful diagnostics after the basic oracle passes, but are
not required for the first derivative-correctness gate.

If hand-written and oracle derivatives disagree, classify the mismatch before
changing code:

- branch convention in `log det`;
- determinant-zero conditioning;
- accidental anti-holomorphic `conjg` usage;
- wrong analytic derivative/HVP formula;
- oracle implementation bug.

## Complexification Gate

Before any sampling run, assert these identities at random complex `Zx,Zy`:

```text
X      = Zx + i Zy
Xsharp = transpose(Zx) - i transpose(Zy)
tr(Xsharp X) = sum_ij (Zx_ij^2 + Zy_ij^2)
```

Also assert that the code path does not call `conjg(transpose(X))` in the
action or force. `conjg` is allowed only in diagnostics that explicitly measure
distances or norms, not in the holomorphic model definition.

## Exact Reference Values

Use the one-dimensional `N_f=1` exact formulas in `MODEL_PLAN.md`.

Baseline exact values for `n=10`, `m=0.004`, `tau=0`:

| `mu` | `chiral_condensate` | `number_density` |
| ---: | ---: | ---: |
| 0.400 | 0.0463518204500106 | 0.000123843527101594 |
| 0.450 | 0.0480297596655891 | 0.00115854214822130 |
| 0.500 | 0.0496280232202187 | 0.0159584321716699 |
| 0.550 | 0.0479729034107004 | 0.185178613814114 |
| 0.575 | 0.0410303846892515 | 0.528163348285385 |
| 0.600 | 0.0268050789190667 | 1.14844042496847 |
| 0.625 | 0.0115987659465361 | 1.76040548239078 |
| 0.650 | 0.00269984805093797 | 2.08438008406104 |
| 0.700 | -0.00213306162734530 | 2.20472873490897 |
| 0.750 | -0.00259775475399774 | 2.16992673292301 |
| 0.800 | -0.00254451553874721 | 2.12952043858681 |

The same data is available as
`exact_reference_values_n10_m0004_tau0.csv`.

## Local Smoke

Smallest local run that should pass before cluster use:

```bash
cd build
TLTM_STAGE2_NUM_REPLICAS=1 \
TLTM_STAGE2_CYCLES=2 \
TLTM_STAGE2_LOCAL_UPDATES=1 \
TLTM_STAGE2_MAX_FLOW_TIME=<flow_time> \
TLTM_STAGE2_SWAP_ENABLED=0 \
TLTM_STAGE2_COLD_OBSERVABLE_FILE=/tmp/tltm_stephanov_smoke/observable_history.dat \
TLTM_STAGE2_V1_OUTPUT_DIR=/tmp/tltm_stephanov_smoke/v1 \
../bin/run_tltm_stage2
```

Smoke order:

1. `n=2`, `m=0.05`, `mu=0.4`, `tau=0`, `t=0`.
2. `n=4`, `m=0.004`, `mu=0.4`, `tau=0`, small fixed flow.
3. `n=4`, `m=0.004`, `mu=0.6`, `tau=0`, small fixed flow.
4. `n=6`, `m=0.004`, `mu=0.6`, `tau=0`, TLTM ladder smoke.

## Observable Readback

```bash
cd build
EVAL_OBSERVABLE_HISTORY_FILE=/tmp/tltm_stephanov_smoke/observable_history.dat \
EVAL_OBSERVABLE_NAME=chiral_condensate \
../bin/evaluate_expectations
```

Repeat for

```text
number_density
logdet_dirac
phase_factor
min_singular_ba_m2
```

## Sign-Problem Diagnostics

For each `n,mu` point, stream these diagnostics before judging physics:

- `Arg det M` or `Im S`;
- `log abs det M`;
- average phase factor from the phase-quenched `t=0` run;
- `min_singular_ba_m2`;
- HMC acceptance and reversibility rejection counters;
- TLTM swap acceptance / round-trip rate when replicas are enabled.

Expected hard point: `m=0.004`, `tau=0`, `mu` near `0.6`, especially at
`n >= 8`.

## Acceptance Criteria

- Build succeeds.
- Hand-written derivative/HVP tests match AD/FD oracles within tolerance at
  both real and complexified points.
- `Xsharp` complexification tests pass at complex `z`.
- Stage2 smoke produces observable stream and v1 sidecars.
- Observable stream schema names match the intended model observables.
- `n=2` and `n=4` exact-value checks pass before `n=6`.
- `n=10`, `m=0.004`, `tau=0` reproduces both exact observables within
  statistical errors across the full `mu` sweep.
- No model-specific formula is added to sampler or evaluator code.
- Any failure near `mu=0.6` is reported metric-by-metric: sign phase,
  determinant-zero proximity, reverse-gate rejects, swap mixing, and observable
  bias must not be collapsed into one headline result.

# Stephanov Provider Implementation - 2026-05-22

## Decision

The canonical code now uses one active model provider behind the existing model
API. There is no runtime `model_name` branch in sampler/config code.

Active provider:

- `src/physics/model_stephanov.f90`

Retired from the active tree:

- legacy 1d `model_action_body.inc` / observable include bodies;
- `model_generated.f90`, `model_autodiff.f90`, and `model_tape_ad.f90`;
- `regen_model_derivatives` and the old source-transformation codegen scripts.

The action returns a nonfinite value for nonfinite input or singular Dirac
logdet, so Metropolis/Stage2 effective-energy code can reject the proposal
instead of aborting. Shape/configuration errors remain hard failures.

Stable public model API:

- `calculate_action`
- `ds`
- `hessian_vec`
- `hessian`
- `model_observables` facade for observable names and values

## Implemented Model

The provider implements the complexified Stephanov chiral random matrix model:

```text
X      = Zx + i Zy
Xsharp = transpose(Zx) - i transpose(Zy)
A      = X + C
B      = Xsharp + C
M      = [ m I   i A ]
         [ i B   m I ]
S(z)   = n sum_ij (Zx_ij^2 + Zy_ij^2) - N_f log det M
```

The action and force do not use `conjg(transpose(X))`.

## Validation

Local commands run from the repository root while the cluster was unavailable:

```bash
make -C build fast ../bin/test_program2 ../bin/run_tltm_stage2 ../bin/evaluate_expectations
bin/test_program2
```

Result:

```text
Norm of ds(manual-fd)=  1.0104E-10
Norm of Hv(manual-fd)=  7.3519E-11
Norm of hessian*v-Hv=  6.4172E-15
Stephanov observable registry/count=5
```

Stage2 smoke:

```bash
TLTM_PARAMETERS_FILE=data/parameters_stephanov_n2_smoke.dat \
TLTM_STAGE2_NUM_REPLICAS=2 \
TLTM_STAGE2_FLOW_TIME_LADDER=0,0.01 \
TLTM_STAGE2_MAX_FLOW_TIME=0.01 \
TLTM_STAGE2_CYCLES=2 \
TLTM_STAGE2_LOCAL_UPDATES=1 \
TLTM_STAGE2_SWAP_ENABLED=1 \
TLTM_STAGE2_INIT_SIGMA=0.05 \
TLTM_STAGE2_SUMMARY_FILE=/tmp/tltm_stephanov_stage2_smoke/summary.dat \
TLTM_STAGE2_LABEL_TRACE_FILE=/tmp/tltm_stephanov_stage2_smoke/label_trace.dat \
TLTM_STAGE2_COLD_Z_HISTORY_FILE=/tmp/tltm_stephanov_stage2_smoke/z_history.dat \
TLTM_STAGE2_COLD_PHI_HISTORY_FILE=/tmp/tltm_stephanov_stage2_smoke/phi_history.dat \
TLTM_STAGE2_COLD_OBSERVABLE_FILE=/tmp/tltm_stephanov_stage2_smoke/observable_history.dat \
TLTM_STAGE2_V1_OUTPUT_DIR=/tmp/tltm_stephanov_stage2_smoke/v1 \
bin/run_tltm_stage2
```

Result:

- summary, label trace, `z_history`, `phi_history`, and observable stream were written;
- v1 sidecars parsed as JSON, including
  `/tmp/tltm_stephanov_stage2_smoke/v1/observables/observable_schema.json`;
- `config.resolved.json` reports `model_id=stephanov_chiral_rmt_v1`,
  `stephanov_n=2`, and `observable_count=5`;
- observable schema names are `chiral_condensate`, `number_density`,
  `logdet_dirac`, `phase_factor`, `min_singular_ba_m2`.

Evaluator stream readback:

```bash
TLTM_PARAMETERS_FILE=data/parameters_stephanov_n2_smoke.dat \
EVAL_OBSERVABLE_HISTORY_FILE=/tmp/tltm_stephanov_stage2_smoke/observable_history.dat \
EVAL_OBSERVABLE_NAME=chiral_condensate \
bin/evaluate_expectations
```

Result: stream readback completed with `samples=3`; the expected tiny-sample
gnuplot logscale warning does not affect stream parsing.

Swap-kernel contract:

```bash
make -C build fast ../bin/test_tltm_swap_kernel_contract
bin/test_tltm_swap_kernel_contract
```

Result: `[PASS] TLTM swap kernel contract`.  The test fixture now uses a small
nonzero Stephanov n=2 flow separation and Stage2 effective-energy evaluation
rejects nonfinite `z`/Jacobian inputs before calling the model action.

## Next Scale Gate

Before `n=10`, run:

1. `n=4` random-complex derivative/HVP test.
2. `n=4`, `mu=0.4`, short TLTM observable-stream smoke.
3. `n=4`, `mu=0.6`, short TLTM observable-stream smoke.
4. `n=6`, `mu=0.6`, short TLTM ladder smoke.

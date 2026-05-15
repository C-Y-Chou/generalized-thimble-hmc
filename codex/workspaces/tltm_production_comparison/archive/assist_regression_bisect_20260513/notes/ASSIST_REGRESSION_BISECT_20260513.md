# TLTM Solver-Assist / Modernization Discrepancy Investigation

Date: 2026-05-13 JST

## Scope

This investigation used the isolated local worktree:

- `/Users/ccy/Documents/TLTM_assist_regression_bisect`
- branch target: `codex/assist-regression-bisect`
- source/canonical reference: `/Users/ccy/Documents/TLTM_qn_error_handling`, `codex/fortran-modernization`

No build products, PBS outputs, registry files, or experiment outputs were written into the active modernization worktree. No remote/HPC worktree was needed for this pass.

## Tiny Reproducer

Config:

- `codex/workspaces/assist_regression_bisect/configs/tiny_1seed_1000cycle_p28_rg.json`
- seed: `20260421`
- cycles: `1000`
- flow ladder: `[0.05, 0.35]`
- max flow time: `0.35`
- `L=2`, `nstep=20`, local updates per cycle `1`
- stage2 init: `adaptive`
- `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`
- reverse gate enabled: `QN_REVERSE_GATE_ENABLED=1`, `QN_REVERSE_GATE_TOL=1e-8`
- QN: `p28`, near rescue off, nonnear rescue off, global fallback off
- backend: `QN_SOLVER_BACKEND=official_dfols`, `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`
- post-Newton refine off for `fb_norefine`

Build command:

```bash
PYTHON=/Users/ccy/Documents/TLTM_qn_error_handling/.venv-dfols/bin/python \
TLTM_OFFICIAL_DFOLS_PYTHONPATH=/Users/ccy/Documents/TLTM_qn_error_handling/.venv-dfols/lib/python3.11/site-packages \
make -C build OMP=0 ENABLE_OFFICIAL_DFOLS=1 ../bin/run_tltm_stage2 ../bin/evaluate_expectations
```

Runner:

```bash
python3 codex/workspaces/assist_regression_bisect/tools/run_tiny_commit.py \
  --force-navigation-assist \
  --config codex/workspaces/assist_regression_bisect/configs/tiny_1seed_1000cycle_p28_rg.json \
  --label-prefix c1000_assist_ \
  d3f133d1fd7de2ec6a5b7ac27840c01287be5be7 709a7de d26c939 f987cf3 fce0ea3 4076124 9a2f591 18a354a 2d8f1c1 6f98b5bfce60678293c163764e1cefe8307736ba 6abd1e09792681f9d3ad17de41240e39fa35a8d8
```

Important correction applied: this sweep did not classify typed policy / NT-assist-off as the root cause. For legacy pre-typed commits the runner forced:

```bash
INTODE_SOLVER_ASSIST_ENABLED=1
```

For typed-policy commits the runner patched its temporary runner copy so method-level `off` / `qn_navigation` became:

```bash
INTODE_SOLVER_ASSIST_POLICY=all_navigation_diagnostic
```

The patched runner copies live under `output/assist_regression_bisect/patched_runners/` and do not modify source files.

## Selected-Commit Results

Primary result file:

- `output/assist_regression_bisect/results/tiny_results.csv`

`fb_norefine`, forced NT+QN navigation assist:

| commit | subject | failures | mean Re<O> | mean Im<O> | NT assist | NT hmin fail | QN success | QN assist | rev rejects |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `d3f133d` | Add official DFO-LS 32seed 50k comparison gate | 15 | -0.561235 | 0.022270 | 7135 | 0 | 16741 | 7 | 8 |
| `709a7de` | Implement standalone ODEX endpoint backend | 12 | -0.201866 | -0.338387 | 7728 | 0 | 17695 | 12 | 14 |
| `36cded3` | Prepare modernization-head production redo | 12 | -0.201866 | -0.338387 | 7728 | 0 | 17695 | 12 | 14 |
| `a22de1c` | Add production window diagnostic tables | 12 | -0.201866 | -0.338387 | 7728 | 0 | 17695 | 12 | 14 |
| `84523cb` | Record production pre-redo submission | 12 | -0.201866 | -0.338387 | 7728 | 0 | 17695 | 12 | 14 |
| `d26c939` | Close modernization foundation gates and route-B RNG | 22 | 0.762998 | 0.401465 | 7820 | 0 | 17604 | 7 | 9 |
| `2ab0285` | Add post-B RNG anchor and decompose workspace | 22 | 0.762998 | 0.401465 | 7820 | 0 | 17604 | 7 | 9 |
| `f987cf3` | Add top-level TLTM run context | 22 | 0.762998 | 0.401465 | 7820 | 0 | 17604 | 7 | 9 |
| `fce0ea3` | Thread flow context through HMC QN paths | 22 | 0.762998 | 0.401465 | 7820 | 0 | 17604 | 7 | 9 |
| `4076124` | Pass official DFO-LS callback context through ctx | 22 | 0.762998 | 0.401465 | 7820 | 0 | 17604 | 7 | 9 |
| `9a2f591` | Thread QN trace state through run context | 22 | 0.762998 | 0.401465 | 7820 | 0 | 17604 | 7 | 9 |
| `18a354a` | Move QN policy into run context | 22 | 0.762998 | 0.401465 | 7820 | 0 | 17604 | 7 | 9 |
| `2d8f1c1` | Implement typed solver assist policy | 22 | 0.762998 | 0.401465 | 7820 | 0 | 17772 | 7 | 9 |
| `6f98b5b` | Record production sync for solver assist policy | 22 | 0.762998 | 0.401465 | 7820 | 0 | 17772 | 7 | 9 |
| `6abd1e0` | Implement Newton flow status context ownership | 22 | 0.762998 | 0.401465 | 7820 | 0 | 17772 | 7 | 9 |

First bad transition in this tiny deterministic reproducer:

- good through `84523cb55cf66c6a1d309e35d76d32e8444c18bc`
- first bad: `d26c939d3db9bfc382f80ebb2c607d173a0a8fc4`

This remains true with NT+QN navigation assist forced on.

## Mechanism

`d26c939` is an RNG stream contract commit, not an ODEX or DFO-LS callback commit. It changes Stage2 from the old global RNG consumption path to per-slot RNG streams plus a separate swap RNG stream:

- `src/sampler/tltm_stage2_driver.f90`: `swap_rng_seed = derive_swap_seed(base_seed)` and `mt95_seed_state(swap_rng_state, swap_rng_seed)` are introduced.
- `src/sampler/tltm_stage2_driver.f90`: the old `call sgrnd(base_seed)` before the cycle loop is removed.
- `src/sampler/tltm_stage2_driver.f90`: each slot initialization now seeds and stores `slot%rng_state`; local updates call `mt95_set_state(slot%rng_state)` before updates and `mt95_get_state(slot%rng_state)` after updates.
- `src/sampler/tltm_stage2_driver.f90`: swap accept/reject now temporarily installs `swap_rng_state`, draws `grnd()`, then saves it back.
- `src/core/mt95.f90`: `mt95_state_t`, `mt95_seed_state`, `mt95_get_state`, and `mt95_set_state` are introduced; Gaussian spare state becomes part of MT state and is reset on `sgrnd` / `mtget`.

This changes deterministic trajectory selection under the same base seed. It does not merely change logging or diagnostics. The failure and observable markers jump immediately at `d26c939` and then remain unchanged through flow-context, DFO-LS callback-context, QN diagnostics/policy context, typed assist policy, formalized assist, and current HEAD.

## Ablation Proof

A temporary ablation was run at `d26c939` in the isolated worktree only.

Stage2-RNG-only ablation:

```bash
git diff d26c939d3db9bfc382f80ebb2c607d173a0a8fc4 84523cb -- \
  src/sampler/tltm_stage2_driver.f90 src/sampler/tltm_stage1_driver.f90 src/sampler/tltm_types.f90 | git apply
```

Full RNG ablation:

```bash
git diff d26c939d3db9bfc382f80ebb2c607d173a0a8fc4 84523cb -- src/core/mt95.f90 | git apply
```

Results:

| case | method | failures | mean Re<O> | mean Im<O> | NT assist | QN success | QN assist | rev rejects |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `84523cb` good | no_fb | 75 | -0.256943 | 0.216203 | 4174 | 0 | 0 | 14 |
| `84523cb` good | fb_norefine | 12 | -0.201866 | -0.338387 | 7728 | 17695 | 12 | 14 |
| `d26c939` bad | no_fb | 64 | -0.321239 | 0.017697 | 3888 | 0 | 0 | 12 |
| `d26c939` bad | fb_norefine | 22 | 0.762998 | 0.401465 | 7820 | 17604 | 7 | 9 |
| `d26c939` + Stage2 RNG ablation | no_fb | 74 | -0.142142 | 0.430041 | 4428 | 0 | 0 | 14 |
| `d26c939` + Stage2 RNG ablation | fb_norefine | 12 | -0.201733 | -0.338295 | 7728 | 17509 | 12 | 14 |
| `d26c939` + full RNG ablation | no_fb | 75 | -0.256943 | 0.216203 | 4174 | 0 | 0 | 14 |
| `d26c939` + full RNG ablation | fb_norefine | 12 | -0.201866 | -0.338387 | 7728 | 17695 | 12 | 14 |

Conclusion from ablation:

- Reverting the Stage2 RNG route alone restores `fb_norefine` to the good-side signature.
- Reverting both Stage2 RNG route and `mt95.f90` Gaussian-spare/state changes gives exact parity with `84523cb` for both `no_fb` and `fb_norefine`.

## Ruled Out / Not Primary

- Not typed policy alone: `2d8f1c1`, `6f98b5b`, and `6abd1e0` were tested with `INTODE_SOLVER_ASSIST_POLICY=all_navigation_diagnostic`; they still match the already-bad `d26c939` signature.
- Not ODEX extraction: `709a7de` and subsequent pre-d26 commits remain on the good-side tiny signature.
- Not ODEX `at`/`rt`: this reproducer did not touch tolerances except the explicit frozen `cttol=1e-13`/`QN_QUASI_TOL_OVERRIDE=1e-13`, and the jump happens at an RNG-only commit.
- Not DFO-LS callback context migration: `4076124` is unchanged from the d26 bad signature under forced NT+QN navigation assist.
- Not QN diagnostics/policy context migration: `9a2f591`, `18a354a`, and later context commits are unchanged from the d26 bad signature.
- Not "assist quasi finite residual accidentally certified below tol": the transition is caused before those policy/context commits, and full RNG ablation gives exact parity without changing solver residual acceptance logic.

## Recommendation

Treat `d26c939` as the first behavioral transition for this discrepancy.

The code change is not a numerical solver regression in ODEX/DFO-LS itself; it is a deterministic sampling trajectory change from the Stage2 RNG stream contract plus MT95 Gaussian-spare state ownership. The tiny reproducer proves the first jump. If longer-chain evidence continues to show bad failure density / means under the new contract, then `per_replica_rng_v1` must be treated as an unvalidated or broken sampling-kernel change, not merely as another acceptable fixed-seed trajectory.

Important correctness distinction:

- `legacy_global_v0` is the only RNG contract currently validated against the historical TLTM Stage2 behavior.
- `per_replica_rng_v1` may be a valid design only after proving stream independence, assignment of RNG state to the correct Markov object, and detailed-balance/statistical equivalence. The present evidence does not establish that.
- In the current code, RNG state is attached to fixed temperature slots and accepted swaps exchange `label_id`/configuration data but do not move `slot%rng_state`. If RNG history is intended to travel with the mobile replica/label, this is the wrong ownership model. If RNG is intended to belong to the fixed temperature kernel, it still needs direct validation because the longer-chain result is already negative.

Recommended path:

1. Add an explicit Stage2 RNG compatibility mode, e.g. `TLTM_STAGE2_RNG_STREAM_CONTRACT=legacy_global_v0|per_replica_rng_v1`.
2. Use `legacy_global_v0` when comparing to old `d3f133d`/official gate artifacts or when reproducing historical failure density.
3. Do not keep `per_replica_rng_v1` as a production-equivalent path unless it passes longer-chain statistical parity and a targeted detailed-balance/route audit.
4. Test a minimal alternative `per_label_rng_v1` where local-update RNG state moves with the accepted replica/label, plus a hashed/substream seed derivation, before claiming any explicit-RNG modernization is correct.
5. Add regression tests that run a tiny fixed-seed Stage2 smoke and assert both the RNG contract string and a small signature tuple such as `(failures, mean Re, mean Im, NT assist, QN success)` for each compatibility mode.
6. Do not use typed assist policy as the root-cause explanation. It is a later waypoint and may still be a policy choice, but the discrepancy already exists at `d26c939` with NT+QN navigation assist forced on.

## Modernization Directive: Stage2 Kernel RNG v2

Do not treat `legacy_global_v0` as the desired modernization design. Keep it only as a historical compatibility baseline. The modernization target should be a new explicit RNG contract:

```text
TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2
```

Design contract:

- RNG is owned by a transition-kernel invocation, not by a label, mobile replica, or long-lived temperature slot stream.
- All random events use domain-separated keys derived from the same `base_seed`.
- No long-lived local-update RNG state is advanced across proposals.
- Accepted replica exchange does not swap RNG state, because RNG state is not stored on labels/configurations.
- `mt95.f90` Gaussian spare state remains part of explicit RNG state when MT95 is used inside a kernel stream; the spare must never cross domain boundaries.
- Solver/HMC/QN/flow contexts must be scratch or diagnostics only. Any context field that changes the proposal law across invocations must be reset per proposal or promoted into an explicit Markov-state variable.

Required random domains:

```text
stage2:init              key = base_seed, slot_id, attempt_id
stage2:local_momentum    key = base_seed, cycle_idx, slot_id, update_idx
stage2:local_accept      key = base_seed, cycle_idx, slot_id, update_idx
stage2:swap_accept       key = base_seed, cycle_idx, pair_id
```

Implementation preference:

1. Prefer a counter-based RNG for v2, with `(domain, base_seed, cycle_idx, slot_id/pair_id, update_idx, draw_idx)` as the counter/key material.
2. If MT95 must be kept initially, instantiate one short-lived MT95 state per domain invocation using a robust 64-bit hash/mixer such as SplitMix64-derived seeding. Do not use linear seed derivation like `base_seed + stride*offset`.
3. `grand(momentum)` must be able to draw from the provided kernel RNG object, not from uncontrolled module-global RNG.
4. Metropolis accept and swap accept must draw from their own domain RNG objects.
5. Initialization RNG must be separate from production local-update RNG so adaptive init attempt counts cannot shift production sampling randomness.

Minimum tests for v2:

1. Deterministic replay test: rerun the same tiny config twice with `stage2_kernel_rng_v2`; assert byte-identical diagnostic signature and the printed contract metadata.
2. Schedule-invariance test: run the same fixed tiny config with local slot update order reversed or parallel-order simulated. With domain-separated kernel RNG, the final signature must be identical.
3. Init-decoupling test: force an extra rejected/adaptive init attempt in one slot while keeping the first accepted initial configuration fixed; production local RNG keys and post-init transition signatures must not shift.
4. Swap-isolation test: run a tiny two-slot config with swap disabled vs enabled and audit that local momentum/accept RNG keys for a given `(cycle, slot, update)` are unchanged.
5. Statistical smoke test: run old `legacy_global_v0`, current `per_replica_rng_v1`, and new `stage2_kernel_rng_v2` on the established `1 seed x 1000 cycles` p28/RG/cttol=1e-13 reproducer with NT+QN navigation assist forced. This is not a proof of correctness; it verifies that v2 is not immediately reproducing the known v1 bad transition.
6. Longer-chain benchmark: compare `stage2_kernel_rng_v2` against an independent physical/statistical benchmark, not only against `legacy_global_v0`. Track failure density plus mean Re<O>, Im<O>, acceptance, swap acceptance, round trips, NT assist, QN success, QN assist, and RG rejects.

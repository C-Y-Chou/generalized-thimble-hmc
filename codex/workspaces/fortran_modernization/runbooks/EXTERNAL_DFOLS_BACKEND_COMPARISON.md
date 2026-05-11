# External DFO-LS Backend Comparison

Updated: 2026-05-11 JST

## Purpose

This runbook defines the first external-DFO-LS integration boundary for the TLTM quasi-Newton / BTN rescue path.

The initial goal was offline comparison, not production-chain replacement:

- TLTM owns the physics residual, BTN variable convention, flow/backflow evaluation, and initial guess policy.
- The official Python DFO-LS package owns only the derivative-free least-squares solver mechanism.
- The comparison is behavior-diagnostic. It must not silently change the HMC proposal path or accepted production outputs.

After the 2026-05-11 license decision, official DFO-LS is also the intended
production backend target. The subprocess bridge remains offline-only; production
integration still needs a runtime architecture and behavior-preservation gates.

## External Package Contract

Official DFO-LS documentation defines the main API as `dfols.solve(objfun, x0)`, where `objfun(x)` returns a one-dimensional residual vector and `x0` is the user-provided starting point. Optional controls include `rhobeg`, `rhoend`, and `maxfun`.

Local dtype probe on 2026-05-11 using `DFO-LS==1.6.5`:

- Objective callback received `x.dtype == np.float64` and `itemsize == 8`.
- `soln.x.dtype == np.float64`.
- `soln.resid.dtype == np.float64`.
- `soln.jacobian.dtype == np.float64`.
- This version exposes the objective value as `soln.obj`; wrapper code still computes `dot(resid,resid)` when needed rather than relying on a single attribute name.

## Hard Boundary: Jacobian Meaning

The TLTM/flow Jacobian used in the current code is not the BTN residual/loss Jacobian.

Therefore:

- The bridge may use the base flow Jacobian only where the current TLTM code already uses it: seed construction and BTN residual geometry.
- The bridge must not pass a TLTM flow Jacobian to DFO-LS as a loss/residual derivative.
- The Python DFO-LS backend must see only `objfun(xi) -> residual_vector`; any interpolation/model Jacobian is owned internally by DFO-LS.

## Implemented Bridge

Source additions:

- `src/apps/evaluate_btn_residual_case.f90`
- `scripts/run_external_dfols_btn_compare.py`
- `requirements/external-dfols.txt`
- opt-in representative QN-attempt capture in `src/sampler/quasi_newton_solver.f90`

Build target:

```bash
make -C build evaluate_btn_residual_case
```

The makefile keeps the Linux `noexecstack` linker flag on Linux but omits it on macOS/Darwin, so the target should build on the local macOS/gfortran environment without `LDFLAGS=` overrides.

Bridge input:

- A capture directory containing `{PREFIX}_z0.dat`, `{PREFIX}_delz.dat`, and `{PREFIX}_x0.dat`.
- The default prefix is `constraint_solver_fail` for legacy hard-tail captures.
- For representative QN-entry captures, use prefix `qn_attempt`; these bundles also include `{PREFIX}_xi0.dat` and `{PREFIX}_meta.csv`.

This is the legacy failure-capture file shape. It is useful for checking the residual oracle and hard-tail behavior, but it is not a representative solver-replacement benchmark by itself.

Bridge modes:

```bash
bin/evaluate_btn_residual_case seed CASE_DIR SAMPLE_IDX
bin/evaluate_btn_residual_case residual CASE_DIR SAMPLE_IDX XI_1 ... XI_2N
```

Set `BTN_CAPTURE_PREFIX=qn_attempt` when reading representative QN-attempt captures.

The bridge recomputes the flow/Jacobian from captured `x0`, reports `z_recompute_inf`, and evaluates the retained BTN residual:

```text
xi(1:n)=b
xi(n+1:2n)=a
ztrial = z + del_z - J*(a+i*b)
fq = [aimag(flowzr(xt,ztrial)); a]
```

## Python Comparison Runner

Install package in an isolated environment:

```bash
python3 -m venv .venv-dfols
.venv-dfols/bin/python -m pip install -r requirements/external-dfols.txt
```

Run comparison:

```bash
.venv-dfols/bin/python scripts/run_external_dfols_btn_compare.py \
  --case-dir PATH_TO_CAPTURE_BUNDLE \
  --sample-ids all \
  --max-cases 100 \
  --maxfun 28 \
  --rhoend 1e-13 \
  --residual-success-tol 1e-12 \
  --out-csv codex/workspaces/fortran_modernization/output/external_dfols_btn_compare.csv
```

Important behavior:

- The runner enforces `np.float64` for `x0`, all DFO-LS objective inputs, and residual outputs.
- Residual-evaluation failure is not converted into a fake large value such as `1e10`; failed cases are recorded as errors for inspection.
- The CSV records a TLTM-side `residual_success` gate separately from the DFO-LS package `flag`. This is required because DFO-LS `Success: rho has reached rhoend` can still leave a residual that is too large for the TLTM projection tolerance.
- The runner can pass official DFO-LS internal controls through `--objfun-has-noise` and repeatable `--dfols-param KEY=VALUE`; these remain package options, not external optimization logic.
- The runner is intentionally subprocess-based. It is slower but keeps the external package decoupled from production Fortran and avoids unsafe in-process Python calls from HMC.

## Representative QN-Attempt Probe

Local probe on 2026-05-11:

- Source: 1 seed, 500-cycle `fb_norefine` Stage3-style smoke at `t=0.35`, `L=2`, `nstep=20`.
- Capture root: `output/tests/external_dfols_qn_attempt_probe/attempts`.
- Capture controls: `QN_ATTEMPT_CAPTURE_DIR`, `QN_ATTEMPT_CAPTURE_LIMIT=20`, `QN_ATTEMPT_CAPTURE_STRIDE=1`.
- Captured rows: 20 QN attempts before knowing solver outcome.
- In-house outcome in the captured attempt metadata: 17/20 converged; 3/20 non-converged.
- Initial residual range in the captured rows: about `2.7e-2` to `1.9e-1`.

External DFO-LS comparison observations:

| Setting | Float64 contract | DFO-LS package success flags | Final residual <= `1e-6` | Final residual <= `1e-12` | Notes |
|---|---:|---:|---:|---:|---|
| `maxfun=28`, package default `model.abs_tol=1e-12` | 20/20 | 14/20 | 14/20 | 0/20 | Package default stops near residual `1e-6`; not comparable to current TLTM QN tolerance. |
| `maxfun=112`, `model.abs_tol=1e-26`, default `rhobeg` | 20/20 | 19/20 | 15/20 | 11/20 | Lower package objective tolerance improves accuracy, but several cases still stop with residual around `1e-2`. |
| `maxfun=112`, `model.abs_tol=1e-26`, `rhobeg=0.25` | 20/20 | 19/20 | 17/20 | 13/20 | Best tested setting by count, but still not a drop-in replacement. |

Interpretation:

- Official DFO-LS can be called safely in double precision through the residual-only callback.
- The package default `model.abs_tol=1e-12` is an objective tolerance, not the TLTM residual tolerance. For a target residual around `1e-13`, the package tolerance must be set near `1e-26`.
- DFO-LS success flags are not sufficient for TLTM acceptance. A TLTM residual gate must be applied to the returned solution.
- Even with tighter tolerance and a larger initial trust radius, the tested external package settings did not uniformly match the current in-house QN attempt best residuals. Production replacement remains blocked pending a deliberate backend design and broader representative comparison.

## Tuned Official-DFO-LS Candidate

Follow-up tuning on 2026-05-11 restricted the search to official DFO-LS package controls. No external multistart, escape, line search, backtracking, or best-rescue logic was added.

Candidate command:

```bash
.venv-dfols/bin/python scripts/run_external_dfols_btn_compare.py \
  --case-dir output/tests/external_dfols_qn_attempt_probe_100/attempts \
  --capture-prefix qn_attempt \
  --seed-source capture \
  --maxfun 250 \
  --objfun-has-noise \
  --model-abs-tol 1e-30 \
  --model-rel-tol 0 \
  --rhobeg 0.05 \
  --rhoend 1e-16 \
  --residual-success-tol 1e-13 \
  --out-csv output/tests/external_dfols_qn_attempt_probe_100/tuning_candidate_noise_r005_maxfun250_abs1e30_rhoend1e16.csv
```

Candidate result on the 69-attempt representative probe:

| Subset | Count | Official residual <= `1e-13` | Max official residual | Notes |
|---|---:|---:|---:|---|
| All attempts | 69 | 66/69 | `3.30e-2` | Three failures are attempts where current in-house QN also did not converge. |
| In-house-converged attempts | 61 | 61/61 | `1.59e-15` | This is the key replacement-safety signal for the attempt-level solver. |
| In-house-nonconverged attempts | 8 | 5/8 | `3.30e-2` | Official DFO-LS solves five attempts that in-house did not, but still leaves three hard failures. |

Budget observations for the same candidate family on the first 20-attempt probe:

| `maxfun` | Official residual <= `1e-13` | DFO-LS package flag success | Max residual | Max `nf` | Notes |
|---:|---:|---:|---:|---:|---|
| 80 | 19/20 | 15/20 | `2.33e-2` | 80 | Too small. |
| 100 | 19/20 | 17/20 | `5.32e-10` | 100 | Too small for `cttol=1e-13`. |
| 150 | 20/20 | 19/20 | `1.27e-15` | 150 | Residual gate passes; one package flag hits max evals after reaching good residual. |
| 250 | 20/20 | 20/20 | `9.98e-16` | 209 | Conservative candidate. |

Hard-case notes:

- Attempts 33, 64, and 68 in the 69-attempt probe are in-house nonconverged attempts.
- Official DFO-LS with the candidate setting leaves 33 and 64 at `O(1e-3)` and 68 at `O(1e-2)` under `maxfun=250`.
- Additional official-only tuning can solve 33 and 64, for example `npt=4`/`npt=5` with larger budget, but sample 68 remained nonconverged in tested official settings up to `maxfun=1000`.
- This supports using official DFO-LS as an attempt-level backend candidate, while preserving the existing outer QN/HMC failure-as-rejection/control-flow semantics.

Current conclusion:

- Official DFO-LS is usable as a backend candidate for the retained BTN residual, provided the wrapper sets noise-aware official defaults, a small `rhobeg`, a much tighter objective tolerance, and a TLTM residual gate.
- The candidate setting is not the package default. Using package defaults would be incorrect for TLTM because the default objective tolerance stops too early.
- The next implementation decision is runtime integration design, not more external solver invention. Production integration must call official DFO-LS or a compiled equivalent backend through a residual-only boundary and keep TLTM acceptance based on `residual_norm <= cttol`.

## Replacement-Gate Cost Probe

The replacement-gate probe regenerated the same 1-seed, 500-cycle representative capture with extra in-house diagnostics:

- Capture root: `output/tests/external_dfols_replacement_gate/attempts`.
- Official candidate CSV: `output/tests/external_dfols_replacement_gate/official_candidate_maxfun250.csv`.
- In-house metadata now includes `residual_eval_count` and `cpu_seconds`.

Cost proxy result:

| Subset | Count | In-house residual calls median/mean/p90/max | Official `nf` median/mean/p90/max | Official residual <= `1e-13` |
|---|---:|---:|---:|---:|
| All attempts | 69 | 46 / 63.5 / 146 / 228 | 41 / 75.7 / 209 / 250 | 66/69 |
| In-house-converged attempts | 61 | 46 / 50.6 / 72 / 92 | 40 / 65.4 / 127 / 250 | 61/61 |
| In-house-nonconverged attempts | 8 | 153 / 161.9 / 163 / 228 | 245 / 154.1 / 250 / 250 | 5/8 |

Interpretation:

- Typical successful attempts are not obviously more expensive under official DFO-LS: median `nf=40` versus in-house median `46` residual calls.
- Official DFO-LS has a heavier successful-attempt tail: several in-house-converged attempts reach `nf=250` while still returning residual `O(1e-15)`.
- The cost proxy is residual-call based. It does not include Python/subprocess overhead, which is intentionally excluded from production feasibility because the subprocess bridge is an offline comparison tool.

## Replacement Decision Gate

Algorithmic readiness:

- Pass for attempt-level backend candidate on the current 1D toy-model representative probe.
- Official DFO-LS preserves all in-house-converged attempts in the replacement-gate probe.
- Official DFO-LS improves several in-house-nonconverged attempts but does not eliminate every hard failure.

Runtime readiness:

- Pass only as a residual-call proxy.
- Direct Python subprocess calls are rejected for production HMC inner-loop use.
- A production replacement would need either a compiled in-process backend, a carefully embedded Python design that is demonstrated not to dominate runtime, or an explicit decision to accept a Python-driven product architecture.

License/product readiness:

- `DFO-LS==1.6.5` reports license `GPL-3.0-or-later`.
- User decided preserving MIT is not required.
- The repository now carries a root `LICENSE` with GPL v3 text, a root
  `LICENSE_POLICY.md` with the project-level GPL-3.0-or-later grant, and a root
  `THIRD_PARTY_NOTICES.md`.
- Tapenade AD was checked as part of the toolchain. Local usage is external
  CLI/source-transformation codegen; the official Tapenade distribution license
  checked on 2026-05-11 is MIT License, Copyright INRIA. Tapenade does not drive
  the GPL decision, but generated-source provenance must be tracked.

Current final gate status:

- `GO` for: keeping official DFO-LS as the offline validation/calibration oracle and candidate reference backend.
- `GO` for: designing a residual-only backend interface in TLTM that can host either the current in-house solver or an official-DFO-LS-compatible backend.
- `NO-GO` for: direct production replacement by per-residual Python subprocess calls.
- `GO` for: GPL-compatible product direction.
- `HOLD` for: making official DFO-LS the production default until runtime
  integration is implemented and a small chain-level behavior gate is run.

Remaining implementation choices:

1. Backend-interface first: introduce a solver-backend abstraction, keep in-house as default, and add official DFO-LS as an opt-in experimental backend.
2. Full replacement: after behavior gates pass, make the official-DFO-LS backend the production default and keep the in-house solver only as a controlled fallback or deletion candidate.
3. Runtime architecture: choose compiled/in-process backend, carefully embedded Python, or a Python-driven product architecture; per-residual subprocess is rejected.

## Reference Dataset Comparison Plan

Current M6 R1-R4 reference packages are registered in `state/M6_REFERENCE_PACKAGES.tsv`.

Readback status on 2026-05-11:

- Correct materialized M6 reference-package root is remote worktree
  `/home/cychou/TLTM_worktrees/qn_error_handling_validation/output/reference/fortran_modernization/m6`.
- That root contains R1-R4 `no_fb` and `fb_norefine` summary/per-seed package tables at source commit `a1028ad`.
- The materialized packages do not contain representative QN-attempt capture files. Aggregate behavior comparison can use the existing M6 summary tables; official DFO-LS residual replay needs a separate M6-aligned attempt-capture bundle.

Historical-capture smoke on 2026-05-11:

- Input: local historical capture `/Users/ccy/Documents/local_repo/build/rehydrate_eval/s20l2_t035_2M_p02_withfb/chain_003/output`.
- Scope: first 3 captured failures only; this is not an accepted M6 reference package.
- Result: official `DFO-LS==1.6.5` preserved `float64_contract=1`, but was not a drop-in solver replacement under the current budget. At `maxfun=28`, external final residuals were around `2.4e-2` to `3.9e-2`, while the historical in-house trace best residuals were around `4e-9` to `1e-7`.
- Interpretation: failure-only replay is biased and not sufficient evidence for solver replacement. It samples hard tail / already-problematic cases rather than the QN attempt distribution seen by production.

Comparison sequence:

1. Residual-oracle smoke: use the existing failure-capture-shaped bridge only to verify variable order, sign convention, `flowzr` direction, double precision, and failure propagation.
2. Representative QN-attempt capture: use opt-in `QN_ATTEMPT_CAPTURE_DIR` instrumentation to record solver-entry cases before the solver outcome is known, including successful and failed attempts, a range of initial residual sizes, seeds/chains, and route/context labels.
3. Attempt-level solver comparison: replay the representative QN-attempt bundle through official DFO-LS and compare success rate within the same evaluation budget, final residual norm, `flowzr` imaginary norm, `a` norm, evaluation count, and error statuses against the in-house solver trace.
4. Aggregate behavior comparison: only if attempt-level comparison is acceptable, run a small M6-aligned chain comparison and compare against the existing R1/R2 M6 summary tables.
5. Reference-level behavior comparison: only after an explicit production integration design exists, run R1 -> R2 -> R3/R4 against M6 package metrics and route counters.

No production replacement is implied by this bridge. Production integration requires a separate runtime-boundary decision because per-residual subprocess/Python calls are unsuitable for HMC-scale execution.

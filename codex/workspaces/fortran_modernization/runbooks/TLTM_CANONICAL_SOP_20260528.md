# TLTM Canonical SOP

Date: 2026-05-28

Scope: canonical TLTM workflow for this repository after the Stephanov `n=6`
modernization and production-design work.  This document is a workflow freeze,
not an implementation patch.  It records the order of decisions and the
production boundary for closing the TLTM side of the repo before adding a
second sampler path such as WV-HMC.

Closure update, 2026-05-29: the frozen final criterion packet keeps this SOP's
canonical policy: `nofb` production, `withfb` default-off legacy diagnostic.
See
`runbooks/generated/post_tltm_wv_hmc_ready_20260529/FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md`.

## 0. Canonical Policy

Canonical TLTM production mode:

- `nofb` is the default production mode.
- `withfb` / DFO-LS fallback is legacy diagnostic mode, not default production.
- Lower numerical failure count is not itself a production criterion.
- Reverse gate remains on for production.
- Flow time is metadata / replica label state, not packed physical state.
- Model choice belongs in the model provider and parameter files, not in
  canonical Stage2 control logic.

Canonical acceleration layers:

- Keep phase/action/logdet caching.
- Keep batched model-provider RHS hooks when provider validation passes.
- Keep process-level job/record parallelism.
- Keep flow-bank initialization for a fixed ladder.
- Keep snapshot restart.
- Keep direct swap reflow as the default swap reflow backend.

Opt-in / non-canonical layers:

- `withfb` / DFO-LS fallback.
- External BLAS/LAPACK unless a target machine benchmark justifies it.
- Stage2 OpenMP local-update parallelism unless a production benchmark justifies
  it for the selected model and machine.
- Dense-output swap reflow, continuation cache, and lower-neighbor cache unless
  they beat direct reflow under trajectory-equivalence validation.
- Any tolerance loosening, reverse-gate relaxation, or failure-minimizing
  protocol tuning.

## 1. Model Gate

Before any TLTM production workflow, the model provider must define:

- scalar action;
- manually supplied gradient;
- manually supplied Hessian or Hessian-vector product;
- observable registry;
- observable analytic definitions;
- parameter schema and physical state layout;
- holomorphic complexification rule when the original model contains complex
  conjugation or Hermitian adjoints.

Validation:

- random complex-seed derivative validation against AD or finite differences;
- random complex-seed Hessian/Hv validation against AD or finite differences;
- observable registry consistency checks;
- small-size exact-reference check when available;
- no model-specific logic inside canonical Stage2 control code.

Output:

- validated model parameter file;
- model/provider validation log;
- exact-reference table if available.

## 2. HMC-0 Gate: Base Sampler at `t = 0`

Purpose: decide the HMC parameters used to build the physical `t=0` bank.

Decision order:

1. Choose `epsilon`.
2. Choose `nstep`.
3. Define `L = epsilon * nstep`.

Primary criteria:

- local acceptance is usable;
- trajectories do not stall or repeatedly enter pathological regions;
- autocorrelation and seed-to-seed scatter are acceptable for bank building;
- cost per usable physical sample is acceptable;
- exact observables pass when an exact small-size target exists.

Non-criteria:

- do not tune `nofb` by minimizing proposal or reflow failure count;
- do not use lower failure count as the reason to change `epsilon`, `nstep`, or
  `L` unless it also predicts downstream observable, mixing, or runtime damage.

Output:

- `t=0` HMC protocol: `epsilon`, `nstep`, `L`, cycles, burn-in, seeds;
- acceptance and autocorrelation readback;
- decision note explaining why the protocol is usable.

## 3. Build And Validate The `t = 0` Bank

Build the physical checkpoint bank only after HMC-0 is fixed.

Required bank content:

- physical state `x` only;
- model id and model parameters;
- physical state size;
- source HMC protocol;
- source RNG contract;
- source commit and output root;
- record count and seed list.

Required validation:

- action and observable distributions;
- seed-to-seed scatter;
- split-bank consistency;
- tail occupancy for important observables;
- exact-reference consistency when available.

If the bank fails coverage or stability checks, return to HMC-0.  Do not proceed
to flow-time endpoint selection with an untrusted bank.

## 4. Flow-Time Endpoint Selection

Purpose: choose `t_high`.

Procedure:

- start from the validated `t=0` bank;
- scan candidate flow times;
- inspect phase coherence / phase ESS;
- inspect local stability and runtime;
- inspect whether nofb remains able to produce usable samples;
- do not expect raw fixed-flow observables to match final TLTM observables
  before ladder tempering is active.

Endpoint rule:

- `t_high` must be large enough to materially improve the sign problem;
- `t_high` must not be so numerically unstable that canonical nofb production
  cannot generate usable samples;
- endpoint selection should be based on phase improvement, stability, and
  downstream ladder feasibility, not on fixed-flow observable correctness alone.

Output:

- selected `t_high`;
- rejected candidate flow times and reasons;
- phase / stability / runtime readback.

## 5. HMC-L Gate: Local HMC Parameters On The Ladder

Purpose: decide local HMC parameters for TLTM replicas after candidate flow
times are known.

Decision order:

1. Choose `epsilon`.
2. Choose `nstep`.
3. Define `L = epsilon * nstep`.

This gate is separate from HMC-0.  Do not assume the `t=0` HMC protocol remains
appropriate at higher flow time.

Criteria:

- acceptance is usable at each important flow-time region;
- trajectory length is sufficient for local movement;
- `nstep < 10` is preferred unless mixing evidence requires otherwise;
- wall-clock cost is recorded;
- failures are diagnostics only unless they predict downstream damage.

Output:

- ladder-local HMC protocol;
- per-flow or grouped-flow acceptance/runtimes;
- rationale for `epsilon`, `nstep`, and `L`.

## 6. Ladder Construction Gate

Purpose: choose the TLTM flow-time ladder.

Procedure:

- begin with a sparse ladder;
- run short equal-cycle probes;
- add intermediate replicas only where transport diagnostics require them;
- avoid making a dense ladder merely to suppress failure counts;
- rerun local HMC checks if a new flow-time region changes the local dynamics.

Diagnostics:

- swap acceptance by edge;
- label mean-squared displacement;
- round trips;
- first passage to high flow;
- return time from high flow;
- zero-round-trip seed fraction;
- high-flow trapping or non-return;
- edge-localized bottlenecks.

Output:

- final ladder list;
- edge diagnostics;
- round-trip / high-flow-return readback;
- statement of whether transport is adequate for production.

## 7. Flow-Bank Cache And Snapshot Setup

Purpose: reduce startup and restart cost without changing the production
transition kernel.

Flow-bank cache:

- keyed by model id, parameters, physical state size, backend, tolerances,
  `t=0` bank, and final ladder;
- fail-closed on missing or mismatched cache entries;
- records failures instead of silently dropping unreachable records;
- used for initialization only.

Snapshot restart:

- enabled for production segments;
- preserves replica states, labels, flow times, counters, pair swap counters,
  and round-trip bookkeeping;
- uses `skip` restart-boundary policy by default to avoid duplicate boundary
  samples.

Output:

- flow-bank manifest and diagnostics;
- snapshot policy;
- restart command pattern.

## 8. Production Run

Canonical production controls:

- method: `nofb`;
- reverse gate: on;
- swap reflow backend: direct;
- initialization: validated flow bank or validated snapshot;
- observable history: on;
- label trace: on;
- final snapshot: on.

Required metadata:

- model id and parameters;
- git commit;
- parameter file;
- flow ladder;
- HMC-0 and HMC-L protocol records;
- bank/cache roots;
- seeds and cycles;
- scheduler queue and node allocation;
- wall-clock timing.

Output:

- observable histories;
- label traces;
- summary files;
- final snapshots;
- timing records.

## 9. Production Readback

Primary readback:

- complex ratio estimator preserving numerator/denominator structure;
- exact-reference z-scores for available observables;
- real and imaginary parts reported separately;
- seed/block bootstrap or jackknife;
- phase coherence and phase ESS;
- denominator magnitude and angle stability;
- seed influence and leave-one-seed-out sensitivity.

Transport readback:

- swap acceptance by edge;
- label MSD;
- round trips;
- high-flow first passage;
- high-flow return time;
- high-flow residence and trapping;
- zero-round-trip seed fraction.

Efficiency readback:

- wall-clock per cycle;
- phase ESS per wall-clock hour;
- `1 / SE^2` per wall-clock hour for primary observables;
- bottleneck timing breakdown when available.

Failure readback:

- failure counts are diagnostic covariates only;
- failure matters only if it predicts or repairs downstream damage in
  observables, ratio stability, transport, high-flow return, or wall-clock
  efficiency.

## 10. Extension And Restart

If statistics are insufficient:

- continue from snapshot;
- keep the same model, ladder, HMC parameters, and production mode;
- concatenate using the recorded restart-boundary policy;
- rerun readback on common-prefix, all-available, and equal-wall-clock cuts.

Do not change HMC parameters or ladder mid-production unless a gate explicitly
fails.  If a gate fails, return to that gate and start a new campaign rather
than silently mixing protocols.

## 11. `withfb` Legacy Boundary

`withfb` remains available for:

- historical comparison;
- diagnostic failure-impact studies;
- final frozen-criterion checks;
- solver/backend research.

`withfb` is not canonical production unless a frozen criterion framework shows
that it repairs a real downstream problem:

- observable correctness failure;
- ratio-estimator instability;
- severe high-flow ergodicity risk;
- transport degradation that propagates to estimator quality;
- wall-clock-normalized information-rate advantage.

Lower failure count alone is explicitly insufficient.

## 12. TLTM Closure Checklist

TLTM is considered closed enough for a two-way repo layout only when:

- this SOP is the authoritative workflow;
- canonical run scripts match this SOP;
- non-canonical experiments are moved behind explicit legacy or experimental
  boundaries;
- `withfb` is default-off and documented as legacy diagnostic mode;
- HMC-0 and HMC-L decision records exist for the active benchmark;
- flow-bank and snapshot restart are documented and validated;
- production readback scripts report observable, ratio, transport, and
  wall-clock metrics without relying on failure count as a criterion;
- model-provider surfaces are general enough for the next model and for WV-HMC.

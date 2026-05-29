# Prompt Package: Readback Cycle for Testing Whether `withfb` Is Necessary

This package is meant to be copied into another AI conversation. The goal is not to ask that conversation for a final answer immediately. The goal is a readback cycle:

1. The other conversation reads the context.
2. It returns a structured readback of the problem.
3. It gives a concrete analysis request: what data, summaries, tests, or clarifications it needs.
4. That analysis request is brought back to this project workspace, where Codex can compute or answer it from the actual run data.
5. The resulting answer can then be sent back to the other conversation for criterion design.

## Round 1 Copy-Paste Prompt

```text
I need help designing finite-sample diagnostic criteria for a scientific Monte Carlo project. This is a readback cycle, not a request for a final answer yet.

Your task in this round:

1. Read the full context below.
2. Produce a concise readback of your understanding.
3. Identify missing information, ambiguity, or assumptions that matter.
4. Produce a concrete "analysis request" that I can send back to the code-running assistant.

Do not yet propose the final criterion package. First help me decide exactly what data and summaries should be requested from the actual project workspace.

Project goal
============

We are testing whether a more expensive algorithm variant called `withfb` is necessary compared with a cheaper variant called `nofb`.

The project is about TLTM, tempered Lefschetz-thimble Monte Carlo. In plain terms:

- We sample a difficult complex-valued path integral.
- The original integral has a sign problem: samples have complex phases that cancel, so estimates can become noisy or biased if sampling is poor.
- We use holomorphic flow to deform configurations into complex space. Larger flow time can reduce phase cancellation but makes numerical evolution harder.
- We use multiple replicas at different flow times, like temperature replicas in parallel tempering.
- The high-flow replica is important because it should have a milder sign problem.
- Replicas swap configurations along a flow-time ladder.

Current model and experiment
============================

Model: Stephanov model.
Matrix size: n = 6.
High flow time endpoint: t_high = 0.03.
Current comparison:

- `nofb`: cheaper production mode. It does not use the expensive fallback solver when reflow / inverse-flow related steps fail.
- `withfb`: more expensive mode. It uses a DFO-LS fallback solver to reduce some solver / reflow failures.

Important: We are not allowed to use "lower failure count" itself as proof that `withfb` is better. That would be circular. Failure count can be used only as a diagnostic or explanatory variable.

What we really need to know:

1. Does `nofb` have a sampling or correctness problem?
2. Does `withfb` actually improve observable estimates, mixing, effective sample size, or robustness?
3. Or does `withfb` merely reduce failure count while costing much more time?

Terms and definitions
=====================

TLTM:
Tempered Lefschetz-thimble Monte Carlo. A method that combines complexified holomorphic flow with a replica ladder in flow time.

Holomorphic flow:
An ODE that moves a real configuration into complexified configuration space. Flow time t controls how far the configuration is flowed. Larger t can improve the sign problem but can make the ODE more unstable or expensive.

Flow-time ladder:
A set of replicas at flow times t_0, t_1, ..., t_high. Neighboring replicas can swap. This is analogous to parallel tempering, but the ladder coordinate is flow time.

Replica:
One Markov chain at one flow-time label. It has its own local HMC updates and participates in swaps with neighboring flow-time replicas.

Cycle:
One production iteration or update cycle. It includes local moves and possibly swap attempts, depending on implementation.

Seed:
An independent run initialized with an independent random seed. We often run many seeds, for example 512, to measure seed-to-seed scatter and reduce wall-clock time through parallelism.

Observable:
A measured physical quantity. Current key observables include:

- chiral_condensate
- number_density
- logdet_dirac
- phase_factor
- min_singular_ba_m2

For n = 6, the exact reference values known for comparison are approximately:

- chiral_condensate = 0.0244771983
- number_density = 0.5661155667

Complex estimator:
Observables can be complex. For correctness checks, real and imaginary parts should be tested separately. For observables expected to be real, the imaginary part should be statistically consistent with zero.

Pooled ratio estimator:
The estimator has the form

    <O> = sum_i w_i O_i / sum_i w_i

where w_i is a complex phase / reweighting factor. Because the denominator is noisy and complex, ordinary independent-sample intuition can fail. Error estimation should respect the ratio structure.

Phase coherence:
A rough sign-problem indicator, often like

    |sum_i w_i| / sum_i |w_i|

Small values mean stronger phase cancellation. But phase coherence alone is not proof of correctness.

ESS:
Effective sample size. We care about both ESS per cycle and ESS per wall-clock time.

`nofb`:
The cheaper production mode. Some reflow / inverse-flow related operations may fail and are not recovered by the expensive fallback solver.

`withfb`:
The more expensive production mode. It uses an expensive fallback solver, currently DFO-LS, to recover some failed reflow / solver attempts.

DFO-LS:
Derivative-Free Optimizer for Least Squares. In this project it is used as a fallback nonlinear solver. It is expensive because it may require many objective function calls, and each objective call may require flowing a configuration.

Failure count:
How often a numerical step fails. It is useful diagnostic information, but not a primary criterion. A method with fewer failures is not automatically better if observables, ESS/time, and mixing do not improve.

Reflow / swap:
When swapping replicas at different flow times, one often needs to map or evaluate a configuration at another flow time. This can involve ODE integration and can fail if the flow is unstable.

Round trip:
In a replica ladder, a trajectory where a tagged configuration or label travels from low flow time to high flow time and back. More round trips usually suggest better ladder mixing.

High-flow endpoint:
The largest flow time replica. It is chosen large enough to reduce the sign problem but not so large that production becomes numerically pathological.

Current partial results
=======================

A partial check compared `withfb` common prefix 1500 cycles against `nofb` all currently available samples.

withfb prefix 1500:

- records: 512
- samples: 768000
- phase coherence: about 0.1190
- phase effective N: about 10876

nofb all currently available:

- samples: about 3.04 million
- phase coherence: about 0.1164
- phase effective N: about 41158

Observable comparison:

chiral_condensate:

- withfb1500 Re = 0.0241369, error = 0.0006336, z = -0.54
- withfb1500 Im = 0.0000858, error = 0.0005878, z = 0.15
- nofb all Re = 0.0248966, error = 0.0004732, z = 0.89
- nofb all Im = -0.0003412, error = 0.0004557, z = -0.75

number_density:

- withfb1500 Re = 0.562285, error = 0.02262, z = -0.17
- withfb1500 Im = 0.01388, error = 0.02544, z = 0.55
- nofb all Re = 0.565391, error = 0.01865, z = -0.04
- nofb all Im = 0.01145, error = 0.01938, z = 0.59

Initial observation:

- Current observable estimates do not show a clear advantage for `withfb`.
- Phase coherence is almost the same.
- `withfb` is much more expensive.
- However, complete long-run data are still being produced, so we need better criteria before making a final decision.

Task
====

This round is only for readback and analysis-request generation.

Please do not directly decide whether `withfb` is necessary yet.

Please produce:

1. Readback:
   - Restate the scientific and computational question in your own words.
   - Identify the main risk of circular reasoning.
   - Identify what would make evidence convincing versus inconclusive.

2. Missing information:
   - List the data or diagnostics that are necessary before designing the final criteria.
   - Separate "must have" from "nice to have".

3. Analysis request:
   - Write a concrete request that I can paste back to the code-running assistant.
   - The request should ask for computable quantities from the existing data.
   - The request should specify formulas or at least unambiguous definitions where possible.
   - The request should avoid vague requests like "analyze mixing"; instead say exactly what to compute.

The final criteria will eventually need to cover these categories:

1. Correctness criteria:
   - How to test whether `nofb` observable estimates are biased or wrong.
   - How to compare real and imaginary parts against exact values or expected symmetry.
   - How to handle pooled ratio estimators with complex weights.

2. Efficiency criteria:
   - ESS per cycle.
   - ESS per wall-clock time.
   - Error reduction per wall-clock time.
   - How to decide whether `withfb` earns back its runtime cost.

3. Ergodicity and mixing criteria:
   - Replica label movement.
   - Round trips across the flow-time ladder.
   - High-flow residence and return statistics.
   - Block means and seed-to-seed scatter.
   - Whether high-flow local proposals are stuck or non-ergodic.

4. Robustness criteria:
   - Stability across seeds.
   - Stability across block sizes.
   - Stability when comparing equal cycle count versus equal wall-clock budget.
   - Stability when using common-prefix data versus all-available data.

5. Diagnostic-only quantities:
   - Failure count.
   - Acceptance rates.
   - Swap rates.
   - Solver iteration counts.
   - ODE step counts.
   These may explain behavior but should not be the primary proof.

For each proposed criterion, please provide:

- Name of the criterion.
- Required data.
- Concrete formula or procedure.
- Null hypothesis or expected behavior.
- Decision rule.
- What would count as evidence for `withfb`.
- What would count as evidence against `withfb`.
- False positive risks.
- False negative risks.
- Priority level: must-do, useful, or optional.

Important constraints
=====================

- Do not say "`withfb` is better because it has fewer failures." That is not enough.
- Do not give only generic MCMC advice. The criteria must be tailored to:
  - complex reweighting,
  - ratio estimators,
  - flow-time replica ladders,
  - high-flow endpoint selection,
  - and `nofb` versus `withfb`.
- The experiment has finite cycles and many independent seeds, so the criteria should work under finite-sample uncertainty.
- We care about whether `withfb` is necessary enough to justify much higher runtime.

Please end with a prioritized experimental plan:

1. What should be computed first from the current data?
2. What should be computed after the full nofb and withfb runs finish?
3. What would be a convincing evidence threshold for adopting `withfb`?
4. What would be enough evidence to keep using `nofb`?

But in this round, only produce the readback and analysis request. Do not give the final criteria yet.
```

## Expected Round 1 Output Format

Ask the other conversation to use this structure:

```text
READBACK
- ...

KEY RISKS / AMBIGUITIES
- ...

MUST-HAVE ANALYSES TO REQUEST
- ...

NICE-TO-HAVE ANALYSES TO REQUEST
- ...

PASTE-BACK ANALYSIS REQUEST
Please compute/report the following from the actual TLTM run data:
1. ...
2. ...
3. ...
```

## Round 2 Prompt for This Workspace

After the other conversation returns its paste-back analysis request, send it here with:

```text
下面是另一個對話給出的 analysis request。
請使用目前 TLTM workspace 和 cluster outputs 回答它。
先不要改 simulation 設定；先只做可讀取資料的 analysis。

[paste the analysis request here]
```

## Optional Short Round 1 Prompt

Use this if the other conversation already understands TLTM and only needs the task:

```text
This is a readback cycle. Read the TLTM nofb vs withfb context and do not give final criteria yet. Instead produce: (1) a readback of the problem, (2) key risks and ambiguities, and (3) a concrete paste-back analysis request that asks the code-running assistant to compute specific finite-sample diagnostics from the actual data. The eventual goal is to decide whether expensive `withfb` is necessary over cheaper `nofb` in a Stephanov n=6, t_high=0.03 TLTM study, without using lower failure count as circular proof.
```

## Notes for Future Updates

- Replace the partial-result numbers once the full `nofb15k` and `withfb5k` runs finish.
- If exact reference values are updated or more exact observables are added, update the "Current model and experiment" section.
- If new diagnostics become available, add them to the required data list rather than changing the core decision principle.

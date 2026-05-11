# Implementation Truth Caveats

Updated: 2026-05-11 JST

Scope: caveats where the implementation or evidence is narrower than a casual project label could imply. These are not cosmetic wording issues; they define what can be claimed, what must be rerun, and what modernization work must address before publication-grade production.

## Rule

If a label is stronger than the implementation, fix the label or fix the implementation before using the result as evidence.

## DFO-LS Truth Boundary

Historical TLTM QN rescue code used a retained p28 BTN residual and in-house derivative-free least-squares machinery. It was "DFO-LS-style" in the local engineering sense, not the official DFO-LS package.

Official DFO-LS means all of the following are true:

- built with `ENABLE_OFFICIAL_DFOLS=1`;
- runtime uses `QN_SOLVER_BACKEND=official_dfols`;
- official package provenance is present, currently `DFO-LS==1.6.5`;
- official preset provenance is present, currently `QN_OFFICIAL_DFOLS_PRESET=stable_gate77`;
- TLTM accepts or rejects by the TLTM residual gate, not by package success flag alone;
- logs contain no official bridge/import/runtime failure.

Pre-official datasets remain useful as in-house/internal comparison baselines, but they must not be called official DFO-LS outputs.

## ODEX Truth Boundary

The current flow policy is:

```text
ODEX primary integration + solver-internal residual assist + strict final proposal flow
```

It is not:

- pure ODEX-only production policy;
- a complete Hairer ODEX package implementation claim;
- a hidden secondary-integrator final-proposal rescue policy.

Known ODEX scope differences or publication-facing decisions:

- dense output is absent or unused because TLTM currently needs endpoint flow values;
- explicit full-Hairer-style stability control is not exposed as a separate completed claim;
- solver-internal assist is deliberately allowed only for Newton/QN residual evaluation;
- final proposal `flow(...)` remains strict and cannot be completed by assist.

Therefore, modernization docs and wrapper/schema wording should say "ODEX-primary with solver-internal residual assist and strict final flow" unless a future implementation explicitly changes this contract.

## Historical Probe Boundary

Older kernel-correctness and validation probes are valuable evidence for the route they actually exercised. They must be tagged as historical when they used now-deleted or changed policy surfaces such as post-refine, in-house DFO-LS-style machinery, or pre-official backend semantics.

For official DFO-LS publication claims, rerun or extend the relevant correctness gates on the official backend line.

## Required Work Items

1. Audit project wording and output/report titles for DFO-LS ambiguity.
2. Audit ODEX wording for pure-ODEX or complete-ODEX overclaim.
3. Update the full program map so it distinguishes official backend, internal backend, ODEX-primary policy, and historical evidence.
4. Before final publication production, run or explicitly accept the official-DFO-LS-line kernel correctness gate.

## Rerun Or Relabel Rule

- If a run lacks official DFO-LS backend provenance, relabel it as in-house/internal/DFO-LS-style; rerun only if official DFO-LS evidence is needed.
- If a claim depends on pure ODEX-only or complete ODEX behavior, relabel it to the current reduced/specialized policy or implement and validate the missing ODEX feature.
- If source changes alter solver backend, flow policy, route order, tolerances, reverse gate, final-flow strictness, or Metropolis acceptance, rerun affected reference/correctness gates.

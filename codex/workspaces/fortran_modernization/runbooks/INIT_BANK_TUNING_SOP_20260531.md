# Initial Bank Tuning SOP

Date: 2026-05-31

Purpose: define how initial banks are built, validated, and used before TLTM
or WV-HMC parameter tuning.  This is a child SOP of
`PARAMETER_TUNING_SOP_20260531.md`.

## Core Rule

The initial bank is an upstream ensemble contract.  It must be fixed and
validated before interpreting solver traces, HMC acceptance, movement, ladder
transport, `W(t)` histograms, or observable z-scores.

Changing the bank, bank source, burn-in, thinning, record-selection policy, or
preflow/safe-flow filter invalidates downstream tuning unless an equivalence
check shows the downstream diagnostics are unchanged.

## Bank Types

Use these labels explicitly:

- `physical_t0_bank`: records drawn from a validated physical sampler at
  `t=0`.
- `flow_safe_bank`: a physical bank filtered to records that can be safely
  flowed to a target start flow time or interval.
- `lower_tau_fixed_bank`: records produced by a fixed-flow-time sampler at a
  declared lower flow time `tau_bank` inside or below the target WV/TLTM flow
  range.  This is a bank-construction sampler, not production evidence.
- `safe_init_only_bank`: a bank that prevents initial-flow aborts but has not
  passed physical coverage checks.
- `physical_quality_bank`: a bank that has passed physical coverage and
  exact-reference checks where available.
- `derived_post_burn_bank`: records harvested from a later sampler after a
  declared burn-in phase.
- `single_record_start`: all chains start from the same record; diagnostic only.
- `random_bank_draw`: each chain draws or maps deterministically to bank records;
  default production-shaped mode.

Do not call a safe-init bank a physical-quality bank.  Avoid using a
single-record start as evidence of ergodicity or correctness; it is a stress
test for mixing from one sector.

## Bank-Build Order

1. Fix model and observables.
   - Same model parameters and physical state layout as the target simulation.
   - Bank records store physical `x` only unless a documented snapshot format is
     used.

2. Tune the bank-building base sampler.
   - For a `t=0` physical bank, use the base HMC/TLTM `t=0` protocol selected by
     the standard order: `epsilon` first, then `nstep`, then `L`.
   - Do not tune the high-flow or WV production parameters before the base bank
     exists.

3. Generate bank records.
   - Use multiple seeds/chains.
   - Declare burn-in and history stride before inspecting final results.
   - Store source chain summaries and raw history sufficient to audit selection.

4. Validate physical quality.
   - action and primary observable distributions;
   - seed-to-seed scatter;
   - split-chain or split-bank consistency;
   - tail occupancy for important scalar diagnostics;
   - exact-reference consistency when available;
   - record count and byte-size checks.

5. Prevalidate flow safety if the target starts at nonzero flow time.
   - Flow each candidate record to the target start time or target interval
     using the selected ODE backend policy.
   - Save diagnostics and filter only by explicit safety criteria.
   - The filtered bank inherits physical quality only if the filter does not
     visibly distort the physical diagnostics; otherwise label it safe-init only.

6. For WV-HMC or high-flow initialization, prefer a lower fixed-tau bank when
   a direct target-flow bank is expensive or poorly mixed.
   - Default to `tau_bank = 0`, the physical-manifold lower endpoint.  Do not
     use a positive lower `tau_bank` to hide solver/reflow failures.
   - Run a fixed-tau simulation at `tau_bank` with its own HMC tuning.  Because
     lower flow time is usually numerically easier, this builder can often use
     larger `epsilon` and larger `L` than the target WV-HMC production kernel.
   - Tune the fixed-tau builder by the same order: `epsilon` first for
     acceptance, then `nstep/L` for configuration-space movement.
   - If a positive `tau_bank` is intentionally used, it must remain failure-free
     at the selected fixed-tau builder `epsilon/L`; otherwise lower `tau_bank`,
     not `epsilon`.
   - Harvest cyclic snapshots, final states, or x-history after declared
     burn-in and pack records as needed into the downstream state-bank format.
   - Label this as `lower_tau_fixed_bank`; do not claim the fixed-tau builder
     observable as production evidence for the target algorithm.
   - Decide builder cycle sufficiency from bank coverage and sampler health:
     zero proposal/reflow solver failures, stable acceptance/movement across
     seeds and chunks, post-burn first-half versus second-half state stability,
     seed-to-seed scatter, enough harvested records after stride, and a
     downstream WV/TLTM validation rerun from the packed bank.

7. Freeze record-selection policy.
   - Production-shaped runs use random or deterministic seed-based bank draws.
   - Matched comparisons use the same bank and a recorded matched selection
     policy.
   - Single fixed record starts are diagnostic controls, not production
     evidence.

## Validation Criteria

A bank can be used for parameter tuning only after:

- source model and state size match the target;
- raw byte count and record count match the manifest;
- no hidden flow-time label is packed into physical-state records;
- each record-selection policy is reproducible from seed/run metadata;
- safe-flow prevalidation target and ODE policy are recorded when applicable;
- bank source chains have acceptable split/seed diagnostics for the intended
  development stage.

For production-quality claims, additionally require:

- exact-reference agreement for small models when available;
- split-bank estimates stable under disjoint subsets;
- no small subset of seeds dominates primary observables;
- coverage stable when increasing bank size or changing disjoint source chains;
- any filtering to a flow-safe bank does not create observable bias beyond
  statistical error.

## Downstream Use

When using a bank for HMC/WV/TLTM tuning, every scan row must record:

- bank path;
- bank type label;
- record count and state width;
- selection mode: random/deterministic matched/single record;
- source record ids or seed mapping if available;
- burn-in applied after bank start, if any;
- preflow/adaptive initialization policy;
- safe-flow filter target and failure count when applicable.

If the initial bank is safe-init only, the sampler must include a burn-in or
thermalization plan before observable claims.  If a later run harvests a
derived post-burn bank, that bank becomes a new upstream input and downstream
solver/HMC/geometry tuning must be revalidated or explicitly checked for
equivalence.

## Comparisons

For algorithm comparisons such as `nofb` vs `withfb`, TLTM vs fixed-tau, or
WV-HMC parameter variants:

- use the same physical bank whenever possible;
- use matched record-selection policy for paired comparisons;
- separate random-start coverage tests from single-record stress tests;
- do not interpret a single-record start as proof of global ergodicity;
- if one method uses a flow-safe filtered bank and another does not, label the
  comparison initialization-mismatched unless the filter effect is measured.

## Invalidation Rules

| Bank Change | Downstream Recheck |
|---|---|
| model parameters or physical state size | rebuild bank; all downstream gates |
| bank-building HMC protocol | physical-quality validation; all downstream tuning |
| burn-in or thinning/stride | bank coverage; HMC/movement validation |
| record count or source seed set | seed robustness; observable and movement checks |
| random draw to single fixed record | diagnostic-only; no production claim |
| single fixed record to random draw | acceptance/movement and observables |
| safe-flow filter target changes | solver trace, HMC tuning, flow/WV diagnostics |
| ODE backend/tolerance used for prevalidation changes | safe-flow validation and solver health |
| `tau_bank` or fixed-tau bank-builder HMC protocol changes | bank coverage; solver trace, HMC tuning, flow/WV diagnostics |
| derived post-burn bank replaces t=0 bank | all downstream gates unless equivalence checked |

## Existing Bank Policy Documents

- `STEPHANOV_T0_CHECKPOINT_BANK_20260522.md`: first Stephanov `n=6`, `t=0`
  development bank and coverage diagnostics.
- `WV_HMC_INITIAL_BANK_POLICY_20260530.md`: WV-HMC safe-init vs
  physical-quality bank distinction and bank hooks.

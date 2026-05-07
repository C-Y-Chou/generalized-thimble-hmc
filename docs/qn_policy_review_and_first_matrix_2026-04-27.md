# QN Policy Review And First Matrix

Date: 2026-04-27

## Evidence Reviewed

Policy documents:

- `docs/fallback_policy_s1.md`
- `docs/stage3_4_rescue_path_ablation_plan_2026-04-25.md`
- `docs/stage3_4_nonnear_rescue_ablation_2026-04-24.md`
- `docs/local_kernel_fallback_debug_plan_2026-04-24.md`
- `docs/qn_proposal_inclusion_design_2026-04-27.md`
- `docs/stage_3_4_t035_rescue_screening_50k.json`
- `docs/stage_3_4_t035_rescue_promotion_100k.json`

Result summaries:

- `output/tests/stage3_4/probe_only_1024seed_200k_t035`
- `output/tests/stage3_4/rescue_ablation/promote_100k`
- `output/tests/stage3_4/rescue_ablation/probe_filter_matrix_64seed_200k_t035`

## Current Facts

At `t=0.35`, `1024 seeds x 200k`:

- `no_fb`: `Re<virial> = -0.0208976`, unresolved failures `15131675`.
- `probe_only_p28`: `Re<virial> = +0.00543094`, unresolved failures `2974657`.

So QN is useful, but p28 is not fully consistent in Re mean.

Promotion screen:

- `p28` / `nonnear_off_p28` reduces failures by about `80%`.
- `p32` gives only tiny extra failure gain but a measurable paired shift.
- `p34/p36/p40` reduce failures by about `96%`, but Re coverage fails badly.
- `nonnear_on_cheap36` behaves like the bad deep-QN region and is rejected.

Probe/filter screen:

- raw deeper QN can shift Re.
- filter variants suppress the bad shift but rescue little beyond p28.

Zero-start fallback:

- removed. It reduced failure count but did not provide a robust correctness improvement.

## Design Conclusion

The right design is not:

```text
p28 fail -> conditional route escalation
```

and not production-first:

```text
replace p28 by p34/p40/full_s1
```

The previous proposal in this note was a certified priority extension (`CPE`).
That is not strong enough as a first filter. Actual-policy reverse certification is a necessary sanity check, but it is not sufficient:

- fullpath can plausibly pass reverse checks while still changing the ensemble;
- reverse checks do not test volume preservation;
- reverse checks do not test missing proposal-density / multiple-candidate selection factors;
- reverse checks do not explain why Re-virial shifts.

Therefore the first task is not to promote a certified extension. The first task is to explain why fullpath changes the ensemble.

The correct first diagnostic target is:

```text
fullpath-added proposals
  = proposals that p28 would not include, but fullpath includes
```

Branch switching is allowed. The question is whether these added proposals are valid under the current Metropolis accounting.

## Why Reverse Certification Is Not Enough

For deterministic HMC-style proposals, standard `exp(-Delta H)` Metropolis needs more than reversibility. The proposal map also has to be volume-preserving, or else the acceptance ratio needs a Jacobian/proposal-density correction.

So a proposal can satisfy:

```text
forward then reverse returns to the start
```

and still be invalid under the current acceptance rule if the map is not volume-preserving or if candidate selection changes proposal density.

This is the likely missing piece if fullpath passes reverse sanity checks but moves Re mean.

## First Required Diagnostic: Fullpath Added-Proposal Audit

Before designing another rescue policy, run a proposal-level audit comparing `p28` and `fullpath` on the same local states/momenta.

For every local projection failure:

1. Run `p28`.
2. Run `fullpath`.
3. Classify event:

   | class | meaning |
   |---|---|
   | `common_success` | p28 succeeds; fullpath would also succeed |
   | `added_success` | p28 fails; fullpath succeeds |
   | `common_fail` | both fail |
   | `route_changed` | both solve, but produce materially different endpoints |

4. For `added_success`, record:

   - final endpoint and phase-weighted observable contribution;
   - region on manifold, especially `Re z` bins;
   - QN route/stage/candidate selected;
   - `Delta H`;
   - reverse return error;
   - local finite-difference log-volume estimate if feasible;
   - candidate multiplicity: how many QN candidates also solve.

This answers whether fullpath is adding a structured biased subset, or whether the issue is a missing proposal-density/volume factor.

## Local Volume / Proposal-Density Test

For the 1d toy model, finite-difference volume diagnostics are affordable.

For a sample of `added_success` events, estimate the local Jacobian of the full proposal map in tangent phase-space coordinates:

```text
logJ = log |det dT|
```

Compare:

- p28 accepted proposals;
- fullpath common proposals;
- fullpath added proposals.

If `logJ` is not near zero for added proposals, then fullpath is not valid with the current Metropolis ratio. The correct solution is either:

- include the Jacobian/proposal-density correction, if practical;
- or reject/certify only proposals whose map is locally volume-preserving.

If `logJ` is near zero and reverse errors are small, then the bias is likely from proposal-density / multiple-candidate selection accounting or finite-time transport, not gross non-volume preservation.

## Revised First Test Matrix

The first matrix should be diagnostic, not a rescue promotion matrix.

Run:

```text
stage3_4, t=0.35, ladder [0.05, 0.35]
8 seeds x 20k cycles
capture local projection events
```

Policies:

| policy | role |
|---|---|
| `p28` | base QN policy |
| `p34_raw` | known bad deeper QN |
| `p40_raw` | stronger bad/deep QN |
| `fullpath_raw` | maximal old rescue path |
| `fullpath_with_reverse_audit` | same fullpath, record actual-policy reverse errors |
| `fullpath_with_volume_audit` | same fullpath, finite-difference logJ on sampled added proposals |

Required output:

- per-event audit table;
- per-policy summary;
- added-proposal observable contribution by `Re z` bin;
- reverse return error distribution;
- logJ distribution for added proposals;
- candidate multiplicity distribution.

Only after this audit should we design a rescue inclusion policy.

## Possible Outcomes

### Outcome A: Fullpath Added Proposals Fail Reverse

Then reverse failure is one concrete defect in fullpath. It can be used to
explain part of the bad behavior, but it should not be promoted as the whole
solution unless it removes the same proposal class that causes the Re shift.

If reverse rejection removes only a tiny fraction of fullpath-added proposals,
then reverse certification is only a sanity diagnostic and not a useful rescue
policy.

### Outcome B: Fullpath Added Proposals Pass Reverse But Have Nonzero logJ

Then the problem is missing Jacobian/proposal-density correction. A filter based only on reverse is not enough.

### Outcome C: Fullpath Added Proposals Pass Reverse And logJ Is Near Zero

Then the problem is likely candidate-selection probability / multiple-try accounting, or finite-time transport rather than local map validity.

### Outcome D: Added Proposals Are Concentrated In A Biased Manifold Region

Then we need a proposal-density-correct method, not a heuristic geometry gate. A geometry gate could diagnose but should not become production unless its acceptance ratio is accounted for.

## Design After Audit

If the audit identifies the missing factor, production should be one of:

1. fullpath with corrected Metropolis factor;
2. multiple-try QN with explicit candidate weights;
3. delayed-rejection QN with proper acceptance formula;
4. a reduced proposal route whose inclusion rule is understood from the
   proposal-measure audit.

Do not promote another gate until the fullpath-added-proposal audit explains the observed Re shift.
If fullpath passes the proposed filters and still shifts Re, then those filters
have not identified the defect and should not be treated as a solution.

## First Minimal Replay Result

Run:

```text
output/tests/stage3_4/qn_added_audit/min_capture_1seed_1000
```

Setup:

- `stage3_4`, `t=0.35`, ladder `[0.05,0.35]`
- seed `20260421`, `1000` cycles
- fallback off capture, `86` Newton failures
- replayed the same failures under several QN policies

Result:

| policy | global fallback | max_iter | success |
|---|---:|---:|---:|
| `p28` | off | 28 | `70/86` |
| `p34` | off | 34 | `70/86` |
| `p40` | off | 40 | `70/86` |
| `p100_noglobal` | off | 100 | `70/86` |
| `global36` | on | 36 | `86/86` |
| `global100` | on | 100 | `86/86` |

Interpretation:

- the extra solved proposals do not come from a larger single-pass iteration
  budget;
- they come from the global continuation/restart route;
- the 16 added proposals are a structured endpoint subset, not a random copy of
  the p28 successes;
- therefore the next diagnostic should instrument global route phase,
  local log-volume/Jacobian, reverse return, and candidate multiplicity.

Detailed report:

```text
output/tests/stage3_4/qn_added_audit/min_capture_1seed_1000/replay/minimal_replay_audit_report.md
```

## Minimal Replay: Reverse/Route Update

The first route-level audit changes the interpretation.

For the 86 captured Newton failures:

- `p28` solves `70/86`.
- `global36` solves `86/86`.
- `global36` added cases are the 16 cases that p28 did not solve.

Route source for the 16 added cases:

| route | count |
|---|---:|
| continuation scale `1.00` | `10` |
| fine continuation scale `1.00` | `1` |
| restart kick positive | `2` |
| seed sweep zero | `2` |
| seed sweep negative-stage | `1` |

Actual-policy local reverse audit:

| group | n | reverse converged | small reverse error |
|---|---:|---:|---:|
| p28/common successes | `70` | `70` | `65` |
| global36-added successes | `16` | `16` | `16` |

The important point is that the added proposals do not fail this reverse audit.
Their reverse errors are at roundoff level:

```text
median dx = 2.43e-14
median dz = 4.29e-14
median dp = 7.86e-13
```

By contrast, five baseline p28/common successes reverse to a different state
with `dx ~= 0.56..0.65`, concentrated near endpoint `Re z ~= +/-0.265`.

This means the current defect cannot be summarized as:

```text
fullpath adds non-reversible proposals
```

The more accurate statement is:

```text
added proposals are structured, but this small sample does not show them failing
local reverse; baseline p28 already has a small non-reversible subset; deeper
rescue likely changes route support/proposal measure or exposes a larger added
class not captured by the first 1000-cycle sample.
```

Immediate implication:

- Do not design a filter that only checks reverse convergence; it would keep all
  16 added proposals in this audit.
- The next useful test is either full local phase-space volume/Jacobian, or a
  larger route-specific capture focused on the known bad `p34/p36/p40` region.
- The p28 reverse-defect cases around `Re z ~= +/-0.265` should be tracked as a
  separate baseline defect, because they may explain the remaining p28 Re-mean
  offset.

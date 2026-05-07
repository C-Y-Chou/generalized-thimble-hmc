# Local Kernel / Fallback Debug Plan

Date: 2026-04-24

## Purpose

This note records the current working plan for debugging fallback-induced bias in stage 3, so the logic is not lost across sessions.

## Current picture

1. `stage3_4` shows a real tension:
   - fallback greatly reduces unresolved failures
   - but `Re <virial>` / `Re` coverage can get worse

2. A plausible interpretation is:
   - the `no_fb` local kernel is not good enough by itself
   - but when a local proposal fails, it is cleanly rejected and the remaining transport is handled by TLTM
   - fallback may be rescuing some proposals that are better left to TLTM

3. A single-seed reversibility sanity check suggests:
   - fallback-rescued trajectories can still be numerically reversible
   - therefore the problem is not obviously "gross irreversibility"
   - this does **not** prove the rescued local kernel is fully correct

## Important caution

Do **not** assume that because `stage3_3` looks good, its fallback path is universally correct.

Possible realities:

1. `stage3_3` uses a structurally simple rescue subset that is genuinely safe
2. `stage3_3` only looks safe in that regime
3. the same "safe-looking" subset may already fail once moved to `stage3_4`

So we should **not** freeze `stage3_3` directly as truth.
We should first inspect its structure and only freeze it if that structure is simple and survives testing at higher flow time.

## Working hypothesis to test

The right question is not:

- "How do we reduce failures as much as possible?"

The right question is:

- "Which local rescue structures are safe to add beyond the baseline kernel?"

Equivalently:

- a rescued local accept may be individually reasonable
- but the added rescued ensemble must still be the correct added distribution
- otherwise failure reduction can make the global result worse

## Core principle

Any new rescue layer should be treated as an **extension** of a trusted simpler kernel.

That means:

1. if a proposal is already solved by the simpler path, the richer path should not materially change the result
2. any added rescue should only enlarge the success set
3. the added rescued ensemble must be checked for correctness, not only for lower failure count

## What to look for in `stage3_3`

We should perform a structure census of successful fallback usage and ask:

1. Are most successful rescues concentrated in a simple subset?
   - `NEAR` only?
   - no coarse continuation acceptance?
   - no multistart/reset diversification?
   - strict final stage only?

2. Is that subset small and interpretable enough to become a candidate core?

Only if the answer is yes should we consider freezing it.

## What must be tested in `stage3_4`

Take the candidate simple subset from `stage3_3` and test whether it remains safe at `t=0.35`.

Required checks:

1. Does the same structure remain numerically stable?
2. Does it preserve observable quality?
3. Does it still avoid introducing a `Re <virial>` shift?
4. On overlap cases, does it agree with the simpler path?

If it fails here, then it is not a true core; it is only a regime-specific workaround.

## Engineering direction

Do not center future debugging on failure count alone.

Instead, organize fallback internals into structural pieces such as:

1. `NEAR` vs `NON-NEAR`
2. `SKIP` / `LIGHT` / `ANCHOR`
3. coarse continuation acceptance at `lambda < 1`
4. multistart/reset diversification

Then treat them as candidate extension layers on top of a simpler base.

## Recommended validation order

1. Structure census in `stage3_3`
   - identify what successful fallback actually does there

2. Candidate core extraction
   - only if the structure is simple enough

3. Cross-regime validation in `stage3_4`
   - same structure, same diagnostics

4. Extension-only checks
   - richer rescue must not alter already-safe overlap cases in a meaningful way

5. Only after that, add more rescue depth
   - and verify that the newly added rescued ensemble is correct

## What not to assume

Do not assume:

1. fewer failures automatically means more correct
2. `stage3_3` correctness automatically transfers to `stage3_4`
3. a numerically reversible fallback trajectory is automatically a fully correct local kernel

## Immediate next-step recommendation

When resuming this line of work, start with:

1. a `stage3_3` fallback structure census
2. extraction of the simplest plausible candidate core
3. explicit testing of that same structure in `stage3_4`

The main decision to make after that is:

- whether a transferable simple core exists at all
- or whether high-flow local rescue should remain deliberately limited and leave harder cases to TLTM transport

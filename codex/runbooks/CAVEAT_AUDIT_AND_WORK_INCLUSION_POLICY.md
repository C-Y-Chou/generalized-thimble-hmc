# Caveat Audit And Work Inclusion Policy

Updated: 2026-05-11 JST

Scope: prevent known caveats from living only in chat, long logs, or hidden runbooks.

## Rule

Every material caveat must be classified in `codex/state/CAVEATS.tsv` before the work continues past the point where that caveat could change interpretation.

## Classification

- `blocking`: must also appear as an active high-priority row in `codex/state/OPEN_ITEMS.tsv`.
- `provisional`: work may continue, but outputs must be labeled provisional and rerun triggers must be explicit.
- `guardrail`: the caveat changes workflow safety, not science; fix the workflow and rerun only invalid artifacts.
- `implementation_truth`: the project label or claim is stronger than the implementation or evidence; fix the claim, fix the implementation, or rerun the right evidence before using it.
- `historical`: no active work unless that historical artifact or script is reused.

## Audit Steps

Before entering a major TLTM workflow, read:

1. `codex/context/L0_BOOT.md`
2. `codex/state/CAVEATS.tsv`
3. `codex/state/OPEN_ITEMS.tsv`
4. the chosen workspace `context/STATE_BRIEF.md`
5. any source file named by the caveat row

Then answer three questions:

1. Is there any active high-priority caveat that blocks the requested next step?
2. If not blocking, does it make the output provisional or trigger a later rerun?
3. If a new caveat was found, was it added to `CAVEATS.tsv` and, when blocking, to `OPEN_ITEMS.tsv`?

## Rerun Boundary

- Science rerun is required only when the caveat changes physics, solver route/order, tolerances, seed/cycle contract, RNG stream, output schema meaning, counter/status semantics, wrapper behavior, or acceptance criteria.
- Workflow rerun is required when a job/artifact was created under the wrong worktree, branch, commit, dirty state, or dependency set.
- Documentation, guardrail, or registry corrections do not invalidate already correctly routed and correctly pinned outputs.

## Closure

A caveat can be closed only after:

- the required work is complete or explicitly accepted as a known limitation;
- rerun triggers are updated if needed;
- `CAVEATS.tsv`, `OPEN_ITEMS.tsv`, and the relevant workspace session log agree.

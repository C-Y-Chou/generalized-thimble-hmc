# Pre-Stage3_4 Completion Plan

Updated: 2026-05-08
Scope: work that is safe and useful before Stage3_4/TLTM judgment completes. No Fortran source edits, no production job submissions.

## Position

We are at the end of M0 planning. Before Stage3_4/TLTM judgment completes, the modernization task should not implement algorithm or architecture changes. The useful work now is to finish static planning artifacts, decision capture, and audit queues so the post-judgment phase can begin cleanly.

## Correct Sequence After Stage3_4

1. Stage3_4/TLTM judgment completes.
2. Generate a temporary characterization baseline of current behavior.
3. Canonicalize the core numerical behavior: p28-only route, RG permanent, post-refine decision, ODEX-only comparison, legacy rescue/route deletion decisions.
4. Freeze the official baseline for the confirmed canonical TLTM algorithm.
5. Proceed with repo-wide modernization: code hygiene, architecture, wrapper, reentrancy/OpenMP, product readiness.

## What To Complete Before Stage3_4 Finishes

Planning artifacts:

- Confirmed decisions and roadmap.
- Pre-Stage3_4 completion plan.
- Cross-cutting infrastructure audit.
- Code hygiene audit.
- Legacy deletion candidates registry.
- Planning index.

Static audit scope:

- File/module responsibility map.
- Cross-cutting infrastructure map.
- Module `save` state inventory plan.
- RNG/config/I/O/diagnostics/output schema risk map.
- Safe cleanup checklist.

Do not do before Stage3_4/TLTM judgment:

- No source refactor.
- No ODEX-only implementation switch.
- No deletion of Radau/JFNK/final-resort stack.
- No deletion of non-p28 routes.
- No post-refine removal.
- No Stage2/Stage3 output schema changes.
- No RNG/context rewrite.

## Exit Criteria For M0

M0 is complete when these files exist and are internally consistent:

- `CONFIRMED_DECISIONS_AND_NEXT_PLAN.md`
- `PRE_STAGE3_4_COMPLETION_PLAN.md`
- `CROSS_CUTTING_INFRASTRUCTURE_AUDIT.md`
- `CODE_HYGIENE_AUDIT.md`
- `LEGACY_DELETION_CANDIDATES.md`
- `PLANNING_INDEX.md`

After M0 exit, this modernization thread should wait for Stage3_4/TLTM judgment or continue only with read-only/static audit notes.

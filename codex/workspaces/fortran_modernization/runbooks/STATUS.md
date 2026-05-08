# Task Status: fortran_modernization

Updated: 2026-05-08 JST

## Objective
- Define the governing principles, workstreams, milestones, and verification rules for systematic TLTM Fortran modernization.
- Keep behavior preservation explicit: engineering changes must not silently change the underlying physics or accepted reference outputs.

## Current state
- Initial modernization governance set established.
- Architecture review started; large solver and flow modules identified as primary structural risk.
- Behavior-preservation protocol elevated to a hard requirement for all future refactors.
- User-confirmed alias: "code refine" means this `fortran_modernization` task, not a separate workspace.

## Next actions
1. Expand the architecture audit with concrete dependency and responsibility findings.
2. Build a baseline verification matrix for representative configs and fixed seeds.
3. Rank refactor targets by risk and payoff before touching Fortran kernels.
4. After the current Stage3_4 test round finishes, revisit this workspace before implementation-level code cleanup/refactor.

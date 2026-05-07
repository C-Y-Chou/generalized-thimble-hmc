# Task Status: fortran_modernization

Updated: 2026-04-30 16:05 JST

## Objective
- Define the governing principles, workstreams, milestones, and verification rules for systematic TLTM Fortran modernization.
- Keep behavior preservation explicit: engineering changes must not silently change the underlying physics or accepted reference outputs.

## Current state
- Initial modernization governance set established.
- Architecture review started; large solver and flow modules identified as primary structural risk.
- Behavior-preservation protocol elevated to a hard requirement for all future refactors.

## Next actions
1. Expand the architecture audit with concrete dependency and responsibility findings.
2. Build a baseline verification matrix for representative configs and fixed seeds.
3. Rank refactor targets by risk and payoff before touching Fortran kernels.

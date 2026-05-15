# Tree Convergence After Assist Resolution - 2026-05-14

## Decision

The solver-assist discrepancy/root-cause branch is no longer an active
production-comparison blocker. Keep its readbacks as diagnostic evidence, but do
not continue parameter tuning, ODEX sequence controls, NT-assist controls, or
`npt5` scale-up as the next production path.

Active TLTM work is now narrowed back to two trees:

- `fortran_modernization`: finish the modernization fix and source/product
  closure.
- `tltm_production_comparison`: stay on hold until the fixed modernization
  commit is selected, then sync and regenerate production.

## Production Hold Rule

Do not submit new production-comparison jobs from the current formalized-assist
or diagnostic branches.

Before production resumes:

1. Confirm the modernization fix is complete and identify the exact commit.
2. Refresh remote worktree/job state.
3. Fast-forward/sync the production-comparison branch/worktree to that commit.
4. Clean or namespace outputs so old diagnostics cannot be merged with the redo.
5. Rebuild and rerun the production comparison from the synchronized tree.

## Closed Diagnostic Branches

The following remain useful evidence, but are not active next steps:

- assist-off DFO-LS parameter tuning campaign;
- formalized assist bridge at commit `6f98b5b`;
- NT+QN assist diagnostic control;
- ODEX legacy-sequence control;
- QN+assist preset/refinement matrix and `npt5` scale-up.

## Next Production Action

Wait for the modernization fixed commit. After synchronization, redo production
from a clean namespace and record the new dataset as the post-fix production
line.

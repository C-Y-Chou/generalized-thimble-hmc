# Local TLTM Repo Divergence - 2026-05-11

Updated: 2026-05-11 JST

Scope: protect the local legacy checkout at `/Users/ccy/Documents/New project/TLTM_repo`.

## Initial State

The local checkout is behind the remote branch and contains an uncommitted local change:

- Local path: `/Users/ccy/Documents/New project/TLTM_repo`
- Branch: `codex/preprod-hardening`
- Local HEAD: `b3676ff`
- Upstream HEAD observed locally: `70b9dea`
- Uncommitted file: `src/sampler/quasi_newton_solver.f90`

The local diff matched the canonical QN hardening change already present in commit:

- `166aa96 harden QN invalid evaluation handling`

## Resolution

Resolved on 2026-05-11 JST:

- The local QN residue was preserved with `git stash`.
- Stash label: `stash@{0}: On codex/preprod-hardening: preserve local QN residue before 2026-05-11 sync`
- The local checkout was fast-forwarded to `70b9dea`.
- Post-resolution status: clean worktree, branch `codex/preprod-hardening`, upstream `origin/codex/preprod-hardening`.
- Follow-up rename: the branch was renamed to `codex/control-plane` on 2026-05-11, and the checkout was later fast-forwarded with the control-plane registries.

The stash should be treated as historical safety evidence, not an unmerged required change, unless a future audit finds a discrepancy.

## Safety Rule

Do not run `git pull`, `git checkout`, `git reset`, `git clean`, or any overwrite operation in local TLTM checkouts until local worktree state has been refreshed.

Required preflight:

```bash
bash codex/tasks/refresh_local_state.sh
bash codex/tasks/render_l0_boot.sh
```

If a local worktree is dirty or locally ahead, preserve/stash/commit or get explicit discard approval before sync.

## Workflow Fix

This incident created the local worktree registry:

- `codex/state/LOCAL_TARGETS.tsv`
- `codex/state/LOCAL_WORKTREES.tsv`
- `codex/tasks/refresh_local_state.py`
- `codex/tasks/refresh_local_state.sh`

Local worktrees are now part of the same safety model as remote PBS worktrees.

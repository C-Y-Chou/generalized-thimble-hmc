# Codex Read Policy

Updated: 2026-05-11 JST

## Default Read Set

New conversations should read only:

- `context/HANDOFF_MIN.txt`
- `context/L0_BOOT.md`
- `indexes/L1_INDEX.tsv`
- the chosen workspace `context/TASK.md`
- the chosen workspace `context/STATE_BRIEF.md` when present

## Canonical Entry Rule

If a conversation starts in `/Users/ccy/Documents/New project`, first route to
`/Users/ccy/Documents/TLTM_qn_error_handling`. The nested
`/Users/ccy/Documents/New project/TLTM_repo` checkout is legacy unless the user
explicitly asks for legacy/control-plane work.

Workflow scripts must not hardcode `/home/cychou/TLTM` as the working root.
They should derive the repo root from their own script location and run
`codex/tasks/assert_canonical_route.sh` when they can change state, refresh
state, or guide a new conversation.

## Triggered Deep Reads

Read long runbooks only when triggered by L1:

- PBS, queue choice, job repair, or dataset scheduling: read the cluster02 scheduling agent and remote registries.
- Code edits: read behavior-preservation and baseline verification docs for the affected area.
- Algorithm changes: read the relevant algorithm-to-implementation map and paper reference notes.
- Output cleanup: read dataset/job/worktree registries before touching files.
- Historical explanation: read the archived long runbook named by L1.

## Remote Rule

Remote state is not trusted unless freshly refreshed.

Before `ssh`, `qsub`, `qdel`, remote `git pull`, remote cleanup, or production output cleanup:

```bash
bash codex/tasks/refresh_remote_state.sh
bash codex/tasks/render_l0_boot.sh
```

If a remote worktree has active pinned jobs, do not fast-forward or clean that worktree.

## Local Worktree Rule

Local worktrees are also first-class state. Before local `git pull`, branch switch, cleanup, or any operation that may overwrite files in a TLTM checkout:

```bash
bash codex/tasks/refresh_local_state.sh
bash codex/tasks/render_l0_boot.sh
```

If a local worktree is dirty or locally ahead, do not pull or overwrite it until the change is preserved, stashed, committed, or explicitly discarded.

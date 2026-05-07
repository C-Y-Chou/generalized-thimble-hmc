# TLTM Git Workflow

## Repository identity
- Working tree: `/home/cychou/TLTM`
- Main branch: `main`
- Bare origin: `/home/cychou/git/TLTM.git`

## Daily workflow
1. Sync and inspect:
   - `git status -sb`
   - `git log --oneline -n 10`
2. Create feature branch:
   - `git checkout -b exp/<topic>`
3. Commit before validation or submission:
   - include code/config/PBS edits in logical commits.
   - do not leave production-relevant edits only in the working tree.
4. Push before validation or submission:
   - `git push -u origin exp/<topic>`
   - if the branch already tracks origin, use `git push`.
5. Record manifest:
   - commit SHA, queue, walltime, env vars, output root.
6. Merge to main after validation.

## Production gate
Production jobs may be submitted only when all of these are true:
- `git status -sb` is clean except intentionally ignored output/log files.
- `git rev-parse --abbrev-ref HEAD` is not an unnamed detached state.
- `git rev-parse HEAD` equals the commit recorded in the task run manifest.
- The current branch has been pushed to `origin`.
- The task workspace records the pushed branch and commit SHA.

Use:
```bash
git status -sb
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
git ls-remote origin "$(git rev-parse --abbrev-ref HEAD)"
```

## Mandatory reproducibility fields per run
- `git rev-parse HEAD`
- PBS script path and queue
- Key env vars (`QN_*`, `TLTM_STAGE2_*`, `TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE`)
- output/tests path and output/logs path

## Guardrails
- Never run production jobs from an uncommitted dirty tree.
- Never run production jobs from an unpushed branch.
- Never overwrite existing historical result directories; use a new run label.
- Keep `output/` out of git.

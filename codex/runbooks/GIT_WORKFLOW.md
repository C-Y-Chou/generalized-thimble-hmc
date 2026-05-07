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
3. Commit before submission:
   - include code/config/PBS edits in one logical commit.
4. Record manifest:
   - commit SHA, queue, walltime, env vars, output root.
5. Push branch:
   - `git push -u origin exp/<topic>`
6. Merge to main after validation.

## Mandatory reproducibility fields per run
- `git rev-parse HEAD`
- PBS script path and queue
- Key env vars (`QN_*`, `TLTM_STAGE2_*`, `TLTM_STAGE2_CONSTRAINT_TOL_OVERRIDE`)
- output/tests path and output/logs path

## Guardrails
- Never run production jobs from an uncommitted dirty tree.
- Never overwrite existing historical result directories; use a new run label.
- Keep `output/` out of git.

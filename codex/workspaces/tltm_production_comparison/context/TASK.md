# Task: tltm_production_comparison

- Task type: ops
- Status: active
- Owner: codex
- Root: /home/cychou/TLTM/codex/workspaces/tltm_production_comparison
- Legacy alias: stage3_4
- Goal: manage provisional TLTM `nofb` vs `withfb` production-comparison runs for collaborator discussion and workflow rehearsal; final publication datasets are regenerated after Fortran modernization converges.
- Current comparison point: `t=0.35,L=2,nstep=20`
- Canonical method roles: `nofb` and `withfb`
- Legacy raw method mapping: `nofb == no_fb`, `withfb == fb_norefine` for the current p28 fallback-enabled no-post-refine route.
- Write scope: this workspace state plus approved scheduler actions for production-comparison jobs.
- Boundary: do not change Fortran source in this workspace unless explicitly entering a production-comparison code-fix task; code refinement belongs to `fortran_modernization`.

# Task: tltm_production_comparison

- Task type: ops
- Status: active for production-facing provenance; no active F20F 1D jobs
- Owner: codex
- Root: /Users/ccy/Documents/TLTM_fortran_modernization/codex/workspaces/tltm_production_comparison
- Legacy alias: stage3_4
- Goal: manage TLTM `nofb` vs `withfb` production-comparison provenance and any explicitly reopened production redo handoff.
- Current F20F 1D status: closed as no-rerun production-facing evidence.
- Current comparison point: historical production comparison used `t=0.35,L=2,nstep=20`; current F20F 1D evidence is documented separately.
- Canonical method roles: `nofb` and `withfb`
- Legacy raw method mapping: `nofb == no_fb`, `withfb == fb_norefine` for the current p28 fallback-enabled no-post-refine route.
- Write scope: this workspace state plus explicitly approved scheduler actions for production-comparison jobs.
- Boundary: modernization supplies the official-DFO-LS code commit, but production-comparison jobs execute from `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison` after sync. Do not run production-comparison jobs from the modernization worktree.
- Boundary resolution: `PCB-001` is resolved as of 2026-05-12 JST. The diagnostic source was moved out of modernization `src/` to `codex/workspaces/tltm_production_comparison/diagnostics/probe_hmc_volume.f90`. Do not re-add production diagnostics to modernization source/build roots without a separate reviewed task.

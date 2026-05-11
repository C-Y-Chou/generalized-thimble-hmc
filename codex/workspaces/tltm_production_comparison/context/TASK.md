# Task: tltm_production_comparison

- Task type: ops
- Status: active
- Owner: codex
- Root: /Users/ccy/Documents/TLTM_qn_error_handling/codex/workspaces/tltm_production_comparison
- Legacy alias: stage3_4
- Goal: manage TLTM `nofb` vs `withfb` production-comparison workflow and the official-DFO-LS production redo handoff.
- Current comparison point: `t=0.35,L=2,nstep=20`
- Canonical method roles: `nofb` and `withfb`
- Legacy raw method mapping: `nofb == no_fb`, `withfb == fb_norefine` for the current p28 fallback-enabled no-post-refine route.
- Write scope: this workspace state plus approved scheduler actions for production-comparison jobs.
- Boundary: current redo execution uses the official-DFO-LS `fortran_modernization` code line. Do not switch to legacy/control-plane branches unless explicitly requested.

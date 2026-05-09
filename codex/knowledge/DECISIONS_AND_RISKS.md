# Decisions and Risks

Updated: 2026-05-10 JST

## Confirmed decisions
- Keep codex workspace isolated at `TLTM/codex`.
- Maintain live state in `codex/state/*` and per-task state in `codex/workspaces/<task>/state/*`.
- Keep only selected stage3_4 campaigns in output/tests/stage3_4.
- Unified RG gate semantics required before Metropolis.

## Key technical decision
- Reverse gate must not depend on whether fallback was triggered.
- Rationale: experiment intent requires comparable RG enforcement for nofb/withfb accepted proposals.
- Production solver/fallback counters must describe only the forward proposal path, not internal RG diagnostic replay.
- Reverse gate must check the full carried local state used downstream: `x`, `z`, `jac`, and momentum.
- Stage3 production configs currently require `warmup_cycles_optional = 0`; nonzero warmup must be implemented explicitly before use.
- Each Stage3 seed/method output should include `run_manifest.json` so env-driven algorithm settings are reproducible outside chat context.

## Pre-production hardening on 2026-05-07
- Added stats suppression around reverse-gate internal replay to prevent counter contamination.
- Replaced Metropolis `h_final == 0` failure sentinel with explicit `proposal_ok` plus NaN/Inf guards.
- Added RG `jac` consistency check.
- Added Stage3 multiseed warmup fail-fast guard.
- Added Stage3 per-seed/method run manifests.
- Historical: added merged CSV post-refine columns so downstream analysis could read the same fields shown in reports. Post-refine output columns were later removed with the post-refine source path.

## Modernization decisions on 2026-05-09
- Canonical p28 production route is Newton -> p28 QN BTN/backflow rescue -> reverse gate -> Metropolis, without post-refine.
- DFO-GN paper, Broyden/line-search, global continuation/restart/sweep, and post-refine source paths were removed from active source.
- Flow policy is ODEX primary plus solver-internal residual assist for NT/QN residual evaluation, with strict final proposal flow. Radau/JFNK secondary-integrator rescue source was removed.
- The legacy RATTLE state-progress sentinel is diagnostic only; proposal validity is carried by solver convergence, constraint residual handling, strict final flow, reverse gate, finite Hamiltonians, and Metropolis/status gates.
- Preferred QN watchdog terminology is solver assist. `QN_SOLVER_ASSIST_BUDGET` is the preferred env name; `QUASI_FINAL_RESORT_BUDGET` remains a compatibility alias.
- Runtime config now requires key-value `parameters.dat`; legacy positional parsing and the unused `initial_x.dat` runtime path were intentionally deleted.
- Runtime env parser/token mechanics are centralized in `runtime_env_mod`; caller defaults, env names, and valid/invalid override semantics are preserved.
- Active `param_mod` consumers use explicit `only:` imports; the legacy globals still exist, but accidental module-wide coupling is reduced.
- Active `utils` consumers use explicit `only:` imports; shared helper visibility is now explicit at call sites.

## Operational risks
1. Queue congestion can dominate wall-clock completion.
2. Large array jobs in a single queue may starve; split strategy is mandatory.
3. Fragmented-resource periods can favor 16-core repack jobs over 32-core jobs.
4. Merge dependency can become stale when job IDs are replaced; must refresh dependency target.

## Queue heuristics (observed 2026-05-01 for stage3_3 50k heavy jobs)
- Heavy profile: `select=1:ncpus=20:mpiprocs=20:mem=90gb`.
- Immediate starts observed on `C17` and `G`; `C17-LONG`/`G-LONG` and some C-queues can queue during congestion.
- For 1024-seed 50k rerun, effective split was `C17(12 chunks) + G(4 chunks)` with `64 seeds/chunk`.
- This produced 14 running chunks immediately and only 2 queued tails.

## Mitigations in use
- Multi-queue split based on live probe results (not static queue assumptions).
- Repack strategy for queued ranges when starvation persists.
- Explicit merge hold job with current dependency IDs.
- Session and tracker updates in codex state after every submit/repack action.

# Decisions and Risks

Updated: 2026-05-01 JST

## Confirmed decisions
- Keep codex workspace isolated at `TLTM/codex`.
- Maintain live state in `codex/state/*` and per-task state in `codex/workspaces/<task>/state/*`.
- Keep only selected stage3_4 campaigns in output/tests/stage3_4.
- Unified RG gate semantics required before Metropolis.

## Key technical decision
- Reverse gate must not depend on whether fallback was triggered.
- Rationale: experiment intent requires comparable RG enforcement for nofb/withfb accepted proposals.

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

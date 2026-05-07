# Stage3_4 Task Status

Updated: 2026-05-02 10:58:50 JST

## Active objective
- Fix Stage3_4 p28+RG degradation versus nofb by enabling post-Newton refine on fallback accepts.

## Live jobs (current)
- 13622[] on C12: main array chunk_00..23
- 13623[] on C17: tail array chunk_24..31
- 13624 on C8: merge hold afterok on both arrays

## Protocol
- Method: fb only (for direct comparison against existing nofb reference)
- Policy id: reverse_gate_p28_unifiedrg_refine
- Key refinement: QN_POST_NEWTON_REFINE_ENABLED=1, QN_POST_NEWTON_REFINE_MAX_ITER=20

## Next actions
1. Wait first completed chunks and compare seed-level Zmean trend against nofb baseline.
2. If trend improves, keep full 1024 run; else tighten refine/RG settings and restart remaining chunks.

# Stage3_4 Experiment Map

Updated: 2026-04-30 JST

## Kept 1024-seed groups (authoritative)
1. `probe_only_1024seed_200k_t035/no_fb_ref`
2. `probe_only_1024seed_200k_t035/probe_only_p28`
3. `reverse_gate_p28_1024seed_200k_t035/reverse_gate_p28`
4. `full_s1_raw_reverse_gate_1024seed_200k_t035/full_s1_raw_reverse_gate`
5. `no_fb_ref_reverse_gate_1024seed_200k_t035/no_fb_ref_reverse_gate` (current run)

## Interpretation
- `no_fb_ref`: reference mode with fallback disabled.
- `probe_only_p28`: bounded probe fallback (p28), rescue/global routes disabled.
- `reverse_gate_p28`: probe-only baseline + reverse gate.
- `full_s1_raw_reverse_gate`: full raw stage-1 rescue policy + reverse gate.
- `no_fb_ref_reverse_gate`: control experiment to measure nofb under unified RG path.

## Current run objective
- Isolate the effect of reverse gate when fallback is disabled.
- Ensure kernel path is unified before Metropolis accept/reject.

## Merge and reporting
- Merge script: `scripts/merge_stage3_multiseed_chunks.py`
- Expected merged rows: 1024
- Final outputs placed under each policy root.

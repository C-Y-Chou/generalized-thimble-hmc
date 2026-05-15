# Split ODEX Sequence And NPT5 Scale-Up - 2026-05-13

## Purpose

Run two independent checks after the NT+QN assist baseline still failed to
recover old assist-on density:

1. ODEX sequence control: restore the legacy ODEX extrapolation sequence
   `2,4,6,12,18,36,...` through `TLTM_ODEX_STEP_SEQUENCE=legacy`, while keeping
   the current certification, RG, and Metropolis paths.
2. QN candidate scale-up: scale `npt5_r0055_m500` from the 10seed/10k local
   refinement to 32seed/50k.

## ODEX Legacy Sequence Control

- Worktree:
  `/lustre1/home/cychou/TLTM_worktrees/tltm_odex_legacy_sequence_control`
- Branch: `codex/odex-legacy-sequence-control`
- Commit: `9fc3b80c9555a3892deb9486b809814292e6d326`
- Config: `docs/production_comparison_official_dfols_20260511_10seed_10k_nofb_withfb.json`
- Label: `odex_legacy_sequence_ntqn_control_20260513_10s10k_v1`
- Jobs:
  - preflight `15142.anode01`, completed `Exit_status=0`
  - control `15143.anode01`, running on `C8`

Decision comparison:
- Primary baseline is current IWORK3 NT+QN assist control
  `qn_assist_legacy_nt_control_20260513_6f98b5b_10s10k_v2`.
- Baseline failures: `3394`; projected 32seed/50k failures: `54304`;
  mean Re/Im: `+0.0830396450/+0.0065988950`.
- ODEX sequence is a plausible culprit only if this control sharply reduces
  failures and improves mean Re/Im under the same assist/solver gate.

## NPT5 Scale-Up

- Worktree:
  `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`
- Branch: `codex/tltm-production-comparison-official-dfols`
- Commit: `6f98b5bfce60678293c163764e1cefe8307736ba`
- Config: `docs/production_comparison_official_dfols_20260511_32seed_50k_nofb_withfb.json`
- Label:
  `qn_assist_npt5_r0055_scale32_20260513_6f98b5b_32seed_50000cyc_t035_L2_nstep20_v3`
- Candidate: `npt=5`, `rhobeg=0.055`, `maxfun=500`,
  `objfun_has_noise=1`
- Assist policy:
  `nt_strict_qn_navassist_cert_strict_rg_metropolis_v1`
- Active jobs:
  - chunks `15149-15152.anode01`
  - merge/readback `15153.anode01`, held `afterok` on chunks

Decision comparison:
- Old assist-on same-scale reference failures: `19579`.
- 10seed/10k projection for `npt5_r0055_m500`: about `24960`.
- The scale-up is positive only if failures and mean Re/Im remain competitive
  at 32seed/50k; RG rejects and P68/P95 remain diagnostic rather than blockers.

## Wrapper Failures To Ignore

- `15137-15140`: first npt5 scale-up wrapper attempt exited before science;
  no stdout was captured. Superseded.
- `15144-15147`: second npt5 wrapper attempt captured a config error:
  unsynced `docs/production_comparison_formalized_assist_bridge_32seed_50k_nofb_withfb.json`.
  Superseded by v3 with the existing production 32seed/50k config.

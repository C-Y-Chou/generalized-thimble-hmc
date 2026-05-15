# Formalized Assist Bridge 32seed/50k Readback - 2026-05-13 JST

## Campaign

- Dataset id: `prodcomp_formalized_assist_bridge_6f98b5b_32seed_50k_20260513`
- Campaign: `formalized_assist_bridge_20260513_6f98b5b_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb`
- Remote root: `output/production_comparison/formalized_assist_bridge/formalized_assist_bridge_20260513_6f98b5b_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb`
- Commit: `6f98b5bfce60678293c163764e1cefe8307736ba`
- Jobs: `15097`-`15106`, all `Exit_status=0`
- Scale: `32 seeds x 50000 cycles` per method

## Policy Check

- Chunk manifest policy env: `INTODE_SOLVER_ASSIST_POLICY=nt_strict_qn_navassist_cert_strict_rg_metropolis_v1`
- Legacy env: `INTODE_SOLVER_ASSIST_ENABLED=unset`
- Per-seed manifest resolved policy:
  - `no_fb`: `off`
  - `fb_norefine`: `qn_navigation`
- Exact-gate contract preserved in manifests: certification residual, final flow, reverse gate, and Metropolis are unassisted.
- `fb_norefine` QN assist counters are nonzero; the policy was exercised.

## Summary Table

| canonical | raw | n | mean Re<O> | mean Im<O> | Zmean Re<O> | Zmean Im<O> | failures | RG rejects | runtime |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| nofb | no_fb | 32 | 0.1285051491 | -0.0004415082 | 8.5306320302 | -0.0465385645 | 267455 | 15112 | 3356.982668 |
| withfb | fb_norefine | 32 | 0.0713344436 | -0.0046860855 | 6.7549242962 | -0.7868762110 | 67159 | 15088 | 5436.790358 |

Direct `withfb - nofb`:

- mean Re shift: `-0.0571707055`
- mean Im shift: `-0.0042445773`
- Zmean Re shift: `-1.7757077340`
- Zmean Im shift: `-0.7403376465`
- unresolved failures: `-200296`
- RG rejects: `-24`
- mean runtime: `+2079.807689` seconds

## Failure References

- Same-scale assist-on/default `fb_norefine` reference: `19579`
- Same-scale assist-off tuned Phase D reference: `33872`
- Formalized bridge `fb_norefine`: `67159`

Relative to references:

- formalized bridge minus assist-on: `+47580`, ratio `3.43x`
- formalized bridge minus assist-off tuned: `+33287`, ratio `1.98x`

## Verdict

This bridge did not reproduce the assist-on/default failure scale.  It behaves much closer to the assist-off stable line on the primary hard criterion, even though `fb_norefine` resolved to `qn_navigation` and QN assist counters are nonzero.

Observable means also do not rescue the result: `withfb` improves relative to `nofb`, but its Re mean is worse than the prior assist-off tuned Phase D reference recorded in state (`0.0434491`), and failures are far above both the assist-on and tuned references.

Operational conclusion: the current formalization is too weak if the target is to recover the useful old assist behavior.  The missing piece is likely not broad DFO-LS parameter tuning; it is a more faithful formalization of the old assist proposal semantics while still certifying/final-gating strictly.

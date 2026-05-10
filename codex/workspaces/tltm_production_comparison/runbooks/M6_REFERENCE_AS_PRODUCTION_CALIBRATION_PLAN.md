# M6 Reference As Production Calibration Plan

Updated: 2026-05-10 JST

Scope: define how accepted `fortran_modernization` M6 reference datasets can be reused by `tltm_production_comparison` as the first production-calibration tier.

## Decision

The accepted M6 reference datasets are not only modernization baselines. They are also valid first-round production calibration evidence for the same physical point:

- `t=0.35,L=2,nstep=20`
- raw methods: `no_fb`, `fb_norefine`
- canonical production roles: `nofb`, `withfb`

This is an alias/use decision, not a raw-data move:

- M6 raw data remains owned by `fortran_modernization`.
- `tltm_production_comparison` may consume M6 readback/aggregate artifacts as calibration input.
- Production-calibration reports derived from M6 should be written under the production-comparison workspace.
- Final publication datasets still need to be regenerated after modernization converges.

## Calibration Ladder

| Tier | M6 package | Production use |
| --- | --- | --- |
| R1 | `m6_r1_4seed_1k` | Smoke/schema sanity only; not enough for statistical conclusions. |
| R2 | `m6_r2_10seed_10k` | Early method-behavior and runtime sanity; rough direction only. |
| R3 | `m6_r3_32seed_50k` | First useful scaling checkpoint for runtime, failure rates, RG rejects, and rough variance. |
| R4 | `m6_r4_128seed_100k` | First production pilot baseline for deciding whether to increase seeds, cycles, or both. |

## Required Production Readback

The first production-calibration report should read M6 R1-R4 and summarize:

- mean Re/Im for `nofb` and `withfb`
- `Z_mean` using the project convention: mean divided by the standard error
- per-tier trend from R1 to R4
- unresolved failure counts
- reverse-gate reject counts
- pair0 acceptance
- mean runtime and estimated cost scaling
- whether R4 looks seed-limited, cycle-limited, or dominated by systematic implementation/route behavior

The report should explicitly preserve the raw/canonical mapping:

```text
raw no_fb       -> canonical nofb
raw fb_norefine -> canonical withfb
```

## Decision Logic For Next Production Scale

Use R4 as the first real pilot, then decide the next production step:

- If R1-R4 trends are stable and R4 uncertainty is too large, increase seed count first.
- If means drift materially with cycles or lower tiers disagree qualitatively with R4, run a longer-cycle pilot before simply adding seeds.
- If `withfb` robustness is good but runtime is high, optimize queue splitting and cost model before scaling.
- If failure or reverse-gate counters dominate interpretation, do not call the next run final; audit route/counter semantics first.
- If naming/schema/counter semantics change in modernization, keep M6 useful as historical calibration but regenerate production data.

## Output Policy

Derived production-calibration outputs should use:

```text
output/production_comparison/calibration/m6_reference_readback
output/logs/production_comparison/calibration/m6_reference_readback
```

Do not copy M6 raw data into production-comparison output roots unless there is a concrete operational reason. Prefer registry aliases and derived reports.

## Next Action

Create a read-only M6 production-calibration readback report before launching new production jobs. That report should answer:

1. What statistical precision does R4 already provide?
2. Is the next production step more likely seed-limited or cycle-limited?
3. What seed/cycle grid should be launched next for collaborator-facing production comparison?

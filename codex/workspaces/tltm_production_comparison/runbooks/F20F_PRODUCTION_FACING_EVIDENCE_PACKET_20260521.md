# F20F Production-Facing Evidence Packet

Date: 2026-05-21 JST

Status: final no-rerun packet.  This promotes existing canonical F20F data into
production-facing evidence.  It does not authorize PBS submission, scheduler
handoff, or new raw-output generation.

## Decision Boundary

The user decision for this packet is no rerun.  The current F20F evidence is
read from the canonical modernization execution tree:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization
```

The old production-comparison execution tree remains historical and must not be
used to create a misleading "new production" dataset for this decision.

## Observable Definitions

- `Ohat` is the current code's virial observable.  For this one-dimensional
  model it is the production-facing `z dS/dz - 1` / pole-free virial identity
  observable with exact target `0 + 0i`.
- `z` is read from existing `eval_multichain/multichain_expectations.dat`
  metadata, with exact target `0 - 1i`.
- `Z` below means mean divided by seed standard error.  For `z_im`, `Z` is
  `(mean_z_im + 1) / SE`.

The structural and numeric readback is frozen in:

```text
codex/workspaces/tltm_production_comparison/state/F20F_FINAL_VALIDATION_20260521.tsv
```

The manuscript-facing interpretation layer is:

```text
codex/workspaces/tltm_production_comparison/runbooks/F20F_1D_MANUSCRIPT_CLAIM_BOUNDARY_20260521.md
```

## Structural Validation

| bucket | component | method | rows | source | aggregate | audit |
| --- | --- | --- | ---: | --- | --- | --- |
| `TLTM_t030` | preset validation | `no_fb` | 32 | root per-seed table | present | 32/32 pass |
| `TLTM_t030` | preset validation | `fb_norefine` | 32 | root per-seed table | present | 32/32 pass |
| `fixed_flow_t030` | base128 | `no_fb` | 128 | root per-seed table | present | 128/128 pass |
| `fixed_flow_t030` | base128 | `fb_norefine` | 128 | 16 chunk per-seed tables | root aggregate absent | 128/128 pass |
| `fixed_flow_t030` | extension384 | `no_fb` | 384 | root per-seed table | present | 384/384 pass |
| `fixed_flow_t030` | extension384 | `fb_norefine` | 384 | root per-seed table | present | 384/384 pass |
| `fixed_flow_t050` | nofb pathology | `no_fb` | 128 | root per-seed table | present | 128/128 pass |
| `TLTM_t050` | base32 | `no_fb` | 32 | root per-seed table | present | 32/32 pass |
| `TLTM_t050` | base32 | `fb_norefine` | 32 | root per-seed table | present | 32/32 pass |
| `TLTM_t050` | topup96 | `no_fb` | 96 | root per-seed table | present | 96/96 pass |
| `TLTM_t050` | topup96 | `fb_norefine` | 96 | root per-seed table | present | 96/96 pass |

The only structural caveat is the known `fixed_flow_t030` base128
`fb_norefine` missing root-level merged table.  The chunk tables are complete
and are the canonical source for that 128-row component.

## Canonical Buckets

| bucket | production-facing role | canonical scale |
| --- | --- | --- |
| `TLTM_t030` | F20F tolerance validation and active double preset anchor | 32 seeds x 50000 cycles, paired |
| `fixed_flow_t030` | negative control: failures do not produce visible support or observable pathology | 512 seeds x 200000 cycles, paired |
| `fixed_flow_t050` | fixed-flow no-fallback pathology threshold | 128 seeds x 200000 cycles, `no_fb` only |
| `TLTM_t050` | TLTM low005 repair and fallback comparison | 128 seeds x 200000 cycles, paired |

## Method Summary

`Ohat` is the virial / `z dS/dz - 1` observable.

| bucket | method | rows | Ohat Re | Z Re | Ohat Im | Z Im | z Re | Z z Re | z Im | Z z Im | unresolved | projection mean | RG rejects | runtime s |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `TLTM_t030` | `no_fb` | 32 | 0.0093236730 | 0.722 | -0.0069709609 | -0.694 | 0.0311159758 | 1.751 | -0.9920031088 | 1.125 | 133379 | 4683.31 | 16487 | 2409.26 |
| `TLTM_t030` | `fb_norefine` | 32 | 0.0117964990 | 0.979 | -0.0004064170 | -0.061 | 0.0357362057 | 2.175 | -0.9941114563 | 0.910 | 26714 | 1243.72 | 13085 | 3595.63 |
| `fixed_flow_t030` | `no_fb` | 512 | -0.0018257699 | -0.640 | -0.0018512135 | -0.935 | -0.0031738713 | -1.076 | -0.9976952956 | 2.153 | 1260068 | 8063.98 | 2868692 | 7768.11 |
| `fixed_flow_t030` | `fb_norefine` | 512 | -0.0017898159 | -0.760 | 0.0003013731 | 0.171 | 0.0014900401 | 0.554 | -0.9979566832 | 2.212 | 0 | 0.00 | 0 | 8902.78 |
| `fixed_flow_t050` | `no_fb` | 128 | -0.2412559808 | -211.902 | -0.0077456212 | -0.371 | 0.0240667404 | 0.354 | 1.1236897890 | 12258.450 | 3149863 | 26205.23 | 204408 | 10166.46 |
| `TLTM_t050` | `no_fb` | 128 | -0.0012320877 | -0.328 | 0.0030541044 | 1.239 | -0.0013117924 | -0.230 | -0.9987173842 | 0.920 | 4094188 | 33979.48 | 255186 | 11612.75 |
| `TLTM_t050` | `fb_norefine` | 128 | 0.0013011465 | 0.514 | -0.0012213477 | -0.643 | 0.0044203777 | 0.827 | -0.9984151817 | 1.881 | 189662 | 4110.51 | 336483 | 23504.27 |

## Paired Differences

The paired difference is `no_fb - fb_norefine`.

| bucket | rows | dOhat Re | Z | dOhat Im | Z | dz Re | Z | dz Im | Z |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `TLTM_t030` | 32 | -0.0024728260 | -0.217 | -0.0065645439 | -1.071 | -0.0046202299 | -0.438 | 0.0021083475 | 0.430 |
| `fixed_flow_t030` | 512 | -0.0000359540 | -0.013 | -0.0021525866 | -1.019 | -0.0046639115 | -1.454 | 0.0002613876 | 0.241 |
| `TLTM_t050` | 128 | -0.0025332342 | -0.772 | 0.0042754521 | 1.933 | -0.0057321701 | -1.537 | -0.0003022024 | -0.261 |

## Sign-Support Evidence

| bucket | method | files | only positive | only negative | both signs | median sign changes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `fixed_flow_t030` | `no_fb` | 512 | 0 | 0 | 512 | 32821.0 |
| `fixed_flow_t030` | `fb_norefine` | 512 | 0 | 0 | 512 | 38341.5 |
| `fixed_flow_t050` | `no_fb` | 128 | 66 | 62 | 0 | 0.0 |

For `fixed_flow_t050`, sector conditioning already showed both sign sectors
give `Ohat_re ~= -0.241`, so equalizing positive/negative seed counts would
cancel the odd imaginary sector effect but would not repair the real bias.

## Final Claims

Established by this packet:

- F20F is the only active double-precision tolerance preset.
- Single precision is closed as an active direction.
- Fixed-flow `t=0.5` no-fallback has a real sign-lock and observable pathology:
  `Ohat_re = -0.2412559808`, `Z = -211.902`, and `z_im` is in the wrong sector.
- TLTM `t=0.5` low005 repairs that fixed-flow pathology: both TLTM methods have
  `Ohat` and `z` compatible with the expected values at the current scale.
- `fb_norefine` massively improves solver-health counters in TLTM `t=0.5`
  (`unresolved` 4094188 to 189662), but the paired observable differences stay
  below the robust decision boundary in this one-dimensional toy model.

Not established by this packet:

- that failures alone imply sampling bias;
- that `fb_norefine` is required for unbiased TLTM observables in the 1D toy;
- that the 1D toy model alone can support the strongest BTN fallback motivation.

## Production Conclusion

Use the existing canonical F20F roots as the production-facing 1D evidence.
Do not run a new P0/P1/P2 production-comparison campaign for this decision.
The next scientific step, if the paper needs a stronger fallback claim, is a
new model or higher-dimensional scenario where TLTM requires larger flow time,
not another rerun of these completed 1D F20F datasets.

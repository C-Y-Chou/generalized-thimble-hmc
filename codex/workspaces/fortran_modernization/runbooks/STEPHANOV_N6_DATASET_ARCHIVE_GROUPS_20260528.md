# Stephanov N6 Dataset Archive Groups

Date: 2026-05-28

Scope: archive grouping plan for the current Stephanov `n=6`, `t_high=0.03`
fixed-tau and TLTM data.  This is an archive plan and summary table only.
Actual data movement, compression, copying, hashing, or deletion remains
deferred.  The final criterion analysis is now complete enough to fill compact
registry rows, but raw archive actions are still pending.

Machine-readable group table:

```text
codex/workspaces/fortran_modernization/state/STEPHANOV_N6_DATASET_GROUPS_20260528.tsv
```

Final closure packet:

```text
codex/workspaces/fortran_modernization/runbooks/generated/post_tltm_wv_hmc_ready_20260529/FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md
```

## Archive Timing Policy

Do not archive or move active production data while jobs, continuation segments,
readback dependencies, or final criterion analysis dependencies are still live.

For now:

- keep raw output roots in place;
- do not commit raw history payloads to git;
- do not move remote output directories;
- keep the compact four-group registry filled;
- keep runtime-excluded repair/outlier jobs out of runtime, throughput,
  equal-wall-clock, ESS/hour, and `1/SE^2/hour` claims.

After the final criterion analysis:

- actual output roots and log roots are recorded in
  `state/STEPHANOV_N6_DATASET_GROUPS_20260528.tsv`;
- readback packet paths and final criterion packet paths are recorded;
- raw archive movement/deletion remains a later archive operation, not part of
  this WV-HMC preparation gate.

## Four Data Groups

| group | dataset id | method | flow setup | role | archive status |
|---|---|---|---|---|---|
| fixed tau nofb | `stephanov_n6_fixed_tau_nofb` | `no_fb` | single-replica fixed `t=0.03` | fixed-tau nofb comparison / runtime and mixing baseline | compact registry filled; raw archive decision pending |
| fixed tau withfb | `stephanov_n6_fixed_tau_withfb` | `withfb` | single-replica fixed `t=0.03` | fixed-tau legacy diagnostic comparison | partial legacy diagnostic; raw archive decision pending |
| TLTM nofb | `stephanov_n6_tltm_nofb` | `no_fb` | TLTM ladder with `t_high=0.03` | canonical TLTM production group | canonical raw component pending raw archive decision |
| TLTM withfb | `stephanov_n6_tltm_withfb` | `withfb` | TLTM ladder with `t_high=0.03` | legacy diagnostic TLTM comparison group | legacy archive pending raw archive decision |

## Summary Fields To Fill Later

Each group now has one compact row containing:

- dataset id;
- method;
- flow setup;
- source commit;
- parameter/config file;
- output root;
- log root;
- seeds;
- cycles per seed or segment;
- total samples;
- snapshot availability;
- observable history availability;
- label trace availability;
- timing metadata availability;
- final criterion analysis packet path;
- readback packet path;
- archive action;
- short key result without interpretation overreach.

## Archive Action Vocabulary

Use the same style as the 1D cleanup:

- `canonical_raw`: keep raw data as production evidence.
- `canonical_raw_component`: keep raw data as one component of a combined final
  dataset.
- `compact_only`: keep compact tables and runbooks, but do not preserve raw
  history payloads as production evidence.
- `legacy_archive`: preserve for reproducibility but do not use as current
  production evidence.
- `delete_candidate`: remove only after compact provenance is sufficient and no
  active dependency remains.
- `archive_deferred_until_final_criterion_complete`: current status for all
  four Stephanov groups.

## Boundary Against Interpretation

This archive grouping does not decide whether `withfb` is needed.

The method decision remains governed by the frozen criterion framework:

- lower failure count alone is not evidence for `withfb`;
- `withfb` must repair observable correctness, ratio stability, severe
  high-flow ergodicity risk, or wall-clock-normalized information rate to become
  canonical;
- otherwise `nofb` remains the TLTM default.

## Post-Production Checklist

Status:

1. Confirm no PBS jobs depend on the output roots: done for the closure packet.
2. Freeze the final list of output and log roots for all four groups without
   moving data: done in the state TSV.
3. Run the final frozen-criterion analysis: done.
4. Save the final criterion packet and compact comparison tables: done.
5. Generate compact estimator/readback summaries for each group: done for the
   TLTM observable/z closure packet; fixed-tau groups remain compactly
   registered as comparison/diagnostic groups.
6. Fill `STEPHANOV_N6_DATASET_GROUPS_20260528.tsv`: done.
7. Build one final dataset registry or append these four groups to the chosen
   production-comparison registry: deferred archive/productization work.
8. Only then decide whether any raw remote output should be copied, archived,
   or compacted away: still deferred.

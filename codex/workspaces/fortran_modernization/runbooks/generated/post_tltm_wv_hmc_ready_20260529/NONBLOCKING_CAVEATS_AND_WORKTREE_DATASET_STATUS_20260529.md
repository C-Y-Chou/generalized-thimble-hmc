# Nonblocking Caveats And Worktree Dataset Status

Date: 2026-05-29

Scope: final pre-WV-HMC cleanup status for the modernization worktree after the
Stephanov `n=6`, `t_high=0.03` TLTM closure.  This document separates blockers
from deferred cleanup so the next work item can start with WV-HMC.

## Blocking Status

No known blocking caveat or blocking hygiene issue remains before adding
WV-HMC as a sibling sampler.

This means:

- TLTM `nofb` is the canonical production path for this phase.
- `withfb` is default-off legacy diagnostic mode.
- stale `wv` runtime flag semantics have been removed from canonical source.
- stale docs no longer claim WV-HMC is already implemented.
- current local guardrails pass with the official DFO-LS package import path.
- WV-HMC must not reuse the old `wv` flag or be hidden as a TLTM model choice.

## Nonblocking Deferred Items

| item | status | why nonblocking before WV-HMC |
| --- | --- | --- |
| Raw output archive movement/deletion | deferred | The four dataset groups and output roots are registered; no raw data movement is required to start WV-HMC. |
| Raw Stage entry-point deprecation | deferred | Current Stage1/Stage2 SOP and guardrails are stable; deprecation can wait until compatibility policy closes. |
| Broader `param_mod` global mirror migration | deferred | The blocking stale `wv` flag is removed; remaining mirrors are compatibility debt and should not be mixed with WV-HMC implementation. |
| Legacy packed flow-time helper cleanup | deferred | Flow time is documented as metadata and current TLTM behavior is guarded; helper removal is a later compatibility refactor. |
| Structured diagnostics schema migration | deferred | Existing summaries are still needed for readback compatibility; schema cleanup can be done after WV-HMC boundaries are explicit. |
| RNG/state/cache ownership refactors | deferred | Current RNG anchors and guardrails pass; larger state migration would be a behavior-risking refactor. |
| Public product-doc consolidation | deferred | Stale claims are corrected; full public docs can be consolidated after TLTM/WV-HMC architecture is real. |
| Historical scripts/PBS/archive pruning | deferred | Script evidence audit quarantines the current surface; deletion can wait for archive policy. |
| Equal-wall-clock ESS/hour claim | unavailable/nonblocking | Runtime exclusion manifest blocks a clean all-available claim; this is not needed for the nofb canonical decision or WV-HMC start. |

## Dataset Groups

| group | status | role | canonicality |
| --- | --- | --- | --- |
| `fixed_tau_nofb` | complete | fixed-tau comparison group | noncanonical control |
| `fixed_tau_withfb` | partial legacy diagnostic | legacy diagnostic comparison group | noncanonical |
| `TLTM_nofb` | complete | canonical production group | canonical TLTM evidence |
| `TLTM_withfb` | complete | legacy diagnostic comparison group | noncanonical diagnostic |

Authoritative dataset registry files:

- `runbooks/generated/post_tltm_wv_hmc_ready_20260529/dataset_archive_groups_final.tsv`
- `state/STEPHANOV_N6_DATASET_GROUPS_20260528.tsv`

Authoritative final observable/readback packet:

- `runbooks/generated/stephanov_n6_final_observable_z_20260529_complete/`

Authoritative criterion closure packet:

- `runbooks/generated/post_tltm_wv_hmc_ready_20260529/`

## Local Workbook Cleanup

The local generated workbook should retain only the final closure/readback
packets that are needed for handoff:

- `generated/withfb_criterion_framework_20260527/`
- `generated/stephanov_n6_final_observable_z_20260529_complete/`
- `generated/stephanov_n6_final_runtime_exclusions_20260529/`
- `generated/post_tltm_wv_hmc_ready_20260529/`

Superseded intermediate generated folders from the readback exploration were
removed from the local workbook after final packets were created.  Their
decisions are represented by the final criterion closure and final observable
packet listed above.

## WV-HMC Start Contract

Start WV-HMC from:

- `runbooks/WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`
- the existing model-provider/action/observable boundary;
- a new sibling sampler namespace, not a hidden TLTM mode;
- a new explicit WV-HMC config key, not the deleted legacy `wv` key.

Do not change TLTM canonical behavior while adding the first WV-HMC scaffold.

# Post-TLTM Pre-Production Completion

Date: 2026-05-28

Purpose: record the work that can be completed before current TLTM production
finishes.  This avoids waiting idly while also avoiding changes that could
invalidate active results.

## Completed Now

| Item | Artifact | Status |
| --- | --- | --- |
| Explicit post-TLTM workflow | `MODERNIZATION_POST_TLTM_WORKFLOW_20260528.md` | complete |
| Earlier handoff TODO crosswalk | `MODERNIZATION_POST_TLTM_WORKFLOW_20260528.md` | complete |
| Canonical TLTM SOP anchor | `TLTM_CANONICAL_SOP_20260528.md` | complete |
| Frozen interim withfb criterion framework | `runbooks/generated/withfb_criterion_framework_20260527/interim_criterion_framework_v1.md` | complete |
| Dataset archive grouping template | `STEPHANOV_N6_DATASET_ARCHIVE_GROUPS_20260528.md` and `state/STEPHANOV_N6_DATASET_GROUPS_20260528.tsv` | complete; raw archive move/delete deferred |
| WV-HMC simplified algorithm readback | `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md` | complete |
| WV legacy residue audit | `WV_LEGACY_RESIDUE_AUDIT_20260528.md` | complete |
| Artifact inventory | `POST_TLTM_ARTIFACT_INVENTORY_20260528.md` | complete |
| Source boundary audit | `POST_TLTM_SOURCE_BOUNDARY_AUDIT_20260528.md` | complete |
| Guardrail checklist | `POST_TLTM_GUARDRAIL_CHECKLIST_20260528.md` | complete |
| Product documentation consolidation design | `PRODUCT_DOCS_CONSOLIDATION_DESIGN_20260528.md` | complete |
| Stale WV documentation correction | `docs/readme.md` | complete |
| Planning index update | `PLANNING_INDEX.md` | complete |
| Script evidence audit catch-up for tracked Stephanov n6 scripts/PBS files | `state/SCRIPT_EVIDENCE_AUDIT_20260512.tsv` | complete |

## Verification Run Now

```text
git diff --check
rg -n "WV-HMC Fortran Project|implements a worldvolume-HMC workflow" docs/readme.md scripts/README.md docs/module_architecture.md docs/file_layout.md
make -C build script_evidence_audit_gate
```

Observed status:

- `git diff --check`: pass;
- stale WV overview claim search: pass, no current overview hits;
- `script_evidence_audit_gate`: pass in M4 with all tracked task evidence
  accounted for.

Final pre-WV source guardrails, 2026-05-29:

- `make -C build modernization_guardrails`: pass;
- `make -C build test_official_dfols_preset_contract test_retained_core_qn_route_contract test1 test2`: pass;
- `make -C build test_mt95_state_contract test_tltm_rng_contract test_tltm_swap_kernel_contract`: pass.

## Completed By Constraint

Source hygiene changes made after production closure were behavior-preserving and
guardrailed:

- stale `wv` config residue removed from canonical parser/state;
- high-dimensional guardrail fixtures were moved from old large-flow smoke
  assumptions to near-zero smoke tests;
- QN route tracing was made dimension-neutral;
- no RNG stream changed;
- no snapshot or observable-history schema changed;
- no production default changed;
- no active output moved or archived;
- final `nofb`/`withfb` conclusion recorded from frozen gates only.

## Ready To Execute After Production Finishes

Status, 2026-05-29: items 1-5 are complete for opening the WV-HMC gate.  Raw
archive movement/deletion and deeper source refactors remain deferred.

1. Run final frozen-criterion analysis using completed nofb and withfb outputs.
   Completed:
   `runbooks/generated/post_tltm_wv_hmc_ready_20260529/FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md`.
2. Fill the four dataset archive groups.  Completed:
   - fixed tau nofb;
   - fixed tau withfb;
   - TLTM nofb;
   - TLTM withfb.
3. Decide canonical/legacy method boundary from frozen gates only.  Completed:
   `nofb` canonical, `withfb` legacy/default-off.
4. Archive or register compact result packets.  Compact registry complete; raw
   archive action deferred.
5. Start source hygiene slices in this order:
   - stale `wv` config residue: completed;
   - docs/index cleanup pass: completed for the pre-WV gate;
   - withfb legacy/default-off boundary if final gates permit: completed in
     docs/runbooks;
   - raw Stage wrapper/deprecation plan;
   - typed result/status compatibility surface;
   - structured diagnostics accounting;
   - RNG/state/cache migrations only with accepted baseline.
6. Re-run source guardrails after each source slice.
7. Open WV-HMC implementation gate only after TLTM guardrails remain unchanged.

## Still Blocked

- raw archive movement/deletion;
- raw Stage deprecation;
- RNG, `save` workspace, cache, and diagnostics migrations;
- WV-HMC implementation.

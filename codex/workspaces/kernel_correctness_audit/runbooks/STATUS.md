# Kernel Correctness Audit Status

Updated: 2026-05-07 JST

## Current status
- Active diagnostic workspace.
- First probe completed: `PASS` for deterministic/single-valued repeatability.
- Probe 2a completed: captured failure-case replay returned `FAIL`, but it is not a valid conclusion about successful-proposal reversibility because the input rows are solver-failure/difficult captures rather than accepted proposal states.
- Probe 2b completed: `PASS` for successful-proposal reversibility through the main HMC `REVCHK` hook.
- Probe 2c completed: `PASS` for RG-reject identity handling in the full Stage2/Metropolis path.
- Probe 3 completed: `PASS` for local metric-corrected volume preservation on sampled branch-stable successful proposal points.
- Probe 4a completed: `PASS` for fallback-only successful-proposal reversibility coverage.
- Probe 4b completed: `FAIL` for QN-enriched local volume at eps `3e-5`, `1e-5`, `3e-6`.
- Probe 4c completed: smaller-eps ladder shows QN-enriched metric error converges below tolerance at `eps=1e-7`.
- Current interpretation: Probe 4b's local-volume failure is likely finite-difference/high-curvature, not a demonstrated local-volume defect.
- Probe 5a completed: weak branch stability clean, NT strong-stable, QN aggregate route counters show small perturbation sensitivity.
- Probe 5a2 completed: QN strong-instability is solely post-refine skip/attempt/success counter sensitivity.
- Probe 5b0 completed: post-refine skip-vs-attempt routes are proposal-equivalent in the diagnostic sample.
- Current audit conclusion: no kernel-correctness blocker identified so far.
- Next active action: decide whether to run optional forward/reverse route signature census or proceed back to production benchmark planning.

## Pre-production hardening follow-up
- 2026-05-07: added reverse-gate replay stats suppression, so internal reverse replay no longer contaminates production solver/failure/post-refine counters.
- 2026-05-07: added `jac` to the RG accept check.
- 2026-05-07: replaced Metropolis `h_final == 0` sentinel with explicit `proposal_ok` and finite-Hamiltonian guards.
- 2026-05-07: local Stage2 smoke with RG on completed after these changes: `nstep=20`, `constraint_stats total=20`, `reverse_gate_route_candidates total=20`.
- 2026-05-07: remote Intel-module Stage2 smoke with RG on also completed after sync: `nstep=20`, `constraint_stats total=20`, `reverse_gate_route_candidates total=20`.
- 2026-05-07: these are production-hardening fixes, not new proof probes; rerun optional route-signature census if we want one final audit table before 1024-seed production.

## First probe definition
- Full-run repeatability:
  - same seed: `20260421`
  - same short Stage3_4 smoke config: `docs/stage_3_4_t035_smoke_post_newton_refine_500.json`
  - method: `fb`
  - RG enabled
  - `cttol=1e-13`
  - QN p28 setting via `QN_S1_PROBE_MAX_ITER=28`
  - QN tol `1e-13`
  - post-refine enabled through method `fb`
- Captured-case replay repeatability:
  - source capture: `output/tests/stage3_4/post_refine_fail_replay_capture/withfb_p28_refine_rg_ct1e13_qn1e13_10seed_10k/fb/seed_20260421/output`
  - same replay binary, same env, same input files, two independent output CSVs.

## Interpretation boundary
- PASS means no non-determinism was detected in this small full-run/replay probe.
- PASS does not prove phase-space volume preservation.
- PASS does not prove proposal-density symmetry.
- FAIL means inspect the first differing artifact before moving to volume/reversibility audits.

## Latest artifacts
- `output/tests/kernel_correctness_audit/single_valued_probe_20260507/single_valued_probe_report.md`
- `output/tests/kernel_correctness_audit/reversibility_probe_20260507/reversibility_probe_report.md`
- `output/tests/kernel_correctness_audit/successful_reversibility_probe_20260507/successful_reversibility_probe_report.md`
- `output/tests/kernel_correctness_audit/rg_reject_identity_probe_20260507/rg_reject_identity_probe_report.md`
- `output/tests/kernel_correctness_audit/volume_probe_20260507/volume_probe_report.md`
- `output/tests/kernel_correctness_audit/fallback_only_reversibility_probe_20260507/fallback_only_reversibility_probe_report.md`
- `output/tests/kernel_correctness_audit/qn_enriched_volume_probe_20260507/qn_enriched_volume_probe_report.md`
- `output/tests/kernel_correctness_audit/qn_volume_eps_ladder_20260507/qn_volume_eps_ladder_report.md`
- `output/tests/kernel_correctness_audit/branch_stability_probe_20260507/branch_stability_probe_report.md`
- `output/tests/kernel_correctness_audit/branch_stability_detail_probe_20260507/branch_stability_detail_probe_report.md`
- `output/tests/kernel_correctness_audit/post_refine_skip_equivalence_probe_20260507/post_refine_skip_equivalence_probe_report.md`
- `codex/workspaces/kernel_correctness_audit/runbooks/PROBE5_BRANCH_SYMMETRY_DESIGN.md`

## Next probe
- Optional Probe 5b: forward/reverse route signature census.
- Design doc: `codex/workspaces/kernel_correctness_audit/runbooks/PROBE5_BRANCH_SYMMETRY_DESIGN.md`.
- Goal:
  - document route signatures of accepted forward proposals and explicit reverse replays.
  - this is now optional because reversibility, RG identity, local volume, weak branch stability, and post-refine route equivalence have all passed the targeted probes.
  - use it if we want a final audit table before restarting production runs.

## Caveat
- PBS job `14115.anode01` finished with `Exit_status=1`, but all planned scientific outputs were present.
- The PASS report was generated afterward by file-only post-processing of those outputs.
- Probe 2a used failure captures and is not a valid accepted-proposal reversibility conclusion.
- Probe 2c uses an env-gated diagnostic added to Stage2: `TLTM_RG_REJECT_AUDIT_FILE`.
- Probe 3 labels in the existing report use `1e5`, `3e5`, `3e6` to mean eps `1e-5`, `3e-5`, `3e-6`; the PBS label formatting has been fixed for future reruns.

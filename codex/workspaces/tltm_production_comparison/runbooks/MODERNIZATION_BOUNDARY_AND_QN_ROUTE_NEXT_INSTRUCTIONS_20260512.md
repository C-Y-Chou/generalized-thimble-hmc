# Modernization Boundary and QN Route Next Instructions

Date: 2026-05-12 JST
Audience: production-comparison Codex working in the shared TLTM tree

## Boundary

`PCB-001` was resolved on 2026-05-12 JST. The diagnostic source was moved out of
the modernization `src/` tree to:

- `codex/workspaces/tltm_production_comparison/diagnostics/probe_hmc_volume.f90`

Do not re-add this or any other production diagnostic source to modernization
source/build roots without a separate reviewed modernization task.

You are currently investigating `withfb` / QN route bias in the
production-comparison line. This is separate from the modernization ODEX/F14
workstream.

Do not add, commit, or leave production-diagnostic source in modernization
source roots as if it were part of the modernization package. In particular,
`src/apps/probe_hmc_volume.f90` was identified by the user as an adjacent
production Codex artifact. It must not be committed into the modernization
branch or wired into `build/makefile` as a normal modernization executable.

If you still need that diagnostic app, keep it in a production-comparison-only
boundary after the current run completes: a dedicated production-comparison
diagnostic branch/worktree, or a clearly named task/diagnostic area under
`codex/workspaces/tltm_production_comparison/`. Do not modify the canonical
modernization build graph for that purpose.

Cleanup readback:

1. `src/apps/probe_hmc_volume.f90` no longer exists in the modernization source tree.
2. The diagnostic copy is preserved under the production-comparison diagnostics path above.
3. `build/makefile` has no `probe_hmc_volume` target or source-list entry.
4. `PCB-001` and `PCV-001` are marked resolved.

## Current Observed Work

At 2026-05-12 JST, a local job was observed and then completed:

- `scripts/run_stage3_3_multiseed.py --config docs/qn_route_bias_audit_10seed_2k.json --max-seeds 1 --methods fb_norefine ... --output-subdir output/tests/qn_route_bias_exact_event_capture_1seed_2k`
- Child process: `bin/run_tltm_stage2`

Its output is available under
`output/tests/qn_route_bias_exact_event_capture_1seed_2k/`.

Important: despite the label, this run appears to contain only local transition
audit/history/summary outputs. I did not see accepted-QN event-state files that
are sufficient for exact volume or route-signature replay. Treat this as a
single-seed audit replay, not as completed exact-event evidence.

## Evidence Already Present

The 10seed x 2k internal-p28 route audit has completed locally:

- `output/tests/qn_route_bias_audit_10seed_2k/qn_route_bias_2k_report.md`
- `output/tests/qn_route_bias_audit_10seed_2k/per_seed_summary_table.csv`
- `output/tests/qn_route_bias_audit_10seed_2k/audit/*/seed_*/local_transition_audit.csv`

Aggregate route-conditioned event readback from those audit files:

- `fb_norefine`, hot slot, accepted Newton-only:
  - `n=18321`, mean `delta_h=+1.729251001345983e-4`, negative count `9190/18321`.
- `fb_norefine`, hot slot, accepted QN:
  - `n=626`, mean `delta_h=-2.4017814090184074e-2`, negative count `389/626`.
- `fb_norefine`, hot slot, QN Metropolis rejects:
  - `n=157`, mean finite `delta_h=+11.954052702752692`, negative count `0/157`.
- `no_fb`, hot slot, accepted Newton-only:
  - `n=17981`, mean `delta_h=+3.7117924548002717e-4`, negative count `8983/17981`.

Per-seed correlations in this 10seed x 2k audit are suggestive but not proof:

- accepted-QN count vs `Ohat_Re`: `corr=+0.5478`
- accepted-QN count vs `Ohat_Im`: `corr=+0.7870`
- accepted-QN mean `delta_h` vs `Ohat_Re`: `corr=-0.0677`
- accepted-QN mean `delta_h` vs `Ohat_Im`: `corr=-0.3365`
- unresolved failures vs `Ohat_Re`: `corr=+0.6088`
- RG rejects vs `Ohat_Re`: `corr=+0.5774`

The current volume scan files under
`output/tests/qn_route_bias_volume_current/` mostly show near-zero
`metric_logvol` on generic stable points:

- `volume_branch_scan_eps3e-7.csv`: `n=120`, `qn=11`, one unstable signature,
  max absolute `metric_logvol=1.1576e-5`.
- `volume_eps3e-7.csv`: `n=20`, all QN, max absolute
  `metric_logvol=1.9476e-4`.
- `volume_eps1e-6.csv`: `n=20`, all QN, max absolute
  `metric_logvol=2.2125e-3`.
- `volume_eps3e-6.csv`: `n=20`, all QN, max absolute
  `metric_logvol=1.9698e-2`.

This means the generic local volume probe has not yet explained the negative
accepted-QN `delta_h` signal. The next useful target is exact accepted-QN
events, not more generic sampled points.

## Required Next Steps

1. Write a short readback of the completed
   `output/tests/qn_route_bias_exact_event_capture_1seed_2k` run and explicitly
   state that it did not produce replayable accepted-QN event-state files, unless
   you find such files under a path I missed.
2. Add or enable a production-comparison-only event-state capture for accepted
   hot-slot QN moves. It must record enough state to replay local volume and
   route signatures on the exact event, not only aggregate counters.
3. Then write a readback that joins exact captured accepted-QN events to:
   - route counters,
   - `delta_h`,
   - reverse-gate status,
   - observable seed row,
   - and any volume/route-signature replay result.
4. Decide from evidence:
   - If exact accepted-QN events have near-zero local volume and stable route
     signatures, then the current negative `delta_h` signal is not by itself a
     proof of proposal-density bias; report that and propose the next falsifier.
   - If exact accepted-QN events show route-signature instability, nonzero
     local volume, asymmetric reverse replay, or proposal-density mismatch,
     stop production scaling and write the concrete failing event set.
5. Do not submit a new large production-comparison gate until this readback is
   complete.
6. Do not use official DFO-LS tuning or ODEX modernization as the explanation
   for this issue unless the new event evidence specifically points there. The
   current hypothesis is QN/fallback route balance, branch selection, local
   volume, or proposal-density symmetry.

## Reporting Contract

Update `codex/workspaces/tltm_production_comparison/runbooks/QN_ROUTE_BIAS_DIAGNOSTICS_20260512.md`
with a new section titled `Exact Event Capture Readback`.

Include:

- exact command/config used,
- git branch and commit,
- whether any untracked source was required,
- event counts by route/status,
- route-conditioned `delta_h` table,
- exact-event volume or route-signature table,
- and a clear next-stop decision: `production_scaling_blocked`,
  `needs_more_event_capture`, or `bias_hypothesis_not_supported_by_current_event_evidence`.

Also state explicitly that any diagnostic source outside tracked modernization
work is production-comparison-only and must not be promoted into the
modernization package without a separate reviewed task.

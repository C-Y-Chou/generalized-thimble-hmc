# Final `withfb`/`nofb` Criterion Closure - 2026-05-29

Scope: Stephanov `n=6`, TLTM ladder endpoint `t_high=0.03`, before opening the WV-HMC implementation gate.

This packet applies the frozen criterion framework.  It does not retune thresholds after seeing the final data.

## Decision

- Keep `nofb` as canonical TLTM production mode.
- Keep `withfb` / DFO-LS fallback as default-off legacy diagnostic mode.
- Lower failure count remains diagnostic-only and is not a production criterion.
- Do not use the runtime-excluded repair/outlier jobs for equal-wall-clock, throughput, ESS/hour, or `1/SE^2/hour` claims.

## Primary Observable Gate

| group | samples | phase | effN | chiral Re z | chiral Im z | density Re z | density Im z | max abs z | gate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `nofb_all_available` | 7680512 | 0.117377 | 105817 | +0.962 | -1.027 | -0.535 | +0.266 | 1.027 | pass |
| `withfb_all_available` | 2560512 | 0.120014 | 36880 | -1.736 | +1.798 | +1.556 | -1.867 | 1.867 | pass |
| `nofb_same_config_size_as_withfb` | 2560512 | 0.116900 | 34991 | +1.194 | -0.526 | -0.962 | +0.722 | 1.194 | pass |

Observable-gate conclusion: `nofb_all_available` passes the four primary z checks (`abs(z)<2`). `withfb_all_available` also has `abs(z)<2`, but does not rescue a `nofb` observable failure and is not closer on the four checks as a set.

## Ratio-Estimator Gate

- `nofb_all_available` phase coherence: `0.117377`.
- `withfb_all_available` phase coherence: `0.120014`.
- `nofb_same_config_size_as_withfb` phase coherence: `0.1169`.

Ratio-gate conclusion: there is no denominator or phase-coherence rescue that requires `withfb`.

## Transport Gate

- `nofb:all_available`: round-trip median `221.0`, zero-round-trip fraction `0.0`, high-flow return median `7.0`.
- `withfb:all_available`: round-trip median `88.0`, zero-round-trip fraction `0.0`, high-flow return median `7.0`.

Transport-gate conclusion: the earlier failure-mediated ladder-transport signal remains a warning flag, but transport-only improvement does not justify a production switch without observable, ratio, high-flow ergodicity, or wall-clock productivity impact.

## Runtime Diagnostic

| method | rows included | rows excluded | median wall sec/row | mean wall sec/row | acceptance proxy | proposal failure proxy | reverse-gate reject proxy | median round trips/row | note |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `nofb` | 2880 | 192 | 31698.3 | 31747.4 | 0.649517 | 0.277262 | 0.0620962 | 284 | segment diagnostic only; excluded rows are not used for runtime/equal-wall-clock accounting |
| `withfb` | 288 | 0 | 90425.8 | 90419.2 | 0.742312 | 0.209669 | 0.0288141 | 143 | segment diagnostic only; excluded rows are not used for runtime/equal-wall-clock accounting |

Runtime-gate conclusion: a clean all-available equal-wall-clock comparison is blocked by the runtime exclusion manifest.  The included segment diagnostics are still sufficient to show that `withfb` is much slower per 2500-cycle row, so without an observable or ratio rescue there is no basis to promote it.

## Gate Status

| gate | status | basis |
|---|---|---|
| `observable_correctness` | `passes_nofb_no_withfb_rescue` | All four nofb primary z scores have abs(z)<2; withfb all-available also abs(z)<2 but does not improve over nofb. |
| `ratio_estimator_stability` | `passes_nofb_no_withfb_rescue` | Final pooled phase coherence: nofb_all=0.117377, withfb_all=0.120014, nofb_same_size=0.116900; no denominator rescue signal. |
| `ladder_transport_high_flow` | `transport_warning_secondary_no_switch` | Interim failure-mediated transport warning exists, but zero-round-trip fraction was 0 and final summaries show positive round trips. |
| `failure_mediated_repair` | `diagnostic_only_no_downstream_rescue` | Failure count is not a criterion; final data do not show observable or ratio-quality rescue. |
| `wall_clock_efficiency` | `equal_wall_clock_blocked_by_exclusion_manifest` | Runtime repair/outlier exclusions prevent a clean all-available equal-wall-clock cut; segment diagnostics show withfb is substantially slower per 2500-cycle row. |
| `production_method` | `keep_nofb_canonical_withfb_legacy_default_off` | Frozen gates do not justify promoting withfb; TLTM remains canonical nofb before WV-HMC work starts. |

## Dataset Groups

| group | status | role | archive action | output root |
|---|---|---|---|---|
| `fixed_tau_nofb` | `complete` | `fixed_tau_comparison_group` | `compact_only_or_legacy_archive_pending_raw_archive_decision` | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/stephanov_fixed_tau_nofb_init_tests/stephanov_n6_fixed_tau_t003_nofb_single_source473_512x10000_20260527h` |
| `fixed_tau_withfb` | `partial_legacy_diagnostic` | `legacy_diagnostic_comparison_group` | `legacy_archive_or_compact_only_pending_raw_archive_decision` | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/stephanov_fixed_tau_withfb_init_tests/stephanov_n6_fixed_tau_t003_withfb_single_source473_512x10000_20260528a` |
| `TLTM_nofb` | `complete` | `canonical_production_group` | `canonical_raw_component_pending_raw_archive_decision` | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/stephanov_tltm_production/stephanov_n6_nofb15k_512_equalcost_20260526f` |
| `TLTM_withfb` | `complete` | `legacy_diagnostic_comparison_group` | `legacy_archive_pending_raw_archive_decision` | `/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/stephanov_tltm_production/stephanov_n6_5000_complete_512_optimal_20260526e` |

## Runtime Exclusions

The manifest below is authoritative for runtime accounting:

- `codex/workspaces/fortran_modernization/runbooks/generated/stephanov_n6_final_runtime_exclusions_20260529/runtime_exclusion_manifest.json`

Allowed use: observable/sample completeness. Forbidden use: runtime totals, throughput, equal-wall-clock, ESS/hour, and `1/SE^2/hour` claims.

## Pre-WV-HMC Consequence

- TLTM closure is sufficient to proceed with source hygiene and WV-HMC preparation.
- Future WV-HMC must be added as a sibling sampler following `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`.
- The old `wv` config residue must not be reused as the WV-HMC sampler switch.

## Artifacts

- `final_criterion_summary.json`
- `gate_status.csv`
- `diagnostic_summary_by_method.csv`
- `dataset_archive_groups_final.tsv`

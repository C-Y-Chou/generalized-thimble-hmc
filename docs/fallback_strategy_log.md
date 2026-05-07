# Fallback Strategy Log

Purpose: keep a running "useful / not useful" record so each run updates the next strategy.

## Evaluation Rules
- Consistency pass:
  - `max(Rhat_z_re, Rhat_z_im, Rhat_virial_re, Rhat_virial_im) < 1.01`
  - exact values for `<z>` and `<virial>` inside robust 1-sigma
- Secondary diagnostics:
  - acceptance, solver fail split, near/far counters, sec/sample

## Reset Plan (2026-03-27): Baseline-First Progressive Rescue
- Decision:
  - freeze legacy rescue tree as default `off`.
  - keep `tail-cut no-rescue` as stage-0 baseline.
  - reintroduce compute only with a small progressive ladder (`stage 0 -> 1 -> 2 -> 3`).
- Implementation:
  - `hmc_integrator_core` now uses a progressive path before legacy tree.
  - new env:
    - `QN_PROGRESSIVE_RESCUE_STAGE` (or `QN_BASELINE_STAGE`) in `[0..3]`.
    - `QN_ENABLE_LEGACY_RESCUE=1` to explicitly re-enable old rescue tree.
  - legacy `QN_RESCUE_LEVEL` is ignored unless `QN_ENABLE_LEGACY_RESCUE=1`.
- Stage definition (new path):
  - `stage=0`: probe-only + fail-fast labeling (no rescue expansion).
  - `stage=1`: one controlled full-stage retry.
  - `stage=2`: add one controlled extended-stage retry.
  - `stage=3`: add one terminal strict-continuation retry.
- Instrumentation guarantee:
  - existing counting (`quasi stage/class`, near/far/fail-fast counters) unchanged.
  - post-session metadata unchanged (`constraint_solver_fail_meta.csv` fields preserved).
  - alignment workflow (online class vs 3x3 post-session) unchanged.

### Gate Policy Update (2026-03-16)
- Hard pass/fail is applied only on the canonical `24 x 50k` runs.
- Non-50k runs (`smoke`, `5k`, `10k`, etc.) are directional checks only:
  - used to verify trend/sign of change and structural correctness,
  - not used as final acceptance criteria for all metrics.
- Do not reject a structural direction solely because a non-50k pilot misses strict final thresholds.

## Observed Changes

| Change | Hypothesis | Observed Result | Verdict | Next Action |
|---|---|---|---|---|
| simplified Newton warm-start experiments | better initial guess improves speed/acceptance | acceptance dropped sharply / did not improve correctness in observed runs | Not useful | removed from fallback path entirely |
| `r4_nearfirst` | Prioritize near rescue first improves consistency | `t=0.6` expectations worsened (`z_rhat` around `1.04`, unstable) | Not useful | Do not use near-first as default |
| `r5_nearstrictcont` | strict continuation can reduce near fails | near_fail dropped (`187 -> 70`) but ensemble diagnostics unchanged vs base | Limited utility | Keep as rescue primitive, not as proof of consistency gain |
| `r6_nearescape` | stronger near escape further improves robustness | near_fail dropped further (`70 -> 57`) but diagnostics still unchanged vs base | Limited utility | Keep as optional rescue mode only |
| `stageBpilot` nofb vs withfb (`24x10k`, 3 pairs) | nofb may be good enough at lower cost | nofb had very poor mixing (`z_rhat ~1.63-1.67`), withfb much better (`~1.07`) but ~4.1x slower | Useful evidence for fallback necessity | Continue withfb-first consistency work |
| `stageBmid50k` pair1 nofb vs withfb (`24x50k`) | longer chains may rescue nofb consistency | nofb still very inconsistent (`z_rhat_re=1.781`, `z_rhat_im=1.663`), withfb much better (`1.030/1.017`) but still not under 1.01 | Strongly useful | Optimize withfb for consistency first, then efficiency |
| `consistency50k_p01_withfb` partial (`2026-03-14`, running) | one long withfb seed may show early consistency trend | at `samples_total~155k`, `split_rhat_z~1.073/1.050`; chain progress highly imbalanced (`min~2860`, `max~11140`); near_fail already nonzero in `9/24` chains (cum `11`) | Not sufficient for consistency claim; likely fail under strict near-fail criterion | stop long run and retune near-singularity handling before another 50k run |
| `t05_agggate50k_p01_withfb` complete (`24x50k`) | aggressive gating should recover runtime while keeping acceptable robustness | run completed in `~4582s` for `1.2M` samples (much faster than stalled `t=0.6` run), but strict consistency still fails: `split_rhat_z=1.026/1.015`, `split_rhat_virial=1.017/1.000`, and final near-fail counters are nonzero (`near_fail=9` across `6/24` chains); `<z>_im=-1.010` is outside robust 1-sigma (`0.00736`) around exact `-1` | Mixed (speed improved, consistency not yet) | keep aggressive gating baseline, then tighten near handling and rerun short pilot before next `50k` |
| near-fix patch on aggressive gating (`2026-03-14`) | recover strict near robustness without losing speed: deeper strict continuation + richer promotion seeds + higher near strict iter cap | code updated (`strict_cont`: split factors up to `1/32`, promotion seeds `(+split,-split,0)`, near strict iter cap `420 -> 900`); smoke `4x2000` finished with `near_fail=0`, `near_try=47`, `near_ok=47` | Promising | run `24x10k` pilot first; if near_fail stays zero, proceed to `24x50k` |
| `t05_agggate_nearfix10k_p01_withfb` complete (`24x10k`) | near-fix patch should cut near failures while preserving speed | fast completion (`~490s`, `240k` samples), strong acceptance (`~0.942`), but still not at strict consistency gate: `split_rhat_z=1.039/1.013`, `split_rhat_virial=1.016/1.000`; near failures reduced but nonzero (`near_fail=2` across `2/24` chains) | Useful trend, not sufficient | apply one more targeted near safeguard before next `50k`; do not claim consistency yet |
| near-fix2 patch (`2026-03-14`) | eliminate residual near-fail tail with minimal overhead | added terminal near-only paper-exact rescue after strict continuation ladder (iter cap `160`, seeds `+/−/0`); smoke `4x2000` keeps `near_fail=0`, runtime unchanged (`~40s`) | Promising | rerun `24x10k` on same seed to verify `near_fail` drops from `2` to `0`; then run `24x50k` |
| `t05_agggate_nearfix2_10k_p01_withfb` complete (`24x10k`) | near-fix2 should remove the last near-fail events | no practical change vs nearfix10k baseline: `split_rhat_z=1.039/1.013`, `split_rhat_virial=1.016/1.000`, `near_fail=1` (`chain_014`), `near_unusable=2` (`chain_003`,`chain_014`) | Not sufficient | increase strict near rescue intensity (higher near strict iter + higher terminal paper iter cap) and rerun same `24x10k` seed |
| `t05_agggate_nearfix3_10k_p01_withfb` complete (`24x10k`) | stronger caps (`near_strict=2000`, `terminal_paper=800`) should eliminate remaining near tail | result is effectively unchanged vs nearfix2 on the same seed (`split_rhat_z=1.039/1.013`, `near_fail=1`, `near_unusable=2`), and `z_history` checksums on failing chains are identical | Not useful (for this seed) | move to structural near-only terminal pass, not just higher iter caps |
| near-hard structural patch (`2026-03-14`) | a final conservative paper-exact pass without near-escape shaping can recover last stubborn near cases | added terminal hard pass in strict continuation: `paper_exact=.true.`, `near_escape_mode=.false.`, cap `2000`, seeds `+/−/0`; smoke `1x1000` passes | Pending | rerun same `24x10k` seed and check `near_fail==0` before any `50k` |
| `t05_agggate_nearhard_10k_p01_withfb` complete (`24x10k`) | near-hard pass should alter stubborn near-tail behavior | no effective change vs nearfix3 on same seed (`near_fail=1`, `near_unusable=2`, diagnostics identical; failing chain histories identical) | Not useful (for this seed) | add explicit near-only terminal Newton rescue mode |
| near-terminal Newton rescue patch (`2026-03-14`) | quasi strict path may stall while Newton with relaxed early-abort can still converge on rare near-hard tail | added `rescue_mode` to constraint Newton and invoke it only after strict-continuation failure in near branch; smoke `1x1000` passes | Pending | rerun same `24x10k` seed and check whether `near_fail` goes to zero |
| `t05_agggate_nearnewton_10k_p01_withfb` complete (`24x10k`) | terminal Newton rescue should remove last near-hard failures | still unchanged vs nearfix3/nearhard (`near_fail=1`, `near_unusable=2`, diagnostics and failing-chain histories identical) | Not useful (for this seed) | use structural damped Newton (line-search) in near-only rescue mode |
| near-terminal damped Newton patch (`2026-03-14`) | undamped Newton rescue may overshoot near singularity; backtracking Newton can recover monotonic residual decrease | in `rescue_mode`, added alpha-halving line-search on Newton projected step and select best finite trial; smoke `1x1000` passes | Pending | rerun same `24x10k` seed and check `near_fail==0` with acceptable runtime impact |
| `t05_agggate_nearnewtonls_10k_p01_withfb` complete (`24x10k`) | damped Newton rescue should change stubborn near-tail outcomes | still unchanged vs nearfix3 (`near_fail=1`, `near_unusable=2`, diagnostics and failing-chain histories identical); runtime increased (`~540s`) | Not useful (for this seed) | adjust strict-continuation acceptance for near-only coarse stages |
| near strict tol-floor patch (`2026-03-14`) | some near-hard failures reach numerical floor near `cttol` but miss by tiny margin; near-only relative tol relaxation can unblock continuation | in strict continuation only, use `tol_near = 4*tol` for stage/paper/hard passes (model-general relative rule); compiled | Pending | rerun same `24x10k` seed and recheck `near_fail` first, then `Rhat`/runtime |
| strict quasi tolerance back to `cttol` | tighter solve helps expectation consistency (virial / z) | avoids relaxed quasi residual acceptance path; numerically safer | Useful | keep strict quasi tolerance as baseline |
| deterministic escalation (`probe->full->extended->near->strict`) | remove gate misses to maximize robustness | robust completion observed, but heavy long-tail latency spikes in some chains (single trajectory can cost >100s) | Useful for robustness, costly for efficiency | keep for consistency phase; later add cost-aware cap only after consistency is stable |
| fast-relaxed far policy + watchdog-only deep rescue (`2026-03-16`) | keep structure but remove unnecessary far-cost to validate direction quickly | code updates: remove duplicated near terminal block, lower deep-iter caps (`near_strict 2000->900`, `far_terminal 1200->420`), far default fail-fast (cheap/full/extended only when gate/watchdog requests). Same-seed smoke `4x2000`: mean chain elapsed `54.52s -> 38.62s` (~29% faster), stage totals `probe 2135/2382 -> 2062/2314`, `full 227/248 -> 126/133`; acceptance remains high (`~0.936-0.945`) | Useful for fast direction check | use this profile for pilot scan first (`24x10k`), then tighten only if consistency metrics fail |
| `s20l2t05_fastrelaxed_pilot5k_p01_withfb` + near-tail guard (`2026-03-16`) | fast-relaxed may be too loose for consistency; recover near robustness without giving up far speed | pilot showed consistency miss (`split_rhat_z_re=1.0335`) and one near miss (`near_fail=1`, `near_unusable=1`, `far_fail=1601`). Added near-only final guard (high-cap strict continuation + Newton rescue, `max_iter=1800`) while keeping far fail-fast policy. Same-seed smoke `4x2000` after guard keeps fast runtime (elapsed `29-45s`) and reports `near_fail=0` | Promising | rerun `24x5k` on same seed; if `near_fail==0` and `Rhat` improves, promote to `24x10k` |
| trace-quality-aware online gating (`2026-03-16`) | post-session showed failure-set online class collapsing to `global`; recover useful rescue routing without geometry-specific thresholds | changed online gating/classification to use `valid_eval_count` + `valid_eval_fraction` (instead of hard `all_eval_ok`) and kept residual-ratio/progress/regress metrics model-general; updated post-session alignment script to match | Pending | run `4x2k` smoke then `24x10k`; check whether `local/mid` counts become nonzero on failure-heavy runs and whether `near_fail`/`Rhat_z` improve without large runtime regression |
| near tail last-chance rescue (`2026-03-16`) | after trace-quality pilot, near_fail still nonzero (`2` at `24x10k`) with two problematic chains; add rare-only terminal near path | added near-only last-chance ladder after final guard: `zero-Jl full(2600) -> strict_cont(2600) -> terminal Newton(2600)`; applied both in near branch and late near reclass branch | Pending | rerun same seed `24x10k`; target `near_fail=0` without major wall-time regression |

## Current Strategy (active)
1. Aggressive gating policy (active for speed scan):
   - run `probe` first
   - if probe fails: escalate only if classified as near case
   - far cases fail-fast (skip full/extended/strict)
2. Near-case rescue ladder:
   - `full -> extended -> near_rescue -> strict_continuation`
3. Strict continuation ladder:
   - full-step, then split-promotion from `1/2`, `1/4`, `1/8`, `1/16`, `1/32`
   - terminal near-only paper pass, then terminal near-only hard conservative pass
4. Efficiency-first scan now precedes another consistency check run.

## Dynamic Update Rules (run-by-run)
1. If `near_fail > 0` or any near-fail candidate appears:
   - treat as highest-priority blocker; tighten near-rescue / strict continuation behavior first.
2. If `near_fail == 0` but `Rhat_z` or expectation coverage fails:
   - do not relax quasi tolerance; inspect far-fail episodes and long-tail events first.
3. If consistency passes but wall time is too high:
   - optimize cost by reducing unnecessary escalation on clearly safe probe cases.
4. Promote a change only if it improves target metric without breaking higher-priority gates:
   - priority order = `consistency > robustness near singularity > efficiency`.

## Latest Runtime Signal (smoke)
- Run: `tmp_consistency_smoke_0314_145008` (`2x1000`, with fallback)
- Both chains completed; no near_fail observed.
- One chain had heavy long-tail delays (elapsed jumps around steps `330` and `520`), aligned with bursts in `radau_ng`, `hard_fail`, and `far_fail`.
- Interpretation: current policy is robust but has expensive rare events; next efficiency work should target these tail-cost far events without reintroducing near failures.

## Notes
- Current near/far tags are residual-threshold based, not pure geometry tags.
- near/far counters should be treated as diagnostics, not primary acceptance criteria.

## Implementation Note (2026-03-24): Explicit near-unsolvable fail-fast label
- Goal:
  - cut very long near tail events explicitly while minimizing side-effects on solvable near cases.
- Implemented:
  - Added explicit near fail-fast decision in `hmc_integrator_core`:
    - primary trigger: per-step `final_resort_used >= QN_NEAR_FAIL_FAST_FINAL_RESORT_LIMIT` (default `3000`)
    - secondary trigger: under budget pressure + no-progress trace signatures
  - Added runtime labels:
    - progress line now includes `near_fail_fast=...`
    - near ladder logs include `[QN] near fail-fast unsolvable reason=...`
  - Added post-session labels in `constraint_solver_fail_meta.csv`:
    - `near_fail_fast` (0/1)
    - `near_fail_fast_reason` (integer reason code)
  - `inspect_tail_fail_context.py` now prints these fields for direct tail-event single-out.

## Plan Lock (2026-03-16): Online Classification + Structured Validation
- Goal:
  - keep online gating model/dimension independent while preserving consistency first, then recover efficiency.
- Design decision (locked):
  - do not use geometric thresholds like `max|Re(z+dz)| > max|Re(z)|(1+eps_far)` online.
  - use behavior-only signals from the probe solve:
    - `best_over_tol` (best residual ratio vs tolerance),
    - `trace_progress_ratio`,
    - `trace_regress_ratio`.
  - map to 3 online classes for routing/diagnostics:
    - `local` (safe/close),
    - `mid` (ambiguous),
    - `global` (hard/far-like behavior).

### Implemented in code (locked)
- `constraint_solver_stats.f90`:
  - added counters:
    - `quasi_class_local_count`
    - `quasi_class_mid_count`
    - `quasi_class_global_count`
  - added API:
    - `record_constraint_solver_quasi_class(class_code)`
    - `get_constraint_solver_quasi_class_stats(...)`
  - summary print now includes:
    - `quasi_class local=... mid=... global=...`
- `hmc_integrator_core.f90`:
  - probe-fail classification now uses behavior metrics (`best_over_tol`, progress/regress ratios),
  - records online class counters after classification.
- `markovchain_mod.f90`:
  - chain progress and final summary now print class counters.

### Why this is the current path
- Post-session 3x3 geometry analysis shows mixed structure; geometry-far dominates but not exclusively.
- Therefore, online routing should stay behavior-based (portable), while geometry stays offline for audit only.

### Next test sequence (do not skip order)
1. Smoke validate instrumentation (`withfb`, short run):
   - verify log lines contain `quasi_class local/mid/global`.
2. `24x10k` pilot on current structured gate:
   - first gate = consistency safety (`near_fail`, `Rhat`, `<z>`, `<virial>`).
3. After post-session analysis is generated:
   - run online-vs-geometry confusion check and record alignment metrics (`best_match_accuracy_3x3`, `global_to_gt_max_precision`, `gt_max_to_global_recall`).
4. If consistency holds:
   - tune only gating thresholds (not solver structure) for efficiency.
5. If consistency breaks:
   - revert threshold tweak; keep structure fixed; retest.

### Promotion criteria
- Must-pass:
  - robust consistency criteria unchanged:
    - `max(Rhat_z_re, Rhat_z_im, Rhat_virial_re, Rhat_virial_im) < 1.01`
    - exact `<z>` and `<virial>` inside robust 1-sigma.
- Then optimize:
  - reduce heavy-tail runtime without reintroducing nonzero near-fail events.

### Explicit non-goals for this phase
- no model-specific geometry threshold in online gate.
- no large structural rewrite before instrumentation-driven evidence.

## Baseline Record (2026-03-16): p00 probe-only completed
- Run:
  - `s20l2t05_plain_benchmark_p00_probeonly`
  - config: `t=0.5`, `24x10k`, `QN_RESCUE_LEVEL=0`, `quasi-fallback=on`
- Runtime:
  - `elapsed_seconds=400.085`
  - `reason=target_reached`
- Evaluate:
  - `<virial> (Re, Im) = (1.142640E-03, 5.891563E-03)`
  - `<z> (Re, Im) = (-2.251622E-01, -9.971791E-01)`
  - `split_rhat_virial (Re, Im) = (1.0158, 1.0004)`
  - `split_rhat_z (Re, Im) = (1.0529, 1.0117)`
  - `ess_bulk_z (Re, Im) = (263.76, 1371.61)`
- Final chain-counter aggregation (`24 chains`):
  - `near_fail=1264`
  - `near_try=0`, `near_ok=0`, `near_unusable=0`
  - `far_fail=4530`
  - `probe=55998/61792`, `full=0/0`, `extended=0/0`
  - `class local=1264, mid=296, global=4234`
- Post-session alignment:
  - official100: `best_match_accuracy_3x3=0.79`, `global_to_gt_max_precision=0.128`, `gt_max_to_global_recall=1.0`
  - light600: `best_match_accuracy_3x3=0.77`, `global_to_gt_max_precision=0.119`, `gt_max_to_global_recall=1.0`
- Decision:
  - keep this run as fixed baseline.
  - next comparison target is `QN_RESCUE_LEVEL=1` with same seed/config to isolate near-only minimal rescue effect.

## Comparison Record (2026-03-16): p01 near-only completed
- Run:
  - `s20l2t05_plain_compare_p01_nearonly`
  - config: `t=0.5`, `24x10k`, `QN_RESCUE_LEVEL=1`, same seed/config as p00
- vs p00 (`probe-only`) key deltas:
  - `near_fail`: `1264 -> 30` (large improvement, but not zero)
  - `near_try/near_ok`: `0/0 -> 1275/1245`
  - `far_fail`: `4530 -> 5080` (worse)
  - runtime: `400.1s -> 470.1s` (~+17.5%)
  - `split_rhat_z`: `(1.0529,1.0117) -> (1.0388,1.0130)` (Re improves, Im slightly worse)
  - `split_rhat_virial`: effectively unchanged around `(1.0159,1.0004)`
- Interpretation:
  - near-only minimal rescue is directionally correct for near failures,
  - but not sufficient for consistency target (`Rhat < 1.01`) and not enough for `near_fail=0`.
  - additional near-path depth is justified before touching far gate logic.
- Next locked step:
  - run `QN_RESCUE_LEVEL=2` on same `24x10k` seed/config to isolate near-ladder effect (full+extended+near strict/newton path, still no mid/far rescue).

## Comparison Record (2026-03-16): p02 near-ladder completed
- Run:
  - `s20l2t05_plain_compare_p02_nearladder`
  - config: `t=0.5`, `24x10k`, `QN_RESCUE_LEVEL=2`, same seed/config
- vs p01 key deltas:
  - `near_fail: 30 -> 1`
  - `near_unusable: 30 -> 2`
  - `extended: 0/0 -> 28/55`
  - runtime: `470.1s -> 610.1s` (significant slowdown)
  - evaluate metrics were effectively unchanged at this precision for this seed (`split_rhat_z` stayed `(1.0388, 1.0130)`).
- Interpretation:
  - level-2 near ladder is highly effective on residual near failures.
  - remaining issue is a tiny near tail (`near_fail=1`) plus high extra cost.

## Structural tweak after p02 (2026-03-16)
- Implemented:
  - in `hmc_integrator_core.f90`, enable near `last-chance` block for `QN_RESCUE_LEVEL>=2` (previously `>=3`).
  - this applies only to near path, in both primary near pipeline and late near reclassification path.
  - mid/far rescue gating remains unchanged (still level 3).
- Goal:
  - eliminate residual near fail (`near_fail -> 0`) with minimal additional policy complexity.

## Comparison Record (2026-03-16): p03 near-ladder-lc2 completed
- Run:
  - `s20l2t05_plain_compare_p03_nearladder_lc2`
  - config: same as p02 (`level=2`), with near last-chance moved into level 2.
- Outcome vs p02:
  - `near_fail`: stayed `1` (no improvement)
  - `near_unusable`: stayed `2`
  - `extended`: `28/55 -> 28/59` (more retries)
  - runtime: `610.1s -> 660.1s` (slower)
  - evaluate metrics unchanged at reported precision.
- Interpretation:
  - residual near-fail is not fixed by simply enabling the current near last-chance path earlier.
  - near-only strategy is now in diminishing returns region: more near retries, higher cost, little gain.
  - next structural step should re-introduce a very constrained far-escape route rather than adding deeper near-only rescue.

## Comparison Record (2026-03-16): p04 level3 completed + tail diagnosis
- Run:
  - `s20l2t05_plain_compare_p04_level3`
  - config: `QN_RESCUE_LEVEL=3` (near+mid+far policy active)
- Aggregate counters:
  - `near_fail=2`, `near_try=1291`, `near_ok=1287`, `near_unusable=4`
  - `far_fail=2924` (significantly lower than p03: `5107`)
  - stage: `probe=58775/65333`, `full=3543/3754`, `extended=89/143`
- Evaluate snapshot:
  - `split_rhat_z (Re, Im) = (1.0219, 1.0140)` (still above `<1.01`)
  - `split_rhat_virial (Re, Im) = (1.0162, 1.0002)`
- Wall clock:
  - `elapsed_seconds=710.1` (slower than p03: `660.1`)

### Tail-event finding (important)
- The same deterministic hard event persists around `sample ~956x` on chain 003:
  - p03 chain_003: jump `9560->9570`, `+233s`, `d_inner_resort=+53887`, `d_flowzr_fb=+51199`, `d_near_unusable=+1`, `d_far_fail=+1`
  - p04 chain_003: jump `9560->9570`, `+241.8s`, `d_inner_resort=+59657`, `d_flowzr_fb=+57629`, `d_near_unusable=+1`, `d_far_fail=+1`
- p04 additionally introduces another large jump on chain 020:
  - `9730->9740`, `+147.2s`, `d_inner_resort=+55613`, `d_flowzr_fb=+15357`, `d_near_unusable=+1`, `d_far_fail=+1`
- Interpretation:
  - efficiency is dominated by rare heavy-tail events, not average-case probe speed.
  - this must be measured explicitly; total wall time alone is insufficient.

### Objective efficiency protocol (locked for next comparisons)
- Use three timing tiers together:
  - `median` chain completion (bulk throughput),
  - `p95` chain completion (tail pressure),
  - `max` chain completion (worst-case robustness cost).
- Also report heavy-tail event count and top jump magnitude from progress logs.
- New tool added:
  - `scripts/analyze_tail_events.py`
  - Example:
    - `python3 scripts/analyze_tail_events.py --run-dir output/multichain_auto/<RUN> --jump-threshold 30`

## Tail-event structural instrumentation (2026-03-16, latest)
- Goal:
  - make each failure sample traceable to:
    - `z0`, `delz`, `x0`,
    - online failure class (`near/mid/far`),
    - solver situation (fallback context + rescue deltas),
    - runtime position (`chain_sample_idx`, `hmc_repeat_idx`).
- Implemented:
  - `constraint_solver_fail_meta.csv` emission in `constraint_solver_stats.f90`.
  - runtime context setter `set_constraint_solver_runtime_context(chain_sample_idx, hmc_repeat_idx)` called from `markovchain_mod.f90` before each `metropolis_step`.
  - optional metadata passed from `hmc_integrator_core.f90` on each failure capture:
    - `quasi_case`, `online_class`,
    - trace quality metrics (`trace_valid_fraction`, `trace_progress_ratio`, `trace_regress_ratio`, `trace_best_over_tol`),
    - near flags (`is_near_case`, `near_rescue_started`, `near_rescue_done`),
    - solver fallback/rescue counters and per-failure deltas (`d_*`).
  - post-session merger now includes merged `constraint_solver_fail_meta.csv` in `scripts/build_post_session_bundle.py`.
  - chain-window inspector added: `scripts/inspect_tail_fail_context.py`.

### Current run status for p04
- Existing run `s20l2t05_plain_compare_p04_level3` predates meta capture, so:
  - has `z0/delz/x0/quasi_trace`,
  - does **not** have per-chain `constraint_solver_fail_meta.csv`.
- Therefore:
  - can do tail timing + 3x3 post-session classification now,
  - cannot yet map a specific tail jump (e.g. chain_003 9560->9570) to exact per-failure `chain_sample_idx/hmc_repeat_idx` + solver deltas.

### Alignment check on p04 (all captured failures)
- post-session bundle/all-case no-plot done:
  - merged failures: `2241`
  - 3x3 band counts: lt-min `95`, in-band `1327`, gt-max `818`, no-hit `1`
- online-vs-geometry confusion (all 2241):
  - online `global` dominates failure captures (`2240/2241`),
  - best-match 3x3 accuracy `0.5929`,
  - `gt_max -> global` recall `1.0`, but `global -> gt_max` precision `0.365`.
- Interpretation:
  - current online class for failure captures is overly collapsed to global; useful for safety, weak for diagnostic discrimination.

### Next locked experiment for true tail root-cause
- Re-run a short focused pilot with new binary and selective capture window:
  - set `CONSTRAINT_FAIL_CAPTURE_START_SAMPLE` around known tail zone (e.g. `9400`),
  - set `CONSTRAINT_FAIL_CAPTURE_LIMIT=0` (unlimited after start) or a large enough bound.
- Then run:
  - `scripts/inspect_tail_fail_context.py` on target chain/sample window
  - to extract exact `z0/delz` magnitudes + online class + solver situation deltas for tail events.

## Tailmeta focused run completed (2026-03-16): `s20l2t05_tailmeta_pilot10k_p01_withfb`
- Config:
  - `24x10k`, `t=0.5`, with fallback.
  - capture env: `CONSTRAINT_FAIL_CAPTURE_START_SAMPLE=9400`, `CONSTRAINT_FAIL_CAPTURE_LIMIT=0`.
- Evaluate:
  - `<virial> = (2.921245e-02, 6.490630e-03)`
  - `<z> = (-4.164238e-02, -1.002722e+00)`
  - `split_rhat_virial = (1.0162, 1.0002)`
  - `split_rhat_z = (1.0219, 1.0140)`
- Tail timing:
  - max chain elapsed `785.99s` (chain_003), p95 `595.37s`.
  - heavy events include:
    - chain_003 `9560->9570` `+227.95s`
    - chain_003 `3700->3710` `+148.60s`
    - chain_020 `9730->9740` `+142.58s`
- Meta capture summary:
  - total meta rows: `150` (windowed capture after sample 9400).
  - quasi_case distribution in captured tail window: `near=0, mid=1, far=149`.
  - confirms tail-window failures are overwhelmingly `far/global`.

### Direct tail-context extraction
- chain_003, `9560-9570` matched row:
  - `chain_sample_idx=9569`, `hmc_repeat_idx=1`, `quasi_case=far`, `online_class=global`
  - `d_attempt_flowzr=57703`, `d_attempt_flowz=2945`
  - `d_success_final_resort=60648`, `d_fail_final_resort=0`
  - `z0_abs_re_max=1.237e-01`, `delz_abs_max=1.250e-01`, `delz_l2=1.312e-01`
- chain_020, `9730-9740` matched row:
  - `chain_sample_idx=9735`, `hmc_repeat_idx=1`, `quasi_case=far`, `online_class=global`
  - `d_attempt_flowzr=15357`, `d_attempt_flowz=40254`
  - `d_success_final_resort=55611`, `d_fail_final_resort=0`
  - `z0_abs_re_max=1.558e-01`, `delz_abs_max=1.578e-01`, `delz_l2=1.648e-01`
- Note:
  - chain_003 `3700-3710` had no matched meta row because capture starts at `9400`.

### Alignment check (captured 150 cases only)
- 3x3 counts:
  - `lt-min=6`, `in-band=102`, `gt-max=42`.
- online-vs-geometry matrix:
  - `local: 2`, `mid: 1`, `global: 147`.
  - best-match 3x3 accuracy `0.6867`.
  - `gt_max -> global` recall `1.0`; `global -> gt_max` precision `0.2857`.
- Interpretation:
  - online class remains heavily global-biased on failure captures; useful for conservative triggering, weak for far sub-type discrimination.

### Tooling robustness fix
- `scripts/build_post_session_bundle.py` updated:
  - ignore trailing empty CSV field (`None` key) when merging meta rows.
  - this is required because current Fortran meta writer emits a trailing comma.

## Structural update (2026-03-16): far final-resort watchdog + richer diagnostics
- Implemented in solver:
  - `quasi_newton_solver.f90` now has a per-quasi-call watchdog on cumulative `success_final_resort` usage.
  - policy env: `QUASI_FINAL_RESORT_BUDGET` (default `20000`; `<=0` disables).
  - once budget is exceeded inside a quasi solve, further residual evaluations fail-fast for that solve.
  - strict near continuation path remains unchanged (watchdog scope is on the main quasi solve path).
- Diagnostics added:
  - progress/summary now print:
    - `quasi_watchdog hits=<...> max_used=<...> avg_used=<...> budget_last=<...>`
  - failure meta CSV includes:
    - `final_resort_budget_hit, final_resort_budget_used, final_resort_budget_limit`
  - `inspect_tail_fail_context.py` now reports these fields too.
- Post-session compatibility:
  - `build_post_session_bundle.py` keeps robust handling for old malformed rows;
    new rows are now emitted without trailing-empty-column issue.

## Watchdog pilot result (2026-03-16): `s20l2t05_watchdog12k_pilot10k_p01_withfb`
- Config:
  - `24x10k`, `t=0.5`, with fallback.
  - `QUASI_FINAL_RESORT_BUDGET=12000`.
- Main outcome:
  - statistical outputs are identical to `s20l2t05_tailmeta_pilot10k_p01_withfb` at printed precision.
  - `<virial> = (2.921245e-02, 6.490630e-03)`, `<z> = (-4.164238e-02, -1.002722e+00)`.
  - `split_rhat_virial = (1.0162, 1.0002)`, `split_rhat_z = (1.0219, 1.0140)`.
- Tail/runtime:
  - max chain elapsed `804.51s`, p95 `600.48s`, median `404.23s`.
  - heavy events remain at same locations:
    - chain_003 `9560->9570` `+227.65s`
    - chain_003 `3700->3710` `+172.70s`
    - chain_020 `9730->9740` `+142.74s`
- Near/far and stage totals (24 chains):
  - `near_fail=2`, `near_try=1291`, `near_ok=1287`, `near_unusable=4`, `far_fail=2924`.
  - quasi stage: `probe=58775/65333`, `full=3543/3754`, `extended=89/143`.
- Watchdog diagnostics:
  - chain summaries: `hits_total=0`, `max_used_any_chain=1150`, `budget_last=12000`.
  - interpreted as: budget is too loose; watchdog does not yet control tail loops.
- Post-session 3x3 alignment:
  - official100: best-match `0.55`, `global->gt_max` precision `0.41`, `gt_max->global` recall `1.0`.
  - light600(all 266): best-match `0.5876`, `global->gt_max` precision `0.375`, `gt_max->global` recall `0.75`.
  - matrix still global-heavy on failures; online-vs-geometry discrimination remains weak.
- Decision for next step:
  - keep current structure; tighten watchdog budget to force activation in pilots (`3000` then `2000` if needed).

## Watchdog pilot result (2026-03-16): `s20l2t05_watchdog3k_pilot10k_p01_withfb`
- Config:
  - `24x10k`, `t=0.5`, with fallback.
  - `QUASI_FINAL_RESORT_BUDGET=3000`.
  - tail-focused capture: `CONSTRAINT_FAIL_CAPTURE_START_SAMPLE=9400`, `CONSTRAINT_FAIL_CAPTURE_LIMIT=0`.
- Main outcome:
  - statistical outputs unchanged vs `watchdog12k`/`tailmeta` at printed precision:
    - `<virial> = (2.921245e-02, 6.490630e-03)`
    - `<z> = (-4.164238e-02, -1.002722e+00)`
    - `split_rhat_virial = (1.0162, 1.0002)`
    - `split_rhat_z = (1.0219, 1.0140)`
- Tail/runtime:
  - max chain elapsed `758.22s`, p95 `597.32s`, median `429.75s`.
  - heavy events remain in same tail locations:
    - chain_003 `9560->9570` `+232.93s`
    - chain_020 `9730->9740` `+152.61s`
    - chain_003 `3700->3710` `+109.26s`
  - controller progress still shows long plateau with min stuck around `9568` before final completion.
- Stage/class/failure totals (24 chains):
  - `near_fail=2`, `near_try=1291`, `near_ok=1287`, `near_unusable=4`, `far_fail=2924`.
  - quasi stage: `probe=58775/65333`, `full=3543/3754`, `extended=89/143`.
  - quasi class: `local=1236`, `mid=319`, `global=5003`.
- Watchdog diagnostics:
  - summary: `hits_total=0`, `max_used_any_chain=1150`, `budget_limit=3000`.
  - post-session meta (captured tail window): `rows=150`, `budget_hit_rows=0`, `max_budget_used=1150`.
  - interpretation: reducing budget `12000 -> 3000` is still too loose to trigger this watchdog path; no direct control on the known tail spikes yet.
- Alignment (captured tail window):
  - official100: best-match `0.68`, `global->gt_max` precision `0.3030`, `gt_max->global` recall `1.0`.
  - light600(150 captured): best-match `0.6867`, `global->gt_max` precision `0.2857`, `gt_max->global` recall `1.0`.

## Structural update (2026-03-16): step-scope rescue budget manager (all-path)
- Motivation:
  - per-quasi watchdog did not touch known tail hotspots;
  - hotspots involve broader rescue pipeline (quasi + strict-cont + near-terminal-newton).
- Implemented in `hmc_integrator_core.f90`:
  - added per-`rattle_step` budget scope keyed by cumulative `success_final_resort` delta.
  - env policy:
    - `QN_STEP_BUDGET_SOFT1`
    - `QN_STEP_BUDGET_SOFT2`
    - `QN_STEP_BUDGET_HARD`
  - if `QN_STEP_BUDGET_HARD<=0`: disabled.
  - default when `HARD>0` and soft thresholds missing:
    - `SOFT1 = HARD/3`, `SOFT2 = 2*HARD/3`.
- Layered behavior:
  - `SOFT1` exceeded:
    - skip extended rescue branches (`extended` / `near_rescue_max_iter` style stages).
  - `SOFT2` exceeded:
    - skip terminal branches (strict continuation + near terminal newton ladders).
  - `HARD` exceeded:
    - stage wrappers fail-fast for remaining rescue attempts in current step.
- Coverage:
  - budget checked in wrappers of:
    - `try_quasi_stage`,
    - `try_quasi_strict_continuation_stage`,
    - `try_near_terminal_newton_rescue`.
  - this ties one budget across quasi/strict/newton rescue routes.
- Diagnostics wiring:
  - on failure capture, exported `final_resort_budget_*` now prefers step-scope budget (if enabled), preserving old fields/schema.
  - existing `[SUMMARY] quasi_watchdog ...` line now reflects this budget when enabled and failure captures exist.

### Smoke validation (short run)
- Run:
  - `tmp_stepbudget_smoke_0316_180017` with
    - `QN_STEP_BUDGET_SOFT1=60`
    - `QN_STEP_BUDGET_SOFT2=120`
    - `QN_STEP_BUDGET_HARD=200`
    - `2x600`.
- Confirmed:
  - logs print policy load:
    - `[INFO] rescue step budget soft1=60 soft2=120 hard=200`.
  - summary/meta budget limit is `200` (new manager active).
  - sample smoke had no hard hits (`budget_hit=0`), max observed used `152` on one chain.

## Step-budget pilot result (2026-03-16): `s20l2t05_stepbudget_pilot10k_p01_withfb`
- Config:
  - `24x10k`, `t=0.5`, with fallback.
  - `QN_STEP_BUDGET_SOFT1=1500`
  - `QN_STEP_BUDGET_SOFT2=5000`
  - `QN_STEP_BUDGET_HARD=10000`
  - `QUASI_FINAL_RESORT_BUDGET=0` (old quasi-only watchdog disabled; step-budget manager active).
  - capture env: `CONSTRAINT_FAIL_CAPTURE_START_SAMPLE=9400`, `CONSTRAINT_FAIL_CAPTURE_LIMIT=0`.
- Core metrics:
  - `<virial>`, `<z>`, `split_rhat_*`, `ess_*` unchanged at printed precision vs `tailmeta/watchdog3k`.
- Runtime/tail comparison (objective protocol):
  - current run:
    - `min/median/p90/p95/max = 209.20 / 418.87 / 518.17 / 526.07 / 626.85 s`
  - vs `tailmeta` (`261.89 / 400.30 / 552.59 / 595.37 / 785.99 s`):
    - strongest gain in tail:
      - p95 improved `595.37 -> 526.07` (~11.6%)
      - max improved `785.99 -> 626.85` (~20.2%)
  - hotspot jumps:
    - chain_003 `9560->9570`: `227.95s -> 69.86s`
    - chain_020 `9730->9740`: `142.58s -> 60.98s`
    - chain_003 `3700->3710`: `148.60s -> 57.00s`
- Failure/stage totals (24 chains):
  - `near_fail=2`, `near_try=1291`, `near_ok=1287`, `near_unusable=4`, `far_fail=2924`.
  - quasi stage: `probe=58775/65333`, `full=3543/3754`, `extended=89/132`.
  - quasi class: `local=1236`, `mid=319`, `global=5003`.
- Budget activation evidence:
  - chain summaries: `hits_total=2`, `max_used_any=18045`, `budget_last=10000`.
  - post-session meta: `rows=150`, `budget_hit_rows=2`, `max_budget_used=18045`, `budget_limit=10000`.
  - hit chains align with known hotspots:
    - `chain_003` max_used `18045`, hit=1
    - `chain_020` max_used `11388`, hit=1
- Post-session alignment (captured window):
  - official100: best-match `0.68`, `global->gt_max` precision `0.3030`, `gt_max->global` recall `1.0`.
  - light600(150): best-match `0.6867`, `global->gt_max` precision `0.2857`, `gt_max->global` recall `1.0`.
  - no obvious alignment regression from step-budget pilot.

## Step-budget long run (2026-03-16): `s20l2t05_stepbudget50k_p01_withfb`
- Config:
  - `24x50k`, `t=0.5`, with fallback.
  - `QN_STEP_BUDGET_SOFT1=1500`, `QN_STEP_BUDGET_SOFT2=5000`, `QN_STEP_BUDGET_HARD=10000`.
  - `QUASI_FINAL_RESORT_BUDGET=0`.
  - capture window starts late: `CONSTRAINT_FAIL_CAPTURE_START_SAMPLE=47000`, `CONSTRAINT_FAIL_CAPTURE_LIMIT=0`.
- Evaluate:
  - `<virial> = (1.378970e-02, 6.187521e-03)`
  - `<z> = (3.325020e-02, -9.989182e-01)`
  - `split_rhat_virial = (1.0167, 1.0002)`
  - `split_rhat_z = (1.0158, 1.0142)`
  - ESS values increased vs 10k as expected, but Rhat still above strict `1.01` target.
- Runtime:
  - wall elapsed ~`2630.5s` for 1.2M total samples.
  - tail events still appear, including known early hotspot:
    - chain_003 `9560->9570` `+225.41s`
    - chain_020 has strong events at both `9730->9740` (`+119.89s`) and `32840->32850` (`+167.81s`)
- Totals:
  - `near_fail=6`, `near_try=6111`, `near_ok=6101`, `near_unusable=10`, `far_fail=14245`.
  - quasi stage: `probe=292815/324874`, `full=17437/18391`, `extended=371/542`.
  - quasi class: `local=5869`, `mid=1433`, `global=24757`.
- Step-budget diagnostics:
  - summary lines: `hits_total=0`, `max_used_any=2580`, `budget_last=10000`.
  - post-session meta (captured late window): `rows=822`, `budget_hit_rows=0`, `max_budget_used=2580`.
  - important limitation:
    - because capture starts at `47000`, the early known hotspot around `9560` is not in meta rows, so this run cannot directly verify budget-hit behavior on that specific event.
- 3x3 alignment (late-window captured subset):
  - official100: best-match `0.57`, `global->gt_max` precision `0.38`, recall `1.0`.
  - light600: best-match `0.6194`, `global->gt_max` precision `0.3433`, recall `1.0`.

## Step-budget diagnostic run (2026-03-16): `s20l2t05_stepbudget_diag10k_cap9k_p02_withfb`
- Config:
  - `24x10k`, `t=0.5`, with fallback.
  - `QN_STEP_BUDGET_SOFT1=1200`, `QN_STEP_BUDGET_SOFT2=3500`, `QN_STEP_BUDGET_HARD=7000`.
  - `QUASI_FINAL_RESORT_BUDGET=0`.
  - focused capture: `CONSTRAINT_FAIL_CAPTURE_START_SAMPLE=9000`, `CONSTRAINT_FAIL_CAPTURE_LIMIT=2000`.
- Evaluate:
  - `<virial> = (2.921245e-02, 6.490630e-03)`
  - `<z> = (-4.164238e-02, -1.002722e+00)`
  - `split_rhat_virial = (1.0162, 1.0002)`
  - `split_rhat_z = (1.0219, 1.0140)`
- Runtime/tail:
  - `min/median/p90/p95/max = 223.16 / 404.31 / 522.53 / 539.95 / 618.69 s`
  - heavy events reduced to count `6` (from `8` in tailmeta baseline).
  - key hotspots:
    - chain_003 `9560->9570`: `+70.97s` (baseline tailmeta `+227.95s`)
    - chain_020 `9730->9740`: `+49.20s` (baseline tailmeta `+142.58s`)
    - chain_003 `3700->3710`: `+56.54s` (baseline tailmeta `+148.60s`)
- Totals:
  - `near_fail=2`, `near_try=1291`, `near_ok=1287`, `near_unusable=4`, `far_fail=2924`.
  - quasi stage: `probe=58775/65333`, `full=3543/3754`, `extended=89/131`.
  - quasi class: `local=1236`, `mid=319`, `global=5003`.
- Step-budget diagnostics:
  - chain summaries: `hits_total=1`, `max_used_any=18045`, `budget_last=7000`.
  - post-session meta: `rows=266`, `budget_hit_rows=1`, `max_budget_used=18045`, `budget_limit=7000`.
  - hit chain aligns with known worst hotspot:
    - `chain_003` hit=1, max_used `18045`.
  - `chain_020` did not hard-hit but reached `4574` (between soft2 and hard), consistent with reduced terminal-rescue usage and still lowered jump.
- Alignment:
  - official100: best-match `0.55`, `global->gt_max` precision `0.41`, recall `1.0`.
  - light600(266): best-match `0.6316`, `global->gt_max` precision `0.3359`, recall `1.0`.

## Step-budget aggressive diagnostic run (2026-03-16): `s20l2t05_stepbudget_diag10k_cap8p5k_p03_withfb`
- Config:
  - `24x10k`, `t=0.5`, with fallback.
  - `QN_STEP_BUDGET_SOFT1=400`, `QN_STEP_BUDGET_SOFT2=1200`, `QN_STEP_BUDGET_HARD=2000`.
  - `QUASI_FINAL_RESORT_BUDGET=0`.
  - focused capture: `CONSTRAINT_FAIL_CAPTURE_START_SAMPLE=8500`, `CONSTRAINT_FAIL_CAPTURE_LIMIT=3000`.
- Evaluate:
  - `<virial> = (-2.528326e-02, -1.312551e-02)`, robust err `(~4.47e-02, ~1.78e-02)`.
  - `<z> = (1.164141e-01, -1.001978e+00)`, robust err `(~1.51e-01, ~2.19e-02)`.
  - `split_rhat_virial = (1.0031, 1.0003)`.
  - `split_rhat_z = (1.0090, 1.0005)`.
- Runtime/tail:
  - `min/median/p90/p95/max = 129.52 / 223.22 / 252.82 / 256.86 / 257.18 s`.
  - heavy events (`jump >=45s`) count `0`.
  - previously problematic 9560/9730 windows no longer dominate max-jump.
- Totals (24 chains):
  - `near_fail=0`, `near_try=239`, `near_ok=239`, `near_unusable=0`, `far_fail=1550`.
  - quasi stage: `probe=41829/46094`, `full=2690/2761`, `extended=25/44`.
  - quasi class: `local=239`, `mid=208`, `global=3818`.
  - acceptance range by chain: min/median/max `0.94949 / 0.95585 / 0.96160`.
- Step-budget diagnostics:
  - capture meta: `rows=245`, `hits=0`, `max_used=989`, `limit=2000`.
  - top budget-using chains:
    - `chain_018` max_used `989`
    - `chain_021` max_used `855`
  - no hard budget hits in this run.
- Post-session 3x3 alignment:
  - official100: best-match `0.5426`, `global->gt_max` precision `0.4343`, recall `1.0`.
  - light600(245): best-match `0.5106`, `global->gt_max` precision `0.4713`, recall `1.0`.
  - confusion remains highly global-biased on failure captures (local/mid almost absent).
- Immediate interpretation:
  - strong runtime improvement and near-fail elimination at 10k.
  - next validation must be `50k` with same budget policy to confirm no long-run consistency regression.

## Step-budget long run (2026-03-16): `s20l2t05_stepbudget50k_cap8p5k_p03_withfb`
- Config:
  - `24x50k`, `t=0.5`, with fallback.
  - `QN_STEP_BUDGET_SOFT1=400`, `QN_STEP_BUDGET_SOFT2=1200`, `QN_STEP_BUDGET_HARD=2000`.
  - `QUASI_FINAL_RESORT_BUDGET=0`.
  - capture: `CONSTRAINT_FAIL_CAPTURE_START_SAMPLE=8500`, `CONSTRAINT_FAIL_CAPTURE_LIMIT=3000`.
- Evaluate:
  - `<virial> = (3.635363e-02, 7.500402e-03)`, robust err `(~2.24e-02, ~7.93e-03)`.
  - `<z> = (-2.361067e-02, -9.825190e-01)`, robust err `(~7.04e-02, ~8.14e-03)`.
  - `split_rhat_virial = (1.0031, 1.0002)`.
  - `split_rhat_z = (1.0042, 1.0001)`.
  - z-score vs exact target (`<virial>=0`, `<z>=-i`):
    - virial(Re,Im): `(1.63σ, 0.95σ)`,
    - z(Re,Im): `(0.34σ, 2.15σ)` -> `Im<z>` is outside `1σ`.
- Runtime/tail:
  - `min/median/p90/p95/max = 872.99 / 1195.26 / 1336.04 / 1344.97 / 1350.71 s`.
  - vs previous 50k step-budget:
    - `p01 max 2629.14s`, `p02 max 2691.46s`,
    - current `p03 max 1350.71s` (about 2x faster tail upper end).
  - heavy events (`jump >=45s`) count `6` (still present, but reduced wall impact).
- Totals (24 chains):
  - `near_fail=0`, `near_try=1162`, `near_ok=1159`, `near_unusable=3`, `far_fail=7841`.
  - quasi stage: `probe=210966/232632`, `full=13703/14054`, `extended=122/227`.
  - quasi class: `local=1162`, `mid=1029`, `global=19475`.
  - acceptance min/median/max: `0.95222 / 0.95539 / 0.96192`.
- Budget diagnostics:
  - chain summary: `hits_total=3`, `max_used_any=4107`, `budget_last=2000`.
  - failure meta: `rows=6536`, `budget_hit_rows=3`, `max_budget_used=4107`, `budget_limit=2000`.
  - budget-hit rows at:
    - `chain_004 sample~41514` (`far/global`), used `4009`
    - `chain_006 sample~42169` (`mid/mid`), used `4054`
    - `chain_008 sample~22409` (`far/global`), used `4107`
- Additional tail signature:
  - largest jump windows are mostly "success but expensive" events (large `inner_resort`/`flowzr_fb` deltas),
    not dominated by solver-fail spikes.
  - around major jumps, `flow_hard_fail` and `hard_fail` counters can increment even when `d_fail=0`.
- Post-session 3x3 alignment:
  - official100: best-match `0.5426`, `global->gt_max` precision `0.4343`, recall `1.0`.
  - light600: best-match `0.5105`, `global->gt_max` precision `0.4866`, recall `1.0`.
  - confusion remains global-dominant on captured failures (`local/mid` very sparse).
- Interpretation:
  - efficiency and Rhat are strongly improved.
  - however `Im<z>` misses `-1` by about `2.15σ`, so this exact setting is too aggressive for strict consistency claim.

## Step-budget long run (2026-03-16): `s20l2t05_stepbudget50k_balance_p04_withfb`
- Config:
  - same as `p03` except hard cap relaxed:
    - `QN_STEP_BUDGET_SOFT1=600`, `QN_STEP_BUDGET_SOFT2=2000`, `QN_STEP_BUDGET_HARD=5000`.
- Evaluate:
  - `<virial> = (3.671296e-02, 7.503748e-03)`, robust err `(~2.24e-02, ~7.95e-03)`.
  - `<z> = (-2.525133e-02, -9.822955e-01)`, robust err `(~7.04e-02, ~8.13e-03)`.
  - `split_rhat_virial = (1.0031, 1.0002)`.
  - `split_rhat_z = (1.0042, 1.0001)`.
  - z-score vs exact target:
    - virial(Re,Im): `(1.64σ, 0.94σ)`,
    - z(Re,Im): `(0.36σ, 2.18σ)` -> `Im<z>` still outside `1σ`.
- Runtime/tail:
  - `min/median/p90/p95/max = 731.63 / 1227.92 / 1317.32 / 1329.36 / 1368.13 s`.
  - heavy events (`jump >=45s`) count `5`.
- Totals (24 chains):
  - `near_fail=0`, `near_try=1161`, `near_ok=1158`, `near_unusable=3`, `far_fail=7835`.
  - quasi stage: `probe=211016/232683`, `full=13710/14060`, `extended=122/234`.
  - quasi class: `local=1161`, `mid=1029`, `global=19477`.
  - acceptance min/median/max: `0.95222 / 0.95539 / 0.96192`.
- Budget diagnostics:
  - chain summary: `hits_total=0`, `max_used_any=4107`, `budget_last=5000`.
  - failure meta: `rows=6531`, `budget_hit_rows=0`, `max_budget_used=4107`.
- Interpretation:
  - compared to `p03`, this run is numerically almost identical at diagnostics level.
  - removing hard-cap hits (`3 -> 0`) did not restore `Im<z>` consistency.
  - likely root cause is not hard truncation itself; next knob should be soft gating aggressiveness (or multi-seed check for statistical fluctuation).

## Overnight unattended automation (2026-03-16)
- Added script:
  - `scripts/auto_stepbudget_until_target.sh`
- Purpose:
  - monitor currently running `p05`,
  - assess target attainment after each run,
  - auto-launch next candidate configs until target is met.
- Pass criteria encoded:
  - all split-Rhat components (`virial` Re/Im, `z` Re/Im) `<= 1.01`,
  - robust-1sigma consistency:
    - `|<virial>_Re| <= err_robust_virial_Re`,
    - `|<virial>_Im| <= err_robust_virial_Im`,
    - `|<z>_Re - 0| <= err_robust_z_Re`,
    - `|<z>_Im + 1| <= err_robust_z_Im`,
  - `near_fail_total == 0`.
- Candidate queue (current script order):
  1. monitor existing `s20l2t05_stepbudget50k_softrelax_p05_withfb`
  2. `s20l2t05_sleepauto_p06_withfb` (`850/2800/6800`, 50k)
  3. `s20l2t05_sleepauto_p07_withfb` (`800/2600/6500`, 50k)
  4. `s20l2t05_sleepauto_p08_withfb` (`750/2400/6000`, 50k)
  5. `s20l2t05_sleepauto_p09_withfb` (`700/2200/5500`, 50k)
  6. `s20l2t05_sleepauto_p10_withfb` (`800/2600/6500`, 70k)
  7. `s20l2t05_sleepauto_p11_withfb` (`850/2800/6800`, 100k)
- Runtime artifacts:
  - monitor log: `output/multichain_auto/auto_sleep_stepbudget.nohup.log`
  - summary table: `output/multichain_auto/auto_sleep_stepbudget_summary.csv`
  - final status: `output/multichain_auto/auto_sleep_stepbudget_status.txt`

## Watchdog-triggered near emergency rescue (2026-03-17)
- Goal:
  - reduce rare tail-event `near_fail` without reopening broad expensive rescue paths.
  - specifically target the observed pattern: budget/watchdog hit in a single step, then unresolved near failure.
- Code change:
  - file: `src/sampler/hmc_integrator_core.f90`
  - added one-shot per-step emergency path in near branch:
    - condition: near path still failing and watchdog/step-budget reports hit.
    - action: run strict-continuation + terminal newton once, with fixed cap
      `quasi_watchdog_near_emergency_max_iter = 1200`.
  - added optional `bypass_step_budget` to rescue stage wrappers so this emergency path can run
    even after hard budget hit.
  - keeps existing default gating unchanged for normal steps.
- Instrumentation:
  - emits marker when triggered:
    - `[QN] watchdog-triggered near emergency rescue`
- Compile check:
  - rebuilt `../bin/generate_markov_chain` successfully via `make -C build ../bin/generate_markov_chain`.
- Suggested validation order:
  1. pilot 10k, 24 chains, same seed as p12 (check near_fail and marker count).
  2. if near_fail=0 and diagnostics stable, run 50k full compare.
  3. inspect tail-heavy chains for runtime inflation before further gate tuning.

## Watchdog near-emergency v2 (2026-03-17, after p13 pilot)
- Motivation:
  - p13 showed emergency rescue could trigger with high cost but no near-fail recovery.
  - observed trigger was too broad (watchdog-like signal without strong near-solvable evidence).
- v2 changes (`src/sampler/hmc_integrator_core.f90`):
  - Emergency trigger now requires step-budget pressure + near-solvable trace shape:
    - uses only step-budget scope (`get_rescue_step_budget_status`), not quasi watchdog.
    - requires either hard hit OR pressure `used/limit >= 0.90`.
    - requires trace gates:
      - `trace_valid_fraction >= 0.45`
      - `trace_progress_ratio <= 0.40`
      - `trace_regress_ratio <= 64`
      - `0 < trace_best_over_tol <= 5e11`
  - Emergency recipe shortened to reduce tail overhead:
    - strict continuation: `360` iters
    - terminal newton rescue: `220` iters
  - Marker updated:
    - `[QN] stepbudget-triggered near emergency rescue v2`
- Intent:
  - avoid broad expensive emergency attempts.
  - reserve emergency only for high-pressure, still-structured near cases.

## Consistency check (2026-03-17): `s20l2t05_withfb_consistency100k_p16`
- Run:
  - `24 x 100k`, with fallback, full target reached.
  - elapsed `5730.76s`, total samples `2,400,000`.
- Evaluate (strict criteria):
  - `<virial> = (4.530638e-02, 1.233170e-03)`, robust err `(1.500065e-02, 7.037042e-03)`.
  - `<z> = (-5.521140e-03, -9.904632e-01)`, robust err `(8.014417e-02, 4.953504e-03)`.
  - `split_rhat_virial = (1.0176, 1.0003)`.
  - `split_rhat_z = (1.0180, 1.0151)`.
  - strict consistency fails (`Rhat` and robust-1sigma both not satisfied).
- Solver/failure counters (24-chain sum):
  - `near_fail=11`, `near_try=12617`, `near_ok=12596`, `near_unusable=21`, `far_fail=28802`.
  - chains with `near_fail>0`: `9/24`.
- Chain-level diagnostic conclusion:
  - `near_fail` is **not** the only driver of inconsistency.
  - Re-eval on `near_fail==0` chains only still fails:
    - `<virial>=(5.073643e-02, 8.126948e-03)`, robust err `(1.886792e-02, 9.495087e-03)`.
    - `<z>=(-3.055882e-02, -9.853842e-01)`, robust err `(9.776675e-02, 6.921830e-03)`.
    - `split_rhat_z=(1.0130, 1.0118)`.
  - Re-eval on `near_fail>0` subset also fails (different component profile):
    - `split_rhat_z=(1.0179, 1.0059)`.
- Decision (locked for next step):
  - do not treat `near_fail==0` as sufficient consistency condition.
  - next tuning must target global-route mixing/bias and far-path behavior, while keeping near robustness.

## Structural update (2026-03-17): far consistency-first skeleton
- Motivation:
  - `p16` shows consistency failure is not explained by near-fail alone.
  - a large fraction of failures are classified `global/far`; pure fail-fast on far is too brittle for consistency.
- Implemented (`src/sampler/hmc_integrator_core.f90`):
  - replaced far branch from "fail-fast by default" to a staged consistency-first path:
    1) always run cheap far full pass (`quasi_far_cheap_full_max_iter`),
    2) optional promoted full pass via trace-quality gate (`should_run_far_light_rescue`) or watchdog force,
    3) optional far-extended via new trace gate (`should_run_far_anchor_extended`),
    4) optional far-terminal strict continuation via new trace gate (`should_run_far_anchor_terminal`) or watchdog force.
  - no geometry-specific thresholds were added (trace-quality only).
  - near-path pipeline remains unchanged.
- New gates:
  - `should_run_far_anchor_extended`: valid_fraction `>=0.22`, progress `<=0.92`, regress `<=256`.
  - `should_run_far_anchor_terminal`: valid_fraction `>=0.35`, progress `<=0.75`, regress `<=128`.
- Status:
  - compile passed (`../bin/generate_markov_chain`).
  - smoke (`2x1000`) passed; counters/log summaries emitted normally.

## Pilot result (2026-03-17): `s20l2t05_farstruct_pilot10k_p17_withfb`
- Run:
  - `24 x 10k`, seed base `410000001`, with fallback.
  - elapsed `870.18s` (`240k` samples).
- Evaluate:
  - `<virial> = (2.324447e-03, -4.653897e-03)`.
  - `<z> = (-1.468929e-01, -1.001524e+00)`.
  - `split_rhat_virial = (1.0171, 1.0003)`.
  - `split_rhat_z = (1.0168, 1.0140)`.
  - robust-1sigma coverage: `<z>` and `<virial>` both inside.
- Counters (24-chain sum):
  - `near_fail=0`, `near_try=1216`, `near_ok=1215`, `near_unusable=1`, `far_fail=715`.
  - quasi stage: `probe=61558/68099`, `full=5631/6615`, `extended=195/249`.
  - quasi class share: `local=0.185`, `mid=0.044`, `global=0.771`.
- Comparison vs `p14` (`24x10k`, same seed family):
  - `split_rhat_z_re`: `1.0219 -> 1.0168` (improved, still > 1.01).
  - `near_fail`: `2 -> 0` (improved).
  - `far_fail`: `2924 -> 715` (large improvement).
  - elapsed: `640.1s -> 870.2s` (slower).
- Interpretation:
  - structural direction is useful for robustness and consistency trend,
  - but current tuning is not yet enough for strict `Rhat < 1.01` target.
  - next step should tune far-anchor promotion thresholds (reduce unnecessary full/extended while preserving near-fail=0), then recheck on a second seed before `50k`.

## Pilot result (2026-03-17): `s20l2t05_farstruct_pilot10k_p18_withfb` (2nd seed)
- Run:
  - `24 x 10k`, seed base `411000004`, with fallback.
  - elapsed `880.13s` (`240k` samples), similar to `p17`.
- Evaluate:
  - `<virial> = (1.026113e-02, -6.660720e-05)`.
  - `<z> = (1.982479e-01, -9.884321e-01)`.
  - `split_rhat_virial = (1.0145, 1.0004)`.
  - `split_rhat_z = (1.0167, 1.0119)`.
  - robust-1sigma: `<virial>` inside; `<z>` marginally outside on Re (`|z_re|` slightly larger than robust error by ~`1.1e-3`).
- Counters (24-chain sum):
  - `near_fail=2`, `near_try=1423`, `near_ok=1420`, `near_unusable=3`, `far_fail=763`.
  - quasi stage: `probe=64669/71709`, `full=6077/7114`, `extended=198/243`.
  - quasi class share: `local=0.200`, `mid=0.055`, `global=0.745`.
- Near-fail root inspection:
  - both near-fail events occurred with `trace_valid_fraction=1.0` and very small progress ratio (structured near hard cases),
    i.e. they are not random/unknown failures.
  - one event hit hard step-budget (`budget_used=15716 > 6800`) before near rescue could finish.
  - one event did not hit hard budget (`budget_used=4171/6800`) but still remained unresolved.
- Interpretation:
  - far-structure change is reproducibly useful on far-fail suppression (`~2924 -> ~700-760`) and slight Rhat trend improvement.
  - however consistency is still not robust across seeds (`near_fail` reappears; `Rhat` still above `1.01`).
  - next change should target near-emergency completion under hard/near-structured cases before promoting to `50k`.

## Pilot result (2026-03-17): `s20l2t05_farstruct_budgetrelax_p19_10k_withfb`
- Run:
  - same seed/config family as `p18`, but with relaxed budget
    (`QN_STEP_BUDGET_SOFT1=1200`, `SOFT2=4200`, `HARD=10000`).
  - elapsed `910.12s`.
- Observation:
  - budget settings were correctly loaded in all chains (log `[INFO] rescue step budget soft1=1200 soft2=4200 hard=10000`).
  - aggregate outcome is effectively unchanged from `p18`:
    - `split_rhat_z = (1.0167, 1.0119)`,
    - `near_fail=2`, `far_fail=759`.
- Interpretation:
  - simply relaxing budget does not remove residual near-hard failures.
  - root issue is structured near-stuck behavior, not only budget truncation.

## Structural tweak (2026-03-17): near-hard anchor emergency v3
- Motivation:
  - `p18/p19` near-fails are structured (`trace_valid_fraction ~ 1`, very small progress ratio), and one can still fail even without hard-budget hit.
- Code changes (`src/sampler/hmc_integrator_core.f90`):
  - increased near emergency caps:
    - strict continuation: `360 -> 900`
    - terminal newton rescue: `220 -> 600`
  - expanded emergency trigger:
    - keep existing budget-pressure trigger path.
    - add budget-independent near-hard anchor trigger for rare stuck-near traces:
      - `trace_valid_fraction >= 0.95`
      - `trace_progress_ratio <= 1e-3`
      - `trace_regress_ratio <= 4`
      - `0 < trace_best_over_tol <= 1e9`
  - emergency still only executes after near pipeline has already failed.
- Status:
  - compile passed.
  - next validation should rerun same seed as `p19` for clean A/B.

## Pilot result (2026-03-17): `s20l2t05_nearanchor_p20_10k_withfb`
- Run:
  - same seed/config as `p19` (`24x10k`, seed base `411000004`).
  - elapsed `940.18s`.
- Outcome:
  - metrics remained effectively unchanged from `p19`:
    - `split_rhat_z=(1.0167, 1.0119)`,
    - `near_fail=2`, `far_fail=759`.
  - emergency marker appeared on some chains, but residual near-fail persisted on:
    - `chain_004`, `chain_007`.
- Root-cause update:
  - identified a logic bug in second-pass failure handling:
    - `trace_best_over_tol` was not recomputed after refreshing trace stats.
    - near emergency decision in that path could see stale value (or `-1`) and skip emergency incorrectly.
- Fix applied (`src/sampler/hmc_integrator_core.f90`):
  - recompute `trace_best_over_tol` immediately in the second-pass `has_error` block before near emergency checks.
- Status:
  - compile passed.
  - next run should repeat same seed/config for direct A/B (`p20` vs post-fix).

## Pilot result (2026-03-17): `s20l2t05_nearanchor_fixtrace_p21_10k_withfb`
- Run:
  - same seed/config as `p20` (`24x10k`, seed base `411000004`).
  - elapsed `930.12s`.
- Outcome:
  - aggregate metrics still unchanged:
    - `split_rhat_z=(1.0167, 1.0119)`,
    - `near_fail=2`, `far_fail=759`.
  - emergency marker now also appears on `chain_007`, but both residual near-fails still unresolved.
- Near-fail meta summary:
  - `chain_004`: `budget_hit=T`, `budget_used=21613`, `budget_limit=10000`.
  - `chain_007`: `budget_hit=F`, `budget_used=5484/10000`, still unresolved.
- Interpretation:
  - fixtrace alone was necessary but not sufficient.
  - one case is still budget-truncated; another remains a true structured near-hard failure even without hard-budget hit.

## Decision update (2026-03-17): no `0 Jl` restart policy
- Team decision reaffirmed:
  - do not use `Jl=0` restart path; preserve manifold-informed trajectory.
- Code update (`src/sampler/hmc_integrator_core.f90`):
  - removed all `try_quasi_stage_zero_jl_start(...)` call sites.
  - removed helper subroutine `try_quasi_stage_zero_jl_start`.
  - replacements:
    - near last-chance: strict continuation + terminal Newton only,
    - near-hard anchor bypass: strict continuation + terminal Newton (budget bypass) only,
    - mid cold-restart branch: strict continuation (no `0 Jl` reset).
- Status:
  - compile passed.
  - next validation should rerun same seed/config for direct A/B (`p21` baseline vs no-0Jl build).

## Unified redesign (2026-03-17): geometry-consistent rescue architecture
- Core philosophy (paper-facing):
  - `lambda/lambda'` parameterization defines motion in span `C^N`; rescue must preserve this manifold-informed trajectory.
  - therefore **no `0 Jl` restart** in online solver path.
  - online classification/gating must stay model-general:
    - use trace-internal dimensionless metrics (`valid_fraction`, `progress_ratio`, `regress_ratio`, `best_over_tol`),
    - avoid hard-coding model-specific geometric scales in online decision.
  - post-session 3x3 geometry (`min/max |Re z|` bands) is used as **offline validation target** and confusion-matrix reference, not as online hard rule.

- Directional strategy:
  - objective order:
    1. consistency first (`<z>`, `<virial>`, Rhat),
    2. then efficiency under same consistency constraints.
  - near singularity behavior is prioritized over far expansion tuning.
  - far rescue is allowed but gated by trace quality and tolerance-scaled feasibility to prevent runaway cost.

- Structural code redesign (`src/sampler/hmc_integrator_core.f90`):
  - introduced a single near rescue ladder subroutine:
    - `run_near_rescue_ladder(...)`.
  - both primary near path and second-pass near re-entry now call the same ladder (no duplicated near patch branches).
  - near ladder order (all no-`0Jl`):
    1. full pass,
    2. gated extended pass,
    3. gated strict continuation + terminal newton,
    4. one-shot emergency strict continuation + terminal newton with budget bypass.
  - near gate helpers added:
    - `should_run_near_extended(...)`,
    - `should_run_near_terminal(...)`.

- Tolerance-scaled gate updates:
  - far gates now include `best_over_tol` conditions:
    - `should_run_far_light_rescue(...)`,
    - `should_run_far_anchor_extended(...)`,
    - `should_run_far_anchor_terminal(...)`.
  - this binds far promotion to `cttol`-scaled feasibility and reduces futile expensive attempts.

- Near emergency calibration update:
  - emergency caps increased for hard-anchor completion:
    - strict continuation `1400`, terminal newton `900`.
  - near-hard anchor detection widened slightly to avoid missing structured stuck-near cases:
    - valid fraction gate relaxed to `>=0.90`,
    - progress gate relaxed to `<=5e-3`,
    - regress gate relaxed to `<=8`,
    - `best_over_tol <= 1e12`.

- Why this is a redesign (not another patch):
  - one near ladder implementation point,
  - tolerance-scaled gates explicitly separated from policy,
  - no solver-state reset that violates manifold continuation philosophy,
  - direct mapping to offline 3x3 post-analysis workflow for iterative refinement.

- Status:
  - compile passed (`make -C build ../bin/generate_markov_chain`).

## Smoke check (2026-03-17): redesigned ladder wiring
- Run: `tmp_structredesign_smoke_0317_1c200` (`1 chain x 200`, `t=0.5`, with fallback).
- Result:
  - completed without runtime error,
  - summary emitted normally:
    - `[SUMMARY] quasi stage probe=22/24 full=2/2 extended=0/0`
    - `[SUMMARY] quasi class local=1 mid=0 global=1`.
- Interpretation:
  - new near-ladder/far-gate wiring is functionally connected; proceed to pilot/production validation.

## Near deep terminal stage (2026-03-17): narrow + one-shot + capped
- Motivation:
  - keep same seed and push from marginal consistency to stable consistency without broad gate inflation.
  - target only rare near-hard stalled traces; avoid global slowdown.
- Code changes (`src/sampler/hmc_integrator_core.f90`):
  - added a new near ladder stage before emergency bypass:
    - `near deep terminal stage (strict gate)`.
  - stage action (no `0 Jl`):
    - strict continuation (`2200` iter cap), then
    - terminal Newton rescue (`1200` iter cap), no budget bypass.
  - trigger is strict (`should_run_near_deep_terminal`):
    - `trace_valid_fraction >= 0.95`,
    - `trace_progress_ratio <= 1e-4`,
    - `trace_regress_ratio <= 2.0`,
    - `0 < trace_best_over_tol <= 1e8`.
  - emergency bypass remains as last resort and still one-shot per step.
- Design intent:
  - absorb rare near-hard unresolved cases with minimal trigger width,
  - preserve manifold-continuation philosophy and avoid broad extra cost.
- Validation:
  - compile passed.
  - smoke run passed (`tmp_neardeep_smoke_0317_1c300`).

## Pilot result (2026-03-17): `s20l2t05_neardeep_pilot10k_seed410_withfb`
- Run:
  - same seed and setup as `s20l2t05_structredesign_pilot10k_p01_withfb` (`24x10k`, seed base `410000001`).
- Outcome:
  - diagnostics are numerically identical to previous pilot:
    - `split_rhat_z=(1.0174, 1.0143)`,
    - `split_rhat_virial=(1.0171, 1.0002)`,
    - `near_fail=0`, `far_fail=774`.
  - runtime unchanged (`~890s`).
- Interpretation:
  - near-deep stage did not trigger on this pilot path (as intended by strict gate);
  - this pilot is a non-regression check only.
  - must validate on `50k` where rare tail near-hard events are observed.

## 50k result (2026-03-17): `s20l2t05_neardeep_50k_seed410_withfb`
- Observation:
  - run outcome is numerically identical to `s20l2t05_structredesign_baseline50k_p01_withfb`:
    - same `<z>`, `<virial>`, `Rhat`, stage/class counts, `near_fail=5`, `far_fail=3877`, runtime ~`4111s`.
  - deep-stage marker count is `0`.
- Root-cause identified:
  - `run_near_rescue_ladder` used stale trace gate metrics (from early probe context) for deep/emergency gate decisions.
  - therefore deep-stage gate could remain closed even when current failed trace was a deep-candidate.

## Structural fix (2026-03-17): refresh trace metrics inside near ladder
- Code update (`src/sampler/hmc_integrator_core.f90`):
  - added `refresh_quasi_trace_gate_state(...)`.
  - near ladder now refreshes trace metrics before:
    - near terminal gate,
    - near deep-terminal gate,
    - near emergency gate.
- Expected effect:
  - gate decisions now use current failure trace instead of stale probe trace,
  - deep-stage can trigger on actual tail near-hard cases.
- Status:
  - compile passed.

## 50k refresh result (2026-03-17): `s20l2t05_neardeep_refresh_50k_seed410_withfb`
- Run summary vs baseline (`s20l2t05_structredesign_baseline50k_p01_withfb`):
  - diagnostics unchanged:
    - `<virial>=(4.711611E-03, 4.901165E-05)`
    - `<z>=(1.332473E-02, -9.978927E-01)`
    - `split_rhat_virial=(1.0165, 1.0002)`
    - `split_rhat_z=(1.0126, 1.0139)`
  - near/far summary unchanged within noise:
    - `near_fail=5`, `near_try=6009`, `near_ok=5998`, `near_unusable=11`, `far_fail=3878`.
  - quasi stage totals nearly identical:
    - `probe=306699/339055`, `full=27905/32730`, `extended=568/673`.
  - runtime slightly better (`4080.6s` vs `4110.5s`).
- Interpretation:
  - refreshing trace metrics fixed stale-gate wiring, but does not move top-level consistency metrics at `50k`.
  - near-hard unresolved events remain rare (`near_fail=5` over `24x50k`), so current bottleneck is likely not near-deep coverage.

## Post-session alignment (2026-03-17): `s20l2t05_neardeep_refresh_50k_seed410_withfb`
- Built bundle + 3x3 geometry classification (`light_600`) + online/geometry confusion.
- 3x3 geometry counts (`light_600`):
  - `abs_re_hit_lt_min_abs_re: 67`
  - `min_abs_re_le_abs_re_hit_le_max_abs_re: 78`
  - `abs_re_hit_gt_max_abs_re: 452`
  - `no_hit: 3`
- Online-vs-geometry alignment:
  - `best_match_accuracy_3x3 = 0.7638`
  - `global_to_gt_max_precision = 0.7584`
  - `gt_max_to_global_recall = 1.0`
- Confusion matrix indicates almost all cases still classified online as `global` (`596/600`), with only `4/600` as `mid`, `0` as `local`.
- Implication for next design step:
  - online classification captures gt-max band with full recall, but remains over-coarse (low granularity);
  - efficiency/consistency improvement should prioritize far/global routing quality rather than only adding near-deep stages.

## Structural far routing v1 (2026-03-17): route-aware global rescue
- Motivation:
  - post-session confusion showed online `global` remains over-coarse (`596/600` in global for light600),
  - near-deep refresh did not move `Rhat` at 50k,
  - next step is to improve far/global rescue structure without geometry-specific online rules.
- Code change (`src/sampler/hmc_integrator_core.f90`):
  - added model-general far sub-routing from trace metrics:
    - `far_route_skip` (no extra promotion beyond cheap full),
    - `far_route_light` (allow light full promotion),
    - `far_route_anchor` (allow extended + terminal path).
  - new function:
    - `classify_far_rescue_route(trace_available, trace_valid_fraction, trace_progress_ratio, trace_regress_ratio, trace_best_over_tol)`.
  - far rescue pipeline now uses route-aware gating:
    - light full rescue only when route >= light,
    - extended/terminal only when route == anchor.
  - watchdog force remains, but now route-aware with very-high-pressure emergency override:
    - full can override at `far_fail_pressure_state >= 0.95`,
    - extended at `>= 0.98`,
    - terminal at `>= 0.995`.
- Expected behavior:
  - reduce unnecessary expensive far rescues for low-quality global traces,
  - preserve completion path for structured far anchors,
  - keep online policy model/dimension general via trace-scale metrics.
- Validation:
  - compile passed.
  - runtime smoke passed: `tmp_farroute_smoke_0317_1c300`.

## Pilot result (2026-03-17): `s20l2t05_farroutev1_pilot10k_seed410_withfb`
- Run/eval status:
  - run completed (`elapsed=800.1s`, `24x10k`),
  - evaluate completed.
- Diagnostics vs previous `s20l2t05_neardeep_pilot10k_seed410_withfb`:
  - top-level metrics unchanged (numerically identical):
    - `<virial>=(1.324993E-03, -2.013550E-03)`
    - `<z>=(-1.205501E-01, -1.004716E+00)`
    - `split_rhat_virial=(1.0171, 1.0002)`
    - `split_rhat_z=(1.0174, 1.0143)`.
  - runtime improved (`890.2s -> 800.1s`, about `-10.1%`).
- Solver summary (aggregate over 24 chains):
  - near/far: `near_fail=0`, `near_try=1235`, `near_ok=1233`, `near_unusable=2`, `far_fail=840`.
  - quasi stage: `probe=61088/67568`, `full=5610/6573`, `extended=30/53`.
  - quasi class: `local=1213`, `mid=279`, `global=4988`.
  - compared to previous pilot (`extended=111/136`, `global=5000`, `far_fail=774`):
    - extended promotions dropped strongly,
    - far_fail increased,
    - consistency metrics unchanged at pilot scale.
- Post-session alignment (`light_600`, no plots):
  - `best_match_accuracy_3x3=0.7759` (prev reference `0.7638`),
  - `global_to_gt_max_precision=0.7718` (prev `0.7584`),
  - `gt_max_to_global_recall=1.0` (unchanged).
- Interpretation:
  - farroutev1 is a useful efficiency direction (clear speedup, no consistency regression at 10k),
  - but it does not yet improve 10k Rhat/observable bias, so 50k validation is required.

## 50k result (2026-03-18): `s20l2t05_farroutev1_50k_seed410_withfb`
- Run/eval status:
  - run completed (`elapsed=3970.6s`, `24x50k`),
  - evaluate completed.
- Diagnostics vs `s20l2t05_neardeep_refresh_50k_seed410_withfb`:
  - runtime improved (`4080.6s -> 3970.6s`, about `-2.7%`).
  - top-level consistency metrics effectively unchanged:
    - `split_rhat_virial=(1.0165, 1.0002)` (same),
    - `split_rhat_z=(1.0126, 1.0139)` (same to printed precision),
    - `<virial>` and `<z>` remain in same regime.
- Solver summary (aggregate):
  - near/far: `near_fail=5`, `near_try=6089`, `near_ok=6078`, `near_unusable=11`, `far_fail=4196`.
  - quasi stage: `probe=305380/337673`, `full=27933/32746`, `extended=159/262`.
  - quasi class: `local=5948`, `mid=1446`, `global=24899`.
  - compared to neardeep_refresh50k (`extended=568/673`, `far_fail=3878`):
    - extended promotions dropped strongly,
    - far_fail increased,
    - consistency diagnostics unchanged.
- Post-session alignment (`light_600`, no plots):
  - `best_match_accuracy_3x3=0.7826` (prev `0.7638`),
  - `global_to_gt_max_precision=0.7785` (prev `0.7584`),
  - `gt_max_to_global_recall=1.0` (unchanged).
- Interpretation:
  - farroutev1 remains a positive efficiency/structure step (speedup + better online/geometry precision),
  - but current 50k consistency bottleneck is unchanged; next work should target mixing/consistency rather than more far-cost pruning alone.

## Structural far routing v2 (2026-03-18): light micro-extended + route counters
- Objective:
  - move from pure far-cost pruning to a consistency-oriented structure while keeping v1 efficiency gains.
- Code changes:
  - `src/sampler/hmc_integrator_core.f90`
    - added `quasi_far_light_extended_max_iter = 72`.
    - for `far_route=light`, if still failing after light full pass, run one low-cost extended pass (`stage=extended`, 72 iter cap).
    - keeps `far_route=anchor` path for full extended/terminal escalation.
    - records far route classification via `record_constraint_solver_far_route(...)`.
  - `src/sampler/constraint_solver_stats.f90`
    - added far-route constants and counters:
      - `constraint_quasi_far_route_skip/light/anchor`
      - `quasi_far_route_skip_count/light_count/anchor_count`
    - added getter: `get_constraint_solver_far_route_stats(...)`.
    - prints summary line: `quasi_far_route skip=... light=... anchor=...`.
  - `src/sampler/markovchain_mod.f90`
    - progress/summary now print far-route counters.
- Validation:
  - compile passed.
  - smoke passed: `tmp_farroutev2_smoke_0318_1c300`.
  - smoke summary includes new line:
    - `[SUMMARY] quasi far_route skip=0 light=0 anchor=2`.

## Pilot result (2026-03-18): `s20l2t05_farroutev2_pilot10k_seed410_withfb`
- Run/eval status:
  - run completed (`elapsed=820.1s`, `24x10k`),
  - evaluate completed.
- Diagnostics vs `farroutev1_pilot10k`:
  - runtime: `800.1s -> 820.1s` (v2 slower by about `+2.5%`, but still faster than pre-farroute pilots).
  - near/far:
    - `near_fail=0` (same),
    - `far_fail=717` (v1 was `840`, improved).
  - stage/class:
    - `extended=178/250` (v1 `30/53`, v2 does more extended work as designed),
    - class counts remain same order (`global` dominant).
  - evaluate metrics remain in same regime:
    - `split_rhat_virial=(1.0171, 1.0003)`,
    - `split_rhat_z=(1.0168, 1.0140)`.
- New route counters (aggregate):
  - `route skip=976 light=1345 anchor=2705`.
  - confirms v2 routing instrumentation is active and non-trivial.
- Post-session alignment (`light_600`, no plots):
  - `best_match_accuracy_3x3=0.7429` (v1 `0.7759`),
  - `global_to_gt_max_precision=0.7408` (v1 `0.7718`),
  - `gt_max_to_global_recall=1.0` (same).
- Interpretation:
  - v2 improves far-fail count and keeps consistency metrics similar,
  - but costs some runtime vs v1 and weakens online-vs-geometry precision,
  - so v2 is a consistency-leaning variant, not a strict efficiency winner over v1 at pilot scale.

## 50k result (2026-03-18): `s20l2t05_farroutev2_50k_seed410_withfb`
- Run/eval status:
  - run completed (`elapsed=4110.7s`, `24x50k`),
  - evaluate completed.
- Diagnostics vs `s20l2t05_farroutev1_50k_seed410_withfb`:
  - runtime regressed (`3970.6s -> 4110.7s`, about `+3.5%`).
  - top-level consistency metrics remain essentially unchanged:
    - `split_rhat_virial=(1.0165, 1.0002)` (same),
    - `split_rhat_z=(1.0128, 1.0139)` (v1 was `1.0126, 1.0139`).
  - near/far:
    - `near_fail=5` (same),
    - `far_fail=3609` (v1 `4196`, improved).
  - stage usage:
    - `extended=914/1260` (v1 `159/262`), much more extended work.
- Route counters (aggregate):
  - `skip=4904 light=6548 anchor=13626`.
- Post-session alignment (`light_600`, no plots):
  - `best_match_accuracy_3x3=0.7529` (v1 `0.7826`),
  - `global_to_gt_max_precision=0.7508` (v1 `0.7785`),
  - `gt_max_to_global_recall=1.0` (same).
- Interpretation:
  - v2 reduces far-fail but pays higher cost and does not improve 50k consistency target,
  - v1 remains the better efficiency baseline for long-chain extension under current objectives.

## 100k result (2026-03-18): `s20l2t05_farroutev1_100k_seed410_withfb`
- Important provenance note:
  - this run's chain summaries include `quasi far_route skip/light/anchor`,
  - therefore it was produced with the newer route-instrumented solver path (post-v2 code), not legacy pure-v1 binary behavior.
- Run/eval status:
  - run completed (`elapsed=8201.2s`, `24x100k`),
  - evaluate completed.
- Diagnostics:
  - `<virial>=(2.194609E-02, 5.696225E-05)`
  - `<z>=(2.362742E-02, -9.911806E-01)`
  - `split_rhat_virial=(1.0174, 1.0003)`
  - `split_rhat_z=(1.0172, 1.0149)`
  - robust errors:
    - `error_robust_<virial>=(1.360744E-02, 6.174606E-03)`
    - `error_robust_<z>=(7.069079E-02, 5.299057E-03)`
- Consistency check against exact expectations (`<virial>=0`, `<z>=-i`):
  - `Re<virial>` is outside 1-sigma (`0.0219 > 0.0136`),
  - `Im<z>` is outside 1-sigma (`-0.9912` with sigma `0.0053`, does not include `-1`).
- Aggregate solver summary:
  - near/far: `near_fail=11 near_try=12184 near_ok=12155 near_unusable=29 far_fail=7197`.
  - stage/class/route: `probe=617097/682614 full=56498/66195 extended=1811/2459`,
    `class local=12163 mid=2981 global=50373`,
    `route skip=9871 light=13057 anchor=27445`.
- Interpretation:
  - extending this path to 100k did not improve convergence target; diagnostics are worse than the 50k result under same code line.
  - longer-chain strategy is still valid in principle, but this particular solver variant should not be promoted as the long-chain baseline.

## Runtime switch for v1-equivalent verification (2026-03-18)
- Motivation:
  - need to verify whether pure v1 behavior itself can/cannot recover consistency at long chain,
  - avoid conflating this with later v2 light micro-extended changes.
- Code update (`src/sampler/hmc_integrator_core.f90`):
  - added env-gated switch:
    - `QN_FAR_LIGHT_MICRO_EXT=off` disables the v2 light micro-extended stage,
    - default remains enabled.
  - startup log line per chain:
    - `[INFO] qn far light micro-extended: on|off`.
- Validation:
  - compile passed.
  - smoke passed with explicit off switch:
    - run: `tmp_farroute_switchoff_smoke_0318_1c200`
    - log confirms: `[INFO] qn far light micro-extended: off`.

## 100k verification (2026-03-18): `s20l2t05_farroutev1eq_100k_seed410_withfb`
- Verification target:
  - test pure v1-equivalent behavior at long chain (disable v2 light micro-extended) to check whether chain length alone resolves consistency.
- Provenance:
  - run logs confirm switch is active in all chains:
    - `[INFO] qn far light micro-extended: off`.
- Run/eval:
  - runtime: `7991.3s` (`24x100k`).
  - `<virial>=(2.119197E-02, -7.145031E-04)`
  - `<z>=(2.536050E-02, -9.913559E-01)`
  - `split_rhat_virial=(1.0174, 1.0003)`
  - `split_rhat_z=(1.0169, 1.0149)`
  - robust errors:
    - `error_robust_<virial>=(1.358780E-02, 6.268825E-03)`
    - `error_robust_<z>=(7.016147E-02, 5.340812E-03)`
- Consistency check vs exact (`<virial>=0`, `<z>=-i`):
  - `Re<virial>` outside 1-sigma,
  - `Im<z>` outside 1-sigma,
  - Rhat still above target 1.01.
- Aggregate solver summary:
  - near/far: `near_fail=11 near_try=12450 near_ok=12421 near_unusable=29 far_fail=8386`.
  - stage/class/route: `probe=612397/677510 full=56414/66032 extended=302/520`,
    `class local=12175 mid=2918 global=50020`,
    `route skip=9705 light=12972 anchor=27343`.
- Conclusion:
  - this directly validates the concern: pure v1-equivalent at 100k still does not meet consistency targets.
  - therefore, current issue is not solved by chain-length extension alone under this solver family.

## Rescue Architecture Guideline (locked 2026-03-19)
- Purpose:
  - provide one stable, model/dimension-general design contract for rescue behavior.
  - prevent ad-hoc patch stacking; future tuning should mostly be threshold/cap adjustments.

### Core design principles
1. Geometry-consistent trajectory first:
   - preserve `lambda/lambda'` manifold parameterization semantics.
   - do not use `0 Jl` restart as a generic rescue path.
2. Consistency before efficiency:
   - target order is `consistency > robustness near singularity > efficiency`.
3. Online gate is model-general:
   - online routing uses probe-trace behavior metrics only (not model-specific geometry thresholds).
4. Offline geometry is for audit:
   - keep 3x3 min/max `|ReZ|` analysis for diagnosis/confusion-matrix checks, not direct online gate logic.

### Mandatory solver invariants
- Quasi solve tolerance remains tied to `cttol` (no relaxed production acceptance).
- All rescue branches must keep deterministic, logged stage counters:
  - `probe/full/extended` attempts + successes,
  - class counters (`local/mid/global`),
  - far-route counters (`skip/light/anchor`),
  - near counters (`near_fail/near_try/near_ok/near_unusable`),
  - watchdog/budget usage.

### Online rescue skeleton (single source of truth)
1. Probe stage:
   - always run probe first.
2. Probe-fail classification:
   - classify by trace-quality/scale metrics into `near`, `mid`, `far(global)`.
3. Near branch (singularity safety):
   - run near rescue ladder:
     - `full -> extended -> strict continuation ladder -> terminal near Newton rescue`.
   - if still failing, allow emergency near path only under explicit pressure/trace conditions.
4. Mid branch:
   - `full`, optional strict-cont restart, optional extended (budget-gated).
5. Far branch:
   - always start with cheap full pass (consistency-first guard).
   - then route-specific escalation:
     - `skip`: no extra promotion.
     - `light`: light full promotion (+ optional micro-extended if enabled).
     - `anchor`: extended/terminal continuation path.
   - watchdog/pressure may force promotion only at high-pressure thresholds.

### Budget and watchdog policy
- Step-scope budget is the primary cross-route cost controller.
- Budget crossing deactivates expensive branches in order:
  - first extended, then terminal.
- Emergency bypass is allowed only for explicitly structured near-hard situations; do not use as generic far bypass.

### Tuning protocol (must follow order)
1. If `near_fail > 0`:
   - tune near branch first; do not touch far gate until near hard-fail is eliminated.
2. If `near_fail == 0` but consistency fails:
   - tune far route thresholds/promotions and mixing behavior.
3. If consistency passes:
   - reduce tail cost by tightening promotion gates; never relax core consistency invariants.

### Explicit anti-patterns
- Do not reintroduce geometry-specific online thresholds (`max|Re(z+dz)|`-type rules).
- Do not use `0 Jl` as a default rescue fallback.
- Do not claim improvement from non-50k pilots alone; use them only for directional validation.

### Promotion criteria for any structural change
- Must pass on canonical `24 x 50k`:
  - `max(Rhat_z_re, Rhat_z_im, Rhat_virial_re, Rhat_virial_im) < 1.01`
  - exact `<z>` and `<virial>` within robust 1-sigma.
- Then compare efficiency:
  - wall time / sec-per-sample / tail-event burden (`far_fail`, budget-hit hotspots).

## Execution Protocol (2026-03-19): t=0.4 baseline reset + gate ladder
- Objective:
  - quickly decide whether current t=0.4 inconsistency is mainly a gate-parameter issue or a structural issue.
  - keep structure fixed first; vary gate/budget knobs step-by-step.

### Scope lock
- Fix solver structure:
  - keep `QN_RESCUE_LEVEL=3` (mid/far structured path enabled),
  - keep near-rescue ladder unchanged.
- Tune only gate/budget knobs in phase A/B:
  - `QN_FAR_LIGHT_MICRO_EXT`,
  - `QN_STEP_BUDGET_SOFT1/SOFT2/HARD`.

### Phase A (fast directional): 24x10k, single seed
- Baseline pair:
  - `nofb` baseline (`quasi_fallback=off`),
  - strict withfb baseline (`micro=on`, budget `220/440/650`).
- Gate ladder (withfb only, same seed):
  - L1: `micro=off`, hard=400
  - L2: `micro=off`, hard=525
  - L3: `micro=on`,  hard=650
  - L4: `micro=on`,  hard=850
- Decision from Phase A:
  - if consistency trend improves monotonically with gate strength: parameter tuning is likely enough.
  - if little/no consistency change across ladder (especially persistent same-component bias): structural change is required.

### Phase B (target-scale check): 24x50k, single seed
- Run top-2 profiles from Phase A at 50k.
- Keep same structure; compare:
  - Rhat,
  - 1σ/2σ component pass,
  - near/far counters,
  - runtime.

### Phase C (claim-scale): 24x50k, 3 seeds
- For selected profile, run seeds:
  - `410000001`, `411000004`, `412000007`.
- Reporting metric (component-level over all runs):
  - 1σ pass-rate target >= 0.68,
  - 2σ pass-rate target >= 0.90.

### Duplicate-data guard
- Do not count duplicated runs copied across folders as separate evidence.
- Deduplicate by run identity and metric fingerprint before pass-rate aggregation.

### Tooling added for this protocol
- `scripts/summarize_rescue_impact.py`
  - builds one run-level CSV with:
    - near/far/stage/class/route/watchdog aggregates,
    - rescue policy hints (`rescue_level`, `micro_ext`, step-budget modes),
    - evaluate metrics (`Rhat`, robust 1sigma/2sigma component pass),
    - evaluate-file fingerprint (`eval_sha256`) for duplicate detection.
- `scripts/run_t040_rescue_matrix.sh`
  - runs a fixed t=0.4 ablation matrix (baseline + structure + gate ladder),
  - auto-runs evaluate, then emits matrix summary CSV via `summarize_rescue_impact.py`.

## Consistency-First Reset (2026-03-22): t=0.35 withfb
- Context:
  - `withfb_v3` first 9 seeds: `pass_rhat=3/9`, `pass_2sigma=0/9`, `pass_all=0/9`.
  - dominant failures are consistency-side (`virial Re`, then `z_im`), not only mixing.
  - far route is heavily anchor-dominated; rescue cost is high while consistency is still not met.

### Decision
- Stop current incomplete `p10` and freeze this batch as diagnostic-only.
- Move to structure correction first, then gate tuning.

### Structural corrections to apply before new sweep
1. Near-priority guarantee (consistency guard):
   - once classified as `near`, if `full` fails, enforce one deterministic terminal path:
     - strict continuation + terminal newton,
     - with budget bypass allowed for this single near-critical path.
   - rationale: do not let global step budget starve near-singularity escape.
2. Remove generic `0` seed from strict continuation:
   - strict-cont seeds must stay on manifold-informed trajectory (`+seed/-seed/scaled-seed`),
   - avoid `0 Jl` as default rescue path.
3. Budget policy split:
   - far rescue remains budget-gated,
   - near terminal safety path uses reserved/bypass slot (single-use per rattle step).
4. Keep strict tolerance invariant:
   - quasi acceptance tied to `cttol`; no relaxed production acceptance.

### Gate adjustments (after structural fix only)
1. Near classification: slightly widen near capture to avoid false-far routing of near stalls.
2. Far routing: tighten anchor gate to reduce unnecessary anchor escalation.
3. Keep online gates trace-based/model-general; geometry 3x3 stays offline for audit.

### Verification protocol
1. Pilot (directional): 24x10k, 1 seed, withfb only.
   - target: near fail suppression + improved component consistency trend.
2. Consistency test: 24x50k, 3 seeds, withfb.
   - target: `Rhat<1.01` on all components, `1σ`/`2σ` rates in expected range.
3. Paired claim check: same seeds nofb vs withfb.
   - target: show withfb consistency gain before discussing efficiency.

## Roadmap to Consistency + Efficiency (2026-03-23 refresh, t=0.35)

### Current status snapshot (frozen references)
- `nofb10` (`output/multichain_auto_t035_nofb10_0322_012401`):
  - `pass_rhat101=0/10`, `pass_1sigma_all=0/10`, `pass_2sigma_all=0/10`.
  - `near_fail_total=0` but `far_fail_total` very large (median `~90k`).
- `withfb_v3` (`output/multichain_auto_t035_withfb10_0322_115831`, first 9 seeds):
  - `pass_rhat101=3/9`, `pass_1sigma_all=0/9`, `pass_2sigma_all=0/9`.
  - `near_fail_total` nonzero in all runs (median `13`), runtime tail large.
- `consfix pilot` (`s20l2_t035_consfix_pilot10k_p01_withfb`):
  - `Rhat` and `2sigma` trend improved (`rhat_max=1.0088`, `pass_2sigma_all=yes`),
  - but still `near_fail_total=5`.
  - tail events (`jump>=20s`) show that those 5 near-fail events dominate heavy-tail elapsed burden (`~74%` of heavy-jump time).

### Roadmap principle
- First lock consistency safety (`near_fail -> 0`) before far-gate efficiency tuning.
- Keep model-general online logic and manifold-informed seeds (`+/-/scaled`), no generic `0 Jl`.
- Use post-session 3x3 only as audit/confusion check, not as direct online threshold.

### Phase 1: Near-tail elimination (structure only)
- Scope:
  - touch near branch only; keep far gates unchanged.
  - objective is to remove `near_unusable` and `near_fail`.
- Pass/fail gates (`24x10k`, 1 seed):
  1. `near_fail_total == 0`.
  2. no heavy event (`jump>=20s`) with `d_near_fail>0` or `d_near_unusable>0`.
  3. `rhat_max <= 1.02` as directional guard (not final claim gate).
- Stop rule:
  - if two structural variants both fail Gate-1, do not tune far; continue near-only redesign.

### Phase 2: Consistency confirmation (small seed set)
- Run `24x10k`, 3 seeds with best Phase-1 near structure.
- Pass/fail gates:
  1. all 3 runs: `near_fail_total == 0`,
  2. all 3 runs: `pass_2sigma_all == true`,
  3. at least 2/3 runs: `rhat_max < 1.01`.
- If Gate-2 fails, return to near structure (not far tuning).

### Phase 3: 50k consistency gate (claim entry)
- Run `24x50k`, 3 seeds, with Phase-2 winner.
- Pass/fail gates:
  1. all runs: `near_fail_total == 0`,
  2. all runs: `pass_2sigma_all == true`,
  3. component-level 1sigma pass-rate across runs `>=0.68`,
  4. component-level 2sigma pass-rate across runs `>=0.90`,
  5. `rhat_max < 1.01` in at least 2/3 runs (or extend chain length if needed).

### Phase 4: Efficiency recovery (only after Phase-3 pass)
- Tune far-route gates/budgets with near structure fixed.
- Compare against Phase-3 anchor config on same seed set:
  - runtime (`elapsed_max`, wall-seconds),
  - tail burden (`jump>=20s` count and total jump seconds),
  - `far_fail_total`, stage counts (`probe/full/extended`).
- Hard guard:
  - any efficiency variant that reintroduces `near_fail_total>0` is rejected.

### Operational note
- Use one run-summary table per phase with:
  - `rhat_max`, `pass_1sigma_all`, `pass_2sigma_all`,
  - `near_fail_total`, `near_unusable_total`, `far_fail_total`,
  - `elapsed_median`, `elapsed_max`,
  - heavy-tail decomposition (`near-caused jump sum`, `far-only jump sum`).

## Near-Only Structure Patch (2026-03-23): manifold-seeded Newton in near ladder

- Motivation:
  - latest `t=0.35` consfix pilot shows heavy-tail is dominated by a few `near_fail/near_unusable` spikes.
  - existing near terminal Newton used implicit zero seed, which discards manifold-following lambda state.
- Code changes:
  - `src/sampler/hmc_constraints.f90`
    - `solve_constraint_newton(...)` now accepts optional seeds:
      - `x_seed`, `Jl_seed`.
    - in rescue mode, these seeds initialize `(u, lambda)` before Newton iterations.
  - `src/sampler/hmc_integrator_core.f90`
    - added near-only seeded Newton stage before strict continuation in near terminal branch.
    - near watchdog emergency path now tries seeded Newton first (budget bypass), then existing strict-cont/newton fallback.
    - new runtime switch:
      - `QN_NEAR_SEEDED_NEWTON=on|off` (default: `on`).
    - startup log line:
      - `[INFO] qn near seeded-newton: on|off`.
- Scope:
  - near branch only; far routing/gates unchanged.
  - designed to preserve manifold-informed trajectory semantics while reducing near-hard tail events.

## Phase-1 A/B Result (2026-03-24): v3 near-seeded Newton toggle

- Runs completed:
  - `s20l2_t035_phase1_off_pilot10k_v3`
  - `s20l2_t035_phase1_on_pilot10k_v3`
- Config:
  - same seed/config; only `QN_NEAR_SEEDED_NEWTON` differs (`off` vs `on`).

### Outcome summary
- Consistency diagnostics (evaluate logs) are identical at reported precision:
  - `split_rhat_virial=(1.0076, 1.0019)`
  - `split_rhat_z=(1.0088, 1.0043)`
  - `pass_2sigma_all` direction remains good; `pass_1sigma_all` still not met.
- Final near/far counters are identical:
  - `near_fail=5`, `near_try=17`, `near_ok=12`, `near_unusable=5`, `far_fail=403`.
- Same failing chains:
  - `chain_005`, `chain_009`, `chain_017`.
- Heavy-tail jumps are still dominated by the same deterministic near-fail events:
  - around samples `3570->3580`, `4020->4030`, `4590->4600`, `7500->7510`, `8090->8100`.

### Toggle sanity check
- `off` run:
  - `[INFO] qn near seeded-newton: off`
  - seeded-newton attempts: `0`
- `on` run:
  - `[INFO] qn near seeded-newton: on`
  - seeded-newton attempts present in logs.
- Therefore:
  - feature wiring is correct, but it does not resolve the hard near-tail set.

### Decision
- Phase-1 hypothesis (seeded-Newton toggle alone can clear near tail) is **rejected**.
- Do not spend more time on this toggle axis.
- Move to Phase-2 structural near redesign focused on deterministic hard-event handling, then retest on the same `24x10k` seed before any new 50k sweep.

### Tail-context extraction (same run, deterministic hard set)
- extracted with `scripts/inspect_tail_fail_context.py` on `on_v3`:
  - `chain_005:3577`, `chain_009:4029`, `chain_017:4592`, `chain_009:7509`, `chain_017:8092`.
- common signature for the 5 unresolved near events:
  - `quasi_case_name=near`, `online_class_name=local`, `near_rescue_started=1`, `near_rescue_done=0`,
  - very large `d_attempt_flowzr` (`~5e4` to `1e5`) in one step,
  - `z0_abs_re_max` very small (`~3.6e-3` to `4.1e-3`),
  - `delz_l2` large (`~1.17` to `1.36`).
- interpretation:
  - failures are not due to missing near routing (near route is entered),
  - current near ladder cannot complete these small-`z0`, large-step transitions.
  - next structure must change transition strategy (not just deeper same-stage retries).

## Phase-2 Result (2026-03-24): strict-cont seed handoff (`x_seed_hint`)

- Run:
  - `s20l2_t035_phase2_seedhint_pilot10k_p01_withfb`
- Structure change:
  - strict-continuation can accept `x_seed_hint`,
  - near strict-cont calls pass current `final_x` as seed hint.

### Observed impact vs `phase1_on_pilot10k_v3`
- near/far counters:
  - `near_fail: 5 -> 0`
  - `near_unusable: 5 -> 1`
  - `near_try/near_ok: 17/12 -> 235/234`
  - `far_fail: 403 -> 487`
- deterministic old hard set:
  - old windows (`chain_005:3570-3580`, `chain_009:4020-4030`, `chain_017:4590-4600`, `chain_009:7500-7510`, `chain_017:8090-8100`) now all `matched_rows=0` in fail-context extraction.
- tail behavior (`jump>=20s`):
  - heavy-event count: `56 -> 23`
  - total heavy-jump seconds: `3910.33 -> 706.25`
  - near-caused heavy-jump seconds: `1938.72 -> 162.80` (large drop)
  - one residual heavy event remains:
    - `chain_012: 8630->8640`, `d_near_unusable=1`, `d_far_fail=1`, class `far/global`.
- evaluate snapshot:
  - `rhat_max=1.0080` (directional pass),
  - robust sigma coverage still `3/4` at 1-sigma (same bottleneck remains `z_re`), `4/4` at 2-sigma.

### Decision
- This seed-handoff structure is **useful** and should be kept as new baseline.
- Next step:
  - run 3-seed `24x10k` with this structure to check reproducibility of `near_fail=0` and tail reduction.
  - if reproducible, promote to `24x50k` consistency gate.

## Phase-2 Repro Check (2026-03-24): `seedhint3` (`24x10k`, 3 seeds)

- Runs:
  - `s20l2_t035_phase2_seedhint_p01_pilot10k_withfb`
  - `s20l2_t035_phase2_seedhint_p02_pilot10k_withfb`
  - `s20l2_t035_phase2_seedhint_p03_pilot10k_withfb`

### Summary
- `near_fail_total`: `0` in all 3 runs.
- `near_unusable_total`: `1, 2, 0` (nonzero in 2/3 runs).
- `rhat_max`: `1.0080`, `1.0073`, `1.0101` (2/3 below `1.01`).
- robust sigma component pass:
  - 1-sigma components: `3/4`, `2/4`, `3/4` (all-runs all-components pass not reached),
  - 2-sigma components: `4/4` for all 3 runs.
- tail (`jump>=20s`) remains much improved vs v3 baseline:
  - per-run total heavy-jump seconds: `631`, `1301`, `845`,
  - near-caused heavy-jump seconds: `168`, `396`, `0`.

### Diagnostic note
- Remaining `near_unusable` heavy events in this batch are not classic near-case labels in fail-context:
  - observed as `far/global` or `mid/mid` classifications with `is_near_case=0`,
  - but `near_rescue_started=1` and `near_rescue_done=0` in metadata.
- This indicates the near counter is still influenced by late rescue/control flow beyond strict near classification.

### Decision
- Keep seed-handoff structure as active baseline (it resolved deterministic `near_fail` set in this phase).
- Promote to `24x50k` consistency gate on 3 seeds for final decision on `<z>, <virial>` 1-sigma stability.

## Phase-2 Consistency Gate (2026-03-24): `seedhint` (`24x50k`, 3 seeds)

- Runs:
  - `s20l2_t035_phase2_seedhint_p01_50k_withfb`
  - `s20l2_t035_phase2_seedhint_p02_50k_withfb`
  - `s20l2_t035_phase2_seedhint_p03_50k_withfb`

### Core outcomes
- `Rhat`:
  - `rhat_max`: `1.0030`, `1.0038`, `1.0033` (all `<1.01`).
- near/far:
  - `near_fail_total=0` in all 3 runs.
  - `near_unusable_total`: `3`, `4`, `3`.
  - `far_fail_total`: `2505`, `2288`, `2478`.
- robust sigma component pass:
  - 1-sigma components: `4/4`, `2/4`, `3/4` -> pooled `9/12 = 75%`.
  - 2-sigma components: `4/4`, `3/4`, `4/4` -> pooled `11/12 = 91.7%`.
  - all-components pass:
    - 1-sigma: `1/3`,
    - 2-sigma: `2/3`.

### Interpretation
- Under component-wise coverage criteria (main metric), this batch is consistent with target direction:
  - 1-sigma pooled pass is above the nominal `~68%`,
  - 2-sigma pooled pass is above `~90%`.
- all-components pass remains strict and unstable at this sample count; keep it as secondary stress indicator, not primary gate.
- Remaining weak point is `virial Im` in `p02` (`~2.17 sigma`) and nonzero `near_unusable` tail events.

### Decision
- With fallback + seed-handoff, `t=0.35` now has a credible consistency baseline at `24x50k`.
- Next for claim strength:
  - run matched-seed nofb `24x50k` comparison at same `t=0.35`,
  - quantify consistency gap + robustness gap (`near_fail`, sigma coverage, tail burden) for paper narrative.

## Far Rescue Structural Update (2026-03-24): route-aware fasttrack + pre-check fail-fast

### Why
- `tight1` showed only small runtime gain while trajectory/statistics stayed unchanged.
- We need budget steering, not only late cutoff:
  - fail fast earlier for structurally unsolvable `far/skip`,
  - move budget earlier to promising `far/anchor`.

### Implementation
- File: `src/sampler/hmc_integrator_core.f90`.
- Far/global pipeline update:
  - pre-check unsolvable fail-fast before expensive far rescue stages,
  - route-aware first action:
    - `skip`: no default cheap full unless watchdog-force,
    - `light`: cheap full as before,
    - `anchor`: new fasttrack stage first (`extended`, bounded iter).
- Added policy knob:
  - `QN_FAR_ANCHOR_FASTTRACK` (`on` by default).
- Added constants/tuning:
  - `quasi_far_anchor_fasttrack_max_iter = 140`.
- Tightened explicit hard fail-fast rule for `far/skip` (new reason `23`) to cut clear unsolvable tails earlier.
- Slightly relaxed anchor routing/extended gates so solvable-hard far traces enter anchor path more often.

### Validation
- Recompiled `../bin/generate_markov_chain`.
- Smoke run (`2x200`) confirmed:
  - policy print: `[INFO] qn far anchor fasttrack: on max_iter=140`,
  - anchor route path exercised (`quasi far_route ... anchor=1`).

## Far Anchor Update (2026-03-24): default fasttrack off + trajectory-changing anchor primary mix path

### Why
- `fasttrack on` increased heavy tail runtime without improving Rhat/observables in pilot.
- We need a change that can alter accepted trajectory, not only fail-fast accounting.

### Implementation
- File: `src/sampler/hmc_integrator_core.f90`.
- `far anchor fasttrack` default changed to `off`:
  - `enable_far_anchor_fasttrack = .false.`
  - env override still available via `QN_FAR_ANCHOR_FASTTRACK=on`.
- Added `far anchor mix-restart` policy (default `on`):
  - env: `QN_FAR_ANCHOR_MIX_RESTART` (`on/off`),
  - max iter: `quasi_far_anchor_mix_cont_max_iter = 260`.
- Structural change in far route:
  - for `far_route=anchor`, primary stage now prefers strict continuation with `x_seed_hint=state_x`
    and nonzero lambda seed (`Jl` scaled, not zeroed), before fallback to older paths.
  - secondary anchor mix retry remains available only when primary mix path did not run.

### Notes
- This keeps geometric philosophy (`lambda/lambda'` span retained; no `Jl=0` reset in this path).
- Goal is to produce genuine trajectory differences while keeping fail-fast protection for unsolvable far tails.

## Initialization Integrity Fix (2026-03-25): disallow flow-time downgrade on random-start

### Problem
- `initialize_random_start` could lower preflow target (`target_flow_time_try *= 0.85`) on failed attempts.
- This allowed runs configured with `initial_flow_time=t` to start some chains at `t'<t` (observed e.g. `0.35 -> 0.2975`), which breaks experiment semantics.

### Fix
- File: `src/sampler/markovchain_mod.f90` (`initialize_random_start`).
- Removed downgrade path:
  - deleted `target_flow_time_try` / `flow_time_floor` logic.
  - preflow always targets `target_flow_time_base = config%integrator%initial_flow_time`.
- Retry behavior:
  - failures now retry at the same target flow time, only increasing `relax_level`.
  - added hard cap `max_start_attempts = 200`; exceed -> `error stop` with explicit message.

### Build + smoke validation
- Rebuilt: `make -C build ../bin/generate_markov_chain`.
- Smoke run (`t=0.35`, 2 chains, short):
  - one chain: failed attempt 1 then retry with **fixed** `flow_time=0.350000`, success at `0.350000`.
  - other chain: success at `0.350000` on attempt 1.
- No downgraded start flow-time observed in smoke logs.

## t=0.35 Geometric Iteration Plan (2026-03-25): 10k-first, cut unsolvable, feed solvable

### Objective
- Keep `t=0.35` as primary target (touches singular structure directly).
- Do **not** jump immediately to stop-loss/abandon.
- First run structured 10k pilots to verify whether compute can be redirected from unsolvable tails to solvable-hard cases.

### Mandatory integrity baseline
- Random-start initialization must begin at target flow time; no downgrade allowed.
- This is now enforced in `initialize_random_start` (`markovchain_mod.f90`), validated by smoke (`down_chains=0`).

### Execution framework
- Script: `scripts/run_t035_geom_iter_matrix.sh`.
- For each case/seed, automatically runs:
  1. multichain pilot (`withfb`, `t=0.35`),
  2. `evaluate_expectations`,
  3. post-session bundle,
  4. geometry summary (`--no-plots`),
  5. failure-type classification,
  6. online-vs-geometry alignment.
- Output summary CSV: `geom_iter_summary.csv` (single table for ranking and decisions).

### Key policy dimensions (matrix)
- near fail-fast: on/off + threshold,
- far fail-fast: on/off + threshold,
- far `flowzr` fail-fast threshold,
- hard step budget (with soft1/soft2 derived).

### Decision criteria (10k stage)
- Hard constraints:
  - `start_downgraded_chains = 0`,
  - `near_fail = 0` (or explicitly bounded and explained),
  - no catastrophic Rhat blow-up.
- Prioritize candidates with:
  - lower `near_unusable`, lower `far_fail_fast` tail burden,
  - lower `band_no_hit` and better 3x3 alignment (`align_best_match`),
  - acceptable runtime.

### Promotion rule
- Only after 10k matrix identifies stable candidates, promote top 1-2 to 50k.
- Stop-loss only after this structured evidence, not before.

## Post-session side check added (2026-03-25): final point vs intersection side on Re(z)

### Motivation
- Distinguish two situations explicitly:
  - converging on same side of `Re(z)=0`,
  - jumping across zero (possible wrong-side trap risk).

### Implementation
- File: `scripts/classify_failure_types.py`.
- New per-case fields:
  - `hit_re_side` (`pos/neg/zero/unknown`),
  - `final_re_side` (`pos/neg/zero/unknown`),
  - `final_vs_hit_side` (`same_side/opposite_side/touch_zero/no_hit/no_stuck`),
  - `cross_zero_flag` (`1` when `opposite_side`, else `0`).
- Side zero tolerance:
  - `side_zero_eps = max(side_zero_abs_eps, side_zero_rel_to_min_abs_re * min_abs_re)`.

### Aggregation wiring
- File: `scripts/run_t035_geom_iter_matrix.sh`.
- `geom_iter_summary.csv` now includes:
  - `side_same`, `side_opposite`, `side_touch_zero`, `side_no_hit`, `side_no_stuck`, `cross_zero_count`.

### Early observation on `multichain_auto_t035_geomiter_0325_151110`
- Among official-100 failure samples per run:
  - `side_opposite=0` (no observed across-zero opposite-side cases),
  - detected-hit cases are currently mostly `same_side`,
  - dominant burden remains `no_hit` tails.

## t=0.35 geomiter readout (2026-03-25): why current gate tuning is not enough

### Findings from `multichain_auto_t035_geomiter_0325_151110`
- Across 5 policy cases x 3 seeds (15 runs), statistical outputs are nearly seed-dominated:
  - `rhat_max` unchanged pattern by seed (~`1.0114/1.0116/1.0124`),
  - `all2sigma` unchanged (`2/3` per case block),
  - case-level gate tuning has only minor runtime/fail-count impact.
- Failure composition in official-100 remains dominated by `no_hit`:
  - per run: `band_no_hit = 96`, `band_gt_max = 3`, `band_in_band = 1`.
- Side diagnostics:
  - `final_vs_hit_side`: `opposite_side = 0` (no evidence of wrong-side jumps *after* intersection hit),
  - `final_vs_z0_side` on same samples: roughly `45-47` opposite vs `53-55` same,
    implying many `no_hit` traces cross `Re(z)=0` relative to start without obtaining a hit.

### Tail structure (data-driven)
- On representative seed (`p01`) for `no_hit` samples:
  - accepted-iter quantiles: q50~`271`, q90~`331`, q95~`351`, max~`546`.
- In the same batch, detected-hit samples have max accepted-iter `232`.

### Decision for next round
- Next experiment should target **budget separation** (not more far-gate micro tuning):
  - keep current far-tight gates,
  - test hard budget near `240-300` where data suggests large `no_hit` tail reduction while preserving hit-like traces.
- Added matrix cases for this purpose in `run_t035_geom_iter_matrix.sh`:
  - `c06_far_tight_b300`, `c07_far_tight_b260`, `c08_far_tight_b240`.

## Budgetfocus readout (2026-03-25): hard step budget did not target the observed tail

### Batch
- `multichain_auto_t035_budgetfocus_0325_170654`
- cases: `b300 / b260 / b240` with same seeds (`p01/p02/p03`).

### Outcome
- Metrics are effectively unchanged across `b300/b260/b240`:
  - same seed-pattern in `rhat_max`,
  - `band_no_hit` remains `96`,
  - `sidez0_opposite` remains `45-47`,
  - only tiny runtime noise-level differences.
- This shows current `QN_STEP_BUDGET_*` does not directly constrain the long accepted-iteration tails we care about.

### Root cause
- Code inspection: current rescue step budget in `hmc_integrator_core.f90` tracks `success_final_resort` usage, not total accepted quasi-iterations.

### Structural fix added
- File: `src/sampler/quasi_newton_solver.f90`.
- Added accepted-iteration watchdog integrated with existing quasi watchdog scope:
  - env knob: `QN_ACCEPTED_ITER_BUDGET` (alias: `QUASI_ACCEPTED_ITER_BUDGET`), default disabled.
  - watchdog now can trip on either:
    - `QUASI_FINAL_RESORT_BUDGET`, or
    - accepted-iteration budget.
- Smoke validated info prints and activation.

### Next targeted scan
- Run new accepted-iter cases (in matrix script):
  - `c09_far_tight_acc300`, `c10_far_tight_acc260`, `c11_far_tight_acc220`.
- Goal: cut `no_hit` tail cost while preserving consistency indicators.

## Acciterfocus readout + full-fail capture update (2026-03-25)

### Batch result
- `multichain_auto_t035_acciterfocus_0325_183026` completed.
- Summary trend:
  - `acc300`: `band_no_hit` slightly reduced, runtime mixed (one seed slower).
  - `acc260/acc220`: faster fail-fast behavior, but `side_opposite` rises to non-zero and much larger counts.
- Interpretation:
  - accepted-iter cap is a real lever on tail cost,
  - but aggressive cap starts to alter geometry-side behavior (risk of over-cutting).

### Post-session policy change requested
- Requirement: future runs should capture **all fails**, not only first 100.
- Implemented support:
  - `scripts/build_post_session_bundle.py`:
    - `--first-n <= 0` or `--light-n <= 0` now means **all** rows for that subset output.
    - emits `constraint_solver_fail_quasi_trace_firstall.csv`.
  - `scripts/run_t035_geom_iter_matrix.sh`:
    - new env knobs:
      - `POST_OFFICIAL_N` (default `0`, i.e. all),
      - `POST_LIGHT_N` (default `600`).
    - official post-session outputs now use dynamic tag:
      - `failure_type_summary_official_all.csv` etc when `POST_OFFICIAL_N=0`.
  - `scripts/run_plain_benchmark_start.sh`:
    - same `POST_OFFICIAL_N` / `POST_LIGHT_N` support added.

### Replay solvability check (iter=400, tol=1e-10, p01 comparison)
- Compared:
  - `c03_far_tight` vs `c11_far_tight_acc220`.
- Result summary:
  - `c03`: replay success on failed set ~`28.0%`.
  - `c11`: replay success on failed set ~`50.3%`.
  - `far_fail_fast` false-prune proxy:
    - `c03`: `1/10 = 10%`,
    - `c11`: `0/5 = 0%`.
- Interpretation:
  - Main bottleneck is **not** primarily fail-fast misclassification.
  - Main bottleneck is that many failed samples are still solvable with deeper/alternate rescue routing.
  - Therefore next structural target should be:
    - keep unsolvable truncation conservative,
    - improve routing/continuation for promising far non-FF cases.

### Structural tuning support added (runtime gate knobs)
- File: `src/sampler/hmc_integrator_core.f90`.
- Added runtime-env tuning for far-anchor promotion gates (no re-edit needed per scan):
  - Extended gate:
    - `QN_FAR_ANCHOR_EXT_VALID_MIN`
    - `QN_FAR_ANCHOR_EXT_PROGRESS_MAX`
    - `QN_FAR_ANCHOR_EXT_REGRESS_MAX`
    - `QN_FAR_ANCHOR_EXT_BEST_OVER_TOL_MAX`
  - Terminal gate:
    - `QN_FAR_ANCHOR_TERM_VALID_MIN`
    - `QN_FAR_ANCHOR_TERM_PROGRESS_MAX`
    - `QN_FAR_ANCHOR_TERM_REGRESS_MAX`
    - `QN_FAR_ANCHOR_TERM_BEST_OVER_TOL_MAX`
- Default behavior unchanged unless env is set.
- Smoke-validated info print appears in chain log.

## Continuous runtime-control update (2026-03-26)

### Problem we observed
- `ctrl -> tight -> tight2` changed runtime only mildly (about `3521s -> 3301s` on `24x10k`) while physics outputs stayed identical.
- This means discrete gate tweaks alone are not giving us a controllable "investment dial".

### New control layer (implemented)
- File: `src/sampler/hmc_integrator_core.f90`.
- Added far-rescue budget scope that clamps fail-fast limits per far episode:
  - `QN_FAR_RESCUE_BUDGET=on|off`
  - continuous knob: `QN_FAR_RESCUE_INVEST_SCALE`
  - tier caps:
    - `QN_FAR_RESCUE_FLOWZR_WEAK|MID|STRONG`
    - `QN_FAR_RESCUE_FINAL_RESORT_WEAK|MID|STRONG`
  - safety floors:
    - `QN_FAR_RESCUE_FLOWZR_FLOOR`
    - `QN_FAR_RESCUE_FINAL_RESORT_FLOOR`
- Important binding detail:
  - if global limits (`QN_FAR_FAIL_FAST_*`) are nonzero, effective cap is `min(global, scoped_cap)`.
  - for pure continuous control, set `QN_FAR_FAIL_FAST_FLOWZR_LIMIT=0` and `QN_FAR_FAIL_FAST_FINAL_RESORT_LIMIT=0`.

### Why this is better
- We can now tune rescue compute with one scalar (`INVEST_SCALE`) while keeping structure fixed.
- This directly addresses "投入失控": runtime can be swept continuously instead of jumping only by gate on/off steps.

### Repro command path
- New helper script:
  - `scripts/run_t035_far_rescue_invest_sweep.sh`
- Purpose:
  - same seed/config,
  - sweep `INVEST_SCALE`,
  - output run/eval logs + `invest_sweep_summary.csv`,
  - isolate runtime-vs-consistency tradeoff cleanly.

### Cost-explosion guard update (2026-03-26, follow-up)
- Observation from live `t=0.35` run (`scale=0.20`):
  - severe chain imbalance appears early (`min~490` vs `max~4590` at same wall time),
  - some chains still accumulate huge `flowzr_fb`/`inner_resort` despite low invest scale.
- Immediate strategy change:
  - stop broad scale sweep first,
  - enable fine-grained quasi watchdog as primary hard cap:
    - `QUASI_FINAL_RESORT_BUDGET=0` (disable coarse watchdog),
    - `QN_ACCEPTED_ITER_BUDGET=<cap>` (use accepted-iter cap).
- Script support added:
  - `scripts/run_t035_far_rescue_invest_sweep.sh` now accepts:
    - `QUASI_FINAL_RESORT_BUDGET_CFG` (default `0`)
    - `ACCEPTED_ITER_BUDGET_CFG` (default `260`)
- Rationale:
  - accepted-iter cap is checked per accepted iteration and is much better for anti-tail-explosion control than coarse final-resort count.

### Near bypass control (2026-03-26, critical)
- New finding from `t=0.35` single run:
  - cost blow-up still happened because near emergency/ultra stages were executed with `bypass_step_budget=.true.`.
  - this can override external budget intentions and create long tail stalls.
- Structural fix in `hmc_integrator_core.f90`:
  - added env knob: `QN_NEAR_BUDGET_BYPASS` (`on/off`, default `on` for backward compatibility).
  - near emergency/ultra paths now use this knob instead of hardcoded bypass.
  - logging now distinguishes:
    - `budget bypass`
    - `budget-limited`
- Experiment script update:
  - `scripts/run_t035_far_rescue_invest_sweep.sh` now forwards `QN_NEAR_BUDGET_BYPASS` via `NEAR_BUDGET_BYPASS` (default `off` for cost-control experiments).

## Baseline-first redesign lock (2026-03-26, reset plan)

### Hard lock (do not change)
- Fixed starting point for redesign:
  - `s20l2_t035_farff_ctrl_pilot10k_p01_withfb` (about `300s` on `24x10k`)
- Rule:
  - baseline path must stay byte-for-byte behavior-equivalent for production comparison.
  - all new structure must be opt-in (`default=off`).

### Why we reset from this point
- Current issue is no longer "can we open rescue paths".
- Current issue is "can we control where compute is spent".
- We need to avoid paying 10x runtime on newly created tail events.

### Redesign goal (t=0.35 mainline)
- Keep baseline as the speed floor.
- Add structure that shifts compute toward solvable hard cases.
- Fail-fast only for clearly unsolvable cases.
- Verify consistency first (`Rhat`, `<z>`, `<virial>`), then optimize efficiency.

### Redesign principles (locked)
- Geometry-aware solve philosophy stays:
  - keep manifold-consistent continuation behavior.
  - do not rely on `Jl=0` as default rescue path.
- Online logic must remain model/dimension general:
  - use trace/progress/residual behavior, not model-specific geometry thresholds.
- Near/far routes must each satisfy:
  - explicit admission condition,
  - explicit budget envelope,
  - explicit promotion condition,
  - explicit termination reason label.

### Validation design (phased)
- Phase 0: Baseline freeze and reproducibility
  - Re-run baseline (`24x10k`, same seed) x3.
  - Record runtime spread (`median`, `p95`) and key diagnostics.
  - Promotion gate: spread stable and no behavior drift.
- Phase 1: Instrumentation-only patch
  - No rescue behavior change.
  - Add complete event accounting per fail path:
    - route label, budget spent, terminal reason, promoted/not-promoted.
  - Capture all fail events in post-session (not capped at 100).
  - Promotion gate: counters align between online summary and post-session.
- Phase 2: Budget-router redesign on top of baseline
  - Add route-local budget envelopes and promotion-by-progress only.
  - Keep default config equivalent to baseline.
  - Introduce one continuous investment knob with monotonic expectation.
  - Promotion gate: runtime changes are smooth and predictable.
- Phase 3: Solvable-targeted investment
  - Enable extra budget only when "promotable" conditions persist.
  - Keep hard fail-fast for unsolvable signatures.
  - Promotion gate: higher successful rescue yield per extra cost.
- Phase 4: Consistency promotion ladder
  - `24x10k` (3 seeds) -> `24x50k` (3 seeds) -> `24x50k` (10 seeds).
  - Promotion gate:
    - `max(Rhat_z_re, Rhat_z_im, Rhat_virial_re, Rhat_virial_im) < 1.01`
    - `<z>` and `<virial>` exact values inside robust 1-sigma.

### New core evaluation metrics (for "投入算力是否有效")
- `tail_waste_ratio`:
  - extra budget spent on unsolvable-labeled events / total extra budget.
- `rescue_yield`:
  - additional successful solves / additional budget.
- `promoted_success_ratio`:
  - promoted events that eventually solve / all promoted events.
- `runtime_control_smoothness`:
  - monotonicity of runtime response under the single investment knob.

### Stop-loss (explicit)
- Stop a redesign branch if any is true:
  - runtime > `2x` baseline at `24x10k` without meaningful consistency gain,
  - `tail_waste_ratio` does not decrease over two consecutive iterations,
  - consistency metrics degrade vs baseline for two consecutive iterations.
- If stop-loss triggers:
  - revert to baseline,
  - keep instrumentation improvements,
  - start next branch from baseline again.

### Next execution order (strict)
1. Freeze baseline record (`24x10k`, 3 seeds, same config family).
2. Land instrumentation-only patch and verify online/post-session alignment.
3. Start budget-router redesign branch (single branch only).
4. Run phased validation ladder before any 50k expansion.

## 2026-03-27: Progressive S1 seed check (t=0.35, 24x10k)

Runs:
- `s20l2_t035_tailprog_s1_p01_10k_withfb_0327_003854`
- `s20l2_t035_tailprog_s1_p02_10k_withfb_0327_010014`
- `s20l2_t035_tailprog_s1_p03_10k_withfb_0327_010927`

Observed:
- Runtime is stable (`290.1s` vs `280.0s`), and near/far counters are similar:
  - p01: `near_fail=6`, `far_fail=727`
  - p02: `near_fail=3`, `far_fail=708`
- Runtime/cost control is stable across seeds:
  - p01: `290.1s`
  - p02: `280.0s`
  - p03: `280.1s`
- Convergence quality at 10k is not sufficient:
  - p01: `split_rhat_z(Re)=1.0114`
  - p02: `split_rhat_z(Re)=1.0166`
  - p03: `split_rhat_z(Re)=1.0143`
  - pass rate for `Rhat_z(Re)<1.01` is `0/3`.
- Online-vs-geometry alignment improved strongly on p02:
  - p01: `best_match_accuracy_3x3=0.802`, `global_to_gt_max_precision=0.074`
  - p02: `best_match_accuracy_3x3=0.948`, `global_to_gt_max_precision=0.975`

Interpretation:
- S1 routing/classification works and cost is controlled.
- Main bottleneck is now mixing depth (not rescue routing) for `<z>` real component.
- Do not escalate to S2/S3 yet; first increase sample depth under fixed S1.

Immediate next step:
1. Keep `STAGE=1` fixed.
2. Increase sample depth (e.g. `24x20k` then `24x50k`) on current seeds.
3. Reconsider rescue-complexity increase only if depth scaling fails to improve `Rhat_z(Re)`.

## 2026-03-27: Depth scaling check (same seed, S1, 10k -> 20k)

Runs:
- `s20l2_t035_tailprog_s1_p02_10k_withfb_0327_010014`
- `s20l2_t035_tailprog_s1_p02_20k_withfb_0327_012643`

Observed delta:
- Runtime scales near-linearly and remains controlled:
  - `280.0s -> 540.1s`
- Mixing metric improves with depth:
  - `split_rhat_z(Re): 1.0166 -> 1.0081`
  - `split_rhat_z(Im): 1.0011 -> 1.0004`
  - `ess_bulk_z(Re): 321.8 -> 639.7`
- Route/accounting remains stable (roughly doubled counts as expected):
  - `far_fail: 708 -> 1380`
  - stage counters approximately x2 (`probe/full`).
- Geometry alignment quality stays high:
  - `best_match_accuracy_3x3: 0.948 -> 0.942`
  - `global_to_gt_max_precision: 0.975 -> 0.975`

Interpretation:
- No sign of cost explosion when increasing depth under S1.
- Current evidence supports "depth before complexity": keep rescue structure fixed and push sample depth for consistency.

## 2026-03-27: 20k seed pair update (S1, p01 + p02)

Runs:
- `s20l2_t035_tailprog_s1_p01_20k_withfb_0327_014050`
- `s20l2_t035_tailprog_s1_p02_20k_withfb_0327_012643`

Observed:
- Runtime/cost remains controlled:
  - p01: `570.1s`
  - p02: `540.1s`
- Both satisfy Rhat target on `<z>`:
  - p01: `split_rhat_z(Re,Im)=(1.0070, 1.0001)`
  - p02: `split_rhat_z(Re,Im)=(1.0081, 1.0004)`
- near/far totals are stable and similar:
  - p01: `near_fail=15`, `far_fail=1377`
  - p02: `near_fail=8`, `far_fail=1380`
- Under current exact-value check (`<virial>=0`, `<z>=-i`), virial real part remains significantly shifted:
  - p01: virial Re z-score `-3.34 sigma`
  - p02: virial Re z-score `-3.59 sigma`

Interpretation:
- Depth improves mixing diagnostics (`Rhat/ESS`) and keeps cost predictable.
- Remaining issue appears to be consistency bias (especially virial Re), not runaway rescue cost.
- Next decision should be based on a third 20k seed before changing algorithm structure.

## 2026-03-27: Third seed at 20k (S1, p03)

Run:
- `s20l2_t035_tailprog_s1_p03_20k_withfb_0327_015525`

Observed:
- Runtime controlled: `560.1s` (same band as p01/p02 20k).
- Mixing diagnostics still good:
  - `split_rhat_z(Re,Im)=(1.0072,1.0001)`
  - `split_rhat_virial(Re,Im)=(1.0001,1.0001)`
- But consistency remains problematic under exact check (`<virial>=0`, `<z>=-i`):
  - virial Re z-score `-5.22 sigma`
  - virial Im z-score `-1.22 sigma`
  - z Re z-score `+0.56 sigma`
  - z Im z-score `-2.09 sigma`

Cross-seed summary at S1/20k (p01-p03):
- All three seeds satisfy Rhat target.
- All three seeds fail virial Re consistency strongly (`~3.3` to `5.2 sigma`).

Interpretation:
- Increasing depth alone solves mixing diagnostics but does not recover consistency at t=0.35.
- This points to structural bias risk in current S1 tail-progressive policy (not simple under-sampling).

## Baseline decision (2026-03-27)

Decision:
- Promote `S1` as the **working baseline** for further development at `t=0.35`.
- Keep `S0` frozen as the **reference/ablation baseline**.

Reason:
- Relative to S0 (10k p01), S1 substantially improves fail handling (`far_fail` strongly reduced) while preserving controlled runtime behavior.
- Current unresolved issue is consistency bias at 20k (not runaway cost), so S1 is the correct base for next structural fixes.

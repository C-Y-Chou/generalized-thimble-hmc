# DFO-LS Assist-Off Tuning Campaign

Date: 2026-05-12 JST

Status: active

## Goal

Test whether official DFO-LS parameter tuning can make the QN solver robust
enough under `INTODE_SOLVER_ASSIST_ENABLED=0`, without reintroducing solver
assist or adding external rescue logic.

This campaign is a rule-out / verify campaign.  It must answer one of:

1. verified: one or more official DFO-LS parameter settings materially improve
   assist-off QN reliability and survive chain-level holdout checks;
2. ruled out for current surface: the allowed official DFO-LS tuning surface
   does not materially recover assist-off reliability at practical cost.

## Fixed Protocol

- Remote worktree:
  `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`.
- Expected branch:
  `codex/tltm-production-comparison-official-dfols`.
- Expected commit:
  `a22de1c19633793cf9c3ff7037b7cbc399e1b568`.
- Backend:
  `QN_SOLVER_BACKEND=official_dfols`.
- Assist:
  `INTODE_SOLVER_ASSIST_ENABLED=0` for every production-like run.
- Physical point:
  `t=0.35,L=2,nstep=20`, RG on, p28, `cttol=1e-13`,
  `QN_QUASI_TOL_OVERRIDE=1e-13`.
- Methods:
  `no_fb -> nofb`, `fb_norefine -> withfb`.

Frozen 2026-05-11 outputs are assist-on/default evidence and must not be mixed
as same-protocol replicas.  They can be used only as contextual evidence for
what solver assist used to recover.

## Allowed Tuning Surface

Only official DFO-LS controls are in scope:

- `QN_OFFICIAL_DFOLS_NPT`
- `QN_OFFICIAL_DFOLS_MAXFUN`
- `QN_OFFICIAL_DFOLS_OBJFUN_HAS_NOISE`
- `QN_OFFICIAL_DFOLS_RHOBEG`
- `QN_OFFICIAL_DFOLS_RHOEND`
- `QN_OFFICIAL_DFOLS_MODEL_ABS_TOL`
- `QN_OFFICIAL_DFOLS_MODEL_REL_TOL`

Out of scope:

- enabling `INTODE_SOLVER_ASSIST_ENABLED`;
- adding external multistart, escape steps, line search, backtracking, or
  best-rescue wrappers;
- choosing parameters by final observable agreement alone.

## Primary Metrics

Primary solver-local metrics:

- TLTM residual-gated success count at `1e-13`;
- embedded-converged replay regressions;
- final residual norm distribution, especially p90/p95/max;
- DFO-LS function evaluations `nf`;
- embedded Stage3 unresolved failure count;
- runtime.

Solver-strength acceptance gate:

- At matched scale, assist-off tuned `fb_norefine` must reach the same
  unresolved-failure order as assist-on `fb_norefine`, and ideally match or beat
  the assist-on count.
- Current 32seed/50k reference: assist-on `fb_norefine` unresolved failures
  `19579`.
- The current tuned candidate `rho050_m500` has `33872`; this is improved but
  not enough to claim the solver-assist problem solved.

Primary chain acceptance metrics:

- `mean_Ohat_re`, `mean_Ohat_im`;
- `Zmean_re`, `Zmean_im` using the standard-error definition;
- paired method difference `withfb - nofb`;
- same-seed comparison against the assist-off baseline, not against assist-on
  frozen output.

Diagnostic chain metrics:

- reverse-gate reject count;
- P68/P95 quantiles.

## Baseline

Assist-off baseline at 32 seeds x 50000 cycles:

- campaign:
  `official_dfols_preredo_20260512_a22de1c_32seed_50000cyc_t035_L2_nstep20_rg_nofb_withfb`;
- nofb: `Zmean_re=5.9903`, `Zmean_im=-0.1760`, unresolved failures `265127`;
- withfb: `Zmean_re=4.9468`, `Zmean_im=1.7950`, unresolved failures `67061`;
- direct paired `withfb - nofb`: Re `-0.034698 +/- 0.017361`,
  Im `+0.013055 +/- 0.010462`.

## Test Plan

### Phase A: Current-Commit Assist-Off Attempt Capture

Run current commit with assist off and capture representative QN entries:

- scale: 10 seeds x 10000 cycles;
- methods: `no_fb` and `fb_norefine`;
- capture: up to 100 QN attempts per seed and method through
  `QN_ATTEMPT_CAPTURE_BASE_DIR`;
- output namespace:
  `output/tests/dfols_assist_off_tuning/20260512_a22de1c_phaseA_capture`.

This phase validates the test material before tuning.  It should not change
production code or source-controlled files on the remote worktree.

### Phase B: Offline Official DFO-LS Coarse Sweep

Replay captured QN attempts through official DFO-LS with only official package
knobs changed.

Coarse candidate grid:

| label | npt | maxfun | noise | rhobeg | rhoend | model.abs_tol | model.rel_tol |
|---|---:|---:|---|---:|---:|---:|---:|
| stable_gate77 | 4 | 250 | true | 0.018 | 1e-16 | 1e-30 | 0 |
| budget500 | 4 | 500 | true | 0.018 | 1e-16 | 1e-30 | 0 |
| budget1000 | 4 | 1000 | true | 0.018 | 1e-16 | 1e-30 | 0 |
| rho010_m500 | 4 | 500 | true | 0.010 | 1e-16 | 1e-30 | 0 |
| rho030_m500 | 4 | 500 | true | 0.030 | 1e-16 | 1e-30 | 0 |
| rho050_m500 | 4 | 500 | true | 0.050 | 1e-16 | 1e-30 | 0 |
| npt0_rho018_m500 | 0 | 500 | true | 0.018 | 1e-16 | 1e-30 | 0 |
| npt6_rho018_m500 | 6 | 500 | true | 0.018 | 1e-16 | 1e-30 | 0 |
| no_noise_m500 | 4 | 500 | false | 0.018 | 1e-16 | 1e-30 | 0 |
| rho050_no_noise_m500 | 4 | 500 | false | 0.050 | 1e-16 | 1e-30 | 0 |

Stop early if no candidate improves residual success or unresolved hard-tail
behavior relative to `stable_gate77` while keeping zero embedded-converged
regressions and acceptable cost.

### Phase C: Embedded Stage3 Candidate Validation

If Phase B finds candidates, run top candidates as embedded Stage3 campaigns:

- first holdout: 10 seeds x 10000 cycles, both methods, same seed set;
- keep assist off;
- record DFO-LS parameters in manifests;
- compare against the assist-off stable baseline, not against frozen assist-on.

Promotion criteria:

- lower unresolved failure count in both methods, or a strong improvement in the
  worse method with no material regression in the other;
- runtime increase acceptable for production scale;
- `mean_Ohat_re` and `mean_Ohat_im` do not move in the wrong direction on the
  same seed grid.

Reverse-gate rejects and P68/P95 are recorded as diagnostics, but they are not
blockers for this tuning campaign unless the observable means also degrade.

### Phase D: Scale Confirmation

If Phase C passes, run the best candidate at 32 seeds x 50000 cycles.  Only then
consider 32 seeds x 200000 cycles or larger production-like scale.

## Current Verdict Field

Verdict: current official DFO-LS parameter tuning improves the assist-off
solver-local tail, but `rho050_m500` has not yet solved the no-assist problem
because it has not reached assist-on failure parity at 32 seeds x 50000 cycles.

Interpretation:

- Verified: `rho050_m500` materially strengthens the `fb_norefine` QN route
  without solver assist; unresolved failures dropped by roughly half at Phase D.
- Verified: the `fb_norefine` observable means moved toward zero relative to the
  stable assist-off baseline: Re `0.0607926 -> 0.0434491`, Im
  `0.0112710 -> 0.00824623`.
- Caveat: the Re mean is still not zero (`Zmean_re=3.3284`), so this is not a
  final physics-quality production proof.
- Blocker: failures remain above the same-scale assist-on reference
  (`33872` vs `19579`).  Unless the tuned assist-off route reaches the same
  failure scale or lower, it is hard to argue that DFO-LS tuning has genuinely
  replaced solver assist.
- Diagnostics: reverse-gate rejects and P68/P95 worsened, but these are not
  blockers for this campaign unless they also degrade `mean_Ohat_re` or
  `mean_Ohat_im`.
- Action: continue focused tuning around `rho050_m500`; the next gate should
  target failure parity with assist-on while preserving mean Re/Im improvement.

## Phase Updates

### Phase A/B Readback

Job: `14984.anode01`

Output root:
`output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseAB_10s10k_c200s10_m5`

Readback:

- Stage3 capture and all coarse replay CSVs completed.
- PBS exit status was `1` because the original aggregate parser did not handle
  blank `dfols_nf` fields on residual-evaluation error rows.  A robust
  recovery aggregate wrote `coarse_summary.csv` and `REPORT.md`.
- Captured QN attempt directories appeared only for `fb_norefine`; `no_fb` is
  therefore a control for this parameter-tuning surface.
- `stable_gate77`: `40/50` residual-gated successes, `0`
  embedded-converged regressions, `3` replay error rows.
- Best coarse candidate: `rho050_m500`, with `45/50` residual-gated successes,
  `0` embedded-converged regressions, `4` replay error rows, and `5` hard
  successes.

Decision:

- Promote `rho050_m500` to embedded Stage3 holdout.
- Repair the aggregate parser so future Phase A/B reruns treat replay error
  rows as tracked evidence instead of a fatal parse condition.

### Phase C Readback

Job: `15005.anode01`

Exit status: `0`

Candidate:
`rho050_m500` (`npt=4`, `maxfun=500`, `noise=true`, `rhobeg=0.050`,
`rhoend=1e-16`, `model.abs_tol=1e-30`, `model.rel_tol=0`).

Scale:
10 seeds x 10000 cycles, methods `no_fb` and `fb_norefine`, assist off.

Output root:
`output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseC_rho050_m500_10s10k`

Readback:

- `no_fb` control unchanged exactly: unresolved failures `16821 -> 16821`,
  reverse-gate rejects `889 -> 889`, Zmean Re/Im unchanged
  `1.5006/1.2686`.
- `fb_norefine` unresolved failures improved `4004 -> 2171`; every seed had
  fewer unresolved failures than the `stable_gate77` embedded baseline.
- `fb_norefine` reverse-gate rejects increased `909 -> 1550`.
- `fb_norefine` mean runtime increased only `1018.32s -> 1040.68s`.
- `fb_norefine` Zmean Re improved `1.2826 -> -0.5002`, but Zmean Im worsened
  `2.5434 -> 3.9564` at this 10seed scale.

Decision:

- Promote to Phase D because the embedded solver-local improvement is real and
  not just an offline replay artifact.
- Do not call the candidate verified yet: the 10seed Im mean/Zmean caveat needs
  a 32seed/50k observable-mean confirmation.  Reverse-gate rejects are tracked
  diagnostics, not blockers.

### Phase D Submitted

Label:
`dfols_assist_off_tuning_20260512_a22de1c_phaseD_rho050_m500_32s50k`

Scale:
32 seeds x 50000 cycles, methods `no_fb` and `fb_norefine`, assist off.

Jobs:

- chunks: `15006.anode01` through `15013.anode01`;
- merge: `15014.anode01`, held on `afterok` for all chunks.

Scripts:

- `codex/workspaces/tltm_production_comparison/tasks/pbs/dfols_assist_off_candidate_32seed_50k_chunk_20260512.pbs`
- `codex/workspaces/tltm_production_comparison/tasks/pbs/dfols_assist_off_candidate_32seed_50k_merge_20260512.pbs`

### Phase D Readback and Verdict

Jobs:

- chunks `15006.anode01` through `15013.anode01`: all `Exit_status=0`;
- merge `15014.anode01`: `Exit_status=0`.

Output root:
`output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseD_rho050_m500_32s50k`

Artifacts:

- `REPORT.md`;
- `combined_summary_table.csv`;
- per-method `aggregated_summary_table.csv`;
- per-method `per_seed_summary_table.csv`;
- seed rows: `32/32` for both `no_fb` and `fb_norefine`.

Readback versus the stable assist-off 32seed/50k baseline:

| method | metric | stable assist-off | `rho050_m500` | delta |
|---|---:|---:|---:|---:|
| `no_fb` | unresolved failures | `265127` | `265127` | `0` |
| `no_fb` | reverse-gate rejects | `15086` | `15086` | `0` |
| `no_fb` | Zmean Re/Im | `5.9903/-0.1760` | `5.9903/-0.1760` | `0/0` |
| `fb_norefine` | unresolved failures | `67061` | `33872` | `-33189` |
| `fb_norefine` | reverse-gate rejects | `14991` | `24280` | `+9289` |
| `fb_norefine` | mean runtime | `5271.58s` | `5425.29s` | `+153.71s` |
| `fb_norefine` | mean Re/Im | `0.0607926/0.0112710` | `0.0434491/0.00824623` | `-0.0173435/-0.00302481` |
| `fb_norefine` | Zmean Re/Im | `4.9468/1.7950` | `3.3284/1.2868` | `-1.6185/-0.5081` |
| `fb_norefine` | P68 Re/Im | `0.46875/0.6875` | `0.53125/0.78125` | `+0.0625/+0.09375` |
| `fb_norefine` | P95 Re/Im | `0.8125/0.96875` | `0.875/1.0` | `+0.0625/+0.03125` |

Paired seed checks:

- `fb_norefine` unresolved failures improved on `32/32` seeds
  (mean delta `-1037.16` per seed).
- `fb_norefine` reverse-gate rejects worsened on `32/32` seeds
  (mean delta `+290.28` per seed), recorded as diagnostic evidence.
- `fb_norefine` runtime increased on `32/32` seeds
  (mean delta `+153.71s` per seed).
- `fb_norefine` mean observables moved toward zero: Re delta `-0.0173435`,
  Im delta `-0.00302481`.
- `no_fb` is an exact control match for solver counters and observables; only
  runtime noise changed slightly.

Decision:

- The candidate verifies that official DFO-LS tuning can substantially reduce
  the assist-off QN unresolved tail.
- Under the corrected criterion, reverse-gate rejects and P68/P95 are not
  blockers.  The relevant observable means both improved relative to the stable
  assist-off baseline.
- The remaining solver-strength issue is failure parity with assist-on:
  `rho050_m500` reached `33872` failures versus the assist-on 32seed/50k
  reference `19579`.
- The remaining physics issue is that Re is still nonzero at this scale
  (`Zmean_re=3.3284`).
- Continue focused tuning.  A candidate should not be treated as having solved
  the no-assist problem unless it reaches the same failure scale as assist-on
  while keeping `mean_Ohat_re` and `mean_Ohat_im` from regressing.

### Phase E Focused Replay Readback

Job: `15095.anode01`

Queue: `C12`

Status: completed, `Exit_status=0`

Label:
`dfols_assist_off_tuning_20260513_a22de1c_phaseE_fullreplay_focus`

Purpose:

- determine whether official DFO-LS parameter tuning has a realistic path to
  assist-on failure parity;
- reuse existing Phase A/B captured `fb_norefine` QN attempts rather than
  rerunning Stage3 capture;
- replay all captured attempts instead of the previous 5-case-per-seed coarse
  screen.

Input:

- source capture:
  `output/tests/dfols_assist_off_tuning/dfols_assist_off_tuning_20260512_a22de1c_phaseAB_10s10k_c200s10_m5/attempts`;
- captured attempt files: 10 seed directories, roughly 200 attempts per seed.

Candidate family:

- centered on `rho050_m500`;
- sweep `rhobeg` around `0.04` to `0.15`;
- sweep `maxfun` around `500`, `750`, and `1000`;
- probe `npt=0`, `4`, `5`, and `6`;
- keep `objfun_has_noise=true`, `rhoend=1e-16`, `model.abs_tol=1e-30`,
  `model.rel_tol=0`.

Hard target:

- same-scale assist-on `fb_norefine` 32seed/50k failures: `19579`;
- current best assist-off tuned `rho050_m500`: `33872`;
- next candidate must plausibly reach the `<= 20k` failure scale while
  preserving mean Re/Im improvement.

Artifacts expected:

- `focused_summary.csv`;
- `REPORT.md`;
- `official_replay/<candidate>/<case>.csv`;
- `task_index.tsv`.

Readback:

- replay candidates: `24`;
- replay scope: all captured Phase A/B `fb_norefine` QN attempts,
  `1994` attempts across 10 seed directories;
- stable replay baseline: `1593/1994` successes (`0.79889669`);
- current tuned anchor `rho050_m500`: `1706/1994` successes
  (`0.85556670`), delta `+113` versus stable;
- best focused replay candidate: `rho050_m1000`;
- `rho050_m1000` successes: `1726/1994` (`0.86559679`);
- `rho050_m1000` delta: `+133` versus stable, only `+20` versus
  `rho050_m500`;
- `rho050_m1000` regressions/errors/hard successes: `12` / `237` / `148`;
- nf mean/p95/max: `110.405` / `408.8` / `1000`.

Conclusion:

- Parameter-only official DFO-LS tuning produced a real gain from stable to
  `rho050_m500`, but the focused neighborhood has saturated.
- The best tested extension, `rho050_m1000`, is only marginally stronger than
  `rho050_m500` on the full replay (`+20/1994`).
- This is not plausibly enough to move the 32seed/50k `fb_norefine` failure
  count from `33872` down to the assist-on reference scale `19579`.
- Do not submit another embedded Stage3 parameter-only candidate from this
  family.  The next solution path should address assist/proposal semantics:
  either formalize assist as navigation-only proposal construction, or replace
  it with an equivalent audited continuation/preconditioner whose final
  residual, RG, and Metropolis gates are fully unassisted.

Update this file after each phase with:

- job ids;
- output roots;
- parameter labels tested;
- solver-local readback;
- chain-level readback when available;
- conclusion and next action.

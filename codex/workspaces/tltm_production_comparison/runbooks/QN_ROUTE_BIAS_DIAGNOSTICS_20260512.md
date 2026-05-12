# QN Route Bias Diagnostics - 2026-05-12 JST

## Context

The current problem is not an official-DFO-LS-only regression. The same qualitative `withfb/fb_norefine` concern existed on the old in-house p28 line, so the active hypothesis must focus on the QN/fallback route itself and the RATTLE/HMC correctness conditions around that route.

Current 256seed/200k production-comparison readback:

- `nofb`: mean Re `0.0025128804602197745`, Zmean Re `1.0465518987029727`, unresolved failures `3846795`, RG rejects `607777`.
- `withfb/fb_norefine`: mean Re `0.004020561055771586`, Zmean Re `1.9729537196453188`, unresolved failures `618706`, RG rejects `510906`.
- `withfb` improves solver/failure counters but gives a worse positive Re Zmean at this scale.

## Code Reading

- Newton/RATTLE first solves `solve_constraint_newton(cttol, 100, ...)`.
- If Newton fails and fallback is enabled, QN uses `try_quasi_stage(quasi_tol, s1_probe_max_iter, ...)`.
- QN residual is BTN/backflow-style:
  - `xi(1:n)=b`, `xi(n+1:2n)=a`.
  - `Jl = ReVec(-J*(a+i*b))`.
  - `ztrial = z + del_z - J*(a+i*b)`.
  - residual is `[Im(flowzr(ztrial)); a]`.
- At an exact root, `a=0` and `flowzr(z + del_z + Jl)` is real. This is algebraically equivalent to the Newton projection only if the forward/inverse flow and root branch are consistent.
- RG checks actual reverse replay of the full RATTLE step, including `x/z/jac/p`; it is necessary but does not by itself prove volume preservation or route-density symmetry.
- Metropolis uses only `exp(-(H_final-H_initial))`; there is no proposal-Jacobian correction.

## Diagnostic Added

Added an env-gated local transition audit:

- `TLTM_LOCAL_TRANSITION_AUDIT_FILE=/path/to/local_transition_audit.csv`
- `TLTM_LOCAL_TRANSITION_AUDIT_MAX_ROWS=N`
- `TLTM_LOCAL_TRANSITION_AUDIT_BASE_DIR=/path/root` for `scripts/run_stage3_3_multiseed.py`, which writes per-method/per-seed audit files.

This does not change proposal/acceptance behavior when the env var is absent. It records per local update:

- accepted/proposal_failed/transition_status
- `h_initial`, `h_final`, `delta_h`, `accept_probability`
- Newton/QN/probe/full-stage/class/far-route/near-route counter deltas
- RG candidate/pass/reject deltas

Local compile check passed with `make -C build tltm_stage2`.

## First Smoke Evidence

Local diagnostic run:

- Output: `output/tests/qn_transition_audit_local_1seed_1k`
- Method: `fb_norefine`
- Seed: `20260421`
- Scale: `1000 cycles`, two-slot `t=0.05,0.35`, `L=2`, `nstep=20`
- Backend: `QN_SOLVER_BACKEND=internal`
- RG: enabled, `QN_REVERSE_GATE_TOL=1e-8`
- Tolerances: `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`
- Rescue: near/nonnear rescue disabled

Audit summary:

- Rows: `2000` local updates.
- QN events occurred only in hot slot `slot_id=1`.
- Hot-slot accepted Newton-only: `904` rows, mean `delta_h = +9.751148437639863e-4`, negative count `464/904`.
- Hot-slot accepted QN: `38` rows, mean `delta_h = -2.385424146627109e-2`, negative count `27/38`.
- QN any-route rows: `70`; of the `47` rows with finite `delta_h`, mean `delta_h = +1.0128737357774704` because rejected/failed positive-tail proposals are large.
- RG rejects: `15`; these have no finite proposal `delta_h` because the proposal is rejected before Hamiltonian acceptance.

This is not a final proof of bias, but it is a concrete event-level signal: the accepted QN route has a much more negative `delta_h` profile than Newton-only in the same short run. If the QN route is not exactly volume-preserving/proposal-symmetric, Metropolis will overaccept these negative-`delta_h` moves because the acceptance rule has no proposal-Jacobian correction.

## Current Hypothesis

The most suspicious failure mode is not official solver tuning. It is:

1. QN/fallback selects a different projection branch or route basin for a small fraction of hot-slot RATTLE substeps.
2. RG removes non-reversible proposals but may leave a route that is reversible yet not volume-preserving, or whose route selection is not proposal-density symmetric.
3. Metropolis then treats these proposals as ordinary volume-preserving HMC proposals, so accepted negative-`delta_h` QN moves can shift the sampled observable.

## Next Test

Run a short multi-seed audit before more production:

- `10 seeds x 10k` or `10 seeds x 2k` if queue time is tight.
- Methods: at least `nofb` and `fb_norefine`.
- Backend: old/internal p28 first, because the issue predates official DFO-LS.
- Keep event audit enabled for `fb_norefine`.
- Summarize route-conditioned:
  - accepted Newton-only vs accepted QN `delta_h`
  - negative-`delta_h` fraction
  - route-conditioned accept/reject/proposal-failed counts
  - per-seed correlation between accepted-QN count/mean QN `delta_h` and Re observable

If the negative accepted-QN `delta_h` profile persists and correlates with Re shift, the next code-level proof test should capture accepted QN states and run local volume/route-signature replay on those exact events, not on generic sampled successful proposals.

## Follow-Up Evidence: 10seed/2k Route Audit

Local diagnostic run:

- Output: `output/tests/qn_route_bias_audit_10seed_2k`
- Methods: `no_fb`, `fb_norefine`
- Scale: `10 seeds x 2000 cycles`, two-slot ladder `t=0.05,0.35`
- Backend/settings: internal p28-equivalent, `cttol=1e-13`, `QN_QUASI_TOL_OVERRIDE=1e-13`, RG on, near/nonnear rescue off

Aggregate result:

- `fb_norefine`: mean Re `0.01367017675688588`, Zmean Re `0.1462250058436495`, unresolved failures `374`, RG rejects `314`.
- `no_fb`: mean Re `0.0026863432389113142`, Zmean Re `0.021369106160438255`, unresolved failures `1539`, RG rejects `283`.

Route-conditioned event audit:

- `fb_norefine` accepted Newton-only: `38307` rows, mean `delta_h = +8.7575066e-05`, negative fraction `0.5000`.
- `fb_norefine` accepted QN: `626` rows, mean `delta_h = -2.4017814e-02`, negative fraction `0.6214`.
- `fb_norefine` QN-any rows: `1176`; finite-`delta_h` mean `+2.3777154` because large positive-tail proposals are rejected.
- `fb_norefine` proposal failures: `688`; RG rejects: `314`.
- `no_fb` accepted QN: `0`; proposal failures: `1822`; RG rejects: `283`.

Paired seed difference at this small scale:

- `fb_norefine - no_fb` Re mean difference: `+0.010983833517974556`.
- Paired standard error: `0.13625212368149983`.
- Paired t-statistic: `0.0806`.

Interpretation: the accepted-QN negative-`delta_h` signature persists, but this 10seed/2k two-slot sample does not show a statistically meaningful method-level Re shift.

## Follow-Up Evidence: Fallback REVCHK

Local fallback-only REVCHK:

- Output: `output/tests/qn_route_bias_revchk_1seed_10k`
- Method: `fb_norefine`
- Seed: `20260421`
- Probe settings: `HMC_REVERSIBILITY_PROBE_LIMIT=100`, `HMC_REVERSIBILITY_PROBE_FALLBACK_ONLY=1`

Result:

- Records: `100`; fallback records: `100`; bad reverse checks: `0`.
- Max `dx_inf = 3.554019e-10`.
- Max `dz_inf = 6.244020e-10`.
- Max `dj_inf = 2.029964e-09`.
- Max `dp_inf = 9.862868e-10`.
- `dH_reverse` was the sign-flipped counterpart of `dH_forward` in the printed summary.

Interpretation: the accepted fallback/QN route passes the basic involution/reversibility test at the current tolerance. The primary bug hypothesis should not be "reverse replay obviously fails."

## Follow-Up Evidence: Local Volume/Branch Probe

A diagnostic-only `probe_hmc_volume` source was restored for current-code testing, but it should not be left promoted in the modernization build graph. It estimates the 1D local chart map `(q,c)->(q',c')` and reports

`metric_logvol = log(abs(det d(q',c')/d(q,c))) + 2 log |J_out| - 2 log |J_in|`.

Generic QN stable-branch scan:

- Output root: `output/tests/qn_route_bias_volume_current`
- QN stable branch, 20 kept points, `eps=1e-6`: median metric log-volume `1.92e-07`, max abs `2.21e-03`.
- QN stable branch, same points, `eps=3e-7`: median metric log-volume `-2.79e-07`, max abs `1.95e-04`.
- Larger outliers shrink with smaller `eps`, consistent with finite-difference/curvature sensitivity rather than an O(1) volume defect.

Generic branch scan:

- 120 successful base points at `eps=3e-7`.
- Base QN points: `11/120`.
- Branch stable: `119/120`; strong-branch stable: `119/120`.
- Base QN branch stable: `11/11`.
- Metric log-volume max abs over all 120 points: `1.1576069419039214e-05`.
- Metric log-volume max abs over base-QN points: `7.559821265545885e-06`.

Interpretation: the smooth local QN/fallback map appears volume-preserving to finite-difference accuracy in the tested region, and branch instability is rare in this scan.

## Follow-Up Evidence: Exact Accepted-QN Event Replay

The local transition audit was extended to record diagnostic-only momentum chart coordinates:

- `q_initial`, `c_initial`, `q_proposal`, `c_proposal`, `q_after`
- The formal sampler behavior is unchanged when these optional diagnostics are absent.

Exact event capture:

- Output: `output/tests/qn_route_bias_exact_event_capture_1seed_2k`
- Seed: `20260421`
- Method: `fb_norefine`
- Accepted QN events: `68`
- Accepted QN mean `delta_h = -0.0522854508663588`; negative count `43/68`.

Exact accepted-QN volume replay:

- Input: first 40 accepted-QN `(q_initial,c_initial)` events from the above audit.
- `eps=3e-7`: 40/40 base-QN, 40/40 branch-stable, max abs metric log-volume `3.825305352256336e-06`.
- `eps=1e-6`: 40/40 base-QN, 40/40 branch-stable, max abs metric log-volume `2.0546363967977044e-06`.

Exact reverse replay:

- Input: `(q_out,-c_out)` from the 40 exact accepted-QN replay rows.
- Backward max `|q_back-q_initial| = 2.0110135778850236e-11`.
- Backward max `|c_back+c_initial| = 1.4170664641710573e-11`.
- Reverse metric log-volume max abs `6.316032570952146e-06`.

Interpretation: for actual production-captured accepted QN events, the tested map is reversible and locally volume-preserving. This substantially lowers the priority of a direct QN/RATTLE detailed-balance bug as the explanation for worse finite-sample Zmean.

## Follow-Up Evidence: Single-Slot Sampler Check

Local single-slot no-effective-swap run:

- Config: `docs/qn_route_bias_single_slot_t035_10seed_2k.json`
- Output: `output/tests/qn_route_bias_single_slot_t035_10seed_2k`
- Methods: `no_fb`, `fb_norefine`
- Scale: `10 seeds x 2000 cycles`, one slot `t=0.35`

Aggregate result:

- `fb_norefine`: mean Re `0.12963743619072704`, Zmean Re `0.7897597879888678`, unresolved failures `371`, RG rejects `284`.
- `no_fb`: mean Re `-0.1521142989534558`, Zmean Re `-1.9538183653570738`, unresolved failures `1165`, RG rejects `239`.
- Paired Re difference `fb_norefine - no_fb`: mean `+0.28175173514418284`, paired SE `0.15446513515009014`, t-statistic `1.8240`.

Interpretation: at 10seed/2k, single-slot results are too noisy to claim a stable method shift. They do show that the sign and size of small-window Zmean can swing strongly even when the exact QN map passes reversibility/volume checks.

## Current Working Conclusion

As of these diagnostics, the direct correctness checks are mostly clean:

- Fallback/QN accepted proposals pass REVCHK at the tested tolerance.
- Generic QN stable branches are locally volume-preserving to finite-difference accuracy.
- Exact production-captured accepted QN events are locally volume-preserving and reverse back to the original chart coordinates.
- The accepted-QN route has a real negative-`delta_h` conditional profile, but that alone is not a bug if the deterministic proposal map is reversible and volume-preserving.

The next priority should shift from "QN solver map is obviously invalid" to sampler/statistics questions:

- quantify the 256seed/200k `nofb` vs `fb_norefine` paired seed difference and uncertainty, not only separate Zmeans;
- inspect autocorrelation/effective sample size and window stability by seed/cycle block;
- check whether the larger positive Re Zmean persists under larger statistics or is a finite-window fluctuation;
- only reopen QN-map correctness if an exact accepted event fails reverse/volume replay.

## Follow-Up Evidence: 256seed/200k Paired Production Difference

Remote provisional production readback:

- Worktree: `/lustre1/home/cychou/TLTM_worktrees/tltm_production_comparison`
- Output: `output/production_comparison/provisional/official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`
- Methods: `no_fb`, `fb_norefine`
- Scale: `256 seeds x 200k cycles`

Separate method summary, already known:

- `no_fb`: mean Re `0.0025128804602197745`, Zmean Re `1.0465518987029727`.
- `fb_norefine`: mean Re `0.004020561055771586`, Zmean Re `1.9729537196453188`.

Paired seed comparison:

- `paired_n = 256`
- mean paired difference `fb_norefine - no_fb = +0.001507680595551813`
- paired SD `0.04429784768083099`
- paired SE `0.002768615480051937`
- paired t-statistic `0.5445612098952543`
- positive/negative paired differences: `131/125`
- min/max paired difference: `-0.1220926451436903` / `+0.1110175784085578`

Chunk-of-8 paired means:

- 32 chunk means.
- min/max chunk mean: `-0.03898994043106506` / `+0.046625209467511475`
- positive/negative chunk means: `19/13`

Interpretation:

- The separate Zmeans made `fb_norefine` look worse against exact, but the direct paired method difference is not statistically meaningful.
- At 256seed/200k there is no strong evidence that `fb_norefine` is systematically worse than `no_fb`.
- Combined with exact-event reversibility/volume checks, the current concern should be treated as finite-window/statistical until contradicted by a larger or block-stability analysis.

## Follow-Up Evidence: 256seed/200k Window/Block Diagnostic

Diagnostic script:

- Local source: `codex/workspaces/tltm_production_comparison/diagnostics/window_bias_analysis.py`
- Remote output: `codex/workspaces/tltm_production_comparison/diagnostics/window_bias_256seed_200k_20260512`
- Inputs: per-seed `eval_multichain/virial.dat` and binary `eval_multichain/chain_001/output/phi_history.dat` from `official_dfols_gate_20260511_256seed_200k_p28_rg_nofb_withfb`.
- Ratio convention: window means recompute `sum(O*phi)/sum(phi)`, matching `evaluate_expectations`; `virial.dat` is not averaged directly.

Integrity check:

- Recomputed full-run per-seed ratios agree with `per_seed_summary_table.csv`.
- Max absolute recompute difference: Re `3.30291e-15`, Im `2.17881e-15`.

Four 50k-sample windows:

| method | window | mean Re | Zmean Re | mean Im | Zmean Im |
| --- | --- | --- | --- | --- | --- |
| `fb_norefine` | 0 | `0.00137891` | `0.34327` | `0.000891453` | `0.303027` |
| `fb_norefine` | 1 | `0.00736861` | `1.76167` | `-0.000385239` | `-0.139789` |
| `fb_norefine` | 2 | `0.00559802` | `1.37464` | `-0.00155994` | `-0.577698` |
| `fb_norefine` | 3 | `-0.000142914` | `-0.0353124` | `-0.00236484` | `-0.885691` |
| `no_fb` | 0 | `0.00290375` | `0.575669` | `-0.00333222` | `-1.18168` |
| `no_fb` | 1 | `0.00190483` | `0.371351` | `0.00124817` | `0.411938` |
| `no_fb` | 2 | `-0.000457481` | `-0.0907287` | `-0.00427269` | `-1.45167` |
| `no_fb` | 3 | `0.00387284` | `0.797027` | `0.0029318` | `1.05698` |

Paired 50k-window differences `fb_norefine - no_fb`:

- window 0: `-0.00152483`, t `-0.248018`, positive/negative `128/128`
- window 1: `+0.00546378`, t `+0.978189`, positive/negative `136/120`
- window 2: `+0.0060555`, t `+0.998639`, positive/negative `134/122`
- window 3: `-0.00401575`, t `-0.686853`, positive/negative `126/130`

Twenty 10k-window sign summary:

- `fb_norefine` windows with positive mean Re: `12/20`.
- `no_fb` windows with positive mean Re: `9/20`.
- paired 10k-window mean differences positive/negative: `10/10`.

Counter-correlation readback:

- For full 200k `fb_norefine`, Re correlates with counters: fallback trigger `r=0.6600`, accepted QN `r=0.3647`, unresolved failures `r=0.5398`, RG rejects `r=0.3967`, local Metropolis rejects `r=0.4509`.
- However `no_fb` also has strong Re correlation with hard-region counters: unresolved failures `r=0.7251`, local Metropolis rejects `r=0.3943`, accepted local total `r=-0.7805`.
- Same-seed Re correlation between `no_fb` and `fb_norefine` is only `r=0.2302`; the paired method difference remains weak.

Quartile diagnostic:

- `fb_norefine` fallback-trigger quartiles show mean Re from `-0.0258` in Q1 to `+0.0328` in Q4.
- `no_fb` unresolved-failure quartiles show the same qualitative hard-region ladder: mean Re from `-0.0291` in Q1 to `+0.0402` in Q4.

Interpretation:

- The 256seed/200k `fb_norefine` positive Zmean is not a stable positive offset across all time windows; it is concentrated in middle windows and partly cancels in the last window.
- The 20-window paired differences are exactly split by sign, so the direct fb-vs-nofb degradation hypothesis is not supported by this block test.
- The strong counter correlations occur in both methods, so route/failure counters are likely tracking hard, slowly mixing state-space regions rather than proving QN route bias by themselves.
- Current best diagnosis: a finite-window/long-autocorrelation or hard-region sampling issue is more plausible than a direct QN detailed-balance or volume bug.

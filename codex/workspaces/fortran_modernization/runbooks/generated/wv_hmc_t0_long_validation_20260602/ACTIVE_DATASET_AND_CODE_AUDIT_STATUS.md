# Active Dataset, Bank, and WV-HMC Code-Audit Status

Recorded: 2026-06-02 17:07 JST

Purpose: pin the correct long-cycle WV-HMC dataset and initial bank before
continuing analysis.  This file is a routing and provenance record, not a final
physics conclusion.

## Active Dataset Pin

Use this dataset for the current `T0=0`, fixed-tau-bank long-validation
analysis:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_t0_long_validation_20260601/wv_hmc_n6_t0_g65e009n10_m025_64x15000_12h_20260601
```

Remote logs:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_t0_long_validation_20260601/wv_hmc_n6_t0_g65e009n10_m025_64x15000_12h_20260601
```

Protocol:

- model: Stephanov `n=6`, `mu=0.6`, `tau=0`
- sampler interval: `[T0,T1]=[0,0.03]`
- measurement interval: `[0.025,0.03]`
- measurement start cycle: `1001`
- `W(t)`: `paper_wall`, `gamma=65`, `D0=0.0001`, `D1=0.005`
- HMC: `epsilon=0.009`, `nstep=10`, `L=0.09`
- constraint tolerance: `1e-10`
- constraint max iterations: `192`
- ODE backend: `dop853`
- requested scale: `64` seeds x `15000` cycles
- jobs: `18680.anode01` to `18683.anode01`
- queues/nodes: `C17`; `cnode37` for chunks 00-02 and `cnode38` for chunk 03

Verified remote completeness:

- total files: `321`
- observable histories: `64`
- summaries: `63`
- observables: `63`
- final states: `63`
- snapshot files: `0`
- manifest files: `4`
- failed/no-measurement seed: `9630023`

Important limitation: no cyclic snapshots were produced.  This run is usable for
observable/history/flow-cut analysis, but not for rebuilding a cyclic snapshot
bank.

## Active Initial Bank Pin

Use this fixed-tau `T0=0` WV state bank as the initial-bank provenance for the
active dataset:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260601/stephanov_n6_tau0_hmc_eps080_n8_64x3000_20260601/state_bank_tau0/x_bank.dat
```

Current symlink:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_initial_banks_20260601/current_stephanov_n6_t0_state_bank
```

Builder provenance:

- `tau_bank=0`
- `epsilon=0.08`
- `nstep=8`
- `L=0.64`
- chunks: `4`
- records: `64`
- cycles per record: `3000`
- packed records: `16064`
- record layout: `flow_time + x`
- record width: `73`
- bank flow time: `0`

Builder diagnostics:

- attempts: `192000`
- acceptance: `0.7716979167`
- proposal failure: `0`
- reverse-gate reject: `0`
- chunk acceptance range: `0.7702708333 .. 0.7734791667`
- step rms/coord range: `0.4590859046 .. 0.4604930611`
- max record sec/cycle: `0.00904696897`

## Source Pin and Code Provenance

The active long-validation dataset predates the simplified-paper full-flip
boundary-policy fix.  Treat it as an old-implementation long dataset, not as a
validation of the current post-fix WV-HMC code.

Boot-log source pin:

```text
TLTM_SOURCE_PIN_ID=8ec6dc0d9b87-86f750bba994
TLTM_SOURCE_PIN_COMMIT=8ec6dc0d9b8768c5432e8c9df883a9cd870a82ba
TLTM_SOURCE_PIN_DIRTY_COUNT=51
TLTM_WORKTREE=/lustre1/home/cychou/TLTM_worktrees/runtime_snapshots/wv_hmc_n6_t003_prod15k_gitless_r3_20260601
```

Do not mix this dataset with the later full-flip fast-audit data without an
explicit method/source-pin label.

## Do Not Use As This Dataset

These are related but distinct runs:

- `wv_hmc_n6_gamma55_validation_20260601`: gamma55 validation path, not the
  pinned `T0=0`, `gamma=65`, high-measurement-window long dataset.
- `wv_hmc_n6_prod15k_20260601`: large prod15k dataset with different
  measurement/window provenance.
- `wv_hmc_t0_retune_20260601/wv_hmc_n6_t0_retuned_g65e009n10_validation_32x1500_20260601`:
  short old-source retune validation, useful for diagnostics but not the
  12-hour long dataset.
- `wv_hmc_fast_audit_20260602/wv_hmc_fast_audit_n6_paperflip_highcut_32x3000_20260602`:
  post-fix full-flip high-flow diagnostic, useful for code comparison but not
  the active long dataset.

## Code-Audit Progress

Current status: code correctness is not closed.  The audit has localized and
fixed one concrete implementation mismatch, but it has not yet proven that the
current WV-HMC production estimator is mathematically correct for n=6.

Update, 2026-06-02 later checkpoint:

- The independent n=6 measurement-factor identity/oracle was completed after
  this file's original checkpoint.  See
  `../wv_hmc_measure_n6_oracle_gate_20260602/RESULT.md`.
- The active follow-up workflow and current trust-boundary ledger is
  `../wv_hmc_verification_workflow_20260602/CURRENT_CODE_VERIFICATION_LEDGER_AND_TODO_WORKFLOW.md`.
- That ledger supersedes the immediate TODO list below where it mentions the
  alpha/measurement oracle as still required.
- WV-HMC production correctness remains open because the full invariant-measure
  / detailed-balance gate for the production kernel has not been completed.

Completed checks:

1. Deterministic WV-HMC math/constraint gates were added and run on cluster.
   They cover force/projection checks, simplified Newton/RATTLE checks,
   trajectory energy-order checks, forward/reverse energy checks, reverse-gate
   checks, nonzero-`W` transition checks, and dense measurement-factor
   self-consistency checks.
2. A boundary-policy mismatch was found: the previous implementation was
   self-consistent for normal/component reflection, but failed the
   simplified-paper full momentum flip gate.
3. The boundary-policy implementation was patched so boundary exits restore the
   current state and apply `pi -> -pi`.  The post-fix deterministic gate passes.
4. A post-fix n=2 sanity run at `T0=0`, `T1=0.01` with a valid WV state bank
   passes the exact-reference observable gate.  Random-Gaussian starts showed
   an initial-transient problem, not a clean kernel correctness failure.
5. Existing n=6 diagnostics showed that broad-window bias was not explained by
   low-flow contamination alone.  Offline alpha/W weight variants on the same
   old history made the measurement-factor convention a serious suspect.
6. A post-fix n=6 high-flow diagnostic did not show the earlier gross
   observable drift, but it is only a high-flow diagnostic and is not a full
   production correctness gate.

Unclosed checks:

1. Superseded: the independent n=6 measurement-factor identity/oracle was
   completed in cluster job `18806.anode01`.
2. A full-window or explicitly chosen measurement-window post-fix n=6
   validation must be analyzed after the measurement-factor audit.  The old
   long dataset pinned above cannot answer whether the current full-flip code
   is correct.
3. Same-seed old-vs-full-flip A/B is not available from the existing files.
   Existing comparisons are historical before/after comparisons, not paired
   seed-level tests.
4. The exact rule for promoting a high-flow measurement subwindow to production
   still depends on the measurement-factor audit and observable-gate result.

Immediate next code-audit task:

1. Use the current trust-boundary ledger:
   `../wv_hmc_verification_workflow_20260602/CURRENT_CODE_VERIFICATION_LEDGER_AND_TODO_WORKFLOW.md`.
2. Add and scheduler-run the exact positive-target invariant-measure test for
   the dense explicit-J production kernel.
3. Only after that gate passes, run a short current-source n=6 validation
   before any new long production-scale validation.

## Current Analysis Routing

For the current data analysis, use the active long dataset and bank pinned
above.  Label it as:

```text
n6_t0_long_old_boundary_sourcepin_8ec6dc0d9b87_86f750bba994
```

For current-code validation, do not use this dataset alone.  Use post-fix data
or launch new post-fix validation only after the measurement-factor oracle is
closed.

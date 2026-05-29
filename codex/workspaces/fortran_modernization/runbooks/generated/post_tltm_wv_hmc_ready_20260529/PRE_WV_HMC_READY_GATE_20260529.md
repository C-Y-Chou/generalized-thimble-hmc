# Pre-WV-HMC Ready Gate

Date: 2026-05-29

Scope: final local readiness gate after the Stephanov `n=6`, `t_high=0.03`
TLTM closure and before adding WV-HMC.  This artifact does not implement WV-HMC.

## Status

Ready to open the WV-HMC implementation gate.

The TLTM line is closed for this phase:

- canonical TLTM production mode: `nofb`;
- `withfb` / DFO-LS fallback: default-off legacy diagnostic mode;
- lower failure count alone is not a criterion;
- raw output archive movement/deletion remains deferred;
- old `wv` runtime flag semantics are removed from canonical source and must not
  be reused for WV-HMC.

## Closure Artifacts

- Final criterion packet:
  `runbooks/generated/post_tltm_wv_hmc_ready_20260529/FINAL_WITHFB_NOFB_CRITERION_CLOSURE_20260529.md`
- Machine summary:
  `runbooks/generated/post_tltm_wv_hmc_ready_20260529/final_criterion_summary.json`
- Gate status:
  `runbooks/generated/post_tltm_wv_hmc_ready_20260529/gate_status.csv`
- Four dataset groups:
  `runbooks/generated/post_tltm_wv_hmc_ready_20260529/dataset_archive_groups_final.tsv`
  and `state/STEPHANOV_N6_DATASET_GROUPS_20260528.tsv`
- Canonical TLTM SOP:
  `runbooks/TLTM_CANONICAL_SOP_20260528.md`
- WV-HMC algorithm readback:
  `runbooks/WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`
- Nonblocking caveat and dataset/worktree status:
  `runbooks/generated/post_tltm_wv_hmc_ready_20260529/NONBLOCKING_CAVEATS_AND_WORKTREE_DATASET_STATUS_20260529.md`

## Source Hygiene Completed

- Removed stale source-level `wv` runtime residue from
  `src/config/param_mod.f90`.
- Kept future WV-HMC separate from TLTM Stage2 mode flags.
- Added a dimension-neutral QN trace metadata getter so retained-core QN route
  checks no longer depend on the legacy one-complex-variable trace accessor.
- Made local M4/F14/RNG anchor smoke fixtures high-dimensional safe by using
  near-zero flow smoke tests instead of old large-flow direct-init assumptions.
- Updated local-transition audit schema for the current producer columns,
  including QN capture counters.
- Normalized runtime-only telemetry in RNG anchors so deterministic hashes test
  samples and labels, not wall-clock seconds.

## Verification

Passed commands:

```bash
PYTHON="$PWD/.venv-dfols/bin/python" \
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" \
make -C build FC=gfortran LDFLAGS= modernization_guardrails

PYTHON="$PWD/.venv-dfols/bin/python" \
TLTM_OFFICIAL_DFOLS_PYTHONPATH="$($PWD/.venv-dfols/bin/python -c 'import site; print(site.getsitepackages()[0])')" \
make -C build FC=gfortran LDFLAGS= test_official_dfols_preset_contract test_retained_core_qn_route_contract test1 test2

make -C build test_mt95_state_contract test_tltm_rng_contract test_tltm_swap_kernel_contract
```

Observed guardrail notes:

- M4 reported `all guardrails passed`.
- Retained-core QN route contract passed with high-dimensional
  `trace_dim=8`.
- `test2` passed Stephanov random-complex manual derivative and Hessian-vector
  finite-difference checks for `n=2`, `n=4`, and `n=6`.

## Nonblocking Deferred

- Raw archive movement/deletion.
- Raw Stage deprecation.
- Larger RNG/state/cache refactors.
- Public product-doc consolidation beyond stale-claim correction and README-level
  TLTM status.

These items are explicitly nonblocking for opening the WV-HMC implementation
gate.  The blocking stale WV residue and TLTM method-boundary decisions are
closed above.

## Next Gate

The next implementation step can be WV-HMC as a sibling sampler, using the
simplified-algorithm readback as the algorithm contract.  Do not add it as a
hidden TLTM model choice or revive the old `wv` config flag.

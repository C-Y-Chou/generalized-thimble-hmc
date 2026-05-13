# CV011 Stage2 Kernel RNG v2 Implementation - 2026-05-14

## Scope

Implemented the modernization RNG v2 target:

```text
TLTM_STAGE2_RNG_STREAM_CONTRACT=stage2_kernel_rng_v2
```

The Stage2 default is now `stage2_kernel_rng_v2`.  `per_replica_rng_v1` remains
available for the post-B anchor and `legacy_global_v0` remains available as a
historical compatibility mode.

## Source Changes

- Added `src/core/tltm_rng.f90` for deterministic domain-separated Stage2
  kernel seeding.
- Added optional explicit MT95 RNG state arguments to the HMC proposal momentum
  draw and Metropolis accept draw.
- Stage2 now derives short-lived RNG states for:
  - `stage2:init`;
  - `stage2:local_momentum`;
  - `stage2:local_accept`;
  - `stage2:swap_accept`.
- Stage2 summaries and v1 manifests now print the selected
  `rng_stream_contract` and matching seed policy.
- `scripts/run_stage3_3_multiseed.py` now passes and records the Stage2 RNG
  stream contract explicitly; default production runs therefore use
  `stage2_kernel_rng_v2` rather than an implicit binary default.
- Added `stage2_rng_v2_anchor.py` and a `make stage2_rng_v2_anchor` guardrail.

## F8 Patch Reference Statement

This is behavior-relevant because it changes the Stage2 finite same-seed
proposal stream by design.  It is not claimed to preserve `per_replica_rng_v1`
or historical `legacy_global_v0` same-seed trajectories.  The preserved
interfaces are the explicit compatibility modes and the post-B v1 anchor.

## Verification

Focused checks passed locally:

```bash
python3 -m py_compile scripts/run_stage3_3_multiseed.py scripts/run_m4_guardrails.py codex/workspaces/fortran_modernization/tasks/scripts/stage2_rng_v2_anchor.py codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py
make -C build FC=gfortran LDFLAGS= ../bin/run_tltm_stage2 ../bin/evaluate_expectations test_tltm_swap_kernel_contract test_mt95_state_contract stage2_rng_v2_anchor post_b_rng_reference_anchor
python3 scripts/run_stage3_3_multiseed.py --repo-root . --config docs/production_comparison_official_dfols_20260511_10seed_10k_nofb_withfb.json --max-seeds 1 --dry-run
git diff --check
```

The full M4 guardrail also passed all build/smoke/science checks on the first
run, but correctly failed the source/task boundary check until the new source
and guardrail script were staged intentionally.

## Production Sync Rule

Production-comparison must sync to the committed modernization patch before
rerunning production from a clean namespace.  Do not continue the archived
assist-diagnostic scale-up as the post-v2 production line.

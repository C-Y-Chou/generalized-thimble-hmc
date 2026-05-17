# Post-B RNG Reference Anchor

Updated: 2026-05-18 JST

Scope: deterministic local reference for the accepted CV-011 route-B RNG
contract, `per_replica_rng_v1`.

## Purpose

Route B intentionally changes finite same-seed trajectories relative to the old
shared serial RNG stream. This anchor freezes the new contract before deeper
OpenMP/thread-safe productization work so later workspace/state refactors have a
small, fast, deterministic comparison point.

## Gate

Script:

```bash
python3 codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py --repo-root . --fc gfortran --ldflags ''
```

Make target:

```bash
make -C build FC=gfortran LDFLAGS= post_b_rng_reference_anchor
```

Reference file:

```text
codex/workspaces/fortran_modernization/state/POST_B_RNG_REFERENCE_ANCHOR_V1.json
```

The gate runs tiny Stage1 and Stage2 jobs twice with `CHAIN_RNG_SEED=12345`,
normalizes elapsed/runtime fields plus compiler-sensitive pair
`last_accept_prob`, verifies both runs have identical normalized hashes, and
compares those hashes to the frozen reference JSON.

## Frozen Hashes

| Artifact | Normalized SHA-256 |
| --- | --- |
| Stage1 summary | `bafe7ce2089cfc2af646f4d216f3b7ec915e0f329b44e96a4becaf723236ab79` |
| Stage2 summary | `774bdc288abbbcf6a0a2f375dd6ebdcf8f82d89bda9c805f1f9ead2f326a571c` |
| Stage2 label trace | `7a6a9b82a0e7c78fed27357ff95649ad0c467c220f29a46db91d6042303bf299` |

## Verification

Passed locally on 2026-05-12 JST:

```bash
python3 -m py_compile codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py scripts/run_m4_guardrails.py
python3 codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py --repo-root . --fc gfortran --ldflags '' --update-reference
python3 codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py --repo-root . --fc gfortran --ldflags ''
make -C build FC=gfortran LDFLAGS= post_b_rng_reference_anchor
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

Manifest path:

```text
output/tests/post_b_rng_reference_anchor/POST_B_RNG_reference_anchor_manifest.json
output/tests/m4_guardrails/post_b_rng_reference_anchor/POST_B_RNG_reference_anchor_manifest.json
```

## Boundary

This anchor protects the post-B RNG contract. It is not a production-output
redo and does not compare against the old shared serial stream, because the user
accepted route B as a deliberate stream-contract change.

## 2026-05-18 Cross-Compiler Normalization

Remote Intel `ifx` and local `gfortran` runs produced the same Stage1 summary,
the same Stage2 label trace, and the same Stage2 accept/reject decisions, but
the Stage2 summary's diagnostic `last_accept_prob` differed in the final
floating-point digits.  That field is not the RNG stream contract, so it is now
normalized like runtime fields.  The label trace remains the primary exact
Stage2 stream-order anchor.

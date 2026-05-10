# M6 Reference Dataset Readback - 2026-05-10

Updated: 2026-05-10 22:50 JST

Scope: final readback of modernization M6 R1-R4 reference packages generated on `fortran_modernization_m6_active`.

## Verdict

M6 R1-R4 are accepted as modernization reference baselines for the current canonical route.

Acceptance state:

- `accepted`
- Package class: `stage3_4_context_aligned_reference`
- Physical point: `t=0.35,L=2,nstep=20`
- Raw methods: `no_fb`, `fb_norefine`
- Canonical roles: `nofb`, `withfb`
- Caveat: `fb_norefine` is a legacy raw method name for the canonical fallback-enabled no-post-refine p28 route. Public wrapper/schema naming still needs to rename or alias this cleanly.

## Source And Remote State

- Source commit: `a1028ad6d68eabfd6c400ec135b3df9cab1e4af2`
- Active remote worktree during generation: `/lustre1/home/cychou/TLTM_worktrees/qn_error_handling_validation`
- Branch during generation: `codex/qn-error-handling-validation`
- Latest remote refresh: no active PBS jobs remain.
- Worktree safety: no active pinned M6 jobs remain, so future remote fast-forward, rename, or cleanup is possible after a fresh refresh and explicit scope check.

## Structural Readback

| Level | Label | Expected rows per method | `no_fb` rows | `fb_norefine` rows | Protocol audit |
| --- | --- | ---: | ---: | ---: | --- |
| R1 | `r1_4seed_1k` | 4 | 4 | 4 | pass, bad=0 |
| R2 | `r2_10seed_10k` | 10 | 10 | 10 | pass, bad=0 |
| R3 | `r3_32seed_50k` | 32 | 32 | 32 | pass, bad=0 |
| R4 | `r4_128seed_100k` | 128 | 128 | 128 | pass, bad=0 |

All levels have `reference_manifest.json`, `reference_aggregate_comparison.csv`, `reference_registry_rows.tsv`, and one aggregate row per raw method. The v1alpha sidecar/protocol audit status is preserved through merge.

## PBS Completion

- R3 replacement `14669`: `Exit_status=0`
- R3 merge `14670`: `Exit_status=0`
- R4 final replacement `14674`: `Exit_status=0`
- R4 merge `14675`: `Exit_status=0`
- No active PBS jobs remain after the latest refresh.

## Key Aggregate Readback

| Level | Method | Seeds | Mean Re | Mean Im | Unresolved failures | RG rejects | Pair0 accept | Mean runtime |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| R1 | `no_fb` | 4 | 0.2885818242 | 0.0843695367 | 316 | 54 | 0.432000 | 73.760435 |
| R1 | `fb_norefine` | 4 | -0.0018318526 | 0.0583715410 | 77 | 69 | 0.427500 | 74.874499 |
| R2 | `no_fb` | 10 | 0.0265222881 | 0.0247701103 | 7502 | 1252 | 0.438620 | 729.547965 |
| R2 | `fb_norefine` | 10 | -0.0039843442 | 0.0321239666 | 1770 | 1577 | 0.439860 | 731.171055 |
| R3 | `no_fb` | 32 | 0.0201887921 | -0.0049858728 | 120858 | 19197 | 0.438043 | 3433.969112 |
| R3 | `fb_norefine` | 32 | 0.0001684020 | 0.0015007415 | 28206 | 24927 | 0.438588 | 4066.603039 |
| R4 | `no_fb` | 128 | 0.0067843097 | -0.0026896585 | 962417 | 152279 | 0.438617 | 7689.963103 |
| R4 | `fb_norefine` | 128 | -0.0011736472 | -0.0012498974 | 224580 | 200530 | 0.438762 | 8486.587849 |

## Accepted Refactor Scopes

These packages may protect:

- behavior-preserving code hygiene
- non-physics utility cleanup
- config/provenance refactors preserving config semantics
- read-only reference comparison tooling
- architecture/API refactor slices preserving current route, RNG order, schema meaning, and counters
- state/status cleanup only when comparison checks explicitly cover affected outputs

Still decision-gated:

- RNG stream ownership changes
- public output schema removal or renaming
- method naming migration from raw `fb_norefine` to public `withfb` or algorithm id
- wrapper replacing Stage2/Stage3 public behavior
- counter timing or meaning changes
- changes to proposal construction, solver route order, tolerances, or final-flow policy

## Next Step

Proceed from the workstream matrix:

```text
Completed foundation -> Accepted M6 reference baseline -> Remaining modernization blocks
```

Recommended immediate sequence:

1. Add/formalize read-only comparison tooling against these accepted packages.
2. Start the next low-risk modernization block, preferably public naming/schema design or non-physics utility/API cleanup, before RNG/reentrancy/state ownership.

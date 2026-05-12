# Schema And Reference F7/F8 Completion

Updated: 2026-05-12 JST

## Status

F7/F8 are implemented for the conservative pre-redo gate. They are not being
left as reduced-scope caveats.

M4 now runs `f14_complete_pre_redo_gate.py`, which validates the F7 schema and
F8 patch-local reference statement before F14 can proceed.

## F7 Public Naming And Schema Boundary

The pre-redo public method names are frozen in:

```text
codex/workspaces/fortran_modernization/schema/F7_METHOD_ALIASES_V1.json
```

Canonical public names:

| Canonical | Raw compatibility aliases |
| --- | --- |
| `nofb` | `no_fb`, `nofb` |
| `withfb` | `fb_norefine`, `withfb` |

Policy:

- public reports use canonical `nofb` and `withfb`;
- raw names remain accepted as compatibility aliases;
- no v0/raw-name field removal is allowed before a future v2 schema decision.

## F8 Reference Comparison Boundary

Patch-local reference statements are frozen in:

```text
codex/workspaces/fortran_modernization/schema/F8_PATCH_REFERENCE_STATEMENT_V1.json
```

The current gate wrote:

```text
output/tests/m4_guardrails/f14_complete_pre_redo_gate/F8_patch_reference_statement.json
```

Current patch classification:

- `behavior_level`: `behavior_relevant`
- `affected_surfaces`: `counters`, `flow_policy`, `guardrail`,
  `reverse_gate`, `schema`, `solver_route`, `wrapper`
- `allowed_drift`: `explicitly_accepted_assist_default_off`
- `decision`: `pass`

Reference anchors:

- `codex/workspaces/fortran_modernization/state/M6_REFERENCE_COMPARISON_SUMMARY.tsv`
- `codex/workspaces/fortran_modernization/runbooks/M6_REFERENCE_COMPARISON_REPORT_20260511.md`

## Verification

```bash
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

Readback:

- F14 complete gate passed inside M4.
- M6 reference summary contains both `nofb` and `withfb` for R1-R4.
- The current patch-local F8 statement passed without reduced-scope wording.

## Reopen Conditions

Reopen F7/F8 only if public method taxonomy, schema compatibility policy,
reference baselines, behavior-drift policy, or production wrapper semantics
change.

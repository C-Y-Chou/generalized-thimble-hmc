# Diagnostics Status Accounting F4 Completion

Updated: 2026-05-12 JST

## Status

F4 is implemented for the conservative pre-redo gate. It is not being left as a
reduced-scope compatibility caveat.

## Implemented Typed Context

The local-transition typed event source is:

```text
src/sampler/tltm_types.f90:tltm_local_transition_event_t
```

`record_tltm_local_transition(...)` now constructs a
`tltm_local_transition_event_t` and derives local accept/reject and typed
rejection counters from that event. The old call signature is preserved for
callers, so this is a behavior-neutral accounting refactor.

Typed event fields:

| Field | Role |
| --- | --- |
| `schema_version` | local-transition diagnostics schema version |
| `context_id` | event context, currently local transition |
| `counter_denominator` | one Stage2 local Metropolis transition |
| `transition_status` | status code from `markovchain_transition_status` |
| `accepted` | live-state update role |
| `proposal_failed` | legacy compatibility projection-failure denominator |

## Audit Schema

The file

```text
codex/workspaces/fortran_modernization/schema/F4_LOCAL_TRANSITION_AUDIT_V1.json
```

freezes the local-transition audit context and columns, including chart
coordinates `q_initial`, `c_initial`, `q_proposal`, `c_proposal`, and `q_after`.

M4 enables a tiny Stage3 sidecar smoke with:

```text
TLTM_LOCAL_TRANSITION_AUDIT_BASE_DIR=<stage3_out>/local_transition_audit
TLTM_LOCAL_TRANSITION_AUDIT_MAX_ROWS=200
```

and validates:

- exact audit header against `F4_LOCAL_TRANSITION_AUDIT_V1`;
- sequential `row_index`;
- accepted/proposal-failed/status consistency;
- finite Hamiltonian/chart coordinate fields;
- nonnegative route/counter deltas;
- `rg_candidate_delta = rg_pass_delta + rg_reject_delta`;
- Stage3 reverse-gate summary candidate/pass/reject identities.

## Verification

```bash
make -C build FC=gfortran LDFLAGS= test_retained_core_rg_reject_identity
python3 scripts/run_m4_guardrails.py --repo-root . --fc gfortran --ldflags '' --keep-going
```

Readback:

- `test_retained_core_rg_reject_identity` passed with typed event context and
  stay-put reverse-gate rejection accounting.
- M4 passed `F14 complete pre-redo gate validates F3/F4/F7/F8`.
- Typed audit file:
  `output/tests/m4_guardrails/stage3_sidecar_on/local_transition_audit/no_fb/seed_20260421/local_transition_audit.csv`
  had 8 validated rows.

## Reopen Conditions

Reopen F4 only if local-transition status codes, counter meanings, sidecar
schema, audit row semantics, or proposal/rejection accounting rules change.

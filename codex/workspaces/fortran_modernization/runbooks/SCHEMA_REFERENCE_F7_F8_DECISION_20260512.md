# Schema And Reference F7/F8 Decision

Updated: 2026-05-12 JST

## F7 Public Naming And Schema Boundary

Before final production regeneration, choose one of these schema policies:

- Freeze a final schema version and canonical public method names now, with
  current raw names retained as compatibility aliases.
- Keep the current v0/v1alpha compatibility schema for the next production redo
  and explicitly label the output as reduced-scope rather than final public
  schema.

Until that choice is made:

- do not remove or rename existing v0 fields;
- do not claim current method labels are the final publication taxonomy;
- keep official DFO-LS provenance and assist policy explicit in manifests and
  reports.

## F8 Reference Comparison Boundary

Before behavior-relevant source patches resume after F14, require a patch-local
comparison statement:

```text
behavior_level: no_physics_change | diagnostic_only | behavior_relevant
affected_surfaces: solver_route | reverse_gate | flow_policy | rng | counters | schema | wrapper
baseline: M6 historical/internal | official_DFO-LS representative | narrower accepted local guardrail
commands: <exact commands run>
allowed_drift: exact | tolerance_bound | explicitly accepted
decision: pass | reduced_scope_accepted | blocked
```

For final production regeneration, either complete this F8 harness and schema
freeze first, or explicitly accept that the next production redo is operating on
the current compatibility layer.

## F14 Link

F7/F8 do not need more hidden audit before the next step. They need the same F14
decision as F3/F4: conservative completion first, or reduced-scope production
redo acceptance.

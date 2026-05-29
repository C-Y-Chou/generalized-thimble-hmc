# WV Legacy Residue Audit

Date: 2026-05-28

Scope: current TLTM modernization source tree.  The purpose is to identify old
handwritten or stale WV-HMC-related residue before the repo hygiene step, so the
future WV-HMC implementation can be added from the simplified-algorithm contract
instead of inheriting stale code.

Closure update, 2026-05-29: the stale source-level `wv` runtime config residue
listed below has been removed from canonical source.  This audit remains the
record of what was found and why the old flag must not be reused.

## Search Result

Searches over source, tests, scripts, docs, and runtime parameter files found no
current executable implementation of:

- worldvolume state `(t, x, z, pi)`;
- worldvolume projection using `xi_n`;
- WV force with `W(t)` or `W'(t)`;
- WV simplified RATTLE solve for `(h, u, lambda)`;
- WV boundary bounce;
- WV measurement subinterval or `alpha^{-1}` weight.

## Residues Found

### Dead Runtime Flag

File:

- `src/config/param_mod.f90`

Residue:

```text
runtime_flags_t%wv
legacy global logical wv
key parser case "wv"
sync_legacy_from_config: wv = config%flags%wv
```

Observed usage:

- no active source module imports or branches on `wv`;
- `data/parameters.dat` does not set `wv`;
- one generated historical output parameter file contains `wv = false`.

Classification:

```text
resolved delete candidate / legacy config residue
```

Hygiene action:

- removed `runtime_flags_t%wv`, legacy global logical `wv`, and
  `config%flags%wv` synchronization from `src/config/param_mod.f90`;
- removed the `"wv"` parser write path.  Historical `wv = false` parameters now
  fall through the existing unknown-key warning path and have no semantics;
- do not reuse this flag name as the future WV-HMC switch.

### Stale Project Documentation Claim

File:

- `docs/readme.md`

Residue:

```text
# WV-HMC Fortran Project
This repository implements a worldvolume-HMC workflow...
```

Observed state:

- this conflicts with the current source audit;
- the repo currently contains TLTM/GT-HMC-style fixed-flow RATTLE code, not a
  complete WV-HMC transition kernel.

Classification:

```text
documentation correction required
```

Required hygiene action:

- rewrite the project title/summary to describe the current TLTM modernization
  state;
- mention WV-HMC only as a planned sibling sampler after canonical TLTM closure.

## Hygiene Gate

The modernization hygiene step must explicitly clear these residues before the
new WV-HMC work starts.

Minimum exit criteria:

- no canonical runtime config key named `wv` remains unless it is part of the new
  paper-derived WV-HMC schema: satisfied for current source;
- no documentation claims that the current TLTM code already implements WV-HMC;
- any old WV-HMC-related code, if discovered later, is classified as
  `legacy/archive` or `delete candidate`;
- new WV-HMC code is introduced only through
  `WV_HMC_SIMPLIFIED_ALGORITHM_READBACK_20260528.md`.

## Future WV-HMC Insertion Rule

Do not resurrect old `wv` flag semantics.  The future implementation should add
a sibling sampler with explicit components:

- WV state `(t, x, z, pi)`;
- `W(t)` / `W'(t)` / boundary schema;
- WV projection;
- WV simplified RATTLE `(h, u, lambda)`;
- WV measurement weights and subinterval policy;
- WV-specific diagnostics.

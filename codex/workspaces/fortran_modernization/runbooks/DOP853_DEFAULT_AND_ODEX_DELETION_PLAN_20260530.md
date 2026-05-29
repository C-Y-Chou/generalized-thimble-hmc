# DOP853 Default and ODEX Deletion Plan 2026-05-30

## Decision

DOP853 is the default active `flow_at` endpoint backend.

Unset `TLTM_ODE_BACKEND` and `TLTM_ODE_BACKEND=default` now resolve to
`dop853`.  The legacy handwritten endpoint ODEX backend remains available only
through an explicit `TLTM_ODE_BACKEND=odex` opt-in while the deletion slice is
prepared.

## Why

The WV-HMC bank-initialized validation run `17928.anode01` completed and
validated the initial-bank path, but the WV-HMC PBS wrapper did not force
`TLTM_ODE_BACKEND=dop853`.  Because the core default was still ODEX, that run
cannot be used as DOP853 WV-HMC runtime evidence.

The modernization product route should not rely on per-PBS remember-to-export
behavior.  The default must live in source policy, with wrappers only echoing
and pinning the intended default for provenance.

## Implemented Default Changes

- `odex_options%backend` default is `odex_backend_kind_dop853`.
- `odex_default_options` initializes `options%backend` to DOP853.
- `TLTM_ODE_BACKEND=default` resolves to DOP853.
- `TLTM_ODE_BACKEND=odex` remains an explicit legacy override.
- Stage2 sidecar policy resolution defaults to `dop853_endpoint_v1`.
- Product wrapper route identity uses `flow_policy_id=dop853_endpoint_v1`.
- WV-HMC pilot, observable-validation, and initial-bank PBS wrappers export and
  echo DOP853 backend controls.

## ODEX Status

ODEX is now legacy.  It is not the active default and should not be used for new
production-shaped TLTM or WV-HMC evidence unless the run is explicitly labeled
as an ODEX legacy comparison.

The remaining ODEX source is kept temporarily because it still owns:

- historical endpoint-controller tests;
- ODEX-specific diagnostic counters and result contracts;
- historical PBS/readback artifacts;
- explicit legacy comparison paths.

## Deletion Schedule

### Phase 1: Default Isolation

Status: implemented in this slice.

Requirements:

- DOP853 is the source default.
- PBS wrappers needed for current WV-HMC work explicitly export DOP853.
- Product sidecars identify DOP853 as the default flow policy.
- ODEX can only be selected by explicit `TLTM_ODE_BACKEND=odex`.

### Phase 2: Naming and Diagnostics Split

Goal: remove misleading generic use of `odex_*` names from DOP853 paths before
source deletion.

Tasks:

- Introduce neutral `ode_backend_*` or `flow_backend_*` naming for result and
  diagnostics types used by both DOP853 and legacy ODEX.
- Preserve historical ODEX counter columns only in archived/historical
  readbacks.
- Update product manifests and readbacks so DOP853 counters are not reported as
  ODEX runtime evidence.

### Phase 3: Historical Quarantine

Goal: make ODEX-only tests/scripts explicitly non-product.

Tasks:

- Move ODEX controller package tests into a legacy/historical target group.
- Keep only a minimal compile/API guard while any source remains.
- Mark ODEX PBS wrappers and ODEX readback scripts as historical comparison
  only in the script-evidence audit.
- Remove ODEX from current production and WV-HMC SOPs.

### Phase 4: Source Deletion

Goal: delete the handwritten ODEX endpoint integrator.

Tasks:

- Remove `odex_backend_kind_odex`.
- Remove `odex_integrate_endpoint` ODEX-controller branches, or split the file
  so DOP853 survives under neutral naming without legacy ODEX code.
- Remove ODEX controller policy aliases such as `tltm_endpoint` and
  `hairer_odex`.
- Delete or archive ODEX-only tests/PBS wrappers.
- Run the current source gate on cluster after deletion.

## Verification Required Before Source Deletion

Before removing ODEX source, run cluster-gated checks for:

- DOP853 default smoke with `TLTM_ODE_BACKEND` unset.
- WV-HMC bank-init smoke with DOP853 default.
- WV-HMC bank-init observable validation rerun, replacing `17928` as runtime
  evidence.
- Stage2 sidecar/product wrapper validation showing
  `flow_policy_id=dop853_endpoint_v1`.
- Script-evidence audit after ODEX historical quarantine or deletion.

## Verification Completed In This Slice

Cluster job `17929.anode01` completed with `Exit_status=0` on `cnode17` at
commit `42fb257075c8ea31228cc049c907f1f9c1a9f34a`.

Scope:

- submitted through `codex/agents/cluster02_scheduler/cluster02_qsub_gate.sh`;
- `TLTM_ODE_BACKEND` was unset inside the PBS job;
- `test_odex_result_contract` passed and printed
  `default_options ok=T backend=2`;
- WV-HMC math and constraint kernel tests passed;
- a one-cycle WV-HMC dense pilot scan completed with `TLTM_ODE_BACKEND` unset.

Artifacts:

```text
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/logs/wv_hmc_dop853_default_smoke_20260530/dop853_default_source_smoke_20260530/pbs_boot_17929.anode01.log
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_dop853_default_smoke_20260530/dop853_default_source_smoke_20260530_17929.anode01/dense_pilot_scan_summary.csv
/lustre1/home/cychou/TLTM_worktrees/fortran_modernization/output/wv_hmc_dop853_default_smoke_20260530/dop853_default_source_smoke_20260530_17929.anode01/dense_pilot_scan_readback.md
```

This verifies the source default and the WV-HMC dense smoke path.  It does not
replace the full WV-HMC bank-initialized observable validation that previously
ran as `17928.anode01`, because that run predated the DOP853-default correction.

## Interpretation Rule

Old ODEX runs remain valid historical evidence for the source state they tested.
They do not define the current default backend and must not be used as current
DOP853 runtime evidence.

# Flow Backend

The public product path uses DOP853 as the flow ODE backend.

For WV-HMC runs launched through:

```bash
python3 scripts/run_tltm_product.py wv-hmc ...
```

the wrapper pins:

```text
TLTM_ODE_BACKEND=dop853
```

No additional backend selection is required for normal public use.

## DOP853 Role

DOP853 is the default backend for flow integration in the public WV-HMC path.
It is used for endpoint flow and dense-output flow operations needed by the
current dense explicit-J WV-HMC implementation.

Public validation should therefore record DOP853 as part of the run metadata.
If a result was produced without the product wrapper, record the value of
`TLTM_ODE_BACKEND` explicitly.

## Legacy Backend Scope

The source tree still contains historical `odex` names in implementation
modules, tests, diagnostics, and telemetry fields.  Those names are legacy
implementation surface, not the normal user-facing backend path.

Do not configure new public examples around legacy ODEX behavior.  Remaining
cleanup is scoped as technical work:

- keep DOP853 as the default public path;
- quarantine or delete ODEX-only tests and scripts only after an accepted
  DOP853-default validation gate;
- replace legacy ODEX-specific diagnostic names with neutral flow-backend names
  where they appear in public output;
- delete handwritten ODEX source only after affected baselines are reviewed.

Until that technical cleanup is complete, public documentation should describe
the shipped backend as DOP853 and avoid presenting legacy ODEX as a supported
user workflow.

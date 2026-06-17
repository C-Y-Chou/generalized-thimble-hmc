# Changelog

## 2026-06-18 - DOP853 Public Surface Cleanup

- Documented DOP853 as the public flow-backend path.
- Clarified that legacy ODEX names are implementation and telemetry cleanup
  surface, not the normal user workflow.
- Scoped remaining ODEX deletion/quarantine work behind a DOP853-default
  validation gate.

## 2026-06-18 - Model Provider Onboarding Contract

- Expanded the public model-provider contract for new physics models.
- Added a model-specification template for action, manual gradient,
  Hessian-vector product, observables, and small-reference validation.
- Clarified that model choice stays out of canonical sampler kernels.

## 2026-06-16 - WV-HMC Public Validation Path

- Set dense WV-HMC public defaults to `normal_reflect` boundary handling.
- Kept `full_bounce` / `paper_full_flip` as optional benchmark behavior, not
  the product default.
- Added a public validation route for dense explicit-J WV-HMC smoke and
  benchmark-style checks.
- Clarified the current claim boundary: TLTM is the mature production workflow;
  dense explicit-J WV-HMC is validated for Stephanov benchmark development and
  is not yet a high-dimensional production-performance path.

## 2026-06-03 - Productization Staging

- Removed local cluster assumptions from public documentation.
- Added product-facing build, test, and runner entry points.
- Consolidated user-facing terminology around generalized thimble HMC, TLTM,
  GT-HMC, and WV-HMC.

# Changelog

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

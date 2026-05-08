# ODEX Location Guide

Updated: 2026-05-08 JST

Reference source:
- `Hairer_Norsett_Wanner_SODE_I_Nonstiff_Problems_full.pdf`

Convenience excerpts:
- `Hairer_SODE_I_II9_Extrapolation_Methods_pdfpages_237_270.pdf`
  - Main target for ODEX/extrapolation-method review.
  - Contains Chapter II.9 material on extrapolation methods and the ODEX step-number discussion region.

- `Hairer_SODE_I_Appendix_Subroutine_ODEX_pdfpages_494_496.pdf`
  - Appendix/code-location excerpt for Subroutine ODEX.

Text-search anchors observed in the full PDF:
- `II.9 Extrapolation Methods`: PDF pages 237-256 region.
- `Effect of Step-Number Sequence in ODEX`: PDF page 269.
- `Subroutine ODEX`: PDF pages 494-496 region.

Use this guide before reviewing `src/physics/solve_flow.f90`. The modernization question is not only whether the code is clean, but whether its flow/inverse-flow integration contract, tolerance semantics, and failure handling remain faithful to the ODEX/extrapolation method role used by TLTM.

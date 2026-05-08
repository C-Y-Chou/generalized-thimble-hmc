# Algorithm References Index

Updated: 2026-05-08 JST

This directory collects the algorithm references needed for behavior-preserving TLTM Fortran modernization. Keep this bundle stable so future Codex conversations can reconstruct the theory map even after chat compression.

## Collected PDFs
- `1912.13303_TLTM_HMC.pdf`
  - Role: TLTM / tempered Lefschetz thimble HMC main framework.
  - Source copy: `/home/cychou/TLTM/docs/1912.13303 Implementation of the HMC algorithm on the tempered Lefschetz thimble method.pdf`

- `2311.10663v4.pdf`
  - Role: simplified Newton, RATTLE, GT-HMC / WV-HMC reference.
  - Source copy: `/Users/ccy/Downloads/2311.10663v4.pdf`

- `s12532-019-00161-7_DFO_GN.pdf`
  - Role: derivative-free Gauss-Newton theory for nonlinear least-squares.
  - Source copy: `/home/cychou/TLTM/docs/s12532-019-00161-7.pdf`

- `1804.00154v2.pdf`
  - Role: DFO-LS robustness, software extensions, restarts, noisy/expensive objective handling.
  - Source copy: `/Users/ccy/Downloads/1804.00154v2.pdf`

- `new_algorithm__Copy_.pdf`
  - Role: project-specific original quasi-Newton projection-loss / parametrization-layer design.
  - Source copy: `/Users/ccy/Downloads/new_algorithm__Copy_.pdf`

## ODE / ODEX reference
- `Hairer_Norsett_Wanner_SODE_I_Nonstiff_Problems_full.pdf`
  - Role: full Hairer, Norsett, Wanner reference for nonstiff ODE methods, including extrapolation/ODEX context.
  - Source copy: `/Users/ccy/Documents/paper/GTM/(Springer Series in Computational Mathematics 8) Ernst Hairer, Gerhard Wanner, Syvert P. Norsett (auth.) - Solving Ordinary Differential Equations I_ Nonstiff Problems. Volume 1-Springer-Verlag Berlin.pdf`

- `Hairer_SODE_I_II9_Extrapolation_Methods_pdfpages_237_270.pdf`
  - Role: focused excerpt for Chapter II.9 extrapolation methods and ODEX step-number discussion.

- `Hairer_SODE_I_Appendix_Subroutine_ODEX_pdfpages_494_496.pdf`
  - Role: focused appendix excerpt around Subroutine ODEX.

- `ODEX_LOCATION_GUIDE.md`
  - Role: page-location guide for future `solve_flow.f90` review.

## Usage rule
Before reviewing or refactoring core algorithms, read `ALGORITHM_TO_IMPLEMENTATION_REVIEW_MAP.md` and the relevant PDFs here. Do not treat DFO-GN/DFO-LS references as replacements for the project-specific projection-loss design.

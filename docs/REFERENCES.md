# References

This repository uses the terminology of the generalized-thimble and
worldvolume-HMC literature.  For external reuse, cite this repository together
with the algorithm papers relevant to the run and the exact commit hash.

## Core Algorithm Papers

- M. Fukuma and N. Umeda, "Parallel tempering algorithm for integration over
  Lefschetz thimbles," arXiv:1703.00861.
  This is the origin of using flow time as the tempering parameter.
- M. Fukuma, N. Matsumoto, and N. Umeda, "Implementation of the HMC algorithm on
  the tempered Lefschetz thimble method," arXiv:1912.13303.
  This is the closest reference for TLTM with HMC transitions on flowed
  surfaces.
- M. Fukuma, N. Matsumoto, and N. Umeda, "Tempered Lefschetz thimble method and
  its application to the Hubbard model away from half filling,"
  arXiv:2001.01665.
  This is a compact physics-facing TLTM overview and application reference.
- M. Fukuma and N. Matsumoto, "Worldvolume approach to the tempered Lefschetz
  thimble method," Prog. Theor. Exp. Phys. 2021, 023B08, arXiv:2012.08468.
  This is the main WV-HMC reference for sampling the worldvolume of flowed
  surfaces.
- M. Fukuma, N. Matsumoto, and Y. Namekawa, "Worldvolume tempered Lefschetz
  thimble method and its error estimation," arXiv:2111.14669.
  This is the main reference for WV-TLTM statistical analysis and the Stephanov
  model demonstration.
- M. Fukuma, "Simplified algorithm for the Worldvolume HMC and the
  Generalized-thimble HMC," Prog. Theor. Exp. Phys. 2024, 053B02,
  arXiv:2311.10663.
  This is the reference for simplified Newton/RATTLE and matrix-free
  orthogonal-decomposition roadmap work.

## Terminology Used In This Repository

- `antiholomorphic gradient flow`: the flow used to deform the original real
  integration surface.
- `Sigma_t`: the deformed integration surface at flow time `t`.
- `flow time`: the deformation parameter and TLTM tempering parameter.
- `TLTM`: tempered Lefschetz thimble method, implemented here as the canonical
  tempered workflow.
- `GT-HMC`: HMC on a fixed generalized-thimble surface `Sigma_t`.
- `WV-HMC`: HMC on the worldvolume swept out by the family of `Sigma_t`.
- `W(t)`: worldvolume potential controlling the flow-time distribution.
- `RATTLE`: constrained molecular-dynamics update used for WV-HMC/GT-HMC
  projection.
- `measurement factor`: the complex factor used when accumulating observables
  on the deformed surface or worldvolume.

## Citation Template

When using this repository, cite:

1. this repository and commit hash;
2. the model or benchmark paper used for the physics target;
3. the TLTM paper if using the tempered ladder workflow;
4. the WV-HMC and simplified WV-HMC papers if using worldvolume trajectories;
5. the exact output manifest and run directory for reproducibility.

Example text:

```text
The simulations used Generalized Thimble HMC by CHOU CHIEN YU
(commit <hash>), with terminology and algorithms following the TLTM and
WV-HMC formulations of Fukuma and collaborators.
```

Public validation readbacks and benchmark provenance are kept as compact
packets under `docs/` and `codex/runbooks/`.  Local Codex workspace archives are
not part of the public repository surface.

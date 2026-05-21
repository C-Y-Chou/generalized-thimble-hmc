! Stephanov model action draft. Not compiled from model_specs/.
!
! Production decision:
!   This model must be promoted as a hand-written analytic dense provider,
!   not through the retired generated/autodiff model pipeline.
!
! Likely promotion target after review:
!   src/physics/model_stephanov.f90 or equivalent model-provider module,
!   wired through the stable src/physics/model.f90 facade.
!
! Mathematical action, dropping the constant -n*mu^2:
!
!   S(z) = n sum_ij (Zx_ij**2 + Zy_ij**2)
!        - N_f log det M(z)
!
!   M = [ m I_n    i A ]
!       [ i B      m I_n ]
!
!   A = X + C
!   B = Xsharp + C
!   X      = Zx + i Zy
!   Xsharp = transpose(Zx) - i transpose(Zy)
!
!   i C = diag((mu + i tau) I_{n/2}, (mu - i tau) I_{n/2})
!
! Important:
!   Xsharp is the holomorphic continuation of the original X dagger.
!   Do not use conjg(transpose(X)) in the promoted action or force.
!
! Required promoted helpers:
!   - decode z(:) into Zx(n,n), Zy(n,n) using Fortran column-major order.
!   - build C diagonal.
!   - build dense complex Dirac matrix M(2*n,2*n), or use Schur-complement
!     logdet logic.
!   - compute logdet(M) with a dense complex LU helper.
!   - compute ds and hessian_vec analytically from dense matrix identities.
!
! AD/FD use:
!   AD and finite differences are validation oracles only. They must test
!   random genuinely complexified Zx,Zy points, not only real t=0 configurations.
!
! Pseudocode:
!
!   call decode_stephanov_state(z, Zx, Zy)
!   X      = Zx + ci * Zy
!   Xsharp = transpose(Zx) - ci * transpose(Zy)
!
!   gaussian = sum(Zx**2 + Zy**2)
!   call build_stephanov_c_diag(mu, tau, Cdiag)
!   call build_stephanov_dirac_matrix(X, Xsharp, Cdiag, m, M)
!   logdet_m = dense_complex_logdet(M)
!
!   s = cmplx(n, 0.0_dp, dp) * gaussian
!   s = s - cmplx(N_f, 0.0_dp, dp) * logdet_m
!   if (include_mu_prefactor) s = s - cmplx(n, 0.0_dp, dp) * mu**2
!
! Placeholder keeps the draft inert if read by tooling.
s = zero

! Stephanov model observable-body draft. Not compiled from model_specs/.
!
! Production decision:
!   Promote this as part of the hand-written Stephanov model provider, sharing
!   decode/Xsharp/A/B/K helpers with action, ds, and hessian_vec.
!
! Pointwise definitions:
!
!   A = X + C
!   B = Xsharp + C
!   K = inverse(B A + m^2 I)
!
!   chiral_condensate = (m/n) tr K
!   number_density    = mu - (i/(2n)) tr K(A+B)
!
! These are pointwise model observables. The sampler/evaluator must still
! apply the GTM/TLTM Jacobian and residual-phase reweighting when forming final
! estimates.
!
! Important:
!   Xsharp = transpose(Zx) - i transpose(Zy)
!   not conjg(transpose(X)).
!
! Pseudocode:
!
!   call decode_stephanov_state(z, Zx, Zy)
!   X      = Zx + ci * Zy
!   Xsharp = transpose(Zx) - ci * transpose(Zy)
!   call build_stephanov_c_diag(mu, tau, Cdiag)
!   A = X
!   B = Xsharp
!   do i = 1, n
!      A(i,i) = A(i,i) + Cdiag(i)
!      B(i,i) = B(i,i) + Cdiag(i)
!   end do
!
!   BA = matmul(B, A)
!   do i = 1, n
!      BA(i,i) = BA(i,i) + m*m
!   end do
!   K = inverse(BA)
!
!   observables(1) = cmplx(m / n, 0.0_dp, dp) * trace(K)
!   observables(2) = cmplx(mu, 0.0_dp, dp) &
!                    - ci / cmplx(2*n, 0.0_dp, dp) * trace(matmul(K, A + B))
!   observables(3) = dense_complex_logdet(M)
!   observables(4) = exp(-ci * aimag(s_action))
!   observables(5) = cmplx(min_singular_value(BA), 0.0_dp, dp)
!
! Placeholder keeps the draft inert if read by tooling.
observables = cmplx(0.0_dp, 0.0_dp, dp)

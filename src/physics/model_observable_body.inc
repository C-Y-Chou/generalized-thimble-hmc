observables = cmplx(0.0_dp, 0.0_dp, dp)
do i = 1, size(z)
   z_val = z(i)
   observables(1) = observables(1) - ci*(z_val - ci*beta)*(z_val**2 + alpha) - 2.0_dp
   observables(2) = observables(2) + z_val
end do

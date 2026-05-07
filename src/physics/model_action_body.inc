s = zero
do i = 1, size(z)
   s = s - ci*(z(i)**3/three + z(i)*alpha) - log(z(i) - ci*beta)
end do

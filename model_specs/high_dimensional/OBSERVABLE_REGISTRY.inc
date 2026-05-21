! Stephanov model observable registry draft. Not compiled from model_specs/.
!
! Promotion target after review:
!   provider-owned observable metadata exposed through
!   src/physics/model_observables.f90
!
! Required physics observables:
!   chiral_condensate = (m/n) tr K
!   number_density    = mu - (i/(2n)) tr K(A+B)
!
! Useful diagnostics:
!   logdet_dirac        = log det M
!   phase_factor        = exp(-i Im S)
!   min_singular_ba_m2  = min singular value(B A + m^2 I)
!
! Proposed promoted registry:
!
! integer, parameter :: model_observable_count_value = 5
! character(len=model_observable_name_len), parameter :: model_observable_names(model_observable_count_value) = [ &
!    character(len=model_observable_name_len) :: "chiral_condensate", "number_density", &
!                                                "logdet_dirac", "phase_factor", &
!                                                "min_singular_ba_m2" &
! ]

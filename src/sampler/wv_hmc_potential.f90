module wv_hmc_potential
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use utils, only: dp
   implicit none

   private
   public :: wv_potential_profile_t, wv_potential_paper_wall, wv_potential_polynomial, wv_potential_zero
   public :: wv_potential_value_and_derivative

   integer, parameter :: wv_potential_kind_polynomial = 1
   integer, parameter :: wv_potential_kind_paper_wall = 2

   type :: wv_potential_profile_t
      integer :: kind = wv_potential_kind_polynomial
      real(dp) :: constant = 0.0_dp
      real(dp) :: linear = 0.0_dp
      real(dp) :: quadratic = 0.0_dp
      real(dp) :: t0 = 0.0_dp
      real(dp) :: t1 = 0.0_dp
      real(dp) :: d0 = 0.0_dp
      real(dp) :: d1 = 0.0_dp
      real(dp) :: gamma = 0.0_dp
      real(dp) :: c0 = 0.0_dp
      real(dp) :: c1 = 0.0_dp
   end type wv_potential_profile_t

contains

   function wv_potential_zero() result(profile)
      type(wv_potential_profile_t) :: profile

      profile%kind = wv_potential_kind_polynomial
      profile%constant = 0.0_dp
      profile%linear = 0.0_dp
      profile%quadratic = 0.0_dp
   end function wv_potential_zero

   function wv_potential_polynomial(constant, linear, quadratic) result(profile)
      real(dp), intent(in) :: constant, linear, quadratic
      type(wv_potential_profile_t) :: profile

      profile%kind = wv_potential_kind_polynomial
      profile%constant = constant
      profile%linear = linear
      profile%quadratic = quadratic
   end function wv_potential_polynomial

   function wv_potential_paper_wall(t0, t1, d0, d1, gamma, c0, c1) result(profile)
      real(dp), intent(in) :: t0, t1, d0, d1, gamma, c0, c1
      type(wv_potential_profile_t) :: profile

      profile%kind = wv_potential_kind_paper_wall
      profile%t0 = t0
      profile%t1 = t1
      profile%d0 = d0
      profile%d1 = d1
      profile%gamma = gamma
      profile%c0 = c0
      profile%c1 = c1
   end function wv_potential_paper_wall

   subroutine wv_potential_value_and_derivative(profile, flow_time, value, derivative, error)
      type(wv_potential_profile_t), intent(in) :: profile
      real(dp), intent(in) :: flow_time
      real(dp), intent(out) :: value, derivative
      logical, intent(out) :: error

      value = 0.0_dp
      derivative = 0.0_dp
      error = .true.
      if ((.not. ieee_is_finite(flow_time)) .or. flow_time < 0.0_dp) return

      select case (profile%kind)
      case (wv_potential_kind_polynomial)
         call polynomial_value_and_derivative(profile, flow_time, value, derivative, error)
      case (wv_potential_kind_paper_wall)
         call paper_wall_value_and_derivative(profile, flow_time, value, derivative, error)
      case default
         return
      end select
      if (error) return
      if ((.not. ieee_is_finite(value)) .or. (.not. ieee_is_finite(derivative))) then
         value = 0.0_dp
         derivative = 0.0_dp
         return
      end if
      error = .false.
   end subroutine wv_potential_value_and_derivative

   subroutine polynomial_value_and_derivative(profile, flow_time, value, derivative, error)
      type(wv_potential_profile_t), intent(in) :: profile
      real(dp), intent(in) :: flow_time
      real(dp), intent(out) :: value, derivative
      logical, intent(out) :: error

      value = 0.0_dp
      derivative = 0.0_dp
      error = .true.
      if ((.not. ieee_is_finite(profile%constant)) .or. (.not. ieee_is_finite(profile%linear)) .or. &
          (.not. ieee_is_finite(profile%quadratic))) return

      value = profile%constant + profile%linear*flow_time + 0.5_dp*profile%quadratic*flow_time*flow_time
      derivative = profile%linear + profile%quadratic*flow_time
      error = .false.
   end subroutine polynomial_value_and_derivative

   subroutine paper_wall_value_and_derivative(profile, flow_time, value, derivative, error)
      type(wv_potential_profile_t), intent(in) :: profile
      real(dp), intent(in) :: flow_time
      real(dp), intent(out) :: value, derivative
      logical, intent(out) :: error

      real(dp) :: distance, denominator, exponent, exp_value

      value = 0.0_dp
      derivative = 0.0_dp
      error = .true.
      if (.not. all(ieee_is_finite([profile%t0, profile%t1, profile%d0, profile%d1, profile%gamma, &
                                    profile%c0, profile%c1]))) return
      if (profile%t1 <= profile%t0) return
      if (profile%d0 <= 0.0_dp .or. profile%d1 <= 0.0_dp) return
      if (profile%gamma < 0.0_dp .or. profile%c0 < 0.0_dp .or. profile%c1 < 0.0_dp) return

      value = -profile%gamma*(flow_time - profile%t0)
      derivative = -profile%gamma
      if (flow_time < profile%t0) then
         distance = flow_time - profile%t0
         denominator = profile%d0*profile%d0
         exponent = 0.5_dp*distance*distance/denominator
         if (exponent > log(huge(1.0_dp)) - 1.0_dp) return
         exp_value = exp(exponent)
         value = value + profile%c0*(exp_value - 1.0_dp)
         derivative = derivative + profile%c0*exp_value*distance/denominator
      else if (flow_time > profile%t1) then
         distance = flow_time - profile%t1
         denominator = profile%d1*profile%d1
         exponent = 0.5_dp*distance*distance/denominator
         if (exponent > log(huge(1.0_dp)) - 1.0_dp) return
         exp_value = exp(exponent)
         value = value + profile%c1*(exp_value - 1.0_dp)
         derivative = derivative + profile%c1*exp_value*distance/denominator
      end if
      error = .false.
   end subroutine paper_wall_value_and_derivative

end module wv_hmc_potential

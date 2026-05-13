module tltm_rng
   use, intrinsic :: iso_fortran_env, only: int64
   use mt95, only: mt95_seed_state, mt95_state_t
   implicit none
   private

   public :: tltm_rng_domain_stage2_init
   public :: tltm_rng_domain_stage2_local_momentum
   public :: tltm_rng_domain_stage2_local_accept
   public :: tltm_rng_domain_stage2_swap_accept
   public :: tltm_seed_kernel_state
   public :: tltm_kernel_seed

   integer, parameter :: tltm_rng_domain_stage2_init = 1101
   integer, parameter :: tltm_rng_domain_stage2_local_momentum = 1102
   integer, parameter :: tltm_rng_domain_stage2_local_accept = 1103
   integer, parameter :: tltm_rng_domain_stage2_swap_accept = 1104

   integer(int64), parameter :: seed_modulus = 2147483647_int64
   integer(int64), parameter :: seed_range = seed_modulus - 1_int64

contains

   subroutine tltm_seed_kernel_state(state, domain_id, base_seed, cycle_idx, lane_id, update_idx)
      type(mt95_state_t), intent(out) :: state
      integer, intent(in) :: domain_id, base_seed, cycle_idx, lane_id, update_idx

      call mt95_seed_state(state, tltm_kernel_seed(domain_id, base_seed, cycle_idx, lane_id, update_idx))
   end subroutine tltm_seed_kernel_state

   integer function tltm_kernel_seed(domain_id, base_seed, cycle_idx, lane_id, update_idx) result(seed_value)
      integer, intent(in) :: domain_id, base_seed, cycle_idx, lane_id, update_idx
      integer(int64) :: h

      h = 1779033703_int64
      call mix_component(h, domain_id)
      call mix_component(h, base_seed)
      call mix_component(h, cycle_idx)
      call mix_component(h, lane_id)
      call mix_component(h, update_idx)
      seed_value = int(modulo(h, seed_range) + 1_int64)
   end function tltm_kernel_seed

   subroutine mix_component(h, value)
      integer(int64), intent(inout) :: h
      integer, intent(in) :: value
      integer(int64) :: v

      v = modulo(int(value, int64), seed_modulus)
      h = modulo(h + 140294673668970197_int64, seed_modulus)
      h = modulo(h + v*1103515245_int64 + 12345_int64, seed_modulus)
      h = modulo(ieor(h, ishft(h, 7)), seed_modulus)
      h = modulo(h*48271_int64 + 1_int64, seed_modulus)
      h = modulo(ieor(h, ishft(h, -11)), seed_modulus)
      h = modulo(h*69621_int64 + 7_int64, seed_modulus)
   end subroutine mix_component

end module tltm_rng

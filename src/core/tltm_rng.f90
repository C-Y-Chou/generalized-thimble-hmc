module tltm_rng
   use, intrinsic :: iso_fortran_env, only: int64, real64
   use mt95, only: mt95_seed_state, mt95_state_t
   implicit none
   private

   public :: tltm_rng_domain_stage2_init
   public :: tltm_rng_domain_stage2_local_momentum
   public :: tltm_rng_domain_stage2_local_accept
   public :: tltm_rng_domain_stage2_swap_accept
   public :: tltm_seed_kernel_state
   public :: tltm_kernel_seed
   public :: tltm_rng_uniform
   public :: tltm_rng_uniform_open
   public :: tltm_rng_fill_normal
   public :: tltm_rng_philox4x32_10

   integer, parameter :: tltm_rng_domain_stage2_init = 1101
   integer, parameter :: tltm_rng_domain_stage2_local_momentum = 1102
   integer, parameter :: tltm_rng_domain_stage2_local_accept = 1103
   integer, parameter :: tltm_rng_domain_stage2_swap_accept = 1104

   real(real64), parameter :: pi = 3.141592653589793238462643383279502884197_real64
   integer(int64), parameter :: uint16_base = 65536_int64
   integer(int64), parameter :: uint32_modulus = 4294967296_int64
   integer(int64), parameter :: uint32_mask = uint32_modulus - 1_int64
   integer(int64), parameter :: philox_m0 = int(z'D2511F53', int64)
   integer(int64), parameter :: philox_m1 = int(z'CD9E8D57', int64)
   integer(int64), parameter :: philox_w0 = int(z'9E3779B9', int64)
   integer(int64), parameter :: philox_w1 = int(z'BB67AE85', int64)

   ! Legacy seeded-MT compatibility path.  The official stage2_kernel_rng_v2
   ! path below is counter-based and does not use this 31-bit seed space.
   integer(int64), parameter :: seed_modulus = 2147483647_int64
   integer(int64), parameter :: seed_range = seed_modulus - 1_int64

   interface to_uint32
      module procedure to_uint32_int
      module procedure to_uint32_int64
   end interface

contains

   subroutine tltm_rng_fill_normal(values, domain_id, base_seed, cycle_idx, lane_id, update_idx)
      real(real64), intent(out) :: values(:)
      integer, intent(in) :: domain_id, base_seed, cycle_idx, lane_id, update_idx

      integer :: i, draw_idx
      real(real64) :: u1, u2, radius, angle

      draw_idx = 1
      i = 1
      do while (i <= size(values))
         u1 = tltm_rng_uniform_open(domain_id, base_seed, cycle_idx, lane_id, update_idx, draw_idx)
         u2 = tltm_rng_uniform_open(domain_id, base_seed, cycle_idx, lane_id, update_idx, draw_idx + 1)
         radius = sqrt(-2.0_real64*log(u1))
         angle = 2.0_real64*pi*u2
         values(i) = radius*cos(angle)
         if (i + 1 <= size(values)) values(i + 1) = radius*sin(angle)
         draw_idx = draw_idx + 2
         i = i + 2
      end do
   end subroutine tltm_rng_fill_normal

   real(real64) function tltm_rng_uniform(domain_id, base_seed, cycle_idx, lane_id, update_idx, draw_idx) result(value)
      integer, intent(in) :: domain_id, base_seed, cycle_idx, lane_id, update_idx, draw_idx

      value = real(tltm_rng_uint32(domain_id, base_seed, cycle_idx, lane_id, update_idx, draw_idx), real64)/ &
              real(uint32_modulus, real64)
   end function tltm_rng_uniform

   real(real64) function tltm_rng_uniform_open(domain_id, base_seed, cycle_idx, lane_id, update_idx, draw_idx) result(value)
      integer, intent(in) :: domain_id, base_seed, cycle_idx, lane_id, update_idx, draw_idx

      value = (real(tltm_rng_uint32(domain_id, base_seed, cycle_idx, lane_id, update_idx, draw_idx), real64) + 0.5_real64)/ &
              real(uint32_modulus, real64)
   end function tltm_rng_uniform_open

   integer(int64) function tltm_rng_uint32(domain_id, base_seed, cycle_idx, lane_id, update_idx, draw_idx) result(word)
      integer, intent(in) :: domain_id, base_seed, cycle_idx, lane_id, update_idx, draw_idx

      integer(int64) :: counter(4), key(2), output(4)
      integer :: block_idx, word_idx

      if (draw_idx < 1) then
         write (*, '(A,I0)') "[ERROR][TLTM-RNG] draw_idx must be >= 1; got ", draw_idx
         error stop 1
      end if

      block_idx = (draw_idx - 1)/4
      word_idx = mod(draw_idx - 1, 4) + 1
      key = [to_uint32(base_seed), to_uint32(domain_id)]
      counter = [to_uint32(cycle_idx), to_uint32(lane_id), to_uint32(update_idx), to_uint32(block_idx)]
      call tltm_rng_philox4x32_10(counter, key, output)
      word = output(word_idx)
   end function tltm_rng_uint32

   subroutine tltm_rng_philox4x32_10(counter, key, output)
      integer(int64), intent(in) :: counter(4), key(2)
      integer(int64), intent(out) :: output(4)

      integer(int64) :: ctr(4), round_key(2)
      integer :: round_idx

      ctr = to_uint32_vec4(counter)
      round_key = [to_uint32(key(1)), to_uint32(key(2))]
      do round_idx = 1, 10
         call philox4x32_round(ctr, round_key)
         round_key(1) = add_uint32(round_key(1), philox_w0)
         round_key(2) = add_uint32(round_key(2), philox_w1)
      end do
      output = ctr
   end subroutine tltm_rng_philox4x32_10

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

   subroutine philox4x32_round(counter, key)
      integer(int64), intent(inout) :: counter(4)
      integer(int64), intent(in) :: key(2)

      integer(int64) :: hi0, lo0, hi1, lo1
      integer(int64) :: c0, c1, c2, c3

      c0 = counter(1)
      c1 = counter(2)
      c2 = counter(3)
      c3 = counter(4)
      call mulhilo_uint32(philox_m0, c0, hi0, lo0)
      call mulhilo_uint32(philox_m1, c2, hi1, lo1)
      counter(1) = xor_uint32(xor_uint32(hi1, c1), key(1))
      counter(2) = lo1
      counter(3) = xor_uint32(xor_uint32(hi0, c3), key(2))
      counter(4) = lo0
   end subroutine philox4x32_round

   subroutine mulhilo_uint32(a, b, hi, lo)
      integer(int64), intent(in) :: a, b
      integer(int64), intent(out) :: hi, lo

      integer(int64) :: a0, a1, b0, b1
      integer(int64) :: p0, p1, p2, p3
      integer(int64) :: carry, mid

      a0 = modulo(a, uint16_base)
      a1 = modulo(a/uint16_base, uint16_base)
      b0 = modulo(b, uint16_base)
      b1 = modulo(b/uint16_base, uint16_base)

      p0 = a0*b0
      p1 = a0*b1
      p2 = a1*b0
      p3 = a1*b1

      mid = p1 + p2 + p0/uint16_base
      lo = modulo(modulo(p0, uint16_base) + modulo(mid, uint16_base)*uint16_base, uint32_modulus)
      carry = mid/uint16_base
      hi = modulo(p3 + carry, uint32_modulus)
   end subroutine mulhilo_uint32

   integer(int64) function to_uint32_int(value) result(word)
      integer, intent(in) :: value

      word = modulo(int(value, int64), uint32_modulus)
   end function to_uint32_int

   integer(int64) function to_uint32_int64(value) result(word)
      integer(int64), intent(in) :: value

      word = modulo(value, uint32_modulus)
   end function to_uint32_int64

   function to_uint32_vec4(values) result(words)
      integer(int64), intent(in) :: values(4)
      integer(int64) :: words(4)

      integer :: i

      do i = 1, 4
         words(i) = modulo(values(i), uint32_modulus)
      end do
   end function to_uint32_vec4

   integer(int64) function add_uint32(a, b) result(value)
      integer(int64), intent(in) :: a, b

      value = modulo(a + b, uint32_modulus)
   end function add_uint32

   integer(int64) function xor_uint32(a, b) result(value)
      integer(int64), intent(in) :: a, b

      value = modulo(ieor(int(a, int64), int(b, int64)), uint32_modulus)
   end function xor_uint32

end module tltm_rng

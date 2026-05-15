program test_tltm_rng_contract
   use, intrinsic :: iso_fortran_env, only: int64, real64
   use tltm_rng, only: tltm_rng_domain_stage2_local_accept, tltm_rng_domain_stage2_local_momentum, &
                       tltm_rng_fill_normal, tltm_rng_philox4x32_10, tltm_rng_uniform, tltm_rng_uniform_open
   implicit none

   integer(int64) :: counter(4), key(2), output(4)
   real(real64) :: expected_uniform, uniform_value, open_value
   real(real64) :: normals_a(5), normals_b(5), normals_c(5)
   real(real64), parameter :: uint32_modulus_real = 4294967296.0_real64

   counter = [0_int64, 0_int64, 0_int64, 0_int64]
   key = [0_int64, 0_int64]
   call tltm_rng_philox4x32_10(counter, key, output)
   call assert_equal_i64_vec(output, [1713891541_int64, 3781805453_int64, 3159862348_int64, 2600524760_int64], &
                             "Philox4x32-10 zero counter/key known-answer vector")

   counter = [1_int64, 2_int64, 3_int64, 4_int64]
   key = [5_int64, 6_int64]
   call tltm_rng_philox4x32_10(counter, key, output)
   call assert_equal_i64_vec(output, [3234347452_int64, 2291959749_int64, 1637377849_int64, 759571408_int64], &
                             "Philox4x32-10 mixed counter/key known-answer vector")

   uniform_value = tltm_rng_uniform(tltm_rng_domain_stage2_local_momentum, 20260421, 1, 0, 1, 1)
   expected_uniform = real(3034070204_int64, real64)/uint32_modulus_real
   call assert_equal_real(uniform_value, expected_uniform, "draw index 1 maps to Philox word 1")
   call assert_true(uniform_value >= 0.0_real64 .and. uniform_value < 1.0_real64, "uniform draw is in [0,1)")

   open_value = tltm_rng_uniform_open(tltm_rng_domain_stage2_local_momentum, 20260421, 1, 0, 1, 1)
   call assert_true(open_value > 0.0_real64 .and. open_value < 1.0_real64, "open uniform draw is in (0,1)")

   call tltm_rng_fill_normal(normals_a, tltm_rng_domain_stage2_local_momentum, 20260421, 17, 1, 1)
   call tltm_rng_fill_normal(normals_b, tltm_rng_domain_stage2_local_momentum, 20260421, 17, 1, 1)
   call tltm_rng_fill_normal(normals_c, tltm_rng_domain_stage2_local_momentum, 20260421, 17, 1, 2)
   call assert_equal_real_vec(normals_a, normals_b, "normal kernel replay is deterministic")
   call assert_true(any(normals_a /= normals_c), "normal kernel changes when update_idx changes")
   call assert_true(all(abs(normals_a) < huge(1.0_real64)), "normal kernel produces finite values")

   uniform_value = tltm_rng_uniform(tltm_rng_domain_stage2_local_momentum, 20260421, 17, 1, 1, 1)
   open_value = tltm_rng_uniform(tltm_rng_domain_stage2_local_accept, 20260421, 17, 1, 1, 1)
   call assert_true(uniform_value /= open_value, "momentum and accept domains are separated")

   write (*, '(A)') "[PASS] TLTM counter-based RNG v2 contract"

contains

   subroutine assert_equal_i64_vec(observed, expected, message)
      integer(int64), intent(in) :: observed(:), expected(:)
      character(len=*), intent(in) :: message

      if (size(observed) /= size(expected) .or. any(observed /= expected)) then
         write (*, '(A,A)') "[FAIL] ", trim(message)
         write (*, '(A,4(1X,I0))') "observed:", observed
         write (*, '(A,4(1X,I0))') "expected:", expected
         error stop 1
      end if
   end subroutine assert_equal_i64_vec

   subroutine assert_equal_real(observed, expected, message)
      real(real64), intent(in) :: observed, expected
      character(len=*), intent(in) :: message

      if (observed /= expected) then
         write (*, '(A,A,A,ES24.16,A,ES24.16)') "[FAIL] ", trim(message), " observed=", observed, " expected=", expected
         error stop 1
      end if
   end subroutine assert_equal_real

   subroutine assert_equal_real_vec(observed, expected, message)
      real(real64), intent(in) :: observed(:), expected(:)
      character(len=*), intent(in) :: message

      if (size(observed) /= size(expected) .or. any(observed /= expected)) then
         write (*, '(A,A)') "[FAIL] ", trim(message)
         error stop 1
      end if
   end subroutine assert_equal_real_vec

   subroutine assert_true(condition, message)
      logical, intent(in) :: condition
      character(len=*), intent(in) :: message

      if (.not. condition) then
         write (*, '(A,A)') "[FAIL] ", trim(message)
         error stop 1
      end if
   end subroutine assert_true

end program test_tltm_rng_contract

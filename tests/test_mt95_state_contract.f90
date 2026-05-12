program test_mt95_state_contract
   use mt95, only: gaussrnd, grnd, mt95_get_state, mt95_seed_state, mt95_set_state, mt95_state_t, sgrnd
   use mtdefs, only: rk
   implicit none

   type(mt95_state_t) :: stream_a, stream_b, saved_after_gauss
   real(rk) :: a_first, a_second, a_second_replay
   real(rk) :: b_first, b_second, b_second_replay
   real(rk) :: after_reseed, expected_after_reseed, throwaway

   call mt95_seed_state(stream_a, 246813)
   call mt95_set_state(stream_a)
   a_first = gaussrnd()
   call mt95_get_state(saved_after_gauss)
   a_second = gaussrnd()
   call mt95_set_state(saved_after_gauss)
   a_second_replay = gaussrnd()
   call assert_equal_real(a_second_replay, a_second, "gaussian spare state is captured by explicit RNG state")

   call mt95_seed_state(stream_a, 10101)
   call mt95_seed_state(stream_b, 20202)
   call mt95_set_state(stream_a)
   a_first = grnd()
   call mt95_get_state(stream_a)

   call mt95_set_state(stream_b)
   b_first = grnd()
   call mt95_get_state(stream_b)

   call mt95_set_state(stream_a)
   a_second = grnd()
   call mt95_get_state(stream_a)

   call mt95_set_state(stream_b)
   b_second = grnd()
   call mt95_get_state(stream_b)

   call mt95_seed_state(stream_a, 10101)
   call mt95_set_state(stream_a)
   call assert_equal_real(grnd(), a_first, "stream A first draw is reproducible")
   call assert_equal_real(grnd(), a_second, "stream A survives interleaved stream B draws")

   call mt95_seed_state(stream_b, 20202)
   call mt95_set_state(stream_b)
   call assert_equal_real(grnd(), b_first, "stream B first draw is reproducible")
   b_second_replay = grnd()
   call assert_equal_real(b_second_replay, b_second, "stream B survives interleaved stream A draws")

   call sgrnd(30303)
   throwaway = gaussrnd()
   call assert_equal_real(throwaway, throwaway, "throwaway gaussian draw is finite enough for equality")
   call sgrnd(40404)
   after_reseed = gaussrnd()
   call mt95_seed_state(stream_a, 40404)
   call mt95_set_state(stream_a)
   expected_after_reseed = gaussrnd()
   call assert_equal_real(after_reseed, expected_after_reseed, "sgrnd resets gaussian spare state")

   write (*, '(A)') "[PASS] mt95 explicit state contract"

contains

   subroutine assert_equal_real(observed, expected, message)
      real(rk), intent(in) :: observed, expected
      character(len=*), intent(in) :: message

      if (observed /= expected) then
         write (*, '(A,A,A,ES24.16,A,ES24.16)') "[FAIL] ", trim(message), " observed=", observed, " expected=", expected
         error stop 1
      end if
   end subroutine assert_equal_real

end program test_mt95_state_contract

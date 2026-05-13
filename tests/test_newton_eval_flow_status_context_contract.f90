program test_newton_eval_flow_status_context_contract
   use, intrinsic :: iso_fortran_env, only: int64
   use hmc_constraints, only: get_newton_eval_flow_status_counts, newton_eval_flow_status_context_t, &
                              record_newton_eval_flow_status, release_newton_eval_flow_status_context, &
                              reset_newton_eval_flow_status_counts
   use solve_flow, only: intode_status_failure_h_min, intode_status_failure_invalid, intode_status_success, &
                         intode_status_success_solver_assist
   implicit none

   type(newton_eval_flow_status_context_t) :: context_a, context_b
   integer(int64) :: success, zero_time, stiff_rescue, solver_assist
   integer(int64) :: failure_max_steps, failure_invalid, failure_h_min, unknown

   call reset_newton_eval_flow_status_counts(context_a)
   call reset_newton_eval_flow_status_counts(context_b)

   call record_newton_eval_flow_status(intode_status_success, context_a)
   call record_newton_eval_flow_status(intode_status_success_solver_assist, context_a)
   call record_newton_eval_flow_status(intode_status_failure_invalid, context_a)
   call record_newton_eval_flow_status(-999, context_a)
   call record_newton_eval_flow_status(intode_status_failure_h_min, context_b)

   call get_newton_eval_flow_status_counts(success, zero_time, stiff_rescue, solver_assist, &
                                           failure_max_steps, failure_invalid, failure_h_min, unknown, context_a)
   call assert_equal_int64(success, 1_int64, "context A records success")
   call assert_equal_int64(zero_time, 0_int64, "context A leaves zero-time isolated")
   call assert_equal_int64(stiff_rescue, 0_int64, "context A leaves stiff-rescue isolated")
   call assert_equal_int64(solver_assist, 1_int64, "context A records solver assist")
   call assert_equal_int64(failure_max_steps, 0_int64, "context A leaves max-steps isolated")
   call assert_equal_int64(failure_invalid, 1_int64, "context A records invalid failure")
   call assert_equal_int64(failure_h_min, 0_int64, "context A does not receive context B h_min")
   call assert_equal_int64(unknown, 1_int64, "context A records unknown status")

   call get_newton_eval_flow_status_counts(success, zero_time, stiff_rescue, solver_assist, &
                                           failure_max_steps, failure_invalid, failure_h_min, unknown, context_b)
   call assert_equal_int64(success, 0_int64, "context B success remains isolated")
   call assert_equal_int64(solver_assist, 0_int64, "context B solver assist remains isolated")
   call assert_equal_int64(failure_invalid, 0_int64, "context B invalid failure remains isolated")
   call assert_equal_int64(failure_h_min, 1_int64, "context B records h_min failure")
   call assert_equal_int64(unknown, 0_int64, "context B unknown remains isolated")

   call release_newton_eval_flow_status_context(context_a)
   call get_newton_eval_flow_status_counts(success, zero_time, stiff_rescue, solver_assist, &
                                           failure_max_steps, failure_invalid, failure_h_min, unknown, context_a)
   call assert_equal_int64(success + zero_time + stiff_rescue + solver_assist + failure_max_steps + &
                           failure_invalid + failure_h_min + unknown, 0_int64, "release clears context A")

   write (*, '(A)') "[PASS] newton eval-flow status context contract"

contains

   subroutine assert_equal_int64(observed, expected, message)
      integer(int64), intent(in) :: observed, expected
      character(len=*), intent(in) :: message

      if (observed /= expected) then
         write (*, '(A,A,A,I0,A,I0)') "[FAIL] ", trim(message), " observed=", observed, " expected=", expected
         error stop 1
      end if
   end subroutine assert_equal_int64

end program test_newton_eval_flow_status_context_contract

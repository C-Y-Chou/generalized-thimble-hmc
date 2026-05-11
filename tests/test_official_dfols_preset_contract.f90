program test_official_dfols_preset_contract
   use quasi_newton_solver_mod, only: apply_qn_official_dfols_preset, get_qn_official_dfols_policy, &
                                     qn_backend_official_dfols
   use utils, only: dp
   implicit none

   integer :: failures

   failures = 0

   write (*, '(A)') "[INIT] Official DFO-LS preset contract starts."

   call check_default_policy(failures)
   call check_stable_aliases(failures)
   call check_legacy_alias(failures)
   call check_unknown_falls_back_to_stable(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] Official DFO-LS preset contract failures=", failures
      error stop 1
   end if

   write (*, '(A)') "[DONE] Official DFO-LS preset contract complete."

contains

   subroutine check_default_policy(failures)
      integer, intent(inout) :: failures
      integer :: backend_code, npt, maxfun
      logical :: objfun_has_noise, ok
      real(dp) :: rhobeg, rhoend, model_abs_tol, model_rel_tol

      call get_qn_official_dfols_policy(backend_code, npt, maxfun, objfun_has_noise, &
                                        rhobeg, rhoend, model_abs_tol, model_rel_tol)
      ok = backend_code == qn_backend_official_dfols .and. stable_gate77_matches(npt, maxfun, objfun_has_noise, &
                                                                                  rhobeg, rhoend, model_abs_tol, &
                                                                                  model_rel_tol)
      write (*, '(A,L1,A,I0,A,I0,A,I0)') "[CHECK] default_policy ok=", ok, &
         " backend=", backend_code, " npt=", npt, " maxfun=", maxfun
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] default official DFO-LS backend/preset contract changed."
      end if
   end subroutine check_default_policy

   subroutine check_stable_aliases(failures)
      integer, intent(inout) :: failures
      character(len=32), parameter :: aliases(5) = [character(len=32) :: "", "stable", "gate77", "production", "official_alone"]
      integer :: idx
      logical :: ok

      ok = .true.
      do idx = 1, size(aliases)
         call apply_qn_official_dfols_preset(aliases(idx))
         ok = ok .and. current_policy_is_stable()
      end do
      write (*, '(A,L1)') "[CHECK] stable_aliases ok=", ok
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] stable_gate77 alias mapping changed."
      end if
   end subroutine check_stable_aliases

   subroutine check_legacy_alias(failures)
      integer, intent(inout) :: failures
      integer :: backend_code, npt, maxfun
      logical :: objfun_has_noise, ok
      real(dp) :: rhobeg, rhoend, model_abs_tol, model_rel_tol

      call apply_qn_official_dfols_preset("legacy")
      call get_qn_official_dfols_policy(backend_code, npt, maxfun, objfun_has_noise, &
                                        rhobeg, rhoend, model_abs_tol, model_rel_tol)
      ok = backend_code == qn_backend_official_dfols .and. npt == 0 .and. maxfun == 250 .and. &
           objfun_has_noise .and. close_to(rhobeg, 5.0e-2_dp) .and. close_to(rhoend, 1.0e-16_dp) .and. &
           close_to(model_abs_tol, 1.0e-30_dp) .and. close_to(model_rel_tol, 0.0_dp)
      write (*, '(A,L1,A,I0,A,ES12.4)') "[CHECK] legacy_alias ok=", ok, " npt=", npt, " rhobeg=", rhobeg
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] legacy official DFO-LS preset alias changed."
      end if
   end subroutine check_legacy_alias

   subroutine check_unknown_falls_back_to_stable(failures)
      integer, intent(inout) :: failures
      logical :: ok

      call apply_qn_official_dfols_preset("not_a_real_preset")
      ok = current_policy_is_stable()
      write (*, '(A,L1)') "[CHECK] unknown_fallback ok=", ok
      if (.not. ok) then
         failures = failures + 1
         write (*, '(A)') "[FAIL] unknown official DFO-LS preset no longer falls back to stable_gate77."
      end if
   end subroutine check_unknown_falls_back_to_stable

   logical function current_policy_is_stable() result(ok)
      integer :: backend_code, npt, maxfun
      logical :: objfun_has_noise
      real(dp) :: rhobeg, rhoend, model_abs_tol, model_rel_tol

      call get_qn_official_dfols_policy(backend_code, npt, maxfun, objfun_has_noise, &
                                        rhobeg, rhoend, model_abs_tol, model_rel_tol)
      ok = backend_code == qn_backend_official_dfols .and. stable_gate77_matches(npt, maxfun, objfun_has_noise, &
                                                                                  rhobeg, rhoend, model_abs_tol, &
                                                                                  model_rel_tol)
   end function current_policy_is_stable

   logical function stable_gate77_matches(npt, maxfun, objfun_has_noise, rhobeg, rhoend, model_abs_tol, model_rel_tol) result(ok)
      integer, intent(in) :: npt, maxfun
      logical, intent(in) :: objfun_has_noise
      real(dp), intent(in) :: rhobeg, rhoend, model_abs_tol, model_rel_tol

      ok = npt == 4 .and. maxfun == 250 .and. objfun_has_noise .and. &
           close_to(rhobeg, 1.8e-2_dp) .and. close_to(rhoend, 1.0e-16_dp) .and. &
           close_to(model_abs_tol, 1.0e-30_dp) .and. close_to(model_rel_tol, 0.0_dp)
   end function stable_gate77_matches

   logical function close_to(observed, expected) result(ok)
      real(dp), intent(in) :: observed, expected
      real(dp) :: scale

      scale = max(1.0_dp, abs(expected))
      ok = abs(observed - expected) <= 100.0_dp*epsilon(1.0_dp)*scale
   end function close_to

end program test_official_dfols_preset_contract

program test_numerical_helper_contracts
   use hmc_kernels, only: calculate_hamiltonian, decompose2
   use param_mod, only: read_parameters
   use utils, only: complex_to_real, dp, log_determinant, map_to_complex, map_to_complex_mat, &
                    map_to_real, map_to_real_mat, real_to_complex
   implicit none

   integer :: failures

   failures = 0
   call read_parameters()

   call check_pack_roundtrip(failures)
   call check_invalid_pack_outputs(failures)
   call check_log_determinant_contract(failures)
   call check_decompose2_contract(failures)
   call check_hamiltonian_shape_guard(failures)

   if (failures /= 0) then
      write (*, '(A,I0)') "[ERROR] numerical helper contract failures=", failures
      error stop 1
   end if
   write (*, '(A)') "[PASS] numerical helper contracts"

contains

   subroutine check_pack_roundtrip(failures)
      integer, intent(inout) :: failures
      complex(dp) :: cvec(2), cvec_back(2)
      complex(dp) :: cmat(2, 2), cmat_back(2, 2)
      real(dp) :: rvec(4), rmat(4, 4), flat(8)
      logical :: ok

      cvec = [cmplx(1.0_dp, -2.0_dp, dp), cmplx(-0.5_dp, 0.25_dp, dp)]
      call complex_to_real(cvec, rvec)
      call real_to_complex(rvec, cvec_back)

      cmat(1, 1) = cmplx(1.0_dp, 0.5_dp, dp)
      cmat(1, 2) = cmplx(-2.0_dp, 0.25_dp, dp)
      cmat(2, 1) = cmplx(0.75_dp, -1.5_dp, dp)
      cmat(2, 2) = cmplx(3.0_dp, 0.0_dp, dp)
      call map_to_real_mat(cmat, rmat)
      call map_to_complex_mat(rmat, cmat_back)
      call map_to_real(cmat, flat)
      call map_to_complex(flat, cmat_back)

      ok = maxval(abs(cvec - cvec_back)) == 0.0_dp .and. maxval(abs(cmat - cmat_back)) == 0.0_dp
      write (*, '(A,L1)') "[CHECK] helper_pack_roundtrip ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_pack_roundtrip

   subroutine check_invalid_pack_outputs(failures)
      integer, intent(inout) :: failures
      complex(dp) :: cvec(2), cmat(2, 2), c_out(2), m_out(2, 2)
      real(dp) :: r_bad(3), flat_bad(7), block_bad(3, 3)
      logical :: ok

      cvec = [cmplx(1.0_dp, 2.0_dp, dp), cmplx(3.0_dp, 4.0_dp, dp)]
      cmat = cmplx(1.0_dp, 1.0_dp, dp)
      r_bad = 7.0_dp
      flat_bad = 7.0_dp
      block_bad = 7.0_dp
      c_out = cmplx(7.0_dp, 7.0_dp, dp)
      m_out = cmplx(7.0_dp, 7.0_dp, dp)

      call complex_to_real(cvec, r_bad)
      call real_to_complex(r_bad, c_out)
      call map_to_real(cmat, flat_bad)
      call map_to_real_mat(cmat, block_bad)
      call map_to_complex(flat_bad, m_out)

      ok = maxval(abs(r_bad)) == 0.0_dp .and. maxval(abs(c_out)) == 0.0_dp .and. &
           maxval(abs(flat_bad)) == 0.0_dp .and. maxval(abs(block_bad)) == 0.0_dp .and. &
           maxval(abs(m_out)) == 0.0_dp
      write (*, '(A,L1)') "[CHECK] helper_invalid_pack_outputs ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_invalid_pack_outputs

   subroutine check_log_determinant_contract(failures)
      integer, intent(inout) :: failures
      complex(dp) :: ident(2, 2), singular(2, 2), nonsquare(2, 3), log_det
      logical :: error_flag, ok

      ident = cmplx(0.0_dp, 0.0_dp, dp)
      ident(1, 1) = cmplx(1.0_dp, 0.0_dp, dp)
      ident(2, 2) = cmplx(1.0_dp, 0.0_dp, dp)
      call log_determinant(ident, log_det, error_flag)
      ok = (.not. error_flag) .and. abs(log_det) == 0.0_dp

      singular = cmplx(0.0_dp, 0.0_dp, dp)
      call log_determinant(singular, log_det, error_flag)
      ok = ok .and. error_flag .and. abs(log_det) == 0.0_dp

      nonsquare = cmplx(1.0_dp, 0.0_dp, dp)
      call log_determinant(nonsquare, log_det, error_flag)
      ok = ok .and. error_flag .and. abs(log_det) == 0.0_dp

      write (*, '(A,L1)') "[CHECK] helper_log_determinant_contract ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_log_determinant_contract

   subroutine check_decompose2_contract(failures)
      integer, intent(inout) :: failures
      real(dp) :: b(4), x(4), au(4), av(4)
      complex(dp) :: jac(2, 2), bad_jac(2, 1)
      logical :: ierr, ok

      b = [1.0_dp, 2.0_dp, -3.0_dp, 4.0_dp]
      jac = cmplx(0.0_dp, 0.0_dp, dp)
      jac(1, 1) = cmplx(1.0_dp, 0.0_dp, dp)
      jac(2, 2) = cmplx(1.0_dp, 0.0_dp, dp)
      call decompose2(b, x, au, av, jac, ierr)
      ok = (.not. ierr) .and. maxval(abs(x - b)) == 0.0_dp .and. &
           maxval(abs(au - [1.0_dp, 0.0_dp, -3.0_dp, 0.0_dp])) == 0.0_dp .and. &
           maxval(abs(av - [0.0_dp, 2.0_dp, 0.0_dp, 4.0_dp])) == 0.0_dp

      x = 9.0_dp
      au = 9.0_dp
      av = 9.0_dp
      bad_jac = cmplx(1.0_dp, 0.0_dp, dp)
      call decompose2(b, x, au, av, bad_jac, ierr)
      ok = ok .and. ierr .and. maxval(abs(x)) == 0.0_dp .and. maxval(abs(au)) == 0.0_dp .and. &
           maxval(abs(av)) == 0.0_dp

      write (*, '(A,L1)') "[CHECK] helper_decompose2_contract ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_decompose2_contract

   subroutine check_hamiltonian_shape_guard(failures)
      integer, intent(inout) :: failures
      complex(dp) :: z(2)
      real(dp) :: p_bad(3), h
      logical :: ok

      z = [cmplx(0.1_dp, 0.0_dp, dp), cmplx(-0.2_dp, 0.0_dp, dp)]
      p_bad = 0.0_dp
      call calculate_hamiltonian(z, p_bad, h)
      ok = h > 0.5_dp*huge(1.0_dp)
      write (*, '(A,L1)') "[CHECK] helper_hamiltonian_shape_guard ok=", ok
      if (.not. ok) failures = failures + 1
   end subroutine check_hamiltonian_shape_guard

end program test_numerical_helper_contracts

module model_tape_ad
   use utils, only: dp
   implicit none
   private

   integer, parameter :: OP_INPUT = 1
   integer, parameter :: OP_CONST = 2
   integer, parameter :: OP_ADD = 3
   integer, parameter :: OP_SUB = 4
   integer, parameter :: OP_MUL = 5
   integer, parameter :: OP_DIV = 6
   integer, parameter :: OP_NEG = 7
   integer, parameter :: OP_POWI = 8
   integer, parameter :: OP_LOG = 9
   integer, parameter :: OP_EXP = 10

   type, public :: rev_t
      integer :: id = 0
   end type rev_t

   integer, allocatable, save :: op_code(:), arg_l(:), arg_r(:), pow_int(:), in_pos(:), in_node(:)
   complex(dp), allocatable, save :: node_val(:), node_dot(:), node_adj(:), node_hadj(:)
   integer, save :: tape_size = 0
   integer, save :: tape_cap = 0
   integer, save :: n_inputs = 0
   logical, save :: adj_valid = .false.
   integer, save :: adj_out_id = 0

   public :: tape_begin, tape_input, tape_const, tape_set_inputs, tape_forward_values, tape_grad, tape_hvp
   public :: operator(+), operator(-), operator(*), operator(/), operator(**), log, exp

   interface operator(+)
      module procedure rev_add_rev
      module procedure rev_add_c
      module procedure c_add_rev
      module procedure rev_add_r
      module procedure r_add_rev
      module procedure rev_add_i
      module procedure i_add_rev
   end interface

   interface operator(-)
      module procedure rev_sub_rev
      module procedure rev_sub_c
      module procedure c_sub_rev
      module procedure rev_sub_r
      module procedure r_sub_rev
      module procedure rev_sub_i
      module procedure i_sub_rev
      module procedure rev_uminus
   end interface

   interface operator(*)
      module procedure rev_mul_rev
      module procedure rev_mul_c
      module procedure c_mul_rev
      module procedure rev_mul_r
      module procedure r_mul_rev
      module procedure rev_mul_i
      module procedure i_mul_rev
   end interface

   interface operator(/)
      module procedure rev_div_rev
      module procedure rev_div_c
      module procedure c_div_rev
      module procedure rev_div_r
      module procedure r_div_rev
      module procedure rev_div_i
      module procedure i_div_rev
   end interface

   interface operator(**)
      module procedure rev_pow_i
   end interface

   interface log
      module procedure rev_log
   end interface

   interface exp
      module procedure rev_exp
   end interface

contains

   subroutine tape_begin(n_in)
      integer, intent(in) :: n_in

      if (n_in < 1) then
         write (*, '(A)') "[ERROR] tape_begin: input size must be >= 1."
         error stop 1
      end if

      n_inputs = n_in
      tape_size = 0
      call ensure_capacity(max(128, 16*n_in))
      adj_valid = .false.
      adj_out_id = 0

      if (allocated(in_node)) then
         if (size(in_node) /= n_inputs) deallocate (in_node)
      end if
      if (.not. allocated(in_node)) allocate (in_node(n_inputs))
      in_node = 0
   end subroutine tape_begin

   function tape_input(value, idx) result(a)
      complex(dp), intent(in) :: value
      integer, intent(in) :: idx
      type(rev_t) :: a

      if (idx < 1 .or. idx > n_inputs) then
         write (*, '(A)') "[ERROR] tape_input: invalid input index."
         error stop 1
      end if

      a%id = append_node(OP_INPUT, 0, 0, value, 0, idx)
      in_node(idx) = a%id
   end function tape_input

   function tape_const(value) result(a)
      complex(dp), intent(in) :: value
      type(rev_t) :: a

      a%id = append_node(OP_CONST, 0, 0, value, 0, 0)
   end function tape_const

   subroutine tape_set_inputs(z)
      complex(dp), intent(in) :: z(:)
      integer :: j

      if (size(z) /= n_inputs) then
         write (*, '(A)') "[ERROR] tape_set_inputs: vector size mismatch."
         error stop 1
      end if

      do j = 1, n_inputs
         node_val(in_node(j)) = z(j)
      end do
      adj_valid = .false.
      adj_out_id = 0
   end subroutine tape_set_inputs

   subroutine tape_forward_values()
      integer :: i, a, b, k

      do i = 1, tape_size
         select case (op_code(i))
         case (OP_INPUT, OP_CONST)
            cycle
         case (OP_ADD)
            a = arg_l(i)
            b = arg_r(i)
            node_val(i) = node_val(a) + node_val(b)
         case (OP_SUB)
            a = arg_l(i)
            b = arg_r(i)
            node_val(i) = node_val(a) - node_val(b)
         case (OP_MUL)
            a = arg_l(i)
            b = arg_r(i)
            node_val(i) = node_val(a)*node_val(b)
         case (OP_DIV)
            a = arg_l(i)
            b = arg_r(i)
            node_val(i) = node_val(a)/node_val(b)
         case (OP_NEG)
            a = arg_l(i)
            node_val(i) = -node_val(a)
         case (OP_POWI)
            a = arg_l(i)
            k = pow_int(i)
            node_val(i) = node_val(a)**k
         case (OP_LOG)
            a = arg_l(i)
            node_val(i) = log(node_val(a))
         case (OP_EXP)
            a = arg_l(i)
            node_val(i) = exp(node_val(a))
         case default
            write (*, '(A)') "[ERROR] tape_forward_values: unsupported opcode."
            error stop 1
         end select
      end do
      adj_valid = .false.
      adj_out_id = 0
   end subroutine tape_forward_values

   subroutine tape_grad(out_id, grad)
      integer, intent(in) :: out_id
      complex(dp), intent(out) :: grad(:)
      integer :: j

      call validate_out_id(out_id)
      if (size(grad) /= n_inputs) then
         write (*, '(A)') "[ERROR] tape_grad: vector size mismatch."
         error stop 1
      end if

      call ensure_adjoints(out_id)
      do j = 1, n_inputs
         grad(j) = node_adj(in_node(j))
      end do
   end subroutine tape_grad

   subroutine tape_hvp(out_id, v, hv)
      integer, intent(in) :: out_id
      complex(dp), intent(in) :: v(:)
      complex(dp), intent(out) :: hv(:)
      integer :: i, a, b, j, k
      complex(dp) :: x, z, invz, f1, f2, yb, yh, k_c, km1_c

      call validate_out_id(out_id)
      if (size(v) /= n_inputs .or. size(hv) /= n_inputs) then
         write (*, '(A)') "[ERROR] tape_hvp: vector size mismatch."
         error stop 1
      end if

      node_dot(1:tape_size) = cmplx(0.0_dp, 0.0_dp, dp)
      do i = 1, tape_size
         select case (op_code(i))
         case (OP_INPUT)
            node_dot(i) = v(in_pos(i))
         case (OP_CONST)
            node_dot(i) = cmplx(0.0_dp, 0.0_dp, dp)
         case (OP_ADD)
            a = arg_l(i)
            b = arg_r(i)
            node_dot(i) = node_dot(a) + node_dot(b)
         case (OP_SUB)
            a = arg_l(i)
            b = arg_r(i)
            node_dot(i) = node_dot(a) - node_dot(b)
         case (OP_MUL)
            a = arg_l(i)
            b = arg_r(i)
            node_dot(i) = node_dot(a)*node_val(b) + node_val(a)*node_dot(b)
         case (OP_DIV)
            a = arg_l(i)
            b = arg_r(i)
            z = node_val(b)
            node_dot(i) = (node_dot(a)*z - node_val(a)*node_dot(b))/(z*z)
         case (OP_NEG)
            a = arg_l(i)
            node_dot(i) = -node_dot(a)
         case (OP_POWI)
            a = arg_l(i)
            k = pow_int(i)
            if (k == 0) then
               node_dot(i) = cmplx(0.0_dp, 0.0_dp, dp)
            else
               k_c = cmplx(real(k, dp), 0.0_dp, dp)
               node_dot(i) = k_c*(node_val(a)**(k - 1))*node_dot(a)
            end if
         case (OP_LOG)
            a = arg_l(i)
            node_dot(i) = node_dot(a)/node_val(a)
         case (OP_EXP)
            a = arg_l(i)
            node_dot(i) = node_val(i)*node_dot(a)
         case default
            write (*, '(A)') "[ERROR] tape_hvp: unsupported opcode."
            error stop 1
         end select
      end do

      call ensure_adjoints(out_id)

      node_hadj(1:tape_size) = cmplx(0.0_dp, 0.0_dp, dp)
      node_hadj(out_id) = cmplx(0.0_dp, 0.0_dp, dp)

      do i = tape_size, 1, -1
         yb = node_adj(i)
         yh = node_hadj(i)
         if (real(yb, dp) == 0.0_dp .and. aimag(yb) == 0.0_dp .and. real(yh, dp) == 0.0_dp .and. aimag(yh) == 0.0_dp) cycle

         select case (op_code(i))
         case (OP_INPUT, OP_CONST)
            cycle
         case (OP_ADD)
            a = arg_l(i)
            b = arg_r(i)
            node_hadj(a) = node_hadj(a) + yh
            node_hadj(b) = node_hadj(b) + yh
         case (OP_SUB)
            a = arg_l(i)
            b = arg_r(i)
            node_hadj(a) = node_hadj(a) + yh
            node_hadj(b) = node_hadj(b) - yh
         case (OP_MUL)
            a = arg_l(i)
            b = arg_r(i)
            node_hadj(a) = node_hadj(a) + yh*node_val(b) + yb*node_dot(b)
            node_hadj(b) = node_hadj(b) + yh*node_val(a) + yb*node_dot(a)
         case (OP_DIV)
            a = arg_l(i)
            b = arg_r(i)
            x = node_val(a)
            z = node_val(b)
            invz = cmplx(1.0_dp, 0.0_dp, dp)/z
            node_hadj(a) = node_hadj(a) + yh*invz + yb*(-invz*invz)*node_dot(b)
            node_hadj(b) = node_hadj(b) + yh*(-x*invz*invz) + yb*((-invz*invz)*node_dot(a) + (cmplx(2.0_dp, 0.0_dp, dp)*x*invz*invz*invz)*node_dot(b))
         case (OP_NEG)
            a = arg_l(i)
            node_hadj(a) = node_hadj(a) - yh
         case (OP_POWI)
            a = arg_l(i)
            k = pow_int(i)
            x = node_val(a)
            if (k == 0) then
               cycle
            else
               k_c = cmplx(real(k, dp), 0.0_dp, dp)
               f1 = k_c*(x**(k - 1))
               if (k == 1) then
                  f2 = cmplx(0.0_dp, 0.0_dp, dp)
               else
                  km1_c = cmplx(real(k - 1, dp), 0.0_dp, dp)
                  f2 = k_c*km1_c*(x**(k - 2))
               end if
               node_hadj(a) = node_hadj(a) + yh*f1 + yb*f2*node_dot(a)
            end if
         case (OP_LOG)
            a = arg_l(i)
            x = node_val(a)
            f1 = cmplx(1.0_dp, 0.0_dp, dp)/x
            f2 = -f1*f1
            node_hadj(a) = node_hadj(a) + yh*f1 + yb*f2*node_dot(a)
         case (OP_EXP)
            a = arg_l(i)
            f1 = node_val(i)
            node_hadj(a) = node_hadj(a) + yh*f1 + yb*f1*node_dot(a)
         case default
            write (*, '(A)') "[ERROR] tape_hvp reverse pass: unsupported opcode."
            error stop 1
         end select
      end do

      do j = 1, n_inputs
         hv(j) = node_hadj(in_node(j))
      end do
   end subroutine tape_hvp

   subroutine ensure_adjoints(out_id)
      integer, intent(in) :: out_id

      if (.not. adj_valid .or. adj_out_id /= out_id) then
         call compute_adjoints(out_id)
         adj_valid = .true.
         adj_out_id = out_id
      end if
   end subroutine ensure_adjoints

   subroutine validate_out_id(out_id)
      integer, intent(in) :: out_id
      if (out_id < 1 .or. out_id > tape_size) then
         write (*, '(A)') "[ERROR] AD tape: invalid output node id."
         error stop 1
      end if
   end subroutine validate_out_id

   subroutine compute_adjoints(out_id)
      integer, intent(in) :: out_id
      integer :: i, a, b, k
      complex(dp) :: yb, x, z, invz, k_c

      node_adj(1:tape_size) = cmplx(0.0_dp, 0.0_dp, dp)
      node_adj(out_id) = cmplx(1.0_dp, 0.0_dp, dp)

      do i = tape_size, 1, -1
         yb = node_adj(i)
         if (real(yb, dp) == 0.0_dp .and. aimag(yb) == 0.0_dp) cycle

         select case (op_code(i))
         case (OP_INPUT, OP_CONST)
            cycle
         case (OP_ADD)
            a = arg_l(i)
            b = arg_r(i)
            node_adj(a) = node_adj(a) + yb
            node_adj(b) = node_adj(b) + yb
         case (OP_SUB)
            a = arg_l(i)
            b = arg_r(i)
            node_adj(a) = node_adj(a) + yb
            node_adj(b) = node_adj(b) - yb
         case (OP_MUL)
            a = arg_l(i)
            b = arg_r(i)
            node_adj(a) = node_adj(a) + yb*node_val(b)
            node_adj(b) = node_adj(b) + yb*node_val(a)
         case (OP_DIV)
            a = arg_l(i)
            b = arg_r(i)
            x = node_val(a)
            z = node_val(b)
            invz = cmplx(1.0_dp, 0.0_dp, dp)/z
            node_adj(a) = node_adj(a) + yb*invz
            node_adj(b) = node_adj(b) - yb*x*invz*invz
         case (OP_NEG)
            a = arg_l(i)
            node_adj(a) = node_adj(a) - yb
         case (OP_POWI)
            a = arg_l(i)
            k = pow_int(i)
            if (k /= 0) then
               k_c = cmplx(real(k, dp), 0.0_dp, dp)
               node_adj(a) = node_adj(a) + yb*k_c*(node_val(a)**(k - 1))
            end if
         case (OP_LOG)
            a = arg_l(i)
            node_adj(a) = node_adj(a) + yb/node_val(a)
         case (OP_EXP)
            a = arg_l(i)
            node_adj(a) = node_adj(a) + yb*node_val(i)
         case default
            write (*, '(A)') "[ERROR] compute_adjoints: unsupported opcode."
            error stop 1
         end select
      end do
   end subroutine compute_adjoints

   subroutine ensure_capacity(need)
      integer, intent(in) :: need
      integer :: new_cap

      if (need <= tape_cap) return
      new_cap = max(need, max(128, 2*tape_cap))

      call resize_int_array(op_code, new_cap)
      call resize_int_array(arg_l, new_cap)
      call resize_int_array(arg_r, new_cap)
      call resize_int_array(pow_int, new_cap)
      call resize_int_array(in_pos, new_cap)
      call resize_cpx_array(node_val, new_cap)
      call resize_cpx_array(node_dot, new_cap)
      call resize_cpx_array(node_adj, new_cap)
      call resize_cpx_array(node_hadj, new_cap)

      tape_cap = new_cap
   end subroutine ensure_capacity

   subroutine resize_int_array(arr, new_size)
      integer, allocatable, intent(inout) :: arr(:)
      integer, intent(in) :: new_size
      integer, allocatable :: tmp(:)
      integer :: old_size

      old_size = 0
      if (allocated(arr)) old_size = size(arr)
      allocate (tmp(new_size))
      tmp = 0
      if (old_size > 0) tmp(1:old_size) = arr
      call move_alloc(tmp, arr)
   end subroutine resize_int_array

   subroutine resize_cpx_array(arr, new_size)
      complex(dp), allocatable, intent(inout) :: arr(:)
      integer, intent(in) :: new_size
      complex(dp), allocatable :: tmp(:)
      integer :: old_size

      old_size = 0
      if (allocated(arr)) old_size = size(arr)
      allocate (tmp(new_size))
      tmp = cmplx(0.0_dp, 0.0_dp, dp)
      if (old_size > 0) tmp(1:old_size) = arr
      call move_alloc(tmp, arr)
   end subroutine resize_cpx_array

   integer function append_node(opc, a, b, v, p_int, idx_in) result(id)
      integer, intent(in) :: opc, a, b, p_int, idx_in
      complex(dp), intent(in) :: v

      call ensure_capacity(tape_size + 1)
      tape_size = tape_size + 1
      id = tape_size

      op_code(id) = opc
      arg_l(id) = a
      arg_r(id) = b
      pow_int(id) = p_int
      in_pos(id) = idx_in
      node_val(id) = v
      node_dot(id) = cmplx(0.0_dp, 0.0_dp, dp)
      node_adj(id) = cmplx(0.0_dp, 0.0_dp, dp)
      node_hadj(id) = cmplx(0.0_dp, 0.0_dp, dp)
   end function append_node

   function mk_bin(opc, a, b, v) result(r)
      integer, intent(in) :: opc
      type(rev_t), intent(in) :: a, b
      complex(dp), intent(in) :: v
      type(rev_t) :: r

      r%id = append_node(opc, a%id, b%id, v, 0, 0)
   end function mk_bin

   function mk_un(opc, a, v) result(r)
      integer, intent(in) :: opc
      type(rev_t), intent(in) :: a
      complex(dp), intent(in) :: v
      type(rev_t) :: r

      r%id = append_node(opc, a%id, 0, v, 0, 0)
   end function mk_un

   function c_from_r(x) result(c)
      real(dp), intent(in) :: x
      complex(dp) :: c
      c = cmplx(x, 0.0_dp, dp)
   end function c_from_r

   function c_from_i(x) result(c)
      integer, intent(in) :: x
      complex(dp) :: c
      c = cmplx(real(x, dp), 0.0_dp, dp)
   end function c_from_i

   function rev_add_rev(a, b) result(r)
      type(rev_t), intent(in) :: a, b
      type(rev_t) :: r
      r = mk_bin(OP_ADD, a, b, node_val(a%id) + node_val(b%id))
   end function rev_add_rev

   function rev_add_c(a, b) result(r)
      type(rev_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(rev_t) :: r
      r = rev_add_rev(a, tape_const(b))
   end function rev_add_c

   function c_add_rev(a, b) result(r)
      complex(dp), intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = rev_add_rev(tape_const(a), b)
   end function c_add_rev

   function rev_add_r(a, b) result(r)
      type(rev_t), intent(in) :: a
      real(dp), intent(in) :: b
      type(rev_t) :: r
      r = rev_add_c(a, c_from_r(b))
   end function rev_add_r

   function r_add_rev(a, b) result(r)
      real(dp), intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = c_add_rev(c_from_r(a), b)
   end function r_add_rev

   function rev_add_i(a, b) result(r)
      type(rev_t), intent(in) :: a
      integer, intent(in) :: b
      type(rev_t) :: r
      r = rev_add_c(a, c_from_i(b))
   end function rev_add_i

   function i_add_rev(a, b) result(r)
      integer, intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = c_add_rev(c_from_i(a), b)
   end function i_add_rev

   function rev_sub_rev(a, b) result(r)
      type(rev_t), intent(in) :: a, b
      type(rev_t) :: r
      r = mk_bin(OP_SUB, a, b, node_val(a%id) - node_val(b%id))
   end function rev_sub_rev

   function rev_sub_c(a, b) result(r)
      type(rev_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(rev_t) :: r
      r = rev_sub_rev(a, tape_const(b))
   end function rev_sub_c

   function c_sub_rev(a, b) result(r)
      complex(dp), intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = rev_sub_rev(tape_const(a), b)
   end function c_sub_rev

   function rev_sub_r(a, b) result(r)
      type(rev_t), intent(in) :: a
      real(dp), intent(in) :: b
      type(rev_t) :: r
      r = rev_sub_c(a, c_from_r(b))
   end function rev_sub_r

   function r_sub_rev(a, b) result(r)
      real(dp), intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = c_sub_rev(c_from_r(a), b)
   end function r_sub_rev

   function rev_sub_i(a, b) result(r)
      type(rev_t), intent(in) :: a
      integer, intent(in) :: b
      type(rev_t) :: r
      r = rev_sub_c(a, c_from_i(b))
   end function rev_sub_i

   function i_sub_rev(a, b) result(r)
      integer, intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = c_sub_rev(c_from_i(a), b)
   end function i_sub_rev

   function rev_uminus(a) result(r)
      type(rev_t), intent(in) :: a
      type(rev_t) :: r
      r = mk_un(OP_NEG, a, -node_val(a%id))
   end function rev_uminus

   function rev_mul_rev(a, b) result(r)
      type(rev_t), intent(in) :: a, b
      type(rev_t) :: r
      r = mk_bin(OP_MUL, a, b, node_val(a%id)*node_val(b%id))
   end function rev_mul_rev

   function rev_mul_c(a, b) result(r)
      type(rev_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(rev_t) :: r
      r = rev_mul_rev(a, tape_const(b))
   end function rev_mul_c

   function c_mul_rev(a, b) result(r)
      complex(dp), intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = rev_mul_rev(tape_const(a), b)
   end function c_mul_rev

   function rev_mul_r(a, b) result(r)
      type(rev_t), intent(in) :: a
      real(dp), intent(in) :: b
      type(rev_t) :: r
      r = rev_mul_c(a, c_from_r(b))
   end function rev_mul_r

   function r_mul_rev(a, b) result(r)
      real(dp), intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = c_mul_rev(c_from_r(a), b)
   end function r_mul_rev

   function rev_mul_i(a, b) result(r)
      type(rev_t), intent(in) :: a
      integer, intent(in) :: b
      type(rev_t) :: r
      r = rev_mul_c(a, c_from_i(b))
   end function rev_mul_i

   function i_mul_rev(a, b) result(r)
      integer, intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = c_mul_rev(c_from_i(a), b)
   end function i_mul_rev

   function rev_div_rev(a, b) result(r)
      type(rev_t), intent(in) :: a, b
      type(rev_t) :: r
      r = mk_bin(OP_DIV, a, b, node_val(a%id)/node_val(b%id))
   end function rev_div_rev

   function rev_div_c(a, b) result(r)
      type(rev_t), intent(in) :: a
      complex(dp), intent(in) :: b
      type(rev_t) :: r
      r = rev_div_rev(a, tape_const(b))
   end function rev_div_c

   function c_div_rev(a, b) result(r)
      complex(dp), intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = rev_div_rev(tape_const(a), b)
   end function c_div_rev

   function rev_div_r(a, b) result(r)
      type(rev_t), intent(in) :: a
      real(dp), intent(in) :: b
      type(rev_t) :: r
      r = rev_div_c(a, c_from_r(b))
   end function rev_div_r

   function r_div_rev(a, b) result(r)
      real(dp), intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = c_div_rev(c_from_r(a), b)
   end function r_div_rev

   function rev_div_i(a, b) result(r)
      type(rev_t), intent(in) :: a
      integer, intent(in) :: b
      type(rev_t) :: r
      r = rev_div_c(a, c_from_i(b))
   end function rev_div_i

   function i_div_rev(a, b) result(r)
      integer, intent(in) :: a
      type(rev_t), intent(in) :: b
      type(rev_t) :: r
      r = c_div_rev(c_from_i(a), b)
   end function i_div_rev

   function rev_pow_i(a, p) result(r)
      type(rev_t), intent(in) :: a
      integer, intent(in) :: p
      type(rev_t) :: r

      r%id = append_node(OP_POWI, a%id, 0, node_val(a%id)**p, p, 0)
   end function rev_pow_i

   function rev_log(a) result(r)
      type(rev_t), intent(in) :: a
      type(rev_t) :: r

      r = mk_un(OP_LOG, a, log(node_val(a%id)))
   end function rev_log

   function rev_exp(a) result(r)
      type(rev_t), intent(in) :: a
      type(rev_t) :: r

      r = mk_un(OP_EXP, a, exp(node_val(a%id)))
   end function rev_exp

end module model_tape_ad

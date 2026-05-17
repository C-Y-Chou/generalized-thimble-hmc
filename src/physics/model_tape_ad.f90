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

   type, public :: model_tape_context_t
      integer, allocatable :: op_code(:), arg_l(:), arg_r(:), pow_int(:), in_pos(:), in_node(:)
      complex(dp), allocatable :: node_val(:), node_dot(:), node_adj(:), node_hadj(:)
      integer :: tape_size = 0
      integer :: tape_cap = 0
      integer :: n_inputs = 0
      logical :: adj_valid = .false.
      integer :: adj_out_id = 0
   end type model_tape_context_t

   type(model_tape_context_t), target, save :: module_model_tape_context
   type(model_tape_context_t), pointer, save :: active_tape_context => null()

   public :: tape_begin, tape_input, tape_const, tape_set_inputs, tape_forward_values, tape_grad, tape_hvp
   public :: bind_model_tape_context, bind_module_model_tape_context, release_model_tape_context
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

   subroutine ensure_model_tape_context_bound()
      implicit none

      if (.not. associated(active_tape_context)) call bind_module_model_tape_context()
   end subroutine ensure_model_tape_context_bound

   subroutine bind_model_tape_context(context)
      implicit none
      type(model_tape_context_t), intent(inout), target :: context

      active_tape_context => context
   end subroutine bind_model_tape_context

   subroutine bind_module_model_tape_context()
      implicit none

      active_tape_context => module_model_tape_context
   end subroutine bind_module_model_tape_context

   subroutine release_model_tape_context(context)
      implicit none
      type(model_tape_context_t), intent(inout), target :: context
      logical :: was_active

      was_active = associated(active_tape_context)
      if (was_active) was_active = associated(active_tape_context, context)
      call clear_model_tape_context(context)
      if (was_active) call bind_module_model_tape_context()
   end subroutine release_model_tape_context

   subroutine clear_model_tape_context(context)
      implicit none
      type(model_tape_context_t), intent(inout) :: context

      if (allocated(context%op_code)) deallocate (context%op_code)
      if (allocated(context%arg_l)) deallocate (context%arg_l)
      if (allocated(context%arg_r)) deallocate (context%arg_r)
      if (allocated(context%pow_int)) deallocate (context%pow_int)
      if (allocated(context%in_pos)) deallocate (context%in_pos)
      if (allocated(context%in_node)) deallocate (context%in_node)
      if (allocated(context%node_val)) deallocate (context%node_val)
      if (allocated(context%node_dot)) deallocate (context%node_dot)
      if (allocated(context%node_adj)) deallocate (context%node_adj)
      if (allocated(context%node_hadj)) deallocate (context%node_hadj)
      context%tape_size = 0
      context%tape_cap = 0
      context%n_inputs = 0
      context%adj_valid = .false.
      context%adj_out_id = 0
   end subroutine clear_model_tape_context

   subroutine tape_begin(n_in)
      integer, intent(in) :: n_in

      call ensure_model_tape_context_bound()
      if (n_in < 1) then
         write (*, '(A)') "[ERROR] tape_begin: input size must be >= 1."
         error stop 1
      end if

      active_tape_context%n_inputs = n_in
      active_tape_context%tape_size = 0
      call ensure_capacity(max(128, 16*n_in))
      active_tape_context%adj_valid = .false.
      active_tape_context%adj_out_id = 0

      if (allocated(active_tape_context%in_node)) then
         if (size(active_tape_context%in_node) /= active_tape_context%n_inputs) deallocate (active_tape_context%in_node)
      end if
      if (.not. allocated(active_tape_context%in_node)) allocate (active_tape_context%in_node(active_tape_context%n_inputs))
      active_tape_context%in_node = 0
   end subroutine tape_begin

   function tape_input(value, idx) result(a)
      complex(dp), intent(in) :: value
      integer, intent(in) :: idx
      type(rev_t) :: a

      call ensure_model_tape_context_bound()
      if (idx < 1 .or. idx > active_tape_context%n_inputs) then
         write (*, '(A)') "[ERROR] tape_input: invalid input index."
         error stop 1
      end if

      a%id = append_node(OP_INPUT, 0, 0, value, 0, idx)
      active_tape_context%in_node(idx) = a%id
   end function tape_input

   function tape_const(value) result(a)
      complex(dp), intent(in) :: value
      type(rev_t) :: a

      call ensure_model_tape_context_bound()
      a%id = append_node(OP_CONST, 0, 0, value, 0, 0)
   end function tape_const

   subroutine tape_set_inputs(z)
      complex(dp), intent(in) :: z(:)
      integer :: j

      call ensure_model_tape_context_bound()
      if (size(z) /= active_tape_context%n_inputs) then
         write (*, '(A)') "[ERROR] tape_set_inputs: vector size mismatch."
         error stop 1
      end if

      do j = 1, active_tape_context%n_inputs
         active_tape_context%node_val(active_tape_context%in_node(j)) = z(j)
      end do
      active_tape_context%adj_valid = .false.
      active_tape_context%adj_out_id = 0
   end subroutine tape_set_inputs

   subroutine tape_forward_values()
      integer :: i, a, b, k

      call ensure_model_tape_context_bound()
      do i = 1, active_tape_context%tape_size
         select case (active_tape_context%op_code(i))
         case (OP_INPUT, OP_CONST)
            cycle
         case (OP_ADD)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_val(i) = active_tape_context%node_val(a) + active_tape_context%node_val(b)
         case (OP_SUB)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_val(i) = active_tape_context%node_val(a) - active_tape_context%node_val(b)
         case (OP_MUL)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_val(i) = active_tape_context%node_val(a)*active_tape_context%node_val(b)
         case (OP_DIV)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_val(i) = active_tape_context%node_val(a)/active_tape_context%node_val(b)
         case (OP_NEG)
            a = active_tape_context%arg_l(i)
            active_tape_context%node_val(i) = -active_tape_context%node_val(a)
         case (OP_POWI)
            a = active_tape_context%arg_l(i)
            k = active_tape_context%pow_int(i)
            active_tape_context%node_val(i) = active_tape_context%node_val(a)**k
         case (OP_LOG)
            a = active_tape_context%arg_l(i)
            active_tape_context%node_val(i) = log(active_tape_context%node_val(a))
         case (OP_EXP)
            a = active_tape_context%arg_l(i)
            active_tape_context%node_val(i) = exp(active_tape_context%node_val(a))
         case default
            write (*, '(A)') "[ERROR] tape_forward_values: unsupported opcode."
            error stop 1
         end select
      end do
      active_tape_context%adj_valid = .false.
      active_tape_context%adj_out_id = 0
   end subroutine tape_forward_values

   subroutine tape_grad(out_id, grad)
      integer, intent(in) :: out_id
      complex(dp), intent(out) :: grad(:)
      integer :: j

      call ensure_model_tape_context_bound()
      call validate_out_id(out_id)
      if (size(grad) /= active_tape_context%n_inputs) then
         write (*, '(A)') "[ERROR] tape_grad: vector size mismatch."
         error stop 1
      end if

      call ensure_adjoints(out_id)
      do j = 1, active_tape_context%n_inputs
         grad(j) = active_tape_context%node_adj(active_tape_context%in_node(j))
      end do
   end subroutine tape_grad

   subroutine tape_hvp(out_id, v, hv)
      integer, intent(in) :: out_id
      complex(dp), intent(in) :: v(:)
      complex(dp), intent(out) :: hv(:)
      integer :: i, a, b, j, k
      complex(dp) :: x, z, invz, f1, f2, yb, yh, k_c, km1_c

      call ensure_model_tape_context_bound()
      call validate_out_id(out_id)
      if (size(v) /= active_tape_context%n_inputs .or. size(hv) /= active_tape_context%n_inputs) then
         write (*, '(A)') "[ERROR] tape_hvp: vector size mismatch."
         error stop 1
      end if

      active_tape_context%node_dot(1:active_tape_context%tape_size) = cmplx(0.0_dp, 0.0_dp, dp)
      do i = 1, active_tape_context%tape_size
         select case (active_tape_context%op_code(i))
         case (OP_INPUT)
            active_tape_context%node_dot(i) = v(active_tape_context%in_pos(i))
         case (OP_CONST)
            active_tape_context%node_dot(i) = cmplx(0.0_dp, 0.0_dp, dp)
         case (OP_ADD)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_dot(i) = active_tape_context%node_dot(a) + active_tape_context%node_dot(b)
         case (OP_SUB)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_dot(i) = active_tape_context%node_dot(a) - active_tape_context%node_dot(b)
         case (OP_MUL)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_dot(i) = active_tape_context%node_dot(a)*active_tape_context%node_val(b) + active_tape_context%node_val(a)*active_tape_context%node_dot(b)
         case (OP_DIV)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            z = active_tape_context%node_val(b)
            active_tape_context%node_dot(i) = (active_tape_context%node_dot(a)*z - active_tape_context%node_val(a)*active_tape_context%node_dot(b))/(z*z)
         case (OP_NEG)
            a = active_tape_context%arg_l(i)
            active_tape_context%node_dot(i) = -active_tape_context%node_dot(a)
         case (OP_POWI)
            a = active_tape_context%arg_l(i)
            k = active_tape_context%pow_int(i)
            if (k == 0) then
               active_tape_context%node_dot(i) = cmplx(0.0_dp, 0.0_dp, dp)
            else
               k_c = cmplx(real(k, dp), 0.0_dp, dp)
               active_tape_context%node_dot(i) = k_c*(active_tape_context%node_val(a)**(k - 1))*active_tape_context%node_dot(a)
            end if
         case (OP_LOG)
            a = active_tape_context%arg_l(i)
            active_tape_context%node_dot(i) = active_tape_context%node_dot(a)/active_tape_context%node_val(a)
         case (OP_EXP)
            a = active_tape_context%arg_l(i)
            active_tape_context%node_dot(i) = active_tape_context%node_val(i)*active_tape_context%node_dot(a)
         case default
            write (*, '(A)') "[ERROR] tape_hvp: unsupported opcode."
            error stop 1
         end select
      end do

      call ensure_adjoints(out_id)

      active_tape_context%node_hadj(1:active_tape_context%tape_size) = cmplx(0.0_dp, 0.0_dp, dp)
      active_tape_context%node_hadj(out_id) = cmplx(0.0_dp, 0.0_dp, dp)

      do i = active_tape_context%tape_size, 1, -1
         yb = active_tape_context%node_adj(i)
         yh = active_tape_context%node_hadj(i)
         if (real(yb, dp) == 0.0_dp .and. aimag(yb) == 0.0_dp .and. real(yh, dp) == 0.0_dp .and. aimag(yh) == 0.0_dp) cycle

         select case (active_tape_context%op_code(i))
         case (OP_INPUT, OP_CONST)
            cycle
         case (OP_ADD)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_hadj(a) = active_tape_context%node_hadj(a) + yh
            active_tape_context%node_hadj(b) = active_tape_context%node_hadj(b) + yh
         case (OP_SUB)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_hadj(a) = active_tape_context%node_hadj(a) + yh
            active_tape_context%node_hadj(b) = active_tape_context%node_hadj(b) - yh
         case (OP_MUL)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_hadj(a) = active_tape_context%node_hadj(a) + yh*active_tape_context%node_val(b) + yb*active_tape_context%node_dot(b)
            active_tape_context%node_hadj(b) = active_tape_context%node_hadj(b) + yh*active_tape_context%node_val(a) + yb*active_tape_context%node_dot(a)
         case (OP_DIV)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            x = active_tape_context%node_val(a)
            z = active_tape_context%node_val(b)
            invz = cmplx(1.0_dp, 0.0_dp, dp)/z
            active_tape_context%node_hadj(a) = active_tape_context%node_hadj(a) + yh*invz + yb*(-invz*invz)*active_tape_context%node_dot(b)
            active_tape_context%node_hadj(b) = active_tape_context%node_hadj(b) + yh*(-x*invz*invz) + yb*((-invz*invz)*active_tape_context%node_dot(a) + (cmplx(2.0_dp, 0.0_dp, dp)*x*invz*invz*invz)*active_tape_context%node_dot(b))
         case (OP_NEG)
            a = active_tape_context%arg_l(i)
            active_tape_context%node_hadj(a) = active_tape_context%node_hadj(a) - yh
         case (OP_POWI)
            a = active_tape_context%arg_l(i)
            k = active_tape_context%pow_int(i)
            x = active_tape_context%node_val(a)
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
               active_tape_context%node_hadj(a) = active_tape_context%node_hadj(a) + yh*f1 + yb*f2*active_tape_context%node_dot(a)
            end if
         case (OP_LOG)
            a = active_tape_context%arg_l(i)
            x = active_tape_context%node_val(a)
            f1 = cmplx(1.0_dp, 0.0_dp, dp)/x
            f2 = -f1*f1
            active_tape_context%node_hadj(a) = active_tape_context%node_hadj(a) + yh*f1 + yb*f2*active_tape_context%node_dot(a)
         case (OP_EXP)
            a = active_tape_context%arg_l(i)
            f1 = active_tape_context%node_val(i)
            active_tape_context%node_hadj(a) = active_tape_context%node_hadj(a) + yh*f1 + yb*f1*active_tape_context%node_dot(a)
         case default
            write (*, '(A)') "[ERROR] tape_hvp reverse pass: unsupported opcode."
            error stop 1
         end select
      end do

      do j = 1, active_tape_context%n_inputs
         hv(j) = active_tape_context%node_hadj(active_tape_context%in_node(j))
      end do
   end subroutine tape_hvp

   subroutine ensure_adjoints(out_id)
      integer, intent(in) :: out_id

      call ensure_model_tape_context_bound()
      if (.not. active_tape_context%adj_valid .or. active_tape_context%adj_out_id /= out_id) then
         call compute_adjoints(out_id)
         active_tape_context%adj_valid = .true.
         active_tape_context%adj_out_id = out_id
      end if
   end subroutine ensure_adjoints

   subroutine validate_out_id(out_id)
      integer, intent(in) :: out_id

      call ensure_model_tape_context_bound()
      if (out_id < 1 .or. out_id > active_tape_context%tape_size) then
         write (*, '(A)') "[ERROR] AD tape: invalid output node id."
         error stop 1
      end if
   end subroutine validate_out_id

   subroutine compute_adjoints(out_id)
      integer, intent(in) :: out_id
      integer :: i, a, b, k
      complex(dp) :: yb, x, z, invz, k_c

      call ensure_model_tape_context_bound()
      active_tape_context%node_adj(1:active_tape_context%tape_size) = cmplx(0.0_dp, 0.0_dp, dp)
      active_tape_context%node_adj(out_id) = cmplx(1.0_dp, 0.0_dp, dp)

      do i = active_tape_context%tape_size, 1, -1
         yb = active_tape_context%node_adj(i)
         if (real(yb, dp) == 0.0_dp .and. aimag(yb) == 0.0_dp) cycle

         select case (active_tape_context%op_code(i))
         case (OP_INPUT, OP_CONST)
            cycle
         case (OP_ADD)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_adj(a) = active_tape_context%node_adj(a) + yb
            active_tape_context%node_adj(b) = active_tape_context%node_adj(b) + yb
         case (OP_SUB)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_adj(a) = active_tape_context%node_adj(a) + yb
            active_tape_context%node_adj(b) = active_tape_context%node_adj(b) - yb
         case (OP_MUL)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            active_tape_context%node_adj(a) = active_tape_context%node_adj(a) + yb*active_tape_context%node_val(b)
            active_tape_context%node_adj(b) = active_tape_context%node_adj(b) + yb*active_tape_context%node_val(a)
         case (OP_DIV)
            a = active_tape_context%arg_l(i)
            b = active_tape_context%arg_r(i)
            x = active_tape_context%node_val(a)
            z = active_tape_context%node_val(b)
            invz = cmplx(1.0_dp, 0.0_dp, dp)/z
            active_tape_context%node_adj(a) = active_tape_context%node_adj(a) + yb*invz
            active_tape_context%node_adj(b) = active_tape_context%node_adj(b) - yb*x*invz*invz
         case (OP_NEG)
            a = active_tape_context%arg_l(i)
            active_tape_context%node_adj(a) = active_tape_context%node_adj(a) - yb
         case (OP_POWI)
            a = active_tape_context%arg_l(i)
            k = active_tape_context%pow_int(i)
            if (k /= 0) then
               k_c = cmplx(real(k, dp), 0.0_dp, dp)
               active_tape_context%node_adj(a) = active_tape_context%node_adj(a) + yb*k_c*(active_tape_context%node_val(a)**(k - 1))
            end if
         case (OP_LOG)
            a = active_tape_context%arg_l(i)
            active_tape_context%node_adj(a) = active_tape_context%node_adj(a) + yb/active_tape_context%node_val(a)
         case (OP_EXP)
            a = active_tape_context%arg_l(i)
            active_tape_context%node_adj(a) = active_tape_context%node_adj(a) + yb*active_tape_context%node_val(i)
         case default
            write (*, '(A)') "[ERROR] compute_adjoints: unsupported opcode."
            error stop 1
         end select
      end do
   end subroutine compute_adjoints

   subroutine ensure_capacity(need)
      integer, intent(in) :: need
      integer :: new_cap

      call ensure_model_tape_context_bound()
      if (need <= active_tape_context%tape_cap) return
      new_cap = max(need, max(128, 2*active_tape_context%tape_cap))

      call resize_int_array(active_tape_context%op_code, new_cap)
      call resize_int_array(active_tape_context%arg_l, new_cap)
      call resize_int_array(active_tape_context%arg_r, new_cap)
      call resize_int_array(active_tape_context%pow_int, new_cap)
      call resize_int_array(active_tape_context%in_pos, new_cap)
      call resize_cpx_array(active_tape_context%node_val, new_cap)
      call resize_cpx_array(active_tape_context%node_dot, new_cap)
      call resize_cpx_array(active_tape_context%node_adj, new_cap)
      call resize_cpx_array(active_tape_context%node_hadj, new_cap)

      active_tape_context%tape_cap = new_cap
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

      call ensure_model_tape_context_bound()
      call ensure_capacity(active_tape_context%tape_size + 1)
      active_tape_context%tape_size = active_tape_context%tape_size + 1
      id = active_tape_context%tape_size

      active_tape_context%op_code(id) = opc
      active_tape_context%arg_l(id) = a
      active_tape_context%arg_r(id) = b
      active_tape_context%pow_int(id) = p_int
      active_tape_context%in_pos(id) = idx_in
      active_tape_context%node_val(id) = v
      active_tape_context%node_dot(id) = cmplx(0.0_dp, 0.0_dp, dp)
      active_tape_context%node_adj(id) = cmplx(0.0_dp, 0.0_dp, dp)
      active_tape_context%node_hadj(id) = cmplx(0.0_dp, 0.0_dp, dp)
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

      call ensure_model_tape_context_bound()
      r = mk_bin(OP_ADD, a, b, active_tape_context%node_val(a%id) + active_tape_context%node_val(b%id))
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

      call ensure_model_tape_context_bound()
      r = mk_bin(OP_SUB, a, b, active_tape_context%node_val(a%id) - active_tape_context%node_val(b%id))
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

      call ensure_model_tape_context_bound()
      r = mk_un(OP_NEG, a, -active_tape_context%node_val(a%id))
   end function rev_uminus

   function rev_mul_rev(a, b) result(r)
      type(rev_t), intent(in) :: a, b
      type(rev_t) :: r

      call ensure_model_tape_context_bound()
      r = mk_bin(OP_MUL, a, b, active_tape_context%node_val(a%id)*active_tape_context%node_val(b%id))
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

      call ensure_model_tape_context_bound()
      r = mk_bin(OP_DIV, a, b, active_tape_context%node_val(a%id)/active_tape_context%node_val(b%id))
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

      call ensure_model_tape_context_bound()
      r%id = append_node(OP_POWI, a%id, 0, active_tape_context%node_val(a%id)**p, p, 0)
   end function rev_pow_i

   function rev_log(a) result(r)
      type(rev_t), intent(in) :: a
      type(rev_t) :: r

      call ensure_model_tape_context_bound()
      r = mk_un(OP_LOG, a, log(active_tape_context%node_val(a%id)))
   end function rev_log

   function rev_exp(a) result(r)
      type(rev_t), intent(in) :: a
      type(rev_t) :: r

      call ensure_model_tape_context_bound()
      r = mk_un(OP_EXP, a, exp(active_tape_context%node_val(a%id)))
   end function rev_exp

end module model_tape_ad

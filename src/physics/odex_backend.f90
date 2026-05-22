module odex_backend
   use utils, only: dp
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use, intrinsic :: iso_c_binding, only: c_associated, c_double, c_f_pointer, c_funloc, c_funptr, c_int, &
                                          c_null_ptr, c_ptr
   implicit none
   private

   integer, parameter, public :: odex_max_steps_default = 200000
   integer, parameter, public :: odex_backend_kind_odex = 0
   integer, parameter, public :: odex_backend_kind_sundials_cvode = 1
   integer, parameter, public :: odex_backend_kind_dop853 = 2
   integer, parameter, public :: odex_k_min = 4
   integer, parameter, public :: odex_k_max = 10
   integer, parameter, public :: odex_cache_size = odex_k_max + 1
   integer, parameter, public :: odex_reason_none = 0
   integer, parameter, public :: odex_reason_max_steps = 1
   integer, parameter, public :: odex_reason_invalid = 2
   integer, parameter, public :: odex_reason_h_min = 3
   integer, parameter, public :: odex_reason_max_rhs_evals = 4
   integer, parameter, public :: odex_reason_max_rejects = 5
   integer, parameter, public :: odex_reason_stiffness = 6
   integer, parameter, public :: odex_status_unknown = -1
   integer, parameter, public :: odex_status_success = 0
   integer, parameter, public :: odex_status_success_zero_time = 1
   integer, parameter, public :: odex_status_failure_max_steps = 101
   integer, parameter, public :: odex_status_failure_invalid = 102
   integer, parameter, public :: odex_status_failure_h_min = 103
   integer, parameter, public :: odex_status_failure_max_rhs_evals = 104
   integer, parameter, public :: odex_status_failure_max_rejects = 105
   integer, parameter, public :: odex_status_failure_stiffness = 106
   integer, parameter, public :: odex_step_sequence_iwork3 = 3
   integer, parameter, public :: odex_stability_control_none = 0
   integer, parameter, public :: odex_stability_control_conservative = 1
   integer, parameter, public :: odex_controller_policy_hairer_experimental = 1
   integer, parameter, public :: odex_controller_policy_tltm_endpoint = odex_controller_policy_hairer_experimental
   integer, parameter :: odex_controller_policy_legacy_tltm_endpoint = 0
   integer, parameter, public :: odex_order_transition_demote = -1
   integer, parameter, public :: odex_order_transition_keep = 0
   integer, parameter, public :: odex_order_transition_promote = 1
   integer, parameter, public :: odex_hairer_controller_action_continue = 0
   integer, parameter, public :: odex_hairer_controller_action_accept = 1
   integer, parameter, public :: odex_hairer_controller_action_reject = 2
   integer, parameter, public :: odex_hairer_controller_action_retry = 3
   integer, parameter, public :: odex_hairer_controller_action_endpoint = 4
   integer, parameter, public :: odex_hairer_controller_action_invalid = 5
   integer, parameter, public :: odex_hairer_controller_phase_first_last = 1
   integer, parameter, public :: odex_hairer_controller_phase_basic = 2
   real(dp), parameter, public :: odex_hairer_errold_initial = 1.0e10_dp
   integer(c_int), parameter :: sundials_cvode_status_success = 0_c_int
   integer(c_int), parameter :: sundials_cvode_status_max_steps = 1_c_int
   integer(c_int), parameter :: sundials_cvode_status_invalid = 2_c_int
   integer(c_int), parameter :: sundials_cvode_status_unavailable = 10_c_int
   integer, parameter :: dop853_stage_count = 12
   integer, parameter :: dop853_order = 8
   real(dp), parameter :: dop853_c2 = 0.526001519587677318785587544488e-01_dp
   real(dp), parameter :: dop853_c3 = 0.789002279381515978178381316732e-01_dp
   real(dp), parameter :: dop853_c4 = 0.118350341907227396726757197510_dp
   real(dp), parameter :: dop853_c5 = 0.281649658092772603273242802490_dp
   real(dp), parameter :: dop853_c6 = 0.333333333333333333333333333333_dp
   real(dp), parameter :: dop853_c7 = 0.25_dp
   real(dp), parameter :: dop853_c8 = 0.307692307692307692307692307692_dp
   real(dp), parameter :: dop853_c9 = 0.651282051282051282051282051282_dp
   real(dp), parameter :: dop853_c10 = 0.6_dp
   real(dp), parameter :: dop853_c11 = 0.857142857142857142857142857142_dp
   real(dp), parameter :: dop853_b1 = 5.42937341165687622380535766363e-2_dp
   real(dp), parameter :: dop853_b6 = 4.45031289275240888144113950566_dp
   real(dp), parameter :: dop853_b7 = 1.89151789931450038304281599044_dp
   real(dp), parameter :: dop853_b8 = -5.8012039600105847814672114227_dp
   real(dp), parameter :: dop853_b9 = 3.1116436695781989440891606237e-1_dp
   real(dp), parameter :: dop853_b10 = -1.52160949662516078556178806805e-1_dp
   real(dp), parameter :: dop853_b11 = 2.01365400804030348374776537501e-1_dp
   real(dp), parameter :: dop853_b12 = 4.47106157277725905176885569043e-2_dp
   real(dp), parameter :: dop853_bhh1 = 0.244094488188976377952755905512_dp
   real(dp), parameter :: dop853_bhh2 = 0.733846688281611857341361741547_dp
   real(dp), parameter :: dop853_bhh3 = 0.220588235294117647058823529412e-1_dp
   real(dp), parameter :: dop853_er1 = 0.1312004499419488073250102996e-01_dp
   real(dp), parameter :: dop853_er6 = -0.1225156446376204440720569753e+01_dp
   real(dp), parameter :: dop853_er7 = -0.4957589496572501915214079952_dp
   real(dp), parameter :: dop853_er8 = 0.1664377182454986536961530415e+01_dp
   real(dp), parameter :: dop853_er9 = -0.3503288487499736816886487290_dp
   real(dp), parameter :: dop853_er10 = 0.3341791187130174790297318841_dp
   real(dp), parameter :: dop853_er11 = 0.8192320648511571246570742613e-01_dp
   real(dp), parameter :: dop853_er12 = -0.2235530786388629525884427845e-01_dp
   real(dp), parameter :: dop853_a21 = 5.26001519587677318785587544488e-2_dp
   real(dp), parameter :: dop853_a31 = 1.97250569845378994544595329183e-2_dp
   real(dp), parameter :: dop853_a32 = 5.91751709536136983633785987549e-2_dp
   real(dp), parameter :: dop853_a41 = 2.95875854768068491816892993775e-2_dp
   real(dp), parameter :: dop853_a43 = 8.87627564304205475450678981324e-2_dp
   real(dp), parameter :: dop853_a51 = 2.41365134159266685502369798665e-1_dp
   real(dp), parameter :: dop853_a53 = -8.84549479328286085344864962717e-1_dp
   real(dp), parameter :: dop853_a54 = 9.24834003261792003115737966543e-1_dp
   real(dp), parameter :: dop853_a61 = 3.7037037037037037037037037037e-2_dp
   real(dp), parameter :: dop853_a64 = 1.70828608729473871279604482173e-1_dp
   real(dp), parameter :: dop853_a65 = 1.25467687566822425016691814123e-1_dp
   real(dp), parameter :: dop853_a71 = 3.7109375e-2_dp
   real(dp), parameter :: dop853_a74 = 1.70252211019544039314978060272e-1_dp
   real(dp), parameter :: dop853_a75 = 6.02165389804559606850219397283e-2_dp
   real(dp), parameter :: dop853_a76 = -1.7578125e-2_dp
   real(dp), parameter :: dop853_a81 = 3.70920001185047927108779319836e-2_dp
   real(dp), parameter :: dop853_a84 = 1.70383925712239993810214054705e-1_dp
   real(dp), parameter :: dop853_a85 = 1.07262030446373284651809199168e-1_dp
   real(dp), parameter :: dop853_a86 = -1.53194377486244017527936158236e-2_dp
   real(dp), parameter :: dop853_a87 = 8.27378916381402288758473766002e-3_dp
   real(dp), parameter :: dop853_a91 = 6.24110958716075717114429577812e-1_dp
   real(dp), parameter :: dop853_a94 = -3.36089262944694129406857109825_dp
   real(dp), parameter :: dop853_a95 = -8.68219346841726006818189891453e-1_dp
   real(dp), parameter :: dop853_a96 = 2.75920996994467083049415600797e+1_dp
   real(dp), parameter :: dop853_a97 = 2.01540675504778934086186788979e+1_dp
   real(dp), parameter :: dop853_a98 = -4.34898841810699588477366255144e+1_dp
   real(dp), parameter :: dop853_a101 = 4.77662536438264365890433908527e-1_dp
   real(dp), parameter :: dop853_a104 = -2.48811461997166764192642586468_dp
   real(dp), parameter :: dop853_a105 = -5.90290826836842996371446475743e-1_dp
   real(dp), parameter :: dop853_a106 = 2.12300514481811942347288949897e+1_dp
   real(dp), parameter :: dop853_a107 = 1.52792336328824235832596922938e+1_dp
   real(dp), parameter :: dop853_a108 = -3.32882109689848629194453265587e+1_dp
   real(dp), parameter :: dop853_a109 = -2.03312017085086261358222928593e-2_dp
   real(dp), parameter :: dop853_a111 = -9.3714243008598732571704021658e-1_dp
   real(dp), parameter :: dop853_a114 = 5.18637242884406370830023853209_dp
   real(dp), parameter :: dop853_a115 = 1.09143734899672957818500254654_dp
   real(dp), parameter :: dop853_a116 = -8.14978701074692612513997267357_dp
   real(dp), parameter :: dop853_a117 = -1.85200656599969598641566180701e+1_dp
   real(dp), parameter :: dop853_a118 = 2.27394870993505042818970056734e+1_dp
   real(dp), parameter :: dop853_a119 = 2.49360555267965238987089396762_dp
   real(dp), parameter :: dop853_a1110 = -3.0467644718982195003823669022_dp
   real(dp), parameter :: dop853_a121 = 2.27331014751653820792359768449_dp
   real(dp), parameter :: dop853_a124 = -1.05344954667372501984066689879e+1_dp
   real(dp), parameter :: dop853_a125 = -2.00087205822486249909675718444_dp
   real(dp), parameter :: dop853_a126 = -1.79589318631187989172765950534e+1_dp
   real(dp), parameter :: dop853_a127 = 2.79488845294199600508499808837e+1_dp
   real(dp), parameter :: dop853_a128 = -2.85899827713502369474065508674_dp
   real(dp), parameter :: dop853_a129 = -8.87285693353062954433549289258_dp
   real(dp), parameter :: dop853_a1210 = 1.23605671757943030647266201528e+1_dp
   real(dp), parameter :: dop853_a1211 = 6.43392746015763530355970484046e-1_dp

   type, public :: odex_options
      real(dp) :: abs_tol = 0.0_dp
      real(dp) :: rel_tol = 0.0_dp
      integer :: backend = odex_backend_kind_odex
      integer :: k_min = odex_k_min
      integer :: k_max = odex_k_max
      integer :: max_steps = odex_max_steps_default
      integer :: cvode_fixedpoint_m = 0
      integer :: cvode_max_order = 0
      integer :: cvode_max_steps = 0
      integer :: cvode_max_err_test_fails = 0
      integer :: cvode_max_conv_fails = 0
      integer :: cvode_max_nonlin_iters = 0
      real(dp) :: cvode_min_step = 0.0_dp
      integer :: dop853_max_reject = 100000
      integer :: dop853_max_rhs_evals = 0
      real(dp) :: dop853_min_step = 0.0_dp
      real(dp) :: dop853_max_step = 0.0_dp
      real(dp) :: dop853_safety = 0.9_dp
      real(dp) :: dop853_fac1 = 0.333_dp
      real(dp) :: dop853_fac2 = 6.0_dp
      real(dp) :: dop853_beta = 0.0_dp
      logical :: dop853_hinit_enabled = .true.
      real(dp) :: dop853_hinit_factor = 0.01_dp
      real(dp) :: dop853_hinit_min = 1.0e-6_dp
      logical :: dop853_stiffness_check_enabled = .true.
      integer :: dop853_stiffness_check_interval = 1000
      integer :: dop853_stiffness_max_hits = 15
      real(dp) :: dop853_stiffness_threshold = 6.1_dp
      integer :: step_sequence = odex_step_sequence_iwork3
      integer :: stability_control = odex_stability_control_none
      integer :: controller_policy = odex_controller_policy_hairer_experimental
      logical :: endpoint_only = .true.
      real(dp) :: h_min_c_fp = 16.0_dp
      real(dp) :: h_min_c_tol = 0.01_dp
      real(dp) :: h_min_c_span = 1.0e-12_dp
      real(dp) :: initial_step_fraction = 0.01_dp
      real(dp) :: step_size_bound_fac1 = 0.02_dp
      real(dp) :: step_size_bound_fac2 = 4.0_dp
      real(dp) :: order_decrease_factor = 0.8_dp
      real(dp) :: order_increase_factor = 0.9_dp
      real(dp) :: stability_growth_limit = 4.0_dp
   end type odex_options

   type, public :: odex_workspace
      real(dp), allocatable :: tableau(:, :, :)
      real(dp), allocatable :: ystate(:), yprev(:), ycurr(:), ynext(:), fval(:), fbase(:)
      integer, allocatable :: nsteps(:)
      real(dp), allocatable :: ak(:), invexp(:), ratio(:, :)
      logical :: tables_ready = .false.
      integer :: table_k = 0
   end type odex_workspace

   type, public :: odex_result
      integer :: status = odex_status_unknown
      integer :: failure_reason = odex_reason_none
      integer :: accepted_steps = 0
      integer :: rejected_steps = 0
      integer :: stability_rejects = 0
      integer :: final_order = 0
      real(dp) :: final_step_size = 0.0_dp
      real(dp) :: t_remaining = 0.0_dp
      logical :: endpoint_available = .false.
      logical :: cvode_backend_used = .false.
      integer :: cvode_rhs_evals = 0
      integer :: cvode_error_test_fails = 0
      integer :: cvode_nonlinear_iters = 0
      integer :: cvode_nonlinear_conv_fails = 0
      integer :: cvode_step_solve_fails = 0
      integer :: odex_rhs_evals = 0
      integer :: odex_midpoint_rows = 0
      integer :: odex_kplus1_attempts = 0
      integer :: odex_accept_k_minus_1 = 0
      integer :: odex_accept_k = 0
      integer :: odex_accept_k_plus_1 = 0
      integer :: odex_large_error_rejects = 0
      integer :: odex_kplus1_rejects = 0
      integer :: odex_hairer_policy_steps = 0
      integer :: odex_tltm_policy_steps = 0
      integer :: odex_first_step_entries = 0
      integer :: odex_last_step_entries = 0
      integer :: odex_basic_step_entries = 0
      integer :: odex_row_j1_calls = 0
      integer :: odex_row_j2_calls = 0
      integer :: odex_row_jge3_calls = 0
      integer :: odex_row_j1_no_error_returns = 0
      integer :: odex_error_estimates = 0
      integer :: odex_hairer_scal_estimates = 0
      integer :: odex_default_scal_estimates = 0
      integer :: odex_errold_checks = 0
      integer :: odex_atov_events = 0
      integer :: odex_convergence_rejects = 0
      integer :: odex_kplus1_hope_rejects = 0
      integer :: odex_reject_kc_k_minus_1 = 0
      integer :: odex_reject_kc_k = 0
      integer :: odex_reject_kc_k_plus_1 = 0
      integer :: odex_kopt_accept_updates = 0
      integer :: odex_kopt_demotions = 0
      integer :: odex_kopt_keeps = 0
      integer :: odex_kopt_promotions = 0
      integer :: odex_after_reject_clamps = 0
      integer :: odex_reject_updates = 0
   end type odex_result

   type :: odex_step_telemetry
      integer :: rhs_evals = 0
      integer :: midpoint_rows = 0
      integer :: kplus1_attempts = 0
      integer :: accept_k_minus_1 = 0
      integer :: accept_k = 0
      integer :: accept_k_plus_1 = 0
      integer :: large_error_rejects = 0
      integer :: kplus1_rejects = 0
      integer :: row_j1_calls = 0
      integer :: row_j2_calls = 0
      integer :: row_jge3_calls = 0
      integer :: row_j1_no_error_returns = 0
      integer :: error_estimates = 0
      integer :: hairer_scal_estimates = 0
      integer :: default_scal_estimates = 0
      integer :: errold_checks = 0
      integer :: atov_events = 0
      integer :: convergence_rejects = 0
      integer :: kplus1_hope_rejects = 0
      integer :: reject_kc_k_minus_1 = 0
      integer :: reject_kc_k = 0
      integer :: reject_kc_k_plus_1 = 0
      integer :: kopt_accept_updates = 0
      integer :: kopt_demotions = 0
      integer :: kopt_keeps = 0
      integer :: kopt_promotions = 0
      integer :: after_reject_clamps = 0
      integer :: reject_updates = 0
   end type odex_step_telemetry

   type, public :: odex_row_result
      integer :: row_index = 0
      integer :: rhs_evals = 0
      logical :: err_available = .false.
      logical :: atov = .false.
      logical :: invalid_rhs = .false.
      logical :: stability_rejected = .false.
      real(dp) :: err = 0.0_dp
      real(dp) :: hh = 0.0_dp
      real(dp) :: work = huge(1.0_dp)
      real(dp) :: h_after = 0.0_dp
      real(dp) :: errold_after = 0.0_dp
   end type odex_row_result

   type, public :: odex_hairer_row_lifecycle
      logical :: initialized = .false.
      integer :: dimension = 0
      integer :: max_rows = 0
      integer :: rows_attempted = 0
      integer :: error_rows = 0
      integer :: atov_events = 0
      integer :: rhs_evals = 0
      integer :: last_row = 0
      real(dp) :: errold = odex_hairer_errold_initial
      real(dp) :: h_after = 0.0_dp
      logical :: atov = .false.
      real(dp), allocatable :: scal(:)
      real(dp), allocatable :: hh(:)
      real(dp), allocatable :: work(:)
   end type odex_hairer_row_lifecycle

   type, public :: odex_hairer_controller_state
      logical :: initialized = .false.
      logical :: rejected = .false.
      logical :: last_step = .false.
      logical :: endpoint_reached = .false.
      integer :: k = 2
      integer :: kc = 0
      integer :: km = odex_k_max
      real(dp) :: h = 0.0_dp
      real(dp) :: hmax_abs = 0.0_dp
      real(dp) :: hoptde = 0.0_dp
      real(dp) :: posneg = 1.0_dp
   end type odex_hairer_controller_state

   type, public :: odex_hairer_controller_decision
      integer :: action = odex_hairer_controller_action_continue
      integer :: next_row = 0
      integer :: accepted_row = 0
      integer :: rejected_row = 0
      integer :: next_k = 0
      real(dp) :: next_h = 0.0_dp
      logical :: rejected_after = .false.
      logical :: last_step = .false.
      logical :: endpoint_reached = .false.
   end type odex_hairer_controller_decision

   abstract interface
      function ode_rhs(y) result(dy)
         import :: dp
         real(dp), intent(in) :: y(:)
         real(dp) :: dy(size(y))
      end function ode_rhs

      function ode_rhs_context(y, context) result(dy)
         import :: dp
         real(dp), intent(in) :: y(:)
         class(*), intent(inout) :: context
         real(dp) :: dy(size(y))
      end function ode_rhs_context
   end interface

   interface
      integer(c_int) function tltm_sundials_cvode_available() bind(C, name="tltm_sundials_cvode_available")
         import :: c_int
      end function tltm_sundials_cvode_available

      integer(c_int) function tltm_sundials_cvode_integrate(n, y0, t_final, abs_tol, rel_tol, max_steps, &
                                                            fixedpoint_m, max_order, cvode_max_steps, min_step, &
                                                            max_err_test_fails, max_conv_fails, max_nonlin_iters, &
                                                            y_out, num_steps_out, last_step_out, t_reached_out, &
                                                            rhs_evals_out, error_test_fails_out, nonlinear_iters_out, &
                                                            nonlinear_conv_fails_out, step_solve_fails_out, last_order_out, &
                                                            user_ctx, rhs_cb) &
         bind(C, name="tltm_sundials_cvode_integrate")
         import :: c_double, c_funptr, c_int, c_ptr
         integer(c_int), value :: n
         real(c_double), intent(in) :: y0(*)
         real(c_double), value :: t_final, abs_tol, rel_tol
         integer(c_int), value :: max_steps, fixedpoint_m, max_order, cvode_max_steps
         real(c_double), value :: min_step
         integer(c_int), value :: max_err_test_fails, max_conv_fails, max_nonlin_iters
         real(c_double), intent(out) :: y_out(*)
         integer(c_int), intent(out) :: num_steps_out
         real(c_double), intent(out) :: last_step_out
         real(c_double), intent(out) :: t_reached_out
         integer(c_int), intent(out) :: rhs_evals_out
         integer(c_int), intent(out) :: error_test_fails_out
         integer(c_int), intent(out) :: nonlinear_iters_out
         integer(c_int), intent(out) :: nonlinear_conv_fails_out
         integer(c_int), intent(out) :: step_solve_fails_out
         integer(c_int), intent(out) :: last_order_out
         type(c_ptr), value :: user_ctx
         type(c_funptr), value :: rhs_cb
      end function tltm_sundials_cvode_integrate
   end interface

   procedure(ode_rhs), pointer, save :: cvode_active_rhs => null()
   procedure(ode_rhs_context), pointer, save :: cvode_active_rhs_context => null()
   class(*), pointer, save :: cvode_active_rhs_context_data => null()
   integer, save :: cvode_active_rhs_mode = 0
   logical, save :: cvode_callback_active = .false.

   public :: ode_rhs
   public :: ode_rhs_context

   public :: build_nsteps
   public :: odex_apply_backend_name
   public :: odex_apply_controller_policy_name
   public :: odex_backend_name
   public :: odex_controller_policy_name
   public :: odex_default_options
   public :: ensure_odex_workspace_object
   public :: odex_integrate_endpoint
   public :: odex_integrate_endpoint_context
   public :: odex_observe_controller_estimate
   public :: odex_hairer_controller_decision_reset
   public :: odex_hairer_controller_state_reset
   public :: odex_hairer_row_lifecycle_reset
   public :: odex_observe_hairer_controller_accept_update
   public :: odex_observe_hairer_controller_initial_state
   public :: odex_observe_hairer_controller_reject_update
   public :: odex_observe_hairer_controller_row_action
   public :: odex_observe_hairer_controller_step_entry
   public :: odex_observe_hairer_initial_state
   public :: odex_observe_hairer_midex_row
   public :: odex_observe_hairer_midex_lifecycle_row
   public :: odex_observe_hairer_promotion_step
   public :: odex_observe_hairer_kopt
   public :: odex_observe_hairer_reject_update
   public :: odex_observe_hairer_row_lifecycle_begin
   public :: odex_observe_hairer_step_entry
   public :: odex_observe_hairer_h_min
   public :: odex_observe_h_min
   public :: odex_observe_initial_step
   public :: odex_observe_large_error_threshold
   public :: odex_observe_order_transition
   public :: odex_observe_stability_reject
   public :: odex_result_reset
   public :: odex_result_mark_success
   public :: odex_result_mark_failure
   public :: odex_result_to_intode_status
   public :: odex_status_from_failure_reason
   public :: odex_status_is_failure
   public :: odex_status_is_mechanism_status
   public :: odex_sundials_cvode_available

contains

   subroutine odex_default_options(options, abs_tol, rel_tol)
      type(odex_options), intent(out) :: options
      real(dp), intent(in), optional :: abs_tol, rel_tol

      options%abs_tol = 0.0_dp
      options%rel_tol = 0.0_dp
      if (present(abs_tol)) options%abs_tol = abs_tol
      if (present(rel_tol)) options%rel_tol = rel_tol
      options%backend = odex_backend_kind_odex
      options%k_min = odex_k_min
      options%k_max = odex_k_max
      options%max_steps = odex_max_steps_default
      options%cvode_fixedpoint_m = 0
      options%cvode_max_order = 0
      options%cvode_max_steps = 0
      options%cvode_max_err_test_fails = 0
      options%cvode_max_conv_fails = 0
      options%cvode_max_nonlin_iters = 0
      options%cvode_min_step = 0.0_dp
      options%dop853_max_reject = 100000
      options%dop853_max_rhs_evals = 0
      options%dop853_min_step = 0.0_dp
      options%dop853_max_step = 0.0_dp
      options%dop853_safety = 0.9_dp
      options%dop853_fac1 = 0.333_dp
      options%dop853_fac2 = 6.0_dp
      options%dop853_beta = 0.0_dp
      options%dop853_hinit_enabled = .true.
      options%dop853_hinit_factor = 0.01_dp
      options%dop853_hinit_min = 1.0e-6_dp
      options%dop853_stiffness_check_enabled = .true.
      options%dop853_stiffness_check_interval = 1000
      options%dop853_stiffness_max_hits = 15
      options%dop853_stiffness_threshold = 6.1_dp
      options%step_sequence = odex_step_sequence_iwork3
      options%stability_control = odex_stability_control_none
      options%controller_policy = odex_controller_policy_hairer_experimental
      options%endpoint_only = .true.
      options%h_min_c_fp = 16.0_dp
      options%h_min_c_tol = 0.01_dp
      options%h_min_c_span = 1.0e-12_dp
      options%initial_step_fraction = 0.01_dp
      options%step_size_bound_fac1 = 0.02_dp
      options%step_size_bound_fac2 = 4.0_dp
      options%order_decrease_factor = 0.8_dp
      options%order_increase_factor = 0.9_dp
      options%stability_growth_limit = 4.0_dp
   end subroutine odex_default_options

   subroutine odex_apply_backend_name(options, backend_token)
      type(odex_options), intent(inout) :: options
      character(len=*), intent(in) :: backend_token

      select case (trim(odex_to_lower_ascii(backend_token)))
      case ("odex", "internal", "default")
         options%backend = odex_backend_kind_odex
      case ("sundials", "sundials_cvode", "cvode")
         options%backend = odex_backend_kind_sundials_cvode
      case ("dop853", "dopri853", "dormand_prince_853")
         options%backend = odex_backend_kind_dop853
      case default
         options%backend = -1
      end select
   end subroutine odex_apply_backend_name

   subroutine odex_apply_controller_policy_name(options, policy_token)
      type(odex_options), intent(inout) :: options
      character(len=*), intent(in) :: policy_token

      select case (trim(odex_to_lower_ascii(policy_token)))
      case ("", "default", "tltm", "tltm_endpoint", "endpoint", "f18b4b", &
            "hairer", "hairer_experimental", "hairer_route", "experimental")
         options%controller_policy = odex_controller_policy_hairer_experimental
      case default
         options%controller_policy = -1
      end select
   end subroutine odex_apply_controller_policy_name

   function odex_backend_name(backend) result(name)
      integer, intent(in) :: backend
      character(len=32) :: name

      select case (backend)
      case (odex_backend_kind_odex)
         name = "odex"
      case (odex_backend_kind_sundials_cvode)
         name = "sundials_cvode"
      case (odex_backend_kind_dop853)
         name = "dop853"
      case default
         name = "invalid"
      end select
   end function odex_backend_name

   function odex_controller_policy_name(controller_policy) result(name)
      integer, intent(in) :: controller_policy
      character(len=32) :: name

      select case (controller_policy)
      case (odex_controller_policy_hairer_experimental)
         name = "hairer_experimental"
      case default
         name = "invalid"
      end select
   end function odex_controller_policy_name

   logical function odex_sundials_cvode_available() result(available)
      available = (tltm_sundials_cvode_available() == 1_c_int)
   end function odex_sundials_cvode_available

   subroutine odex_integrate_endpoint(f, y, t, res, error_flag, result_state, workspace, options)
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      type(odex_result), intent(out) :: result_state
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in), optional :: options

      type(odex_options) :: opts
      real(dp) :: h, tc, er1, h_min, t_new, h_step, h_initial_guess
      real(dp) :: h_min_fp, h_min_tol, h_min_span
      integer :: state_size, k, step_count, accepted_steps, rejected_steps, stability_rejects
      integer :: hairer_phase
      logical :: is_last_step, invalid_rhs, stability_rejected, hairer_policy, endpoint_reached
      type(odex_step_telemetry) :: step_stats
      type(odex_hairer_controller_state) :: hairer_state
      type(odex_hairer_controller_decision) :: hairer_decision

      call odex_default_options(opts)
      if (present(options)) opts = options
      call odex_normalize_options(opts)
      call odex_result_reset(result_state)

      state_size = size(y)
      error_flag = .true.

      if (size(res) /= state_size .or. state_size <= 0) then
         if (size(res) > 0) res = 0.0_dp
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if
      res = y

      if (opts%max_steps <= 0) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if

      if (t == 0.0_dp) then
         error_flag = .false.
         call odex_result_mark_success(result_state, odex_status_success_zero_time, 0, 0, 0.0_dp)
         return
      end if

      select case (opts%backend)
      case (odex_backend_kind_sundials_cvode)
         call odex_sundials_integrate_endpoint(f, y, t, res, error_flag, result_state, opts)
         return
      case (odex_backend_kind_dop853)
         call dop853_integrate_endpoint(f, y, t, res, error_flag, result_state, workspace, opts)
         return
      case (odex_backend_kind_odex)
         continue
      case default
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end select

      if (opts%step_sequence /= odex_step_sequence_iwork3) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if
      if (.not. odex_controller_policy_is_valid(opts%controller_policy)) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if

      call ensure_odex_workspace_object(workspace, opts%k_max + 1, state_size)
      hairer_policy = (opts%controller_policy == odex_controller_policy_hairer_experimental)

      if (hairer_policy) then
         call odex_observe_hairer_h_min(opts, t, h_min, h_min_fp, h_min_tol, h_min_span)
      else
         call odex_observe_h_min(opts, t, h_min, h_min_fp, h_min_tol, h_min_span)
      end if

      tc = 0.0_dp
      workspace%ystate(1:state_size) = y
      h_initial_guess = t*opts%initial_step_fraction
      if (h_initial_guess == 0.0_dp) h_initial_guess = sign(h_min, t)
      if (hairer_policy) then
         call odex_observe_hairer_controller_initial_state(opts, t, h_initial_guess, 0.0_dp, hairer_state)
         h = hairer_state%h
         k = hairer_state%k
      else
         h = h_initial_guess
         k = opts%k_min
      end if
      step_count = 0
      accepted_steps = 0
      rejected_steps = 0
      stability_rejects = 0
      h_step = 0.0_dp

      do
         step_count = step_count + 1
         if (step_count > opts%max_steps) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_max_steps, accepted_steps, &
                                          1 + rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if

         if (hairer_policy) then
            call odex_observe_hairer_controller_step_entry(tc, t, epsilon(1.0_dp), hairer_state, hairer_decision)
            if (hairer_decision%action == odex_hairer_controller_action_invalid) then
               res = workspace%ystate(1:state_size)
               call odex_result_mark_failure(result_state, odex_reason_invalid, accepted_steps, &
                                             rejected_steps, k, h, t - tc)
               result_state%stability_rejects = stability_rejects
               return
            end if
            endpoint_reached = hairer_decision%endpoint_reached
            is_last_step = hairer_decision%last_step
            h = hairer_state%h
            k = hairer_state%k
            if (endpoint_reached .or. h == 0.0_dp) exit
         else
            if ((t >= 0.0_dp .and. tc + h >= t) .or. (t < 0.0_dp .and. tc + h <= t)) then
               is_last_step = .true.
               h = t - tc
            else
               is_last_step = .false.
            end if
         end if

         call odex_result_record_step_entry(result_state, hairer_policy, step_count, is_last_step)
         t_new = tc + h
         h_step = h
         if (hairer_policy) then
            if (step_count == 1 .or. is_last_step) then
               hairer_phase = odex_hairer_controller_phase_first_last
            else
               hairer_phase = odex_hairer_controller_phase_basic
            end if
            call odex_step_hairer_controller(f, workspace%ystate(1:state_size), hairer_phase, hairer_state, &
                                             res, er1, workspace, opts, stability_rejected, invalid_rhs, step_stats)
            h = hairer_state%h
            k = hairer_state%k
         else
            call odex_step(f, workspace%ystate(1:state_size), h, k, res, er1, workspace, opts, &
                           stability_rejected, invalid_rhs, step_stats)
         end if
         call odex_result_record_step_telemetry(result_state, step_stats)

         if (invalid_rhs) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_invalid, accepted_steps, &
                                          rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if

         if (vector_has_invalid(res(1:state_size)) .or. .not. ieee_is_finite(h)) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_invalid, accepted_steps, &
                                          1 + rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if

         if (er1 < 1.0_dp) then
            tc = t_new
            workspace%ystate(1:state_size) = res(1:state_size)
            accepted_steps = accepted_steps + 1
            if (is_last_step) exit
         else
            rejected_steps = rejected_steps + 1
            if (stability_rejected) stability_rejects = stability_rejects + 1
         end if

         if (abs(h) < h_min) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_h_min, accepted_steps, &
                                          1 + rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if
      end do

      res = workspace%ystate(1:state_size)
      error_flag = .false.
      call odex_result_mark_success(result_state, odex_status_success, accepted_steps, k, h_step)
      result_state%rejected_steps = rejected_steps
      result_state%stability_rejects = stability_rejects
   end subroutine odex_integrate_endpoint

   subroutine odex_integrate_endpoint_context(f, y, t, res, error_flag, result_state, workspace, options, rhs_context)
      procedure(ode_rhs_context) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      type(odex_result), intent(out) :: result_state
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in), optional :: options
      class(*), intent(inout), target :: rhs_context

      type(odex_options) :: opts
      real(dp) :: h, tc, er1, h_min, t_new, h_step, h_initial_guess
      real(dp) :: h_min_fp, h_min_tol, h_min_span
      integer :: state_size, k, step_count, accepted_steps, rejected_steps, stability_rejects
      integer :: hairer_phase
      logical :: is_last_step, invalid_rhs, stability_rejected, hairer_policy, endpoint_reached
      type(odex_step_telemetry) :: step_stats
      type(odex_hairer_controller_state) :: hairer_state
      type(odex_hairer_controller_decision) :: hairer_decision

      call odex_default_options(opts)
      if (present(options)) opts = options
      call odex_normalize_options(opts)
      call odex_result_reset(result_state)

      state_size = size(y)
      error_flag = .true.

      if (size(res) /= state_size .or. state_size <= 0) then
         if (size(res) > 0) res = 0.0_dp
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if
      res = y

      if (opts%max_steps <= 0) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if

      if (t == 0.0_dp) then
         error_flag = .false.
         call odex_result_mark_success(result_state, odex_status_success_zero_time, 0, 0, 0.0_dp)
         return
      end if

      select case (opts%backend)
      case (odex_backend_kind_sundials_cvode)
         call odex_sundials_integrate_endpoint_context(f, y, t, res, error_flag, result_state, opts, rhs_context)
         return
      case (odex_backend_kind_dop853)
         call dop853_integrate_endpoint_context(f, y, t, res, error_flag, result_state, workspace, opts, rhs_context)
         return
      case (odex_backend_kind_odex)
         continue
      case default
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end select

      if (opts%step_sequence /= odex_step_sequence_iwork3) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if
      if (.not. odex_controller_policy_is_valid(opts%controller_policy)) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if

      call ensure_odex_workspace_object(workspace, opts%k_max + 1, state_size)
      hairer_policy = (opts%controller_policy == odex_controller_policy_hairer_experimental)

      if (hairer_policy) then
         call odex_observe_hairer_h_min(opts, t, h_min, h_min_fp, h_min_tol, h_min_span)
      else
         call odex_observe_h_min(opts, t, h_min, h_min_fp, h_min_tol, h_min_span)
      end if

      tc = 0.0_dp
      workspace%ystate(1:state_size) = y
      h_initial_guess = t*opts%initial_step_fraction
      if (h_initial_guess == 0.0_dp) h_initial_guess = sign(h_min, t)
      if (hairer_policy) then
         call odex_observe_hairer_controller_initial_state(opts, t, h_initial_guess, 0.0_dp, hairer_state)
         h = hairer_state%h
         k = hairer_state%k
      else
         h = h_initial_guess
         k = opts%k_min
      end if
      step_count = 0
      accepted_steps = 0
      rejected_steps = 0
      stability_rejects = 0
      h_step = 0.0_dp

      do
         step_count = step_count + 1
         if (step_count > opts%max_steps) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_max_steps, accepted_steps, &
                                          1 + rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if

         if (hairer_policy) then
            call odex_observe_hairer_controller_step_entry(tc, t, epsilon(1.0_dp), hairer_state, hairer_decision)
            if (hairer_decision%action == odex_hairer_controller_action_invalid) then
               res = workspace%ystate(1:state_size)
               call odex_result_mark_failure(result_state, odex_reason_invalid, accepted_steps, &
                                             rejected_steps, k, h, t - tc)
               result_state%stability_rejects = stability_rejects
               return
            end if
            endpoint_reached = hairer_decision%endpoint_reached
            is_last_step = hairer_decision%last_step
            h = hairer_state%h
            k = hairer_state%k
            if (endpoint_reached .or. h == 0.0_dp) exit
         else
            if ((t >= 0.0_dp .and. tc + h >= t) .or. (t < 0.0_dp .and. tc + h <= t)) then
               is_last_step = .true.
               h = t - tc
            else
               is_last_step = .false.
            end if
         end if

         call odex_result_record_step_entry(result_state, hairer_policy, step_count, is_last_step)
         t_new = tc + h
         h_step = h
         if (hairer_policy) then
            if (step_count == 1 .or. is_last_step) then
               hairer_phase = odex_hairer_controller_phase_first_last
            else
               hairer_phase = odex_hairer_controller_phase_basic
            end if
            call odex_step_hairer_controller_context(f, workspace%ystate(1:state_size), hairer_phase, hairer_state, &
                                                     res, er1, workspace, opts, stability_rejected, invalid_rhs, &
                                                     step_stats, rhs_context)
            h = hairer_state%h
            k = hairer_state%k
         else
            call odex_step_context(f, workspace%ystate(1:state_size), h, k, res, er1, workspace, opts, &
                                   stability_rejected, invalid_rhs, step_stats, rhs_context)
         end if
         call odex_result_record_step_telemetry(result_state, step_stats)

         if (invalid_rhs) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_invalid, accepted_steps, &
                                          rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if

         if (vector_has_invalid(res(1:state_size)) .or. .not. ieee_is_finite(h)) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_invalid, accepted_steps, &
                                          1 + rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if

         if (er1 < 1.0_dp) then
            tc = t_new
            workspace%ystate(1:state_size) = res(1:state_size)
            accepted_steps = accepted_steps + 1
            if (is_last_step) exit
         else
            rejected_steps = rejected_steps + 1
            if (stability_rejected) stability_rejects = stability_rejects + 1
         end if

         if (abs(h) < h_min) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_h_min, accepted_steps, &
                                          1 + rejected_steps, k, h, t - tc)
            result_state%stability_rejects = stability_rejects
            return
         end if
      end do

      res = workspace%ystate(1:state_size)
      error_flag = .false.
      call odex_result_mark_success(result_state, odex_status_success, accepted_steps, k, h_step)
      result_state%rejected_steps = rejected_steps
      result_state%stability_rejects = stability_rejects
   end subroutine odex_integrate_endpoint_context

   subroutine odex_sundials_integrate_endpoint(f, y, t, res, error_flag, result_state, opts)
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      type(odex_result), intent(inout) :: result_state
      type(odex_options), intent(in) :: opts

      integer(c_int) :: c_status, c_steps
      integer(c_int) :: c_rhs_evals, c_error_test_fails, c_nonlinear_iters
      integer(c_int) :: c_nonlinear_conv_fails, c_step_solve_fails, c_last_order
      real(c_double) :: c_last_step, c_t_reached
      integer :: state_size

      state_size = size(y)
      res = y
      error_flag = .true.

      if (.not. odex_sundials_cvode_available()) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 0, 0, 0.0_dp, t)
         return
      end if
      if (cvode_callback_active) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 0, 0, 0.0_dp, t)
         return
      end if

      cvode_callback_active = .true.
      cvode_active_rhs_mode = 1
      cvode_active_rhs => f

      c_status = tltm_sundials_cvode_integrate(int(state_size, c_int), y, real(t, c_double), &
                                               real(opts%abs_tol, c_double), real(opts%rel_tol, c_double), &
                                               int(opts%max_steps, c_int), int(opts%cvode_fixedpoint_m, c_int), &
                                               int(opts%cvode_max_order, c_int), int(opts%cvode_max_steps, c_int), &
                                               real(opts%cvode_min_step, c_double), &
                                               int(opts%cvode_max_err_test_fails, c_int), &
                                               int(opts%cvode_max_conv_fails, c_int), &
                                               int(opts%cvode_max_nonlin_iters, c_int), &
                                               res, c_steps, c_last_step, c_t_reached, &
                                               c_rhs_evals, c_error_test_fails, c_nonlinear_iters, &
                                               c_nonlinear_conv_fails, c_step_solve_fails, c_last_order, &
                                               c_null_ptr, c_funloc(odex_cvode_rhs_dispatch))

      call odex_cvode_clear_callback()
      call odex_sundials_status_to_result(c_status, c_steps, c_last_step, c_t_reached, c_rhs_evals, &
                                          c_error_test_fails, c_nonlinear_iters, c_nonlinear_conv_fails, &
                                          c_step_solve_fails, c_last_order, t, error_flag, result_state)
   end subroutine odex_sundials_integrate_endpoint

   subroutine odex_sundials_integrate_endpoint_context(f, y, t, res, error_flag, result_state, opts, rhs_context)
      procedure(ode_rhs_context) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      type(odex_result), intent(inout) :: result_state
      type(odex_options), intent(in) :: opts
      class(*), intent(inout), target :: rhs_context

      integer(c_int) :: c_status, c_steps
      integer(c_int) :: c_rhs_evals, c_error_test_fails, c_nonlinear_iters
      integer(c_int) :: c_nonlinear_conv_fails, c_step_solve_fails, c_last_order
      real(c_double) :: c_last_step, c_t_reached
      integer :: state_size

      state_size = size(y)
      res = y
      error_flag = .true.

      if (.not. odex_sundials_cvode_available()) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 0, 0, 0.0_dp, t)
         return
      end if
      if (cvode_callback_active) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 0, 0, 0.0_dp, t)
         return
      end if

      cvode_callback_active = .true.
      cvode_active_rhs_mode = 2
      cvode_active_rhs_context => f
      cvode_active_rhs_context_data => rhs_context

      c_status = tltm_sundials_cvode_integrate(int(state_size, c_int), y, real(t, c_double), &
                                               real(opts%abs_tol, c_double), real(opts%rel_tol, c_double), &
                                               int(opts%max_steps, c_int), int(opts%cvode_fixedpoint_m, c_int), &
                                               int(opts%cvode_max_order, c_int), int(opts%cvode_max_steps, c_int), &
                                               real(opts%cvode_min_step, c_double), &
                                               int(opts%cvode_max_err_test_fails, c_int), &
                                               int(opts%cvode_max_conv_fails, c_int), &
                                               int(opts%cvode_max_nonlin_iters, c_int), &
                                               res, c_steps, c_last_step, c_t_reached, &
                                               c_rhs_evals, c_error_test_fails, c_nonlinear_iters, &
                                               c_nonlinear_conv_fails, c_step_solve_fails, c_last_order, &
                                               c_null_ptr, c_funloc(odex_cvode_rhs_dispatch))

      call odex_cvode_clear_callback()
      call odex_sundials_status_to_result(c_status, c_steps, c_last_step, c_t_reached, c_rhs_evals, &
                                          c_error_test_fails, c_nonlinear_iters, c_nonlinear_conv_fails, &
                                          c_step_solve_fails, c_last_order, t, error_flag, result_state)
   end subroutine odex_sundials_integrate_endpoint_context

   subroutine odex_sundials_status_to_result(c_status, c_steps, c_last_step, c_t_reached, c_rhs_evals, c_error_test_fails, &
                                             c_nonlinear_iters, c_nonlinear_conv_fails, c_step_solve_fails, c_last_order, &
                                             t_final, error_flag, result_state)
      integer(c_int), intent(in) :: c_status, c_steps
      integer(c_int), intent(in) :: c_rhs_evals, c_error_test_fails, c_nonlinear_iters
      integer(c_int), intent(in) :: c_nonlinear_conv_fails, c_step_solve_fails, c_last_order
      real(c_double), intent(in) :: c_last_step, c_t_reached
      real(dp), intent(in) :: t_final
      logical, intent(out) :: error_flag
      type(odex_result), intent(inout) :: result_state
      integer :: accepted_steps
      real(dp) :: t_remaining

      accepted_steps = max(0, int(c_steps))
      t_remaining = t_final - real(c_t_reached, dp)

      select case (c_status)
      case (sundials_cvode_status_success)
         error_flag = .false.
         call odex_result_mark_success(result_state, odex_status_success, accepted_steps, max(0, int(c_last_order)), &
                                       real(c_last_step, dp))
      case (sundials_cvode_status_max_steps)
         error_flag = .true.
         call odex_result_mark_failure(result_state, odex_reason_max_steps, accepted_steps, 0, max(0, int(c_last_order)), &
                                       real(c_last_step, dp), t_remaining)
      case (sundials_cvode_status_invalid, sundials_cvode_status_unavailable)
         error_flag = .true.
         call odex_result_mark_failure(result_state, odex_reason_invalid, accepted_steps, 0, max(0, int(c_last_order)), &
                                       real(c_last_step, dp), t_remaining)
      case default
         error_flag = .true.
         call odex_result_mark_failure(result_state, odex_reason_invalid, accepted_steps, 0, max(0, int(c_last_order)), &
                                       real(c_last_step, dp), t_remaining)
      end select
      result_state%cvode_backend_used = .true.
      result_state%cvode_rhs_evals = max(0, int(c_rhs_evals))
      result_state%cvode_error_test_fails = max(0, int(c_error_test_fails))
      result_state%cvode_nonlinear_iters = max(0, int(c_nonlinear_iters))
      result_state%cvode_nonlinear_conv_fails = max(0, int(c_nonlinear_conv_fails))
      result_state%cvode_step_solve_fails = max(0, int(c_step_solve_fails))
   end subroutine odex_sundials_status_to_result

   integer(c_int) function odex_cvode_rhs_dispatch(user_ctx, n_c, t_c, y_ptr, ydot_ptr) result(status_code) bind(C)
      type(c_ptr), value :: user_ctx
      integer(c_int), value :: n_c
      real(c_double), value :: t_c
      type(c_ptr), value :: y_ptr, ydot_ptr
      real(dp), pointer :: y(:), ydot(:)
      integer :: n

      status_code = 1_c_int
      n = int(n_c)
      if (n <= 0) return
      if (.not. c_associated(y_ptr) .or. .not. c_associated(ydot_ptr)) return
      if (c_associated(user_ctx)) continue
      if (t_c /= t_c) return

      call c_f_pointer(y_ptr, y, [n])
      call c_f_pointer(ydot_ptr, ydot, [n])

      select case (cvode_active_rhs_mode)
      case (1)
         if (.not. associated(cvode_active_rhs)) return
         ydot(1:n) = cvode_active_rhs(y(1:n))
      case (2)
         if (.not. associated(cvode_active_rhs_context)) return
         if (.not. associated(cvode_active_rhs_context_data)) return
         ydot(1:n) = cvode_active_rhs_context(y(1:n), cvode_active_rhs_context_data)
      case default
         return
      end select

      if (vector_has_invalid(ydot(1:n))) return
      status_code = 0_c_int
   end function odex_cvode_rhs_dispatch

   subroutine odex_cvode_clear_callback()
      nullify (cvode_active_rhs)
      nullify (cvode_active_rhs_context)
      nullify (cvode_active_rhs_context_data)
      cvode_active_rhs_mode = 0
      cvode_callback_active = .false.
   end subroutine odex_cvode_clear_callback

   subroutine dop853_integrate_endpoint(f, y, t, res, error_flag, result_state, workspace, opts)
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      type(odex_result), intent(inout) :: result_state
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts

      integer :: state_size, step_attempts, accepted_steps, rejected_steps, rhs_evals, rhs_used, consecutive_rejects
      integer :: stiffness_hits
      logical :: invalid_rhs, is_last_step, rejected_last, stiffness_hit
      real(dp) :: tc, h, h_new, h_min, h_step, err, facold, t_new, h_abs_max

      call odex_result_reset(result_state)
      state_size = size(y)
      error_flag = .true.
      if (size(res) /= state_size .or. state_size <= 0) then
         if (size(res) > 0) res = 0.0_dp
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if
      res = y
      if (opts%max_steps <= 0) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if
      if (t == 0.0_dp) then
         error_flag = .false.
         call odex_result_mark_success(result_state, odex_status_success_zero_time, 0, dop853_order, 0.0_dp)
         return
      end if

      call ensure_odex_workspace_object(workspace, max(dop853_stage_count, opts%k_max + 1), state_size)
      workspace%ystate(1:state_size) = y(1:state_size)
      tc = 0.0_dp
      step_attempts = 0
      accepted_steps = 0
      rejected_steps = 0
      consecutive_rejects = 0
      stiffness_hits = 0
      rhs_evals = 0
      facold = 1.0e-4_dp
      rejected_last = .false.
      h_min = dop853_effective_h_min(opts, tc)
      h_abs_max = dop853_step_abs_bound(opts, tc, t)
      if (h_abs_max < h_min) then
         call odex_result_mark_failure(result_state, odex_reason_h_min, 0, 0, dop853_order, &
                                       sign(h_abs_max, t), t)
         call dop853_record_result(result_state, rhs_evals, step_attempts)
         return
      end if
      if (opts%dop853_hinit_enabled) then
         if (opts%dop853_max_rhs_evals > 0 .and. 2 > opts%dop853_max_rhs_evals) then
            call odex_result_mark_failure(result_state, odex_reason_max_rhs_evals, 0, 0, dop853_order, 0.0_dp, t)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if
         call dop853_initial_step(f, y, t, h_abs_max, h_min, workspace, opts, h, invalid_rhs, rhs_used)
         rhs_evals = rhs_evals + rhs_used
         if (invalid_rhs) then
            call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 0, dop853_order, 0.0_dp, t)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if
      else
         h = t*opts%initial_step_fraction
         if (h == 0.0_dp) h = sign(h_min, t)
         h = dop853_clamp_step(h, opts, tc, t)
      end if
      h_step = h

      do
         h_min = dop853_effective_h_min(opts, tc)
         h = dop853_clamp_step(h, opts, tc, t)
         if (step_attempts >= opts%max_steps) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_max_steps, accepted_steps, rejected_steps, &
                                          dop853_order, h, t - tc)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if
         if (opts%dop853_max_rhs_evals > 0 .and. rhs_evals + dop853_stage_count > opts%dop853_max_rhs_evals) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_max_rhs_evals, accepted_steps, rejected_steps, &
                                          dop853_order, h, t - tc)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if
         if (abs(h) < h_min) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_h_min, accepted_steps, rejected_steps, &
                                          dop853_order, h, t - tc)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if

         if ((tc + 1.01_dp*h - t)*sign(1.0_dp, t - tc) > 0.0_dp) then
            h = t - tc
            is_last_step = .true.
         else
            is_last_step = .false.
         end if

         h_step = h
         call dop853_step(f, workspace%ystate(1:state_size), h, res, err, workspace, opts, invalid_rhs, rhs_used)
         step_attempts = step_attempts + 1
         rhs_evals = rhs_evals + rhs_used
         if (invalid_rhs) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_invalid, accepted_steps, rejected_steps, &
                                          dop853_order, h, t - tc)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if

         if (err <= 1.0_dp) then
            t_new = tc + h
            accepted_steps = accepted_steps + 1
            if (.not. is_last_step) then
               stiffness_hit = dop853_stiffness_hit(workspace%ystate(1:state_size), res(1:state_size), h, workspace, &
                                                    opts, accepted_steps)
               if (stiffness_hit) then
                  stiffness_hits = stiffness_hits + 1
               else
                  stiffness_hits = 0
               end if
               if (opts%dop853_stiffness_check_enabled .and. &
                   stiffness_hits >= opts%dop853_stiffness_max_hits) then
                  workspace%ystate(1:state_size) = res(1:state_size)
                  call odex_result_mark_failure(result_state, odex_reason_stiffness, accepted_steps, rejected_steps, &
                                                dop853_order, h, t - t_new)
                  call dop853_record_result(result_state, rhs_evals, step_attempts)
                  return
               end if
            end if
            workspace%ystate(1:state_size) = res(1:state_size)
            consecutive_rejects = 0
            h_new = dop853_next_accepted_step(h, err, facold, opts)
            facold = max(err, 1.0e-4_dp)
            if (is_last_step) exit
            if (rejected_last) h_new = sign(min(abs(h_new), abs(h)), h_new)
            rejected_last = .false.
            tc = t_new
            h = dop853_clamp_step(h_new, opts, tc, t)
         else
            rejected_steps = rejected_steps + 1
            consecutive_rejects = consecutive_rejects + 1
            if (opts%dop853_max_reject > 0 .and. consecutive_rejects >= opts%dop853_max_reject) then
               res = workspace%ystate(1:state_size)
               call odex_result_mark_failure(result_state, odex_reason_max_rejects, accepted_steps, rejected_steps, &
                                             dop853_order, h, t - tc)
               call dop853_record_result(result_state, rhs_evals, step_attempts)
               return
            end if
            h = dop853_clamp_step(dop853_next_rejected_step(h, err, opts), opts, tc, t)
            rejected_last = .true.
         end if
      end do

      error_flag = .false.
      call odex_result_mark_success(result_state, odex_status_success, accepted_steps, dop853_order, h_step)
      result_state%rejected_steps = rejected_steps
      call dop853_record_result(result_state, rhs_evals, step_attempts)
   end subroutine dop853_integrate_endpoint

   subroutine dop853_integrate_endpoint_context(f, y, t, res, error_flag, result_state, workspace, opts, rhs_context)
      procedure(ode_rhs_context) :: f
      real(dp), intent(in) :: y(:), t
      real(dp), intent(out) :: res(:)
      logical, intent(out) :: error_flag
      type(odex_result), intent(inout) :: result_state
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      class(*), intent(inout) :: rhs_context

      integer :: state_size, step_attempts, accepted_steps, rejected_steps, rhs_evals, rhs_used, consecutive_rejects
      integer :: stiffness_hits
      logical :: invalid_rhs, is_last_step, rejected_last, stiffness_hit
      real(dp) :: tc, h, h_new, h_min, h_step, err, facold, t_new, h_abs_max

      call odex_result_reset(result_state)
      state_size = size(y)
      error_flag = .true.
      if (size(res) /= state_size .or. state_size <= 0) then
         if (size(res) > 0) res = 0.0_dp
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if
      res = y
      if (opts%max_steps <= 0) then
         call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 1, 0, 0.0_dp, t)
         return
      end if
      if (t == 0.0_dp) then
         error_flag = .false.
         call odex_result_mark_success(result_state, odex_status_success_zero_time, 0, dop853_order, 0.0_dp)
         return
      end if

      call ensure_odex_workspace_object(workspace, max(dop853_stage_count, opts%k_max + 1), state_size)
      workspace%ystate(1:state_size) = y(1:state_size)
      tc = 0.0_dp
      step_attempts = 0
      accepted_steps = 0
      rejected_steps = 0
      consecutive_rejects = 0
      stiffness_hits = 0
      rhs_evals = 0
      facold = 1.0e-4_dp
      rejected_last = .false.
      h_min = dop853_effective_h_min(opts, tc)
      h_abs_max = dop853_step_abs_bound(opts, tc, t)
      if (h_abs_max < h_min) then
         call odex_result_mark_failure(result_state, odex_reason_h_min, 0, 0, dop853_order, &
                                       sign(h_abs_max, t), t)
         call dop853_record_result(result_state, rhs_evals, step_attempts)
         return
      end if
      if (opts%dop853_hinit_enabled) then
         if (opts%dop853_max_rhs_evals > 0 .and. 2 > opts%dop853_max_rhs_evals) then
            call odex_result_mark_failure(result_state, odex_reason_max_rhs_evals, 0, 0, dop853_order, 0.0_dp, t)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if
         call dop853_initial_step_context(f, y, t, h_abs_max, h_min, workspace, opts, h, invalid_rhs, rhs_used, rhs_context)
         rhs_evals = rhs_evals + rhs_used
         if (invalid_rhs) then
            call odex_result_mark_failure(result_state, odex_reason_invalid, 0, 0, dop853_order, 0.0_dp, t)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if
      else
         h = t*opts%initial_step_fraction
         if (h == 0.0_dp) h = sign(h_min, t)
         h = dop853_clamp_step(h, opts, tc, t)
      end if
      h_step = h

      do
         h_min = dop853_effective_h_min(opts, tc)
         h = dop853_clamp_step(h, opts, tc, t)
         if (step_attempts >= opts%max_steps) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_max_steps, accepted_steps, rejected_steps, &
                                          dop853_order, h, t - tc)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if
         if (opts%dop853_max_rhs_evals > 0 .and. rhs_evals + dop853_stage_count > opts%dop853_max_rhs_evals) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_max_rhs_evals, accepted_steps, rejected_steps, &
                                          dop853_order, h, t - tc)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if
         if (abs(h) < h_min) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_h_min, accepted_steps, rejected_steps, &
                                          dop853_order, h, t - tc)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if

         if ((tc + 1.01_dp*h - t)*sign(1.0_dp, t - tc) > 0.0_dp) then
            h = t - tc
            is_last_step = .true.
         else
            is_last_step = .false.
         end if

         h_step = h
         call dop853_step_context(f, workspace%ystate(1:state_size), h, res, err, workspace, opts, invalid_rhs, rhs_used, &
                                  rhs_context)
         step_attempts = step_attempts + 1
         rhs_evals = rhs_evals + rhs_used
         if (invalid_rhs) then
            res = workspace%ystate(1:state_size)
            call odex_result_mark_failure(result_state, odex_reason_invalid, accepted_steps, rejected_steps, &
                                          dop853_order, h, t - tc)
            call dop853_record_result(result_state, rhs_evals, step_attempts)
            return
         end if

         if (err <= 1.0_dp) then
            t_new = tc + h
            accepted_steps = accepted_steps + 1
            if (.not. is_last_step) then
               stiffness_hit = dop853_stiffness_hit(workspace%ystate(1:state_size), res(1:state_size), h, workspace, &
                                                    opts, accepted_steps)
               if (stiffness_hit) then
                  stiffness_hits = stiffness_hits + 1
               else
                  stiffness_hits = 0
               end if
               if (opts%dop853_stiffness_check_enabled .and. &
                   stiffness_hits >= opts%dop853_stiffness_max_hits) then
                  workspace%ystate(1:state_size) = res(1:state_size)
                  call odex_result_mark_failure(result_state, odex_reason_stiffness, accepted_steps, rejected_steps, &
                                                dop853_order, h, t - t_new)
                  call dop853_record_result(result_state, rhs_evals, step_attempts)
                  return
               end if
            end if
            workspace%ystate(1:state_size) = res(1:state_size)
            consecutive_rejects = 0
            h_new = dop853_next_accepted_step(h, err, facold, opts)
            facold = max(err, 1.0e-4_dp)
            if (is_last_step) exit
            if (rejected_last) h_new = sign(min(abs(h_new), abs(h)), h_new)
            rejected_last = .false.
            tc = t_new
            h = dop853_clamp_step(h_new, opts, tc, t)
         else
            rejected_steps = rejected_steps + 1
            consecutive_rejects = consecutive_rejects + 1
            if (opts%dop853_max_reject > 0 .and. consecutive_rejects >= opts%dop853_max_reject) then
               res = workspace%ystate(1:state_size)
               call odex_result_mark_failure(result_state, odex_reason_max_rejects, accepted_steps, rejected_steps, &
                                             dop853_order, h, t - tc)
               call dop853_record_result(result_state, rhs_evals, step_attempts)
               return
            end if
            h = dop853_clamp_step(dop853_next_rejected_step(h, err, opts), opts, tc, t)
            rejected_last = .true.
         end if
      end do

      error_flag = .false.
      call odex_result_mark_success(result_state, odex_status_success, accepted_steps, dop853_order, h_step)
      result_state%rejected_steps = rejected_steps
      call dop853_record_result(result_state, rhs_evals, step_attempts)
   end subroutine dop853_integrate_endpoint_context

   subroutine dop853_initial_step(f, y, t, h_abs_max, h_min, workspace, opts, h, invalid_rhs, rhs_evals)
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), t, h_abs_max, h_min
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      real(dp), intent(out) :: h
      logical, intent(out) :: invalid_rhs
      integer, intent(out) :: rhs_evals

      integer :: i, n
      real(dp) :: d0, d1, d2, der12, h0_abs, h1_abs, scale

      n = size(y)
      h = sign(min(max(h_min, tiny(1.0_dp)), max(h_abs_max, tiny(1.0_dp))), t)
      rhs_evals = 0
      invalid_rhs = .false.
      if (n <= 0 .or. h_abs_max <= 0.0_dp) then
         invalid_rhs = .true.
         return
      end if

      workspace%fbase(1:n) = f(y)
      rhs_evals = rhs_evals + 1
      if (vector_has_invalid(workspace%fbase(1:n))) then
         invalid_rhs = .true.
         return
      end if

      d0 = 0.0_dp
      d1 = 0.0_dp
      do i = 1, n
         scale = opts%abs_tol + opts%rel_tol*abs(y(i))
         scale = max(scale, tiny(1.0_dp))
         d0 = d0 + (y(i)/scale)**2
         d1 = d1 + (workspace%fbase(i)/scale)**2
      end do
      d0 = sqrt(d0/real(n, dp))
      d1 = sqrt(d1/real(n, dp))
      if (d0 < 1.0e-5_dp .or. d1 < 1.0e-5_dp) then
         h0_abs = opts%dop853_hinit_min
      else
         h0_abs = opts%dop853_hinit_factor*d0/d1
      end if
      h0_abs = min(max(h0_abs, h_min), h_abs_max)

      workspace%yprev(1:n) = y(1:n) + sign(h0_abs, t)*workspace%fbase(1:n)
      workspace%fval(1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (vector_has_invalid(workspace%fval(1:n))) then
         invalid_rhs = .true.
         return
      end if

      d2 = 0.0_dp
      do i = 1, n
         scale = opts%abs_tol + opts%rel_tol*max(abs(y(i)), abs(workspace%yprev(i)))
         scale = max(scale, tiny(1.0_dp))
         d2 = d2 + ((workspace%fval(i) - workspace%fbase(i))/scale)**2
      end do
      d2 = sqrt(d2/real(n, dp))/max(h0_abs, tiny(1.0_dp))
      der12 = max(d1, d2)
      if (der12 <= 1.0e-15_dp) then
         h1_abs = max(opts%dop853_hinit_min, h0_abs*1.0e-3_dp)
      else
         h1_abs = (opts%dop853_hinit_factor/der12)**(1.0_dp/real(dop853_order, dp))
      end if
      h = sign(min(max(h_min, min(100.0_dp*h0_abs, h1_abs)), h_abs_max), t)
   end subroutine dop853_initial_step

   subroutine dop853_initial_step_context(f, y, t, h_abs_max, h_min, workspace, opts, h, invalid_rhs, rhs_evals, rhs_context)
      procedure(ode_rhs_context) :: f
      real(dp), intent(in) :: y(:), t, h_abs_max, h_min
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      real(dp), intent(out) :: h
      logical, intent(out) :: invalid_rhs
      integer, intent(out) :: rhs_evals
      class(*), intent(inout) :: rhs_context

      integer :: i, n
      real(dp) :: d0, d1, d2, der12, h0_abs, h1_abs, scale

      n = size(y)
      h = sign(min(max(h_min, tiny(1.0_dp)), max(h_abs_max, tiny(1.0_dp))), t)
      rhs_evals = 0
      invalid_rhs = .false.
      if (n <= 0 .or. h_abs_max <= 0.0_dp) then
         invalid_rhs = .true.
         return
      end if

      workspace%fbase(1:n) = f(y, rhs_context)
      rhs_evals = rhs_evals + 1
      if (vector_has_invalid(workspace%fbase(1:n))) then
         invalid_rhs = .true.
         return
      end if

      d0 = 0.0_dp
      d1 = 0.0_dp
      do i = 1, n
         scale = opts%abs_tol + opts%rel_tol*abs(y(i))
         scale = max(scale, tiny(1.0_dp))
         d0 = d0 + (y(i)/scale)**2
         d1 = d1 + (workspace%fbase(i)/scale)**2
      end do
      d0 = sqrt(d0/real(n, dp))
      d1 = sqrt(d1/real(n, dp))
      if (d0 < 1.0e-5_dp .or. d1 < 1.0e-5_dp) then
         h0_abs = opts%dop853_hinit_min
      else
         h0_abs = opts%dop853_hinit_factor*d0/d1
      end if
      h0_abs = min(max(h0_abs, h_min), h_abs_max)

      workspace%yprev(1:n) = y(1:n) + sign(h0_abs, t)*workspace%fbase(1:n)
      workspace%fval(1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (vector_has_invalid(workspace%fval(1:n))) then
         invalid_rhs = .true.
         return
      end if

      d2 = 0.0_dp
      do i = 1, n
         scale = opts%abs_tol + opts%rel_tol*max(abs(y(i)), abs(workspace%yprev(i)))
         scale = max(scale, tiny(1.0_dp))
         d2 = d2 + ((workspace%fval(i) - workspace%fbase(i))/scale)**2
      end do
      d2 = sqrt(d2/real(n, dp))/max(h0_abs, tiny(1.0_dp))
      der12 = max(d1, d2)
      if (der12 <= 1.0e-15_dp) then
         h1_abs = max(opts%dop853_hinit_min, h0_abs*1.0e-3_dp)
      else
         h1_abs = (opts%dop853_hinit_factor/der12)**(1.0_dp/real(dop853_order, dp))
      end if
      h = sign(min(max(h_min, min(100.0_dp*h0_abs, h1_abs)), h_abs_max), t)
   end subroutine dop853_initial_step_context

   subroutine dop853_step(f, y, h, res, err, workspace, opts, invalid_rhs, rhs_evals)
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:), h
      real(dp), intent(out) :: res(:), err
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      logical, intent(out) :: invalid_rhs
      integer, intent(out) :: rhs_evals

      integer :: n

      n = size(y)
      res = y
      err = huge(1.0_dp)
      rhs_evals = 0
      invalid_rhs = .false.

      workspace%tableau(1, 1, 1:n) = f(y)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(1, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*dop853_a21*workspace%tableau(1, 1, 1:n)
      workspace%tableau(2, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(2, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a31*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a32*workspace%tableau(2, 1, 1:n))
      workspace%tableau(3, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(3, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a41*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a43*workspace%tableau(3, 1, 1:n))
      workspace%tableau(4, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(4, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a51*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a53*workspace%tableau(3, 1, 1:n) + &
                                    dop853_a54*workspace%tableau(4, 1, 1:n))
      workspace%tableau(5, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(5, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a61*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a64*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a65*workspace%tableau(5, 1, 1:n))
      workspace%tableau(6, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(6, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a71*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a74*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a75*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a76*workspace%tableau(6, 1, 1:n))
      workspace%tableau(7, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(7, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a81*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a84*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a85*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a86*workspace%tableau(6, 1, 1:n) + &
                                    dop853_a87*workspace%tableau(7, 1, 1:n))
      workspace%tableau(8, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(8, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a91*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a94*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a95*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a96*workspace%tableau(6, 1, 1:n) + &
                                    dop853_a97*workspace%tableau(7, 1, 1:n) + &
                                    dop853_a98*workspace%tableau(8, 1, 1:n))
      workspace%tableau(9, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(9, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a101*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a104*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a105*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a106*workspace%tableau(6, 1, 1:n) + &
                                    dop853_a107*workspace%tableau(7, 1, 1:n) + &
                                    dop853_a108*workspace%tableau(8, 1, 1:n) + &
                                    dop853_a109*workspace%tableau(9, 1, 1:n))
      workspace%tableau(10, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(10, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a111*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a114*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a115*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a116*workspace%tableau(6, 1, 1:n) + &
                                    dop853_a117*workspace%tableau(7, 1, 1:n) + &
                                    dop853_a118*workspace%tableau(8, 1, 1:n) + &
                                    dop853_a119*workspace%tableau(9, 1, 1:n) + &
                                    dop853_a1110*workspace%tableau(10, 1, 1:n))
      workspace%tableau(11, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(11, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a121*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a124*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a125*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a126*workspace%tableau(6, 1, 1:n) + &
                                    dop853_a127*workspace%tableau(7, 1, 1:n) + &
                                    dop853_a128*workspace%tableau(8, 1, 1:n) + &
                                    dop853_a129*workspace%tableau(9, 1, 1:n) + &
                                    dop853_a1210*workspace%tableau(10, 1, 1:n) + &
                                    dop853_a1211*workspace%tableau(11, 1, 1:n))
      workspace%tableau(12, 1, 1:n) = f(workspace%yprev(1:n))
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(12, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      call dop853_finish_step(y, h, res, err, workspace, opts, invalid_rhs)
   end subroutine dop853_step

   subroutine dop853_step_context(f, y, h, res, err, workspace, opts, invalid_rhs, rhs_evals, rhs_context)
      procedure(ode_rhs_context) :: f
      real(dp), intent(in) :: y(:), h
      real(dp), intent(out) :: res(:), err
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      logical, intent(out) :: invalid_rhs
      integer, intent(out) :: rhs_evals
      class(*), intent(inout) :: rhs_context

      integer :: n

      n = size(y)
      res = y
      err = huge(1.0_dp)
      rhs_evals = 0
      invalid_rhs = .false.

      workspace%tableau(1, 1, 1:n) = f(y, rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(1, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*dop853_a21*workspace%tableau(1, 1, 1:n)
      workspace%tableau(2, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(2, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a31*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a32*workspace%tableau(2, 1, 1:n))
      workspace%tableau(3, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(3, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a41*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a43*workspace%tableau(3, 1, 1:n))
      workspace%tableau(4, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(4, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a51*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a53*workspace%tableau(3, 1, 1:n) + &
                                    dop853_a54*workspace%tableau(4, 1, 1:n))
      workspace%tableau(5, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(5, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a61*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a64*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a65*workspace%tableau(5, 1, 1:n))
      workspace%tableau(6, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(6, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a71*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a74*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a75*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a76*workspace%tableau(6, 1, 1:n))
      workspace%tableau(7, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(7, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a81*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a84*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a85*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a86*workspace%tableau(6, 1, 1:n) + &
                                    dop853_a87*workspace%tableau(7, 1, 1:n))
      workspace%tableau(8, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(8, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a91*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a94*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a95*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a96*workspace%tableau(6, 1, 1:n) + &
                                    dop853_a97*workspace%tableau(7, 1, 1:n) + &
                                    dop853_a98*workspace%tableau(8, 1, 1:n))
      workspace%tableau(9, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(9, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a101*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a104*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a105*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a106*workspace%tableau(6, 1, 1:n) + &
                                    dop853_a107*workspace%tableau(7, 1, 1:n) + &
                                    dop853_a108*workspace%tableau(8, 1, 1:n) + &
                                    dop853_a109*workspace%tableau(9, 1, 1:n))
      workspace%tableau(10, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(10, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a111*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a114*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a115*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a116*workspace%tableau(6, 1, 1:n) + &
                                    dop853_a117*workspace%tableau(7, 1, 1:n) + &
                                    dop853_a118*workspace%tableau(8, 1, 1:n) + &
                                    dop853_a119*workspace%tableau(9, 1, 1:n) + &
                                    dop853_a1110*workspace%tableau(10, 1, 1:n))
      workspace%tableau(11, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(11, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      workspace%yprev(1:n) = y + h*(dop853_a121*workspace%tableau(1, 1, 1:n) + &
                                    dop853_a124*workspace%tableau(4, 1, 1:n) + &
                                    dop853_a125*workspace%tableau(5, 1, 1:n) + &
                                    dop853_a126*workspace%tableau(6, 1, 1:n) + &
                                    dop853_a127*workspace%tableau(7, 1, 1:n) + &
                                    dop853_a128*workspace%tableau(8, 1, 1:n) + &
                                    dop853_a129*workspace%tableau(9, 1, 1:n) + &
                                    dop853_a1210*workspace%tableau(10, 1, 1:n) + &
                                    dop853_a1211*workspace%tableau(11, 1, 1:n))
      workspace%tableau(12, 1, 1:n) = f(workspace%yprev(1:n), rhs_context)
      rhs_evals = rhs_evals + 1
      if (dop853_stage_invalid(workspace%tableau(12, 1, 1:n))) then
         invalid_rhs = .true.
         return
      end if

      call dop853_finish_step(y, h, res, err, workspace, opts, invalid_rhs)
   end subroutine dop853_step_context

   subroutine dop853_finish_step(y, h, res, err, workspace, opts, invalid_rhs)
      real(dp), intent(in) :: y(:), h
      real(dp), intent(out) :: res(:), err
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      logical, intent(out) :: invalid_rhs

      integer :: i, n
      real(dp) :: err3_sum, err5_sum, erri, deno, scale

      n = size(y)
      invalid_rhs = .false.
      workspace%fval(1:n) = dop853_b1*workspace%tableau(1, 1, 1:n) + &
                            dop853_b6*workspace%tableau(6, 1, 1:n) + &
                            dop853_b7*workspace%tableau(7, 1, 1:n) + &
                            dop853_b8*workspace%tableau(8, 1, 1:n) + &
                            dop853_b9*workspace%tableau(9, 1, 1:n) + &
                            dop853_b10*workspace%tableau(10, 1, 1:n) + &
                            dop853_b11*workspace%tableau(11, 1, 1:n) + &
                            dop853_b12*workspace%tableau(12, 1, 1:n)
      res(1:n) = y(1:n) + h*workspace%fval(1:n)
      if (vector_has_invalid(res(1:n))) then
         invalid_rhs = .true.
         err = huge(1.0_dp)
         return
      end if

      ! Hairer DOP853 controls the order-8 solution with the stretched
      ! 5th/3rd-order estimator from SODE I, Sec. II.10:
      ! abs(h) * sum(err5_i**2) / sqrt(n * (sum(err5_i**2) + 0.01*sum(err3_i**2))).
      err3_sum = 0.0_dp
      err5_sum = 0.0_dp
      do i = 1, n
         scale = opts%abs_tol + opts%rel_tol*max(abs(y(i)), abs(res(i)))
         scale = max(scale, tiny(1.0_dp))
         erri = workspace%fval(i) - dop853_bhh1*workspace%tableau(1, 1, i) - &
                dop853_bhh2*workspace%tableau(9, 1, i) - dop853_bhh3*workspace%tableau(12, 1, i)
         err3_sum = err3_sum + (erri/scale)**2
         erri = dop853_er1*workspace%tableau(1, 1, i) + dop853_er6*workspace%tableau(6, 1, i) + &
                dop853_er7*workspace%tableau(7, 1, i) + dop853_er8*workspace%tableau(8, 1, i) + &
                dop853_er9*workspace%tableau(9, 1, i) + dop853_er10*workspace%tableau(10, 1, i) + &
                dop853_er11*workspace%tableau(11, 1, i) + dop853_er12*workspace%tableau(12, 1, i)
         err5_sum = err5_sum + (erri/scale)**2
      end do
      deno = err5_sum + 0.01_dp*err3_sum
      if (deno <= 0.0_dp) deno = 1.0_dp
      err = abs(h)*err5_sum*sqrt(1.0_dp/(real(n, dp)*deno))
      if (.not. ieee_is_finite(err)) err = huge(1.0_dp)
   end subroutine dop853_finish_step

   real(dp) function dop853_effective_h_min(opts, current_t) result(h_min)
      type(odex_options), intent(in) :: opts
      real(dp), intent(in) :: current_t

      if (opts%dop853_min_step > 0.0_dp) then
         call odex_observe_hairer_h_min(opts, current_t, h_min)
         h_min = max(h_min, opts%dop853_min_step)
      else
         call odex_observe_hairer_h_min(opts, current_t, h_min)
      end if
      h_min = max(h_min, tiny(1.0_dp))
   end function dop853_effective_h_min

   real(dp) function dop853_step_abs_bound(opts, current_t, final_t) result(h_abs_max)
      type(odex_options), intent(in) :: opts
      real(dp), intent(in) :: current_t, final_t

      h_abs_max = abs(final_t - current_t)
      if (opts%dop853_max_step > 0.0_dp) h_abs_max = min(h_abs_max, opts%dop853_max_step)
      h_abs_max = max(h_abs_max, 0.0_dp)
   end function dop853_step_abs_bound

   real(dp) function dop853_clamp_step(h_candidate, opts, current_t, final_t) result(h_limited)
      real(dp), intent(in) :: h_candidate, current_t, final_t
      type(odex_options), intent(in) :: opts
      real(dp) :: h_abs_max

      h_abs_max = dop853_step_abs_bound(opts, current_t, final_t)
      if (h_abs_max <= 0.0_dp) then
         h_limited = 0.0_dp
      else if (h_candidate == 0.0_dp) then
         h_limited = sign(h_abs_max, final_t - current_t)
      else
         h_limited = sign(min(abs(h_candidate), h_abs_max), final_t - current_t)
      end if
   end function dop853_clamp_step

   logical function dop853_stiffness_hit(y_old, y_new, h, workspace, opts, accepted_steps) result(hit)
      real(dp), intent(in) :: y_old(:), y_new(:), h
      type(odex_workspace), intent(in) :: workspace
      type(odex_options), intent(in) :: opts
      integer, intent(in) :: accepted_steps

      integer :: i, n
      real(dp) :: dy_norm, df_norm, dy, df, hlamb

      hit = .false.
      if (.not. opts%dop853_stiffness_check_enabled) return
      if (opts%dop853_stiffness_check_interval > 1) then
         if (mod(max(accepted_steps, 1), opts%dop853_stiffness_check_interval) /= 0) return
      end if
      n = size(y_old)
      if (n <= 0 .or. size(y_new) /= n) return
      dy_norm = 0.0_dp
      df_norm = 0.0_dp
      do i = 1, n
         dy = y_new(i) - y_old(i)
         df = workspace%tableau(12, 1, i) - workspace%tableau(1, 1, i)
         dy_norm = dy_norm + dy*dy
         df_norm = df_norm + df*df
      end do
      dy_norm = sqrt(dy_norm/real(n, dp))
      df_norm = sqrt(df_norm/real(n, dp))
      if (dy_norm <= tiny(1.0_dp)) return
      hlamb = abs(h)*df_norm/dy_norm
      if (.not. ieee_is_finite(hlamb)) then
         hit = .true.
      else
         hit = (hlamb > opts%dop853_stiffness_threshold)
      end if
   end function dop853_stiffness_hit

   real(dp) function dop853_next_accepted_step(h, err, facold, opts) result(h_new)
      real(dp), intent(in) :: h, err, facold
      type(odex_options), intent(in) :: opts
      real(dp) :: expo1, fac, fac11, facc1, facc2

      expo1 = 1.0_dp/8.0_dp - opts%dop853_beta*0.2_dp
      facc1 = 1.0_dp/opts%dop853_fac1
      facc2 = 1.0_dp/opts%dop853_fac2
      fac11 = max(err, tiny(1.0_dp))**expo1
      fac = fac11/max(facold, tiny(1.0_dp))**opts%dop853_beta
      fac = max(facc2, min(facc1, fac/opts%dop853_safety))
      h_new = h/fac
   end function dop853_next_accepted_step

   real(dp) function dop853_next_rejected_step(h, err, opts) result(h_new)
      real(dp), intent(in) :: h, err
      type(odex_options), intent(in) :: opts
      real(dp) :: expo1, fac11, facc1

      expo1 = 1.0_dp/8.0_dp - opts%dop853_beta*0.2_dp
      facc1 = 1.0_dp/opts%dop853_fac1
      fac11 = max(err, 1.0_dp)**expo1
      h_new = h/min(facc1, fac11/opts%dop853_safety)
   end function dop853_next_rejected_step

   logical function dop853_stage_invalid(stage_values) result(invalid)
      real(dp), intent(in) :: stage_values(:)

      invalid = vector_has_invalid(stage_values)
   end function dop853_stage_invalid

   subroutine dop853_record_result(result_state, rhs_evals, step_attempts)
      type(odex_result), intent(inout) :: result_state
      integer, intent(in) :: rhs_evals, step_attempts

      result_state%odex_rhs_evals = max(0, rhs_evals)
      result_state%odex_error_estimates = max(0, step_attempts)
      result_state%odex_large_error_rejects = max(0, result_state%rejected_steps)
      result_state%odex_reject_updates = max(0, result_state%rejected_steps)
   end subroutine dop853_record_result

   subroutine odex_step(f, y, h, k, res, err, workspace, opts, stability_rejected, invalid_rhs, step_stats)
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:)
      real(dp), intent(inout) :: h
      integer, intent(inout) :: k
      real(dp), intent(out) :: res(:), err
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      logical, intent(out) :: stability_rejected, invalid_rhs
      type(odex_step_telemetry), intent(out) :: step_stats

      integer :: i, j, l, n, ni, k_prev
      real(dp) :: dt, scale, errsum, wk1, wk2, wk3, hk0, hk1, hk2, hk3
      real(dp) :: work_values(odex_cache_size), step_values(odex_cache_size)
      real(dp) :: prev_norm, curr_norm
      logical :: hairer_policy

      n = size(y)
      res = y
      stability_rejected = .false.
      invalid_rhs = .false.
      call odex_step_telemetry_reset(step_stats)
      wk1 = 0.0_dp
      wk2 = 0.0_dp
      wk3 = 0.0_dp
      hk0 = h
      hk1 = h
      hk2 = h
      hk3 = h
      work_values = huge(1.0_dp)
      step_values = max(abs(h), tiny(1.0_dp))
      hairer_policy = (opts%controller_policy == odex_controller_policy_hairer_experimental)

      workspace%fbase(1:n) = f(y)
      step_stats%rhs_evals = step_stats%rhs_evals + 1

      if (vector_has_invalid(workspace%fbase(1:n))) then
         invalid_rhs = .true.
         err = huge(1.0_dp)
         res = y
         return
      end if

      do i = 1, k
         ni = workspace%nsteps(i)
         dt = h/real(ni, dp)

         workspace%yprev(1:n) = y
         workspace%ycurr(1:n) = y + dt*workspace%fbase(1:n)
         prev_norm = vector_rms(workspace%fbase(1:n))

         do l = 2, ni
            workspace%fval(1:n) = f(workspace%ycurr(1:n))
            step_stats%rhs_evals = step_stats%rhs_evals + 1
            if (vector_has_invalid(workspace%fval(1:n))) then
               invalid_rhs = .true.
               err = huge(1.0_dp)
               res = y
               return
            end if
            if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
               stability_rejected = .true.
               err = huge(1.0_dp)
               res = y
               h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
               k = max(opts%k_min, k - 1)
               return
            end if
            curr_norm = vector_rms(workspace%fval(1:n))
            workspace%ynext(1:n) = workspace%yprev(1:n) + 2.0_dp*dt*workspace%fval(1:n)
            workspace%yprev(1:n) = workspace%ycurr(1:n)
            workspace%ycurr(1:n) = workspace%ynext(1:n)
            prev_norm = max(prev_norm, curr_norm)
         end do

         workspace%fval(1:n) = f(workspace%ycurr(1:n))
         step_stats%rhs_evals = step_stats%rhs_evals + 1
         if (vector_has_invalid(workspace%fval(1:n))) then
            invalid_rhs = .true.
            err = huge(1.0_dp)
            res = y
            return
         end if
         if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
            stability_rejected = .true.
            err = huge(1.0_dp)
            res = y
            h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
            k = max(opts%k_min, k - 1)
            return
         end if
         workspace%tableau(i, 1, 1:n) = 0.5_dp*(workspace%yprev(1:n) + workspace%ycurr(1:n) + dt*workspace%fval(1:n))
         call odex_step_record_midpoint_row(step_stats, i)
      end do

      do j = 2, k
         do i = j, k
            workspace%tableau(i, j, 1:n) = workspace%tableau(i, j - 1, 1:n) + &
                                           (workspace%tableau(i, j - 1, 1:n) - workspace%tableau(i - 1, j - 1, 1:n))/ &
                                           workspace%ratio(i, i - j + 1)

            if (k > 3 .and. i == k - 1 .and. j == k - 1) then
               errsum = 0.0_dp
               call odex_step_record_error_scale(step_stats, hairer_policy)
               do l = 1, n
                  scale = odex_error_scale(opts, y(l), workspace%tableau(k - 2, k - 2, l), &
                                           workspace%tableau(k - 2, k - 2, l), &
                                           workspace%tableau(k - 2, k - 3, l), hairer_policy)
                  errsum = errsum + ((workspace%tableau(k - 2, k - 2, l) - workspace%tableau(k - 2, k - 3, l))/scale)**2
               end do
               err = sqrt(errsum/real(n, dp))
               wk2 = calculate_wk(h, err, k - 2, workspace, opts)
               hk0 = calculate_hk(h, err, k - 2, workspace, opts)
               call odex_store_hairer_controller_row(work_values, step_values, k - 2, wk2, hk0)

               errsum = 0.0_dp
               call odex_step_record_error_scale(step_stats, hairer_policy)
               do l = 1, n
                  scale = odex_error_scale(opts, y(l), workspace%tableau(k - 1, k - 1, l), &
                                           workspace%tableau(k - 1, k - 1, l), &
                                           workspace%tableau(k - 1, k - 2, l), hairer_policy)
                  errsum = errsum + ((workspace%tableau(k - 1, k - 1, l) - workspace%tableau(k - 1, k - 2, l))/scale)**2
               end do
               err = sqrt(errsum/real(n, dp))
               wk1 = calculate_wk(h, err, k - 1, workspace, opts)
               hk1 = calculate_hk(h, err, k - 1, workspace, opts)
               call odex_store_hairer_controller_row(work_values, step_values, k - 1, wk1, hk1)

               if (err < 1.0_dp) then
                  res = workspace%tableau(k - 1, k - 1, 1:n)
                  step_stats%accept_k_minus_1 = step_stats%accept_k_minus_1 + 1
                  if (hairer_policy) then
                     k_prev = k
                     step_stats%kopt_accept_updates = step_stats%kopt_accept_updates + 1
                     call odex_apply_hairer_accept_update(k_prev, k - 1, wk2, wk2, wk1, hk1, hk1, workspace, opts, k, h)
                     call odex_step_record_kopt_transition(step_stats, k_prev - 1, k)
                  else
                     if (wk1 > opts%order_increase_factor*wk2) then
                        k = max(opts%k_min, k - 1)
                        h = hk1
                     else
                        h = hk1*workspace%ak(k)/workspace%ak(k - 1)
                     end if
                  end if
                  return
               else if (err > odex_convergence_reject_threshold(k, workspace, hairer_policy)) then
                  step_stats%large_error_rejects = step_stats%large_error_rejects + 1
                  step_stats%convergence_rejects = step_stats%convergence_rejects + 1
                  step_stats%reject_kc_k_minus_1 = step_stats%reject_kc_k_minus_1 + 1
                  if (hairer_policy) then
                     step_stats%reject_updates = step_stats%reject_updates + 1
                     call odex_observe_hairer_reject_update(k, k - 1, opts%k_max, work_values, step_values, &
                                                            opts, sign(1.0_dp, h), k, h)
                  else
                     k = max(opts%k_min, k - 1)
                     h = hk1
                  end if
                  res = y
                  return
               end if
            end if
         end do
      end do

      errsum = 0.0_dp
      call odex_step_record_error_scale(step_stats, hairer_policy)
      do i = 1, n
         scale = odex_error_scale(opts, y(i), workspace%tableau(k, k, i), &
                                  workspace%tableau(k, k, i), workspace%tableau(k, k - 1, i), hairer_policy)
         errsum = errsum + ((workspace%tableau(k, k, i) - workspace%tableau(k, k - 1, i))/scale)**2
      end do
      err = sqrt(errsum/real(n, dp))

      hk2 = calculate_hk(h, err, k, workspace, opts)
      wk2 = calculate_wk(h, err, k, workspace, opts)
      call odex_store_hairer_controller_row(work_values, step_values, k, wk2, hk2)
      if (err < 1.0_dp) then
         res = workspace%tableau(k, k, 1:n)
         step_stats%accept_k = step_stats%accept_k + 1
         if (hairer_policy) then
            k_prev = k
            step_stats%kopt_accept_updates = step_stats%kopt_accept_updates + 1
            call odex_apply_hairer_accept_update(k_prev, k, 0.0_dp, wk1, wk2, hk1, hk2, workspace, opts, k, h)
            call odex_step_record_kopt_transition(step_stats, k_prev, k)
         else
            if (wk1 <= opts%order_decrease_factor*wk2) then
               k = max(opts%k_min, k - 1)
               h = hk1
            else if (wk2 <= opts%order_increase_factor*wk1) then
               k_prev = k
               k = min(opts%k_max, k + 1)
               if (k > k_prev) then
                  h = odex_hairer_promotion_step(hk2, k_prev, k, workspace)
               else
                  h = hk2
               end if
            else
               h = hk2
            end if
         end if
         return
      end if

      if (hairer_policy .and. err > odex_kplus1_hope_threshold(k, workspace)) then
         res = y
         step_stats%large_error_rejects = step_stats%large_error_rejects + 1
         step_stats%kplus1_hope_rejects = step_stats%kplus1_hope_rejects + 1
         step_stats%reject_kc_k = step_stats%reject_kc_k + 1
         step_stats%reject_updates = step_stats%reject_updates + 1
         call odex_observe_hairer_reject_update(k, k, opts%k_max, work_values, step_values, &
                                                opts, sign(1.0_dp, h), k, h)
         return
      end if

      step_stats%kplus1_attempts = step_stats%kplus1_attempts + 1
      ni = workspace%nsteps(k + 1)
      dt = h/real(ni, dp)
      workspace%yprev(1:n) = y
      workspace%ycurr(1:n) = y + dt*workspace%fbase(1:n)
      prev_norm = vector_rms(workspace%fbase(1:n))

      do l = 2, ni
         workspace%fval(1:n) = f(workspace%ycurr(1:n))
         step_stats%rhs_evals = step_stats%rhs_evals + 1
         if (vector_has_invalid(workspace%fval(1:n))) then
            invalid_rhs = .true.
            err = huge(1.0_dp)
            res = y
            return
         end if
         if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
            stability_rejected = .true.
            err = huge(1.0_dp)
            res = y
            h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
            k = max(opts%k_min, k - 1)
            return
         end if
         curr_norm = vector_rms(workspace%fval(1:n))
         workspace%ynext(1:n) = workspace%yprev(1:n) + 2.0_dp*dt*workspace%fval(1:n)
         workspace%yprev(1:n) = workspace%ycurr(1:n)
         workspace%ycurr(1:n) = workspace%ynext(1:n)
         prev_norm = max(prev_norm, curr_norm)
      end do

      workspace%fval(1:n) = f(workspace%ycurr(1:n))
      step_stats%rhs_evals = step_stats%rhs_evals + 1
      if (vector_has_invalid(workspace%fval(1:n))) then
         invalid_rhs = .true.
         err = huge(1.0_dp)
         res = y
         return
      end if
      if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
         stability_rejected = .true.
         err = huge(1.0_dp)
         res = y
         h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
         k = max(opts%k_min, k - 1)
         return
      end if
      workspace%tableau(k + 1, 1, 1:n) = 0.5_dp*(workspace%yprev(1:n) + workspace%ycurr(1:n) + dt*workspace%fval(1:n))
      call odex_step_record_midpoint_row(step_stats, k + 1)

      do j = 2, k + 1
         workspace%tableau(k + 1, j, 1:n) = workspace%tableau(k + 1, j - 1, 1:n) + &
                                            (workspace%tableau(k + 1, j - 1, 1:n) - workspace%tableau(k, j - 1, 1:n))/ &
                                            workspace%ratio(k + 1, k - j + 2)
      end do

      errsum = 0.0_dp
      call odex_step_record_error_scale(step_stats, hairer_policy)
      do i = 1, n
         scale = odex_error_scale(opts, y(i), workspace%tableau(k + 1, k + 1, i), &
                                  workspace%tableau(k + 1, k + 1, i), &
                                  workspace%tableau(k + 1, k, i), hairer_policy)
         errsum = errsum + ((workspace%tableau(k + 1, k + 1, i) - workspace%tableau(k + 1, k, i))/scale)**2
      end do
      err = sqrt(errsum/real(n, dp))
      hk3 = calculate_hk(h, err, k + 1, workspace, opts)
      wk3 = calculate_wk(h, err, k + 1, workspace, opts)
      call odex_store_hairer_controller_row(work_values, step_values, k + 1, wk3, hk3)

      if (err < 1.0_dp) then
         res = workspace%tableau(k + 1, k + 1, 1:n)
         step_stats%accept_k_plus_1 = step_stats%accept_k_plus_1 + 1
         if (hairer_policy) then
            k_prev = k
            step_stats%kopt_accept_updates = step_stats%kopt_accept_updates + 1
            call odex_apply_hairer_accept_update(k_prev, k + 1, wk1, wk2, wk3, hk2, hk3, workspace, opts, k, h)
            call odex_step_record_kopt_transition(step_stats, k_prev + 1, k)
         else
            if (wk1 <= opts%order_decrease_factor*wk2) then
               k = max(opts%k_min, k - 1)
               h = hk1
            else if (wk2 <= opts%order_increase_factor*wk1) then
               hk1 = hk3
               k = min(opts%k_max, k + 1)
               h = hk1
            else
               h = hk2
            end if
         end if
      else
         res = y
         step_stats%kplus1_rejects = step_stats%kplus1_rejects + 1
         step_stats%reject_kc_k_plus_1 = step_stats%reject_kc_k_plus_1 + 1
         if (hairer_policy) then
            step_stats%reject_updates = step_stats%reject_updates + 1
            call odex_observe_hairer_reject_update(k, k + 1, opts%k_max, work_values, step_values, &
                                                   opts, sign(1.0_dp, h), k, h)
         else
            k = max(opts%k_min, k - 1)
            h = hk1
         end if
      end if
   end subroutine odex_step

   subroutine odex_step_context(f, y, h, k, res, err, workspace, opts, stability_rejected, invalid_rhs, step_stats, rhs_context)
      procedure(ode_rhs_context) :: f
      real(dp), intent(in) :: y(:)
      real(dp), intent(inout) :: h
      integer, intent(inout) :: k
      real(dp), intent(out) :: res(:), err
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      logical, intent(out) :: stability_rejected, invalid_rhs
      type(odex_step_telemetry), intent(out) :: step_stats
      class(*), intent(inout) :: rhs_context

      integer :: i, j, l, n, ni, k_prev
      real(dp) :: dt, scale, errsum, wk1, wk2, wk3, hk0, hk1, hk2, hk3
      real(dp) :: work_values(odex_cache_size), step_values(odex_cache_size)
      real(dp) :: prev_norm, curr_norm
      logical :: hairer_policy

      n = size(y)
      res = y
      stability_rejected = .false.
      invalid_rhs = .false.
      call odex_step_telemetry_reset(step_stats)
      wk1 = 0.0_dp
      wk2 = 0.0_dp
      wk3 = 0.0_dp
      hk0 = h
      hk1 = h
      hk2 = h
      hk3 = h
      work_values = huge(1.0_dp)
      step_values = max(abs(h), tiny(1.0_dp))
      hairer_policy = (opts%controller_policy == odex_controller_policy_hairer_experimental)

      workspace%fbase(1:n) = f(y, rhs_context)
      step_stats%rhs_evals = step_stats%rhs_evals + 1

      if (vector_has_invalid(workspace%fbase(1:n))) then
         invalid_rhs = .true.
         err = huge(1.0_dp)
         res = y
         return
      end if

      do i = 1, k
         ni = workspace%nsteps(i)
         dt = h/real(ni, dp)

         workspace%yprev(1:n) = y
         workspace%ycurr(1:n) = y + dt*workspace%fbase(1:n)
         prev_norm = vector_rms(workspace%fbase(1:n))

         do l = 2, ni
            workspace%fval(1:n) = f(workspace%ycurr(1:n), rhs_context)
            step_stats%rhs_evals = step_stats%rhs_evals + 1
            if (vector_has_invalid(workspace%fval(1:n))) then
               invalid_rhs = .true.
               err = huge(1.0_dp)
               res = y
               return
            end if
            if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
               stability_rejected = .true.
               err = huge(1.0_dp)
               res = y
               h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
               k = max(opts%k_min, k - 1)
               return
            end if
            curr_norm = vector_rms(workspace%fval(1:n))
            workspace%ynext(1:n) = workspace%yprev(1:n) + 2.0_dp*dt*workspace%fval(1:n)
            workspace%yprev(1:n) = workspace%ycurr(1:n)
            workspace%ycurr(1:n) = workspace%ynext(1:n)
            prev_norm = max(prev_norm, curr_norm)
         end do

         workspace%fval(1:n) = f(workspace%ycurr(1:n), rhs_context)
         step_stats%rhs_evals = step_stats%rhs_evals + 1
         if (vector_has_invalid(workspace%fval(1:n))) then
            invalid_rhs = .true.
            err = huge(1.0_dp)
            res = y
            return
         end if
         if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
            stability_rejected = .true.
            err = huge(1.0_dp)
            res = y
            h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
            k = max(opts%k_min, k - 1)
            return
         end if
         workspace%tableau(i, 1, 1:n) = 0.5_dp*(workspace%yprev(1:n) + workspace%ycurr(1:n) + dt*workspace%fval(1:n))
         call odex_step_record_midpoint_row(step_stats, i)
      end do

      do j = 2, k
         do i = j, k
            workspace%tableau(i, j, 1:n) = workspace%tableau(i, j - 1, 1:n) + &
                                           (workspace%tableau(i, j - 1, 1:n) - workspace%tableau(i - 1, j - 1, 1:n))/ &
                                           workspace%ratio(i, i - j + 1)

            if (k > 3 .and. i == k - 1 .and. j == k - 1) then
               errsum = 0.0_dp
               call odex_step_record_error_scale(step_stats, hairer_policy)
               do l = 1, n
                  scale = odex_error_scale(opts, y(l), workspace%tableau(k - 2, k - 2, l), &
                                           workspace%tableau(k - 2, k - 2, l), &
                                           workspace%tableau(k - 2, k - 3, l), hairer_policy)
                  errsum = errsum + ((workspace%tableau(k - 2, k - 2, l) - workspace%tableau(k - 2, k - 3, l))/scale)**2
               end do
               err = sqrt(errsum/real(n, dp))
               wk2 = calculate_wk(h, err, k - 2, workspace, opts)
               hk0 = calculate_hk(h, err, k - 2, workspace, opts)
               call odex_store_hairer_controller_row(work_values, step_values, k - 2, wk2, hk0)

               errsum = 0.0_dp
               call odex_step_record_error_scale(step_stats, hairer_policy)
               do l = 1, n
                  scale = odex_error_scale(opts, y(l), workspace%tableau(k - 1, k - 1, l), &
                                           workspace%tableau(k - 1, k - 1, l), &
                                           workspace%tableau(k - 1, k - 2, l), hairer_policy)
                  errsum = errsum + ((workspace%tableau(k - 1, k - 1, l) - workspace%tableau(k - 1, k - 2, l))/scale)**2
               end do
               err = sqrt(errsum/real(n, dp))
               wk1 = calculate_wk(h, err, k - 1, workspace, opts)
               hk1 = calculate_hk(h, err, k - 1, workspace, opts)
               call odex_store_hairer_controller_row(work_values, step_values, k - 1, wk1, hk1)

               if (err < 1.0_dp) then
                  res = workspace%tableau(k - 1, k - 1, 1:n)
                  step_stats%accept_k_minus_1 = step_stats%accept_k_minus_1 + 1
                  if (hairer_policy) then
                     k_prev = k
                     step_stats%kopt_accept_updates = step_stats%kopt_accept_updates + 1
                     call odex_apply_hairer_accept_update(k_prev, k - 1, wk2, wk2, wk1, hk1, hk1, workspace, opts, k, h)
                     call odex_step_record_kopt_transition(step_stats, k_prev - 1, k)
                  else
                     if (wk1 > opts%order_increase_factor*wk2) then
                        k = max(opts%k_min, k - 1)
                        h = hk1
                     else
                        h = hk1*workspace%ak(k)/workspace%ak(k - 1)
                     end if
                  end if
                  return
               else if (err > odex_convergence_reject_threshold(k, workspace, hairer_policy)) then
                  step_stats%large_error_rejects = step_stats%large_error_rejects + 1
                  step_stats%convergence_rejects = step_stats%convergence_rejects + 1
                  step_stats%reject_kc_k_minus_1 = step_stats%reject_kc_k_minus_1 + 1
                  if (hairer_policy) then
                     step_stats%reject_updates = step_stats%reject_updates + 1
                     call odex_observe_hairer_reject_update(k, k - 1, opts%k_max, work_values, step_values, &
                                                            opts, sign(1.0_dp, h), k, h)
                  else
                     k = max(opts%k_min, k - 1)
                     h = hk1
                  end if
                  res = y
                  return
               end if
            end if
         end do
      end do

      errsum = 0.0_dp
      call odex_step_record_error_scale(step_stats, hairer_policy)
      do i = 1, n
         scale = odex_error_scale(opts, y(i), workspace%tableau(k, k, i), &
                                  workspace%tableau(k, k, i), workspace%tableau(k, k - 1, i), hairer_policy)
         errsum = errsum + ((workspace%tableau(k, k, i) - workspace%tableau(k, k - 1, i))/scale)**2
      end do
      err = sqrt(errsum/real(n, dp))

      hk2 = calculate_hk(h, err, k, workspace, opts)
      wk2 = calculate_wk(h, err, k, workspace, opts)
      call odex_store_hairer_controller_row(work_values, step_values, k, wk2, hk2)
      if (err < 1.0_dp) then
         res = workspace%tableau(k, k, 1:n)
         step_stats%accept_k = step_stats%accept_k + 1
         if (hairer_policy) then
            k_prev = k
            step_stats%kopt_accept_updates = step_stats%kopt_accept_updates + 1
            call odex_apply_hairer_accept_update(k_prev, k, 0.0_dp, wk1, wk2, hk1, hk2, workspace, opts, k, h)
            call odex_step_record_kopt_transition(step_stats, k_prev, k)
         else
            if (wk1 <= opts%order_decrease_factor*wk2) then
               k = max(opts%k_min, k - 1)
               h = hk1
            else if (wk2 <= opts%order_increase_factor*wk1) then
               k_prev = k
               k = min(opts%k_max, k + 1)
               if (k > k_prev) then
                  h = odex_hairer_promotion_step(hk2, k_prev, k, workspace)
               else
                  h = hk2
               end if
            else
               h = hk2
            end if
         end if
         return
      end if

      if (hairer_policy .and. err > odex_kplus1_hope_threshold(k, workspace)) then
         res = y
         step_stats%large_error_rejects = step_stats%large_error_rejects + 1
         step_stats%kplus1_hope_rejects = step_stats%kplus1_hope_rejects + 1
         step_stats%reject_kc_k = step_stats%reject_kc_k + 1
         step_stats%reject_updates = step_stats%reject_updates + 1
         call odex_observe_hairer_reject_update(k, k, opts%k_max, work_values, step_values, &
                                                opts, sign(1.0_dp, h), k, h)
         return
      end if

      step_stats%kplus1_attempts = step_stats%kplus1_attempts + 1
      ni = workspace%nsteps(k + 1)
      dt = h/real(ni, dp)
      workspace%yprev(1:n) = y
      workspace%ycurr(1:n) = y + dt*workspace%fbase(1:n)
      prev_norm = vector_rms(workspace%fbase(1:n))

      do l = 2, ni
         workspace%fval(1:n) = f(workspace%ycurr(1:n), rhs_context)
         step_stats%rhs_evals = step_stats%rhs_evals + 1
         if (vector_has_invalid(workspace%fval(1:n))) then
            invalid_rhs = .true.
            err = huge(1.0_dp)
            res = y
            return
         end if
         if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
            stability_rejected = .true.
            err = huge(1.0_dp)
            res = y
            h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
            k = max(opts%k_min, k - 1)
            return
         end if
         curr_norm = vector_rms(workspace%fval(1:n))
         workspace%ynext(1:n) = workspace%yprev(1:n) + 2.0_dp*dt*workspace%fval(1:n)
         workspace%yprev(1:n) = workspace%ycurr(1:n)
         workspace%ycurr(1:n) = workspace%ynext(1:n)
         prev_norm = max(prev_norm, curr_norm)
      end do

      workspace%fval(1:n) = f(workspace%ycurr(1:n), rhs_context)
      step_stats%rhs_evals = step_stats%rhs_evals + 1
      if (vector_has_invalid(workspace%fval(1:n))) then
         invalid_rhs = .true.
         err = huge(1.0_dp)
         res = y
         return
      end if
      if (odex_stability_reject(workspace%fval(1:n), prev_norm, dt, opts)) then
         stability_rejected = .true.
         err = huge(1.0_dp)
         res = y
         h = sign(max(abs(h)*0.5_dp, 1.0e-16_dp), h)
         k = max(opts%k_min, k - 1)
         return
      end if
      workspace%tableau(k + 1, 1, 1:n) = 0.5_dp*(workspace%yprev(1:n) + workspace%ycurr(1:n) + dt*workspace%fval(1:n))
      call odex_step_record_midpoint_row(step_stats, k + 1)

      do j = 2, k + 1
         workspace%tableau(k + 1, j, 1:n) = workspace%tableau(k + 1, j - 1, 1:n) + &
                                            (workspace%tableau(k + 1, j - 1, 1:n) - workspace%tableau(k, j - 1, 1:n))/ &
                                            workspace%ratio(k + 1, k - j + 2)
      end do

      errsum = 0.0_dp
      call odex_step_record_error_scale(step_stats, hairer_policy)
      do i = 1, n
         scale = odex_error_scale(opts, y(i), workspace%tableau(k + 1, k + 1, i), &
                                  workspace%tableau(k + 1, k + 1, i), &
                                  workspace%tableau(k + 1, k, i), hairer_policy)
         errsum = errsum + ((workspace%tableau(k + 1, k + 1, i) - workspace%tableau(k + 1, k, i))/scale)**2
      end do
      err = sqrt(errsum/real(n, dp))
      hk3 = calculate_hk(h, err, k + 1, workspace, opts)
      wk3 = calculate_wk(h, err, k + 1, workspace, opts)
      call odex_store_hairer_controller_row(work_values, step_values, k + 1, wk3, hk3)

      if (err < 1.0_dp) then
         res = workspace%tableau(k + 1, k + 1, 1:n)
         step_stats%accept_k_plus_1 = step_stats%accept_k_plus_1 + 1
         if (hairer_policy) then
            k_prev = k
            step_stats%kopt_accept_updates = step_stats%kopt_accept_updates + 1
            call odex_apply_hairer_accept_update(k_prev, k + 1, wk1, wk2, wk3, hk2, hk3, workspace, opts, k, h)
            call odex_step_record_kopt_transition(step_stats, k_prev + 1, k)
         else
            if (wk1 <= opts%order_decrease_factor*wk2) then
               k = max(opts%k_min, k - 1)
               h = hk1
            else if (wk2 <= opts%order_increase_factor*wk1) then
               hk1 = hk3
               k = min(opts%k_max, k + 1)
               h = hk1
            else
               h = hk2
            end if
         end if
      else
         res = y
         step_stats%kplus1_rejects = step_stats%kplus1_rejects + 1
         step_stats%reject_kc_k_plus_1 = step_stats%reject_kc_k_plus_1 + 1
         if (hairer_policy) then
            step_stats%reject_updates = step_stats%reject_updates + 1
            call odex_observe_hairer_reject_update(k, k + 1, opts%k_max, work_values, step_values, &
                                                   opts, sign(1.0_dp, h), k, h)
         else
            k = max(opts%k_min, k - 1)
            h = hk1
         end if
      end if
   end subroutine odex_step_context

   subroutine odex_step_hairer_controller(f, y, controller_phase, controller_state, res, err, workspace, opts, &
                                          stability_rejected, invalid_rhs, step_stats)
      procedure(ode_rhs) :: f
      real(dp), intent(in) :: y(:)
      integer, intent(in) :: controller_phase
      type(odex_hairer_controller_state), intent(inout) :: controller_state
      real(dp), intent(out) :: res(:), err
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      logical, intent(out) :: stability_rejected, invalid_rhs
      type(odex_step_telemetry), intent(out) :: step_stats

      integer :: accepted_row, k_reference, n, next_row, rejected_row
      logical :: was_rejected
      type(odex_hairer_controller_decision) :: decision, update_decision
      type(odex_hairer_row_lifecycle) :: row_lifecycle
      type(odex_row_result) :: row_state

      n = size(y)
      res = y
      err = huge(1.0_dp)
      stability_rejected = .false.
      invalid_rhs = .false.
      call odex_step_telemetry_reset(step_stats)

      if (.not. controller_state%initialized .or. n <= 0) then
         invalid_rhs = .true.
         return
      end if

      workspace%fbase(1:n) = f(y)
      step_stats%rhs_evals = step_stats%rhs_evals + 1
      if (vector_has_invalid(workspace%fbase(1:n))) then
         invalid_rhs = .true.
         return
      end if

      call odex_observe_hairer_row_lifecycle_begin(y, opts, controller_state%km, row_lifecycle)
      if (.not. row_lifecycle%initialized) then
         invalid_rhs = .true.
         return
      end if

      next_row = 1
      do
         if (next_row < 1 .or. next_row > row_lifecycle%max_rows) then
            invalid_rhs = .true.
            return
         end if
         if (next_row == controller_state%k + 1) step_stats%kplus1_attempts = step_stats%kplus1_attempts + 1

         call odex_observe_hairer_midex_lifecycle_row(f, next_row, y, controller_state%h, &
                                                      controller_state%hmax_abs, workspace%fbase(1:n), workspace, &
                                                      opts, row_lifecycle, row_state)
         call odex_step_record_hairer_row(step_stats, row_state)
         if (row_state%invalid_rhs .or. row_state%stability_rejected) then
            invalid_rhs = row_state%invalid_rhs
            stability_rejected = row_state%stability_rejected
            return
         end if

         call odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                        opts, controller_phase, decision)
         select case (decision%action)
         case (odex_hairer_controller_action_continue)
            if (decision%next_row <= next_row) then
               invalid_rhs = .true.
               return
            end if
            next_row = decision%next_row
         case (odex_hairer_controller_action_accept)
            accepted_row = decision%accepted_row
            if (accepted_row < 1 .or. accepted_row > row_lifecycle%max_rows) then
               invalid_rhs = .true.
               return
            end if
            k_reference = controller_state%k
            was_rejected = controller_state%rejected
            res = workspace%tableau(accepted_row, accepted_row, 1:n)
            err = max(0.0_dp, row_state%err)
            call odex_step_record_hairer_accept(step_stats, accepted_row, k_reference)
            call odex_observe_hairer_controller_accept_update(controller_state, row_lifecycle, workspace, opts, &
                                                              update_decision)
            if (update_decision%action == odex_hairer_controller_action_invalid) then
               invalid_rhs = .true.
               return
            end if
            step_stats%kopt_accept_updates = step_stats%kopt_accept_updates + 1
            call odex_step_record_kopt_transition(step_stats, accepted_row, controller_state%k)
            if (was_rejected) step_stats%after_reject_clamps = step_stats%after_reject_clamps + 1
            return
         case (odex_hairer_controller_action_reject)
            rejected_row = decision%rejected_row
            if (rejected_row <= 0) rejected_row = row_state%row_index
            call odex_step_record_hairer_reject(step_stats, rejected_row, controller_state%k)
            res = y
            err = max(row_state%err, 1.0_dp)
            return
         case (odex_hairer_controller_action_retry)
            res = y
            err = huge(1.0_dp)
            return
         case default
            invalid_rhs = .true.
            return
         end select
      end do
   end subroutine odex_step_hairer_controller

   subroutine odex_step_hairer_controller_context(f, y, controller_phase, controller_state, res, err, workspace, opts, &
                                                  stability_rejected, invalid_rhs, step_stats, rhs_context)
      procedure(ode_rhs_context) :: f
      real(dp), intent(in) :: y(:)
      integer, intent(in) :: controller_phase
      type(odex_hairer_controller_state), intent(inout) :: controller_state
      real(dp), intent(out) :: res(:), err
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: opts
      logical, intent(out) :: stability_rejected, invalid_rhs
      type(odex_step_telemetry), intent(out) :: step_stats
      class(*), intent(inout) :: rhs_context

      integer :: accepted_row, k_reference, n, next_row, rejected_row
      logical :: was_rejected
      type(odex_hairer_controller_decision) :: decision, update_decision
      type(odex_hairer_row_lifecycle) :: row_lifecycle
      type(odex_row_result) :: row_state

      n = size(y)
      res = y
      err = huge(1.0_dp)
      stability_rejected = .false.
      invalid_rhs = .false.
      call odex_step_telemetry_reset(step_stats)

      if (.not. controller_state%initialized .or. n <= 0) then
         invalid_rhs = .true.
         return
      end if

      workspace%fbase(1:n) = f(y, rhs_context)
      step_stats%rhs_evals = step_stats%rhs_evals + 1
      if (vector_has_invalid(workspace%fbase(1:n))) then
         invalid_rhs = .true.
         return
      end if

      call odex_observe_hairer_row_lifecycle_begin(y, opts, controller_state%km, row_lifecycle)
      if (.not. row_lifecycle%initialized) then
         invalid_rhs = .true.
         return
      end if

      next_row = 1
      do
         if (next_row < 1 .or. next_row > row_lifecycle%max_rows) then
            invalid_rhs = .true.
            return
         end if
         if (next_row == controller_state%k + 1) step_stats%kplus1_attempts = step_stats%kplus1_attempts + 1

         call odex_observe_hairer_midex_lifecycle_row_context(f, next_row, y, controller_state%h, &
                                                              controller_state%hmax_abs, workspace%fbase(1:n), &
                                                              workspace, opts, row_lifecycle, row_state, rhs_context)
         call odex_step_record_hairer_row(step_stats, row_state)
         if (row_state%invalid_rhs .or. row_state%stability_rejected) then
            invalid_rhs = row_state%invalid_rhs
            stability_rejected = row_state%stability_rejected
            return
         end if

         call odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                        opts, controller_phase, decision)
         select case (decision%action)
         case (odex_hairer_controller_action_continue)
            if (decision%next_row <= next_row) then
               invalid_rhs = .true.
               return
            end if
            next_row = decision%next_row
         case (odex_hairer_controller_action_accept)
            accepted_row = decision%accepted_row
            if (accepted_row < 1 .or. accepted_row > row_lifecycle%max_rows) then
               invalid_rhs = .true.
               return
            end if
            k_reference = controller_state%k
            was_rejected = controller_state%rejected
            res = workspace%tableau(accepted_row, accepted_row, 1:n)
            err = max(0.0_dp, row_state%err)
            call odex_step_record_hairer_accept(step_stats, accepted_row, k_reference)
            call odex_observe_hairer_controller_accept_update(controller_state, row_lifecycle, workspace, opts, &
                                                              update_decision)
            if (update_decision%action == odex_hairer_controller_action_invalid) then
               invalid_rhs = .true.
               return
            end if
            step_stats%kopt_accept_updates = step_stats%kopt_accept_updates + 1
            call odex_step_record_kopt_transition(step_stats, accepted_row, controller_state%k)
            if (was_rejected) step_stats%after_reject_clamps = step_stats%after_reject_clamps + 1
            return
         case (odex_hairer_controller_action_reject)
            rejected_row = decision%rejected_row
            if (rejected_row <= 0) rejected_row = row_state%row_index
            call odex_step_record_hairer_reject(step_stats, rejected_row, controller_state%k)
            res = y
            err = max(row_state%err, 1.0_dp)
            return
         case (odex_hairer_controller_action_retry)
            res = y
            err = huge(1.0_dp)
            return
         case default
            invalid_rhs = .true.
            return
         end select
      end do
   end subroutine odex_step_hairer_controller_context

   subroutine odex_observe_hairer_midex_row_context(f, row_index, y, h, hmax_abs, fbase, scal, errold, workspace, &
                                                    options, row_state, rhs_context)
      procedure(ode_rhs_context) :: f
      integer, intent(in) :: row_index
      real(dp), intent(in) :: y(:), hmax_abs, fbase(:)
      real(dp), intent(inout) :: h
      real(dp), intent(inout) :: scal(:), errold
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: options
      type(odex_row_result), intent(out) :: row_state
      class(*), intent(inout) :: rhs_context

      type(odex_options) :: opts
      integer :: col, idx, mm, n, ni
      real(dp) :: dt, errsum, hmax_safe, scale

      call odex_row_result_reset(row_state)
      row_state%row_index = row_index
      row_state%h_after = h
      row_state%errold_after = errold

      n = size(y)
      if (row_index < 1 .or. n <= 0 .or. size(fbase) < n .or. size(scal) < n) then
         row_state%invalid_rhs = .true.
         return
      end if
      if (vector_has_invalid(y) .or. vector_has_invalid(fbase(1:n)) .or. .not. ieee_is_finite(h)) then
         row_state%invalid_rhs = .true.
         return
      end if

      opts = options
      call odex_normalize_options(opts)
      call ensure_odex_workspace_object(workspace, row_index, n)

      ni = workspace%nsteps(row_index)
      dt = h/real(ni, dp)
      workspace%yprev(1:n) = y(1:n)
      workspace%ycurr(1:n) = y(1:n) + dt*fbase(1:n)

      do mm = 1, ni - 1
         workspace%fval(1:n) = f(workspace%ycurr(1:n), rhs_context)
         row_state%rhs_evals = row_state%rhs_evals + 1
         if (vector_has_invalid(workspace%fval(1:n))) then
            row_state%invalid_rhs = .true.
            return
         end if
         workspace%ynext(1:n) = workspace%yprev(1:n) + 2.0_dp*dt*workspace%fval(1:n)
         workspace%yprev(1:n) = workspace%ycurr(1:n)
         workspace%ycurr(1:n) = workspace%ynext(1:n)
      end do

      workspace%fval(1:n) = f(workspace%ycurr(1:n), rhs_context)
      row_state%rhs_evals = row_state%rhs_evals + 1
      if (vector_has_invalid(workspace%fval(1:n))) then
         row_state%invalid_rhs = .true.
         return
      end if

      workspace%tableau(row_index, 1, 1:n) = &
         0.5_dp*(workspace%yprev(1:n) + workspace%ycurr(1:n) + dt*workspace%fval(1:n))

      if (row_index == 1) then
         row_state%h_after = h
         row_state%errold_after = errold
         return
      end if

      do col = 2, row_index
         workspace%tableau(row_index, col, 1:n) = workspace%tableau(row_index, col - 1, 1:n) + &
            (workspace%tableau(row_index, col - 1, 1:n) - workspace%tableau(row_index - 1, col - 1, 1:n))/ &
            workspace%ratio(row_index, row_index - col + 1)
      end do

      errsum = 0.0_dp
      do idx = 1, n
         scal(idx) = opts%abs_tol + opts%rel_tol*max(abs(y(idx)), abs(workspace%tableau(row_index, row_index, idx)))
         scale = max(scal(idx), tiny(1.0_dp))
         errsum = errsum + &
            ((workspace%tableau(row_index, row_index, idx) - workspace%tableau(row_index, row_index - 1, idx))/scale)**2
      end do
      row_state%err = sqrt(errsum/real(n, dp))
      row_state%err_available = .true.

      if (row_state%err*epsilon(1.0_dp) >= 1.0_dp .or. (row_index > 2 .and. row_state%err >= errold)) then
         row_state%atov = .true.
         h = h*0.5_dp
         row_state%h_after = h
         row_state%errold_after = errold
         return
      end if

      errold = max(4.0_dp*row_state%err, 1.0_dp)
      row_state%errold_after = errold
      hmax_safe = abs(hmax_abs)
      if (hmax_safe <= 0.0_dp) hmax_safe = huge(1.0_dp)
      row_state%hh = min(abs(h)*odex_step_scale(row_state%err, row_index, workspace, opts), hmax_safe)
      if (row_state%hh <= tiny(1.0_dp) .or. .not. ieee_is_finite(row_state%hh)) then
         row_state%work = huge(1.0_dp)
      else
         row_state%work = workspace%ak(row_index)/row_state%hh
      end if
      row_state%h_after = h
   end subroutine odex_observe_hairer_midex_row_context

   subroutine odex_observe_hairer_midex_lifecycle_row_context(f, row_index, y, h, hmax_abs, fbase, workspace, &
                                                              options, row_lifecycle, row_state, rhs_context)
      procedure(ode_rhs_context) :: f
      integer, intent(in) :: row_index
      real(dp), intent(in) :: y(:), hmax_abs, fbase(:)
      real(dp), intent(inout) :: h
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: options
      type(odex_hairer_row_lifecycle), intent(inout) :: row_lifecycle
      type(odex_row_result), intent(out) :: row_state
      class(*), intent(inout) :: rhs_context

      call odex_row_result_reset(row_state)
      row_state%row_index = row_index
      row_state%h_after = h
      row_state%errold_after = row_lifecycle%errold

      if (.not. row_lifecycle%initialized) then
         row_state%invalid_rhs = .true.
         return
      end if
      if (row_index < 1 .or. row_index > row_lifecycle%max_rows) then
         row_state%invalid_rhs = .true.
         return
      end if
      if (size(y) /= row_lifecycle%dimension) then
         row_state%invalid_rhs = .true.
         return
      end if

      call odex_observe_hairer_midex_row_context(f, row_index, y, h, hmax_abs, fbase, row_lifecycle%scal, &
                                                 row_lifecycle%errold, workspace, options, row_state, rhs_context)

      row_lifecycle%rows_attempted = row_lifecycle%rows_attempted + 1
      row_lifecycle%rhs_evals = row_lifecycle%rhs_evals + max(0, row_state%rhs_evals)
      row_lifecycle%last_row = row_index
      row_lifecycle%h_after = h
      row_lifecycle%atov = row_state%atov
      if (row_state%err_available) row_lifecycle%error_rows = row_lifecycle%error_rows + 1
      if (row_state%atov) row_lifecycle%atov_events = row_lifecycle%atov_events + 1

      if (row_state%err_available .and. (.not. row_state%atov) .and. (.not. row_state%invalid_rhs)) then
         row_lifecycle%hh(row_index) = row_state%hh
         row_lifecycle%work(row_index) = row_state%work
      end if
   end subroutine odex_observe_hairer_midex_lifecycle_row_context

   subroutine odex_step_record_hairer_row(step_stats, row_state)
      type(odex_step_telemetry), intent(inout) :: step_stats
      type(odex_row_result), intent(in) :: row_state

      step_stats%rhs_evals = step_stats%rhs_evals + max(0, row_state%rhs_evals)
      if (row_state%invalid_rhs .or. row_state%stability_rejected) return

      call odex_step_record_midpoint_row(step_stats, row_state%row_index)
      if (row_state%err_available) then
         call odex_step_record_error_scale(step_stats, .true.)
         step_stats%errold_checks = step_stats%errold_checks + 1
      end if
      if (row_state%atov) step_stats%atov_events = step_stats%atov_events + 1
   end subroutine odex_step_record_hairer_row

   subroutine odex_step_record_hairer_accept(step_stats, accepted_row, k_reference)
      type(odex_step_telemetry), intent(inout) :: step_stats
      integer, intent(in) :: accepted_row, k_reference

      if (accepted_row < k_reference) then
         step_stats%accept_k_minus_1 = step_stats%accept_k_minus_1 + 1
      else if (accepted_row == k_reference) then
         step_stats%accept_k = step_stats%accept_k + 1
      else
         step_stats%accept_k_plus_1 = step_stats%accept_k_plus_1 + 1
      end if
   end subroutine odex_step_record_hairer_accept

   subroutine odex_step_record_hairer_reject(step_stats, rejected_row, k_reference)
      type(odex_step_telemetry), intent(inout) :: step_stats
      integer, intent(in) :: rejected_row, k_reference

      step_stats%large_error_rejects = step_stats%large_error_rejects + 1
      step_stats%reject_updates = step_stats%reject_updates + 1
      if (rejected_row < k_reference) then
         step_stats%convergence_rejects = step_stats%convergence_rejects + 1
         step_stats%reject_kc_k_minus_1 = step_stats%reject_kc_k_minus_1 + 1
      else if (rejected_row == k_reference) then
         step_stats%kplus1_hope_rejects = step_stats%kplus1_hope_rejects + 1
         step_stats%reject_kc_k = step_stats%reject_kc_k + 1
      else
         step_stats%kplus1_rejects = step_stats%kplus1_rejects + 1
         step_stats%reject_kc_k_plus_1 = step_stats%reject_kc_k_plus_1 + 1
      end if
   end subroutine odex_step_record_hairer_reject

   subroutine odex_observe_hairer_midex_row(f, row_index, y, h, hmax_abs, fbase, scal, errold, workspace, options, row_state)
      procedure(ode_rhs) :: f
      integer, intent(in) :: row_index
      real(dp), intent(in) :: y(:), hmax_abs, fbase(:)
      real(dp), intent(inout) :: h
      real(dp), intent(inout) :: scal(:), errold
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: options
      type(odex_row_result), intent(out) :: row_state

      type(odex_options) :: opts
      integer :: col, idx, mm, n, ni
      real(dp) :: dt, errsum, hmax_safe, scale

      call odex_row_result_reset(row_state)
      row_state%row_index = row_index
      row_state%h_after = h
      row_state%errold_after = errold

      n = size(y)
      if (row_index < 1 .or. n <= 0 .or. size(fbase) < n .or. size(scal) < n) then
         row_state%invalid_rhs = .true.
         return
      end if
      if (vector_has_invalid(y) .or. vector_has_invalid(fbase(1:n)) .or. .not. ieee_is_finite(h)) then
         row_state%invalid_rhs = .true.
         return
      end if

      opts = options
      call odex_normalize_options(opts)
      call ensure_odex_workspace_object(workspace, row_index, n)

      ni = workspace%nsteps(row_index)
      dt = h/real(ni, dp)
      workspace%yprev(1:n) = y(1:n)
      workspace%ycurr(1:n) = y(1:n) + dt*fbase(1:n)

      do mm = 1, ni - 1
         workspace%fval(1:n) = f(workspace%ycurr(1:n))
         row_state%rhs_evals = row_state%rhs_evals + 1
         if (vector_has_invalid(workspace%fval(1:n))) then
            row_state%invalid_rhs = .true.
            return
         end if
         workspace%ynext(1:n) = workspace%yprev(1:n) + 2.0_dp*dt*workspace%fval(1:n)
         workspace%yprev(1:n) = workspace%ycurr(1:n)
         workspace%ycurr(1:n) = workspace%ynext(1:n)
      end do

      workspace%fval(1:n) = f(workspace%ycurr(1:n))
      row_state%rhs_evals = row_state%rhs_evals + 1
      if (vector_has_invalid(workspace%fval(1:n))) then
         row_state%invalid_rhs = .true.
         return
      end if

      workspace%tableau(row_index, 1, 1:n) = &
         0.5_dp*(workspace%yprev(1:n) + workspace%ycurr(1:n) + dt*workspace%fval(1:n))

      if (row_index == 1) then
         row_state%h_after = h
         row_state%errold_after = errold
         return
      end if

      do col = 2, row_index
         workspace%tableau(row_index, col, 1:n) = workspace%tableau(row_index, col - 1, 1:n) + &
            (workspace%tableau(row_index, col - 1, 1:n) - workspace%tableau(row_index - 1, col - 1, 1:n))/ &
            workspace%ratio(row_index, row_index - col + 1)
      end do

      errsum = 0.0_dp
      do idx = 1, n
         scal(idx) = opts%abs_tol + opts%rel_tol*max(abs(y(idx)), abs(workspace%tableau(row_index, row_index, idx)))
         scale = max(scal(idx), tiny(1.0_dp))
         errsum = errsum + &
            ((workspace%tableau(row_index, row_index, idx) - workspace%tableau(row_index, row_index - 1, idx))/scale)**2
      end do
      row_state%err = sqrt(errsum/real(n, dp))
      row_state%err_available = .true.

      if (row_state%err*epsilon(1.0_dp) >= 1.0_dp .or. (row_index > 2 .and. row_state%err >= errold)) then
         row_state%atov = .true.
         h = h*0.5_dp
         row_state%h_after = h
         row_state%errold_after = errold
         return
      end if

      errold = max(4.0_dp*row_state%err, 1.0_dp)
      row_state%errold_after = errold
      hmax_safe = abs(hmax_abs)
      if (hmax_safe <= 0.0_dp) hmax_safe = huge(1.0_dp)
      row_state%hh = min(abs(h)*odex_step_scale(row_state%err, row_index, workspace, opts), hmax_safe)
      if (row_state%hh <= tiny(1.0_dp) .or. .not. ieee_is_finite(row_state%hh)) then
         row_state%work = huge(1.0_dp)
      else
         row_state%work = workspace%ak(row_index)/row_state%hh
      end if
      row_state%h_after = h
   end subroutine odex_observe_hairer_midex_row

   subroutine odex_row_result_reset(row_state)
      type(odex_row_result), intent(out) :: row_state

      row_state%row_index = 0
      row_state%rhs_evals = 0
      row_state%err_available = .false.
      row_state%atov = .false.
      row_state%invalid_rhs = .false.
      row_state%stability_rejected = .false.
      row_state%err = 0.0_dp
      row_state%hh = 0.0_dp
      row_state%work = huge(1.0_dp)
      row_state%h_after = 0.0_dp
      row_state%errold_after = 0.0_dp
   end subroutine odex_row_result_reset

   subroutine odex_hairer_row_lifecycle_reset(row_lifecycle)
      type(odex_hairer_row_lifecycle), intent(inout) :: row_lifecycle

      if (allocated(row_lifecycle%scal)) deallocate(row_lifecycle%scal)
      if (allocated(row_lifecycle%hh)) deallocate(row_lifecycle%hh)
      if (allocated(row_lifecycle%work)) deallocate(row_lifecycle%work)

      row_lifecycle%initialized = .false.
      row_lifecycle%dimension = 0
      row_lifecycle%max_rows = 0
      row_lifecycle%rows_attempted = 0
      row_lifecycle%error_rows = 0
      row_lifecycle%atov_events = 0
      row_lifecycle%rhs_evals = 0
      row_lifecycle%last_row = 0
      row_lifecycle%errold = odex_hairer_errold_initial
      row_lifecycle%h_after = 0.0_dp
      row_lifecycle%atov = .false.
   end subroutine odex_hairer_row_lifecycle_reset

   subroutine odex_observe_hairer_row_lifecycle_begin(y, options, max_rows, row_lifecycle)
      real(dp), intent(in) :: y(:)
      type(odex_options), intent(in) :: options
      integer, intent(in) :: max_rows
      type(odex_hairer_row_lifecycle), intent(inout) :: row_lifecycle

      type(odex_options) :: opts
      integer :: n, row_count

      call odex_hairer_row_lifecycle_reset(row_lifecycle)

      n = size(y)
      if (n <= 0 .or. max_rows <= 0) return
      if (vector_has_invalid(y)) return

      opts = options
      call odex_normalize_options(opts)

      row_count = max(1, max_rows)
      allocate (row_lifecycle%scal(n), row_lifecycle%hh(row_count), row_lifecycle%work(row_count))
      row_lifecycle%scal(1:n) = opts%abs_tol + opts%rel_tol*abs(y(1:n))
      row_lifecycle%hh = 0.0_dp
      row_lifecycle%work = huge(1.0_dp)
      row_lifecycle%errold = odex_hairer_errold_initial
      row_lifecycle%dimension = n
      row_lifecycle%max_rows = row_count
      row_lifecycle%initialized = .true.
   end subroutine odex_observe_hairer_row_lifecycle_begin

   subroutine odex_observe_hairer_midex_lifecycle_row(f, row_index, y, h, hmax_abs, fbase, workspace, &
                                                      options, row_lifecycle, row_state)
      procedure(ode_rhs) :: f
      integer, intent(in) :: row_index
      real(dp), intent(in) :: y(:), hmax_abs, fbase(:)
      real(dp), intent(inout) :: h
      type(odex_workspace), intent(inout) :: workspace
      type(odex_options), intent(in) :: options
      type(odex_hairer_row_lifecycle), intent(inout) :: row_lifecycle
      type(odex_row_result), intent(out) :: row_state

      call odex_row_result_reset(row_state)
      row_state%row_index = row_index
      row_state%h_after = h
      row_state%errold_after = row_lifecycle%errold

      if (.not. row_lifecycle%initialized) then
         row_state%invalid_rhs = .true.
         return
      end if
      if (row_index < 1 .or. row_index > row_lifecycle%max_rows) then
         row_state%invalid_rhs = .true.
         return
      end if
      if (size(y) /= row_lifecycle%dimension) then
         row_state%invalid_rhs = .true.
         return
      end if

      call odex_observe_hairer_midex_row(f, row_index, y, h, hmax_abs, fbase, row_lifecycle%scal, &
                                         row_lifecycle%errold, workspace, options, row_state)

      row_lifecycle%rows_attempted = row_lifecycle%rows_attempted + 1
      row_lifecycle%rhs_evals = row_lifecycle%rhs_evals + max(0, row_state%rhs_evals)
      row_lifecycle%last_row = row_index
      row_lifecycle%h_after = h
      row_lifecycle%atov = row_state%atov
      if (row_state%err_available) row_lifecycle%error_rows = row_lifecycle%error_rows + 1
      if (row_state%atov) row_lifecycle%atov_events = row_lifecycle%atov_events + 1

      if (row_state%err_available .and. (.not. row_state%atov) .and. (.not. row_state%invalid_rhs)) then
         row_lifecycle%hh(row_index) = row_state%hh
         row_lifecycle%work(row_index) = row_state%work
      end if
   end subroutine odex_observe_hairer_midex_lifecycle_row

   subroutine odex_hairer_controller_state_reset(controller_state)
      type(odex_hairer_controller_state), intent(out) :: controller_state

      controller_state%initialized = .false.
      controller_state%rejected = .false.
      controller_state%last_step = .false.
      controller_state%endpoint_reached = .false.
      controller_state%k = 2
      controller_state%kc = 0
      controller_state%km = odex_k_max
      controller_state%h = 0.0_dp
      controller_state%hmax_abs = 0.0_dp
      controller_state%hoptde = 0.0_dp
      controller_state%posneg = 1.0_dp
   end subroutine odex_hairer_controller_state_reset

   subroutine odex_hairer_controller_decision_reset(decision)
      type(odex_hairer_controller_decision), intent(out) :: decision

      decision%action = odex_hairer_controller_action_continue
      decision%next_row = 0
      decision%accepted_row = 0
      decision%rejected_row = 0
      decision%next_k = 0
      decision%next_h = 0.0_dp
      decision%rejected_after = .false.
      decision%last_step = .false.
      decision%endpoint_reached = .false.
   end subroutine odex_hairer_controller_decision_reset

   subroutine odex_observe_hairer_controller_initial_state(options, t, caller_h, hmax_input, controller_state)
      type(odex_options), intent(in) :: options
      real(dp), intent(in) :: t, caller_h, hmax_input
      type(odex_hairer_controller_state), intent(out) :: controller_state

      type(odex_options) :: opts
      integer :: k_initial
      real(dp) :: h_initial, hmax_abs

      call odex_hairer_controller_state_reset(controller_state)
      opts = options
      call odex_normalize_options(opts)
      call odex_observe_hairer_initial_state(opts, t, caller_h, hmax_input, h_initial, k_initial, hmax_abs)

      controller_state%initialized = .true.
      controller_state%k = k_initial
      controller_state%km = opts%k_max
      controller_state%h = h_initial
      controller_state%hmax_abs = hmax_abs
      controller_state%posneg = sign(1.0_dp, t)
      controller_state%hoptde = controller_state%posneg*hmax_abs
   end subroutine odex_observe_hairer_controller_initial_state

   subroutine odex_observe_hairer_controller_step_entry(x, xend, u_round, controller_state, decision)
      real(dp), intent(in) :: x, xend, u_round
      type(odex_hairer_controller_state), intent(inout) :: controller_state
      type(odex_hairer_controller_decision), intent(out) :: decision

      real(dp) :: h_step
      logical :: endpoint_reached, last_step

      call odex_hairer_controller_decision_reset(decision)
      if (.not. controller_state%initialized) then
         decision%action = odex_hairer_controller_action_invalid
         return
      end if

      call odex_observe_hairer_step_entry(x, xend, controller_state%h, controller_state%hmax_abs, &
                                          controller_state%hoptde, u_round, h_step, last_step, endpoint_reached)
      controller_state%endpoint_reached = endpoint_reached
      controller_state%last_step = last_step
      decision%endpoint_reached = endpoint_reached
      decision%last_step = last_step

      if (endpoint_reached) then
         controller_state%h = 0.0_dp
         decision%action = odex_hairer_controller_action_endpoint
         return
      end if

      controller_state%h = h_step
      controller_state%posneg = sign(1.0_dp, xend - x)
      decision%next_h = h_step
      decision%next_k = controller_state%k
      decision%next_row = 1
   end subroutine odex_observe_hairer_controller_step_entry

   subroutine odex_observe_hairer_controller_row_action(controller_state, row_state, row_lifecycle, workspace, &
                                                        options, phase, decision)
      type(odex_hairer_controller_state), intent(inout) :: controller_state
      type(odex_row_result), intent(in) :: row_state
      type(odex_hairer_row_lifecycle), intent(in) :: row_lifecycle
      type(odex_workspace), intent(in) :: workspace
      type(odex_options), intent(in) :: options
      integer, intent(in) :: phase
      type(odex_hairer_controller_decision), intent(out) :: decision

      integer :: row_index
      real(dp) :: convergence_threshold, hope_threshold

      call odex_hairer_controller_decision_reset(decision)
      decision%next_k = controller_state%k
      decision%next_h = controller_state%h
      decision%last_step = controller_state%last_step
      decision%endpoint_reached = controller_state%endpoint_reached

      if (.not. controller_state%initialized .or. .not. row_lifecycle%initialized) then
         decision%action = odex_hairer_controller_action_invalid
         return
      end if
      if (row_state%invalid_rhs .or. row_state%stability_rejected) then
         decision%action = odex_hairer_controller_action_invalid
         return
      end if

      row_index = row_state%row_index
      if (row_index <= 0) then
         decision%action = odex_hairer_controller_action_invalid
         return
      end if

      controller_state%kc = row_index
      if (row_state%atov) then
         controller_state%h = row_state%h_after
         controller_state%rejected = .true.
         decision%action = odex_hairer_controller_action_retry
         decision%next_h = controller_state%h
         decision%next_k = controller_state%k
         decision%next_row = 1
         decision%rejected_after = .true.
         return
      end if

      if (.not. row_state%err_available) then
         decision%next_row = row_index + 1
         return
      end if

      select case (phase)
      case (odex_hairer_controller_phase_first_last)
         if (row_index > 1 .and. row_state%err <= 1.0_dp) then
            decision%action = odex_hairer_controller_action_accept
            decision%accepted_row = row_index
            return
         end if
         if (row_index < controller_state%k) then
            decision%next_row = row_index + 1
            return
         end if
         if (row_index == controller_state%k) then
            hope_threshold = odex_kplus1_hope_threshold(controller_state%k, workspace)
            if (row_state%err > hope_threshold) then
               call odex_observe_hairer_controller_reject_update(controller_state, row_lifecycle, options, decision)
            else
               decision%next_row = controller_state%k + 1
            end if
            return
         end if
         if (row_index == controller_state%k + 1) then
            if (row_state%err > 1.0_dp) then
               call odex_observe_hairer_controller_reject_update(controller_state, row_lifecycle, options, decision)
            else
               decision%action = odex_hairer_controller_action_accept
               decision%accepted_row = row_index
            end if
            return
         end if

      case (odex_hairer_controller_phase_basic)
         if (row_index < controller_state%k - 1) then
            decision%next_row = row_index + 1
            return
         end if
         if (row_index == controller_state%k - 1) then
            if (controller_state%k == 2 .or. controller_state%rejected) then
               decision%next_row = controller_state%k
            else if (row_state%err <= 1.0_dp) then
               decision%action = odex_hairer_controller_action_accept
               decision%accepted_row = row_index
            else
               convergence_threshold = odex_convergence_reject_threshold(controller_state%k, workspace, .true.)
               if (row_state%err > convergence_threshold) then
                  call odex_observe_hairer_controller_reject_update(controller_state, row_lifecycle, options, decision)
               else
                  decision%next_row = controller_state%k
               end if
            end if
            return
         end if
         if (row_index == controller_state%k) then
            if (row_state%err <= 1.0_dp) then
               decision%action = odex_hairer_controller_action_accept
               decision%accepted_row = row_index
            else
               hope_threshold = odex_kplus1_hope_threshold(controller_state%k, workspace)
               if (row_state%err > hope_threshold) then
                  call odex_observe_hairer_controller_reject_update(controller_state, row_lifecycle, options, decision)
               else
                  decision%next_row = controller_state%k + 1
               end if
            end if
            return
         end if
         if (row_index == controller_state%k + 1) then
            if (row_state%err > 1.0_dp) then
               call odex_observe_hairer_controller_reject_update(controller_state, row_lifecycle, options, decision)
            else
               decision%action = odex_hairer_controller_action_accept
               decision%accepted_row = row_index
            end if
            return
         end if

      case default
         decision%action = odex_hairer_controller_action_invalid
         return
      end select

      decision%action = odex_hairer_controller_action_invalid
   end subroutine odex_observe_hairer_controller_row_action

   subroutine odex_observe_hairer_controller_accept_update(controller_state, row_lifecycle, workspace, options, decision)
      type(odex_hairer_controller_state), intent(inout) :: controller_state
      type(odex_hairer_row_lifecycle), intent(in) :: row_lifecycle
      type(odex_workspace), intent(in) :: workspace
      type(odex_options), intent(in) :: options
      type(odex_hairer_controller_decision), intent(out) :: decision

      type(odex_options) :: opts
      integer :: kc, km, kopt, next_k
      real(dp) :: h_abs, w_km2, w_km1, w_k

      call odex_hairer_controller_decision_reset(decision)
      if (.not. controller_state%initialized .or. .not. row_lifecycle%initialized .or. &
          .not. allocated(workspace%ak)) then
         decision%action = odex_hairer_controller_action_invalid
         return
      end if
      opts = options
      call odex_normalize_options(opts)

      kc = controller_state%kc
      km = min(controller_state%km, row_lifecycle%max_rows, size(workspace%ak))
      if (kc < 2 .or. kc > row_lifecycle%max_rows .or. km < 3) then
         decision%action = odex_hairer_controller_action_invalid
         return
      end if

      w_km2 = odex_hairer_lifecycle_work(row_lifecycle, kc - 2)
      w_km1 = odex_hairer_lifecycle_work(row_lifecycle, kc - 1)
      w_k = odex_hairer_lifecycle_work(row_lifecycle, kc)
      call odex_observe_hairer_kopt(kc, controller_state%k, km, controller_state%rejected, &
                                    w_km2, w_km1, w_k, opts, kopt)

      if (controller_state%rejected) then
         next_k = max(2, min(kopt, kc))
         h_abs = min(abs(controller_state%h), abs(odex_hairer_lifecycle_hh(row_lifecycle, next_k)))
         controller_state%rejected = .false.
      else
         next_k = kopt
         if (kopt <= kc) then
            h_abs = abs(odex_hairer_lifecycle_hh(row_lifecycle, kopt))
         else if (kc < controller_state%k .and. &
                  odex_hairer_lifecycle_work(row_lifecycle, kc) < &
                  odex_hairer_lifecycle_work(row_lifecycle, kc - 1)*opts%order_increase_factor) then
            h_abs = abs(odex_hairer_lifecycle_hh(row_lifecycle, kc))*workspace%ak(min(kopt + 1, km))/workspace%ak(kc)
         else
            h_abs = abs(odex_hairer_lifecycle_hh(row_lifecycle, kc))*workspace%ak(kopt)/workspace%ak(kc)
         end if
      end if

      controller_state%k = next_k
      controller_state%h = sign(h_abs, controller_state%posneg)
      decision%action = odex_hairer_controller_action_continue
      decision%next_k = controller_state%k
      decision%next_h = controller_state%h
      decision%next_row = 1
      decision%rejected_after = controller_state%rejected
   end subroutine odex_observe_hairer_controller_accept_update

   subroutine odex_observe_hairer_controller_reject_update(controller_state, row_lifecycle, options, decision)
      type(odex_hairer_controller_state), intent(inout) :: controller_state
      type(odex_hairer_row_lifecycle), intent(in) :: row_lifecycle
      type(odex_options), intent(in) :: options
      type(odex_hairer_controller_decision), intent(out) :: decision

      type(odex_options) :: opts
      integer :: next_k

      call odex_hairer_controller_decision_reset(decision)
      if (.not. controller_state%initialized .or. .not. row_lifecycle%initialized) then
         decision%action = odex_hairer_controller_action_invalid
         return
      end if
      opts = options
      call odex_normalize_options(opts)

      next_k = min(controller_state%k, controller_state%kc, controller_state%km - 1)
      next_k = max(2, next_k)
      if (next_k > 2 .and. next_k <= row_lifecycle%max_rows .and. next_k - 1 <= row_lifecycle%max_rows) then
         if (odex_hairer_lifecycle_work(row_lifecycle, next_k - 1) < &
             odex_hairer_lifecycle_work(row_lifecycle, next_k)*opts%order_decrease_factor) next_k = next_k - 1
      end if

      controller_state%k = next_k
      controller_state%h = sign(abs(odex_hairer_lifecycle_hh(row_lifecycle, next_k)), controller_state%posneg)
      controller_state%rejected = .true.
      decision%action = odex_hairer_controller_action_reject
      decision%next_k = controller_state%k
      decision%next_h = controller_state%h
      decision%next_row = 1
      decision%rejected_row = controller_state%kc
      decision%rejected_after = .true.
   end subroutine odex_observe_hairer_controller_reject_update

   real(dp) function odex_hairer_lifecycle_work(row_lifecycle, row_index) result(work_value)
      type(odex_hairer_row_lifecycle), intent(in) :: row_lifecycle
      integer, intent(in) :: row_index

      if (row_index >= 1 .and. row_index <= row_lifecycle%max_rows .and. allocated(row_lifecycle%work)) then
         work_value = row_lifecycle%work(row_index)
      else
         work_value = huge(1.0_dp)
      end if
   end function odex_hairer_lifecycle_work

   real(dp) function odex_hairer_lifecycle_hh(row_lifecycle, row_index) result(hh_value)
      type(odex_hairer_row_lifecycle), intent(in) :: row_lifecycle
      integer, intent(in) :: row_index

      if (row_index >= 1 .and. row_index <= row_lifecycle%max_rows .and. allocated(row_lifecycle%hh)) then
         hh_value = row_lifecycle%hh(row_index)
      else
         hh_value = 0.0_dp
      end if
   end function odex_hairer_lifecycle_hh

   function calculate_wk(h, er1, k, workspace, opts) result(wk)
      real(dp), intent(in) :: h, er1
      integer, intent(in) :: k
      type(odex_workspace), intent(in) :: workspace
      type(odex_options), intent(in) :: opts
      integer :: kc
      real(dp) :: hk_abs, scale, wk

      kc = max(1, k)
      scale = odex_step_scale(er1, kc, workspace, opts)
      hk_abs = abs(h)*scale
      if (.not. ieee_is_finite(hk_abs) .or. hk_abs <= tiny(1.0_dp)) then
         wk = huge(1.0_dp)
      else
         wk = workspace%ak(kc)/hk_abs
      end if
   end function calculate_wk

   function calculate_hk(h, er1, k, workspace, opts) result(hk)
      real(dp), intent(in) :: h, er1
      integer, intent(in) :: k
      type(odex_workspace), intent(in) :: workspace
      type(odex_options), intent(in) :: opts
      integer :: kc
      real(dp) :: hk

      kc = max(1, k)
      hk = h*odex_step_scale(er1, kc, workspace, opts)
   end function calculate_hk

   function odex_step_scale(er1, k, workspace, opts) result(scale)
      real(dp), intent(in) :: er1
      integer, intent(in) :: k
      type(odex_workspace), intent(in) :: workspace
      type(odex_options), intent(in) :: opts
      integer :: kc
      real(dp) :: facmin, lower_bound, raw_scale, scale, upper_bound

      kc = max(1, k)
      raw_scale = 0.94_dp*(0.65_dp/max(er1, 1.0e-14_dp))**workspace%invexp(kc)
      facmin = opts%step_size_bound_fac1**workspace%invexp(kc)
      lower_bound = facmin/opts%step_size_bound_fac2
      upper_bound = 1.0_dp/facmin
      if (.not. ieee_is_finite(raw_scale)) raw_scale = upper_bound
      scale = min(upper_bound, max(lower_bound, raw_scale))
   end function odex_step_scale

   pure function odex_error_scale(opts, y_start, row_estimate, error_value_a, error_value_b, hairer_policy) result(scale)
      type(odex_options), intent(in) :: opts
      real(dp), intent(in) :: y_start, row_estimate, error_value_a, error_value_b
      logical, intent(in) :: hairer_policy
      real(dp) :: scale

      if (hairer_policy) then
         scale = opts%abs_tol + opts%rel_tol*max(abs(y_start), abs(row_estimate))
      else
         scale = opts%abs_tol + opts%rel_tol*max(abs(error_value_a), abs(error_value_b))
      end if
      scale = max(scale, tiny(1.0_dp))
   end function odex_error_scale

   function odex_convergence_reject_threshold(k, workspace, hairer_policy) result(threshold)
      integer, intent(in) :: k
      type(odex_workspace), intent(in) :: workspace
      logical, intent(in) :: hairer_policy
      integer :: kc, k_next
      real(dp) :: threshold

      kc = max(1, k)
      if (hairer_policy .and. allocated(workspace%nsteps) .and. kc + 1 <= size(workspace%nsteps)) then
         k_next = kc + 1
         threshold = (real(workspace%nsteps(k_next)*workspace%nsteps(kc), dp)/4.0_dp)**2
      else
         threshold = real((kc*kc + 1)**2, dp)
      end if
   end function odex_convergence_reject_threshold

   function odex_kplus1_hope_threshold(k, workspace) result(threshold)
      integer, intent(in) :: k
      type(odex_workspace), intent(in) :: workspace
      integer :: k_next
      real(dp) :: threshold

      if (allocated(workspace%nsteps) .and. k + 1 <= size(workspace%nsteps)) then
         k_next = max(1, k + 1)
         threshold = (real(workspace%nsteps(k_next), dp)/2.0_dp)**2
      else
         threshold = huge(1.0_dp)
      end if
   end function odex_kplus1_hope_threshold

   function calculate_ak(k) result(ak)
      integer, intent(in) :: k
      integer :: kc, i, w_sum
      real(dp) :: ak

      kc = max(1, k)
      w_sum = 0
      do i = 1, kc
         w_sum = w_sum + odex_iwork3_nstep(i)
      end do
      ak = 1.0_dp + real(w_sum, dp)
   end function calculate_ak

   subroutine build_nsteps(max_k, nsteps)
      integer, intent(in) :: max_k
      integer, intent(out) :: nsteps(max_k)
      integer :: i

      if (max_k < 1) return
      nsteps = 0
      do i = 1, max_k
         nsteps(i) = odex_iwork3_nstep(i)
      end do
   end subroutine build_nsteps

   subroutine odex_observe_h_min(options, t, h_min, h_min_fp, h_min_tol, h_min_span)
      type(odex_options), intent(in) :: options
      real(dp), intent(in) :: t
      real(dp), intent(out) :: h_min
      real(dp), intent(out), optional :: h_min_fp, h_min_tol, h_min_span
      type(odex_options) :: opts
      real(dp) :: fp_component, tol_component, span_component

      opts = options
      call odex_normalize_options(opts)
      fp_component = opts%h_min_c_fp*epsilon(1.0_dp)*max(1.0_dp, abs(t))
      tol_component = opts%h_min_c_tol*max(opts%abs_tol, opts%rel_tol, epsilon(1.0_dp))
      span_component = opts%h_min_c_span*abs(t)
      h_min = max(fp_component, min(tol_component, span_component))
      if (present(h_min_fp)) h_min_fp = fp_component
      if (present(h_min_tol)) h_min_tol = tol_component
      if (present(h_min_span)) h_min_span = span_component
   end subroutine odex_observe_h_min

   subroutine odex_observe_hairer_h_min(options, t, h_min, h_min_fp, h_min_tol, h_min_span)
      type(odex_options), intent(in) :: options
      real(dp), intent(in) :: t
      real(dp), intent(out) :: h_min
      real(dp), intent(out), optional :: h_min_fp, h_min_tol, h_min_span
      type(odex_options) :: opts
      real(dp) :: fp_component

      opts = options
      call odex_normalize_options(opts)
      fp_component = opts%h_min_c_fp*epsilon(1.0_dp)*max(1.0_dp, abs(t))
      h_min = fp_component
      if (present(h_min_fp)) h_min_fp = fp_component
      if (present(h_min_tol)) h_min_tol = 0.0_dp
      if (present(h_min_span)) h_min_span = 0.0_dp
   end subroutine odex_observe_hairer_h_min

   function odex_observe_initial_step(options, t) result(h_initial)
      type(odex_options), intent(in) :: options
      real(dp), intent(in) :: t
      type(odex_options) :: opts
      real(dp) :: h_initial, h_min

      opts = options
      call odex_normalize_options(opts)
      call odex_observe_h_min(opts, t, h_min)
      h_initial = t*opts%initial_step_fraction
      if (h_initial == 0.0_dp) h_initial = sign(h_min, t)
   end function odex_observe_initial_step

   subroutine odex_observe_hairer_initial_state(options, t, caller_h, hmax_input, h_initial, k_initial, hmax_abs)
      type(odex_options), intent(in) :: options
      real(dp), intent(in) :: t, caller_h, hmax_input
      real(dp), intent(out) :: h_initial, hmax_abs
      integer, intent(out) :: k_initial
      type(odex_options) :: opts
      real(dp) :: h_abs, reltol, span, posneg

      opts = options
      call odex_normalize_options(opts)

      span = abs(t)
      if (hmax_input == 0.0_dp) then
         hmax_abs = span
      else
         hmax_abs = abs(hmax_input)
      end if

      reltol = max(opts%rel_tol, 0.0_dp)
      k_initial = int(-log10(reltol + 1.0e-40_dp)*0.6_dp + 1.5_dp)
      k_initial = max(2, min(opts%k_max - 1, k_initial))

      if (t == 0.0_dp) then
         h_initial = 0.0_dp
         return
      end if

      posneg = sign(1.0_dp, t)
      h_abs = max(abs(caller_h), 1.0e-4_dp)
      h_initial = posneg*min(h_abs, hmax_abs, span/2.0_dp)
   end subroutine odex_observe_hairer_initial_state

   subroutine odex_observe_hairer_step_entry(x, xend, h_current, hmax_abs, hoptde, u_round, &
                                             h_step, last_step, endpoint_reached)
      real(dp), intent(in) :: x, xend, h_current, hmax_abs, hoptde, u_round
      real(dp), intent(out) :: h_step
      logical, intent(out) :: last_step, endpoint_reached
      real(dp) :: posneg, span

      span = abs(xend - x)
      posneg = sign(1.0_dp, xend - x)
      endpoint_reached = 0.1_dp*span <= abs(x)*u_round
      last_step = .false.
      if (endpoint_reached) then
         h_step = 0.0_dp
         return
      end if

      h_step = posneg*min(abs(h_current), span, abs(hmax_abs), abs(hoptde))
      if ((x + 1.01_dp*h_step - xend)*posneg > 0.0_dp) then
         h_step = xend - x
         last_step = .true.
      end if
   end subroutine odex_observe_hairer_step_entry

   subroutine odex_observe_hairer_kopt(kc, k_current, km, rejected, w_km2, w_km1, w_k, options, kopt)
      integer, intent(in) :: kc, k_current, km
      logical, intent(in) :: rejected
      real(dp), intent(in) :: w_km2, w_km1, w_k
      type(odex_options), intent(in) :: options
      integer, intent(out) :: kopt
      type(odex_options) :: opts
      real(dp) :: selected_work

      opts = options
      call odex_normalize_options(opts)

      if (kc <= 2) then
         kopt = min(3, km - 1)
         if (rejected) kopt = 2
         return
      end if

      if (kc <= k_current) then
         kopt = kc
         if (w_km1 < w_k*opts%order_decrease_factor) kopt = kc - 1
         if (w_k < w_km1*opts%order_increase_factor) kopt = min(kc + 1, km - 1)
      else
         kopt = kc - 1
         if (kc > 3 .and. w_km2 < w_km1*opts%order_decrease_factor) kopt = kc - 2
         selected_work = odex_hairer_work_at_index(kopt, kc, w_km2, w_km1, w_k)
         if (w_k < selected_work*opts%order_increase_factor) kopt = min(kc, km - 1)
      end if

      kopt = max(2, min(km - 1, kopt))
   end subroutine odex_observe_hairer_kopt

   subroutine odex_observe_hairer_promotion_step(workspace, h_candidate, k_previous, k_next, h_next)
      type(odex_workspace), intent(in) :: workspace
      real(dp), intent(in) :: h_candidate
      integer, intent(in) :: k_previous, k_next
      real(dp), intent(out) :: h_next

      h_next = odex_hairer_promotion_step(h_candidate, k_previous, k_next, workspace)
   end subroutine odex_observe_hairer_promotion_step

   subroutine odex_observe_hairer_reject_update(k_current, kc, km, work_values, step_values, &
                                                options, posneg, next_k, next_h)
      integer, intent(in) :: k_current, kc, km
      real(dp), intent(in) :: work_values(:), step_values(:), posneg
      type(odex_options), intent(in) :: options
      integer, intent(out) :: next_k
      real(dp), intent(out) :: next_h
      type(odex_options) :: opts

      opts = options
      call odex_normalize_options(opts)
      next_k = min(k_current, kc, km - 1)
      next_k = max(2, next_k)

      if (next_k > 2 .and. next_k <= size(work_values) .and. next_k - 1 <= size(work_values)) then
         if (work_values(next_k - 1) < work_values(next_k)*opts%order_decrease_factor) next_k = next_k - 1
      end if

      if (next_k <= size(step_values)) then
         next_h = sign(abs(step_values(next_k)), posneg)
      else
         next_h = 0.0_dp
      end if
   end subroutine odex_observe_hairer_reject_update

   subroutine odex_store_hairer_controller_row(work_values, step_values, row_index, work_estimate, step_estimate)
      real(dp), intent(inout) :: work_values(:), step_values(:)
      integer, intent(in) :: row_index
      real(dp), intent(in) :: work_estimate, step_estimate

      if (row_index < 1 .or. row_index > size(work_values) .or. row_index > size(step_values)) return
      work_values(row_index) = work_estimate
      step_values(row_index) = abs(step_estimate)
   end subroutine odex_store_hairer_controller_row

   subroutine odex_apply_hairer_accept_update(k_current, kc, w_km2, w_km1, w_k, h_km1, h_k, &
                                              workspace, options, next_k, next_h)
      integer, intent(in) :: k_current, kc
      real(dp), intent(in) :: w_km2, w_km1, w_k, h_km1, h_k
      type(odex_workspace), intent(in) :: workspace
      type(odex_options), intent(in) :: options
      integer, intent(out) :: next_k
      real(dp), intent(out) :: next_h
      integer :: kopt, km

      km = min(options%k_max, size(workspace%ak))
      call odex_observe_hairer_kopt(kc, k_current, km, .false., w_km2, w_km1, w_k, options, kopt)
      next_k = max(2, min(km, kopt))

      if (next_k > kc) then
         next_h = odex_hairer_promotion_step(h_k, kc, next_k, workspace)
      else if (next_k < kc) then
         next_h = h_km1
      else
         next_h = h_k
      end if
   end subroutine odex_apply_hairer_accept_update

   subroutine odex_observe_controller_estimate(workspace, h, er1, k, h_candidate, work_estimate, options)
      type(odex_workspace), intent(in) :: workspace
      real(dp), intent(in) :: h, er1
      integer, intent(in) :: k
      real(dp), intent(out) :: h_candidate, work_estimate
      type(odex_options), intent(in), optional :: options
      integer :: kc
      type(odex_options) :: opts

      kc = max(1, k)
      if (.not. workspace%tables_ready .or. workspace%table_k < kc) then
         h_candidate = 0.0_dp
         work_estimate = huge(1.0_dp)
         return
      end if

      if (present(options)) then
         opts = options
      else
         call odex_default_options(opts)
      end if
      call odex_normalize_options(opts)

      h_candidate = calculate_hk(h, er1, kc, workspace, opts)
      work_estimate = calculate_wk(h, er1, kc, workspace, opts)
   end subroutine odex_observe_controller_estimate

   function odex_observe_large_error_threshold(k) result(threshold)
      integer, intent(in) :: k
      integer :: kc
      real(dp) :: threshold

      kc = max(1, k)
      threshold = real((kc*kc + 1)**2, dp)
   end function odex_observe_large_error_threshold

   subroutine odex_observe_order_transition(wk_lower, wk_current, k, options, transition, next_k)
      real(dp), intent(in) :: wk_lower, wk_current
      integer, intent(in) :: k
      type(odex_options), intent(in) :: options
      integer, intent(out) :: transition, next_k
      type(odex_options) :: opts
      integer :: kc

      opts = options
      call odex_normalize_options(opts)
      kc = min(max(k, opts%k_min), opts%k_max)
      transition = odex_order_transition_keep
      next_k = kc

      if (wk_lower <= opts%order_decrease_factor*wk_current) then
         transition = odex_order_transition_demote
         next_k = max(opts%k_min, kc - 1)
      else if (wk_current <= opts%order_increase_factor*wk_lower) then
         transition = odex_order_transition_promote
         next_k = min(opts%k_max, kc + 1)
      end if
   end subroutine odex_observe_order_transition

   pure function odex_hairer_work_at_index(kopt, kc, w_km2, w_km1, w_k) result(work)
      integer, intent(in) :: kopt, kc
      real(dp), intent(in) :: w_km2, w_km1, w_k
      real(dp) :: work

      if (kopt <= kc - 2) then
         work = w_km2
      else if (kopt == kc - 1) then
         work = w_km1
      else
         work = w_k
      end if
   end function odex_hairer_work_at_index

   pure function odex_hairer_promotion_step(h_candidate, k_previous, k_next, workspace) result(h_next)
      real(dp), intent(in) :: h_candidate
      integer, intent(in) :: k_previous, k_next
      type(odex_workspace), intent(in) :: workspace
      real(dp) :: h_next

      if (k_next > k_previous .and. k_previous >= 1 .and. k_next <= size(workspace%ak)) then
         h_next = h_candidate*workspace%ak(k_next)/workspace%ak(k_previous)
      else
         h_next = h_candidate
      end if
   end function odex_hairer_promotion_step

   logical function odex_observe_stability_reject(values, prev_norm, dt, options) result(reject)
      real(dp), intent(in) :: values(:), prev_norm, dt
      type(odex_options), intent(in) :: options
      type(odex_options) :: opts

      opts = options
      call odex_normalize_options(opts)
      reject = odex_stability_reject(values, prev_norm, dt, opts)
   end function odex_observe_stability_reject

   integer function odex_iwork3_nstep(idx) result(nstep)
      integer, intent(in) :: idx

      if (idx <= 1) then
         nstep = 2
      else if (mod(idx, 2) == 0) then
         nstep = 2**(idx/2 + 1)
      else
         nstep = 3*2**((idx - 1)/2)
      end if
   end function odex_iwork3_nstep

   subroutine ensure_odex_workspace_object(workspace, k_need, n_need)
      type(odex_workspace), intent(inout) :: workspace
      integer, intent(in) :: k_need, n_need
      integer :: k_safe, n_safe

      k_safe = max(1, k_need)
      n_safe = max(1, n_need)
      if (.not. allocated(workspace%tableau) .or. size(workspace%tableau, 1) < k_safe .or. &
          size(workspace%tableau, 2) < k_safe .or. size(workspace%tableau, 3) < n_safe) then
         if (allocated(workspace%tableau)) deallocate(workspace%tableau)
         allocate (workspace%tableau(k_safe, k_safe, n_safe))
      end if
      call ensure_odex_workspace_vector(workspace%yprev, n_safe)
      call ensure_odex_workspace_vector(workspace%ystate, n_safe)
      call ensure_odex_workspace_vector(workspace%ycurr, n_safe)
      call ensure_odex_workspace_vector(workspace%ynext, n_safe)
      call ensure_odex_workspace_vector(workspace%fval, n_safe)
      call ensure_odex_workspace_vector(workspace%fbase, n_safe)
      call ensure_odex_tables(workspace, k_safe)
   end subroutine ensure_odex_workspace_object

   subroutine ensure_odex_workspace_vector(vec, n_need)
      real(dp), allocatable, intent(inout) :: vec(:)
      integer, intent(in) :: n_need

      if (.not. allocated(vec) .or. size(vec) < n_need) then
         if (allocated(vec)) deallocate(vec)
         allocate (vec(n_need))
      end if
   end subroutine ensure_odex_workspace_vector

   subroutine ensure_odex_tables(workspace, k_need)
      type(odex_workspace), intent(inout) :: workspace
      integer, intent(in) :: k_need
      integer :: idx, jdx

      if (workspace%tables_ready .and. workspace%table_k >= k_need) return

      if (allocated(workspace%nsteps)) deallocate(workspace%nsteps)
      if (allocated(workspace%ak)) deallocate(workspace%ak)
      if (allocated(workspace%invexp)) deallocate(workspace%invexp)
      if (allocated(workspace%ratio)) deallocate(workspace%ratio)
      allocate (workspace%nsteps(k_need), workspace%ak(k_need), workspace%invexp(k_need), workspace%ratio(k_need, k_need))

      call build_nsteps(k_need, workspace%nsteps)
      do idx = 1, k_need
         workspace%ak(idx) = calculate_ak(idx)
         workspace%invexp(idx) = 1.0_dp/(2.0_dp*real(idx, dp) - 1.0_dp)
      end do
      do idx = 1, k_need
         do jdx = 1, k_need
            workspace%ratio(idx, jdx) = (real(workspace%nsteps(idx), dp)/real(workspace%nsteps(jdx), dp))**2 - 1.0_dp
         end do
      end do
      workspace%table_k = k_need
      workspace%tables_ready = .true.
   end subroutine ensure_odex_tables

   subroutine odex_result_reset(result_state)
      type(odex_result), intent(out) :: result_state

      result_state%status = odex_status_unknown
      result_state%failure_reason = odex_reason_none
      result_state%accepted_steps = 0
      result_state%rejected_steps = 0
      result_state%stability_rejects = 0
      result_state%final_order = 0
      result_state%final_step_size = 0.0_dp
      result_state%t_remaining = 0.0_dp
      result_state%endpoint_available = .false.
      result_state%cvode_backend_used = .false.
      result_state%cvode_rhs_evals = 0
      result_state%cvode_error_test_fails = 0
      result_state%cvode_nonlinear_iters = 0
      result_state%cvode_nonlinear_conv_fails = 0
      result_state%cvode_step_solve_fails = 0
      result_state%odex_rhs_evals = 0
      result_state%odex_midpoint_rows = 0
      result_state%odex_kplus1_attempts = 0
      result_state%odex_accept_k_minus_1 = 0
      result_state%odex_accept_k = 0
      result_state%odex_accept_k_plus_1 = 0
      result_state%odex_large_error_rejects = 0
      result_state%odex_kplus1_rejects = 0
      result_state%odex_hairer_policy_steps = 0
      result_state%odex_tltm_policy_steps = 0
      result_state%odex_first_step_entries = 0
      result_state%odex_last_step_entries = 0
      result_state%odex_basic_step_entries = 0
      result_state%odex_row_j1_calls = 0
      result_state%odex_row_j2_calls = 0
      result_state%odex_row_jge3_calls = 0
      result_state%odex_row_j1_no_error_returns = 0
      result_state%odex_error_estimates = 0
      result_state%odex_hairer_scal_estimates = 0
      result_state%odex_default_scal_estimates = 0
      result_state%odex_errold_checks = 0
      result_state%odex_atov_events = 0
      result_state%odex_convergence_rejects = 0
      result_state%odex_kplus1_hope_rejects = 0
      result_state%odex_reject_kc_k_minus_1 = 0
      result_state%odex_reject_kc_k = 0
      result_state%odex_reject_kc_k_plus_1 = 0
      result_state%odex_kopt_accept_updates = 0
      result_state%odex_kopt_demotions = 0
      result_state%odex_kopt_keeps = 0
      result_state%odex_kopt_promotions = 0
      result_state%odex_after_reject_clamps = 0
      result_state%odex_reject_updates = 0
   end subroutine odex_result_reset

   subroutine odex_step_telemetry_reset(step_stats)
      type(odex_step_telemetry), intent(out) :: step_stats

      step_stats%rhs_evals = 0
      step_stats%midpoint_rows = 0
      step_stats%kplus1_attempts = 0
      step_stats%accept_k_minus_1 = 0
      step_stats%accept_k = 0
      step_stats%accept_k_plus_1 = 0
      step_stats%large_error_rejects = 0
      step_stats%kplus1_rejects = 0
      step_stats%row_j1_calls = 0
      step_stats%row_j2_calls = 0
      step_stats%row_jge3_calls = 0
      step_stats%row_j1_no_error_returns = 0
      step_stats%error_estimates = 0
      step_stats%hairer_scal_estimates = 0
      step_stats%default_scal_estimates = 0
      step_stats%errold_checks = 0
      step_stats%atov_events = 0
      step_stats%convergence_rejects = 0
      step_stats%kplus1_hope_rejects = 0
      step_stats%reject_kc_k_minus_1 = 0
      step_stats%reject_kc_k = 0
      step_stats%reject_kc_k_plus_1 = 0
      step_stats%kopt_accept_updates = 0
      step_stats%kopt_demotions = 0
      step_stats%kopt_keeps = 0
      step_stats%kopt_promotions = 0
      step_stats%after_reject_clamps = 0
      step_stats%reject_updates = 0
   end subroutine odex_step_telemetry_reset

   subroutine odex_result_record_step_telemetry(result_state, step_stats)
      type(odex_result), intent(inout) :: result_state
      type(odex_step_telemetry), intent(in) :: step_stats

      result_state%odex_rhs_evals = result_state%odex_rhs_evals + max(0, step_stats%rhs_evals)
      result_state%odex_midpoint_rows = result_state%odex_midpoint_rows + max(0, step_stats%midpoint_rows)
      result_state%odex_kplus1_attempts = result_state%odex_kplus1_attempts + max(0, step_stats%kplus1_attempts)
      result_state%odex_accept_k_minus_1 = result_state%odex_accept_k_minus_1 + max(0, step_stats%accept_k_minus_1)
      result_state%odex_accept_k = result_state%odex_accept_k + max(0, step_stats%accept_k)
      result_state%odex_accept_k_plus_1 = result_state%odex_accept_k_plus_1 + max(0, step_stats%accept_k_plus_1)
      result_state%odex_large_error_rejects = result_state%odex_large_error_rejects + max(0, step_stats%large_error_rejects)
      result_state%odex_kplus1_rejects = result_state%odex_kplus1_rejects + max(0, step_stats%kplus1_rejects)
      result_state%odex_row_j1_calls = result_state%odex_row_j1_calls + max(0, step_stats%row_j1_calls)
      result_state%odex_row_j2_calls = result_state%odex_row_j2_calls + max(0, step_stats%row_j2_calls)
      result_state%odex_row_jge3_calls = result_state%odex_row_jge3_calls + max(0, step_stats%row_jge3_calls)
      result_state%odex_row_j1_no_error_returns = result_state%odex_row_j1_no_error_returns + &
         max(0, step_stats%row_j1_no_error_returns)
      result_state%odex_error_estimates = result_state%odex_error_estimates + max(0, step_stats%error_estimates)
      result_state%odex_hairer_scal_estimates = result_state%odex_hairer_scal_estimates + &
         max(0, step_stats%hairer_scal_estimates)
      result_state%odex_default_scal_estimates = result_state%odex_default_scal_estimates + &
         max(0, step_stats%default_scal_estimates)
      result_state%odex_errold_checks = result_state%odex_errold_checks + max(0, step_stats%errold_checks)
      result_state%odex_atov_events = result_state%odex_atov_events + max(0, step_stats%atov_events)
      result_state%odex_convergence_rejects = result_state%odex_convergence_rejects + max(0, step_stats%convergence_rejects)
      result_state%odex_kplus1_hope_rejects = result_state%odex_kplus1_hope_rejects + max(0, step_stats%kplus1_hope_rejects)
      result_state%odex_reject_kc_k_minus_1 = result_state%odex_reject_kc_k_minus_1 + &
         max(0, step_stats%reject_kc_k_minus_1)
      result_state%odex_reject_kc_k = result_state%odex_reject_kc_k + max(0, step_stats%reject_kc_k)
      result_state%odex_reject_kc_k_plus_1 = result_state%odex_reject_kc_k_plus_1 + &
         max(0, step_stats%reject_kc_k_plus_1)
      result_state%odex_kopt_accept_updates = result_state%odex_kopt_accept_updates + max(0, step_stats%kopt_accept_updates)
      result_state%odex_kopt_demotions = result_state%odex_kopt_demotions + max(0, step_stats%kopt_demotions)
      result_state%odex_kopt_keeps = result_state%odex_kopt_keeps + max(0, step_stats%kopt_keeps)
      result_state%odex_kopt_promotions = result_state%odex_kopt_promotions + max(0, step_stats%kopt_promotions)
      result_state%odex_after_reject_clamps = result_state%odex_after_reject_clamps + &
         max(0, step_stats%after_reject_clamps)
      result_state%odex_reject_updates = result_state%odex_reject_updates + max(0, step_stats%reject_updates)
   end subroutine odex_result_record_step_telemetry

   subroutine odex_result_record_step_entry(result_state, hairer_policy, step_count, is_last_step)
      type(odex_result), intent(inout) :: result_state
      logical, intent(in) :: hairer_policy, is_last_step
      integer, intent(in) :: step_count

      if (hairer_policy) then
         result_state%odex_hairer_policy_steps = result_state%odex_hairer_policy_steps + 1
      else
         result_state%odex_tltm_policy_steps = result_state%odex_tltm_policy_steps + 1
      end if

      if (step_count == 1) then
         result_state%odex_first_step_entries = result_state%odex_first_step_entries + 1
      end if

      if (is_last_step) then
         result_state%odex_last_step_entries = result_state%odex_last_step_entries + 1
      else if (step_count /= 1) then
         result_state%odex_basic_step_entries = result_state%odex_basic_step_entries + 1
      end if
   end subroutine odex_result_record_step_entry

   subroutine odex_step_record_midpoint_row(step_stats, row_index)
      type(odex_step_telemetry), intent(inout) :: step_stats
      integer, intent(in) :: row_index

      step_stats%midpoint_rows = step_stats%midpoint_rows + 1
      if (row_index == 1) then
         step_stats%row_j1_calls = step_stats%row_j1_calls + 1
         step_stats%row_j1_no_error_returns = step_stats%row_j1_no_error_returns + 1
      else if (row_index == 2) then
         step_stats%row_j2_calls = step_stats%row_j2_calls + 1
      else
         step_stats%row_jge3_calls = step_stats%row_jge3_calls + 1
      end if
   end subroutine odex_step_record_midpoint_row

   subroutine odex_step_record_error_scale(step_stats, hairer_policy)
      type(odex_step_telemetry), intent(inout) :: step_stats
      logical, intent(in) :: hairer_policy

      step_stats%error_estimates = step_stats%error_estimates + 1
      if (hairer_policy) then
         step_stats%hairer_scal_estimates = step_stats%hairer_scal_estimates + 1
      else
         step_stats%default_scal_estimates = step_stats%default_scal_estimates + 1
      end if
   end subroutine odex_step_record_error_scale

   subroutine odex_step_record_kopt_transition(step_stats, accepted_order, next_order)
      type(odex_step_telemetry), intent(inout) :: step_stats
      integer, intent(in) :: accepted_order, next_order

      if (next_order < accepted_order) then
         step_stats%kopt_demotions = step_stats%kopt_demotions + 1
      else if (next_order > accepted_order) then
         step_stats%kopt_promotions = step_stats%kopt_promotions + 1
      else
         step_stats%kopt_keeps = step_stats%kopt_keeps + 1
      end if
   end subroutine odex_step_record_kopt_transition

   subroutine odex_result_mark_success(result_state, status_code, accepted_steps, final_order, final_step_size)
      type(odex_result), intent(inout) :: result_state
      integer, intent(in) :: status_code, accepted_steps, final_order
      real(dp), intent(in) :: final_step_size

      result_state%status = status_code
      result_state%failure_reason = odex_reason_none
      result_state%accepted_steps = accepted_steps
      result_state%rejected_steps = 0
      result_state%stability_rejects = 0
      result_state%final_order = final_order
      result_state%final_step_size = final_step_size
      result_state%t_remaining = 0.0_dp
      result_state%endpoint_available = .true.
   end subroutine odex_result_mark_success

   subroutine odex_result_mark_failure(result_state, reason_code, accepted_steps, rejected_steps, &
                                       final_order, final_step_size, t_remaining)
      type(odex_result), intent(inout) :: result_state
      integer, intent(in) :: reason_code, accepted_steps, rejected_steps, final_order
      real(dp), intent(in) :: final_step_size, t_remaining

      result_state%status = odex_status_from_failure_reason(reason_code)
      result_state%failure_reason = reason_code
      result_state%accepted_steps = accepted_steps
      result_state%rejected_steps = rejected_steps
      result_state%stability_rejects = 0
      result_state%final_order = final_order
      result_state%final_step_size = final_step_size
      result_state%t_remaining = t_remaining
      result_state%endpoint_available = .false.
   end subroutine odex_result_mark_failure

   pure integer function odex_status_from_failure_reason(reason_code) result(status_code)
      integer, intent(in) :: reason_code

      select case (reason_code)
      case (odex_reason_max_steps)
         status_code = odex_status_failure_max_steps
      case (odex_reason_invalid)
         status_code = odex_status_failure_invalid
      case (odex_reason_h_min)
         status_code = odex_status_failure_h_min
      case (odex_reason_max_rhs_evals)
         status_code = odex_status_failure_max_rhs_evals
      case (odex_reason_max_rejects)
         status_code = odex_status_failure_max_rejects
      case (odex_reason_stiffness)
         status_code = odex_status_failure_stiffness
      case default
         status_code = odex_status_unknown
      end select
   end function odex_status_from_failure_reason

   pure integer function odex_result_to_intode_status(result_state) result(status_code)
      type(odex_result), intent(in) :: result_state

      if (odex_status_is_mechanism_status(result_state%status)) then
         status_code = result_state%status
      else
         status_code = odex_status_unknown
      end if
   end function odex_result_to_intode_status

   pure logical function odex_status_is_failure(status_code) result(is_failure)
      integer, intent(in) :: status_code

      select case (status_code)
      case (odex_status_failure_max_steps, odex_status_failure_invalid, odex_status_failure_h_min, &
            odex_status_failure_max_rhs_evals, odex_status_failure_max_rejects, odex_status_failure_stiffness)
         is_failure = .true.
      case default
         is_failure = .false.
      end select
   end function odex_status_is_failure

   pure logical function odex_status_is_mechanism_status(status_code) result(is_mechanism)
      integer, intent(in) :: status_code

      select case (status_code)
      case (odex_status_unknown, odex_status_success, odex_status_success_zero_time, &
            odex_status_failure_max_steps, odex_status_failure_invalid, odex_status_failure_h_min, &
            odex_status_failure_max_rhs_evals, odex_status_failure_max_rejects, odex_status_failure_stiffness)
         is_mechanism = .true.
      case default
         is_mechanism = .false.
      end select
   end function odex_status_is_mechanism_status

   subroutine odex_normalize_options(options)
      type(odex_options), intent(inout) :: options

      options%abs_tol = max(options%abs_tol, 0.0_dp)
      options%rel_tol = max(options%rel_tol, 0.0_dp)
      options%k_min = max(odex_k_min, options%k_min)
      options%k_max = max(options%k_min, options%k_max)
      options%max_steps = max(0, options%max_steps)
      options%cvode_fixedpoint_m = max(0, options%cvode_fixedpoint_m)
      options%cvode_max_order = max(0, options%cvode_max_order)
      options%cvode_max_steps = max(0, options%cvode_max_steps)
      options%cvode_max_err_test_fails = max(0, options%cvode_max_err_test_fails)
      options%cvode_max_conv_fails = max(0, options%cvode_max_conv_fails)
      options%cvode_max_nonlin_iters = max(0, options%cvode_max_nonlin_iters)
      options%cvode_min_step = max(options%cvode_min_step, 0.0_dp)
      options%dop853_max_reject = max(0, options%dop853_max_reject)
      options%dop853_max_rhs_evals = max(0, options%dop853_max_rhs_evals)
      options%dop853_min_step = max(options%dop853_min_step, 0.0_dp)
      options%dop853_max_step = max(options%dop853_max_step, 0.0_dp)
      options%dop853_safety = min(0.999999_dp, max(options%dop853_safety, 1.0e-4_dp))
      options%dop853_fac1 = min(1.0_dp, max(options%dop853_fac1, 1.0e-6_dp))
      options%dop853_fac2 = max(options%dop853_fac2, 1.0_dp)
      options%dop853_beta = min(0.2_dp, max(options%dop853_beta, 0.0_dp))
      options%dop853_hinit_factor = min(1.0_dp, max(options%dop853_hinit_factor, 1.0e-12_dp))
      options%dop853_hinit_min = max(options%dop853_hinit_min, tiny(1.0_dp))
      options%dop853_stiffness_check_interval = max(1, options%dop853_stiffness_check_interval)
      options%dop853_stiffness_max_hits = max(1, options%dop853_stiffness_max_hits)
      options%dop853_stiffness_threshold = max(options%dop853_stiffness_threshold, 0.0_dp)
      options%h_min_c_fp = max(options%h_min_c_fp, 0.0_dp)
      options%h_min_c_tol = max(options%h_min_c_tol, 0.0_dp)
      options%h_min_c_span = max(options%h_min_c_span, 0.0_dp)
      options%initial_step_fraction = max(options%initial_step_fraction, epsilon(1.0_dp))
      options%step_size_bound_fac1 = min(1.0_dp, max(options%step_size_bound_fac1, tiny(1.0_dp)))
      options%step_size_bound_fac2 = max(options%step_size_bound_fac2, 1.0_dp)
      options%order_decrease_factor = min(1.0_dp, max(options%order_decrease_factor, 0.0_dp))
      options%order_increase_factor = min(1.0_dp, max(options%order_increase_factor, 0.0_dp))
      options%stability_growth_limit = max(options%stability_growth_limit, 1.0_dp)
      if (options%controller_policy == odex_controller_policy_legacy_tltm_endpoint) then
         options%controller_policy = odex_controller_policy_hairer_experimental
      end if
   end subroutine odex_normalize_options

   pure logical function odex_controller_policy_is_valid(controller_policy) result(is_valid)
      integer, intent(in) :: controller_policy

      select case (controller_policy)
      case (odex_controller_policy_hairer_experimental)
         is_valid = .true.
      case default
         is_valid = .false.
      end select
   end function odex_controller_policy_is_valid

   logical function odex_stability_reject(values, prev_norm, dt, opts) result(reject)
      real(dp), intent(in) :: values(:), prev_norm, dt
      type(odex_options), intent(in) :: opts
      real(dp) :: curr_norm, base_norm

      reject = .false.
      if (opts%stability_control /= odex_stability_control_conservative) return
      if (vector_has_invalid(values)) then
         reject = .true.
         return
      end if

      curr_norm = vector_rms(values)
      base_norm = max(prev_norm, tiny(1.0_dp))
      if (abs(dt)*curr_norm > 1.0_dp .and. curr_norm > opts%stability_growth_limit*base_norm) reject = .true.
   end function odex_stability_reject

   real(dp) function vector_rms(values) result(norm)
      real(dp), intent(in) :: values(:)

      if (size(values) <= 0) then
         norm = 0.0_dp
      else
         norm = sqrt(sum(values*values)/real(size(values), dp))
      end if
   end function vector_rms

   logical function vector_has_invalid(values) result(has_invalid)
      real(dp), intent(in) :: values(:)
      integer :: idx

      has_invalid = .false.
      do idx = 1, size(values)
         if (.not. ieee_is_finite(values(idx))) then
            has_invalid = .true.
            return
         end if
      end do
   end function vector_has_invalid

   pure function odex_to_lower_ascii(text) result(lower)
      character(len=*), intent(in) :: text
      character(len=len(text)) :: lower
      integer :: i, code

      lower = text
      do i = 1, len(text)
         code = iachar(text(i:i))
         if (code >= iachar("A") .and. code <= iachar("Z")) then
            lower(i:i) = achar(code + iachar("a") - iachar("A"))
         end if
      end do
   end function odex_to_lower_ascii

end module odex_backend

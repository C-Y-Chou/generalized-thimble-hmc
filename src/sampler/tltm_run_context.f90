module tltm_run_context_mod
   use solve_flow, only: flow_workspace_t, release_flow_workspace
   use hmc_state_buffers, only: rattle_step_workspace_t, release_rattle_step_workspace
   use quasi_newton_solver_mod, only: qn_context_t, release_qn_context
   implicit none
   private

   public :: tltm_run_context_t
   public :: tltm_hmc_context_t
   public :: tltm_flow_context_t
   public :: tltm_qn_context_t
   public :: release_tltm_run_context
   public :: release_tltm_hmc_context
   public :: release_tltm_flow_context
   public :: release_tltm_qn_context

   type :: tltm_hmc_context_t
      type(rattle_step_workspace_t) :: proposal_ws
      type(rattle_step_workspace_t) :: reverse_probe_ws
      type(rattle_step_workspace_t) :: warmup_ws
   end type tltm_hmc_context_t

   type :: tltm_flow_context_t
      type(flow_workspace_t) :: workspace
   end type tltm_flow_context_t

   type :: tltm_qn_context_t
      type(qn_context_t) :: workspace
   end type tltm_qn_context_t

   type :: tltm_model_context_t
      integer :: reserved = 0
   end type tltm_model_context_t

   type :: tltm_diagnostics_context_t
      integer :: reserved = 0
   end type tltm_diagnostics_context_t

   type :: tltm_config_context_t
      integer :: reserved = 0
   end type tltm_config_context_t

   type :: tltm_profile_context_t
      integer :: reserved = 0
   end type tltm_profile_context_t

   type :: tltm_run_context_t
      type(tltm_hmc_context_t) :: hmc
      type(tltm_flow_context_t) :: flow
      type(tltm_qn_context_t) :: qn
      type(tltm_model_context_t) :: model
      type(tltm_diagnostics_context_t) :: diagnostics
      type(tltm_config_context_t) :: config
      type(tltm_profile_context_t) :: profile
   end type tltm_run_context_t

contains

   subroutine release_tltm_run_context(context)
      type(tltm_run_context_t), intent(inout) :: context

      call release_tltm_hmc_context(context%hmc)
      call release_tltm_flow_context(context%flow)
      call release_tltm_qn_context(context%qn)
   end subroutine release_tltm_run_context

   subroutine release_tltm_hmc_context(context)
      type(tltm_hmc_context_t), intent(inout) :: context

      call release_rattle_step_workspace(context%proposal_ws)
      call release_rattle_step_workspace(context%reverse_probe_ws)
      call release_rattle_step_workspace(context%warmup_ws)
   end subroutine release_tltm_hmc_context

   subroutine release_tltm_flow_context(context)
      type(tltm_flow_context_t), intent(inout) :: context

      call release_flow_workspace(context%workspace)
   end subroutine release_tltm_flow_context

   subroutine release_tltm_qn_context(context)
      type(tltm_qn_context_t), intent(inout) :: context

      call release_qn_context(context%workspace)
   end subroutine release_tltm_qn_context

end module tltm_run_context_mod

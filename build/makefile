# --------- toolchain & optimisation flags -----------------------------------
SHELL       := /bin/bash

# Prefer Intel toolchain when available (module-loaded environments), then MPI
# wrappers, then GNU fallback.
ifeq ($(origin FC), default)
FC          := $(shell if command -v ifx >/dev/null 2>&1; then echo ifx; \
                 elif command -v mpiifx >/dev/null 2>&1; then echo mpiifx; \
                 elif command -v mpifort >/dev/null 2>&1; then echo mpifort; \
                 elif command -v mpif90 >/dev/null 2>&1; then echo mpif90; \
                 elif command -v gfortran >/dev/null 2>&1; then echo gfortran; \
                 fi)
endif

ifeq ($(strip $(FC)),)
$(error No Fortran compiler found. Load modules (e.g. Intel/MPI) or set FC=<compiler>)
endif

ifeq ($(origin CC), default)
CC          := $(shell if command -v icx >/dev/null 2>&1; then echo icx; \
                 elif command -v clang >/dev/null 2>&1; then echo clang; \
                 elif command -v gcc >/dev/null 2>&1; then echo gcc; \
                 elif command -v cc >/dev/null 2>&1; then echo cc; \
                 fi)
endif

ifeq ($(strip $(CC)),)
$(error No C compiler found. Load modules or set CC=<compiler>)
endif

FC_VERSION   := $(shell $(FC) --version 2>/dev/null | head -n 1 | tr '[:upper:]' '[:lower:]')
ifneq ($(findstring intel,$(FC_VERSION)),)
FC_FAMILY    := intel
else ifneq ($(findstring ifx,$(FC_VERSION)),)
FC_FAMILY    := intel
else ifneq ($(findstring ifort,$(FC_VERSION)),)
FC_FAMILY    := intel
else
FC_FAMILY    := gnu
endif

# Python for code generation (generate_model_generated.py needs >=3.8).
PYTHON       ?= $(shell if command -v python3.11 >/dev/null 2>&1; then echo python3.11; \
                    elif command -v python3.10 >/dev/null 2>&1; then echo python3.10; \
                    elif command -v python3.9 >/dev/null 2>&1; then echo python3.9; \
                    elif command -v python3.8 >/dev/null 2>&1; then echo python3.8; \
                    elif command -v python3 >/dev/null 2>&1; then echo python3; \
                    fi)

ifeq ($(strip $(PYTHON)),)
$(error No Python interpreter found. Set PYTHON=<path> with Python >=3.8)
endif

PYTHON_GE_38 := $(shell $(PYTHON) -c "import sys; print(1 if sys.version_info >= (3, 8) else 0)" 2>/dev/null)
ifneq ($(PYTHON_GE_38),1)
$(error $(PYTHON) is not usable for code generation. Use Python >=3.8, e.g. PYTHON=python3.11)
endif

ENABLE_OFFICIAL_DFOLS ?= 1
PYTHON_EMBED_CFLAGS ?= $(shell $(PYTHON)-config --includes 2>/dev/null || \
                    $(PYTHON) -c "import sysconfig; print('-I' + sysconfig.get_paths()['include'])")
PYTHON_EMBED_LDFLAGS ?= $(shell $(PYTHON)-config --ldflags --embed 2>/dev/null || \
                    $(PYTHON) -c "import sysconfig; libdir=sysconfig.get_config_var('LIBDIR') or ''; version=sysconfig.get_config_var('VERSION') or ''; libs=' '.join(str(sysconfig.get_config_var(k) or '') for k in ('LIBS','SYSLIBS','LINKFORSHARED')); print((' -L' + libdir if libdir else '') + (' -lpython' + version if version else '') + (' ' + libs if libs.strip() else ''))")
CFLAGS ?= -O2
LDLIBS ?=
ifneq ($(filter 1 yes true on,$(ENABLE_OFFICIAL_DFOLS)),)
LDLIBS += $(PYTHON_EMBED_LDFLAGS)
OFFICIAL_DFOLS_C_MODE := enabled
RETAINED_QN_EXPECT_PACKAGE_SUCCESS := QN_ROUTE_CONTRACT_EXPECT_PACKAGE_SUCCESS=1
else
OFFICIAL_DFOLS_C_MODE := stub
RETAINED_QN_EXPECT_PACKAGE_SUCCESS :=
endif

ENABLE_SUNDIALS_CVODE ?= 0
SUNDIALS_PREFIX ?=
ifneq ($(strip $(SUNDIALS_PREFIX)),)
SUNDIALS_DEFAULT_LIBDIR := $(if $(wildcard $(SUNDIALS_PREFIX)/lib64),$(SUNDIALS_PREFIX)/lib64,$(SUNDIALS_PREFIX)/lib)
SUNDIALS_CFLAGS ?= -I$(SUNDIALS_PREFIX)/include
SUNDIALS_LDFLAGS ?= -L$(SUNDIALS_DEFAULT_LIBDIR) -Wl,-rpath,$(SUNDIALS_DEFAULT_LIBDIR)
else
SUNDIALS_CFLAGS ?=
SUNDIALS_LDFLAGS ?=
endif
SUNDIALS_LIBS ?= -lsundials_cvode -lsundials_sunnonlinsolfixedpoint -lsundials_nvecserial -lsundials_core -lm
ifneq ($(filter 1 yes true on,$(ENABLE_SUNDIALS_CVODE)),)
LDLIBS += $(SUNDIALS_LDFLAGS) $(SUNDIALS_LIBS)
SUNDIALS_CVODE_C_MODE := enabled
else
SUNDIALS_CVODE_C_MODE := stub
endif

OMP         ?= 0
ARCH_FLAG_INTEL ?= -xCORE-AVX2
ARCH_FLAG_GNU   ?= -march=native
UNAME_S     := $(shell uname -s 2>/dev/null || echo unknown)
ifeq ($(UNAME_S),Darwin)
NOEXECSTACK_LDFLAG :=
else
NOEXECSTACK_LDFLAG := -Wl,-z,noexecstack
endif

ifeq ($(FC_FAMILY),intel)
ARCH_FLAG   = $(ARCH_FLAG_INTEL)
ifeq ($(OMP),1)
THREAD_FLAG = -qopenmp
MKL_FLAG    = -qmkl=parallel
else
THREAD_FLAG =
MKL_FLAG    = -qmkl=sequential
endif

OPT_COMMON  = -qopt-zmm-usage=high -qopt-prefetch=3 -qopt-streaming-stores=always \
              -qopt-mem-layout-trans=3 -align array64byte -heap-arrays 256 \
              -warn all -diag-error-limit=0

FFLAGS_OPT  = -O3 -ipo $(ARCH_FLAG) $(THREAD_FLAG) $(OPT_COMMON) \
              -fp-model precise
FFLAGS_FAST = -O2 -g -traceback -debug minimal $(ARCH_FLAG) $(THREAD_FLAG) $(OPT_COMMON) \
              -fp-model source -heap-arrays 128
MOD_FLAG    = -module $(MOD_DIR)
LDFLAGS_OPT = $(MKL_FLAG) $(THREAD_FLAG) $(ARCH_FLAG) -ipo $(NOEXECSTACK_LDFLAG)
LDFLAGS_FAST = $(MKL_FLAG) $(THREAD_FLAG) $(ARCH_FLAG) $(NOEXECSTACK_LDFLAG)
LDFLAGS     ?= $(LDFLAGS_OPT)
else
ARCH_FLAG   = $(ARCH_FLAG_GNU)
ifeq ($(OMP),1)
THREAD_FLAG = -fopenmp
else
THREAD_FLAG =
endif

# GNU path: keep line-length unbounded for large generated/source files.
OPT_COMMON  = -ffree-line-length-none -fbacktrace
FFLAGS_OPT  = -O3 $(ARCH_FLAG) $(THREAD_FLAG) $(OPT_COMMON)
FFLAGS_FAST = -O2 -g $(ARCH_FLAG) $(THREAD_FLAG) $(OPT_COMMON)
MOD_FLAG    = -J$(MOD_DIR)
GNU_LINALG_LIBS ?=
LDFLAGS_OPT = $(THREAD_FLAG) $(GNU_LINALG_LIBS) $(NOEXECSTACK_LDFLAG)
LDFLAGS_FAST = $(LDFLAGS_OPT)
LDFLAGS     ?= $(LDFLAGS_OPT)
endif

# Include path for generated module files
FFLAGS_INC  = -I$(MOD_DIR) -I$(SRC_DIR)/physics

# --------- project layout ----------------------------------------------------
SRC_DIR     = ../src
TEST_DIR    = ../tests
BIN_DIR     = ../bin
OBJ_DIR     = .obj
MOD_DIR     = $(OBJ_DIR)/mod
OFFICIAL_DFOLS_MODE_STAMP := $(OBJ_DIR)/official_dfols_bridge_mode.stamp
OUT_DIR     ?= ../output
OUT_PROD_DIR ?= $(OUT_DIR)/production
OUT_TEST_DIR ?= $(OUT_DIR)/tests
OUT_TEST1_DIR ?= $(OUT_TEST_DIR)/hamiltonian
OUT_LOG_DIR ?= $(OUT_DIR)/logs
GEN_SCRIPT  = ../scripts/generate_model_generated.py
GEN_BODY    = ../src/physics/model_action_body.inc
GEN_OUT     = ../src/physics/model_generated.f90
DEP_SCRIPT  = ../scripts/fortran_module_deps.py
DEP_OUT     = $(OBJ_DIR)/fortran_module_deps.mk
ST_TAPENADE_DEFAULT = $(HOME)/tools/tapenade-3.16-v2/bin/tapenade
ifneq ($(wildcard $(ST_TAPENADE_DEFAULT)),)
ST_TAPENADE_CMD ?= $(ST_TAPENADE_DEFAULT)
endif
export ST_TAPENADE_CMD
GEN_BACKEND ?= auto

# --------- layered source lists ----------------------------------------------
CORE_SRC     = core/mtdefs core/mt95 core/tltm_rng core/utils core/lapack_fallback core/perf_profile
CONFIG_SRC   = config/runtime_env_mod config/param_mod
PHYSICS_SRC  = physics/model_autodiff physics/model_tape_ad physics/model_generated physics/model physics/odex_backend physics/solve_flow
SAMPLER_SRC  = sampler/hmc_kernels sampler/hmc_constraints sampler/hmc_state_buffers sampler/tltm_run_context sampler/hmc_reversibility_checks \
               sampler/quasi_newton_linear_solver sampler/quasi_newton_solver \
               sampler/constraint_solver_stats sampler/hmc_integrator_core sampler/hmc sampler/markovchain_phase sampler/markovchain_io \
               sampler/markovchain_transition_status sampler/markovchain_metropolis sampler/markovchain_mod sampler/markovchain \
               sampler/tltm_types sampler/tltm_stage1_driver sampler/tltm_stage2_driver
APP_CHAIN    = apps/generate_markov_chain
APP_EXPECT   = apps/evaluate_expectations
APP_TLTM_STAGE1 = apps/run_tltm_stage1
APP_TLTM_STAGE2 = apps/run_tltm_stage2
APP_BTN_RESIDUAL = apps/evaluate_btn_residual_case

COMMON_SRC   = $(CORE_SRC) $(CONFIG_SRC) $(PHYSICS_SRC) $(SAMPLER_SRC)

# helper to prepend SRC_DIR and append .f90
define mk_src
$(addprefix $(SRC_DIR)/,$(addsuffix .f90,$(1)))
endef

SOURCES_COMMON := $(call mk_src,$(COMMON_SRC))
SOURCES_STEP2  := $(SOURCES_COMMON) $(call mk_src,$(APP_CHAIN))
SOURCES_STEP3  := $(SOURCES_COMMON) $(call mk_src,$(APP_EXPECT))
SOURCES_STEP9  := $(SOURCES_COMMON) $(call mk_src,$(APP_TLTM_STAGE1))
SOURCES_STEP10 := $(SOURCES_COMMON) $(call mk_src,$(APP_TLTM_STAGE2))
SOURCES_BTN_RESIDUAL := $(SOURCES_COMMON) $(call mk_src,$(APP_BTN_RESIDUAL))
SOURCES_TEST1  := $(SOURCES_COMMON) $(TEST_DIR)/test_hamiltonian_conservation.f90
SOURCES_TEST2  := $(SOURCES_COMMON) $(TEST_DIR)/test_action_derivatives.f90
SOURCES_TEST_ODEX := $(SOURCES_COMMON) $(TEST_DIR)/test_odex_solver.f90
SOURCES_TEST_ODEX_FOUNDATION := $(SOURCES_COMMON) $(TEST_DIR)/test_odex_foundation_contract.f90
SOURCES_TEST_ODEX_ASSIST_POLICY := $(SOURCES_COMMON) $(TEST_DIR)/test_odex_assist_policy.f90
SOURCES_TEST_ODEX_RESULT := $(SOURCES_COMMON) $(TEST_DIR)/test_odex_result_contract.f90
SOURCES_TEST_ODEX_FLOW_JAC := $(SOURCES_COMMON) $(TEST_DIR)/test_odex_flow_jacobian_contract.f90
SOURCES_TEST_ODEX_BACKEND_PACKAGE := $(call mk_src,core/utils core/lapack_fallback physics/odex_backend) $(TEST_DIR)/test_odex_backend_package_contract.f90
SOURCES_TEST_SUNDIALS_CVODE_BACKEND := $(call mk_src,core/utils core/lapack_fallback physics/odex_backend) $(TEST_DIR)/test_sundials_cvode_backend_contract.f90
SOURCES_TEST_OFFICIAL_DFOLS_PRESET := $(SOURCES_COMMON) $(TEST_DIR)/test_official_dfols_preset_contract.f90
SOURCES_TEST_TLTM_SWAP := $(SOURCES_COMMON) $(TEST_DIR)/test_tltm_swap_kernel_contract.f90
SOURCES_TEST_MT95_STATE := $(call mk_src,core/mtdefs core/mt95 core/tltm_rng) $(TEST_DIR)/test_mt95_state_contract.f90
SOURCES_TEST_TLTM_RNG := $(call mk_src,core/mtdefs core/mt95 core/tltm_rng) $(TEST_DIR)/test_tltm_rng_contract.f90
SOURCES_TEST_PERF_PROFILE := $(call mk_src,core/lapack_fallback core/utils config/runtime_env_mod core/perf_profile) $(TEST_DIR)/test_perf_profile_context_contract.f90
SOURCES_TEST_HMC_REVERSIBILITY := $(call mk_src,core/lapack_fallback core/utils config/runtime_env_mod sampler/hmc_reversibility_checks) $(TEST_DIR)/test_hmc_reversibility_context_contract.f90
SOURCES_TEST_NEWTON_FLOW_STATUS := $(call mk_src,core/mtdefs core/mt95 core/tltm_rng core/lapack_fallback core/utils core/perf_profile config/runtime_env_mod config/param_mod physics/model_autodiff physics/model_tape_ad physics/model_generated physics/model physics/odex_backend physics/solve_flow sampler/hmc_constraints) $(TEST_DIR)/test_newton_eval_flow_status_context_contract.f90
SOURCES_TEST_RETAINED_NEWTON := $(SOURCES_COMMON) $(TEST_DIR)/test_retained_core_newton_contract.f90
SOURCES_TEST_RETAINED_RATTLE_RG := $(SOURCES_COMMON) $(TEST_DIR)/test_retained_core_rattle_rg_contract.f90
SOURCES_TEST_RETAINED_QN_ROUTE := $(SOURCES_COMMON) $(TEST_DIR)/test_retained_core_qn_route_contract.f90
SOURCES_TEST_RETAINED_RG_REJECT := $(SOURCES_COMMON) $(TEST_DIR)/test_retained_core_rg_reject_identity.f90
OFFICIAL_DFOLS_C_OBJECT := $(OBJ_DIR)/src/external/official_dfols_c_bridge_$(OFFICIAL_DFOLS_C_MODE).o
SUNDIALS_CVODE_C_OBJECT := $(OBJ_DIR)/src/external/sundials_cvode_bridge_$(SUNDIALS_CVODE_C_MODE).o

# map source path -> object path
define src_to_obj
$(patsubst $(SRC_DIR)/%.f90,$(OBJ_DIR)/src/%.o,$(1))
endef

define test_to_obj
$(patsubst $(TEST_DIR)/%.f90,$(OBJ_DIR)/tests/%.o,$(1))
endef

OBJECTS_STEP2 := $(call src_to_obj,$(SOURCES_STEP2)) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_STEP3 := $(call src_to_obj,$(SOURCES_STEP3)) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_STEP9 := $(call src_to_obj,$(SOURCES_STEP9)) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_STEP10 := $(call src_to_obj,$(SOURCES_STEP10)) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_BTN_RESIDUAL := $(call src_to_obj,$(SOURCES_BTN_RESIDUAL)) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST1 := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST1))) \
                 $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST1))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST2 := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST2))) \
                 $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST2))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_ODEX := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_ODEX))) \
                     $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_ODEX))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_ODEX_FOUNDATION := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_ODEX_FOUNDATION))) \
                                $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_ODEX_FOUNDATION))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_ODEX_ASSIST_POLICY := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_ODEX_ASSIST_POLICY))) \
                                   $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_ODEX_ASSIST_POLICY))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_ODEX_RESULT := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_ODEX_RESULT))) \
                            $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_ODEX_RESULT))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_ODEX_FLOW_JAC := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_ODEX_FLOW_JAC))) \
                              $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_ODEX_FLOW_JAC))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_ODEX_BACKEND_PACKAGE := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_ODEX_BACKEND_PACKAGE))) \
                                     $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_ODEX_BACKEND_PACKAGE)))
OBJECTS_TEST_SUNDIALS_CVODE_BACKEND := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_SUNDIALS_CVODE_BACKEND))) \
                                       $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_SUNDIALS_CVODE_BACKEND)))
OBJECTS_TEST_OFFICIAL_DFOLS_PRESET := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_OFFICIAL_DFOLS_PRESET))) \
                                      $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_OFFICIAL_DFOLS_PRESET))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_TLTM_SWAP := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_TLTM_SWAP))) \
                          $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_TLTM_SWAP))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_MT95_STATE := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_MT95_STATE))) \
                           $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_MT95_STATE)))
OBJECTS_TEST_TLTM_RNG := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_TLTM_RNG))) \
                         $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_TLTM_RNG)))
OBJECTS_TEST_PERF_PROFILE := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_PERF_PROFILE))) \
                             $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_PERF_PROFILE)))
OBJECTS_TEST_HMC_REVERSIBILITY := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_HMC_REVERSIBILITY))) \
                                  $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_HMC_REVERSIBILITY)))
OBJECTS_TEST_NEWTON_FLOW_STATUS := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_NEWTON_FLOW_STATUS))) \
                                   $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_NEWTON_FLOW_STATUS)))
OBJECTS_TEST_RETAINED_NEWTON := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_RETAINED_NEWTON))) \
                                $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_RETAINED_NEWTON))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_RETAINED_RATTLE_RG := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_RETAINED_RATTLE_RG))) \
                                   $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_RETAINED_RATTLE_RG))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_RETAINED_QN_ROUTE := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_RETAINED_QN_ROUTE))) \
                                  $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_RETAINED_QN_ROUTE))) $(OFFICIAL_DFOLS_C_OBJECT)
OBJECTS_TEST_RETAINED_RG_REJECT := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_RETAINED_RG_REJECT))) \
                                   $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_RETAINED_RG_REJECT))) $(OFFICIAL_DFOLS_C_OBJECT)

OBJECTS_STEP2 += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_STEP3 += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_STEP9 += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_STEP10 += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_BTN_RESIDUAL += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST1 += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST2 += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_ODEX += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_ODEX_FOUNDATION += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_ODEX_ASSIST_POLICY += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_ODEX_RESULT += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_ODEX_FLOW_JAC += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_ODEX_BACKEND_PACKAGE += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_SUNDIALS_CVODE_BACKEND += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_OFFICIAL_DFOLS_PRESET += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_TLTM_SWAP += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_MT95_STATE += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_TLTM_RNG += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_PERF_PROFILE += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_HMC_REVERSIBILITY += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_NEWTON_FLOW_STATUS += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_RETAINED_NEWTON += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_RETAINED_RATTLE_RG += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_RETAINED_QN_ROUTE += $(SUNDIALS_CVODE_C_OBJECT)
OBJECTS_TEST_RETAINED_RG_REJECT += $(SUNDIALS_CVODE_C_OBJECT)

SOURCES_DEP := $(sort $(SOURCES_STEP2) $(SOURCES_STEP3) $(SOURCES_STEP9) $(SOURCES_BTN_RESIDUAL) \
                $(SOURCES_STEP10) $(SOURCES_TEST1) $(SOURCES_TEST2) $(SOURCES_TEST_ODEX) \
                $(SOURCES_TEST_ODEX_FOUNDATION) $(SOURCES_TEST_ODEX_ASSIST_POLICY) \
                $(SOURCES_TEST_ODEX_RESULT) $(SOURCES_TEST_ODEX_FLOW_JAC) \
                $(SOURCES_TEST_ODEX_BACKEND_PACKAGE) $(SOURCES_TEST_SUNDIALS_CVODE_BACKEND) \
                $(SOURCES_TEST_OFFICIAL_DFOLS_PRESET) $(SOURCES_TEST_TLTM_SWAP) $(SOURCES_TEST_MT95_STATE) \
                $(SOURCES_TEST_TLTM_RNG) \
                $(SOURCES_TEST_PERF_PROFILE) $(SOURCES_TEST_HMC_REVERSIBILITY) $(SOURCES_TEST_NEWTON_FLOW_STATUS) \
                $(SOURCES_TEST_RETAINED_NEWTON) $(SOURCES_TEST_RETAINED_RATTLE_RG) \
                $(SOURCES_TEST_RETAINED_QN_ROUTE) $(SOURCES_TEST_RETAINED_RG_REJECT))

$(DEP_OUT): $(SOURCES_DEP) $(DEP_SCRIPT) | $(MOD_DIR)
	$(PYTHON) $(DEP_SCRIPT) --root .. --obj-dir $(OBJ_DIR) > $@

SKIP_DEP_GOALS := clean clean_outputs veryclean help
ifneq ($(filter-out $(SKIP_DEP_GOALS),$(MAKECMDGOALS)),)
-include $(DEP_OUT)
else ifeq ($(strip $(MAKECMDGOALS)),)
-include $(DEP_OUT)
endif

# executables
BINARIES     = generate_markov_chain evaluate_expectations \
               run_tltm_stage1 run_tltm_stage2 \
               evaluate_btn_residual_case \
               test_program test_program2 test_odex_solver test_odex_foundation_contract \
               test_odex_assist_policy test_odex_result_contract test_odex_flow_jacobian_contract \
               test_odex_backend_package_contract test_sundials_cvode_backend_contract \
               test_official_dfols_preset_contract test_tltm_swap_kernel_contract \
               test_mt95_state_contract test_tltm_rng_contract \
               test_perf_profile_context_contract test_hmc_reversibility_context_contract \
               test_newton_eval_flow_status_context_contract \
               test_retained_core_newton_contract test_retained_core_rattle_rg_contract \
               test_retained_core_qn_route_contract test_retained_core_rg_reject_identity
EXECUTABLES  = $(addprefix $(BIN_DIR)/,$(BINARIES))

###############################################################################
#  build targets
###############################################################################
.DEFAULT_GOAL := all
override FFLAGS := $(FFLAGS_OPT) $(FFLAGS_INC)

.PHONY: all fast help chain expect tltm_stage1 test_tltm_stage1 tltm_stage2 tltm_stage2_ref stage3_1 stage3_3 test_tltm_stage2 test1 test2 test_odex_solver test_odex_foundation_contract test_odex_assist_policy test_odex_result_contract test_odex_flow_jacobian_contract test_odex_backend_package_contract test_sundials_cvode_backend_contract test_official_dfols_preset_contract evaluate_btn_residual_case test_tltm_swap_kernel_contract test_mt95_state_contract test_tltm_rng_contract test_perf_profile_context_contract test_hmc_reversibility_context_contract test_newton_eval_flow_status_context_contract test_retained_core_newton_contract test_retained_core_rattle_rg_contract test_retained_core_qn_route_contract test_retained_core_rg_reject_identity modernization_guardrails f14_pre_redo_complete_gate official_line_kernel_correctness_gate post_b_rng_reference_anchor stage2_rng_v2_anchor script_evidence_audit_gate FORCE \
        test1_fb_on test1_fb_off test2_fb_on test2_fb_off test_fb_matrix \
        prepare_outputs clean_outputs clean veryclean
all: regen_model_derivatives $(EXECUTABLES)

fast: override FFLAGS := $(FFLAGS_FAST) $(FFLAGS_INC)
fast: override LDFLAGS := $(LDFLAGS_FAST)
fast: regen_model_derivatives $(EXECUTABLES)

# compile rules
$(OBJ_DIR)/src/%.o: $(SRC_DIR)/%.f90 | $(MOD_DIR)
	@mkdir -p $(dir $@)
	$(FC) $(FFLAGS) -c $< -o $@ $(MOD_FLAG)

$(OBJ_DIR)/tests/%.o: $(TEST_DIR)/%.f90 | $(MOD_DIR)
	@mkdir -p $(dir $@)
	$(FC) $(FFLAGS) -c $< -o $@ $(MOD_FLAG)

$(OBJ_DIR)/src/external/official_dfols_c_bridge_enabled.o: $(SRC_DIR)/external/official_dfols_c_bridge.c | $(MOD_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(PYTHON_EMBED_CFLAGS) -DTLTM_ENABLE_OFFICIAL_DFOLS -c $< -o $@

$(OBJ_DIR)/src/external/official_dfols_c_bridge_stub.o: $(SRC_DIR)/external/official_dfols_c_bridge.c | $(MOD_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/src/external/sundials_cvode_bridge_enabled.o: $(SRC_DIR)/external/sundials_cvode_bridge.c | $(MOD_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(SUNDIALS_CFLAGS) -DTLTM_ENABLE_SUNDIALS_CVODE -c $< -o $@

$(OBJ_DIR)/src/external/sundials_cvode_bridge_stub.o: $(SRC_DIR)/external/sundials_cvode_bridge.c | $(MOD_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OFFICIAL_DFOLS_MODE_STAMP): FORCE | $(MOD_DIR)
	@mode="$(OFFICIAL_DFOLS_C_MODE)"; \
	if [ ! -f "$@" ] || [ "$$(cat "$@")" != "$$mode" ]; then \
		echo "$$mode" > "$@"; \
	fi

# link rules
$(BIN_DIR)/generate_markov_chain: $(OBJECTS_STEP2) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/evaluate_expectations: $(OBJECTS_STEP3) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/run_tltm_stage1: $(OBJECTS_STEP9) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/run_tltm_stage2: $(OBJECTS_STEP10) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/evaluate_btn_residual_case: $(OBJECTS_BTN_RESIDUAL) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_program: $(OBJECTS_TEST1) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_program2: $(OBJECTS_TEST2) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_odex_solver: $(OBJECTS_TEST_ODEX) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_odex_foundation_contract: $(OBJECTS_TEST_ODEX_FOUNDATION) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_odex_assist_policy: $(OBJECTS_TEST_ODEX_ASSIST_POLICY) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_odex_result_contract: $(OBJECTS_TEST_ODEX_RESULT) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_odex_flow_jacobian_contract: $(OBJECTS_TEST_ODEX_FLOW_JAC) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_odex_backend_package_contract: $(OBJECTS_TEST_ODEX_BACKEND_PACKAGE) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_sundials_cvode_backend_contract: $(OBJECTS_TEST_SUNDIALS_CVODE_BACKEND) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_official_dfols_preset_contract: $(OBJECTS_TEST_OFFICIAL_DFOLS_PRESET) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_tltm_swap_kernel_contract: $(OBJECTS_TEST_TLTM_SWAP) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_mt95_state_contract: $(OBJECTS_TEST_MT95_STATE) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_tltm_rng_contract: $(OBJECTS_TEST_TLTM_RNG) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_perf_profile_context_contract: $(OBJECTS_TEST_PERF_PROFILE) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_hmc_reversibility_context_contract: $(OBJECTS_TEST_HMC_REVERSIBILITY) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_newton_eval_flow_status_context_contract: $(OBJECTS_TEST_NEWTON_FLOW_STATUS) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_retained_core_newton_contract: $(OBJECTS_TEST_RETAINED_NEWTON) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_retained_core_rattle_rg_contract: $(OBJECTS_TEST_RETAINED_RATTLE_RG) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_retained_core_qn_route_contract: $(OBJECTS_TEST_RETAINED_QN_ROUTE) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

$(BIN_DIR)/test_retained_core_rg_reject_identity: $(OBJECTS_TEST_RETAINED_RG_REJECT) $(OFFICIAL_DFOLS_MODE_STAMP) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $(filter %.o,$^) $(LDLIBS)

# create build directories if missing
$(MOD_DIR) $(BIN_DIR) $(OUT_DIR) $(OUT_PROD_DIR) $(OUT_TEST_DIR) $(OUT_TEST1_DIR) $(OUT_LOG_DIR):
	mkdir -p $@

prepare_outputs: $(OUT_DIR) $(OUT_PROD_DIR) $(OUT_TEST_DIR) $(OUT_TEST1_DIR) $(OUT_LOG_DIR)
PARAM_FILE ?= ../data/parameters.dat

help:
	@echo "Build targets:"
	@echo "  make all      - build all executables (default)"
	@echo "  make fast     - build with debug-friendly fast flags"
	@echo "  make OMP=1    - enable OpenMP (Intel path also enables parallel MKL)"
	@echo "  make FC=<compiler> PYTHON=<python> - override auto-detected toolchain"
	@echo "  make ENABLE_OFFICIAL_DFOLS=1 - build the embedded official DFO-LS backend (default)"
	@echo "  make ENABLE_OFFICIAL_DFOLS=0 - build a stub bridge for package-off route tests"
	@echo "  make ENABLE_SUNDIALS_CVODE=1 SUNDIALS_PREFIX=<prefix> - build the disabled-by-default SUNDIALS CVODE ODE backend"
	@echo "  make GNU_LINALG_LIBS='-lopenblas'   - optionally link external BLAS/LAPACK on GNU"
	@echo "  make regen_model_derivatives - regenerate src/physics/model_generated.f90 (GEN_BACKEND=auto|symbolic|tape|st_auto|st_tapenade|st_enzyme; default=auto)"
	@echo "    uses ST_TAPENADE_CMD if set; otherwise auto-detects ~/tools/tapenade-3.16-v2/bin/tapenade"
	@echo ""
	@echo "Run targets:"
	@echo "  make chain    - run generate_markov_chain (outputs -> $(OUT_PROD_DIR), log -> $(OUT_LOG_DIR))"
	@echo "  make expect   - run evaluate_expectations (analysis -> $(OUT_PROD_DIR), log -> $(OUT_LOG_DIR))"
	@echo "  make tltm_stage1 - run stage-1 multi-replica baseline (no swap)"
	@echo "  make test_tltm_stage1 - smoke run with max flow=0.3, L=2, nstep=20"
	@echo "  make tltm_stage2 - run stage-2 multi-replica baseline with adjacent swap"
	@echo "  make tltm_stage2_ref - run stage-2 with frozen stage-2.5 reference ladder"
	@echo "  make stage3_1 - run matched-control fallback OFF vs ON comparison on frozen ladder"
	@echo "  make stage3_3 - run multiseed matched-control summary (fallback OFF vs ON, parallel via STAGE3_3_JOBS)"
	@echo "  make test_tltm_stage2 - smoke run with swap and max flow=0.3, L=2, nstep=20"
	@echo "  make test1    - run Hamiltonian conservation test (artifacts -> $(OUT_TEST1_DIR))"
	@echo "  make test2    - run action derivative test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_odex_solver - run analytic ODEX/status smoke test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_odex_foundation_contract - run ODEX foundation contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_odex_assist_policy - run ODEX assist deletion policy gate (log -> $(OUT_LOG_DIR))"
	@echo "  make test_odex_result_contract - run ODEX result/workspace/status contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_odex_flow_jacobian_contract - run ODEX flow/Jacobian deterministic contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_odex_backend_package_contract - run standalone ODEX backend package contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_sundials_cvode_backend_contract - run SUNDIALS CVODE backend contract test, skipping if the bridge is stubbed (log -> $(OUT_LOG_DIR))"
	@echo "  make test_official_dfols_preset_contract - run official DFO-LS backend/preset policy contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make evaluate_btn_residual_case - build offline BTN residual bridge for external DFO-LS comparison"
	@echo "  make test_tltm_swap_kernel_contract - run TLTM swap-kernel contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_mt95_state_contract - run explicit mt95 RNG-state contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_tltm_rng_contract - run counter-based TLTM RNG v2 contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_perf_profile_context_contract - run explicit profiler-context contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_hmc_reversibility_context_contract - run HMC reversibility/progress context contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make test_newton_eval_flow_status_context_contract - run Newton eval-flow status context contract test (log -> $(OUT_LOG_DIR))"
	@echo "  make modernization_guardrails - run M4 local compile/build/audit/smoke guardrails"
	@echo "  make f14_pre_redo_complete_gate - run complete F3/F4/F7/F8 pre-redo gate"
	@echo "  make post_b_rng_reference_anchor - run post-B per-replica RNG reference anchor"
	@echo "  make stage2_rng_v2_anchor - run Stage2 kernel RNG v2 deterministic anchor"
	@echo "  make script_evidence_audit_gate - run CV-005 script/evidence audit coverage gate"
	@echo "  make test1_fb_on / test1_fb_off - run test1 with fallback forced on/off"
	@echo "  make test2_fb_on / test2_fb_off - run test2 with fallback forced on/off"
	@echo "  make test_fb_matrix - run (test1,test2) x (fallback on,off)"
	@echo "  make menu     - interactive menu (alias: mn)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean"
	@echo "  make clean_outputs"
	@echo "  make veryclean"

chain: $(BIN_DIR)/generate_markov_chain prepare_outputs
	@set -o pipefail; $(BIN_DIR)/generate_markov_chain 2>&1 | tee $(OUT_LOG_DIR)/generate_markov_chain.log

expect: $(BIN_DIR)/evaluate_expectations prepare_outputs
	@set -o pipefail; $(BIN_DIR)/evaluate_expectations 2>&1 | tee $(OUT_LOG_DIR)/evaluate_expectations.log

evaluate_btn_residual_case: $(BIN_DIR)/evaluate_btn_residual_case
	@echo "[DONE] Built $(BIN_DIR)/evaluate_btn_residual_case"

TLTM_STAGE1_NUM_REPLICAS ?= 2
TLTM_STAGE1_CYCLES ?= 20
TLTM_STAGE1_MAX_FLOW_TIME ?= 0.3
TLTM_STAGE1_SUMMARY_FILE ?= $(OUT_TEST_DIR)/tltm_stage1_summary.dat
tltm_stage1: $(BIN_DIR)/run_tltm_stage1 prepare_outputs
	@set -o pipefail; \
	TLTM_STAGE1_NUM_REPLICAS="$(TLTM_STAGE1_NUM_REPLICAS)" \
	TLTM_STAGE1_CYCLES="$(TLTM_STAGE1_CYCLES)" \
	TLTM_STAGE1_MAX_FLOW_TIME="$(TLTM_STAGE1_MAX_FLOW_TIME)" \
	TLTM_STAGE1_SUMMARY_FILE="$(TLTM_STAGE1_SUMMARY_FILE)" \
	$(BIN_DIR)/run_tltm_stage1 2>&1 | tee $(OUT_LOG_DIR)/tltm_stage1.log

test_tltm_stage1: tltm_stage1
	@echo "[DONE] TLTM stage-1 smoke complete"

TLTM_STAGE2_NUM_REPLICAS ?= 4
TLTM_STAGE2_CYCLES ?= 20
TLTM_STAGE2_MAX_FLOW_TIME ?= 0.3
TLTM_STAGE2_SWAP_ENABLED ?= 1
TLTM_STAGE2_SUMMARY_FILE ?= $(OUT_TEST_DIR)/tltm_stage2_summary.dat
TLTM_STAGE2_LABEL_TRACE_FILE ?= $(OUT_TEST_DIR)/tltm_stage2_label_trace.dat
tltm_stage2: $(BIN_DIR)/run_tltm_stage2 prepare_outputs
	@set -o pipefail; \
	TLTM_STAGE2_NUM_REPLICAS="$(TLTM_STAGE2_NUM_REPLICAS)" \
	TLTM_STAGE2_CYCLES="$(TLTM_STAGE2_CYCLES)" \
	TLTM_STAGE2_MAX_FLOW_TIME="$(TLTM_STAGE2_MAX_FLOW_TIME)" \
	TLTM_STAGE2_SWAP_ENABLED="$(TLTM_STAGE2_SWAP_ENABLED)" \
	TLTM_STAGE2_SUMMARY_FILE="$(TLTM_STAGE2_SUMMARY_FILE)" \
	TLTM_STAGE2_LABEL_TRACE_FILE="$(TLTM_STAGE2_LABEL_TRACE_FILE)" \
	$(BIN_DIR)/run_tltm_stage2 2>&1 | tee $(OUT_LOG_DIR)/tltm_stage2.log

tltm_stage2_ref: TLTM_STAGE2_NUM_REPLICAS=5
tltm_stage2_ref: TLTM_STAGE2_FLOW_TIME_LADDER=0,0.05,0.1,0.2,0.3
tltm_stage2_ref: TLTM_STAGE2_SUMMARY_FILE=$(OUT_TEST_DIR)/tltm_stage2_ref_summary.dat
tltm_stage2_ref: TLTM_STAGE2_LABEL_TRACE_FILE=$(OUT_TEST_DIR)/tltm_stage2_ref_label_trace.dat
tltm_stage2_ref: $(BIN_DIR)/run_tltm_stage2 prepare_outputs
	@set -o pipefail; \
	TLTM_STAGE2_NUM_REPLICAS="$(TLTM_STAGE2_NUM_REPLICAS)" \
	TLTM_STAGE2_FLOW_TIME_LADDER="$(TLTM_STAGE2_FLOW_TIME_LADDER)" \
	TLTM_STAGE2_CYCLES="$(TLTM_STAGE2_CYCLES)" \
	TLTM_STAGE2_LOCAL_UPDATES="$(TLTM_STAGE2_LOCAL_UPDATES)" \
	TLTM_STAGE2_MAX_FLOW_TIME="$(TLTM_STAGE2_MAX_FLOW_TIME)" \
	TLTM_STAGE2_SWAP_ENABLED="$(TLTM_STAGE2_SWAP_ENABLED)" \
	TLTM_STAGE2_SUMMARY_FILE="$(TLTM_STAGE2_SUMMARY_FILE)" \
	TLTM_STAGE2_LABEL_TRACE_FILE="$(TLTM_STAGE2_LABEL_TRACE_FILE)" \
	$(BIN_DIR)/run_tltm_stage2 2>&1 | tee $(OUT_LOG_DIR)/tltm_stage2_ref.log

STAGE3_1_CYCLES ?= 120
STAGE3_1_SEED ?= 20260421
stage3_1: prepare_outputs
	@set -o pipefail; \
	$(PYTHON) ../scripts/run_stage3_1_compare.py --repo-root .. --cycles $(STAGE3_1_CYCLES) --seed $(STAGE3_1_SEED) \
	2>&1 | tee $(OUT_LOG_DIR)/stage3_1_compare.log

STAGE3_3_CONFIG ?= docs/stage_3_3_todo.json
STAGE3_3_MAX_SEEDS ?= 0
STAGE3_3_JOBS ?= 2
STAGE3_3_STAGE2_THREADS ?= 1
STAGE3_3_EVAL_THREADS ?= 1
STAGE3_3_SCHEDULE ?= paired
STAGE3_3_PAIR_ORDER ?= alternating
STAGE3_3_ALLOW_OVERSUBSCRIBE ?= 0
stage3_3: prepare_outputs
	@set -o pipefail; \
	extra_flags=""; \
	if [ "$(STAGE3_3_ALLOW_OVERSUBSCRIBE)" = "1" ]; then extra_flags="$$extra_flags --allow-oversubscribe"; fi; \
	$(PYTHON) ../scripts/run_stage3_3_multiseed.py --repo-root .. --config $(STAGE3_3_CONFIG) --max-seeds $(STAGE3_3_MAX_SEEDS) --jobs $(STAGE3_3_JOBS) \
	--stage2-threads $(STAGE3_3_STAGE2_THREADS) --eval-threads $(STAGE3_3_EVAL_THREADS) \
	--schedule $(STAGE3_3_SCHEDULE) --pair-order $(STAGE3_3_PAIR_ORDER) $$extra_flags \
	2>&1 | tee $(OUT_LOG_DIR)/stage3_3_multiseed.log

test_tltm_stage2: tltm_stage2
	@echo "[DONE] TLTM stage-2 smoke complete"

M4_GUARDRAIL_FC ?= $(FC)
M4_GUARDRAIL_LDFLAGS ?= $(LDFLAGS)
modernization_guardrails: prepare_outputs
	@set -o pipefail; \
	$(PYTHON) ../scripts/run_m4_guardrails.py --repo-root .. --fc "$(M4_GUARDRAIL_FC)" --ldflags "$(M4_GUARDRAIL_LDFLAGS)" \
	2>&1 | tee $(OUT_LOG_DIR)/modernization_guardrails.log

F14_PREREDO_FC ?= $(FC)
F14_PREREDO_LDFLAGS ?= $(LDFLAGS)
f14_pre_redo_complete_gate: prepare_outputs
	@set -o pipefail; \
	$(PYTHON) ../codex/workspaces/fortran_modernization/tasks/scripts/f14_complete_pre_redo_gate.py --repo-root .. --fc "$(F14_PREREDO_FC)" --ldflags "$(F14_PREREDO_LDFLAGS)" \
	2>&1 | tee $(OUT_LOG_DIR)/f14_pre_redo_complete_gate.log

OFFICIAL_LINE_KERNEL_FC ?= $(FC)
OFFICIAL_LINE_KERNEL_LDFLAGS ?= $(LDFLAGS)
official_line_kernel_correctness_gate: prepare_outputs
	@set -o pipefail; \
	$(PYTHON) ../codex/workspaces/fortran_modernization/tasks/scripts/official_line_kernel_correctness_gate.py --repo-root .. --fc "$(OFFICIAL_LINE_KERNEL_FC)" --ldflags "$(OFFICIAL_LINE_KERNEL_LDFLAGS)" \
	2>&1 | tee $(OUT_LOG_DIR)/official_line_kernel_correctness_gate.log

POST_B_RNG_FC ?= $(FC)
POST_B_RNG_LDFLAGS ?= $(LDFLAGS)
post_b_rng_reference_anchor: prepare_outputs
	@set -o pipefail; \
	$(PYTHON) ../codex/workspaces/fortran_modernization/tasks/scripts/post_b_rng_reference_anchor.py --repo-root .. --fc "$(POST_B_RNG_FC)" --ldflags "$(POST_B_RNG_LDFLAGS)" \
	2>&1 | tee $(OUT_LOG_DIR)/post_b_rng_reference_anchor.log

STAGE2_RNG_V2_FC ?= $(FC)
STAGE2_RNG_V2_LDFLAGS ?= $(LDFLAGS)
stage2_rng_v2_anchor: prepare_outputs
	@set -o pipefail; \
	$(PYTHON) ../codex/workspaces/fortran_modernization/tasks/scripts/stage2_rng_v2_anchor.py --repo-root .. --fc "$(STAGE2_RNG_V2_FC)" --ldflags "$(STAGE2_RNG_V2_LDFLAGS)" \
	2>&1 | tee $(OUT_LOG_DIR)/stage2_rng_v2_anchor.log

script_evidence_audit_gate: prepare_outputs
	@set -o pipefail; \
	$(PYTHON) ../codex/workspaces/fortran_modernization/tasks/scripts/validate_script_evidence_audit.py --repo-root .. \
	2>&1 | tee $(OUT_LOG_DIR)/script_evidence_audit_gate.log

test1: $(BIN_DIR)/test_program prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_program 2>&1 | tee $(OUT_LOG_DIR)/test_hamiltonian_conservation.log
	@for f in hamiltonian_conservation.dat hamiltonian_conservation_loglog.gp hamiltonian_conservation_loglog.png; do \
		if [ -f "$$f" ]; then mv -f "$$f" "$(OUT_TEST1_DIR)/"; fi; \
	done
	@echo "[DONE] test1 artifacts in $(OUT_TEST1_DIR)"

test2: $(BIN_DIR)/test_program2 prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_program2 2>&1 | tee $(OUT_LOG_DIR)/test_action_derivatives.log

test_odex_solver: $(BIN_DIR)/test_odex_solver prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_odex_solver 2>&1 | tee $(OUT_LOG_DIR)/test_odex_solver.log

test_odex_foundation_contract: $(BIN_DIR)/test_odex_foundation_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_odex_foundation_contract 2>&1 | tee $(OUT_LOG_DIR)/test_odex_foundation_contract.log

test_odex_assist_policy: $(BIN_DIR)/test_odex_assist_policy prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_odex_assist_policy default 2>&1 | tee $(OUT_LOG_DIR)/test_odex_assist_policy_default_deleted.log
	@set -o pipefail; INTODE_SOLVER_ASSIST_POLICY=off $(BIN_DIR)/test_odex_assist_policy env_off 2>&1 | tee $(OUT_LOG_DIR)/test_odex_assist_policy_policy_off.log
	@set -o pipefail; INTODE_SOLVER_ASSIST_POLICY=all_navigation_diagnostic $(BIN_DIR)/test_odex_assist_policy env_policy_ignored 2>&1 | tee $(OUT_LOG_DIR)/test_odex_assist_policy_policy_ignored.log
	@set -o pipefail; INTODE_SOLVER_ASSIST_ENABLED=0 $(BIN_DIR)/test_odex_assist_policy legacy_disabled_ignored 2>&1 | tee $(OUT_LOG_DIR)/test_odex_assist_policy_legacy_disabled_ignored.log
	@set -o pipefail; INTODE_SOLVER_ASSIST_ENABLED=1 $(BIN_DIR)/test_odex_assist_policy legacy_enabled_ignored 2>&1 | tee $(OUT_LOG_DIR)/test_odex_assist_policy_legacy_enabled_ignored.log

test_odex_result_contract: $(BIN_DIR)/test_odex_result_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_odex_result_contract 2>&1 | tee $(OUT_LOG_DIR)/test_odex_result_contract.log

test_odex_flow_jacobian_contract: $(BIN_DIR)/test_odex_flow_jacobian_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_odex_flow_jacobian_contract 2>&1 | tee $(OUT_LOG_DIR)/test_odex_flow_jacobian_contract.log

test_odex_backend_package_contract: $(BIN_DIR)/test_odex_backend_package_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_odex_backend_package_contract 2>&1 | tee $(OUT_LOG_DIR)/test_odex_backend_package_contract.log

test_sundials_cvode_backend_contract: $(BIN_DIR)/test_sundials_cvode_backend_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_sundials_cvode_backend_contract 2>&1 | tee $(OUT_LOG_DIR)/test_sundials_cvode_backend_contract.log

test_official_dfols_preset_contract: $(BIN_DIR)/test_official_dfols_preset_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_official_dfols_preset_contract 2>&1 | tee $(OUT_LOG_DIR)/test_official_dfols_preset_contract.log

test_tltm_swap_kernel_contract: $(BIN_DIR)/test_tltm_swap_kernel_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_tltm_swap_kernel_contract 2>&1 | tee $(OUT_LOG_DIR)/test_tltm_swap_kernel_contract.log

test_mt95_state_contract: $(BIN_DIR)/test_mt95_state_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_mt95_state_contract 2>&1 | tee $(OUT_LOG_DIR)/test_mt95_state_contract.log

test_tltm_rng_contract: $(BIN_DIR)/test_tltm_rng_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_tltm_rng_contract 2>&1 | tee $(OUT_LOG_DIR)/test_tltm_rng_contract.log

test_perf_profile_context_contract: $(BIN_DIR)/test_perf_profile_context_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_perf_profile_context_contract 2>&1 | tee $(OUT_LOG_DIR)/test_perf_profile_context_contract.log

test_hmc_reversibility_context_contract: $(BIN_DIR)/test_hmc_reversibility_context_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_hmc_reversibility_context_contract 2>&1 | tee $(OUT_LOG_DIR)/test_hmc_reversibility_context_contract.log

test_newton_eval_flow_status_context_contract: $(BIN_DIR)/test_newton_eval_flow_status_context_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_newton_eval_flow_status_context_contract 2>&1 | tee $(OUT_LOG_DIR)/test_newton_eval_flow_status_context_contract.log

test_retained_core_newton_contract: $(BIN_DIR)/test_retained_core_newton_contract prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_retained_core_newton_contract 2>&1 | tee $(OUT_LOG_DIR)/test_retained_core_newton_contract.log

test_retained_core_rattle_rg_contract: $(BIN_DIR)/test_retained_core_rattle_rg_contract prepare_outputs
	@set -o pipefail; QN_REVERSE_GATE_ENABLED=1 $(BIN_DIR)/test_retained_core_rattle_rg_contract 2>&1 | tee $(OUT_LOG_DIR)/test_retained_core_rattle_rg_contract.log

test_retained_core_qn_route_contract: $(BIN_DIR)/test_retained_core_qn_route_contract prepare_outputs
	@set -o pipefail; QN_SOLVER_BACKEND=official_dfols QN_OFFICIAL_DFOLS_PRESET=stable_gate77 $(RETAINED_QN_EXPECT_PACKAGE_SUCCESS) $(BIN_DIR)/test_retained_core_qn_route_contract 2>&1 | tee $(OUT_LOG_DIR)/test_retained_core_qn_route_contract.log

test_retained_core_rg_reject_identity: $(BIN_DIR)/test_retained_core_rg_reject_identity prepare_outputs
	@set -o pipefail; QN_REVERSE_GATE_ENABLED=1 QN_REVERSE_GATE_TOL=1e-20 $(BIN_DIR)/test_retained_core_rg_reject_identity 2>&1 | tee $(OUT_LOG_DIR)/test_retained_core_rg_reject_identity.log

test1_fb_on: $(BIN_DIR)/test_program prepare_outputs
	@set -e; \
	param_file="$(PARAM_FILE)"; \
	backup_file="$$param_file.bak.make.$$$$"; \
	cp "$$param_file" "$$backup_file"; \
	cleanup(){ mv -f "$$backup_file" "$$param_file"; }; \
	trap cleanup EXIT INT TERM; \
	awk -v v=true 'BEGIN{done=0} { if ($$0 ~ /^[[:space:]]*enable_quasi_fallback[[:space:]]*=/) { print "enable_quasi_fallback = " v; done=1; } else { print $$0; } } END{ if (!done) print "enable_quasi_fallback = " v; }' "$$backup_file" > "$$param_file"; \
	set -o pipefail; $(BIN_DIR)/test_program 2>&1 | tee $(OUT_LOG_DIR)/test_hamiltonian_conservation_fb_on.log; \
	for f in hamiltonian_conservation.dat hamiltonian_conservation_loglog.gp hamiltonian_conservation_loglog.png; do \
		if [ -f "$$f" ]; then mv -f "$$f" "$(OUT_TEST1_DIR)/"; fi; \
	done; \
	echo "[DONE] test1 fallback=on artifacts in $(OUT_TEST1_DIR)"

test1_fb_off: $(BIN_DIR)/test_program prepare_outputs
	@set -e; \
	param_file="$(PARAM_FILE)"; \
	backup_file="$$param_file.bak.make.$$$$"; \
	cp "$$param_file" "$$backup_file"; \
	cleanup(){ mv -f "$$backup_file" "$$param_file"; }; \
	trap cleanup EXIT INT TERM; \
	awk -v v=false 'BEGIN{done=0} { if ($$0 ~ /^[[:space:]]*enable_quasi_fallback[[:space:]]*=/) { print "enable_quasi_fallback = " v; done=1; } else { print $$0; } } END{ if (!done) print "enable_quasi_fallback = " v; }' "$$backup_file" > "$$param_file"; \
	set -o pipefail; $(BIN_DIR)/test_program 2>&1 | tee $(OUT_LOG_DIR)/test_hamiltonian_conservation_fb_off.log; \
	for f in hamiltonian_conservation.dat hamiltonian_conservation_loglog.gp hamiltonian_conservation_loglog.png; do \
		if [ -f "$$f" ]; then mv -f "$$f" "$(OUT_TEST1_DIR)/"; fi; \
	done; \
	echo "[DONE] test1 fallback=off artifacts in $(OUT_TEST1_DIR)"

test2_fb_on: $(BIN_DIR)/test_program2 prepare_outputs
	@set -e; \
	param_file="$(PARAM_FILE)"; \
	backup_file="$$param_file.bak.make.$$$$"; \
	cp "$$param_file" "$$backup_file"; \
	cleanup(){ mv -f "$$backup_file" "$$param_file"; }; \
	trap cleanup EXIT INT TERM; \
	awk -v v=true 'BEGIN{done=0} { if ($$0 ~ /^[[:space:]]*enable_quasi_fallback[[:space:]]*=/) { print "enable_quasi_fallback = " v; done=1; } else { print $$0; } } END{ if (!done) print "enable_quasi_fallback = " v; }' "$$backup_file" > "$$param_file"; \
	set -o pipefail; $(BIN_DIR)/test_program2 2>&1 | tee $(OUT_LOG_DIR)/test_action_derivatives_fb_on.log; \
	echo "[DONE] test2 fallback=on complete"

test2_fb_off: $(BIN_DIR)/test_program2 prepare_outputs
	@set -e; \
	param_file="$(PARAM_FILE)"; \
	backup_file="$$param_file.bak.make.$$$$"; \
	cp "$$param_file" "$$backup_file"; \
	cleanup(){ mv -f "$$backup_file" "$$param_file"; }; \
	trap cleanup EXIT INT TERM; \
	awk -v v=false 'BEGIN{done=0} { if ($$0 ~ /^[[:space:]]*enable_quasi_fallback[[:space:]]*=/) { print "enable_quasi_fallback = " v; done=1; } else { print $$0; } } END{ if (!done) print "enable_quasi_fallback = " v; }' "$$backup_file" > "$$param_file"; \
	set -o pipefail; $(BIN_DIR)/test_program2 2>&1 | tee $(OUT_LOG_DIR)/test_action_derivatives_fb_off.log; \
	echo "[DONE] test2 fallback=off complete"

test_fb_matrix: test1_fb_on test1_fb_off test2_fb_on test2_fb_off
	@echo "[DONE] test fallback matrix complete"

regen_model_derivatives: $(GEN_OUT)

$(GEN_OUT): $(GEN_SCRIPT) $(GEN_BODY)
	$(PYTHON) $(GEN_SCRIPT) --body $(GEN_BODY) --output $(GEN_OUT) --backend $(GEN_BACKEND)

###############################################################################
#  interactive menu
###############################################################################
define banner
	@printf "\n\033[1;36m%-60s\033[0m\n" "==============================="
	@printf "\033[1;36m%-60s\033[0m\n" "$(1)"
	@printf "\033[1;36m%-60s\033[0m\n\n" "==============================="
endef

menu mn: all
	$(call banner,HMC Simulation Steps)
	@echo "1. Generate Markov Chain"
	@echo "2. Evaluate Expectations"
	@echo "3. Run Test Program 1: Hamiltonian Conservation"
	@echo "4. Run Test Program 2: Action Derivatives"
	@echo "5. Exit"
	@echo "-----------------------------------------------"
	@read -p "Enter your choice: " choice; \
	case $$choice in \
	  1)  $(MAKE) chain ;; \
	  2)  $(MAKE) expect ;; \
	  3)  $(MAKE) test1 ;; \
	  4)  $(MAKE) test2 ;; \
	  5)  echo "Exiting. Goodbye!" ;; \
	  *)  echo "Invalid option." ;; \
	esac

###############################################################################
#  housekeeping
###############################################################################
clean:
	$(RM) -r $(OBJ_DIR) *.mod

clean_outputs:
	$(RM) -r $(OUT_PROD_DIR) $(OUT_TEST_DIR) $(OUT_LOG_DIR)
	@mkdir -p $(OUT_DIR)

veryclean: clean
	$(RM) $(EXECUTABLES)

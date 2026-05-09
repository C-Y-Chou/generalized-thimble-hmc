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

OMP         ?= 0
ARCH_FLAG_INTEL ?= -xCORE-AVX2
ARCH_FLAG_GNU   ?= -march=native

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
LDFLAGS_OPT = $(MKL_FLAG) $(THREAD_FLAG) $(ARCH_FLAG) -ipo -Wl,-z,noexecstack
LDFLAGS_FAST = $(MKL_FLAG) $(THREAD_FLAG) $(ARCH_FLAG) -Wl,-z,noexecstack
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
LDFLAGS_OPT = $(THREAD_FLAG) $(GNU_LINALG_LIBS) -Wl,-z,noexecstack
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
CORE_SRC     = core/mtdefs core/mt95 core/utils core/lapack_fallback core/perf_profile
CONFIG_SRC   = config/param_mod
PHYSICS_SRC  = physics/model_autodiff physics/model_tape_ad physics/model_generated physics/model physics/solve_flow
SAMPLER_SRC  = sampler/hmc_kernels sampler/hmc_constraints sampler/hmc_state_buffers sampler/hmc_reversibility_checks \
               sampler/quasi_newton_linear_solver sampler/quasi_newton_line_search \
               sampler/quasi_newton_jacobian_update sampler/quasi_newton_solver \
               sampler/constraint_solver_stats sampler/hmc_integrator_core sampler/hmc sampler/markovchain_phase sampler/markovchain_io \
               sampler/markovchain_transition_status sampler/markovchain_metropolis sampler/markovchain_mod sampler/markovchain \
               sampler/tltm_types sampler/tltm_stage1_driver sampler/tltm_stage2_driver
APP_CHAIN    = apps/generate_markov_chain
APP_EXPECT   = apps/evaluate_expectations
APP_TLTM_STAGE1 = apps/run_tltm_stage1
APP_TLTM_STAGE2 = apps/run_tltm_stage2

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
SOURCES_TEST1  := $(SOURCES_COMMON) $(TEST_DIR)/test_hamiltonian_conservation.f90
SOURCES_TEST2  := $(SOURCES_COMMON) $(TEST_DIR)/test_action_derivatives.f90
SOURCES_TEST_ODEX := $(SOURCES_COMMON) $(TEST_DIR)/test_odex_solver.f90

# map source path -> object path
define src_to_obj
$(patsubst $(SRC_DIR)/%.f90,$(OBJ_DIR)/src/%.o,$(1))
endef

define test_to_obj
$(patsubst $(TEST_DIR)/%.f90,$(OBJ_DIR)/tests/%.o,$(1))
endef

OBJECTS_STEP2 := $(call src_to_obj,$(SOURCES_STEP2))
OBJECTS_STEP3 := $(call src_to_obj,$(SOURCES_STEP3))
OBJECTS_STEP9 := $(call src_to_obj,$(SOURCES_STEP9))
OBJECTS_STEP10 := $(call src_to_obj,$(SOURCES_STEP10))
OBJECTS_TEST1 := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST1))) \
                 $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST1)))
OBJECTS_TEST2 := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST2))) \
                 $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST2)))
OBJECTS_TEST_ODEX := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_TEST_ODEX))) \
                     $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_TEST_ODEX)))

SOURCES_DEP := $(sort $(SOURCES_STEP2) $(SOURCES_STEP3) $(SOURCES_STEP9) \
                $(SOURCES_STEP10) $(SOURCES_TEST1) $(SOURCES_TEST2) $(SOURCES_TEST_ODEX))

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
               test_program test_program2 test_odex_solver
EXECUTABLES  = $(addprefix $(BIN_DIR)/,$(BINARIES))

###############################################################################
#  build targets
###############################################################################
.DEFAULT_GOAL := all
override FFLAGS := $(FFLAGS_OPT) $(FFLAGS_INC)

.PHONY: all fast help chain expect tltm_stage1 test_tltm_stage1 tltm_stage2 tltm_stage2_ref stage3_1 stage3_3 test_tltm_stage2 test1 test2 test_odex_solver \
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

# link rules
$(BIN_DIR)/generate_markov_chain: $(OBJECTS_STEP2) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $^

$(BIN_DIR)/evaluate_expectations: $(OBJECTS_STEP3) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $^

$(BIN_DIR)/run_tltm_stage1: $(OBJECTS_STEP9) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $^

$(BIN_DIR)/run_tltm_stage2: $(OBJECTS_STEP10) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $^

$(BIN_DIR)/test_program: $(OBJECTS_TEST1) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $^

$(BIN_DIR)/test_program2: $(OBJECTS_TEST2) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $^

$(BIN_DIR)/test_odex_solver: $(OBJECTS_TEST_ODEX) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $^

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

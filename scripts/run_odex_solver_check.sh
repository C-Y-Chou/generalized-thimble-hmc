#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
build_dir="$repo_root/build"
overlay_makefile="$build_dir/.odex_solver_check.mk"

if [[ ! -f "$build_dir/makefile" ]]; then
  echo "[ERROR] Missing $build_dir/makefile. Configure/build the project first." >&2
  exit 1
fi

cleanup() {
  rm -f "$overlay_makefile"
}
trap cleanup EXIT INT TERM

cat > "$overlay_makefile" <<'MAKE_EOF'
include makefile

SOURCES_ODEX_SOLVER := $(SOURCES_COMMON) $(TEST_DIR)/test_odex_solver.f90
OBJECTS_ODEX_SOLVER := $(call src_to_obj,$(filter $(SRC_DIR)/%.f90,$(SOURCES_ODEX_SOLVER))) \
                       $(call test_to_obj,$(filter $(TEST_DIR)/%.f90,$(SOURCES_ODEX_SOLVER)))

$(BIN_DIR)/test_odex_solver: $(OBJECTS_ODEX_SOLVER) | $(BIN_DIR)
	$(FC) $(LDFLAGS) -o $@ $^

.PHONY: test_odex_solver

test_odex_solver: $(BIN_DIR)/test_odex_solver prepare_outputs
	@set -o pipefail; $(BIN_DIR)/test_odex_solver 2>&1 | tee $(OUT_LOG_DIR)/test_odex_solver.log
MAKE_EOF

make -C "$build_dir" -f "$overlay_makefile" test_odex_solver

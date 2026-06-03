SHELL := /bin/bash
PYTHON ?= python3
TLTM_PRECISION ?= double
TLTM_TOLERANCE_PROFILE ?= f20f_most_conservative_double

ifneq ($(filter command line environment,$(origin FC)),)
export FC
endif
ifneq ($(filter command line environment,$(origin CC)),)
export CC
endif
ifneq ($(filter command line environment,$(origin OMP)),)
export OMP
endif
ifneq ($(filter command line environment,$(origin USE_EXTERNAL_LINALG)),)
export USE_EXTERNAL_LINALG
endif
ifneq ($(filter command line environment,$(origin EXTERNAL_LINALG_LIBS)),)
export EXTERNAL_LINALG_LIBS
endif
export TLTM_PRECISION
export PYTHON
export TLTM_TOLERANCE_PROFILE

.PHONY: help build test wv-hmc-smoke clean

help:
	@echo "Generalized Thimble HMC product targets:"
	@echo "  make build        - build public executables"
	@echo "  make test         - run public validation checks"
	@echo "  make wv-hmc-smoke - run a short dense WV-HMC smoke"
	@echo "  make clean        - remove build objects"

build:
	$(PYTHON) scripts/run_tltm_product.py build

test:
	$(PYTHON) scripts/run_tltm_product.py test

wv-hmc-smoke:
	$(PYTHON) scripts/run_tltm_product.py wv-hmc --cycles 3 --t0 0 --d0 0 --w-profile zero --w-gamma 0 --step-size 0.004 --output-dir output/product/wv_hmc_smoke

clean:
	$(MAKE) -C build clean

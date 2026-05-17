#!/usr/bin/env python3
"""Validate the F20 precision/GPU readiness contract.

This is a governance/readiness gate, not a single-precision enablement test.
It keeps the current strict-double baseline explicit while checking that the
known precision boundaries and future-mode contract are discoverable.
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_OUTPUT_REL = Path("output/tests/precision_readiness")

REQUIRED_CHECKS = (
    {
        "id": "kind_dp_real64",
        "path": "src/core/utils.f90",
        "patterns": (r"use,\s*intrinsic\s*::\s*iso_fortran_env.*real64", r"integer,\s*parameter\s*::\s*dp\s*=\s*real64"),
        "boundary": "canonical Fortran real/complex kind is strict double",
    },
    {
        "id": "mt95_kind_real64",
        "path": "src/core/mtdefs.f90",
        "patterns": (r"integer,\s*parameter\s*::\s*rk\s*=\s*real64",),
        "boundary": "legacy MT95 real RNG state emits real64 values",
    },
    {
        "id": "stage2_rng_real64",
        "path": "src/core/tltm_rng.f90",
        "patterns": (r"real\(real64\).*function\s+tltm_rng_uniform", r"real\(real64\).*intent\(out\).*values"),
        "boundary": "Stage2 RNG v2 converts counter words into real64 variates",
    },
    {
        "id": "lapack_double_boundary",
        "path": "src/core/lapack_fallback.f90",
        "patterns": (r"subroutine\s+dgetrf", r"subroutine\s+dgetrs", r"subroutine\s+dgemv", r"subroutine\s+zgetrf", r"real64"),
        "boundary": "linear algebra fallback exposes double/complex-double LAPACK ABI",
    },
    {
        "id": "hmc_lapack_calls",
        "path": "src/sampler/hmc_kernels.f90",
        "patterns": (r"external\s*::\s*dgetrf,\s*dgetrs,\s*dgemv", r"call\s+dgetrf", r"call\s+dgetrs", r"call\s+dgemv"),
        "boundary": "RATTLE projection helper calls double LAPACK routines",
    },
    {
        "id": "official_dfols_c_double",
        "path": "src/external/official_dfols_c_bridge.c",
        "patterns": (r"typedef\s+int\s+\(\*tltm_dfols_objfun_cb\).*double", r"PyFloat_AsDouble", r"double_list_from_array"),
        "boundary": "official DFO-LS bridge is a double-precision C/Python ABI",
    },
    {
        "id": "cvode_c_double",
        "path": "src/external/sundials_cvode_bridge.c",
        "patterns": (r"typedef\s+int\s+\(\*tltm_cvode_rhs_cb\).*double", r"sunrealtype", r"CVodeSStolerances"),
        "boundary": "SUNDIALS CVODE comparison bridge is currently double/sunrealtype",
    },
    {
        "id": "fortran_c_double_bridge",
        "path": "src/physics/odex_backend.f90",
        "patterns": (r"real\(c_double\)", r"tltm_sundials_cvode_integrate"),
        "boundary": "Fortran ODE bridge casts endpoint data to C double",
    },
    {
        "id": "strict_double_parameters",
        "path": "data/parameters.dat",
        "patterns": (r"abs_tol\s*=\s*3\.0d-14", r"rel_tol\s*=\s*3\.0d-14", r"constraint_tol\s*=\s*1\.0d-13"),
        "boundary": "default parameter file preserves the strict double tolerance baseline",
    },
    {
        "id": "build_profile_gate",
        "path": "build/makefile",
        "patterns": (r"TLTM_PRECISION\s*\?=\s*double", r"TLTM_TOLERANCE_PROFILE\s*\?=\s*strict_double", r"SUPPORTED_TLTM_PRECISIONS\s*:=\s*double"),
        "boundary": "build-time profile interface exists and currently accepts only certified strict double",
    },
    {
        "id": "stage2_manifest_precision_fields",
        "path": "src/sampler/tltm_stage2_driver.f90",
        "patterns": (
            r'"precision"\s*:',
            r'"precision_mode",\s*"double"',
            r'"tolerance_profile",\s*"strict_double"',
            r'"output_binary_precision",\s*"double_real64"',
        ),
        "boundary": "Stage2 v1alpha manifest records precision and tolerance profile metadata",
    },
    {
        "id": "f20_contract_documented",
        "path": "codex/workspaces/fortran_modernization/runbooks/F20_PRECISION_GPU_READINESS_CLOSURE_20260517.md",
        "patterns": (
            r"TLTM_PRECISION=double\|single\|mixed",
            r"TLTM_TOLERANCE_PROFILE=strict_double\|loose_double\|experimental_single",
            r"single/mixed precision remains experimental",
            r"paired-seed certification",
        ),
        "boundary": "F20 closeout packet documents future precision/tolerance interfaces and certification gates",
    },
)


def parse_args():
    parser = argparse.ArgumentParser(description="Validate F20 precision/GPU readiness boundaries.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument(
        "--output-root",
        default=str(DEFAULT_OUTPUT_REL),
        help="Manifest output root relative to repo root, or absolute.",
    )
    return parser.parse_args()


def resolve(repo_root, raw_path):
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return repo_root / path


def check_patterns(repo_root):
    checks = []
    failures = []
    for check in REQUIRED_CHECKS:
        rel_path = check["path"]
        path = repo_root / rel_path
        result = {
            "id": check["id"],
            "path": rel_path,
            "boundary": check["boundary"],
            "status": "pass",
            "missing_patterns": [],
        }
        if not path.exists():
            result["status"] = "fail"
            result["missing_patterns"] = list(check["patterns"])
            failures.append("{0}: missing file".format(rel_path))
            checks.append(result)
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for pattern in check["patterns"]:
            if re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE | re.DOTALL) is None:
                result["missing_patterns"].append(pattern)
        if result["missing_patterns"]:
            result["status"] = "fail"
            failures.append(
                "{0}: missing pattern(s): {1}".format(rel_path, "; ".join(result["missing_patterns"]))
            )
        checks.append(result)
    return checks, failures


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_root = resolve(repo_root, args.output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    checks, failures = check_patterns(repo_root)
    manifest = {
        "status": "fail" if failures else "pass",
        "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "precision_mode": "double",
        "tolerance_profile": "strict_double",
        "single_mixed_status": "experimental_until_certified",
        "checks": checks,
        "failures": failures,
    }
    manifest_path = output_root / "F20_precision_readiness_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print("status={0}".format(manifest["status"]))
    print("precision_mode={0}".format(manifest["precision_mode"]))
    print("tolerance_profile={0}".format(manifest["tolerance_profile"]))
    print("checks={0}".format(len(checks)))
    print("manifest={0}".format(manifest_path))
    if failures:
        for failure in failures[:80]:
            print("[F20][FAIL] {0}".format(failure), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

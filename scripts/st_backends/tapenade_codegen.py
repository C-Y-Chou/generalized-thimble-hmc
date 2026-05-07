#!/usr/bin/env python3
"""Best-effort Tapenade source-transformation backend.

This script generates model_generated.f90 by:
1) writing a primal Fortran subroutine from model_action_body.inc
2) running Tapenade reverse mode to get gradient code
3) running Tapenade tangent mode on the reverse routine to get Hessian-vector code
4) emitting wrappers `calculate_action_generated/ds_generated/hessian_vec_generated`

Notes:
- Tapenade CLI options and generated signatures can vary by version.
- The wrapper call signatures here follow common Tapenade naming conventions and may
  require adjustment for your local Tapenade build.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


def _indent_block(text: str, spaces: int) -> str:
    prefix = " " * spaces
    lines = text.splitlines()
    if not lines:
        return ""
    return "\n".join((prefix + line if line.strip() else "") for line in lines)


def _run(cmd: list[str], cwd: Path) -> None:
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if proc.returncode != 0:
        msg = [f"Command failed ({proc.returncode}): {' '.join(cmd)}"]
        if proc.stdout.strip():
            msg += ["--- stdout ---", proc.stdout.rstrip()]
        if proc.stderr.strip():
            msg += ["--- stderr ---", proc.stderr.rstrip()]
        raise RuntimeError("\n".join(msg))


def _latest_matching(workdir: Path, pattern: re.Pattern[str], exclude: set[Path]) -> Path:
    cands = [p for p in workdir.iterdir() if p.is_file() and pattern.search(p.name) and p not in exclude]
    if not cands:
        raise RuntimeError(f"No Tapenade output file matched pattern: {pattern.pattern}")
    cands.sort(key=lambda p: p.stat().st_mtime)
    return cands[-1]


def _first_subroutine_signature(text: str) -> tuple[str, list[str]]:
    m = re.search(r"(?ims)^\s*subroutine\s+([a-z_][a-z0-9_]*)\s*\((.*?)\)", text)
    if not m:
        raise RuntimeError("Failed to find subroutine signature in Tapenade output.")
    name = m.group(1)
    arg_blob = m.group(2)
    arg_blob = arg_blob.replace("&", " ").replace("\n", " ")
    args = [tok.strip() for tok in arg_blob.split(",") if tok.strip()]
    return name, args


def _sanitize_tapenade_text(text: str) -> str:
    # Tapenade 3.16 may emit this invalid declaration even when dp is imported.
    text = re.sub(r"(?im)^\s*type\s*\(\s*unknowntype\s*\)\s*::\s*dp\s*$\n?", "", text)
    return text


def _build_call(name: str, args: list[str], mapping: dict[str, str]) -> str:
    mapped: list[str] = []
    for arg in args:
        key = arg.lower()
        if key not in mapping:
            raise RuntimeError(
                f"Unsupported argument '{arg}' in Tapenade routine '{name}'. "
                "Update tapenade_codegen.py mapping for this Tapenade signature."
            )
        mapped.append(mapping[key])
    return f"call {name}({', '.join(mapped)})"


def _primal_source(body_text: str, body_path: Path) -> str:
    body = _indent_block(body_text.rstrip("\n"), 3)
    src_note = str(body_path)
    return f"""! Auto-generated Tapenade primal source.
! Source action body: {src_note}
subroutine action_eval_st(n, z, alpha, beta, s)
   use utils, only: dp
   implicit none
   integer, intent(in) :: n
   complex(dp), intent(in) :: z(n)
   complex(dp), intent(in) :: alpha, beta
   complex(dp), intent(out) :: s
   complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
   complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
   complex(dp) :: zero
   integer :: i

   zero = cmplx(0.0_dp, 0.0_dp, dp)
{body}
end subroutine action_eval_st
"""


def _generated_module(
    primal_text: str,
    rev_text: str,
    tan_text: str,
    rev_name: str,
    tan_name: str,
    rev_call: str,
    tan_call: str,
) -> str:
    return f"""! This file is auto-generated. Do not edit manually.
! Backend: st-tapenade-experimental
module model_generated
   use utils, only: dp
   implicit none

contains

   subroutine calculate_action_generated(z, alpha, beta, s)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: s
      integer :: n

      n = size(z)
      call action_eval_st(n, z, alpha, beta, s)
   end subroutine calculate_action_generated

   subroutine ds_generated(z, alpha, beta, s)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: s(:)
      integer :: n
      complex(dp) :: action_val, sb
      complex(dp) :: alphab, betab
      complex(dp) :: zb(size(z))

      n = size(z)
      if (size(s) /= n) then
         write (*, '(A)') '[ERROR] ds_generated: vector size mismatch.'
         error stop 1
      end if

      zb = cmplx(0.0_dp, 0.0_dp, dp)
      alphab = cmplx(0.0_dp, 0.0_dp, dp)
      betab = cmplx(0.0_dp, 0.0_dp, dp)
      sb = cmplx(1.0_dp, 0.0_dp, dp)
      call action_eval_st(n, z, alpha, beta, action_val)
      {rev_call}
      s = conjg(zb)
   end subroutine ds_generated

   subroutine hessian_generated(z, alpha, beta, h)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: h(:, :)
      complex(dp) :: e(size(z))
      integer :: n, j

      n = size(z)
      if (size(h, 1) /= n .or. size(h, 2) /= n) then
         write (*, '(A)') '[ERROR] hessian_generated: matrix size mismatch.'
         error stop 1
      end if

      h = cmplx(0.0_dp, 0.0_dp, dp)
      do j = 1, n
         e = cmplx(0.0_dp, 0.0_dp, dp)
         e(j) = cmplx(1.0_dp, 0.0_dp, dp)
         call hessian_vec_generated(z, alpha, beta, e, h(:, j))
      end do
   end subroutine hessian_generated

   subroutine hessian_vec_generated(z, alpha, beta, v, hv)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(in) :: v(:)
      complex(dp), intent(out) :: hv(:)
      integer :: n, nd
      complex(dp) :: action_val, action_d
      complex(dp) :: sb, sb_d
      complex(dp) :: alphab, alphabd, alphad
      complex(dp) :: betab, betabd, betad
      complex(dp) :: zb(size(z)), zbd(size(z)), zd(size(z))

      n = size(z)
      if (size(v) /= n .or. size(hv) /= n) then
         write (*, '(A)') '[ERROR] hessian_vec_generated: vector size mismatch.'
         error stop 1
      end if

      nd = 0
      zd = v
      zb = cmplx(0.0_dp, 0.0_dp, dp)
      zbd = cmplx(0.0_dp, 0.0_dp, dp)
      alphad = cmplx(0.0_dp, 0.0_dp, dp)
      alphab = cmplx(0.0_dp, 0.0_dp, dp)
      alphabd = cmplx(0.0_dp, 0.0_dp, dp)
      betad = cmplx(0.0_dp, 0.0_dp, dp)
      betab = cmplx(0.0_dp, 0.0_dp, dp)
      betabd = cmplx(0.0_dp, 0.0_dp, dp)
      sb = cmplx(1.0_dp, 0.0_dp, dp)
      sb_d = cmplx(0.0_dp, 0.0_dp, dp)
      action_d = cmplx(0.0_dp, 0.0_dp, dp)

      call action_eval_st(n, z, alpha, beta, action_val)
      {tan_call}
      hv = conjg(zbd)
   end subroutine hessian_vec_generated

end module model_generated

! ===== Tapenade generated program units (primal/reverse/tangent) =====
{primal_text}
{rev_text}
{tan_text}
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate model_generated.f90 using Tapenade source transformation.")
    parser.add_argument("--body", required=True, help="Path to model_action_body.inc")
    parser.add_argument("--output", required=True, help="Path to output model_generated.f90")
    parser.add_argument("--tapenade-cmd", default="", help="Tapenade executable path (default: ST_TAPENADE_CMD env or 'tapenade')")
    parser.add_argument("--keep-temp", action="store_true", help="Keep temporary Tapenade files")
    args = parser.parse_args()

    body_path = Path(args.body).resolve()
    out_path = Path(args.output).resolve()
    tapenade_cmd = args.tapenade_cmd or os.environ.get("ST_TAPENADE_CMD", "tapenade")

    if shutil.which(tapenade_cmd) is None:
        raise RuntimeError(
            "Tapenade executable not found. Set ST_TAPENADE_CMD or pass --tapenade-cmd.\n"
            "Example:\n"
            "  export ST_TAPENADE_CMD=/path/to/tapenade\n"
            "  make -B regen_model_derivatives GEN_BACKEND=st_tapenade"
        )

    body_text = body_path.read_text(encoding="utf-8")
    if not body_text.strip():
        raise RuntimeError(f"Action body is empty: {body_path}")

    with tempfile.TemporaryDirectory(prefix="st_tapenade_") as td:
        workdir = Path(td)
        primal_path = workdir / "action_eval_st.f90"
        primal_text = _primal_source(body_text, body_path)
        primal_path.write_text(primal_text, encoding="utf-8")

        existing = set(workdir.iterdir())
        _run([tapenade_cmd, "-b", "-head", "action_eval_st", primal_path.name], cwd=workdir)
        rev_path = _latest_matching(workdir, re.compile(r"_b\.(f90|f95|f03|f|for)$", re.IGNORECASE), existing)

        existing2 = set(workdir.iterdir())
        _run([tapenade_cmd, "-d", "-head", "action_eval_st_b", rev_path.name], cwd=workdir)
        tan_path = _latest_matching(workdir, re.compile(r"_d\.(f90|f95|f03|f|for)$", re.IGNORECASE), existing2)

        rev_text = _sanitize_tapenade_text(rev_path.read_text(encoding="utf-8", errors="ignore"))
        tan_text = _sanitize_tapenade_text(tan_path.read_text(encoding="utf-8", errors="ignore"))
        rev_name, rev_args = _first_subroutine_signature(rev_text)
        tan_name, tan_args = _first_subroutine_signature(tan_text)

        rev_call = _build_call(
            rev_name,
            rev_args,
            {
                "n": "n",
                "z": "z",
                "zb": "zb",
                "alpha": "alpha",
                "alphab": "alphab",
                "beta": "beta",
                "betab": "betab",
                "s": "action_val",
                "sb": "sb",
            },
        )
        tan_call = _build_call(
            tan_name,
            tan_args,
            {
                "n": "n",
                "nd": "nd",
                "z": "z",
                "zd": "zd",
                "zb": "zb",
                "zbd": "zbd",
                "alpha": "alpha",
                "alphad": "alphad",
                "alphab": "alphab",
                "alphabd": "alphabd",
                "beta": "beta",
                "betad": "betad",
                "betab": "betab",
                "betabd": "betabd",
                "s": "action_val",
                "sd": "action_d",
                "sb": "sb",
                "sbd": "sb_d",
            },
        )

        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(
            _generated_module(primal_text, rev_text, tan_text, rev_name, tan_name, rev_call, tan_call),
            encoding="utf-8",
        )

        if args.keep_temp:
            keep_dir = out_path.parent / "st_tapenade_tmp"
            keep_dir.mkdir(parents=True, exist_ok=True)
            for p in workdir.iterdir():
                if p.is_file():
                    (keep_dir / p.name).write_text(p.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")


if __name__ == "__main__":
    main()

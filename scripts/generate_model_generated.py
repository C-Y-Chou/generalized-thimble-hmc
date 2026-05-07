#!/usr/bin/env python3
"""Generate model_generated.f90 from a single-source action body.

Backend modes:
  - auto:        try symbolic source generation for separable forms, fallback to tape AD
  - symbolic:    require separable symbolic generation
  - tape:        always emit tape-based generated AD
  - st_auto:     try st_tapenade then st_enzyme, fallback to auto when unavailable
  - st_tapenade: run Tapenade adapter script
  - st_enzyme:   run Enzyme adapter script
"""

from __future__ import annotations

import argparse
import re
import subprocess
import shlex
from pathlib import Path


def _indent_block(text: str, spaces: int) -> str:
    prefix = " " * spaces
    lines = text.splitlines()
    if not lines:
        return ""
    return "\n".join((prefix + line if line.strip() else "") for line in lines)


def _strip_comment(line: str) -> str:
    return line.split("!", 1)[0].rstrip()


def _extract_separable_term(body_text: str) -> str | None:
    lines = [_strip_comment(line).strip() for line in body_text.splitlines()]
    lines = [line for line in lines if line]

    # Expected minimal structure:
    #   s = zero
    #   do i = 1, size(z)
    #      s = s +/- expr(z(i), alpha, beta, ...)
    #   end do
    if len(lines) != 4:
        return None
    if lines[0].lower() != "s = zero":
        return None
    if lines[1].lower().replace(" ", "") != "doi=1,size(z)":
        return None
    if lines[3].lower() != "end do":
        return None

    m = re.match(r"^s\s*=\s*s\s*(.+)$", lines[2], re.IGNORECASE)
    if m is None:
        return None

    term = m.group(1).strip()
    if not term:
        return None
    if term[0] not in {"+", "-"}:
        return None

    # Must be element-wise in z(i) only for symbolic separable backend.
    if "z(i)" not in term:
        return None
    if re.search(r"z\(\s*(?!i\b)[^)]+\)", term, re.IGNORECASE):
        return None

    return term


def _sympy_fortran(term_fortran: str) -> tuple[str, str]:
    try:
        import sympy as sp
    except Exception as exc:  # pragma: no cover - runtime environment dependent
        raise RuntimeError(f"sympy is unavailable: {exc}") from exc

    w, alpha, beta, ci, three = sp.symbols("w alpha beta ci three")
    locals_map = {
        "w": w,
        "alpha": alpha,
        "beta": beta,
        "ci": ci,
        "three": three,
        "log": sp.log,
        "exp": sp.exp,
    }

    sympy_expr = term_fortran.replace("z(i)", "w")
    expr = sp.sympify(sympy_expr, locals=locals_map)
    ds_expr = sp.diff(expr, w)
    d2_expr = sp.diff(ds_expr, w)

    ds_code = sp.fcode(ds_expr, source_format="free", standard=2008)
    d2_code = sp.fcode(d2_expr, source_format="free", standard=2008)

    # The scalar symbol is w in the symbolic template.
    return ds_code, d2_code


def _generate_symbolic_fortran(body_text: str, body_path: Path, ds_expr: str, d2_expr: str) -> str:
    body = _indent_block(body_text.rstrip("\n"), 6)
    src_note = str(body_path)
    ds_line = re.sub(r"\bw\b", "z(i)", ds_expr)
    d2_line = re.sub(r"\bw\b", "z(i)", d2_expr)

    return f"""! This file is auto-generated. Do not edit manually.
! Source action body: {src_note}
! Backend: symbolic-separable
module model_generated
   use utils, only: dp
   implicit none

contains

   subroutine calculate_action_generated(z, alpha, beta, s)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: s
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
      complex(dp) :: zero
      integer :: i

      zero = cmplx(0.0_dp, 0.0_dp, dp)
{body}
   end subroutine calculate_action_generated

   subroutine ds_generated(z, alpha, beta, s)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: s(:)
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
      integer :: n, i

      n = size(z)
      if (size(s) /= n) then
         write (*, '(A)') '[ERROR] ds_generated: vector size mismatch.'
         error stop 1
      end if

      do i = 1, n
         s(i) = {ds_line}
      end do
   end subroutine ds_generated

   subroutine hessian_generated(z, alpha, beta, h)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: h(:, :)
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
      integer :: n, i

      n = size(z)
      if (size(h, 1) /= n .or. size(h, 2) /= n) then
         write (*, '(A)') '[ERROR] hessian_generated: matrix size mismatch.'
         error stop 1
      end if

      h = cmplx(0.0_dp, 0.0_dp, dp)
      do i = 1, n
         h(i, i) = {d2_line}
      end do
   end subroutine hessian_generated

   subroutine hessian_vec_generated(z, alpha, beta, v, hv)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(in) :: v(:)
      complex(dp), intent(out) :: hv(:)
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
      integer :: n, i

      n = size(z)
      if (size(v) /= n .or. size(hv) /= n) then
         write (*, '(A)') '[ERROR] hessian_vec_generated: vector size mismatch.'
         error stop 1
      end if

      do i = 1, n
         hv(i) = ({d2_line})*v(i)
      end do
   end subroutine hessian_vec_generated

end module model_generated
"""


def _generate_tape_fortran(body_text: str, body_path: Path) -> str:
    body = _indent_block(body_text.rstrip("\n"), 6)
    src_note = str(body_path)

    return f"""! This file is auto-generated. Do not edit manually.
! Source action body: {src_note}
! Backend: tape-generic
module model_generated
   use utils, only: dp
   use model_tape_ad
   implicit none
   logical, save :: tape_ready = .false.
   logical, save :: tape_point_ready = .false.
   integer, save :: tape_n = 0
   integer, save :: tape_out_id = 0
   complex(dp), save :: tape_alpha = cmplx(0.0_dp, 0.0_dp, dp)
   complex(dp), save :: tape_beta = cmplx(0.0_dp, 0.0_dp, dp)
   complex(dp), allocatable, save :: tape_last_z(:)

contains

   subroutine calculate_action_generated(z, alpha, beta, s)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: s
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
      complex(dp) :: zero
      integer :: i

      zero = cmplx(0.0_dp, 0.0_dp, dp)
{body}
   end subroutine calculate_action_generated

   subroutine build_action_tape(z_in, alpha, beta, out_id)
      complex(dp), intent(in) :: z_in(:)
      complex(dp), intent(in) :: alpha, beta
      integer, intent(out) :: out_id
      type(rev_t), allocatable :: z(:)
      type(rev_t) :: s, zero
      complex(dp), parameter :: ci = cmplx(0.0_dp, 1.0_dp, dp)
      complex(dp), parameter :: three = cmplx(3.0_dp, 0.0_dp, dp)
      integer :: i, n

      n = size(z_in)
      call tape_begin(n)

      allocate (z(n))
      do i = 1, n
         z(i) = tape_input(z_in(i), i)
      end do

      zero = tape_const(cmplx(0.0_dp, 0.0_dp, dp))
{body}
      out_id = s%id
   end subroutine build_action_tape

   subroutine ensure_action_tape(z, alpha, beta)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      integer :: n

      n = size(z)
      if (.not. tape_ready .or. tape_n /= n .or. alpha /= tape_alpha .or. beta /= tape_beta) then
         call build_action_tape(z, alpha, beta, tape_out_id)
         tape_n = n
         tape_alpha = alpha
         tape_beta = beta
         tape_ready = .true.
         if (allocated(tape_last_z)) then
            if (size(tape_last_z) /= n) deallocate (tape_last_z)
         end if
         if (.not. allocated(tape_last_z)) allocate (tape_last_z(n))
         tape_last_z = z
         tape_point_ready = .true.
      else
         if (.not. tape_point_ready .or. any(z /= tape_last_z)) then
            call tape_set_inputs(z)
            call tape_forward_values()
            tape_last_z = z
            tape_point_ready = .true.
         end if
      end if
   end subroutine ensure_action_tape

   subroutine ds_generated(z, alpha, beta, s)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: s(:)
      integer :: n

      n = size(z)
      if (size(s) /= n) then
         write (*, '(A)') '[ERROR] ds_generated: vector size mismatch.'
         error stop 1
      end if

      call ensure_action_tape(z, alpha, beta)
      call tape_grad(tape_out_id, s)
   end subroutine ds_generated

   subroutine hessian_generated(z, alpha, beta, h)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(out) :: h(:, :)
      complex(dp) :: e(size(z))
      integer :: n
      integer :: j

      n = size(z)
      if (size(h, 1) /= n .or. size(h, 2) /= n) then
         write (*, '(A)') '[ERROR] hessian_generated: matrix size mismatch.'
         error stop 1
      end if

      h = cmplx(0.0_dp, 0.0_dp, dp)
      call ensure_action_tape(z, alpha, beta)
      do j = 1, n
         e = cmplx(0.0_dp, 0.0_dp, dp)
         e(j) = cmplx(1.0_dp, 0.0_dp, dp)
         call tape_hvp(tape_out_id, e, h(:, j))
      end do
   end subroutine hessian_generated

   subroutine hessian_vec_generated(z, alpha, beta, v, hv)
      complex(dp), intent(in) :: z(:)
      complex(dp), intent(in) :: alpha, beta
      complex(dp), intent(in) :: v(:)
      complex(dp), intent(out) :: hv(:)
      integer :: n

      n = size(z)
      if (size(v) /= n .or. size(hv) /= n) then
         write (*, '(A)') '[ERROR] hessian_vec_generated: vector size mismatch.'
         error stop 1
      end if

      call ensure_action_tape(z, alpha, beta)
      call tape_hvp(tape_out_id, v, hv)
   end subroutine hessian_vec_generated

end module model_generated
"""


def generate_fortran(body_text: str, body_path: Path, backend: str) -> str:
    term = _extract_separable_term(body_text)

    if backend in {"auto", "symbolic"}:
        if term is not None:
            try:
                ds_expr, d2_expr = _sympy_fortran(term)
                return _generate_symbolic_fortran(body_text, body_path, ds_expr, d2_expr)
            except Exception as exc:
                if backend == "symbolic":
                    raise RuntimeError(f"symbolic backend failed: {exc}") from exc
        elif backend == "symbolic":
            raise RuntimeError("symbolic backend requires separable body shape: s=zero; do i=1,size(z); s=s+/-f(z(i)); end do")

    return _generate_tape_fortran(body_text, body_path)


def _run_external_codegen(script_path: Path, body_path: Path, out_path: Path, backend_name: str) -> None:
    if not script_path.exists():
        raise RuntimeError(f"{backend_name} backend script not found: {script_path}")
    cmd = ["python3", str(script_path), "--body", str(body_path), "--output", str(out_path)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        msg = [
            f"{backend_name} backend failed with exit code {proc.returncode}.",
            f"Command: {' '.join(shlex.quote(c) for c in cmd)}",
        ]
        if proc.stdout.strip():
            msg.append("--- stdout ---")
            msg.append(proc.stdout.rstrip())
        if proc.stderr.strip():
            msg.append("--- stderr ---")
            msg.append(proc.stderr.rstrip())
        raise RuntimeError("\n".join(msg))


def _generate_with_source_transform(script_dir: Path, body_path: Path, out_path: Path, backend: str) -> bool:
    tapenade_script = script_dir / "st_backends" / "tapenade_codegen.py"
    enzyme_script = script_dir / "st_backends" / "enzyme_codegen.py"

    if backend == "st_tapenade":
        _run_external_codegen(tapenade_script, body_path, out_path, "st_tapenade")
        return True
    if backend == "st_enzyme":
        _run_external_codegen(enzyme_script, body_path, out_path, "st_enzyme")
        return True
    if backend == "st_auto":
        try:
            _run_external_codegen(tapenade_script, body_path, out_path, "st_tapenade")
            return True
        except Exception:
            pass
        try:
            _run_external_codegen(enzyme_script, body_path, out_path, "st_enzyme")
            return True
        except Exception:
            pass
        return False
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate model_generated.f90 from model_action_body.inc.")
    parser.add_argument("--body", default="../src/physics/model_action_body.inc", help="Action body file")
    parser.add_argument("--output", default="../src/physics/model_generated.f90", help="Output Fortran file")
    parser.add_argument(
        "--backend",
        choices=["auto", "symbolic", "tape", "st_auto", "st_tapenade", "st_enzyme"],
        default="auto",
        help="Generation backend",
    )
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    body_path = (script_dir / args.body).resolve()
    out_path = (script_dir / args.output).resolve()

    body_text = body_path.read_text(encoding="utf-8")
    if not body_text.strip():
        raise ValueError(f"Action body is empty: {body_path}")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if args.backend.startswith("st_"):
        ok = _generate_with_source_transform(script_dir, body_path, out_path, args.backend)
        if ok:
            return
        # st_auto fallback when external tools are unavailable.
        if args.backend == "st_auto":
            out_path.write_text(generate_fortran(body_text, body_path, "auto"), encoding="utf-8")
            print("[WARN] st_auto backend unavailable; fell back to auto (symbolic/tape).")
            return
        raise RuntimeError(f"{args.backend} backend was requested but could not generate output.")
    out_path.write_text(generate_fortran(body_text, body_path, args.backend), encoding="utf-8")


if __name__ == "__main__":
    main()

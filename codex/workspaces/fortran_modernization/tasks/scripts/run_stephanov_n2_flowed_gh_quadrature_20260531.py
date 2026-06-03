#!/usr/bin/env python3
"""Flowed-contour Gauss-Hermite check for Stephanov n=2.

This is a deterministic diagnostic: it generates a t=0 Gauss-Hermite bank,
uses the Fortran dense-flow cache builder to evaluate z_t(x) and J_t(x), then
checks that the flowed contour gives the same chiral condensate and number
density as the t=0 exact reference.
"""

import argparse
import cmath
import csv
import itertools
import math
import os
import struct
import subprocess
from pathlib import Path


EXACT_CHIRAL = 0.380047505938398
EXACT_DENSITY = 0.0387173396674602


def stephanov_ab(z, n_model, mass, mu, tau):
    del mass
    a = [[0.0 + 0.0j for _ in range(n_model)] for _ in range(n_model)]
    b = [[0.0 + 0.0j for _ in range(n_model)] for _ in range(n_model)]
    half_n = n_model // 2
    c_diag = [tau - 1j * mu if i < half_n else -tau - 1j * mu for i in range(n_model)]
    for j in range(n_model):
        for i in range(n_model):
            base_x = j * n_model + i
            base_y = n_model * n_model + j * n_model + i
            zx = z[base_x]
            zy = z[base_y]
            a[i][j] = zx + 1j * zy
            b[j][i] = zx - 1j * zy
    for i in range(n_model):
        a[i][i] += c_diag[i]
        b[i][i] += c_diag[i]
    return a, b


def matmul(a, b):
    n = len(a)
    m = len(b[0])
    kdim = len(b)
    return [[sum(a[i][k] * b[k][j] for k in range(kdim)) for j in range(m)] for i in range(n)]


def trace(mat):
    return sum(mat[i][i] for i in range(len(mat)))


def det_matrix(mat):
    n = len(mat)
    a = [list(row) for row in mat]
    det = 1.0 + 0.0j
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(a[r][col]))
        if abs(a[pivot][col]) == 0.0:
            return 0.0 + 0.0j
        if pivot != col:
            a[col], a[pivot] = a[pivot], a[col]
            det = -det
        pivot_value = a[col][col]
        det *= pivot_value
        for row in range(col + 1, n):
            factor = a[row][col] / pivot_value
            if factor == 0.0:
                continue
            for j in range(col + 1, n):
                a[row][j] -= factor * a[col][j]
    return det


def inv2(mat):
    det = mat[0][0] * mat[1][1] - mat[0][1] * mat[1][0]
    if abs(det) == 0.0:
        raise ZeroDivisionError("singular 2x2 matrix")
    return [[mat[1][1] / det, -mat[0][1] / det], [-mat[1][0] / det, mat[0][0] / det]]


def stephanov_observables(z, n_model, mass, mu, tau):
    a, b = stephanov_ab(z, n_model, mass, mu, tau)
    q = matmul(b, a)
    for i in range(n_model):
        q[i][i] += mass * mass
    if n_model != 2:
        raise ValueError("pure-python diagnostic currently supports n_model=2")
    q_inv = inv2(q)
    chiral = (mass / float(n_model)) * trace(q_inv)
    a_plus_b = [[a[i][j] + b[i][j] for j in range(n_model)] for i in range(n_model)]
    density = mu - 1j / (2.0 * float(n_model)) * trace(matmul(q_inv, a_plus_b))
    det_dirac = det_matrix(q)
    return chiral, density, det_dirac


def action_value(z, n_model, nf, mass, mu, tau):
    _chiral, _density, det_dirac = stephanov_observables(z, n_model, mass, mu, tau)
    quad = sum(value * value for value in z)
    return float(n_model) * quad - float(nf) * cmath.log(det_dirac)


def hermgauss(order):
    sqrt_pi = math.sqrt(math.pi)
    if order == 3:
        a = math.sqrt(1.5)
        return [-a, 0.0, a], [sqrt_pi / 6.0, 2.0 * sqrt_pi / 3.0, sqrt_pi / 6.0]
    if order == 5:
        a = math.sqrt((5.0 - math.sqrt(10.0)) / 2.0)
        b = math.sqrt((5.0 + math.sqrt(10.0)) / 2.0)
        w_a = sqrt_pi * (7.0 + 2.0 * math.sqrt(10.0)) / 60.0
        w_b = sqrt_pi * (7.0 - 2.0 * math.sqrt(10.0)) / 60.0
        return [-b, -a, 0.0, a, b], [w_b, w_a, 8.0 * sqrt_pi / 15.0, w_a, w_b]
    raise ValueError("supported GH orders are 3 and 5")


def generate_gh_bank(out_dir: Path, order: int, n_model: int):
    dim = 2 * n_model * n_model
    nodes, weights = hermgauss(order)
    x_bank = out_dir / f"stephanov_n2_gh_k{order}_x_bank.dat"
    weights_csv = out_dir / f"stephanov_n2_gh_k{order}_weights.csv"
    scale = math.sqrt(float(n_model))
    count = order**dim
    with x_bank.open("wb") as bank, weights_csv.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["source_record", "weight"])
        for rec, multi_idx in enumerate(itertools.product(range(order), repeat=dim)):
            x = [nodes[i] / scale for i in multi_idx]
            # The common n^{-dim/2} factor cancels in ratios, so omit it.
            w = 1.0
            for idx in multi_idx:
                w *= weights[idx]
            bank.write(struct.pack("<" + "d" * dim, *x))
            writer.writerow([rec, "{:.17e}".format(w)])
    return x_bank, weights_csv, count


def read_slot(path: Path, state_size: int):
    raw = path.read_bytes()
    int_count = 11
    header_bytes = 4 * int_count + 8
    if len(raw) < header_bytes:
        raise ValueError(f"slot too short: {path}")
    ints = struct.unpack("<" + "i" * int_count, raw[: 4 * int_count])
    target_time = struct.unpack("<d", raw[4 * int_count : header_bytes])[0]
    available = ints[6]
    offset = header_bytes
    x = list(struct.unpack_from("<" + "d" * state_size, raw, offset))
    offset += 8 * state_size
    z_pairs = struct.unpack_from("<" + "d" * (2 * state_size), raw, offset)
    z = [z_pairs[2 * i] + 1j * z_pairs[2 * i + 1] for i in range(state_size)]
    offset += 16 * state_size
    jac_pairs = struct.unpack_from("<" + "d" * (2 * state_size * state_size), raw, offset)
    jac_values = [jac_pairs[2 * i] + 1j * jac_pairs[2 * i + 1] for i in range(state_size * state_size)]
    jac = [[jac_values[j * state_size + i] for j in range(state_size)] for i in range(state_size)]
    return available, target_time, x, z, jac


def analyze_flow_bank(bank_dir: Path, weights_csv: Path, slot_id: int, state_size: int, n_model: int, nf: int, mass: float, mu: float, tau: float, allow_missing: bool):
    total_w = 0.0
    d0 = 0.0 + 0.0j
    n_chiral0 = 0.0 + 0.0j
    n_density0 = 0.0 + 0.0j
    d0_available = 0.0 + 0.0j
    n_chiral0_available = 0.0 + 0.0j
    n_density0_available = 0.0 + 0.0j
    d_flow = 0.0 + 0.0j
    n_chiral_flow = 0.0 + 0.0j
    n_density_flow = 0.0 + 0.0j
    total_abs_direct_weight0 = 0.0
    missing_abs_direct_weight0 = 0.0
    missing_gh_weight = 0.0
    max_direct_weight_abs = 0.0
    max_direct_weight0_abs = 0.0
    rows = 0
    unavailable = 0
    unavailable_records = []
    with weights_csv.open() as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            rec = int(row["source_record"])
            gh_w = float(row["weight"])
            slot = bank_dir / "records" / f"record_{rec:06d}" / f"slot_{slot_id:06d}.bin"
            available, _target_time, x, z, jac = read_slot(slot, state_size)
            rows += 1
            total_w += gh_w
            x_complex = [complex(value, 0.0) for value in x]
            ch0, de0, _det0 = stephanov_observables(x_complex, n_model, mass, mu, tau)
            s0 = action_value(x_complex, n_model, nf, mass, mu, tau)
            direct_weight0 = cmath.exp(-s0 + float(n_model) * sum(value * value for value in x))
            d0 += gh_w * direct_weight0
            n_chiral0 += gh_w * direct_weight0 * ch0
            n_density0 += gh_w * direct_weight0 * de0
            abs_weight0 = abs(gh_w * direct_weight0)
            total_abs_direct_weight0 += abs_weight0
            max_direct_weight0_abs = max(max_direct_weight0_abs, abs(direct_weight0))
            if available != 1:
                unavailable += 1
                missing_gh_weight += gh_w
                missing_abs_direct_weight0 += abs_weight0
                if len(unavailable_records) < 32:
                    unavailable_records.append(rec)
                continue
            d0_available += gh_w * direct_weight0
            n_chiral0_available += gh_w * direct_weight0 * ch0
            n_density0_available += gh_w * direct_weight0 * de0
            ch, de, _det = stephanov_observables(z, n_model, mass, mu, tau)
            s = action_value(z, n_model, nf, mass, mu, tau)
            det_j = det_matrix(jac)
            # GH weights integrate exp(-n*x^2).  Convert the flowed integrand
            # exp(-S(z)) detJ dx to that measure by multiplying exp(+n*x^2).
            direct_weight = cmath.exp(-s + float(n_model) * sum(value * value for value in x)) * det_j
            max_direct_weight_abs = max(max_direct_weight_abs, abs(direct_weight))
            d_flow += gh_w * direct_weight
            n_chiral_flow += gh_w * direct_weight * ch
            n_density_flow += gh_w * direct_weight * de
    if unavailable and not allow_missing:
        raise RuntimeError(f"{unavailable} unavailable flow slots out of {rows}")
    available_rows = rows - unavailable
    return {
        "rows": rows,
        "available_rows": available_rows,
        "unavailable_rows": unavailable,
        "gh_weight_sum": total_w,
        "missing_gh_weight_sum": missing_gh_weight,
        "missing_gh_weight_fraction": missing_gh_weight / total_w if total_w else math.nan,
        "missing_abs_t0_weight_sum": missing_abs_direct_weight0,
        "total_abs_t0_weight_sum": total_abs_direct_weight0,
        "missing_abs_t0_weight_fraction": missing_abs_direct_weight0 / total_abs_direct_weight0 if total_abs_direct_weight0 else math.nan,
        "unavailable_record_preview": unavailable_records,
        "t0_chiral": n_chiral0 / d0,
        "t0_density": n_density0 / d0,
        "t0_chiral_available": n_chiral0_available / d0_available if available_rows else complex(math.nan, math.nan),
        "t0_density_available": n_density0_available / d0_available if available_rows else complex(math.nan, math.nan),
        "flow_chiral": n_chiral_flow / d_flow if available_rows else complex(math.nan, math.nan),
        "flow_density": n_density_flow / d_flow if available_rows else complex(math.nan, math.nan),
        "denominator_t0": d0,
        "denominator_t0_available": d0_available,
        "denominator_flow": d_flow,
        "max_direct_weight_abs": max_direct_weight_abs,
        "max_direct_weight0_abs": max_direct_weight0_abs,
    }


def write_outputs(out_dir: Path, result: dict, order: int, flow_time: float):
    csv_path = out_dir / "flowed_gh_quadrature_summary.csv"
    md_path = out_dir / "flowed_gh_quadrature_readback.md"
    fields = [
        "order",
        "flow_time",
        "rows",
        "available_rows",
        "unavailable_rows",
        "observable",
        "t0_re",
        "t0_im",
        "t0_available_re",
        "t0_available_im",
        "flow_re",
        "flow_im",
        "exact_re",
        "flow_minus_exact_re",
        "flow_minus_t0_re",
        "flow_minus_t0_available_re",
    ]
    rows = []
    for name, exact, t0_key, flow_key in [
        ("chiral_condensate", EXACT_CHIRAL, "t0_chiral", "flow_chiral"),
        ("number_density", EXACT_DENSITY, "t0_density", "flow_density"),
    ]:
        t0 = result[t0_key]
        t0_available = result[f"{t0_key}_available"]
        flow = result[flow_key]
        rows.append(
            {
                "order": order,
                "flow_time": flow_time,
                "rows": result["rows"],
                "available_rows": result["available_rows"],
                "unavailable_rows": result["unavailable_rows"],
                "observable": name,
                "t0_re": t0.real,
                "t0_im": t0.imag,
                "t0_available_re": t0_available.real,
                "t0_available_im": t0_available.imag,
                "flow_re": flow.real,
                "flow_im": flow.imag,
                "exact_re": exact,
                "flow_minus_exact_re": flow.real - exact,
                "flow_minus_t0_re": flow.real - t0.real,
                "flow_minus_t0_available_re": flow.real - t0_available.real,
            }
        )
    with csv_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    with md_path.open("w") as handle:
        handle.write("# Stephanov n=2 Flowed GH Quadrature Readback\n\n")
        handle.write(f"- order: `{order}`\n")
        handle.write(f"- flow_time: `{flow_time}`\n")
        handle.write(f"- rows: `{result['rows']}`\n")
        handle.write(f"- available_rows: `{result['available_rows']}`\n")
        handle.write(f"- unavailable_rows: `{result['unavailable_rows']}`\n")
        handle.write(f"- missing_gh_weight_fraction: `{result['missing_gh_weight_fraction']}`\n")
        handle.write(f"- missing_abs_t0_weight_fraction: `{result['missing_abs_t0_weight_fraction']}`\n")
        handle.write(f"- unavailable_record_preview: `{result['unavailable_record_preview']}`\n")
        handle.write(f"- denominator_t0: `{result['denominator_t0']}`\n")
        handle.write(f"- denominator_t0_available: `{result['denominator_t0_available']}`\n")
        handle.write(f"- denominator_flow: `{result['denominator_flow']}`\n")
        handle.write(f"- max_direct_weight0_abs: `{result['max_direct_weight0_abs']}`\n")
        handle.write(f"- max_direct_weight_abs: `{result['max_direct_weight_abs']}`\n\n")
        handle.write("| observable | t0 all Re | t0 available Re | flowed available Re | exact Re | flowed-exact Re | flowed-t0avail Re |\n")
        handle.write("|---|---:|---:|---:|---:|---:|---:|\n")
        for row in rows:
            handle.write(
                "| {observable} | {t0_re:.16g} | {t0_available_re:.16g} | {flow_re:.16g} | {exact_re:.16g} | {flow_minus_exact_re:.3e} | {flow_minus_t0_available_re:.3e} |\n".format(
                    **row
                )
            )
    return csv_path, md_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--parameters-file", default="data/parameters_stephanov_n2_smoke.dat")
    parser.add_argument("--binary", default="bin/build_flow_bank_dense")
    parser.add_argument("--order", type=int, default=3)
    parser.add_argument("--flow-time", type=float, default=5.5e-4)
    parser.add_argument("--n-model", type=int, default=2)
    parser.add_argument("--nf", type=int, default=1)
    parser.add_argument("--mass", type=float, default=0.2)
    parser.add_argument("--mu", type=float, default=0.3)
    parser.add_argument("--tau", type=float, default=0.1)
    parser.add_argument("--allow-missing", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()

    out_dir = Path(args.output_root)
    out_dir.mkdir(parents=True, exist_ok=True)
    state_size = 2 * args.n_model * args.n_model
    x_bank, weights_csv, count = generate_gh_bank(out_dir, args.order, args.n_model)
    bank_dir = out_dir / f"flow_bank_t{args.flow_time:g}_k{args.order}"
    env = os.environ.copy()
    env["TLTM_PARAMETERS_FILE"] = args.parameters_file
    if not args.skip_build:
        subprocess.run(
            [
                args.binary,
                str(x_bank),
                str(bank_dir),
                "{:.17g}".format(args.flow_time),
                "0",
                str(count),
            ],
            check=True,
            env=env,
        )
    result = analyze_flow_bank(
        bank_dir,
        weights_csv,
        0,
        state_size,
        args.n_model,
        args.nf,
        args.mass,
        args.mu,
        args.tau,
        args.allow_missing,
    )
    csv_path, md_path = write_outputs(out_dir, result, args.order, args.flow_time)
    print(f"summary_csv={csv_path}")
    print(f"readback_md={md_path}")


if __name__ == "__main__":
    main()

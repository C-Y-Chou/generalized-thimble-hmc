#!/usr/bin/env python3
"""Deterministic WV-HMC nonzero-W reweighting identity check.

This is not a Markov-chain run.  It builds a small flowed Gauss-Hermite bank at
several flow-time quadrature nodes and verifies, point by point, that

    exp(-Re S - W) * alpha * |det J|
      * [exp(-i Im S) * detJ/|detJ| / alpha]

reconstructs the W-weighted direct flowed-contour integrand
exp(-S - W) detJ.  This catches accidental W leakage into the measurement
factor, the alpha convention, and the
Jacobian phase convention without relying on finite-chain convergence.
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


def offset_x(i, j, n_model):
    return j * n_model + i


def offset_y(i, j, n_model):
    return n_model * n_model + j * n_model + i


def stephanov_ab_grouped(z, n_model, mass, mu, tau):
    del mass
    a = [[0.0 + 0.0j for _ in range(n_model)] for _ in range(n_model)]
    b = [[0.0 + 0.0j for _ in range(n_model)] for _ in range(n_model)]
    half_n = n_model // 2
    c_diag = [tau - 1j * mu if i < half_n else -tau - 1j * mu for i in range(n_model)]
    for j in range(n_model):
        for i in range(n_model):
            zx = z[offset_x(i, j, n_model)]
            zy = z[offset_y(i, j, n_model)]
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


def inverse_matrix(mat):
    n = len(mat)
    a = [list(row) + [1.0 + 0.0j if row_idx == col_idx else 0.0 + 0.0j for col_idx in range(n)]
         for row_idx, row in enumerate(mat)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(a[r][col]))
        if abs(a[pivot][col]) == 0.0:
            raise ZeroDivisionError("singular matrix")
        if pivot != col:
            a[col], a[pivot] = a[pivot], a[col]
        pivot_value = a[col][col]
        for j in range(2 * n):
            a[col][j] /= pivot_value
        for row in range(n):
            if row == col:
                continue
            factor = a[row][col]
            if factor == 0.0:
                continue
            for j in range(2 * n):
                a[row][j] -= factor * a[col][j]
    return [row[n:] for row in a]


def stephanov_dirac(z, n_model, mass, mu, tau):
    a, b = stephanov_ab_grouped(z, n_model, mass, mu, tau)
    dim = 2 * n_model
    d = [[0.0 + 0.0j for _ in range(dim)] for _ in range(dim)]
    for i in range(n_model):
        d[i][i] = mass
        d[n_model + i][n_model + i] = mass
    for i in range(n_model):
        for j in range(n_model):
            d[i][n_model + j] = 1j * a[i][j]
            d[n_model + i][j] = 1j * b[i][j]
    return d


def stephanov_gradient(z, n_model, nf, mass, mu, tau):
    d_inv = inverse_matrix(stephanov_dirac(z, n_model, mass, mu, tau))
    grad = [0.0 + 0.0j for _ in z]
    for j in range(n_model):
        for i in range(n_model):
            ox = offset_x(i, j, n_model)
            oy = offset_y(i, j, n_model)
            grad[ox] = 2.0 * float(n_model) * z[ox] - float(nf) * 1j * (
                d_inv[n_model + j][i] + d_inv[i][n_model + j]
            )
            grad[oy] = 2.0 * float(n_model) * z[oy] - float(nf) * (
                d_inv[i][n_model + j] - d_inv[n_model + j][i]
            )
    return grad


def stephanov_observables(z, n_model, mass, mu, tau):
    a, b = stephanov_ab_grouped(z, n_model, mass, mu, tau)
    q = matmul(b, a)
    for i in range(n_model):
        q[i][i] += mass * mass
    q_inv = inverse_matrix(q)
    chiral = (mass / float(n_model)) * trace(q_inv)
    a_plus_b = [[a[i][j] + b[i][j] for j in range(n_model)] for i in range(n_model)]
    density = mu - 1j / (2.0 * float(n_model)) * trace(matmul(q_inv, a_plus_b))
    return chiral, density


def action_value(z, n_model, nf, mass, mu, tau):
    dirac = stephanov_dirac(z, n_model, mass, mu, tau)
    quad = sum(value * value for value in z)
    return float(n_model) * quad - float(nf) * cmath.log(det_matrix(dirac))


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


def legendre_interval(order, t0, t1):
    if order == 3:
        nodes = [-math.sqrt(3.0 / 5.0), 0.0, math.sqrt(3.0 / 5.0)]
        weights = [5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0]
    elif order == 5:
        nodes = [
            -math.sqrt(5.0 + 2.0 * math.sqrt(10.0 / 7.0)) / 3.0,
            -math.sqrt(5.0 - 2.0 * math.sqrt(10.0 / 7.0)) / 3.0,
            0.0,
            math.sqrt(5.0 - 2.0 * math.sqrt(10.0 / 7.0)) / 3.0,
            math.sqrt(5.0 + 2.0 * math.sqrt(10.0 / 7.0)) / 3.0,
        ]
        weights = [
            (322.0 - 13.0 * math.sqrt(70.0)) / 900.0,
            (322.0 + 13.0 * math.sqrt(70.0)) / 900.0,
            128.0 / 225.0,
            (322.0 + 13.0 * math.sqrt(70.0)) / 900.0,
            (322.0 - 13.0 * math.sqrt(70.0)) / 900.0,
        ]
    else:
        raise ValueError("supported t orders are 3 and 5")
    midpoint = 0.5 * (t0 + t1)
    half_width = 0.5 * (t1 - t0)
    return [midpoint + half_width * node for node in nodes], [half_width * weight for weight in weights]


def generate_gh_bank(out_dir, order, n_model):
    dim = 2 * n_model * n_model
    nodes, weights = hermgauss(order)
    x_bank = out_dir / f"stephanov_n2_grouped_gh_k{order}_x_bank.dat"
    weights_csv = out_dir / f"stephanov_n2_grouped_gh_k{order}_weights.csv"
    scale = math.sqrt(float(n_model))
    count = order ** dim
    with x_bank.open("wb") as bank, weights_csv.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["source_record", "weight"])
        for rec, multi_idx in enumerate(itertools.product(range(order), repeat=dim)):
            x = [nodes[i] / scale for i in multi_idx]
            weight = 1.0
            for idx in multi_idx:
                weight *= weights[idx]
            bank.write(struct.pack("<" + "d" * dim, *x))
            writer.writerow([rec, "{:.17e}".format(weight)])
    return x_bank, weights_csv, count


def read_slot(path, state_size):
    raw = path.read_bytes()
    int_count = 11
    header_bytes = 4 * int_count + 8
    ints = struct.unpack("<" + "i" * int_count, raw[: 4 * int_count])
    target_time = struct.unpack("<d", raw[4 * int_count:header_bytes])[0]
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


def solve_real_system(mat, rhs):
    n = len(rhs)
    a = [list(mat[i]) + [rhs[i]] for i in range(n)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(a[r][col]))
        if abs(a[pivot][col]) == 0.0:
            raise ZeroDivisionError("singular real system")
        if pivot != col:
            a[col], a[pivot] = a[pivot], a[col]
        pivot_value = a[col][col]
        for j in range(col, n + 1):
            a[col][j] /= pivot_value
        for row in range(n):
            if row == col:
                continue
            factor = a[row][col]
            if factor == 0.0:
                continue
            for j in range(col, n + 1):
                a[row][j] -= factor * a[col][j]
    return [row[n] for row in a]


def alpha_from_jacobian_and_xi(jac, xi):
    state_size = len(xi)
    xi_real = []
    for value in xi:
        xi_real.extend([value.real, value.imag])
    columns = []
    for col in range(state_size):
        vector = []
        for row in range(state_size):
            vector.extend([jac[row][col].real, jac[row][col].imag])
        columns.append(vector)
    gram = [[sum(columns[i][k] * columns[j][k] for k in range(2 * state_size)) for j in range(state_size)]
            for i in range(state_size)]
    rhs = [sum(columns[i][k] * xi_real[k] for k in range(2 * state_size)) for i in range(state_size)]
    coeff = solve_real_system(gram, rhs)
    tangent = [sum(coeff[j] * columns[j][k] for j in range(state_size)) for k in range(2 * state_size)]
    normal = [xi_real[k] - tangent[k] for k in range(2 * state_size)]
    alpha2 = sum(value * value for value in normal)
    if not math.isfinite(alpha2) or alpha2 <= 0.0:
        raise ValueError("invalid alpha2")
    return math.sqrt(alpha2), alpha2


def paper_wall_value(flow_time, t0, t1, d0, d1, gamma, c0, c1):
    value = -gamma * (flow_time - t0)
    derivative = -gamma
    if flow_time < t0:
        distance = flow_time - t0
        exp_value = math.exp(0.5 * distance * distance / (d0 * d0))
        value += c0 * (exp_value - 1.0)
        derivative += c0 * exp_value * distance / (d0 * d0)
    elif flow_time > t1:
        distance = flow_time - t1
        exp_value = math.exp(0.5 * distance * distance / (d1 * d1))
        value += c1 * (exp_value - 1.0)
        derivative += c1 * exp_value * distance / (d1 * d1)
    return value, derivative


def cdiv(num, den):
    return num / den if den != 0 else complex(float("nan"), float("nan"))


def analyze(args, bank_dir, weights_csv, target_times, t_weights):
    state_size = 2 * args.n_model * args.n_model
    gamma_values = [float(text) for text in args.gamma_values.split(",") if text.strip()]
    rows_by_gamma = []
    totals = {
        gamma: {
            "direct_D": 0.0 + 0.0j,
            "direct_chiral_N": 0.0 + 0.0j,
            "direct_density_N": 0.0 + 0.0j,
            "wv_D": 0.0 + 0.0j,
            "wv_chiral_N": 0.0 + 0.0j,
            "wv_density_N": 0.0 + 0.0j,
            "wrong_D": 0.0 + 0.0j,
            "wrong_chiral_N": 0.0 + 0.0j,
            "wrong_density_N": 0.0 + 0.0j,
            "no_w_D": 0.0 + 0.0j,
            "no_w_chiral_N": 0.0 + 0.0j,
            "no_w_density_N": 0.0 + 0.0j,
            "max_pointwise_rel_error": 0.0,
            "max_wrong_pointwise_rel_error": 0.0,
            "min_alpha": float("inf"),
            "max_alpha": 0.0,
            "samples": 0,
            "unavailable_slots": 0,
        }
        for gamma in gamma_values
    }
    with weights_csv.open() as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            rec = int(row["source_record"])
            gh_weight = float(row["weight"])
            for slot_id, t_weight in enumerate(t_weights):
                slot = bank_dir / "records" / f"record_{rec:06d}" / f"slot_{slot_id:06d}.bin"
                available, flow_time, x, z, jac = read_slot(slot, state_size)
                if available != 1:
                    if not args.allow_missing:
                        raise RuntimeError(f"unavailable flow slot: rec={rec} slot={slot_id} t={flow_time}")
                    for total in totals.values():
                        total["unavailable_slots"] += 1
                    continue
                chiral, density = stephanov_observables(z, args.n_model, args.mass, args.mu, args.tau)
                action = action_value(z, args.n_model, args.nf, args.mass, args.mu, args.tau)
                det_j = det_matrix(jac)
                grad = stephanov_gradient(z, args.n_model, args.nf, args.mass, args.mu, args.tau)
                xi = [value.conjugate() for value in grad]
                alpha, _alpha2 = alpha_from_jacobian_and_xi(jac, xi)
                base = gh_weight * t_weight * math.exp(float(args.n_model) * sum(value * value for value in x))
                phase = cmath.exp(-1j * action.imag) * det_j / abs(det_j)
                for gamma in gamma_values:
                    w_value, _wprime = paper_wall_value(
                        flow_time, args.t0, args.t1, args.d0, args.d1, gamma, args.c0, args.c1
                    )
                    direct_weight = base * cmath.exp(-action - w_value) * det_j
                    positive_weight = base * math.exp(-action.real - w_value) * alpha * abs(det_j)
                    correct_weight = positive_weight * phase / alpha
                    wrong_weight = positive_weight * math.exp(w_value) * phase / alpha
                    no_w_weight = correct_weight
                    total = totals[gamma]
                    total["direct_D"] += direct_weight
                    total["direct_chiral_N"] += direct_weight * chiral
                    total["direct_density_N"] += direct_weight * density
                    total["wv_D"] += correct_weight
                    total["wv_chiral_N"] += correct_weight * chiral
                    total["wv_density_N"] += correct_weight * density
                    total["wrong_D"] += wrong_weight
                    total["wrong_chiral_N"] += wrong_weight * chiral
                    total["wrong_density_N"] += wrong_weight * density
                    total["no_w_D"] += no_w_weight
                    total["no_w_chiral_N"] += no_w_weight * chiral
                    total["no_w_density_N"] += no_w_weight * density
                    scale = max(1.0, abs(direct_weight))
                    total["max_pointwise_rel_error"] = max(
                        total["max_pointwise_rel_error"], abs(correct_weight - direct_weight) / scale
                    )
                    total["max_wrong_pointwise_rel_error"] = max(
                        total["max_wrong_pointwise_rel_error"], abs(wrong_weight - direct_weight) / scale
                    )
                    total["min_alpha"] = min(total["min_alpha"], alpha)
                    total["max_alpha"] = max(total["max_alpha"], alpha)
                    total["samples"] += 1
    for gamma, total in totals.items():
        direct_chiral = cdiv(total["direct_chiral_N"], total["direct_D"])
        direct_density = cdiv(total["direct_density_N"], total["direct_D"])
        wv_chiral = cdiv(total["wv_chiral_N"], total["wv_D"])
        wv_density = cdiv(total["wv_density_N"], total["wv_D"])
        wrong_chiral = cdiv(total["wrong_chiral_N"], total["wrong_D"])
        wrong_density = cdiv(total["wrong_density_N"], total["wrong_D"])
        no_w_chiral = cdiv(total["no_w_chiral_N"], total["no_w_D"])
        no_w_density = cdiv(total["no_w_density_N"], total["no_w_D"])
        rows_by_gamma.append({
            "gamma": gamma,
            "samples": total["samples"],
            "unavailable_slots": total["unavailable_slots"],
            "direct_chiral_re": direct_chiral.real,
            "direct_chiral_im": direct_chiral.imag,
            "wv_chiral_re": wv_chiral.real,
            "wv_chiral_im": wv_chiral.imag,
            "wrong_chiral_re": wrong_chiral.real,
            "wrong_chiral_im": wrong_chiral.imag,
            "no_w_chiral_re": no_w_chiral.real,
            "no_w_chiral_im": no_w_chiral.imag,
            "direct_density_re": direct_density.real,
            "direct_density_im": direct_density.imag,
            "wv_density_re": wv_density.real,
            "wv_density_im": wv_density.imag,
            "wrong_density_re": wrong_density.real,
            "wrong_density_im": wrong_density.imag,
            "no_w_density_re": no_w_density.real,
            "no_w_density_im": no_w_density.imag,
            "max_direct_minus_wv_abs": max(
                abs(direct_chiral - wv_chiral), abs(direct_density - wv_density)
            ),
            "max_wrong_minus_direct_abs": max(
                abs(direct_chiral - wrong_chiral), abs(direct_density - wrong_density)
            ),
            "max_no_w_minus_direct_abs": max(
                abs(direct_chiral - no_w_chiral), abs(direct_density - no_w_density)
            ),
            "max_pointwise_rel_error": total["max_pointwise_rel_error"],
            "max_wrong_pointwise_rel_error": total["max_wrong_pointwise_rel_error"],
            "min_alpha": total["min_alpha"],
            "max_alpha": total["max_alpha"],
            "direct_minus_exact_chiral_re": direct_chiral.real - EXACT_CHIRAL,
            "direct_minus_exact_density_re": direct_density.real - EXACT_DENSITY,
        })
    return rows_by_gamma


def write_outputs(out_dir, args, rows, target_times):
    csv_path = out_dir / "wv_nonzero_w_reweight_identity.csv"
    md_path = out_dir / "wv_nonzero_w_reweight_identity.md"
    fields = list(rows[0].keys()) if rows else []
    with csv_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    with md_path.open("w") as handle:
        handle.write("# WV-HMC Nonzero-W Reweight Identity\n\n")
        handle.write("This deterministic check uses grouped Fortran Stephanov state ordering.\n\n")
        handle.write(f"- GH order: `{args.order}`\n")
        handle.write(f"- t order: `{args.t_order}`\n")
        handle.write(f"- T0/T1: `{args.t0}` / `{args.t1}`\n")
        handle.write(f"- target_times: `{','.join(f'{t:.17g}' for t in target_times)}`\n\n")
        handle.write("| gamma | samples | skipped slots | max pointwise direct-WV rel err | max obs direct-WV abs | max obs exp(+W)-direct abs | direct chiral Re | direct density Re | min alpha | max alpha |\n")
        handle.write("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n")
        for row in rows:
            handle.write(
                "| {gamma:.8g} | {samples} | {unavailable_slots} | {max_pointwise_rel_error:.3e} | {max_direct_minus_wv_abs:.3e} | {max_wrong_minus_direct_abs:.3e} | {direct_chiral_re:.16g} | {direct_density_re:.16g} | {min_alpha:.3e} | {max_alpha:.3e} |\n".format(
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
    parser.add_argument("--t-order", type=int, default=3)
    parser.add_argument("--t0", type=float, default=1.0e-4)
    parser.add_argument("--t1", type=float, default=1.0e-3)
    parser.add_argument("--d0", type=float, default=1.0e-4)
    parser.add_argument("--d1", type=float, default=2.5e-4)
    parser.add_argument("--c0", type=float, default=1.0)
    parser.add_argument("--c1", type=float, default=1.0)
    parser.add_argument("--gamma-values", default="0,0.02,0.2,20")
    parser.add_argument("--allow-missing", action="store_true")
    parser.add_argument("--n-model", type=int, default=2)
    parser.add_argument("--nf", type=int, default=1)
    parser.add_argument("--mass", type=float, default=0.2)
    parser.add_argument("--mu", type=float, default=0.3)
    parser.add_argument("--tau", type=float, default=0.1)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()

    out_dir = Path(args.output_root)
    out_dir.mkdir(parents=True, exist_ok=True)
    target_times, t_weights = legendre_interval(args.t_order, args.t0, args.t1)
    x_bank, weights_csv, count = generate_gh_bank(out_dir, args.order, args.n_model)
    bank_dir = out_dir / f"flow_bank_torder{args.t_order}_k{args.order}"
    if not args.skip_build:
        env = os.environ.copy()
        env["TLTM_PARAMETERS_FILE"] = args.parameters_file
        subprocess.run(
            [
                args.binary,
                str(x_bank),
                str(bank_dir),
                ",".join("{:.17g}".format(value) for value in target_times),
                "0",
                str(count),
            ],
            check=True,
            env=env,
        )
    rows = analyze(args, bank_dir, weights_csv, target_times, t_weights)
    csv_path, md_path = write_outputs(out_dir, args, rows, target_times)
    print(f"summary_csv={csv_path}")
    print(f"readback_md={md_path}")


if __name__ == "__main__":
    main()

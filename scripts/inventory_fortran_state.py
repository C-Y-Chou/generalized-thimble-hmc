#!/usr/bin/env python3
"""Inventory Fortran state, RNG, env, and config coupling surfaces.

This is a conservative source scanner for modernization planning. It does not
try to fully parse Fortran; it records high-risk patterns that need explicit
ownership before M5 context/state refactors.
"""

import argparse
import csv
import re
from collections import Counter
from pathlib import Path


DECL_SAVE_RE = re.compile(r"\bsave\b\s*::\s*(.*)", re.IGNORECASE)
MODULE_RE = re.compile(r"^\s*module\s+([a-z_][a-z0-9_]*)\b", re.IGNORECASE)
PROGRAM_UNIT_RE = re.compile(r"^\s*(program|subroutine|function)\s+([a-z_][a-z0-9_]*)\b", re.IGNORECASE)
END_PROGRAM_UNIT_RE = re.compile(r"^\s*end\s*(program|subroutine|function)\b", re.IGNORECASE)
USE_PARAM_RE = re.compile(r"^\s*use\s+param_mod\b(.*)", re.IGNORECASE)
GET_ENV_RE = re.compile(r"\bget_environment_variable\s*\(", re.IGNORECASE)
RNG_RE = re.compile(r"\b(random_number|random_seed|sgrnd|grnd|getseed)\b", re.IGNORECASE)
QUOTED_RE = re.compile(r"['\"]([^'\"]+)['\"]")


def parse_args():
    parser = argparse.ArgumentParser(description="Inventory TLTM Fortran state and ownership surfaces.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--out-tsv", required=True, help="TSV output path.")
    parser.add_argument("--out-summary", required=True, help="Markdown summary output path.")
    parser.add_argument("--include-tests", action="store_true", help="Include tests/*.f90.")
    return parser.parse_args()


def strip_comment(line):
    in_single = False
    in_double = False
    for idx, ch in enumerate(line):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "!" and not in_single and not in_double:
            return line[:idx]
    return line


def split_top_level(text, sep=","):
    parts = []
    start = 0
    paren_depth = 0
    bracket_depth = 0
    in_single = False
    in_double = False
    for idx, ch in enumerate(text):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif not in_single and not in_double:
            if ch == "(":
                paren_depth += 1
            elif ch == ")" and paren_depth > 0:
                paren_depth -= 1
            elif ch == "[":
                bracket_depth += 1
            elif ch == "]" and bracket_depth > 0:
                bracket_depth -= 1
            elif ch == sep and paren_depth == 0 and bracket_depth == 0:
                parts.append(text[start:idx])
                start = idx + 1
    parts.append(text[start:])
    return parts


def strip_top_level_initializer(text):
    return split_top_level(text, sep="=")[0]


def split_decl_names(text):
    names = []
    for part in split_top_level(text):
        token = part.strip()
        if not token:
            continue
        token = strip_top_level_initializer(token).strip()
        token = token.split("(", 1)[0].strip()
        if token:
            names.append(token)
    return names


def classify(file_path, kind, name):
    text = "{0} {1}".format(file_path, name).lower()
    if "param_mod" in text or name == "config":
        return "config_global"
    if "mt95" in text or kind == "rng_call":
        return "rng"
    if "model_generated" in text or "model_tape_ad" in text or "tape_" in text:
        return "model_tape_cache"
    if "solve_flow" in text or "odex" in text or "intode" in text or name.startswith("flow_"):
        return "flow_workspace_or_counter"
    if "quasi_newton" in text or name.startswith("quasi_") or name.startswith("qn_"):
        return "quasi_newton_workspace_or_counter"
    if "hmc_constraints" in text or "newton_" in text or name in ("b", "xtu", "u", "dxi", "ld"):
        return "newton_workspace_or_counter"
    if "hmc_reversibility" in text or "probe_" in text or "progress_diag" in text:
        return "diagnostic_policy"
    if "perf_profile" in text or name.startswith("perf_"):
        return "diagnostic_policy"
    if "env" in kind:
        return "runtime_env"
    return "unclassified_state"


def source_files(repo_root, include_tests):
    roots = [repo_root / "src"]
    if include_tests:
        roots.append(repo_root / "tests")
    files = []
    for root in roots:
        files.extend(sorted(root.rglob("*.f90")))
    return files


def scan_file(repo_root, path):
    rel = path.relative_to(repo_root)
    module_name = ""
    program_unit = ""
    in_module_decls = False
    rows = []
    for line_no, raw in enumerate(path.read_text().splitlines(), start=1):
        code = strip_comment(raw)
        low = code.lower().strip()
        if not low:
            continue

        module_match = MODULE_RE.match(code)
        if module_match and not low.startswith("module procedure"):
            module_name = module_match.group(1)
            in_module_decls = True
            program_unit = ""

        if low == "contains":
            in_module_decls = False

        unit_match = PROGRAM_UNIT_RE.match(code)
        if unit_match and not low.startswith("module procedure"):
            program_unit = "{0}:{1}".format(unit_match.group(1).lower(), unit_match.group(2))

        if END_PROGRAM_UNIT_RE.match(code):
            program_unit = ""

        save_match = DECL_SAVE_RE.search(code)
        if save_match:
            scope = "module" if in_module_decls and not program_unit else "procedure"
            for name in split_decl_names(save_match.group(1)):
                rows.append(
                    {
                        "file": str(rel),
                        "line": line_no,
                        "module": module_name,
                        "program_unit": program_unit,
                        "kind": "save_declaration",
                        "name": name,
                        "scope": scope,
                        "category": classify(str(rel), "save_declaration", name),
                        "raw": raw.strip(),
                    }
                )

        if GET_ENV_RE.search(code):
            quoted = QUOTED_RE.findall(code)
            env_name = quoted[0] if quoted else "(dynamic)"
            rows.append(
                {
                    "file": str(rel),
                    "line": line_no,
                    "module": module_name,
                    "program_unit": program_unit,
                    "kind": "env_read",
                    "name": env_name,
                    "scope": "procedure" if program_unit else "module",
                    "category": classify(str(rel), "env_read", env_name),
                    "raw": raw.strip(),
                }
            )

        use_match = USE_PARAM_RE.match(code)
        if use_match:
            rows.append(
                {
                    "file": str(rel),
                    "line": line_no,
                    "module": module_name,
                    "program_unit": program_unit,
                    "kind": "param_mod_import",
                    "name": use_match.group(1).strip() or "(bare)",
                    "scope": "procedure" if program_unit else "module",
                    "category": "config_global",
                    "raw": raw.strip(),
                }
            )

        rng_match = RNG_RE.search(code)
        if rng_match:
            rows.append(
                {
                    "file": str(rel),
                    "line": line_no,
                    "module": module_name,
                    "program_unit": program_unit,
                    "kind": "rng_call",
                    "name": rng_match.group(1).lower(),
                    "scope": "procedure" if program_unit else "module",
                    "category": classify(str(rel), "rng_call", rng_match.group(1)),
                    "raw": raw.strip(),
                }
            )

    return rows


def write_tsv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = ["file", "line", "module", "program_unit", "kind", "name", "scope", "category", "raw"]
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns, delimiter="\t")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_summary(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    by_kind = Counter(row["kind"] for row in rows)
    by_category = Counter(row["category"] for row in rows)
    save_by_file = Counter(row["file"] for row in rows if row["kind"] == "save_declaration")
    env_by_file = Counter(row["file"] for row in rows if row["kind"] == "env_read")
    rng_by_file = Counter(row["file"] for row in rows if row["kind"] == "rng_call")

    lines = [
        "# M5 State And Config Ownership Inventory Summary",
        "",
        "Generated by `scripts/inventory_fortran_state.py`.",
        "",
        "## Counts By Kind",
        "",
    ]
    for key, value in sorted(by_kind.items()):
        lines.append("- `{0}`: {1}".format(key, value))
    lines.extend(["", "## Counts By Category", ""])
    for key, value in sorted(by_category.items()):
        lines.append("- `{0}`: {1}".format(key, value))
    lines.extend(["", "## Save Declarations By File", ""])
    for key, value in save_by_file.most_common():
        lines.append("- `{0}`: {1}".format(key, value))
    lines.extend(["", "## Env Reads By File", ""])
    for key, value in env_by_file.most_common():
        lines.append("- `{0}`: {1}".format(key, value))
    lines.extend(["", "## RNG Calls By File", ""])
    for key, value in rng_by_file.most_common():
        lines.append("- `{0}`: {1}".format(key, value))
    lines.append("")
    path.write_text("\n".join(lines))


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    rows = []
    for path in source_files(repo_root, args.include_tests):
        rows.extend(scan_file(repo_root, path))
    rows = sorted(rows, key=lambda row: (row["file"], int(row["line"]), row["kind"], row["name"]))
    write_tsv(Path(args.out_tsv), rows)
    write_summary(Path(args.out_summary), rows)
    print("[DONE] wrote {0} inventory rows".format(len(rows)))


if __name__ == "__main__":
    main()

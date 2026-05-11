#!/usr/bin/env python3
"""Read back the installed official DFO-LS package provenance.

This script records the package version/license visible to the Python
interpreter used by the embedded TLTM bridge. It does not run a solver case.
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path


EXPECTED_VERSION = "1.6.5"
EXPECTED_LICENSE = "GPL-3.0-or-later"


def parse_args():
    parser = argparse.ArgumentParser(description="Read official DFO-LS package provenance.")
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument(
        "--python",
        default="",
        help="Python executable to inspect. Defaults to .venv-dfols/bin/python when present, else current Python.",
    )
    parser.add_argument(
        "--state-out",
        default="codex/workspaces/fortran_modernization/state/OFFICIAL_DFOLS_PROVENANCE.tsv",
        help="Output TSV path relative to repo root, or absolute.",
    )
    parser.add_argument(
        "--runbook-out",
        default="codex/workspaces/fortran_modernization/runbooks/OFFICIAL_DFOLS_PROVENANCE_READBACK_20260511.md",
        help="Output Markdown runbook path relative to repo root, or absolute.",
    )
    return parser.parse_args()


def resolve_path(repo_root, path_text):
    path = Path(path_text)
    if path.is_absolute():
        return path
    return repo_root / path


def default_python(repo_root):
    venv_python = repo_root / ".venv-dfols" / "bin" / "python"
    if venv_python.exists():
        return str(venv_python)
    return sys.executable


def collect_package_info(python_exe):
    probe_code = r'''
import json
import sys

data = {
    "python_executable": sys.executable,
    "python_version": sys.version.split()[0],
    "import_ok": False,
    "module_file": "",
    "module_version": "",
    "dist_version": "",
    "dist_license": "",
    "error": "",
}

try:
    import dfols
    data["import_ok"] = True
    data["module_file"] = getattr(dfols, "__file__", "") or ""
    data["module_version"] = getattr(dfols, "__version__", "") or ""
except Exception as exc:
    data["error"] = type(exc).__name__ + ": " + str(exc)

try:
    try:
        import importlib.metadata as metadata
    except Exception:
        import importlib_metadata as metadata
    try:
        data["dist_version"] = metadata.version("DFO-LS")
        meta = metadata.metadata("DFO-LS")
        data["dist_license"] = meta.get("License", "") or ""
    except Exception as exc:
        if not data["error"]:
            data["error"] = type(exc).__name__ + ": " + str(exc)
except Exception as exc:
    if not data["error"]:
        data["error"] = type(exc).__name__ + ": " + str(exc)

print(json.dumps(data, sort_keys=True))
'''
    output = subprocess.check_output([python_exe, "-c", probe_code], universal_newlines=True)
    return json.loads(output)


def jst_now_text():
    jst = timezone(timedelta(hours=9))
    return datetime.now(jst).strftime("%Y-%m-%d %H:%M:%S JST")


def status_from_info(info):
    version = info.get("dist_version") or info.get("module_version")
    license_text = info.get("dist_license", "")
    if not info.get("import_ok"):
        return "fail_import"
    if version != EXPECTED_VERSION:
        return "fail_version"
    if license_text != EXPECTED_LICENSE:
        return "fail_license"
    return "pass"


def write_state(path, info, status):
    path.parent.mkdir(parents=True, exist_ok=True)
    headers = [
        "date_jst",
        "status",
        "expected_version",
        "expected_license",
        "python_executable",
        "python_version",
        "module_version",
        "dist_version",
        "dist_license",
        "module_file",
        "error",
    ]
    values = {
        "date_jst": jst_now_text(),
        "status": status,
        "expected_version": EXPECTED_VERSION,
        "expected_license": EXPECTED_LICENSE,
        "python_executable": info.get("python_executable", ""),
        "python_version": info.get("python_version", ""),
        "module_version": info.get("module_version", ""),
        "dist_version": info.get("dist_version", ""),
        "dist_license": info.get("dist_license", ""),
        "module_file": info.get("module_file", ""),
        "error": info.get("error", "") or "none",
    }
    with path.open("w") as f:
        f.write("\t".join(headers) + "\n")
        f.write("\t".join(str(values[h]) for h in headers) + "\n")


def write_runbook(path, state_path, info, status):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = """# Official DFO-LS Provenance Readback

Updated: {date_jst}

Scope: local/package provenance readback for the embedded official DFO-LS
backend. This is not a solver-performance gate and does not replace
representative captured-attempt or production-scale readback.

## Result

- status: `{status}`
- expected package: `DFO-LS=={expected_version}`
- expected license: `{expected_license}`
- Python executable: `{python_executable}`
- Python version: `{python_version}`
- module version: `{module_version}`
- distribution version: `{dist_version}`
- distribution license: `{dist_license}`
- module file: `{module_file}`
- state TSV: `{state_path}`

## Interpretation

This confirms the official package identity visible to the inspected Python
environment. Production runs still must record `TLTM_OFFICIAL_DFOLS_PYTHONPATH`
and use `ENABLE_OFFICIAL_DFOLS=1`, `QN_SOLVER_BACKEND=official_dfols`, and
`QN_OFFICIAL_DFOLS_PRESET=stable_gate77`.
""".format(
        date_jst=jst_now_text(),
        status=status,
        expected_version=EXPECTED_VERSION,
        expected_license=EXPECTED_LICENSE,
        python_executable=info.get("python_executable", ""),
        python_version=info.get("python_version", ""),
        module_version=info.get("module_version", ""),
        dist_version=info.get("dist_version", ""),
        dist_license=info.get("dist_license", ""),
        module_file=info.get("module_file", ""),
        state_path=state_path,
    )
    if info.get("error"):
        text += "\n## Error\n\n```text\n{0}\n```\n".format(info.get("error"))
    path.write_text(text)


def main():
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    python_exe = args.python or default_python(repo_root)
    state_out = resolve_path(repo_root, args.state_out)
    runbook_out = resolve_path(repo_root, args.runbook_out)

    info = collect_package_info(python_exe)
    status = status_from_info(info)
    write_state(state_out, info, status)
    write_runbook(runbook_out, state_out.relative_to(repo_root), info, status)
    print("[OFFICIAL_DFOLS_PROVENANCE] status={0}".format(status))
    print("[OFFICIAL_DFOLS_PROVENANCE] state={0}".format(state_out))
    print("[OFFICIAL_DFOLS_PROVENANCE] runbook={0}".format(runbook_out))
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

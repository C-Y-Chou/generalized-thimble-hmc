#!/usr/bin/env python3
"""Enzyme source-transformation backend adapter.

This adapter delegates to an external Enzyme-based generator command provided via
`ST_ENZYME_DRIVER` environment variable.

Expected contract for the driver command:
  <driver> --body <model_action_body.inc> --output <model_generated.f90>
"""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser(description="Run external Enzyme source-transform generator.")
    parser.add_argument("--body", required=True, help="Path to model_action_body.inc")
    parser.add_argument("--output", required=True, help="Path to output model_generated.f90")
    args = parser.parse_args()

    driver = os.environ.get("ST_ENZYME_DRIVER", "").strip()
    if not driver:
        raise RuntimeError(
            "ST_ENZYME_DRIVER is not set.\n"
            "Set it to an Enzyme-based generator command, e.g.\n"
            "  export ST_ENZYME_DRIVER='python3 /path/to/enzyme_codegen_driver.py'"
        )

    cmd = shlex.split(driver) + ["--body", args.body, "--output", args.output]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        msg = [
            f"Enzyme driver failed with exit code {proc.returncode}.",
            f"Command: {' '.join(shlex.quote(c) for c in cmd)}",
        ]
        if proc.stdout.strip():
            msg += ["--- stdout ---", proc.stdout.rstrip()]
        if proc.stderr.strip():
            msg += ["--- stderr ---", proc.stderr.rstrip()]
        raise RuntimeError("\n".join(msg))


if __name__ == "__main__":
    main()

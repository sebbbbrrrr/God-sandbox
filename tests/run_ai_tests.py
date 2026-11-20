#!/usr/bin/env python3
"""Run Godot AI regressions, rejecting script errors even if Godot exits with 0."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TESTS = {
    "simulation_test.gd": "SIMULATION_TESTS_PASSED",
    "citizen_ai_test.gd": "CITIZEN_AI_TESTS_PASSED",
    "citizen_cognition_test.gd": "COGNITION_TESTS_PASSED",
    "citizen_ai_500_trace.gd": "AI_BEHAVIOURAL_TRACE_PASSED",
    "citizen_ai_trace.gd": "AI_BEHAVIOURAL_TRACE_PASSED",
    "citizen_scalability_test.gd": "SCALABILITY_TESTS_PASSED",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot"))
    args = parser.parse_args()
    if not args.godot:
        parser.error("Pass --godot /path/to/Godot-4.5.2")
    failed = False
    for filename, marker in TESTS.items():
        result = subprocess.run(
            [args.godot, "--headless", "--path", str(ROOT), "--script", f"res://tests/{filename}"],
            capture_output=True, text=True, timeout=120,
        )
        output = result.stdout + result.stderr
        print(output, end="", flush=True)
        if result.returncode or "SCRIPT ERROR" in output or "ERROR:" in output or marker not in output:
            failed = True
            print(f"SUITE_FAILED: {filename}", file=sys.stderr)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())

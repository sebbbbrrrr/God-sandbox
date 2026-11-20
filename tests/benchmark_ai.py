#!/usr/bin/env python3
"""Sequential headless CPU/memory benchmarks; wall time never affects simulation decisions."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import time

try:
    import resource
except ImportError:
    resource = None

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot"))
    parser.add_argument("--ticks", type=int, default=900)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.godot:
        parser.error("Pass --godot /path/to/Godot-4.5.2")
    engine = subprocess.check_output([args.godot, "--version"], text=True).strip()
    document = {"engine": engine, "host": platform.platform(), "results": []}
    for population, dense in [(160, False), (500, False), (1500, False), (1500, True)]:
        command = [args.godot, "--headless", "--path", str(ROOT), "--script",
                   "res://tests/citizen_ai_benchmark.gd", "--", f"--population={population}",
                   f"--ticks={max(60, args.ticks)}"]
        if dense:
            command.append("--dense")
        before = resource.getrusage(resource.RUSAGE_CHILDREN) if resource else None
        start = time.monotonic()
        completed = subprocess.run(command, capture_output=True, text=True, timeout=180)
        output = completed.stdout + completed.stderr
        print(output, end="", flush=True)
        if completed.returncode or "SCRIPT ERROR" in output or "ERROR:" in output:
            raise SystemExit("Benchmark failed")
        line = next(line for line in output.splitlines() if line.startswith("AI_BENCHMARK "))
        result = json.loads(line.removeprefix("AI_BENCHMARK "))
        result["process_wall_seconds"] = time.monotonic() - start
        if resource:
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            result["process_cpu_seconds"] = after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime
            # POSIX getrusage reports a cumulative high-water mark, not this case's individual RSS.
            result["cumulative_child_peak_rss_kib"] = after.ru_maxrss
        document["results"].append(result)
        if args.output:
            args.output.write_text(json.dumps(document, indent=2) + "\n")
    print("AI_BENCHMARKS_PASSED", flush=True)


if __name__ == "__main__":
    main()

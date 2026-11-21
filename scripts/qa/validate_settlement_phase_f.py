#!/usr/bin/env python3
"""Run the Phase F settlement lifecycle and inherited regressions, fail closed."""
import argparse
import json
import pathlib
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--godot", default="godot")
parser.add_argument("--logs", default="/tmp/god-sandbox-phase-f-qa")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
logs = pathlib.Path(args.logs)
logs.mkdir(parents=True, exist_ok=True)
names = ["civilisation_premium_menu", "simulation", "citizen_ai", "citizen_cognition", "civilisation_calendar_lifecycle",
         "household_care", "food_survival", "autonomous_demography", "era_occupations",
         "item_catalogue", "physical_inventory", "construction", "toolmaking",
         "toolmaking_autonomy", "item_inspector", "game_item_ui", "unified_integration",
         "pinch_zoom_anchor", "universal_construction", "construction_animation",
         "regional_economy", "settlement_founding", "settlement_planning", "settlement_network_lifecycle", "settlement_family_farm", "rendering", "input", "civilisation_observatory"]
commands = [("import", ["--headless", "--editor", "--path", str(root), "--import", "--quit"])]
commands += [(n, ["--headless", "--path", str(root), "--script", f"res://tests/{n}_test.gd"]) for n in names]
commands += [("demo_scene", ["--headless", "--path", str(root), "res://scenes/settlement_demo.tscn", "--quit-after", "30"])]
results = []
for name, command in commands:
    start = time.monotonic()
    try:
        proc = subprocess.run([args.godot, *command], capture_output=True, cwd=root, timeout=90)
        output = (proc.stdout + proc.stderr).decode(errors="replace")
        passed = proc.returncode == 0 and not any(s in output for s in
            ["SCRIPT ERROR", "Parse Error", "FAILED:", "FAIL:", "Failed to load script"])
    except subprocess.TimeoutExpired as err:
        output = ((err.stdout or b"") + (err.stderr or b"")).decode(errors="replace")
        passed = False
    (logs / f"{name}.log").write_text(output)
    results.append({"suite": name, "passed": passed, "seconds": round(time.monotonic() - start, 3)})
    print(f'{name}: {"PASS" if passed else "FAIL"}', flush=True)
    if not passed:
        print(output[-3000:], flush=True)
    if name == "import" and not passed:
        break
report = {"scope": "F1-F7 early-age settlement runtime; Android hardware performance pending",
          "results": results, "passed": all(r["passed"] for r in results)}
(root / "docs/settlement-phase-f-validation.json").write_text(json.dumps(report, indent=2) + "\n")
raise SystemExit(0 if report["passed"] else 1)

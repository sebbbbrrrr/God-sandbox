#!/usr/bin/env python3
"""Instrument an isolated source copy. Inclusive timings are diagnostic, never benchmark claims."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# Explicit argument lists keep the copied wrappers readable and avoid parsing GDScript expressions.
SPECS = {
    'citizen_ai': {'sense':'world, person, state', 'interact':'world, person, other', 'step':'world, person, state'},
    'perception': {'observe':'state, cell, terrain_type, tick, visited, index, trim', 'finish_observation':'state', 'view':'world, pos', 'nearby':'world, person', 'begin_tick':'world'},
    'decision_engine': {'choose':'world, person, state, nearby, urgent'},
    'navigation': {'next_step':'world, person, state, target', 'plan':'world, state, start, target'},
    'emotions': {'advance':'state, tick'},
    'relationships': {'advance':'state, tick', 'find':'state, id'},
    'memory': {'advance':'state, tick'},
}

def instrument(root):
    for module, functions in SPECS.items():
        path = root / 'scripts/ai' / (module + '.gd')
        source = path.read_text() + '\nstatic var profile_stats: Dictionary = {}\n'
        for name, arguments in functions.items():
            pattern = r'(?m)^((?:static )?func )' + name + r'(\([\s\S]*?\) -> ([\w\[\]]+):)'
            match = re.search(pattern, source)
            if not match:
                raise RuntimeError(f'Missing {module}.{name}')
            declaration, tail, result_type = match.groups()
            if name == 'step' and 'scheduled:' in tail:
                arguments += ', scheduled'
            if name == 'choose' and 'known_index:' in tail:
                arguments += ', known_index, diagnostics'
            if name == 'finish_observation' and 'index:' in tail:
                arguments += ', index'
            source = source[:match.start()] + declaration + '_profile_' + name + tail + source[match.end():]
            source += '\n' + declaration + name + tail + '\n    var started := Time.get_ticks_usec()\n'
            call = '_profile_' + name + '(' + arguments + ')'
            source += ('    ' + call if result_type == 'void' else '    var result = ' + call) + '\n'
            source += f'    var data: Array = profile_stats.get("{name}", [0, 0])\n    data[0] += Time.get_ticks_usec() - started\n    data[1] += 1\n    profile_stats["{name}"] = data\n'
            if result_type != 'void':
                source += '    return result\n'
        path.write_text(source)
    path = root / 'tests/citizen_ai_benchmark.gd'
    source = path.read_text()
    prints = ''
    for module in SPECS:
        prints += f'    print("AI_PROFILE {module} ", JSON.stringify(load("res://scripts/ai/{module}.gd").profile_stats))\n'
    source = source.replace('    print("AI_BENCHMARK ",', prints + '    print("AI_BENCHMARK ",')
    path.write_text(source)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--source', type=Path, default=ROOT)
    parser.add_argument('--population', type=int, default=1500)
    parser.add_argument('--ticks', type=int, default=180)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='citizen-ai-profile-') as folder:
        root = Path(folder)
        shutil.copytree(args.source, root, dirs_exist_ok=True, ignore=shutil.ignore_patterns('.git', '.godot', '__pycache__'))
        (root / '.godot').mkdir()
        shutil.copyfile(args.source / '.godot/global_script_class_cache.cfg', root / '.godot/global_script_class_cache.cfg')
        instrument(root)
        run = subprocess.run([args.godot, '--headless', '--path', str(root), '--script', 'res://tests/citizen_ai_benchmark.gd', '--', f'--population={args.population}', f'--ticks={args.ticks}'], capture_output=True, text=True, timeout=180)
        output = run.stdout + run.stderr
        print(output)
        if run.returncode or 'ERROR:' in output or 'SCRIPT ERROR' in output:
            raise SystemExit(1)

if __name__ == '__main__':
    main()

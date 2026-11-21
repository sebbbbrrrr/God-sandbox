#!/usr/bin/env python3
"""Godot 4.5.2 architecture QA; fail on script errors even when Godot returns 0."""
import argparse,json,os,shutil,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SUITES=['architecture_integration','simulation','universal_construction','construction_animation','workforce_distribution','item_catalogue','physical_inventory','toolmaking','toolmaking_autonomy','era_occupations','food_survival','settlement_founding','settlement_planning','settlement_family_farm','settlement_network_lifecycle','regional_economy','rendering','civilisation_observatory','civilisation_premium_menu','unified_integration','game_item_ui','item_inspector','pinch_zoom_anchor','civilisation_calendar_lifecycle','household_care','autonomous_demography','construction']
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--godot',default=os.environ.get('GODOT_BIN') or shutil.which('godot'))
 args=parser.parse_args()
 version=subprocess.check_output([args.godot,'--version'],text=True).strip()
 if not version.startswith('4.5.2'):parser.error('Godot 4.5.2 is required for this project')
 logs=ROOT/'build/architecture-qa';logs.mkdir(parents=True,exist_ok=True)
 results=[]
 for suite in SUITES:
  start=time.monotonic()
  try:
   run=subprocess.run([args.godot,'--headless','--path',str(ROOT),'--script',f'res://tests/{suite}_test.gd'],capture_output=True,text=True,timeout=150)
   output=run.stdout+run.stderr
   (logs/(suite+'.log')).write_text(output)
   passed=run.returncode==0 and 'SCRIPT ERROR' not in output and 'ERROR:' not in output and ('PASSED' in output or 'CHECKS=' in output or '0 failures' in output)
  except subprocess.TimeoutExpired:
   passed=False
  result={'suite':suite,'passed':passed,'seconds':round(time.monotonic()-start,3)}
  results.append(result);print(json.dumps(result),flush=True)
 (ROOT/'docs/architecture/validation-results.json').write_text(json.dumps({'engine':version,'results':results,'passed':all(x['passed'] for x in results)},indent=2)+'\n')
 return 0 if all(x['passed'] for x in results) else 1
if __name__=='__main__':raise SystemExit(main())

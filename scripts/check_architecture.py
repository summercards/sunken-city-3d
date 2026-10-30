#!/usr/bin/env python3
"""Check production boundaries without running a scene or editing project data."""
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'godot/src'
RULES = [
    'building/building_service.gd', 'building/material_shop.gd',
    'building/assembly_rules.gd', 'building/assembly_surfaces.gd',
    'construction/construction_service.gd', 'facilities/facility_service.gd',
    'ship/ship_service.gd', 'warehouse/warehouse_service.gd', 'goals/goal_service.gd',
    'salvage/salvage_rewards.gd', 'farming/farm.gd', 'orders/orders.gd',
    'time/world_clock.gd', 'weather/weather_service.gd',
    'navigation/water_navigation.gd', 'save/save_game.gd', 'save/snapshot_registry.gd',
]
# These two existing scripts are development probes, not loaded by the game.
PROBES = {'ui/verify_ac_ui.gd', 'ui/verify_island_ui.gd'}

def check():
    errors = []
    for path in SRC.rglob('*.gd'):
        name = path.relative_to(SRC).as_posix()
        code = '\n'.join(line.split('#', 1)[0] for line in path.read_text(encoding='utf-8').splitlines())
        if name not in PROBES:
            if re.search(r'\b(?:farm|farm_model)\.(?:specs|crops|states)\b', code):
                errors.append(name + ': bypasses farming query/command boundary')
            if re.search(r'\b(?:model|board|order_model)\.slots\b', code):
                errors.append(name + ': bypasses detached order queries')
            if re.search(r'\b(?:farm|farm_model)\.state\([^\n]*\)\.\w+\s*=(?!=)', code):
                errors.append(name + ': writes a query result')
        if name == 'bootstrap/main.gd' and re.search(r'\b(?:hud|cam|dive|navigation)\._\w+', code):
            errors.append(name + ': calls private feature implementation')
        if name.startswith('bootstrap/') or name in PROBES:
            continue
        if re.search(r'\b(?:Economy|GameState|Zones)\.', code):
            errors.append(name + ': direct singleton access')
        if re.search(r'get_node(?:_or_null)?\(["\']/root/', code):
            errors.append(name + ': global scene lookup')
        if 'res://tests/' in code or 'res://web/' in code:
            errors.append(name + ': production depends on test/prototype')
        if 'SailNavLib.' in code and 'res://src/navigation/sail_nav.gd' not in code:
            errors.append(name + ': implicit parity class dependency')
        if name in RULES and re.search(r'get_parent\(|get_node(?:_or_null)?\(', code):
            errors.append(name + ': rule/service reads scene hierarchy')
    for name in RULES:
        if not (SRC / name).is_file(): errors.append('Missing owned service: ' + name)
    for domain in ['player', 'camera', 'diving']:
        states = list((SRC / domain / 'states').glob('*.gd'))
        if not states: errors.append(domain + ': missing independent state files')
        for state in states:
            text = state.read_text(encoding='utf-8')
            if 'res://src/core/state.gd' not in text and '/states/walking.gd' not in text:
                errors.append(str(state) + ': state does not implement shared lifecycle')
    index = json.loads((ROOT / 'docs/generated/feature_index.json').read_text(encoding='utf-8'))
    # Feature/path/link coverage remains the responsibility of check_feature_contracts.
    if not index: errors.append('Missing feature navigation index')
    for error in errors: print('FAIL:', error)
    print(f"{'FAIL' if errors else 'PASS'}: architecture boundaries; {len(RULES)} independent rule/storage services; {len(errors)} issues")
    return errors

if __name__ == '__main__':
    sys.exit(bool(check()))

#!/usr/bin/env python3
"""Declare water_layer / water_layer_role on scene roots.

The ledger says which layer an asset belongs to; this puts the same declaration
on the node that actually gets instantiated, so the runtime suite can check the
duty instead of trusting a JSON row. See docs/standards/水层分类与空间职责.md.

Roots whose script exports the fields get `water_layer = "..."`; the rest get
`metadata/water_layer` (the runtime check reads both).

Idempotent. Existing lines are left alone.
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ATTR = 'attr'   # the root script exports water_layer
META = 'meta'   # no export on this root; declare through metadata

# path -> (layer, role, style)
SCENES = {
    # 水下景观六栋：纯装饰，无阻挡无碰撞
    'godot/scenes/decorations/underwater/buildings/terraced_tower.tscn': ('submerged', 'entity', ATTR),
    'godot/scenes/decorations/underwater/buildings/rounded_tower.tscn': ('submerged', 'entity', ATTR),
    'godot/scenes/decorations/underwater/buildings/slender_tower.tscn': ('submerged', 'entity', ATTR),
    'godot/scenes/decorations/underwater/buildings/stepped_lowrise.tscn': ('submerged', 'entity', ATTR),
    'godot/scenes/decorations/underwater/buildings/flat_annex.tscn': ('submerged', 'entity', ATTR),
    'godot/scenes/decorations/underwater/buildings/rear_slab.tscn': ('submerged', 'entity', ATTR),
    'godot/scenes/decorations/underwater/neighborhood.tscn': ('submerged', 'entity', META),
    # 跨水线的设施与区块
    'godot/scenes/facilities/floating_shop.tscn': ('amphibious', 'entity', ATTR),
    'godot/scenes/facilities/solar_cabin.tscn': ('amphibious', 'entity', ATTR),
    'godot/scenes/facilities/wild_fishery.tscn': ('amphibious', 'entity', ATTR),
    'godot/scenes/facilities/salvage_station.tscn': ('amphibious', 'entity', META),
    'godot/scenes/facilities/solar_cabin_surface.tscn': ('surface', 'part', META),
    'godot/scenes/facilities/solar_cabin_submerged_base.tscn': ('submerged', 'part', META),
    'godot/scenes/zones/zone1_home_harbor.tscn': ('amphibious', 'entity', ATTR),
    'godot/scenes/zones/zone2_yokohama_station.tscn': ('amphibious', 'entity', ATTR),
    'godot/scenes/zones/zone3_arc_farm.tscn': ('amphibious', 'entity', ATTR),
    'godot/scenes/zones/zone4_far_shore.tscn': ('amphibious', 'entity', ATTR),
    'godot/scenes/zones/zone5_aqua_platform.tscn': ('amphibious', 'entity', ATTR),
    # 远景烘焙：不挡船，不参与玩法
    'godot/scenes/world/environment.tscn': ('backdrop', 'entity', META),
    # 玩家自建
    'godot/scenes/buildables/wood_deck.tscn': ('surface', 'entity', META),
    # 种植平台与土格是宿主甲板上的构件：能踩、不挡船（SEA-BUILDING-R16）。
    'godot/scenes/props/cultivation_deck.tscn': ('surface', 'part', META),
    'godot/scenes/props/farm_cell.tscn': ('surface', 'part', META),
    'godot/scenes/props/reference_skiff.tscn': ('none', 'none', META),
}

# 12 structural kit pieces are walkable, boat-blocking entities.
KIT_STRUCTURES = ['beam', 'door_frame', 'post', 'raft_2x4', 'raft_4x4', 'railing',
                  'roof_flat', 'roof_slope', 'stairs', 'upper_floor', 'wall', 'window_wall']
# 10 furniture pieces sit on a finished deck and own no water space (SEA-BUILDING-R21).
KIT_FURNITURE = ['flag', 'flower_pot', 'lamp_post', 'oil_lamp', 'stool',
                 'storage_crate', 'table', 'water_barrel', 'wind_chime', 'windmill']

for name in KIT_STRUCTURES:
    SCENES[f'godot/scenes/buildables/kit/{name}.tscn'] = ('surface', 'entity', META)
for name in KIT_FURNITURE:
    SCENES[f'godot/scenes/buildables/kit/{name}.tscn'] = ('none', 'none', META)


def apply(path, layer, role, style, dry_run):
    raw = path.read_bytes()
    eol = '\r\n' if b'\r\n' in raw else '\n'
    lines = [line[:-1] if line.endswith('\r') else line for line in raw.decode('utf-8').split('\n')]
    start = next((i for i, line in enumerate(lines) if line.startswith('[node name=')), None)
    if start is None:
        raise ValueError(f'{path}: no root node')
    end = start + 1
    while end < len(lines) and not lines[end].startswith('['):
        end += 1
    # Idempotent, and re-running is also how a wrong earlier value gets corrected.
    current = [line for line in lines[start:end] if 'water_layer' in line]
    wanted = [f'water_layer = "{layer}"', f'water_layer_role = "{role}"'] if style == ATTR else \
             [f'metadata/water_layer = "{layer}"', f'metadata/water_layer_role = "{role}"']
    if sorted(line.strip() for line in current) == sorted(wanted):
        return 0
    kept = [line for line in lines[:start]] + [line for line in lines[start:end] if 'water_layer' not in line]
    keep_end = len(kept)
    tail = lines[end:]
    if style == ATTR:
        added = [f'water_layer = "{layer}"', f'water_layer_role = "{role}"']
    else:
        added = [f'metadata/water_layer = "{layer}"',
                 f'metadata/water_layer_role = "{role}"']
    # Insert after the last non-blank line of the root block, before blank padding.
    insert_at = keep_end
    while insert_at - 1 > start and kept[insert_at - 1].strip() == '':
        insert_at -= 1
    if not dry_run:
        kept[insert_at:insert_at] = added
        path.write_bytes(eol.join(kept + tail).encode('utf-8'))
    return 1


def main(dry_run):
    changed, missing = 0, []
    for relative, (layer, role, style) in SCENES.items():
        path = ROOT / relative
        if not path.is_file():
            missing.append(relative)
            continue
        changed += apply(path, layer, role, style, dry_run)
    for relative in missing:
        print('MISSING:', relative)
    print(f'{"DRY" if dry_run else "WROTE"}: {changed} scene roots updated, {len(SCENES)} mapped, {len(missing)} missing')
    return 1 if missing else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    raise SystemExit(main(args.dry_run))

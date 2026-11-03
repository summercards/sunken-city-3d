#!/usr/bin/env python3
"""Maintain the two building responsibility classes and legacy spatial descriptors.

The rule table lives here and nowhere else: docs/standards/水层分类与空间职责.md
defines above_water (functional) and underwater (visual only). building_class
is the primary category; water_layer remains a compatible spatial descriptor.

Idempotent. Unknown families are a hard error -- adding an asset without slotting
it into a layer is exactly the mistake this is meant to stop.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / 'assets/registry/ledger_index.json'

BUILDING_CLASSES = {'above_water', 'underwater'}
BUILDING_CONTRACTS = {
    'above_water': {
        'label': '水上功能建筑',
        'responsibility': 'owns_gameplay_space',
        'activity_area': 'required_at_facility_level',
        'boat_blocking': 'required_at_facility_level',
        'actor_collision': 'as_authored',
        'interaction_and_production': 'as_feature_contract',
        'underwater_geometry': 'visual_only_excluded_from_space_derivation',
    },
    'underwater': {
        'label': '水下观赏建筑（含海下基座）',
        'responsibility': 'visual_only',
        'forbidden': ['actor_collision', 'boat_blocking', 'walkable_area',
                      'landing_point', 'navigation_obstacle', 'interaction',
                      'resource_output', 'gameplay_state', 'shoreline_source'],
    },
}
CLASSIFICATION_HEADER = {
    'schema_version': 1,
    'field': 'building_class',
    'scope': 'surface_world_only',
    'excluded': ['godot/scenes/underwater/', 'ENV-TOWER-DISTRICT- (separate reference, scope pending)'],
    'classes': BUILDING_CONTRACTS,
    'not_applicable': None,
    'legacy_water_layer': 'spatial_description_only_not_a_building_class',
    'verification': 'declared_responsibility_does_not_imply_runtime_verified',
}

LAYERS = {'surface', 'amphibious', 'submerged', 'backdrop', 'none'}
ROLES = {'entity', 'part', 'none'}

# prefix -> (layer, role); role 'assembly' means "assembly id -> entity, siblings -> part".
FAMILIES = [
    ('SEA-SCENE-SUBMERGED-', 'submerged', 'entity'),
    ('SEA-REF-01-BG-', 'backdrop', 'entity'),
    ('SEA-REF-01-BACKGROUND-BUILDING-LIBRARY', 'backdrop', 'entity'),
    ('SEA-REF-01-PLAYABLE-OVERVIEW', 'backdrop', 'entity'),
    ('ENV-TOWER-DISTRICT-', 'backdrop', 'part'),
    # Zone unit/detail entries are the pieces of a facility; the facility itself
    # is the row that carries the name without --UNIT/--DETAIL.
    ('SEA-REF-01-ZONE', 'amphibious', 'assembly'),
    ('SEA-REF-FACILITY-', 'amphibious', 'entity'),
    ('SEA-SCENE-FSH-', 'amphibious', 'assembly'),
    ('SEA-FISHERY-', 'amphibious', 'assembly'),
    ('SEA-SCENE-ORF2-', 'surface', 'assembly'),
    ('SEA-SCENE-ORF-', 'surface', 'assembly'),
    ('SEA-SCENE-SBR-', 'surface', 'part'),
    ('SEA-SCENE-SOLAR-', 'surface', 'part'),
    ('SEA-SCENE-BLB-', 'submerged', 'part'),
    ('SEA-SCENE-PFH-', 'surface', 'assembly'),
    ('SEA-SCENE-TFH-', 'surface', 'assembly'),
    # The lighthouse shop floats on a barge: the deck sits above water while the
    # hull sits below it, same as the floating shop.
    ('SEA-SCENE-LHL-', 'amphibious', 'assembly'),
    ('SEA-BUILDING-', 'surface', 'entity'),
    ('SEA-KIT-', 'surface', 'entity'),
    # 种植平台与土格坐在宿主甲板上，行走面与船阻挡都由宿主派生（SEA-BUILDING-R16）。
    ('SEA-FARM-CULTIVATION-DECK', 'surface', 'part'),
    ('SEA-FARM-SOIL-CELL', 'surface', 'part'),
    ('SEA-SCENE-SKIFF-', 'none', 'none'),
    ('SEA-PLANT-', 'none', 'none'),
    ('SEA-DECO-', 'none', 'none'),
    ('SEA-PALETTE-', 'none', 'none'),
]

# Anchor keys are tried in order; the new fields are inserted right after the
# first one present, so a human reading the JSON sees classification -> layer.
ANCHORS = ['classification', 'category', 'scope', 'note']

# SEA-BUILDING-R21 furniture: sits on a finished deck, carries no water-space
# duty of its own. Only the 12 structural kit pieces are space entities.
KIT_FURNITURE = {
    'SEA-KIT-OIL-LAMP', 'SEA-KIT-LAMP-POST', 'SEA-KIT-WINDMILL', 'SEA-KIT-FLOWER-POT',
    'SEA-KIT-STORAGE-CRATE', 'SEA-KIT-WATER-BARREL', 'SEA-KIT-FLAG', 'SEA-KIT-TABLE',
    'SEA-KIT-STOOL', 'SEA-KIT-WIND-CHIME',
}


def classify(asset_id):
    if asset_id == 'SEA-SCENE-SOLAR-FLOWER-HOUSE':
        return 'surface', 'entity'
    if asset_id in KIT_FURNITURE:
        return 'none', 'none'
    for prefix, layer, role in FAMILIES:
        if not asset_id.startswith(prefix):
            continue
        if role != 'assembly':
            return layer, role
        return layer, 'entity' if asset_id.endswith('-ASSEMBLY') else 'part'
    raise KeyError(asset_id)


def insert_after(asset, fields):
    out = {}
    placed = False
    for key, value in asset.items():
        out[key] = value
        if not placed and key in ANCHORS:
            for name, setting in fields.items():
                out[name] = setting
            placed = True
    if not placed:
        for name, setting in fields.items():
            out[name] = setting
    return out


# Explicit foundation / underwater visual components. A component containing a
# top slab is still visual only: its walkable surface belongs to the above-water
# facility projection. Geometry crossing the waterline remains pending section
# validation; this registration never proves that a source was already split.
UNDERWATER_VISUAL_COMPONENTS = {
    'SEA-SCENE-SOLAR-PIER', 'SEA-SCENE-SOLAR-FOUNDATION',
    'SEA-SCENE-SOLAR-BASE-SLAB', 'SEA-SCENE-SOLAR-STILT',
    'SEA-SCENE-SOLAR-STAGE-BASE',
    'SEA-SCENE-PFH-PILLAR', 'SEA-SCENE-PFH-BASE',
    'SEA-SCENE-TFH-BASE', 'SEA-SCENE-TFH-DOCK-SUPPORT',
    'SEA-SCENE-SBR-FOUNDATION', 'SEA-SCENE-SBR-PIER',
    'SEA-SCENE-LHL-BARGE',
    'SEA-SCENE-FSH-ENGINE', 'SEA-SCENE-FSH-ENGINE-GLOW',
    'SEA-SCENE-FSH-FLOAT-POD', 'SEA-SCENE-FSH-AUX-NOZZLE',
    'SEA-SCENE-FSH-AUX-GLOW',
}


def classify_building(asset_id):
    """Two responsibility classes; null excludes non-building assets/overviews.

    A below-water net that belongs to a functional fishery is an above_water
    component. Its model owns no blocking: the surface facility owns that area.
    Backdrop building libraries are underwater visual scenery, not a third class;
    their geometry/waterline must still be validated before runtime acceptance.
    """
    layer, _ = classify(asset_id)
    if asset_id in UNDERWATER_VISUAL_COMPONENTS:
        return 'underwater'
    if (asset_id.startswith('ENV-TOWER-DISTRICT-') or
            asset_id == 'SEA-REF-01-PLAYABLE-OVERVIEW' or layer == 'none'):
        return None
    return 'above_water' if layer in ('surface', 'amphibious') else 'underwater'


def classify_building_asset(asset):
    # The independent seabed / diving world is deliberately outside this task.
    # decorations/underwater/buildings is surface-world scenery, a different path.
    for key in ('source', 'runtime_path', 'prefab'):
        path = str(asset.get(key) or '').replace('\\', '/')
        if path.startswith(('godot/scenes/underwater/', 'godot/assets/models/underwater/',
                            'art_source/underwater/')):
            return None
    return classify_building(asset['asset_id'])


def building_views(assets, ledger_path):
    return {
        name: {
            'schema_version': 1,
            'generated_from': ledger_path + '#building_class',
            'building_class': name,
            'asset_ids': [a['asset_id'] for a in assets if a.get('building_class') == name],
        }
        for name in sorted(BUILDING_CLASSES)
    }


def write_json(path, value):
    payload = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').replace('\n', '\r\n')
    if path.exists() and path.read_bytes() == payload.encode('utf-8'):
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload.encode('utf-8'))
    return True


def migrate(dry_run=False):
    route = json.loads(INDEX.read_text(encoding='utf-8'))['domains']['scenes']
    ledger_path = route['ledger']
    ledger = ROOT / ledger_path
    book = json.loads(ledger.read_text(encoding='utf-8'))
    unknown, changed, counts = [], 0, {}
    class_counts = {'above_water': 0, 'underwater': 0, None: 0}
    for index, asset in enumerate(book[route['asset_key']]):
        try:
            layer, role = classify(asset['asset_id'])
            building_class = classify_building_asset(asset)
        except KeyError:
            unknown.append(asset['asset_id'])
            continue
        assert layer in LAYERS and role in ROLES, asset['asset_id']
        counts[(layer, role)] = counts.get((layer, role), 0) + 1
        class_counts[building_class] += 1
        fields = {'building_class': building_class,
                  'water_layer': layer, 'water_layer_role': role}
        if (all(key in asset and asset[key] == value for key, value in fields.items())
                and 'placement_layer' not in asset):
            continue
        for key in [*fields, 'placement_layer']:
            asset.pop(key, None)
        book[route['asset_key']][index] = insert_after(asset, fields)
        changed += 1
    if unknown:
        print('FAIL: no classification rule for ' + ', '.join(unknown[:10]))
        return 1
    header_changed = book.get('building_classification') != CLASSIFICATION_HEADER
    book['building_classification'] = CLASSIFICATION_HEADER
    views = building_views(book[route['asset_key']], ledger_path)
    stale_views = []
    for name, value in views.items():
        path = ROOT / route['building_views'][name]
        if not path.exists() or json.loads(path.read_text(encoding='utf-8')) != value:
            stale_views.append(name)
        if not dry_run:
            write_json(path, value)
    if not dry_run and (changed or header_changed):
        # Put the policy before the asset rows, without changing their order.
        book = {key: value for key, value in book.items() if key != route['asset_key']} | {
            route['asset_key']: book[route['asset_key']]}
        write_json(ledger, book)
    for name, count in class_counts.items():
        print(f'building_class={str(name):12} {count:4}')
    for (layer, role), count in sorted(counts.items()):
        print(f'legacy {layer:11} {role:6} {count:4}')
    print(f'{"DRY" if dry_run else "WROTE"}: {changed} rows updated; '
          f'policy_changed={header_changed}; stale_views={stale_views}; '
          f'{len(book[route["asset_key"]])} assets total')
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    raise SystemExit(migrate(args.dry_run))

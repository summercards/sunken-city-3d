"""Register submerged_street v001 into the scenes ledger, source index and runtime inventory.

Reads the export manifest and the in-Blender self-check report; every hash is recomputed from
disk. Only this kit's rows are touched. Run tools/apply_water_layer.py afterwards to refresh
the two building-class views.

Run: python -X utf8 tools/blender/submerged_street/register.py
"""
import hashlib
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/scenes/submerged_street/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'submerged_street_v001'
P = json.loads((D / 'component_plan.json').read_text(encoding='utf-8'))
E = json.loads((D / 'export_manifest.json').read_text(encoding='utf-8'))
SELFCHECK = json.loads((W / 'selfcheck_report.json').read_text(encoding='utf-8'))
INDEX = json.loads((ROOT / 'assets/registry/ledger_index.json').read_text(encoding='utf-8'))
ROUTE = INDEX['domains']['scenes']
LEDGER_PATH = ROUTE['ledger']
LEDGER = ROOT / LEDGER_PATH


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def write_json(path, value):
    payload = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').replace('\n', '\r\n')
    Path(path).write_bytes(payload.encode('utf-8'))


assert SELFCHECK['checks']['passed'], 'in-Blender self check must pass before registration'
assert sha(D / 'submerged_street.blend') == E['source_sha256'], 'master source drifted since export'
assert sha(ROOT / P['palette']) == P['palette_sha256'], 'public palette drifted'

STAGE = 'source_verified_runtime_integration_pending'
evidence = [(W / 'selfcheck_report.json').relative_to(ROOT.parent).as_posix()
            if W.is_relative_to(ROOT.parent) else str(W / 'selfcheck_report.json')]
buildings = {c['key']: c for c in P['components']}
selfcheck = {b['key']: b for b in SELFCHECK['buildings']}
new_rows = []

for comp in E['components']:
    key = comp['key']
    meta = buildings[key]
    pkg = D / 'component_packages' / key
    manifest_path = pkg / 'asset_manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    assert sha(ROOT / manifest['source']) == manifest['source_sha256'], key + ': package hash drift'
    assert manifest['asset_ledger'] == LEDGER_PATH + '#' + meta['asset_id'], key + ': manifest ledger link'
    assert sha(ROOT / comp['runtime_path']) == comp['runtime_sha256'], key + ': GLB hash drift'
    manifest.update(
        asset_ledger=LEDGER_PATH + '#' + meta['asset_id'],
        stage=STAGE,
        triangles=comp['exported_triangles'],
        runtime_path=comp['runtime_path'],
        runtime_sha256=comp['runtime_sha256'],
        export_manifest='art_source/scenes/submerged_street/v001/export_manifest.json',
        optimized_source=E['optimized_source'],
        optimized_sha256=E['optimized_sha256'],
        verification=evidence,
        classification={'category': 'decoration', 'subcategory': 'underwater_buildings'},
        collision=False, interactive=False, emission=False,
    )
    write_json(manifest_path, manifest)
    new_rows.append(dict(
        asset_id=meta['asset_id'],
        name=meta['name'],
        domain='scenes',
        suite='submerged_street',
        scope='scene_local',
        building_class='underwater',
        stage=STAGE,
        source=manifest['source'],
        source_sha256=manifest['source_sha256'],
        manifest=manifest_path.relative_to(ROOT).as_posix(),
        version='v001',
        runtime_path=comp['runtime_path'],
        runtime_sha256=comp['runtime_sha256'],
        category='underwater_scenic_building',
        classification={'category': 'decoration', 'subcategory': 'underwater_buildings'},
        license=P['reference_license'],
        consumer_features=['SEA-ASSET', 'SEA-WORLD'],
        verification=evidence,
        triangles=comp['exported_triangles'],
        polygons=selfcheck[key]['polygons'],
        triangle_budget=meta['triangle_budget'],
        origin='bottom_center',
        front_axis='+Y',
        bounds_blender={'min': selfcheck[key]['bounds_min'], 'max': selfcheck[key]['bounds_max']},
        material_roles=selfcheck[key]['material_roles'],
        palette=P['palette'],
        source_optimization_manifest='art_source/scenes/submerged_street/v001/export_manifest.json',
        collision=False,
        interactive=False,
        emission=False,
        maintenance_status='source_verified',
        note=('Purely decorative sunken-street building. Colour is PaletteUV only, three material roles, '
              'no emissive. In-Blender self check: per-face UV area and single-cell safe margin, identity '
              'transforms, bottom-centre origin, triangle budget, no large near-black face, no coplanar '
              'z-fighting group. No collision, walk area, landing, interaction, production or save field. '
              'Godot placement, blocking review and user art acceptance stay pending.'),
    ))

ASSEMBLY_ID = 'SEA-SCENE-SUBMERGED-STREET-ASSEMBLY'
assembly_manifest = D / 'asset_manifest.json'
assembly = dict(
    asset_id=ASSEMBLY_ID,
    name='阳光房水下街景-十栋独立装配',
    domain='scenes',
    suite='submerged_street',
    scope='scene_local',
    building_class='underwater',
    stage=STAGE,
    source=E['source'],
    source_sha256=E['source_sha256'],
    manifest=assembly_manifest.relative_to(ROOT).as_posix(),
    version='v001',
    category='underwater_scenery_assembly',
    classification={'category': 'decoration', 'subcategory': 'underwater_buildings'},
    license=P['reference_license'],
    consumer_features=['SEA-ASSET', 'SEA-WORLD'],
    verification=evidence,
    status='reference_only',
    placement_owner='unassigned: main.tscn World/UnderwaterScenery is the intended owner',
    collision=False,
    interactive=False,
    note=('Grouping record for the ten buildings. component_instances.json is a traceable reference '
          'layout only; no formal TSCN instantiates it yet.'),
)
write_json(assembly_manifest, dict(
    assembly, asset_ledger=LEDGER_PATH + '#' + ASSEMBLY_ID,
    dependencies=[r['asset_id'] for r in new_rows],
    palette=P['palette'], palette_sha256=P['palette_sha256'],
    component_plan='art_source/scenes/submerged_street/v001/component_plan.json',
    component_instances='art_source/scenes/submerged_street/v001/component_instances.json',
    export_manifest='art_source/scenes/submerged_street/v001/export_manifest.json',
    design_brief='art_source/scenes/submerged_street/v001/design_brief.md',
    selfcheck=evidence,
    style_reference_source=P['style_reference_source'],
    style_reference_sha256=P['style_reference_sha256'],
    collision=False, interactive=False))

ALL_NEW = new_rows + [assembly]
ids = {r['asset_id'] for r in ALL_NEW}

book = json.loads(LEDGER.read_text(encoding='utf-8'))
for domain, route in INDEX['domains'].items():
    for row in json.loads((ROOT / route['ledger']).read_text(encoding='utf-8'))[route['asset_key']]:
        if row['asset_id'] in ids and row.get('suite') != 'submerged_street':
            sys.exit('AssetID already owned elsewhere: ' + row['asset_id'])
book[ROUTE['asset_key']] = [r for r in book[ROUTE['asset_key']] if r['asset_id'] not in ids] + ALL_NEW
write_json(LEDGER, book)

# derived source index
sources = []
for domain, route in INDEX['domains'].items():
    data = json.loads((ROOT / route['ledger']).read_text(encoding='utf-8'))[route['asset_key']]
    sources.extend({k: r[k] for k in ('asset_id', 'source', 'source_sha256', 'manifest')} for r in data)
index_path = ROOT / 'assets/registry/current_source_index.json'
index_doc = json.loads(index_path.read_text(encoding='utf-8'))
index_doc['sources'] = sources
write_json(index_path, index_doc)

# runtime inventory
inventory_path = ROOT / INDEX['runtime_inventory']
inventory = json.loads(inventory_path.read_text(encoding='utf-8'))
owned = {r['runtime_path']: r['asset_id'] for r in new_rows}
inventory['resources'] = [r for r in inventory['resources'] if r['path'] not in owned]
inventory['resources'] += [dict(path=p, bytes=(ROOT / p).stat().st_size, sha256=sha(ROOT / p),
                                asset_id=aid, status=STAGE) for p, aid in owned.items()]
inventory['resources'].sort(key=lambda r: r['path'])
write_json(inventory_path, inventory)

print('REGISTERED %d rows (%d buildings + assembly) into %s' % (len(ALL_NEW), len(new_rows), LEDGER_PATH))
for r in ALL_NEW:
    print('  %-46s %-5s %6s tris' % (r['asset_id'], r.get('stage') == STAGE and 'new', r.get('triangles', '-')))

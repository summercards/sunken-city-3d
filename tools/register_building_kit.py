#!/usr/bin/env python3
"""Register the reviewed 22-component kit without accepting unrelated hash changes.

Run after source/GLB changes settle. This refreshes only kit assets and the explicit
integration paths below; current_source_index projects ledger hashes verbatim.
"""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/scenes/ocean_building_kit/v001'
EVIDENCE = 'docs/development/2026-10-30_modular_building_kit.md'
KNOWN_INTEGRATION = [
    'godot/src/building/building_catalog.gd',
    'godot/src/building/building_service.gd',
    'godot/src/building/building_space.gd',
    'godot/src/building/building_boundary.gd',
    'godot/src/building/building_world.gd',
    'godot/src/building/building_access.gd',
    'godot/src/building/building_controller.gd',
    'godot/src/building/building_book.gd',
    'godot/src/building/recipe_card.gd',
    'godot/src/building/recipe_thumbnail.gd',
    'godot/src/building/assembly_rules.gd',
    'godot/src/building/assembly_surfaces.gd',
    'godot/src/building/kit_visual.gd',
    'godot/src/bootstrap/main.gd',
    'godot/src/navigation/walk_area.gd',
    'godot/src/navigation/ground_space.gd',
    'godot/src/player/actions/walk_action.gd',
    'godot/assets/data/building_kit.json',
]


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def write(path, value):
    path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets-only', action='store_true', help='Do not refresh integration code hashes while it is being edited')
    parser.add_argument('--promote-verified', action='store_true', help='Promote only after the final kit verification record passes all required checks')
    args = parser.parse_args()
    if args.promote_verified:
        final = read('docs/development/2026-10-30_modular_building_verification.json')
        required = {'kit-safety', 'building-kit', 'visual-building-kit', 'visual-kit-uv', 'visual-recipe-cards'}
        passed = {row['check'] for row in final['results'] if row['passed'] and row['exit_code'] == 0 and not row['unexpected_errors']}
        assert required <= passed, 'Missing final kit verification: ' + str(required - passed)
    index = read('assets/registry/ledger_index.json')
    route = index['domains']['scenes']
    book = read(route['ledger'])
    rows = read('godot/assets/data/building_kit.json')['modules']
    catalog = {x['id']: x for x in read(rel(SOURCE / 'catalog.json'))['components']}
    assert len(rows) == 22 and sum(x['category'] == 'structure' for x in rows) == 12
    ids = {x['asset_id'] for x in rows}
    existing = {x['asset_id']: x for x in book[route['asset_key']]}
    resources = read(index['runtime_inventory'])
    by_path = {x['path']: x for x in resources['resources']}

    def runtime(path, asset_id=None, stage='runtime_resource_verified'):
        assert (ROOT / path).is_file(), path
        row = by_path.get(path)
        if row is None:
            row = {'path': path, 'asset_id': asset_id, 'status': stage}
            resources['resources'].append(row)
            by_path[path] = row
        row.update({'bytes': (ROOT / path).stat().st_size, 'sha256': sha(path)})
        if asset_id is not None:
            row.update({'asset_id': asset_id, 'status': stage})

    for definition in rows:
        key = definition['id']
        aid = definition['asset_id']
        component = catalog[key]
        source = rel(SOURCE / 'component_packages' / key / (key + '.blend'))
        manifest = rel(SOURCE / 'component_packages' / key / 'asset_manifest.json')
        glb = 'godot/assets/models/building_kit/' + key + '/' + key + '.glb'
        prefab = definition['prefab'].replace('res://', 'godot/')
        assert (ROOT / source).is_file() and (ROOT / glb).is_file() and (ROOT / prefab).is_file()
        previous = existing.get(aid, {})
        # Parent promotes final render status only after final scene evidence exists.
        stage = 'runtime_integrated_verified' if args.promote_verified else previous.get('stage', 'source_verified_runtime_final_pending')
        asset = dict(previous)
        asset.update({
            'asset_id': aid, 'name': definition['name'], 'asset_key': key,
            'domain': 'scenes', 'stage': stage, 'version': 'v001',
            'source': source, 'source_sha256': sha(source), 'manifest': manifest,
            'runtime_path': glb, 'runtime_sha256': sha(glb), 'prefab': prefab,
            'license': 'project_authored_procedural_geometry',
            'classification': {'category': 'building' if definition['category'] == 'structure' else 'decoration',
                               'subcategory': 'modular_structure' if definition['category'] == 'structure' else 'placeable_prop'},
            'consumer_features': ['SEA-BUILDING', 'SEA-ASSET', 'SEA-MOVE'],
            'collection': component['collection'], 'triangles': component['triangles'],
            'bounds_blender': component['bounds'], 'origin': definition.get('source_origin', 'bottom_center'),
            'front_axis': definition['front_axis'], 'profile': definition['profile'],
            'footprint': definition['footprint'], 'height': definition['height'],
            'placement_owner': 'BuildingService instances; Godot PackedScene projection',
            'collision_responsibility': 'BuildingWorld/AssemblySurfaces/BuildingSpace derived projection; pure visual GLB',
            'mother_source': rel(SOURCE / 'building_kit.blend'),
            'palette': 'art_source/shared/palettes/sea_cozy_8x8_512.png',
            'verification': EVIDENCE,
            'note': '每件独立母版/可打开组件包/GLB/PackedScene。源重开及PaletteUV检查完成；最终游戏画面结果以交付记录为准。无第三层、电网或风铃音效。',
        })
        if aid in existing:
            existing[aid].clear()
            existing[aid].update(asset)
        else:
            book[route['asset_key']].append(asset)
        write(manifest, {
            'asset_id': aid, 'asset_ledger': route['ledger'] + '#' + aid,
            'version': 'v001', 'source': source, 'source_sha256': asset['source_sha256'],
            'mother_source': asset['mother_source'], 'runtime_path': glb,
            'runtime_sha256': asset['runtime_sha256'], 'prefab': prefab,
            'component': component, 'license': asset['license'], 'stage': stage,
            'verification': EVIDENCE,
            'source_verification': {'tool': 'tools/blender/building_kit/refine.py',
                                    'log': 'D:/projects/sea-work/building_kit_v001/refine.log',
                                    'checks': 'saved mother reopen, independent package scene/collection, nonempty geometry, PaletteUV area and one-tile islands; four renders'},
            'transfer_verification': {'tool': 'tools/blender/building_kit/fix_palette_export.py',
                                      'report': 'D:/projects/sea-work/building_kit_v001/uv_transfer_report.json',
                                      'contract': 'PaletteUV is sole TEXCOORD_0; GLB UV tile samples match source; four named material roles survive without embedded palette copy'},
        })
        runtime(glb, aid, 'runtime_available_final_scene_pending' if 'pending' in stage else 'runtime_component_verified')
        runtime(prefab, aid, 'runtime_available_final_scene_pending' if 'pending' in stage else 'runtime_component_verified')

    write(route['ledger'], book)
    if not args.assets_only:
        for path in KNOWN_INTEGRATION:
            runtime(path)
    for path in sorted((ROOT / 'godot/assets/materials/building_kit').glob('*.tres')):
        runtime(rel(path))
    write(index['runtime_inventory'], resources)
    source_projection = read('assets/registry/current_source_index.json')
    source_projection['sources'] = [
        {k: asset[k] for k in ['asset_id', 'source', 'source_sha256', 'manifest']}
        for routing in index['domains'].values()
        for asset in read(routing['ledger'])[routing['asset_key']]
    ]
    write('assets/registry/current_source_index.json', source_projection)
    content = read(index['content_index'])
    table = {'owner': 'SEA-BUILDING', 'path': 'godot/assets/data/building_kit.json',
             'collection_key': 'modules', 'ids': [x['id'] for x in rows],
             'note': '配方ID唯一源；active控制新建，旧档定义不因停用删除。'}
    found = next((x for x in content['tables'] if x['path'] == table['path']), None)
    if found is None:
        content['tables'].append(table)
    else:
        found.clear(); found.update(table)
    write(index['content_index'], content)
    print(f'Registered {len(ids)} kit assets; only explicit kit/integration hashes updated')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""登记 water_building_002/v003 的源级资产，并严格保护无关登记。"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SOURCE_DIR = ROOT / 'art_source/scenes/water_building_002/v003'
WORK_DIR = Path('D:/projects/sea-work/water_building_002/v003')
SOURCE = SOURCE_DIR / 'water_building_002_v003.blend'
PLAN = SOURCE_DIR / 'component_plan.json'
CATALOG = SOURCE_DIR / 'catalog.json'
INSTANCES = SOURCE_DIR / 'component_instances.json'
EXPORT_MANIFEST = SOURCE_DIR / 'export/v003/export_manifest.json'
SOURCE_QA = WORK_DIR / 'source_verification.json'
PALETTE = ROOT / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
LEDGER_INDEX = ROOT / 'assets/registry/ledger_index.json'
LEDGER = ROOT / 'assets/registry/ledgers/scenes.json'
SOURCE_INDEX = ROOT / 'assets/registry/current_source_index.json'
VIEWS = {
    'above_water': ROOT / 'assets/registry/views/buildings_above_water.json',
    'underwater': ROOT / 'assets/registry/views/buildings_underwater.json',
}
ASSEMBLY_ID = 'SEA-SCENE-WATER-BUILDING-002'
PREFIX = ASSEMBLY_ID + '-'
VERSION = 'v003'
STAGE = 'source_verified_runtime_pending'
DISPLAY_NUMBER = '002'
COMPONENT_MANIFESTS = [
    SOURCE_DIR / 'component_packages' / component['key'] / 'asset_manifest.json'
    for component in json.loads(CATALOG.read_text(encoding='utf-8'))['components']
]
EXPORT_MANIFEST_REL = EXPORT_MANIFEST.relative_to(ROOT).as_posix()
PARENT_SOURCE_REL = SOURCE.relative_to(ROOT).as_posix()
PARENT_SOURCE_SHA = 'b362c1b669b5ad2a7d32705df2339182e8d2447f9fd35a53d95c76b7d8541751'
PALETTE_SHA = 'f4b1f52544e9e785b2ef7ae5eabbe378a551f1c48b5ef0f79905f2a9f8f15d09'
PLANT_KEYS = {'trunk_a', 'trunk_b', 'crown_a', 'crown_b', 'vine', 'flower'}


def read_json(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def dump_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
    path.write_text(payload, encoding='utf-8', newline='\n')


def load_policy():
    spec = importlib.util.spec_from_file_location('water_layer_policy', ROOT / 'tools/apply_water_layer.py')
    policy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(policy)
    return policy


def classification(component):
    if component['group'] == 'plant':
        return {'category': 'upgrade_attachment', 'subcategory': 'plants'}
    if component['group'] == 'structure':
        return {'category': 'building', 'subcategory': 'structure'}
    return {'category': 'upgrade_attachment', 'subcategory': 'decoration'}


def name_for(key: str) -> str:
    names = {
        'deck': '平台', 'story_wall': '楼层墙体', 'ground_wall': '底层墙体',
        'floor_slab': '楼板', 'parapet': '女儿墙', 'front_window': '正面窗',
        'side_window': '侧窗', 'entry': '入口', 'balcony': '阳台', 'ac_unit': '空调外机',
        'pipe': '排水管', 'switchbox': '配电箱', 'solar_panel': '太阳能板',
        'solar_frame': '太阳能框架', 'roof_utilities': '屋顶设备', 'antenna': '天线',
        'trunk_a': '树干A', 'trunk_b': '树干B', 'crown_a': '树冠A', 'crown_b': '树冠B',
        'vine': '藤蔓', 'planter': '种植箱', 'flower': '花朵', 'wall_patch': '墙面修补片',
        'brace': '支撑件', 'orange_tank': '橙色水箱', 'small_sign': '小招牌', 'entry_step': '入口台阶',
    }
    return names[key]


def pending_fields():
    return {
        'license': 'pending_user_reference_commercial_rights_review',
        'commercial_rights': 'pending',
        'user_acceptance': 'pending',
        'runtime': 'pending',
        'collision': 'pending',
        'navigation': 'pending',
        'runtime_path': None,
        'prefab': None,
        'runtime_integrated': False,
    }


def source_projection(row):
    return {key: row[key] for key in ('asset_id', 'source', 'source_sha256', 'manifest')}


def component_record(component, package_path: Path, manifest_path: Path, export, policy):
    asset_id = component['asset_id']
    layer, role = policy.classify(asset_id)
    building_class = policy.classify_building_asset({'asset_id': asset_id, 'source': rel(package_path)})
    expected = ('none', 'none') if component['key'] in PLANT_KEYS else ('surface', 'part')
    assert (layer, role) == expected, asset_id
    assert building_class is None if component['key'] in PLANT_KEYS else building_class == 'above_water', asset_id
    package_sha = sha256(package_path)
    export_component = export['components'][component['key']]
    return {
        'asset_id': asset_id,
        'name': name_for(component['key']),
        'display_name': DISPLAY_NUMBER,
        'domain': 'scenes',
        'suite': 'water_building_002',
        'scope': 'scene_local',
        'category': component['group'],
        'classification': classification(component),
        'building_class': building_class,
        'water_layer': layer,
        'water_layer_role': role,
        'source': rel(package_path),
        'source_sha256': package_sha,
        'manifest': rel(manifest_path),
        'material_roles': component['material_roles'],
        'palette': rel(PALETTE),
        'palette_sha256': PALETTE_SHA,
        'version': VERSION,
        'origin': component['origin'],
        'front_axis': component['front_axis'],
        'stage': STAGE,
        'consumer_features': ['SEA-ASSET'],
        'bounds_size_m': component['bounds_size'],
        'geometry_fingerprint': component['geometry_fingerprint'],
        'polygons': component['polygons'],
        'triangles': component['triangles'],
        'meshes': component['meshes'],
        'instance_count': component.get('instance_count', 0),
        'package_sha256': package_sha,
        'runtime_path': rel(ROOT / Path(export_component['path'].replace('D:/projects/sea/', ''))),
        'runtime_sha256': export_component['sha256'],
        'export_manifest': EXPORT_MANIFEST_REL,
        'verification': [str(SOURCE_QA).replace('\\', '/'), EXPORT_MANIFEST_REL],
        'source_verification': 'passed_0_failures',
        'verification_pending': ['Godot', 'collision', 'navigation', 'commercial_authorization', 'user_final_art_acceptance'],
        **pending_fields(),
    }


def assembly_record(source_qa, plan, catalog, instances, manifest_path: Path):
    return {
        'asset_id': ASSEMBLY_ID,
        'name': '水上普通建筑002',
        'display_name': DISPLAY_NUMBER,
        'domain': 'scenes',
        'suite': 'water_building_002',
        'scope': 'scene_local',
        'category': 'building',
        'classification': {'category': 'building', 'subcategory': 'ordinary_water_building', 'display_number': DISPLAY_NUMBER},
        'building_class': 'above_water',
        'water_layer': 'surface',
        'water_layer_role': 'entity',
        'source': PARENT_SOURCE_REL,
        'source_sha256': PARENT_SOURCE_SHA,
        'manifest': rel(manifest_path),
        'material_roles': sorted({role for component in catalog for role in component['material_roles']}),
        'palette': rel(PALETTE),
        'palette_sha256': PALETTE_SHA,
        'version': VERSION,
        'origin': 'bottom_center',
        'front_axis': '-Y',
        'stage': STAGE,
        'consumer_features': ['SEA-ASSET'],
        'component_count': len(catalog),
        'instance_count': len(instances),
        'expanded_triangles': source_qa['source_depsgraph']['evaluated_triangles'],
        'expanded_polygons': source_qa['source_depsgraph']['evaluated_polygons'],
        'verification': [str(SOURCE_QA).replace('\\', '/'), EXPORT_MANIFEST_REL],
        'source_verification': 'passed_0_failures',
        'verification_pending': ['Godot', 'collision', 'navigation', 'commercial_authorization', 'user_final_art_acceptance'],
        **pending_fields(),
    }


def validate_inputs():
    for path in (SOURCE, PLAN, CATALOG, INSTANCES, EXPORT_MANIFEST, SOURCE_QA, PALETTE, LEDGER_INDEX, LEDGER, SOURCE_INDEX):
        assert path.is_file(), f'缺少登记输入：{path}'
    assert sha256(SOURCE) == PARENT_SOURCE_SHA, '002主源哈希错误，停止登记'
    assert sha256(PALETTE) == PALETTE_SHA, '002色板哈希错误，停止登记'
    plan = read_json(PLAN)
    catalog = read_json(CATALOG)['components']
    instances = read_json(INSTANCES)['instances']
    export = read_json(EXPORT_MANIFEST)
    source_qa = read_json(SOURCE_QA)
    assert plan['asset_id'] == ASSEMBLY_ID and plan['version'] == VERSION
    assert len(catalog) == 28 and len(instances) == 167
    assert not source_qa.get('failures', [])
    assert source_qa['source_sha256_before'] == PARENT_SOURCE_SHA
    assert source_qa['source_sha256_after'] == PARENT_SOURCE_SHA
    assert source_qa['source_unchanged'] is True
    assert source_qa['palette_sha256_before'] == PALETTE_SHA
    assert source_qa['palette_sha256_after'] == PALETTE_SHA
    assert source_qa['palette_unchanged'] is True
    assert source_qa['catalog_components'] == 28
    assert source_qa['catalog_instances'] == 167
    assert source_qa['source_depsgraph']['evaluated_triangles'] == 10342
    assert source_qa['source_depsgraph']['evaluated_polygons'] == 6293
    assert export['source']['sha256'] == PARENT_SOURCE_SHA
    assert export['source']['expanded_instances'] == 167
    assert export['source']['expanded_triangles_depsgraph'] == 10342
    assert export['source']['expanded_polygons_depsgraph'] == 6293
    assert export['failures'] == []
    assert len(export['components']) == 28
    return plan, catalog, instances, export, source_qa


def classification_self_test(policy):
    cases = {
        'SEA-SCENE-WATER-BUILDING-002': (('surface', 'entity'), 'above_water'),
        'SEA-SCENE-WATER-BUILDING-002-DECK': (('surface', 'part'), 'above_water'),
        'SEA-SCENE-WATER-BUILDING-002-TRUNK-A': (('none', 'none'), None),
        'SEA-SCENE-B1109A-ASSEMBLY': (('surface', 'entity'), 'above_water'),
        'SEA-SCENE-B1109A-LEAF-CLUSTER': (('none', 'none'), None),
    }
    for asset_id, expected in cases.items():
        assert policy.classify(asset_id) == expected[0], asset_id
        assert policy.classify_building(asset_id) == expected[1], asset_id
    try:
        policy.classify('SEA-SCENE-WATER-BUILDING-999')
    except KeyError:
        pass
    else:
        raise AssertionError('未知编号资产不应被硬造分类')
    return {'passed': True, 'cases': len(cases), 'unknown_number_rejected': True}


def all_rows(ledger_index):
    rows = {}
    for domain, route in ledger_index['domains'].items():
        book = read_json(ROOT / route['ledger'])
        for row in book[route['asset_key']]:
            assert row['asset_id'] not in rows, f'重复AssetID：{row["asset_id"]}'
            rows[row['asset_id']] = row
    return rows


def snapshot(paths):
    return {path: (path.read_bytes() if path.exists() else None) for path in paths}


def backup_before_write(paths):
    backup = WORK_DIR / 'registry_before'
    backup.mkdir(parents=True, exist_ok=True)
    for path in paths:
        target = backup / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() and path.exists():
            target.write_bytes(path.read_bytes())
    return backup


def make_001_manifest(row):
    old = row.get('manifest')
    path = ROOT / 'art_source/scenes/bld_20261109_a/v004_lowpoly/water_building_001_asset_manifest.json'
    runtime_export = read_json(Path('D:/projects/sea-work/bld_20261109_a/v004_lowpoly/runtime_export.json'))
    manifest = {
        'schema': 'sea.scene.assembly_manifest',
        'asset_id': row['asset_id'],
        'asset_ledger': 'assets/registry/ledgers/scenes.json#' + row['asset_id'],
        'name': row['name'],
        'display_name': '001',
        'domain': 'scenes',
        'suite': row.get('suite'),
        'version': row['version'],
        'category': row['category'],
        'classification': row['classification'],
        'building_class': row['building_class'],
        'water_layer': row['water_layer'],
        'water_layer_role': row['water_layer_role'],
        'source': row['source'],
        'source_sha256': row['source_sha256'],
        'runtime_path': row['runtime_path'],
        'runtime_glb_sha256': row['runtime_glb_sha256'],
        'runtime_integrated': False,
        'stage': 'source_registered_runtime_validation_pending',
        'component_plan': 'art_source/scenes/bld_20261109_a/v004_lowpoly/component_plan.json',
        'runtime_export_manifest': 'art_source/scenes/bld_20261109_a/v004_lowpoly/runtime_export.json',
        'runtime_export': runtime_export,
        'replaced_manifest': old,
        'source_sha256_semantics': 'v004_lowpoly source blend sha256; unchanged from prior ledger row',
        'note': '仅修复 ledger manifest 指向与运行待验状态；不改原 source/hash，不改旧 B1109A 登记。',
    }
    return path, manifest


def register(write: bool):
    plan, catalog, instances, export, source_qa = validate_inputs()
    policy = load_policy()
    self_test = classification_self_test(policy)
    ledger_index = read_json(LEDGER_INDEX)
    route = ledger_index['domains']['scenes']
    assert route['ledger'] == 'assets/registry/ledgers/scenes.json'
    assert route['building_views']['above_water'] == 'assets/registry/views/buildings_above_water.json'
    assert route['building_views']['underwater'] == 'assets/registry/views/buildings_underwater.json'

    book_before = read_json(LEDGER)
    source_index_before = read_json(SOURCE_INDEX)
    existing = {row['asset_id']: row for row in book_before['assets']}
    all_existing = all_rows(ledger_index)
    policy_rows = []
    manifest_paths = []
    component_rows = []
    for component in catalog:
        package_path = ROOT / component['component_source']
        manifest_path = package_path.parent / 'asset_manifest.json'
        assert package_path.is_file(), f'缺少组件源：{package_path}'
        assert sha256(package_path) == component['package_sha256'], f'组件包哈希错误：{component["key"]}'
        manifest = read_json(manifest_path)
        assert manifest['package_sha256_before_reopen'] == component['package_sha256']
        assert manifest['package_sha256_after_reopen'] == component['package_sha256']
        assert manifest['palette_sha256'] == PALETTE_SHA
        export_component = export['components'][component['key']]
        glb_path = ROOT / export_component['path'].replace('D:/projects/sea/', '')
        assert glb_path.is_file(), f'缺少组件GLB：{glb_path}'
        assert sha256(glb_path) == export_component['sha256'] == component['glb_sha256'], f'组件GLB哈希错误：{component["key"]}'
        row = component_record(component, package_path, manifest_path, export, policy)
        if component['asset_id'] in all_existing:
            assert all_existing[component['asset_id']].get('suite') == 'water_building_002', component['asset_id']
        component_rows.append(row)
        manifest_paths.append(manifest_path)
    assembly_manifest_path = SOURCE_DIR / 'asset_manifest.json'
    master = assembly_record(source_qa, plan, catalog, instances, assembly_manifest_path)
    target_ids = {row['asset_id'] for row in component_rows} | {ASSEMBLY_ID}
    assert all(
        asset_id not in all_existing or all_existing[asset_id].get('suite') == 'water_building_002'
        for asset_id in target_ids
    )

    row_001 = existing['SEA-SCENE-WATER-BUILDING-001']
    assert sha256(ROOT / row_001['source']) == row_001['source_sha256']
    manifest_001_path, manifest_001 = make_001_manifest(row_001)
    assert manifest_001_path.parent.is_dir()

    write_paths = [LEDGER, SOURCE_INDEX, *VIEWS.values(), *manifest_paths, assembly_manifest_path, manifest_001_path]
    before = snapshot(write_paths)
    source_sha_before = sha256(SOURCE)
    palette_sha_before = sha256(PALETTE)
    package_sha_before = {path: sha256(path) for path in [ROOT / component['component_source'] for component in catalog]}
    unrelated_rows_before = {aid: copy.deepcopy(row) for aid, row in existing.items() if aid not in target_ids and aid != 'SEA-SCENE-WATER-BUILDING-001'}
    unrelated_index_before = {row['asset_id']: copy.deepcopy(row) for row in source_index_before['sources'] if row['asset_id'] not in target_ids and row['asset_id'] != 'SEA-SCENE-WATER-BUILDING-001'}

    report = {
        'passed': True,
        'write': write,
        'registered_rows': 29,
        'component_rows': 28,
        'assembly_rows': 1,
        'instance_count': 167,
        'expanded_triangles': 10342,
        'expanded_polygons': 6293,
        'source_sha256': PARENT_SOURCE_SHA,
        'palette_sha256': PALETTE_SHA,
        'source_unchanged': True,
        'palette_unchanged': True,
        'package_hashes_verified': 28,
        'glb_hashes_verified': 28,
        'building_class_counts': {'above_water': 23, 'none': 6},
        'legacy_water_counts': {'surface/entity': 1, 'surface/part': 22, 'none/none': 6},
        'unrelated_ledger_rows_before': len(unrelated_rows_before),
        'unrelated_source_index_rows_before': len(unrelated_index_before),
        'classification_self_test': self_test,
        'runtime_integrated': False,
        'stage': STAGE,
        'godot_files_changed': 0,
        'forbidden_files_changed': [],
    }
    if not write:
        report['would_write'] = [rel(path) for path in write_paths]
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return report

    backup_before_write(write_paths)
    assert LEDGER.read_bytes() == before[LEDGER]
    assert SOURCE_INDEX.read_bytes() == before[SOURCE_INDEX]
    assert sha256(SOURCE) == source_sha_before
    assert sha256(PALETTE) == palette_sha_before
    assert all(sha256(path) == digest for path, digest in package_sha_before.items())

    for component, row, manifest_path in zip(catalog, component_rows, manifest_paths):
        manifest = read_json(manifest_path)
        old_parent = {
            'path': PARENT_SOURCE_REL,
            'source_sha256': PARENT_SOURCE_SHA,
            'source_version': VERSION,
        }
        manifest.update(row)
        manifest.update({
            'schema': 'sea.scene.component_manifest',
            'asset_ledger': route['ledger'] + '#' + row['asset_id'],
            'component_key': component['key'],
            'component_family': component['family'],
            'source': rel(ROOT / component['component_source']),
            'source_blend': rel(ROOT / component['component_source']),
            'source_sha256': row['source_sha256'],
            'parent_source': old_parent,
            'palette_sha256': PALETTE_SHA,
            'export_manifest': EXPORT_MANIFEST_REL,
        })
        dump_json(manifest_path, manifest)

    assembly_manifest = {
        'schema': 'sea.scene.assembly_manifest',
        **master,
        'asset_ledger': route['ledger'] + '#' + ASSEMBLY_ID,
        'component_plan': rel(PLAN),
        'catalog': rel(CATALOG),
        'instances': rel(INSTANCES),
        'reference': rel(SOURCE_DIR / plan['reference_image']),
        'reference_sha256': plan['reference_sha256'],
        'parent_source': {
            'path': plan.get('source_parent'),
            'source_sha256': plan.get('source_parent_sha256'),
        },
        'source_report': str(SOURCE_QA).replace('\\', '/'),
        'export_manifest': EXPORT_MANIFEST_REL,
        'optimized_source': export['optimized']['path'].replace('D:/projects/sea/', ''),
        'optimized_sha256': export['optimized']['sha256'],
        'pending': ['Godot integration', 'runtime collision', 'navigation', 'commercial rights', 'user final art acceptance'],
    }
    dump_json(assembly_manifest_path, assembly_manifest)
    dump_json(manifest_001_path, manifest_001)

    updated_001 = copy.deepcopy(row_001)
    updated_001['manifest'] = rel(manifest_001_path)
    updated_001['stage'] = 'source_registered_runtime_validation_pending'
    updated_001['runtime_integrated'] = False
    ledger_rows = []
    for row in book_before['assets']:
        if row['asset_id'] in target_ids:
            continue
        ledger_rows.append(updated_001 if row['asset_id'] == updated_001['asset_id'] else row)
    ledger_rows.extend(component_rows)
    ledger_rows.append(master)
    book_after = copy.deepcopy(book_before)
    book_after['assets'] = ledger_rows
    dump_json(LEDGER, book_after)

    projected = []
    for domain, domain_route in ledger_index['domains'].items():
        rows = read_json(ROOT / domain_route['ledger'])[domain_route['asset_key']]
        projected.extend(source_projection(row) for row in rows)
    source_index_after = copy.deepcopy(source_index_before)
    source_index_after['sources'] = projected
    dump_json(SOURCE_INDEX, source_index_after)

    for name, view in policy.building_views(book_after['assets'], route['ledger']).items():
        dump_json(VIEWS[name], view)

    current_rows = {row['asset_id']: row for row in read_json(LEDGER)['assets']}
    for asset_id, old_row in unrelated_rows_before.items():
        assert current_rows[asset_id] == old_row, f'无关ledger行被改变：{asset_id}'
    current_index_rows = {row['asset_id']: row for row in read_json(SOURCE_INDEX)['sources']}
    for asset_id, old_row in unrelated_index_before.items():
        assert current_index_rows[asset_id] == old_row, f'无关source index行被改变：{asset_id}'
    assert sha256(SOURCE) == source_sha_before
    assert sha256(PALETTE) == palette_sha_before
    assert all(sha256(path) == digest for path, digest in package_sha_before.items())

    report['ledger_rows_after'] = len(current_rows)
    report['source_index_rows_after'] = len(current_index_rows)
    report['unrelated_ledger_rows_unchanged'] = True
    report['unrelated_source_index_rows_unchanged'] = True
    report['backup'] = rel(WORK_DIR / 'registry_before') if WORK_DIR.is_relative_to(ROOT) else str(WORK_DIR / 'registry_before').replace('\\', '/')
    dump_json(WORK_DIR / 'registration.json', report)
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='通过快照校验后写入登记')
    args = parser.parse_args()
    register(args.write)

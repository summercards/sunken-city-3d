"""Register bld_20261109_a/v001 source assets without rewriting unrelated ledger rows."""
from pathlib import Path
import copy
import hashlib
import importlib.util
import json
import shutil

ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / 'art_source/scenes/bld_20261109_a/v001'
WORK_DIR = Path('D:/projects/sea-work/bld_20261109_a/v001')
CATALOG_PATH = SOURCE_DIR / 'catalog.json'
PLAN_PATH = SOURCE_DIR / 'component_plan.json'
INSTANCES_PATH = SOURCE_DIR / 'component_instances.json'
ASSEMBLY_SOURCE = SOURCE_DIR / 'bld_20261109_a.blend'
SOURCE_QA_PATH = WORK_DIR / 'source_verification.json'
VISUAL_QA_PATH = WORK_DIR / 'visual_review.json'
INDEX_PATH = ROOT / 'assets/registry/ledger_index.json'
SOURCE_INDEX_PATH = ROOT / 'assets/registry/current_source_index.json'
PREFIX = 'SEA-SCENE-B1109A-'
ASSEMBLY_ID = PREFIX + 'ASSEMBLY'
VERSION = 'v001'
STAGE = 'source_verified_runtime_integration_pending'
DISPLAY_NAME = 'B1109A'
EVIDENCE = [
    'docs/development/2026-11-09_bld_20261109_a.md',
    'D:/projects/sea-work/bld_20261109_a/v001/source_verification.json',
    'D:/projects/sea-work/bld_20261109_a/v001/visual_review.json',
]


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def load_policy():
    spec = importlib.util.spec_from_file_location('water_policy', ROOT / 'tools/apply_water_layer.py')
    policy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(policy)
    return policy


def classification(component):
    group = component.get('group')
    if group == 'structure':
        return {'category': 'building', 'subcategory': 'structure'}
    if group == 'plant':
        return {'category': 'upgrade_attachment', 'subcategory': 'plants'}
    return {'category': 'upgrade_attachment', 'subcategory': 'decoration'}


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
    }


def component_record(component, package_path, manifest_path, policy):
    layer, role = policy.classify(component['asset_id'])
    building_class = policy.classify_building_asset({
        'asset_id': component['asset_id'],
        'source': rel(package_path),
    })
    expected_layer_role = ('none', 'none') if component['group'] == 'plant' else ('surface', 'part')
    assert (layer, role) == expected_layer_role, component['asset_id']
    assert building_class == component['building_class']
    record = {
        'asset_id': component['asset_id'],
        'name': component['name'],
        'display_name': DISPLAY_NAME,
        'domain': 'scenes',
        'suite': 'bld_20261109_a',
        'scope': component['scope'],
        'category': component['group'],
        'classification': classification(component),
        'building_class': building_class,
        'water_layer': layer,
        'water_layer_role': role,
        'source': rel(package_path),
        'source_sha256': component['source_sha256'],
        'manifest': rel(manifest_path),
        'material_roles': component['material_roles'],
        'palette': component['palette'],
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
        'instance_count': component['instance_count'],
        'verification': EVIDENCE,
        'source_verification': 'source_verification_passed_visual_review_signed',
        'verification_pending': ['Godot', 'collision', 'navigation', 'commercial_authorization', 'user_final_art_acceptance'],
    }
    record.update(pending_fields())
    return record


def source_projection(row):
    return {key: row[key] for key in ('asset_id', 'source', 'source_sha256', 'manifest')}


def main():
    for path in (CATALOG_PATH, PLAN_PATH, INSTANCES_PATH, ASSEMBLY_SOURCE, SOURCE_QA_PATH, VISUAL_QA_PATH, INDEX_PATH, SOURCE_INDEX_PATH):
        assert path.is_file(), f'缺少登记文件：{path}'

    plan = read_json(PLAN_PATH)
    catalog = read_json(CATALOG_PATH)['components']
    instances = read_json(INSTANCES_PATH)['instances']
    source_qa = read_json(SOURCE_QA_PATH)
    visual_qa = read_json(VISUAL_QA_PATH)
    assert len(catalog) == 49 and len(instances) == 92
    assert len({c['asset_id'] for c in catalog}) == 49
    assert all(c['asset_id'].startswith(PREFIX) for c in catalog)
    assert plan['suite'] == 'bld_20261109_a' and plan['version'] == VERSION
    assert plan['component_budget']['planned'] == 49
    assert plan['display_name'] is None
    assert source_qa.get('passed') is True and source_qa.get('exit_code') == 0
    assert visual_qa.get('passed') is True
    source_sha = sha256(ASSEMBLY_SOURCE)
    assert source_qa['source_sha256'] == source_sha
    assert visual_qa['source_sha256'] == source_sha
    assert source_qa['components'] == 49 and source_qa['instances'] == 92
    assert source_qa['expanded_triangles'] == 390194
    assert source_qa['expanded_polygons'] == 204526
    assert source_qa['checks'] == 1321844
    assert source_qa['packages_reopened'] == 49

    policy = load_policy()
    component_paths = {}
    manifest_before = {}
    new_rows = []
    for component in catalog:
        package_path = ROOT / component['component_source'].replace('\\', '/')
        manifest_path = package_path.parent / 'asset_manifest.json'
        assert package_path.is_file(), f'缺少组件源：{package_path}'
        assert sha256(package_path) == component['source_sha256'], f'组件哈希不匹配：{component["key"]}'
        assert manifest_path.is_file(), f'缺少组件manifest：{manifest_path}'
        component_paths[component['asset_id']] = (package_path, manifest_path)
        manifest_before[manifest_path] = manifest_path.read_bytes()
        new_rows.append(component_record(component, package_path, manifest_path, policy))

    ledger_index = read_json(INDEX_PATH)
    route = ledger_index['domains']['scenes']
    ledger_path = ROOT / route['ledger']
    ledger_before = ledger_path.read_bytes()
    source_index_before = SOURCE_INDEX_PATH.read_bytes()
    views_before = {name: (ROOT / path).read_bytes() for name, path in route['building_views'].items()}
    book = read_json(ledger_path)
    source_index = read_json(SOURCE_INDEX_PATH)
    all_domain_rows = {}
    for domain, domain_route in ledger_index['domains'].items():
        rows = read_json(ROOT / domain_route['ledger'])[domain_route['asset_key']]
        for row in rows:
            assert row['asset_id'] not in all_domain_rows, f'重复AssetID：{row["asset_id"]}'
            all_domain_rows[row['asset_id']] = row
    existing_rows = {row['asset_id']: row for row in book[route['asset_key']]}
    target_ids = {row['asset_id'] for row in new_rows} | {ASSEMBLY_ID}
    assert not (target_ids - set(existing_rows)) or all(existing_rows[x].get('suite') == 'bld_20261109_a' for x in target_ids & set(existing_rows))

    old_index_rows = {row['asset_id']: row for row in source_index['sources']}
    for asset_id, row in existing_rows.items():
        if asset_id not in target_ids:
            assert old_index_rows.get(asset_id) == source_projection(row), f'旧source index不一致：{asset_id}'

    assembly_manifest_path = SOURCE_DIR / 'asset_manifest.json'
    manifest_before[assembly_manifest_path] = assembly_manifest_path.read_bytes() if assembly_manifest_path.exists() else None
    palette = plan['palette']
    palette_sha = plan.get('palette_sha256')
    if palette_sha is None:
        palette_sha = sha256(ROOT / palette)
    assert sha256(ROOT / palette) == palette_sha
    material_roles = sorted({role for component in catalog for role in component['material_roles']})
    master_row = {
        'asset_id': ASSEMBLY_ID,
        'name': DISPLAY_NAME,
        'display_name': DISPLAY_NAME,
        'domain': 'scenes',
        'suite': 'bld_20261109_a',
        'scope': 'scene_local',
        'category': 'building_assembly',
        'classification': {'category': 'building', 'subcategory': 'structure'},
        'building_class': 'above_water',
        'water_layer': 'surface',
        'water_layer_role': 'entity',
        'source': rel(ASSEMBLY_SOURCE),
        'source_sha256': source_sha,
        'manifest': rel(assembly_manifest_path),
        'material_roles': material_roles,
        'palette': palette,
        'palette_sha256': palette_sha,
        'version': VERSION,
        'origin': 'bottom_center',
        'front_axis': plan['dimensions']['front_axis'],
        'stage': STAGE,
        'consumer_features': ['SEA-ASSET'],
        'component_count': 49,
        'instance_count': 92,
        'expanded_triangles': source_qa['expanded_triangles'],
        'expanded_polygons': source_qa['expanded_polygons'],
        'verification': EVIDENCE,
        'source_verification': 'source_verification_passed_visual_review_signed',
        'verification_pending': ['Godot', 'collision', 'navigation', 'commercial_authorization', 'user_final_art_acceptance'],
    }
    master_row.update(pending_fields())
    new_rows.append(master_row)

    registration_backup = WORK_DIR / 'registry_before_registration'
    registration_backup.mkdir(parents=True, exist_ok=True)
    if not (registration_backup / 'scenes.json').exists():
        (registration_backup / 'scenes.json').write_bytes(ledger_before)
    if not (registration_backup / 'current_source_index.json').exists():
        (registration_backup / 'current_source_index.json').write_bytes(source_index_before)
    manifest_backup = registration_backup / 'asset_manifests'
    manifest_backup.mkdir(parents=True, exist_ok=True)
    for manifest_path, content in manifest_before.items():
        target = manifest_backup / (manifest_path.relative_to(SOURCE_DIR).as_posix().replace('/', '__'))
        if not target.exists() and content is not None:
            target.write_bytes(content)

    # Re-check all optimistic snapshots before any JSON write.
    assert ledger_path.read_bytes() == ledger_before, '账本并发修改，拒绝写入'
    assert SOURCE_INDEX_PATH.read_bytes() == source_index_before, 'source index并发修改，拒绝写入'
    assert all(path.read_bytes() == content for path, content in manifest_before.items() if content is not None), 'manifest并发修改，拒绝写入'
    assert sha256(ASSEMBLY_SOURCE) == source_sha, '主源并发修改，拒绝写入'

    for component, row in zip(catalog, new_rows[:49]):
        package_path, manifest_path = component_paths[component['asset_id']]
        manifest = read_json(manifest_path)
        manifest.update(row)
        manifest.update({
            'schema': 'sea.scene.component_manifest',
            'asset_ledger': route['ledger'] + '#' + row['asset_id'],
            'component_key': component['key'],
            'component_family': component['component_family'],
            'source': rel(package_path),
            'source_sha256': component['source_sha256'],
            'palette_sha256': palette_sha,
        })
        dump(manifest_path, manifest)

    assembly_manifest = {
        'schema': 'sea.scene.assembly_manifest',
        **master_row,
        'asset_ledger': route['ledger'] + '#' + ASSEMBLY_ID,
        'component_plan': rel(PLAN_PATH),
        'catalog': rel(CATALOG_PATH),
        'instances': rel(INSTANCES_PATH),
        'reference': rel(SOURCE_DIR / plan['reference']),
        'reference_sha256': plan['reference_sha256'],
        'palette_sha256': palette_sha,
        'dimensions': plan['dimensions'],
        'source_report': str(SOURCE_QA_PATH).replace('\\', '/'),
        'visual_review': str(VISUAL_QA_PATH).replace('\\', '/'),
        'pending': ['Godot integration', 'runtime collision', 'navigation', 'commercial rights', 'user final art acceptance'],
    }
    dump(assembly_manifest_path, assembly_manifest)

    old_rows = [row for row in book[route['asset_key']] if row['asset_id'] not in target_ids]
    book[route['asset_key']] = old_rows + new_rows
    assert all(next(row for row in book[route['asset_key']] if row['asset_id'] == asset_id) == row for asset_id, row in existing_rows.items() if asset_id not in target_ids)
    dump(ledger_path, book)

    projected = []
    for domain, domain_route in ledger_index['domains'].items():
        rows = read_json(ROOT / domain_route['ledger'])[domain_route['asset_key']]
        for row in rows:
            projected.append(source_projection(row))
    source_index['sources'] = projected
    dump(SOURCE_INDEX_PATH, source_index)

    scene_rows = book[route['asset_key']]
    for name, view in policy.building_views(scene_rows, route['ledger']).items():
        dump(ROOT / route['building_views'][name], view)

    report = {
        'passed': True,
        'registered_rows': len(new_rows),
        'component_rows': 49,
        'assembly_rows': 1,
        'instance_count': 92,
        'expanded_triangles': source_qa['expanded_triangles'],
        'expanded_polygons': source_qa['expanded_polygons'],
        'unrelated_rows_preserved': len(old_rows),
        'source_sha256': source_sha,
        'building_class_counts': {
            'above_water': sum(row['building_class'] == 'above_water' for row in new_rows),
            'none': sum(row['building_class'] is None for row in new_rows),
        },
        'texture_rows': 0,
        'godot_files_changed': 0,
        'glb_files_changed': 0,
    }
    dump(WORK_DIR / 'registration_report.json', report)
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))


if __name__ == '__main__':
    main()

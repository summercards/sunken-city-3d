"""登记 ocean_rooftop_farm/v002；只在主源最终稳定后执行。"""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / 'art_source/scenes/ocean_rooftop_farm/v002'
CATALOG_PATH = SOURCE_DIR / 'component_catalog.json'
PLAN_PATH = SOURCE_DIR / 'component_plan.json'
INSTANCES_PATH = SOURCE_DIR / 'component_instances.json'
ASSEMBLY_SOURCE = SOURCE_DIR / 'ocean_rooftop_farm_v002.blend'
INDEX_PATH = ROOT / 'assets/registry/ledger_index.json'
PREFIX = 'SEA-SCENE-ORF2-'
ASSEMBLY_ID = 'SEA-SCENE-ORF2-ASSEMBLY'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def rel(path):
    return path.relative_to(ROOT).as_posix()


def component_record(component, package, manifest_path, package_sha, geometry_fingerprint):
    return {
        'asset_id': component['asset_id'],
        'name': component['name'],
        'domain': 'scenes',
        'stage': 'source_verified_runtime_pending',
        'source': rel(package),
        'source_sha256': package_sha,
        'manifest': rel(manifest_path),
        'version': 'v002',
        'runtime_path': None,
        'prefab': None,
        'license': 'pending_user_reference_rights_review',
        'geometry_fingerprint': geometry_fingerprint,
        'consumer_features': ['SEA-ASSET'],
        'category': component['category'],
        'building_class': 'above_water',
        'water_layer': 'surface',
        'water_layer_role': 'part',
        'scope': 'scene_local',
        'source_verification': 'passed_independent_reopen_130_checks_and_skill_validator',
        'verification_pending': [
            'Godot',
            'collision',
            'commercial_authorization',
            'final_art_review',
        ],
        'note': '海上屋顶农场 v002 全新组件；39组件913实例，源级130检查与技能验证通过；未接入Godot，碰撞、商业授权及最终美术验收pending。',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--confirm-final', action='store_true', help='确认主源已最终稳定并允许计算登记哈希')
    args = parser.parse_args()
    if not args.confirm_final:
        parser.error('主源未确认最终稳定；请在确认后使用 --confirm-final 执行')

    for path in [CATALOG_PATH, PLAN_PATH, INSTANCES_PATH, ASSEMBLY_SOURCE]:
        assert path.is_file(), f'缺少 v002 文件：{rel(path)}'
    plan = read_json(PLAN_PATH)
    catalog = read_json(CATALOG_PATH)['components']
    instances = read_json(INSTANCES_PATH)['instances']
    assert len(catalog) == 39, f'组件数不是39：{len(catalog)}'
    ids = [component['asset_id'] for component in catalog]
    assert len(set(ids)) == 39 and all(asset_id.startswith(PREFIX) for asset_id in ids)
    assert ASSEMBLY_ID not in ids
    assert plan['version'] == 'v002' and plan['design_clause'] == 'SEA-ASSET-R41'
    assert plan['building_class'] == 'above_water'
    assert plan['dimensions']['building_xy_m'] == [48, 32]
    assert plan['dimensions']['floors'] == 12 and plan['dimensions']['floor_height_m'] == 5.0
    assert plan['dimensions']['roof_top_z_m'] == 60.0
    assert set(plan['excluded']) >= {'animals', 'people', 'sea', 'background_geometry'}

    route = read_json(INDEX_PATH)['domains']['scenes']
    ledger_path = ROOT / route['ledger']
    book = read_json(ledger_path)
    rows = book[route['asset_key']]
    existing = {row['asset_id']: row for row in rows}
    target_ids = set(ids) | {ASSEMBLY_ID}
    for asset_id in target_ids:
        old = existing.get(asset_id)
        if old is not None:
            old_source = str(old['source']).replace('\\', '/')
            assert old_source.startswith('art_source/scenes/ocean_rooftop_farm/v002/'), (
                f'拒绝覆盖其他版本或其他源：{asset_id} -> {old_source}'
            )

    source_sha = sha256(ASSEMBLY_SOURCE)
    qa = read_json(ROOT.parent / 'sea-work/ocean_rooftop_farm/v002/source_verification.json')
    skill_qa = read_json(ROOT.parent / 'sea-work/ocean_rooftop_farm/v002/skill_verification.json')
    assert qa['passed'] and skill_qa['passed'], '源级或技能级验收未通过'
    assert qa['source_sha256'] == source_sha, '验收后主源发生变化'
    reference_path = SOURCE_DIR / plan['reference']
    assert reference_path.is_file(), f'缺少参考图：{rel(reference_path)}'
    reference_sha = sha256(reference_path)
    manifest_rows = []
    records = []
    for component in catalog:
        package = ROOT / component['component_source'].replace('\\', '/')
        assert package.is_file(), f'组件源未准备好：{rel(package)}'
        package_sha = sha256(package)
        manifest_path = package.parent / 'asset_manifest.json'
        old_manifest = read_json(manifest_path) if manifest_path.is_file() else {}
        geometry_fingerprint = old_manifest.get('geometry_fingerprint')
        manifest = dict(old_manifest)
        manifest.update({
            'schema': 'sea.scene.component_manifest',
            'asset_id': component['asset_id'],
            'name': component['name'],
            'asset_ledger': route['ledger'] + '#' + component['asset_id'],
            'source': rel(package),
            'source_sha256': package_sha,
            'version': 'v002',
            'category': component['category'],
            'component_family': component['component_family'],
            'building_class': 'above_water',
            'water_layer': 'surface',
            'water_layer_role': 'part',
            'scope': 'scene_local',
            'source_verification': 'passed_independent_reopen_130_checks_and_skill_validator',
            'license': 'pending_user_reference_rights_review',
        })
        write_json(manifest_path, manifest)
        manifest_rows.append((manifest_path, manifest))
        records.append(component_record(component, package, manifest_path, package_sha, geometry_fingerprint))

    assembly_manifest = {
        'schema': 'sea.scene.assembly_manifest',
        'asset_id': ASSEMBLY_ID,
        'name': '六十米海上屋顶农场 v002',
        'asset_ledger': route['ledger'] + '#' + ASSEMBLY_ID,
        'source': rel(ASSEMBLY_SOURCE),
        'source_sha256': source_sha,
        'version': 'v002',
        'category': 'scene_assembly',
        'building_class': 'above_water',
        'water_layer': 'surface',
        'water_layer_role': 'entity',
        'runtime_status': 'pending',
        'source_verification': 'passed_independent_reopen_130_checks_and_skill_validator',
        'license': 'pending_user_reference_rights_review',
        'component_catalog': 'component_catalog.json',
        'component_plan': 'component_plan.json',
        'component_instances': 'component_instances.json',
        'reference': plan['reference'],
        'reference_sha256': reference_sha,
        'component_count': len(catalog),
        'instance_count': len(instances),
        'palette': plan['palette'].replace('\\', '/'),
        'palette_asset_id': 'SEA-PALETTE-CABIN-TIMBER-64',
        'metrics': {
            'components': len(catalog),
            'instances': len(instances),
            'floors': plan['dimensions']['floors'],
            'floor_height_m': plan['dimensions']['floor_height_m'],
            'building_xy_m': plan['dimensions']['building_xy_m'],
            'roof_top_z_m': plan['dimensions']['roof_top_z_m'],
        },
        'excluded': plan['excluded'],
        'verification_pending': [
            'Godot',
            'collision',
            'commercial_authorization',
            'final_art_review',
        ],
        'visual_review': {'status': 'four_views_reviewed_final_user_art_acceptance_pending', 'views': ['01_reference_roof.png', '02_full_building.png', '03_top_plan.png', '04_greenhouse_detail.png'], 'expanded_triangles': qa['expanded_triangles']}, 
        'note': '新建 v002；不覆盖 ocean_rooftop_farm/v001，不含动物、人物、海面或背景；包含草地、作物、太阳能组件。',
    }
    assembly_manifest_path = SOURCE_DIR / 'asset_manifest.json'
    write_json(assembly_manifest_path, assembly_manifest)
    records.append({
        'asset_id': ASSEMBLY_ID,
        'name': assembly_manifest['name'],
        'domain': 'scenes',
        'stage': 'source_verified_runtime_pending',
        'source': assembly_manifest['source'],
        'source_sha256': source_sha,
        'manifest': rel(assembly_manifest_path),
        'version': 'v002',
        'runtime_path': None,
        'prefab': None,
        'license': assembly_manifest['license'],
        'geometry_fingerprint': None,
        'consumer_features': ['SEA-ASSET'],
        'category': 'scene_assembly',
        'building_class': 'above_water',
        'water_layer': 'surface',
        'water_layer_role': 'entity',
        'scope': 'scene_local',
        'runtime_status': 'pending',
        'source_verification': 'passed_independent_reopen_130_checks_and_skill_validator',
        'verification_pending': assembly_manifest['verification_pending'],
        'note': assembly_manifest['note'],
    })

    by_id = {row['asset_id']: row for row in records}
    book[route['asset_key']] = [row for row in rows if row['asset_id'] not in target_ids] + [by_id[asset_id] for asset_id in ids] + [by_id[ASSEMBLY_ID]]
    write_json(ledger_path, book)

    source_index_path = ROOT / 'assets/registry/current_source_index.json'
    index = read_json(source_index_path)
    old_index_rows = {row['asset_id']: row for row in index['sources']}
    ledger_rows_by_id = {}
    for routing in read_json(INDEX_PATH)['domains'].values():
        domain_book = read_json(ROOT / routing['ledger'])
        ledger_rows_by_id.update({row['asset_id']: row for row in domain_book[routing['asset_key']]})
    for asset_id, old_row in old_index_rows.items():
        if asset_id in target_ids:
            continue
        ledger_row = ledger_rows_by_id.get(asset_id)
        assert ledger_row is not None, f'索引存在账本缺失资产，拒绝覆盖：{asset_id}'
        expected = {key: ledger_row[key] for key in ['asset_id', 'source', 'source_sha256', 'manifest']}
        assert old_row == expected, f'并行改动或旧索引不一致，拒绝覆盖：{asset_id}'
    source_rows = []
    for domain, routing in read_json(INDEX_PATH)['domains'].items():
        domain_book = read_json(ROOT / routing['ledger'])
        source_rows.extend({key: asset[key] for key in ['asset_id', 'source', 'source_sha256', 'manifest']} for asset in domain_book[routing['asset_key']])
    index['sources'] = source_rows
    write_json(source_index_path, index)
    print(json.dumps({
        'registered_components': len(catalog),
        'registered_assembly': ASSEMBLY_ID,
        'version': 'v002',
        'source_verification': 'passed_independent_reopen_130_checks_and_skill_validator',
        'v001_touched': False,
        'final_hashes_computed_at_registration': True,
    }, ensure_ascii=False))


if __name__ == '__main__':
    main()

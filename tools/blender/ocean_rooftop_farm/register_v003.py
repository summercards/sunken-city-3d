"""登记 ocean_rooftop_farm/v003；仅在两级验证通过且源哈希匹配后执行。"""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / 'art_source/scenes/ocean_rooftop_farm/v003'
CATALOG_PATH = SOURCE_DIR / 'component_catalog.json'
PLAN_PATH = SOURCE_DIR / 'component_plan.json'
INSTANCES_PATH = SOURCE_DIR / 'component_instances.json'
ASSEMBLY_SOURCE = SOURCE_DIR / 'ocean_rooftop_farm_v003.blend'
QA_DIR = ROOT.parent / 'sea-work/ocean_rooftop_farm/v003'
SOURCE_QA_PATH = QA_DIR / 'source_verification.json'
SKILL_QA_PATH = QA_DIR / 'skill_verification.json'
INDEX_PATH = ROOT / 'assets/registry/ledger_index.json'
SOURCE_INDEX_PATH = ROOT / 'assets/registry/current_source_index.json'
PREFIX = 'SEA-SCENE-ORF2-'
ASSEMBLY_ID = 'SEA-SCENE-ORF2-ASSEMBLY'
SOURCE_VERIFICATION_LABEL = 'passed_source_and_skill_verification'
EXPECTED_ADDED_KEYS = {
    'window_cracked',
    'window_broken',
    'moss_cluster',
    'stair_flight',
    'stair_landing',
    'roof_entry',
    'stair_landing_open',
    'broken_flight',
    'turf_core',
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def rel(path):
    return path.relative_to(ROOT).as_posix()


def source_row(record):
    return {key: record[key] for key in ['asset_id', 'source', 'source_sha256', 'manifest']}


def component_record(component, package, manifest_path, package_sha, geometry_fingerprint, previous):
    record = {
        'asset_id': component['asset_id'],
        'name': component['name'],
        'domain': 'scenes',
        'stage': 'source_verified_runtime_pending',
        'source': rel(package),
        'source_sha256': package_sha,
        'manifest': rel(manifest_path),
        'version': 'v003',
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
        'source_verification': SOURCE_VERIFICATION_LABEL,
        'verification_pending': [
            'Godot',
            'collision',
            'commercial_authorization',
            'final_art_review',
        ],
        'note': '海上屋顶农场 v003 48组件；厚外挑无草水泥边台、深凹窗、宽主柱、三种破损窗、坡顶高差、不均苔藓及上三层消防梯修订；源级与技能级验证门禁通过。',
    }
    if previous is not None:
        history = list(previous.get('previous_sources', []))
        history.append({key: previous[key] for key in ['source', 'source_sha256', 'manifest', 'version']})
        record['previous_sources'] = history
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--confirm-final', action='store_true', help='确认 v003 主源已最终稳定并允许登记')
    args = parser.parse_args()
    if not args.confirm_final:
        parser.error('v003 主源未确认最终稳定；请在确认后使用 --confirm-final 执行')

    required = [CATALOG_PATH, PLAN_PATH, INSTANCES_PATH, ASSEMBLY_SOURCE,
                SOURCE_QA_PATH, SKILL_QA_PATH, INDEX_PATH, SOURCE_INDEX_PATH]
    for path in required:
        assert path.is_file(), f'缺少登记所需文件：{path}'

    plan = read_json(PLAN_PATH)
    catalog = read_json(CATALOG_PATH)['components']
    instances = read_json(INSTANCES_PATH)['instances']
    assert len(catalog) == 48, f'v003组件数不是48：{len(catalog)}'
    ids = [component['asset_id'] for component in catalog]
    keys = [component['key'] for component in catalog]
    assert len(set(ids)) == 48 and all(asset_id.startswith(PREFIX) for asset_id in ids)
    assert len(set(keys)) == 48
    assert ASSEMBLY_ID not in ids

    old_plan = read_json(ROOT / 'art_source/scenes/ocean_rooftop_farm/v002/component_plan.json')
    old_catalog = read_json(ROOT / 'art_source/scenes/ocean_rooftop_farm/v002/component_catalog.json')['components']
    old_ids = {component['asset_id'] for component in old_catalog}
    v003_ids = set(ids)
    assert len(old_catalog) == 39
    assert old_ids <= v003_ids
    assert {component['key'] for component in catalog} - {component['key'] for component in old_catalog} == EXPECTED_ADDED_KEYS
    assert plan['version'] == 'v003' and plan['design_clause'] == 'SEA-ASSET-R41'
    assert plan['building_class'] == 'above_water'
    assert plan['component_budget']['planned'] == 48
    assert plan['dimensions']['building_xy_m'] == [48, 32]
    assert plan['dimensions']['floors'] == 12 and plan['dimensions']['floor_height_m'] == 5.0
    assert plan['dimensions']['roof_top_z_m'] == 60.0
    assert set(plan['excluded']) >= {'animals', 'people', 'sea', 'background_geometry'}
    assert plan['stair_contract']['base_z'] == 45
    assert plan['stair_contract']['roof_z'] == 60
    assert plan['stair_contract']['flights'] == 6
    assert plan['stair_contract']['continuous_from_ground'] is False
    assert plan['latest_user_revision_1101']['perimeter'] == 'thick outward concrete rim without grass'
    assert plan['latest_user_revision_1101']['fire_escape'] == 'top three floors only, suspended broken lower end'
    assert plan['latest_user_revision_1101']['metal'] == 'dark diffuse matte, no polished shiny metal'

    ledger_index = read_json(INDEX_PATH)
    route = ledger_index['domains']['scenes']
    ledger_path = ROOT / route['ledger']
    book = read_json(ledger_path)
    rows = book[route['asset_key']]
    existing = {row['asset_id']: row for row in rows}
    source_index = read_json(SOURCE_INDEX_PATH)
    source_index_rows = {row['asset_id']: row for row in source_index['sources']}
    target_ids = v003_ids | {ASSEMBLY_ID}

    baseline_ids = old_ids | {ASSEMBLY_ID}
    for asset_id in baseline_ids:
        old = existing.get(asset_id)
        assert old is not None, f'缺少 v002 登记基线：{asset_id}'
        old_source = str(old['source']).replace('\\', '/')
        assert old_source.startswith('art_source/scenes/ocean_rooftop_farm/v002/'), (
            f'拒绝覆盖其他版本或其他源：{asset_id} -> {old_source}'
        )
        old_path = ROOT / old_source
        assert old_path.is_file(), f'缺少 v002 基线源：{old_source}'
        assert sha256(old_path) == old['source_sha256'], f'v002源哈希漂移：{asset_id}'
        indexed = source_index_rows.get(asset_id)
        assert indexed == source_row(old), f'current_source_index 的 v002 基线不一致：{asset_id}'

    for asset_id in target_ids - baseline_ids:
        old = existing.get(asset_id)
        if old is not None:
            old_source = str(old['source']).replace('\\', '/')
            assert old_source.startswith('art_source/scenes/ocean_rooftop_farm/v002/'), (
                f'拒绝覆盖其他版本或其他源：{asset_id} -> {old_source}'
            )

    source_qa = read_json(SOURCE_QA_PATH)
    skill_qa = read_json(SKILL_QA_PATH)
    assert source_qa.get('passed') is True, 'source_verification.json 未通过'
    assert skill_qa.get('passed') is True, 'skill_verification.json 未通过'
    skill_rows = skill_qa.get('components')
    assert isinstance(skill_rows, list) and len(skill_rows) == 48, 'skill_verification.json 组件数不是48'
    assert all(row.get('passed') is True for row in skill_rows), '存在未通过的技能验证组件'
    source_sha = sha256(ASSEMBLY_SOURCE)
    assert source_qa.get('source_sha256') == source_sha, '验收后 v003 主源发生变化'

    route_records = []
    for component in catalog:
        package = ROOT / component['component_source'].replace('\\', '/')
        assert package.is_file(), f'组件源未准备好：{rel(package)}'
        package_sha = sha256(package)
        assert component.get('source_sha256') == package_sha, f'组件目录哈希不匹配：{component["key"]}'
        manifest_path = package.parent / 'asset_manifest.json'
        old_manifest = read_json(manifest_path) if manifest_path.is_file() else {}
        if old_manifest.get('source_sha256') is not None:
            assert old_manifest['source_sha256'] == package_sha, f'组件manifest哈希不匹配：{component["key"]}'
        geometry_fingerprint = component.get('geometry_fingerprint')
        manifest = dict(old_manifest)
        manifest.update({
            'schema': 'sea.scene.component_manifest',
            'asset_id': component['asset_id'],
            'name': component['name'],
            'asset_ledger': route['ledger'] + '#' + component['asset_id'],
            'source': rel(package),
            'source_sha256': package_sha,
            'version': 'v003',
            'category': component['category'],
            'component_family': component['component_family'],
            'building_class': 'above_water',
            'water_layer': 'surface',
            'water_layer_role': 'part',
            'scope': 'scene_local',
            'source_verification': SOURCE_VERIFICATION_LABEL,
            'license': 'pending_user_reference_rights_review',
        })
        write_json(manifest_path, manifest)
        route_records.append(component_record(
            component, package, manifest_path, package_sha, geometry_fingerprint, existing.get(component['asset_id'])
        ))

    reference_path = SOURCE_DIR / plan['reference']
    assembly_manifest = {
        'schema': 'sea.scene.assembly_manifest',
        'asset_id': ASSEMBLY_ID,
        'name': '六十米海上屋顶农场 v003',
        'asset_ledger': route['ledger'] + '#' + ASSEMBLY_ID,
        'source': rel(ASSEMBLY_SOURCE),
        'source_sha256': source_sha,
        'version': 'v003',
        'category': 'scene_assembly',
        'building_class': 'above_water',
        'water_layer': 'surface',
        'water_layer_role': 'entity',
        'runtime_status': 'pending',
        'source_verification': SOURCE_VERIFICATION_LABEL,
        'license': 'pending_user_reference_rights_review',
        'component_catalog': 'component_catalog.json',
        'component_plan': 'component_plan.json',
        'component_instances': 'component_instances.json',
        'reference': plan['reference'],
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
            'navigation',
            'commercial_authorization',
            'final_art_review',
        ],
        'visual_review': {
            'status': 'views_reviewed_source_and_skill_verification_passed',
            'views': [
                '01_reference_roof.png',
                '02_fire_escape_full.png',
                '03_roof_entry.png',
                '04_facade_detail.png',
                '05_top_plan.png',
            ],
        },
        'revision_summary': [
            '厚外挑无草水泥边台 49.6x33.6x0.65m',
            '深凹窗、宽主柱、intact/cracked/broken 三种窗状态',
            '坡顶高差与不均苔藓',
            '粗杆直径 0.18-0.2m，金属 metallic 0.15、roughness 0.82',
            '消防梯仅保留45至60米上三层6段，下挂残梯，取消地面连续通行',
            '屋顶入口删除共面桥面，边对边接承接板顶59.97m',
        ],
        'note': 'v003 基于 v002 的稳定 AssetID 更新；不修改 v002 源文件和源哈希记录基线；未接入 Godot。',
    }
    if reference_path.is_file():
        reference_sha = sha256(reference_path)
        assembly_manifest['reference_sha256'] = reference_sha
        if source_qa.get('reference_sha256') is not None:
            assert source_qa['reference_sha256'] == reference_sha, '参考图哈希不匹配'
    assembly_manifest_path = SOURCE_DIR / 'asset_manifest.json'
    write_json(assembly_manifest_path, assembly_manifest)
    previous_assembly = existing.get(ASSEMBLY_ID)
    assembly_record = {
        'asset_id': ASSEMBLY_ID,
        'name': assembly_manifest['name'],
        'domain': 'scenes',
        'stage': 'source_verified_runtime_pending',
        'source': assembly_manifest['source'],
        'source_sha256': source_sha,
        'manifest': rel(assembly_manifest_path),
        'version': 'v003',
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
        'source_verification': SOURCE_VERIFICATION_LABEL,
        'verification_pending': assembly_manifest['verification_pending'],
        'note': assembly_manifest['note'],
    }
    if previous_assembly is not None:
        history = list(previous_assembly.get('previous_sources', []))
        history.append({key: previous_assembly[key] for key in ['source', 'source_sha256', 'manifest', 'version']})
        assembly_record['previous_sources'] = history
    route_records.append(assembly_record)

    by_id = {record['asset_id']: record for record in route_records}
    book[route['asset_key']] = [row for row in rows if row['asset_id'] not in target_ids]
    book[route['asset_key']].extend(by_id[asset_id] for asset_id in ids)
    book[route['asset_key']].append(by_id[ASSEMBLY_ID])
    write_json(ledger_path, book)

    # current_source_index 是来源索引；ledger_index 只负责取得上面的账本路由。
    new_source_rows = {record['asset_id']: source_row(record) for record in route_records}
    source_rows = []
    seen = set()
    for row in source_index['sources']:
        asset_id = row['asset_id']
        if asset_id in target_ids:
            if asset_id not in seen:
                source_rows.append(new_source_rows[asset_id])
                seen.add(asset_id)
        else:
            source_rows.append(row)
    for asset_id in ids + [ASSEMBLY_ID]:
        if asset_id not in seen:
            source_rows.append(new_source_rows[asset_id])
            seen.add(asset_id)
    assert len({row['asset_id'] for row in source_rows}) == len(source_rows)
    source_index['sources'] = source_rows
    write_json(SOURCE_INDEX_PATH, source_index)

    print(json.dumps({
        'registered_components': len(catalog),
        'registered_assembly': ASSEMBLY_ID,
        'version': 'v003',
        'source_verification': 'passed',
        'skill_verification': 'passed',
        'v002_source_files_touched': False,
        'v002_hash_baseline_updated': False,
        'unrelated_source_index_rows_preserved': True,
    }, ensure_ascii=False))


if __name__ == '__main__':
    main()

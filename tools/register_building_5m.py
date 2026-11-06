#!/usr/bin/env python3
"""精确登记五米十组件及建筑 UI 路径；默认只预检，不运行 Godot 或全局同步。"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'art_source/scenes/ocean_building_kit/v002'
CATALOG = 'godot/assets/data/building_kit_5m.json'
EVIDENCE = 'docs/development/2026-11-06_building_5m_and_ui.md'
PENDING = 'source_verified_runtime_final_pending'
VERIFIED = 'runtime_integrated_verified'
IDS = {
    'platform_5x5': 'SEA-KIT-PLATFORM-5X5',
    'wall_5m': 'SEA-KIT-WALL-5M',
    'window_wall_5m': 'SEA-KIT-WINDOW-WALL-5M',
    'door_frame_5m': 'SEA-KIT-DOOR-FRAME-5M',
    'post_5m': 'SEA-KIT-POST-5M',
    'beam_5m': 'SEA-KIT-BEAM-5M',
    'railing_5m': 'SEA-KIT-RAILING-5M',
    'stairs_5m': 'SEA-KIT-STAIRS-5M',
    'roof_slope_5x5': 'SEA-KIT-ROOF-SLOPE-5X5',
    'roof_flat_5x5': 'SEA-KIT-ROOF-FLAT-5X5',
}
MOVED_UIDS = {
    'building_book': 'uid://dyd34mhaftlpl',
    'recipe_card': 'uid://b6b474lgxoc1x',
    'recipe_thumbnail': 'uid://bs56ry6xkjr4j',
    'demolition_tool': 'uid://dtxn88x1ceivp',
}
# 只接受本次逐文件审阅的字节；后续并行编辑必须重新审阅，不能自动洗白。
REVIEWED_CODE = {
    'godot/src/building/assembly_rules.gd': '31229887070395b7609b8101c905a99beed7b7d1ea7918c9c4214496671340a0',
    'godot/src/building/assembly_surfaces.gd': 'e46385c6f61c215cdf99247b53c3e5eb3007667db2941556f6fad99369652ec2',
    'godot/src/building/building_access.gd': '04dd9e2772df80f0b8a936c47d830d05bcd766761a7ff09926b45fca7f406248',
    'godot/src/building/building_boundary.gd': '975f6d206e9cdf7bc7c99cf103b9a16ec99c037a4befcdb8ebabd6d4104b0bc7',
    'godot/src/building/building_catalog.gd': 'de723cd326adf57f66411a76f3a969037c2c9e7329e0e94cf86afb6c9cf1af41',
    'godot/src/building/building_controller.gd': '91977dd75f3735ceef93846b6336d83f014c04f221c43a47ba9bdc0a8f87aef0',
    'godot/src/building/building_pointer.gd': '37c7e80667bb42b5a70f0e66189b44701976bd7157c4f0b8e18ba753540268d3',
    'godot/src/building/building_service.gd': '3216ffe8b7f2f6086f73fd0a8a2c9f671b280683487c4e12e26e6dd0373db4b9',
    'godot/src/building/building_space.gd': 'aa08a9aa4096fe488cc8db69ea39ea1c198cc8e50b725d1935c68a43440a5680',
    'godot/src/building/building_world.gd': '38a3744a183d98c4d8982c30de59b7c8e27e2c3d4c05c916e0339ffe47961815',
    'godot/src/building/deck_visual.gd': 'bedb33953f15271bb02d6a41333185fca54aadef4fbbc69f81092fc32d5a03d2',
    'godot/src/building/kit_visual.gd': 'd2cc12782f87824639b9caabbb4694dae679f205f7eb3ec9f0bb7f794b15e54f',
    'godot/src/building/material_shop.gd': 'e4aa642e4d0b07269024d68da54f7c9f95d2d2a9a45bbfee754d4f9166757990',
    'godot/src/building/ui/building_book.gd': '3dde43c306e794876968b1d4f9b2c5e2452afe3adbb9fc7e4d4c788238e3ac5b',
    'godot/src/building/ui/recipe_card.gd': 'b9e4ab76db81b88918b8d2bf9ae8595c0d6eabd9c202ad1cff2ffe89030e506e',
    'godot/src/building/ui/recipe_thumbnail.gd': 'e7ddd080e6228681450792b2eed15a24f48fd4c0801e2ec32d5e53ba79dbcef9',
    'godot/src/building/ui/demolition_tool.gd': '75bb68feff6cd6a9081208a7cd290c625d7b4b3e4306cb4121f2e325707257d3',
    'godot/src/building/ui/building_view.gd': 'c58558c33d535d8dae03379caf7eb76131c812c776d66987794b5e75b68da616',
    'godot/src/building/ui/building_progress_presenter.gd': '027003b56ca64700520df390999833cc3bf3b1494527f69030b6c009b09dda5c',
    'godot/src/navigation/ground_space.gd': 'c42b93eea8e7848b576506cf8e5526127861bd70d0d5e5e2ce52323616f0b962',
}
REQUIRED_CHECKS = {
    'building-5m-rules', 'building-5m-experience', 'visual-building-5m-experience',
    'building-ui-unified', 'visual-building-ui-unified', 'keyboard-building',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def unique(rows, key):
    result = {row[key]: row for row in rows}
    require(len(result) == len(rows), '重复登记键：' + key)
    return result


def register(root=ROOT, evidence_dir=None, write=False, promotion=None):
    root = Path(root).resolve()
    evidence_dir = Path(evidence_dir) if evidence_dir else root.parent / 'sea-work/building_kit_v002'
    require(evidence_dir.is_dir(), '证据父目录必须已存在：' + str(evidence_dir))
    observed = {}
    planned = {}

    def raw(path):
        target = root / path
        require(target.is_file(), '缺少文件：' + path)
        value = target.read_bytes()
        if path in observed:
            require(observed[path] == value, '读取期间发生并行改动：' + path)
        observed[path] = value
        return value

    def read(path):
        return json.loads(raw(path).decode('utf-8'))

    def sha(path):
        return digest(raw(path))

    def plan(path, value):
        require((root / path).parent.is_dir(), '写入父目录必须已存在：' + path)
        before = raw(path)
        if json.loads(before.decode('utf-8')) == value:
            return
        newline = '\r\n' if b'\r\n' in before else '\n'
        planned[path] = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').replace('\n', newline).encode('utf-8')

    index = read('assets/registry/ledger_index.json')
    route = index['domains']['scenes']
    books = {name: read(routing['ledger']) for name, routing in index['domains'].items()}
    all_assets = [a for name, routing in index['domains'].items() for a in books[name][routing['asset_key']]]
    existing = unique(all_assets, 'asset_id')
    book = books['scenes']
    before_assets = deepcopy(book[route['asset_key']])
    catalog = unique(read(SOURCE + '/catalog.json')['components'], 'id')
    modules = read(CATALOG)['modules']
    require({x['id']: x['asset_id'] for x in modules} == IDS and len(modules) == 10, '只能登记冻结的十件资产')
    require({key: row['asset_id'] for key, row in catalog.items()} == IDS, '源 catalog 与十组件契约不符')
    source_report = json.loads((evidence_dir / 'source_validation.json').read_text(encoding='utf-8'))
    output_report = json.loads((evidence_dir / 'output_validation.json').read_text(encoding='utf-8'))
    require(source_report.get('passed') is True and source_report['invalid_uv_islands'] == 0, '源重开/UV未通过')
    require(output_report.get('passed') is True and output_report['module_count'] == 10, 'GLB静态验证未通过')
    output_rows = unique(output_report['components'], 'id')
    exports = unique(read(SOURCE + '/export/v002/export_manifest.json')['exports'], 'id')
    mother = SOURCE + '/building_kit.blend'
    optimized = SOURCE + '/export/v002/building_kit_optimized.blend'
    mother_hash, optimized_hash = sha(mother), sha(optimized)
    reopened = {(Path(x['reopened_file'].replace('\\', '/')).resolve(), x['id']): x for x in source_report['components']}
    for name, expected in REVIEWED_CODE.items():
        require(sha(name) == expected, '已审阅代码再次漂移，拒绝重算：' + name)

    resources = read(index['runtime_inventory'])
    before_resources = deepcopy(resources['resources'])
    by_path = unique(resources['resources'], 'path')
    touched = set()

    def runtime(path, asset_id=None):
        touched.add(path)
        row = by_path.get(path)
        if row is None:
            row = {'path': path, 'asset_id': asset_id}
            resources['resources'].append(row)
            by_path[path] = row
        if asset_id is not None:
            require(row.get('asset_id') in (None, asset_id), '运行路径已有其他资产：' + path)
            row['asset_id'] = asset_id
        new_hash = sha(path)
        if row.get('sha256') and row['sha256'] != new_hash:
            row['previous_sha256'] = row['sha256']
        keep_verified = (row.get('sha256') == new_hash and row.get('verification') == EVIDENCE
                         and row.get('status') in ('runtime_resource_verified', 'runtime_component_verified'))
        row.update(bytes=len(raw(path)), sha256=new_hash, verification=EVIDENCE)
        if not keep_verified:
            row['status'] = 'runtime_available_final_scene_pending'
        return row

    migrations = {}
    for name, uid in MOVED_UIDS.items():
        old = 'godot/src/building/' + name + '.gd'
        new = 'godot/src/building/ui/' + name + '.gd'
        require(not (root / old).exists() and not (root / (old + '.uid')).exists(), '旧UI路径仍存在：' + old)
        require(raw(new + '.uid').decode('utf-8').strip() == uid, '迁移UID改变：' + new)
        for suffix in ('', '.uid'):
            old_path, new_path = old + suffix, new + suffix
            previous = by_path.pop(old_path, None)
            if previous is not None:
                require(new_path not in by_path, '新旧路径同时登记，拒绝覆盖关联：' + new_path)
                resources['resources'].remove(previous)
                previous['path'] = new_path
                previous['previous_path'] = old_path
                resources['resources'].append(previous)
                by_path[new_path] = previous
            runtime(new_path)
            migrations[old_path] = new_path
    for path in REVIEWED_CODE:
        runtime(path)
    runtime(CATALOG)
    for definition in modules:
        key, aid = definition['id'], definition['asset_id']
        component = catalog[key]
        for field in ('name', 'profile', 'footprint', 'height', 'front_axis'):
            require(definition[field] == component[field], key + ' 目录字段不一致：' + field)
        source = SOURCE + '/component_packages/' + key + '/' + key + '.blend'
        manifest_path = SOURCE + '/component_packages/' + key + '/asset_manifest.json'
        manifest = read(manifest_path)
        glb = 'godot/assets/models/building_kit/' + key + '/' + key + '.glb'
        prefab = 'godot/scenes/buildables/kit/' + key + '.tscn'
        require(definition['prefab'] == prefab.replace('godot/', 'res://', 1), '不稳定的预制体路径：' + key)
        source_hash, glb_hash = sha(source), sha(glb)
        for path, expected in ((mother, mother_hash), (optimized, optimized_hash), (source, source_hash)):
            result = reopened.get(((root / path).resolve(), key))
            require(result is not None and result['sha256'] == expected and result['invalid_uv_islands'] == 0,
                    '重开证据哈希不匹配：' + path)
        export = exports[key]
        require(export['source_sha256_before'] == export['source_sha256_after'] == mother_hash, '母版保护哈希不匹配')
        require(export['optimized_sha256'] == optimized_hash, '优化源哈希不匹配')
        require(export['glb_sha256'] == output_rows[key]['sha256'] == manifest['glb_sha256'] == glb_hash, 'GLB证据漂移：' + key)
        require(manifest['source_sha256'] == mother_hash and manifest['component_sha256'] == source_hash, '组件证据漂移：' + key)
        require(output_rows[key]['embedded_images'] == 0 and output_rows[key]['prefab_references_valid'], 'GLB静态检查失败：' + key)
        prefab_text = raw(prefab).decode('utf-8')
        require(aid in prefab_text and glb.replace('godot/', 'res://', 1) in prefab_text, '预制体关联错误：' + key)
        old = existing.get(aid)
        asset = {
            'asset_id': aid, 'name': definition['name'], 'asset_key': key, 'domain': 'scenes',
            'stage': PENDING, 'version': 'v002', 'source': source, 'source_sha256': source_hash,
            'manifest': manifest_path, 'runtime_path': glb, 'runtime_sha256': glb_hash, 'prefab': prefab,
            'license': 'project_authored_procedural_geometry',
            'classification': {'category': 'building', 'subcategory': 'modular_structure'},
            'building_class': 'above_water', 'water_layer': 'surface', 'water_layer_role': 'entity',
            'consumer_features': ['SEA-BUILDING', 'SEA-ASSET', 'SEA-MOVE'],
            'collection': component['collection'], 'triangles': output_rows[key]['triangles'],
            'source_triangles': component['triangles'], 'bounds_blender': component['bounds'],
            'origin': definition['source_origin'], 'front_axis': definition['front_axis'],
            'profile': definition['profile'], 'footprint': definition['footprint'], 'height': definition['height'],
            'mother_source': mother, 'mother_source_sha256': mother_hash,
            'optimized_source': optimized, 'optimized_source_sha256': optimized_hash,
            'palette': 'art_source/shared/palettes/sea_cozy_8x8_512.png',
            'placement_owner': 'BuildingService instances; Godot PackedScene projection',
            'collision_responsibility': 'BuildingWorld/AssemblySurfaces/BuildingSpace derived projection; pure visual GLB',
            'source_verification': {'status': 'passed', 'report': str(evidence_dir / 'source_validation.json')},
            'transfer_verification': {'status': 'passed', 'report': str(evidence_dir / 'output_validation.json')},
            'runtime_verification': {'status': 'pending', 'owner': 'main_agent', 'verification': EVIDENCE},
            'verification': EVIDENCE,
            'note': '源重开、PaletteUV与GLB静态通过；Godot真实运行、通行、UI及最终渲染由主agent验收，登记不代签。',
        }
        if old:
            require(old['domain'] == 'scenes' and old['source'] == source and old['source_sha256'] == source_hash
                    and old['runtime_sha256'] == glb_hash, '既有同ID记录漂移，拒绝覆盖：' + aid)
            require(old['stage'] in (PENDING, VERIFIED), '未知阶段：' + aid)
            if old['stage'] == VERIFIED:
                asset = deepcopy(old)
            else:
                require(old == asset, '已登记内容改变，须审阅后独立更新：' + aid)
            book[route['asset_key']][book[route['asset_key']].index(old)] = asset
        else:
            book[route['asset_key']].append(asset)
        manifest.update(asset_ledger=route['ledger'] + '#' + aid, stage=asset['stage'],
                        source=source, registered_source_sha256=source_hash,
                        runtime_path=glb, runtime_sha256=glb_hash, verification=EVIDENCE,
                        runtime_verification=asset['runtime_verification'])
        plan(manifest_path, manifest)
        runtime(glb, aid)
        runtime(prefab, aid)
        if asset['stage'] == VERIFIED:
            for path in (glb, prefab):
                by_path[path]['status'] = 'runtime_component_verified'

    if promotion:
        final = json.loads(Path(promotion).read_text(encoding='utf-8'))
        passed = {x['check'] for x in final.get('results', []) if x.get('passed') is True
                  and x.get('exit_code') == 0 and x.get('unexpected_errors') == []}
        require(REQUIRED_CHECKS <= passed, '缺少最终真实运行/渲染结果：' + str(sorted(REQUIRED_CHECKS - passed)))
        require(final.get('runner') == 'scripts/run_verification.py' and final.get('approved_by') == 'main_agent', '仅主agent最终签署可晋升')
        require((root / EVIDENCE).is_file(), '主agent开发记录尚未创建')
        expected = {path: sha(path) for path in touched}
        require(final.get('resource_sha256') == expected, '最终证据必须绑定全部本批运行文件的当前哈希')
        for asset in book[route['asset_key']]:
            if asset['asset_id'] not in IDS.values():
                continue
            asset['stage'] = VERIFIED
            asset['runtime_verification'] = {'status': 'passed', 'owner': 'main_agent', 'report': str(promotion), 'verification': EVIDENCE}
            manifest_path = asset['manifest']
            manifest = json.loads(planned.get(manifest_path, raw(manifest_path)).decode('utf-8'))
            manifest.update(stage=VERIFIED, runtime_integrated=True, runtime_verification=asset['runtime_verification'])
            plan(manifest_path, manifest)
        for path in touched:
            by_path[path]['status'] = 'runtime_component_verified' if by_path[path].get('asset_id') in IDS.values() else 'runtime_resource_verified'

    projection_path = 'assets/registry/current_source_index.json'
    projection = read(projection_path)
    projection['sources'] = [{k: a[k] for k in ('asset_id', 'source', 'source_sha256', 'manifest')}
                            for name, routing in index['domains'].items() for a in books[name][routing['asset_key']]]
    content = read(index['content_index'])
    table = {'owner': 'SEA-BUILDING', 'path': CATALOG, 'collection_key': 'modules',
             'ids': [x['id'] for x in modules], 'note': '五米新组件目录；保留旧配方和稳定AssetID，不以登记代替运行验收。'}
    found = next((x for x in content['tables'] if x['path'] == CATALOG), None)
    if found is None:
        content['tables'].append(table)
    else:
        require(found == table, '五米content_index已有未知改动')
    require([a for a in before_assets if a['asset_id'] not in IDS.values()] ==
            [a for a in book[route['asset_key']] if a['asset_id'] not in IDS.values()], '修改了旧资产')
    require([x for x in before_resources if x['path'] not in touched and x['path'] not in migrations] ==
            [x for x in resources['resources'] if x['path'] not in touched], '修改了范围外运行记录')
    plan(route['ledger'], book)
    plan(index['runtime_inventory'], resources)
    plan(projection_path, projection)
    plan(index['content_index'], content)
    view_path = route['building_views']['above_water']
    view = read(view_path)
    view['asset_ids'] = [a['asset_id'] for a in book[route['asset_key']] if a.get('building_class') == 'above_water']
    plan(view_path, view)
    for path, before in observed.items():
        require((root / path).read_bytes() == before, '写入前发现并行修改，停止：' + path)
    if write:
        for path, value in planned.items():
            (root / path).write_bytes(value)
    print(json.dumps({'mode': '写入' if write else '只读预检', 'asset_count': 10,
                      'stage': VERIFIED if promotion else PENDING, 'changed_files': sorted(planned),
                      'resource_sha256': {path: by_path[path]['sha256'] for path in sorted(touched)},
                      'migrations': migrations, 'unrelated_records_unchanged': True}, ensure_ascii=False, indent=2))
    return planned


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='预检通过后精确写入')
    parser.add_argument('--evidence-dir', type=Path, help='已存在的源级验证证据目录')
    parser.add_argument('--promote-verified', type=Path, metavar='JSON', help='仅主agent最终验收后提供带文件哈希的结果清单')
    args = parser.parse_args()
    register(evidence_dir=args.evidence_dir, write=args.write, promotion=args.promote_verified)


if __name__ == '__main__':
    main()

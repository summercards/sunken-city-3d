"""本轮 NPC／住所／花卉登记；默认预检，--write 才写入，不接纳任务外漂移。"""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'assets/registry/'
DELIVERY = 'docs/features/asset/ledger.md#2026-11-07-npc住所花卉资产与内容登记'
ACTOR = 'godot/src/npc/npc_actor.gd'
ACCESSORIES = 'godot/src/npc/npc_accessories.gd'
AUTHOR = 'godot/src/residence/author_scenes.py'
FLOWER = 'godot/src/crops/flower_view.gd'
PARTS = {
    'signal_spool': ['RopeCoil', 'RouteClasp'],
    'seed_pouch': ['SeedPouch', 'LeafBrooch'],
    'diving_goggle': ['ForeheadGoggles', 'SealedRecordTube'],
    'joint_pencil': ['EarPencil', 'ToolBelt'],
    'lantern_badge': ['LampBadge', 'ArchiveBook'],
    'petal_visor': ['PetalVisor', 'PruningShears'],
    'stock_clip': ['CargoTagClip', 'WaistPack'],
}
# 已逐文件审阅本轮 diff；混有阳光房修改的 save 与多线程 Main 不在此表。
REVIEWED = {
    'godot/assets/data/items.json', 'godot/assets/data/crops.json',
    'godot/src/inventory/inventory.gd', 'godot/src/crops/crop_catalog.gd',
    'godot/src/crops/harvest_visual.gd',
}
PENDING = {
    'godot/src/bootstrap/main.gd': '多个并行模块接线，不能签署整文件未知变更',
    'godot/scenes/main.tscn': '大量并行场景变更，不能签署整文件未知变更',
    'godot/src/save/save_game.gd': 'NPC 与 SEA-SUNROOM 修改混合，整文件哈希保持原基线',
    'godot/src/save/save_schema.gd': 'NPC 与 SEA-SUNROOM 修改混合，整文件哈希保持原基线',
}


def main(write=False):
    snapshots, outputs, source_hashes = {}, {}, {}

    def read(path):
        raw = (ROOT / path).read_bytes()
        snapshots[path] = raw
        return json.loads(raw)

    def emit(path, value):
        if path not in snapshots:
            snapshots[path] = (ROOT / path).read_bytes() if (ROOT / path).exists() else None
        outputs[path] = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')

    def digest(path):
        raw = (ROOT / path).read_bytes()
        source_hashes[path] = hashlib.sha256(raw).hexdigest()
        return hashlib.sha256(raw.replace(b'\r\n', b'\n')).hexdigest()

    index = read(PREFIX + 'ledger_index.json')
    books = {d: read(v['ledger']) for d, v in index['domains'].items()}
    before = {d: len(books[d][r['asset_key']]) for d, r in index['domains'].items()}
    prior_rows = {a['asset_id']: a.copy() for d, r in index['domains'].items()
                  for a in books[d][r['asset_key']]}
    assert sum(before.values()) == len(prior_rows), '既有 AssetID 重复'
    rows, manifests = [], []
    spec = importlib.util.spec_from_file_location('water_rules', ROOT / 'tools/apply_water_layer.py')
    rules = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rules)

    def asset(domain, aid, name, source, related, consumers, category, **fields):
        route = index['domains'][domain]
        manifest_path = PREFIX + 'manifests/' + aid.lower() + '.json'
        row = dict(asset_id=aid, source_id='SRC-' + aid, name=name, domain=domain,
                   stage='source_registered_runtime_visual_pending', source=source,
                   source_sha256=digest(source), manifest=manifest_path, version='v001',
                   runtime_path=source, license='project_authored_procedural_source',
                   consumer_features=consumers,
                   classification={'category': category}, verification=DELIVERY,
                   validation={'source': 'registered_and_hash_checked', 'runtime': 'pending',
                               'visual': 'pending', 'user_art_acceptance': 'pending'},
                   note='正式 Godot 程序源／原生场景；未伪造 Blender 或 GLB。原创新增部分不替共享素材或商业参考签署许可。')
        row.update(fields)
        if domain == 'scenes':
            row.update(building_class=rules.classify_building(aid),
                       water_layer=rules.classify(aid)[0], water_layer_role=rules.classify(aid)[1])
        files = list(dict.fromkeys([source] + related))
        manifest = dict(asset_id=aid, source_id=row['source_id'],
                        asset_ledger=route['ledger'] + '#' + aid,
                        source=source, source_sha256=row['source_sha256'], version='v001',
                        source_type='project_authored_native_Godot_source_no_Blender_or_GLB',
                        authored_files=[{'path': p, 'sha256': digest(p)} for p in files],
                        validation=row['validation'], verification=DELIVERY,
                        reference_commercial_rights='not_granted_by_this_registration')
        for key in ['prefab', 'content_selector', 'accessory_parts', 'reused_asset_ids', 'stage_nodes']:
            if key in row: manifest[key] = row[key]
        rows.append(row)
        manifests.append((manifest_path, manifest))

    npcs = read('godot/assets/data/npc/npcs.json')['npcs']
    assert len(npcs) == 7 and len({n['accessory_id'] for n in npcs}) == 7
    asset('characters', 'SEA-CHAR-NPC-ACTOR-001', 'NPC 共用 AvatarRig 表现装配', ACTOR,
          [ACCESSORIES], ['SEA-RESIDENT'], 'character_assembly',
          reused_asset_ids=['SEA-CHAR-AVATAR-001', 'SEA-CHAR-RIG-001'])
    asset('characters', 'SEA-CHAR-NPC-ACCESSORIES-001', '七职业双配件程序源库', ACCESSORIES,
          [], ['SEA-RESIDENT'], 'character_accessory_library',
          accessory_parts=PARTS)
    for npc in npcs:
        aid = 'SEA-CHAR-' + npc['id'].replace('_', '-').upper()
        asset('characters', aid, npc['display_name'] + ' · ' + npc['role'], ACTOR,
              [ACCESSORIES], ['SEA-RESIDENT'], 'character_career_variant',
              content_selector={'path': 'godot/assets/data/npc/npcs.json', 'collection': 'npcs',
                                'id': npc['id']},
              accessory_parts=PARTS[npc['accessory_id']],
              reused_asset_ids=['SEA-CHAR-NPC-ACTOR-001', 'SEA-CHAR-NPC-ACCESSORIES-001',
                                'SEA-CHAR-AVATAR-001', 'SEA-CHAR-RIG-001'])

    kit_ids = ['SEA-KIT-PLATFORM-5X5', 'SEA-KIT-DOOR-FRAME-5M',
               'SEA-KIT-WINDOW-WALL-5M', 'SEA-KIT-WALL-5M', 'SEA-KIT-RAILING-5M',
               'SEA-KIT-TABLE', 'SEA-KIT-OIL-LAMP', 'SEA-KIT-STOOL',
               'SEA-KIT-STORAGE-CRATE', 'SEA-KIT-FLOWER-POT', 'SEA-KIT-WATER-BARREL',
               'SEA-KIT-WIND-CHIME', 'SEA-KIT-LAMP-POST']
    assert set(kit_ids) <= prior_rows.keys(), '共用 Kit 必须已登记'
    residence_dir = 'godot/scenes/residence/'
    materials = [residence_dir + 'materials/' + key + '.tres' for key in ['wood', 'linen', 'teal']]
    residences = read('godot/assets/data/npc/residences.json')['residences']
    for key, name, prefab in [('HARBOR', '七灯住所港总装', 'resident_harbor'),
                               ('SHELL', '七住所共用壳体', 'residence_shell')]:
        path = residence_dir + prefab + '.tscn'
        asset('scenes', 'SEA-SCENE-RESIDENCE-' + key, name, AUTHOR,
              [path] + materials, ['SEA-RESIDENCE', 'SEA-RESIDENT'], 'building_assembly',
              runtime_path=path, prefab=path, reused_asset_ids=kit_ids)
    for residence in residences:
        rid = residence['id']
        path = residence_dir + rid + '.tscn'
        asset('scenes', 'SEA-SCENE-' + rid.replace('_', '-').upper(), residence['label'], AUTHOR,
              [path, residence_dir + 'residence_shell.tscn'] + materials,
              ['SEA-RESIDENCE', 'SEA-RESIDENT'], 'building_residence',
              runtime_path=path, prefab=path,
              content_selector={'path': 'godot/assets/data/npc/residences.json',
                                'collection': 'residences', 'id': rid},
              reused_asset_ids=['SEA-SCENE-RESIDENCE-SHELL'] + kit_ids)
    for path in materials:
        key = Path(path).stem
        asset('scenes', 'SEA-SCENE-RESIDENCE-MATERIAL-' + key.upper(), '住所共用材质 · ' + key,
              path, [AUTHOR], ['SEA-RESIDENCE'], 'shared_material')

    crops = read('godot/assets/data/crops.json')['crops']
    assert [c['id'] for c in crops] == ['lettuce', 'tomato', 'pumpkin', 'flower_blue', 'flower_sun', 'flower_coral']
    for crop in crops[3:]:
        path = 'godot/' + crop['model'].removeprefix('res://')
        asset('crops', 'SEA-CROP-' + crop['id'].replace('_', '-').upper(), crop['name'] + ' · 四阶段',
              FLOWER, [path], ['SEA-CROP', 'SEA-FARM', 'SEA-RESIDENT', 'SEA-SHOP'],
              'procedural_crop_stage_set', runtime_path=FLOWER, prefab=path,
              stage_nodes=['Stage0Seed', 'Stage1Sprout', 'Stage2Leaf', 'Stage3Harvest'],
              content_selector={'path': 'godot/assets/data/crops.json', 'collection': 'crops', 'id': crop['id']})

    ids = [r['asset_id'] for r in rows]
    assert len(ids) == len(set(ids))
    new_ids = []
    for row, (path, manifest) in zip(rows, manifests):
        route = index['domains'][row['domain']]
        existing = prior_rows.get(row['asset_id'])
        if existing:
            assert existing == row, '已登记本轮资产发生变化，需重新审阅：' + row['asset_id']
            assert read(path) == manifest, '既有 manifest 变化，禁止覆盖：' + path
        else:
            assert not (ROOT / path).exists(), '未知同名 manifest，禁止覆盖：' + path
            books[row['domain']][route['asset_key']].append(row)
            new_ids.append(row['asset_id'])
            emit(path, manifest)
    for domain in ['characters', 'crops', 'scenes']:
        route = index['domains'][domain]
        emit(route['ledger'], books[domain])
    # 严格投影既存字段，不读取其他源来重算哈希。
    sources = read(PREFIX + 'current_source_index.json')
    sources['sources'] = [{k: a[k] for k in ['asset_id', 'source', 'source_sha256', 'manifest']}
                          for d, route in index['domains'].items()
                          for a in books[d][route['asset_key']]]
    emit(PREFIX + 'current_source_index.json', sources)
    route = index['domains']['scenes']
    for name, view in rules.building_views(books['scenes'][route['asset_key']], route['ledger']).items():
        read(route['building_views'][name])
        emit(route['building_views'][name], view)

    content = read(index['content_index'])
    tables = [
        ('SEA-INVENTORY', 'godot/assets/data/items.json', 'items'),
        ('SEA-CROP', 'godot/assets/data/crops.json', 'crops'),
        ('SEA-RESIDENT', 'godot/assets/data/npc/npcs.json', 'npcs'),
        ('SEA-RESIDENT', 'godot/assets/data/npc/events.json', 'events'),
        ('SEA-RESIDENT', 'godot/assets/data/npc/requests.json', 'requests'),
        ('SEA-RESIDENT', 'godot/assets/data/npc/dialogues.json', 'dialogues'),
        ('SEA-RESIDENCE', 'godot/assets/data/npc/residences.json', 'residences'),
        ('SEA-SHOP', 'godot/assets/data/shop/shops.json', 'shops'),
    ]
    content_summary = {}
    for owner, path, key in tables:
        values = read(path)[key]
        matches = [t for t in content['tables'] if t['path'] == path]
        assert len(matches) <= 1
        table = matches[0] if matches else dict(owner=owner, path=path, collection_key=key)
        table.update(owner=owner, collection_key=key, ids=[str(v['id']) for v in values if 'id' in v])
        assert len(table['ids']) == len(set(table['ids']))
        if key == 'dialogues':
            npc_ids = [v['npc_id'] for v in values]
            assert len(npc_ids) == len(set(npc_ids)) == 7
            table.update(primary_key='npc_id', primary_ids=npc_ids,
                         id_validation_status='pending_checker_only_supports_id',
                         note='实际主键为 npc_id；ids=[] 是现门禁对 id 的空投影，不代表无对白。primary_ids保存真实七人键；需主线程扩展检查器主键能力或另行登记有id的collection，本轮不改规则数据或检查器。')
        if not matches: content['tables'].append(table)
        content_summary[path] = {'ids': table['ids']}
        if key == 'dialogues': content_summary[path]['primary_ids'] = table['primary_ids']
    emit(index['content_index'], content)

    inventory = read(index['runtime_inventory'])
    prior_inventory = {r['path']: r.copy() for r in inventory['resources']}
    owned = [f'godot/src/npc/{name}.gd' for name in [
        'npc_actor', 'npc_accessories', 'npc_catalog', 'npc_dialogue_runner', 'npc_interactable',
        'npc_relationship_graph', 'npc_save_codec', 'npc_schedule_resolver', 'npc_service',
        'npc_world_presenter', 'npc_session', 'npc_panel', 'npc_world_ports', 'npc_career_panel']]
    owned += [f'godot/src/shop/{name}.gd' for name in ['shop_catalog', 'shop_panel', 'shop_service']]
    owned += ['godot/src/residence/resident_harbor.gd', FLOWER]
    owned += [p for _, p, _ in tables if p not in REVIEWED]
    owned += [r['prefab'] for r in rows if 'prefab' in r] + materials
    # 只登记与上述已知本轮脚本对应的 UID；不扫描整个运行树。
    owned += [p + '.uid' for p in list(owned) if p.endswith('.gd') and (ROOT / (p + '.uid')).is_file()]
    runtime_assets = {}
    for row in rows:
        runtime_assets.setdefault(row['runtime_path'], []).append(row['asset_id'])
        if 'prefab' in row: runtime_assets.setdefault(row['prefab'], []).append(row['asset_id'])
    changed_runtime = []
    for path in sorted(set(owned) | REVIEWED):
        assert (ROOT / path).is_file(), path
        sha = digest(path)
        old = prior_inventory.get(path)
        if old and old['sha256'] != sha and path not in REVIEWED:
            raise AssertionError('已登记新增文件发生漂移，需重新审阅：' + path)
        row = next((r for r in inventory['resources'] if r['path'] == path), None)
        if row is None:
            row = {'path': path, 'asset_id': None}
            inventory['resources'].append(row)
        if old and old['sha256'] != sha: row['previous_sha256'] = old['sha256']
        row.update(sha256=sha, bytes=(ROOT / path).stat().st_size,
                   status='registered_npc_round_runtime_verification_pending',
                   note='2026-11-07 本轮定点登记；不代表运行／美术验收。' +
                        ('已审阅本轮库存／作物差异。' if path in REVIEWED else '本轮新增文件。'))
        if path in runtime_assets:
            row['asset_id'] = runtime_assets[path][0]
            row['asset_ids'] = runtime_assets[path]
        if row != old: changed_runtime.append(path)
    emit(index['runtime_inventory'], inventory)

    for d, route in index['domains'].items():
        for row in books[d][route['asset_key']]:
            if row['asset_id'] in prior_rows:
                assert row == prior_rows[row['asset_id']], '非新增行被改变'
    for row in inventory['resources']:
        if row['path'] not in set(owned) | REVIEWED:
            assert row == prior_inventory[row['path']], '非白名单运行记录被改变'
    all_rows = [a for d, route in index['domains'].items() for a in books[d][route['asset_key']]]
    source_ids = [a['source_id'] for a in all_rows if a.get('source_id')]
    assert len(source_ids) == len(set(source_ids)), 'SourceID 重复'
    assert len(all_rows) == len({a['asset_id'] for a in all_rows}), 'AssetID 重复'
    summary = dict(before_counts=before,
                   after_counts={d: len(books[d][r['asset_key']]) for d, r in index['domains'].items()},
                   new_asset_ids=new_ids, round_asset_ids=ids,
                   round_domain_counts=dict(Counter(r['domain'] for r in rows)),
                   runtime_updated_paths=changed_runtime, runtime_count=len(inventory['resources']),
                   pending_unchanged_hashes=PENDING, content_tables=content_summary,
                   ownership='只写 registry；不写 appearance agent 的 art_source JSON；不写 GDD 或其他功能文档',
                   source_id_policy='每条新资产唯一 SRC-AssetID；可共用真实程序 source 路径，不复制外观主表')
    # 乐观并发保护：所有读过的登记文件与实际签名输入必须仍是最新快照。
    for path, raw in snapshots.items():
        current = (ROOT / path).read_bytes() if (ROOT / path).exists() else None
        assert current == raw, '并发修改，停止写入：' + path
    for path, sha in source_hashes.items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == sha, '签名前源发生变化：' + path
    if write:
        for path, payload in outputs.items():
            target = ROOT / path
            assert target.parent.is_dir(), path
            current = target.read_bytes() if target.exists() else None
            assert current == snapshots[path], '写入前出现并发修改：' + path
            if current != payload: target.write_bytes(payload)
    print(json.dumps({'mode': 'write' if write else 'dry_run', **summary}, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    raise SystemExit(main(parser.parse_args().write))

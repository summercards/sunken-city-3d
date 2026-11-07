"""本轮修复定点重签：默认预检；只写已审阅的登记字段，不晋升验收阶段。"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUTHOR = 'godot/src/residence/author_scenes.py'
HARBOR = 'godot/scenes/residence/resident_harbor.tscn'
OLD_AUTHOR = '4c48fc06c27cd674a82cf252e67d77b6ee352e6876da74cb9f1b31f0b821d284'
OLD_HARBOR = 'e06608d32e379e96355af81bc15330f7193b9ffdc25839240d5aac31f472c1b7'
# 下列指纹冻结于本次逐文件审阅；变化时停止，不自动签新版本。
REVIEWED = {
    AUTHOR: '782b5ab3d0fc27a47c7386d07da35a3cb0bf305b87ae5fd22a9ac7b6867c041c',
    HARBOR: 'c49bb6c063d3d8aecc638164cce2fb58ffe62ef24ef42ba52d6e1d9c02a249ad',
    'godot/src/core/play_scope.gd': 'b7abac1bee2df0663ea50a28f8246e9c1ca28608b4b38adb3edc71a21bd195fc',
    'godot/src/shop/shop_panel.gd': '998c042ec0022d23b59e9056a0b0d0110ce35d368c4467211894eed13981e3f2',
    'godot/src/ui/hud.gd': 'dc2394d2fcf711524153ae919e4fa01efa4fa007a8f21bd31e68757c30185753',
    'godot/src/ui/pocket_service.gd': '9dcf93ba38d43f6d1cd747bdc008a4857065d5f3961ad1296f2bb4ef56532218',
}
RUNTIME_PATHS = set(REVIEWED) - {AUTHOR}
REVIEW_NOTE = '2026-11-07 本轮修复定点重签：住所泊位main、职业商店输入去重、HUD商店委托与住所范围；运行/视觉仍pending，等待主线程最终合批。'


def digest(data):
    return hashlib.sha256(data.replace(b'\r\n', b'\n')).hexdigest()


def main(write=False):
    snapshots, outputs = {}, {}

    def read(path):
        raw = (ROOT / path).read_bytes()
        snapshots[path] = raw
        return json.loads(raw)

    def emit(path, value):
        assert path.startswith('assets/registry/')
        assert path in snapshots
        outputs[path] = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')

    def resign(row, key, new):
        old = row[key]
        if old == new: return False
        previous_key = 'previous_' + key
        if previous_key in row:
            row.setdefault('hash_history', []).append({key: old, previous_key: row[previous_key],
                                                       'review': REVIEW_NOTE})
        row[previous_key] = old
        row[key] = new
        return True

    for path, expected in REVIEWED.items():
        raw = (ROOT / path).read_bytes()
        snapshots[path] = raw
        assert digest(raw) == expected, '审阅后文件变化，禁止重签：' + path
    old_landing = b'landing_id = "resident_harbor_main"'
    new_landing = b'landing_id = "main"'
    for path, old in [(AUTHOR, OLD_AUTHOR), (HARBOR, OLD_HARBOR)]:
        raw = snapshots[path]
        assert raw.count(new_landing) == 1
        assert digest(raw.replace(new_landing, old_landing)) == old, '并非已确认的单行修改：' + path

    index = read('assets/registry/ledger_index.json')
    books = {d: read(route['ledger']) for d, route in index['domains'].items()}
    original_books = deepcopy(books)
    source_changes, manifest_changes = [], []
    own_rows = [a for d, route in index['domains'].items() for a in books[d][route['asset_key']]
                if a.get('source_id', '').startswith('SRC-SEA-SCENE-RESIDENCE-')]
    assert len(own_rows) == 12
    for asset in own_rows:
        if asset['source'] == AUTHOR:
            assert asset['source_sha256'] in {OLD_AUTHOR, REVIEWED[AUTHOR]}
            if resign(asset, 'source_sha256', REVIEWED[AUTHOR]): source_changes.append(asset['asset_id'])
        manifest = read(asset['manifest'])
        before_manifest = deepcopy(manifest)
        assert manifest['asset_ledger'] == index['domains']['scenes']['ledger'] + '#' + asset['asset_id']
        if manifest['source'] == AUTHOR:
            resign(manifest, 'source_sha256', REVIEWED[AUTHOR])
        for entry in manifest['authored_files']:
            path = entry['path']
            if path in {AUTHOR, HARBOR}:
                resign(entry, 'sha256', REVIEWED[path])
        if manifest != before_manifest:
            emit(asset['manifest'], manifest)
            manifest_changes.append(asset['asset_id'])
    assert len(source_changes) in {0, 9}
    if source_changes: emit(index['domains']['scenes']['ledger'], books['scenes'])
    for d, route in index['domains'].items():
        for old, current in zip(original_books[d][route['asset_key']], books[d][route['asset_key']]):
            if old['asset_id'] in source_changes:
                assert {k: v for k, v in old.items() if k != 'source_sha256'} == {
                    k: v for k, v in current.items() if k not in {'source_sha256', 'previous_source_sha256'}}, '越界变更资产字段'
            else: assert current == old, '非本轮源记录变化'

    source_index = read('assets/registry/current_source_index.json')
    source_index['sources'] = [{k: a[k] for k in ['asset_id', 'source', 'source_sha256', 'manifest']}
                               for d, route in index['domains'].items()
                               for a in books[d][route['asset_key']]]
    emit('assets/registry/current_source_index.json', source_index)

    inventory = read(index['runtime_inventory'])
    old_inventory = deepcopy(inventory)
    runtime_changes, runtime_added = [], []
    for path in sorted(RUNTIME_PATHS):
        matches = [r for r in inventory['resources'] if r['path'] == path]
        assert len(matches) <= 1
        if matches:
            row = matches[0]
            if not resign(row, 'sha256', REVIEWED[path]): continue
            runtime_changes.append(path)
        else:
            assert path == 'godot/src/ui/pocket_service.gd', '仅可补登已审阅的pocket委托'
            row = {'path': path, 'asset_id': None, 'sha256': REVIEWED[path]}
            inventory['resources'].append(row)
            runtime_added.append(path)
        row.update(bytes=len(snapshots[path]), status='registered_npc_round_runtime_verification_pending')
        row['note'] = row.get('note', '') + (' ' if row.get('note') else '') + REVIEW_NOTE
    for row in old_inventory['resources']:
        if row['path'] not in RUNTIME_PATHS:
            assert row == next(x for x in inventory['resources'] if x['path'] == row['path'])
    emit(index['runtime_inventory'], inventory)

    content = read(index['content_index'])
    old_content = deepcopy(content)
    table_changes = []
    for table in content['tables']:
        if table['path'] not in {'godot/assets/data/npc/dialogues.json', 'godot/assets/data/zones.json'}: continue
        old_table = deepcopy(table)
        data = read(table['path'])
        values = data[table['collection_key']] if table['collection_key'] else data
        if table['path'].endswith('/dialogues.json'):
            table['primary_key'] = 'npc_id'
            table['ids'] = [str(x['npc_id']) for x in values]
            table['note'] = '七名NPC对白，以npc_id为真实主键；不复制规则数据。'
            table.pop('primary_ids', None)
            table.pop('id_validation_status', None)
            assert len(table['ids']) == 7
        else:
            table['ids'] = [str(x['id']) for x in values]
        assert len(table['ids']) == len(set(table['ids']))
        if table != old_table: table_changes.append(table['path'])
    for old, current in zip(old_content['tables'], content['tables']):
        if old['path'] not in table_changes: assert old == current
    emit(index['content_index'], content)
    for path, raw in snapshots.items():
        assert (ROOT / path).read_bytes() == raw, '并发修改，停止写入：' + path
    if write:
        for path, payload in outputs.items():
            assert (ROOT / path).read_bytes() == snapshots[path], '写前并发修改：' + path
            if payload != snapshots[path]: (ROOT / path).write_bytes(payload)
    print(json.dumps(dict(mode='write' if write else 'dry_run', source_assets_resigned=source_changes,
                         manifests_updated=manifest_changes, runtime_resigned=runtime_changes,
                         runtime_added=runtime_added, content_tables_updated=table_changes,
                         asset_count=sum(len(books[d][v['asset_key']]) for d, v in index['domains'].items()),
                         runtime_count=len(inventory['resources']),
                         stage_policy='不晋升任何资产runtime/visual阶段',
                         excluded_hashes='Main/save/water/world/zones及其他并行记录原样保留'), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    main(parser.parse_args().write)

"""Register reviewed avatar revisions only; reject unreviewed source hash drift."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DELIVERY = 'docs/development/2026-11-03_avatar_customization.md'


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def write(path, value):
    (ROOT / path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def digest_bytes(data, path):
    if Path(path).suffix in ['.gd', '.gdshader', '.json', '.md', '.py']:
        data = data.replace(b'\r\n', b'\n')
    return hashlib.sha256(data).hexdigest()


def digest(path):
    return digest_bytes((ROOT / path).read_bytes(), path)


def guard(path, previous):
    if previous == digest(path):
        return
    baseline = subprocess.check_output(['git', 'show', 'HEAD:' + path], cwd=ROOT)
    if previous not in {digest_bytes(baseline, path), digest(path)}:
        raise SystemExit('Unreviewed recorded source drift: ' + path)


index = read('assets/registry/ledger_index.json')
revisions = {
    'SEA-CHAR-AVATAR-001': ('characters', 'v003', ['godot/src/avatar/avatar_visual.gd', 'godot/src/player/character.gd', 'godot/assets/data/avatar_catalog.json', 'godot/src/avatar/avatar_catalog.gd', 'godot/src/avatar/avatar_profile.gd', 'art_source/characters/avatar/v003/customization_contract.json']),
    'SEA-CHAR-RIG-001': ('characters', 'v002', ['godot/src/avatar/avatar_limb_skinning.gd', 'godot/src/player/character.gd']),
    'SEA-CHAR-RECEIVE-001': ('characters', 'v004', ['godot/src/player/animation/item_receive.gd']),
    'SEA-UI-AVATAR-001': ('ui', 'v002', ['godot/src/avatar/avatar_editor.gd', 'godot/src/avatar/avatar_session.gd', 'godot/src/onboarding/arrival_camera.gd']),
}
new = {
    'SEA-CHAR-FACE-001': ('曲面五官与透明脸颊贴图', 'godot/src/avatar/avatar_face.gd', [
        'godot/src/avatar/avatar_face.gd', 'godot/assets/textures/avatar/blush_soft.png',
        'godot/assets/textures/avatar/freckles.png', 'godot/assets/textures/avatar/stubble.png',
        'tools/author_avatar_face_textures.py']),
    'SEA-CHAR-HAIR-001': ('模块化发型与参数DIY', 'godot/src/avatar/avatar_hair.gd', ['godot/src/avatar/avatar_hair.gd']),
    'SEA-CHAR-SHAPE-001': ('旅人有界形体适配', 'godot/src/avatar/avatar_morphology.gd', ['godot/src/avatar/avatar_morphology.gd']),
}
books = {}
for aid, (domain, version, paths) in revisions.items():
    route = index['domains'][domain]
    book = books.setdefault(domain, read(route['ledger']))
    row = next(r for r in book[route['asset_key']] if r['asset_id'] == aid)
    guard(row['source'], row['source_sha256'])
    if row['source_sha256'] != digest(row['source']):
        row['previous_source_sha256'] = row['source_sha256']
    row.update(source_sha256=digest(row['source']), version=version, verification=DELIVERY,
               note='2026-11-03 有界形体、贴图五官、发型DIY与界面深度验收；保存兼容原v1档案。详见本轮交付。')
    manifest = read(row['manifest'])
    manifest.update(version=version, verification=DELIVERY)
    for path in paths:
        entry = next((r for r in manifest['authored_files'] if r['path'] == path), None)
        if entry is None:
            manifest['authored_files'].append(dict(path=path, sha256=digest(path)))
        else:
            guard(path, entry['sha256'])
            entry['sha256'] = digest(path)
    write(row['manifest'], manifest)

route = index['domains']['characters']
book = books['characters']
for aid, (name, source, paths) in new.items():
    manifest_path = 'assets/registry/manifests/' + aid.lower() + '.json'
    existing = next((r for r in book[route['asset_key']] if r['asset_id'] == aid), None)
    if existing is not None and existing['source'] != source:
        raise SystemExit('Duplicate AssetID: ' + aid)
    if existing is not None and existing['source_sha256'] != digest(source):
        raise SystemExit('Existing new asset changed; review its revision explicitly: ' + aid)
    row = dict(asset_id=aid, name=name, domain='characters', stage='runtime_component_verified',
               source=source, source_sha256=digest(source), manifest=manifest_path, version='v001', runtime_path=source,
               license='project_authored_procedural_mesh_and_texture', consumer_features=['SEA-AVATAR'], verification=DELIVERY,
               note='独立可维护的Godot程序源/自制透明遮罩；未使用外部游戏资产，未声称Blender或GLB产物。')
    if existing is None:
        book[route['asset_key']].append(row)
    else:
        existing.update(row)
    write(manifest_path, dict(asset_id=aid, asset_ledger=route['ledger'] + '#' + aid, version='v001', source=source, runtime_path=source,
          authored_files=[dict(path=p, sha256=digest(p)) for p in paths], verification=DELIVERY,
          source_type='original Godot procedural source and deterministic Pillow-authored PNG masks; no Blender/GLB',
          units='metres / +Y up / +Z forward / root scale 1', external_game_assets_used=False,
          self_verification='actual mesh and skinned vertices, mixed extremes, dense action samples, real renderer and real UI input'))
for domain, book in books.items():
    write(index['domains'][domain]['ledger'], book)

# Projection copies recorded hashes, never refreshes another domain's source.
projection = read('assets/registry/current_source_index.json')
projection['sources'] = [
    {k: row[k] for k in ['asset_id', 'source', 'source_sha256', 'manifest']}
    for route in index['domains'].values() for row in read(route['ledger'])[route['asset_key']]
]
write('assets/registry/current_source_index.json', projection)
inventory = read(index['runtime_inventory'])
changed_paths = {p for _, _, paths in revisions.values() for p in paths}
changed_paths.add('godot/src/bootstrap/main.gd')
for resource in inventory['resources']:
    path = resource['path']
    if path not in changed_paths:
        continue
    guard(path, resource['sha256'])
    if resource['sha256'] != digest(path):
        resource['previous_sha256'] = resource['sha256']
    resource.update(sha256=digest(path), bytes=(ROOT / path).stat().st_size)
    marker = '2026-11-03 SEA-AVATAR-R15–R19'
    if marker not in resource.get('note', ''):
        resource['note'] = resource.get('note', '') + ' ' + marker + '：本轮角色定制扩充，原HEAD与登记基线精确匹配后定点更新，详见当前交付。'
for aid, (_, source, paths) in new.items():
    for path in paths:
        if not path.startswith('godot/'):
            continue
        existing = next((r for r in inventory['resources'] if r['path'] == path), None)
        row = dict(path=path, bytes=(ROOT / path).stat().st_size, sha256=digest(path), asset_id=aid, status='runtime_component_verified')
        if existing is None:
            inventory['resources'].append(row)
        else:
            existing.update(row)
write(index['runtime_inventory'], inventory)
content = read(index['content_index'])
for table in content['tables']:
    if table['path'] == 'godot/assets/data/avatar_catalog.json':
        table['ids'] = [slot['id'] for slot in read(table['path'])['slots']]
write(index['content_index'], content)
print('Registered reviewed avatar sources, face masks, hair, morphology and UI only.')

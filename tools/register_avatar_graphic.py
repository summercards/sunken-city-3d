"""Register only the reviewed r5 avatar revisions against the captured r4 source."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT.parent / 'sea-work/avatar-graphic-baseline-20261103'
REVIEWED_RECEIVE = ROOT.parent / 'sea-work/verification/20261103-100021-avatar-graphic-delivery-visual-d770cb/project/src/player/animation/item_receive.gd'
DELIVERY = 'docs/development/2026-11-03_avatar_graphic_revision.md'


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def write(path, value):
    (ROOT / path).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def digest_at(path):
    value = Path(path).read_bytes()
    if Path(path).suffix in ['.gd','.gdshader','.json','.py','.md']:
        value = value.replace(b'\r\n', b'\n')
    return hashlib.sha256(value).hexdigest()


def digest(path):
    return digest_at(ROOT / path)


def guard(path, previous):
    known = {digest(path)}
    if (BASELINE / path).exists():
        known.add(digest_at(BASELINE / path))
    if path=='godot/src/player/animation/item_receive.gd' and REVIEWED_RECEIVE.exists():
        # Final review changed only the left release-front clearance to retain
        # the same large-head margin as the overhead hold. No other drift.
        known.add(digest_at(REVIEWED_RECEIVE))
    if previous not in known:
        raise SystemExit('Unreviewed r4 source drift: '+path)


index = read('assets/registry/ledger_index.json')
revisions = {
    'SEA-CHAR-AVATAR-001': ('characters','v004',['godot/src/avatar/avatar_visual.gd','godot/src/player/character.gd','godot/assets/data/avatar_catalog.json']),
    'SEA-CHAR-RIG-001': ('characters','v003',['godot/src/avatar/avatar_limb_skinning.gd','godot/src/player/character.gd']),
    'SEA-CHAR-RECEIVE-001': ('characters','v005',['godot/src/player/animation/item_receive.gd','godot/src/player/animation/idle_action.gd']),
    'SEA-CHAR-FACE-001': ('characters','v002',['godot/src/avatar/avatar_face.gd','godot/assets/textures/avatar/graphic_eyes.png','godot/shaders/avatar_eye.gdshader','art_source/characters/avatar/v004/graphic_eye_source.png','art_source/characters/avatar/v004/graphic_eye_manifest.json','tools/prepare_avatar_graphic_atlas.py']),
    'SEA-CHAR-SHAPE-001': ('characters','v002',['godot/src/avatar/avatar_morphology.gd']),
    'SEA-UI-AVATAR-001': ('ui','v003',['godot/src/avatar/avatar_editor.gd','godot/src/avatar/avatar_session.gd']),
}
books = {domain:read(index['domains'][domain]['ledger']) for domain in ['characters','ui']}
updates = []
# Preflight all recorded predecessors before mutating any registry file.
for aid, (domain, version, paths) in revisions.items():
    row = next(r for r in books[domain]['assets'] if r['asset_id']==aid)
    guard(row['source'],row['source_sha256'])
    manifest = read(row['manifest'])
    for entry in manifest['authored_files']:
        if entry['path'] in paths:
            guard(entry['path'],entry['sha256'])
    updates.append((aid,row,manifest,version,paths))
inventory = read(index['runtime_inventory'])
paths = {p for _,_,items in revisions.values() for p in items}
for row in inventory['resources']:
    if row['path'] in paths:
        guard(row['path'],row['sha256'])

for aid,row,manifest,version,paths in updates:
    if row['source_sha256']!=digest(row['source']):
        row['previous_source_sha256']=row['source_sha256']
    row.update(source_sha256=digest(row['source']),version=version,verification=DELIVERY,
               note='r5 用户指定粗线条图形五官、独立表情动画；直上臂和肩袖/腰胯腿连贯，真实网格/动作/渲染专项，详见当前交付。')
    manifest.update(version=version,verification=DELIVERY)
    for path in paths:
        entry=next((e for e in manifest['authored_files'] if e['path']==path),None)
        if entry is None:
            manifest['authored_files'].append(dict(path=path,sha256=digest(path)))
        else:
            entry['sha256']=digest(path)
    if aid=='SEA-CHAR-FACE-001':
        manifest['source_type']='original generated eye artwork + transparent atlas extraction + Godot curved facial mesh/shader; no copied reference pixels'
        manifest['texture_source']='art_source/characters/avatar/v004/graphic_eye_source.png'
    if aid=='SEA-CHAR-AVATAR-001':
        manifest['expression_asset_id']='SEA-CHAR-EXPRESSION-001'
    write(row['manifest'],manifest)

aid='SEA-CHAR-EXPRESSION-001'; source='godot/src/avatar/avatar_expression.gd'
manifest='assets/registry/manifests/sea-char-expression-001.json'
row=dict(asset_id=aid,name='旅人图形表情与自然眨眼',domain='characters',stage='runtime_component_verified',
         source=source,source_sha256=digest(source),manifest=manifest,version='v001',runtime_path=source,
         license='project_authored_animation_adapter_and_generated_graphic_texture',consumer_features=['SEA-AVATAR','SEA-MOVE'],verification=DELIVERY,
         note='独立瞬时表现：6情绪、眨眼、视线与动作映射；不写存档。')
existing=next((r for r in books['characters']['assets'] if r['asset_id']==aid),None)
if existing is not None and (existing['source']!=source or existing['source_sha256']!=digest(source)):
    raise SystemExit('Duplicate or unreviewed expression asset ID')
if existing is None:
    books['characters']['assets'].append(row)
else:
    existing.update(row)
write(manifest,dict(asset_id=aid,asset_ledger=index['domains']['characters']['ledger']+'#'+aid,version='v001',source=source,runtime_path=source,
      authored_files=[dict(path=p,sha256=digest(p)) for p in [source,'godot/shaders/avatar_eye.gdshader']],verification=DELIVERY,
      ownership='transient visual intent only; no profile/save/gameplay writes'))
for domain,book in books.items():
    write(index['domains'][domain]['ledger'],book)

owners={p:aid for aid,(_,_,ps) in revisions.items() for p in ps if p.startswith('godot/')}
owners[source]=aid
for path,owner in owners.items():
    entry=next((r for r in inventory['resources'] if r['path']==path),None)
    if entry is None:
        inventory['resources'].append(dict(path=path,bytes=(ROOT/path).stat().st_size,sha256=digest(path),asset_id=owner,status='runtime_component_verified'))
    else:
        if entry['sha256']!=digest(path): entry['previous_sha256']=entry['sha256']
        entry.update(bytes=(ROOT/path).stat().st_size,sha256=digest(path))
        marker='2026-11-03 SEA-AVATAR-R20/R21'
        if marker not in entry.get('note',''): entry['note']=entry.get('note','')+' '+marker+'：已审阅图形表情和连续衔接修订，当前证据见开发记录。'
write(index['runtime_inventory'],inventory)
projection=read('assets/registry/current_source_index.json')
projection['sources']=[{k:r[k] for k in ['asset_id','source','source_sha256','manifest']} for route in index['domains'].values() for r in read(route['ledger'])[route['asset_key']]]
write('assets/registry/current_source_index.json',projection)
print('Registered reviewed r5 avatar revisions and expression asset; other sources untouched.')

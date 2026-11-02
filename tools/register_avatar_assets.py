"""Register only this feature's original procedural sources; never refresh unrelated hashes."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))

def write(path, value):
    (ROOT / path).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def digest(path):
    data=(ROOT/path).read_bytes()
    if Path(path).suffix in ['.gd','.gdshader','.json','.md']: data=data.replace(b'\r\n',b'\n')
    return hashlib.sha256(data).hexdigest()

index = read('assets/registry/ledger_index.json')
delivery = 'docs/development/2026-11-02_avatar_and_arrival.md'
for domain, aid, name, source, related in [
    ('characters','SEA-CHAR-AVATAR-001','原创模块化海上旅人','godot/src/avatar/avatar_visual.gd',
     ['godot/src/player/character.gd','godot/assets/data/avatar_catalog.json','godot/shaders/avatar_cloth.gdshader','godot/src/avatar/avatar_dimensions.gd',
      'art_source/characters/avatar/v001/reference_proportions.png','art_source/characters/avatar/v001/reference_contract.json']),
    ('ui','SEA-UI-AVATAR-001','旅人创建与外观编辑界面','godot/src/avatar/avatar_editor.gd',
     ['godot/src/avatar/avatar_session.gd','godot/src/onboarding/arrival_camera.gd']),
]:
    route=index['domains'][domain]
    book=read(route['ledger'])
    manifest='assets/registry/manifests/'+aid.lower()+'.json'
    row=dict(asset_id=aid,name=name,domain=domain,stage='runtime_component_verified',
             source=source,source_sha256=digest(source),manifest=manifest,version='v001',
             runtime_path=source,license='project_authored_original_procedural_geometry_and_UI',
             consumer_features=['SEA-AVATAR','SEA-ONBOARDING'],verification=delivery,
             note='原创程序源；用户提供游戏截图仅作比例参考，不进入运行或导出包，参考图商业授权未主张。按六项网格投影比例逐项5%阈值自验。字体与场景资产沿用各自登记。')
    rows=book[route['asset_key']]
    matches=[i for i,r in enumerate(rows) if r['asset_id']==aid]
    if matches: rows[matches[0]]=row
    else: rows.append(row)
    write(route['ledger'],book)
    write(manifest,dict(asset_id=aid,asset_ledger=route['ledger']+'#'+aid,
         source=source,runtime_path=source,version='v001',source_type='original procedural Godot source; no Blender/GLB',
         authored_files=[dict(path=p,sha256=digest(p)) for p in [source]+related],
         units='metres / +Y up / +Z forward / root scale 1' if domain=='characters' else '1600x1000 responsive logical canvas',
         consumer='Character + AvatarSession',verification=delivery,
         user_art_acceptance='self_verified_per_user_instruction_2026-11-02',
         self_verification='six projected anatomy ratios within 5%; original reference, three-quarter/front/side and gameplay/editor renders inspected',
         external_game_assets_used=False))

# Deliberate wrist-chain retargeting for the new reference proportions. The
# duration, action ID and reward boundary remain the existing 2.4s contract.
route=index['domains']['characters']; book=read(route['ledger'])
for row in book[route['asset_key']]:
    if row['asset_id']!='SEA-CHAR-RECEIVE-001': continue
    row['previous_source_sha256']='8b08f26c14d3f080855a78a5e2ff1ee6e040194ba71cdc2848a9d0467493455b'
    row['source_sha256']=digest(row['source']); row['version']='v002'
    row['note']='原2.4秒获物动作适配用户参考的窄肩、手臂长度和缩小挎包；由AvatarDimensions共用静止尺寸，保留动作ID/时长/头顶1.60m展示和奖励边界；本轮动作专项重验。'
    manifest=read(row['manifest']); manifest['version']='v002'
    for entry in manifest['authored_files']:
        if entry['path']==row['source']: entry['sha256']=digest(row['source'])
    dimension='godot/src/avatar/avatar_dimensions.gd'
    manifest['authored_files']=[e for e in manifest['authored_files'] if e['path']!=dimension]+[dict(path=dimension,sha256=digest(dimension))]
    manifest['verification']=delivery
    write(row['manifest'],manifest)
write(route['ledger'],book)

# Exact projection, without changing any other asset's stored hash.
sources=[]
for route in index['domains'].values():
    for row in read(route['ledger'])[route['asset_key']]:
        sources.append({k:row[k] for k in ['asset_id','source','source_sha256','manifest']})
projection=read('assets/registry/current_source_index.json'); projection['sources']=sources
write('assets/registry/current_source_index.json',projection)

catalog='godot/assets/data/avatar_catalog.json'
inventory=read(index['runtime_inventory'])
item=dict(path=catalog,bytes=(ROOT/catalog).stat().st_size,sha256=digest(catalog),
          asset_id='SEA-CHAR-AVATAR-001',status='runtime_component_verified')
inventory['resources']=[r for r in inventory['resources'] if r['path']!=catalog]+[item]
# Exact registered predecessor was found in this isolated project. Its diff
# contains only the avatar wiring reviewed in this delivery; no bulk refresh.
main_source='godot/src/bootstrap/main.gd'
for row in inventory['resources']:
    if row['path']==main_source:
        if row['sha256']!=digest(main_source):
            row['previous_sha256']=row['sha256']
            row['sha256']=digest(main_source); row['bytes']=(ROOT/main_source).stat().st_size
            row['note'] += ' 2026-11-02 SEA-AVATAR/SEA-ONBOARDING接线；与已登记原哈希精确匹配的173802隔离副本逐行核对，仅本次角色/开场改动；保存、重置与移动动作回归见交付。'
    if row['path']=='godot/src/player/animation/item_receive.gd' and row['sha256']!=digest(row['path']):
        row['previous_sha256']=row['sha256']
        row['sha256']=digest(row['path']); row['bytes']=(ROOT/row['path']).stat().st_size
        row['note']='SEA-CHAR-RECEIVE-001 v002；已审阅指定比例的肩肘/腕部长度和缩小挎包适配，80项动作及当前角色/界面回归通过，动作ID/2.4秒/奖励边界保持。'
write(index['runtime_inventory'],inventory)
content=read(index['content_index'])
table=dict(owner='SEA-AVATAR',path=catalog,collection_key='slots',
           ids=[s['id'] for s in read(catalog)['slots']],note='稳定槽位ID；各选项ID在槽位内唯一，扩展需保留既有ID。')
content['tables']=[r for r in content['tables'] if r['path']!=catalog]+[table]
write(index['content_index'],content)
print('Registered two original procedural assets and the avatar catalogue only.')

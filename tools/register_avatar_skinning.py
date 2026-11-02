"""Register only reviewed limb-skinning sources, without refreshing other domains."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT.parent / 'sea-work/avatar-skinning-baseline'
DELIVERY = 'docs/development/2026-11-02_avatar_limb_skinning.md'

def read(path):
    return json.loads((ROOT/path).read_text(encoding='utf-8'))

def write(path, value):
    (ROOT/path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def digest(path):
    data=Path(path).read_bytes()
    if Path(path).suffix in ['.gd','.gdshader','.json','.md']: data=data.replace(b'\r\n',b'\n')
    return hashlib.sha256(data).hexdigest()

index=read('assets/registry/ledger_index.json')
route=index['domains']['characters']
book=read(route['ledger'])
changed={
    'SEA-CHAR-AVATAR-001':['godot/src/avatar/avatar_visual.gd','godot/src/player/character.gd'],
    'SEA-CHAR-RECEIVE-001':['godot/src/player/animation/item_receive.gd'],
}
for row in book[route['asset_key']]:
    if row['asset_id'] not in changed: continue
    before=BASELINE/row['source']
    allowed={digest(before),digest(ROOT/row['source'])}
    if row['source_sha256'] not in allowed:
        raise SystemExit('Unreviewed source-ledger drift: '+row['asset_id'])
    if row['source_sha256']!=digest(ROOT/row['source']): row['previous_source_sha256']=row['source_sha256']
    row['source_sha256']=digest(ROOT/row['source'])
    row['version']='v002' if row['asset_id']=='SEA-CHAR-AVATAR-001' else 'v003'
    row['verification']=DELIVERY
    row['note']='四肢改为连续封闭网格和原生Skeleton3D/Skin；保留外观ID/碰撞/动作生命周期，旧节点仅作不可见姿势控制；实测详见本轮交付。'
    manifest=read(row['manifest']); manifest['version']=row['version']; manifest['verification']=DELIVERY
    for item in manifest['authored_files']:
        if item['path'] in changed[row['asset_id']]: item['sha256']=digest(ROOT/item['path'])
    manifest['skeleton_asset_id']='SEA-CHAR-RIG-001'
    manifest['rig_contract']='art_source/characters/avatar/v002/rig_contract.json'
    write(row['manifest'],manifest)

source='godot/src/avatar/avatar_limb_skinning.gd'
aid='SEA-CHAR-RIG-001'
manifest='assets/registry/manifests/sea-char-rig-001.json'
row=dict(asset_id=aid,name='旅人连续四肢蒙皮骨骼',domain='characters',stage='runtime_component_verified',
         source=source,source_sha256=digest(ROOT/source),manifest=manifest,version='v001',runtime_path=source,
         license='project_authored_procedural_skeleton_mesh_skin_and_shader',consumer_features=['SEA-AVATAR','SEA-MOVE'],
         verification=DELIVERY,note='21骨骼；四张各自封闭连通的手臂/腿网格；真实GPU蒙皮及原动作采样适配，4权重通道，肘膝0–120度专项与近景自行验收。')
rows=book[route['asset_key']]
found=next((i for i,r in enumerate(rows) if r['asset_id']==aid),None)
if found is None: rows.append(row)
else: rows[found]=row
write(route['ledger'],book)
paths=[source,'godot/shaders/avatar_limb.gdshader','godot/src/avatar/avatar_dimensions.gd','godot/src/player/character.gd','art_source/characters/avatar/v002/rig_contract.json','art_source/characters/avatar/v002/joint_request.png']
write(manifest,dict(asset_id=aid,asset_ledger=route['ledger']+'#'+aid,version='v001',source=source,runtime_path=source,
    authored_files=[dict(path=p,sha256=digest(ROOT/p)) for p in paths],source_type='project-authored Godot procedural Skeleton3D + indexed ArrayMesh + Skin; no Blender/GLB claimed',
    rig_contract='art_source/characters/avatar/v002/rig_contract.json',coordinate_system='+Y up, +Z forward, metres, root scale 1',
    animation_driver='registered action samples -> non-rendering pose controls -> Skeleton3D bone poses -> GPU skinning',
    verification=DELIVERY,self_verification='closed/connected/manifold, weights, bone-only GPU deformation, 0-120deg, pose/render/profile regressions'))

# Projection uses the existing recorded hashes, never recalculates other sources.
projection=read('assets/registry/current_source_index.json'); projection['sources']=[]
for entry in index['domains'].values():
    for asset in read(entry['ledger'])[entry['asset_key']]:
        projection['sources'].append({k:asset[k] for k in ['asset_id','source','source_sha256','manifest']})
write('assets/registry/current_source_index.json',projection)
inventory=read(index['runtime_inventory'])
for item in inventory['resources']:
    if item['path']=='godot/src/player/animation/item_receive.gd':
        before=BASELINE/item['path']
        if item['sha256'] not in {digest(before),digest(ROOT/item['path'])}: raise SystemExit('Unreviewed runtime drift: '+item['path'])
        if item['sha256']!=digest(ROOT/item['path']): item['previous_sha256']=item['sha256']
        item['sha256']=digest(ROOT/item['path']); item['bytes']=(ROOT/item['path']).stat().st_size
        item['note']='v003 骨骼连续四肢适配：姿势控制仅改节点/骨骼长度，不再写分段网格；举物绕开头部，2.4秒/奖励边界及双腕支持实测。'
for path in [source,'godot/shaders/avatar_limb.gdshader']:
    inventory['resources']=[r for r in inventory['resources'] if r['path']!=path]
    inventory['resources'].append(dict(path=path,bytes=(ROOT/path).stat().st_size,sha256=digest(ROOT/path),asset_id=aid,status='runtime_component_verified'))
write(index['runtime_inventory'],inventory)
print('Registered only avatar/receive revisions, the new limb rig and its shader.')

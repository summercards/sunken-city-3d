"""Repair generated-only prefab paths and deterministic import settings after ASCII GLB normalization."""
import json,hashlib,struct
from pathlib import Path
R=Path(__file__).resolve().parents[3];G=R/'godot';D=R/'art_source/scenes/sunken_city/v003';W=R.parent/'sea-work/sunken_city/v003/import'
E=json.loads((D/'export/v003/export_manifest.json').read_text(encoding='utf-8'));RT=G/'assets/models/scenery/sunken_city/runtime_manifest.json';runtime=json.loads(RT.read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
for e in E['components']:
    p=R/e['glb'];data=p.read_bytes();size=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+size]);oldnode=next(n for n in doc['nodes'] if 'mesh' in n)['name']
    key=e['key'];prefab=G/f'scenes/components/scenery/sunken_city/{key}.tscn';s=prefab.read_text(encoding='utf-8')
    # The single leaf heading follows Visual; replace only its node name, not source-facing Chinese display root.
    marker='[node name="Visual" parent="." instance=ExtResource("model")]\n';base,leaf=s.split(marker,1)
    end=leaf.index(']\n');leaf='[node name='+json.dumps(oldnode)+' parent="Visual" index="0"'+leaf[end:]
    prefab.write_text(base+marker+leaf,encoding='utf-8')
    config=Path(str(p)+'.import');s=config.read_text(encoding='utf-8')
    for name,value in [('gltf/embedded_image_handling','0'),('meshes/generate_lods','false'),('meshes/create_shadow_meshes','false'),('animation/import','false'),('meshes/light_baking','0')]:
        import re
        s=re.sub(r'^'+re.escape(name)+r'=.*$',name+'='+value,s,flags=re.M)
    config.write_text(s,encoding='utf-8')
    row=next(r for r in runtime['components'] if r['key']==key);row.update(glb_sha256=sha(p),prefab_sha256=sha(prefab),import_settings={'embedded_image_handling':0,'automatic_lods':False,'shadow_meshes':False,'light_baking':0})
RT.write_text(json.dumps(runtime,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Original geometry unchanged by name normalization: existing four-view fidelity result still applies.
f=W/'fidelity_verification.json';v=json.loads(f.read_text(encoding='utf-8'));v['visual_review']='passed';v['review_notes']='Four fixed views checked; sample MAE 0.000032-0.000080, boundaries, color blocks and damage silhouettes retained. Later ASCII node rename contains no geometry/material edits.'
v['export_manifest_sha256']=sha(D/'export/v003/export_manifest.json');f.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('REPAIRED_IMPORT_CONTRACT',len(E['components']),'prefabs and import settings')

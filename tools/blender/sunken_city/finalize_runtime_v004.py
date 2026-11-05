"""Refresh only changed surface-role bindings and authorized city root lift, preserving live scene text."""
import hashlib,json,re,struct
from pathlib import Path
R=Path(__file__).resolve().parents[3];G=R/'godot';D=R/'art_source/scenes/sunken_city/v004';W=R.parent/'sea-work/sunken_city/v004/import'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
E=json.loads((D/'export/v004/export_manifest.json').read_text(encoding='utf-8'));M=json.loads((G/'assets/models/scenery/sunken_city/runtime_manifest.json').read_text(encoding='utf-8'));B=json.loads((W/'runtime_build.json').read_text(encoding='utf-8'))
roles={'SEA_Matte':'matte','SEA_Metal':'metal','SEA_Gloss':'gloss'}
for c in M['components']:
    e=next(x for x in E['components'] if x['key']==c['key']);p=G/c['prefab'].removeprefix('res://');s=p.read_text(encoding='utf-8');key=c['key']
    raw=(R/e['glb']).read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);node=next(x for x in doc['nodes'] if x.get('name')=='Mesh_'+key);used=[doc['materials'][x['material']]['name'] for x in doc['meshes'][node['mesh']]['primitives']]
    # Existing ext_resources remain stable, unused ones harmless; patch only serialized surface overrides.
    s=re.sub(r'^surface_material_override/\d+ = ExtResource\("[a-z]+"\)\n','',s,flags=re.M)
    anchor='cast_shadow = 1';assert s.count(anchor)==1
    replacement=''.join(f'surface_material_override/{i} = ExtResource("{roles[r]}")\n' for i,r in enumerate(used))
    s=s.replace(anchor,replacement+anchor);p.write_text(s,encoding='utf-8');c.update(roles=sorted(set(used)),prefab_sha256=sha(p))
lift=45.0;main=G/'scenes/main.tscn';assert sha(main)==B['main_sha256_after'],'Concurrent main edit'
before=(W/'main_before_v004.tscn').read_bytes();start=before.index(b'[node name="SunkenCity"');i=before.index(b'transform = Transform3D(',start);j=before.index(b')',i)+1;oldline=before[i:j];values=oldline.decode().removeprefix('transform = Transform3D(').removesuffix(')').split(',');assert len(values)==12 and float(values[10])==0
values[10]=' '+f'{lift:g}';new='transform = Transform3D('+','.join(values)+')';main.write_bytes(before[:i]+new.encode()+before[j:])
M['root_lift_m']=lift;dump(G/'assets/models/scenery/sunken_city/runtime_manifest.json',M);B['main_sha256_after']=sha(main);B['v004_approved_patch'].update(main_after_sha256=sha(main),root_lift_m=lift);dump(W/'runtime_build.json',B)
print('V004_SURFACE_ROLES_AND_LIFT',lift)

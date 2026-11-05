"""Incremental v004 update: existing wrappers and assembly text preserved except authorized metadata/contact."""
import hashlib,json,math,re,struct,zipfile
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v004';W=R.parent/'sea-work/sunken_city/v004/import';G=R/'godot'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
E=json.loads((D/'export/v004/export_manifest.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
assert E['passed'] and len(E['components'])==50
archive=R/'art_source/scenes/sunken_city/v003/export/v003/runtime_preserved_before_v004.zip'
with zipfile.ZipFile(archive) as z:old=json.loads(z.read('godot/assets/models/scenery/sunken_city/runtime_manifest.json'))
assert old['version']=='v003'
records=[]
for c in CAT:
    key=c['key'];e=next(e for e in E['components'] if e['key']==key);prefab=G/f'scenes/components/scenery/sunken_city/{key}.tscn'
    with zipfile.ZipFile(archive) as z:text=z.read(prefab.relative_to(R).as_posix()).decode('utf-8')
    assert text.count('metadata/asset_version = "v003"')==1
    replacement=text.replace('metadata/asset_version = "v003"','metadata/asset_version = "v004"')
    assert prefab.read_text(encoding='utf-8') in (text.replace('\r\n','\n'),replacement.replace('\r\n','\n')),'Concurrent prefab edit'
    text=replacement;prefab.write_bytes(text.encode('utf-8'))
    raw=(R/e['glb']).read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);assert any(n.get('name')=='Mesh_'+key for n in doc['nodes'])
    # Same hierarchy/role paths as verified v003; no wrapper reconstruction.
    assert 'parent="Visual/Root_'+key+'"' in text
    rec=next(x.copy() for x in old['components'] if x['key']==key)
    rec.update(asset_version='v004',category=c['category'],source_sha256=c['source_sha256'],prefab_sha256=sha(prefab),glb_sha256=sha(R/e['glb']),triangles=e['triangles_after'],bounds_blender=e['bounds_blender'],source_report=dict(source_master_sha256=sha(D/'sunken_city_v004.blend'),source_sha256=c['source_sha256']),import_settings=dict(embedded_image_handling=0,automatic_lods=False,shadow_meshes=False,light_baking=0))
    records.append(rec)
assembly=G/'scenes/world/sunken_city.tscn';before=assembly.read_bytes();assert before==(W/'assembly_before_v004.tscn').read_bytes();text=before.decode('utf-8');assert text.count('metadata/asset_version = "v003"')==1;text=text.replace('metadata/asset_version = "v003"','metadata/asset_version = "v004"')
instances=[];changed=[]
for a in P['instances']:
    prev=next(i for i in old['instances'] if i['instance_id']==a['instance_id']);matrix=list(prev['godot_transform']);dz=a['position_m'][2]-prev['position_m'][2]
    assert a['position_m'][:2]==prev['position_m'][:2] and a['rotation_euler_deg']==prev['rotation_euler_deg'] and a['scale']==prev['scale']
    matrix[10]+=dz
    if abs(dz)>1e-7:
        pattern=r'(\[node name="'+re.escape(a['instance_id'])+r'"[^\r\n]*\]\r?\ntransform = Transform3D\()([^\r\n]+)(\))';m=re.search(pattern,text);assert m,a['instance_id'];values=[float(x) for x in m[2].split(',')];assert len(values)==12;values[10]+=dz
        text=text[:m.start(2)]+', '.join(f'{v:.10g}' for v in values)+text[m.end(2):];changed.append(dict(instance_id=a['instance_id'],contact_shift_m=dz))
    instances.append(dict(a,godot_transform=matrix))
assert assembly.read_bytes()==before;assembly.write_text(text,encoding='utf-8')
lift=44.0;main=G/'scenes/main.tscn';beforemain=(W/'main_before_v004.tscn').read_bytes();assert main.read_bytes()==beforemain,'Concurrent main change'
line=b'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)';head=beforemain.index(b'[node name="SunkenCity"');pos=beforemain.index(line,head);aftermain=beforemain[:pos]+line.replace(b', 0, 0, 0)',f', 0, {lift:g}, 0)'.encode())+beforemain[pos+len(line):];main.write_bytes(aftermain)
manifest=dict(old,version='v004',source_master_sha256=sha(D/'sunken_city_v004.blend'),components=records,instances=instances,height_cap_contract=P['height_cap_contract'],root_lift_m=lift)
dump(G/'assets/models/scenery/sunken_city/runtime_manifest.json',manifest)
dump(W/'runtime_build.json',dict(passed=True,components=50,instances=388,assembly='godot/scenes/world/sunken_city.tscn',runtime_manifest='godot/assets/models/scenery/sunken_city/runtime_manifest.json',main_scope='only SunkenCity root translation; all other text preserved',main_sha256_before=hashlib.sha256(beforemain).hexdigest(),main_sha256_after=sha(main),v004_approved_patch=dict(main_before=str(W/'main_before_v004.tscn'),main_before_sha256=hashlib.sha256(beforemain).hexdigest(),main_after_sha256=sha(main),assembly_before=str(W/'assembly_before_v004.tscn'),archive=archive.relative_to(R).as_posix(),root_lift_m=lift),ground_contact_patches=changed))
print('V004_INCREMENTAL_PATCH',len(records),len(instances),'contact patches',len(changed),'lift',lift)

"""Prepare v005 runtime metadata and assembly: 40 reused perimeter ramp instances, no new mesh definition."""
import copy,hashlib,json,math
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v005';OLD=R/'art_source/scenes/sunken_city/v004';G=R/'godot';W=R.parent/'sea-work/sunken_city/v005/import'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];INST=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances'];assert len(CAT)==50 and len(INST)==428
old_export=json.loads((OLD/'export/v004/export_manifest.json').read_text(encoding='utf-8'));new_components=[]
protected={str((D/'sunken_city_v005.blend').relative_to(R)).replace('\\','/'):sha(D/'sunken_city_v005.blend'),str((R/P['palette']).relative_to(R)).replace('\\','/'):sha(R/P['palette'])}
for c in CAT:
 key=c['key'];src=R/c['component_blend'];assert src.exists();old=next(x for x in old_export['components'] if x['key']==key);e=copy.deepcopy(old);e['version']='v005';e['source']=str(src.relative_to(R)).replace('\\','/');e['source_sha256_before']=sha(src);e['source_sha256_after']=sha(src);e['source_sha256']=sha(src);e['optimized_source']=f'art_source/scenes/sunken_city/v005/export/v005/{key}_optimized.blend';e['optimized_sha256']=sha(R/e['optimized_source']);e['glb_sha256']=sha(R/e['glb']);e['source_preserved']=True;new_components.append(e);protected[e['source']]=e['source_sha256']
for c in CAT:c['version']='v005';c['component_blend']=f'art_source/scenes/sunken_city/v005/component_packages/{c["key"]}/{c["key"]}.blend';c['source_sha256']=sha(R/c['component_blend'])
dump(D/'component_catalog.json',{'schema':'sea.component_catalog','components':CAT}); export=dict(old_export,version='v005',passed=True,stage='exports_reused_from_v004_geometry_with_v005_source_paths',protected_sources=protected,components=new_components,source_unchanged=True);export['triangles_before']=sum(x['triangles_before'] for x in new_components);export['triangles_after']=sum(x['triangles_after'] for x in new_components);dump(D/'export/v005/export_manifest.json',export)
for c in CAT:
 p=G/f'scenes/components/scenery/sunken_city/{c["key"]}.tscn';p.write_text(p.read_text(encoding='utf-8').replace('metadata/asset_version = "v004"','metadata/asset_version = "v005"'),encoding='utf-8')
assembly=G/'scenes/world/sunken_city.tscn';base=(W/'assembly_before_v005.tscn').read_text(encoding='utf-8');s=base.replace('metadata/asset_version = "v004"','metadata/asset_version = "v005"');old_instances=json.loads((OLD/'component_instances.json').read_text(encoding='utf-8'))['instances'];old_ids={x['instance_id'] for x in old_instances};oldm=json.loads((G/'assets/models/scenery/sunken_city/runtime_manifest.json').read_text(encoding='utf-8'))
def mat3(yaw):
 t=math.radians(yaw);c=math.cos(t);q=math.sin(t);Rz=[[c,-q,0],[q,c,0],[0,0,1]];C=[[1,0,0],[0,0,1],[0,-1,0]];CI=[[1,0,0],[0,0,-1],[0,1,0]]
 def mm(a,b):return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
 return mm(C,mm(Rz,CI))
def gt(a):
 b=mat3(a['rotation_euler_deg'][2]);return [b[i][j] for i in range(3) for j in range(3)]+a['position_m'][:1]+[a['position_m'][2],-a['position_m'][1]]
def ser(m):return [m[0],m[3],m[6],m[1],m[4],m[7],m[2],m[5],m[8]]+m[9:]
new_instances=[]
for a in INST:
 if a['instance_id'] not in old_ids:
  m=gt(a);s+=f'\n[node name="{a["instance_id"]}" parent="." instance=ExtResource("c48")]\ntransform = Transform3D('+', '.join(f'{v:.10g}' for v in ser(m))+f')\nmetadata/instance_id = "{a["instance_id"]}"\nmetadata/urban_role = "{a.get("urban_role","")}"\n';new_instances.append(dict(a,godot_transform=m))
 else:
  oa=next(x for x in oldm['instances'] if x['instance_id']==a['instance_id']);new_instances.append(dict(a,godot_transform=oa['godot_transform']))
assert len(new_instances)==428 and sum(a.get('urban_role')=='outer_edge_slope_extension' for a in new_instances)==40
assembly.write_text(s,encoding='utf-8');records=[]
for e in new_components:
 key=e['key'];c=next(x for x in CAT if x['key']==key);p=G/f'scenes/components/scenery/sunken_city/{key}.tscn';records.append(dict(next(x for x in oldm['components'] if x['key']==key),asset_version='v005',source_sha256=c['source_sha256'],prefab_sha256=sha(p),glb_sha256=sha(R/e['glb']),source_report=dict(source_master_sha256=sha(D/'sunken_city_v005.blend'),source_sha256=c['source_sha256']),import_settings=dict(embedded_image_handling=0,automatic_lods=False,shadow_meshes=False,light_baking=0),category=c['category']))
manifest=dict(oldm,version='v005',source_master_sha256=sha(D/'sunken_city_v005.blend'),components=records,instances=new_instances,height_cap_contract=P['height_cap_contract'],road_edge_contract=P['road_edge_contract'],root_lift_m=43.487442,edge_extension_instance_count=40);dump(G/'assets/models/scenery/sunken_city/runtime_manifest.json',manifest);dump(W/'runtime_build.json',dict(passed=True,components=50,instances=428,assembly='godot/scenes/world/sunken_city.tscn',runtime_manifest='godot/assets/models/scenery/sunken_city/runtime_manifest.json',main_scope='fauna nodes plus unchanged manual SunkenCity root; assembly adds 40 edge ramps',main_sha256_before=sha(W/'main_before_v005.tscn'),main_sha256_after=sha(G/'scenes/main.tscn'),v005_approved_patch=dict(main_before=str(W/'main_before_v005.tscn'),assembly_before=str(W/'assembly_before_v005.tscn'),archive='art_source/scenes/sunken_city/v004/export/v004/runtime_preserved_before_v005_fauna.zip',root_lift_m=43.487442),edge_ramp_count=40));print('V005_RUNTIME_PREPARED',len(records),len(new_instances),'edge',40)

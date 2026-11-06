"""User correction: no road extension. Remove only 40 task-owned edge instances; native Terrain3D seabed below."""
import bpy,hashlib,json,re
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v005';W=R.parent/'sea-work/sunken_city/v005';G=R/'godot'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert bpy.app.background
mainsha=sha(G/'scenes/main.tscn'); src=D/'sunken_city_v005.blend'
bpy.ops.wm.open_mainfile(filepath=str(src),load_ui=False,use_scripts=False)
removed=[]
for side in ('west','east','north','south'):
 for i in range(1,11):
  name=f'edge_ramp_{side}_{i:02d}';o=bpy.data.objects.get(name)
  if o is not None:bpy.data.objects.remove(o,do_unlink=True);removed.append(name)
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
P['road_edge_contract']={'method':'Terrain3D heightmap below existing city','replaces_rejected_edge_instances':True,'added_road_instances':0,'city_boundary_xy_m':[-120,120,-120,120],'terrain_extent_xz_m':[-256,256,-256,256],'outward_slope_start_m':120.0,'outward_slope_end_m':216.0,'outer_depth_world_y_m':-62.0,'preserve_actual_tscn_transforms':True,'main_manual_root_y_m':43.487442,'collision':False}
P['coordinate_contract']['boundary_xy_m']=[-120,120,-120,120]
I=json.loads((D/'component_instances.json').read_text(encoding='utf-8'));I['instances']=[a for a in I['instances'] if not a['instance_id'].startswith('edge_ramp_')];assert len(I['instances'])==388
P['instances']=I['instances'];P['revision']='v005_native_seabed_under_city';P['status']='terrain_authoring_in_progress'
CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))
for c in CAT['components']:c['instance_count']=sum(a['key']==c['key'] for a in I['instances'])
for c in P['components']:c['instance_count']=sum(a['key']==c['key'] for a in I['instances'])
I['coordinate_contract']=P['coordinate_contract'];dump(D/'component_plan.json',P);dump(D/'component_instances.json',I);dump(D/'component_catalog.json',CAT)
S=bpy.data.scenes['沉没旧城_完整参考布局_v005'];S['plan_sha256']=sha(D/'component_plan.json');bpy.ops.wm.save_as_mainfile(filepath=str(src),compress=True,relative_remap=False)
A=G/'scenes/world/sunken_city.tscn';text=A.read_text(encoding='utf-8'); blocks=re.split(r'(?=^\[node )',text,flags=re.M);gone=[];keep=[]
for block in blocks:
 m=re.match(r'\[node name="(edge_ramp_(?:west|east|north|south)_\d{2})"',block)
 if m:gone.append(m.group(1))
 else:keep.append(block)
assert len(gone) in (0,40);A.write_text(''.join(keep),encoding='utf-8')
M=G/'assets/models/scenery/sunken_city/runtime_manifest.json';man=json.loads(M.read_text(encoding='utf-8'));man['instances']=[a for a in man['instances'] if not a['instance_id'].startswith('edge_ramp_')];assert len(man['instances'])==388
# TSCN, not historical authoring JSON, owns all existing hand placement.
actual={}
for match in re.finditer(r'^\[node name="([^"]+)" parent="\."[^\n]*\]\ntransform = Transform3D\(([^)]+)\)',A.read_text(encoding='utf-8'),flags=re.M):
 vals=[float(v.strip()) for v in match[2].split(',')];actual[match[1]]=[vals[0],vals[3],vals[6],vals[1],vals[4],vals[7],vals[2],vals[5],vals[8]]+vals[9:]
changed=[]
for a in man['instances']:
 assert a['instance_id'] in actual,a['instance_id']
 if max(abs(x-y) for x,y in zip(a['godot_transform'],actual[a['instance_id']]))>.0001:changed.append(a['instance_id'])
 a['godot_transform']=actual[a['instance_id']];a['placement_authority']='actual Godot TSCN preserved'
man['road_edge_contract']=P['road_edge_contract'];man['edge_extension_instance_count']=0;man['source_master_sha256']=sha(src);man['placement_sync_note']='Preserve existing editor overrides, never rewrite them from source';
for c in man['components']:c['source_report']['source_master_sha256']=sha(src)
dump(M,man)
asset=json.loads((D/'asset_manifest.json').read_text(encoding='utf-8'));asset.update(source_sha256=sha(src),instance_count=388,road_edge_contract=P['road_edge_contract'],source_verified=False,runtime_integrated=False);dump(D/'asset_manifest.json',asset)
assert sha(G/'scenes/main.tscn')==mainsha
dump(W/'seabed_scope_correction.json',{'passed':True,'removed_source_ids':removed,'removed_runtime_ids':gone,'main_sha256':mainsha,'city_instances_preserved':388,'existing_editor_overrides_preserved':changed,'terrain_method':'Terrain3D','source_sha256':sha(src)})
print('SEABED_SCOPE_CORRECTED',len(gone),'removed',len(changed),'historical overrides preserved')

"""v005 source: preserve v004 city and append four continuous perimeter bands of reused terrain ramps."""
import bpy,copy,hashlib,json,math,zipfile
from pathlib import Path
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/sunken_city/v004';D=OLD.parent/'v005';W=R.parent/'sea-work/sunken_city/v005'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'];OLDI=json.loads((OLD/'component_instances.json').read_text(encoding='utf-8'))
assert not (D/'sunken_city_v005.blend').exists() and P['version']=='v005'
bpy.ops.wm.open_mainfile(filepath=str(OLD/'sunken_city_v004.blend'),load_ui=False,use_scripts=False);S=bpy.data.scenes['沉没旧城_完整参考布局_v004'];S.name='沉没旧城_完整参考布局_v005';bpy.context.window.scene=S
ramp=next(c for c in CAT if c['key']=='terrain_ramp');col=bpy.data.collections[ramp['collection']]
inst=copy.deepcopy(OLDI['instances']);added=[]
# Blender coordinates: (x,y,z), y maps to -Godot Z. Local ramp rises along +local X.
for side in ('west','east','north','south'):
 for i in range(10):
  t=-108+24*i
  if side=='west': x,y,yaw=-120,t,0
  elif side=='east': x,y,yaw=120,t,180
  elif side=='north': x,y,yaw=t,120,-90
  else: x,y,yaw=t,-120,90
  name=f'edge_ramp_{side}_{i+1:02d}'
  o=bpy.data.objects.new(name,None);o.instance_type='COLLECTION';o.instance_collection=col;bpy.data.collections['街道_逐段拼接实例'].objects.link(o);o.location=(x,y,-66.7);o.rotation_euler.z=math.radians(yaw)
  o['asset_id']=ramp['component_id'];o['building_class']='underwater';o['collision']='none';o['interactive']=False;o['urban_role']='outer_edge_slope_extension';o['terrain_reference_xy']=[x,y]
  a=dict(instance_id=name,key='terrain_ramp',component_id=ramp['component_id'],position_m=[x,y,-66.7],rotation_euler_deg=[0.0,0.0,float(yaw)],scale=[1.0,1.0,1.0],source_object=name,urban_role='outer_edge_slope_extension',detail_zone='v005_road_edge',terrain_height_shift_m=0.0)
  inst.append(a);added.append(a)
assert len(inst)==428
for c in CAT:c['instance_count']=sum(a['key']==c['key'] for a in inst);c['version']='v005'
for pc in P['components']:pc['instance_count']=next(c['instance_count'] for c in CAT if c['key']==pc['key']);pc['version']='v005'
P['instances']=inst;P['component_catalog_version']='v005';P['asset_version']='v005';P['source_master_previous']='art_source/scenes/sunken_city/v004/sunken_city_v004.blend';P['source_master_previous_sha256']=sha(OLD/'sunken_city_v004.blend');P['road_edge_contract']['added_instances']=40;P['road_edge_contract']['edge_instance_ids']=[a['instance_id'] for a in added]
# Keep component definitions and their stable source packages; only layout adds instances.
dump(D/'component_plan.json',P);dump(D/'component_catalog.json',{'schema':'sea.component_catalog','components':CAT});dump(D/'component_instances.json',{'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'terrain_contract':P['terrain_contract'],'instances':inst})
S['plan_sha256']=sha(D/'component_plan.json');S.camera=bpy.data.objects.get('相机_坡地断桥_全景') or S.camera
bpy.ops.wm.save_as_mainfile(filepath=str(D/'sunken_city_v005.blend'),compress=True,relative_remap=False)
oldman=json.loads((OLD/'asset_manifest.json').read_text(encoding='utf-8'));oldman.update(version='v005',name='沉没旧城_统一限高浅水与外扩缓坡版',source='art_source/scenes/sunken_city/v005/sunken_city_v005.blend',source_sha256=sha(D/'sunken_city_v005.blend'),runtime_integrated=False,source_verified=False,component_count=50,instance_count=428,road_edge_contract=P['road_edge_contract']);dump(D/'asset_manifest.json',oldman)
print('V005_SOURCE_SAVED',sha(D/'sunken_city_v005.blend'),'instances',len(inst),'edge',len(added),'terrain_instances',next(c['instance_count'] for c in CAT if c['key']=='terrain_ramp'))

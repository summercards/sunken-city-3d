"""Broaden red-box detail clusters after real render review; inherited terrain/architecture stays locked."""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v002';W=R.parent/'sea-work/sunken_city/v002'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];C={c['key']:c for c in CAT}
S=bpy.data.scenes['沉没旧城_完整参考布局_v002']
for o in list(S.objects):
    if o.get('detail_pass')=='cluster_density':bpy.data.objects.remove(o,do_unlink=True)
# Denser broad slabs at wreck ends, retaining-wall groups and service courts. Not all vacant central ground is filled.
items=[
 ('rubble_cluster',-72,-84,12,'redbox_01'),('rubble_cluster',-71,-79,76,'redbox_01'),('rubble_cluster',-90,-65,31,'redbox_01'),
 ('rubble_cluster',-95,-78,113,'redbox_01'),('moss_patch',-71,-74,16,'redbox_01'),
 ('rubble_cluster',8,-85,15,'redbox_02'),('rubble_cluster',9,-93,61,'redbox_02'),('retaining_wall_ruin',18,-98,8,'redbox_02'),
 ('moss_patch',21,-93,21,'redbox_02'),('rubble_cluster',-19,-88,77,'redbox_02'),
 ('retaining_wall_ruin',-1,-39,88,'redbox_03'),('retaining_wall_ruin',5,-31,8,'redbox_03'),
 ('rubble_cluster',8,-36,5,'redbox_03'),('rubble_cluster',15,-33,61,'redbox_03'),('car_sedan',18,-48,11,'redbox_03'),
 ('kelp_clump',-3,-35,31,'redbox_03'),('moss_patch',13,-39,77,'redbox_03'),
 ('retaining_wall_ruin',4,56,90,'redbox_04'),('rubble_cluster',18,56,11,'redbox_04'),('rubble_cluster',7,70,61,'redbox_04'),
 ('car_sedan',22,68,102,'redbox_04'),('moss_patch',17,69,3,'redbox_04'),
 ('rubble_cluster',32,65,23,'redbox_05'),('rubble_cluster',38,51,77,'redbox_05'),('retaining_wall_ruin',27,52,-12,'redbox_05'),
 ('kelp_clump',25,61,14,'redbox_05'),
 ('retaining_wall_ruin',52,65,-5,'redbox_06'),('retaining_wall_ruin',46,58,90,'redbox_06'),
 ('rubble_cluster',53,58,14,'redbox_06'),('rubble_cluster',59,63,77,'redbox_06'),('rubble_cluster',69,43,113,'redbox_06'),
 ('rubble_cluster',73,50,25,'redbox_06'),('car_sedan',61,46,10,'redbox_06'),('bench',47,49,89,'redbox_06'),
 ('moss_patch',57,55,5,'redbox_06'),('kelp_clump',74,54,51,'redbox_06'),('rubble_cluster',88,54,31,'redbox_06'),
 ('rubble_cluster',51,-10,55,'redbox_07'),('retaining_wall_ruin',57,-23,-5,'redbox_07'),('moss_patch',52,-22,16,'redbox_07'),
 ('rubble_cluster',62,-70,44,'redbox_08'),('rubble_cluster',52,-64,111,'redbox_08'),('retaining_wall_ruin',57,-60,5,'redbox_08'),
 ('moss_patch',60,-72,73,'redbox_08'),
 ('retaining_wall_ruin',62,-49,15,'redbox_09'),('rubble_cluster',64,-56,25,'redbox_09'),('rubble_cluster',72,-37,76,'redbox_09'),
 ('rubble_cluster',80,-58,45,'redbox_09'),('kelp_clump',65,-40,11,'redbox_09'),
 ('retaining_wall_ruin',98,-33,-3,'redbox_10'),('rubble_cluster',105,-49,16,'redbox_10'),('rubble_cluster',102,-54,78,'redbox_10'),
 ('rubble_cluster',114,-39,45,'redbox_10'),('pump_cabinet',111,-32,-3,'redbox_10'),('moss_patch',108,-42,33,'redbox_10'),
]
added=[]
# Broad phase: avoid inherited building envelopes for newly added low clusters.
bpy.context.view_layer.update()
old_arch=[]
for o in S.objects:
    if o.instance_type!='COLLECTION' or o.get('revision_owner'):continue
    c=next(c for c in CAT if c['collection']==o.instance_collection.name)
    if c['category']!='architecture':continue
    pts=[o.matrix_world@v.co for q in o.instance_collection.objects if q.type=='MESH' for v in q.data.vertices]
    old_arch.append(([min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]))
skips=[]
for index,(key,x,y,yaw,zone) in enumerate(items):
    c=C[key];o=bpy.data.objects.new(f'DETAIL2_DENSE_{index:03}_{key}',None);o.instance_type='COLLECTION';o.instance_collection=bpy.data.collections[c['collection']]
    dest='海藻青苔_独立可隐藏' if c['category']=='vegetation' else '设施车辆_独立实例';bpy.data.collections[dest].objects.link(o)
    o.rotation_euler.z=math.radians(yaw);rot=o.rotation_euler.to_matrix()
    ps=[rot@v.co for q in o.instance_collection.objects if q.type=='MESH' for v in q.data.vertices];lo=[min(p[i] for p in ps) for i in range(3)];hi=[max(p[i] for p in ps) for i in range(3)]
    o.location=(x-(lo[0]+hi[0])/2,y-(lo[1]+hi[1])/2,-61.3-lo[2])
    if any(min(x+(hi[0]-lo[0])/2,ah[0])-max(x-(hi[0]-lo[0])/2,al[0])>1 and min(y+(hi[1]-lo[1])/2,ah[1])-max(y-(hi[1]-lo[1])/2,al[1])>1 for al,ah in old_arch):
        skips.append(o.name);bpy.data.objects.remove(o,do_unlink=True);continue
    for k,v in [('revision_owner','sunken_city_v002'),('detail_pass','cluster_density'),('asset_id',c['component_id']),('building_class','underwater'),('collision','none'),('interactive',False),('detail_zone',zone),('urban_role','clustered_low_ruin')]:o[k]=v
    added.append(o)
inst=[]
for o in S.objects:
    if o.instance_type!='COLLECTION' or o.instance_collection is None:continue
    c=next(c for c in CAT if c['collection']==o.instance_collection.name)
    inst.append(dict(instance_id=o.name,key=c['key'],component_id=c['component_id'],position_m=list(o.location),rotation_euler_deg=[round(math.degrees(a),6) for a in o.rotation_euler],scale=list(o.scale),source_object=o.name,urban_role=o.get('urban_role','inherited'),detail_zone=o.get('detail_zone','')))
for c in CAT:c['instance_count']=sum(a['key']==c['key'] for a in inst)
for c in P['components']:c['instance_count']=C[c['key']]['instance_count']
P['instances']=inst;P['render_review_revision']='cluster-density-pass-after-closeup-review'
for f,v in [('component_plan.json',P),('component_catalog.json',{'schema':'sea.component_catalog','components':CAT}),('component_instances.json',{'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'floor_contract':P['floor_contract'],'instances':inst})]:(D/f).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
S['plan_sha256']=hashlib.sha256((D/'component_plan.json').read_bytes()).hexdigest()
bpy.ops.wm.save_as_mainfile(filepath=str(W/'sunken_city_v002_working.blend'),compress=True)
print('DENSITY_PASS',len(added),'added',len(skips),'skipped to avoid old building overlap','instances',len(inst))

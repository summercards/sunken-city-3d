"""Live Blender v002 local enrichment: four reusable low facilities + ten red-box groups + road wrecks.
Preserves all v001 component geometries and aligned terrain. Idempotent, safe checkpoint required.
"""
import ast,bpy,bmesh,hashlib,json,math,random,os
from pathlib import Path
from mathutils import Euler,Matrix,Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v002';OLD=D.parent/'v001';W=R.parent/'sea-work/sunken_city/v002'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components']
assert P['status']=='frozen_before_geometry' and len(P['components'])==50
assert (W/'pre_detail_session.blend').exists()
assert not (D/'sunken_city_v002.blend').exists(),'Delivered file already exists: bump version'
assert hashlib.sha256((OLD/'sunken_city_v001.blend').read_bytes()).hexdigest()==P['previous_source_sha256']
S=bpy.data.scenes.get('沉没旧城_完整参考布局_v002') or bpy.data.scenes['沉没旧城_完整参考布局_v001']
if bpy.context.window:bpy.context.window.scene=S
MASTER=bpy.data.scenes['01_组件母版_独立编辑'];MA=bpy.data.collections['01_制作组件_单栋与街段']
# Fast byte-level geometry/material/UV signatures independent of the building helper.
def mesh_signature(o):
    from array import array
    me=o.data;h=hashlib.sha256()
    for data,field,typ,num in [(me.vertices,'co','f',3),(me.loops,'vertex_index','i',1),(me.polygons,'loop_total','i',1),(me.polygons,'material_index','i',1),(me.uv_layers['PaletteUV'].data,'uv','f',2)]:
        buf=array(typ,[0])*(len(data)*num);data.foreach_get(field,buf);h.update(buf.tobytes())
    h.update(json.dumps([m.name for m in me.materials]).encode());return h.hexdigest()
def signature():
    return {c['key']:mesh_signature(next(o for o in bpy.data.collections[c['collection']].objects if o.type=='MESH')) for c in CAT if c['key'] not in {'retaining_wall_ruin','pump_cabinet','kiosk_ruin','bench'}}
lockfile=W/'scope_lock.json'
if not lockfile.exists():
    lock={'before_geometry':signature(),'before_instances':{o.name:[list(r) for r in o.matrix_world] for o in S.objects if o.instance_type=='COLLECTION'},'previous_source_sha256':P['previous_source_sha256'],'reference_cameras':{o.name:{'matrix':[list(r) for r in o.matrix_world],'ortho_scale':o.data.ortho_scale} for o in S.objects if o.type=='CAMERA'}}
    lockfile.write_text(json.dumps(lock,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
else:lock=json.loads(lockfile.read_text(encoding='utf-8'))
# Retry restores only candidate-local fixture relocations from this task's checkpoint.
for name,matrix in lock['before_instances'].items():
    o=bpy.data.objects.get(name)
    if o and o.instance_type=='COLLECTION' and next(c['category'] for c in CAT if c['collection']==o.instance_collection.name)=='facilities':
        o.matrix_world=Matrix(matrix)
bpy.context.view_layer.update()
# Reuse existing geometry primitives without running any startup/reset code.
mod=ast.parse(Path(__file__).with_name('build.py').read_text(encoding='utf-8'))
keep=[n for n in mod.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ('box_template','Builder','text_shape')]
exec(compile(ast.Module(body=keep,type_ignores=[]),'v002_geometry_primitives_only','exec'),globals())
CUBE_F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)];CACHE={}
MATS=[bpy.data.materials[n] for n in ('SEA_Matte','SEA_Metal','SEA_Gloss')]
CELLS={c['name']:c for c in json.loads((R/P['palette']).with_suffix('.json').read_text(encoding='utf-8'))['cells']}
newkeys={'retaining_wall_ruin','pump_cabinet','kiosk_ruin','bench'}
# Remove only v002-owned new objects on retry; never delete inherited instances/geometry.
for o in list(bpy.data.objects):
    if o.get('revision_owner')=='sunken_city_v002':bpy.data.objects.remove(o,do_unlink=True)
for c in list(bpy.data.collections):
    if c.get('revision_owner')=='sunken_city_v002':bpy.data.collections.remove(c)
for c in P['components']:
    if c['key'] not in newkeys:continue
    key=c['key'];B=Builder()
    if key=='retaining_wall_ruin':
        # Stepped, missing wall bays; exposed pipe and concrete tongues retain human-scale rhythm.
        for x,length,h in [(-2.8,2.4,1.7),(-.4,2.2,1.05),(2.1,2.6,2.05)]:
            B.box((x,0,h/2),(length,.7,h),'plaster',.095)
            B.box((x,-.03,h+.08),(length+.08,.85,.16),'stone',.06)
        B.box((-.5,0,.16),(7.9,1.8,.32),'stone',.08)
        B.tube([(-3.8,-.6,.5),(-1,-.6,.5),(-1,-.6,1.3),(1.5,-.6,1.3),(1.5,-.6,.3),(3.5,-.6,.3)],.12,'jade')
        for x in (-2.8,2.6):B.tube([(x,.1,1.1),(x+.4,.2,2.4)],.045,'bark')
        for i in range(3):B.box((-2+i*1.8,-.5,.3),(1.0,.8,.3),'stone',.05,rot=(.1,.08,i*.5))
    elif key=='pump_cabinet':
        B.box((0,0,.16),(3.4,2.7,.32),'stone',.07)
        B.box((-.6,.15,1.2),(1.5,1.4,2.1),'seafoam',.12)
        B.box((-.6,-.6,1.15),(1.2,.12,1.7),'teal',.065)
        for i in range(6):B.box((-.6,-.68,.65+i*.16),(.9,.055,.055),'steel',.01)
        B.box((-.6,-.68,1.86),(.85,.07,.2),'honey',.025)
        B.cyl((.75,.12,.9),.55,1.1,'gray',1,12,'Y')
        B.tube([(.8,-.8,.85),(.8,-1.0,.4),(1.5,-1.0,.4),(1.5,.7,.4),(1.1,.7,1.4)],.18,'jade')
        B.cyl((1.1,.7,1.6),.3,.1,'red_dark',1,12)
        for a in range(0,360,90):
            ang=math.radians(a);B.tube([(1.1,.7,1.6),(1.1+.24*math.cos(ang),.7+.24*math.sin(ang),1.6)],.035,'red_dark')
    elif key=='kiosk_ruin':
        B.box((0,0,.18),(5.3,4.1,.36),'stone',.08)
        for x in (-2.2,2.2):
            for y in (-1.6,1.6):B.box((x,y,1.7),(.3,.3,3.3),'cream',.055)
        B.box((0,1.6,1.65),(4.5,.3,2.9),'seafoam',.065)
        for x in (-2.2,2.2):B.box((x,.25,1.0),(.3,2.6,1.3),'seafoam',.065)
        B.box((0,-1.6,1.15),(4.6,.9,.22),'wood',.06)
        B.box((-.65,0,3.45),(4.1,4.2,.28),'coral',.095,rot=(.04,.05,0))
        B.box((0,-1.78,2.95),(4.3,.24,.65),'teal',.06);text_shape('TICKETS',(0,-1.93,2.76),.44,'cream')
        for i in range(5):B.box((-1.45+i*.7,-1.3,1.36),(.5,.4,.2),('butter','seafoam','coral')[i%3],.03)
        # Broken roof fragment is part of its own kiosk, not an unrelated merged floor.
        B.box((1.9,.1,.5),(1.2,2.3,.2),'coral',.06,rot=(.15,.3,-.15))
    elif key=='bench':
        for xx in (-1.2,1.2):
            B.box((xx,0,.4),(.2,.8,.8),'steel',.04,1)
            B.box((xx,.36,.85),(.16,.18,1.2),'steel',.035,1)
        for yy in (-.3,-.05,.2):B.box((0,yy,.82),(3.4,.22,.15),'wood',.045)
        for zz,lx,cx in [(1.15,3.4,0),(1.48,2.45,-.45)]:B.box((cx,.4,zz),(lx,.15,.22),'wood_light',.04)
    col=bpy.data.collections.new(c['component_id']+'_'+c['name']);col['revision_owner']='sunken_city_v002';MA.children.link(col)
    o=B.finish(c['name'],col);o['revision_owner']='sunken_city_v002'
    lo=[min(v.co[i] for v in o.data.vertices) for i in range(3)];hi=[max(v.co[i] for v in o.data.vertices) for i in range(3)]
    shift=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
    for v in o.data.vertices:v.co-=shift
    root=bpy.data.objects.new(c['component_id']+'_ROOT',None);col.objects.link(root);root['revision_owner']='sunken_city_v002';o.parent=root
    for ob in (o,root):
        ob['asset_id']=c['component_id'];ob['building_class']='underwater';ob['collision']='none';ob['interactive']=False;ob['emission']=False
    o.data.update();o.data.calc_loop_triangles()
    row=dict(c,collection=col.name,root_object=root.name,objects=[root.name,o.name],bounds_size_m=[hi[i]-lo[i] for i in range(3)],
        local_origin=[0,0,0],triangles=len(o.data.loop_triangles),polygons=len(o.data.polygons),material_roles=sorted({o.data.materials[f.material_index].name for f in o.data.polygons}),palette=P['palette'],collision_owner='none_pure_scenery',dependencies=[])
    CAT.append(row)
for c in CAT:
    c.update(version='v002',component_blend=f'art_source/scenes/sunken_city/v002/component_packages/{c["key"]}/{c["key"]}.blend')
    c.pop('source_sha256',None);c.pop('geometry_fingerprint',None)
bykey={c['key']:c for c in CAT}
newinst=[]
def add(key,x,y,yaw=0,rx=0,ry=0,zone='',surface=-61.3,role='red_box_detail'):
    c=bykey[key];col=bpy.data.collections[c['collection']]
    o=bpy.data.objects.new(f'DETAIL2_{key}_{len(newinst)+1:03}',None);o.instance_type='COLLECTION';o.instance_collection=col
    name='建筑_独立实例' if c['category']=='architecture' else '海藻青苔_独立可隐藏' if c['category']=='vegetation' else '设施车辆_独立实例'
    bpy.data.collections[name].objects.link(o);o.rotation_euler=[math.radians(v) for v in (rx,ry,yaw)]
    rot=o.rotation_euler.to_matrix();pts=[rot@v.co for q in col.objects if q.type=='MESH' for v in q.data.vertices]
    lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
    # Add uses actual bbox-centre XY, then maps to root origin; rotation cannot lift the wreck off the road.
    o.location=(x-(lo[0]+hi[0])/2,y-(lo[1]+hi[1])/2,surface-lo[2])
    o['revision_owner']='sunken_city_v002';o['asset_id']=c['component_id'];o['building_class']='underwater';o['collision']='none';o['interactive']=False;o['detail_zone']=zone;o['urban_role']=role
    newinst.append(o);return o
# Horizontal road wrecks use existing whole-building masters: no duplicate geometry definitions.
add('canal_shell',-84,-78,90,90,0,'redbox_01',-61.12,'horizontal_road_wreck')
add('electronics_shop',-6,-84,0,90,0,'redbox_02',-61.12,'horizontal_road_wreck')
add('electronics_shop',86,66,0,-90,0,'redbox_06',-61.12,'horizontal_road_wreck')
# Each red area gets an authored identity and asymmetric visual density, not a repetitive rubble stamp.
# 1: snapped services and masonry at the road collapse.
for key,x,y,yaw in [('rubble_cluster',-78,-87,17),('rubble_cluster',-92,-70,71),('leaning_pole',-68,-76,28),('kelp_clump',-70,-70,15)]:add(key,x,y,yaw,zone='redbox_01')
# 2: wreck-side vehicle queue with small curb furniture.
for key,x,y,yaw in [('car_van',13,-92,96),('car_sedan',18,-86,72),('retaining_wall_ruin',5,-96,5),('moss_patch',9,-91,21),('kelp_clump',17,-97,60)]:add(key,x,y,yaw,zone='redbox_02')
# 3: utility remnant in the original no-building centre. Low props only, 2.4m-high wall max.
for key,x,y,yaw in [('retaining_wall_ruin',8,-43,7),('pump_cabinet',15,-38,32),('bench',1,-35,5),('bench',7,-34,-18),('rubble_cluster',14,-45,50),('moss_patch',2,-42,0),('kelp_clump',16,-43,44)]:add(key,x,y,yaw,zone='redbox_03')
# 4: old ticket/service corner near existing shop line.
for key,x,y,yaw in [('kiosk_ruin',12,66,180),('vending',17,64,180),('bench',7,61,161),('scooter',18,60,42),('rubble_cluster',11,58,70),('kelp_clump',5,68,25)]:add(key,x,y,yaw,zone='redbox_04')
# 5: drain service with short broken retaining-wall arc.
for key,x,y,yaw in [('retaining_wall_ruin',32,62,12),('pump_cabinet',34,56,20),('retaining_wall_ruin',39,55,95),('moss_patch',29,57,33),('kelp_clump',39,61,70)]:add(key,x,y,yaw,zone='redbox_05')
# 6: broad court, two very different islands; east road wreck remains legible.
for key,x,y,yaw in [('kiosk_ruin',54,52,90),('bus_shelter',64,39,180),('bench',53,43,95),('retaining_wall_ruin',71,47,-15),('pump_cabinet',62,58,8),('car_van',71,58,-18),('rubble_cluster',71,69,47),('kelp_clump',59,46,13),('moss_patch',68,52,45)]:add(key,x,y,yaw,zone='redbox_06')
# 7: broken-room edge with fans of broad slabs; no new whole building below the supply footprint.
for key,x,y,yaw in [('retaining_wall_ruin',51,-16,-21),('rubble_cluster',58,-11,17),('rubble_cluster',57,-19,70),('bench',47,-9,-23),('kelp_clump',48,-20,33),('moss_patch',60,-16,18)]:add(key,x,y,yaw,zone='redbox_07')
# 8: abandoned service van and toppled signal hardware.
for key,x,y,yaw in [('car_van',56,-70,19),('retaining_wall_ruin',49,-72,12),('vending',60,-67,-11),('rubble_cluster',56,-76,30),('kelp_clump',48,-68,40)]:add(key,x,y,yaw,zone='redbox_08')
# 9: fallen street fixtures and vehicle pair along the large southern-right strip.
for key,x,y,yaw in [('retaining_wall_ruin',69,-46,90),('car_sedan',76,-51,15),('car_van',76,-37,-9),('rubble_cluster',72,-58,47),('pump_cabinet',67,-35,50),('kelp_clump',74,-43,77)]:add(key,x,y,yaw,zone='redbox_09')
add('street_lamp',69,-56,35,rx=86,zone='redbox_09',role='fallen_street_fixture')
# 10: old forecourt squeezed around an existing outer building, not a new stand-alone building.
for key,x,y,yaw in [('kiosk_ruin',102,-43,90),('retaining_wall_ruin',104,-35,88),('car_van',98,-51,10),('bench',98,-39,78),('rubble_cluster',109,-45,50),('kelp_clump',111,-37,23),('moss_patch',99,-46,60)]:add(key,x,y,yaw,zone='redbox_10')
# Streets are deliberately obstructed by fallen visual buildings; surrounding fixed services may be locally moved
# only if their real envelopes intersect. Record exact before/after; no inherited ground or building is changed.
bpy.context.view_layer.update()
relocations=[]
wrecks=[o for o in newinst if o.get('urban_role')=='horizontal_road_wreck']
def obb(o):
    ps=[o.matrix_world@v.co for q in o.instance_collection.objects if q.type=='MESH' for v in q.data.vertices]
    return [[min(p[i] for p in ps) for i in range(3)],[max(p[i] for p in ps) for i in range(3)]]
for w in wrecks:
    wl,wh=obb(w)
    for o in list(S.objects):
        if o.get('revision_owner') or o.instance_type!='COLLECTION':continue
        c=next(c for c in CAT if c['collection']==o.instance_collection.name)
        if c['category']!='facilities':continue
        ol,oh=obb(o)
        if min(wh[0],oh[0])-max(wl[0],ol[0])>.2 and min(wh[1],oh[1])-max(wl[1],ol[1])>.2:
            before=list(o.location);o.location.x+=8 if w.location.x>-20 else -4;o.location.y+=5
            relocations.append(dict(instance=o.name,before=before,after=list(o.location),reason='clear horizontal road wreck; original floor/building not touched'))
# The old 46 mesh/material/UV signatures must be identical. All ground and original building transforms are locked.
after=signature();assert after==lock['before_geometry'],'Inherited component geometry drift'
for name,matrix in lock['before_instances'].items():
    o=bpy.data.objects.get(name)
    if o and next(c['category'] for c in CAT if c['collection']==o.instance_collection.name) in ('architecture','ground'):
        assert all(abs(o.matrix_world[i][j]-matrix[i][j])<1e-5 for i in range(4) for j in range(4)),'locked original '+name
# Stable new camera matching the submitted viewport's broad orthogonal-like perspective.
STAGE=bpy.data.collections['90_展示与验收_不导出']
def cam(name,pos,target,scale):
    o=bpy.data.objects.get(name)
    if o:return o
    data=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,data);STAGE.objects.link(o);o['revision_owner']='sunken_city_v002'
    o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=scale;return o
cam('相机_补景_红框全景',(230,-100,380),(0,0,-45),325)
cam('相机_补景_道路横卧',(-130,-155,3),(-73,-79,-49),103)
cam('相机_补景_中央设施',(112,-112,-5),(22,-34,-56),115)
cam('相机_补景_服务街',(145,106,-2),(69,49,-55),115)
S.name='沉没旧城_完整参考布局_v002';S['suite']='sunken_city';S['version']='v002';S['revision']='red_box_detail_and_horizontal_wrecks'
inst=[]
for o in S.objects:
    if o.instance_type!='COLLECTION' or o.instance_collection is None:continue
    c=next(c for c in CAT if c['collection']==o.instance_collection.name)
    inst.append(dict(instance_id=o.name,key=c['key'],component_id=c['component_id'],position_m=list(o.location),rotation_euler_deg=[round(math.degrees(a),6) for a in o.rotation_euler],scale=list(o.scale),source_object=o.name,urban_role=o.get('urban_role','inherited'),detail_zone=o.get('detail_zone','')))
for c in CAT:c['instance_count']=sum(a['key']==c['key'] for a in inst)
for pc in P['components']:pc['instance_count']=bykey[pc['key']]['instance_count']
P['instances']=inst;P['fixture_relocations']=relocations
P['exclusion_policy']['central']='no additional whole building; low street detail allowed by red-box feedback; continuous ground unchanged'
P['validation_contract']={'horizontal_road_wreck_count':3,'inherited_components_locked':46,'ground_instances_locked':100,'detail_zones':10,'unchanged_source_hash':P['previous_source_sha256']}
for f,v in [('component_plan.json',P),('component_catalog.json',{'schema':'sea.component_catalog','components':CAT}),('component_instances.json',{'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'floor_contract':P['floor_contract'],'instances':inst})]:
    (D/f).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_tree.txt').write_text('\n'.join(c['component_id']+' '+c['name']+' -> component_packages/'+c['key'] for c in CAT)+'\n',encoding='utf-8')
lock.update(after_geometry=after,geometry_locked_match=after==lock['before_geometry'],fixture_relocations=relocations)
lockfile.write_text(json.dumps(lock,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
S['plan_sha256']=hashlib.sha256((D/'component_plan.json').read_bytes()).hexdigest()
bpy.ops.wm.save_as_mainfile(filepath=str(W/'sunken_city_v002_working.blend'),compress=True)
print('DETAIL_V002',len(CAT),'components',len(inst),'instances',len(newinst),'added',len(relocations),'fixture moves')

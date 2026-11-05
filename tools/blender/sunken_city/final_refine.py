"""Final source refinement: fix physically overlapping facade piers, enrich real street blocks.
Only this new suite's architecture is revised; floor geometry remains locked and aligned.
"""
import ast,bpy,bmesh,hashlib,json,math,random
from pathlib import Path
from mathutils import Euler,Matrix,Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v001';W=R.parent/'sea-work/sunken_city/v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];bykey={c['key']:c for c in CAT}
S=bpy.data.scenes['沉没旧城_完整参考布局_v001'];MA=bpy.data.collections['01_制作组件_单栋与街段']
if not (W/'before_facade_refine.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'before_facade_refine.blend'),copy=True,compress=True)
MATS=[bpy.data.materials[n] for n in ('SEA_Matte','SEA_Metal','SEA_Gloss')]
CELLS={c['name']:c for c in json.loads((R/P['palette']).with_suffix('.json').read_text(encoding='utf-8'))['cells']}
CUBE_F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)];CACHE={}
mod=ast.parse(Path(__file__).with_name('build.py').read_text(encoding='utf-8'))
names=('box_template','Builder','text_shape','clip','tank','aircon','rail','building')
keep=[n for n in mod.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in names]
exec(compile(ast.Module(body=keep,type_ignores=[]),'facade_fixed_geometry_only','exec'),globals())
# Before geometry edits record floors to prove user-requested aligned modules remain unchanged.
floor_fps={}
for c in CAT:
    if c['category']=='ground':
        o=next(o for o in bpy.data.collections[c['collection']].objects if o.type=='MESH')
        floor_fps[c['key']]=hashlib.sha256(str([(tuple(v.co)) for v in o.data.vertices]).encode()).hexdigest()
for c in CAT:
    if c['category']!='architecture' or c['key'] in ('collapsed_residence','fallen_hall'):continue
    col=bpy.data.collections[c['collection']];old=next(o for o in col.objects if o.type=='MESH')
    B=Builder();building(c)
    # Attached details are architecture, not a second building or independent prop.
    if c['style'] in ('tram','balcony','terrace','canal'):
        w,d,_=c['size_design_m'];x=-w*.38;yy=-d*.5-.2
        # Vertical service sign, thick backing/hangers; readable but unlit underwater.
        B.box((x,yy,10),(1.6,.6,5),'teal',.09)
        text_shape('SEA\nINN',(x,yy-.34,10.8),.65,'cream')
        for zz in (8.0,12.0):B.box((x,yy+.4,zz),(.15,1.2,.15),'steel',.025,1)
        # Drainpipe has real bends rather than floating isolated rods.
        B.tube([(w*.38,-d*.47,1),(w*.38,-d*.47,c['floors']*5.1-1),(w*.32,-d*.47,c['floors']*5.1-.5)],.1,'bark')
    bpy.data.objects.remove(old,do_unlink=True)
    obj=B.finish(c['name'],col);obj.parent=bpy.data.objects[c['root_object']]
    for field,val in [('asset_id',c['component_id']),('building_class','underwater'),('collision','none'),('interactive',False),('emission',False)]:obj[field]=val
    # Remove repeated coincident faces left where mirrored corner piers meet. UV and face materials preserved.
    bm=bmesh.new();bm.from_mesh(obj.data);seen=set();bad=[]
    for f in bm.faces:
        sig=tuple(sorted(tuple(round(v,4) for v in q.co) for q in f.verts))
        if sig in seen:bad.append(f)
        else:seen.add(sig)
    if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
    bm.to_mesh(obj.data);bm.free()
    lo=[min(v.co[i] for v in obj.data.vertices) for i in range(3)];hi=[max(v.co[i] for v in obj.data.vertices) for i in range(3)]
    shift=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
    for v in obj.data.vertices:v.co-=shift
    obj.data.update();obj.data.calc_loop_triangles()
    c.update(objects=[c['root_object'],obj.name],bounds_size_m=[hi[i]-lo[i] for i in range(3)],triangles=len(obj.data.loop_triangles),polygons=len(obj.data.polygons),material_roles=sorted({obj.data.materials[f.material_index].name for f in obj.data.polygons}))
# Diverse inward-facing blocks outside the central no-build rectangle and existing facilities.
newlots=[
 ('electronics_shop',-33,-51,180,0,0,'inner_south_retail_alley'),
 ('canal_shell',-5,-59,180,0,0,'collapsed_side_of_alley'),
 ('coffee_steps',51,-61,180,0,0,'south_east_shop_court'),
 ('low_foundation',73,-57,0,0,0,'ruined_court_near_supply'),
 ('cutaway_tenement',-33,57,0,0,0,'inner_north_lane'),
 ('roof_garden_shell',-10,55,0,0,0,'inner_north_small_shop'),
 ('workshop_shell',12,18,0,0,0,'DO_NOT_PLACE_CENTRAL'),
]
# Never place the explicit example in central exclusion; it documents the omission rather than hiding it.
newlots=[n for n in newlots if n[6]!='DO_NOT_PLACE_CENTRAL']
# Existing original lots moved where a new alley needs space; one shop was sitting over the main roadway.
movements={'electronics_shop_instance_001':(-85,-106),'canal_shell_instance_001':(63,-106),'cinema_ruin_instance_001':(104,-105),'workshop_shell_instance_003':(108,-16)}
for name,(x,y) in movements.items():
    o=bpy.data.objects.get(name)
    if o:o.location.x=x;o.location.y=y
for key,x,y,yaw,rx,ry,role in newlots:
    c=bykey[key];count=sum(o.instance_type=='COLLECTION' and o.instance_collection and o.instance_collection.name==c['collection'] for o in S.objects)
    o=bpy.data.objects.new(f'{key}_instance_{count+1:03}',None);o.instance_type='COLLECTION';o.instance_collection=bpy.data.collections[c['collection']]
    bpy.data.collections['建筑_独立实例'].objects.link(o);o.location=(x,y,-61.3);o.rotation_euler=[math.radians(a) for a in (rx,ry,yaw)]
    o['asset_id']=c['component_id'];o['building_class']='underwater';o['collision']='none';o['interactive']=False;o['urban_role']=role
# Record instance matrices anew and reset terrain contact for selected tilted buildings after facade repair.
inst=[]
for o in S.objects:
    if o.instance_type!='COLLECTION' or o.instance_collection is None:continue
    c=next(c for c in CAT if c['collection']==o.instance_collection.name)
    if c['category']=='architecture':
        mesh=next(q for q in o.instance_collection.objects if q.type=='MESH');rot=o.rotation_euler.to_matrix()
        low=min((rot@v.co).z for v in mesh.data.vertices);o.location.z=-61.3-low
    inst.append(dict(instance_id=o.name,key=c['key'],component_id=c['component_id'],position_m=list(o.location),rotation_euler_deg=[round(math.degrees(a),6) for a in o.rotation_euler],scale=list(o.scale),source_object=o.name,urban_role=o.get('urban_role','street_support')))
for c in CAT:c['instance_count']=sum(a['key']==c['key'] for a in inst)
for pc in P['components']:pc['instance_count']=bykey[pc['key']]['instance_count']
P['instances']=inst;P['revision']='r4_facade_overlap_fixed_inner_street_blocks'
(D/'component_catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':CAT},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'floor_contract':P['floor_contract'],'instances':inst},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Reposition closeup cameras to the feature, no more claiming a tower-occluded frame shows the tram.
for name,pos,target,scale in [
 ('相机_电车街近景',(-155,-87,-6),(-91,-47,-47),80),
 ('相机_咖啡楼近景',(-139,-159,-16),(-106,-104,-48),58),
 ('相机_运河街近景',(-15,2,14),(-64,11,-40),112),
]:
    cam=bpy.data.objects[name];cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
for key,fp in floor_fps.items():
    c=bykey[key];o=next(o for o in bpy.data.collections[c['collection']].objects if o.type=='MESH')
    assert hashlib.sha256(str([tuple(v.co) for v in o.data.vertices]).encode()).hexdigest()==fp,'Floor changed '+key
S['plan_sha256']=hashlib.sha256((D/'component_plan.json').read_bytes()).hexdigest()
bpy.ops.wm.save_as_mainfile(filepath=str(W/'sunken_city_working.blend'),compress=True)
print('REFINED',len(CAT),'components',len(inst),'instances',sum(c['instance_count'] for c in CAT if c['category']=='architecture'),'buildings; floor locked')

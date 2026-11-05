"""Live v003: continuous two-terrace relief and reusable curved/disconnected tram viaduct.
No scene reset; source components stay independently editable. Never writes v001/v002.
"""
import ast,bpy,bmesh,hashlib,json,math,os,random
from pathlib import Path
from array import array
from mathutils import Euler,Matrix,Vector
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/sunken_city/v002';D=OLD.parent/'v003';W=R.parent/'sea-work/sunken_city/v003'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));OLD_CAT=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components']
assert P['status']=='frozen_before_geometry' and len(P['components'])==50
assert (W/'pre_terrain_bridge_session.blend').exists()
assert not (D/'sunken_city_v003.blend').exists()
S=bpy.data.scenes.get('沉没旧城_完整参考布局_v003') or bpy.data.scenes['沉没旧城_完整参考布局_v002']
if bpy.context.window:bpy.context.window.scene=S
MA=bpy.data.collections['01_制作组件_单栋与街段'];STAGE=bpy.data.collections['90_展示与验收_不导出']
# Record BEFORE state including any user changes since v002 was saved; restore it on candidate retry.
def sig(me):
    h=hashlib.sha256()
    for data,field,typ,n in [(me.vertices,'co','f',3),(me.loops,'vertex_index','i',1),(me.polygons,'material_index','i',1),(me.uv_layers['PaletteUV'].data,'uv','f',2)]:
        buf=array(typ,[0])*(len(data)*n);data.foreach_get(field,buf);h.update(buf.tobytes())
    return h.hexdigest()
lockpath=W/'terrain_scope_lock.json'
if not lockpath.exists():
    lock={'instances':{o.name:[list(row) for row in o.matrix_world] for o in S.objects if o.instance_type=='COLLECTION'},
          'geometry':{c['key']:sig(next(o for o in bpy.data.collections[c['collection']].objects if o.type=='MESH').data) for c in OLD_CAT},
          'terrain_changed_keys':['street_intact','plaza_tile','canal_segment','canal_end'],
          'source_sha256':P['previous_source_sha256']}
    lockpath.write_text(json.dumps(lock,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
else:
    lock=json.loads(lockpath.read_text(encoding='utf-8'))
    # Restoring is candidate-local only; v002 on disk was never touched.
    for o in list(bpy.data.objects):
        if o.get('revision_owner')=='sunken_city_v003':bpy.data.objects.remove(o,do_unlink=True)
    for col in list(bpy.data.collections):
        if col.get('revision_owner')=='sunken_city_v003':bpy.data.collections.remove(col)
    for name,m in lock['instances'].items():
        if bpy.data.objects.get(name):bpy.data.objects[name].matrix_world=Matrix(m)
# Replace v003 candidates' changed definitions from the saved v002 library if retried.
for key in ('street_intact','street_split','plaza_tile','canal_segment'):
    c=next(c for c in OLD_CAT if c['key']==key);col=bpy.data.collections[c['collection']]
    # Use mesh data from the unchanged external package. Object names remain stable.
    obj=next(o for o in col.objects if o.type=='MESH')
    with bpy.data.libraries.load(str(R/c['component_blend']),link=False) as (src,dst):dst.meshes=[obj.data.name] if obj.data.name in src.meshes else src.meshes[:1]
    obj.data=dst.meshes[0]
    for index,mat in enumerate(list(obj.data.materials)):
        obj.data.materials[index]=bpy.data.materials[mat.name.split('.')[0]]
# Remove only unused copies introduced by appending the unchanged terrain mesh definitions.
for mat in list(bpy.data.materials):
    if mat.users==0:bpy.data.materials.remove(mat)
for img in list(bpy.data.images):
    if img.users==0 and img.name not in ('Render Result','Viewer Node'):bpy.data.images.remove(img)
# Retrieve compatible geometry primitives only, no top-level startup/run code.
mod=ast.parse(Path(__file__).with_name('build.py').read_text(encoding='utf-8'))
keep=[n for n in mod.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ('box_template','Builder')]
exec(compile(ast.Module(body=keep,type_ignores=[]),'terrain_geometry_primitives','exec'),globals())
CUBE_F=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)];CACHE={}
MATS=[bpy.data.materials[n] for n in ('SEA_Matte','SEA_Metal','SEA_Gloss')]
CELLS={c['name']:c for c in json.loads((R/P['palette']).with_suffix('.json').read_text(encoding='utf-8'))['cells']}
CAT=[dict(c) for c in OLD_CAT if c['key'] not in ('t_junction','canal_end')]
C={c['key']:c for c in CAT}
def component(c,b):
    col=bpy.data.collections.new(c['component_id']+'_'+c['name']);MA.children.link(col);col['revision_owner']='sunken_city_v003'
    o=b.finish(c['name'],col);o['revision_owner']='sunken_city_v003'
    root=bpy.data.objects.new(c['component_id']+'_ROOT',None);col.objects.link(root);root['revision_owner']='sunken_city_v003';o.parent=root
    for ob in (o,root):ob['asset_id']=c['component_id'];ob['building_class']='underwater';ob['collision']='none';ob['interactive']=False;ob['emission']=False
    col.instance_offset=(0,0,0)
    lo=[min(v.co[i] for v in o.data.vertices) for i in range(3)];hi=[max(v.co[i] for v in o.data.vertices) for i in range(3)];shift=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]))
    for v in o.data.vertices:v.co-=shift
    o.data.update()
    row=dict(c,collection=col.name,root_object=root.name,objects=[root.name,o.name],local_origin=[0,0,0],palette=P['palette'],collision_owner='none_pure_scenery',dependencies=[],authored_origin_shift=list(shift))
    CAT.append(row);C[c['key']]=row;return o,shift
# A sloped full-24m plaza/road transition, with a thick real wedge rather than disconnected tilted plates.
B=Builder();N=12
for j in range(N):
    x0=-12+j*2;x1=x0+2;z0=.6+(x0+12)*.2;z1=.6+(x1+12)*.2
    # Thin continuous top skin and solid side faces. Interior panels share boundaries exactly.
    v=[(x0,-12,0),(x1,-12,0),(x1,12,0),(x0,12,0),(x0,-12,z0),(x1,-12,z1),(x1,12,z1),(x0,12,z0)]
    fs=[f for index,f in enumerate(CUBE_F) if not(index==3 and j<N-1) and not(index==5 and j>0)]
    B.geo(v,fs,'stone')
    # Broad tile seams preserve a visible direction without a noisy sculpted landscape.
    for y in (-9,-3,3,9):B.box(((x0+x1)/2,y,(z0+z1)/2+.015),(1.97,5.97,.025),'plaster',.008,rot=(0,-math.atan(.2),0))
obj,ramp_shift=component(next(c for c in P['components'] if c['key']=='terrain_ramp'),B)
# Variable slope must preserve the original paving top exactly, thus use a dedicated reusable module.
# Existing ramp strips cross roads at y=+-84: overlay markings are kept as part of this module's broad paving,
# rather than deforming a copied road mesh per slot. Curbs are interrupted only at these authored plazas.
# One shared canal family is warped along its local Y (instances face +/-90, two ends separately rotate).
canal_warps={}
for key in ('canal_segment',):
    c=C[key];o=next(o for o in bpy.data.collections[c['collection']].objects if o.type=='MESH')
    # All instances occupy the west -72..-48 ramp strip. Original local y becomes negative world x at +90yaw.
    # Store both endpoint orientations explicitly for the canal ends below.
    for v in o.data.vertices:v.co.z+=.2*(v.co.y+12)
    low=min(v.co.z for v in o.data.vertices)
    for v in o.data.vertices:v.co.z-=low
    o.data.update();canal_warps[key]=low
# Shared untouched flat street/plaza masters remain original. Terrain shift is owned by instance, not copied mesh.
def H(x,y=0):
    if x<=-72:return 0.0
    if x<-48:return -(x+72)*.2
    if x<=24:return -4.8
    if x<48:return -4.8+(x-24)*.2
    return 0.0
# Map every logical tile to its exact profile segment. Slopes fall only in x=-60/+36 cells.
ground_keys={'street_intact','street_split','junction','t_junction','plaza_tile','canal_segment','canal_end'}
for o in list(S.objects):
    if o.instance_type!='COLLECTION':continue
    oldc=next((c for c in OLD_CAT if c['collection']==o.instance_collection.name),None)
    if not oldc:continue
    x,y,z=lock['instances'][o.name][0][3],lock['instances'][o.name][1][3],lock['instances'][o.name][2][3]
    if oldc['key'] in ground_keys:
        if abs(x+60)<.01 and oldc['key'] in ('canal_segment','canal_end'):
            # Shared canal_end originally reversed at the north cap. Replace by same yaw, routing the end cap
            # does not alter its symmetric cross-section; depth shift follows warped local Y.
            o.instance_collection=bpy.data.collections[C['canal_segment']['collection']]
            o.rotation_euler=(0,0,math.pi/2);o.location.z=-63.4-4.8+canal_warps['canal_segment']
        elif abs(x+60)<.01 or abs(x-36)<.01:
            o.instance_collection=bpy.data.collections[C['terrain_ramp']['collection']]
            o.rotation_euler=(0,0,math.pi if x<0 else 0)
            o.location.z=-66.7
            o['terrain_role']='slope_transition'
        else:
            o.location.z=z+H(x,y)
        o['terrain_reference_xy']=[x,y]
    elif oldc['key'] not in ('viaduct_intact','viaduct_broken','stair_link','tram_wreck'):
        # Rigid geometry, touch local surface based on the lowest footprint band; never distort the building.
        o.location.z=z
        bpy.context.view_layer.update()
        mesh=next(q for q in o.instance_collection.objects if q.type=='MESH');rot=o.rotation_euler.to_matrix()
        pts=[o.matrix_world@v.co for v in mesh.data.vertices]
        minz=min(p.z for p in pts);support=[p for p in pts if p.z<minz+.28]
        # Minimum support terrain height guarantees at least one actual base contact, no corner floating.
        dz=min(H(p.x,p.y) for p in support) if support else H(x,y)
        o.location.z=z+dz;o['terrain_height_shift_m']=dz
# Existing bridge track axis is X and deck top=-50.8. First two intact spans stay, terminal fractured piece moves
# to the authored curve break below. Original line is NOT duplicated elsewhere.
oldbroken=bpy.data.objects['viaduct_broken_instance_001']
oldbroken.hide_render=True;oldbroken.hide_viewport=True;oldbroken['v003_retired_layout_instance']=True
# Create a 45-degree reusable arc with exact radial connector end faces, rail ribbons and terrain-reaching piers.
B=Builder();rad=26;phi=math.pi/4;steps=24;deckz=16.3
# local start (0,0), tangent +X, left centre(0,R)
def pt(t,lateral=0,z=deckz):return ((rad+lateral)*math.sin(t),rad-(rad+lateral)*math.cos(t),z)
for j in range(steps):
    a=j*phi/steps;b=(j+1)*phi/steps
    vs=[pt(a,-4.5,deckz-.5),pt(b,-4.5,deckz-.5),pt(b,4.5,deckz-.5),pt(a,4.5,deckz-.5),pt(a,-4.5,deckz),pt(b,-4.5,deckz),pt(b,4.5,deckz),pt(a,4.5,deckz)]
    spanfaces=[f for index,f in enumerate(CUBE_F) if not(index==3 and j<steps-1) and not(index==5 and j>0)]
    B.geo(vs,spanfaces,'stone')
    # True thin rail ribbons follow the curve, no straight chord skipping its centre.
    for offset in (-1.1,1.1):
        vs=[pt(a,offset-.065,deckz+.10),pt(b,offset-.065,deckz+.10),pt(b,offset+.065,deckz+.10),pt(a,offset+.065,deckz+.10),pt(a,offset-.065,deckz+.25),pt(b,offset-.065,deckz+.25),pt(b,offset+.065,deckz+.25),pt(a,offset+.065,deckz+.25)]
        B.geo(vs,spanfaces,'steel',1)
for j in range(12):
    t=j*phi/11;c=pt(t,0,deckz+.035);B.box(c,(.32,3.4,.12),'wood_dark',.025,rot=(0,0,t))
for lateral in (-4.25,4.25):
    B.tube([pt(j*phi/steps,lateral,deckz+1.0) for j in range(steps+1)],.07,'steel')
    for j in range(0,steps+1,3):
        t=j*phi/steps;B.tube([pt(t,lateral,deckz),pt(t,lateral,deckz+1)],.05,'steel',1,6)
for t in (.18,.60):
    px,py,_=pt(t)
    B.box((px,py,8),(1.3,1.8,16),'plaster',.095,rot=(0,0,t))
curve,curve_shift=component(next(c for c in P['components'] if c['key']=='viaduct_curve'),B)
# Deck connectors are geometric points in the centred curve collection, independent of source world position.
C['viaduct_curve']['connector_local']={'start':list(Vector(pt(0,0,deckz))-curve_shift),'end':list(Vector(pt(phi,0,deckz))-curve_shift),'tangent_start_deg':0,'tangent_end_deg':45,'span_m':rad*phi}
rail=[]
def add(key,loc,yaw,name=None,role='rail_extension'):
    c=C[key];o=bpy.data.objects.new(name or f'V3_{key}_{len(rail):03}',None);o.instance_type='COLLECTION';o.instance_collection=bpy.data.collections[c['collection']]
    bpy.data.collections['街道_逐段拼接实例' if c['category']=='ground' else '设施车辆_独立实例'].objects.link(o)
    o.location=loc;o.rotation_euler.z=yaw;o['revision_owner']='sunken_city_v003';o['asset_id']=c['component_id'];o['building_class']='underwater';o['collision']='none';o['interactive']=False;o['urban_role']=role
    return o
p=Vector((-78,-48,-50.8));heading=0;connectors=[];tramspots=[];gap=None
# Original last intact span overlaps the new bend; keep definition, retire only that old layout instance.
if bpy.data.objects.get('viaduct_intact_instance_002'):bpy.data.objects.remove(bpy.data.objects['viaduct_intact_instance_002'],do_unlink=True)
for i,cmd in enumerate(P['rail_extension']['commands']):
    kind=cmd['kind'];start=p.copy();headstart=heading
    if kind=='curve':
        left=cmd['turn']=='left';endheading=heading+(phi if left else -phi)
        if left:
            yaw=heading;local_start=Vector(C['viaduct_curve']['connector_local']['start']);local_end=Vector(C['viaduct_curve']['connector_local']['end']);rot=Matrix.Rotation(yaw,3,'Z')
            loc=p-rot@local_start;p=loc+rot@local_end
        else:
            # Traverse the same undirected 45degree left curve backwards, preserving physical rails and profile.
            yaw=endheading+math.pi;rot=Matrix.Rotation(yaw,3,'Z');local_end=Vector(C['viaduct_curve']['connector_local']['end']);local_start=Vector(C['viaduct_curve']['connector_local']['start'])
            loc=p-rot@local_end;p=loc+rot@local_start
        o=add('viaduct_curve',loc,yaw);heading=endheading
        rail.append(dict(name=o.name,key='viaduct_curve',start=list(start),end=list(p),heading_start_deg=math.degrees(headstart),heading_end_deg=math.degrees(heading)))
    elif kind in ('straight','broken'):
        length=cmd.get('length_m',20);key='viaduct_broken' if kind=='broken' else 'viaduct_intact'
        yaw=heading;rot=Matrix.Rotation(yaw,3,'Z');mid=p+Vector((math.cos(heading)*length/2,math.sin(heading)*length/2,0))
        # The 12m connector segment uses same geometry only via length scale along its tangent. All normal
        # segments remain unit scale; structural cross-section and deck height never change.
        o=add(key,(mid.x,mid.y,-61.3),yaw)
        if length!=20:o.scale.x=length/20;o['length_scale_authorized']=True
        p+=Vector((math.cos(heading)*length,math.sin(heading)*length,0))
        rail.append(dict(name=o.name,key=key,start=list(start),end=list(p),heading_start_deg=math.degrees(heading),heading_end_deg=math.degrees(heading)))
        if kind=='straight':tramspots.append((mid.copy(),heading,length))
    else:
        p+=Vector((math.cos(heading)*cmd['length_m'],math.sin(heading)*cmd['length_m'],0));gap=dict(start=list(start),end=list(p),length_m=cmd['length_m'])
# Additional two old trams, touch the track plane. Original tram remains on original span.
for n,(mid,yaw,length) in enumerate(tramspots[:2]):
    c=C['tram_wreck'];col=bpy.data.collections[c['collection']];mesh=next(o for o in col.objects if o.type=='MESH')
    ob=add('tram_wreck',(mid.x,mid.y,-50.55),yaw,f'V3_TRAM_ADDITION_{n+1:02}','tram_on_track');ob['track_tangent_deg']=math.degrees(yaw)
    rail.append({'name':ob.name,'key':'tram_wreck','mid':list(mid),'heading_deg':math.degrees(yaw)})
# Broad concrete fragments and exposed rebar beneath the gap, not a hidden continuous deck.
for n,t in enumerate((.2,.5,.8)):
    x=gap['start'][0]*(1-t)+gap['end'][0]*t;y=gap['start'][1]*(1-t)+gap['end'][1]*t
    o=add('rubble_cluster',(x,y,-61.3+H(x,y)),.4+n*.7,role='broken_bridge_fall_debris')
    rail.append({'name':o.name,'key':'rubble_cluster','fracture_debris':True})
# Grounded pier extensions for existing straight modules: keep upper bridge silhouettes, extend lower column
# bottoms only in each span definition. Shared straight piers reach the deepest courtyard terrace.
# Extend the original master piers below z=0 to -4.8, then recenter; account for anchor shift in every instance.
for key in ('viaduct_intact','viaduct_broken'):
    c=C[key];o=next(q for q in bpy.data.collections[c['collection']].objects if q.type=='MESH');me=o.data
    if not o.get('v3_pier_extended'):
        for v in me.vertices:
            # Only lower half columns; do not stretch track deck/rails.
            if v.co.z<1.1:v.co.z-=4.8*(1-v.co.z/1.1)
        for v in me.vertices:v.co.z+=4.8
        o['v3_pier_extended']=True
        for ob in S.objects:
            if ob.instance_type=='COLLECTION' and ob.instance_collection==bpy.data.collections[c['collection']]:ob.location.z-=4.8
        me.update()
# Retired definitions retained on disk, not smuggled into current scene/budget.
for key in ('t_junction','canal_end'):
    c=next(c for c in OLD_CAT if c['key']==key);col=bpy.data.collections.get(c['collection'])
    if col:
        for ob in list(col.objects):bpy.data.objects.remove(ob,do_unlink=True)
        bpy.data.collections.remove(col)
# Remove the hidden old broken layout instance: the definition remains used at the new break.
if bpy.data.objects.get('viaduct_broken_instance_001'):bpy.data.objects.remove(bpy.data.objects['viaduct_broken_instance_001'],do_unlink=True)
# Update canonical mesh metadata and package paths.
for c in CAT:
    o=next(q for q in bpy.data.collections[c['collection']].objects if q.type=='MESH');me=o.data;me.update();me.calc_loop_triangles()
    lo=[min(v.co[i] for v in me.vertices) for i in range(3)];hi=[max(v.co[i] for v in me.vertices) for i in range(3)]
    c.update(version='v003',component_blend=f'art_source/scenes/sunken_city/v003/component_packages/{c["key"]}/{c["key"]}.blend',bounds_size_m=[hi[i]-lo[i] for i in range(3)],triangles=len(me.loop_triangles),polygons=len(me.polygons),material_roles=sorted({me.materials[f.material_index].name for f in me.polygons}))
    c.pop('source_sha256',None);c.pop('geometry_fingerprint',None)
bpy.context.view_layer.update();inst=[]
for o in S.objects:
    if o.instance_type!='COLLECTION' or o.instance_collection is None:continue
    c=next(c for c in CAT if c['collection']==o.instance_collection.name)
    inst.append(dict(instance_id=o.name,key=c['key'],component_id=c['component_id'],position_m=list(o.location),rotation_euler_deg=[round(math.degrees(a),6) for a in o.rotation_euler],scale=list(o.scale),source_object=o.name,urban_role=o.get('urban_role','inherited'),detail_zone=o.get('detail_zone',''),terrain_height_shift_m=o.get('terrain_height_shift_m',0)))
for c in CAT:c['instance_count']=sum(a['key']==c['key'] for a in inst)
for pc in P['components']:pc['instance_count']=C[pc['key']]['instance_count']
P['instances']=inst;P['rail_extension']['actual_segments']=rail;P['rail_extension']['actual_gap']=gap
P['scope_lock']['v003_override']='terrain/bridge changes authorized by latest user: all ground elevations may change, intact rigid building geometry and XY remain; central supports/track authorized by drawn red route'
S.name='沉没旧城_完整参考布局_v003';S['version']='v003';S['plan_sha256']=hashlib.sha256(json.dumps(P,ensure_ascii=False).encode()).hexdigest()
for f,v in [('component_plan.json',P),('component_catalog.json',{'schema':'sea.component_catalog','components':CAT}),('component_instances.json',{'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'terrain_contract':P['terrain_contract'],'instances':inst})]:(D/f).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_tree.txt').write_text('\n'.join(c['component_id']+' '+c['name'] for c in CAT)+'\n',encoding='utf-8')
# Separate inspection camera targeted to the new curve and missing span.
for name,pos,target,scale in [('相机_坡地断桥_全景',(205,-250,150),(0,0,-39),365),('相机_坡地断桥_近景',(73,-126,2),(3,-30,-54),145),('相机_坡地_剖向',(170,-20,-20),(0,0,-61),265)]:
    if bpy.data.objects.get(name):continue
    data=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,data);STAGE.objects.link(o);o['revision_owner']='sunken_city_v003';o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=scale
bpy.ops.wm.save_as_mainfile(filepath=str(W/'sunken_city_v003_working.blend'),compress=True)
print('V003_TERRAIN_BRIDGE',len(CAT),'components',len(inst),'instances',len(rail),'rail records','gap',gap)

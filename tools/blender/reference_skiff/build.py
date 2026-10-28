"""Author only the new skiff source. Never regenerates a pre-existing Godot scene."""
import bpy, bmesh, hashlib, json, math, os, sys
from pathlib import Path
from mathutils import Vector, Matrix
R=Path(__file__).resolve().parents[3]; D=R/'art_source/scenes/reference_skiff/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'reference_skiff_v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert P['status']=='frozen_before_geometry' and sha(D/'reference.png')==P['reference_sha256']
if (D/'reference_skiff.blend').exists():raise RuntimeError('Do not overwrite an authored source; use a new version')
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.context.preferences.filepaths.save_version=0
S=bpy.context.scene; S.name='黄白木船_参考装配'; S.unit_settings.system='METRIC'
L=bpy.data.scenes.new('船体与固定设施_组件母版'); L.unit_settings.system='METRIC'
MA=bpy.data.collections.new('船体结构_母版'); MF=bpy.data.collections.new('固定设施_母版')
L.collection.children.link(MA);L.collection.children.link(MF)
ASM=bpy.data.collections.new('船体与设施_组件实例');S.collection.children.link(ASM)
ST=bpy.data.collections.new('展示支持_不导出');S.collection.children.link(ST)
palette=R/P['palette'];img=bpy.data.images.load(str(palette));img.name='SEA_公共方格色板';img.colorspace_settings.name='sRGB'
cells={c['name']:c for c in json.loads(palette.with_suffix('.json').read_text())['cells']}
materials={}
for role,rough,metal in [('Matte',.72,0),('Metal',.32,.55),('Gloss',.26,.05)]:
    m=bpy.data.materials.new('SEA_'+role);m.use_nodes=True;n=m.node_tree.nodes;n.clear()
    p=n.new('ShaderNodeBsdfPrincipled');p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
    t=n.new('ShaderNodeTexImage');t.image=img;t.interpolation='Closest'
    uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';out=n.new('ShaderNodeOutputMaterial')
    for a,b in [(uv.outputs['UV'],t.inputs['Vector']),(t.outputs['Color'],p.inputs['Base Color']),(p.outputs[0],out.inputs[0])]:m.node_tree.links.new(a,b)
    materials[role]=m
components={}; records=[];current=None
def activate(o):
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
def finish(o,name,color,role='Matte',bevel=0,smooth=False):
    o.name=name
    for c in list(o.users_collection):c.objects.unlink(o)
    current.objects.link(o);bpy.context.window.scene=L;activate(o);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        m=o.modifiers.new('真实柔和倒角','BEVEL');m.width=bevel;m.segments=3;m.limit_method='ANGLE'
        bpy.ops.object.modifier_apply(modifier=m.name)
    for f in o.data.polygons:f.use_smooth=smooth
    if bevel:
        m=o.modifiers.new('保留平面的加权法线','WEIGHTED_NORMAL');m.keep_sharp=True
        try:bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError:o.modifiers.remove(m)
    o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4);o.data.materials.clear();o.data.materials.append(materials[role])
    for u in list(o.data.uv_layers):o.data.uv_layers.remove(u)
    uv=o.data.uv_layers.new(name='PaletteUV');uv.active_render=True;c=cells[color];cx=(c['column']+.5)/8;cy=1-(c['row']+.5)/8
    for f in o.data.polygons:
        for i,li in enumerate(f.loop_indices):uv.data[li].uv=(cx+.025*math.cos(math.tau*i/len(f.loop_indices)),cy+.025*math.sin(math.tau*i/len(f.loop_indices)))
    o['palette_color']=color;o['hard_edge']='real_bevel' if bevel else 'authored_curvature';return o
def box(name,loc,size,col,bevel=.025,role='Matte',rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.dimensions=size;o.rotation_euler=rot;return finish(o,name,col,role,bevel)
def sphere(name,loc,size,col):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=loc);o=bpy.context.object;o.scale=Vector(size)*.5;return finish(o,name,col,smooth=True)
def tube(name,pts,radius,col,role='Matte',resolution=8):
    cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=1;cu.bevel_depth=radius;cu.bevel_resolution=2
    sp=cu.splines.new('POLY');sp.points.add(len(pts)-1)
    for p,v in zip(sp.points,pts):p.co=(*v,1)
    ob=bpy.data.objects.new(name,cu);bpy.context.scene.collection.objects.link(ob);activate(ob);bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,name,col,role,smooth=True)
def mesh(name,vs,fs,col,bevel=0,smooth=False):
    me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new(name,me);S.collection.objects.link(o)
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    return finish(o,name,col,bevel=bevel,smooth=smooth)
def start(key):
    global current
    item=next(e for e in P['components'] if e['key']==key);current=bpy.data.collections.new(item['asset_id']);components[key]=current
    (MA if item['category']=='structure' else MF).children.link(current)
def bounds(col):
    vs=[o.matrix_world@v.co for o in col.all_objects if o.type=='MESH' for v in o.data.vertices]
    return {'min':[min(v[i] for v in vs) for i in range(3)],'max':[max(v[i] for v in vs) for i in range(3)]}
offsets={}
def end(key):
    col=components[key];b=bounds(col);off=Vector(((b['min'][0]+b['max'][0])*.5,(b['min'][1]+b['max'][1])*.5,b['min'][2]));offsets[key]=off
    for o in col.all_objects:o.data.transform(Matrix.Translation(-off))
    col.instance_offset=(0,0,0)
def inst(key,loc=(0,0,0),rot=(0,0,0),scale=(1,1,1),absolute=False,name=None):
    # Geometry recipes use assembled coordinates; account for their normalized bottom-center origin.
    from mathutils import Euler
    o=bpy.data.objects.new(name or key+'_%03d'%len(records),None);ASM.objects.link(o);o.instance_type='COLLECTION';o.instance_collection=components[key]
    o.rotation_euler=rot;o.scale=scale;o.location=Vector(loc) if absolute else Vector(loc)+Euler(rot).to_matrix()@(offsets[key]*Vector(scale))
    aid=next(c['asset_id'] for c in P['components'] if c['key']==key);o['asset_id']=aid
    records.append(dict(instance_id='boat/'+o.name,key=key,asset_id=aid,position=list(o.location),rotation_euler_xyz=list(rot),scale=list(scale)))
    return o
# A lofted solid shell with separate inner lining, sole and gunwale. Rounded outline
# preserves the open interior instead of hiding a box inside a boat silhouette.
stations=[(-2.46,.95),(-2.25,1.08),(-1.75,1.18),(-1.0,1.25),(0,1.287),(1,1.18),(1.8,.91),(2.4,.53),(2.75,.24),(2.936,.018)]
path=[]
for (y0,w0),(y1,w1) in zip(stations,stations[1:]):
    for j in range(4):
        t=j/4;path.append((w0+(w1-w0)*t,y0+(y1-y0)*t))
path.append((.018,2.936));path+= [(-x,y) for x,y in reversed(path)]
N=len(path)
def sheer(y):return .66+.15*((y+2.46)/5.396)**3+.035*max(0,(-y-1.4))
def loft(name,rings,col,bevel=.012):
    vs=[p for ring in rings for p in ring];fs=[]
    for k in range(len(rings)-1):
        for j in range(N):fs.append((k*N+j,k*N+(j+1)%N,(k+1)*N+(j+1)%N,(k+1)*N+j))
    return mesh(name,vs,fs,col,bevel)
start('hull')
outer_bottom=[(x*.38,y*.89,-.2056+.06*abs(y)/2.94) for x,y in path]
outer_chine=[(x*.76,y*.96,.04+.06*max(0,y)/2.94) for x,y in path]
outer_top=[(x*.963,y,sheer(y)-.045) for x,y in path]
loft('金黄外壳',[outer_bottom,outer_chine,outer_top],'gold',.018)
inner_top=[(x*.85,y*.97,sheer(y)-.045) for x,y in path]
inner_low=[(x*.62,y*.88,.12) for x,y in path]
loft('暖木内舷',[outer_top,inner_top,inner_low],'wood_light',.012)
mesh('完整船底',outer_bottom,[tuple(range(N))],'ochre',.018)
mesh('内舱底面',inner_low,[tuple(reversed(range(N)))],'wood_mid',.012)
end('hull')
start('gunwale')
# Outer white rail, golden interior strip and low cream waterline stripe.
for ratio0,ratio1,drop,col,name in [(1,.905,.105,'cream','奶白厚舷边'),(.905,.85,.065,'yellow','金黄内舷')]:
    a=[(x*ratio0,y,sheer(y)+.045) for x,y in path];b=[(x*ratio1,y*.982,sheer(y)+.035) for x,y in path]
    c=[(x*ratio1,y*.982,sheer(y)-drop) for x,y in path];d=[(x*ratio0,y,sheer(y)-drop) for x,y in path]
    loft(name,[a,b,c,d,a],col,.014)
loft('下缘奶白压条',[[(x*.78,y*.961,.065) for x,y in path],[(x*.80,y*.968,.125) for x,y in path]],'cream',.008)
end('gunwale')
# Precisely normalize the combined envelope to the measured legacy hull.
target=P['dimensions']['legacy_hull_godot'];tmin=Vector((target['min'][0],-target['max'][2],target['min'][1]));tmax=Vector((target['max'][0],-target['min'][2],target['max'][1]))
pts=[v.co+offsets[k] for k in ['hull','gunwale'] for o in components[k].all_objects for v in o.data.vertices]
mn=Vector([min(p[i] for p in pts) for i in range(3)]);mx=Vector([max(p[i] for p in pts) for i in range(3)])
fit=Vector([(tmax[i]-tmin[i])/(mx[i]-mn[i]) for i in range(3)])
for k in ['hull','gunwale']:
    for o in components[k].all_objects:
        for v in o.data.vertices:v.co=(v.co+offsets[k]-mn)*fit+tmin
    end(k);inst(k)
start('floor_board');box('宽厚木底板',(0,0,.165),(1.73,.225,.075),'wood_light',.025);end('floor_board')
for j in range(17):
    y=-1.96+j*.235;sc=.90 if y>1.4 else (1.0 if y>-.9 else 1.02)
    inst('floor_board',(0,y,0),scale=(sc,1,1))
start('bench')
box('座板前条',(0,-.135,.535),(2.02,.255,.135),'wood_light',.035)
box('座板后条',(0,.135,.535),(2.02,.255,.135),'honey',.035)
for x in [-.76,.76]:box('座板横档',(x,0,.415),(.13,.44,.14),'wood_mid',.02)
end('bench')
for y,sc in [(-1.50,1.0),(-.15,1.04),(1.40,.85)]:inst('bench',(0,y,0),scale=(sc,1,1))
start('rib');box('内侧木肋',(0,0,.38),(.105,.12,.55),'wood_mid',.025,rot=(0,.27,0));end('rib')
for y,x in [(-1.8,.87),(-.9,.92),(0,.94),(.9,.85),(1.8,.61)]:
    for side in [-1,1]:inst('rib',(side*x,y,.105),rot=(0,0,math.pi if side<0 else 0),absolute=True)
start('outboard')
box('船外机夹座',(0,0,.29),(.47,.26,.32),'steel',.055,'Metal')
box('灰紫机身',(0,-.20,.60),(.64,.60,.45),'lilac',.10,'Gloss')
box('奶白圆角机盖',(0,-.20,.83),(.73,.66,.24),'snow',.10,'Gloss')
box('深灰盖缝',(0,-.21,.708),(.68,.63,.045),'slate',.014)
box('舷外机竖腿',(0,-.32,.015),(.17,.19,.70),'steel',.045,'Metal')
box('防空蚀板',(0,-.34,-.30),(.41,.38,.055),'silver',.02,'Metal')
box('螺旋桨轴',(0,-.43,-.38),(.12,.24,.12),'slate',.035,'Metal')
for a in [0,math.tau/3,2*math.tau/3]:
    box('螺旋桨叶',(.13*math.cos(a),-.54,-.38+.13*math.sin(a)),(.28,.045,.09),'lightgray',.025,'Metal',rot=(0,-a,0))
for x in [-.20,.20]:box('机盖通风口',(x,-.18,.957),(.10,.23,.012),'gray',.008)
box('机身金色铭牌',(0,-.516,.61),(.18,.012,.10),'gold',.02)
tube('转向手柄',[(.28,.02,.64),(.52,.17,.62),(.65,.48,.61)],.035,'rubber')
end('outboard');inst('outboard',(0,-2.38,.17))
start('luggage')
box('绿色帆布包',(0,0,.22),(.55,.44,.44),'sage',.105)
box('翻盖',(0,0,.437),(.57,.46,.14),'moss_light',.06)
for x in [-.18,.18]:
    box('浅棕捆带',(x,-.228,.26),(.075,.025,.34),'wood_mid',.012)
    box('上部捆带',(x,0,.513),(.075,.40,.018),'wood_mid',.008)
    box('黄铜扣',(x,-.246,.32),(.105,.025,.10),'gold',.012,'Metal')
tube('包提手',[(-.10,0,.51),(-.10,0,.62),(.10,0,.62),(.10,0,.51)],.025,'forest');end('luggage');inst('luggage',(.44,.74,.20),rot=(0,0,-.18))
start('fender');sphere('饱满防撞浮球',(0,0,.19),(.25,.22,.44),'moss_light')
tube('挂绳',[(0,0,.40),(0,0,.60),(-.05,0,.72)],.018,'sand');end('fender')
for side,y in [(-1,-1.0),(1,.8)]:inst('fender',(side*1.255,y,.0),absolute=True)
start('oar')
tube('圆木桨杆',[(-.43,0,.075),(1.70,0,.075)],.044,'wood_mid')
tube('奶白握柄',[(-.55,0,.075),(-.24,0,.075)],.056,'wood_edge')
vs=[]
outline=[(1.53,-.075),(1.75,-.18),(2.38,-.23),(2.57,-.14),(2.62,0),(2.57,.14),(2.38,.23),(1.75,.18),(1.53,.075)]
for z in [.04,.105]:vs.extend((x,y,z) for x,y in outline)
n=len(outline);fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
mesh('宽厚圆角桨叶',vs,fs,'honey',.025)
box('桨叶木筋',(2.10,0,.115),(.76,.045,.018),'wood_light',.008);end('oar')
for side in [-1,1]:
    # Inward handle and outward blade; runtime rotates wrapper, leaving asset root normalized.
    a=0 if side==1 else math.pi
    inst('oar',(side*1.10,-.10,.68),rot=(0,0,a),absolute=False,name='OarRVisual' if side==1 else 'OarLVisual')
start('oarlock')
box('金属桨座',(0,0,.035),(.19,.20,.07),'silver',.025,'Metal')
tube('U形桨叉',[(-.075,0,.06),(-.075,0,.22),(.075,0,.22),(.075,0,.06)],.025,'steel','Metal');end('oarlock')
for side in [-1,1]:inst('oarlock',(side*1.10,-.10,.66),absolute=True)
start('cleat');box('系缆底座',(0,0,.03),(.18,.13,.06),'ochre',.02,'Metal')
tube('系缆羊角',[(-.13,0,.12),(.13,0,.12)],.035,'gold','Metal');end('cleat')
for x,y in [(-.72,-2.24),(.72,-2.24),(.10,2.68)]:inst('cleat',(x,y,.73),absolute=True)
start('rope_coil')
pts=[]
for j in range(145):
    t=j/144;ang=t*math.tau*3;rad=.105+.08*t;pts.append((rad*math.cos(ang),rad*.76*math.sin(ang),.027+t*.024))
tube('三圈缆绳',pts,.018,'sand');end('rope_coil');inst('rope_coil',(-.50,-1.52,.61),absolute=True)
# Studio supports are never exported.
bpy.context.window.scene=S
world=bpy.data.worlds.new('奶蓝摄影棚');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.22,.34,.40,1);world.node_tree.nodes['Background'].inputs[1].default_value=.6;S.world=world
def support_obj(o):
    for c in list(o.users_collection):c.objects.unlink(o)
    ST.objects.link(o)
for name,loc,power,size in [('柔和主光',(-4,-4,8),950,5),('船头轮廓光',(4,5,6),750,4),('暖色补光',(-4,3,4),300,4)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,.1))-o.location).to_track_quat('-Z','Y').to_euler();support_obj(o)
bpy.ops.object.camera_add(location=(8,-10,11));cam=bpy.context.object;cam.name='参考镜头';cam.data.type='ORTHO';cam.data.ortho_scale=9.3;cam.rotation_euler=(Vector((0,0,.25))-cam.location).to_track_quat('-Z','Y').to_euler();support_obj(cam);S.camera=cam
S.render.engine='CYCLES';S.cycles.samples=32;S.cycles.use_denoising=True;S.render.resolution_x=1100;S.render.resolution_y=1100;S.render.resolution_percentage=100
S.render.image_settings.file_format='PNG';S.view_settings.view_transform='AgX';S.render.film_transparent=False
S['reference_sha256']=P['reference_sha256'];S['source_only_support']='Cameras and lamps excluded from component exports'
items=[]
for e in P['components']:
    key=e['key'];col=components[key];geo=hashlib.sha256()
    for o in col.all_objects:
        geo.update(o.data.name.encode());geo.update(str([list(v.co) for v in o.data.vertices]).encode());geo.update(str([list(f.vertices) for f in o.data.polygons]).encode())
    items.append({**e, 'collection':col.name, 'bounds':bounds(col), 'origin':[0,0,0], 'front_axis':'+Y', 'instance_count':sum(r['key']==key for r in records), 'material_roles':sorted({m.name for o in col.all_objects for m in o.data.materials}), 'geometry_fingerprint':geo.hexdigest(), 'collision_responsibility':'Boat/WaterNavigation; no collision exported'})
write(D/'catalog.json',dict(schema='sea.scene_catalog',components=items))
write(D/'component_instances.json',dict(schema='sea.component_instances',plane='Blender XY',up='+Z',rotation='Euler XYZ radians',godot_mapping='(x,y,z)->(x,z,-y)',runtime_placement_owner='godot/scenes/props/reference_skiff.tscn',instances=records))
img.filepath=bpy.path.relpath(str(palette),start=str(D))
bpy.ops.wm.save_as_mainfile(filepath=str(D/'reference_skiff.blend'),compress=True)
for e in items:
    key=e['key'];pkg=D/'component_packages'/key;pkg.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(D/'reference_skiff.blend'))
    sc=bpy.data.scenes.new('独立组件_'+key);sc.collection.children.link(bpy.data.collections[e['collection']]);sc.world=bpy.data.worlds['奶蓝摄影棚']
    bpy.context.window.scene=sc
    for other in list(bpy.data.scenes):
        if other!=sc:bpy.data.scenes.remove(other)
    bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
    path=pkg/(key+'.blend');bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
    manifest=dict(asset_id=e['asset_id'],asset_ledger='assets/registry/ledgers/scenes.json#'+e['asset_id'],version='v001',source=path.relative_to(R).as_posix(),source_sha256=sha(path),component=e,reference_sha256=P['reference_sha256'],license=P['reference_license'],stage='source_created_pending_reopen_validation')
    write(pkg/'asset_manifest.json',manifest)
# Make the sole source image external and portable after all saves.
assert sha(palette)==P['palette_sha256']
print('SKIFF_SOURCE_CREATED',len(items),'components',len(records),'instances',flush=True)

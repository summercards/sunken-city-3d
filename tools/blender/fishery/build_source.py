"""Author only the frozen wild-fishery kit; never open/overwrite legacy sources."""
import bpy,math,json,hashlib,os,random
from pathlib import Path
from mathutils import Vector,Matrix
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/wild_fishery/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'wild_fishery/v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
assert P['status']=='frozen_before_geometry' and not (D/'wild_fishery.blend').exists()
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
for path,digest in P['protected_files'].items():assert sha(R/path)==digest
random.seed(1102);bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
S=bpy.context.scene;S.name='野外渔场_v001';S.unit_settings.system='METRIC'
LIB=bpy.data.scenes.new('组件母版_建筑花草水域');LIB.unit_settings.system='METRIC'
groups={}
for key,label in [('land','岸坪与渔具_实例'),('flora','花草圆石_实例'),('water','水下围网浮漂_实例'),('fish','水下鱼群_实例')]:
 c=bpy.data.collections.new(label);S.collection.children.link(c);groups[key]=c
pal=R/P['palette'];img=bpy.data.images.load(str(pal));img.filepath=str(pal)
cells={c['name']:c for c in json.loads(pal.with_suffix('.json').read_text(encoding='utf-8'))['cells']}
M={}
for role,rough,metal in [('Matte',.82,0),('Metal',.34,.45),('Gloss',.23,0),('Emission',.4,0)]:
 m=bpy.data.materials.new('SEA_'+role);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;n.clear()
 out=n.new('ShaderNodeOutputMaterial');bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 tx=n.new('ShaderNodeTexImage');tx.image=img;tx.interpolation='Closest';uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV'
 l.new(uv.outputs['UV'],tx.inputs['Vector']);l.new(tx.outputs['Color'],bs.inputs['Base Color']);l.new(bs.outputs[0],out.inputs['Surface'])
 if role=='Emission':l.new(tx.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=.3
 M[role]=m
COL=None
def uvmap(o):
 me=o.data
 for layer in list(me.uv_layers):me.uv_layers.remove(layer)
 uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True;me.uv_layers.active_index=0
 c=cells[o['palette_cell']];u=(c['column']+.5)/8;v=1-(c['row']+.5)/8
 for f in me.polygons:
  for j,li in enumerate(f.loop_indices):
   a=math.tau*j/len(f.loop_indices);uv.data[li].uv=(u+.026*math.cos(a),v+.026*math.sin(a))
def finish(o,name,color,role='Matte',bevel=0,smooth=False):
 o.name=name
 for c in list(o.users_collection):c.objects.unlink(o)
 COL.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True)
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 if bevel:
  mod=o.modifiers.new('实体软倒角','BEVEL');mod.width=bevel;mod.segments=3;mod.harden_normals=True
  bpy.ops.object.modifier_apply(modifier=mod.name)
 for f in o.data.polygons:f.use_smooth=smooth
 o.data.materials.clear();o.data.materials.append(M[role]);o['palette_cell']=color;o['material_role']=role
 uvmap(o);o.select_set(False);return o
def box(n,p,d,c='wood_light',bev=.06,rot=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.scale=d
 if rot:o.rotation_euler=rot
 return finish(o,n,c,bevel=bev)
def sphere(n,p,s,c='stone',seg=16,rings=8):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,location=p);o=bpy.context.object;o.scale=s
 return finish(o,n,c,smooth=True)
def cyl(n,p,r,h,c='wood_mid',verts=12,rot=None,bev=.03):
 bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=h,location=p);o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,c,bevel=bev,smooth=True)
def rod(n,a,b,r=.04,c='sand',verts=8,bev=0):
 a=Vector(a);b=Vector(b);bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=(b-a).length,location=(a+b)/2)
 o=bpy.context.object;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
 return finish(o,n,c,bevel=bev,smooth=True)
def tube(n,points,r,c='sand',sides=2):
 cu=bpy.data.curves.new(n,'CURVE');cu.dimensions='3D';cu.resolution_u=1;cu.bevel_depth=r;cu.bevel_resolution=sides;cu.use_fill_caps=True
 sp=cu.splines.new('POLY');sp.points.add(len(points)-1)
 for p,co in zip(sp.points,points):p.co=(*co,1)
 ob=bpy.data.objects.new(n,cu);S.collection.objects.link(ob);bpy.context.view_layer.objects.active=ob;ob.select_set(True)
 bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,n,c,smooth=True)
def torus(n,p,r,thick,c='wood_edge',rot=None):
 bpy.ops.mesh.primitive_torus_add(major_segments=24,minor_segments=8,location=p,major_radius=r,minor_radius=thick)
 o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,c,smooth=True)
def rounded_slab(n,w,d,h,r,color,z=0):
 outline=[]
 for cx,cy,start in [(w/2-r,d/2-r,0),(-w/2+r,d/2-r,90),(-w/2+r,-d/2+r,180),(w/2-r,-d/2+r,270)]:
  for j in range(7):
   a=math.radians(start+j*90/6);outline.append((cx+r*math.cos(a),cy+r*math.sin(a)))
 count=len(outline);vs=[(x,y,z) for x,y in outline]+[(x,y,z+h) for x,y in outline]
 faces=[tuple(reversed(range(count))),tuple(range(count,count*2))]
 for i in range(count):j=(i+1)%count;faces.append((i,j,j+count,i+count))
 me=bpy.data.meshes.new(n);me.from_pydata(vs,[],faces);me.update();ob=bpy.data.objects.new(n,me);S.collection.objects.link(ob)
 return finish(ob,n,color,bevel=.045)
def net(w):
 # Coarse geometric diamonds remain readable through the real sea shader.
 for k in range(-4,5):
  offset=k*.55
  for slope in [-1,1]:
   points=[]
   for x in [-w/2,w/2]:
    z=slope*(x+w/2)+offset
    if .08<=z<=2.12:points.append((x,0,z))
   for z in [.08,2.12]:
    x=(z-offset)/slope-w/2
    if -w/2<=x<=w/2:points.append((x,0,z))
   if len(points)>=2 and (Vector(points[0])-Vector(points[1])).length>.06:
    rod('粗网绳',points[0],points[1],.026,'petrol',6)
 for x in [-w/2+.04,w/2-.04]:rod('边绳',(x,0,.055),(x,0,2.15),.038,'jade',8)
 tube('浮绳',[(w*(j/8-.5),0,2.15-.055*math.sin(math.pi*j/8)) for j in range(9)],.05,'sand',1)
 rod('沉绳',(-w/2+.04,0,.055),(w/2-.04,0,.055),.04,'forest',8)
 for x in [-w*.35,w*.35]:sphere('圆沉子',(x,0,.11),(.09,.07,.11),'slate',12,6)
def fish_parts():
 sphere('饱满鱼身',(0,.03,.18),(.16,.32,.18),'aqua',20,10)
 sphere('奶白鱼腹',(0,.05,.125),(.145,.255,.105),'cream',16,8)
 # Soft triangular fan tail; no bones or gameplay contract in this ambient mesh.
 for side in [-1,1]:sphere('圆尾鳍',(side*.09,-.30,.18),(.12,.15,.10),'teal',12,6)
 sphere('背鳍',(0,-.025,.31),(.045,.14,.08),'seafoam',12,6)
 for side in [-1,1]:
  sphere('侧鳍',(side*.16,.015,.17),(.09,.13,.035),'seafoam',12,6)
  sphere('深色眼',(side*.123,.245,.22),(.036,.035,.039),'deepblue',12,6)
  sphere('眼高光',(side*.139,.263,.235),(.011,.012,.012),'snow',8,4)
catalog=[];masters={}
for e in P['components']:
 key=e['key'];COL=bpy.data.collections.new(e['asset_id']);S.collection.children.link(COL)
 if key=='shore':
  rounded_slab('自然岸坪',6.3400993347,5.3,.30,.42,'stone')
  rounded_slab('沙土表层',6.22,5.18,.07,.43,'sand',.29)
 elif key=='turf':
  sphere('苔草软垫',(0,0,.07),(.46,.32,.07),'moss')
  for i in range(5):
   a=i*2.4;sphere('胖叶片',(.25*math.cos(a),.18*math.sin(a),.10),(.18,.10,.065),'moss_light' if i%2 else 'sage',12,6)
 elif key=='pebbles':
  for i,(x,y,r) in enumerate([(-.22,0,.23),(.18,.06,.19),(0,-.18,.14)]):sphere('圆河石',(x,y,r*.52),(r,r*.78,r*.58),'stone' if i%2 else 'lightgray',16,8)
 elif key=='reeds':
  for i in range(3):
   x=(i-1)*.15;y=math.sin(i*2)*.12;h=.70+i*.09
   rod('芦苇圆茎',(x,y,0),(x+.025,y,h),.028,'forest',8)
   sphere('厚蒲棒',(x+.025,y,h),(.075,.075,.17),'wood_mid',12,8)
   for side in [-1,1]:tube('弯叶',[(x,y,.07),(x+side*.16,y+.03,.30),(x+side*.24,y+.05,.55)],.045,'moss',2)
 elif key=='drying_rack':
  for x in [-.65,.65]:cyl('浑厚木柱',(x,0,.78),.105,1.56,'wood_mid',16,bev=.045)
  rod('圆晾梁',(-.82,0,1.52),(.82,0,1.52),.11,'wood_edge',16,.03)
  for i in range(3):
   x=(i-1)*.42;rod('挂绳',(x,0,1.48),(x,0,1.12),.022,'sand',8)
   sphere('胖晒鱼',(x,0,.89),(.12,.075,.27),'cream' if i%2 else 'seafoam',16,8)
   sphere('晒鱼尾鳍',(x+.065,0,.65),(.10,.05,.08),'aqua',12,6)
  for x in [-.65,.65]:box('厚底座',(x,0,.07),(.40,.42,.14),'wood_dark',.06)
 elif key=='creel':
  cyl('圆鱼篓',(0,0,.30),.34,.60,'wood_mid',24,bev=.11)
  torus('厚口沿',(0,0,.59),.30,.065,'wood_edge')
  cyl('暗篓口',(0,0,.585),.25,.025,'darkwood',24,bev=.008)
  for h in [.18,.38]:torus('宽编绳',(0,0,h),.335,.028,'wood_edge')
  tube('圆把手',[(.26*math.cos(a),0,.60+.28*math.sin(a)) for a in [j*math.pi/12 for j in range(13)]],.045,'wood_edge')
 elif key=='bait_table':
  for x in [-.39,.39]:
   for y in [-.22,.22]:box('工作台腿',(x,y,.34),(.15,.15,.68),'wood_mid',.045)
  box('饵料台面',(0,0,.70),(1.08,.72,.16),'seafoam',.075)
  cyl('饵料罐',(.20,.02,.93),.16,.34,'ochre',16,bev=.06)
  cyl('奶油罐盖',(.20,.02,1.10),.18,.07,'cream',16,bev=.025)
  box('暖木案板',(-.24,-.02,.815),(.38,.44,.055),'wood_edge',.025)
 elif key in ['buoy','marker_buoy']:
  sphere('圆肚浮漂',(0,0,.31),(.31,.31,.31),'coral',20,12)
  cyl('奶油色腰带',(0,0,.31),.315,.18,'cream',24,bev=.045)
  cyl('上系绳柱',(0,0,.64),.06,.17,'wood_mid',12,bev=.025)
  if key=='marker_buoy':
   cyl('短旗杆',(0,0,.99),.045,.65,'wood_edge',12,bev=.018)
   box('圆角标记旗',(.20,0,1.18),(.46,.06,.29),'butter',.045)
 elif key in ['net_panel','net_corner']:net(2.0 if key=='net_panel' else math.sqrt(2))
 elif key=='fish':fish_parts()
 meshes=[o for o in COL.objects if o.type=='MESH'];coords=[v.co.copy() for o in meshes for v in o.data.vertices]
 lo=Vector([min(v[k] for v in coords) for k in range(3)]);hi=Vector([max(v[k] for v in coords) for k in range(3)])
 shift=Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z))
 root=bpy.data.objects.new('Root',None);COL.objects.link(root);root['asset_id']=e['asset_id']
 for o in meshes:o.data.transform(Matrix.Translation(shift));o.parent=root
 COL.instance_offset=(0,0,0);root['component_key']=key
 tris=0;polys=0
 for o in meshes:o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons)
 xyz=[v.co for o in meshes for v in o.data.vertices]
 bounds={'min':[min(v[k] for v in xyz) for k in range(3)],'max':[max(v[k] for v in xyz) for k in range(3)]}
 row=dict(e,collection=COL.name,root='Root',bounds=bounds,triangles=tris,polygons=polys)
 # Root names must remain identical across separately exportable packages.
 root.name=e['asset_id']+'_Root';row['root']=root.name
 pkg=D/'component_packages'/key;pkg.mkdir(parents=True,exist_ok=True)
 bpy.data.libraries.write(str(pkg/(key+'.blend')),{COL},fake_user=True,compress=True)
 row['component_blend']=(pkg/(key+'.blend')).relative_to(R).as_posix();row['source_sha256']=sha(pkg/(key+'.blend'))
 catalog.append(row);masters[key]=COL;S.collection.children.unlink(COL);LIB.collection.children.link(COL)
def instance(key,world,angle=0,group='land',tag=None,scale=1):
 col=masters[key];o=bpy.data.objects.new((tag or key)+'_%03d'%len(instances),None);o.instance_type='COLLECTION';o.instance_collection=col
 o.location=(world[0]-ORIGIN[0],-(world[2]-ORIGIN[2]),world[1]-ORIGIN[1]);o.rotation_euler.z=angle;o.scale=(scale,)*3;groups[group].objects.link(o)
 o['component_key']=key;instances.append({'instance_id':o.name,'key':key,'position_godot_world':world,'position_blender':list(o.location),'yaw_radians':angle,'scale':scale,'group':group})
ORIGIN=P['dimensions_assumption']['island_center'];instances=[]
height=lambda k:next(c['bounds']['max'][2] for c in catalog if c['key']==k)
instance('shore',[ORIGIN[0],1.33-height('shore'),ORIGIN[2]])
instance('drying_rack',[-15.15,1.33,11.10],.13)
instance('bait_table',[-10.65,1.33,14.15],-.12)
for pos in [[-15.30,1.33,14.55],[-14.57,1.33,14.80]]:instance('creel',pos,.1)
for x,z in [(-15.7,10.7),(-14.8,10.6),(-10.4,10.8),(-10.4,14.9),(-15.65,14.9),(-13.8,15.0),(-15.7,12.8)]:instance('turf',[x,1.30,z],random.uniform(-2,2),'flora')
for x,z in [(-15.8,11.9),(-15.8,14.45),(-10.30,10.65),(-11.50,15.0),(-13.9,10.5)]:instance('pebbles',[x,1.30,z],random.uniform(-2,2),'flora')
for x,z in [(-15.65,10.75),(-10.4,10.7),(-15.6,14.9)]:instance('reeds',[x,1.31,z],random.uniform(-2,2),'flora')
outline=[(-24.2,15.8),(-14.2,15.8),(-13.2,16.8),(-13.2,24.8),(-14.2,25.8),(-24.2,25.8),(-25.2,24.8),(-25.2,16.8)]
buoy_points=[]
for i,a in enumerate(outline):
 b=outline[(i+1)%len(outline)];dx=b[0]-a[0];dz=b[1]-a[1];length=math.hypot(dx,dz);diagonal=abs(dx)>0 and abs(dz)>0
 count=1 if diagonal else round(length/2);key='net_corner' if diagonal else 'net_panel';yaw=-math.atan2(dz,dx)
 for j in range(count):
  t=(j+.5)/count;instance(key,[a[0]+dx*t,.96-height(key),a[1]+dz*t],yaw,'water')
 for j in range(count):
  t=j/count;buoy_points.append((a[0]+dx*t,a[1]+dz*t,diagonal))
for index,(x,z,marker) in enumerate(buoy_points):instance('marker_buoy' if marker else 'buoy',[x,.89,z],0,'water','float')
for i in range(14):
 a=i*2.399963;rad=math.sqrt((i+.5)/14);x=-19.2+3.9*rad*math.cos(a);z=20.8+3.0*rad*math.sin(a)
 instance('fish',[x,.35,z],a,'fish','swimmer',.9+(i%4)*.10)
# Saved source presentation: sea-coloured floor lies below all net geometry.
display=bpy.data.collections.new('90_展示支持_不导出');S.collection.children.link(display)
bpy.ops.mesh.primitive_plane_add(size=200,location=(-5,-6,-3.6));floor=bpy.context.object;floor.name='DISPLAY_海底背景'
for c in list(floor.users_collection):c.objects.unlink(floor)
display.objects.link(floor);mat=bpy.data.materials.new('DISPLAY_蓝绿背景');mat.diffuse_color=(.035,.23,.28,1);mat.use_nodes=True;mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.035,.23,.28,1);mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.9;floor.data.materials.append(mat)
world=bpy.data.worlds.new('DISPLAY_柔光');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.48,.62,.70,1);world.node_tree.nodes['Background'].inputs[1].default_value=.65;S.world=world
for pos,energy,size in [((-8,-6,16),1900,12),((10,7,10),1100,10)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.data.energy=energy;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((-5,-5,0))-o.location).to_track_quat('-Z','Y').to_euler()
 for c in list(o.users_collection):c.objects.unlink(o)
 display.objects.link(o)
bpy.ops.object.camera_add(location=(-16,-20,22));cam=bpy.context.object;cam.name='DISPLAY_参考镜头';cam.data.type='ORTHO';cam.data.ortho_scale=24;S.camera=cam
for c in list(cam.users_collection):c.objects.unlink(cam)
display.objects.link(cam);cam.rotation_euler=(Vector((-5,-4,0))-cam.location).to_track_quat('-Z','Y').to_euler()
S.render.engine='CYCLES';S.cycles.samples=12;S.cycles.use_denoising=True;S.render.resolution_x=1100;S.render.resolution_y=850;S.render.resolution_percentage=100;S.view_settings.view_transform='AgX'
bpy.ops.wm.save_as_mainfile(filepath=str(D/'wild_fishery.blend'),compress=True)
def save(p,data):p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
save(D/'component_catalog.json',{'schema':'sea.scene.components','components':catalog})
save(D/'component_instances.json',{'plane':'Blender XY','up':'+Z','mapping':'(x,y,z)->(x,z,-y)','world_origin_godot':ORIGIN,'instances':instances,'pen_outline_godot_xz':outline})
for path,digest in P['protected_files'].items():assert sha(R/path)==digest
print('FISHERY_SOURCE_BUILT',len(catalog),'components',len(instances),'instances',flush=True)

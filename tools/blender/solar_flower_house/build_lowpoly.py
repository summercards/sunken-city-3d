"""Build the new sea solar flower house source only. Never writes runtime scenes.
Run with Blender --background --factory-startup --python this_file -- [--render]
Existing source refuses overwrite unless --replace-generated is supplied.
"""
import bpy, math, random, json, hashlib, os, sys
from pathlib import Path
from mathutils import Vector, Matrix
R=Path(__file__).resolve().parents[3]
D=R/'art_source/scenes/solar_flower_house/v002'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_flower_house_v002'
if R==W or R in W.parents: raise RuntimeError('SEA_WORK_ROOT must be outside repository')
W.mkdir(parents=True,exist_ok=True); (W/'previews').mkdir(exist_ok=True)
plan=json.loads((D/'component_plan.json').read_text())
assert plan['status']=='frozen_before_geometry' and len(plan['components'])<=50
OUT=D/'solar_flower_house.blend'
if OUT.exists() and '--replace-generated' not in sys.argv: raise RuntimeError('Existing source: use an explicit new version or --replace-generated for this generated candidate')
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(71)
scene=bpy.context.scene; scene.name='太阳能花屋_参考装配'
scene.unit_settings.system='METRIC'
lib=bpy.data.scenes.new('组件母版_建筑与花草')
lib.unit_settings.system='METRIC'
masters=bpy.data.collections.new('01_制作组件'); lib.collection.children.link(masters)
mb=bpy.data.collections.new('建筑_母版'); mf=bpy.data.collections.new('花草_母版'); masters.children.link(mb); masters.children.link(mf)
out=bpy.data.collections.new('02_参考装配_仅组件实例'); scene.collection.children.link(out)
building=bpy.data.collections.new('建筑_实例'); flora=bpy.data.collections.new('花草_实例'); out.children.link(building);out.children.link(flora)
support=bpy.data.collections.new('90_展示环境_不导出');scene.collection.children.link(support)
palette_path=R/'art_source/shared/palettes/sea_cozy_8x8_512.png'
img=bpy.data.images.load(str(palette_path));img.name='SEA_公共色板_8x8';img.colorspace_settings.name='sRGB'
cells={x['name']:x for x in json.loads(palette_path.with_suffix('.json').read_text())['cells']}
materials={}
for role,metal,rough in [('Matte',0,.72),('Metal',.65,.3),('Gloss',.1,.23),('Emission',0,.4)]:
 m=bpy.data.materials.new('SEA_'+role);m.use_nodes=True
 n=m.node_tree.nodes; n.clear();p=n.new('ShaderNodeBsdfPrincipled');p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 t=n.new('ShaderNodeTexImage');t.image=img;t.interpolation='Closest';t.extension='EXTEND'
 uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';o=n.new('ShaderNodeOutputMaterial')
 m.node_tree.links.new(uv.outputs['UV'],t.inputs['Vector']);m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color']);m.node_tree.links.new(p.outputs[0],o.inputs[0])
 if role=='Gloss':p.inputs['Coat Weight'].default_value=.25
 if role=='Emission':m.node_tree.links.new(t.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=.65
 materials[role]=m
current=None; components={}; records=[]
def activate(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o

def finish(o,name,color='cream',role='Matte',bevel=0,smooth=True):
 o.name=name
 for c in list(o.users_collection):c.objects.unlink(o)
 current.objects.link(o)
 # The working collection is temporarily linked to the active scene.
 activate(o)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('低面数实体倒角','BEVEL');mod.width=bevel;mod.segments=1
  bpy.ops.object.modifier_apply(modifier=mod.name)
 for p in o.data.polygons:p.use_smooth=smooth
 if bevel:
  mod=o.modifiers.new('平面加权法线','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=50
  try:bpy.ops.object.modifier_apply(modifier=mod.name)
  except RuntimeError:o.modifiers.remove(mod)
 o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
 o.data.materials.clear();o.data.materials.append(materials[role])
 for old_uv in list(o.data.uv_layers):o.data.uv_layers.remove(old_uv)
 uv=o.data.uv_layers.new(name='PaletteUV');uv.active_render=True
 cell=cells[color];cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
 for p in o.data.polygons:
  count=len(p.loop_indices)
  for k,li in enumerate(p.loop_indices):
   a=2*math.pi*k/count;uv.data[li].uv=(cx+.022*math.cos(a),cy+.022*math.sin(a))
 o['palette_color']=color;o['soft_edge']='beveled_single_segment' if bevel else 'curved_surface'
 return o

def box(n,loc,size,col='cream',bev=.04,role='Matte',rot=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=size
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,bev)
def uvball(n,loc,scale,col='leaf',role='Matte',rot=None):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,location=loc);o=bpy.context.object;o.scale=scale
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role)
def cyl(n,loc,radius,depth,col='wood',role='Matte',rot=None,vertices=32,r2=None):
 bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius,radius2=radius if r2 is None else r2,depth=depth,location=loc)
 o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,min(.025,radius*.13))
def torus(n,loc,major,minor,col='wood',rot=None,role='Matte'):
 bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=12,location=loc,major_radius=major,minor_radius=minor)
 o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role)
def line(n,pts,r=.025,col='wood',role='Matte'):
 curve=bpy.data.curves.new(n,'CURVE');curve.dimensions='3D';curve.resolution_u=16;curve.bevel_depth=r;curve.bevel_resolution=3
 sp=curve.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for p,co in zip(sp.bezier_points,pts):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
 o=bpy.data.objects.new(n,curve);scene.collection.objects.link(o);activate(o);bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,n,col,role)
def mesh(n,verts,faces,col,bev=0):
 me=bpy.data.meshes.new(n);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(n,me);scene.collection.objects.link(o);return finish(o,n,col,bevel=bev)
def leaf(n,base,tip,width,col):
 base=Vector(base);tip=Vector(tip);d=tip-base;side=d.cross(Vector((0,0,1))).normalized()
 if side.length<.1:side=Vector((1,0,0))
 v=[]
 for i in range(9):
  t=i/8;c=base+d*t+Vector((0,0,math.sin(t*math.pi)*d.length*.16));w=max(.006,math.sin(math.pi*t)**.85*width)
  v.extend([tuple(c-side*w),tuple(c+Vector((0,0,w*.22))),tuple(c+side*w)])
 faces=[]
 for i in range(8):
  for j in range(2):a=i*3+j;faces.append((a,a+3,a+4,a+1))
 o=mesh(n,v,faces,col);activate(o)
 mod=o.modifiers.new('叶片厚度','SOLIDIFY');mod.thickness=.012;bpy.ops.object.modifier_apply(modifier=mod.name)
 # Remap UV after solidify so rim faces also have nonzero islands.
 return finish(o,n,col)
def start(slug):
 global current
 item=next(c for c in plan['components'] if c['slug']==slug)
 current=bpy.data.collections.new(item['component_id']);(mf if item['category']=='flora' else mb).children.link(current);scene.collection.children.link(current)
 current['component_id']=item['component_id'];current['category']=item['category'];current.instance_offset=(0,0,0)
 return current

def end(slug):
 global current
 objs=list(current.objects)
 assert objs
 # Normalize each finished package to bottom center; bake every object transform.
 verts=[o.matrix_world@v.co for o in objs for v in o.data.vertices]
 lo=Vector(tuple(min(v[i] for v in verts) for i in range(3)));hi=Vector(tuple(max(v[i] for v in verts) for i in range(3)))
 anchor=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in objs:o.data.transform(Matrix.Translation(-anchor))
 # Consolidate nonemissive surfaces, keep the luminous mesh separate.
 final=[]
 groups={e:[o for o in objs if any(m.name=='SEA_Emission' for m in o.data.materials)==e] for e in [False,True]}
 for emissive,group in groups.items():
  if not group:continue
  bpy.ops.object.select_all(action='DESELECT')
  for o in group:o.select_set(True)
  bpy.context.view_layer.objects.active=group[0];
  if len(group)>1:bpy.ops.object.join()
  o=bpy.context.object
  o.name=slug+('_emissive' if emissive else '_body');o.data.name=o.name+'_mesh';o['soft_edges']='lowpoly_bevel_and_weighted_normals';final.append(o)
 root=bpy.data.objects.new('ROOT_'+slug,None);current.objects.link(root)
 for o in final:o.parent=root
 components[slug]={'collection':current,'anchor':anchor,'bounds':list(hi-lo),'meshes':final}
 scene.collection.children.unlink(current)

def inst(slug,loc=(0,0,0),rot=(0,0,0),scale=1):
 c=components[slug];o=bpy.data.objects.new(slug+'_instance',None);o.instance_type='COLLECTION';o.instance_collection=c['collection']
 (flora if c['collection']['category']=='flora' else building).objects.link(o)
 o.rotation_euler=rot;o.scale=(scale,)*3;o.location=Vector(loc)+o.rotation_euler.to_matrix()@(c['anchor']*scale)
 item=next(x for x in plan['components'] if x['slug']==slug)
 o['component_id']=item['component_id']
 records.append({'component_id':item['component_id'],'instance_id':o.name,'position_m':list(o.location),'rotation_euler_xyz_rad':list(o.rotation_euler),'scale':list(o.scale),'source_object':o.name})
 return o
pi=math.pi
# New deliberately authored low-poly geometry; no automatic decimation of v001.
def poly_tube(n,points,r,col,sides=4,cap=True):
 pts=[Vector(p) for p in points];verts=[]
 for i,p in enumerate(pts):
  tangent=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized();axis=tangent.cross(Vector((0,0,1)))
  if axis.length<.01:axis=tangent.cross(Vector((0,1,0)))
  axis.normalize();other=tangent.cross(axis).normalized()
  for j in range(sides):a=2*math.pi*j/sides;verts.append(tuple(p+r*(math.cos(a)*axis+math.sin(a)*other)))
 faces=[(i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j) for i in range(len(pts)-1) for j in range(sides)]
 if cap:faces.extend([tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))])
 return mesh(n,verts,faces,col)
def low_cyl(n,loc,r,h,col,segments=6):
 return poly_tube(n,[(loc[0],loc[1],loc[2]-h/2),(loc[0],loc[1],loc[2]+h/2)],r,col,segments)
def ring(n,loc,r,t,col,segments=8):
 verts=[]
 for i in range(segments):
  a=2*math.pi*i/segments
  for j in range(4):
   b=2*math.pi*j/4;verts.append((loc[0]+(r+t*math.cos(b))*math.sin(a),loc[1]+t*math.sin(b),loc[2]+(r+t*math.cos(b))*math.cos(a)))
 faces=[(i*4+j,i*4+(j+1)%4,((i+1)%segments)*4+(j+1)%4,((i+1)%segments)*4+j) for i in range(segments) for j in range(4)]
 return mesh(n,verts,faces,col)
def plump(n,base,tip,width,depth,col,shape='diamond'):
 b=Vector(base);t=Vector(tip);axis=t-b;side=axis.cross(Vector((0,0,1))).normalized()
 if side.length<.1:side=Vector((1,0,0))
 up=side.cross(axis).normalized()
 if shape=='full':
  verts=[tuple(b),tuple(t)]
  for at,thickness in [(.26,.86),(.72,.82)]:
   c=b+axis*at
   for j in range(4):a=2*math.pi*j/4;verts.append(tuple(c+side*width*thickness*math.cos(a)+up*depth*math.sin(a)))
  faces=[(0,2+j,2+(j+1)%4) for j in range(4)]+[(1,6+(j+1)%4,6+j) for j in range(4)]+[(2+j,6+j,6+(j+1)%4,2+(j+1)%4) for j in range(4)]
 else:
  sides=6 if shape=='round' else 4;c=b+axis*.48;verts=[tuple(b),tuple(t)]
  for j in range(sides):a=2*math.pi*j/sides;verts.append(tuple(c+side*width*math.cos(a)+up*depth*math.sin(a)))
  faces=[(end,2+j,2+(j+1)%sides) if end==0 else (end,2+(j+1)%sides,2+j) for end in [0,1] for j in range(sides)]
 return mesh(n,verts,faces,col)
def plane(n,pts,col):return mesh(n,pts,[tuple(range(len(pts)))],col)
# Large silhouette surfaces receive actual chamfers; small trim is removed.
start('foundation');box('整体圆角木平台',(0,0,0),(8.6,8.2,.25),'wood',.10);end('foundation')
start('deck_plank');plane('宽木板顶面',[(-.347,-4.01,0),(.347,-4.01,0),(.347,4.01,0),(-.347,4.01,0)],'wood_light');end('deck_plank')
start('pier');box('简约圆角墩柱',(0,0,.8),(.72,.72,1.6),'sand',.10);end('pier')
start('wall_shell')
for x in [-2.28,2.28]:box('圆角侧墙',(x,.65,1.37),(.24,3.6,2.74),'cream',.09)
box('背墙',(0,2.32,1.37),(4.38,.22,2.74),'cream',0)
# Front door gap is genuine geometry; the circular window is a shallow external inset.
box('入口墙体',(-1.06,-1.05,1.37),(2.45,.24,2.74),'cream',.065)
box('门垛',(2.0,-1.05,1.37),(.55,.24,2.74),'cream',.065)
box('门楣',(.96,-1.05,2.43),(1.55,.24,.62),'cream',0)
end('wall_shell')
start('roof_terrace');box('圆角屋顶',(0,.65,0),(4.98,3.84,.22),'wood_light',.08);end('roof_terrace')
start('solar_panel')
outline=[(-.665,-.765),(.665,-.765),(.71,-.72),(.71,.72),(.665,.765),(-.665,.765),(-.71,.72),(-.71,-.72)]
v=[(x,y,z) for z in [-.06,.06] for x,y in outline]
f=[tuple(reversed(range(8))),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
frame=mesh('斜角太阳能白框',v,f,'snow');activate(frame);mod=frame.modifiers.new('白框加权法线','WEIGHTED_NORMAL');bpy.ops.object.modifier_apply(modifier=mod.name)
plane('蓝色光伏面',[(-.625,-.68,.061),(.625,-.68,.061),(.625,.68,.061),(-.625,.68,.061)],'solar')
# A few broad grid lines preserve recognition at the intended camera scale.
for x in [-.21,.21]:plane('简化电池分格',[(x-.008,-.68,.063),(x+.008,-.68,.063),(x+.008,.68,.063),(x-.008,.68,.063)],'sky')
for y in [-.23,.23]:plane('简化电池分格',[(-.625,y-.008,.063),(.625,y-.008,.063),(.625,y+.008,.063),(-.625,y+.008,.063)],'sky')
end('solar_panel')
start('roof_beam');box('屋架木梁',(0,0,0),(.16,3.8,.16),'wood',0);end('roof_beam')
start('ladder')
for x in [-.32,.32]:box('梯柱',(x,0,1.45),(.12,.12,2.9),'wood',0)
for z in [.3,.9,1.5,2.1,2.7]:box('梯阶',(0,-.02,z),(.69,.13,.09),'wood_light',0)
end('ladder')
start('door_arch')
pts=[(-.48,0,0),(.48,0,0),(.48,0,1.4),(.34,0,1.74),(0,0,1.9),(-.34,0,1.74),(-.48,0,1.4)]
o=plane('简化木拱门',pts,'wood_mid');o.data.polygons[0].use_smooth=False
poly_tube('圆润拱形门框',[(-.52,-.03,0),(-.52,-.03,1.4),(-.37,-.03,1.78),(0,-.03,1.96),(.37,-.03,1.78),(.52,-.03,1.4),(.52,-.03,0)],.055,'ochre',4)
plane('门窗',[(-.17,-.055,1.1),(.17,-.055,1.1),(.17,-.055,1.55),(-.17,-.055,1.55)],'deepblue');end('door_arch')
start('door_shutter');box('圆角青色门扇',(0,0,.95),(.63,.10,1.9),'teal',.055);end('door_shutter')
start('porthole');ring('圆窗', (0,0,0),.44,.07,'gold')
plane('蓝色圆窗玻璃',[(.43*math.sin(i*pi/4),.04,.43*math.cos(i*pi/4)) for i in range(8)],'deepblue')
plane('窗十字',[(-.025,-.071,-.41),(.025,-.071,-.41),(.025,-.071,.41),(-.025,-.071,.41)],'wood_edge')
plane('窗十字',[(-.41,-.071,-.025),(.41,-.071,-.025),(.41,-.071,.025),(-.41,-.071,.025)],'wood_edge');end('porthole')
start('awning')
for j in range(8):
 x=-1.0+j*.25;v=[]
 for y,z in [(0,0),(-.4,-.04),(-.9,-.28),(-.94,-.44)]:v.extend([(x,y,z),(x+.25,y,z)])
 mesh('柔软条纹棚',v,[(2*i,2*i+1,2*i+3,2*i+2) for i in range(3)],'yellow' if j%2 else 'butter')
end('awning')
start('shade_sail');v=[]
for j in range(3):
 for i in range(3):u=i/2;t=j/2;v.append(((u-.5)*1.6,(t-.5)*1.95,-.28*math.sin(pi*u)*math.sin(pi*t)+.18*t))
mesh('简约柔软帆布',v,[(j*3+i,j*3+i+1,j*3+i+4,j*3+i+3) for j in range(2) for i in range(2)],'butter');end('shade_sail')
start('post');low_cyl('圆木绳桩',(0,0,.45),.115,.9,'wood_mid',5);end('post')
start('sail_mast');low_cyl('细帆杆',(0,0,1.1),.07,2.2,'wood',6);end('sail_mast')
start('rope_span');poly_tube('简化垂绳',[(-1.4,0,0),(-.47,0,-.2),(.47,0,-.2),(1.4,0,0)],.032,'sand',3);end('rope_span')
start('tire');ring('软轮胎',(0,0,0),.34,.13,'rubber');poly_tube('轮胎吊绳',[(0,-.14,.0),(0,-.14,.65)],.02,'sand',3);end('tire')
start('lifebuoy');o=ring('救生圈',(0,0,0),.40,.10,'snow')
# Assign whole polygons to the alternate palette cell without introducing another material.
uv=o.data.uv_layers['PaletteUV'];cell=cells['coral'];cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
for f in o.data.polygons:
 if (f.index//4)%2==0:
  for k,li in enumerate(f.loop_indices):a=2*pi*k/len(f.loop_indices);uv.data[li].uv=(cx+.022*math.cos(a),cy+.022*math.sin(a))
end('lifebuoy')
start('lantern');box('灯芯_emissive',(0,0,.23),(.22,.22,.32),'butter',0,'Emission');low_cyl('灯顶',(0,0,.43),.19,.10,'wood_dark',4);end('lantern')
start('bench')
box('圆角座垫',(0,0,.54),(1.3,.56,.19),'aqua',.065)
box('圆角椅背',(0,.25,.87),(1.3,.13,.58),'wood_light',.05)
for x in [-.5,.5]:box('椅支腿',(x,0,.25),(.09,.4,.5),'wood',0)
end('bench')
start('planter_round');low_cyl('圆陶盆',(0,0,.24),.30,.48,'sand',6);end('planter_round')
start('boiler');low_cyl('蓝色小锅炉',(0,0,.45),.37,.90,'blue',8);low_cyl('奶白炉盖',(0,0,.93),.4,.08,'snow',8);poly_tube('烟管',[(.15,.05,.99),(.15,.05,1.53)],.05,'wood_dark',5);end('boiler')
start('rug');plane('地毯',[(-.7,-.42,0),(.7,-.42,0),(.7,.42,0),(-.7,.42,0)],'aqua');end('rug')
# Fuller foliage: few large thick almonds rather than dozens of small thin leaves.
start('leaf_cluster')
for a,z,c in [(0,.62,'leaf'),(2.1,.75,'lime'),(4.2,.60,'leaf_yellow')]:
 plump('饱满叶片',(0,0,0),(.60*math.cos(a),.60*math.sin(a),z),.32,.19,c,shape='full')
end('leaf_cluster')
start('vine')
for j in range(4):
 side=(-1)**j;plump('饱满垂叶',(0,0,-j*.27),(side*.27,-.04,-j*.27-.46),.23,.14,'leaf' if j%2 else 'lime',shape='round')
end('vine')
def blossom(slug,col):
 start(slug)
 # A single closed, puffy five-lobed flower head. Its volume survives the low triangle budget.
 verts=[]
 for i in range(20):a=2*pi*i/20;r=[.39,.34,.23,.34][i%4];verts.append((r*math.cos(a),r*math.sin(a),.12))
 verts.extend([(0,0,.27),(0,0,-.025)])
 faces=[(20,i,(i+1)%20) for i in range(20)]+[(21,(i+1)%20,i) for i in range(20)]
 mesh('饱满五瓣花',verts,faces,col)
 plump('金色花蕊',(0,0,.23),(0,0,.33),.085,.07,'gold')
 end(slug)
blossom('daisy','snow');blossom('cosmos','pink')
start('palm')
for i in range(5):
 a=i*2*pi/5;plump('简约厚棕榈叶',(0,0,.05),(math.cos(a)*1.05,math.sin(a)*1.05,.55+(i%2)*.28),.38,.18,'lime' if i%2 else 'leaf',shape='round')
end('palm')
# Assembled layout: house remains the same size, platform expands around it.
inst('foundation',(0,-.1,1.55))
for i in range(12):inst('deck_plank',(-3.85+i*.70,-.1,1.677))
for x in [-3.85,3.85]:
 for y in [-3.75,3.6]:inst('pier',(x,y,-.15))
inst('wall_shell',(0,.55,1.69));inst('roof_terrace',(0,.55,4.45))
slope=math.radians(31)
for x in [-1.53,0,1.53]:
 for y in [-.33,1.13]:inst('solar_panel',(x,y+.55,5.10+(y+.33)*math.tan(slope)),rot=(slope,0,0))
for x in [-2.3,2.3]:inst('roof_beam',(x,.95,5.52),rot=(slope,0,0))
inst('roof_beam',(0,2.57,6.47),rot=(0,0,pi/2),scale=1.25)
inst('door_arch',(-2.42,.99,1.70),rot=(0,0,-pi/2));inst('porthole',(-1.15,-.66,3.08))
inst('door_shutter',(1.72,-.84,1.70),rot=(0,0,.43));inst('awning',(.65,-.73,4.02))
inst('ladder',(2.31,-.85,1.7),rot=(-.08,0,0));inst('lifebuoy',(-2.43,-.15,3.0),rot=(0,0,-pi/2))
inst('shade_sail',(2.63,-1.57,3.98))
for y,z in [(-2.55,1.69),(-.59,1.87)]:inst('sail_mast',(3.41,y,z))
inst('bench',(-1.1,-1.4,1.7));inst('rug',(.8,-1.90,1.70));inst('boiler',(2.78,-1.95,1.70));inst('lantern',(0,2.57,6.57));inst('lantern',(-.23,-.78,3.1))
# Rail is only at the perimeter: a front strip 1.45 m deep remains free of props.
for x in [-4.12,-1.37,1.37,4.12]:inst('post',(x,-4.04,1.69))
for x in [-4.12,4.12]:
 for y in [-1.24,1.56]:inst('post',(x,y,1.69))
for x in [-2.75,0,2.75]:inst('rope_span',(x,-4.04,2.41))
for x in [-4.12,4.12]:
 for y in [-2.64,.16]:inst('rope_span',(x,y,2.41),rot=(0,0,pi/2))
for x in [-2.75,0,2.75]:inst('tire',(x,-4.24,1.14))
# Front of house has larger flowers but fewer groups, so circulation remains readable.
for x,y in [(-2.85,-.15),(1.94,-1.55)]:
 inst('planter_round',(x,y,1.69));inst('leaf_cluster',(x,y,2.15),scale=.75)
 inst('daisy' if x<0 else 'cosmos',(x,y,2.62),rot=(.35,0,.3),scale=.8)
# Roof garden uses six broad leaf groups plus a small number of large, thick blossoms.
for i,(x,y) in enumerate([(-2.1,-.64),(-1.25,-.64),(-.4,-.64),(1.95,-.64),(-2.40,1.15),(2.40,1.15)]):
 inst('leaf_cluster',(x,y,4.65),rot=(0,0,i*1.3),scale=.95)
 inst('daisy' if i%2==0 else 'cosmos',(x,y-.05,5.24),rot=(.25,-.25,i),scale=.95)
for x,y in [(-2.35,-.1),(2.35,.0),(-2.35,1.6)]:inst('vine',(x,y,4.85),rot=(0,0,-pi/2 if x<0 else pi/2),scale=.95)
inst('palm',(-1.45,2.6,6.20),rot=(0,0,.4))
# A single low-cost vine at each outer platform corner; no ground clutter.
for x,y in [(-4.10,-3.8),(4.10,3.65)]:inst('vine',(x,y,1.70),rot=(0,0,-pi/2 if x<0 else pi/2))
# Exact final budget includes EVERY repeated instance and triangulates evaluated topology.
counts={};total=0;polygons=0
for item in plan['components']:
 c=components[item['slug']];tris=0;polys=0
 for o in c['meshes']:o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons)
 n=sum(x['component_id']==item['component_id'] for x in records);counts[item['slug']]={'triangles_per_component':tris,'polygons_per_component':polys,'instances':n,'expanded_triangles':tris*n};total+=tris*n;polygons+=polys*n
report={'schema':'sea.scene.geometry_budget','limit':3000,'expanded_triangles':total,'expanded_polygons':polygons,'components':counts,'instances':len(records),'passed':total<=3000,'counting':'mesh evaluated after modifiers, triangulated, multiplied by every visible Collection Instance; library master scene not added twice'}
(W/'geometry_budget.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('BUDGET',total,'triangles',polygons,'polygons',flush=True)
if total>3000:raise RuntimeError('Over expanded triangle budget: '+str(total))
# Preview support contains no geometry and is excluded from asset output.
world=bpy.data.worlds.new('清新天光');scene.world=world;world.use_nodes=True
wn=world.node_tree.nodes;wl=world.node_tree.links;bg=wn['Background'];bg.inputs[0].default_value=(.6,.84,.87,1);bg.inputs[1].default_value=.45
cbg=wn.new('ShaderNodeBackground');cbg.inputs[0].default_value=(.4,.95,1,1);cbg.inputs[1].default_value=1.35
lp=wn.new('ShaderNodeLightPath');mix=wn.new('ShaderNodeMixShader');wl.new(lp.outputs['Is Camera Ray'],mix.inputs[0]);wl.new(bg.outputs[0],mix.inputs[1]);wl.new(cbg.outputs[0],mix.inputs[2]);wl.new(mix.outputs[0],wn['World Output'].inputs[0])
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
for name,loc,power,size,col in [('暖阳',(-4,-6,12),1320,7,(1,.88,.75)),('柔光',(5,-1,8),880,6,(.75,.9,1)),('轮廓光',(-2,7,10),1520,5,(1,.97,.85))]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=col;o=bpy.data.objects.new(name,data);support.objects.link(o);o.location=loc;aim(o,(0,0,2.8))
cd=bpy.data.cameras.new('参考图正交镜头');cam=bpy.data.objects.new(cd.name,cd);support.objects.link(cam);cam.location=(-10,-14,11);aim(cam,(0,0,3));cd.type='ORTHO';cd.ortho_scale=12.8;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True;scene.render.resolution_x=1400;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=-.65;scene.render.image_settings.file_format='PNG'
for screen in bpy.data.screens:
 for a in screen.areas:
  if a.type=='VIEW_3D':a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.shading.type='MATERIAL'
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes']['ledger'];catalog=[]
for item in plan['components']:
 slug=item['slug'];c=components[slug];dest=D/'component_packages'/slug;dest.mkdir(parents=True,exist_ok=True);filepath=dest/(slug+'.blend')
 geometry=[{'vertices':[[round(float(v),5) for v in p.co] for p in o.data.vertices],'polygons':[list(p.vertices) for p in o.data.polygons]} for o in c['meshes']]
 e={**item,'collection':c['collection'].name,'root_object':'ROOT_'+slug,'component_blend':str(filepath.relative_to(R)),'bounds_size_m':c['bounds'],'local_origin':[0,0,0],'source_anchor_shift_m':list(c['anchor']),'instance_count':counts[slug]['instances'],'palette_uv_layer':'PaletteUV','palette_path':str(palette_path.relative_to(R)),'material_roles':[m.name for m in materials.values()],'collision_owner':'godot_wrapper_pending','geometry_fingerprint':hashlib.sha256(json.dumps(geometry,sort_keys=True).encode()).hexdigest(),'source_sha256':None,'asset_ledger':route+'#'+item['component_id'],'license':'pending_user_reference_rights_review','runtime_status':'not_integrated','source_package_meshes':[o.name for o in c['meshes']],'geometry_budget':counts[slug],'version':'v002'}
 (dest/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n');catalog.append(e)
(D/'component_catalog.json').write_text(json.dumps({'schema':'sea.scene.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.component_instances','source_blend':'solar_flower_house.blend','coordinate_contract':{'source_space':'blender_scene_local','plane':'XY','up':'+Z','rotation':'Euler XYZ radians','godot_mapping':'(x,y,z) -> (x,z,-y)','deck_top_z_m':1.677},'instances':records},ensure_ascii=False,indent=2)+'\n')
(D/'geometry_budget.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
(D/'component_tree.txt').write_text('\n'.join(x['category']+' / '+x['slug']+' / '+str(x['instance_count'])+' instances' for x in catalog)+'\n')
img.filepath=bpy.path.relpath(str(palette_path),start=str(D));scene['feature_id']='SEA-ASSET';scene['expanded_triangle_budget']=3000;scene['expanded_triangles']=total;scene['source_stage']='source_created_runtime_pending';bpy.context.window.scene=scene
bpy.ops.wm.save_as_mainfile(filepath=str(OUT),compress=True);print('SEA_LOWPOLY_BUILT',len(catalog),len(records),total,flush=True)
if '--render' in sys.argv:scene.render.filepath=str(W/'previews/solar_flower_house_beauty.png');bpy.ops.render.render(write_still=True)
print('SEA_BUILD_COMPLETE',flush=True)

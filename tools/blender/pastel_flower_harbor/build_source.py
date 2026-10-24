"""Build the new sea solar flower house source only. Never writes runtime scenes.
Run with Blender --background --factory-startup --python this_file -- [--render]
Existing source refuses overwrite unless --replace-generated is supplied.
"""
import bpy, math, random, json, hashlib, os, sys
from pathlib import Path
from mathutils import Vector, Matrix
R=Path(__file__).resolve().parents[3]
D=R/'art_source/scenes/pastel_flower_harbor/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'pastel_flower_harbor'
if R==W or R in W.parents: raise RuntimeError('SEA_WORK_ROOT must be outside repository')
W.mkdir(parents=True,exist_ok=True); (W/'previews').mkdir(exist_ok=True)
plan=json.loads((D/'component_plan.json').read_text())
assert plan['status']=='frozen_before_geometry' and len(plan['components'])<=50
OUT=D/'pastel_flower_harbor.blend'
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
for role,metal,rough in [('Matte',0,.85),('Metal',.15,.45),('Gloss',0,.38),('Emission',0,.4)]:
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

def finish(o,name,color='cream',role='Matte',bevel=0,smooth=False):
 o.name=name
 for c in list(o.users_collection):c.objects.unlink(o)
 current.objects.link(o)
 # The working collection is temporarily linked to the active scene.
 activate(o)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('柔和倒角_三段','BEVEL');mod.width=bevel;mod.segments=2
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
 o['palette_color']=color;o['soft_edge']='beveled_3_segments' if bevel else 'curved_surface'
 return o

def box(n,loc,size,col='cream',bev=.04,role='Matte',rot=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=size
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,bev)
def uvball(n,loc,scale,col='leaf',role='Matte',rot=None):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,location=loc);o=bpy.context.object;o.scale=scale
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,smooth=True)
def cyl(n,loc,radius,depth,col='wood',role='Matte',rot=None,vertices=32,r2=None):
 bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius,radius2=radius if r2 is None else r2,depth=depth,location=loc)
 o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,min(.025,radius*.13))
def torus(n,loc,major,minor,col='wood',rot=None,role='Matte'):
 bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=12,location=loc,major_radius=major,minor_radius=minor)
 o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,smooth=True)
def line(n,pts,r=.025,col='wood',role='Matte'):
 curve=bpy.data.curves.new(n,'CURVE');curve.dimensions='3D';curve.resolution_u=6;curve.bevel_depth=r;curve.bevel_resolution=2
 sp=curve.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for p,co in zip(sp.bezier_points,pts):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
 o=bpy.data.objects.new(n,curve);scene.collection.objects.link(o);activate(o);bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,n,col,role,smooth=True)
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
  o.name=slug+('_emissive' if emissive else '_body');o.data.name=o.name+'_mesh';o['soft_edges']='bevel_3_segments_and_smooth_curves';final.append(o)
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
# Plan is frozen before geometry. All coordinates below are design anchors.
start('pillar')
box('木墩',(0,0,.58),(.26,.28,1.16),'wood_dark',.035)
end('pillar')
start('base')
outline=[(-3.65,-1.05),(-1.75,-1.05),(-1.75,-3.5),(3.70,-3.5),(3.70,0),(1.50,0),(1.50,3.2),(-3.65,3.2)]
verts=[(x,y,z) for z in [0,.20] for x,y in outline];n=len(outline)
faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
mesh('L形奶油平台',verts,faces,'cream',.045)
box('主房薄荷包边',(-1.10,-1.04,.22),(5.10,.10,.09),'seafoam',.02)
box('左侧薄荷包边',(-3.63,1.10,.22),(.10,4.22,.09),'seafoam',.02)
end('base')

start('house')
# Layered wall silhouette; windows are independent inset/glazed components.
box('左侧外墙',(-2.30,0,1.2),(.20,3.6,2.4),'cream',.035)
box('右侧外墙',(2.30,0,1.2),(.20,3.6,2.4),'cream',.035)
box('后墙',(0,1.7,1.2),(4.6,.20,2.4),'cream',.035)
box('前墙',(0,-1.7,1.2),(4.6,.20,2.4),'cream',.035)
box('底层薄荷腰线',(0,-1.82,.3),(4.82,.12,.12),'seafoam',.02)
box('侧面薄荷腰线',(-2.43,0,.3),(.10,3.62,.12),'seafoam',.02)
end('house')
start('terrace')
box('露台地面',(0,0,.10),(5.1,3.9,.2),'cream',.04)
box('露台内地坪',(0,0,.22),(4.85,3.65,.08),'mint_white',.02)
end('terrace')
start('upper_room')
box('小屋墙体',(0,0,.69),(2.65,1.65,1.38),'cream',.045)
end('upper_room')
start('upper_roof')
box('奶黄小屋顶',(0,0,.09),(2.88,1.90,.18),'butter',.05)
end('upper_roof')
start('pergola')
for x in [-2.4,-.8,.8,2.4]:box('花架立柱',(x,0,1.12),(.20,.23,2.24),'cream',.035)
for z in [.26,1.9]:box('花架横梁',(0,0,z),(5.05,.24,.18),'cream',.035)
# Open rear lattice with visible blue inserts, as in the reference.
for x in [-1.6,0,1.6]:box('后排蓝装饰条',(x,.07,1.0),(.09,.08,1.45),'aqua',.016)
end('pergola')
start('rail')
for x in [-.78,.78]:box('栏杆立柱',(x,0,.42),(.13,.16,.84),'cream',.022)
for z in [.18,.78]:box('栏杆横梁',(0,0,z),(1.72,.17,.12),'cream',.022)
end('rail')
start('porch_roof')
box('前廊浅黄屋顶',(0,0,.10),(3.90,3.10,.20),'butter',.035)
box('前缘屋檐',(0,-1.55,.07),(3.96,.10,.18),'sand',.02)
for x in [-1.05,1.05]:
 verts=[(x+side,y,z) for side in [-.055,.055] for y,z in [(-1.1,.20),(1.05,.20),(1.05,1.10)]]
 mesh('太阳能斜支撑',verts,[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],'wood_light',.01)
end('porch_roof')
start('porch_post')
box('前廊柱',(0,0,1.2),(.16,.18,2.4),'cream',.025)
box('柱脚',(0,0,.12),(.23,.25,.24),'wood_light',.025)
end('porch_post')
start('dock_post')
box('木桩',(0,0,.70),(.23,.24,1.40),'wood_mid',.035)
box('奶白桩帽',(0,0,1.42),(.26,.27,.25),'cream',.045)
end('dock_post')
start('window')
box('蓝窗玻璃',(0,0,.62),(.94,.075,1.24),'ocean',.018,'Gloss')
for x in [-.51,.51]:box('窗边框',(x,-.055,.62),(.075,.10,1.36),'seafoam',.014)
for z in [-.02,1.26]:box('窗横框',(0,-.055,z),(1.1,.10,.075),'seafoam',.014)
box('窗竖格',(0,-.070,.62),(.04,.08,1.23),'honey',.008)
box('窗横格',(0,-.070,.63),(.97,.08,.04),'honey',.008)
end('window')
start('cabinet')
box('紫色柜背',(0,.16,.95),(1.00,.09,1.90),'berry',.025)
for x in [-.49,.49]:box('紫色柜侧',(x,0,.95),(.10,.48,1.9),'berry',.022)
for z in [.05,.68,1.30,1.86]:box('紫色柜层板',(0,-.02,z),(1.05,.52,.09),'berry',.02)
end('cabinet')
start('solar_array')
box('太阳能深蓝边座',(0,0,.06),(3.50,2.40,.12),'blue',.03)
for x in range(4):
 for y in range(3):
  color=['solar','blue','solar','ocean'][(x+y)%4]
  box('蓝色电池片',(-1.275+x*.85,-.78+y*.78,.14),(.80,.73,.035),color,.01,'Gloss')
for x in [-1.735,-.85,0,.85,1.735]:box('白色分隔竖条',(x,0,.18),(.025,2.38,.025),'white',.006,'Metal')
for y in [-1.18,-.39,.39,1.18]:box('白色分隔横条',(0,y,.18),(3.5,.025,.025),'white',.006,'Metal')
box('参考图橙色检修盖',(.02,.10,.245),(1.40,.64,.055),'wood',.018,rot=(0,0,.02))
end('solar_array')
start('awning')
for i in range(10):
 x=(i-4.5)*.28;c='yellow' if i%2==0 else 'white'
 box('条纹棚布',(x,-.25,.13),(.279,.65,.045),c,.014,rot=(.18,0,0))
 box('条纹垂边',(x,-.57,.02),(.279,.055,.22),c,.035)
end('awning')
start('planter_box')
box('花箱土壤',(0,0,.20),(1.12,.38,.30),'darkwood',.01)
for y in [-.23,.23]:box('花箱长壁',(0,y,.23),(1.25,.10,.46),'wood_light',.022)
for x in [-.59,.59]:box('花箱端壁',(x,0,.23),(.10,.46,.46),'wood',.022)
for x in [-.48,.48]:
 for y in [-.29,.29]:box('花箱竖箍',(x,y,.23),(.055,.035,.48),'honey',.01)
end('planter_box')
start('pot')
cyl('花盆',(0,0,.20),.21,.4,'wood',vertices=20,r2=.28)
torus('盆口',(0,0,.40),.27,.035,'honey')
cyl('花土',(0,0,.40),.245,.02,'darkwood',vertices=20)
end('pot')
start('crate')
box('箱体',(0,0,.30),(.85,.65,.60),'wood_mid',.035)
for x in [-.37,0,.37]:box('箱顶条',(x,0,.615),(.035,.66,.025),'honey',.006)
for y in [-.29,.29]:box('箱横箍',(0,y,.62),(.85,.035,.035),'wood_light',.006)
for x in [-.37,.37]:box('箱正面箍',(x,-.335,.30),(.05,.035,.60),'wood_light',.008)
end('crate')
start('bench')
for x in [-.60,.60]:box('凳腿',(x,0,.23),(.13,.40,.46),'wood_mid',.02)
for y in [-.14,.14]:box('凳板',(0,y,.48),(1.55,.25,.10),'honey',.025)
end('bench')
start('tire')
torus('轮胎',(0,0,.32),.25,.105,'blue',rot=(pi/2,0,0))
torus('胎圈',(0,-.095,.32),.17,.027,'ocean',rot=(pi/2,0,0))
end('tire')
start('lantern')
box('灯座',(0,0,.06),(.25,.20,.12),'seafoam',.025)
box('emissive_lamp',(0,0,.28),(.16,.14,.32),'butter',.02,'Emission')
for x in [-.11,.11]:box('灯框',(x,0,.29),(.035,.19,.38),'seafoam',.008)
cyl('灯帽',(0,0,.52),.18,.18,'bark',vertices=16,r2=.04)
end('lantern')

def oval(n,base,tip,width,color):
 a=Vector(base);b=Vector(tip);rot=(b-a).to_track_quat('Y','Z').to_euler()
 return uvball(n,(a+b)/2,(width,(b-a).length*.57,width*.40),color,rot=rot)
start('leaf_cluster')
for i in range(5):
 a=i*2*pi/5
 oval('饱满圆叶',(0,0,.1),(.48*math.cos(a),.48*math.sin(a),.43+(i%2)*.18),.19,['leaf','spring','fern','moss_light','leaf'][i])
end('leaf_cluster')
start('vine')
line('藤茎',[(0,0,0),(.025,0,-.65),(-.02,0,-1.25)],.016,'fern')
for i in range(8):
 z=-i*.16;sgn=(-1)**i
 oval('厚圆藤叶',(0,0,z),(sgn*.20,-.02,z-.16),.12,'leaf' if i%2 else 'moss_light')
end('vine')
start('flower_cluster')
for k in range(2):
 x=[-.20,.19][k];y=[-.08,.09][k];z=[.45,.66][k]
 line('短花茎',[(x*.7,y,.05),(x,y,z)],.020,'fern')
 for sign in [-1,1]:oval('花下圆叶',(x,y,.12),(x+sign*.24,y-.08,.34),.13,'leaf' if sign>0 else 'moss_light')
 for i in range(5):
  a=i*2*pi/5+.12
  uvball('圆润五瓣',(x+.13*math.cos(a),y+.13*math.sin(a),z),(.145,.115,.065),'pink' if k==0 else 'white',rot=(0,0,a))
 uvball('奶黄花心',(x,y,z+.055),(.075,.075,.045),'yellow')
end('flower_cluster')

start('porch_floor')
for i in range(9):
 box('橙木地板',(0,(i-4)*.345,.07),(3.9,.335,.14),'wood',.012)
end('porch_floor')
start('porch_rail')
for x in [-.56,.56]:
 box('木栏立柱',(x,0,.32),(.15,.16,.64),'wood',.025)
 box('栏柱白帽',(x,0,.65),(.18,.19,.14),'cream',.028)
box('橙木横栏',(0,0,.42),(1.18,.12,.14),'wood_light',.022)
end('porch_rail')
start('dock_section')
box('白色栈桥底',(0,0,.055),(1.64,1.02,.11),'cream',.026)
for i in range(3):box('栈桥浅木板',(0,(i-1)*.322,.13),(1.48,.313,.09),'honey',.012)
for x in [-.80,.80]:box('白色包边',(x,0,.13),(.06,1.02,.13),'cream',.016)
end('dock_section')
start('landing')
box('横向平台白边',(0,0,.065),(3.35,1.90,.13),'cream',.06)
for i in range(6):box('落脚平台铺板',(0,(i-2.5)*.30,.16),(3.19,.29,.09),'honey',.012)
end('landing')
start('gold_bloom')
for i in range(5):
 a=i*2*pi/5
 oval('顶柱叶',(0,0,.02),(.28*math.cos(a),.28*math.sin(a),.24),.13,'leaf')
for i in range(7):
 a=i*2*pi/7
 uvball('黄色花瓣',(.12*math.cos(a),.12*math.sin(a),.32),(.10,.08,.065),'butter',rot=(0,0,a))
uvball('黄花花盘',(0,0,.36),(.11,.11,.055),'yellow')
end('gold_bloom')
start('resident_figure')
# Static scene scale figure from the reference, not a rigged gameplay character.
for x in [-.075,.075]:box('小鞋',(x,-.03,.055),(.13,.21,.11),'mint_white',.025)
box('薄荷裙身',(0,0,.28),(.28,.20,.40),'seafoam',.04)
uvball('脸',(0,-.01,.61),(.12,.11,.14),'peach')
uvball('黑发',(0,.025,.69),(.135,.12,.15),'darkwood')
uvball('发髻',(0,.03,.83),(.06,.06,.07),'darkwood')
for x in [-.18,.18]:uvball('手臂',(x,-.04,.40),(.045,.05,.17),'peach',rot=(0,-.25 if x<0 else .25,0))
end('resident_figure')

# Reference arrangement: rear-left white building, right-front veranda,
# two parallel piers extending forward, and a transverse landing on the left pier.
inst('base',(0,0,1.10))
for x,y in [(-3.35,-.80),(-3.35,1.1),(-3.35,2.9),(-1.1,2.9),(1.2,2.9),(1.15,.2),(-1.5,-3.2),(-.18,-3.2),(3.4,-3.2),(3.4,-.3)]:inst('pillar',(x,y,0))
inst('house',(-1.10,1.10,1.35))
inst('terrace',(-1.10,1.10,3.73))
inst('upper_room',(-.55,1.85,4.01))
inst('upper_roof',(-.55,1.85,5.39))
inst('pergola',(-1.10,2.98,3.99))
inst('rail',(-3.59,1.83,3.99),rot=(0,0,pi/2))
for x in [-2.76,-1.02]:inst('rail',(x,-.86,3.99))
# The tall purple feature in the supplied image is an open cabinet at terrace edge.
inst('cabinet',(-3.50,.12,3.99),rot=(0,0,-pi/2),scale=.88)
for x in [-2.37,-.63]:inst('window',(x,-.735,1.87),scale=.86)
for x in [-1.16,.11]:inst('window',(x,1.015,4.18),scale=.67)
# Front veranda, stepped to the right of the white main facade.
inst('porch_floor',(1.68,-1.85,1.32))
inst('porch_roof',(1.68,-1.85,3.94))
for x in [-.15,3.49]:inst('porch_post',(x,-3.25,1.43))
inst('awning',(1.68,-2.95,3.88))
inst('solar_array',(1.68,-1.77,4.62),rot=(.45,0,0),scale=.90)
inst('crate',(-.23,-.94,1.40),scale=1.0)
inst('crate',(-.23,-.94,2.02),scale=.96)
inst('crate',(-1.16,-1.08,1.35),scale=.60)
inst('bench',(-1.12,-2.63,1.34),rot=(0,0,pi/2),scale=.90)
for x in [.34,2.92]:inst('porch_rail',(x,-3.32,1.39),scale=.83)
for x in [1.22,3.10]:inst('tire',(x,-3.49,.94),scale=1.05)
inst('resident_figure',(2.08,-2.95,1.47),rot=(0,0,-.35),scale=1.0)
# Foreground pier attaches at the left front of the veranda/base.
for y in [-3.90,-4.90,-5.90]:inst('dock_section',(.15,y,1.18))
inst('landing',(.15,-7.22,1.18))
# Right pier runs parallel to the front one, instead of projecting sideways.
for y in [-1.95,-2.95,-3.95]:inst('dock_section',(4.47,y,1.18))
for x,y in [(-.67,-3.48),(.97,-3.48),(-.67,-5.45),(.97,-5.45),(-1.45,-6.35),(1.75,-6.35),(-1.45,-8.02),(1.75,-8.02),(3.66,-1.45),(5.28,-1.45),(3.66,-3.45),(5.28,-3.45),(3.66,-4.45),(5.28,-4.45)]:inst('dock_post',(x,y,0))
inst('crate',(-.37,-7.40,1.40),scale=1.0)
inst('lantern',(2.75,-.72,1.47),scale=.7)

# Match the reference's discrete clusters rather than replacing them with a new planting plan.
def flowerbox(x,y,z,rot=0,scale=1,extra=True):
 inst('planter_box',(x,y,z),rot=(0,0,rot),scale=scale)
 inst('flower_cluster',(x-.20*math.cos(rot),y-.20*math.sin(rot),z+.38*scale),rot=(0,0,rot),scale=scale)
 if extra:inst('flower_cluster',(x+.28*math.cos(rot),y+.28*math.sin(rot),z+.38*scale),rot=(0,0,rot+.5),scale=.83*scale)
 inst('leaf_cluster',(x+.10*math.cos(rot),y+.10*math.sin(rot),z+.37*scale),rot=(0,0,rot+.8),scale=.72*scale)
def flowerpot(x,y,z,scale=1):
 inst('pot',(x,y,z),scale=scale)
 inst('flower_cluster',(x,y,z+.39*scale),scale=.86*scale)
# Three front terrace planters and tall flowers along the right side of the upper room.
for x in [-2.91,-1.60,-.29]:flowerbox(x,-.72,4.03,scale=.91)
for y in [.60,1.95]:flowerbox(1.20,y,4.02,rot=pi/2,scale=.90)
# The back pergola carries four rosettes; the two left caps carry yellow flowers.
for i,x in enumerate([-3.50,-1.90,-.30,1.10]):
 inst('leaf_cluster',(x,2.97,6.10),scale=.79)
 if i in [0,2]:inst('gold_bloom',(x,2.97,6.31),scale=.80)
 inst('vine',(x,2.81,6.15),scale=.92 if i%2==0 else .75)
# Outer left balcony and front facade vines, with visible open wall between them.
for x,y,z,r,sc in [(-3.66,1.90,5.02,-pi/2,1.0),(-3.66,-.40,4.53,-pi/2,.85),(-2.97,-.98,4.50,0,1.40),(-1.56,-.98,4.49,0,.95),(-.23,-.98,4.49,0,1.25),(-3.48,-.91,2.88,0,1.0)]:
 inst('vine',(x,y,z),rot=(0,0,r),scale=sc)
# Flower border on the veranda roof: compact low plants, front and right edges.
for i,x in enumerate([.0,.65,1.30,1.95,2.60,3.25]):
 inst('flower_cluster',(x,-3.28,4.15),rot=(0,0,i*.45),scale=.43)
 inst('leaf_cluster',(x,-3.28,4.12),scale=.42)
for y in [-2.60,-1.90,-1.20,-.50]:
 inst('flower_cluster',(3.47,y,4.14),rot=(0,0,.6),scale=.45)
 inst('leaf_cluster',(3.47,y,4.12),scale=.43)
# Larger left corner cluster bridges the roof/terrace, as in the supplied image.
inst('flower_cluster',(-.17,-1.37,4.24),scale=.98)
inst('leaf_cluster',(-.13,-1.40,4.16),scale=.93)
# Lower left facade flowerbox, front planters, left bench corner, and landing pot.
flowerbox(-2.20,-.99,1.44,scale=1.15)
flowerbox(.25,-3.06,1.48,scale=.85)
flowerbox(3.05,-1.75,1.48,rot=pi/2,scale=.78)
flowerpot(3.14,-2.89,1.46,.81)
flowerpot(.10,-1.53,1.47,.78)
flowerpot(-.80,-3.24,1.39,.84)
flowerpot(1.10,-6.83,1.39,.90)
flowerpot(3.43,-.35,1.39,.76)
# Neutral mint studio, soft shadow, no geometry outside the component set.
world=bpy.data.worlds.new('清新柔光');world.use_nodes=True;scene.world=world
world.node_tree.nodes['Background'].inputs[0].default_value=(.66,.80,.77,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.60
wn=world.node_tree.nodes;wl=world.node_tree.links;bg=wn['Background'];back=wn.new('ShaderNodeBackground');back.inputs[0].default_value=(.70,.83,.80,1);back.inputs[1].default_value=.8;lp=wn.new('ShaderNodeLightPath');mix=wn.new('ShaderNodeMixShader');wl.new(lp.outputs['Is Camera Ray'],mix.inputs[0]);wl.new(bg.outputs[0],mix.inputs[1]);wl.new(back.outputs[0],mix.inputs[2]);wl.new(mix.outputs[0],wn['World Output'].inputs[0])
def aim(o,point):o.rotation_euler=(Vector(point)-o.location).to_track_quat('-Z','Y').to_euler()
for name,loc,power,size,col in [('柔暖主光',(-6,-8,14),1700,8,(1,.93,.79)),('柔蓝补光',(7,-2,11),900,7,(.85,.94,1)),('顶部轮廓光',(1,6,13),1300,6,(1,1,.93))]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=col;o=bpy.data.objects.new(name,data);support.objects.link(o);o.location=loc;aim(o,(0,0,2.6))
cd=bpy.data.cameras.new('参考图正交镜头');cam=bpy.data.objects.new('参考图正交镜头',cd);support.objects.link(cam);cam.location=(-11.5,-20.0,19.5);aim(cam,(.5,-1.6,2.5));cd.type='ORTHO';cd.ortho_scale=14.5;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.resolution_x=1600;scene.render.resolution_y=1600;scene.render.resolution_percentage=100
scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=-.80
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL'
# Export manifests with normalized bottom-center component geometry.
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes']['ledger'];catalog=[]
for item in plan['components']:
 slug=item['slug'];c=components[slug];dest=D/'component_packages'/slug;dest.mkdir(parents=True,exist_ok=True)
 geometry=[{'vertices':[[round(float(v),5) for v in p.co] for p in o.data.vertices],'polygons':[list(p.vertices) for p in o.data.polygons]} for o in c['meshes']]
 roles=sorted({m.name for o in c['meshes'] for m in o.data.materials})
 entry={**item,'version':'v001','collection':c['collection'].name,'root_object':'ROOT_'+slug,'component_blend':str((dest/(slug+'.blend')).relative_to(R)),'bounds_size_m':c['bounds'],'local_origin':[0,0,0],'source_anchor_shift_m':list(c['anchor']),'instance_count':sum(r['component_id']==item['component_id'] for r in records),'palette_uv_layer':'PaletteUV','palette_path':str(palette_path.relative_to(R)),'material_roles':roles,'collision_owner':'godot_wrapper_pending','geometry_fingerprint':hashlib.sha256(json.dumps(geometry,sort_keys=True).encode()).hexdigest(),'source_sha256':None,'asset_ledger':route+'#'+item['component_id'],'license':'pending_user_reference_rights_review','runtime_status':'not_integrated','source_package_meshes':[o.name for o in c['meshes']]}
 (dest/'asset_manifest.json').write_text(json.dumps(entry,ensure_ascii=False,indent=2)+'\n');catalog.append(entry)
(D/'component_catalog.json').write_text(json.dumps({'schema':'sea.scene.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.component_instances','source_blend':'pastel_flower_harbor.blend','coordinate_contract':{'source_space':'blender_scene_local','plane':'XY','up':'+Z','rotation':'Euler XYZ radians; solar array tilt included','godot_mapping':'(x,y,z) -> (x,z,-y)'},'instances':records},ensure_ascii=False,indent=2)+'\n')
(D/'component_tree.txt').write_text('\n'.join(x['category']+' / '+x['slug']+' / '+str(x['instance_count'])+' instances' for x in catalog)+'\n')
bpy.context.window.scene=scene
img.filepath=bpy.path.relpath(str(palette_path),start=str(D));scene['feature_id']='SEA-ASSET';scene['source_stage']='source_created_runtime_pending';scene['reference_sha256']=plan['reference_sha256']
bpy.ops.wm.save_as_mainfile(filepath=str(OUT),compress=True)
print('SEA_SOURCE_BUILT',len(catalog),'components',len(records),'instances',flush=True)
if '--render' in sys.argv:
 scene.render.filepath=str(W/'previews/beauty.png');bpy.ops.render.render(write_still=True)

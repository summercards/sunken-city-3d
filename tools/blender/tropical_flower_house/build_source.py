"""Build the new sea solar flower house source only. Never writes runtime scenes.
Run with Blender --background --factory-startup --python this_file -- [--render]
Existing source refuses overwrite unless --replace-generated is supplied.
"""
import bpy, math, random, json, hashlib, os, sys
from pathlib import Path
from mathutils import Vector, Matrix
R=Path(__file__).resolve().parents[3]
D=R/'art_source/scenes/tropical_flower_house/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'tropical_flower_house'
if R==W or R in W.parents: raise RuntimeError('SEA_WORK_ROOT must be outside repository')
W.mkdir(parents=True,exist_ok=True); (W/'previews').mkdir(exist_ok=True)
plan=json.loads((D/'component_plan.json').read_text())
assert plan['status']=='frozen_before_geometry' and len(plan['components'])<=50
OUT=D/'tropical_flower_house.blend'
if OUT.exists() and '--replace-generated' not in sys.argv: raise RuntimeError('Existing source: use an explicit new version or --replace-generated for this generated candidate')
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(71)
scene=bpy.context.scene; scene.name='热带花屋_参考装配'
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
  mod=o.modifiers.new('柔和倒角_三段','BEVEL');mod.width=bevel;mod.segments=1 if current.name.endswith("-PAVING") else (3 if bevel>=.06 else 2)
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
 o['palette_color']=color;o['soft_edge']='beveled_2_or_3_segments' if bevel else 'curved_surface'
 return o

def box(n,loc,size,col='cream',bev=.04,role='Matte',rot=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=size
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,bev)
def uvball(n,loc,scale,col='leaf',role='Matte',rot=None):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=10 if current.name.endswith(('-LEAF-CLUSTER','-VINE','-SPROUT')) else 12,ring_count=6 if current.name.endswith(('-LEAF-CLUSTER','-VINE','-SPROUT')) else 8,location=loc);o=bpy.context.object;o.scale=scale
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,smooth=True)
def cyl(n,loc,radius,depth,col='wood',role='Matte',rot=None,vertices=16,r2=None):
 bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius,radius2=radius if r2 is None else r2,depth=depth,location=loc)
 o=bpy.context.object
 if rot:o.rotation_euler=rot
 return finish(o,n,col,role,min(.025,radius*.13))
def torus(n,loc,major,minor,col='wood',rot=None,role='Matte'):
 bpy.ops.mesh.primitive_torus_add(major_segments=16,minor_segments=6,location=loc,major_radius=major,minor_radius=minor)
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
  o.name=slug+('_emissive' if emissive else '_body');o.data.name=o.name+'_mesh';o['soft_edges']='bevel_2_or_3_segments_and_smooth_curves';final.append(o)
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
# Frozen kit geometry: the latest attached image is the only layout reference.
start('base')
box('灰石浮台',(0,0,.28),(7.4,6.8,.56),'gray',.08)
for x in [-3.45,-2.1,-.7,.7,2.1,3.45]:
 for y in [-3.32,3.32]:box('边缘石墩',(x,y,.28),(.68,.22,.62),'silver',.025)
for y in [-2.3,-.8,.7,2.2]:box('侧边石墩',(-3.64,y,.28),(.22,.67,.62),'silver',.025)
end('base')
start('paving');box('暖橙铺板',(0,0,0),(.60,.60,.12),'wood_light',.025);end('paving')
start('house')
# One continuous shell, with actual window openings: no beveled-box cracks.
w=box('连续奶白墙壳',(0,0,1.425),(5.2,3.5,2.85),'white',0)
for loc,size in [((0,0,1.425),(4.76,3.06,2.50)),((-1.26,-1.65,1.42),(1.14,.80,1.82)),((-2.50,0,1.43),(.80,2.16,1.82))]:
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);c=bpy.context.object;c.scale=size;activate(c);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 activate(w);m=w.modifiers.new('真实开口','BOOLEAN');m.operation='DIFFERENCE';m.object=c;bpy.ops.object.modifier_apply(modifier=m.name);bpy.data.objects.remove(c,do_unlink=True)
finish(w,w.name,'white',bevel=.055)
end('house')
start('terrace');box('奶白厚楼沿',(0,0,.13),(5.45,3.8,.26),'white',.08);box('露台暖木坪',(0,0,.29),(5.12,3.44,.07),'honey',.025)
for x in range(9):box('露台砖缝',(-2.23+x*.56,0,.33),(.014,3.36,.006),'wood',0)
for y in [-1.1,-.5,.1,.7,1.3]:box('露台砖缝',(0,y,.33),(5.04,.014,.006),'wood',0)
end('terrace')
start('upper_room')
# Opaque door covers this compact shell; a single rounded volume avoids corner cracks.
box('屋顶小屋完整墙体',(0,0,1),(2.35,1.9,2),'white',.065)
end('upper_room')
start('roof_cap');box('小屋奶白帽檐',(0,0,.16),(2.66,2.18,.32),'white',.095);end('roof_cap')
start('parapet');box('白色花台矮墙',(0,0,.22),(1.24,.28,.44),'white',.065);end('parapet')
start('porch_roof')
box('单坡奶白屋面',(0,0,0),(3.38,1.78,.18),'white',.065,rot=(.38,0,0))
box('橙木前檐',(0,-.83,-.29),(3.48,.22,.24),'wood_light',.07)
for x in [-1.62,1.62]:box('橙木侧檐',(x,0,0),(.20,1.81,.22),'wood_light',.055,rot=(.38,0,0))
end('porch_roof')
start('dock_support');box('栈桥灰色支承',(0,0,.25),(1.16,2.5,.50),'gray',.035);end('dock_support')
start('dock_plank');box('栈桥宽木板',(0,0,0),(1.16,.48,.19),'wood_light',.05);end('dock_plank')
start('post');box('系绳木桩',(0,0,.42),(.36,.36,.84),'wood_light',.065)
for z in [.17,.27]:torus('奶白绳圈',(0,0,z),.23,.035,'cream')
box('柱脚座',(0,0,.06),(.46,.46,.12),'wood',.045);end('post')
start('shade_post')
for x in [-1.35,1.35]:
 box('棚架厚立柱',(x,0,1.2),(.26,.28,2.4),'wood_light',.065)
 box('棚架底座',(x,0,.09),(.40,.41,.18),'honey',.045)
 cyl('梁端木栓',(x,-.18,2.12),.10,.18,'wood',rot=(pi/2,0,0),vertices=12)
box('棚架横梁',(0,0,2.17),(2.98,.20,.22),'wood_light',.06)
end('shade_post')
start('shade_sail')
v=[]
for j in range(9):
 for i in range(13):
  x=-1.36+i*2.72/12;y=-.82+j*1.64/8;z=-.38*math.sin(pi*i/12)*(.72+.28*math.cos(y/.82*pi/2));v.append((x,y,z))
f=[]
for j in range(8):
 for i in range(12):a=j*13+i;f.append((a,a+1,a+14,a+13))
o=mesh('奶白软布垂弧',v,f,'butter');activate(o);m=o.modifiers.new('布边厚度','SOLIDIFY');m.thickness=.035;bpy.ops.object.modifier_apply(modifier=m.name);finish(o,o.name,'butter',smooth=True);end('shade_sail')
start('window')
box('蓝玻璃',(0,0,.90),(1.12,.06,1.80),'aqua',.02,'Gloss')
for x in [-.57,0,.57]:box('蓝窗竖框',(x,-.06,.9),(.065,.11,1.88),'teal',.018)
for z in [0,1.8]:box('蓝窗横框',(0,-.06,z),(1.2,.11,.065),'teal',.018)
box('淡蓝反光',(-.25,-.037,.94),(.10,.006,1.54),'sky',0);end('window')
start('door')
box('蓝门扇',(0,0,.90),(.86,.10,1.80),'teal',.04)
for x in [-.48,.48]:box('门框',(x,0,.95),(.10,.18,1.90),'wood',.025)
box('门顶框',(0,0,1.88),(1.03,.18,.11),'wood',.025)
box('门牌',(0,-.067,1.45),(.16,.025,.18),'yellow',.012)
cyl('金把手',(-.28,-.1,.85),.035,.12,'gold',rot=(pi/2,0,0),vertices=10);end('door')
start('glass_entry')
# Opaque colored glazing with warm silhouettes: no transparent sorting cost.
for x in [-.63,.63]:
 box('暖色玻璃门',(x,0,1.03),(1.20,.035,2.06),'honey',.01,'Gloss')
 box('蓝色竖窗映光',(x-.42,-.027,1.1),(.10,.015,1.75),'sky',0)
for x in [-1.26,0,1.26]:box('入口青蓝立框',(x,-.055,1.04),(.08,.12,2.16),'teal',.018)
for z in [0,2.12]:box('入口横框',(0,-.055,z),(2.6,.12,.08),'teal',.018)
for x in [-.1,.1]:box('长门柄',(x,-.15,1.02),(.035,.05,.30),'wood_light',.012)
end('glass_entry')
start('solar_panel')
box('白色圆角板框',(0,0,0),(1.42,1.43,.12),'snow',.055)
box('蓝色光伏面',(0,0,.067),(1.27,1.28,.025),'solar',.015,'Gloss')
for x in [-.42,-.21,0,.21,.42]:box('细栅',(x,0,.082),(.008,1.24,.003),'aqua',0)
for y in [-.48,-.32,-.16,0,.16,.32,.48]:box('细栅',(0,y,.083),(1.23,.008,.003),'aqua',0)
end('solar_panel')
start('awning')
for j in range(12):
 x=-1.54+j*.28;col='yellow' if j%2==0 else 'white'
 box('布棚条纹',(x,0,0),(.281,.92,.04),col,.012,rot=(.27,0,0))
 uvball('圆垂边',(x,-.446,-.17),(.14,.055,.13),col)
end('awning')
start('ladder')
for x in [-.34,.34]:box('厚梯柱',(x,0,1.43),(.13,.16,2.86),'wood',.04)
for z in [.22,.58,.94,1.30,1.66,2.02,2.38,2.70]:box('圆木踏步',(0,-.02,z),(.78,.18,.11),'wood_light',.035)
end('ladder')
for slug,siz in [('ac_large',(.92,.52,1.22)),('ac_small',(.67,.45,.77)),('ac_roof',(1.02,.84,.63))]:
 start(slug);w,d,h=siz
 box('奶白空调机壳',(0,0,h/2),siz,'snow',.065)
 box('散热侧面',(0,-d/2-.01,h*.51),(w*.72,.025,h*.65),'gray',.015)
 for k in range(9):box('散热百叶',(0,-d/2-.028,h*.22+k*h*.071),(w*.68,.016,.016),'silver',0)
 box('蓝色铭牌',(w*.27,-d/2-.03,h*.88),(w*.24,.025,.07),'sky',.01)
 box('顶盖',(0,0,h+.015),(w*.90,d*.88,.045),'white',.015);end(slug)
start('vent');box('屋顶烟囱',(0,0,.57),(.24,.27,1.14),'wood_light',.045);box('灰色散热片',(.125,-.025,.55),(.02,.12,.52),'silver',.015);end('vent')
start('lantern')
box('壁灯背板',(0,.08,.28),(.15,.12,.40),'wood',.025)
box('暖灯芯_emissive',(0,-.09,.25),(.19,.16,.28),'yellow',.035,'Emission')
for x in [-.12,.12]:box('灯框',(x,-.1,.25),(.035,.20,.38),'ochre',.01)
for z in [.05,.44]:box('灯框帽',(0,-.10,z),(.29,.25,.075),'ochre',.025)
line('灯钩',[(0,.08,.42),(0,-.06,.61),(0,-.15,.49)],.025,'wood_dark');end('lantern')
start('bench')
for x in [-.65,.65]:
 for y in [-.23,.23]:box('沙发脚',(x,y,.16),(.12,.13,.32),'wood',.025)
box('沙发木座',(0,0,.33),(1.55,.70,.15),'wood_light',.045)
box('饱满奶白坐垫',(0,-.04,.49),(1.38,.60,.22),'white',.09)
box('饱满奶白靠垫',(0,.24,.82),(1.38,.20,.65),'cream',.08,rot=(.12,0,0))
for x in [-.74,.74]:box('木扶手',(x,0,.68),(.13,.72,.20),'wood_light',.05)
box('黄色抱枕',(-.32,.09,.80),(.43,.19,.44),'yellow',.065,rot=(.1,-.18,-.12))
box('蓝色抱枕',(.28,.08,.80),(.42,.19,.43),'aqua',.065,rot=(.1,.15,.12));end('bench')
start('table')
box('圆角桌面',(0,0,.67),(1.18,.88,.16),'wood_light',.055)
for x in [-.44,.44]:
 for y in [-.30,.30]:box('桌腿',(x,y,.31),(.12,.14,.62),'wood',.03)
end('table')
start('stool');box('凳面',(0,0,.39),(.48,.48,.12),'wood_light',.04)
for x in [-.16,.16]:
 for y in [-.16,.16]:box('凳脚',(x,y,.18),(.08,.08,.36),'wood',.018)
end('stool')
start('parasol')
cyl('伞座',(0,0,.055),.27,.11,'stone',vertices=16);cyl('伞杆',(0,0,1.22),.035,2.44,'wood',vertices=12)
for seg in range(8):
 v=[]
 for k in range(5):
  r=k*.235;z=2.48-.42*(k/4)**1.4
  for j in range(4):
   a=(seg+j/3)*pi/4;v.append((r*math.cos(a),r*math.sin(a),z-.045*math.sin(j*pi/3)*k/4))
 f=[]
 for k in range(4):
  for j in range(3):a=k*4+j;f.append((a,a+4,a+5,a+1))
 o=mesh('黄白伞瓣',v,f,'yellow' if seg%2==0 else 'white');activate(o);m=o.modifiers.new('伞布厚度','SOLIDIFY');m.thickness=.025;bpy.ops.object.modifier_apply(modifier=m.name);finish(o,o.name,'yellow' if seg%2==0 else 'white',smooth=True)
uvball('伞帽',(0,0,2.51),(.08,.08,.07),'wood_light');end('parasol')
start('cooler');box('蓝色冰箱体',(0,0,.29),(.86,.62,.58),'teal',.075);box('奶白箱盖',(0,0,.61),(.90,.66,.16),'white',.06)
for x in [-.35,.35]:box('盖扣',(x,-.34,.51),(.08,.045,.14),'aqua',.018)
end('cooler')
start('pot');cyl('圆陶花盆',(0,0,.23),.23,.46,'peach',vertices=16,r2=.31);torus('厚盆口',(0,0,.46),.29,.035,'sand');cyl('盆土',(0,0,.455),.265,.025,'wood_dark',vertices=16);end('pot')
start('cup');cyl('红色保温壶',(0,0,.17),.10,.34,'red',vertices=12);cyl('壶盖',(0,0,.355),.08,.04,'red_dark',vertices=12);end('cup')
start('rug');box('薄荷地垫',(0,0,.012),(.95,.70,.024),'aqua',.015)
for x in [-.42,.42]:box('黄垫边',(x,0,.028),(.025,.59,.006),'yellow',0)
for y in [-.28,.28]:box('黄垫边',(0,y,.028),(.85,.025,.006),'yellow',0)
cyl('太阳图形',(-.12,0,.031),.15,.006,'yellow',vertices=16)
end('rug')
# Chunky organic forms; no subdivision and no alpha cards.
start('leaf_cluster')
for i in range(6):
 a=i*2*pi/6;uvball('饱满宽叶',(.28*math.cos(a),.28*math.sin(a),.21+(.10 if i%2 else 0)),(.17,.29,.135),['leaf','leaf_yellow','lime'][i%3],rot=(.30,0,a-pi/2))
uvball('圆芽',(0,0,.34),(.19,.17,.22),'lime');end('leaf_cluster')
start('vine')
line('藤茎',[(0,0,0),(.06,0,.4),(-.035,0,.8),(0,0,1.2)],.023,'leaf_mid')
for i in range(9):
 z=.10+i*.125;sign=(-1)**i
 uvball('垂藤肥叶',(sign*(.08+.025*(i%3)),-.04,z),(.125,.11,.18),['leaf_yellow','leaf','lime'][i%3],rot=(.2,sign*(.35+.17*(i%3)),sign*.17))
end('vine')
start('palm')
for idx in range(6):
 a=idx*2*pi/6;length=[1.05,.88,1.12,.94,1.0,.84][idx]
 # Inflated lobed leaf, elliptical cross sections with one gently arched spine.
 vs=[];rings=17;sides=10
 for i in range(rings):
  t=i/(rings-1);rad=max(.015,math.sin(pi*t)**.30)*(.27+ .045*math.cos(t*8*pi))
  center=Vector((length*t*math.cos(a),length*t*math.sin(a),.22+.48*math.sin(t*pi*.82)))
  side=Vector((-math.sin(a),math.cos(a),0))
  for j in range(sides):
   b=j*2*pi/sides;vs.append(tuple(center+side*(rad*math.cos(b))+Vector((0,0,.155*math.sin(pi*t)**.3*math.sin(b)))))
 fs=[]
 for i in range(rings-1):
  for j in range(sides):fs.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
 fs.extend([tuple(reversed(range(sides))),tuple(range((rings-1)*sides,rings*sides))])
 o=mesh('圆润裂叶',vs,fs,['leaf_yellow','leaf','lime'][idx%3]);
 for p in o.data.polygons:p.use_smooth=True
end('palm')
for slug,number,col in [('flower',5,'rose'),('daisy',6,'white')]:
 start(slug)
 for i in range(number):
  a=i*2*pi/number;uvball('厚圆花瓣',(.25*math.cos(a),-.025,.40+.25*math.sin(a)),(.19,.105,.29),col,rot=(0,pi/2-a,0))
 uvball('黄色花蕊',(0,-.12,.40),(.135,.11,.135),'yellow');end(slug)
start('sprout')
for i in range(5):
 a=i*2*pi/5;uvball('盆栽叶',(.14*math.cos(a),.14*math.sin(a),.22),(.10,.22,.08),'leaf_yellow' if i%2 else 'leaf',rot=(.6,0,a-pi/2))
cyl('嫩茎',(0,0,.14),.028,.28,'leaf',vertices=8);end('sprout')
# Reference assembly. All repeated pieces are Collection Instances.
inst('base')
for ix in range(12):
 for iy in range(11):inst('paving',(-3.34+ix*.605,-3.02+iy*.605,.62))
inst('house',(-.65,.95,.68));inst('terrace',(-.65,.95,3.53))
inst('upper_room',(.74,1.65,3.86));inst('roof_cap',(.74,1.65,5.86));inst('door',(.57,.69,3.88))
inst('window',(-1.91,-.80,1.20));inst('window',(-3.27,.40,1.25),rot=(0,0,-pi/2));inst('window',(-3.27,1.65,1.25),rot=(0,0,-pi/2))
inst('window',(1.93,1.68,4.18),rot=(0,0,pi/2),scale=.55)
inst('porch_roof',(1.23,-1.55,3.37));inst('glass_entry',(1.18,-1.60,.70));inst('awning',(1.23,-2.55,2.99))
for x in [.43,2.03]:inst('solar_panel',(x,-1.55,3.53),rot=(.38,0,0))
for x in [-2.61,-1.33]:inst('parapet',(x,-.86,3.80))
for y in [.25,1.52,2.55]:inst('parapet',(-3.25,y,3.80),rot=(0,0,pi/2))
inst('ladder',(-.54,-.94,.74))
inst('shade_post',(-1.59,-.18,3.86));inst('shade_post',(-1.59,1.62,3.86));inst('shade_sail',(-1.59,.72,6.01))
inst('bench',(-1.85,.90,3.88),scale=.90);inst('table',(-1.9,-.03,3.88),scale=.75)
inst('pot',(-1.90,-.03,4.44),scale=.28);inst('sprout',(-1.9,-.03,4.57),scale=.4)
for x,y,z,s in [(-3.30,-.45,.70,1),(-2.76,-1.48,.70,.85),(.03,1.70,6.20,1.0),(.10,-.05,3.87,.83)]:inst('ac_roof' if z>6 else ('ac_large' if s>=1 else 'ac_small'),(x,y,z),rot=(0,0,-pi/2 if x<-2 else 0),scale=s)
inst('vent',(-.06,1.93,6.19))
for x,y,z in [(-.06,.60,5.0),(-.18,-1.95,2.29),(2.63,-1.86,2.02)]:inst('lantern',(x,y,z))
inst('bench',(2.09,-2.19,.70),scale=.84);inst('table',(3.02,-2.82,.70),scale=.87);inst('parasol',(3.03,-2.77,1.33),scale=.87)
inst('cup',(3.30,-2.97,1.36));inst('stool',(3.31,-2.0,.70),scale=.75);inst('stool',(2.76,-3.31,.70),scale=.8)
inst('cooler',(-.85,-2.10,.70),scale=.85);inst('cooler',(2.12,-3.0,.70));inst('rug',(.54,-2.44,.70))
for x,y,s in [(-.18,-2.23,.75),(.37,-2.97,.85),(-2.94,.08,.80),(-.17,.48,.75),(3.08,-.48,.8)]:
 z=3.87 if y>.0 and x>-.5 and x<1 else .70
 inst('pot',(x,y,z),scale=s);inst('sprout',(x,y,z+.47*s),scale=s*1.25)
# Bridge: two parallel strips and a gap, two broad planks per row.
for y in [-3.64,-4.14,-4.64,-5.14,-5.64]:
 for x in [.85,2.10]:inst('dock_plank',(x,y,.59))
# Short grey supports follow the two strips without filling the centre water slot.
# Reuse base geometry is inappropriate here; supports belong to the plank assembly visually.
for x in [.85,2.10]:inst('dock_support',(x,-4.64,0))
for x,y in [(-3.2,-2.8),(-3.25,2.8),(.12,-3.35),(2.83,-3.35),(.12,-5.64),(2.83,-5.64)]:inst('post',(x,y,.64))
for x,y,r in [(-2.25,-2.7,0),(-.95,-3.15,0),(3.57,-1.24,pi/2)]:inst('parapet',(x,y,.70),rot=(0,0,r))
# Dense, broad leaf masses along walls; flowers remain separate replaceable components.
random.seed(43)
def cluster(x,y,z,s=1):inst('leaf_cluster',(x,y,z),rot=(0,0,random.random()*6.28),scale=s)
for x in [-3.25,-2.65,-2.03,-1.4,-.78]:cluster(x,-.91,4.08,.75)
for y in [-.20,.45,1.1,1.78,2.45]:cluster(-3.26,y,4.07,.85)
for x,y in [(-3.27,-.7),(-2.5,-.94),(-1.4,-.94),(-3.28,1.3)]:inst('vine',(x,y,2.62),scale=1.18)
for x,y in [(.0,1.0),(.0,2.1),(.7,2.6),(1.65,2.4),(1.95,1.65),(1.75,.72)]:cluster(x,y,6.13,.68)
for x,y in [(1.75,.64),(1.12,.63),(.58,.64)]:inst('vine',(x,y,5.12),scale=.92)
for x,y,z,s in [(-2.9,1.75,5.70,1.0),(-3.32,2.43,4.22,.95),(-3.55,.6,3.9,.95),(-2.25,-2.05,.93,1.2),(2.6,.38,3.03,1.1),(3.48,-1.44,.83,1.1)]:inst('palm',(x,y,z),rot=(0,0,random.random()*6.28),scale=s)
for x,y,z,s in [(-2.70,-2.3,.76,1),(-1.9,-2.65,.76,1),(-1.25,-2.96,.76,.95),(-.55,-3.20,.76,1),(.02,-3.10,.76,.72),(3.55,-.6,.72,1),(3.55,-1.2,.74,1),(3.52,-2,.74,.82),(-3.5,1,.7,.72),(-3.5,2.5,.7,.9)]:cluster(x,y,z,s)
for x,y,z,s in [(-.40,-1.26,3.89,.9),(-.25,-1.85,3.47,.8),(2.8,-.62,3.76,.85),(2.72,.14,4.07,.92),(2.9,-1.45,3.32,.70)]:cluster(x,y,z,s)
# The photo presents large pink blooms at distinct height tiers, white accent daisies.
for x,y,z,s in [(-.36,-1.82,3.72,.9),(2.65,-.55,4.02,.9),(2.49,.30,4.58,.68),(-1.9,-2.53,1.12,.85),(-.47,-3.11,.99,.78),(3.52,-1.02,2.97,.66)]:inst('flower',(x,y,z),rot=(.15,0,-.12),scale=s)
for x,y,z,s in [(-3.43,-.10,4.48,.57),(-2.53,-2.52,1.06,.60),(.32,-3.08,.84,.45),(3.54,-2.06,1.06,.51),(3.49,-.88,3.29,.46),(-.05,-1.75,3.55,.45)]:inst('daisy',(x,y,z),rot=(.15,0,0),scale=s)
for x,y,z in [(-2.95,-2.60,.2),(-1.35,-3.4,.2),(3.6,-2.2,.2)]:inst('vine',(x,y,z),scale=.52)
# Neutral mint studio, soft shadow, no geometry outside the component set.
world=bpy.data.worlds.new('清新柔光');world.use_nodes=True;scene.world=world
world.node_tree.nodes['Background'].inputs[0].default_value=(.66,.80,.77,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.60
wn=world.node_tree.nodes;wl=world.node_tree.links;bg=wn['Background'];back=wn.new('ShaderNodeBackground');back.inputs[0].default_value=(.035,.50,1.0,1);back.inputs[1].default_value=.8;lp=wn.new('ShaderNodeLightPath');mix=wn.new('ShaderNodeMixShader');wl.new(lp.outputs['Is Camera Ray'],mix.inputs[0]);wl.new(bg.outputs[0],mix.inputs[1]);wl.new(back.outputs[0],mix.inputs[2]);wl.new(mix.outputs[0],wn['World Output'].inputs[0])
def aim(o,point):o.rotation_euler=(Vector(point)-o.location).to_track_quat('-Z','Y').to_euler()
for name,loc,power,size,col in [('柔暖主光',(-6,-8,14),1700,8,(1,.93,.79)),('柔蓝补光',(7,-2,11),900,7,(.85,.94,1)),('顶部轮廓光',(1,6,13),1300,6,(1,1,.93))]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=col;o=bpy.data.objects.new(name,data);support.objects.link(o);o.location=loc;aim(o,(0,0,2.6))
cd=bpy.data.cameras.new('参考图正交镜头');cam=bpy.data.objects.new('参考图正交镜头',cd);support.objects.link(cam);cam.location=(-11,-16,12);aim(cam,(0,-.65,2.65));cd.type='ORTHO';cd.ortho_scale=12.7;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1200;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=-.30
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
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
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.component_instances','source_blend':'tropical_flower_house.blend','coordinate_contract':{'source_space':'blender_scene_local','plane':'XY','up':'+Z','rotation':'Euler XYZ radians; solar array tilt included','godot_mapping':'(x,y,z) -> (x,z,-y)'},'instances':records},ensure_ascii=False,indent=2)+'\n')
(D/'component_tree.txt').write_text('\n'.join(x['category']+' / '+x['slug']+' / '+str(x['instance_count'])+' instances' for x in catalog)+'\n')
bpy.context.window.scene=scene
img.filepath=bpy.path.relpath(str(palette_path),start=str(D));scene['feature_id']='SEA-ASSET';scene['source_stage']='source_created_runtime_pending';scene['reference_sha256']=plan['reference_sha256']
bpy.ops.wm.save_as_mainfile(filepath=str(OUT),compress=True)
print('SEA_SOURCE_BUILT',len(catalog),'components',len(records),'instances',flush=True)
if '--render' in sys.argv:
 scene.render.filepath=str(W/'previews/beauty.png');bpy.ops.render.render(write_still=True)

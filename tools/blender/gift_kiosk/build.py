"""Author the reference kiosk directly in the active Blender MCP GUI session."""
import bpy
import bmesh
import hashlib
import json
import math
import os
from pathlib import Path
from mathutils import Matrix, Vector

R=Path('D:/projects/sea'); D=R/'art_source/scenes/gift_kiosk/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001'
PLAN=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
PAL=R/PLAN['palette']; COLS={r['name']:r for r in json.loads(PAL.with_suffix('.json').read_text())['cells']}
TAU=math.tau; PI=math.pi
W.mkdir(parents=True,exist_ok=True)
if not (W/'session_before.blend').exists():
 bpy.ops.wm.save_as_mainfile(filepath=str(W/'session_before.blend'),copy=True)
for old in list(bpy.data.scenes):
 if old.name.startswith('海上礼品商亭_v001'):
  if bpy.context.window.scene==old: bpy.context.window.scene=next(s for s in bpy.data.scenes if s!=old)
  bpy.data.scenes.remove(old)
for old in list(bpy.data.collections):
 if old.name.startswith(('GKS_','SEA-SCENE-GKS-')):
  for obj in list(old.objects):bpy.data.objects.remove(obj,do_unlink=True)
  bpy.data.collections.remove(old)
for old in list(bpy.data.materials):
 if old.get('semantic_role') and old.users==0:bpy.data.materials.remove(old)
# A new scene preserves any existing open scene/datablocks in the session safety copy.
sc=bpy.data.scenes.new('海上礼品商亭_v001')
bpy.context.window.scene=sc
sc.unit_settings.system='METRIC'; sc.unit_settings.scale_length=1
sc.world=bpy.data.worlds.new('GKS_Studio')
sc.world.use_nodes=True
wn=sc.world.node_tree.nodes;wn.clear();bg=wn.new('ShaderNodeBackground');wo=wn.new('ShaderNodeOutputWorld')
sc.world.node_tree.links.new(bg.outputs[0],wo.inputs[0]);bg.inputs[0].default_value=(.78,.83,.90,1);bg.inputs[1].default_value=.45
top={}
for key,label in [('structure','01_建筑结构'),('furnishing','02_固定设施与陈设'),('plant','03_独立植物'),('display','04_展示支持')]:
 c=bpy.data.collections.new('GKS_'+label); sc.collection.children.link(c);top[key]=c
image=bpy.data.images.load(str(PAL),check_existing=True)
roles={}
for name in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission']:
 mat=bpy.data.materials.new(name); mat.use_nodes=True
 # Unique material role names inside this new source, independent of the old source.
 if mat.name!=name: mat.name='GKS_'+name
 nodes=mat.node_tree.nodes; bs=next((n for n in nodes if n.type=='BSDF_PRINCIPLED'),None)
 if bs is None:
  bs=nodes.new('ShaderNodeBsdfPrincipled');out=nodes.new('ShaderNodeOutputMaterial');mat.node_tree.links.new(bs.outputs[0],out.inputs[0])
 bs.inputs['Roughness'].default_value={'SEA_Matte':.5,'SEA_Metal':.28,'SEA_Gloss':.13,'SEA_Emission':.3}[name]
 bs.inputs['Metallic'].default_value=.12 if name=='SEA_Metal' else 0
 if name=='SEA_Gloss':
  bs.inputs['Alpha'].default_value=.095
  mat.surface_render_method='DITHERED'
  mat.use_transparency_overlap=False
 tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest';tex.extension='EXTEND'
 uv=nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';mat.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector'])
 mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
 if name=='SEA_Emission':
  mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=.65
 mat['semantic_role']=name;roles[name]=mat
font_path=Path('C:/Windows/Fonts/arialbd.ttf');font=bpy.data.fonts.load(str(font_path))
components={};catalog=[];layout=[];current=None

def finish(o,color='cream',role='SEA_Matte',bevel=0):
 for c in list(o.users_collection): c.objects.unlink(o)
 current.objects.link(o)
 bpy.context.view_layer.objects.active=o;o.select_set(True)
 if o.type!='MESH': bpy.ops.object.convert(target='MESH');o=bpy.context.object
 bpy.context.view_layer.update()
 o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
 if bevel:
  mo=o.modifiers.new('实体饱满倒角_3段','BEVEL');mo.width=bevel;mo.segments=3;mo.affect='EDGES'
  bpy.ops.object.modifier_apply(modifier=mo.name)
  for p in o.data.polygons: p.use_smooth=p.area<.35
  try:
   mo=o.modifiers.new('平面与圆角法线','WEIGHTED_NORMAL');mo.keep_sharp=True;mo.weight=40
   bpy.ops.object.modifier_apply(modifier=mo.name)
  except Exception: pass
 for uv in list(o.data.uv_layers):o.data.uv_layers.remove(uv)
 uv=o.data.uv_layers.new(name='PaletteUV');uv.active_render=True
 cell=COLS[color];cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
 for p in o.data.polygons:
  for j,li in enumerate(p.loop_indices):
   a=TAU*j/len(p.loop_indices);uv.data[li].uv=(cx+.028*math.cos(a),cy+.028*math.sin(a))
 o.data.materials.clear();o.data.materials.append(roles[role]);o['palette_color']=color;o['role']=role
 o.select_set(False)
 return o

def box(n,p,s,c='cream',r='SEA_Matte',b=.04):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=n;o.scale=s
 return finish(o,c,r,min(b,min(s)*.46) if b else 0)

def cyl(n,p,rad,depth,c='gold',r='SEA_Metal',v=32,b=.03):
 bpy.ops.mesh.primitive_cylinder_add(vertices=v,radius=rad,depth=depth,location=p)
 o=bpy.context.object;o.name=n
 return finish(o,c,r,min(b,depth*.4,rad*.4) if b else 0)

def sphere(n,p,s,c='lime',r='SEA_Matte',v=20,rr=12):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=v,ring_count=rr,radius=1,location=p)
 o=bpy.context.object;o.name=n;o.scale=s
 for f in o.data.polygons:f.use_smooth=True
 return finish(o,c,r)

def mesh(n,vs,fs,c='cream',r='SEA_Matte',bevel=0,smooth=False):
 me=bpy.data.meshes.new(n);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new(n,me);current.objects.link(o)
 for f in me.polygons:f.use_smooth=smooth
 return finish(o,c,r,bevel)

def tube(n,pts,rad,c='gold',r='SEA_Metal',sides=12):
 # Parallel-transport frame prevents twists on 90-degree handrail bends.
 pts=[Vector(p) for p in pts];vs=[]
 for i,p in enumerate(pts):
  tangent=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized()
  ref=Vector((0,0,1)) if abs(tangent.z)<.9 else Vector((0,1,0))
  u=tangent.cross(ref).normalized();v=tangent.cross(u).normalized()
  vs.extend(tuple(p+rad*(u*math.cos(j*TAU/sides)+v*math.sin(j*TAU/sides))) for j in range(sides))
 fs=[(i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j) for i in range(len(pts)-1) for j in range(sides)]
 fs += [tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))]
 return mesh(n,vs,fs,c,r,smooth=True)

def rod(n,a,b,rad,c='gold',r='SEA_Metal'):return tube(n,[a,b],rad,c,r)

def torus(n,p,major,minor,c='rubber',r='SEA_Matte',rot=(0,0,0),seg=36):
 bpy.ops.mesh.primitive_torus_add(major_segments=seg,minor_segments=12,location=p,rotation=rot,major_radius=major,minor_radius=minor)
 o=bpy.context.object;o.name=n
 for f in o.data.polygons:f.use_smooth=True
 return finish(o,c,r)

def round_rect_points(w,d,rad,z=0,steps=10):
 pts=[]
 for cx,cy,start in [(w/2-rad,-d/2+rad,-PI/2),(w/2-rad,d/2-rad,0),(-w/2+rad,d/2-rad,PI/2),(-w/2+rad,-d/2+rad,PI)]:
  for j in range(steps+1):
   a=start+j*PI/2/steps;pts.append((cx+rad*math.cos(a),cy+rad*math.sin(a),z))
 return pts

def slab(n,w,d,rad,z,h,c='cream',r='SEA_Matte',bevel=.08):
 lo=round_rect_points(w,d,rad,z);hi=round_rect_points(w,d,rad,z+h);N=len(lo)
 fs=[tuple(reversed(range(N))),tuple(N+i for i in range(N))]
 fs.extend((i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N))
 return mesh(n,lo+hi,fs,c,r,bevel)

def arc_panel(n,r0,r1,a0,a1,z,h,c='butter',r='SEA_Metal',steps=12,b=.035):
 vs=[]
 for j in range(steps+1):
  a=a0+(a1-a0)*j/steps
  for rad,zz in [(r0,z),(r1,z),(r1,z+h),(r0,z+h)]:vs.append((rad*math.cos(a),rad*math.sin(a),zz))
 fs=[(4*j+k,4*(j+1)+k,4*(j+1)+(k+1)%4,4*j+(k+1)%4) for j in range(steps) for k in range(4)]
 fs += [(3,2,1,0),tuple(4*steps+k for k in range(4))]
 return mesh(n,vs,fs,c,r,b)

def text(n,body,p,width,height,c='blue',depth=.055):
 cu=bpy.data.curves.new(n,'FONT');cu.body=body;cu.font=font;cu.size=1;cu.align_x='CENTER';cu.align_y='CENTER'
 cu.extrude=depth;cu.bevel_depth=.012;cu.bevel_resolution=3;cu.resolution_u=8
 o=bpy.data.objects.new(n,cu);current.objects.link(o);o.location=p;o.rotation_euler=(PI/2,0,0)
 bpy.context.view_layer.update();o.scale=(width/max(o.dimensions.x,.001),height/max(o.dimensions.z,.001),1)
 # Text local Y is the vertical direction after Rx; scale in the font plane.
 o.scale.y=height/max(cu.size*.74,.001)
 return finish(o,c,'SEA_Metal')

def part(k,build):
 global current
 row=next(x for x in PLAN['components'] if x['key']==k)
 current=bpy.data.collections.new(row['asset_id']);current['asset_id']=row['asset_id'];sc.collection.children.link(current);build()
 pts=[v.co.copy() for o in current.objects if o.type=='MESH' for v in o.data.vertices]
 lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)));hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
 pivot=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in current.objects:
  for v in o.data.vertices:v.co-=pivot
  o.data.update()
 current.instance_offset=(0,0,0);components[k]=current;sc.collection.children.unlink(current)
 catalog.append(dict(row,collection=current.name,design_pivot=list(pivot),bounds_min=[-(hi.x-lo.x)/2,-(hi.y-lo.y)/2,0],bounds_size=list(hi-lo),
  component_source=f'art_source/scenes/gift_kiosk/v001/component_packages/{k}/{k}.blend',
  version='v001',material_roles=sorted({o['role'] for o in current.objects}),meshes=len(current.objects)))
 print('BUILT',k,len(current.objects),flush=True)

def put(k,p=(0,0,0),a=0,scale=(1,1,1),rot=None):
 entry=next(x for x in catalog if x['key']==k);pv=Vector(entry['design_pivot'])
 o=bpy.data.objects.new(k+'_'+str(sum(x['key']==k for x in layout)+1).zfill(3),None)
 o.instance_type='COLLECTION';o.instance_collection=components[k];o.rotation_euler=rot or (0,0,a);o.scale=scale
 o.location=Vector(p)+o.rotation_euler.to_matrix()@Vector(tuple(pv[i]*scale[i] for i in range(3)))
 top[entry['group']].objects.link(o)
 layout.append({'name':o.name,'key':k,'asset_id':entry['asset_id'],'position':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale)})
 return o

def deck():
 slab('18米方形圆角承重甲板',18,18,2.0,.1,.2,'plaster',bevel=.085)
 # Inlaid tile seams are shallow, stop at the rounded perimeter, never form black cracks.
 for x in [-7.5,-6,-4.5,-3,-1.5,0,1.5,3,4.5,6,7.5]:
  lim=8.82 if abs(x)<7 else 7+math.sqrt(max(0,1.82**2-(abs(x)-7)**2))
  box('暖沙色铺砖纵缝',(x,0,.3005),(.018,lim*2,.005),'sand',b=.002)
 for y in [-7.5,-6,-4.5,-3,-1.5,0,1.5,3,4.5,6,7.5]:
  lim=8.82 if abs(y)<7 else 7+math.sqrt(max(0,1.82**2-(abs(y)-7)**2))
  box('暖沙色铺砖横缝',(0,y,.301),(lim*2,.018,.005),'sand',b=.002)
part('deck',deck)
part('hull',lambda:[slab('奶油厚实船舷',18.18,18.18,2.1,-.52,.62,'cream','SEA_Metal',.16),slab('深灰圆角护舷底盘',18.25,18.25,2.15,-1.02,.52,'gray','SEA_Metal',.16)])
part('underframe',lambda:[box('船底主梁',(0,0,.17),(1.1,15.6,.34),'steel','SEA_Metal',.12),box('船底横梁',(0,0,.17),(15.6,1.1,.34),'steel','SEA_Metal',.12),tube('船底电缆',[(-2.0,-6,.15),(-2,-2,.15),(0,0,.15),(2,2,.15),(2,6,.15)],.10,'slate')])
def pontoon():
 sphere('饱满橙色浮舱',(0,0,1.35),(2.04,2.04,1.35),'coral','SEA_Metal',32,20)
 cyl('浮舱顶金属箍',(0,0,2.2),1.92,.24,'ochre',v=40,b=.10)
 cyl('浮舱底圆帽',(0,0,.11),.48,.22,'slate',b=.07)
 torus('浮舱中圈接缝',(0,0,1.4),2.015,.027,'ochre',seg=40)
part('pontoon',pontoon)
def thruster():
 for z,rad,h in [(1.5,1.55,.48),(.99,1.25,.55),(.55,.94,.42),(.22,.68,.26)]:cyl('推进器阶梯收口',(0,0,z),rad,h,'gray' if z>1 else 'steel',v=48,b=.10)
 for z,rad in [(.77,1.10),(.36,.82)]:torus('推进器黄色发光圈边',(0,0,z),rad,.075,'gold','SEA_Metal',seg=40)
 for x in [-.8,.8]:box('推进器固定耳',(x,0,1.63),(.32,1.6,.45),'steel','SEA_Metal',.10)
part('thruster',thruster)
part('thruster_glow',lambda:[cyl('推进器暖黄灯芯',(0,0,.035),.51,.07,'yellow','SEA_Emission',v=40,b=.025),torus('喷口发光环',(0,0,.36),.80,.055,'gold','SEA_Emission')])
part('deck_light',lambda:[box('护舷灯灰色包框',(0,0,.13),(1.08,.16,.26),'steel','SEA_Metal',.115),box('胶囊暖黄灯芯',(0,-.10,.13),(.84,.065,.14),'gold','SEA_Emission',.062)])
def railpost():
 cyl('护栏灰脚座',(0,0,.085),.23,.17,'gray',b=.07)
 cyl('护栏立柱',(0,0,.54),.12,.93,'gold',b=.045)
 sphere('护栏饱满球头',(0,0,1.06),(.21,.21,.23),'gold','SEA_Metal')
part('rail_post',railpost)
part('rail_bar',lambda:rod('黄色横栏',(-.75,0,.0),(.75,0,.0),.115))
part('rail_corner',lambda:tube('圆角连续黄色栏杆',[(1.55*math.cos(-PI/2+i*PI/2/16),1.55*math.sin(-PI/2+i*PI/2/16),.0) for i in range(17)],.115))
def fender():
 torus('饱满轮胎护舷',(0,0,.83),.64,.235,'rubber',rot=(PI/2,0,0),seg=40)
 torus('轮胎内沿',(0,-.10,.83),.43,.065,'slate',rot=(PI/2,0,0),seg=40)
 tube('轮胎挂绳',[(0,.08,1.63),(0,.06,2.05),(0,.20,2.15)],.055,'wood_dark','SEA_Matte')
part('fender',fender)
def ladder():
 for x in [-.58,.58]:
  tube('梯子圆头扶手',[(x,.18,0),(x,.18,3.1),(x,.13,3.3),(x,-.05,3.42),(x,-.24,3.38),(x,-.32,3.2),(x,-.32,2.8)],.105)
 for z in [.24,.70,1.16,1.62,2.08,2.54]:rod('圆杆踏步',(-.58,.18,z),(.58,.18,z),.09)
 box('梯脚圆角横踏板',(0,.18,.08),(1.42,.55,.16),'ochre','SEA_Metal',.07)
part('ladder',ladder)
part('bollard',lambda:[cyl('系泊柱底座',(0,0,.07),.26,.14,'slate',b=.06),cyl('黄色系泊柱',(0,0,.35),.14,.56,'gold',b=.05),rod('系泊柱双耳',(-.36,0,.57),(.36,0,.57),.095)])
def pot():
 cyl('花盆饱满盆体',(0,0,.36),.55,.72,'cream',v=32,b=.16)
 torus('花盆厚圆口',(0,0,.71),.51,.085,'white')
 cyl('花盆土壤',(0,0,.73),.445,.035,'wood_dark',v=28,b=.01)
part('pot',pot)
def foliage():
 rod('植物短树干',(0,0,.13),(0,0,.82),.10,'bark','SEA_Matte')
 for p,s,c in [((0,0,1.05),(.53,.53,.52),'leaf'),((-.38,-.10,.78),(.40,.40,.42),'lime'),((.35,-.1,.84),(.45,.42,.44),'leaf_yellow'),((-.18,.30,.95),(.43,.42,.45),'leaf_mid'),((.20,.21,1.22),(.37,.35,.38),'leaf')]:sphere('饱满圆球叶簇',p,s,c)
part('foliage',foliage)
def bench():
 for x in [-1.16,1.16]:
  box('青蓝凳腿',(x,0,.40),(.20,.78,.8),'teal','SEA_Metal',.075)
  box('靠背立柱',(x,.37,.88),(.16,.16,1.35),'teal','SEA_Metal',.06)
 for y in [-.31,0,.31]:box('长凳厚实座木',(0,y,.80),(3.0,.29,.19),'wood_light','SEA_Matte',.075)
 for z in [1.13,1.45]:box('长凳厚实靠背',(0,.39,z),(3,.18,.25),'wood','SEA_Matte',.075)
part('bench',bench)
def glass_bay():
 box('橱窗奶油矮墙',(0,0,.39),(2.4,.26,.78),'cream',b=.10)
 box('透明浅蓝橱窗',(0,-.04,2.8),(2.20,.045,4.14),'sky','SEA_Gloss',.018)
 for x in [-1.15,1.15]:box('青蓝窗竖框',(x,-.12,2.45),(.18,.25,4.9),'teal','SEA_Metal',.07)
 for z in [.85,4.80]:box('青蓝窗横框',(0,-.13,z),(2.4,.26,.16),'teal','SEA_Metal',.065)
 box('橱窗细中档',(0,-.16,2.75),(.09,.14,3.85),'aqua','SEA_Metal',.035)
part('glass_bay',glass_bay)
def back_panel():
 box('后墙奶黄板',(0,0,2.45),(2.4,.30,4.9),'cream',b=.11)
 for z in [1.20,2.45,3.70]:box('后墙浅线缝',(0,.158,z),(2.14,.012,.018),'sand',b=.004)
part('back_panel',back_panel)
part('column',lambda:box('青蓝饱满圆角主柱',(0,0,2.45),(.5,.5,4.9),'teal','SEA_Metal',.095))
def back_door():
 box('灰蓝检修门外框',(0,0,1.7),(1.9,.28,3.4),'steel','SEA_Metal',.22)
 box('奶灰门扇',(0,-.16,1.67),(1.61,.11,3.07),'lightgray','SEA_Metal',.17)
 box('小门玻璃',(0,-.23,2.45),(.83,.055,.85),'teal','SEA_Gloss',.15)
 rod('黄色门把手',(.54,-.32,1.2),(.54,-.32,1.60),.055)
part('back_door',back_door)
def roof():
 slab('奶黄圆角平屋顶',12,12,2.1,0,.2,'plaster','SEA_Metal',.085)
 tube('屋顶黄色圆角檐边',round_rect_points(11.85,11.85,2.0,.31)+[round_rect_points(11.85,11.85,2.0,.31)[0]],.10)
 for x in [-3,-1.5,0,1.5,3]:box('屋顶浅砖缝',(x,0,.201),(.018,11.2,.005),'sand',b=.001)
 for y in [-3,-1.5,0,1.5,3]:box('屋顶浅砖缝',(0,y,.202),(11.2,.018,.005),'sand',b=.001)
part('roof',roof)
def fascia():
 box('灯箱圆角黄色外框',(0,0,.72),(7.8,.32,1.44),'gold','SEA_Metal',.13)
 box('灯箱奶黄面',(0,-.192,.72),(7.54,.11,1.18),'butter','SEA_Matte',.10)
 for x in [-3.64,3.64]:
  for z in [.20,1.24]:sphere('灯箱圆铆钉',(x,-.27,z),(.065,.035,.065),'ochre','SEA_Metal',12,8)
part('fascia',fascia)
def fascia_corner():
 arc_panel('圆角灯箱外框',1.77,2.10,-PI/2,0,0,1.44,'gold',steps=16,b=.055)
 arc_panel('圆角奶黄招牌面',2.103,2.16,-PI/2+.06,-.06,.13,1.18,'butter','SEA_Matte',steps=16,b=.023)
part('fascia_corner',fascia_corner)
def signpost():
 text('POSTCARDS立体蓝字','POSTCARDS',(-.52,-.04,.57),4.65,.92,'blue')
 box('信封圆角卡片',(2.55,0,.57),(1.03,.11,.72),'cream','SEA_Matte',.055)
 for a,b in [((2.07,-.075,.88),(2.55,-.075,.48)),((2.55,-.075,.48),(3.03,-.075,.88)),((2.07,-.075,.23),(2.44,-.075,.53)),((2.66,-.075,.53),(3.03,-.075,.23))]:rod('信封压线',a,b,.025,'wood_mid','SEA_Matte')
part('sign_postcards',signpost)
def signgift():
 text('GIFTS立体红字','GIFTS',(-.38,-.04,.55),2.65,.89,'red_dark')
 box('招牌红色礼盒',(1.55,-.01,.48),(.61,.18,.65),'red_dark','SEA_Metal',.06)
 box('招牌黄色礼带',(1.55,-.12,.49),(.11,.04,.66),'gold','SEA_Metal',.018)
 box('招牌黄色礼带',(1.55,-.125,.52),(.62,.04,.095),'gold','SEA_Metal',.018)
 for x,a in [(1.40,-.4),(1.69,.4)]:torus('礼物蝴蝶结',(x,-.05,.90),.14,.045,'red_dark','SEA_Metal',rot=(PI/2,0,a),seg=20)
part('sign_gifts',signgift)
def signdrink():
 text('COLD DRINKS立体蓝字','COLD DRINKS',(.42,-.04,.53),4.9,.88,'blue')
 cyl('红色饮料杯',(-2.78,0,.44),.22,.72,'red_dark',v=24,b=.065)
 cyl('蓝色杯盖',(-2.78,0,.82),.24,.09,'aqua',v=24,b=.035)
 rod('饮料杯吸管',(-2.78,0,.86),(-2.68,0,1.09),.035,'gold')
part('sign_drinks',signdrink)
def awning(c):
 # Convex roof section and half-round scallop: 3D fabric thickness, no paper edge.
 vs=[];N=12
 for j in range(N+1):
  x=-.325+j*.65/N;drop=.16+.20*math.sqrt(max(0,1-(x/.325)**2))
  for y,z in [(.44,.68),(-.62,.42),(-.70,.30),(-.70,.30-drop),(-.60,.30-drop),(-.60,.39),(.44,.78)]:vs.append((x,y,z))
 fs=[(j*7+k,(j+1)*7+k,(j+1)*7+(k+1)%7,j*7+(k+1)%7) for j in range(N) for k in range(7)]
 fs += [tuple(reversed(range(7))),tuple(N*7+k for k in range(7))]
 mesh('饱满圆垂布棚',vs,fs,c,'SEA_Matte',.027)
part('awning_blue',lambda:awning('solar'));part('awning_white',lambda:awning('snow'))
def awning_corner():
 for j in range(6):
  a0=-PI/2+j*PI/12;a1=a0+PI/12
  # radial wedges, each with its own rounded scallop
  n=8;vs=[]
  for q in range(n+1):
   t=q/n;a=a0+(a1-a0)*t;drop=.16+.20*math.sin(PI*t)
   for rr,z in [(1.6,.74),(2.67,.43),(2.72,.30),(2.72,.30-drop),(2.62,.30-drop),(2.62,.39),(1.6,.81)]:vs.append((rr*math.cos(a),rr*math.sin(a),z))
  fs=[(q*7+k,(q+1)*7+k,(q+1)*7+(k+1)%7,q*7+(k+1)%7) for q in range(n) for k in range(7)]
  fs += [tuple(reversed(range(7))),tuple(n*7+k for k in range(7))]
  mesh('转角蓝白圆垂雨棚',vs,fs,'solar' if j%2==0 else 'snow',bevel=.024)
part('awning_corner',awning_corner)
def roof_disk():
 cyl('屋顶奶黄圆盘',(0,0,.47),1.77,.94,'yellow',v=64,b=.22)
 cyl('圆盘顶黄色包边',(0,0,.98),1.79,.16,'gold',v=64,b=.07)
 sphere('奶白饱满穹盖',(0,0,1.22),(1.48,1.48,.65),'snow','SEA_Metal',48,20)
 cyl('穹盖蓝色小顶',(0,0,1.85),.47,.30,'aqua',v=40,b=.12)
part('roof_disk',roof_disk)
def spotlight():
 cyl('射灯灰色脚座',(0,0,.10),.29,.20,'gray',b=.07)
 rod('射灯短支架',(0,0,.15),(0,0,.72),.13,'slate')
 tube('射灯弯头',[(0,0,.70),(0,0,.84),(0,-.12,.96),(0,-.28,.97)],.14,'slate')
 # spotlight lens faces forward and down, a soft rounded can rather than a sharp cylinder
 sphere('射灯圆润罩壳',(0,-.30,1.02),(.37,.34,.37),'slate','SEA_Metal',24,14)
 torus('射灯黄色外圈',(0,-.573,1.0),.255,.070,'ochre','SEA_Metal',rot=(PI/2,0,0))
 sphere('射灯暖黄玻璃',(0,-.595,1.0),(.23,.055,.23),'gold','SEA_Emission',24,12)
part('spotlight',spotlight)
part('roof_pipe',lambda:[cyl('管脚圆座',(-.58,0,.08),.26,.16,'gray',b=.05),cyl('管脚圆座',(.58,0,.08),.26,.16,'gray',b=.05),tube('屋顶黑色U形弯管',[(-.58,0,.14),(-.58,0,.65),(-.48,0,.80),(-.30,0,.86),(.30,0,.86),(.48,0,.8),(.58,0,.65),(.58,0,.14)],.16,'slate')])
def beacon():
 cyl('信号灯脚座',(0,0,.10),.3,.20,'slate',b=.05)
 cyl('信号灯深灰立柱',(0,0,.65),.14,1.1,'slate',b=.045)
 cyl('信号灯橙底座',(0,0,1.24),.36,.16,'ochre',b=.05)
 sphere('橙色信号灯罩',(0,0,1.52),(.34,.34,.42),'gold','SEA_Emission',32,16)
part('beacon',beacon)
def ebox():
 box('后墙检修盒',(0,0,.50),(1.1,.25,1.0),'lightgray','SEA_Metal',.13)
 for x in [-.38,.38]:
  for z in [.15,.85]:sphere('检修盒铆钉',(x,-.15,z),(.045,.025,.045),'ochre','SEA_Metal',12,8)
 box('盒上小把手',(.25,-.17,.50),(.15,.05,.28),'gray','SEA_Metal',.035)
part('electrical_box',ebox)
def life_ring():
 # Alternate red/white torus quadrants, true curved geometry with a real central hole.
 N=64;M=12;vs=[]
 for j in range(N):
  a=j*TAU/N
  for k in range(M):
   b=k*TAU/M;rr=.58+.18*math.cos(b);vs.append((rr*math.cos(a),.18*math.sin(b),.78+rr*math.sin(a)))
 for q,c in enumerate(['red_dark','snow']*4):
  fs=[(j*M+k,((j+1)%N)*M+k,((j+1)%N)*M+(k+1)%M,j*M+(k+1)%M) for j in range(q*8,(q+1)*8) for k in range(M)]
  mesh('红白救生圈弧段',vs,fs,c,smooth=True)
 torus('救生圈外绑绳',(0,.03,.78),.80,.027,'wood_light',rot=(PI/2,0,0),seg=48)
part('life_ring',life_ring)
def rack():
 cyl('明信片架黄色底盘',(0,0,.08),.55,.16,'gold',v=32,b=.06)
 rod('明信片架中轴',(0,0,.14),(0,0,2.96),.065)
 for a in [0,2*PI/3,4*PI/3]:
  mat=Matrix.Rotation(a,4,'Z')
  for z in [.62,1.25,1.88,2.51]:
   for x in [-.27,.27]:
    p=mat@Vector((x,-.37,z));o=box('明信片架奶白口袋',p,(.49,.08,.57),'snow',b=.04)
    o.data.transform(Matrix.Translation(p)@Matrix.Rotation(a,4,'Z')@Matrix.Translation(-p))
    p2=mat@Vector((x,-.425,z+.04));o=box('明信片橙色画面',p2,(.37,.03,.39),'gold' if z<1.7 else 'aqua',b=.03)
    o.data.transform(Matrix.Translation(p2)@Matrix.Rotation(a,4,'Z')@Matrix.Translation(-p2))
    p3=mat@Vector((x-.05,-.45,z+.08));sphere('卡片简约圆形图案',p3,(.095,.022,.095),'solar' if z<1.7 else 'coral',v=12,rr=8)
part('postcard_rack',rack)
def mailbox():
 box('红色圆角邮筒',(0,0,.95),(1.08,.76,1.75),'red_dark','SEA_Metal',.18)
 box('邮筒倾斜顶盖',(0,-.02,1.89),(1.10,.79,.21),'red_dark','SEA_Metal',.09)
 box('投信黑色开口',(0,-.397,1.48),(.75,.03,.12),'rubber',b=.04)
 box('投信口奶白条',(0,-.42,1.64),(.52,.03,.05),'snow',b=.015)
 for x in [-.37,.37]:box('邮筒短脚',(x,0,.10),(.14,.45,.20),'slate','SEA_Metal',.035)
part('mailbox',mailbox)
def icebox():
 box('ICE奶白冰柜',(0,0,.93),(2.10,1.08,1.86),'snow','SEA_Metal',.20)
 box('冰柜厚盖',(0,0,1.94),(2.16,1.14,.20),'white','SEA_Metal',.09)
 box('冰柜中缝',(0,-.554,.79),(1.91,.02,.028),'lightgray',b=.006)
 text('ICE立体蓝字','ICE',(.10,-.59,1.46),1.12,.62,'solar',.018)
 for x in [-.76,.76]:
  for z in [.26,1.74]:sphere('冰柜门铆钉',(x,-.567,z),(.032,.015,.032),'gray','SEA_Metal',12,8)
 for x in [-.68,.68]:box('冰柜短脚',(x,0,.08),(.20,.70,.16),'gray',b=.045)
 for x in [-.66,-.23,.20]:cyl('冰柜顶彩色小按钮',(x,-.29,2.08),.07,.10,'aqua' if x<0 else 'gold',v=16,b=.025)
part('ice_box',icebox)
part('bin',lambda:[box('黄色分类垃圾桶',(0,0,.62),(.58,.62,1.24),'gold','SEA_Metal',.11),box('垃圾桶圆盖',(0,0,1.28),(.63,.66,.16),'yellow','SEA_Metal',.07),box('垃圾桶投入口',(0,-.33,1.12),(.36,.03,.15),'ochre',b=.04)])
def shelf():
 for x in [-1.07,1.07]:box('货架暖木侧柱',(x,.10,1.50),(.14,.64,3.0),'wood','SEA_Matte',.055)
 for z in [.12,1.06,2,2.94]:box('厚木货架层板',(0,0,z),(2.30,.82,.16),'wood_light','SEA_Matte',.055)
 box('货架暗暖背板',(0,.39,1.50),(2.27,.09,2.9),'wood_dark',b=.03)
part('shelf',shelf)
part('bottle',lambda:[cyl('彩色饮料瓶身',(0,0,.26),.15,.52,'ochre',v=20,b=.065),cyl('饮料短瓶颈',(0,0,.58),.075,.15,'gold',v=16,b=.025),cyl('饮料红瓶盖',(0,0,.68),.085,.08,'red_dark',v=16,b=.02),cyl('饮料奶白标签',(0,0,.30),.153,.19,'cream',v=20,b=.01)])
part('gift',lambda:[box('红色礼品盒',(0,0,.28),(.58,.48,.56),'red_dark','SEA_Matte',.075),box('黄色礼品带',(0,-.252,.28),(.09,.025,.54),'gold','SEA_Metal',.012),box('黄色礼盒盖带',(0,0,.575),(.09,.48,.035),'gold','SEA_Metal',.01),box('礼品厚盒盖',(0,0,.56),(.62,.52,.12),'coral','SEA_Matte',.045)])
part('card',lambda:[box('奶白卡片底',(0,0,.25),(.40,.035,.50),'snow',b=.025),box('蓝色卡片插画',(0,-.026,.27),(.32,.018,.35),'aqua',b=.02),sphere('卡片暖黄太阳',(.075,-.04,.36),(.065,.008,.065),'gold',v=12,rr=8)])
def lantern():
 cyl('紫色圆筒灯壳',(0,0,.41),.21,.82,'lavender','SEA_Metal',v=24,b=.06)
 for z in [.06,.76]:cyl('圆筒灯深灰端盖',(0,0,z),.25,.12,'slate',b=.045)
 for z in [.26,.49]:sphere('圆筒灯小灯点',(0,-.21,z),(.045,.022,.06),'gold','SEA_Emission',v=12,rr=8)
part('lantern',lantern)
part('plaque',lambda:[box('船底检修板',(0,0,.07),(1.35,1.35,.14),'gray','SEA_Metal',.12)]+[cyl('检修板圆铆钉',(x,y,.16),.065,.06,'ochre',v=12,b=.02) for x in [-.48,.48] for y in [-.48,.48]])
def curved_glass():
 arc_panel('圆角奶白矮墙',1.36,1.56,-PI/2,0,0,.78,'cream','SEA_Matte',steps=16,b=.045)
 arc_panel('圆角浅蓝玻璃',1.48,1.52,-PI/2,0,.82,3.98,'sky','SEA_Gloss',steps=20,b=.01)
 for z in [.83,4.81]:tube('圆角青蓝窗横档',[(1.54*math.cos(-PI/2+j*PI/2/20),1.54*math.sin(-PI/2+j*PI/2/20),z) for j in range(21)],.085,'teal')
 for a in [-PI/2,-PI/4,0]:
  x,y=1.54*math.cos(a),1.54*math.sin(a);rod('圆角青蓝窗竖档',(x,y,.0),(x,y,4.9),.09,'teal')
part('curved_glass',curved_glass)
def entry():
 for x in [-1.33,1.33]:box('开放入口圆角青蓝柱',(x,0,2.45),(.26,.40,4.9),'teal','SEA_Metal',.095)
 box('开放入口青蓝横梁',(0,0,4.72),(2.9,.4,.36),'teal','SEA_Metal',.12)
 box('入口米黄门槛',(0,0,.06),(2.9,.60,.12),'cream',b=.055)
part('entry_frame',entry)

# Assemble: square building and round-corner square deck, no circular drum shell.
put('deck');put('hull');put('underframe',(0,0,-1.34))
for x in [-6.0,6.0]:
 for y in [-6.0,6.0]:put('pontoon',(x,y,-3.30));put('plaque',(x,y,-1.20))
put('thruster',(0,0,-3.0));put('thruster_glow',(0,0,-3.0))
# Three cream/grey hull edge lamps per side.
for a in [0,PI/2,PI,3*PI/2]:
 rot=Matrix.Rotation(a,3,'Z')
 for u in [-5.9,0,5.9]:put('deck_light',rot@Vector((u,-9.20,-.80)),a)
# Railing, front centre left clear for boarding. All seats/props remain outside its corridor.
for a in [0,PI/2,PI,3*PI/2]:
 mat=Matrix.Rotation(a,3,'Z')
 for u in [-7,-5.6,-4.2,-2.8,-1.4,0,1.4,2.8,4.2,5.6,7]:
  if a==0 and abs(u)<1.5:continue
  put('rail_post',mat@Vector((u,-8.55,.3)),a)
 for u in [-6.3,-4.9,-3.5,-2.1,-.7,.7,2.1,3.5,4.9,6.3]:
  if a==0 and abs(u)<2.1:continue
  put('rail_bar',mat@Vector((u,-8.55,1.36)),a,scale=(1.4/1.5,1,1))
 for u in [-5.6,0,5.6]:
  if a==0 and u==0:continue
  put('fender',mat@Vector((u,-9.32,-1.55)),a)
 # local quarter-circle rails are centred at the deck's arc centres.
 put('rail_corner',mat@Vector((7,-7,1.36)),a)
for p in [(-7,-7),(-7,7),(7,7),(7,-7)]:
 put('pot',(*p,.3));put('foliage',(*p,1.02))
put('bench',(-7.05,0,.3),-PI/2);put('bench',(7.05,1.3,.3),PI/2)
put('ladder',(4.0,-9.0,-2.48));put('bollard',(-2.8,-8.18,.3));put('bollard',(2.8,-8.18,.3))
# Body front faces -Y; front centre remains a real open 2.4m entrance.
for x in [-2.6,2.6]:put('glass_bay',(x,-5.4,.3))
put('entry_frame',(0,-5.4,.3))
for a in [PI/2,3*PI/2]:
 mat=Matrix.Rotation(a,3,'Z')
 for u in [-2.6,0,2.6]:put('glass_bay',mat@Vector((u,-5.4,.3)),a)
for x in [-2.6,0,2.6]:put('back_panel',(x,5.4,.3))
put('back_door',(0,5.62,.3),PI)
for x,y,a in [(3.9,-3.9,0),(3.9,3.9,PI/2),(-3.9,3.9,PI),(-3.9,-3.9,3*PI/2)]:put('curved_glass',(x,y,.3),a)
for x,y in [(-3.85,-5.35),(3.85,-5.35),(-5.35,3.85),(5.35,3.85)]:put('column',(x,y,.3))
put('roof',(0,0,6.62))
for a in [0,PI/2,PI,3*PI/2]:
 mat=Matrix.Rotation(a,3,'Z');put('fascia',mat@Vector((0,-5.95,5.45)),a)
 put('fascia_corner',mat@Vector((3.9,-3.9,5.45)),a)
 for j in range(12):put('awning_blue' if j%2==0 else 'awning_white',mat@Vector((-3.575+j*.65,-5.57,4.64)),a)
 put('awning_corner',mat@Vector((3.9,-3.9,4.64)),a)
# Main reference shows POSTCARDS front, GIFTS on the rounded corner, drinks on the right.
put('sign_postcards',(0,-6.20,5.62))
put('sign_drinks',(6.20,0,5.62),PI/2)
put('sign_gifts',(5.51,-5.51,5.62),PI/4,scale=(.86,.86,.86))
put('sign_gifts',(0,6.20,5.62),PI)
put('sign_postcards',(-6.20,0,5.62),-PI/2)
put('roof_disk',(0,0,6.86))
for p,a in [((-3.6,-3.4),-.3),((3.5,-3.0),.5),((3.9,3.1),2.5),((-3.8,3.4),3.6)]:put('spotlight',(*p,6.87),a)
put('roof_pipe',(2.85,1.4,6.87),.3);put('roof_pipe',(-3.0,.4,6.87),-PI/2)
put('beacon',(-2.1,2.9,6.87))
for p,a in [((-5.48,-2.7),-PI/2),((5.48,2.7),PI/2)]:put('life_ring',(*p,2.40),a)
for x in [-2.7,2.7]:put('electrical_box',(x,5.64,1.02),PI)
put('roof_pipe',(2.0,5.72,1.70),PI/2,scale=(1.0,1.0,2.4))
for x in [-6.08,6.08]:
 for y in [-3.9,3.9]:put('lantern',(x,y,5.6))
# Reference storefront accessories, each remains a separate component instance.
put('postcard_rack',(-2.8,-6.35,.3),-.12)
put('mailbox',(-1.36,-6.05,.3))
put('ice_box',(5.93,-3.05,.3),PI/2)
put('bin',(1.50,-5.97,.3))
put('pot',(-4.35,-5.98,.3),scale=(.65,.65,.65));put('foliage',(-4.35,-5.98,.77),scale=(.55,.55,.55))
# Warm and varied shelves are actually modelled behind the transparent windows.
for x in [-2.65,2.65]:
 put('shelf',(x,4.60,.3))
 for z in [.61,1.55,2.49]:
  for u in [-.70,-.24,.25,.72]:put('bottle' if (u<0) else 'gift',(x+u,4.48,z+.3),scale=(.75,.75,.85))
for a in [-PI/2,PI/2]:
 mat=Matrix.Rotation(a,3,'Z')
 for y in [-2.6,.6,3.2]:
  put('shelf',mat@Vector((y,-4.6,.3)),a)
  for z in [.61,1.55,2.49]:
   for u in [-.70,-.24,.25,.72]:put('bottle' if u<0 else 'gift',mat@Vector((y+u,-4.88,z+.3)),a,scale=(.74,.74,.85))
for x in [-2.6,2.6]:
 put('shelf',(x,-4.65,.3))
 for z in [.61,1.55,2.49]:
  for u in [-.70,-.24,.25,.72]:put('bottle' if u<0 else 'gift',(x+u,-4.94,z+.3),scale=(.74,.74,.85))
# A short inviting interior counter leaves the front entry view open.
put('shelf',(2.3,-1.4,.3),PI,scale=(1.2,1,.60))
for x in [1.5,2.2,2.9]:put('gift',(x,-1.4,2.19),scale=(.8,.8,.8))
for x in [-2.5,-2,-1.5]:put('card',(x,-4.65,1.80))

# Studio support, excluded from every source component/GLB.
current=top['display']
backdrop=box('展示地面_不导出',(0,0,-3.50),(200,200,.15),'cream',b=.01)
mat=bpy.data.materials.new('GKS_Studio_Backdrop');mat.diffuse_color=(.87,.82,.74,1);mat.use_nodes=True
bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].default_value=(.87,.82,.74,1);bs.inputs['Roughness'].default_value=.83
backdrop.data.materials.clear();backdrop.data.materials.append(mat)
def area(n,p,energy,size):
 data=bpy.data.lights.new(n,'AREA');data.energy=energy;data.shape='DISK';data.size=size
 o=bpy.data.objects.new(n,data);current.objects.link(o);o.location=p;o.rotation_euler=(Vector((0,0,2.7))-o.location).to_track_quat('-Z','Y').to_euler()
area('主柔光',(-12,-16,25),3500,12);area('右侧柔光',(14,-3,18),1800,10);area('后侧柔光',(1,14,20),2200,10)
sun=bpy.data.lights.new('阳光','SUN');sun.energy=1.5;sun.angle=math.radians(18)
o=bpy.data.objects.new('阳光',sun);current.objects.link(o);o.rotation_euler=(.4,-.5,-.4)
cam=bpy.data.cameras.new('GKS_参考相机');camera=bpy.data.objects.new('GKS_参考相机',cam);current.objects.link(camera);sc.camera=camera
camera.location=(25,-32,17.4);camera.rotation_euler=(Vector((0,0,2.7))-camera.location).to_track_quat('-Z','Y').to_euler()
cam.type='ORTHO';cam.ortho_scale=27.6;cam.lens=50
sc.render.engine='CYCLES';sc.cycles.samples=32;sc.cycles.use_denoising=True
try:
 pref=bpy.context.preferences.addons['cycles'].preferences;pref.compute_device_type='OPTIX';pref.get_devices()
 for dev in pref.devices:dev.use=dev.type!='CPU'
 sc.cycles.device='GPU' if any(d.use for d in pref.devices) else 'CPU'
except Exception:pass
sc.render.resolution_x=1700;sc.render.resolution_y=1500;sc.render.resolution_percentage=100
sc.render.image_settings.file_format='PNG';sc.view_settings.view_transform='Standard';sc.view_settings.look='Medium High Contrast';sc.view_settings.exposure=-.65
bpy.context.preferences.filepaths.save_version=0
for area_ui in bpy.context.screen.areas:
 if area_ui.type=='VIEW_3D':
  area_ui.spaces.active.region_3d.view_perspective='CAMERA';area_ui.spaces.active.shading.type='MATERIAL'
for e in catalog:e['instances']=sum(x['key']==e['key'] for x in layout)
(D/'catalog.json').write_text(json.dumps({'schema':'sea.scene.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.instances','up_axis':'Z','front_axis':'-Y','godot_mapping':'(x,y,z)->(x,z,-y)','instances':layout},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
image.filepath=bpy.path.relpath(str(PAL),start=str(D))
bpy.ops.wm.save_as_mainfile(filepath=str(D/'gift_kiosk.blend'),compress=True)
sc.render.filepath=str(W/'hero_initial.png');bpy.ops.render.render(write_still=True)
print('GKS_CREATED',json.dumps({'components':len(catalog),'instances':len(layout),'source':str(D/'gift_kiosk.blend'),'preview':sc.render.filepath}),flush=True)

"""Build the reference shop through Blender MCP, in a new GUI scene."""
import bpy, bmesh, math, json, hashlib, random, os
from pathlib import Path
from mathutils import Vector, Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v001';W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop'
random.seed(1030)
if not (W/'session_before.blend').exists():
 bpy.ops.wm.save_as_mainfile(filepath=str(W/'session_before.blend'),copy=True)
old=bpy.data.scenes.get('海上悬浮商铺_v001')
if old:
 bpy.data.scenes.remove(old)
for c in list(bpy.data.collections):
 if c.name.startswith('SEA-SCENE-FSH-') or c.name.startswith('FSH_'):
  for o in list(c.objects):bpy.data.objects.remove(o,do_unlink=True)
  bpy.data.collections.remove(c)
sc=bpy.data.scenes.new('海上悬浮商铺_v001');bpy.context.window_manager.windows[0].scene=sc;sc.unit_settings.system='METRIC'
pal=R/'art_source/shared/palettes/sea_cozy_8x8_512.png';colors={x['name']:x for x in json.loads(pal.with_suffix('.json').read_text())['cells']}
im=bpy.data.images.load(str(pal),check_existing=True);im.filepath=str(pal)
roles={}
for name,metal,rough in [('SEA_Matte',0,.6),('SEA_Metal',.55,.38),('SEA_Gloss',.05,.16),('SEA_Emission',.1,.25)]:
 m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;n.clear()
 out=n.new('ShaderNodeOutputMaterial');bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
 uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';tx=n.new('ShaderNodeTexImage');tx.image=im;tx.interpolation='Closest';l.new(uv.outputs['UV'],tx.inputs['Vector']);l.new(tx.outputs['Color'],bs.inputs['Base Color']);l.new(bs.outputs[0],out.inputs['Surface'])
 if name=='SEA_Gloss':bs.inputs['Transmission Weight'].default_value=.65;bs.inputs['Alpha'].default_value=.24;m.surface_render_method='DITHERED';m.use_transparency_overlap=False
 if name=='SEA_Emission':l.new(tx.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=2.5
 roles[name]=m

def finish(o,cell,role='SEA_Matte',bevel=0,smooth=False):
 o['palette_cell']=cell;o.data.materials.clear();o.data.materials.append(roles[role])
 if bevel:
  mo=o.modifiers.new('真实圆角','BEVEL');mo.width=bevel;mo.segments=3
 if smooth:
  for f in o.data.polygons:f.use_smooth=True
 return o
def cube(n,p,s,c='cream',role='SEA_Matte',bevel=.035,rot=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=n;o.dimensions=s;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if rot:o.rotation_euler=rot
 return finish(o,c,role,bevel)
def cyl(n,p,r,h,c='cream',role='SEA_Metal',r2=None,rot=None,verts=48,bevel=.025):
 if r2 is None:bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=h,location=p)
 else:bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=r,radius2=r2,depth=h,location=p)
 o=bpy.context.object;o.name=n
 if rot:o.rotation_euler=rot
 finish(o,c,role,bevel)
 for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
 return o
def sphere(n,p,s,c='cream',role='SEA_Matte',seg=32,rings=16):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,location=p);o=bpy.context.object;o.name=n;o.scale=s;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);return finish(o,c,role,0,True)
def rod(n,a,b,r,c='steel',role='SEA_Metal'):
 a=Vector(a);b=Vector(b);o=cyl(n,(a+b)/2,r,(b-a).length,c,role,verts=16,bevel=.008);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def tube(n,pts,r,c='steel',role='SEA_Metal'):
 cu=bpy.data.curves.new(n,'CURVE');cu.dimensions='3D';cu.resolution_u=1;cu.bevel_depth=r;cu.bevel_resolution=3
 sp=cu.splines.new('POLY');sp.points.add(len(pts)-1)
 for p,v in zip(sp.points,pts):p.co=(*v,1)
 o=bpy.data.objects.new(n,cu);sc.collection.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o=bpy.context.object;o.name=n
 return finish(o,c,role,0,True)
def torus(n,p,major,minor,c='rubber',rot=(0,0,0),role='SEA_Matte'):
 bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=48,minor_segments=12,location=p,rotation=rot);o=bpy.context.object;o.name=n;return finish(o,c,role,0,True)
def mesh(n,vs,fs,c='cream',role='SEA_Matte',bev=0):
 me=bpy.data.meshes.new(n);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new(n,me);sc.collection.objects.link(o);return finish(o,c,role,bev)
def arc(n,r0,r1,z0,z1,a0,a1,c='cream',steps=24,role='SEA_Matte',bev=.015):
 vs=[]
 for i in range(steps+1):
  a=a0+(a1-a0)*i/steps
  for r,z in [(r0,z0),(r1,z0),(r1,z1),(r0,z1)]:vs.append((r*math.sin(a),-r*math.cos(a),z))
 fs=[]
 for i in range(steps):
  for j in range(4):fs.append((4*i+j,4*i+(j+1)%4,4*(i+1)+(j+1)%4,4*(i+1)+j))
 fs += [(3,2,1,0),tuple(steps*4+j for j in range(4))]
 return mesh(n,vs,fs,c,role,bev)
def text(n,body,p,size,c='blue',rot=(math.pi/2,0,0)):
 cu=bpy.data.curves.new(n,'FONT');cu.body=body;cu.align_x='CENTER';cu.align_y='CENTER';cu.size=size;cu.extrude=.007;cu.bevel_depth=.0025;cu.bevel_resolution=2
 # Use a rounded bold system font where available.
 fp=Path('C:/Windows/Fonts/arialbd.ttf')
 if fp.exists():
  font=bpy.data.fonts.get('Arial Bold') or bpy.data.fonts.load(str(fp));cu.font=font
 o=bpy.data.objects.new(n,cu);sc.collection.objects.link(o);o.location=p;o.rotation_euler=rot;bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');return finish(bpy.context.object,c)
def radial(r,a,z):return (r*math.sin(a),-r*math.cos(a),z)
def lettering(body,r,z,span,c):
 widths=[.42 if q==' ' else (.42 if q in 'ILT' else .68) for q in body];total=sum(widths)
 p=-total/2
 for q,w in zip(body,widths):
  a=(p+w/2)/total*span;p+=w
  if q!=' ':
   ob=text('招牌字_'+q,q,radial(r,a,z),.67,c,(math.pi/2,0,a))
   ob.data.update();xs=[v.co.x for v in ob.data.vertices];ys=[v.co.y for v in ob.data.vertices]
   sx=(r*span*w/total*.90)/(max(xs)-min(xs));sy=.66/(max(ys)-min(ys))
   for v in ob.data.vertices:v.co.x*=sx;v.co.y*=sy
def uvmap(o):
 for u in list(o.data.uv_layers):o.data.uv_layers.remove(u)
 uv=o.data.uv_layers.new(name='PaletteUV');c=colors[o['palette_cell']];u0=c['column']/8;v0=1-(c['row']+1)/8
 for f in o.data.polygons:
  axis=max(range(3),key=lambda i:abs(f.normal[i]));axes=[i for i in range(3) if i!=axis]
  vals=[[o.data.vertices[o.data.loops[li].vertex_index].co[i] for li in f.loop_indices] for i in axes]
  lo=[min(v) for v in vals];sz=[max(v)-min(v) for v in vals]
  for j,li in enumerate(f.loop_indices):uv.data[li].uv=(u0+(.22+.56*(vals[0][j]-lo[0])/max(sz[0],1e-10))/8,v0+(.22+.56*(vals[1][j]-lo[1])/max(sz[1],1e-10))/8)
  pts=[uv.data[li].uv.copy() for li in f.loop_indices];area=abs(sum(a.x*b.y-b.x*a.y for a,b in zip(pts,pts[1:]+pts[:1])))/2
  if area<1e-10:
   for j,li in enumerate(f.loop_indices):
    a=math.tau*j/len(f.loop_indices);uv.data[li].uv=(u0+(.5+.25*math.cos(a))/8,v0+(.5+.25*math.sin(a))/8)
 uv.active_render=True;o.data.uv_layers.active_index=0

components={};catalog=[];plan=json.loads((D/'component_plan.json').read_text())
def part(key,fn):
 bpy.ops.object.select_all(action='DESELECT');before=set(sc.objects);fn();objs=[o for o in sc.objects if o not in before]
 col=bpy.data.collections.new('SEA-SCENE-FSH-'+key.upper().replace('_','-'));sc.collection.children.link(col)
 for o in objs:
  bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
  for mo in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mo.name)
  o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
  bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.dissolve_degenerate(bm,dist=1e-6,edges=list(bm.edges));bad=[f for f in bm.faces if f.calc_area()<1e-12]
  if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free();o.data.update()
  for c in list(o.users_collection):c.objects.unlink(o)
  col.objects.link(o)
 pts=[v.co for o in objs for v in o.data.vertices];lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);delta=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 root=bpy.data.objects.new(key+'_ROOT',None);col.objects.link(root)
 for o in objs:
  o.data.transform(Matrix.Translation(-delta));o.data.update();o.parent=root;uvmap(o)
 col.instance_offset=(0,0,0);col.use_fake_user=True;sc.collection.children.unlink(col);components[key]=col
 spec=next(x for x in plan['components'] if x['key']==key)
 geom=b''.join(str(tuple(round(x,5) for x in v.co)).encode() for o in objs for v in o.data.vertices)
 catalog.append(dict(spec,collection=col.name,root=root.name,bounds_size=list(hi-lo),authored_origin_shift=list(delta),component_source=f'art_source/scenes/floating_shop/v001/component_packages/{key}/{key}.blend',geometry_fingerprint=hashlib.sha256(geom).hexdigest(),collision_owner='Godot wrapper pending'))

def build_deck():
 cyl('奶油厚圆盘甲板',(0,0,.20),7.2,.4,'plaster',verts=128,bevel=.07)
 cyl('木质浅色甲板面',(0,0,.42),7.13,.08,'sand',verts=128,bevel=.025)
 torus('甲板外圆包边',(0,0,.41),7.14,.055,'cream',role='SEA_Metal')
 for i in range(64):
  a=i*math.tau/64
  rod('环廊径向拼缝',radial(6.0,a,.465),radial(7.05,a,.465),.009,'stone','SEA_Matte')
  # irregular paint chips as thin inset shapes on the cylindrical fascia
  if i%2==0:
   b=random.uniform(-math.pi,math.pi);z=random.uniform(.09,.32);vs=[]
   for j in range(7):
    t=j*math.tau/7;aa=b+random.uniform(.012,.035)*math.cos(t);zz=max(.03,min(.37,z+random.uniform(.03,.10)*math.sin(t)));vs.append(radial(7.207,aa,zz))
   mesh('舷沿不规则脱漆',vs,[tuple(range(7))],'wood_mid')
 for i in range(32):
  a=i*math.tau/32;sphere('舷边铆钉',radial(7.21,a,.28),(.035,.035,.035),'lightgray','SEA_Metal',12,8)
part('deck',build_deck)
def build_roof():
 cyl('屋顶厚包边',(0,0,.13),6.13,.26,'cream',verts=128,bevel=.06)
 sphere('低矮圆穹顶',(0,0,.12),(5.95,5.95,.3),'sand',seg=96,rings=16)
 for r in [5.68,5.95]:torus('屋面环形接缝',(0,0,.29),r,.026,'stone')
 for i in range(16):
  a=i*math.tau/16;rod('屋面径向板缝',radial(1.1,a,.39),radial(5.58,a,.31),.012,'stone','SEA_Matte')
part('roof',build_roof)
def window():
 span=math.pi/8
 arc('青蓝弧形玻璃',5.94,5.965,.14,2.72,-span/2+.022,span/2-.022,'ice',steps=14,role='SEA_Gloss',bev=0)
 for z in [.06,2.78]:arc('青绿弧形横框',5.88,6.02,z,z+.10,-span/2,span/2,'sage_gray',steps=14)
 for a in [-span/2,span/2]:rod('竖向青绿窗框',radial(5.97,a,.07),radial(5.97,a,2.85),.07,'sage_gray')
 arc('下部青绿实心窗裙',5.88,5.98,.10,.42,-span/2,span/2,'sage_gray',steps=14)
part('facade_window',window)
def entry():
 for x in [-1.065,1.065]:cube('开放门洞侧框',(x,0,1.16),(.13,.19,2.32),'sage_gray','SEA_Metal',.025)
 cube('开放门洞横楣',(0,0,2.27),(2.26,.19,.14),'sage_gray','SEA_Metal',.025)
 cube('门洞上方米白填墙',(0,.025,2.56),(2.26,.16,.44),'cream',bevel=.02)
 cube('入口木色门槛',(0,-.04,.035),(2,.23,.07),'wood_light',bevel=.015)
part('entry',entry)
part('rear_wall',lambda:arc('背面米黄封闭墙',5.84,6,0,2.9,-math.pi/8,math.pi/8,'cream',steps=24))
def rear_door():
 cube('检修门外框',(0,0,1.03),(1.16,.16,2.06),'lightgray','SEA_Metal',.10)
 cube('检修门面',(0,-.10,1.02),(1,.06,1.90),'steel','SEA_Metal',.07)
 cube('检修门玻璃小窗',(0,-.14,1.48),(.57,.035,.62),'aqua','SEA_Matte',.055)
 cube('窗银色压边',(0,-.125,1.48),(.67,.03,.72),'silver','SEA_Metal',.06)
 cube('门把',(.35,-.18,.96),(.05,.08,.19),'gold','SEA_Metal',.02)
 for z in [.45,1.6]:cube('门合页',(-.51,-.12,z),(.12,.08,.2),'gray','SEA_Metal',.02)
part('rear_door',rear_door)
part('sign_band',lambda:[arc('奶黄整圈招牌底',5.91,6.12,0,1,-math.pi,math.pi,'honey',128,bev=.02),arc('招牌上金包边',6.08,6.19,.96,1.04,-math.pi,math.pi,'ochre',128),arc('招牌下金包边',6.08,6.19,-.025,.055,-math.pi,math.pi,'ochre',128)])
def sign(body,span,c,icon):
 arc('弧形浅黄招牌面',6.13,6.18,.06,.92,-span/2,span/2,'butter',32,bev=.025)
 for z in [.05,.94]:arc('招牌金色细框',6.17,6.205,z,z+.045,-span/2,span/2,'ochre',32)
 for a in [-span/2,span/2]:rod('招牌竖边',radial(6.205,a,.07),radial(6.205,a,.94),.033,'ochre')
 lettering(body,6.225,.50,span*.72,c)
 # icon on the right, tangent to the arc
 a=span*.43;p=Vector(radial(6.235,a,.5));rot=Matrix.Rotation(a,4,'Z')
 def ib(n,off,size,col):
  q=p+rot.to_3x3()@Vector(off);return cube(n,q,size,col,bevel=.02,rot=(0,0,a))
 if icon=='gift':
  ib('红色礼盒',(0,0,-.02),(.38,.09,.40),'red_dark');ib('礼盒盖',(0,-.025,.20),(.43,.11,.08),'red');ib('礼盒金缎带',(0,-.07,.02),(.075,.025,.43),'gold')
  for x in [-.11,.11]:sphere('礼物蝴蝶结',p+rot.to_3x3()@Vector((x,-.02,.29)),(.11,.06,.08),'red_dark')
 elif icon=='mail':
  ib('米白信封',(0,0,0),(.40,.06,.29),'cream')
  pts=[(-.19,-.045,.13),(0,-.045,-.03),(.19,-.045,.13)];tube('信封折线',[p+rot.to_3x3()@Vector(v) for v in pts],.013,'bark','SEA_Matte')
 else:
  ib('红饮料杯',(0,0,-.02),(.26,.09,.38),'red');ib('杯上蓝盖',(0,-.01,.20),(.30,.12,.07),'aqua');rod('饮料吸管',p+Vector((0,0,.2)),p+Vector((.06,0,.39)),.018,'cream')
part('sign_gifts',lambda:sign('GIFTS',math.radians(42),'red_dark','gift'))
part('sign_postcards',lambda:sign('POSTCARDS',math.radians(66),'deepblue','mail'))
part('sign_drinks',lambda:sign('COLD DRINKS',math.radians(66),'deepblue','drink'))
def awning(cell):
 # One actual curved fabric stripe with a rounded scalloped hem, no flat boxes.
 half=math.tau/80/2;N=8;vs=[];fs=[]
 for i in range(N+1):
  a=-half+2*half*i/N;hem=.26+.09*math.sin(math.pi*i/N)
  for r,z in [(6.03,.69),(6.95,.37),(6.95,.37-hem),(6.89,.37-hem),(6.89,.39),(6.03,.75)]:vs.append(radial(r,a,z))
 for i in range(N):
  for j in range(6):fs.append((i*6+j,(i+1)*6+j,(i+1)*6+(j+1)%6,i*6+(j+1)%6))
 fs += [tuple(reversed(range(6))),tuple(N*6+j for j in range(6))]
 mesh('圆垂边雨棚布',vs,fs,cell,bev=.018)
part('awning_blue',lambda:awning('solar'));part('awning_white',lambda:awning('snow'))
part('rail_post',lambda:[cyl('栏杆脚座',(0,0,.035),.13,.07,'rubber',verts=24),cyl('黄色栏杆柱',(0,0,.56),.065,1.04,'ochre',verts=20),sphere('黄色球头',(0,0,1.1),(.105,.105,.105),'gold','SEA_Metal',20,12),cyl('中部米白箍',(0,0,.69),.075,.12,'cream',verts=20)])
part('rail_arc',lambda:[tube('黄色连续弧栏',[radial(7.0,-math.pi/16+i*math.pi/8/16,z) for i in range(17)],r,'gold') for z,r in [(1.0,.045),(.48,.032)]])
def tire():
 torus('黑色厚轮胎',(0,0,.50),.35,.15,'rubber',(math.pi/2,0,0));torus('胎壁压边',(0,-.13,.5),.34,.018,'slate',(math.pi/2,0,0))
 for i in range(24):
  a=i*math.tau/24;cube('轮胎胎面沟',(math.sin(a)*.49,0,.50+math.cos(a)*.49),(.035,.18,.018),'slate',bevel=.005,rot=(0,a,0))
 tube('轮胎垂挂绳',[(0,.10,.94),(0,.08,1.12),(0,.10,1.36)],.025,'bark','SEA_Matte');torus('挂绳系扣',(0,.1,1.32),.07,.021,'bark',(math.pi/2,0,0))
part('tire',tire)
def lifering():
 torus('救生圈红主体',(0,0,.4),.29,.11,'red_dark',(math.pi/2,0,0))
 # White quarters follow the toroidal surface, not cubes.
 for k in range(4):
  vs=[];fs=[]
  for i in range(9):
   a=k*math.pi/2-.16+i*.32/8
   for j in range(13):
    b=j*math.tau/12;rr=.29+.113*math.cos(b);vs.append((rr*math.sin(a),.113*math.sin(b),.4+rr*math.cos(a)))
  for i in range(8):
   for j in range(12):fs.append((i*13+j,i*13+j+1,(i+1)*13+j+1,(i+1)*13+j))
  mesh('救生圈白包带',vs,fs,'snow')
 torus('外侧救生绳',(0,.035,.4),.43,.018,'cream',(math.pi/2,0,0));tube('救生圈挂绳',[(0,.03,.8),(0,.03,.94)],.025,'bark')
part('life_ring',lifering)
part('ladder',lambda:[rod('爬梯立杆',(x,0,.05),(x,0,2.95),.043,'ochre') for x in [-.3,.3]]+[rod('爬梯横档',(-.3,0,.14+i*.29),(.3,0,.14+i*.29),.033,'silver') for i in range(10)]+[tube('爬梯弯扶手',[(x,.0,2.75),(x,.0,3.12),(x,.18,3.20),(x,.35,3.20)],.043,'ochre') for x in [-.3,.3]])
def controller():
 cyl('主控米黄柱体',(0,0,.42),1,.84,'honey',verts=64,bevel=.07);torus('主控下压边',(0,0,.09),.98,.035,'ochre',role='SEA_Metal')
 sphere('浅灰穹顶盖',(0,0,.84),(1.03,1.03,.27),'cloud','SEA_Metal',64,20);cyl('顶部蓝色圆饰',(0,0,1.13),.24,.14,'aqua',verts=32,bevel=.04)
 for i in range(12):
  a=i*math.tau/12;sphere('主控铆钉',radial(1.01,a,.68),(.025,.025,.025),'silver','SEA_Metal',12,8)
 for i in range(7):
  a=-1.1+i*.36;arc('主控柱体掉漆',1.001,1.006,.22+random.random()*.2,.49+random.random()*.15,a,a+.04,'wood_mid',2,bev=0)
part('controller',controller)
def spot():
 cyl('射灯底盘',(0,0,.045),.20,.09,'slate',verts=24);rod('射灯支柱',(0,0,.1),(0,0,.43),.058,'steel')
 for x in [-.24,.24]:tube('射灯U形叉架',[(x,0,.35),(x,0,.60),(x,-.04,.65)],.037,'gray')
 cyl('黑色灯头',(0,-.02,.65),.23,.38,'rubber',rot=(math.pi/2-.25,0,0),verts=32,bevel=.045)
 cyl('射灯暖色透镜',(0,-.214,.70),.171,.025,'butter','SEA_Emission',rot=(math.pi/2-.25,0,0),verts=32,bevel=.01)
 torus('灯头金属压圈',(0,-.20,.698),.193,.028,'silver',(math.pi/2-.25,0,0),'SEA_Metal')
part('spotlight',spot)
part('roof_pipe',lambda:[tube('屋面弯管',[(-.6,0,0),(-.6,0,.50),(-.58,0,.68),(-.43,0,.78),(.42,0,.78),(.57,0,.67),(.60,0,.48),(.60,0,0)],.075,'slate')]+[cyl('管道脚法兰',(x,0,.035),.15,.07,'gray',verts=20) for x in [-.6,.6]]+[torus('管线接头',(.0,0,.78),.086,.025,'silver',(0,math.pi/2,0),'SEA_Metal'),rod('阀门颈',(-.35,0,.77),(-.35,0,.96),.04,'steel'),torus('红色阀门手轮',(-.35,0,1.0),.13,.025,'red_dark',role='SEA_Metal')])
def electrical():
 cube('浅灰电气箱',(0,0,.34),(.66,.32,.68),'lightgray','SEA_Metal',.055);cube('电气箱门',(0,-.18,.34),(.54,.05,.56),'silver','SEA_Metal',.035)
 for x in [-.23,.23]:
  for z in [.14,.54]:sphere('箱门螺钉',(x,-.215,z),(.018,.012,.018),'slate','SEA_Metal',12,8)
 cube('电气箱拉手',(.16,-.23,.35),(.045,.045,.13),'slate','SEA_Metal',.01);cube('电气黄色警示',(0,-.218,.43),(.16,.012,.13),'gold',bevel=.015)
 for x in [-.17,0,.17]:cube('箱底散热槽',(x,-.21,.18),(.065,.01,.02),'slate',bevel=.004)
part('electrical_box',electrical)
part('beacon',lambda:[cyl('信号灯立柱',(0,0,.35),.065,.7,'slate',verts=20),cyl('信号灯座',(0,0,.7),.13,.09,'rubber',verts=24),sphere('橙色信号灯罩',(0,0,.79),(.135,.135,.15),'ochre','SEA_Emission',24,12)])
def engine():
 cyl('主舱上接盘',(0,0,1.82),1.62,.22,'steel',verts=64,bevel=.06)
 cyl('金属动力主舱',(0,0,1.17),1.25,1.22,'gray',verts=64,bevel=.09)
 for z in [.58,1.72]:torus('主舱压边',(0,0,z),1.21,.075,'slate',role='SEA_Metal')
 cyl('主喷口收口锥',(0,0,.40),.65,.36,'slate',r2=1.1,verts=64,bevel=.035)
 cyl('喷嘴外层',(0,0,.16),.64,.28,'steel',verts=64,bevel=.04);torus('喷口口沿',(0,0,.055),.54,.075,'rubber',role='SEA_Metal')
 for i in range(16):
  a=i*math.tau/16;rod('主舱竖直接缝',radial(1.252,a,.72),radial(1.252,a,1.6),.013,'steel')
  sphere('主舱上螺栓',radial(1.263,a,1.6),(.043,.043,.043),'lightgray','SEA_Metal',12,8)
 for i in range(24):
  a=i*math.tau/24;z=.72+random.random()*.65;arc('主舱锈蚀块',1.252,1.26,z,z+.09+random.random()*.1,a,a+.08,'wood_mid',2,bev=0)
part('engine',engine)
part('engine_glow',lambda:[cyl('主喷口金色内芯',(0,0,.07),.43,.14,'gold','SEA_Emission',verts=48,bevel=.03),sphere('主喷口暖白中心',(0,0,.04),(.29,.29,.065),'butter','SEA_Emission',32,12)])
def pod():
 sphere('橙色圆浮舱',(0,0,1.25),(1.25,1.25,1.25),'coral','SEA_Metal',48,24)
 torus('浮舱环形焊缝',(0,0,1.25),1.251,.018,'wood_mid',role='SEA_Metal')
 for a in [0,math.pi/2,math.pi,3*math.pi/2]:tube('球舱分瓣焊缝',[(1.252*math.sin(t)*math.sin(a),-1.252*math.sin(t)*math.cos(a),1.25+1.252*math.cos(t)) for t in [j*math.pi/24 for j in range(25)]],.012,'wood_mid')
 cyl('浮舱底小喷头',(0,0,.06),.29,.16,'slate',verts=32);cyl('浮舱顶连接',(0,0,2.42),.45,.16,'gray',verts=32)
 # Small irregular chips lie directly on the curved sphere.
 for k in range(18):
  a=random.random()*math.tau;t=random.uniform(.65,2.3);vs=[]
  for j in range(7):
   q=j*math.tau/7;aa=a+.10*math.cos(q)*random.uniform(.6,1.1);tt=t+.075*math.sin(q)*random.uniform(.7,1.2);vs.append((1.256*math.sin(tt)*math.sin(aa),-1.256*math.sin(tt)*math.cos(aa),1.25+1.256*math.cos(tt)))
  mesh('浮舱漆面磨损',vs,[tuple(range(7))],'wood_light')
part('float_pod',pod)
part('aux_nozzle',lambda:[cyl('辅助喷口法兰',(0,0,.48),.36,.13,'gray',verts=32),cyl('辅助喷口锥',(0,0,.28),.25,.36,'steel',r2=.34,verts=32),torus('辅助喷口压边',(0,0,.085),.23,.05,'rubber',role='SEA_Metal')])
part('aux_glow',lambda:cyl('辅助喷口发光芯',(0,0,.035),.18,.07,'gold','SEA_Emission',verts=32,bevel=.02))
part('under_brace',lambda:[cube('辐射底盘支臂',(0,0,.15),(.4,3.9,.3),'steel','SEA_Metal',.04),tube('底盘动力管',[(-.24,-1.9,.2),(-.24,-1.4,.05),(-.24,.8,.05),(-.24,1.8,.2)],.065,'slate')]+[cube('支臂接板',(0,y,.33),(.7,.5,.09),'gray','SEA_Metal',.015) for y in [-1.6,1.6]])
part('counterweight',lambda:[rod('配重悬杆',(0,0,.55),(0,0,1.2),.035,'slate'),cyl('橙色配重柱',(0,0,.27),.12,.54,'ochre',verts=24,bevel=.05),cyl('配重底帽',(0,0,.035),.125,.07,'wood_mid',verts=24)])
def postcards():
 cyl('展架底座',(0,0,.04),.32,.08,'wood_light',verts=32);rod('展架转轴',(0,0,.07),(0,0,1.78),.045,'gray')
 for a in [0,math.pi/2,math.pi,3*math.pi/2]:
  for x in [-.15,.15]:
   for k in range(4):
    p=Matrix.Rotation(a,4,'Z')@Vector((x,-.26,.45+k*.30));o=cube('明信片白色卡套',p,(.25,.04,.28),'snow',bevel=.009,rot=(0,0,a))
    p2=Matrix.Rotation(a,4,'Z')@Vector((x,-.286,.45+k*.30));cube('明信片彩色画面',p2,(.19,.013,.20),['sky','coral','honey','seafoam'][k],bevel=.005,rot=(0,0,a))
    p3=Matrix.Rotation(a,4,'Z')@Vector((x,-.298,.43+k*.30));sphere('明信片图形',p3,(.06,.01,.05),['white','leaf_mid','blue','ochre'][k],seg=12,rings=8)
 cyl('展架顶帽',(0,0,1.8),.16,.08,'wood_light',verts=24)
part('postcard_rack',postcards)
def mailbox():
 cube('红邮筒主体',(0,0,.61),(.49,.40,1.16),'red_dark','SEA_Metal',.08);cube('邮筒顶盖',(0,0,1.19),(.55,.44,.12),'red','SEA_Metal',.055)
 cube('投信口黑缝',(0,-.207,1.02),(.34,.025,.055),'rubber',bevel=.01);cube('投信口雨檐',(0,-.23,1.08),(.39,.09,.045),'red','SEA_Metal',.012)
 cube('邮筒取件门',(0,-.212,.47),(.36,.025,.51),'red','SEA_Metal',.025);text('POST小字','POST',(0,-.236,.78),.105,'cream')
 sphere('邮筒门锁',(.12,-.24,.51),(.025,.015,.025),'gold','SEA_Metal',12,8)
part('mailbox',mailbox)
def icebox():
 cube('ICE白色保温箱',(0,0,.61),(1,.70,1.16),'snow','SEA_Metal',.09);cube('ICE上翻盖',(0,0,1.18),(1.04,.74,.13),'cream','SEA_Metal',.045)
 cube('ICE下部分隔缝',(0,-.358,.45),(.94,.012,.018),'lightgray',bevel=.003);text('ICE蓝色字','ICE',(0,-.374,.85),.34,'ocean')
 for x in [-.37,.37]:cube('冷柜盖扣',(x,-.39,1.13),(.06,.045,.09),'steel','SEA_Metal',.015)
 for x in [-.37,.37]:
  for y in [-.24,.24]:cyl('冷柜脚',(x,y,.035),.04,.07,'slate',verts=12)
part('ice_box',icebox)
def vending():
 cube('黄色售货机身',(0,0,.54),(.43,.38,1.08),'gold','SEA_Metal',.065);cube('售货装置上盖',(0,0,1.07),(.46,.4,.1),'ochre','SEA_Metal',.04)
 cube('售货装置投币口',(.08,-.202,.84),(.13,.03,.035),'slate',bevel=.008);cube('售货装置取货口',(0,-.205,.31),(.24,.025,.15),'wood_mid',bevel=.025)
 cyl('售货机按钮',(-.10,-.218,.70),.047,.027,'red_dark',rot=(math.pi/2,0,0),verts=20)
 sphere('柜顶绿色小饮料',(0,0,1.22),(.095,.095,.16),'leaf_mid',seg=20,rings=12)
part('vending',vending)
part('shelf',lambda:[cube('陈列架层板',(0,0,z),(1.9,.48,.10),'wood_light',bevel=.025) for z in [.08,.77,1.46]]+[cube('陈列架侧撑',(x,0,.76),(.08,.48,1.55),'wood_mid',bevel=.02) for x in [-.92,.92]])
def bottles():
 for i,c in enumerate(['red_dark','gold','leaf_mid','aqua','coral']):
  x=-.44+i*.22;cyl('饮料瓶身',(x,0,.17),.075,.28,c,'SEA_Matte',verts=20,bevel=.025);sphere('饮料瓶肩',(x,0,.3),(.074,.074,.065),c,seg=20,rings=12);cyl('饮料瓶颈',(x,0,.37),.032,.1,c,'SEA_Matte',verts=16);cyl('饮料瓶盖',(x,0,.43),.038,.035,'cream','SEA_Metal',verts=16,bevel=.008);cyl('饮料白标签',(x,0,.17),.077,.09,'cream','SEA_Matte',verts=20,bevel=0)
part('bottle',bottles)
def gifts():
 for i,c in enumerate(['coral','seafoam','honey']):
  x=-.43+i*.42;cube('礼品小盒',(x,0,.17),(.30,.29,.31),c,bevel=.045);cube('礼品盒奶白缎带',(x,-.152,.17),(.06,.015,.32),'cream',bevel=.008)
 sphere('黄色鸭玩偶身',(.12,0,.48),(.15,.13,.14),'gold',seg=20,rings=12);sphere('黄色鸭玩偶头',(.12,-.015,.65),(.10,.095,.105),'gold',seg=20,rings=12);sphere('鸭橙色嘴',(.12,-.105,.63),(.07,.07,.035),'ochre',seg=16,rings=8)
 for x in [.08,.16]:sphere('鸭小黑眼',(x,-.096,.68),(.012,.012,.012),'rubber',seg=12,rings=8)
part('gift',gifts)
part('pot',lambda:[cyl('米白花盆',(0,0,.20),.21,.40,'cream','SEA_Matte',r2=.29,verts=32,bevel=.025),torus('花盆厚口',(0,0,.40),.275,.035,'snow'),cyl('盆内深土',(0,0,.40),.25,.025,'darkwood','SEA_Matte',verts=32,bevel=0)])
def foliage():
 for i in range(9):
  a=i*2.4;length=.36+(i%3)*.11;tip=Vector((math.sin(a)*length,-math.cos(a)*length,.30+(i%3)*.08));base=Vector((0,0,.02));rod('植物短茎',base,tip*.75,.014,'leaf_dark','SEA_Matte');mid=(base+tip)/2+Vector((0,0,.07))
  o=sphere('饱满有机宽叶',mid,(.09,.06,length*.65),'leaf' if i%2 else 'leaf_dark',seg=20,rings=12);o.rotation_euler=(tip-base).to_track_quat('Z','Y').to_euler()
part('foliage',foliage)
def flowers():
 for i in range(3):
  x=(i-1)*.12;z=.24+i*.065;rod('小花茎',(x,0,0),(x,0,z),.012,'leaf_mid','SEA_Matte')
  for k in range(5):a=k*math.tau/5;sphere('圆润暖黄花瓣',(x+math.sin(a)*.065,math.cos(a)*.065,z),(.048,.048,.028),'yellow',seg=16,rings=10)
  sphere('橙色花心',(x,0,z+.023),(.033,.033,.025),'ochre',seg=16,rings=10)
part('flowers',flowers)

# Assembly: all positions are true metre units and all repetitive objects instances.
building=bpy.data.collections.new('FSH_建筑与固定设施');plants=bpy.data.collections.new('FSH_植物附件');display=bpy.data.collections.new('FSH_展示支持')
for c in [building,plants,display]:sc.collection.children.link(c)
layout=[]
def put(key,pos,angle=0,scale=(1,1,1),rot=None):
 n=key+'_'+str(sum(x['key']==key for x in layout)+1).zfill(3);o=bpy.data.objects.new(n,None);o.instance_type='COLLECTION';o.instance_collection=components[key];o.location=pos;o.rotation_euler=rot or (0,0,angle);o.scale=scale
 (plants if key in ['foliage','flowers'] else building).objects.link(o);layout.append({'name':n,'key':key,'asset_id':'SEA-SCENE-FSH-'+key.upper().replace('_','-'),'position':list(pos),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(scale)});return o
put('deck',(0,0,2.04)) # measured deck top = 2.50m
put('roof',(0,0,6.05),scale=(1,1,.5))
for i in range(16):
 if i in [0,8]:continue
 # The curved facade is centered in its own bottom-origin package.
 a=i*math.tau/16;e=next(x for x in catalog if x['key']=='facade_window');d=Vector(e['authored_origin_shift']);p=Matrix.Rotation(a,4,'Z')@d;p.z=2.50;put('facade_window',p,a)
put('entry',(0,-5.96,2.50));put('rear_wall',(0,5.77,2.50),math.pi);put('rear_door',(0,6.02,2.5),math.pi)
put('sign_band',(0,0,5.35))
for key,a in [('sign_gifts',0),('sign_postcards',-math.radians(55)),('sign_drinks',math.radians(55))]:
 e=next(x for x in catalog if x['key']==key);d=Vector(e['authored_origin_shift']);p=Matrix.Rotation(a,4,'Z')@d;p.z=5.40;put(key,p,a)
for i in range(80):
 a=i*math.tau/80;key='awning_blue' if i%2==0 else 'awning_white';e=next(x for x in catalog if x['key']==key);p=Matrix.Rotation(a,4,'Z')@Vector(e['authored_origin_shift']);p.z=4.76;put(key,p,a)
for i in range(32):a=i*math.tau/32;put('rail_post',radial(7,a,2.5),scale=(1,1,1.1/1.205))
for i in range(16):
 a=i*math.tau/16;e=next(x for x in catalog if x['key']=='rail_arc');p=Matrix.Rotation(a,4,'Z')@Vector(e['authored_origin_shift']);p.z=2.98;put('rail_arc',p,a)
for i in range(10):a=(i+.5)*math.tau/10;put('tire',radial(7.30,a,1.63),a)
for a in [-math.pi/3,math.pi/3]:put('life_ring',radial(6.25,a,3.25),a)
put('ladder',radial(6.94,.48,.02),.48)
put('controller',(0,0,6.30))
for a in [-.7,.7,math.pi-.7,math.pi+.7]:put('spotlight',radial(4.7,a,6.32),a)
for a in [-1.8,1.8]:put('roof_pipe',radial(3.15,a,6.32),a)
for a in [-2.6,2.6]:put('electrical_box',radial(3.65,a,6.32),a,rot=(.12,0,a))
for a in [-1.1,1.1]:put('beacon',radial(5.5,a,6.32))
for a in [math.pi-.44,math.pi+.44]:put('electrical_box',radial(6.05,a,2.63),a,scale=(1.25,1,1.35))
put('engine',(0,0,.00));put('engine_glow',(0,0,-.025))
for x in [-3.1,3.1]:put('float_pod',(x,-2.4,.02))
for a in [.2,math.pi-.2,-math.pi+.2,-.2]:
 put('aux_nozzle',radial(5.4,a,1.54));put('aux_glow',radial(5.4,a,1.52))
for i in range(8):
 a=i*math.tau/8;e=next(x for x in catalog if x['key']=='under_brace');p=Vector(radial(3.6,a,1.92));put('under_brace',p,a)
for a in [-1.25,1.25,math.pi-.6,math.pi+.6]:put('counterweight',radial(6.7,a,.67))
put('postcard_rack',(-2.45,-5.85,2.5),-.15);put('mailbox',(-1.0,-6.24,2.5));put('ice_box',(2.65,-5.75,2.5),.12);put('vending',(1.36,-6.12,2.5),.08)
put('mailbox',radial(6.3,-1.62,2.5),-1.62);put('ice_box',radial(6.35,1.60,2.5),1.60)
for a in [-.58,.58,-1.1,1.1,2.4,-2.4,math.pi]:
 put('shelf',radial(5.2,a,2.55),a)
 for h in [.14,.84,1.53]:put('bottle' if a>0 else 'gift',radial(5.17,a,2.55+h),a)
put('shelf',(0,-3.8,2.55),scale=(1.15,1,.82))
put('gift',(0,-3.88,3.83));put('bottle',(-.20,-3.88,3.25))
for a in [-.68,.9,-1.85,2.2]:
 put('pot',radial(6.35,a,2.5));put('foliage',radial(6.35,a,2.91));put('flowers',radial(6.35,a,3.0))
bpy.context.view_layer.update()
for e in catalog:e['instances']=sum(x['key']==e['key'] for x in layout)
(D/'catalog.json').write_text(json.dumps({'schema':'sea.scene.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.instances','up_axis':'Z','front_axis':'-Y','godot_mapping':'(x,y,z)->(x,z,-y)','instances':layout},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

# Neutral reference studio with an optional independently hidden sea presentation.
world=bpy.data.worlds.new('FSH_奶油展示环境');world.use_nodes=True;world.node_tree.nodes.clear();bg=world.node_tree.nodes.new('ShaderNodeBackground');wo=world.node_tree.nodes.new('ShaderNodeOutputWorld');world.node_tree.links.new(bg.outputs[0],wo.inputs[0]);bg.inputs[0].default_value=(.78,.83,.88,1);bg.inputs[1].default_value=.45;sc.world=world
o=cube('展示背景地面',(0,0,-.42),(200,200,.1),'cream',bevel=0)
for c in list(o.users_collection):c.objects.unlink(o)
display.objects.link(o);uvmap(o)
for n,pos,power,size,color in [('柔和主光',(-9,-12,19),2400,9,(1,.86,.69)),('蓝色补光',(10,-1,13),1700,8,(.72,.85,1)),('后侧轮廓光',(0,10,17),2300,7,(1,.93,.8))]:
 d=bpy.data.lights.new(n,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=color;o=bpy.data.objects.new(n,d);display.objects.link(o);o.location=pos;o.rotation_euler=(Vector((0,0,3.6))-o.location).to_track_quat('-Z','Y').to_euler()
cd=bpy.data.cameras.new('参考相机');cam=bpy.data.objects.new('参考相机',cd);display.objects.link(cam);sc.camera=cam;cam.location=(5,-25,9);cam.rotation_euler=(Vector((0,0,3.7))-cam.location).to_track_quat('-Z','Y').to_euler();cd.type='ORTHO';cd.ortho_scale=17.0;cd.lens=50
sc.render.engine='CYCLES';sc.cycles.samples=32;sc.cycles.use_denoising=True
# Select GPU only when the installed driver exposes a real device.
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 for dev in prefs.devices:dev.use=dev.type!='CPU'
 if any(d.use for d in prefs.devices):sc.cycles.device='GPU'
except Exception:pass
sc.render.resolution_x=1500;sc.render.resolution_y=1200;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG'
sc.view_settings.view_transform='Standard';sc.view_settings.look='Medium High Contrast'
sc.view_settings.exposure=-.7
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL';area.spaces.active.overlay.show_overlays=False
for img in bpy.data.images:
 if img==im:img.filepath=bpy.path.relpath(str(pal),start=str(D))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(D/'floating_shop.blend'),compress=True)
print(json.dumps({'source':str(D/'floating_shop.blend'),'components':len(catalog),'instances':len(layout),'cycles_device':sc.cycles.device},ensure_ascii=False))

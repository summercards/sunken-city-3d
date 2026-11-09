"""MCP-owned authoring: numbered above-water reference building. No Godot writes."""
import bpy,bmesh,json,hashlib,math,os
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));assert P['status']=='frozen_before_geometry' and len(P['components'])<=50
if not (W/'session_before.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'session_before.blend'),copy=True)
# Only our prefixed data is ever removed on retry. Preserve the user's original scene.
for s in list(bpy.data.scenes):
 if s.name.startswith('BLDA_'):
  if bpy.context.window.scene==s:bpy.context.window.scene=next(x for x in bpy.data.scenes if x!=s)
  bpy.data.scenes.remove(s)
for c in list(bpy.data.collections):
 if c.name.startswith(('BLDA_','SEA-SCENE-B1109A-')):
  for o in list(c.objects):bpy.data.objects.remove(o,do_unlink=True)
  bpy.data.collections.remove(c)
sc=bpy.data.scenes.new('BLDA_编号海上建筑_v001');bpy.context.window.scene=sc
sc.unit_settings.system='METRIC';sc.unit_settings.scale_length=1
T=math.tau;pi=math.pi
palette=R/P['palette'];cells={c['name']:c for c in json.loads(palette.with_suffix('.json').read_text())['cells']}
image=bpy.data.images.load(str(palette),check_existing=True);image.filepath=str(palette)
roles={}
for role,rough,metal in [('SEA_Matte',.72,0),('SEA_Metal',.48,.18),('SEA_Gloss',.26,0)]:
 mat=bpy.data.materials.new('BLDA_'+role);mat['semantic_role']=role;mat.use_nodes=True
 ns=mat.node_tree.nodes;bs=next(n for n in ns if n.type=='BSDF_PRINCIPLED');bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 uv=ns.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';tex=ns.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest';tex.extension='EXTEND'
 mat.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector']);mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color']);roles[role]=mat
font=bpy.data.fonts.load('C:/Windows/Fonts/msyhbd.ttc')
top={}
for group,label in [('structure','01_建筑结构'),('furnishing','02_固定设施'),('plant','03_独立植物'),('display','90_展示支持')]:
 c=bpy.data.collections.new('BLDA_'+label);sc.collection.children.link(c);top[group]=c
 if group=='display':c['display_support']=True
components={};catalog=[];layout=[];current=None

def finish(o,color='plaster',role='SEA_Matte',bevel=0,smooth=False):
 me=o.data
 if bevel:
  bm=bmesh.new();bm.from_mesh(me)
  try:bmesh.ops.bevel(bm,geom=list(bm.edges),offset=bevel,segments=3,affect='EDGES',profile=.5,clamp_overlap=True)
  except Exception:bm.free();raise
  bm.normal_update();bm.to_mesh(me);bm.free()
 for f in me.polygons:f.use_smooth=smooth or (bevel>0 and f.loop_total==4 and f.area<bevel*bevel*20)
 for old in list(me.uv_layers):me.uv_layers.remove(old)
 uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
 c=cells[color];cx=(c['column']+.5)/8;cy=1-(c['row']+.5)/8
 for face in me.polygons:
  for j,li in enumerate(face.loop_indices):
   a=T*j/face.loop_total;uv.data[li].uv=(cx+.027*math.cos(a),cy+.027*math.sin(a))
 me.materials.clear();me.materials.append(roles[role]);o['palette_color']=color;o['role']=role;o['bevel_width_m']=bevel;o['bevel_segments']=3 if bevel else 0
 me.update();return o

def mesh(n,vs,fs,c='plaster',r='SEA_Matte',b=0,smooth=False):
 me=bpy.data.meshes.new('BLDA_'+n);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new('BLDA_'+n,me);current.objects.link(o);return finish(o,c,r,b,smooth)

def box(n,p,s,c='plaster',r='SEA_Matte',b=.035):
 x,y,z=p;w,d,h=[v/2 for v in s]
 vs=[(x+a*w,y+bb*d,z+cc*h) for a,bb,cc in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 return mesh(n,vs,[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],c,r,min(b,min(s)*.42))

def tapered(n,p,s,rho,c='plaster',r='SEA_Matte',b=.025,axis='z'):
 o=box(n,p,s,c,r,0)
 for v in o.data.vertices:
  t=(v.co.z-(p[2]-s[2]/2))/s[2] if axis=='z' else (v.co.y-(p[1]-s[1]/2))/s[1]
  v.co.x=p[0]+(v.co.x-p[0])*(1-rho*t)
  if axis=='z':v.co.y=p[1]+(v.co.y-p[1])*(1-rho*t)
 return finish(o,c,r,min(b,min(s)*.40))

def cylinder(n,p,rad,h,c='stone',r='SEA_Matte',sides=24,b=.015,radtop=None):
 rt=rad if radtop is None else radtop;vs=[]
 for zz,rr in [(p[2]-h/2,rad),(p[2]+h/2,rt)]:vs.extend((p[0]+rr*math.cos(T*i/sides),p[1]+rr*math.sin(T*i/sides),zz) for i in range(sides))
 fs=[tuple(reversed(range(sides))),tuple(sides+i for i in range(sides))]+[(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
 return mesh(n,vs,fs,c,r,min(b,h*.35,rad*.25),True)

def sphere(n,p,s,c='leaf',sides=16,rings=9):
 vs=[(p[0],p[1],p[2]+s[2])]
 for j in range(1,rings):
  a=pi*j/rings
  vs.extend((p[0]+s[0]*math.sin(a)*math.cos(T*i/sides),p[1]+s[1]*math.sin(a)*math.sin(T*i/sides),p[2]+s[2]*math.cos(a)) for i in range(sides))
 vs.append((p[0],p[1],p[2]-s[2]));fs=[]
 for i in range(sides):fs.append((0,1+i,1+(i+1)%sides))
 for j in range(rings-2):
  a=1+j*sides;bb=a+sides
  for i in range(sides):fs.append((a+i,bb+i,bb+(i+1)%sides,a+(i+1)%sides))
 last=1+(rings-2)*sides
 for i in range(sides):fs.append((len(vs)-1,last+(i+1)%sides,last+i))
 return mesh(n,vs,fs,c,smooth=True)

def tube(n,pts,rad,c='silver',r='SEA_Matte',sides=10):
 pts=[Vector(p) for p in pts];vs=[]
 for i,p in enumerate(pts):
  t=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized();ref=Vector((0,0,1)) if abs(t.z)<.9 else Vector((0,1,0));u=t.cross(ref).normalized();v=t.cross(u).normalized()
  vs.extend(tuple(p+rad*(u*math.cos(T*j/sides)+v*math.sin(T*j/sides))) for j in range(sides))
 fs=[tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))]
 fs += [(i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j) for i in range(len(pts)-1) for j in range(sides)]
 return mesh(n,vs,fs,c,r,0,True)

def ring(n,p,major,minor,c='stone',axis='z',r='SEA_Matte',steps=32):
 pts=[]
 for i in range(steps+1):
  a=T*i/steps
  pts.append((p[0]+major*math.cos(a),p[1]+(major*math.sin(a) if axis=='z' else 0),p[2]+(0 if axis=='z' else major*math.sin(a))))
 return tube(n,pts,minor,c,r,8)

def rotate_mesh(o,angle,axis='Z',center=(0,0,0)):
 m=Matrix.Translation(Vector(center))@Matrix.Rotation(angle,4,axis)@Matrix.Translation(-Vector(center));o.data.transform(m);return o

def text(body,p,width,height,c='cream',depth=.025,n='字'):
 cu=bpy.data.curves.new('BLDA_FONT','FONT');cu.body=body;cu.font=font;cu.align_x='CENTER';cu.align_y='CENTER';cu.size=1;cu.extrude=depth;cu.bevel_depth=.007;cu.bevel_resolution=3;cu.resolution_u=5
 o=bpy.data.objects.new('BLDA_'+n,cu);sc.collection.objects.link(o);o.location=p;o.rotation_euler=(pi/2,0,0)
 bpy.context.view_layer.update();fac=min(width/max(o.dimensions.x,.01),height/max(o.dimensions.z,.01));o.scale=(fac,fac,fac)
 for ob in bpy.context.selected_objects:ob.select_set(False)
 o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');o=bpy.context.object;o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
 for co in list(o.users_collection):co.objects.unlink(o)
 current.objects.link(o);o.select_set(False);return finish(o,c)

def part(key,fn):
 global current
 row=next(c for c in P['components'] if c['key']==key);current=bpy.data.collections.new(row['asset_id']);sc.collection.children.link(current)
 current['form_layer']=row['layer'];current['rho']=row.get('rho',0);current['asset_id']=row['asset_id'];fn()
 pts=[v.co.copy() for o in current.objects for v in o.data.vertices];lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);pivot=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in current.objects:o.data.transform(Matrix.Translation(-pivot))
 current.instance_offset=(0,0,0);components[key]=current;sc.collection.children.unlink(current)
 tris=polys=0;h=hashlib.sha256()
 for o in current.objects:
  o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);polys+=len(o.data.polygons)
  for v in o.data.vertices:h.update((','.join(format(float(x),'.6f') for x in v.co)+';').encode())
 catalog.append(dict(row,collection=current.name,design_pivot=list(pivot),bounds_size=list(hi-lo),component_source=f'art_source/scenes/bld_20261109_a/v001/component_packages/{key}/{key}.blend',material_roles=sorted({o['role'] for o in current.objects}),meshes=len(current.objects),triangles=tris,polygons=polys,geometry_fingerprint=h.hexdigest(),fingerprint_algorithm='ordered_vertices_fixed6_sha256'))
 print('BLDA_BUILT',key,len(current.objects),tris,flush=True)

def put(k,p=(0,0,0),a=0,rot=None):
 e=next(e for e in catalog if e['key']==k);o=bpy.data.objects.new('BLDA_I_'+k+'_'+str(sum(x['key']==k for x in layout)+1).zfill(3),None);o.instance_type='COLLECTION';o.instance_collection=components[k];o.rotation_euler=rot or (0,0,a);o.location=Vector(p)+o.rotation_euler.to_matrix()@Vector(e['design_pivot']);top[e['group']].objects.link(o)
 layout.append({'name':o.name,'key':k,'asset_id':e['asset_id'],'position':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':[1,1,1]});return o

# STRUCTURE: straight walls, real openings; surfaces have thickness, no black overlays.
def deck():
 box('海上平台',(0,0,.2),(11,10.6,.2),'plaster',b=.045)
 for x in range(-10,11):box('浅色砖缝',(x*.5,0,.302),(.014,10.4,.005),'sand',b=.001)
 for y in range(-10,11):box('浅色砖缝',(0,y*.5,.303),(10.8,.014,.005),'sand',b=.001)
part('deck',deck)
def shell():
 # ground left solid wall, rear and right exterior; the front is open shop frontage.
 box('底层广告侧墙',(-4.15,0,2.45),(.3,8.2,4.9),'plaster',b=.044)
 box('底层背墙',(0,3.95,2.45),(8.6,.3,4.9),'stone',b=.044)
 box('底层右墙',(4.15,0,2.45),(.3,8.2,4.9),'plaster',b=.044)
 # Upper storey: aperture bands on the visible two sides.
 for z,h in [(5.55,.9),(9.68,.64)]:
  box('二层正窗裙',(0,-3.95,z),(8.6,.3,h),'plaster',b=.044)
  box('二层侧窗裙',(-4.15,0,z),(.3,8.2,h),'plaster',b=.044)
 box('二层背墙',(0,3.95,7.55),(8.6,.3,4.9),'stone',b=.044)
 box('二层右墙',(4.15,0,7.55),(.3,8.2,4.9),'plaster',b=.044)
 for y in (-3.9,3.9):box('侧窗边柱',(-4.15,y,7.55),(.3,.4,4.9),'plaster',b=.04)
part('shell',shell)
part('slab',lambda:box('整层实体薄楼板',(0,0,.1),(8.6,8.2,.2),'plaster',b=.045))
def coping():
 for x in (-4.15,4.15):box('露台女儿墙',(x,0,.45),(.3,8.2,.9),'plaster',b=.121)
 box('露台背女儿墙',(0,3.95,.45),(8.6,.3,.9),'plaster',b=.121)
part('coping',coping)
part('post',lambda:box('五十厘米主柱',(0,0,2.45),(.5,.5,4.9),'plaster',b=.095))
def window():
 box('暗色凹入窗玻璃',(0,.08,1.68),(7.3,.08,3.36),'slate','SEA_Gloss',.015)
 for x in [-3.73,3.73]:box('竖窗边框',(x,-.01,1.68),(.13,.22,3.52),'wood_edge',b=.025)
 for z in [-.03,3.39]:box('横窗框',(0,-.02,z),(7.6,.22,.13),'wood_edge',b=.025)
 for i in range(17):box('密竖栅',(-3.45+i*.43,-.09,1.68),(.055,.11,3.38),'stone',b=.018)
 box('横档',(0,-.12,1.1),(7.5,.09,.055),'silver',b=.014)
part('barred_window',window)
def transom():
 for i in range(3):
  x=(i-1)*2.43;box('深凹亮窗',(x,.08,.35),(2.18,.07,.70),'rubber','SEA_Gloss',.014)
 for x in [-3.72,-1.22,1.22,3.72]:box('亮窗竖隔',(x,0,.35),(.14,.21,.86),'plaster',b=.028)
 for z in [-.04,.74]:box('亮窗横档',(0,0,z),(7.6,.22,.15),'plaster',b=.03)
part('transom',transom)
def hut():
 box('天台小间背墙',(0,1.75,1.55),(6.6,.2,3.1),'wood_mid',b=.035)
 for x in [-3.2,3.2]:box('小间侧墙',(x,0,1.55),(.2,3.7,3.1),'wood_light',b=.035)
 box('小间正下墙',(0,-1.74,.65),(6.6,.18,1.3),'wood_edge',b=.025)
 for x in [-3.16,-1.05,1.05,3.16]:box('小间木竖框',(x,-1.84,1.55),(.12,.16,3.1),'darkwood',b=.025)
 for x in [-2.1,0,2.1]:box('小间蓝玻璃',(x,-1.77,2.12),(1.93,.06,1.7),'sage_gray','SEA_Gloss',.015)
 for z in [1.25,3.05]:box('小间横框',(0,-1.85,z),(6.6,.13,.12),'darkwood',b=.025)
part('roof_hut',hut)
def corrugated():
 # full corrugated sheet with material thickness, taper across depth 4%.
 vs=[];N=108
 for y,zadd in [(-2.14,0),(2.14,.45)]:
  for i in range(N+1):
   x=-3.65+7.3*i/N;widthfactor=1-.04*((y+2.14)/4.28);z=.16+zadd+.055*math.cos(T*i/4)
   vs.extend([(x*widthfactor,y,z),(x*widthfactor,y,z-.11)])
 fs=[];stride=(N+1)*2
 for i in range(N):
  a=i*2;fs.extend([(a,a+2,a+2+stride,a+stride),(a+1+stride,a+3+stride,a+3,a+1),(a+1,a+3,a+2,a),(a+stride,a+2+stride,a+3+stride,a+1+stride)])
 fs += [(0,stride,stride+1,1),(2*N+1,2*N+1+stride,2*N+stride,2*N)]
 mesh('青蓝真实波纹铁顶',vs,fs,'petrol','SEA_Metal',.008)
part('roof_sheet',corrugated)
part('shop_lintel',lambda:[box('奶白店面门楣',(0,0,.65),(8.45,.42,1.3),'plaster',b=.078),text('廖 孖 記',(0,-.24,.65),7.6,1.0,'darkwood',.04)])
def main_sign():
 tapered('主招牌黄色外框',(0,0,1.14),(9.1,.36,2.28),.025,'gold',b=.065)
 tapered('主招牌红底',(0,-.199,1.14),(8.72,.045,1.91),.025,'red_dark',b=.015)
 text('廖孖記',(0,-.24,1.13),7.7,1.64,'cream',.045)
part('main_sign',main_sign)
def awning():
 # alternating curved fabric strips, each is solid and contiguous.
 count=18
 for i in range(count):
  xa=-4.55+9.1*i/count;xb=-4.55+9.1*(i+1)/count;vs=[];N=14
  for j in range(N+1):
   t=j/N;y=-2.0*t;z=.65-.65*t+.20*math.sin(pi*t);f=1-.035*(1-t)
   vs.extend([(xa*f,y,z),(xb*f,y,z),(xa*f,y,z-.065),(xb*f,y,z-.065)])
  fs=[]
  for j in range(N):
   a=j*4;bb=a+4;fs.extend([(a,bb,bb+1,a+1),(a+2,a+3,bb+3,bb+2),(a,a+2,bb+2,bb),(a+1,bb+1,bb+3,a+3)])
  fs += [(0,1,3,2),(N*4+2,N*4+3,N*4+1,N*4)]
  mesh('红白曲面篷条',vs,fs,'red_dark' if i%2==0 else 'cream',b=.009)
 tube('雨棚圆杆',[(-4.55,-2.01,-.02),(4.55,-2.01,-.02)],.035,'red_dark')
part('awning',awning)
part('fascia',lambda:[box('红色文字檐牌',(0,0,.48),(9.1,.16,.96),'red_dark',b=.035),text('廖 孖 記 腐 乳 王',(0,-.1,.49),8.65,.72,'cream',.024)])
part('blade_sign',lambda:[tapered('小挑挂牌',(0,0,.42),(1.9,.18,.84),.03,'red_dark',b=.03),text('記孖廖',(0,-.12,.42),1.7,.57,'cream',.018),tube('挂牌托架',[(-.65,.1,.42),(-.65,.55,.42)],.05,'stone')])
def poster():
 box('侧面广告金边',(0,0,2.05),(7.5,.16,4.1),'gold',b=.06);box('侧面广告红底',(0,-.10,2.05),(7.26,.06,3.86),'red_dark',b=.02)
 text('廖\n孖\n記',(-2.9,-.15,2.05),.83,3.55,'gold',.017)
 for x in [-1.94,3.05]:
  box('广告黑底细栏',(x,-.145,2.06),(.59,.035,3.6),'darkwood',b=.008)
  text('腐\n乳\n王' if x>0 else '陳\n年\n佳\n釀',(x,-.18,2.05),.46,3.34,'cream',.011)
 box('广告画蓝底',(.52,-.15,2.05),(4.2,.05,3.24),'deepblue',b=.01)
 # All emblem art is geometry, no unapproved image texture. Heads are graphic medallions, not characters.
 for rad,col in [(1.55,'cream'),(1.43,'red_dark'),(1.32,'gold')]:ring('广告圆章',(.52,-.2,2.07),rad,.028,col,'y',steps=60)
 for x in [-.70,1.75]:
  sphere('肖像椭圆',(x,-.22,2.2),(.34,.035,.49),'cream',20,12)
  box('肖像发型',(x,-.27,2.54),(.62,.035,.18),'deepblue',b=.015)
  for xx in [-.10,.10]:sphere('肖像五官',(x+xx,-.27,2.23),(.028,.02,.043),'deepblue',10,6)
  mesh('肖像西装',[(x-.50,-.26,1.19),(x+.50,-.26,1.19),(x+.25,-.26,1.81),(x,-.27,1.48),(x-.25,-.26,1.81)],[(0,1,2,3,4)],'cream')
 box('中央罐身',(.52,-.26,2.02),(.80,.1,1.52),'cream',b=.08)
 for z in [1.35,1.55,2.6,2.78]:box('罐身红条',(.52,-.325,z),(.86,.025,.13),'red_dark',b=.01)
 text('記孖廖',(.52,-.34,2.03),.73,.31,'red_dark',.005)
 for i in range(12):
  a=T*i/12;xx=.52+1.70*math.cos(a);zz=2.05+1.40*math.sin(a)
  sphere('花纹红瓣',(xx,-.22,zz),(.105,.025,.13),'red_dark',10,6)
  sphere('花纹米点',(xx+.13,-.23,zz+.05),(.045,.02,.05),'cream',8,5)
part('poster_panel',poster)
def ac():
 box('外机圆角机壳',(0,0,.825),(2.5,.78,1.65),'cream',b=.085)
 box('外机百叶底色',(.73,-.411,.78),(.88,.018,1.08),'stone',b=.012)
 for z in range(11):box('百叶格',(.73,-.435,.30+z*.095),(.88,.035,.026),'plaster',b=.008)
 sphere('风机深色背孔',(-.51,-.41,.85),(.63,.025,.63),'gray',24,14)
 for i in range(4):
  o=sphere('扇叶',(-.51,-.44,1.13),(.12,.02,.30),'slate',14,8);rotate_mesh(o,i*pi/2,'Y',(-.51,-.44,.85))
 for rad in [.20,.35,.50,.62]:ring('风机保护圈',(-.51,-.47,.85),rad,.012,'stone','y')
 for i in range(10):
  a=pi*i/10;dx=.62*math.cos(a);dz=.62*math.sin(a);tube('风机网栅',[(-.51-dx,-.48,.85-dz),(-.51+dx,-.48,.85+dz)],.009,'stone',sides=6)
 sphere('风机中心',(-.51,-.51,.85),(.09,.025,.09),'plaster',12,8)
 for x in [-.85,.85]:box('外机脚',(x,.06,-.06),(.18,.65,.12),'stone',b=.025)
part('ac_unit',ac)
def pipes():
 tube('弯折排水主管',[(-3.6,0,0),(-3.6,0,3.65),(-3.55,0,3.8),(-2.9,0,3.8),(-2.8,0,3.9),(-2.8,0,4.75)],.065,'stone')
 tube('空调支管',[(-3.3,-.08,2.8),(-3.3,-.08,3.18),(-3.15,-.08,3.27),(3.4,-.08,3.27)],.052,'lightgray')
 for z in [.4,1.9,3.3,4.6]:box('管道固定卡',(-3.60,-.01,z),(.20,.14,.08),'stone',b=.014)
part('pipe_set',pipes)
def vent():
 tube('外墙圆角风管',[(0,0,0),(-.48,0,.1),(-.60,0,.3),(-.60,0,2.2),(-.52,0,2.42),(-.3,0,2.5),(.2,0,2.5)],.36,'wood_mid',sides=16)
 box('通风格口',(.20,-.02,2.5),(.11,.79,.86),'stone',b=.025)
 for y in range(8):tube('通风格条',[(.27,-.32+y*.09,2.14),(.27,-.32+y*.09,2.87)],.013,'slate')
 for z in range(8):tube('通风格条',[(.27,-.35,2.17+z*.09),(.27,.35,2.17+z*.09)],.013,'slate')
part('vent_duct',vent)
def antenna():
 tube('天线主杆',[(0,0,0),(0,0,4.25)],.047,'bark')
 tube('天线横担',[(-1.5,0,4.05),(1.5,0,4.05)],.026,'stone')
 for i in range(11):
  x=-1.43+i*.28;length=.9-.35*abs(x)/1.5;tube('天线振子',[(x,-length/2,4.05),(x,length/2,4.05)],.018,'silver','SEA_Metal',8)
 for z in [.65,.81,1.0]:ring('天线抱箍',(0,0,z),.066,.018,'silver',steps=16)
part('antenna',antenna)
part('clothesline',lambda:[tube('晾衣两杆',[(-2.4,0,0),(-2.4,0,2.7)],.04,'darkwood'),tube('晾衣两杆',[(2.4,0,0),(2.4,0,2.7)],.04,'darkwood'),tube('晾衣绳',[(-2.4,0,2.58),(0,0,2.48),(2.4,0,2.58)],.016,'stone',sides=8)])
def garment(color,jacket=False):
 outline=[(-.48,1.5),(-.20,1.65),(.20,1.65),(.48,1.5),(.86,1.03),(.59,.85),(.43,1.07),(.45,0),(-.45,0),(-.43,1.07),(-.59,.85),(-.86,1.03)]
 vs=[(x,y,z) for y in [-.11,.11] for x,z in outline];N=len(outline);fs=[tuple(reversed(range(N))),tuple(N+i for i in range(N))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
 mesh('柔软圆边衣服',vs,fs,color,b=.05)
 tube('金属衣架',[(-.42,0,1.58),(0,0,1.90),(.42,0,1.58),(-.42,0,1.58)],.021,'stone')
 tube('衣架钩',[(0,0,1.88),(0,0,2.06),(.10,0,2.13),(.18,0,2.04)],.019,'stone')
 if jacket:
  tube('衣服拉链',[(.03,-.17,.12),(.03,-.17,1.58)],.018,'cream')
  for x in [-.25,.25]:box('外套口袋',(x,-.15,.42),(.28,.045,.32),'ochre',b=.025)
 else:
  for x in [-.28,0,.28]:
   for z in [.3,.7,1.12]:
    for j in range(5):sphere('衣服花纹',(x+.04*math.cos(T*j/5),-.17,z+.04*math.sin(T*j/5)),(.033,.015,.033),'pink_light',8,5)
  for z in [.25,.52,.79,1.06,1.33]:sphere('衣扣',(.04,-.18,z),(.024,.02,.024),'cream',8,5)
part('shirt',lambda:garment('red_dark'))
part('jacket',lambda:garment('gold',True))
part('trousers',lambda:[box('长裤左腿',(-.17,0,.69),(.3,.20,1.38),'jade',b=.08),box('长裤右腿',(.17,0,.69),(.3,.20,1.38),'jade',b=.08),box('长裤腰',(0,0,1.4),(.68,.22,.3),'jade',b=.06),tube('裤衣架',[(-.34,0,1.55),(0,0,1.78),(.34,0,1.55)],.02,'stone')])
def washer():
 box('洗衣机壳',(0,0,.73),(1.35,1.1,1.46),'lilac',b=.09);box('洗衣机上盖',(0,0,1.49),(1.30,1.05,.12),'cream',b=.05)
 box('洗衣机操控条',(0,-.57,1.23),(1.12,.05,.19),'plaster',b=.025)
 ring('滚筒圈',(0,-.575,.66),.44,.075,'cream','y');sphere('滚筒玻璃',(0,-.58,.66),(.36,.03,.36),'sage_gray',24,12)
part('washer',washer)
part('table',lambda:[box('木桌面',(0,0,1.21),(3.9,2,.18),'darkwood',b=.07)]+[box('木桌腿',(x,y,.57),(.14,.14,1.14),'wood_mid',b=.025) for x in [-1.7,1.7] for y in [-.8,.8]])
def counter():
 box('店内柜台',(0,0,1.2),(4.1,1.4,2.4),'deepgreen',b=.09);box('柜台面',(0,-.05,2.43),(4.23,1.55,.13),'darkwood',b=.045)
 for z in [2.68,3.45]:box('后陈列架',(0,1.65,z),(4.2,.65,.12),'wood_edge',b=.03)
 for x in [-2.04,2.04]:box('货架竖杆',(x,1.68,2.1),(.11,.12,2.85),'wood_mid',b=.024)
part('shelf',counter)
def jar():
 cylinder('罐装瓶身',(0,0,.30),.19,.54,'ochre','SEA_Gloss',20,.02)
 cylinder('红瓶盖',(0,0,.60),.205,.12,'red_dark',sides=20,b=.025)
 cylinder('奶白纸标签',(0,0,.29),.195,.28,'cream',sides=20,b=.005)
 text('乳',(0,-.20,.30),.25,.22,'red_dark',.003)
part('jar',jar)
part('carton',lambda:[tapered('纸板箱',(0,0,.52),(1.08,.94,1.04),.03,'wood_edge',b=.035),box('封箱带',(0,-.477,.53),(.20,.015,1.0),'butter',b=.003),box('封箱带',(0,0,1.049),(.20,.92,.012),'butter',b=.003)])
def stools():
 for i in range(5):
  z=i*.18
  tapered('套叠凳面',(0,0,z+.89),(.98,.89,.18),.035,'blue',b=.065)
  for x in [-.33,.33]:
   for y in [-.29,.29]:tapered('外撇塑料凳腿',(x,y,z+.41),(.18,.18,.82),.035,'blue',b=.035)
  for y in [-.3,.3]:box('凳脚横撑',(0,y,z+.25),(.78,.09,.09),'blue',b=.025)
part('stool_stack',stools)
part('bin',lambda:[tapered('墨绿带盖收纳桶',(0,0,.57),(1.0,.85,1.14),-.06,'jade',b=.07),box('箱盖',(0,-.01,1.18),(1.14,.98,.15),'sage',b=.045),box('箱把手',(0,-.52,.93),(.34,.07,.11),'deepgreen',b=.03)])
def basket():
 for x in [-.53,.53]:box('筐侧边',(x,0,.47),(.08,.84,.94),'leaf',b=.02)
 for y in [-.40,.40]:
  for i in range(13):box('筐格条',(-.5+i/12,y,.47),(.025,.045,.92),'leaf',b=.006)
  for z in [.08,.25,.42,.59,.76,.93]:box('筐横条',(0,y,z),(1.1,.045,.035),'leaf',b=.007)
 box('筐底',(0,0,.045),(1.1,.85,.09),'leaf',b=.02)
part('basket',basket)
def handtruck():
 tube('手推车竖框',[(-.45,0,.15),(-.45,.22,1.8),(-.34,.25,1.92),(.34,.25,1.92),(.45,.22,1.8),(.45,0,.15)],.042,'silver','SEA_Metal')
 for z in [.42,.73,1.04,1.35]:tube('手推车横档',[(-.43,.12,z),(.43,.12,z)],.031,'silver')
 box('手推车承台',(0,-.29,.13),(.98,.65,.12),'blue',b=.03)
 for x in [-.5,.5]:
  o=cylinder('橡胶轮',(x,.1,.18),.17,.12,'rubber',sides=18,b=.012);rotate_mesh(o,pi/2,'Y',(x,.1,.18))
part('handtruck',handtruck)
part('jerrycan',lambda:[box('青绿水壶',(0,0,.5),(.88,.5,1.0),'teal',b=.08),tube('水壶提手',[(-.2,0,1.02),(-.2,0,1.19),(.20,0,1.19),(.20,0,1.02)],.055,'teal'),cylinder('水壶盖',(.29,0,1.04),.085,.11,'red_dark',sides=16)])
part('mailbox',lambda:[box('红信箱',(0,0,.46),(.66,.37,.92),'red_dark',b=.04),box('邮筒盖',(0,-.01,.96),(.76,.44,.13),'red',b=.03),box('投信槽',(0,-.2,.75),(.43,.02,.05),'darkwood',b=.01)])
def shrine():
 box('壁龛底',(0,0,.1),(.68,.44,.2),'red_dark',b=.025)
 for x in [-.31,.31]:box('壁龛侧柱',(x,0,.56),(.08,.43,.98),'red_dark',b=.018)
 mesh('壁龛尖顶',[(-.36,-.25,1.02),(.36,-.25,1.02),(0,-.25,1.49),(-.36,.25,1.02),(.36,.25,1.02),(0,.25,1.49)],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)],'red_dark',b=.02)
 cylinder('金色小供器',(0,-.05,.35),.13,.23,'gold',sides=16,b=.018);sphere('小供器盖',(0,-.05,.5),(.16,.12,.09),'gold')
part('shrine',shrine)
part('notice',lambda:[box('墙面纸告示',(0,0,.38),(.54,.04,.76),'cream',b=.012),text('記\n1905',(0,-.03,.38),.46,.60,'red_dark',.004)])
def planter():
 cylinder('圆盆',(0,0,.28),.41,.56,'wood_dark',sides=28,b=.024,radtop=.41*1.06)
 ring('圆盆唇口',(0,0,.55),.425,.05,'wood_dark',steps=28);cylinder('盆土',(0,0,.548),.365,.03,'darkwood',sides=24,b=0)
part('planter_round',planter)
part('planter_trough',lambda:[tapered('长盆',(0,0,.30),(2.2,.60,.60),-.06,'wood_mid',b=.04),box('长盆土',(0,0,.603),(2.04,.48,.03),'darkwood',b=.01)])
def leaf(n,a,z=.0,length=.65,width=.20,c='leaf'):
 # closed plump lanceolate leaf, smoothly curved upward.
 d=Vector((math.cos(a),math.sin(a),.65));base=Vector((0,0,z));side=Vector((-math.sin(a),math.cos(a),0));vs=[];N=9
 for i in range(N+1):
  t=i/N;mid=base+d*length*t+Vector((0,0,.19*math.sin(pi*t)));ww=width*math.sin(pi*t)**.7+.005
  for k in [-1,0,1]:vs.append(tuple(mid+side*ww*k+Vector((0,0,.055*(1-abs(k))*math.sin(pi*t)))))
 fs=[]
 for i in range(N):
  for k in range(2):a0=i*3+k;fs.append((a0,a0+1,a0+4,a0+3))
 o=mesh(n,vs,fs,c,smooth=True)
 # Solid leaf thickness, explicit geometry rather than unsupported double-sided faces.
 bm=bmesh.new();bm.from_mesh(o.data);geom=bmesh.ops.extrude_face_region(bm,geom=list(bm.faces))['geom'];verts=[x for x in geom if isinstance(x,bmesh.types.BMVert)];bmesh.ops.translate(bm,verts=verts,vec=Vector((0,0,-.015)));bm.normal_update();bm.to_mesh(o.data);bm.free();finish(o,c,smooth=True)
 return o
part('leaf_cluster',lambda:[leaf('厚阔叶',T*i/9,.03,.58+(i%3)*.15,.13,['leaf','forest','leaf_mid'][i%3]) for i in range(9)])
part('succulent',lambda:[leaf('莲座多肉',T*i/12,.02,.36+(i%2)*.13,.14,'deepgreen' if i%2 else 'jade') for i in range(12)])
def vine():
 pts=[(.12*math.sin(i),0,1.4-i*.175) for i in range(9)];tube('藤蔓茎',pts,.018,'forest',sides=8)
 for i in range(8):
  o=leaf('藤叶',0 if i%2 else pi,0,.27,.10,'leaf_mid');o.data.transform(Matrix.Translation(Vector(pts[i+1])))
part('vine',vine)
def citrus():
 tube('柑橘主干',[(0,0,0),(.05,0,.7),(-.1,0,1.4),(.12,0,2)],.032,'bark')
 for i in range(10):
  a=i*2.4;z=.4+i*.15;p=Vector((.60*math.cos(a),.35*math.sin(a),z+.1));tube('柑橘枝',[(0,0,z),p],.016,'bark',sides=8)
  for j in [-1,1]:
   o=leaf('柑橘叶',a+j*.5,0,.35,.11,'leaf_dark');o.data.transform(Matrix.Translation(p))
  if i%2==0:sphere('金黄柑橘',p+Vector((0,0,-.20)),(.13,.12,.17),'gold',14,9)
part('citrus',citrus)
def fan():
 box('风扇座',(0,0,.08),(.75,.5,.16),'sage_gray',b=.06);tube('风扇颈',[(0,0,.14),(0,0,.6)],.055,'sage_gray')
 for rad in [.2,.36,.48]:ring('风扇罩',(0,0,.96),rad,.014,'sage_gray','y')
 for i in range(3):
  o=sphere('风扇叶',(0,-.03,1.20),(.13,.03,.26),'jade',14,8);rotate_mesh(o,T*i/3,'Y',(0,0,.96))
 for i in range(9):
  a=pi*i/9;tube('风扇护网',[(-.48*math.cos(a),-.08,.96-.48*math.sin(a)),(.48*math.cos(a),-.08,.96+.48*math.sin(a))],.009,'sage_gray',sides=6)
part('display_fan',fan)
part('thermos',lambda:[cylinder('保温瓶身',(0,0,.39),.18,.65,'lightgray',sides=24,b=.03),cylinder('保温杯盖',(0,0,.77),.19,.18,'stone',sides=24,b=.025),cylinder('保温瓶腰线',(0,0,.40),.185,.09,'blue',sides=24,b=.005)])
part('cup',lambda:[cylinder('陶瓷杯',(0,0,.2),.18,.4,'cream',sides=24,b=.02),ring('杯口',(0,0,.41),.18,.018,'cream'),ring('杯柄',(.20,0,.23),.12,.027,'cream','y',steps=20),cylinder('茶面',(0,0,.406),.152,.01,'wood_mid',sides=24,b=0)])
def menu():
 tapered('桌面目录纸板',(0,0,.58),(1.60,.08,1.16),.025,'wood_edge',b=.012)
 for j in range(3):
  for i in range(5):
   x=-.62+i*.31;z=.16+j*.31;box('目录小图',(x,-.048,z),(.22,.015,.22),'darkwood',b=.008);sphere('目录小图亮点',(x,-.06,z+.02),(.07,.01,.065),'wood_light',8,5)
 text('南 貨 目 錄',(0,-.065,1.05),1.42,.15,'darkwood',.003)
part('menu',menu)
part('backdoor',lambda:[box('背门框',(0,0,1.55),(1.8,.20,3.1),'wood_mid',b=.045),box('背面门板',(0,-.12,1.52),(1.53,.10,2.82),'petrol',b=.03),sphere('门把手',(.52,-.22,1.4),(.05,.05,.05),'gold',12,6)])
def ladder():
 for x in [-.55,.55]:tube('背面检修梯边',[(x,0,0),(x,0,10.7)],.055,'steel','SEA_Metal')
 for i in range(34):tube('检修梯横档',[(-.56,-.01,.2+i*.31),(.56,-.01,.2+i*.31)],.041,'steel','SEA_Metal')
part('stair_ladder',ladder)
assert len(catalog)==48
# ASSEMBLY: +X across facade, +Y towards rear, +Z up, storefront faces -Y.
put('deck');put('shell',(0,0,.3));put('slab',(0,0,5.2));put('slab',(0,0,10.3));put('coping',(0,0,10.5))
for x in [-4.05,4.05]:
 put('post',(x,-3.85,.3));put('post',(x,-3.85,5.4))
put('barred_window',(0,-4.02,6.0));put('barred_window',(-4.22,0,6.0),-pi/2)
put('transom',(-4.32,0,4.38),-pi/2)
put('roof_hut',(.0,1.2,10.5));put('roof_sheet',(.0,1.2,13.6))
put('shop_lintel',(0,-4.15,3.70));put('main_sign',(0,-4.48,9.38))
put('awning',(0,-4.12,4.85));put('fascia',(0,-6.16,3.89));put('blade_sign',(4.75,-4.35,3.60),pi/2)
put('poster_panel',(-4.33,.05,.42),-pi/2)
put('ac_unit',(-4.78,-2.30,5.57),-pi/2);put('ac_unit',(-4.78,-2.30,9.83),-pi/2)
for z in [.5,5.6]:put('pipe_set',(-4.42,0,z),-pi/2)
put('vent_duct',(-4.66,3.1,1.7),-pi/2)
put('antenna',(-3.65,3.0,10.5));put('clothesline',(-3.9,.2,10.5),pi/2)
put('jacket',(-4.0,1.2,11.05),-pi/2);put('trousers',(-4.0,-.45,11.16),-pi/2);put('washer',(-3.2,1.0,10.5),-pi/2)
put('shirt',(-4.46,.5,6.55),-pi/2)
put('table',(.6,-2.5,10.5));put('menu',(.7,-2.7,11.8));put('display_fan',(-1.55,-.75,10.5))
put('thermos',(-.4,-2.8,11.8));put('cup',(.2,-3.0,11.8));put('cup',(-1.0,-2.0,11.8));put('carton',(2.1,-1.9,11.8))
put('shelf',(.35,-1.45,.3))
for j in range(2):
 for i in range(8):put('jar',(-1.35+i*.47,.20,.3+2.74+j*.77))
for p in [(-2.9,-3.4,.3),(-2.8,-3.4,1.34),(-2.6,-2.15,.3),(2.9,-2.0,.3)]:put('carton',p)
put('stool_stack',(-3.45,-4.62,.3));put('bin',(-2.15,-4.43,.3));put('basket',(-4.25,-4.52,.31),rot=(math.radians(8),0,0));put('basket',(-3.1,-3.45,2.42))
put('handtruck',(2.93,-3.92,.3));put('jerrycan',(1.80,-3.97,.3));put('mailbox',(4.35,-4.23,2.05));put('shrine',(4.33,-4.20,.40))
for p in [(-3.58,-4.22,2.60),(-3.58,-4.22,3.42),(3.70,-4.23,3.15)]:put('notice',p)
# Plants have separate instances and never share a mesh with containers.
for p,k in [((-3.53,2.25,10.5),'citrus'),((-3.65,3.45,10.5),'leaf_cluster'),((-4.43,2.6,5.55),'leaf_cluster'),((-4.43,1.7,5.55),'succulent'),((-4.43,.1,5.55),'leaf_cluster')]:
 put('planter_round',p);put(k,(p[0],p[1],p[2]+.57),-pi/2 if p[0]<-4 else 0)
for p in [(3.0,-2.7,10.5),(3.5,-.65,10.5)]:
 put('planter_trough',p,pi/2)
 for y in [-.7,0,.7]:put('succulent',(p[0],p[1]+y,p[2]+.62))
put('vine',(-4.5,1.6,5.13),-pi/2)
put('backdoor',(1.1,4.13,.3),pi);put('stair_ladder',(3.3,4.42,.3),pi)
# Display-only studio, no water or fabricated gameplay geometry.
current=top['display'];ground=box('展示地面',(0,0,-.12),(200,200,.14),'sage_gray',b=0);ground['display_support']=True
# neutral background is a display material only, excluded from component roles.
mat=bpy.data.materials.new('BLDA_StudioBackdrop');mat.diffuse_color=(.40,.46,.59,1);mat.use_nodes=True;next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'].default_value=(.40,.46,.59,1);next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Roughness'].default_value=.85;ground.data.materials.clear();ground.data.materials.append(mat)
world=bpy.data.worlds.new('BLDA_StudioWorld');world.use_nodes=True;next(n for n in world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.49,.56,.69,1);next(n for n in world.node_tree.nodes if n.type=='BACKGROUND').inputs[1].default_value=.65;sc.world=world
for name,pos,energy,size in [('Key',(-12,-16,27),3500,13),('Fill',(12,-6,16),2200,12),('Rim',(0,12,23),2800,10)]:
 data=bpy.data.lights.new('BLDA_'+name,'AREA');data.energy=energy;data.shape='DISK';data.size=size;o=bpy.data.objects.new('BLDA_'+name,data);top['display'].objects.link(o);o.location=pos;o.rotation_euler=(Vector((0,0,6))-o.location).to_track_quat('-Z','Y').to_euler();o['display_support']=True
camd=bpy.data.cameras.new('BLDA_Camera');cam=bpy.data.objects.new('BLDA_Camera',camd);top['display'].objects.link(cam);sc.camera=cam;camd.type='ORTHO';camd.ortho_scale=21.7
cam.location=(-26,-33,23);cam.rotation_euler=(Vector((0,0,7.0))-cam.location).to_track_quat('-Z','Y').to_euler()
sc.render.engine='CYCLES';sc.cycles.samples=48;sc.cycles.use_denoising=True;sc.render.resolution_x=1400;sc.render.resolution_y=1400;sc.render.resolution_percentage=100
sc.view_settings.view_transform='Standard';sc.view_settings.look='Medium High Contrast' if 'Medium High Contrast' in [i.name for i in sc.view_settings.bl_rna.properties['look'].enum_items] else 'None';sc.view_settings.exposure=0;sc.view_settings.gamma=1
sc.render.image_settings.file_format='PNG';sc.render.film_transparent=False
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':
  area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.overlay.show_overlays=False;area.spaces.active.shading.type='MATERIAL'
(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.component_instances','coordinate_contract':{'plane':'XY','up':'+Z','rotation':'Euler XYZ radians, Z is vertical','godot_mapping':'(x,y,z)->(x,z,-y)','placement_owner':'Godot TSCN only after future integration'},'instances':layout},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
P['stylized_form']['body']['triangles']=sum(e['triangles']*sum(i['key']==e['key'] for i in layout) for e in catalog if e['layer']=='body')
(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(D/'bld_20261109_a.blend'),compress=True)
sc.render.filepath=str(W/'hero_initial.png');bpy.ops.render.render(write_still=True)
print('BLDA_COMPLETE',json.dumps({'components':len(catalog),'instances':len(layout),'triangles':sum(e['triangles']*sum(i['key']==e['key'] for i in layout) for e in catalog)}),flush=True)

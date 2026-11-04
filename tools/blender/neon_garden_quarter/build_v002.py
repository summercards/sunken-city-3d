"""Revise saved v001: actual connecting garden bridge, continuous arc shell, large damage."""
import bpy,bmesh,ast,math,json,os,hashlib,random
from pathlib import Path
from mathutils import Vector,Matrix,Euler
from mathutils.bvhtree import BVHTree
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/neon_garden_quarter/v002';OLD=D.parent/'v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'neon_garden_quarter/v002'
P=json.loads((D/'component_plan.json').read_text(encoding='utf8'));assert P['status']=='frozen_before_geometry'
assert hashlib.sha256((R/P['parent_source']).read_bytes()).hexdigest()==P['parent_sha256']
bpy.ops.wm.open_mainfile(filepath=str(R/P['parent_source']));bpy.context.preferences.filepaths.save_version=0
S=bpy.data.scenes['霓虹花园街区_完整装配'];M=bpy.data.scenes['组件母版_独立编辑'];bpy.context.window.scene=M
LAY={k:bpy.data.collections[n] for k,n in [('architecture','01_建筑结构'),('fixtures','02_固定设施'),('signage','03_招牌与广告画'),('plants','04_独立植物'),('support','90_展示支持_不导出')]}
ROOTS={k:bpy.data.collections['母版_'+k] for k in ['architecture','fixtures','signage','plants']}
oldcat=json.loads((OLD/'component_catalog.json').read_text(encoding='utf8'))['components'];oldinst=json.loads((OLD/'component_instances.json').read_text(encoding='utf8'))['instances']
COLS={c['key']:bpy.data.collections[c['collection']] for c in oldcat};CAT=[];INST=[];CUR=None
MATS={x:bpy.data.materials['SEA_'+x] for x in ['Matte','Gloss','Emission']}
metal=MATS['Gloss'].copy();metal.name='SEA_Metal'
metal_bsdf=next(n for n in metal.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
metal_bsdf.inputs['Metallic'].default_value=.32
metal_bsdf.inputs['Roughness'].default_value=.46
MATS['Metal']=metal
CELL={c['name']:((c['column']+.5)/8,1-(c['row']+.5)/8) for c in json.loads((R/P['palette']).with_suffix('.json').read_text())['cells']}
FONT=bpy.data.fonts.load('C:/Windows/Fonts/msyhbd.ttc');LATIN=bpy.data.fonts.load('C:/Windows/Fonts/arialbd.ttf')
# Reuse only reviewed primitive/helper definitions, never execute v001's build or layout.
tree=ast.parse((Path(__file__).parent/'build.py').read_text(encoding='utf8'))
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)],type_ignores=[]),'ngq_primitive_helpers','exec'))
for k,c in LAY.items():
 if k!='support':
  for ob in list(c.objects):bpy.data.objects.remove(ob,do_unlink=True)
def remove_component(key):
 if key not in COLS:return
 c=COLS.pop(key)
 for ob in list(c.objects):bpy.data.objects.remove(ob,do_unlink=True)
 bpy.data.collections.remove(c)
def rebuild(key):remove_component(key);return make(key)
def place(key,anchor,rot=(0,0,0),scale=(1,1,1),tag='',author=False,host=None):
 c=COLS[key];mat=Euler(rot).to_matrix();loc=Vector(anchor)
 if author:loc+=mat@Vector([c.get('author_origin_shift',[0,0,0])[i]*scale[i] for i in range(3)])
 ob=bpy.data.objects.new((tag+'_' if tag else '')+key,None);ob.instance_type='COLLECTION';ob.instance_collection=c;ob.location=loc;ob.rotation_euler=rot;ob.scale=scale;LAY[c['category']].objects.link(ob);ob['asset_id']=c['asset_id']
 if host:ob['mounted_to']=host
 INST.append(dict(name=ob.name,key=key,asset_id=c['asset_id'],location=list(loc),euler_xyz=list(rot),scale=list(scale),host=host));return ob
def bounds(col):
 vs=[v.co for o in col.objects for v in o.data.vertices];return [min(v[i] for v in vs) for i in range(3)],[max(v[i] for v in vs) for i in range(3)]
def clean_final(o):
 for _ in range(3):
  o.data.update();bad=[f.index for f in o.data.polygons if f.area<1e-8]
  if not bad:break
  bm=bmesh.new();bm.from_mesh(o.data);bm.faces.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.faces[i] for i in bad],context='FACES_ONLY');bm.to_mesh(o.data);bm.free()
def cut_objects(cutter,objects):
 bpy.context.view_layer.update()
 for ob in objects:
  color=ob.get('palette_color','cream');role=ob.get('material_role','Matte');mod=ob.modifiers.new('真实大体积缺口','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
  bpy.context.view_layer.update();me=bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
  ob.modifiers.remove(mod);ob.data=me
  if len(me.polygons):shade(ob,color,role);clean_final(ob)
  else:bpy.data.objects.remove(ob,do_unlink=True)
 bpy.data.objects.remove(cutter,do_unlink=True)
def flat_window(cx,cy,ang,width=2.4,broken=False):
 rot=Euler((0,0,ang)).to_matrix()
 def b(name,p,s,col,role='Matte'):
  q=rot@Vector(p)+Vector((cx,cy,0));return box(name,q,s,col,.04,role,(0,0,ang))
 for xx in [-width/2,0,width/2]:b('凹窗竖框',(xx,-.06,2.35),(.14,.24,2.7),'sage_gray')
 for z in [1,3.7]:b('窗横框',(0,-.06,z),(width+.14,.24,.14),'cream')
 for xx in [-width/4,width/4]:
  if broken and xx>0:continue
  b('真实凹入玻璃',(xx,.08,2.35),(width/2-.12,.08,2.55),'ocean','Gloss')
def outline(damage=0):
 xy=[]
 for i in range(25):
  a=math.pi+i*math.pi/48;r=4
  if damage and i in [8,9,10,11]:r-=.6 if damage==1 else 1.1
  xy.append((-.5+r*math.cos(a),-5+r*math.sin(a)))
 return xy+[(4.5,-9),(4.5,9),(-4.5,9)]
def arc_band(name,z0,z1,r=4,thick=.4,color='cream',a0=math.pi,a1=math.pi*1.5):
 return arc(name,(-.5,-5),r,thick,z0,z1,a0,a1,color,max(3,round(24*(a1-a0)/(math.pi/2))))
def right_storey(key,damage=0):
 rebuild(key);prism('同一弧形轮廓_实体楼板',outline(damage),0,.2,'cream',.044)
 # Front quarter is real masonry with no rectangular corner behind it.
 gap=(3.48,4.19) if damage==1 else (3.33,4.49)
 segments=[(math.pi,math.pi*1.5)] if not damage else [(math.pi,gap[0]),(gap[1],math.pi*1.5)]
 for a0,a1 in segments:
  arc_band('弧形实体下墙',.2,1,a0=a0,a1=a1,color='plaster');arc_band('弧形实体上梁',3.8,5.1,a0=a0,a1=a1,color='cream')
 if damage:
  # Uneven major stumps at the edges of an actual missing wall/beam volume.
  for a,h in [(gap[0]+.08,1.65),(gap[1]-.08,.75)]:
   arc_band('断墙大残根',.2,h,a0=a-.08,a1=a+.08,color='stone')
   x=-.5+3.8*math.cos(a);y=-5+3.8*math.sin(a);tube('短粗断筋',[(x,y,h),(x+.12,y,h+.45)],.065,'wood_dark',sides=6)
 for i in range(6):
  a=math.pi+i*math.pi/10
  if damage and gap[0]<a<gap[1]:continue
  x=-.5+3.8*math.cos(a);y=-5+3.8*math.sin(a);box('弧面承重柱',(x,y,2.65),(.5,.5,4.9),'cream',.095,rot=(0,0,a))
 for i in range(5):
  a0=math.pi+i*math.pi/10+.055;a1=math.pi+(i+1)*math.pi/10-.055
  if damage and a0<gap[1] and a1>gap[0]:continue
  o=arc_band('与楼体同心的凹弧玻璃',1.05,3.75,3.85,.08,'ocean',a0,a1);shade(o,'ocean','Gloss')
  for zz in [1.02,3.7]:arc_band('弧窗厚框',zz,zz+.14,4.03,.25,'sage_gray',a0-.025,a1+.025)
 # Three remaining elevations plus the straight front tangent are complete.
 for x,y,sx,sy in [(2,-8.8,5,.4),(0,8.8,9,.4),(-4.3,2,.4,14),(4.3,0,.4,18)]:
  for z,h in [(.6,.8),(4.45,1.3)]:box('与弧角连续的直墙',(x,y,z),(sx,sy,h),'plaster',.065)
 for x in [-.35,2,4.25]:box('前侧主柱',(x,-8.75,2.65),(.5,.5,4.9),'cream',.095)
 for x in [-4.25,-1.5,1.5,4.25]:box('后侧主柱',(x,8.75,2.65),(.5,.5,4.9),'cream',.095)
 for x,ys in [(-4.25,[-4.75,-2,1,4,7,8.75]),(4.25,[-8.75,-6,-3,0,3,6,8.75])]:
  for y in ys:box('侧面主柱',(x,y,2.65),(.5,.5,4.9),'cream',.095)
 for x in [.8,3.2]:flat_window(x,-9.05,0,2.0,damage==2)
 for x in [-2.9,0,2.9]:flat_window(x,9.05,math.pi,2.4,damage==1 and x==0)
 for y in [-3.4,-.5,1.8,5.5,7.85]:
  if damage==2 and y==1.8:continue
  flat_window(-4.55,y,-math.pi/2,2.1,damage==2 and y==-3.4)
 for y in [-7.4,-4.5,-1.5,1.5,4.5,7.4]:flat_window(4.55,y,math.pi/2,2.4)
 if damage==2:
  targets=[o for o in CUR.objects if o.name.startswith('与弧角连续的直墙') and min(v.co.x for v in o.data.vertices)<-4.1]
  cutter=box('临时右桥门洞',(-4.3,1.5,1.72),(1.45,1.9,3.04),'stone',0);cut_objects(cutter,targets)
  for yy in [.55,2.45]:box('桥门承托门垛',(-4.34,yy,1.76),(.5,.22,3.12),'cream',.065)
  box('桥门顶部实梁',(-4.34,1.5,3.38),(.5,2.1,.3),'cream',.065)
 finish(key);COLS[key]['curvature_radius_m']=4.0;COLS[key]['arc_center_local']=[-.5,-5];COLS[key]['damage_state']=damage
for k,d in [('round_storey',0),('round_damaged',1),('round_ruin',2)]:right_storey(k,d)
rebuild('round_roof');prism('与七层完全同形的弧形屋顶',outline(),0,.2,'cream',.044)
arc_band('弧形女儿墙',.2,1.25,4.0,.4,'plaster');arc_band('弧形屋顶压顶',1.2,1.42,4.12,.55,'cream')
for x,y,sx,sy in [(2,-8.8,5,.4),(0,8.8,9,.4),(-4.3,2,.4,14),(4.3,0,.4,18)]:box('屋顶连贯围护',(x,y,.75),(sx,sy,1.1),'plaster',.12)
finish('round_roof');COLS['round_roof']['curvature_radius_m']=4.0

# A real large Boolean breach through masonry, not a relief pasted onto an intact wall.
make('left_damaged')
for src in COLS['left_storey'].objects:
 ob=src.copy();ob.data=src.data.copy();CUR.objects.link(ob)
targets=list(CUR.objects)
cutter=box('临时断墙裁切',(-2.9,-8.5,3.75),(4.5,4.1,5.0),'stone',.06,rot=(0,.15,.12));cut_objects(cutter,targets)
targets=list(CUR.objects);cutter=prism('临时楼板大缺角',[(-5,-10),(-1.8,-10),(-2.25,-8.5),(-3.1,-7.6),(-5,-7)],-.2,.5,'stone',0);cut_objects(cutter,targets)
for p in [(-2.75,-8.8,.64),(-3.8,-8.66,.65)]:tube('断墙上露出的短粗筋',[p,(p[0]+.12,p[1],p[2]+.44)],.075,'wood_dark',sides=6)
targets=[o for o in CUR.objects if o.name.startswith('侧面连续墙带') and max(v.co.x for v in o.data.vertices)>4]
cutter=box('临时左桥门洞',(4.3,1.5,1.72),(1.45,1.9,3.04),'stone',0);cut_objects(cutter,targets)
for yy in [.55,2.45]:box('桥门承托门垛',(4.34,yy,1.76),(.5,.22,3.12),'cream',.065)
box('桥门顶部实梁',(4.34,1.5,3.38),(.5,2.1,.3),'cream',.065)
finish('left_damaged')

# Garden now spans the alley. End bearings extend into both structural wings.
make('garden_bridge');box('菜园承重板_0.2',(0,0,1.1),(9.4,8.4,.2),'cream',.044)
for y in [-4.0,4.0]:
 box('前后横跨承重边梁',(0,y,.55),(9.4,.65,1.1),'cream',.10)
 for z in [.22,.88]:box('梁内宽翼缘',(0,y,z),(9.2,.85,.17),'sage_gray',.05)
for x in [-4.4,4.4]:box('两端入楼承台',(x,0,.6),(.8,8.4,1.2),'plaster',.10)
for y in [-2,0,2]:box('桥下粗次梁',(0,y,.78),(8.5,.36,.42),'teal',.07)
finish('garden_bridge')

make('fractured_ground')
prism('左楼完整受力底坪',[(-12.85,-8.4),(-3.25,-8.4),(-3.25,10.35),(-12.85,10.35)],0,.2,'stone',.044)
xy=[(x+8,y+1) for x,y in outline()];prism('右楼同轮廓底坪',xy,0,.2,'stone',.044)
prism('后楼底坪',[(-4.7,9.7),(4.7,9.7),(4.7,18.3),(-4.7,18.3)],0,.2,'stone',.044)
prism('外梯脚下收边平台',[(-17,1.1),(-12.5,1.1),(-12.5,9.6),(-16.2,9.6),(-17,8.6)],0,.2,'stone',.044)
for j in range(5):
 y=-9.9+j*4
 for side in [-1,1]:
  x0=-3.5 if side==-1 else .12;x1=-.12 if side==-1 else 3.5
  xy=[(x0,y+.12),(x1-.2,y),(x1,y+1.5),(x1-.18,y+3.8),(x0+.18,y+3.86),(x0,y+2.2)]
  prism('街巷大块裂分铺地',xy,0,.2+(j%2)*.04,'stone' if j%2 else 'plaster',.035)
prism('路面裂缝下连续的灰青基层',[(-3.5,-9.65),(3.5,-9.65),(3.5,10),(-3.5,10)],0,.14,'sage_gray',.025)
for pts in [[(-12.9,-8.35),(-3.5,-8.35),(-3.5,-10.6),(-6,-10.9),(-6.4,-10.3),(-10.8,-10.5),(-12.9,-9.5)],[(4.5,-8.3),(12.7,-8.3),(12.7,-10),(10.2,-10.6),(8.9,-10.1),(7.3,-10.6),(4.5,-9.2)]]:prism('门前大断边铺装',pts,0,.2,'plaster',.04)
finish('fractured_ground')

make('sign_bracket');box('墙上锚定板',(0,.78,.6),(.3,.16,1.2),'sage_gray',.045,'Metal');box('粗承托臂',(0,.35,.12),(.18,1,.24),'sage_gray',.035,'Metal');tube('三角挂架',[(0,.72,1),(0,-.1,.22)],.075,'wood_dark','Metal');finish('sign_bracket')
def assign_print(ob,tile,uvs):
 uv=ob.data.uv_layers.new(name='PosterUV');mask=ob.data.attributes.new('PosterMask','FLOAT','POINT')
 for t in mask.data:t.value=1
 for f in ob.data.polygons:
  for li in f.loop_indices:
   u,v=uvs[ob.data.loops[li].vertex_index];uv.data[li].uv=((tile%4+.012+u*.976)/4,1-(tile//4+.012+(1-v)*.976)/2)
 ob.data.uv_layers.active_index=0;ob.data.uv_layers[0].active_render=True;uv.active_render=False;ob['poster_tile']=tile
def damage_poster(key,w,h,tile):
 rebuild(key);shape=[(-w/2,0),(w/2-.42,0),(w/2,.62),(w/2,h-.1),(w/2-.3,h),(-w/2,h)]
 ob=prism('缺角厚招牌背板',shape,0,.26,'cream',.05)
 for v in ob.data.vertices:v.co=(v.co.x,.13-v.co.z,v.co.y)
 graphic=[(x,-.145,z) for x,z in shape];ob=mesh('缺角印刷画',graphic,[tuple(range(len(graphic)))],'cream')
 uvs=[((x+w/2)/w,z/h) for x,z in shape]
 if tile==1:uvs=[(u,.38+v*.55) for u,v in uvs]
 assign_print(ob,tile,uvs)
 for x in [-w/2,w/2]:box('折损厚竖框',(x,-.15,h/2+.14),(.16,.18,h-.3),'wood_dark',.045)
 box('缺失一截上框',(.18,-.15,h),(w-.5,.18,.16),'wood_dark',.04,rot=(0,-.035,0));box('断裂下边框',(-.24,-.15,0),(w-.55,.18,.16),'wood_dark',.04)
 finish(key);COLS[key]['damage_state']='large_corner_missing_and_frame_bent'
for row in [('bar_poster',2.35,5,0),('portrait_poster',4.6,4.2,1),('drink_poster',3.4,4.2,2),('route_board',2,3.1,4),('menu_board',3.3,3.3,5),('small_placard',1.25,2.4,7)]:damage_poster(*row)

rebuild('charcoal_sign');a0=math.pi+.06;a1=math.pi*1.5-.03
def sign_bottom(u):return .85*(1-u/.14) if u<.14 else 0
angles=[a0+(a1-a0)*i/28 for i in range(29)]
shell_vertices=[(r*math.cos(a),r*math.sin(a),z) for i,a in enumerate(angles) for r in [4.30,4.08] for z in [sign_bottom(i/28),8.4]]
shell_faces=[(0,1,3,2),(112,114,115,113)]
for i in range(28):
 n=i*4
 for j,k in [(0,1),(1,3),(3,2),(2,0)]:shell_faces.append((n+j,n+k,n+4+k,n+4+j))
mesh('真正弧面缺角广告背壳',shell_vertices,shell_faces,'wood_dark',bevel=.035)
vs=[];uvs=[];faces=[]
for i in range(29):
 u=i/28;a=a0+(a1-a0)*u;bottom=sign_bottom(u)
 for z in [bottom,8.3]:vs.append((4.33*math.cos(a),4.33*math.sin(a),z));uvs.append((u,z/8.3))
 if i:faces.append((2*i-2,2*i,2*i+1,2*i-1))
ob=mesh('弧形缺角炭火印画',vs,faces,'cream');assign_print(ob,3,uvs)
for a,z in [(a0,1.05),(a1,.15)]:tube('弯曲竖招牌框',[(4.37*math.cos(a),4.37*math.sin(a),z),(4.37*math.cos(a),4.37*math.sin(a),8.4)],.10,'wood_dark')
arc('上部弧形奶油眉头',(0,0),4.38,.3,8.4,10.05,a0,a1,'cream',28)
for i,ch in enumerate('海道酒場'):
 a=a0+(a1-a0)*(i+.5)/4;before=set(CUR.objects);text(ch,(0,0,9.2),1.05,1.25,'jade')
 mat=Euler((0,0,a+math.pi/2)).to_matrix()
 for ob in set(CUR.objects)-before:
  for v in ob.data.vertices:v.co=mat@v.co+Vector((4.57*math.cos(a),4.57*math.sin(a),0))
finish('charcoal_sign');COLS['charcoal_sign']['curvature_radius_m']=4.3;COLS['charcoal_sign']['damage_state']='clipped_lower_corner'

# Long signs retain their distinctive thick type but lose chunks of backing/frame.
for key in ['tavern_sign','restaurant_neon']:
 CUR=COLS[key];targets=[o for o in CUR.objects if not o.name.startswith('EM_')]
 lo,hi=bounds(CUR);cutter=box('临时招牌缺口',(hi[0]-.10,0,.25),(.7,3,1.05),'stone',.03,rot=(0,-.3,0));cut_objects(cutter,targets)
 # Original meshes are already centered; recenter and regenerate this catalog entry.
 finish(key);COLS[key]['damage_state']='lower_edge_chunk_missing'
rebuild('lantern');ob=sphere('摔扁熄灭灯笼',(0,0,.55),(.50,.36,.53),'coral',16,10)
targets=[ob];cutter=box('临时灯笼大裂口',(.44,-.2,.8),(.45,.6,.6),'stone',0,rot=(0,.2,.2));cut_objects(cutter,targets)
box('脱落灯笼端帽',(.55,.12,.12),(.55,.5,.2),'wood_dark',.045,rot=(0,.2,.3));tube('弯折灯笼提环',[(-.2,0,.9),(-.28,0,1.3),(.05,0,1.28),(.2,0,.95)],.045,'wood_dark');finish('lantern');COLS['lantern']['fallen_extinguished']=True

for key in P['retired_components']:remove_component(key)
# Re-register retained component definitions without modifying their geometry.
done={c['key'] for c in CAT}
for meta in P['components']:
 key=meta['key']
 if key not in done:
  old=next(c for c in oldcat if c['key']==key);entry=dict(old);entry.update(meta);CAT.append(entry)
for c in CAT:
 c['source']=f'art_source/scenes/neon_garden_quarter/v002/component_packages/{c["key"]}/{c["key"]}.blend';c['manifest']=f'art_source/scenes/neon_garden_quarter/v002/component_packages/{c["key"]}/asset_manifest.json'
 for stale in ['source_sha256','verification','geometry_fingerprint']:c.pop(stale,None)
 c['source_stage']='authored_pending_reopen_verification'
CAT.sort(key=lambda c:c['asset_id'])

# Preserve unrelated details, but remove all former applique corners and arbitrary posters.
plantkeys={c['key'] for c in P['components'] if c['category']=='plants'};signkeys={c['key'] for c in P['components'] if c['category']=='signage'}
for row in oldinst:
 key=row['key'];x,y,z=row['location'];name=row['name']
 if key in P['retired_components'] or key in plantkeys or key in signkeys or key in ['lantern','crop_bed','trellis','planter','roof_soil']:continue
 if name.startswith('right_') and key in ['window_pair','window_broken','double_door','shop_awning']:continue
 if key=='street_deck' and (z<1 or x>4):continue
 if key in ['parapet','broken_parapet'] and z>35:continue
 if key=='round_storey':continue
 if key=='left_storey' and round((z-.3)/5.1)==5:key='left_damaged'
 if name.startswith('left_') and key in ['window_pair','window_broken']:
  k=round((z-1-.3)/5.1)
  if k==5 and ((y< -7 and x< -7.4) or (x< -12 and y< -5.2) or (x> -4 and abs(y-2.5)<1.25)):continue
 place(key,row['location'],tuple(row['euler_xyz']),tuple(row['scale']),tag='保留')
for i in range(7):place(['round_storey','round_storey','round_damaged','round_damaged','round_storey','round_ruin','round_damaged'][i],(8,1,.3+i*5.1),author=True,tag=f'右楼第{i+1}层')
place('round_roof',(8,1,36),author=True,tag='右楼一体弧顶')
ground=place('fractured_ground',(0,0,.1),author=True)
place('street_deck',(0,14,25.8),scale=(9/30,8/29,1),tag='后楼补全屋顶')
place('roof_room',(0,15.2,26));place('water_tank',(-2.5,15.5,26))
place('garden_bridge',(0,0,24.6),author=True,tag='跨街连接_两端进入楼体')
place('roof_soil',(0,-.7,25.8),scale=(.98,.71,1),tag='跨街菜园土坪')
random.seed(298)
for xx in [-2.8,0,2.8]:
 place('crop_bed',(xx,-.75,26.05),scale=(1,.78,1))
 for j in range(5):
  for dx in [-.55,.55]:place('cabbage' if xx<0 else 'herb',(xx+dx,-2.3+j*.76,26.4),rot=(0,0,random.random()*6.28))
 place('trellis',(xx,1.5,26.3))
 for dx in [-.65,.65]:place('tomato',(xx+dx,1.45,26.3),rot=(0,0,random.random()))

mounts=[]
def mount(key,pos,host,rz=0,lean=.08,scale=1):
 row=next(c for c in CAT if c['key']==key);w,dep,h=row['bounds_size_m'];o=place(key,pos,(0,lean,rz),(scale,scale,scale),tag='有支承旧招牌',host=host)
 supports=[];board_transform=Euler((0,lean,rz)).to_matrix()
 for xx,zz in [(-w*.29,h*.16),(w*.29,h*.74)]:
  anchor=Vector(pos)+board_transform@Vector((xx*scale,.12*scale,zz*scale))
  if host.startswith('back'):wall=Vector((anchor.x,10.0,anchor.z))
  elif host.startswith('left') or host.startswith('right_front') or host=='right_shop_pier':wall=Vector((anchor.x,-8.06,anchor.z))
  elif host=='garden_bridge_right_bearing':wall=Vector((min(4.3,anchor.x+.45),-3.97,min(anchor.z,25.62)))
  elif host=='right_inner_wall_and_bridge_bearing':wall=Vector((3.54,-4.4,anchor.z))
  else:
   outward=Vector((anchor.x-7.5,anchor.y+4,0)).normalized();wall=Vector((7.5,-4,anchor.z))+outward*4.0
  delta=wall-anchor;length=delta.length
  rot=delta.to_track_quat('Y','Z').to_euler()
  b=place('sign_bracket',anchor-rot.to_matrix()@Vector((0,0,.12)),rot=rot,scale=(1,max(.2,length/.78),1),author=True,tag='招牌挂架',host=host);supports.append(b.name)
 mounts.append(dict(sign=o.name,host=host,brackets=supports,tilt_euler=list(o.rotation_euler),key=key));return o
mount('bar_poster',(-4.9,-9,24.2),'left_front_masonry',lean=-.075)
mount('bar_poster',(-5.05,-9.0,13.0),'left_front_masonry',lean=.11)
mount('round_sign',(-5.0,-9.1,9.3),'left_front_masonry',lean=-.16)
mount('menu_board',(-9.2,-9.0,18.3),'left_front_masonry',lean=-.09)
mount('small_placard',(-9.5,-9.0,5.8),'left_shop_pier',lean=.13)
mount('route_board',(2.65,-4.72,24.55),'garden_bridge_right_bearing',lean=-.09)
mount('restaurant_neon',(2.15,-4.9,12.6),'right_inner_wall_and_bridge_bearing',lean=.06)
mount('tavern_sign',(4.25,-7.3,9.3),'right_curved_facade',rz=-math.pi/4,lean=-.065)
# Curved panel's center is the actual building corner center; attached standoffs follow that arc.
o=place('charcoal_sign',(7.5,-4,21),rot=(.008,-.012,-.035),author=True,tag='同心弧形酒楼旧牌',host='right_curved_facade')
br=[]
for a,z in [(3.3,22),(4.5,22),(3.3,29),(4.5,29)]:
 b=place('sign_bracket',(7.5+4.25*math.cos(a),-4+4.25*math.sin(a),z),rot=(0,0,a+math.pi/2),author=True,host='right_curved_facade');br.append(b.name)
mounts.append(dict(sign=o.name,host='right_curved_facade',key='charcoal_sign',brackets=br,tilt_euler=list(o.rotation_euler)))
mount('menu_board',(10,-9,13.3),'right_front_tangent_wall',lean=.10)
mount('small_placard',(10.1,-9,5.5),'right_shop_pier',lean=-.15)
mount('portrait_poster',(-1.1,9.2,11.5),'back_front_masonry',lean=-.04)
mount('drink_poster',(-1.15,9.2,17.1),'back_front_masonry',lean=.07)
mount('small_placard',(2.1,9.2,6),'back_shop_pier',lean=.12)
for x in [8.8,11]:place('double_door',(x,-8.2,.3));place('shop_awning',(x,-8.8,3.65),rot=(0,.10 if x>10 else -.10,0))
# Settle fallen objects against the actual uneven street paving.
vertices=[];faces=[]
for ob in COLS['fractured_ground'].objects:
 offset=len(vertices);vertices.extend(v.co+ground.location for v in ob.data.vertices);faces.extend([offset+i for i in f.vertices] for f in ob.data.polygons)
terrain=BVHTree.FromPolygons(vertices,faces)
def on_floor(key,x,y,z,rot,scale=(1,1,1),tag='坠落'):
 mat=Euler(rot).to_matrix();contacts=[]
 for ob in COLS[key].objects:
  for v in ob.data.vertices:
   p=mat@Vector([v.co[i]*scale[i] for i in range(3)]);hit=terrain.ray_cast((x+p.x,y+p.y,2),(0,0,-1))[0]
   if hit is not None:contacts.append(hit.z-p.z)
 assert contacts,(key,x,y)
 return place(key,(x,y,max(contacts)+.002),rot,scale,tag=tag)
for x,y,az in [(-8.1,-9.8,.4),(-5.5,-9.7,1.5),(8.8,-9.1,-.5),(10.2,-9.5,.8),(1.6,7.5,.4)]:on_floor('lantern',x,y,.32,(math.pi/2,.25,az))
on_floor('small_placard',-2.4,-6.2,.32,(math.pi/2,.08,-.25),tag='坠落断招牌')
for x,y,sc in [(-11.4,-9.5,2.2),(-9.1,-9.7,1.3),(6,-8.9,2),(8.0,-10,1.7),(2.6,-.5,1.2),(-2.4,6.8,1.0),(-12.9,7.5,1.6)]:on_floor('rubble',x,y,.32,(.1,.13,random.random()*6.28),(sc,sc,sc),tag='大块坍落混凝土')
# Sparse foliage is rooted in containers, crevices or the bridge, never attached to empty space.
for x,y,z in [(-8,-7,31.1),(-8,7,31.1),(8,7,36.2),(8.6,-5.2,36.2)]:
 place('planter',(x,y,z));place('grass',(x-.5,y,z+.94));place('flowers',(x+.6,y,z+.94));place('hanging_bush',(x,y-.3,z+.5),scale=(.8,.8,.8))
for x,y,z in [(-3.6,-4.35,23.3),(3.3,-4.4,23.3),(-4.4,-8.9,27),(-6,-8.9,14.5),(9.8,-9,16.5)]:place('vine',(x,y,z));place('flowers',(x,y,z+2.9),scale=(.7,.7,.7))
for x,y in [(-11.4,-10),(-4.0,-9.4),(6.6,-9.4),(11.5,-9.8),(-2.9,3),(2.8,6.2)]:place('broadleaf',(x,y,.32));place('grass',(x+.5,y+.2,.32))

# Structural review cameras emphasize the bridge and full-depth rounded building.
def setcam(name,pos,target,ortho):
 o=bpy.data.objects[name];o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();o.data.type='ORTHO';o.data.ortho_scale=ortho
setcam('全景_完整建筑群',(-25,-65,49),(0,2,17),51)
setcam('参考镜头_街巷',(-.5,-52,35),(0,1,18),36)
setcam('近景_屋顶菜园',(-12,-28,36),(0,-.5,25.7),19)
setcam('近景_招牌厚字',(27,-36,33),(5,-4,22),28)
setcam('俯视_空间布局',(0,2,80),(0,2,0),36)
setcam('补全_背面屋顶',(-43,58,42),(0,4,17),51)
for name,pos,targ,ortho in [('专项_弧楼全高',(40,-38,43),(8,1,18),46),('专项_桥下连接',(0,-24,24),(0,0,25),14),('专项_地面坠落',(-18,-28,17),(0,-5,2),30)]:camera(name,pos,targ,ortho)
S.camera=bpy.data.objects['全景_完整建筑群'];S['revision']='v002_structural_rebuild';S['building_class']='above_water'
bpy.context.window.scene=S;bpy.context.view_layer.update()
for sc in bpy.data.screens:
 for area in sc.areas:
  if area.type=='VIEW_3D':area.spaces.active.region_3d.view_location=(0,2,18);area.spaces.active.region_3d.view_distance=58;area.spaces.active.region_3d.view_rotation=S.camera.rotation_euler.to_quaternion()
for img in bpy.data.images:
 if img.source=='FILE':
  actual=R/P['palette'] if img.name.startswith('SEA_') else R/P['poster_source'];img.filepath=bpy.path.relpath(str(actual),start=str(D))
bpy.ops.wm.save_as_mainfile(filepath=str(D/'neon_garden_quarter.blend'),compress=True)
dump(D/'component_catalog.json',dict(schema='sea.component_catalog',version='v002',components=CAT));dump(D/'component_instances.json',dict(schema='sea.component_instances',coordinate_system='Blender XY ground +Z up; full Euler XYZ; Godot(x,z,-y)',instances=INST));dump(D/'mounting_manifest.json',dict(signs=mounts))
print('V002_BUILD_COMPLETE',len(CAT),'components',len(INST),'instances',flush=True)

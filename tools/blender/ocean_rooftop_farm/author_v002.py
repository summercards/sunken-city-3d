"""Fresh sea rooftop farm, authored through live Blender MCP. No old blend read."""
import bpy, math, random, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector, Matrix
R=Path('D:/projects/sea'); D=R/'art_source/scenes/ocean_rooftop_farm/v002'; W=R.parent/'sea-work/ocean_rooftop_farm/v002'
D.mkdir(parents=True,exist_ok=True); W.mkdir(parents=True,exist_ok=True)
random.seed(110309)
REF=Path('C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-11-03T01-00-05-502Z-c2c3c968.jpg')
PAL=R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
DEFS=[
('shell','灰色混凝土塔楼墙壳','structure','shell'),('slab','密集楼层楼板','structure','slab'),('pier','厚实混凝土结构柱','structure','pier'),
('window','深蓝双联窗','fixture','window'),('balcony','崩角生活阳台','structure','balcony'),('weather','混凝土剥落与裂纹','structure','weather'),
('roof','农场屋面基层','structure','roof'),('parapet','青苔破损女儿墙','structure','parapet'),('rail','歪斜锈蚀栏杆','fixture','rail'),
('grass','半野生草皮','flora','ground_cover'),('tuft','丛生野草','flora','grass'),('vine','墙角下垂藤蔓','flora','vine'),
('platform','左后抬高生活区','structure','platform'),('room','平台顶部小间','structure','room'),('ladder','锈蚀外挂爬梯','fixture','ladder'),('line','晾衣架与衣物','fixture','drying'),
('shed','红铁皮顶工具棚','fixture','shed'),('coop','蓝色空鸡舍','fixture','coop'),('fence','断裂歪斜木围栏','fixture','fence'),
('greenhouse','缺片透明温室','fixture','greenhouse'),('tank','木支撑锈蚀水塔','fixture','tank'),('wind','小型偏斜风车','fixture','wind'),('solar','锈框太阳能板','fixture','solar'),
('bed','老化木框菜床','fixture','bed'),('field','条垄主农田','fixture','field'),('cabbage','饱满宽叶菜','flora','crop'),('seedling','双叶幼苗','flora','crop'),('tomato','攀爬果蔬','flora','crop'),
('stone','厚实不规则踏石','fixture','path'),('plank','旧木步道板','fixture','path'),('compost','变形堆肥箱','fixture','compost'),('pot','崩口厚边花盆','fixture','pot'),('plant','宽厚盆栽叶簇','flora','plant'),
('pipe','老化屋顶管线','fixture','utility'),('table','圆桌','fixture','table'),('chair','旧木椅','fixture','chair'),('crate','储物木箱','fixture','crate'),('barrel','锈箍储物桶','fixture','barrel'),('lamp','弯臂屋顶灯','fixture','lamp')]
plan={'schema':'sea.scene.component_plan','version':'v002','status':'frozen_before_final_geometry','reference_sha256':hashlib.sha256(REF.read_bytes()).hexdigest(),'reference':'reference.jpg','previous_source_used':False,'building_class':'above_water','feature_id':'SEA-ASSET','design_clause':'SEA-ASSET-R41','loaded_difference':'.agents/skills/sea-scene-component-authoring/references/above-water.md','palette':str(PAL.relative_to(R)),'material_roles':['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'],'component_budget':{'limit':50,'planned':len(DEFS),'remaining':50-len(DEFS)},'dimensions':{'building_xy_m':[48,32],'roof_top_z_m':60.0,'floors':12,'floor_height_m':5.0,'parapet_wh_m':[1.2,1.1],'greenhouse_m':[6,4,3.6],'tank_height_m':6.0,'tank_diameter_m':3.0,'shed_m':[4,3,3.1],'coop_m':[3,2,2.1]},'exceptions':['Roof 60m follows latest user text, 5m x12 floors replaces default 5.1m; no scale applied to other assets.','Large tower slab thickness 0.3m; ordinary roof slabs 0.2m.','Reference greenhouse depth interpreted as 4m text; arranged as two contiguous 6x4 modules to recover elongated reference silhouette.','Procedural draft was discarded before final component authoring; no claim that failed draft passed plan-first gate.'],'excluded':['animals','people','sea','sky','distant_buildings','background_geometry'],'components':[{'key':k,'asset_id':'SEA-SCENE-ORF2-'+k.upper(),'name':n,'category':cat,'component_family':fam,'scope':'scene_local','origin':'bottom_center','front_axis':'-Y','allowed_rotations_y_deg':[0,90,180,270],'budget_triangles':50000,'collision_owner':'future_Godot_wrapper_pending'} for k,n,cat,fam in DEFS]}
assert len(DEFS)<=50
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8'); shutil.copyfile(REF,D/'reference.jpg')
# Isolate from failed draft and preserve user's initial scene in file.
NAME='海上屋顶农场_全新组件制作_v002'
old=bpy.data.scenes.get(NAME)
if old:
 bpy.context.window.scene=bpy.data.scenes.get('Scene') or bpy.data.scenes[0]
 for o in list(old.objects): bpy.data.objects.remove(o,do_unlink=True)
 bpy.data.scenes.remove(old)
s=bpy.data.scenes.new(NAME);bpy.context.window.scene=s;s.unit_settings.system='METRIC'
root=bpy.data.collections.new('ORF2_屋顶农场_中文资产管理');s.collection.children.link(root)
out=bpy.data.collections.new('02_游戏输出_组件实例');root.children.link(out)
groups={}
for cat,n in [('structure','01_建筑结构'),('fixture','02_固定设施'),('flora','03_花草作物')]:
 c=bpy.data.collections.new('ORF2_'+n);out.children.link(c);groups[cat]=c
src=bpy.data.collections.new('01_制作组件_独立母版');root.children.link(src)
qa=bpy.data.collections.new('90_展示与验收_不导出');root.children.link(qa)
img=bpy.data.images.load(str(PAL),check_existing=True);img.filepath=str(PAL)
cells={x['name']:x for x in json.loads(PAL.with_suffix('.json').read_text(encoding='utf-8'))['cells']}
roles=[]
for name,metal,rough,coat,emit in [('SEA_Matte',.02,.72,0,0),('SEA_Metal',.8,.3,.15,0),('SEA_Gloss',.12,.16,.7,0),('SEA_Emission',0,.38,0,1.1)]:
 # fresh materials never alter another scene's shaders
 m=bpy.data.materials.new('ORF2_'+name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;n.clear();p=n.new('ShaderNodeBsdfPrincipled');o=n.new('ShaderNodeOutputMaterial');u=n.new('ShaderNodeUVMap');u.uv_map='PaletteUV';t=n.new('ShaderNodeTexImage');t.image=img;t.interpolation='Closest';l.new(u.outputs['UV'],t.inputs['Vector']);l.new(t.outputs['Color'],p.inputs['Base Color']);l.new(p.outputs[0],o.inputs['Surface']);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough;p.inputs['Coat Weight'].default_value=coat
 if emit:l.new(t.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=emit
 if name=='SEA_Gloss':
  p.inputs['Alpha'].default_value=.56;p.inputs['Transmission Weight'].default_value=.15;m.surface_render_method='DITHERED'
 roles.append(m)
class Geo:
 def __init__(self):self.v=[];self.f=[];self.c=[];self.r=[]
 def add(self,v,f,c='cloud',r=0):
  start=len(self.v);self.v.extend(v);self.f.extend([tuple(start+i for i in face) for face in f]);self.c.extend([c]*len(f));self.r.extend([r]*len(f))
 def box(self,loc,size,c='cloud',r=0,rot=None):
  v=[Vector((sx*size[0]/2,sy*size[1]/2,sz*size[2]/2)) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
  if rot:
   from mathutils import Euler
   m=Euler(rot).to_matrix();v=[m@p for p in v]
  self.add([tuple(p+Vector(loc)) for p in v],[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],c,r)
 def rod(self,a,b,rad,c='steel',r=1,n=8,rad2=None):
  a=Vector(a);b=Vector(b);q=(b-a).to_track_quat('Z','Y');rr=rad if rad2 is None else rad2
  v=[tuple((a if j==0 else b)+q@Vector((math.cos(i*math.tau/n)*(rad if j==0 else rr),math.sin(i*math.tau/n)*(rad if j==0 else rr),0))) for j in [0,1] for i in range(n)]
  f=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)];self.add(v,f,c,r)
 def leaf(self,loc,scale,c='leaf',r=0,angle=0):
  # rounded ellipsoid mesh; broad leaves, not grass needles
  n=8;nr=4;v=[]
  for j in range(nr+1):
   ph=.001+(math.pi-.002)*j/nr
   for i in range(n):
    th=i*math.tau/n;x=math.sin(ph)*math.cos(th)*scale[0];y=math.sin(ph)*math.sin(th)*scale[1]
    v.append((loc[0]+x*math.cos(angle)-y*math.sin(angle),loc[1]+x*math.sin(angle)+y*math.cos(angle),loc[2]+math.cos(ph)*scale[2]))
  self.add(v,[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(nr) for i in range(n)],c,r)
 def patch(self,loc,w,h,c='stone',plane='XY',r=0):
  n=7;vv=[]
  for i in range(n):
   a=i*math.tau/n;u=math.cos(a)*w/2*random.uniform(.75,1);v=math.sin(a)*h/2*random.uniform(.75,1)
   vv.append((loc[0]+u,loc[1]+v,loc[2]) if plane=='XY' else (loc[0]+u,loc[1],loc[2]+v))
  self.add(vv,[tuple(range(n))],c,r)
components={};specs={k:(n,cat,fam) for k,n,cat,fam in DEFS}
def part(k,g,bevel=.035):
 c=bpy.data.collections.new('ORF2_组件_'+k);src.children.link(c);c.instance_offset=(0,0,0)
 # bake origin to bottom center; geometry transforms remain identity
 pts=g.v;lo=Vector([min(p[i] for p in pts) for i in range(3)]);hi=Vector([max(p[i] for p in pts) for i in range(3)]);ctr=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));g.v=[tuple(Vector(p)-ctr) for p in pts]
 for rr in sorted(set(g.r)):
  fi=[i for i,x in enumerate(g.r) if x==rr];used=sorted({j for i in fi for j in g.f[i]});remap={j:i for i,j in enumerate(used)};me=bpy.data.meshes.new('ORF2_'+k+'_'+str(rr));me.from_pydata([g.v[i] for i in used],[],[[remap[j] for j in g.f[i]] for i in fi]);me.update();o=bpy.data.objects.new('ORF2_'+specs[k][0]+('_自发光' if rr==3 else '')+'_'+str(rr),me);c.objects.link(o);me.materials.append(roles[rr]);uv=me.uv_layers.new(name='PaletteUV')
  for face,idx in zip(me.polygons,fi):
   ce=cells[g.c[idx]];u=ce['column']/8;v=1-(ce['row']+1)/8;n=len(face.loop_indices)
   for j,li in enumerate(face.loop_indices):
    a=j*math.tau/n;uv.data[li].uv=(u+(.5+.20*math.cos(a))/8,v+(.5+.20*math.sin(a))/8)
  uv.active_render=True;me.uv_layers.active=uv
  if bevel and rr!=3:
   mod=o.modifiers.new('实体柔边_三段','BEVEL');mod.width=bevel;mod.segments=3
  if k in ['cabbage','seedling','tomato','plant','grass','vine']:
   for p in me.polygons:p.use_smooth=True
  o['component_id']='SEA-SCENE-ORF2-'+k.upper()
 components[k]={'col':c,'size':list(hi-lo),'offset':list(ctr),'meshes':len(c.objects)}
def inst(k,p,rz=0,tilt=(0,0),scale=(1,1,1)):
 c=components[k]['col'];o=bpy.data.objects.new('ORF2_实例_'+k,None);o.instance_type='COLLECTION';o.instance_collection=c;o.location=p;o.rotation_euler=(tilt[0],tilt[1],rz);o.scale=scale;groups[specs[k][1]].objects.link(o);o['component_id']='SEA-SCENE-ORF2-'+k.upper();return o
# large tower, front -Y. Dense recessed blue window bands and balcony piers.
g=Geo();g.box((0,0,29.8),(45.6,29.6,59.6),'lightgray');part('shell',g,.12)
g=Geo();g.box((0,0,.15),(48,32,.3),'cloud');part('slab',g,.09)
g=Geo();g.box((0,0,29.9),(1.8,1.2,59.8),'cloud');
for z in [5,16,29,43,55]:g.patch((0,-.605,z),1.3,2,'stone','XZ');g.rod((-.4,-.62,z),(.2,-.62,z+1.8),.018,'slate',0)
part('pier',g,.095)
g=Geo();g.box((0,0,1.45),(5.8,.2,2.9),'gray');g.box((0,-.12,1.45),(5.3,.06,2.4),'deepblue',0)
for x in [-2.2,0,2.2]:g.box((x,-.18,1.45),(.09,.10,2.5),'silver',1)
g.box((0,-.2,.15),(6.0,.45,.3),'cloud');part('window',g,.025)
g=Geo();g.box((0,0,.15),(9.2,2.0,.3),'cloud');g.box((0,-.85,.62),(8.8,.2,.95),'lightgray');
for x in [-4.3,0,4.3]:g.rod((x,-.86,.25),(x+.12,-.92,1.25),.045,'wood_dark')
g.rod((-4.3,-.92,1.25),(4.35,-.9,1.28),.045,'steel');g.patch((1.5,-.961,.68),1.2,.4,'stone','XZ');part('balcony',g,.045)
g=Geo()
for i in range(8):g.patch((random.uniform(-1.8,1.8),0,random.uniform(.4,4.6)),random.uniform(.4,1.2),random.uniform(.2,.75),random.choice(['stone','gray','cloud']),'XZ')
for i in range(4):
 x=random.uniform(-1.5,1.5);z=random.uniform(1,3);g.rod((x,-.015,z),(x+.2,-.015,z-.7),.025,'wood_dark',0);g.rod((x+.2,-.02,z-.7),(x+.13,-.02,z-1.0),.015,'ochre',0)
g.rod((-.8,-.03,1.2),(-.5,-.03,1.8),.014,'slate',0);g.rod((-.5,-.03,1.8),(.1,-.03,2),.012,'slate',0);part('weather',g,0)
g=Geo();g.box((0,0,.1),(48,32,.2),'stone');part('roof',g,.09)
g=Geo();g.box((0,0,.55),(3.9,1.2,1.1),'cloud');g.box((0,0,1.11),(3.85,1.15,.04),'sage');
for i in range(7):g.patch((random.uniform(-1.7,1.7),-.606,random.uniform(.2,1)),random.uniform(.2,.6),random.uniform(.2,.5),'forest','XZ')
g.patch((1.1,-.612,.65),.8,.5,'stone','XZ');part('parapet',g,.10)
g=Geo();g.rod((-1.9,0,1.0),(1.9,0,.98),.045,'wood_dark');
for x in [-1.8,0,1.8]:g.rod((x,0,0),(x+.05,-.02,1.02),.04,'steel')
part('rail',g,.008)
g=Geo();g.patch((0,0,.08),4,3.2,'moss');
for i in range(5):g.leaf((random.uniform(-1.2,1.2),random.uniform(-.8,.8),.10),(random.uniform(.35,.9),random.uniform(.3,.7),.10),random.choice(['moss','sage','moss_light']))
part('grass',g,0)
g=Geo()
for i in range(7):
 a=i*2.4;g.leaf((math.cos(a)*.10,math.sin(a)*.1,.18),(.055,.08,random.uniform(.12,.22)),random.choice(['leaf_dark','moss','leaf_mid']),angle=a)
part('tuft',g,0)
g=Geo()
for j in range(3):
 x=j*.22;g.rod((x,0,0),(x+.14,0,1.9-j*.3),.025,'forest',0)
 for z in [.3,.7,1.1,1.4]:g.leaf((x+.12,-.04,z),(.19,.07,.15),'leaf_dark')
part('vine',g,0)
# Raised left rear utility block, small top room, ladder and clothes.
g=Geo();g.box((0,0,2.7),(10,9,5.4),'lightgray');g.box((0,0,5.4),(10.4,9.4,.2),'cloud');g.box((0,-4.52,1.6),(1.8,.08,3.0),'deepblue')
for i in range(7):g.patch((random.uniform(-4,4),-4.57,random.uniform(.3,5)),1.4,.9,random.choice(['stone','sage']),'XZ')
part('platform',g,.095)
g=Geo();g.box((0,0,1.4),(3.6,3.0,2.8),'cloud');g.box((0,0,2.86),(3.9,3.3,.2),'cream');g.box((-.85,-1.52,1.25),(1.0,.08,2.5),'wood_mid');g.box((.85,-1.54,1.65),(1.1,.08,.9),'deepblue');part('room',g,.065)
g=Geo()
for x in [-.45,.45]:g.rod((x,0,0),(x,0,5.8),.055,'wood_dark')
for i in range(14):g.rod((-.45,-.04,.25+i*.4),(.45,-.04,.25+i*.4),.04,'steel')
part('ladder',g,.008)
g=Geo()
for x in [-1.8,1.8]:g.rod((x,0,0),(x,0,2.6),.05,'wood_dark')
g.rod((-1.8,0,2.5),(1.8,0,2.4),.02,'steel');g.box((-.6,-.02,1.8),(.8,.05,1.1),'red');g.box((.7,-.02,1.95),(.6,.05,.65),'cream');part('line',g,.02)
# tool shed with corrugated single slope roof matches reference.
g=Geo();g.box((0,0,1.45),(4,3,2.9),'sage_gray');g.box((.7,-1.55,1.3),(1.1,.12,2.6),'wood_dark');g.box((-.9,-1.56,1.9),(1.0,.10,.9),'deepblue')
for x in [-1.7,-1.35,-1.0,-.65]:g.box((x,-1.57,1.05),(.1,.06,1.6),'wood_mid')
for i in range(12):
 x=-2.1+i*.38;g.box((x,0,3.08),(.39,3.45,.12),'red_dark' if i%3 else 'coral',1,rot=(.12,0,0));g.rod((x,-1.72,2.88),(x,1.72,3.28),.028,'wood_dark')
part('shed',g,.045)
g=Geo();g.box((0,0,1.0),(3,2,1.7),'wood_mid');g.box((0,-1.02,.8),(.65,.08,1.0),'darkwood')
for x in [-.8,.8]:g.box((x,0,2.02),(1.8,2.35,.14),'teal',1,rot=(0,.35 if x>0 else -.35,0))
part('coop',g,.04)
g=Geo()
for x in [-1.5,-.7,.1,.9,1.5]:g.rod((x,0,0),(x+.15,0,.95),.045,'wood_mid',0)
g.rod((-1.5,0,.65),(.7,0,.62),.04,'wood_dark',0);g.rod((.9,0,.66),(1.6,0,.72),.04,'wood_dark',0);part('fence',g,.01)
# greenhouse 6x4 module; translucent roof panes at correct pitched height, missing pane.
g=Geo();g.box((0,0,.12),(6,4,.24),'wood_mid')
for y in [-2,0,2]:
 for x in [-3,3]:g.rod((x,y,.15),(x,y,2.1),.045,'silver');g.rod((x,y,2.1),(0,y,3.6),.045,'seafoam')
g.rod((0,-2,3.6),(0,2,3.6),.05,'cloud')
for x in [-3,3]:g.rod((x,-2,2.1),(x,2,2.1),.045,'silver')
for side in [-1,1]:
 for y in [-1,1]:
  if not(side==-1 and y==1):g.box((side*1.5,y,2.85),(3.31,1.92,.025),'seafoam',2,rot=(0,side*math.atan2(1.5,3),0))
  g.box((side*2.985,y,1.15),(.025,1.9,1.85),'ice',2)
for x in [-2,-1,1,2]:g.box((x,-2.01,1),( .8,.03,1.7),'palegreen',2)
g.box((0,-2.03,1.15),(1.0,.08,2.1),'wood_mid');g.box((0,-2.08,1.55),(.7,.035,1.0),'palegreen',2)
g.rod((-1.8,-2.05,1.2),(-1.5,-2.05,1.6),.012,'cloud',0);part('greenhouse',g,.015)
g=Geo()
for x,y in [(-1.1,-1.1),(1.1,-1.1),(-1.1,1.1),(1.1,1.1)]:g.rod((x*1.25,y*1.25,0),(x,y,3.2),.11,'wood_dark',0)
for y in [-1.1,1.1]:g.rod((-1.3,y,.2),(1.1,y,3.2),.055,'wood_mid',0);g.rod((1.3,y,.2),(-1.1,y,3.2),.055,'wood_mid',0)
g.rod((0,0,3.2),(0,0,5.4),1.5,'silver',1,24,1.35);g.rod((0,0,3.18),(0,0,3.33),1.56,'wood_dark',1,24);g.rod((0,0,5.4),(0,0,5.55),1.4,'wood_dark',1,24);g.rod((0,0,5.55),(0,0,6.0),1.48,'gray',1,24,.04)
for i in range(14):
 a=-math.pi/2+i*.27;x=math.cos(a)*1.5;y=math.sin(a)*1.5;g.box((x,y,3.6+random.uniform(-.1,.2)),(.16,.03,random.uniform(.3,.75)),'wood_dark',0,rot=(0,0,a-math.pi/2))
part('tank',g,.025)
g=Geo();g.rod((0,0,0),(.15,0,3.4),.06,'wood_dark');g.rod((.15,-.13,3.4),(.15,.13,3.4),.13,'ochre')
for i in range(8):
 a=i*math.tau/8;g.box((.15+math.sin(a)*.52,-.15,3.4+math.cos(a)*.52),(.15,.07,.62),'cream' if i%2 else 'red',1,rot=(0,a+.05*(i%3),0))
part('wind',g,.015)
g=Geo()
for x in [-.8,.8]:g.rod((x,-.35,0),(x,-.35,.45),.04,'wood_dark');g.rod((x,.35,0),(x,.35,1.0),.04,'wood_dark')
g.box((0,0,.72),(2.1,1.1,.10),'silver',1,rot=(.42,0,0));g.box((0,-.03,.79),(1.94,.94,.045),'deepblue',0,rot=(.42,0,0))
for x in [-.72,-.36,0,.36,.72]:g.box((x,-.05,.82),(.018,.88,.02),'silver',1,rot=(.42,0,0))
part('solar',g,.015)
# Farm geometries. Plants remain independent instances from soil/wood.
g=Geo();g.box((0,0,.16),(6.0,3.8,.32),'bark')
for y in [-2,2]:g.box((0,y,.25),(6.3,.18,.5),'wood_mid',rot=(0,0,.015 if y>0 else -.012))
for x in [-3.1,3.1]:g.box((x,0,.25),(.18,4,.5),'wood_light')
part('bed',g,.04)
g=Geo();g.box((0,0,.08),(16,8,.16),'bark')
for x in [-7,-5,-3,-1,1,3,5,7]:g.box((x,0,.19),(1.35,7.8,.25),'wood_dark')
for x in [-8,8]:g.box((x,0,.2),(.16,8.2,.3),'wood_mid')
part('field',g,.06)
g=Geo()
for i in range(6):
 a=i*math.tau/6;g.leaf((math.cos(a)*.15,math.sin(a)*.15,.20),(.22,.32,.16),'leaf_mid' if i%2 else 'moss',angle=a)
g.leaf((0,0,.28),(.22,.22,.18),'leaf_light');part('cabbage',g,0)
g=Geo();g.rod((0,0,0),(0,0,.35),.025,'leaf_dark',0);g.leaf((-.12,0,.25),(.18,.1,.06),'leaf');g.leaf((.12,0,.32),(.18,.1,.06),'leaf_light');part('seedling',g,0)
g=Geo();g.rod((0,0,0),(0,0,1.55),.035,'wood_mid',0)
for i in range(5):
 a=i*2.4;g.leaf((math.cos(a)*.17,math.sin(a)*.17,.3+i*.22),(.25,.20,.07),'leaf_dark',angle=a)
for z in [.55,.85,1.1]:g.leaf((.20,-.12,z),(.10,.10,.11),'red')
part('tomato',g,0)
g=Geo();g.box((0,0,.07),(1.0,.65,.14),'cloud',rot=(0,.01,.12));part('stone',g,.06)
g=Geo();g.box((0,0,.08),(1.6,.65,.16),'wood_light');part('plank',g,.04)
g=Geo()
for y in [-.8,.8]:
 for z in [.2,.5,.8,1.1]:g.box((0,y,z),(2.1,.12,.22),'wood_mid',rot=(.04,0,.03))
for x in [-1,1]:g.box((x,0,.65),(.12,1.6,1.3),'wood_dark')
g.box((0,0,.65),(1.9,1.4,1.0),'bark');part('compost',g,.025)
g=Geo();g.rod((0,0,0),(0,0,.6),.28,'coral',0,16,.4);g.rod((0,0,.58),(0,0,.7),.43,'wood_dark',0,16);g.rod((0,0,.69),(0,0,.71),.34,'bark',0,16);part('pot',g,.025)
g=Geo()
for i in range(8):
 a=i*2.4;g.leaf((math.cos(a)*.16,math.sin(a)*.16,.4),(.14,.38,.09),'leaf_mid' if i%2 else 'leaf',angle=a)
part('plant',g,0)
g=Geo();g.rod((0,0,.1),(0,0,2),.08,'wood_dark');g.rod((0,0,2),(1,0,2.2),.08,'wood_dark');g.rod((1,0,2.2),(3,0,2.15),.075,'steel');part('pipe',g,.012)
g=Geo();g.rod((0,0,.7),(0,0,.9),.9,'cloud',0,24);g.rod((0,0,0),(0,0,.8),.12,'wood_dark',0);part('table',g,.03)
g=Geo();g.box((0,0,.45),(.65,.65,.12),'wood_light');g.box((0,.27,.85),(.65,.12,.75),'wood_mid')
for x in [-.25,.25]:
 for y in [-.25,.25]:g.rod((x,y,0),(x,y,.45),.04,'wood_dark',0)
part('chair',g,.025)
g=Geo();g.box((0,0,.4),(.9,.8,.8),'wood_mid')
for x in [-.3,.3]:g.box((x,-.42,.4),(.1,.04,.8),'wood_light')
part('crate',g,.035)
g=Geo();g.rod((0,0,0),(0,0,.9),.4,'wood_mid',0,16)
for z in [.18,.7]:g.rod((0,0,z),(0,0,z+.07),.415,'steel',1,16)
part('barrel',g,.02)
g=Geo();g.rod((0,0,0),(0,0,2.4),.055,'steel');g.rod((0,0,2.4),(.6,0,2.5),.05,'steel');g.rod((.6,0,2.3),(.6,0,2.5),.18,'cloud',1,12,.1);g.leaf((.6,0,2.25),(.1,.1,.08),'butter',3);part('lamp',g,.015)
# Assembly: explicit instances only.
inst('shell',(0,0,0))
for i in range(12):inst('slab',(0,0,i*5))
inst('roof',(0,0,59.8))
for x in [-22.8,-7.6,7.6,22.8]:inst('pier',(x,-15.8,0))
for x in [-22.8,22.8]:
 for y in [-10,0,10]:inst('pier',(x,y,0),math.pi/2)
for i in range(12):
 z=i*5
 for x in [-15.2,0,15.2]:
  inst('balcony',(x,-16.0,z+.6))
  for dx in [-3.2,3.2]:inst('window',(x+dx,-14.85,z+1.3))
 for side in [-1,1]:
  for y in [-10,0,10]:inst('window',(side*22.9,y,z+1.3),-side*math.pi/2)
 for x in [-22.6,-7.6,7.6,22.6]:inst('weather',(x,-16.48,z+.2),scale=(.65,1,.85))
for y in [-15.4,15.4]:
 for x in [-22,-18,-14,-10,-6,-2,2,6,10,14,18,22]:inst('parapet',(x,y,60));inst('rail',(x,y,61.1))
for x in [-23.4,23.4]:
 for y in [-12,-8,-4,0,4,8,12]:inst('parapet',(x,y,60),math.pi/2);inst('rail',(x,y,61.1),math.pi/2)
# broad continuous grass coverage, not separate pill blobs
for x in range(-20,23,3):
 for y in range(-12,15,3):inst('grass',(x+random.uniform(-.2,.2),y+random.uniform(-.2,.2),60),random.uniform(-.3,.3))
for i in range(160):inst('tuft',(random.uniform(-22,22),random.uniform(-14,14),60.08),random.uniform(0,math.tau))
for i in range(48):
 x=random.choice([-23,-8,8,23]);z=random.choice([8,18,28,38,48,58]);inst('vine',(x,-16.5,z),scale=(1,1,random.uniform(.6,1.4)))
# reference back-left block and rooftop living details
inst('platform',(-16,8,60));inst('room',(-15,9,65.5));inst('ladder',(-18,3.35,60));inst('line',(-19,8,65.6))
for x in [-19,-15,-11]:inst('rail',(x,3.4,65.6));inst('rail',(x,12.5,65.6))
inst('solar',(-12,6.0,65.7));inst('solar',(-12,8,65.7),.06);inst('pot',(-19,10,65.6));inst('plant',(-19,10,66.3))
inst('shed',(-7,9,60),tilt=(0,.02));inst('coop',(-17,1,60),-.14,tilt=(math.radians(-4),0))
for x in [-19,-16,-13]:inst('fence',(x,-7.5,60))
for y in [-6,-3,0]:inst('fence',(-21,y,60),math.pi/2)
# greenhouse elongated reference shape assembled from two 6x4 components
inst('greenhouse',(7,5.5,60),tilt=(0,math.radians(3)));inst('greenhouse',(7,9.5,60),math.pi,tilt=(0,math.radians(3)))
inst('tank',(18,10,60),tilt=(0,math.radians(-4)));inst('wind',(12,10,60),tilt=(math.radians(2),0))
for i,y in enumerate([-.3,2.0,4.3]):
 for x in [16.4,18.7]:inst('solar',(x,y,60),.02,tilt=(0,-.04 if i==1 else 0))
# main field front-right and pair of nursery beds middle-left
inst('field',(12,-8.7,60.08));
for j,y in enumerate([-9,-3.5]):
 inst('bed',(-4.3,y,60.10),-.02 if j else .015)
 for ix in range(6):
  for iy in range(4):inst('cabbage' if j==0 else 'seedling',(-6.8+ix*.95,y-1.4+iy*.9,60.45),random.uniform(0,math.tau))
for ix,x in enumerate([5,7,9,11,13,15,17,19]):
 for iy in range(8):inst('tomato' if ix==0 else 'seedling' if ix%3==0 else 'cabbage',(x,-12+iy*.93,60.43),random.uniform(-.2,.2))
inst('bed',(.2,6.5,60.1),math.pi/2,scale=(.9,.8,1))
for x in [-.8,.2,1.2]:
 for y in [4,5,6,7,8]:inst('tomato',(x,y,60.45))
for x in [5.4,8.2]:
 for y in [4,5,6,7,8,9,10]:inst('seedling',(x,y,60.35))
# irregular stone route network and plank boundaries
for i in range(17):inst('stone',(.2+random.uniform(-.18,.18),-13.5+i*1.55,60.12),random.uniform(-.2,.2))
for i in range(14):inst('stone',(-20+i*1.5,-13.6,60.1),random.uniform(-.2,.2))
for i in range(24):inst('plank',(-20+i*1.7,0,60.1),random.uniform(-.08,.08))
for y in [-13,-10,-7,-4,-1]:inst('stone',(-9,y,60.1),.04)
for i in range(9):inst('stone',(-17+i*1.25,4+math.sin(i*.6),60.1),random.uniform(-.3,.3))
inst('compost',(-9,11,60));inst('pipe',(-10,5,60),.1);inst('pipe',(3,-1,60),-math.pi/2)
inst('table',(-4,8.5,60));inst('chair',(-5.2,8,60),.7);inst('chair',(-2.8,9,60),2.7)
for x,y in [(-20,-11),(-10,2),(-11,7),(-4,11),(12,13),(21,-12),(21,7)]:inst('pot',(x,y,60));inst('plant',(x,y,60.7),random.uniform(0,math.tau))
for k,x,y in [('barrel',-9,7),('crate',-10,7),('crate',-12,2),('barrel',21,12),('crate',-9,8)]:inst(k,(x,y,60))
for x in [-22,22]:
 for y in [-14,14]:inst('lamp',(x,y,60),math.pi if x>0 else 0)
for i in [2,5,8,10]:inst('line',(-15,-17,i*5+1));inst('pot',(15,-17,i*5+1));inst('plant',(15,-17,i*5+1.7))
# Hide authoring library via layer exclusion, not collection.hide_render (instances need data).
bpy.context.view_layer.update()
def exclude(layer):
 if layer.collection==src:layer.exclude=True
 for c in layer.children:exclude(c)
exclude(bpy.context.view_layer.layer_collection)
# Neutral illumination and transparent output; no background mesh.
world=bpy.data.worlds.new('ORF2_柔和天光');world.use_nodes=True;bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.70,.78,.87,1);bg.inputs[1].default_value=.8;s.world=world
ld=bpy.data.lights.new('ORF2_柔和日光','SUN');ld.energy=2.1;ld.angle=math.radians(18);lo=bpy.data.objects.new(ld.name,ld);qa.objects.link(lo);lo.rotation_euler=(math.radians(22),math.radians(-28),math.radians(-25))
ld=bpy.data.lights.new('ORF2_正面补光','AREA');ld.energy=4200;ld.shape='DISK';ld.size=38;lo=bpy.data.objects.new(ld.name,ld);qa.objects.link(lo);lo.location=(0,-35,72);lo.rotation_euler=(Vector((0,0,40))-lo.location).to_track_quat('-Z','Y').to_euler()
def camera(name,pos,target,scale):
 data=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,data);qa.objects.link(o);o.location=pos;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=scale;return o
s.camera=camera('ORF2_参考图屋顶主镜头',(10,-68,105),(0,0,57),58)
camera('ORF2_全楼完整镜头',(73,-102,85),(0,0,33),94)
camera('ORF2_垂直俯视',(0,0,145),(0,0,60),56)
camera('ORF2_温室水塔近景',(35,-34,92),(10,5,62),33)
s.render.engine='CYCLES';s.cycles.samples=24;s.cycles.use_denoising=True;s.render.resolution_x=1500;s.render.resolution_y=1125;s.render.resolution_percentage=100;s.render.film_transparent=True;s.render.image_settings.file_format='PNG';s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast'
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL';area.spaces.active.overlay.show_overlays=False
s['reference_camera_contract']='roof view crop intentionally shows upper facade like supplied reference; full tower camera saved separately'
s['authoring_status']='source_candidate_requires_independent_validation';s['component_plan_path']=str(D/'component_plan.json')
# Preserve transforms in manifest (not Godot runtime ownership).
instances=[]
for o in s.objects:
 if o.instance_type=='COLLECTION':instances.append({'name':o.name,'component_id':o['component_id'],'position_m':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale)})
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.instances','coordinate_mapping':'(x,y,z)->(x,z,-y)','instances':instances},ensure_ascii=False,indent=2),encoding='utf-8')
cat=[]
for k,entry in components.items():cat.append({'key':k,'asset_id':'SEA-SCENE-ORF2-'+k.upper(),'name':specs[k][0],'category':specs[k][1],'component_family':specs[k][2],'collection':entry['col'].name,'bounds_size_m':entry['size'],'front_axis':'-Y','origin':'bottom_center','instance_count':sum(i['component_id']=='SEA-SCENE-ORF2-'+k.upper() for i in instances),'component_source':str((D/'component_packages'/k/(k+'.blend')).relative_to(R)),'collision_owner':'future_Godot_wrapper_pending'})
(D/'component_catalog.json').write_text(json.dumps({'components':cat},ensure_ascii=False,indent=2),encoding='utf-8')
# Use unique new file, never overwrite old source.
path=D/'ocean_rooftop_farm_v002.blend';bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
print(json.dumps({'scene':s.name,'path':str(path),'components':len(components),'instances':len(instances),'roof_top':60,'materials':[m.name for m in roles]},ensure_ascii=False))

"""Build the scoped interior via the active Blender MCP GUI; old source is linked reference only."""
import bpy,json,math,os,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/gift_kiosk_interior/v001';OLD=R/'art_source/scenes/gift_kiosk/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/interior/v001';PLAN=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
if not (W/'session_before.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'session_before.blend'),copy=True)
assert not (D/'gift_kiosk_interior.blend').exists(),'Do not overwrite saved source'
sc=bpy.data.scenes.new('海上商亭室内_v001');bpy.context.window.scene=sc;sc.unit_settings.system='METRIC'
PAL=R/PLAN['palette'];COLS={x['name']:x for x in json.loads(PAL.with_suffix('.json').read_text(encoding='utf-8'))['cells']};TAU=math.tau;PI=math.pi
top={}
for k,n in [('structure','01_室内地砖'),('furnishing','02_固定设施与陈设'),('plant','03_独立植物'),('display','90_展示支持')]:
 c=bpy.data.collections.new('GKI_'+n);sc.collection.children.link(c);top[k]=c
image=bpy.data.images.load(str(PAL),check_existing=True);roles={}
for name in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission']:
 mat=bpy.data.materials.new(name);mat.use_nodes=True;mat['semantic_role']=name;roles[name]=mat
 bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Roughness'].default_value={'SEA_Matte':.5,'SEA_Metal':.28,'SEA_Gloss':.13,'SEA_Emission':.3}[name];bs.inputs['Metallic'].default_value=.12 if name=='SEA_Metal' else 0
 tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest';tex.extension='EXTEND';uv=mat.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';mat.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector']);mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
 if name=='SEA_Emission':mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=.65
font=bpy.data.fonts.load('C:/Windows/Fonts/arialbd.ttf');components={};catalog=[];layout=[];current=None
# Reuse proven mesh/UV helpers only; do not execute the exterior builder.
code=(R/'tools/blender/gift_kiosk/build.py').read_text(encoding='utf-8');code=code[code.index('def finish('):code.index('\ndef deck():')]
exec(code.replace('gift_kiosk/v001','gift_kiosk_interior/v001'))

for k,c in [('tile_cream','cream'),('tile_blue','sky'),('tile_honey','honey')]:part(k,lambda k=k,c=c:box('圆边珐琅地砖_'+c,(0,0,.01),(.93,.93,.02),c,b=.006))
def counter():
 # Main bar and attached left return: one fixed L-shaped cabinet.
 box('圆角柜台主身',(0,0,.57),(3.6,1.05,1.06),'teal',b=.11)
 box('左侧短返台',(-1.24,-.70,.57),(1.12,1.0,1.06),'teal',b=.10)
 box('奶油踢脚',(0,0,.08),(3.46,1.00,.16),'cream',b=.055)
 box('返台奶油踢脚',(-1.24,-.70,.08),(1.02,.95,.16),'cream',b=.05)
 box('饱满蜂蜜色木台面',(0,-.24,1.15),(3.84,1.65,.20),'honey',b=.09)
 # Faceted inset panels and soft brass handles, customer side -Y.
 for x in [-1.10,0,1.10]:
  box('奶油柜门镶板',(x,-.54,.60),(.93,.055,.75),'cream',b=.026)
  box('海蓝柜门芯',(x,-.575,.61),(.79,.035,.56),'aqua',b=.016)
  box('金色圆把手',(x,-.612,.82),(.24,.08,.06),'gold','SEA_Metal',.025)
 box('台前金色腰线',(0,-.59,1.03),(3.32,.045,.065),'gold','SEA_Metal',.02)
part('checkout_counter',counter)
def register():
 box('奶油抽屉底座',(0,0,.13),(.72,.58,.26),'cream',b=.08)
 box('珊瑚收银机身',(0,.055,.34),(.60,.43,.39),'coral',b=.08)
 box('抽屉前脸',(0,-.30,.14),(.59,.045,.12),'honey',b=.02)
 box('海蓝显示屏',(0,-.175,.48),(.38,.04,.16),'deepblue','SEA_Metal',.018)
 box('柔和屏幕读数',(0,-.20,.49),(.27,.015,.052),'ice','SEA_Emission',.006)
 for x in [-.16,0,.16]:
  for y in [-.13,-.03]:box('圆按键',(x,y,.31),(.11,.07,.035),'white',b=.015)
 cyl('收据卷',(0,.16,.55),.11,.26,'white',v=20,b=.03)
 box('纸张出口',(0,.12,.67),(.21,.10,.025),'cream',b=.008)
part('cash_register',register)
def display():
 cyl('椭圆陈列桌底盘',(0,0,.10),.72,.20,'cream',v=40,b=.07)
 cyl('木色饱满桌腿',(0,0,.50),.37,.80,'wood',v=32,b=.07)
 slab('椭圆圆角陈列台',2.15,1.5,.66,.85,.17,'honey',bevel=.065)
 slab('奶油台面镶边',1.94,1.29,.54,1.018,.025,'cream',bevel=.009)
part('display_table',display)
def stool():
 for x in [-.20,.20]:
  for y in [-.20,.20]:cyl('小凳粗圆脚',(x,y,.27),.07,.54,'wood',v=16,b=.025)
 cyl('木坐凳圆边',(0,0,.55),.39,.12,'honey',v=32,b=.045)
 cyl('软蓝圆坐垫',(0,0,.63),.35,.09,'aqua',v=32,b=.037)
part('stool',stool)
def poster():
 box('厚圆角木画框',(0,0,.74),(1.16,.13,1.48),'honey',b=.06)
 box('奶油画布',(0,-.078,.74),(1.00,.035,1.30),'cream',b=.015)
 box('海蓝色块',(0,-.103,.47),(.88,.022,.53),'aqua',b=.01)
 sphere('画中暖太阳',(.25,-.125,1.12),(.15,.016,.15),'yellow',v=20,rr=10)
 box('画中小屋',(0,-.128,.70),(.40,.025,.35),'coral',b=.012)
 box('画中窗户',(0,-.148,.73),(.13,.018,.13),'ice',b=.01)
 for x in [-.28,.0,.28]:box('抽象海浪',(x,-.137,.40),(.20,.018,.035),'ice',b=.009)
part('wall_poster',poster)
def clock():
 # Z-up source round face lies in XZ and faces -Y.
 o=cyl('圆钟木框',(0,0,.46),.46,.15,'honey',v=40,b=.05);o.data.transform(Matrix.Translation((0,0,.46))@Matrix.Rotation(PI/2,4,'X')@Matrix.Translation((0,0,-.46)))
 o=cyl('奶油钟面',(0,-.09,.46),.39,.035,'cream',v=40,b=.01);o.data.transform(Matrix.Translation((0,-.09,.46))@Matrix.Rotation(PI/2,4,'X')@Matrix.Translation((0,.09,-.46)))
 for a in range(12):
  ang=a*TAU/12;sphere('钟点',(.31*math.sin(ang),-.128,.46+.31*math.cos(ang)),(.025,.016,.025),'teal',v=10,rr=6)
 rod('时针',(0,-.15,.46),(-.15,-.15,.58),.022,'deepblue');rod('分针',(0,-.15,.46),(.07,-.15,.70),.017,'deepblue')
 sphere('钟心',(0,-.16,.46),(.04,.022,.04),'coral',v=12,rr=8)
part('wall_clock',clock)
def sconce():
 box('壁灯贴墙座',(0,.12,.28),(.25,.10,.50),'teal','SEA_Metal',.04)
 tube('圆弯壁灯臂',[(0,.04,.34),(0,-.26,.34),(0,-.32,.50)],.055,'gold','SEA_Metal')
 cyl('灯罩圆边',(0,-.32,.54),.26,.09,'honey',v=24,b=.033)
 sphere('奶油圆灯泡',(0,-.32,.64),(.19,.19,.19),'butter','SEA_Emission',v=20,rr=12)
part('wall_sconce',sconce)
def cubby():
 box('包装柜奶油背板',(0,.24,.91),(1.56,.12,1.82),'cream',b=.05)
 for x in [-.74,.0,.74]:box('海蓝柜立板',(x,0,.92),(.10,.62,1.84),'aqua',b=.04)
 for z in [.09,.65,1.23,1.80]:box('蜂蜜色柜隔板',(0,0,z),(1.56,.68,.12),'honey',b=.045)
part('cubby',cubby)

# Link protected original collections for context and repeated stocked goods.
oldcat=json.loads((OLD/'catalog.json').read_text(encoding='utf-8'))['components'];oldby={e['key']:e for e in oldcat}
with bpy.data.libraries.load(str(OLD/'gift_kiosk.blend'),link=True) as (src,dst):dst.collections=[e['collection'] for e in oldcat]
linked={c['asset_id']:c for c in dst.collections}
ref=bpy.data.collections.new('GKI_91_原屋参照_不导出');sc.collection.children.link(ref)
for row in json.loads((OLD/'component_instances.json').read_text(encoding='utf-8'))['instances']:
 o=bpy.data.objects.new('REF_'+row['name'],None);o.instance_type='COLLECTION';o.instance_collection=linked[row['asset_id']];o.location=row['position'];o.rotation_euler=row['rotation_euler_xyz'];o.scale=row['scale'];ref.objects.link(o)
 if row['key'].startswith(('roof','fascia','awning','sign','beacon','spotlight','lantern')) and row['name']!='roof_pipe_003':o.hide_render=True;o.hide_viewport=True

# Tiled inset, a quiet cream perimeter and blue checks, honey accents on the aisle.
for j in range(10):
 for i in range(10):
  k='tile_cream' if i in [0,9] or j in [0,9] else ('tile_blue' if (i+j)%2 else 'tile_cream')
  if i in [4,5] and j in [1,8]:k='tile_honey'
  put(k,((i-4.5)*.94,(j-4.5)*.94,.295))
for x in [-.47,.47]:put('tile_honey',(x,-5.17,.295))
put('checkout_counter',(-1.55,2.65,.315))
put('cash_register',(-2.15,2.70,1.57))
put('display_table',(-2.25,-1.45,.315))
put('cubby',(2.50,2.40,.315))
put('stool',(2.60,1.1,.315))
put('wall_clock',(0,5.0,3.25))
for p,a in [((-.2,5.03,1.85),0),((-5.03,-1.25,1.9),PI/2)]:put('wall_poster',p,a)
for x in [-3.9,3.9]:put('wall_sconce',(x,4.98,3.3))

reused=[]
def decor(key,p,a=0,s=(1,1,1)):
 e=oldby[key];pv=Vector(e['design_pivot']);o=bpy.data.objects.new('interior_'+key+'_'+str(len(reused)+1).zfill(3),None);o.instance_type='COLLECTION';o.instance_collection=linked[e['asset_id']];o.rotation_euler=(0,0,a);o.scale=s;o.location=Vector(p)+o.rotation_euler.to_matrix()@Vector(tuple(pv[i]*s[i] for i in range(3)));top['plant' if key=='foliage' else 'furnishing'].objects.link(o);reused.append({'name':o.name,'key':key,'asset_id':e['asset_id'],'position':list(o.location),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(o.scale),'existing_component':True})
for x,y,s in [(-2.8,-1.30,.68),(-2.20,-1.5,.82),(-1.65,-1.50,.61)]:decor('gift',(x,y,1.365),s=(s,s,s))
for x,y in [(-2.60,-1.05),(-2.10,-.98)]:decor('bottle',(x,y,1.365),s=(.52,.52,.55))
for z in [.50,1.07,1.65]:
 for x in [2.15,2.70]:decor('gift',(x,2.35,z),s=(.52,.52,.52))
for x,y in [(-3.1,-3.35),(3.35,3.5)]:
 decor('pot',(x,y,.315),s=(.55,.55,.55));decor('foliage',(x,y,.315+.55*.62),s=(.55,.55,.55))
for x in [-.85,-.45]:decor('card',(x,2.55,1.58),s=(.65,.65,.65))

# Identical fixed cameras for before/after and source/optimized comparisons.
current=top['display'];sc.world=bpy.data.worlds.new('GKI_柔和环境');sc.world.use_nodes=True;bg=sc.world.node_tree.nodes.get('Background');bg.inputs[0].default_value=(.68,.82,.90,1);bg.inputs[1].default_value=.55
for n,p,energy,size in [('主柔光',(-10,-14,22),2200,10),('右柔光',(13,3,18),1500,10)]:
 data=bpy.data.lights.new(n,'AREA');data.energy=energy;data.shape='DISK';data.size=size;o=bpy.data.objects.new(n,data);current.objects.link(o);o.location=p;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
data=bpy.data.lights.new('阳光','SUN');data.energy=1.3;data.angle=.25;o=bpy.data.objects.new('阳光',data);current.objects.link(o);o.rotation_euler=(.4,-.5,-.4)
data=bpy.data.cameras.new('GKI_室内参考相机');cam=bpy.data.objects.new('GKI_室内参考相机',data);current.objects.link(cam);sc.camera=cam;cam.location=(14,-18,21);cam.rotation_euler=(Vector((0,0,1.0))-cam.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=18.5
sc.render.engine='CYCLES';sc.cycles.samples=24;sc.cycles.use_denoising=True
try:
 pref=bpy.context.preferences.addons['cycles'].preferences;pref.compute_device_type='OPTIX';pref.get_devices()
 for dev in pref.devices:dev.use=dev.type!='CPU'
 sc.cycles.device='GPU'
except Exception:pass
sc.render.resolution_x=1400;sc.render.resolution_y=1200;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG';sc.view_settings.view_transform='Standard';sc.view_settings.look='Medium High Contrast';sc.view_settings.exposure=-.6
for e in catalog:
 e['instances']=sum(x['key']==e['key'] for x in layout);e['palette']=PLAN['palette'];e['triangles']=sum(len(o.data.loop_triangles) if o.data.loop_triangles else (o.data.calc_loop_triangles() or len(o.data.loop_triangles)) for o in components[e['key']].objects)
(D/'catalog.json').write_text(json.dumps({'schema':'sea.scene.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.instances','up_axis':'Z','front_axis':'-Y','godot_mapping':'(x,y,z)->(x,z,-y)','instances':layout,'reused_instances':reused},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
image.filepath=bpy.path.relpath(str(PAL),start=str(D));bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(D/'gift_kiosk_interior.blend'),compress=True)
for c in [top['structure'],top['furnishing'],top['plant']]:c.hide_render=True
sc.render.filepath=str(W/'before.png');bpy.ops.render.render(write_still=True)
for c in [top['structure'],top['furnishing'],top['plant']]:c.hide_render=False
sc.render.filepath=str(W/'after.png');bpy.ops.render.render(write_still=True)
print('GKI_BUILT',len(catalog),'components',len(layout),'new instances',len(reused),'reused props')

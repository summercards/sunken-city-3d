import bpy,bmesh,json,hashlib,math,os,random
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v003';W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop/v003';random.seed(1031)
standard=json.loads((R/'.agents/skills/sea-scene-component-authoring/references/building_scale.json').read_text(encoding='utf-8'))['measurements'];CL=standard['ground_clear_height'];BT=standard['slab_thickness'];BW=standard['platform_board_width'];CW=standard['main_column_width'];DZ=2.514+CL-5.55
if not (W/'session_before.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'session_before.blend'),copy=True)
# Input is reopened by load_input_v003.py in the preceding MCP call so the GUI
# context is fresh before creating objects.
old_scene=bpy.data.scenes['海上悬浮商铺_v002'];display=bpy.data.collections['FSH_展示支持'];world=old_scene.world;camera=old_scene.camera
sc=bpy.data.scenes.new('海上悬浮商铺_v003');bpy.context.window_manager.windows[0].scene=sc;sc.unit_settings.system='METRIC';sc.collection.children.link(display);sc.camera=camera;sc.world=world
# Do not remove scenes inside an MCP timer after open_mainfile (Blender 4.5 crash).
reuse={'rail_post','tire','life_ring','ladder','spotlight','roof_pipe','electrical_box','beacon','engine','engine_glow','float_pod','aux_nozzle','aux_glow','counterweight','pot','foliage','flowers'}
oldcat={e['key']:e for e in json.loads((D.parent/'v002/catalog.json').read_text(encoding='utf-8'))['components']}
for col in list(bpy.data.collections):
 if col==display:continue
 if col.name in {'SEA-SCENE-FSH-'+k.upper().replace('_','-') for k in reuse}:continue
 for o in list(col.objects):bpy.data.objects.remove(o,do_unlink=True)
 bpy.data.collections.remove(col)
pal=R/'art_source/shared/palettes/sea_cabin_timber_8x8_512.png';colors={x['name']:x for x in json.loads(pal.with_suffix('.json').read_text())['cells']};roles={n:bpy.data.materials[n] for n in ['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission']}
for im in bpy.data.images:
 if im.source=='FILE' and ('sea_cozy' in im.filepath or 'sea_cabin_timber' in im.filepath):im.filepath=str(pal);im.reload()
bs=next(n for n in roles['SEA_Gloss'].node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Alpha'].default_value=1;bs.inputs['Transmission Weight'].default_value=0
# Tested primitive, PaletteUV, real-bevel and bottom-centre helpers from this kit.
code=(R/'tools/blender/floating_shop/build.py').read_text(encoding='utf-8');exec(code[code.index('def finish('):code.index('def build_deck(')])
for k in reuse:
 col=bpy.data.collections['SEA-SCENE-FSH-'+k.upper().replace('_','-')];components[k]=col;e=dict(oldcat[k]);spec=next(x for x in plan['components'] if x['key']==k);e.update(spec);e['component_source']=f'art_source/scenes/floating_shop/v003/component_packages/{k}/{k}.blend';catalog.append(e)

def deck():
 cube('矩形甲板内部承台',(0,0,.075),(20,15,.13),'plaster','SEA_Metal',.06)
 for i in range(16):
  y=(i-7.5)*.92;join=[-.45,.05,.45,.15][i%4]
  for a,b in [(-9.75,join-.013),(join+.013,9.75)]:cube('阳光房标准木板',((a+b)/2,y,BT/2),(b-a,BW,BT),['wood_light','honey','wood_light','wood'][i%4],bevel=.025)
 for x in [-9.83,9.83]:
  cube('甲板长侧包边',(x,0,.11),(.14,14.7,.18),'cream','SEA_Metal',.035)
 for y in [-7.40,7.40]:cube('甲板短侧包边',(0,y,.11),(19.7,.14,.18),'cream','SEA_Metal',.035)
 for x in [-9.98,9.98]:
  for y in [-6,-3,0,3,6]:sphere('侧沿铆钉',(x,y,.10),(.025,.025,.025),'silver','SEA_Metal',12,8)
 for y in [-7.48,7.48]:
  for x in [-9,-6,-3,0,3,6,9]:sphere('前后铆钉',(x,y,.10),(.025,.025,.025),'silver','SEA_Metal',12,8)
 for i in range(18):
  x=random.uniform(-9.3,9.3);z=random.uniform(.07,.12);vs=[(x+random.uniform(.10,.25)*math.cos(j*math.tau/7),-7.501,z+random.uniform(.015,.03)*math.sin(j*math.tau/7)) for j in range(7)];mesh('舷沿磨损漆斑',vs,[tuple(range(7))],'wood_mid')
part('deck',deck)
def roof():
 cube('矩形屋檐标准楼板',(0,0,BT/2),(13.2,10.2,BT),'honey','SEA_Metal',.06)
 vs=[(-6.5,-5,.2),(6.5,-5,.2),(6.5,5,.2),(-6.5,5,.2),(-6.5,0,.80),(6.5,0,.80)]
 mesh('低坡矩形金属屋面',vs,[(0,1,5,4),(4,5,2,3),(0,4,3),(1,2,5),(3,2,1,0)],'cream','SEA_Metal',.04)
 for x in [-6.1,-4.8,-3.5,-2.2,-.9,.4,1.7,3,4.3,5.6]:tube('屋面立边接缝',[(x,-4.92,.23),(x,0,.82),(x,4.92,.23)],.018,'stone','SEA_Metal')
 rod('矩形屋顶脊盖',(-6.5,0,.84),(6.5,0,.84),.045,'honey')
 for x in [-6.60,6.60]:cube('青绿山墙端包边',(x,0,.12),(.08,10.15,.18),'sage_gray','SEA_Metal',.025)
part('roof',roof)
def wall():
 cube('无门窗封闭墙板',(0,0,CL/2),(2,.19,CL),'cream',bevel=.035)
 for z in [CL*i/6 for i in range(1,6)]:cube('墙板横向凹缝',(0,-.103,z),(1.96,.015,.017),'stone',bevel=.003)
 for x in [-.95,.95]:
  cube('墙板青绿立边',(x,-.13,CL/2),(.09,.075,CL),'sage_gray','SEA_Metal',.02)
  for z in [.12,CL-.12]:sphere('墙边螺栓',(x,-.176,z),(.025,.014,.025),'silver','SEA_Metal',12,8)
part('wall_panel',wall)
part('corner_post',lambda:[cube('阳光房标准主柱',(0,0,CL/2),(CW,CW,CL),'sage_gray','SEA_Metal',.04),cube('柱底金属护脚',(0,0,.16),(CW,CW,.32),'teal','SEA_Metal',.025),cube('柱上金箍',(0,0,CL-.20),(CW,CW,.10),'honey','SEA_Metal',.02)])
part('plinth',lambda:[cube('矩形青绿墙脚',(0,0,.12),(12.1,9.1,.24),'sage_gray','SEA_Metal',.06),cube('墙脚奶白压边',(0,0,.245),(12.15,9.15,.06),'cream','SEA_Metal',.025)])
def canopy(c):
 # Flat straight strips with a curved scallop only at the bottom edge.
 vs=[];N=8
 for i in range(N+1):
  x=-.2+i*.4/N;drop=.25+.07*math.sin(i*math.pi/N)
  for y,z in [(.48,.62),(-.50,.32),(-.50,.32-drop),(-.44,.32-drop),(-.44,.35),(.48,.68)]:vs.append((x,y,z))
 fs=[(i*6+j,(i+1)*6+j,(i+1)*6+(j+1)%6,i*6+(j+1)%6) for i in range(N) for j in range(6)];fs += [tuple(reversed(range(6))),tuple(N*6+j for j in range(6))];mesh('直线蓝白遮棚条',vs,fs,c,bev=.018)
part('awning_blue',lambda:canopy('solar'));part('awning_white',lambda:canopy('snow'))
part('rail_straight',lambda:[rod('黄色直栏上杆',(-1,0,.98),(1,0,.98),.045,'gold'),rod('黄色直栏下杆',(-1,0,.46),(1,0,.46),.032,'gold')])
def control():
 cube('矩形主控米黄机身',(0,0,.40),(2.5,1.75,.80),'honey','SEA_Metal',.12);cube('矩形浅灰顶盖',(0,0,.85),(2.65,1.90,.15),'cloud','SEA_Metal',.08);cube('蓝色矩形顶饰',(0,0,.98),(.5,.32,.11),'aqua','SEA_Metal',.04)
 for x in [-.85,-.56,-.27,.02,.31,.6,.89]:cube('主控正面散热栅',(x,-.886,.41),(.10,.022,.32),'slate',bevel=.02)
 for x in [-1.1,1.1]:sphere('主控铆钉',(x,-.9,.65),(.035,.025,.035),'silver','SEA_Metal',12,8)
part('controller',control)
part('under_brace',lambda:[cube('底盘纵横方梁',(0,0,.15),(.36,5.2,.3),'steel','SEA_Metal',.035),tube('底盘管线',[(-.23,-2.5,.20),(-.23,-2.1,.03),(-.23,1.8,.03),(-.23,2.5,.20)],.065,'slate')])
part('sign_panel',lambda:[cube('方形补给站铭牌外框',(0,0,.45),(5.6,.18,.9),'ochre','SEA_Metal',.06),cube('奶黄铭牌面',(0,-.105,.45),(5.42,.06,.72),'butter',bevel=.045),text('海上补给站英文','SEA  SUPPLY',(0,-.152,.48),.57,'deepblue'),text('铭牌小字','MARINE STATION',(0,-.155,.18),.11,'wood_mid')])
def bench():
 for z in [.38,.63]:cube('长凳木板',(0,.12 if z>.4 else 0,z),(2.2,.44,.12),'wood_light',bevel=.05)
 for x in [-.82,.82]:cube('长凳青绿腿',(x,0,.20),(.12,.4,.4),'sage_gray','SEA_Metal',.035)
part('bench',bench)
part('cargo_crate',lambda:[cube('矩形防水货箱',(0,0,.38),(.95,.72,.76),'seafoam','SEA_Metal',.07),cube('货箱奶白箱盖',(0,0,.78),(1,.77,.10),'cream','SEA_Gloss',.045)]+[cube('货箱金属箍',(x,-.368,.39),(.08,.025,.7),'silver','SEA_Metal',.012) for x in [-.31,.31]]+[cube('箱盖扣',(0,-.405,.72),(.13,.05,.13),'slate','SEA_Metal',.015)])
part('bollard',lambda:[cyl('系泊柱底盘',(0,0,.04),.20,.08,'slate',verts=24),cyl('系泊短柱',(0,0,.29),.095,.5,'ochre',verts=24),rod('双耳横柱',(-.29,0,.5),(.29,0,.5),.065,'gold')])
part('roof_vent',lambda:[cube('矩形通风盒',(0,0,.30),(1.0,.72,.60),'silver','SEA_Metal',.065),cube('通风盒防雨顶',(0,0,.63),(1.08,.8,.09),'cloud','SEA_Metal',.035)]+[cube('通风百叶',(0,-.37,.13+i*.10),(.8,.06,.045),'slate','SEA_Metal',.01) for i in range(4)])

building=bpy.data.collections.new('FSH_建筑与固定设施');plants=bpy.data.collections.new('FSH_植物附件');sc.collection.children.link(building);sc.collection.children.link(plants);layout=[]
def put(k,p,a=0,s=(1,1,1),rot=None):
 n=k+'_'+str(sum(x['key']==k for x in layout)+1).zfill(3);o=bpy.data.objects.new(n,None);o.instance_type='COLLECTION';o.instance_collection=components[k];o.location=p;o.rotation_euler=rot or (0,0,a);o.scale=s;(plants if k in ['foliage','flowers'] else building).objects.link(o);layout.append({'name':n,'key':k,'asset_id':'SEA-SCENE-FSH-'+k.upper().replace('_','-'),'position':list(p),'rotation_euler_xyz':list(o.rotation_euler),'scale':list(s)});return o
put('deck',(0,0,2.514-BT));put('plinth',(0,0,2.514));put('roof',(0,0,2.514+CL))
for y,a in [(-4.5,0),(4.5,math.pi)]:
 for x in [-5,-3,-1,1,3,5]:put('wall_panel',(x,y,2.514),a)
for x,a in [(-6,-math.pi/2),(6,math.pi/2)]:
 for y in [-3.375,-1.125,1.125,3.375]:put('wall_panel',(x,y,2.514),a,s=(1.125,1,1))
for x in [-6,-2,2,6]:
 for y in [-4.5,4.5]:put('corner_post',(x,y,2.514))
for x in [-6,6]:put('corner_post',(x,0,2.514))
for y,a in [(-5.02,0),(5.02,math.pi)]:
 for i in range(33):put('awning_blue' if i%2==0 else 'awning_white',(-6.4+i*.4,y,4.9+DZ),a)
for x,a in [(-6.52,-math.pi/2),(6.52,math.pi/2)]:
 for i in range(23):put('awning_blue' if i%2==0 else 'awning_white',(x,-4.4+i*.4,4.9+DZ),a)
put('sign_panel',(0,-5.25,5.55+DZ))
for x in [-4.7,4.7]:put('life_ring',(x,-4.82,3.20))
post_points=set()
def railing(a,b,n):
 a=Vector(a);b=Vector(b);delta=(b-a)/n;angle=math.atan2(delta.y,delta.x)
 for i in range(n):
  p=a+delta*(i+.5);put('rail_straight',(p.x,p.y,3.014),angle,s=(delta.length/2,1,1))
 for i in range(n+1):p=a+delta*i;post_points.add((round(p.x,5),round(p.y,5)))
railing((-9.5,-7.1),( -1.6,-7.1),4);railing((1.6,-7.1),(9.5,-7.1),4);railing((-9.5,7.1),(9.5,7.1),8)
railing((-9.5,-7.1),(-9.5,7.1),6);railing((9.5,-7.1),(9.5,7.1),6)
for x,y in sorted(post_points):put('rail_post',(x,y,2.514),s=(1,1,1.1/1.205))
for x in [-7,-3,3,7]:put('tire',(x,-7.6,1.63));put('tire',(x,7.6,1.63),math.pi)
for x,a in [(-10.1,-math.pi/2),(10.1,math.pi/2)]:
 for y in [-4.4,0,4.4]:put('tire',(x,y,1.63),a)
put('ladder',(3.7,-7.3,.02));put('controller',(0,0,6.28+DZ))
for x in [-4.8,4.8]:
 for y,a in [(-3.9,0),(3.9,math.pi)]:put('spotlight',(x,y,5.90+DZ),a)
for x in [-2.9,2.9]:put('roof_pipe',(x,1.4,6.12+DZ));put('roof_vent',(x,-1.8,6.10+DZ))
for x in [-5.8,5.8]:put('beacon',(x,3.9,5.92+DZ))
put('engine',(0,0,0));put('engine_glow',(0,0,-.025))
for x in [-3.8,3.8]:put('float_pod',(x,-1.6,.02))
for x in [-7.7,7.7]:
 for y in [-4.8,4.8]:put('aux_nozzle',(x,y,1.46));put('aux_glow',(x,y,1.44))
for x in [-6.5,-3.2,0,3.2,6.5]:put('under_brace',(x,0,2.514-BT-.30))
for x in [-8,8]:
 for y in [-6.7,6.7]:put('counterweight',(x,y,.67));put('bollard',(x,y,2.514))
for x in [-4.8,4.8]:put('pot',(x,-5.6,2.514));put('foliage',(x,-5.6,2.924));put('flowers',(x,-5.6,3.01))
for y in [-2.7,2.7]:put('pot',(-7.1,y,2.514));put('foliage',(-7.1,y,2.924))
put('bench',(-7.5,0,2.514),-math.pi/2);put('bench',(0,5.8,2.514),math.pi)
put('cargo_crate',(7.1,3,2.514));put('cargo_crate',(8.3,3.3,2.514),.08);put('cargo_crate',(7.1,3,3.40))
put('electrical_box',(-4,4.8,2.8),math.pi,s=(1.4,1,1.6));put('electrical_box',(4,4.8,2.8),math.pi,s=(1.4,1,1.6))
for e in catalog:
 e['instances']=sum(x['key']==e['key'] for x in layout);e['version']='v003';e['component_source']=f"art_source/scenes/floating_shop/v003/component_packages/{e['key']}/{e['key']}.blend";e.pop('source_sha256',None)
(D/'catalog.json').write_text(json.dumps({'schema':'sea.scene.component_catalog','components':catalog},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.instances','up_axis':'Z','front_axis':'-Y','godot_mapping':'(x,y,z)->(x,z,-y)','instances':layout},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for im in bpy.data.images:
 if im.source=='FILE' and ('sea_cozy' in im.filepath or 'sea_cabin_timber' in im.filepath):im.filepath=bpy.path.relpath(str(pal),start=str(D))
camera.location=(19,-28,20);camera.rotation_euler=(Vector((0,0,3.6))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=27
sc.render.engine='CYCLES';sc.cycles.samples=32;sc.cycles.use_denoising=True;sc.render.resolution_x=1600;sc.render.resolution_y=1200;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG';sc.view_settings.view_transform='Standard';sc.view_settings.look='Medium High Contrast';sc.view_settings.exposure=-.7
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 for dev in prefs.devices:dev.use=dev.type!='CPU'
 sc.cycles.device='GPU' if any(d.use for d in prefs.devices) else 'CPU'
except Exception:pass
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(D/'floating_shop.blend'),compress=True)
sc.render.filepath=str(W/'preview.png');sc.render.resolution_percentage=70;bpy.ops.render.render(write_still=True)
print(json.dumps({'source':str(D/'floating_shop.blend'),'components':len(catalog),'instances':len(layout)},ensure_ascii=False))

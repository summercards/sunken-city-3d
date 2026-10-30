import bpy,math,json,hashlib,random
from pathlib import Path
from mathutils import Vector
R=Path(r'D:/projects/sea');D=R/'art_source/scenes/liberty_lighthouse/v001';W=R/'sea-work/liberty_lighthouse'
random.seed(27)
# Rebuild only this explicitly task-owned scene; preserve unrelated scenes and data.
for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
for c in list(bpy.data.collections):bpy.data.collections.remove(c)
sc=bpy.data.scenes.new('巨手灯塔_制作与装配_v001');bpy.context.window.scene=sc;sc.unit_settings.system='METRIC'
pal=R/'art_source/shared/palettes/sea_cozy_8x8_512.png'
palette=json.loads((pal.with_suffix('.json')).read_text())
colors={x['name']:x for x in palette['cells']}
# Shared four material roles.
image=bpy.data.images.load(str(pal),check_existing=True);image.filepath=str(pal)
roles={}
for name,metal,rough in [('SEA_Matte',.04,.72),('SEA_Metal',.72,.34),('SEA_Gloss',.18,.16),('SEA_Emission',0,.38)]:
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;n.clear();out=n.new('ShaderNodeOutputMaterial');bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
 uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';tx=n.new('ShaderNodeTexImage');tx.image=image;tx.interpolation='Closest';l.new(uv.outputs['UV'],tx.inputs['Vector']);l.new(tx.outputs['Color'],bs.inputs['Base Color']);l.new(bs.outputs[0],out.inputs['Surface'])
 if name=='SEA_Emission':l.new(tx.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=.75
 roles[name]=m

def norm(v):return Vector(v).normalized()
def place_uv(o,cell):
 for old in list(o.data.uv_layers):o.data.uv_layers.remove(old)
 uv=o.data.uv_layers.new(name='PaletteUV');c=colors[cell];u0=c['column']/8;v0=1-(c['row']+1)/8
 for p in o.data.polygons:
  coords=[(.28,.28),(.72,.28),(.72,.72),(.28,.72)]
  for j,li in enumerate(p.loop_indices):uv.data[li].uv=(u0+coords[j%4][0]/8,v0+coords[j%4][1]/8)
 o.data.uv_layers.active=uv;uv.active_render=True

def finish(o,cell='seafoam',role='SEA_Matte',bev=.035):
 if o.data.materials:o.data.materials.clear()
 o.data.materials.append(roles[role]);place_uv(o,cell)
 for p in o.data.polygons:p.material_index=0
 if bev:
  m=o.modifiers.new('实体柔边','BEVEL');m.width=bev;m.segments=2
 return o

def cube(name,loc,size,cell='seafoam',role='SEA_Matte',bev=.035,rot=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if rot:o.rotation_euler=rot
 return finish(o,cell,role,bev)

def cyl(name,loc,r,depth,cell='seafoam',role='SEA_Metal',verts=32,r2=None,rot=None,bev=.02):
 if r2 is None:bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,location=loc)
 else:bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=r,radius2=r2,depth=depth,location=loc)
 o=bpy.context.object;o.name=name
 if rot:o.rotation_euler=rot
 return finish(o,cell,role,bev)

def sphere(name,loc,scale,cell='seafoam',role='SEA_Matte'):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);return finish(o,cell,role,0)

def tube(name,pts,r,cell='wood_dark',role='SEA_Metal',res=2):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=1;cu.bevel_depth=r;cu.bevel_resolution=res
 s=cu.splines.new('POLY');s.points.add(len(pts)-1)
 for p,co in zip(s.points,pts):p.co=(*co,1)
 o=bpy.data.objects.new(name,cu);sc.collection.objects.link(o);bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');o=bpy.context.object
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 return finish(o,cell,role,0)

def rod(name,a,b,r,cell='wood_dark',role='SEA_Metal',verts=12):
 a=Vector(a);b=Vector(b);o=cyl(name,(a+b)/2,r,(b-a).length,cell,role,verts,bev=.01);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def text(name,body,loc,size,cell='red_dark',rot=(math.pi/2,0,0),role='SEA_Matte',align='CENTER'):
 cu=bpy.data.curves.new(name,'FONT');cu.body=body;cu.align_x=align;cu.align_y='CENTER';cu.size=size;cu.extrude=.006;cu.bevel_depth=.002;cu.space_character=1.07
 o=bpy.data.objects.new(name,cu);sc.collection.objects.link(o);o.location=loc;o.rotation_euler=rot
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');o=bpy.context.object
 return finish(o,cell,role,0)

# Author mesh parts in local bottom-centered collections.
components={}
def part(key,fn):
 col=bpy.data.collections.new('SEA-SCENE-LHL-'+key.upper().replace('_','-'));sc.collection.children.link(col)
 before=set(sc.objects)
 fn()
 objs=[o for o in sc.objects if o not in before]
 root=bpy.data.objects.new(key+'_组件根',None);col.objects.link(root)
 for o in objs:
  for c in list(o.users_collection):c.objects.unlink(o)
  col.objects.link(o);mw=o.matrix_world.copy();o.parent=root;o.matrix_world=mw
 # normalize center XY and bottom Z, preserving authored shape.
 deps=bpy.context.evaluated_depsgraph_get();pts=[]
 for o in objs:
  if o.type=='MESH':
   ev=o.evaluated_get(deps);me=ev.to_mesh();pts += [o.matrix_world@v.co for v in me.vertices];ev.to_mesh_clear()
 lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);ctr=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 root.location=(0,0,0)
 for o in objs:
  if o.parent==root:
   o.matrix_parent_inverse.identity()
   o.location-=ctr
 col.instance_offset=(0,0,0)
 sc.collection.children.unlink(col);components[key]=col
 return col,list(hi-lo)

def inst(key,name,pos,rot=(0,0,0),scale=(1,1,1),cat='structure'):
 o=bpy.data.objects.new(name,None);o.instance_type='COLLECTION';o.instance_collection=components[key];o.location=pos;o.rotation_euler=rot;o.scale=scale;sc.collection.objects.link(o);return o

part('barge',lambda:[cube('驳船做旧船壳',(0,0,.6),(8,6,1.2),'sage_gray','SEA_Metal',.18),cube('驳船甲板',(0,0,1.15),(7.85,5.85,.18),'plaster','SEA_Matte',.04)]+[cube('基座竖向板缝',(-3.7+i*.8,-3.012,.6),(.026,.018,1.02),'steel','SEA_Metal',.005) for i in range(10)]+[cube('基座锈蚀斑',(-3.3+i*1.3,-3.024,.37+random.random()*.3),(.35,.012,.2+random.random()*.24),'wood_dark','SEA_Matte',.015) for i in range(6)])
part('tire',lambda:[o for o in [bpy.ops.mesh.primitive_torus_add(major_radius=.29,minor_radius=.11,major_segments=24,minor_segments=10,rotation=(math.pi/2,0,0)),finish(bpy.context.object,'rubber','SEA_Matte',0)]])
part('shop_shell',lambda:[cube('商铺后墙',(0,2,1.4),(6.4,.18,2.8),'sage_gray'),cube('商铺左墙',(-3.1,0,1.4),(.2,4,2.8),'sage_gray'),cube('商铺右墙',(3.1,0,1.4),(.2,4,2.8),'sage_gray'),cube('正墙门左',(-2.0,-2,1.4),(2.2,.18,2.8),'seafoam'),cube('正墙门右',(2,-2,1.4),(2.2,.18,2.8),'seafoam'),cube('门楣',(0,-2,2.5),(1.8,.18,.6),'seafoam'),cube('商铺内顶棚',(0,0,2.75),(6.4,4.1,.16),'sage_gray','SEA_Metal')]+[cube('外墙金属立缝',(-3.211,-1.5+i*.6,1.4),(.025,.027,2.7),'teal','SEA_Metal',.005) for i in range(6)]+[cube('墙面锈蚀痕',(-3.22,-1.5+i*.9,.55+random.random()),(.02,.22,.45),'wood_dark','SEA_Matte',.01) for i in range(4)])
part('shop_trim',lambda:[cube('商铺立柱',(x,y,1.4),(.16,.16,2.8),'teal','SEA_Metal') for x,y in [(-3.17,-2.02),(3.17,-2.02),(-3.17,2.02),(3.17,2.02)]]+[cube('商铺顶包边',(0,-2.12,2.78),(6.55,.18,.16),'seafoam','SEA_Metal')])
part('awning',lambda:[cube('雨棚后段斜布',(0,-.5,3.50),(7.6,5.6,.1),'blue','SEA_Matte',.025,rot=(.06,0,0))]+[cube('蓝白条纹',(-3.6+i*.4,-3.32,2.55),(.2,.075,.38),'snow' if i%2==0 else 'blue','SEA_Matte',.02) for i in range(19)]+[cube('前沿条纹',(-3.6+i*.4,-3.25,2.72),(.2,1.2,.08),'snow' if i%2==0 else 'blue','SEA_Matte',.01,rot=(.09,0,0)) for i in range(19)]+[cube('侧面蓝白条',(3.82,-2.8+i*.5,2.55),(.08,.25,.38),'snow' if i%2==0 else 'blue','SEA_Matte',.02) for i in range(11)])
part('sign',lambda:[cube('招牌黄色通长底板',(0,0,.4),(7,.16,.8),'honey','SEA_Metal',.035),cube('招牌中段接缝',(0,-.095,.4),(.08,.025,.78),'wood_mid','SEA_Metal',.01),text('纪念品红色字样','SOUVENIRS',(-1.78,-.105,.4),.48),text('自由纪念红色字样','LIBERTY S...',(1.75,-.105,.4),.43)])
part('window',lambda:[cube('窗户外金属框',(0,0,.6),(1.15,.10,1.35),'cream','SEA_Metal'),cube('窗户蓝色玻璃',(0,-.065,.6),(1.0,.035,1.2),'deepblue','SEA_Gloss',.02),cube('窗横梃',(0,-.1,.6),(1.02,.06,.06),'snow','SEA_Metal',.01),cube('窗竖梃',(0,-.1,.6),(.06,.06,1.22),'snow','SEA_Metal',.01)])
part('service_window',lambda:[cube('服务窗黑洞',(0,0,.6),(1.12,.12,1.32),'rubber','SEA_Matte'),cube('服务窗台',(0,-.16,.03),(1.2,.36,.10),'cream','SEA_Metal'),cube('服务窗玻璃',(0,-.075,.72),(1,.025,.92),'deepblue','SEA_Gloss')])
part('notice',lambda:[cube('手写告示底牌',(0,0,.4),(.6,.04,.8),'cream','SEA_Matte',.025),text('告示标题','TODAY',(0,-.026,.59),.105,'slate'),text('告示内容','FRESH\nARTISANAL\nMADE',(0,-.027,.32),.077,'slate')])
part('ice_box',lambda:[cube('冷藏柜外壳',(0,0,.6),(1,.42,1.2),'snow','SEA_Metal',.055),cube('冷藏柜门',(0,-.23,.57),(.88,.055,1.05),'mint_white','SEA_Gloss',.025),cube('冷藏柜把手',(.32,-.275,.55),(.035,.04,.42),'steel','SEA_Metal',.01),text('冷藏柜ICE','ICE',(0,-.267,.88),.30,'blue')])
part('hydrant',lambda:[cyl('消防栓红身',(0,0,.42),.17,.72,'red_dark','SEA_Metal',16),cyl('消防栓顶帽',(0,0,.84),.22,.14,'snow','SEA_Metal',16),cyl('消防栓底座',(0,0,.07),.25,.14,'red_dark','SEA_Metal',16),rod('消防栓侧管',(-.34,0,.48),(.34,0,.48),.115,'red_dark','SEA_Metal',12),cyl('消防栓白环',(0,0,.65),.18,.10,'snow','SEA_Metal',16)])
part('traffic_signal',lambda:[cyl('信号杆',(0,0,1),.065,2,'steel','SEA_Metal',12),cube('交通灯箱',(0,0,1.52),(.42,.34,1.02),'wood_dark','SEA_Metal',.05)]+[cyl('交通灯透镜',(0,-.20,1.22+i*.3),.115,.08,c,'SEA_Emission',16,rot=(math.pi/2,0,0),bev=.01) for i,c in enumerate(['leaf_light','honey','red_dark'])])
part('billboard',lambda:[cube('独立广告牌',(0,0,1.5),(1.8,.18,3),'cream','SEA_Metal',.055),text('广告牌ICE','ICE C',(0,-.105,2.12),.39),text('广告牌手写文字',"We've got\nARTISANAL", (0,-.105,1.42),.18,'slate'),cube('广告牌支脚',(-.55,0,.18),(.15,.5,.36),'wood_dark','SEA_Metal'),cube('广告牌支脚',(.55,0,.18),(.15,.5,.36),'wood_dark','SEA_Metal')]+[rod('广告牌灯臂',(x,0,3),(x,-.3,3.5),.035,'steel') for x in [-.55,.55]]+[cyl('广告牌照明灯',(x,-.32,3.46),.12,.16,'honey','SEA_Emission',12,rot=(math.pi/2,0,0)) for x in [-.55,.55]])
part('arm',lambda:[sphere('手掌',(0,0,4.75),(1.25,.85,2.12)),sphere('手腕',(.15,.12,2.15),(.95,.74,1.65)),sphere('前臂',(.35,.12,.9),(1.03,.73,1.6)),cyl('手腕旧铜环',(.13,.1,2.2),1,.3,'sage_gray','SEA_Metal',20),cube('铜臂断裂片',(.65,-.64,3.35),(.55,.18,1.1),'sage_gray','SEA_Metal',.06,rot=(0,.18,-.1))])
part('finger',lambda:[tube('连续弯曲指身',[(0,.12,.38),(0,-.20,.43),(0,-.65,.55),(0,-1.03,.52),(0,-1.24,.39)],.40,'seafoam','SEA_Matte',3),sphere('圆润指根',(0,.1,.38),(.4,.42,.4)),sphere('圆润指尖',(0,-1.24,.39),(.4,.32,.4)),cube('铜指节纹',(0,-.61,.91),(.51,.10,.035),'sage_gray','SEA_Metal',.015)])
part('thumb',lambda:[sphere('拇指掌根',(0,0,.48),(.58,.6,.72)),rod('拇指上节',(0,0,.45),(.08,-.55,1.23),.46),sphere('拇指尖',(.08,-.55,1.25),(.45,.45,.52))])
part('column',lambda:[cyl('柱身主体',(0,0,2.5),1,5,'sage_gray','SEA_Metal',32)]+[cube('柱身竖向凹槽',(math.sin(a)*.995,-math.cos(a)*.995,2.5),(.055,.035,4.75),'teal','SEA_Metal',.015,rot=(0,0,a)) for a in [i*math.tau/16 for i in range(16)]]+[cyl('柱身环箍',(0,0,z),1.1,.16,'seafoam','SEA_Metal',32) for z in [.3,3.65,4.7]])
part('maintenance_door',lambda:[cube('检修门黑洞',(0,0,.6),(.7,.08,1.2),'rubber','SEA_Matte',.035),cube('检修门边框',(0,-.05,.6),(.8,.08,1.3),'wood_dark','SEA_Metal',.025),cube('检修门开口',(0,-.10,.6),(.64,.03,1.14),'slate','SEA_Metal',.02),cube('检修门把手',(.2,-.13,.6),(.045,.06,.16),'silver','SEA_Metal',.01)])
part('platform',lambda:[cyl('圆形观景平台厚底板',(0,0,.25),3,.5,'sage_gray','SEA_Metal',48),cyl('观景台面',(0,0,.49),2.93,.08,'seafoam','SEA_Metal',48),cyl('平台中心承托',(0,0,-.2),1.35,.45,'teal','SEA_Metal',32,r2=2.2)])
part('platform_trim',lambda:[cyl('平台装饰线脚',(0,0,.05),3.04,.12,'seafoam','SEA_Metal',48)]+[rod('平台底托臂',(math.sin(a)*1.2,math.cos(a)*1.2,-.45),(math.sin(a)*2.75,math.cos(a)*2.75,.05),.12,'teal','SEA_Metal',10) for a in [i*math.tau/12 for i in range(12)]])
part('railing',lambda:[tube('红锈断栏杆',[(-1.15,0,.55),(-1.15,0,1.1),(-.58,0,1.1),(.05,0,1.1)],.045,'red_dark'),rod('栏杆立柱',(-.58,0,0),(-.58,0,1.1),.045,'red_dark'),rod('栏杆立柱',(.05,0,0),(.05,0,1.1),.045,'red_dark'),rod('栏杆下横杆',(-1.15,0,.38),(.05,0,.38),.03,'wood_dark'),tube('断口折弯',[(.05,0,1.1),(.25,0,.95),(.4,0,.78)],.035,'wood_dark')])
part('equipment_box',lambda:[cube('平台小型设备箱',(0,0,.4),(1,.8,.8),'slate','SEA_Metal',.055),cube('设备箱盖',(0,0,.82),(1.04,.84,.08),'sage_gray','SEA_Metal',.02),cube('设备箱扣',(.0,-.42,.46),(.12,.035,.16),'silver','SEA_Metal',.01)])
part('solar_panel',lambda:[cube('斜置太阳能板',(0,0,.55),(1.5,1,.10),'deepblue','SEA_Gloss',.03,rot=(.35,0,0)),cube('太阳能板白框',(0,0,.52),(1.58,1.08,.045),'silver','SEA_Metal',.015,rot=(.35,0,0))]+[cube('太阳能分格',(x,0,.61),(.016,.94,.012),'sky','SEA_Metal',0,rot=(.35,0,0)) for x in [-.5,0,.5]]+[rod('太阳能支脚',(x,0,0),(x,0,.5),.035,'steel') for x in [-.5,.5]])
part('tower_body',lambda:[cyl('收窄塔身',(0,0,1.25),1.25,2.5,'seafoam','SEA_Metal',24,r2=1.1)]+[cube('塔身竖向结构缝',(math.sin(a)*1.17,-math.cos(a)*1.17,1.25),(.035,.035,2.3),'teal','SEA_Metal',.005,rot=(0,0,a)) for a in [i*math.tau/12 for i in range(12)]])
part('lantern',lambda:[cyl('灯室底框',(0,0,.08),.95,.16,'teal','SEA_Metal',8),cyl('灯室顶框',(0,0,1.92),.95,.16,'teal','SEA_Metal',8)]+[rod('灯室金属竖框',(math.sin(a)*.86,math.cos(a)*.86,.15),(math.sin(a)*.86,math.cos(a)*.86,1.85),.04,'steel') for a in [i*math.tau/8 for i in range(8)]]+[cube('灯室多边形玻璃',(math.sin(a)*.79,math.cos(a)*.79,1),(.65,.035,1.7),'sky','SEA_Gloss',.005,rot=(0,0,-a)) for a in [i*math.tau/8 for i in range(8)]])
part('lens',lambda:[cyl('灯座',(0,0,.15),.38,.3,'steel','SEA_Metal',20),sphere('大型灯塔透镜',(0,0,.75),(.48,.48,.64),'honey','SEA_Gloss')]+[cyl('透镜环',(0,0,.42+i*.16),.46,.025,'honey','SEA_Emission',32) for i in range(5)])
part('antenna_mast',lambda:[rod('天线主桅杆',(0,0,0),(0,0,3.5),.065,'steel'),rod('桅杆侧杆',(.22,.1,0),(.22,.1,3.5),.035,'steel')]+[rod('桅杆横担',(0,0,z),(.55,0,z),.035,'steel') for z in [.7,1.55,2.5]]+[rod('桅杆斜撑',(0,0,z),(.22,.1,z+.45),.022,'steel') for z in [.1,.8,1.5,2.2,2.8]])
part('satellite_dish',lambda:[cyl('圆形卫星天线',(0,0,0),.4,.10,'cream','SEA_Metal',24,rot=(math.pi/2,0,0)),rod('卫星接收杆',(0,-.02,0),(0,-.3,0),.035,'steel'),sphere('卫星接收头',(0,-.3,0),(.08,.08,.08),'slate','SEA_Metal'),text('卫星文字','BEYOND',(0,-.062,0),.10,'slate')])
part('panel_antenna',lambda:[cube('矩形通信天线',(0,0,.35),(.7,.16,.4),'cream','SEA_Metal',.055),cube('通信天线安装耳',(0,0,.02),(.25,.24,.06),'steel','SEA_Metal',.015)])
part('roof_cap',lambda:[cyl('灯室尖顶盖',(0,0,.25),1.06,.5,'teal','SEA_Metal',8,r2=.12),cyl('顶盖檐边',(0,0,.03),1.10,.08,'seafoam','SEA_Metal',8)])

# Reference layout in metres, front=-Y.
layout=[]
def put(key,pos,rot=(0,0,0),scale=(1,1,1)):
 name=key+'_'+str(len([x for x in layout if x['key']==key])+1).zfill(2);o=inst(key,name,pos,rot,scale);layout.append({'name':name,'key':key,'position':list(pos),'rotation_euler_xyz':list(rot),'scale':list(scale)})
put('barge',(0,0,0))
for x in [-3,-1.5,0,1.5,3]:put('tire',(x,-3.10,.63))
for y in [-1.8,0,1.8]:
 put('tire',(-4.08,y,.63),(0,0,math.pi/2));put('tire',(4.08,y,.63),(0,0,math.pi/2))
put('shop_shell',(0,0,1.2));put('shop_trim',(0,0,1.2));put('awning',(0,0,3.5));put('sign',(0,-2.26,4.0))
put('window',(-2.05,-2.12,2.25));put('service_window',(2.02,-2.12,2.18));put('notice',(1.0,-2.23,2.35))
put('window',(-3.24,.45,2.2),(0,0,-math.pi/2));put('ice_box',(2.08,-2.20,1.28));put('hydrant',(3.28,-2.42,1.22));put('traffic_signal',(3.45,1.25,1.2));put('billboard',(3.25,1.5,4.0),(0,0,-.06))
# Wrist and arm to hand, with the cylindrical shaft visibly grasped.
put('arm',(0,0,4.4));put('column',(0,.10,10.7))
for i in range(4):
 a=math.radians(-54+i*36);put('finger',(math.sin(a)*.76,-math.cos(a)*.76,8.15+i*.78),(0,0,a))
bpy.context.view_layer.update()
put('thumb',(.95,-.05,7.55),(0,0,-.85))
put('maintenance_door',(0,-1.03,11.55))
put('platform',(0,0,16.4));put('platform_trim',(0,0,16.36))
for i in range(13):
 if i in [1,2,8]:continue
 a=i*math.tau/16;put('railing',(math.sin(a)*2.72,math.cos(a)*2.72,16.94),(0,0,-a))
put('equipment_box',(1.4,.75,16.94));put('solar_panel',(-1.15,.8,16.94),(0,0,-.15))
put('tower_body',(0,0,16.94));put('lantern',(0,0,19.44));put('lens',(0,0,19.67));put('roof_cap',(0,0,21.44))
put('antenna_mast',(.40,.2,21.85));put('satellite_dish',(.25,.15,24.6),(0,0,-.12))
for z,y,a in [(22.5,.20,.08),(23.35,.20,-.08),(24.05,.20,.10)]:put('panel_antenna',(.55,y,z),(0,0,a))

# Catalog and identity.
cat={'schema':'sea.scene.component_catalog','components':[]}
for key,col in components.items():
 root=next(o for o in col.objects if o.type=='EMPTY');deps=bpy.context.evaluated_depsgraph_get();pts=[]
 for o in col.objects:
  if o.type=='MESH':
   ev=o.evaluated_get(deps);me=ev.to_mesh();pts += [o.matrix_world@v.co for v in me.vertices];ev.to_mesh_clear()
 lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)])
 spec=next(x for x in json.loads((D/'component_plan.json').read_text())['components'] if x['key']==key)
 geom=';'.join(o.name+':'+','.join(str(round(c,4)) for v in o.data.vertices for c in v.co) for o in col.objects if o.type=='MESH')
 cat['components'].append(dict(spec,collection=col.name,root=root.name,bounds_size=list(hi-lo),component_source='art_source/scenes/liberty_lighthouse/v001/component_packages/'+key+'/'+key+'.blend',geometry_fingerprint=hashlib.sha256(geom.encode()).hexdigest(),instances=sum(x['key']==key for x in layout),materials=['SEA_Matte','SEA_Metal','SEA_Gloss','SEA_Emission'],collision_owner='Godot PackedScene pending'))
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n');(D/'component_instances.json').write_text(json.dumps({'schema':'sea.scene.instances','up_axis':'Z','front_axis':'-Y','instances':layout},ensure_ascii=False,indent=2)+'\n')
# Exhibition only.
world=bpy.data.worlds.new('灯塔海天展示');world.use_nodes=True;world.node_tree.nodes.clear();bg=world.node_tree.nodes.new('ShaderNodeBackground');wo=world.node_tree.nodes.new('ShaderNodeOutputWorld');world.node_tree.links.new(bg.outputs[0],wo.inputs[0]);bg.inputs[0].default_value=(.22,.38,.48,1);bg.inputs[1].default_value=.65;sc.world=world
cube('展示海面',(0,0,-.20),(200,200,.15),'ocean','SEA_Gloss',0)
for name,loc,power,size,col in [('主光',(-10,-14,25),2300,10,(1,.85,.67)),('天光',(8,3,20),1800,9,(.65,.82,1))]:
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=col;o=bpy.data.objects.new(name,d);sc.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,11))-o.location).to_track_quat('-Z','Y').to_euler()
camd=bpy.data.cameras.new('参考全景相机');cam=bpy.data.objects.new('参考全景相机',camd);sc.collection.objects.link(cam);cam.location=(17,-38,22);cam.rotation_euler=(Vector((0,0,12.3))-cam.location).to_track_quat('-Z','Y').to_euler();camd.type='ORTHO';camd.ortho_scale=29.8;sc.camera=cam
sc.render.engine='CYCLES';sc.cycles.samples=40;sc.cycles.use_denoising=True;sc.render.resolution_x=1000;sc.render.resolution_y=1400;sc.render.resolution_percentage=100
sc.view_settings.view_transform='Standard';sc.view_settings.look='Medium High Contrast'
bpy.context.preferences.filepaths.save_version=0
for im in bpy.data.images:
 if im.source=='FILE':im.filepath=bpy.path.relpath(str(pal))
# Useful viewport.
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL';area.spaces.active.overlay.show_overlays=False
bpy.ops.wm.save_as_mainfile(filepath=str(D/'liberty_lighthouse.blend'),compress=True)
print(json.dumps({'source':str(D/'liberty_lighthouse.blend'),'components':len(components),'instances':len(layout),'scene':sc.name},ensure_ascii=False))

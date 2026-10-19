import bpy, math, random, os, json
from mathutils import Vector, Matrix
random.seed(180026)
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district'
# This generator owns only TD_ datablocks. The original session remains in a separate scene.
for ob in list(bpy.data.objects):
    if ob.name.startswith('TD_'): bpy.data.objects.remove(ob,do_unlink=True)
for co in list(bpy.data.collections):
    if co.name.startswith('TD_'): bpy.data.collections.remove(co)
for sc in list(bpy.data.scenes):
    if sc.name.startswith('TD_'): bpy.data.scenes.remove(sc)
s=bpy.data.scenes.new('TD_TOWER_DISTRICT_v002');bpy.context.window.scene=s
s.render.engine='BLENDER_EEVEE';s.render.resolution_x=1920;s.render.resolution_y=810;s.render.resolution_percentage=60
s.render.image_settings.file_format='PNG';s.render.fps=24;s.frame_start=1;s.frame_end=240
s.world=bpy.data.worlds.new('TD_Night_Atmosphere');s.world.use_nodes=True
s.world.node_tree.nodes['Background'].inputs[0].default_value=(0.025,0.065,0.085,1)
s.world.node_tree.nodes['Background'].inputs[1].default_value=0.16
s.view_settings.view_transform='AgX';s.view_settings.exposure=-.25
try:s.view_settings.look='AgX - Medium High Contrast'
except:pass
s.render.film_transparent=False
s.render.image_settings.color_mode='RGBA'
if hasattr(s.eevee,'taa_render_samples'):s.eevee.taa_render_samples=64
if hasattr(s.eevee,'use_raytracing'):s.eevee.use_raytracing=True
# A small shared palette; every mesh face has a nonzero UV island inside one color cell.
colors={
'void':'071318','black':'0c1b21','navy':'142830','dark':'20343a','steel':'35474c','steel2':'4a5d60','edge':'728080','pale':'a4b5ad',
'wall':'30484b','wall2':'3d5556','tile':'476161','grout':'172d32','blue':'214656','blue2':'2b6071','cyan':'69bdc9','ice':'bce8e2',
'ochre':'635348','rust':'6b4235','rust2':'9c5b3d','copper':'a57d4c','gold':'c4a273','amber':'ff9b42','warm':'ffd4a0','cream':'e8d8b3',
'red':'e72938','redhot':'ff3e49','redmid':'7c2d2c','redlow':'3c2426','green':'70bb64','greenhot':'b5e88a','greendark':'2b5547','white':'c6d8d6',
'paper':'9fac9d','asphalt':'14292e','wet':'25484f','wet2':'396169','window':'173b46','violet':'889fef','yellow':'e2bb58','brown':'5a4a37',
'car':'1b3437','car2':'37443e','tire':'081215','glass':'153038','silver':'7c999c','pink':'c75a7e','faded':'586b62','dirty':'7a8270',
'dimamber':'87633c','dimred':'512a2d','dimcyan':'335b64','offwhite':'94a8a2','neonorange':'ff9d44','neonwhite':'e1f8ee','orange':'d76f35','teal':'376c70'
}
keys=list(colors)
for i in range(16):
    v=0.035+i*.012;key='grain%02d'%i;colors[key]=tuple([v*.72,v*1.12,v*1.2]);keys.append(key)
W=16;H=16
pal=bpy.data.images.new('TD_Shared_Palette',width=256,height=256,alpha=True)
pix=[0.0]*(256*256*4)
for idx,key in enumerate(keys):
 c=colors[key]
 if isinstance(c,str):c=tuple(int(c[j:j+2],16)/255 for j in (0,2,4))
 for yy in range((idx//16)*16,(idx//16+1)*16):
  for xx in range((idx%16)*16,(idx%16+1)*16):
   off=(yy*256+xx)*4;pix[off:off+4]=[*c,1]
pal.pixels.foreach_set(pix);pal.filepath_raw=BASE+'/source/tower_palette.png';pal.file_format='PNG';pal.save();pal.pack()
M=[]
for name,metal,rough,coat,em in [('Metal',.82,.31,.15,0),('Matte',.03,.76,0,0),('WetPaint',.24,.22,.65,0),('Emission',0,.4,0,5.0)]:
 m=bpy.data.materials.new('TD_'+name);m.use_nodes=True;nt=m.node_tree;bs=nt.nodes.get('Principled BSDF')
 tex=nt.nodes.new('ShaderNodeTexImage');tex.image=pal;tex.interpolation='Closest'
 uv=nt.nodes.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';nt.links.new(uv.outputs[0],tex.inputs[0]);nt.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
 bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough;bs.inputs['Coat Weight'].default_value=coat
 if em:
  nt.links.new(tex.outputs['Color'],bs.inputs['Emission Color']);bs.inputs['Emission Strength'].default_value=em
 M.append(m)
# Direct mesh builder: only cuboids, no curves / cylinders / spheres / bevels / subdivision.
class Batch:
 def __init__(self,name,col,parent=None):self.name=name;self.col=col;self.parent=parent;self.v=[];self.f=[];self.ids=[];self.ks=[]
 def box(self,p,d,key='steel',mat=0,rot=None):
  idx=len(self.v);x,y,z=p;a,b,c=[v*.5 for v in d]
  vv=[(-a,-b,-c),(-a,-b,c),(-a,b,-c),(-a,b,c),(a,-b,-c),(a,-b,c),(a,b,-c),(a,b,c)]
  if rot is not None:vv=[rot@Vector(v) for v in vv]
  self.v.extend([(x+v[0],y+v[1],z+v[2]) for v in vv])
  faces=[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]
  for f in faces:self.f.append(tuple(idx+j for j in reversed(f)));self.ids.append(mat);self.ks.append(keys.index(key))
 def done(self):
  me=bpy.data.meshes.new('TD_'+self.name);me.from_pydata(self.v,[],self.f);me.materials.clear()
  for m in M:me.materials.append(m)
  me.polygons.foreach_set('material_index',self.ids)
  uv=me.uv_layers.new(name='PaletteUV');coords=[]
  for k in self.ks:
   u=(k%16+.5)/16;v=(k//16+.5)/16;e=.018
   coords.extend([u-e,v-e,u+e,v-e,u+e,v+e,u-e,v+e])
  uv.data.foreach_set('uv',coords);uv.active_render=True
  ob=bpy.data.objects.new('TD_'+self.name,me);self.col.objects.link(ob)
  if self.parent:ob.parent=self.parent
  ob['construction']='cuboids_only';ob['box_count']=len(self.v)//8
  return ob

def coll(name):
 c=bpy.data.collections.new('TD_'+name);s.collection.children.link(c);return c
C={name:coll(name) for name in ['01_远景楼群','02_主招牌','03_高架桥体','04_机电管线','05_桥下纵深','06_左侧店面','07_右侧街区','08_交通与路灯','09_湿路与人行道','10_车辆','11_无人机','12_雨纸动态','13_体积光雾','90_相机灯光']}
def empty(name,col,loc=(0,0,0)):
 o=bpy.data.objects.new('TD_'+name,None);col.objects.link(o);o.location=loc;return o

def rect(b,x,y,z,w,h,t=.06,key='steel',mat=0):b.box((x,y,z),(w,t,h),key,mat)
def frame(b,x,y,z,w,h,border=.06,depth=.08,key='steel',mat=0):
 for xx in [x-w/2,x+w/2]:b.box((xx,y,z),(border,depth,h+border),key,mat)
 for zz in [z-h/2,z+h/2]:b.box((x,y,zz),(w+border,depth,border),key,mat)
def pipe(b,points,width=.08,key='rust',mat=0):
 for p,q in zip(points[:-1],points[1:]):
  d=Vector(q)-Vector(p);mid=(Vector(p)+Vector(q))/2
  if sum(abs(v)>1e-5 for v in d)==1:dim=[max(abs(v),width) for v in d];b.box(mid,dim,key,mat)
  else:b.box(mid,(width,width,d.length),key,mat,Vector((0,0,1)).rotation_difference(d).to_matrix())
def light(name,loc,color,power,size=1,target=None,kind='AREA',size_y=None,angle=.8):
 d=bpy.data.lights.new('TD_'+name,kind);d.energy=power;d.color=color
 if kind=='AREA':d.shape='RECTANGLE';d.size=size;d.size_y=size_y if size_y is not None else size
 if kind=='SPOT':d.spot_size=angle;d.spot_blend=.65;d.shadow_soft_size=.15
 if kind=='POINT':d.shadow_soft_size=size
 o=bpy.data.objects.new('TD_'+name,d);C['90_相机灯光'].objects.link(o);o.location=loc
 if target:o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
 return o
font={
'A':['01110','11011','11011','11111','11011','11011','11011'],
'B':['11110','11011','11011','11110','11011','11011','11110'],
'C':['01111','11000','11000','11000','11000','11000','01111'],
'D':['11110','11011','11011','11011','11011','11011','11110'],
'E':['11111','11000','11000','11110','11000','11000','11111'],
'F':['11111','11000','11000','11110','11000','11000','11000'],
'G':['01111','11000','11000','11011','11011','11011','01110'],
'H':['11011','11011','11011','11111','11011','11011','11011'],
'I':['11111','00100','00100','00100','00100','00100','11111'],
'J':['00111','00011','00011','00011','11011','11011','01110'],
'K':['11011','11010','11100','11100','11100','11010','11011'],
'L':['11000','11000','11000','11000','11000','11000','11111'],
'M':['10001','11011','11111','10101','10001','10001','10001'],
'N':['11001','11101','11101','11011','11011','11011','11001'],
'O':['01110','11011','11011','11011','11011','11011','01110'],
'P':['11110','11011','11011','11110','11000','11000','11000'],
'Q':['01110','11011','11011','11011','11111','00110','00011'],
'R':['11110','11011','11011','11110','11100','11010','11011'],
'S':['01111','11000','11000','01110','00011','00011','11110'],
'T':['11111','00100','00100','00100','00100','00100','00100'],
'U':['11011','11011','11011','11011','11011','11011','01110'],
'V':['11011','11011','11011','11011','11011','01110','00100'],
'W':['10001','10001','10001','10101','10101','11011','10001'],
'X':['11011','11011','01110','00100','01110','11011','11011'],
'Y':['11011','11011','01110','00100','00100','00100','00100'],
'Z':['11111','00011','00110','00100','01100','11000','11111'],
'0':['01110','11011','11011','11011','11011','11011','01110'],
'1':['00100','01100','00100','00100','00100','00100','01110'],
'2':['01110','11011','00011','00110','01100','11000','11111'],
'3':['11110','00011','00011','01110','00011','00011','11110'],
'4':['11011','11011','11011','11111','00011','00011','00011'],
'5':['11111','11000','11000','11110','00011','00011','11110'],
'6':['01110','11000','11000','11110','11011','11011','01110'],
'7':['11111','00011','00110','00110','00100','00100','00100'],
'8':['01110','11011','11011','01110','11011','11011','01110'],
'9':['01110','11011','11011','01111','00011','00011','01110'],
'-':['00000','00000','00000','11111','00000','00000','00000'],
'.':['00000','00000','00000','00000','00000','00110','00110'],
' ':['00000']*7}
def textmesh(b,txt,x,y,z,h,key='ice',mat=3,step=None,scan=False):
 cell=h/7;advance=6*cell if step is None else step
 for ci,ch in enumerate(txt):
  for row,line in enumerate(font.get(ch.upper(),font[' '])):
   # Merge each horizontal lit run to preserve the striped tube typography.
   j=0
   while j<5:
    if line[j]=='0':j+=1;continue
    a=j
    while j<5 and line[j]=='1':j+=1
    xc=x+ci*advance+(a+j-1)*cell/2
    if scan:
     for dz in [-.26,.26]:rect(b,xc,y,z-row*cell+dz*cell,(j-a)*cell*.96,cell*.30,.055,key,mat)
    else:rect(b,xc,y,z-row*cell,(j-a)*cell*.96,cell*.86,.04,key,mat)
# SKYLINE
b=Batch('Skyline_silhouettes',C['01_远景楼群'])
for i in range(21):
 x=-50+i*5+random.uniform(-1,1);y=random.uniform(27,58);w=random.uniform(3.8,8);h=random.uniform(15,30)
 b.box((x,y,h/2),(w,random.uniform(5,11),h),random.choice(['navy','dark','wall','blue']),1)
 for zz in range(3,int(h),1):
  for xx in range(int(w/.5)-1):
   if random.random()<.65:rect(b,x-w/2+.4+xx*.5,y-5.65,zz,.14,.32,.03,random.choice(['dimcyan','blue2','dimamber','dark']),3 if random.random()<.08 else 1)
 for zz in range(4,int(h),4):b.box((x,y-5.72,zz),(w,.13,.1),'steel',0)
 # Rooftop water boxes and ventilation: angular silhouettes.
 b.box((x,y,h+.6),(w*.65,4,1.2),'dark',0)
b.done()
# STREET AND SIDEWALKS
b=Batch('Wet_asphalt_foundation',C['09_湿路与人行道']);b.box((0,8,-.22),(72,108,.4),'asphalt',2);b.done()
b=Batch('Road_pixel_surface_and_puddles',C['09_湿路与人行道'])
for i in range(14000):
 x=random.uniform(-22,22);y=random.uniform(-28,22)
 b.box((x,y,random.uniform(-.008,.004)),(random.uniform(.025,.15),random.uniform(.035,.24),.008),random.choice(['grain%02d'%i for i in range(1,13)]+['wet','wet2','black']),2 if random.random()<.8 else 1)
for i in range(400):
 x=random.uniform(-15,15);y=random.uniform(-25,18)
 b.box((x,y,.008),(random.uniform(.1,.65),random.uniform(.08,.5),.008),random.choice(['wet','window','blue','asphalt']),2)
for x in [-5.1,5.1]:
 for y in range(-26,45,5):
  for dy in range(14):
   if random.random()>.12:b.box((x,y+dy*.13,.018),(.11,.12,.008),random.choice(['pale','faded','paper']),1)
for x in [-11,11]:b.box((x,2,.025),(.08,53,.02),'dirty',1)
# Crossing marks visible under gate; worn, rectilinear.
for x in range(-9,10,2):
 for i in range(8):
  b.box((x+random.uniform(-.02,.02),-1.6+i*.2,.02),(.86,.16,.015),'faded',1)
b.done()
b=Batch('Sidewalk_tiles_and_curb',C['09_湿路与人行道'])
for side in [-1,1]:
 b.box((side*19,5,.13),(13,49,.26),'grout',1)
 for x in [side*(12.4+i*.61) for i in range(22)]:
  for y in [i*.81-18 for i in range(60)]:b.box((x,y,.28),(.59,.79,.1),random.choice(['wall','wall2','tile','steel','faded']),1)
 for y in [i*.65-18 for i in range(72)]:b.box((side*12.0,y,.2),(.23,.61,.4),random.choice(['pale','steel2','dirty']),1)
 for i in range(1300):
  x=side*random.uniform(12,23);y=random.uniform(-15,17)
  b.box((x,y,.35),(random.uniform(.04,.22),random.uniform(.05,.24),random.uniform(.01,.035)),random.choice(['paper','pale','offwhite','dirty']),1)
 for y in [-6,3,10]:
  b.box((side*12.5,y,.35),(.75,.8,.05),'black',0)
  for k in range(7):b.box((side*12.5,y-.32+k*.1,.39),(.7,.035,.03),'steel',0)
b.done()
# Bridge support geometry. Open tunnel is genuine geometry with no backplate.
b=Batch('Bridge_deck_and_piers',C['03_高架桥体'])
b.box((0,8.2,8.05),(43,7,2.15),'dark',0)
b.box((0,4.49,9.17),(43,.5,.28),'steel2',0)
b.box((0,4.39,9.42),(43,.3,.16),'pale',0)
b.box((0,4.24,9.32),(43,.12,.06),'warm',3)
b.box((0,4.4,6.96),(43,.3,.24),'black',0)
for x in [-9.2,12.8]:
 b.box((x,8,3.45),(2.8,7,6.9),'wall',1)
 b.box((x,4.32,3.4),(2.95,.23,6.7),'dark',0)
 for dx in [-1.25,1.25]:b.box((x+dx,4.11,3.4),(.16,.13,6.7),'steel2',0)
 b.box((x,4.1,.55),(3.2,.6,1.1),'steel',0)
 for z in [.9,2.4,4.4,6.7]:frame(b,x,3.99,z,2.7,.3,.05,.05,'steel2')
for x in [i*.48-21 for i in range(89)]:
 b.box((x,4.28,8.72),(.035,.08,.85),'steel',0)
 if random.random()<.6:b.box((x,4.2,9.08-random.random()*.35),(.018,.035,random.uniform(.12,.65)),random.choice(['rust','dirty','rust2']),1)
for i in range(620):
 x=random.uniform(-21,21);b.box((x,4.4+random.uniform(-.1,.5),9.55),(random.uniform(.05,.35),random.uniform(.07,.4),random.uniform(.02,.09)),random.choice(['paper','pale','dirty','offwhite']),1)
b.done()
# Signs. Each letter is an editable component with its own frame and striped glyph.
chars='TOWER DISTRICT';step=1.98;start=-11.72
for i,ch in enumerate(chars):
 x=start+i*step;z=11.1
 b=Batch('Marquee_%02d_%s'%(i,ch if ch!=' ' else 'blank'),C['02_主招牌'])
 b.box((x,5.1,z),(1.86,.6,3.08),'ochre',0);rect(b,x,4.75,z,1.60,2.67,.08,'dark',1)
 frame(b,x,4.67,z,1.66,2.79,.07,.09,'copper');frame(b,x,4.61,z,1.5,2.62,.025,.04,'steel2')
 for xx in [-.83,.83]:
  for zz in [-1.12,1.12]:b.box((x+xx,4.56,z+zz),(.07,.05,.09),'gold',0)
 b.box((x,5.1,12.75),(1.5,.58,.14),'steel',0)
 if ch!=' ':textmesh(b,ch,x-.64,4.50,12.22,2.45,'neonorange',3,scan=True)
 else:frame(b,x,4.48,z,1.22,2.1,.025,.04,'rust')
 b.done()
# Back deck blocks behind sign.
b=Batch('Marquee_mounts_and_pipework',C['02_主招牌'])
for x in range(-16,18,2):
 b.box((x,5.55,10.3),(.18,.5,2),'steel',0)
 b.box((x,5.9,9.9),(1.9,.12,.11),'black',0)
b.done()
# Dense utilities: mains, stepped conduit offsets, cabinets and screws.
b=Batch('Continuous_rectangular_conduits',C['04_机电管线'])
for zi,z in enumerate([7.15,7.42,7.73,8.08]):
 pts=[(-18,4.03,z),(-9+zi*.4,4.03,z),(-9+zi*.4,4.03,z-.18),(-3,4.03,z-.18),(-3,4.03,z+.1),(6,4.03,z+.1),(6,4.03,z),(19,4.03,z)]
 pipe(b,pts,.07 if zi%2 else .13,'rust' if zi<2 else 'steel')
 for x in range(-18,20,2):b.box((x,3.91,z),(.12,.26,.26),'copper',0)
pipe(b,[(-18,4.0,8.55),(-12,4,8.55),(-12,4,8.34),(-4,4,8.34),(-4,4,7.92),(0,4,7.92)],.14,'black')
pipe(b,[(7,4,8.45),(10.5,4,8.45),(10.5,4,8.65),(16.5,4,8.65),(16.5,4,8.1),(18,4,8.1)],.17,'black')
for i in range(55):
 x=random.uniform(-19,19);z=random.uniform(7.1,8.4)
 if -1<x<1:continue
 w=random.uniform(.18,.58);h=random.uniform(.18,.55)
 b.box((x,3.88,z),(w,.21,h),random.choice(['steel','rust','ochre','dark']),0);frame(b,x,3.74,z,w*.84,h*.8,.025,.035,'steel2')
 if random.random()<.45:
  for j in range(3):rect(b,x-w*.26+j*w*.26,3.70,z,.022,h*.43,.025,'pale',1)
for x in [-10,-1.6,9.8,16.7]:
 b.box((x,3.89,6.99),(.85,.24,.42),'rust',0);frame(b,x,3.73,6.99,.72,.31,.04,.04,'copper')
 for j in range(6):rect(b,x-.25+j*.1,3.69,6.99,.04,.13,.02,'dimamber',3)
b.done()
# Aircon machines; a stepped square annulus instead of circular blades.
for i,x in enumerate([-11.7,-10.1,-8.7,11.8,13.5,16.0]):
 b=Batch('Cooling_unit_%02d'%i,C['04_机电管线']);z=8.05
 b.box((x,3.9,z),(1.25,.7,.85),'steel2',0);frame(b,x,3.49,z,1.15,.75,.05,.08,'edge')
 if i%2:
  for j in range(8):rect(b,x,3.42,z-.31+j*.088,1.03,.032,.02,'black',1)
  rect(b,x-.43,3.38,z+.22,.07,.09,.03,'redmid',3)
 else:
  rect(b,x,3.42,z,.66,.66,.04,'black',1)
  for rr in [.3,.22,.14]:frame(b,x,3.36,z,rr*2,rr*2,.028,.03,'steel')
  rect(b,x,3.30,z,.12,.12,.06,'edge',0)
  for dx in [-.47,.47]:
   for dz in [-.28,.28]:rect(b,x+dx,3.34,z+dz,.045,.045,.03,'pale',0)
 b.done()
for i,x in enumerate([-4.75,6.1]):
 b=Batch('Red_warning_bank_%d'%i,C['04_机电管线']);z=7.85
 rect(b,x,3.50,z,2.85,.85,.30,'steel',0);frame(b,x,3.30,z,2.82,.83,.07,.09,'rust2')
 for j in range(4):
  xx=x-1.02+j*.68;rect(b,xx,3.22,z,.54,.56,.06,'redmid',3);frame(b,xx,3.17,z,.50,.53,.04,.04,'copper')
  for d in range(5):
   for sign in [-1,1]:rect(b,xx+(d-2)*.062,3.12,z+sign*(d-2)*.066,.064,.065,.02,'redhot',3)
 b.done()
b=Batch('Facade_micro_paneling',C['04_机电管线'])
for i in range(110):
 x=random.uniform(-17,18);z=random.uniform(7.0,8.65)
 if random.random()<.45:
  for j in range(5):rect(b,x,3.66,z+j*.045,.21,.012,.025,'black',1)
 else:
  rect(b,x,3.62,z,.11,.085,.02,'gold',0)
  rect(b,x,3.60,z,.04,.035,.02,'black',1)
for i in range(300):
 x=random.uniform(-20,20);z=random.uniform(8.4,9.05)
 rect(b,x,4.19,z,random.uniform(.01,.08),random.uniform(.01,.2),.012,random.choice(['rust','steel','dirty']),1)
b.done()
# Underpass receding walls and ceiling ribs.
b=Batch('Underpass_architecture',C['05_桥下纵深'])
for x in [-7.6,11.2]:
 b.box((x,24,3.25),(.4,32,6.5),'navy',1)
 for y in range(10,42,4):
  b.box((x,y,3.2),(.6,.3,6.4),'steel',0)
  b.box((x,y,1.1),(.65,.5,1.2),'dark',0)
for y in range(12,40,4):
 b.box((0,y,6.85),(23,.35,.3),'black',0)
 for x in [-8.8,8.8]:b.box((x,y,6.68),(.24,1.2,.09),'dimcyan',3)
for x in [-5,0,5]:
 for y in range(9,55,5):b.box((x,y,.025),(.09,1.8,.025),'steel2',1)
b.done()
for side in [-1,1]:
 for y in [12,21,30]:
  light('Tunnel_wall_%d_%d'%(side,y),(side*10.7,y,4),(.45,.65,.65),100,1,(side*11.2,y,2.5))
# Left storefront.
b=Batch('Left_shop_architecture',C['06_左侧店面'])
b.box((-18,6,4.25),(9,9,8.5),'dark',1)
# wall tiled facade
for ix in range(36):
 for iz in range(29):
  x=-22+ix*.24;z=.4+iz*.235
  b.box((x,1.45,z),(.226,.11,.218),random.choice(['wall','tile','wall2','steel']),1)
for x in [-20.3,-16.2,-13.8]:
 rect(b,x,1.31,2.8,1.9,4.9,.08,'black',1);frame(b,x,1.20,2.8,1.9,4.9,.11,.12,'steel2')
 for j in range(19):rect(b,x,1.15,.6+j*.23,1.68,.035,.03,'steel',0)
# Main shop glass panel
rect(b,-18.0,1.12,3.6,2.4,3.1,.08,'window',2)
frame(b,-18,1.03,3.6,2.4,3.1,.12,.12,'steel2')
for x in [-18.6,-17.4]:rect(b,x,.98,3.6,.05,3.0,.03,'edge',0)
b.box((-17.8,.7,6.5),(9.5,2.0,1.72),'black',0)
# Layered striped awning. Side return faces have the same stacked bands.
for z,h,key in [(7.16,.12,'ice'),(6.98,.27,'white'),(6.7,.16,'blue2'),(6.38,.46,'orange'),(6.04,.16,'white'),(5.81,.22,'greendark'),(5.63,.12,'white')]:
 b.box((-17.8,-.33,z),(9.45,.10,h),key,3 if key=='ice' else 1)
 b.box((-13.05,.65,z),(.12,1.9,h),key,1)
textmesh(b,'SEVEN',-15.5,-.4,6.52,.37,'cream',1)
for x in [-22.4,-19.8,-13.1]:b.box((x,-.39,6.4),(.08,.14,1.65),'steel2',0)
b.done()
b=Batch('Left_recessed_shop_annex',C['06_左侧店面'])
b.box((-11.3,6,3.3),(3.4,5,6.6),'dark',1)
for x in [-12.65,-11.85,-11.05,-10.25]:
 rect(b,x,3.38,3.05,.72,5.7,.08,'window',2);frame(b,x,3.29,3.05,.72,5.7,.06,.08,'steel')
 for z in [.6,4.9,5.6]:rect(b,x,3.23,z,.68,.05,.03,'steel2',0)
rect(b,-11.5,3.19,4.65,.82,.52,.1,'rust',0)
for dx in [-.17,.17]:
 for dz in [-.1,.1]:rect(b,-11.5+dx,3.12,4.65+dz,.07,.08,.03,'redmid',3)
b.done()
# LIQUOR vertical sign and red chevrons.
b=Batch('LIQUOR_vertical_marquee',C['06_左侧店面']);x=-14.5;y=-.95;z=7.75
b.box((x,y+.15,z),(1.22,.45,5.0),'black',0);frame(b,x,y-.13,z,1.18,4.98,.06,.07,'cyan',3);frame(b,x,y-.19,z,1.04,4.83,.03,.04,'pale',0)
for i,ch in enumerate('LIQUOR'):textmesh(b,ch,x-.36,y-.24,9.83-i*.76,.57,'ice',3)
for zz in [10.8,11.28]:
 for i in range(5):
  for sign in [-1,1]:rect(b,x+sign*i*.082,y-.24,zz+i*.07,.085,.09,.04,'redhot',3)
pipe(b,[(x,0,5.2),(x,0,4.9),(x+.3,0,4.9),(x+.3,0,4.5)],.065,'rust')
b.done()
# ATM and terminal.
b=Batch('ATM_and_posters',C['06_左侧店面'])
rect(b,-16.2,1.03,3.15,1.6,2.05,.3,'rust',0);frame(b,-16.2,.83,3.15,1.56,2.0,.1,.09,'steel2')
rect(b,-16.2,.73,3.35,.85,.63,.10,'black',0);rect(b,-16.2,.66,3.35,.62,.43,.02,'violet',3)
for j in range(3):
 for k in range(4):rect(b,-16.42+k*.15,.62,3.45-j*.12,.065,.055,.015,'ice',3)
b.box((-16.2,.61,2.8),(.95,.35,.10),'silver',0);rect(b,-16.2,.43,2.59,.57,.065,.05,'black',1)
rect(b,-16.2,.91,4.9,2.15,.83,.13,'black',0);frame(b,-16.2,.8,4.9,2.13,.80,.04,.05,'redmid',3);textmesh(b,'ATM',-17.1,.73,5.18,.65,'red',3)
for i in range(13):
 x=random.uniform(-22,-13.5);z=random.uniform(.7,3.3)
 if abs(x+20.1)<1.2:continue
 rect(b,x,1.02,z,random.uniform(.25,.65),random.uniform(.35,.9),.02,random.choice(['dirty','paper','ochre']),1)
 for k in range(4):rect(b,x,1.0,z+k*.06-.1,.15,.015,.01,'steel',1)
b.done()
b=Batch('Information_terminal',C['06_左侧店面']);x=-10.6;y=1.1
b.box((x,y,.55),(.55,.65,1.1),'dark',0);b.box((x,y,1.99),(1.15,.66,1.8),'steel2',0);frame(b,x,y-.37,2.0,1.05,1.73,.06,.1,'edge')
rect(b,x,y-.42,2.15,.89,1.2,.05,'paper',1);rect(b,x,y-.46,2.94,1.20,.22,.05,'cyan',3)
textmesh(b,'WOW',x-.47,y-.50,3.0,.16,'ice',3)
rect(b,x-.14,y-.49,2.48,.51,.38,.03,'black',1);textmesh(b,'24',x-.34,y-.53,2.6,.25,'ice',3)
rect(b,x+.33,y-.49,2.47,.16,.52,.03,'ice',3)
for iz in range(5):
 for ix in range(6):rect(b,x-.37+ix*.15,y-.51,2.03-iz*.12,.11,.08,.02,random.choice(['ice','gold','steel','paper','blue2']),1)
b.done()
# Right facades, fan and inset doors.
b=Batch('Right_shop_walls',C['07_右侧街区'])
b.box((18.6,7,4.55),(10,10,9.1),'dark',1);b.box((23.5,8,12),(6,12,24),'navy',1)
for xx in [14,16.3,19.2,22.4]:
 b.box((xx,1.86,4.5),(.24,.35,8.9),'steel',0)
 rect(b,xx+1.0,1.90,2.9,1.65,4.9,.08,'window',2);frame(b,xx+1,1.74,2.9,1.65,4.9,.09,.1,'steel2')
 for z in [.6,1.2,4.9]:rect(b,xx+1,1.67,z,1.57,.06,.05,'steel',0)
for z in [6.25,7.1,8.9,11.1]:b.box((19,1.78,z),(11,.18,.14),'steel',0)
for i in range(5):
 xx=14.3+i*1.3;rect(b,xx,1.58,6.9,1.1,.94,.36,'steel2',0);rect(b,xx,1.36,6.9,.85,.77,.08,'black',1)
 for rr in [.34,.27,.20,.13]:frame(b,xx,1.28,6.9,2*rr,2*rr,.025,.025,'steel2')
# two wall cabinets
for x in [14.4,18.5]:
 rect(b,x,1.4,2.0,.75,1.65,.32,'steel2',0);frame(b,x,1.19,2,.65,1.52,.04,.05,'edge')
 for iz in range(7):rect(b,x,1.13,2.35-iz*.15,.4,.04,.03,'black',1)
 rect(b,x+.19,1.09,1.5,.045,.08,.02,'red',3)
b.done()
# Right roadside text sign
b=Batch('Right_signs_and_small_adverts',C['07_右侧街区'])
rect(b,15.4,.88,3.1,.95,2.7,.19,'paper',1);frame(b,15.4,.74,3.1,.94,2.68,.04,.05,'rust')
textmesh(b,'P',15.14,.69,4.22,.56,'blue2',1)
for i,txt in enumerate(['TRUCK','LOADING','ONLY','NO','ENTRY']):textmesh(b,txt,15.04,.69,3.5-i*.32,.14,'dark',1)
pipe(b,[(15.2,.65,2.02),(15.65,.65,2.02),(15.65,.65,2.12)],.04,'redmid')
rect(b,18.2,1.29,9.2,4.1,1.45,.3,'black',0);frame(b,18.2,1.08,9.2,4.0,1.35,.04,.08,'steel2');textmesh(b,'SECTOR.',16.36,1.0,9.48,.64,'ice',3)
for x in [16.6,17,17.4]:rect(b,x,1.25,3.2,.23,.21,.06,'warm',3)
b.done()
# Cropped rooftop billboards.
b=Batch('Rooftop_advertisements',C['07_右侧街区'])
for x,w in [(10.4,3.3),(13.4,1.5),(15.5,2.3),(20.3,2.6)]:
 b.box((x,5.4,14.1),(w,.55,1.7 if x<18 else 5.4),'black',0);frame(b,x,5.06,14.1,w-.12,1.57 if x<18 else 5.2,.08,.12,'steel2')
 for dx in [-w*.4,w*.4]:b.box((x+dx,5.5,12.7),(.1,.12,1.5),'steel',0)
rect(b,10.4,4.98,14.1,3.05,1.35,.04,'cyan',3)
textmesh(b,'HI-FI',9.17,4.91,14.58,.38,'dark',1)
for x in [9.6,11.2]:
 rect(b,x,4.91,13.91,.64,.55,.03,'black',1)
 for rr in [.22,.15,.08]:frame(b,x,4.87,13.91,rr*2,rr*2,.035,.03,'ice',3)
for j in range(6):rect(b,10.4,4.88,13.78+j*.07,.65,.025,.02,'dark',1)
rect(b,13.4,4.98,14.1,1.25,1.35,.04,'warm',3)
for z,w,key in [(13.8,.97,'orange'),(13.97,1.05,'brown'),(14.14,1.0,'green'),(14.3,.85,'gold'),(14.44,.58,'gold')]:rect(b,13.4,4.9,z,w,.14,.04,key,1)
rect(b,15.5,4.98,14.1,2.05,1.35,.04,'redmid',3);textmesh(b,'RUSH',14.61,4.88,14.43,.60,'warm',3)
for j,ch in enumerate('VINYL'):textmesh(b,ch,19.9,4.97,16.05-j*.88,.72,'yellow',3)
b.done()
# Traffic standards and overhead street lamps.
for side in [-1,1]:
 x=(-9.15 if side<0 else 12.8);y=2.1
 b=Batch('Traffic_standard_%s'%side,C['08_交通与路灯'])
 b.box((x,y,3.1),(.15,.20,6.2),'steel',0);b.box((x,y,.3),(.45,.5,.6),'steel2',0)
 pipe(b,[(x,y,5.8),(x,y,7.95),(x-side*.3,y,7.95)],.13,'steel2')
 b.box((x-side*.25,y-.16,7.8),(.62,.46,.4),'dark',0);rect(b,x-side*.25,y-.42,7.68,.37,.13,.06,'ice',3)
 xx=x+side*.78
 pipe(b,[(x,y,6.7),(xx,y,6.7),(xx,y,4.2)],.08,'copper')
 rect(b,xx,y-.13,5.25,.64,1.91,.35,'ochre',0);frame(b,xx,y-.36,5.25,.58,1.84,.06,.08,'gold')
 for zz in [4.85,5.65]:
  rect(b,xx,y-.44,zz,.46,.61,.12,'greendark',0);frame(b,xx,y-.52,zz,.41,.54,.035,.05,'green',3);rect(b,xx,y-.57,zz,.27,.36,.04,'greenhot',3)
 rect(b,xx,y-.56,4.48,.32,.13,.03,'amber',3)
 b.done()
 light('Cold_downlight_%s'%side,(x-side*.22,y-.24,7.45),(.58,.84,1),2000,.6,(x-1.4*side,-1.7,0),kind='SPOT',angle=.9)
 light('Green_spill_%s'%side,(xx,y-.9,5.2),(.4,1,.23),90,.5,kind='POINT')
# Road dividers / railings, left foreground.
b=Batch('Foreground_road_divider',C['09_湿路与人行道'])
for y in [-17+i*1.9 for i in range(12)]:
 x=-11.7
 b.box((x,y,.7),(.28,1.85,1.35),'black',0);frame(b,x+.16,y,.7,.04,1.1,.04,.04,'steel')
 b.box((x+.18,y,.18),(.04,1.75,.05),'rust2',0)
 b.box((x,y+.89,.8),(.42,.10,1.6),'steel',0)
b.done()
# Pixel cars: body/roof tiering, voxel tire silhouette, paneled windows.
def car(name,loc,body='car',scale=1,angle=0,tail=True):
 root=empty(name,C['10_车辆'],loc);root.scale=(scale,)*3;root.rotation_euler.z=angle
 b=Batch(name+'_body',C['10_车辆'],root)
 b.box((0,0,.78),(2.30,4.60,.65),body,2);b.box((0,0,.50),(2.22,4.5,.28),'black',0)
 b.box((0,-1.65,1.17),(2.25,1.25,.16),body,2);b.box((0,1.58,1.18),(2.24,1.4,.16),body,2)
 # stepped roof and window rake
 for k in range(18):
  b.box((0,-.12,1.28+k*.035),(2.15-k*.017,2.65-k*.061,.036),'glass',2)
 b.box((0,-.12,1.94),(1.85,1.55,.12),body,2)
 for side in [-1,1]:
  b.box((side*1.12,0,.94),(.05,3.45,.035),'edge',0)
  for yy in [-.95,.89]:
   b.box((side*.96,yy,1.52),(.10,.10,.85),body,0)
  b.box((side*1.03,-.11,1.56),(.08,.12,.7),body,0)
  b.box((side*1.23,.8,1.35),(.31,.30,.14),body,0)
  for yy in [-.62,.6]:b.box((side*1.16,yy,1.10),(.035,.20,.06),'silver',0)
  # Tire stepped profile in yz-plane, all square blocks.
  for yy in [-1.48,1.45]:
   for a in range(-3,4):
    for c in range(-3,4):
     if abs(a)+abs(c)>4:continue
     b.box((side*1.1,yy+a*.13,.46+c*.13),(.22,.135,.135),'tire',1)
   b.box((side*1.23,yy,.46),(.03,.34,.34),'steel',0)
   b.box((side*1.255,yy,.46),(.025,.17,.17),'edge',0)
 # roof trim and rear glass lines
 for k in range(5):b.box((0,-1.42+k*.13,1.30+k*.14),(1.80-k*.025,.012,.009),'steel',0)
 b.box((0,-2.34,.64),(2.34,.13,.18),'steel',0)
 b.box((0,2.32,.65),(2.32,.12,.18),'steel',0)
 rect(b,0,-2.42,.91,.51,.21,.04,'dark',1)
 for j in range(5):rect(b,-.18+j*.08,-2.45,.91,.035,.09,.02,'paper',1)
 for side in [-1,1]:
  for i in range(4):rect(b,side*(.69+i*.12),-2.36,1.03,.11,.17,.05,'redhot' if i<3 else 'red',3)
  for i in range(3):rect(b,side*.99,-2.36,.83+i*.09,.12,.09,.05,'red',3)
  b.box((side*.81,2.34,1.0),(.45,.06,.18),'warm',3)
  # seams
  rect(b,side*.6,-2.36,1.19,.65,.02,.025,'black',0)
 b.done()
 if tail:
  for side in [-1,1]:
   l=light(name+'_brake_spill'+str(side),(0,0,0),(1,.035,.04),30,.25,kind='POINT');l.parent=root;l.location=(side*.83,-2.55,.72)
 return root
car('Car_left_mid',(-5.8,-8.3,0),'car',1.22,-.035)
car('Car_center_mid',(2.5,-8.0,0),'car2',1.24,.07)
car('Car_right_brown',(10.2,-8.5,0),'brown',1.30,-.26)
car('Car_right_crop',(16.0,-10.3,0),'rust',1.22,-.20)
car('Car_foreground_left',(-5.8,-19.4,0),'black',1.45,.03)
car('Car_foreground_right',(5.2,-19.3,0),'black',1.40,-.1)
for i,(x,y) in enumerate([(-5,17),(1,23),(6,30)]):
 root=car('Tunnel_vehicle_%d'%i,(x,y,0),'dark',.90,0,False)
 root.driver_add('location',1).driver.expression=str(y)+'+3*sin((frame-1)*2*pi/240+'+str(i)+')'
# DRONE, four square raster annuli, angular cockpit, articulated rectangular blades.
drone=empty('Drone_hover_ROOT',C['11_无人机'],(3.4,1.0,11.3));drone.rotation_euler=(.67,-.10,-.16)
b=Batch('Drone_hull',C['11_无人机'],drone)
b.box((0,0,0),(1.16,2.1,.62),'steel2',0);b.box((0,-.38,-.28),(.95,1.15,.36),'steel',0)
for k in range(4):b.box((0,-.67-k*.12,.14-k*.1),(1.0-k*.05,.16,.6),'blue2',0)
rect(b,0,-1.24,-.05,.78,.45,.09,'black',2)
for j in range(7):rect(b,-.30+j*.10,-1.31,.21,.05,.09,.03,'ice',1)
rect(b,0,-1.33,-.31,.72,.12,.04,'redhot',3)
for side in [-1,1]:
 pipe(b,[(side*.42,-.3,-.28),(side*.65,-.3,-.70),(side*.65,.55,-.70)],.09,'black')
 for y in [-.61,.73]:
  pipe(b,[(side*.45,y,.10),(side*1.2,y,.10),(side*1.5,y,.25)],.14,'steel2')
for k in range(5):b.box((0,.44+k*.16,.36),(.65,.06,.05),'black',0)
b.box((0,.7,.7),(.17,.15,.65),'steel',0);b.box((0,.7,1.03),(.45,.27,.10),'ice',0)
b.done()
for i,(x,y) in enumerate([(-1.45,-.6),(1.45,-.6),(-1.45,.85),(1.45,.85)]):
 b=Batch('Drone_rotor_guard_%d'%i,C['11_无人机'],drone)
 # square-grid annulus, circle-like overall silhouette via square steps, never curved faces.
 for ix in range(-5,6):
  for iy in range(-5,6):
   rr=ix*ix+iy*iy
   if 15<=rr<=29:
    b.box((x+ix*.115,y+iy*.115,.3),(.116,.116,.12),'steel2',0)
    if iy<0:b.box((x+ix*.115,y+iy*.115,.38),(.116,.116,.025),'edge',0)
 b.box((x,y,.31),(.20,.20,.25),'blue2',0);b.done()
 rotor=empty('Rotor_spin_%d'%i,C['11_无人机']);rotor.parent=drone;rotor.location=(x,y,.45)
 b=Batch('Rotor_blades_%d'%i,C['11_无人机'],rotor);b.box((0,0,0),(.90,.10,.035),'black',0);b.box((0,0,.01),(.10,.90,.035),'black',0);b.done()
 rotor.driver_add('rotation_euler',2).driver.expression='(frame-1)*%s'%(.71 if i%2 else -.71)
drone.driver_add('location',2).driver.expression='10.9+0.13*sin((frame-1)*2*pi/240)'
drone.driver_add('location',0).driver.expression='3.4+0.12*sin((frame-1)*2*pi/240)'
drone.driver_add('rotation_euler',1).driver.expression='-0.1+0.045*sin((frame-1)*2*pi/240)'
scan=light('Drone_red_downwash',(3.4,.4,10.7),(1,.035,.045),7500,.5,(2.8,.1,0),kind='SPOT',angle=.65)
scan.parent=drone;scan.location=(0,-.65,-.5);scan.rotation_euler=(-.67,-.06,0)
light('Drone_cool_rim',(5,-4,15),(.55,.82,1.0),1000,5,(3.4,1,11.3))
# Scattering volumes using rectangular bounds and animated 4D noise.
def volume(name,loc,dim,density,color,noise_scale=None):
 mat=bpy.data.materials.new('TD_Volume_'+name);mat.use_nodes=True;nt=mat.node_tree;nt.nodes.clear();out=nt.nodes.new('ShaderNodeOutputMaterial');v=nt.nodes.new('ShaderNodeVolumePrincipled');v.inputs['Color'].default_value=(*color,1);v.inputs['Anisotropy'].default_value=.25;nt.links.new(v.outputs['Volume'],out.inputs['Volume'])
 if noise_scale:
  tex=nt.nodes.new('ShaderNodeTexNoise');tex.noise_dimensions='4D';tex.inputs['Scale'].default_value=noise_scale;tex.inputs['Detail'].default_value=3
  tex.inputs['W'].driver_add('default_value').driver.expression='.5+.25*sin((frame-1)*2*pi/240)'
  ramp=nt.nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.32;ramp.color_ramp.elements[1].position=.72
  ramp.color_ramp.elements[0].color=(0,0,0,1);ramp.color_ramp.elements[1].color=(density,density,density,1)
  nt.links.new(tex.outputs['Fac'],ramp.inputs[0]);nt.links.new(ramp.outputs[0],v.inputs['Density'])
 else:v.inputs['Density'].default_value=density
 b=Batch('Volume_'+name,C['13_体积光雾']);b.box(loc,dim,'black',1);ob=b.done();ob.data.materials.clear();ob.data.materials.append(mat)
 for p in ob.data.polygons:p.material_index=0
 ob.display_type='WIRE';return ob
volume('Global_cold_haze',(0,22,12),(110,110,32),.0035,(.48,.66,.72))
volume('Left_exhaust',(-9.4,2,3.6),(4.8,5,6.8),.17,(.61,.76,.79),2.9)
volume('Right_exhaust',(13.3,2.6,3.9),(5.5,5,7.2),.17,(.57,.74,.79),2.8)
volume('Red_scan_dust',(3.4,.8,5.2),(4,5,10),.065,(.85,.60,.56),2.0)
volume('Tunnel_fog',(0,34,3.7),(23,24,7),.045,(.36,.56,.61),1.8)
volume('Above_sign_warm_haze',(1,14,16),(25,12,12),.018,(.72,.57,.47),2.0)
# Rain cuboids grouped into cyclic layers; paper squares each have their own wind motion.
for j in range(18):
 b=Batch('Rain_layer_%02d'%j,C['12_雨纸动态'])
 for i in range(35):
  x=random.uniform(-24,24);y=random.uniform(-13,20);z=random.uniform(0,18)
  b.box((x,y,z),(random.uniform(.008,.018),.012,random.uniform(.07,.20)),random.choice(['dimcyan','pale','steel2','ice']),1)
 ob=b.done();phase=j/18
 ob.driver_add('location',2).driver.expression='-2*((((frame-1)/24)+'+str(phase)+')%1)'
for i in range(24):
 b=Batch('Wind_paper_%02d'%i,C['12_雨纸动态']);b.box((0,0,0),(random.uniform(.05,.15),.012,random.uniform(.07,.18)),'paper',1);ob=b.done()
 x=random.uniform(-18,18);y=random.uniform(-1,20);z=random.uniform(.4,8);ob.location=(x,y,z);ob.rotation_euler=(.2,0,random.random())
 ob.driver_add('location',0).driver.expression=str(x)+'+.25*sin((frame-1)*2*pi/240+'+str(i)+')'
 ob.driver_add('location',2).driver.expression=str(z)+'+.15*cos((frame-1)*2*pi/240+'+str(i)+')'
 ob.driver_add('rotation_euler',1).driver.expression='.4*sin((frame-1)*2*pi/120+'+str(i)+')'
# Lighting: cold fill, warm horizontal marquee, central downwash.
light('Cold_sky_softbox',(-4,-2,21),(.28,.56,.69),5500,24,(0,5,0),size_y=16)
light('Front_soft_fill',(-1,-21,12),(.26,.52,.61),1800,24,(0,4,6),size_y=10)
for x in [-9,-2,5,12]:light('Marquee_amber_wash_'+str(x),(x,3.7,11.0),(1,.37,.12),650,5.7,(x,3.1,7.0),size_y=2.5)
light('Bridge_edge_wash',(0,3.7,9.3),(1,.53,.24),1000,28,(0,2.5,6.5),size_y=.3)
light('Warm_far_city',(0,23,18),(1,.40,.20),7000,15,(0,5,12),size_y=10)
light('Tunnel_exit_cyan',(0,45,6),(.25,.56,.66),3500,15,(0,20,2),size_y=6)
light('Left_store_spill',(-18,-.5,6),(.54,.80,.78),500,5,(-17,-2,0),size_y=1)
light('ATM_screen_spill',(-20,.3,3.3),(.35,.5,1),40,.4,kind='POINT')
light('Terminal_spill',(-10.6,.3,2.5),(.48,.79,1),45,.5,kind='POINT')
# Camera locked to reference framing; second inspection camera provided later.
cd=bpy.data.cameras.new('TD_Reference_Camera');cam=bpy.data.objects.new('TD_Reference_Camera',cd);C['90_相机灯光'].objects.link(cam)
cam.location=(0,-44,4.4);target=Vector((0,6,5.4));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cd.lens=42.5;cd.sensor_width=36;cd.clip_end=250
s.camera=cam;cd.dof.use_dof=True;cd.dof.focus_distance=49;cd.dof.aperture_fstop=3.2
# New compositor API (Blender 5); glare remains subtle enough to preserve striped letters.
nt=bpy.data.node_groups.new('TD_Cinematic_Compositor','CompositorNodeTree');s.compositing_node_group=nt
nt.interface.new_socket(name='Image',in_out='OUTPUT',socket_type='NodeSocketColor')
rl=nt.nodes.new('CompositorNodeRLayers');rl.scene=s
out=nt.nodes.new('NodeGroupOutput');gl=nt.nodes.new('CompositorNodeGlare');gl.inputs['Type'].default_value='Fog Glow';gl.inputs['Quality'].default_value='High'
gl.inputs['Threshold'].default_value=1.2;gl.inputs['Strength'].default_value=.65;gl.inputs['Size'].default_value=.32
nt.links.new(rl.outputs['Image'],gl.inputs['Image']);nt.links.new(gl.outputs['Image'],out.inputs['Image'])
# Easy navigation and authored scene notes.
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':
  area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL'
s['Reference']='codex-clipboard-870292bc-3d91-4ec4-aa63-bc58500cf313.jpg'
s['Scope']='Complete visible district except people; cuboid geometry; animated drone/rain/steam/paper/tunnel cars.'
s['Animation']='1–240 at 24 fps; procedural 10-second cycle. Rotor angular motion is continuous.'
s.frame_set(1);s.render.filepath=BASE+'/previews/02_composition.png'
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/source/tower_district_v002.blend')
print(json.dumps({'objects':len(s.objects),'mesh_objects':sum(o.type=='MESH' for o in s.objects),'boxes':sum(o.get('box_count',0) for o in s.objects),'file':bpy.data.filepath,'camera':list(cam.location)},ensure_ascii=False))

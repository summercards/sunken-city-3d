import bpy,math,json,os
from mathutils import Vector
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district'
s=bpy.context.scene
# Settle the traffic framing and foreground occlusion to the reference.
for name,loc in [('Car_left_mid',(-4.9,-7.8,0)),('Car_right_brown',(9.4,-7.7,0)),('Car_foreground_left',(-4.4,-26.7,0)),('Car_foreground_right',(2.6,-26.5,0))]:bpy.data.objects['TD_'+name].location=loc
s.view_settings.exposure=0
for l in s.objects:
 if l.type=='LIGHT':
  if l.name.startswith('TD_Front_soft_fill'):l.data.energy=4700;l.data.color=(.36,.58,.65)
  if l.name.startswith('TD_Cold_sky_softbox'):l.data.energy=6500
  if l.name.startswith('TD_Cold_downlight'):l.data.energy=1750;l.data.spot_blend=.88
  if l.name.startswith('TD_Marquee_amber_wash'):l.data.energy=950
# Use only active material datablocks; prior versions may coexist in Blender data.
used={m for o in s.objects if o.type=='MESH' for m in o.data.materials}
for m in used:
 if m.name.startswith('TD_Metal'):
  bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Metallic'].default_value=.61;bs.inputs['Roughness'].default_value=.37
 if m.name.startswith('TD_Emission'):
  bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Emission Strength'].driver_add('default_value').driver.expression='5.0+.10*sin((frame-1)*2*pi/24)+.035*sin((frame-1)*2*pi/8)'
for i in range(4):
 o=bpy.data.objects['TD_Rotor_spin_%d'%i]
 o.driver_remove('rotation_euler',2);o.driver_add('rotation_euler',2).driver.expression='(frame-1)*2*pi/12*%d'%(1 if i%2 else -1)
# Red breathing light has a slow, closed cycle.
scan=bpy.data.objects['TD_Drone_red_downwash']
scan.data.driver_add('energy').driver.expression='7100+650*sin((frame-1)*2*pi/120)'
# Load only the mesh helper definitions from the authored source to add fine detail.
src=open(BASE+'/scripts/build_scene.py').read()
a=src.index('class Batch:');end=src.index('# SKYLINE')
# Recreate palette mapping exactly from the source without executing the scene generator.
ns={'bpy':bpy,'math':math,'Vector':Vector,'Matrix':__import__('mathutils').Matrix,'s':s}
exec(src[src.index('colors={'):src.index('W=16;H=16')],ns)
ns['C']={c.name[3:]:c for c in s.collection.children}
ns['M']=[next(m for m in used if m.name.startswith('TD_'+r)) for r in ['Metal','Matte','WetPaint','Emission']]
# Avoid collection construction from the helper block.
helper=src[a:end]
helper=helper[:helper.index('C={name:coll(name)')]+helper[helper.index('def empty(name,col'):]
exec(helper,ns)
Batch=ns['Batch'];C=ns['C'];rect=ns['rect'];frame=ns['frame'];pipe=ns['pipe'];textmesh=ns['textmesh'];light=ns['light']
import random
random.seed(196)
b=Batch('Upper_left_rooftop_infrastructure',C['01_远景楼群'])
# Left tower and rectangular service duct visible above the shop.
b.box((-17.2,10.4,12.7),(3.8,4.1,4.4),'dark',0)
for x in [-18.6,-17.4,-16.2]:
 frame(b,x,8.24,12.7,1.0,3.85,.06,.10,'steel')
 rect(b,x,8.17,12.7,.82,3.6,.07,'navy',1)
pipe(b,[(-20,9,17.5),(-20,9,15.3),(-18.8,9,15.3),(-18.8,9,14.6),(-17.2,9,14.6)],.65,'black')
pipe(b,[(-19.6,8.4,16.1),(-17.8,8.4,16.1),(-17.8,8.4,14.7),(-15.7,8.4,14.7)],.14,'steel')
for z in [11.5,12,12.5,13,13.5]:rect(b,-17.4,8.10,z,.7,.06,.03,'steel',0)
b.done()
b=Batch('Electrical_meter_plates_and_hazard_labels',C['04_机电管线'])
for j,x in enumerate([-8.2,-6.9,-1.9,1.0,9.2,10.2,13.9]):
 z=7.95+(j%3)*.25;w=.42;h=.66
 rect(b,x,3.48,z,w,h,.24,'rust' if j%2 else 'steel2',0);frame(b,x,3.31,z,w*.88,h*.90,.025,.025,'copper')
 for zz in [z-.21,z+.21]:
  for xx in [x-.14,x+.14]:rect(b,xx,3.27,zz,.024,.024,.02,'pale',0)
 rect(b,x,3.26,z+.1,.23,.09,.02,'paper',1)
 textmesh(b,str(j+1),x-.07,3.23,z+.12,.06,'black',1)
 for zz in [z-.06,z-.12,z-.18]:rect(b,x,3.25,zz,.24,.017,.02,'black',1)
for i in range(22):
 x=-18+i*1.6
 rect(b,x,3.42,7.05,.28,.14,.04,'yellow',1)
 for k in range(3):rect(b,x-.08+k*.08,3.38,7.05,.035,.13,.025,'black',1)
b.done()
b=Batch('Street_curbstone_litter_and_bollards',C['09_湿路与人行道'])
for x,y in [(-10.7,-1.3),(-11.1,2),(13.4,0),(14.1,-1.2),(17.2,2)]:
 b.box((x,y,.36),(.65,.55,.65),'dark',1);frame(b,x,y-.29,.36,.58,.5,.04,.05,'steel2')
 for i in range(4):rect(b,x,y-.33,.16+i*.12,.5,.03,.02,'black',1)
 b.box((x,y,.73),(.69,.59,.09),'steel',0)
for x,y in [(-10.2,.1),(12.7,-.4),(-12.7,-3),(15.3,-3)]:
 b.box((x,y,.52),(.18,.18,1.04),'steel',0);b.box((x,y,.92),(.20,.20,.13),'gold',1)
for i in range(180):
 side=random.choice([-1,1]);x=side*random.uniform(10.5,15);y=random.uniform(-5,8)
 b.box((x,y,.08),(random.uniform(.035,.20),random.uniform(.035,.20),random.uniform(.02,.09)),random.choice(['black','dirty','paper','rust']),1)
b.done()
# Short warm wall lamps at tunnel entrances as in the reference.
for x in [-7.0,10.6]:
 b=Batch('Tunnel_entrance_lantern_%s'%x,C['05_桥下纵深'])
 rect(b,x,10.0,3.4,.17,.40,.13,'warm',3);rect(b,x,9.91,3.65,.28,.12,.16,'steel',0);b.done()
 light('Entrance_warm_pool_%s'%x,(x,9.8,3.4),(1,.60,.27),65,.15,kind='POINT')
s.frame_set(1);s.render.resolution_percentage=75;s.render.filepath=BASE+'/previews/03_refined.png'
s['Version']='v003';s['Analysis']=BASE+'/区域分析与制作清单.md';s['GeometryLanguage']='All visible geometry consists of cuboids; no curve, sphere, cylinder or subdivision objects.'
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/source/tower_district_v003.blend')
bpy.ops.render.render(write_still=True)
print('REFINEMENT_RENDER_COMPLETE')

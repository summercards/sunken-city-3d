import bpy,math,json,random
from mathutils import Vector,Matrix
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district';s=bpy.context.scene
# Correct all initial cube windings using the independently observed outward-normal test.
for o in s.objects:
 if o.type=='MESH':
  me=o.data
  if len(me.vertices)>=8:
   cen=sum((v.co for v in list(me.vertices)[:8]),Vector())/8
   if (me.polygons[0].center-cen).dot(me.polygons[0].normal)<0:me.flip_normals();me.update()
# Keep source regeneration consistent.
p=BASE+'/scripts/build_scene.py';src=open(p).read();src=src.replace("self.f.append(tuple(idx+j for j in f))","self.f.append(tuple(idx+j for j in reversed(f)))");open(p,'w').write(src)
used={m for o in s.objects if o.type=='MESH' for m in o.data.materials}
ns={'bpy':bpy,'math':math,'Vector':Vector,'Matrix':Matrix,'s':s}
exec(src[src.index('colors={'):src.index('W=16;H=16')],ns)
ns['C']={c.name[3:]:c for c in s.collection.children};ns['M']=[next(m for m in used if m.name.startswith('TD_'+r)) for r in ['Metal','Matte','WetPaint','Emission']]
helper=src[src.index('class Batch:'):src.index('# SKYLINE')];helper=helper[:helper.index('C={name:coll(name)')]+helper[helper.index('def empty(name,col'):];exec(helper,ns)
Batch=ns['Batch'];C=ns['C'];rect=ns['rect'];frame=ns['frame'];light=ns['light'];textmesh=ns['textmesh']
bodytypes={'Car_left_mid':'car','Car_center_mid':'car2','Car_right_brown':'brown','Car_right_crop':'rust','Car_foreground_left':'black','Car_foreground_right':'black','Tunnel_vehicle_0':'dark','Tunnel_vehicle_1':'dark','Tunnel_vehicle_2':'dark'}
for name,body in bodytypes.items():
 root=bpy.data.objects['TD_'+name]
 old=bpy.data.objects.get('TD_'+name+'_body')
 if old:bpy.data.objects.remove(old,do_unlink=True)
 b=Batch(name+'_body',C['10_车辆'],root)
 # Subtly stepped fenders and body shoulders, a distinctly 1980s angular sedan.
 b.box((0,0,.65),(2.24,4.60,.50),body,2)
 b.box((0,0,.42),(2.13,4.4,.22),'black',0)
 b.box((0,-.05,.99),(2.30,4.54,.22),body,2)
 b.box((0,-1.67,1.15),(2.22,1.17,.16),body,2)
 b.box((0,1.6,1.14),(2.22,1.25,.16),body,2)
 # Cabin central volume, single flat rectangular sloped glass planes; no curved geometry.
 b.box((0,-.08,1.46),(1.90,1.67,.67),'glass',2)
 for yy,ang in [(-1.09,-.64),(.94,.64)]:
  b.box((0,yy,1.47),(1.91,.06,.79),'glass',2,Matrix.Rotation(ang,3,'X'))
 b.box((0,-.08,1.83),(1.97,1.58,.12),body,2)
 b.box((0,-.08,1.91),(1.87,1.49,.05),body,2)
 for side in [-1,1]:
  for yy,ang in [(-1.09,-.64),(.94,.64)]:b.box((side*.98,yy,1.48),(.075,.10,.84),body,0,Matrix.Rotation(ang,3,'X'))
  b.box((side*.98,-.07,1.45),(.07,.12,.71),body,0)
  b.box((side*.98,-.08,1.16),(.07,2.35,.05),'silver',0)
  b.box((side*1.15,-.06,.86),(.04,3.98,.04),'steel2',0)
  b.box((side*1.15,-.06,.72),(.04,4.02,.025),'black',0)
  b.box((side*1.22,.69,1.26),(.28,.27,.13),body,0)
  for yy in [-.58,.52]:b.box((side*1.15,yy,1.05),(.04,.19,.055),'edge',0)
  # Straight door joints and rectangular patchwork along the body.
  for yy in [-1.02,.02,1.08]:b.box((side*1.155,yy,.81),(.015,.02,.50),'black',1)
  for yy in [-1.48,1.45]:
   for a in range(-3,4):
    for c in range(-3,4):
     if abs(a)+abs(c)>4:continue
     b.box((side*1.1,yy+a*.13,.42+c*.13),(.24,.135,.135),'tire',1)
   b.box((side*1.24,yy,.42),(.035,.35,.35),'steel',0)
   b.box((side*1.26,yy,.42),(.03,.19,.19),'edge',0)
 # Defroster wires lie on the plane, subtle enough to read as glass.
 for k in range(6):
  z=1.25+k*.085;y=-1.09+(z-1.47)*math.tan(.64)-.043
  b.box((0,y,z),(1.73,.009,.009),'steel',0)
 for yy in [-2.34,2.34]:b.box((0,yy,.56),(2.31,.13,.17),'steel',0)
 rect(b,0,-2.40,.88,.53,.22,.035,'dark',1)
 for k in range(5):rect(b,-.18+k*.08,-2.43,.88,.037,.085,.015,'paper',1)
 for side in [-1,1]:
  rect(b,side*.84,-2.33,.96,.58,.21,.05,'red',3)
  rect(b,side*.99,-2.33,.81,.18,.14,.05,'redhot',3)
  for k in range(3):rect(b,side*(.65+k*.16),-2.37,1.0,.11,.13,.025,'redhot',3)
  b.box((side*.80,2.33,.98),(.48,.06,.19),'warm',3)
  rect(b,side*.63,-2.335,1.13,.71,.02,.02,'black',0)
 b.done()
# Shift the nearest cars slightly lower; the reference focuses on the street behind them.
for name in ['TD_Car_foreground_left','TD_Car_foreground_right']:bpy.data.objects[name].location.z=-.15
s.camera.data.dof.aperture_fstop=2.0
# Near-front cool raking light makes vehicle roofs and wet asphalt readable.
light('Vehicle_roof_cold_fill',(-6,-11,9),(.22,.55,.65),1500,9,(0,-8,0),size_y=5)
# Fine irregular face weathering on the awning and faded ceramic wall improves visual density.
b=Batch('Storefront_tile_face_detail',C['06_左侧店面'])
random.seed(72)
for i in range(440):
 x=random.uniform(-19.2,-13.6);z=random.uniform(.55,5.5)
 # Texture marks are tiny cuboids flush against front tile, not floating surfaces.
 rect(b,x,1.373,z,random.uniform(.012,.035),random.uniform(.025,.07),.016,random.choice(['dirty','steel2','black']),1)
b.done()
s.frame_set(1);s.render.resolution_percentage=75;s.render.filepath=BASE+'/previews/04_surface_corrected.png'
s.name='TD_TOWER_DISTRICT_FINAL';s['Version']='v004'
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/source/tower_district_v004.blend')
bpy.ops.render.render(write_still=True)
print('FINAL_GEOMETRY_RENDER_COMPLETE')

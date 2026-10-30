from pathlib import Path
p=Path(r'D:/projects/sea/tools/blender/liberty_lighthouse/build.py')
s=p.read_text();prefix=s.split("part('barge'")[0]
prefix=prefix.replace("m=bpy.data.materials.new(name);m.use_nodes=True", "m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.use_nodes=True")
exec(prefix)

def rebuild(key,fn):
 col=bpy.data.collections['SEA-SCENE-LHL-'+key.upper().replace('_','-')]
 for o in list(col.objects):bpy.data.objects.remove(o,do_unlink=True)
 if col.name not in sc.collection.children:sc.collection.children.link(col)
 fn()
 root=bpy.data.objects.new(key+'_组件根',None);col.objects.link(root)
 objs=[o for o in sc.objects if o.name not in [root.name] and (o.name in col.objects or len(o.users_collection)==0)]
 for o in objs:
  if o.name not in col.objects:col.objects.link(o)
 deps=bpy.context.evaluated_depsgraph_get();pts=[]
 for o in objs:
  ev=o.evaluated_get(deps);me=ev.to_mesh();pts += [o.matrix_world@v.co for v in me.vertices];ev.to_mesh_clear()
 lo=Vector([min(v[i] for v in pts) for i in range(3)]);hi=Vector([max(v[i] for v in pts) for i in range(3)]);ctr=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in objs:
  o.parent=root;o.matrix_parent_inverse.identity();o.location-=ctr
 if col.name in sc.collection.children:sc.collection.children.unlink(col)
 print(key,list(hi-lo))

def hand():
 sphere('巨手长掌',(0,0,4.75),(1.25,.85,2.12),'seafoam')
 sphere('巨手手腕',(.15,.12,2.15),(.95,.74,1.65),'seafoam')
 sphere('巨手前臂',(.35,.12,.9),(1.03,.73,1.6),'seafoam')
 cyl('手腕旧铜环',(.13,.1,2.2),1.00,.30,'sage_gray','SEA_Metal',20)
 cube('手掌断裂补片',(.62,-.72,3.35),(.55,.13,1.10),'sage_gray','SEA_Metal',.035,rot=(0,.13,-.1))
 cube('前臂破损黑洞',(.47,-.626,.85),(.50,.045,.75),'slate','SEA_Metal',.01)
rebuild('arm',hand)

def finger():
 tube('连续弯曲指身',[(0,.12,.38),(0,-.20,.43),(0,-.65,.55),(0,-1.03,.52),(0,-1.24,.39)],.40,'seafoam','SEA_Matte',3)
 sphere('圆润指根',(0,.1,.38),(.4,.42,.4),'seafoam')
 sphere('圆润指尖',(0,-1.24,.39),(.4,.32,.4),'seafoam')
 cube('铜指节纹',(0,-.61,.91),(.51,.10,.035),'sage_gray','SEA_Metal',.015)
rebuild('finger',finger)

def thumb():
 tube('连续拇指',[(0,.12,.45),(0,-.15,.68),(.06,-.46,1.05),(.1,-.66,1.40)],.44,'seafoam','SEA_Matte',3)
 sphere('拇指尖',(.1,-.66,1.40),(.43,.40,.44),'seafoam')
rebuild('thumb',thumb)
# Align grip and structural column.
for o in sc.objects:
 if not o.name.startswith('finger_'):continue
 i=int(o.name.split('_')[-1])-1
 a=math.radians(-54+i*36);o.location=(math.sin(a)*.76,-math.cos(a)*.76,8.15+i*.78);o.rotation_euler=(0,0,a)
bpy.data.objects['arm_01'].location=(0,0,4.4)
bpy.data.objects['thumb_01'].location=(.95,-.05,7.55)
bpy.data.objects['column_01'].location=(0,.1,10.7)
bpy.data.objects['maintenance_door_01'].location=(0,-1.03,11.55)
# Platform top is 16.94; body begins there. Overall stays 25m.
# Fix the awning as a perimeter canopy, leaving the shop sign exposed.
col=bpy.data.collections['SEA-SCENE-LHL-AWNING']
for o in col.objects:
 if o.name=='雨棚斜布':o.dimensions.y=4.8;o.location.y=.25
for o in sc.objects:
 if o.name=='awning_01':o.location.z=1.32
# Light comes from camera side, statue readable rather than a toy silhouette.
sc.render.filepath=str(W/'beauty_refined.png')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(D/'liberty_lighthouse.blend'),compress=True)
bpy.ops.render.render(write_still=True)
print('HAND_REFINED')

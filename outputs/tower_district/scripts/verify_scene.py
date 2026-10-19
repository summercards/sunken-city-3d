import bpy,json,math,os
from mathutils import Vector
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district';s=bpy.context.scene
report={'scene':s.name,'file':bpy.data.filepath,'resolution':[s.render.resolution_x,s.render.resolution_y],'frames':[s.frame_start,s.frame_end],'fps':s.render.fps,'collections':[c.name for c in s.collection.children]}
meshes=[o for o in s.objects if o.type=='MESH'];volumes=[o for o in meshes if o.name.startswith('TD_Volume_')];surface=[o for o in meshes if o not in volumes]
report.update({'objects':len(s.objects),'mesh_objects':len(meshes),'cuboids':sum(len(o.data.vertices)//8 for o in meshes),'vertices':sum(len(o.data.vertices) for o in meshes),'polygons':sum(len(o.data.polygons) for o in meshes),'lights':sum(o.type=='LIGHT' for o in s.objects),'volumes':len(volumes),'surface_materials':sorted({m.name for o in surface for m in o.data.materials})})
issues=[];uv_faces=0
for o in meshes:
 me=o.data
 if len(me.vertices)%8:issues.append(o.name+': not a cuboid multiple')
 if o.modifiers:issues.append(o.name+': unexpected modifiers')
 for p in me.polygons:
  if len(p.vertices)!=4:issues.append(o.name+': non-quad');break
  base=(p.vertices[0]//8)*8;cen=sum((me.vertices[j].co for j in range(base,base+8)),Vector())/8
  if (p.center-cen).dot(p.normal)<=0:issues.append(o.name+': inward normal');break
  if p.use_smooth:issues.append(o.name+': smooth faces');break
 if o in volumes:continue
 uv=me.uv_layers.get('PaletteUV')
 if uv is None:issues.append(o.name+': missing palette UV');continue
 if not uv.active_render:issues.append(o.name+': inactive render UV')
 for p in me.polygons:
  coords=[uv.data[i].uv for i in p.loop_indices];us=[c.x for c in coords];vs=[c.y for c in coords]
  cells={(int(u*16),int(v*16)) for u,v in coords}
  if len(cells)!=1 or max(us)-min(us)<.001 or max(vs)-min(vs)<.001:issues.append(o.name+': invalid UV cell / zero area');break
  uv_faces+=1
curves=[o.name for o in s.objects if o.type in ['CURVE','SURFACE','FONT','META']]
report['forbidden_geometry_types']=curves
if curves:issues.append('Forbidden geometry types')
report['uv_faces_verified']=uv_faces
# Independent evaluated matrices at start, quarter, half and loop boundary.
animated=[o for o in s.objects if o.animation_data and o.animation_data.drivers]
samples={}
for f in [1,61,121,181,241]:
 s.frame_set(f);deps=bpy.context.evaluated_depsgraph_get();deps.update()
 samples[f]={o.name:[v for row in o.evaluated_get(deps).matrix_world for v in row] for o in animated}
errors={n:max(abs(a-b) for a,b in zip(samples[1][n],samples[241][n])) for n in samples[1]}
report['animated_object_count']=len(animated);report['loop_matrix_max_error']=max(errors.values(),default=0)
report['loop_boundary_errors']={k:v for k,v in errors.items() if v>0.0001}
report['motion_verified']={n:max(max(abs(a-b) for a,b in zip(samples[1][n],samples[f][n])) for f in [61,121,181]) for n in samples[1]}
# Rotor quarter-cycle samples can land on symmetry; inspect an in-between frame as well.
s.frame_set(4);bpy.context.evaluated_depsgraph_get().update()
report['rotor_frame4_angle']=[float(bpy.data.objects['TD_Rotor_spin_%d'%i].rotation_euler.z) for i in range(4)]
report['driver_invalid']=[]
for o in animated:
 for d in o.animation_data.drivers:
  if not d.driver.is_valid:report['driver_invalid'].append(o.name+':'+d.data_path)
s.frame_set(1)
report['issues']=issues;report['pass']=not issues and not report['loop_boundary_errors'] and not report['driver_invalid']
with open(BASE+'/qa/scene_verification.json','w') as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps({k:report[k] for k in ['pass','objects','mesh_objects','cuboids','vertices','surface_materials','animated_object_count','loop_matrix_max_error','issues']},ensure_ascii=False))

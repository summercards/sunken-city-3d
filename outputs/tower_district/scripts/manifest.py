import bpy,json
from mathutils import Vector
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district';s=bpy.context.scene
objects=[]
for o in s.objects:
 record={'name':o.name,'type':o.type,'collections':[c.name for c in o.users_collection],'parent':o.parent.name if o.parent else None,'location':list(o.location),'rotation_euler':list(o.rotation_euler),'scale':list(o.scale)}
 if o.type=='MESH':
  bb=[o.matrix_world@Vector(v) for v in o.bound_box]
  record.update({'vertices':len(o.data.vertices),'quad_faces':len(o.data.polygons),'materials':[m.name for m in o.data.materials],'bbox_world_min':[min(v[i] for v in bb) for i in range(3)],'bbox_world_max':[max(v[i] for v in bb) for i in range(3)]})
 if o.type=='LIGHT':record.update({'light_type':o.data.type,'energy':o.data.energy,'color':list(o.data.color)})
 if o.type=='CAMERA':record.update({'lens':o.data.lens,'camera_type':o.data.type})
 if o.animation_data:record['drivers']=[{'path':d.data_path,'index':d.array_index,'expression':d.driver.expression,'valid':d.driver.is_valid} for d in o.animation_data.drivers]
 objects.append(record)
node_drivers=[]
for mat in {m for o in s.objects if o.type=='MESH' for m in o.data.materials}:
 nt=mat.node_tree
 if nt and nt.animation_data:
  node_drivers.extend([{'material':mat.name,'path':f.data_path,'expression':f.driver.expression,'valid':f.driver.is_valid} for f in nt.animation_data.drivers])
light_drivers=[]
for o in s.objects:
 if o.type=='LIGHT' and o.data.animation_data:
  light_drivers.extend([{'object':o.name,'path':f.data_path,'expression':f.driver.expression,'valid':f.driver.is_valid} for f in o.data.animation_data.drivers])
manifest={'scene':s.name,'source':bpy.data.filepath,'reference_image':'source/reference.jpg','units':'meters','render_engine':s.render.engine,'camera':s.camera.name,'resolution':[s.render.resolution_x,s.render.resolution_y],'objects':objects,'node_drivers':node_drivers,'light_drivers':light_drivers,'packed_images':[im.name for im in bpy.data.images if im.packed_file]}
with open(BASE+'/qa/scene_manifest.json','w') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
print(json.dumps({'objects':len(objects),'shader_drivers':len(node_drivers),'light_drivers':len(light_drivers),'all_drivers_valid':all(d['valid'] for d in node_drivers+light_drivers)},ensure_ascii=False))

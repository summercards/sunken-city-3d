import bpy,json
from mathutils import Vector
sc=bpy.context.scene;dg=bpy.context.evaluated_depsgraph_get();rows=[]
for k in ['engine','float_pod','deck','roof','entry','sign_gifts']:
 ins=[o for o in sc.objects if o.instance_collection and o.name.startswith(k+'_')]
 for o in ins:
  pts=[o.matrix_world@m.matrix_world@v.co for m in o.instance_collection.objects if m.type=='MESH' for v in m.data.vertices]
  rows.append({'name':o.name,'position':list(o.location),'bounds':[[min(v[i] for v in pts),max(v[i] for v in pts)] for i in range(3)]})
print(json.dumps(rows))
sc.camera.location=(5,-25,8.7);sc.camera.rotation_euler=(Vector((0,0,3.8))-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath='D:/projects/sea-work/floating_shop/low_preview.png';bpy.ops.render.render(write_still=True)

import bpy,json
sc=bpy.data.scenes.get('WB003V2_v002')
print('scene',bpy.context.scene.name,sc.name if sc else None)
for c in sc.collection.children:
 print('COL',c.name,'objs',len(c.objects),'children',len(c.children))
for o in sc.objects:
 if o.name.startswith('WB003V2_I'):
  print('INST',o.name,'loc',tuple(round(x,2) for x in o.location),'coll',o.instance_collection.name if o.instance_collection else None,'hide',o.hide_render,o.visible_camera)

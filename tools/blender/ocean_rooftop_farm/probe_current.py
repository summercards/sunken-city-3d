import bpy, json
print(json.dumps({'filepath':bpy.data.filepath,'scenes':[(s.name,len(s.objects)) for s in bpy.data.scenes],'current_scene':bpy.context.scene.name,'current_objects':[(o.name,o.type) for o in bpy.context.scene.objects]},ensure_ascii=False))

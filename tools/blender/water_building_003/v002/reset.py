import bpy
for k in ('cols','catalog','instances','witness'): bpy.app.driver_namespace.pop(k,None)
for o in list(bpy.data.objects):
 if o.name.startswith('WB003V2_'): bpy.data.objects.remove(o)
for c in list(bpy.data.collections):
 if c.name.startswith('SEA-SCENE-WATER-BUILDING-003'): bpy.data.collections.remove(c)
print('reset')

import bpy
# Remove every WB003V2 collection-instance and its source collections, then rerun cleanly.
for o in list(bpy.data.objects):
 if o.name.startswith('WB003V2_'): bpy.data.objects.remove(o)
for c in list(bpy.data.collections):
 if c.name.startswith('SEA-SCENE-WATER-BUILDING-003') or c.name.startswith('WB003V2_'):
  try:bpy.data.collections.remove(c)
  except:pass
for k in ('cols','catalog','instances','witness'):bpy.app.driver_namespace.pop(k,None)
print('clean')

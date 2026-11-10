import bpy
ns=bpy.app.driver_namespace
for k in ('cols','catalog','instances','witness'):
    ns.pop(k,None)
for o in list(bpy.data.objects):
    if o.name.startswith('WB003_'): bpy.data.objects.remove(o)
for c in list(bpy.data.collections):
    if c.name.startswith('SEA-SCENE-WATER-BUILDING-003'): bpy.data.collections.remove(c)
for m in list(bpy.data.meshes):
    if m.users==0: bpy.data.meshes.remove(m)
print('reset ok', len(bpy.data.objects))

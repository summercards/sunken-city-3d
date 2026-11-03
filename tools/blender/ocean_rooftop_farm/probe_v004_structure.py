import bpy, json
from mathutils import Vector
s=bpy.context.scene
print('FILE',bpy.data.filepath)
print('SCENES', [x.name for x in bpy.data.scenes])
print('COLLECTIONS')
for c in bpy.data.collections:
    print('C',c.name,'objs',len(c.objects),'children',len(c.children))
print('OBJECTS')
for o in bpy.data.objects:
    if any(k in o.name.lower() for k in ['pier','column','stair','landing','roof','shell','slab']):
        print('O',o.name,'type',o.type,'loc',tuple(round(v,3) for v in o.location),'scale',tuple(round(v,3) for v in o.scale),'dim',tuple(round(v,3) for v in o.dimensions),'colls',[c.name for c in o.users_collection])

import bpy, json, hashlib, pathlib
from mathutils import Vector
SRC='D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
OUT='D:/projects/sea/godot/assets/models/facilities/rooftop_ranch/components/pier/pier.glb'
COL='ORF2_组件_pier.001'
col=bpy.data.collections.get(COL)
assert col is not None
bpy.ops.object.select_all(action='DESELECT')
meshes=[]
# The authoring collection is nested under a hidden production collection in the source.
# Link selected output meshes into the active scene collection temporarily so Blender's
# GLB exporter can select them without a ViewLayer ownership error.
for o in col.objects:
    if o.type=='MESH' and not o.hide_render:
        if o.name not in bpy.context.view_layer.objects:
            bpy.context.scene.collection.objects.link(o)
        o.hide_set(False)
        o.select_set(True); meshes.append(o)
assert meshes, COL
bpy.context.view_layer.objects.active=meshes[0]
bpy.ops.export_scene.gltf(filepath=OUT,export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_image_format='NONE',export_keep_originals=False,export_texcoords=True,export_normals=True,export_tangents=False,export_cameras=False,export_lights=False,export_extras=True,export_apply=False,export_animations=False)
print(json.dumps({'saved':OUT,'objects':len(meshes),'sha256':hashlib.sha256(pathlib.Path(OUT).read_bytes()).hexdigest()},ensure_ascii=False))

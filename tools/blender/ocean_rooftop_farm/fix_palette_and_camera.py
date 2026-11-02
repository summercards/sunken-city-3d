import bpy, json
from pathlib import Path
from mathutils import Vector
R = Path(r'D:/projects/sea')
D = R / 'art_source/scenes/ocean_rooftop_farm/v001'
W = R.parent / 'sea-work/ocean_rooftop_farm/v001'
pal = R / 'art_source/shared/palettes/sea_cabin_timber_8x8_512.png'
bpy.ops.wm.open_mainfile(filepath=str(D / 'ocean_rooftop_farm.blend'))
fixed = []
for im in bpy.data.images:
    if im.source == 'FILE' and ('sea_cabin_timber' in im.filepath or 'sea_cabin_timber' in im.name):
        im.filepath = str(pal)
        im.reload()
        im.filepath = bpy.path.relpath(str(pal), start=str(D))
        fixed.append({'name': im.name, 'path': im.filepath, 'size': list(im.size)})
sc = bpy.data.scenes['海上屋顶农场_制作与装配_v001']
cam = sc.camera
cam.location = (42, -53, 52)
cam.rotation_euler = (Vector((0, 0, 8.2)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.ortho_scale = 52
sc.render.filepath = str(W / 'beauty_v002_color.png')
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(D / 'ocean_rooftop_farm.blend'), compress=True)
bpy.ops.render.render(write_still=True, scene=sc.name)
print(json.dumps({'palette_fixed': fixed, 'render': sc.render.filepath}, ensure_ascii=False))

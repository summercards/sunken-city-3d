import bpy, json
from pathlib import Path
from mathutils import Vector
R = Path(r'D:/projects/sea')
D = R / 'art_source/scenes/ocean_rooftop_farm/v001'
W = R.parent / 'sea-work/ocean_rooftop_farm/v001'
bpy.ops.wm.open_mainfile(filepath=str(D / 'ocean_rooftop_farm.blend'))
sc = bpy.data.scenes['海上屋顶农场_制作与装配_v001']
cam = sc.camera
cam.location = (43, -55, 43)
cam.rotation_euler = (Vector((0, 0, 8.0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.ortho_scale = 52
sc.render.resolution_x = 1440
sc.render.resolution_y = 1000
sc.render.filepath = str(W / 'beauty_v001.png')
bpy.ops.render.render(write_still=True, scene=sc.name)
print(json.dumps({'render': sc.render.filepath, 'objects': len(sc.objects), 'camera': list(cam.location)}, ensure_ascii=False))

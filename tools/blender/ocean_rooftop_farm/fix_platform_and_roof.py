import bpy, json
from pathlib import Path
from mathutils import Vector
R = Path(r'D:/projects/sea')
D = R / 'art_source/scenes/ocean_rooftop_farm/v001'
W = R.parent / 'sea-work/ocean_rooftop_farm/v001'
bpy.ops.wm.open_mainfile(filepath=str(D / 'ocean_rooftop_farm.blend'))
sc = bpy.data.scenes['海上屋顶农场_制作与装配_v001']
layout_path = D / 'component_instances.json'
data = json.loads(layout_path.read_text(encoding='utf-8'))
corrections = []
for item in data['instances']:
    if item['position'][2] > 29:
        old = item['position'][2]
        item['position'][2] -= 16.0
        corrections.append([item['name'], old, item['position'][2]])
    o = sc.objects.get(item['name'])
    if o:
        o.location = item['position']
layout_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
cam = sc.camera
cam.location = (48, -62, 68)
cam.rotation_euler = (Vector((0, 0, 13.0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.ortho_scale = 80
sc.render.resolution_x = 1440
sc.render.resolution_y = 1100
sc.render.filepath = str(W / 'beauty_r2_fixed.png')
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(D / 'ocean_rooftop_farm.blend'), compress=True)
bpy.ops.render.render(write_still=True, scene=sc.name)
print(json.dumps({'height_corrections': corrections, 'render': sc.render.filepath}, ensure_ascii=False))

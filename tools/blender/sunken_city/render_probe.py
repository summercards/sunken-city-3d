"""从建筑内部沿指定方位看出去，检查该方向是否透空。

用法：blender -b --python render_probe.py -- <blend> <out.png> <angle_deg> <z_offset>
"""
import bpy
import math
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
src, out_png = argv[0], argv[1]
angle = float(argv[2]) if len(argv) > 2 else 68.0
zoff = float(argv[3]) if len(argv) > 3 else 1.7

bpy.ops.wm.open_mainfile(filepath=src, load_ui=False, use_scripts=False)
sc = bpy.context.scene
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
mw = mesh.matrix_world
vs = [mw @ v.co for v in mesh.data.vertices]
mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
c = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z + zoff))

a = math.radians(angle)
cam_data = bpy.data.cameras.new('P')
cam = bpy.data.objects.new('P', cam_data)
sc.collection.objects.link(cam)
cam.location = c
d = Vector((math.cos(a), math.sin(a), 0)).normalized()
cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
cam_data.lens = 18
sc.camera = cam
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'SINGLE'
sc.display.shading.single_color = (0.75, 0.75, 0.78)
sc.display.shading.show_backface_culling = False
sc.render.resolution_x = 900
sc.render.resolution_y = 560
sc.world.color = (0.02, 0.65, 0.85)  # 亮青背景：凡是透空处都会显出这个颜色
sc.render.filepath = out_png
bpy.ops.render.render(write_still=True)
print('PROBE_RENDERED', out_png)

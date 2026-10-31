"""Quick look pass for the retail detail (does not touch verification.json)."""
import os
from pathlib import Path

import bpy
from mathutils import Vector

R = Path('D:/projects/sea')
D = R / 'art_source/scenes/floating_shop/v003'
W = Path(os.environ.get('SEA_WORK_ROOT', 'D:/projects/sea-work')) / 'floating_shop/v003'
sc = bpy.data.scenes['海上悬浮商铺_v003']
if bpy.context.window_manager.windows:
    bpy.context.window_manager.windows[0].scene = sc
cam = sc.camera
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for dev in prefs.devices:
        dev.use = dev.type != 'CPU'
    sc.cycles.device = 'GPU' if any(d.use for d in prefs.devices) else 'CPU'
except Exception:
    pass
sc.cycles.samples = 40
sc.render.resolution_percentage = 100
if '展示背景地面' in bpy.data.objects:
    bpy.data.objects['展示背景地面'].hide_render = True

VIEWS = [
    ('retail-front', (0, -30, 7), (0, -3.0, 3.6), 22, (1500, 1050)),
    ('retail-quarter', (18, -26, 18), (0, 0, 3.6), 26, (1600, 1200)),
    ('retail-counter', (3.5, -14, 5.0), (0, -4.9, 3.4), 11, (1500, 1100)),
    ('retail-inside', (1.2, -9.0, 4.6), (0, -2.0, 3.2), 12, (1400, 1050)),
]
for name, pos, target, size, res in VIEWS:
    cam.location = pos
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.ortho_scale = size
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = str(W / (name + '.png'))
    bpy.ops.render.render(write_still=True, scene=sc.name)
print('RETAIL_PREVIEW_DONE', len(VIEWS))

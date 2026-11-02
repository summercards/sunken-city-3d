"""Fast single-building preview while iterating. Writes sea-work/submerged_street_v001/preview/."""
import bpy
import json
import math
import os
import sys
from pathlib import Path
from mathutils import Vector

R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/submerged_street/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent / 'sea-work')) / 'submerged_street_v001' / 'preview'
W.mkdir(parents=True, exist_ok=True)
CAT = {c['key']: c for c in json.loads((D / 'catalog.json').read_text(encoding='utf-8'))['components']}
keys = [a for a in sys.argv[sys.argv.index('--') + 1:]] if '--' in sys.argv else list(CAT)

bpy.ops.wm.open_mainfile(filepath=str(D / 'submerged_street.blend'))
S = bpy.data.scenes['沉没街道_参考布局']
bpy.context.window.scene = S
S.render.engine = 'CYCLES'
S.cycles.samples = 24
S.cycles.use_denoising = True
S.view_settings.view_transform = 'Standard'
S.view_settings.exposure = -0.15
S.world.node_tree.nodes['Background'].inputs[0].default_value = (0.075, 0.165, 0.205, 1)
S.world.node_tree.nodes['Background'].inputs[1].default_value = 1.15
STAGE = bpy.data.collections['展示支持_不导出']
for o in [o for o in STAGE.objects if o.type == 'LIGHT']:
    bpy.data.objects.remove(o, do_unlink=True)
for name, rot, energy in (('主阳', (math.radians(50), 0, math.radians(34)), 3.0),
                          ('侧补', (math.radians(66), 0, math.radians(196)), 1.35),
                          ('背补', (math.radians(74), 0, math.radians(96)), 0.7)):
    d = bpy.data.lights.new(name, 'SUN')
    d.energy = energy
    d.angle = 0.2
    lo = bpy.data.objects.new(name, d)
    STAGE.objects.link(lo)
    lo.rotation_euler = rot
cam = S.camera
inst = {o.instance_collection.name: o for o in bpy.data.collections['参考布局_建筑实例'].objects}
for key in keys:
    row = CAT[key]
    ob = inst[row['asset_id']]
    base = ob.matrix_world.translation.copy()
    lo = Vector([min((ob.matrix_world @ Vector(c))[i] for c in ob.instance_collection.objects[0].bound_box) for i in range(3)])
    hi = Vector([max((ob.matrix_world @ Vector(c))[i] for c in ob.instance_collection.objects[0].bound_box) for i in range(3)])
    size = hi - lo
    ctr = (lo + hi) / 2
    for other in inst.values():
        other.hide_render = (other is not ob)
    for tag, offset, res in (('a', Vector((0.70, 0.72, 0.26)), (1100, 820)),
                             ('b', Vector((-0.55, -0.82, 0.20)), (1100, 820)),
                             ('top', Vector((0.001, -0.001, 1.0)), (1000, 800))):
        S.render.resolution_x, S.render.resolution_y = res
        cam.data.type = 'ORTHO'
        cam.data.ortho_scale = max(max(size.x, size.y) * 1.12, size.z * 1.12 * res[0] / res[1]) * 1.1
        cam.location = ctr + offset.normalized() * (max(size) * 2.2 + 20)
        cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
        S.render.filepath = str(W / ('%s_%s.png' % (key, tag)))
        bpy.ops.render.render(write_still=True)
for other in inst.values():
    other.hide_render = False
print('PREVIEW_DONE', keys, flush=True)

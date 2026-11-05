"""家园外围残楼围挡 · 源级验收渲染（EEVEE）。

用法（多视图一次出）：
  blender -b --python tools/blender/sea_barrier/render.py
指定视图：
  blender -b --python tools/blender/sea_barrier/render.py -- ring_top home_north
"""
import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / 'art_source/scenes/sea_barrier/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', ROOT.parent / 'sea-work')) / 'sea_barrier/v001'
OUT = W / 'renders'
OUT.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.open_mainfile(filepath=str(D / 'sea_barrier.blend'))
scene = bpy.data.scenes['家园外围残楼围挡_完整围合']
bpy.context.window.scene = scene if bpy.context.window else scene
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.render.film_transparent = False
scene.view_settings.view_transform = 'Standard'

world = bpy.data.worlds.new('验收天空')
world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs['Color'].default_value = (.56, .66, .72, 1)
bg.inputs['Strength'].default_value = .85
scene.world = world

sun_data = bpy.data.lights.new('验收太阳', 'SUN')
sun_data.energy = 3.4
sun_data.angle = math.radians(3.0)
sun = bpy.data.objects.new('验收太阳', sun_data)
sun.rotation_euler = (math.radians(58), 0, math.radians(35))
scene.collection.objects.link(sun)

water_mat = bpy.data.materials.new('验收水面')
water_mat.use_nodes = True
bsdf = next(n for n in water_mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
bsdf.inputs['Base Color'].default_value = (.46, .62, .68, 1)
bsdf.inputs['Roughness'].default_value = .35
water = bpy.context.blend_data.meshes.new('水面')
water.from_pydata([(-260, -260, 0), (260, -260, 0), (260, 260, 0), (-260, 260, 0)],
                  [], [(0, 1, 2, 3)])
water.update()
water.materials.append(water_mat)
water_obj = bpy.data.objects.new('验收水面', water)
scene.collection.objects.link(water_obj)


def camera(name, location, target, lens=35.0, ortho=None):
    cam_data = bpy.data.cameras.new(name)
    cam_data.lens = lens
    if ortho:
        cam_data.type = 'ORTHO'
        cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new(name, cam_data)
    cam.location = Vector(location)
    direction = Vector(target) - Vector(location)
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    scene.collection.objects.link(cam)
    return cam


# 相机全部按 240 米围合布点（内边界 ±120，围挡进深 10 米，实体落在 120..130）。
VIEWS = {
    'ring_top': (camera('俯视_整圈', (0, 0, 460), (0, 0, 0), ortho=330), False),
    'home_north': (camera('家园看北侧', (2, -8, 4.2), (2, 126, 6), 30), True),
    'home_west': (camera('家园看西侧', (-8, 8, 4.2), (-126, 8, 6), 30), True),
    'corner_view': (camera('内侧看东北角', (96, 94, 12.0), (122, 122, 8), 30), True),
    # south_01 是斜塌楼、south_03 是半沉林带（KIND_CYCLE 起点错开后的实际种类）
    'closeup_house': (camera('近景_残楼', (-100, -108, 4.8), (-100, -124, 4.2), 40), True),
    'closeup_forest': (camera('近景_半沉林带', (-60, -110, 3.4), (-60, -124, 3.0), 34), True),
    'outside': (camera('外侧回望', (4, 214, 40), (0, 126, 8), 40), False),
    'oblique': (camera('斜俯瞰', (176, -176, 150), (20, 40, 2), 45), False),
    # 贴水面平视：专门看「倾斜的楼底边有没有离开水面」。穿帮最容易在这一角度露出来。
    'tilt_check': (camera('贴水平视_南侧', (-72, -104, 1.4), (-72, -124, 1.6), 42), True),
    # 水下 20 米结构：水关掉才看得见。这两张是「下方补上了没有」的直接证据。
    # 水面隐藏；镜头压低到水下 8 米，斜看南墙全高（顶上还有水线上的残楼）
    'deep_side': (camera('水下侧视_南墙', (-70, -205, -8.5), (-55, -126, -6), 34), False),
    'deep_inside': (camera('水下斜切_南墙', (-20, -170, -14), (-45, -126, -12), 30), False),
}

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else list(VIEWS)
scene.render.image_settings.file_format = 'PNG'
for key in args:
    cam, wet = VIEWS[key]
    scene.camera = cam
    water_obj.hide_render = not wet
    scene.render.resolution_x = 1600 if key == 'ring_top' else 1400
    scene.render.resolution_y = 1600 if key == 'ring_top' else 860
    scene.render.filepath = str(OUT / f'{key}.png')
    bpy.ops.render.render(write_still=True)
    print('RENDER', key, flush=True)

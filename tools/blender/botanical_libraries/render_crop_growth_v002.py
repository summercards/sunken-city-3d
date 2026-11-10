"""Render isolated v002 species boards and close-ups without saving the blend."""
import bpy, json, hashlib
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
BLEND = ROOT / 'art_source/crops/libraries/v002/planting_library.blend'
WORK = Path('D:/projects/sea-work/botanical_growth/v002/crops')
OUT = WORK / 'renders'
OUT.mkdir(parents=True, exist_ok=True)
PLANTS = [
    ('SEA-CROP-LETTUCE', '生菜', 0),
    ('SEA-CROP-TOMATO', '番茄', -1.65),
    ('SEA-CROP-PUMPKIN', '南瓜', -3.30),
    ('SEA-CROP-FLOWER-BLUE', '蓝星花', -4.95),
    ('SEA-CROP-FLOWER-SUN', '晨光花', -6.60),
    ('SEA-CROP-FLOWER-CORAL', '珊瑚花', -8.25),
]
GROWTH_LABELS = ('小', '中', '大')


def point_camera(cam, target, location):
    cam.location = location
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat('-Z', 'Y').to_euler()


def set_background(scene):
    # Use a linear-space value that renders as a light cream under Standard view transform.
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.world.color = (0.92, 0.84, 0.68)
    if scene.world.use_nodes:
        bg = scene.world.node_tree.nodes.get('Background')
        bg.inputs['Color'].default_value = (0.92, 0.84, 0.68, 1)
        bg.inputs['Strength'].default_value = 0.8


def setup_label_material():
    mat = bpy.data.materials.get('V002_ReviewLabel') or bpy.data.materials.new('V002_ReviewLabel')
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bs = nodes.get('Principled BSDF')
    if bs:
        bs.inputs['Base Color'].default_value = (0.08, 0.055, 0.035, 1)
        bs.inputs['Roughness'].default_value = 0.9
    support = bpy.data.collections.get('01_标签支持_非植物')
    if support:
        for ob in support.objects:
            ob.hide_render = False
            if ob.type == 'FONT':
                ob.data.materials.clear()
                ob.data.materials.append(mat)


def isolate_species(scene, asset_id, row_y):
    root = bpy.data.collections.get('01_小中大对照_CollectionInstance')
    support = bpy.data.collections.get('01_标签支持_非植物')
    if root:
        for ob in root.objects:
            ob.hide_render = ob.get('asset_id') != asset_id
    if support:
        for ob in support.objects:
            ob.hide_render = abs(ob.location.y - row_y) > 0.72


def render_one(scene, name, asset_id, row_y, target, location, ortho, resolution):
    isolate_species(scene, asset_id, row_y)
    set_background(scene)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    cam = scene.camera
    point_camera(cam, target, location)
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = ortho
    scene.render.filepath = str(OUT / (name + '.png'))
    bpy.context.window.scene = scene
    bpy.ops.render.render(write_still=True)
    return str(OUT / (name + '.png'))


def main():
    bpy.ops.wm.open_mainfile(filepath=str(BLEND), load_ui=False)
    setup_label_material()
    scene = bpy.data.scenes['01_小中大对照']
    views = []
    closeups = []
    # Each board contains only one species and its three Collection Instances.
    for index, (asset_id, display, y) in enumerate(PLANTS, 1):
        target = (1.25, y, 0.40)
        views.append(render_one(scene, f'comparison_{index:02d}_{display}', asset_id, y, target, (5.0, y - 7.2, 3.2), 3.85, (1800, 900)))
        closeups.append(render_one(scene, f'closeup_{index:02d}_{display}', asset_id, y, target, (4.2, y - 5.7, 2.45), 3.35, (1600, 1000)))
    report = {'library_sha256': hashlib.sha256(BLEND.read_bytes()).hexdigest(), 'library': 'SEA-LIB-PLANTING-GROWTH-V002', 'views': views, 'closeups': closeups, 'count': len(views) + len(closeups), 'isolation': 'one species, three collection instances, matching labels only', 'camera': 'orthographic, azimuth approximately 35 degrees, cream world'}
    (WORK / 'render_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('CROP_GROWTH_V002_RENDER ' + json.dumps(report, ensure_ascii=False))

if __name__ == '__main__':
    main()

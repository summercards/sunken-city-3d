import bpy
import hashlib
import json
from pathlib import Path

R = Path(r'D:/projects/sea')
source = R / 'art_source/scenes/liberty_lighthouse/v001/liberty_lighthouse.blend'
if Path(bpy.data.filepath).resolve() != source.resolve():
    bpy.ops.wm.open_mainfile(filepath=str(source))
scene = bpy.data.scenes['巨手灯塔_制作与装配_v001']
bpy.context.window.scene = scene
bpy.context.view_layer.update()
collection = bpy.data.collections['SEA-SCENE-LHL-AWNING']
instance = scene.objects['awning_01']
report = {
    'filepath': bpy.data.filepath,
    'disk_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'active_scene': scene.name,
    'instance_location': list(instance.location),
    'collection_objects': [],
    'evaluated_instance_world_min_z': None,
}
deps = bpy.context.evaluated_depsgraph_get()
world_z = []
for obj in collection.objects:
    if obj.type != 'MESH':
        continue
    evaluated = obj.evaluated_get(deps)
    mesh = evaluated.to_mesh()
    raw_z = [obj.matrix_world @ v.co for v in obj.data.vertices]
    evaluated_z = [obj.matrix_world @ v.co for v in mesh.vertices]
    world_z.extend(instance.matrix_world @ obj.matrix_local @ v.co for v in mesh.vertices)
    report['collection_objects'].append({
        'name': obj.name,
        'location': list(obj.location),
        'raw_min_z': min(v.z for v in raw_z),
        'evaluated_min_z': min(v.z for v in evaluated_z),
        'matrix_local_translation': list(obj.matrix_local.translation),
        'modifiers': [(m.name, m.type) for m in obj.modifiers],
    })
    evaluated.to_mesh_clear()
report['evaluated_instance_world_min_z'] = min(v.z for v in world_z)
report['evaluated_collection_min_z'] = min(o['evaluated_min_z'] for o in report['collection_objects'])
assert abs(report['evaluated_collection_min_z']) < .001, 'Awning local origin is not at bottom Z=0'
assert abs(report['evaluated_instance_world_min_z'] - 3.5) < .03, 'Awning world elevation changed'
print('FINAL_SESSION_PROBE ' + json.dumps(report, ensure_ascii=False))
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            space = area.spaces.active
            space.region_3d.view_perspective = 'CAMERA'
            space.region_3d.view_camera_zoom = 0
            space.shading.type = 'MATERIAL'
            space.overlay.show_overlays = False
bpy.ops.wm.save_as_mainfile(filepath=str(source), compress=True)
report['resaved_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
qa_path = R / 'sea-work/liberty_lighthouse/verification.json'
qa = json.loads(qa_path.read_text(encoding='utf-8'))
assert qa['source_sha256'] == report['resaved_sha256'], 'Verified assembly hash changed during session probe'
(R / 'sea-work/liberty_lighthouse/session_probe.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

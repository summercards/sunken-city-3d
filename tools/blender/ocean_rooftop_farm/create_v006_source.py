import bpy
import json
from pathlib import Path

ROOT = Path('D:/projects/sea')
V004 = ROOT / 'art_source/scenes/ocean_rooftop_farm/v004/ocean_rooftop_farm_v004.blend'
V005 = ROOT / 'art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
V006_DIR = ROOT / 'art_source/scenes/ocean_rooftop_farm/v006'
V006 = V006_DIR / 'ocean_rooftop_farm_v006.blend'
V006_DIR.mkdir(parents=True, exist_ok=True)

PREFIXES = ('ORF3_实例_stair_flight.', 'ORF3_实例_stair_landing.')
ROOF_ENTRY_PREFIX = 'ORF3_实例_roof_entry'

def is_target(name):
    return name.startswith(PREFIXES) or name.startswith(ROOF_ENTRY_PREFIX)

def object_visibility(o):
    return {
        'hide_viewport': bool(o.hide_viewport),
        'hide_render': bool(o.hide_render),
        'hide_set': bool(o.hide_get()),
    }

def matrix(o):
    return [[round(float(v), 10) for v in row] for row in o.matrix_world]

# Read v004 as the visibility and transform reference only.
bpy.ops.wm.open_mainfile(filepath=str(V004))
v004 = {
    o.name: {'visibility': object_visibility(o), 'matrix_world': matrix(o)}
    for o in bpy.data.objects if is_target(o.name)
}

# Start from v005; do not move objects or alter any mesh data.
bpy.ops.wm.open_mainfile(filepath=str(V005))
v005_targets = {o.name: o for o in bpy.data.objects if is_target(o.name)}
missing = sorted(set(v004) - set(v005_targets))
extra = sorted(set(v005_targets) - set(v004))
if missing or extra:
    raise RuntimeError(json.dumps({'missing_from_v005': missing, 'extra_in_v005': extra}, ensure_ascii=False))

for name, ref in v004.items():
    o = v005_targets[name]
    o.hide_viewport = ref['visibility']['hide_viewport']
    o.hide_render = ref['visibility']['hide_render']
    o.hide_set(ref['visibility']['hide_set'])

scene = bpy.context.scene
scene['ORF6_VERSION'] = 'v006'
scene['ORF6_PARENT_SOURCE'] = 'art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
scene['ORF6_VISIBILITY_REFERENCE'] = 'art_source/scenes/ocean_rooftop_farm/v004/ocean_rooftop_farm_v004.blend'
scene['ORF6_WATER_LOCAL_Z'] = 57.04
scene['ORF6_BOARD_LOCAL_Z'] = 57.30
scene['ORF6_ROOT_Y'] = -55.92
scene['ORF6_NOTES'] = '源仅记录Godot正式下沉建议；不移动对象；恢复楼梯、平台和roof_entry可见性至v004；保留v005柱体大块缺损网格、材质与UV。'

bpy.ops.wm.save_as_mainfile(filepath=str(V006), compress=True)
print(json.dumps({
    'saved': str(V006),
    'target_count': len(v004),
    'visibility_reference': str(V004),
    'geometry_source': str(V005),
    'recommended_godot_values': {
        'WATER_LOCAL_Z': 57.04,
        'BOARD_LOCAL_Z': 57.30,
        'ROOT_Y': -55.92,
    },
}, ensure_ascii=False))

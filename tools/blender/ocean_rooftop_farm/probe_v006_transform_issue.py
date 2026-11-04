import bpy
import json
from pathlib import Path

V005 = 'D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v005/ocean_rooftop_farm_v005.blend'
V006 = 'D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v006/ocean_rooftop_farm_v006.blend'
names = [
    'ORF3_实例_roof_entry',
    'ORF3_实例_stair_flight.018', 'ORF3_实例_stair_flight.019', 'ORF3_实例_stair_flight.020',
    'ORF3_实例_stair_flight.021', 'ORF3_实例_stair_flight.022', 'ORF3_实例_stair_flight.023',
    'ORF3_实例_stair_landing.018', 'ORF3_实例_stair_landing.019', 'ORF3_实例_stair_landing.020',
    'ORF3_实例_stair_landing.021', 'ORF3_实例_stair_landing.022', 'ORF3_实例_stair_landing.023',
    'ORF3_实例_stair_landing.024',
]
def row(o):
    return {
        'location': [round(float(v), 12) for v in o.location],
        'rotation_euler': [round(float(v), 12) for v in o.rotation_euler],
        'scale': [round(float(v), 12) for v in o.scale],
        'matrix_basis': [[round(float(v), 12) for v in x] for x in o.matrix_basis],
        'matrix_parent_inverse': [[round(float(v), 12) for v in x] for x in o.matrix_parent_inverse],
        'matrix_local': [[round(float(v), 12) for v in x] for x in o.matrix_local],
        'matrix_world': [[round(float(v), 12) for v in x] for x in o.matrix_world],
        'parent': o.parent.name if o.parent else None,
    }
result = {}
for path, label in [(V005, 'v005'), (V006, 'v006')]:
    bpy.ops.wm.open_mainfile(filepath=path)
    result[label] = {name: row(bpy.data.objects[name]) for name in names}
Path('D:/projects/sea-work/ocean_rooftop_farm/v006_delivery/transform_probe.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print('wrote transform_probe.json')

import bpy, json
from pathlib import Path
from mathutils import Vector
D = Path(r'D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v001')
sc = bpy.data.scenes['海上屋顶农场_制作与装配_v001']
report = {'scene': sc.name, 'instances': [], 'components': {}}
for o in sc.objects:
    if o.instance_type == 'COLLECTION':
        report['instances'].append({'name': o.name, 'key': o.instance_collection.name, 'position': list(o.location), 'scale': list(o.scale)})
for c in bpy.data.collections:
    if c.name.startswith('SEA-SCENE-ORF-'):
        pts = []
        for o in c.objects:
            if o.type == 'MESH':
                pts.extend(o.matrix_world @ v.co for v in o.data.vertices)
        report['components'][c.name] = {'objects': len(c.objects), 'min': [min(v[i] for v in pts) for i in range(3)] if pts else None, 'max': [max(v[i] for v in pts) for i in range(3)] if pts else None}
print(json.dumps(report, ensure_ascii=False))

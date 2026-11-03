import bpy,json
from pathlib import Path
s=bpy.context.scene;up=json.loads(Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v004/upgrade_states.json').read_text(encoding='utf-8'))
bpy.context.view_layer.update()
print(json.dumps([{ 'family':p['family'],'states':{st:{'location':list(s.objects[e['instance_name']].location),'matrix':[list(v) for v in s.objects[e['instance_name']].matrix_world]} for st,e in p['states'].items()}} for p in up['pairs']],ensure_ascii=False))

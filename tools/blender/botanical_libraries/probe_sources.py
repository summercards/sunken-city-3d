"""Read-only probes for botanical library import structure."""
import bpy, json
from pathlib import Path
R = Path(__file__).resolve().parents[3]
paths = [
 'art_source/crops/lettuce/v001/lettuce_v001.blend',
 'art_source/vegetation/v003/components/grass_soft/grass_soft.blend',
 'art_source/scenes/sunny_bloom_retreat/v008/components/foliage/foliage.blend',
 'art_source/scenes/ocean_rooftop_farm/v004/component_packages/grass/grass.blend',
 'art_source/scenes/bld_20261109_a/v001/component_packages/leaf_cluster/leaf_cluster.blend',
]
for p in paths:
 bpy.ops.wm.open_mainfile(filepath=str(R/p), load_ui=False)
 print('SOURCE_PROBE ' + json.dumps({'path':p,'collections':[{'name':c.name,'objects':len(c.objects),'children':[x.name for x in c.children]} for c in bpy.data.collections], 'objects':[{'name':o.name,'type':o.type,'instance':o.instance_collection.name if o.instance_collection else None,'collections':[c.name for c in o.users_collection]} for o in bpy.data.objects][:30], 'images':[{'name':i.name,'path':i.filepath} for i in bpy.data.images]},ensure_ascii=False))

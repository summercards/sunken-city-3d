import bpy,json,math
from pathlib import Path
from mathutils import Vector
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v003');s=bpy.context.scene;cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];e=next(e for e in cat if e['key']=='roof_entry');c=bpy.data.collections[e['collection']];inst=next(o for o in s.objects if o.instance_type=='COLLECTION' and o.instance_collection==c)
# sunken seam plate spans join, top59.97 vs surrounding60.00 -> cannot zfight.
world=[(24.65+dx,-3.9+dy,59.85+dz) for dx,dy,dz in [(0,-1.25,0),(.30,-1.25,0),(.30,1.25,0),(0,1.25,0),(0,-1.25,.12),(.30,-1.25,.12),(.30,1.25,.12),(0,1.25,.12)]]
me=bpy.data.meshes.new('入口下沉承接板');me.from_pydata([inst.matrix_world.inverted()@Vector(v) for v in world],[],[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]);me.update();ob=bpy.data.objects.new('ORF3_防闪面下沉承接板',me);c.objects.link(ob);mat=next(m for m in bpy.data.materials if m.name=='ORF2_FINAL_SEA_Metal');me.materials.append(mat);uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
for p in me.polygons:
 for j,li in enumerate(p.loop_indices):a=j*math.tau/len(p.loop_indices);uv.data[li].uv=((1.5+.2*math.cos(a))/8,(.5+.2*math.sin(a))/8)
route=json.loads((D/'stair_route.json').read_text(encoding='utf-8'));route['zfight_fix']['sunken_support_plate_top_z']=59.97;route['zfight_fix']['sunken_support_plate_span_x']=[24.65,24.95];(D/'stair_route.json').write_text(json.dumps(route,ensure_ascii=False,indent=2),encoding='utf-8')
print('SEAM_SUPPORT_TOP_59_97')

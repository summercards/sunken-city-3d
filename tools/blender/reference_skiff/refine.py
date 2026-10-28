"""Targeted pre-delivery correction: keep the inner ribs inside the solid shell."""
import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Matrix,Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/reference_skiff/v001'
SRC=D/'reference_skiff.blend';bpy.ops.wm.open_mainfile(filepath=str(SRC));bpy.context.preferences.filepaths.save_version=0
if bpy.data.collections['SEA-SCENE-SKIFF-FLOOR-BOARD'].all_objects[0].get('palette_color')=='wood_light':
    raise RuntimeError('This one-time correction is already applied')
col=bpy.data.collections['SEA-SCENE-SKIFF-RIB']
for o in col.all_objects:
    # The existing rib leaned inward; reflect its local X to lean out with the hull.
    for v in o.data.vertices:v.co.x=-v.co.x
    import bmesh
    bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
instances=json.loads((D/'component_instances.json').read_text(encoding='utf-8'));ribs=[i for i in instances['instances'] if i['key']=='rib']
for item,(y,x,side) in zip(ribs,[(y,x,s) for y,x in [(-1.8,.87),(-.9,.92),(0,.94),(.9,.85),(1.8,.61)] for s in [-1,1]]):
    ob=bpy.data.objects[item['instance_id'].split('/')[-1]];ob.location=(x*side,y,.105);ob.rotation_euler=(0,0,math.pi if side<0 else 0)
    item['position']=list(ob.location);item['rotation_euler_xyz']=list(ob.rotation_euler)
# Warm floor matches the honey/orange planks in the supplied reference.
floor=bpy.data.collections['SEA-SCENE-SKIFF-FLOOR-BOARD']
for ob in floor.all_objects:
    # honey column 0 -> wood_light column 1, same row, preserve island shape.
    for loop in ob.data.uv_layers['PaletteUV'].data:loop.uv.x+=1/8
    ob['palette_color']='wood_light'
bpy.context.window.scene=bpy.data.scenes['黄白木船_参考装配'];bpy.ops.wm.save_as_mainfile(filepath=str(SRC),compress=True)
(D/'component_instances.json').write_text(json.dumps(instances,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))
for e in cat['components']:
    if e['key'] not in ('rib','floor_board'):continue
    geo=hashlib.sha256()
    for ob in bpy.data.collections[e['collection']].all_objects:
        geo.update(ob.data.name.encode());geo.update(str([list(v.co) for v in ob.data.vertices]).encode());geo.update(str([list(f.vertices) for f in ob.data.polygons]).encode())
    e['geometry_fingerprint']=geo.hexdigest()
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('REFINED_INNER_RIBS_AND_WARM_TIMBER',flush=True)

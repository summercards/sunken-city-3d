"""Protected component export of the approved seven-storey lower building."""
import bpy,bmesh,json,hashlib,math,os,struct
from pathlib import Path
from mathutils import Matrix,Euler,Vector
R=Path(__file__).resolve().parents[3];SRC=R/'art_source/scenes/bloom_lower_building/v001';D=SRC/'export/v001';W=R.parent/'sea-work/solar_cabin_revision_v006';OUT=R/'godot/assets/models/facilities/bloom_lower_building'
# Same reviewed geometric cleanup as the upper building, without executing its export.
helper=(R/'tools/blender/solar_cabin_revision_v006/export.py').read_text();exec(helper[helper.index('def sha('):helper.index("source=SRC/")])
source=SRC/'bloom_lower_building.blend';source_hash=sha(source);palette=R/'art_source/shared/palettes/sea_cozy_8x8_512.png';palette_hash=sha(palette)
cat=json.loads((SRC/'catalog.json').read_text())['components'];layout=json.loads((SRC/'component_instances.json').read_text())['instances'];byid={e['asset_id']:e for e in cat}
bpy.ops.wm.open_mainfile(filepath=str(source));bpy.context.preferences.filepaths.save_version=0
new=bpy.data.scenes.new('太阳能木屋-七层海下基座-独立优化');entries=[]
for e in cat:
 col=bpy.data.collections.new('EXPORT_BLB_'+e['key']);new.collection.children.link(col);ops=[]
 for ob in bpy.data.collections[e['collection']].all_objects:
  if ob.type!='MESH':continue
  cp=ob.copy();cp.data=ob.data.copy();cp.parent=None;cp.matrix_world=Matrix.Identity(4);col.objects.link(cp);ops.append(cleanup(cp));cp.name=e['key']+'_mesh'
 entries.append(dict(key=e['key'],asset_id=e['asset_id'],name=e['name'],category=e['category'],collection=col.name,bounds=bounds(list(col.objects)),optimization=ops,source=e['component_source'],source_sha256=sha(R/e['component_source'])))
for s in list(bpy.data.scenes):
 if s!=new:bpy.data.scenes.remove(s)
bpy.context.window.scene=new;bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
D.mkdir(parents=True,exist_ok=True);opt=D/'bloom_lower_building_optimized_v001.blend';bpy.ops.wm.save_as_mainfile(filepath=str(opt),compress=True);bpy.ops.wm.open_mainfile(filepath=str(opt))
for e in entries:
 bpy.ops.object.select_all(action='DESELECT');col=bpy.data.collections[e['collection']]
 for ob in col.objects:ob.select_set(True)
 bpy.context.view_layer.objects.active=next(iter(col.objects));p=OUT/'components'/e['key']/(e['key']+'.glb');p.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.export_scene.gltf(filepath=str(p),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_image_format='NONE',export_texcoords=True,export_normals=True,export_cameras=False,export_lights=False)
 with p.open('rb') as f:f.read(12);length,tag=struct.unpack('<II',f.read(8));gl=json.loads(f.read(length))
 assert not gl.get('images') and not gl.get('textures');e.update(glb=str(p.relative_to(R)),glb_sha256=sha(p),exported_triangles=sum(gl['accessors'][p['indices']]['count']//3 for m in gl['meshes'] for p in m['primitives']))
# Fit the existing seven floors below the house: top slab meets the upper deck underside.
# No rotation; long facade continues fore/aft. Horizontal fit is baked in instance matrices.
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)));fit=Matrix.Translation((5.533,1.46-12.32*1.5,1.6))@Matrix.Diagonal((2.5,1.5,1.5,1))
runtime=[];excluded=[]
for i in layout:
 e=byid[i['asset_id']];m=Matrix.Translation(Vector(i['position']))@Euler(i['rotation_euler_xyz'],'XYZ').to_matrix().to_4x4()@Matrix.Diagonal(Vector(i['scale']+[1]));bmin=e['bounds_min'];sz=e['bounds_size'];corners=[m@Vector((bmin[0]+x*sz[0],bmin[1]+y*sz[1],bmin[2]+z*sz[2])) for x in [0,1] for y in [0,1] for z in [0,1]]
 if e['key'] in ['roof_tile','roof_rim'] or (e['category']=='flora' and max(v.z for v in corners)>12.30):
  excluded.append({'name':i['name'],'component':e['key'],'reason':'roof interface covered by upper building; avoid penetrating top floor'});continue
 if e['key'] in ['pink_flower','white_flower']:m=m@Matrix.Diagonal((.75,.75,.75,1))
 world=fit@C@m@C.inverted();runtime.append(dict(component=e['key'],asset_id=e['asset_id'],category=e['category'],module='submerged_base',transform=[list(world[j]) for j in range(3)]))
assert sha(source)==source_hash and sha(palette)==palette_hash
lookup={e['asset_id']:e for e in entries};data=dict(version='1.0',source_version='v001',source=str(source.relative_to(R)),fit_scale_blender=[2.5,1.5,1.5],anchor_godot=[5.533,1.46-12.32*1.5,1.6],roof_contact_y=1.46,storeys=7,instances=runtime,excluded=excluded)
write(OUT/'instances.json',data)
report=dict(source=str(source.relative_to(R)),source_sha256=source_hash,optimized_source=str(opt.relative_to(R)),optimized_sha256=sha(opt),palette_source=str(palette.relative_to(R)),palette_sha256=palette_hash,components=entries,fit=data,expanded_triangles_before=sum(sum(o['triangles_before'] for o in lookup[i['asset_id']]['optimization']) for i in runtime),expanded_triangles_after=sum(lookup[i['asset_id']]['exported_triangles'] for i in runtime))
write(D/'export_manifest.json',report);write(W/'lower_export_manifest.json',report);print('LOWER_EXPORT_COMPLETE',len(entries),len(runtime),len(excluded),flush=True)

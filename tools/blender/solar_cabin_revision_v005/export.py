# -*- coding: utf-8 -*-
"""Create a protected optimized export copy and component GLBs for the home."""
import bpy,bmesh,json,hashlib,math,os,struct
from pathlib import Path
from mathutils import Matrix,Euler,Vector
R=Path(__file__).resolve().parents[3];SRC=R/'art_source/scenes/sunny_bloom_retreat/v005';D=SRC/'export/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v005';OUT=R/'godot/assets/models/facilities/solar_cabin';LEGACY=R/'godot/assets/models/facilities/legacy_home'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def triangles(me):me.calc_loop_triangles();return len(me.loop_triangles)
def bounds(obs):
 coords=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
 return dict(min=[min(p[i] for p in coords) for i in range(3)],max=[max(p[i] for p in coords) for i in range(3)])
def cleanup(ob):
 me=ob.data;before=triangles(me);bm=bmesh.new();bm.from_mesh(me);uv=bm.loops.layers.uv.active;cell=bm.faces.layers.int.new('PaletteCell') if uv else None
 if uv:
  for f in bm.faces:
   p=f.loops[0][uv].uv;f[cell]=min(7,max(0,int(p.x*8)))+8*min(7,max(0,int(p.y*8)))
 duplicates_before=len(bm.verts);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
 deg=[f for f in bm.faces if f.calc_area()<1e-12]
 if deg:bmesh.ops.delete(bm,geom=deg,context='FACES_ONLY')
 face_keys=set();dupes=[]
 bm.verts.index_update()
 for f in bm.faces:
  key=(tuple(sorted(v.index for v in f.verts)),f.material_index,f[cell] if cell else -1)
  if key in face_keys:dupes.append(f)
  else:face_keys.add(key)
 if dupes:bmesh.ops.delete(bm,geom=dupes,context='FACES_ONLY')
 for e in bm.edges:
  if cell and len(e.link_faces)==2 and e.link_faces[0][cell]!=e.link_faces[1][cell]:e.seam=True
 # Dissolve only negligible coplanar subdivisions; preserve color/material seams.
 before_faces=len(bm.faces)
 bmesh.ops.dissolve_limit(bm,angle_limit=.003,verts=list(bm.verts),edges=list(bm.edges),delimit={'MATERIAL','SEAM'},use_dissolve_boundaries=False)
 if uv:
  for f in bm.faces:
   c=f[cell];u=(c%8+.5)/8;v=(c//8+.5)/8
   for j,l in enumerate(f.loops):l[uv].uv=(u+.025*math.cos(2*math.pi*j/len(f.loops)),v+.025*math.sin(2*math.pi*j/len(f.loops)))
 loose_edges=[e for e in bm.edges if not e.link_faces]
 if loose_edges:bmesh.ops.delete(bm,geom=loose_edges,context='EDGES')
 loose=[v for v in bm.verts if not v.link_faces]
 if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
 after_faces=len(bm.faces);after_verts=len(bm.verts);bm.to_mesh(me);bm.free();me.update()
 return dict(triangles_before=before,triangles_after=triangles(me),zero_area_faces_removed=len(deg),duplicate_faces_removed=len(dupes),vertices_merged_or_removed=duplicates_before-after_verts,coplanar_faces_dissolved=before_faces-after_faces,operations=['merge coincident geometry 1e-7m, preserve per-loop UV/color seams','remove zero-area and duplicate faces','dissolve coplanar subdivisions <=0.003 rad with color/material seams locked','remove unused vertices/edges','rebuild nonzero PaletteUV islands in original swatches' if uv else 'preserve legacy UV and vertex colors'],budget=None,budget_reason='User prioritizes style/fidelity; no numeric game triangle cap specified.')
source=SRC/'sunny_bloom_retreat.blend';original_hash=sha(source);palette=R/'art_source/shared/palettes/sea_cozy_8x8_512.png';palette_hash=sha(palette)
catalog=json.loads((SRC/'catalog.json').read_text());components=catalog.get('components',catalog.get('items',[]));assert len(components)<=50
instances=json.loads((SRC/'component_instances.json').read_text())['instances']
bpy.ops.wm.open_mainfile(filepath=str(source));bpy.context.preferences.filepaths.save_version=0
new=bpy.data.scenes.new('太阳能木屋-独立优化输出');new.unit_settings.system='METRIC';entries=[]
for e in components:
 col=bpy.data.collections.new('EXPORT_'+e['key']);new.collection.children.link(col);ops=[]
 source_col=bpy.data.collections[e['collection']]
 for ob in source_col.all_objects:
  if ob.type!='MESH':continue
  copy=ob.copy();copy.data=ob.data.copy();copy.parent=None;copy.matrix_world=Matrix.Identity(4);col.objects.link(copy)
  # Legacy materials are handled separately; source palette islands only here.
  ops.append(cleanup(copy));copy.name=e['key']+('_emissive' if 'emissive' in ob.name else '_mesh')
 entries.append(dict(key=e['key'],asset_id=e['asset_id'],name=e['name'],category=e['category'],collection=col.name,bounds=bounds(list(col.objects)),optimization=ops))
legacy=json.loads((SRC.parent/'v003/export/v001/export_manifest.json').read_text())['legacy']
for sc in list(bpy.data.scenes):
 if sc!=new:bpy.data.scenes.remove(sc)
bpy.context.window.scene=new
# Remove orphan studio/library geometry; only explicit output collections survive.
bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
D.mkdir(parents=True,exist_ok=True);optimized=D/'solar_cabin_optimized_v001.blend';bpy.ops.wm.save_as_mainfile(filepath=str(optimized),compress=True)
# Export only after saving and reopening the persistent optimized file.
bpy.ops.wm.open_mainfile(filepath=str(optimized));scene=bpy.context.scene
for e in entries:
 bpy.ops.object.select_all(action='DESELECT');col=bpy.data.collections[e['collection']]
 for ob in col.all_objects:ob.select_set(True)
 bpy.context.view_layer.objects.active=next(iter(col.all_objects))
 p=(OUT/'components'/e['key']/(e['key']+'.glb')) if e in entries else (LEGACY/(e['key']+'.glb'))
 p.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.export_scene.gltf(filepath=str(p),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_image_format='NONE' if e in entries else 'AUTO',export_texcoords=True,export_normals=True,export_cameras=False,export_lights=False,export_extras=True)
 e['glb']=str(p.relative_to(R));e['glb_sha256']=sha(p)
 with p.open('rb') as f:f.read(12);n,t=struct.unpack('<II',f.read(8));gl=json.loads(f.read(n))
 if e in entries:assert not gl.get('images') and not gl.get('textures'),e['key']
 e['material_names']=[m.get('name','') for m in gl.get('materials',[])];e['exported_triangles']=sum(gl['accessors'][p['indices']]['count']//3 for m in gl['meshes'] for p in m['primitives'])
 print('EXPORTED',e['key'],e['exported_triangles'],flush=True)
assert sha(source)==original_hash and sha(palette)==palette_hash
protected={e['source']:e['source_sha256'] for e in legacy};assert all(sha(R/p)==h for p,h in protected.items())
scale=1.15;anchor=[5.128,1.368,.704];C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
runtime=[];byid={e['asset_id']:e for e in entries}
for i in instances:
 e=byid[i['asset_id']];m=Matrix.Translation(Vector(i['position']))@Euler(i['rotation_euler_xyz'],'XYZ').to_matrix().to_4x4()@Matrix.Diagonal(Vector(i['scale']+[1]))
 world=Matrix.Translation(Vector(anchor))@Matrix.Diagonal((scale,scale,scale,1))@C@m@C.inverted()
 if e['key'] in {'foundation','pier'}:
  h=e['bounds']['max'][2]-e['bounds']['min'][2];world.translation.y=1.12;world[1][1]+= .248/h
 runtime.append(dict(component=e['key'],asset_id=e['asset_id'],category=e['category'],module=i['module'],transform=[list(world[j]) for j in range(3)]))
write(OUT/'instances.json',dict(version='1.2',source_version='v005',scale=scale,total_scale_over_v003=1.725,revision_scale=1.5,anchor_godot=anchor,front_godot=[0,0,1],deck_height=2.15,instances=runtime))
report=dict(source=str(source.relative_to(R)),source_sha256=original_hash,optimized_source=str(optimized.relative_to(R)),optimized_sha256=sha(optimized),palette_source=str(palette.relative_to(R)),palette_sha256=palette_hash,protected_legacy=protected,components=entries,legacy=legacy,fit=dict(uniform_scale=scale,yaw_degrees=0,anchor_godot=anchor,source_front='-Y',godot_front='+Z',wall_width_m=8.625,revision_scale=1.5,total_scale_over_v003=1.725,deck_height_m=2.15,foundation_contact_y=1.12),expanded_triangles_before=sum(sum(o['triangles_before'] for o in byid[i['asset_id']]['optimization']) for i in instances),expanded_triangles_after=sum(byid[i['asset_id']]['exported_triangles'] for i in instances))
write(D/'export_manifest.json',report);write(W/'export_manifest.json',report);print('EXPORT_COMPLETE',flush=True)

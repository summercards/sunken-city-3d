"""Optimize each source component only in a separately saved derivative."""
import bpy,bmesh,json,hashlib,math,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v003';W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop/v003';source=D/'floating_shop.blend';E=D/'export/v001';E.mkdir(parents=True,exist_ok=True);OPT=E/'floating_shop_optimized_v001.blend';pal=R/json.loads((D/'component_plan.json').read_text())['palette']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();beforehash=sha(source);palhash=sha(pal);sc=bpy.data.scenes['海上悬浮商铺_v003'];bpy.context.window_manager.windows[0].scene=sc
colors={x['name']:x for x in json.loads(pal.with_suffix('.json').read_text())['cells']};code=(R/'tools/blender/floating_shop/build.py').read_text(encoding='utf-8');exec(code[code.index('def uvmap('):code.index('components={}')])
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));rows=[]
for e in cat['components']:
 col=bpy.data.collections[e['collection']];sc.collection.children.link(col);before=after=0;collapsed=0;cleaned=0
 for o in col.objects:
  if o.type!='MESH':continue
  o.data=o.data.copy();me=o.data;me.calc_loop_triangles();before+=len(me.loop_triangles);bm=bmesh.new();bm.from_mesh(me);v0=len(bm.verts);f0=len(bm.faces)
  bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7)
  bad=[f for f in bm.faces if f.calc_area()<1e-12]
  if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
  loose=[v for v in bm.verts if not v.link_faces]
  if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
  # Each source mesh has one palette cell; remap UV after safe planar dissolve.
  bmesh.ops.dissolve_limit(bm,angle_limit=.005,verts=list(bm.verts),edges=list(bm.edges),delimit={'MATERIAL','SHARP'})
  cleaned+=max(0,v0-len(bm.verts))+max(0,f0-len(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
  eligible=e['key'] in {'tire','life_ring','foliage','flowers','float_pod','engine','aux_nozzle','counterweight','bollard'} and len(me.polygons)>250
  if eligible:
   bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;mo=o.modifiers.new('受控曲面精简','DECIMATE');mo.ratio=.72;mo.use_collapse_triangulate=False;bpy.ops.object.modifier_apply(modifier=mo.name);collapsed+=1
  uvmap(o);me=o.data;me.calc_loop_triangles();after+=len(me.loop_triangles)
 rows.append({'asset_id':e['asset_id'],'key':e['key'],'triangles_before':before,'triangles_after':after,'reduction_ratio':(before-after)/before if before else None,'operations':{'merge_distance_m':1e-6,'degenerate_distance_m':1e-7,'planar_dissolve_angle_rad':.005,'surface_collapse_ratio':.72 if collapsed else None,'surface_meshes_collapsed':collapsed,'cleanup_elements_removed':cleaned,'palette_uv_reprojected_same_cell':True},'budget':None,'budget_source':'user supplied no triangle cap','retained_faces':'underside/back/internal faces kept unless degenerate; no assumed invisible-face deletion'})
 sc.collection.children.unlink(col)
for im in bpy.data.images:
 if im.source=='FILE' and ('sea_cozy' in im.filepath or 'sea_cabin_timber' in im.filepath):im.filepath=str(pal)
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OPT),compress=True)
assert sha(source)==beforehash and sha(pal)==palhash
counts={x['key']:x for x in rows};layout=json.loads((D/'component_instances.json').read_text())['instances'];bt=sum(counts[x['key']]['triangles_before'] for x in layout);at=sum(counts[x['key']]['triangles_after'] for x in layout)
q={'schema':'sea.scene.optimization','asset_id':'SEA-SCENE-FSH-ASSEMBLY','role':'optimized','source':source.relative_to(R).as_posix(),'source_sha256_before':beforehash,'source_sha256_after':sha(source),'optimized':OPT.relative_to(R).as_posix(),'optimized_sha256':sha(OPT),'palette_sha256_before':palhash,'palette_sha256_after':sha(pal),'triangles_before':bt,'triangles_after':at,'reduction_ratio':(bt-at)/bt,'components':rows,'fidelity_status':'pending_render_review','project_export_contract':'SEA-ASSET-R35 retains a single assembly GLB merged into four stable material meshes; per-component optimization recorded separately.'}
(E/'optimization_manifest.json').write_text(json.dumps(q,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('OPTIMIZED',bt,at, 'scene export properties:',[p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties if 'scene' in p.identifier])

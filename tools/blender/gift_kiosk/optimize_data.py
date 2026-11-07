"""02b data-only cleanup avoids Blender 4.5 collection-instance operator crashes."""
import bpy,bmesh,json,hashlib,os
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/gift_kiosk/v001';OD=D/'export/v001';OPT=OD/'gift_kiosk_optimized_v001.blend';SOURCE=D/'gift_kiosk.blend';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));verified=json.loads((W/'source_verification.json').read_text())
assert verified['passed'] and sha(SOURCE)==verified['source_sha256'];assert Path(bpy.data.filepath).resolve()==OPT.resolve()
protected={str(p):sha(p) for p in [SOURCE,R/plan['palette']]+[R/e['component_source'] for e in cat['components']]}
records=[]
for e in cat['components']:
 col=bpy.data.collections[e['collection']]
 cleanup={'loose_vertices_removed':0,'degenerate_faces_removed':0,'duplicate_faces_removed':0,'vertices_merged':0}
 for o in col.objects:
  bm=bmesh.new();bm.from_mesh(o.data)
  bad=[f for f in bm.faces if f.calc_area()<1e-11];cleanup['degenerate_faces_removed']+=len(bad)
  if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
  seen=set();dup=[]
  for face in bm.faces:
   key=tuple(sorted(tuple(round(c,7) for c in v.co) for v in face.verts))
   if key in seen:dup.append(face)
   else:seen.add(key)
  cleanup['duplicate_faces_removed']+=len(dup)
  if dup:bmesh.ops.delete(bm,geom=dup,context='FACES')
  loose=[v for v in bm.verts if not v.link_faces];cleanup['loose_vertices_removed']+=len(loose)
  if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
  before=len(bm.verts);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7);cleanup['vertices_merged']+=before-len(bm.verts)
  # Keep original n-gon/quad boundaries and custom normals when no change was
  # needed. Export reads Blender's evaluated loop triangulation directly.
  changed=bool(bad or dup or loose or len(bm.verts)!=before)
  if changed:bm.to_mesh(o.data);o.data.update()
  bm.free()
 triangles=0
 for o in col.objects:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
 records.append({'asset_id':e['asset_id'],'key':e['key'],'source':e['component_source'],'source_sha256_before':protected[str(R/e['component_source'])],'optimized_source':OPT.relative_to(R).as_posix(),'role':'optimized','version':'v001','triangles_before':e['triangles'],'triangles_after':triangles,'reduction_ratio':(e['triangles']-triangles)/e['triangles'],'meshes_before':len(col.objects),'meshes_after':len(col.objects),'export_meshes_after':len(e['material_roles']),'cleanup':cleanup,'operations':['check and remove degenerate/duplicate/loose geometry per mesh','merge confirmed coincident vertices at 1e-7m preserving per-corner PaletteUV','retain all visible 3-segment bevels, bottoms, backs and interfaces','consolidate the exported GLB primitives by material role without changing scene object membership'],'budget':None,'budget_source':'user requested reference fidelity, no face cap','retained_faces_reason':'undersides and backs are explicitly shown in supplied reference; no speculative culling','zero_triangle_reduction_reason':'no additional safe reduction after required cleanup' if triangles==e['triangles'] else None,'role_meshes':[{'name':e['key']+'__'+role,'role':role} for role in e['material_roles']]})
for im in bpy.data.images:
 if im.source=='FILE':im.filepath=bpy.path.relpath(str(R/plan['palette']),start=str(OPT.parent))
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':area.spaces.active.shading.type='SOLID'
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OPT),compress=True)
for path,expected in protected.items():assert sha(Path(path))==expected,path
report={'schema':'sea.scene.optimization_manifest','passed':True,'source':SOURCE.relative_to(R).as_posix(),'source_sha256_before':protected[str(SOURCE)],'source_sha256_after':sha(SOURCE),'optimized_source':OPT.relative_to(R).as_posix(),'optimized_sha256':sha(OPT),'protected_sources':protected,'components':records,'master_triangles_before':sum(e['triangles_before'] for e in records),'master_triangles_after':sum(e['triangles_after'] for e in records),'expanded_triangles_before':verified['expanded_triangles'],'export_axis':'Blender(x,y,z)->Godot(x,z,-y)','fidelity':'pending_same_camera_renders','exporter':'data-only GLB writer executed inside active Blender MCP; no dependency-graph operator'}
(OD/'optimization_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('OPTIMIZED_DATA',report['master_triangles_before'],report['master_triangles_after'],flush=True)

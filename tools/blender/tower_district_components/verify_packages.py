import bpy,json,os
from pathlib import Path
from mathutils import Vector
ROOT=Path('/Users/summercards/WorkBuddy/sea');LIB=ROOT/'art_source/environments/tower_zones/tower_district/source/common_components/v008';QA=ROOT/'outputs/tower_district/component_migration_v008/qa'
catalog=json.loads((LIB/'component_catalog.json').read_text())['components'];reports=[]
for i,meta in enumerate(catalog):
 bpy.ops.wm.open_mainfile(filepath=meta['component_blend']);s=bpy.context.scene;co=bpy.data.collections[meta['collection']];rt=bpy.data.objects[meta['root_object']];issues=[]
 if s.name!='Component_'+meta['slug']:issues.append('wrong standalone scene')
 if s.camera is None:issues.append('no preview camera')
 if co.instance_offset.length>1e-8:issues.append('nonzero collection offset')
 if max(abs(rt.matrix_local[j][k]-(1 if j==k else 0)) for j in range(4) for k in range(4))>1e-8:issues.append('nonidentity root')
 meshes=[o for o in co.objects if o.type=='MESH'];verts=[];faces=0
 for ob in meshes:
  if ob.parent!=rt:issues.append('wrong root parent')
  if max(abs(ob.matrix_local[j][k]-(1 if j==k else 0)) for j in range(4) for k in range(4))>1e-8:issues.append('nonidentity mesh')
  verts.extend(v.co[:] for v in ob.data.vertices);uv=ob.data.uv_layers.get('PaletteUV')
  if uv is None or not uv.active_render:issues.append('UV contract')
  else:
   for p in ob.data.polygons:
    points=[uv.data[k].uv for k in p.loop_indices];u=[p.x for p in points];v=[p.y for p in points]
    if len({(int(p.x*16),int(p.y*16)) for p in points})!=1 or max(u)-min(u)<.001 or max(v)-min(v)<.001:issues.append('UV island invalid');break
  faces+=len(ob.data.polygons)
  isemit=any('Emission' in m.name for m in ob.data.materials)
  if isemit and '自发光' not in ob.name:issues.append('emission naming')
  for mat in ob.data.materials:
   for n in mat.node_tree.nodes:
    if n.bl_idname=='ShaderNodeTexImage' and (n.image.packed_file or not os.path.exists(bpy.path.abspath(n.image.filepath))):issues.append('palette external path')
 if not verts:issues.append('empty package')
 else:
  low=[min(v[j] for v in verts) for j in range(3)];high=[max(v[j] for v in verts) for j in range(3)]
  if max(abs(low[2]),abs(low[0]+high[0]),abs(low[1]+high[1]))>1e-4:issues.append('anchor bottom/center')
  if max(abs(high[j]-low[j]-meta['bounds_size_m'][j]) for j in range(3))>1e-4:issues.append('size mismatch')
 if len([o for o in s.objects if o.type=='MESH'])!=len(meshes):issues.append('unrelated mesh in standalone file')
 report={'component_id':meta['component_id'],'slug':meta['slug'],'file':meta['component_blend'],'mesh_count':len(meshes),'uv_faces':faces,'pass':not issues,'issues':issues};reports.append(report)
 if meta['slug'] in ['sedan','pavement_tile','warning_light_bank']:
  s.render.resolution_x=768;s.render.resolution_y=512;s.render.filepath=str(QA/('component_'+meta['slug']+'.png'));bpy.ops.render.render(write_still=True)
 print('PACKAGE_CHECK '+json.dumps({'done':i+1,'total':len(catalog),'slug':meta['slug'],'pass':not issues,'issues':issues}),flush=True)
result={'pass':all(r['pass'] for r in reports),'standalone_blend_count':len(list((LIB/'component_packages').glob('*/*.blend'))),'manifest_count':len(list((LIB/'component_packages').glob('*/asset_manifest.json'))),'catalog_count':len(catalog),'packages':reports}
assert result['standalone_blend_count']==result['manifest_count']==result['catalog_count']
(QA/'standalone_packages_verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print('ALL_PACKAGES_VERIFIED '+str(result['pass']),flush=True)

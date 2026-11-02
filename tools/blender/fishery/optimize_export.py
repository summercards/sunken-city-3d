"""Protected-source -> saved optimized derivative -> reopen -> individual GLBs."""
import bpy,bmesh,math,json,hashlib,os,struct
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/wild_fishery/v001';E=D/'export/v001';E.mkdir(parents=True,exist_ok=True)
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'wild_fishery/v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];LAY=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
qa=json.loads((W/'source_verification.json').read_text(encoding='utf-8'));assert qa['passed']
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
source=D/'wild_fishery.blend';original=sha(source);OPT=E/'wild_fishery_optimized_v001.blend';palette=R/P['palette'];palhash=sha(palette)
assert original==qa['source_sha256']
bpy.ops.wm.open_mainfile(filepath=str(source));bpy.context.preferences.filepaths.save_version=0
def uvmap(ob):
 cells={c['name']:c for c in json.loads(palette.with_suffix('.json').read_text(encoding='utf-8'))['cells']};c=cells[ob['palette_cell']]
 uv=ob.data.uv_layers['PaletteUV'];uv.active_render=True;ob.data.uv_layers.active_index=0;u=(c['column']+.5)/8;v=1-(c['row']+.5)/8
 for face in ob.data.polygons:
  for j,li in enumerate(face.loop_indices):
   a=math.tau*j/len(face.loop_indices);uv.data[li].uv=(u+.026*math.cos(a),v+.026*math.sin(a))
rows=[]
for e in CAT:
 before=0;after=0;removed=0
 col=bpy.data.collections[e['collection']]
 for ob in col.objects:
  if ob.type!='MESH':continue
  ob.data=ob.data.copy();me=ob.data;me.calc_loop_triangles();before+=len(me.loop_triangles)
  bm=bmesh.new();bm.from_mesh(me);v0=len(bm.verts);f0=len(bm.faces)
  bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
  bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7)
  bad=[f for f in bm.faces if f.calc_area()<1e-12]
  if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
  loose=[v for v in bm.verts if not v.link_faces]
  if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
  bmesh.ops.dissolve_limit(bm,angle_limit=.002,verts=list(bm.verts),edges=list(bm.edges),delimit={'MATERIAL','SHARP'})
  removed+=max(0,v0-len(bm.verts))+max(0,f0-len(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
  bm.to_mesh(me);bm.free();me.update();uvmap(ob);me.calc_loop_triangles();after+=len(me.loop_triangles)
 # Consolidate surfaces within each independently reusable component. The
 # editable source remains split; a net segment should cost one draw, not
 # one draw per strand. All parts share SEA_Matte and preserve face UVs.
 parts=[ob for ob in col.objects if ob.type=='MESH'];root=next(ob for ob in col.objects if ob.type=='EMPTY')
 vertices=[];faces=[];uvs=[];smooth=[]
 for ob in parts:
  me=ob.data;offset=len(vertices);vertices.extend(tuple(v.co) for v in me.vertices)
  for face in me.polygons:
   faces.append(tuple(offset+i for i in face.vertices));smooth.append(face.use_smooth);uvs.extend(tuple(me.uv_layers['PaletteUV'].data[li].uv) for li in face.loop_indices)
 merged=bpy.data.meshes.new(e['key']+'_Optimized');merged.from_pydata(vertices,[],faces);merged.update();merged.materials.append(bpy.data.materials['SEA_Matte'])
 uv=merged.uv_layers.new(name='PaletteUV');uv.active_render=True
 for li,co in enumerate(uvs):uv.data[li].uv=co
 for face,is_smooth in zip(merged.polygons,smooth):face.use_smooth=is_smooth
 output=bpy.data.objects.new(e['key']+'_Visual',merged);col.objects.link(output);output.parent=root
 for ob in parts:bpy.data.objects.remove(ob,do_unlink=True)
 xyz=[v.co for o in col.objects if o.type=='MESH' for v in o.data.vertices]
 bounds={'min':[min(v[k] for v in xyz) for k in range(3)],'max':[max(v[k] for v in xyz) for k in range(3)]}
 assert max(abs(bounds[q][k]-e['bounds'][q][k]) for q in ['min','max'] for k in range(3))<1e-5
 rows.append({'asset_id':e['asset_id'],'key':e['key'],'triangles_before':before,'triangles_after':after,'reduction_ratio':(before-after)/before,'operations':{'merge_distance_m':1e-6,'degenerate_distance_m':1e-7,'planar_dissolve_angle_rad':.002,'cleanup_elements_removed':removed,'uv_reprojected_to_original_cell':True,'source_mesh_count':len(parts),'runtime_mesh_count':1,'merged_within_single_component_only':True},'bounds':bounds,'budget_triangles':e['budget_triangles'],'budget_source':e['budget_source'],'retained_faces':'all nondegenerate back/bottom faces retained; enclosure and land may be viewed from below','zero_reduction_reason':'no safely redundant geometry after cleanup' if after==before else None})
bpy.ops.wm.save_as_mainfile(filepath=str(OPT),compress=True)
assert sha(source)==original and sha(palette)==palhash
manifest={'schema':'sea.scene.optimization','role':'optimized','source':source.relative_to(R).as_posix(),'optimized':OPT.relative_to(R).as_posix(),'source_sha256_before':original,'source_sha256_after':sha(source),'optimized_sha256':sha(OPT),'palette_sha256_before':palhash,'palette_sha256_after':sha(palette),'components':rows,'fidelity_status':'pending_same_camera_review'}
(E/'optimization_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Reopen persisted derivative; export never consumes the in-memory source.
bpy.ops.wm.open_mainfile(filepath=str(OPT));bpy.context.window.scene=bpy.data.scenes['野外渔场_v001']
exports=[]
for e in CAT:
 col=bpy.data.collections[e['collection']];ex=bpy.data.scenes.new('TRANSFER_'+e['key']);ex.collection.children.link(col);bpy.context.window.scene=ex
 bpy.ops.object.select_all(action='DESELECT')
 for ob in col.objects:ob.select_set(True)
 path=R/'godot/assets/models/fishery'/e['key']/(e['key']+'.glb');path.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_active_scene=True,use_selection=True,export_yup=True,export_materials='EXPORT',export_image_format='NONE',export_texcoords=True,export_normals=True,export_cameras=False,export_lights=False,export_extras=True,export_apply=False)
 raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+length]);assert not doc.get('images') and not doc.get('textures')
 triangles=sum(doc['accessors'][p['indices']]['count']//3 for m in doc['meshes'] for p in m['primitives'])
 for m in doc['meshes']:
  for p in m['primitives']:assert 'TEXCOORD_0' in p['attributes'] and 'TEXCOORD_1' not in p['attributes']
 exports.append({'key':e['key'],'asset_id':e['asset_id'],'runtime_path':path.relative_to(R).as_posix(),'runtime_sha256':sha(path),'triangles':triangles,'role':'from_saved_optimized_derivative','materials':[m['name'] for m in doc.get('materials',[])],'mesh_count':len(doc['meshes']),'embedded_images':False})
 bpy.context.window.scene=bpy.data.scenes['野外渔场_v001'];bpy.data.scenes.remove(ex)
assert sha(source)==original and sha(OPT)==manifest['optimized_sha256'] and sha(palette)==palhash
(E/'export_manifest.json').write_text(json.dumps({'source':manifest['source'],'optimized':manifest['optimized'],'source_hash_unchanged':True,'optimized_hash_unchanged':True,'exports':exports},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
scene=bpy.data.scenes['野外渔场_v001'];cam=scene.camera;target=Vector((-5,-4,-.5))
for name,pos in {'oblique':(-18,-23,22),'back':(12,13,16),'side':(-27,-1,8),'top':(-5,-4,34),'shore_close':(-8,-9,10)}.items():
 aim=Vector((0,0,.2)) if name=='shore_close' else target;cam.location=pos;cam.rotation_euler=(aim-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=10 if name=='shore_close' else (29 if name=='top' else 24)
 scene.render.filepath=str(W/('optimized_'+name+'.png'));bpy.ops.render.render(write_still=True)
print('FISHERY_OPTIMIZED_EXPORTED',sum(r['triangles_before'] for r in rows),sum(r['triangles_after'] for r in rows),len(exports),flush=True)

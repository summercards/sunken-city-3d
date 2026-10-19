import bpy,json,math,hashlib,re,os
from mathutils import Vector,Matrix
from pathlib import Path
ROOT=Path('/Users/summercards/WorkBuddy/sea');LIB=ROOT/'art_source/environments/tower_zones/tower_district/source/common_components/v008';QA=ROOT/'outputs/tower_district/component_migration_v008/qa'
plan=json.loads((LIB/'component_plan.json').read_text());doc=json.loads((LIB/'component_instances.json').read_text());catalog=json.loads((LIB/'component_catalog.json').read_text())['components'];source_sha=hashlib.sha256(Path(plan['source_blend']).read_bytes()).hexdigest()
s=bpy.context.scene;s.frame_set(1);s.eevee.shadow_pool_size='1024';s.eevee.shadow_resolution_scale=.5
for ob in list(bpy.data.objects):
 if ob.name.startswith('JSON_'):bpy.data.objects.remove(ob,do_unlink=True)
for old in list(bpy.data.scenes):
 if old.name.startswith('TD_JSON重放验收'):bpy.data.scenes.remove(old)
for old in list(bpy.data.collections):
 if old.name.startswith('JSON重放_'):bpy.data.collections.remove(old)
report={'source_sha256_unchanged':source_sha==plan['source_blend_sha256'],'component_count':len(catalog),'instance_count':len(doc['instances']),'legacy_static_mesh_count':66,'source_cuboids_covered':plan['source_cuboid_count'],'issues':[],'not_executed':{'godot':'User requested Blender model hierarchy only; workspace has no Godot project.','cross_room_interop':'Standalone reference scene has one actual consumer; no additional room types asserted.'},'historical_presentation_scales':[d['instance_id'] for d in doc['instances'] if d['historical_uniform_presentation_scale']]}
assert report['source_sha256_unchanged']
components={m['component_id']:bpy.data.collections[m['collection']] for m in catalog}
report['master_checks']=[];palette_images=set();roles=set();alluv=0
for meta in catalog:
 co=components[meta['component_id']];root=bpy.data.objects[meta['root_object']];meshes=[o for o in co.objects if o.type=='MESH'];vertices=[];entry={'component_id':meta['component_id'],'root_identity':max(abs(root.matrix_local[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))<1e-8,'collection_offset_zero':co.instance_offset.length<1e-8,'mesh_transforms_identity':True,'uv_faces':0,'issues':[]}
 for o in meshes:
  if max(abs(o.matrix_local[i][j]-(1 if i==j else 0)) for i in range(4) for j in range(4))>1e-8:entry['mesh_transforms_identity']=False
  vertices.extend([v.co for v in o.data.vertices]);uv=o.data.uv_layers.get('PaletteUV')
  if not uv or not uv.active_render:entry['issues'].append('missing or inactive PaletteUV');continue
  for p in o.data.polygons:
   cc=[uv.data[i].uv for i in p.loop_indices];us=[v.x for v in cc];vs=[v.y for v in cc]
   if len({(int(v.x*16),int(v.y*16)) for v in cc})!=1 or max(us)-min(us)<.001 or max(vs)-min(vs)<.001:entry['issues'].append('UV island invalid');break
   entry['uv_faces']+=1
  emission=any('Emission' in m.name for m in o.data.materials)
  if emission and '自发光' not in o.name:entry['issues'].append('emissive mesh not clearly named')
  if emission and any('Emission' not in m.name for m in o.data.materials):entry['issues'].append('mixed body/emissive mesh')
  for mat in o.data.materials:
   roles.add(mat.name)
   for n in mat.node_tree.nodes:
    if n.bl_idname=='ShaderNodeTexImage':
     palette_images.add(n.image.name)
     if n.interpolation!='Closest' or n.image.packed_file:entry['issues'].append('palette not external nearest')
 lo=[min(v[i] for v in vertices) for i in range(3)];hi=[max(v[i] for v in vertices) for i in range(3)]
 entry['origin_bottom_center']=max(abs(lo[2]),abs(lo[0]+hi[0]),abs(lo[1]+hi[1]))<1e-4
 entry['size_error_m']=max(abs(hi[i]-lo[i]-meta['bounds_size_m'][i]) for i in range(3))
 if not all(entry[k] for k in ['root_identity','collection_offset_zero','mesh_transforms_identity','origin_bottom_center']) or entry['size_error_m']>1e-4:entry['issues'].append('anchor contract failed')
 alluv+=entry['uv_faces'];report['master_checks'].append(entry)
 if entry['issues']:report['issues'].append({meta['slug']:entry['issues']})
report['surface_roles']=sorted(roles);report['palette_images']=sorted(palette_images);report['uv_faces_checked']=alluv
assert len(roles)==4 and len(palette_images)==1
fam={}
for g in plan['groups']:fam[g['component_family']]=fam.get(g['component_family'],0)+1
report['family_counts']=fam
for family,count in fam.items():
 if count>5:report['issues'].append('family >5: '+family)
 if count>3:
  for g in plan['groups']:
   if g['component_family']==family and not all(g.get(k) for k in ['variant_axis','variant_value','variant_reason']):report['issues'].append('family state axis missing: '+family)
assert len(catalog)<=50
# Check actual depsgraph instances: authoring masters must not be drawn directly.
outs=bpy.data.collections['02_游戏输出_独立资产包_v008'];actual=list(outs.all_objects)
report['layout_has_only_collection_instances']=all(o.type=='EMPTY' and o.instance_type=='COLLECTION' for o in actual)
report['master_offsets_zero']=all(co.instance_offset.length<1e-8 for co in components.values())
assert len(actual)==len(doc['instances']) and report['layout_has_only_collection_instances']
# Independent reconstruction from JSON. It deliberately does not copy any existing layout object.
replay=bpy.data.scenes.new('TD_JSON重放验收_v008');replay.world=s.world;replay.render.engine='BLENDER_EEVEE';replay.render.resolution_x=1920;replay.render.resolution_y=810;replay.render.resolution_percentage=60;replay.render.fps=24;replay.frame_start=1;replay.frame_end=240;replay.eevee.taa_render_samples=64;replay.eevee.use_raytracing=s.eevee.use_raytracing;replay.eevee.shadow_pool_size='1024';replay.eevee.shadow_resolution_scale=.5
replay.view_settings.view_transform=s.view_settings.view_transform;replay.view_settings.look=s.view_settings.look;replay.view_settings.exposure=s.view_settings.exposure
rigcol=bpy.data.collections.new('JSON重放_动画控制');replay.collection.children.link(rigcol);layout=bpy.data.collections.new('JSON重放_集合实例');replay.collection.children.link(layout)
rf=bpy.data.objects.new('JSON_ROOM_FRAME',None);rigcol.objects.link(rf);rf.matrix_world=Matrix.Translation(Vector(doc['coordinate_contract']['room_frame_world_translation_m']))
rigs={}
for item in doc['animation_rigs']:
 ob=bpy.data.objects.new('JSON_'+item['name'],None);rigcol.objects.link(ob);rigs[item['name']]=ob
for item in doc['animation_rigs']:
 ob=rigs[item['name']]
 if item['parent']:ob.parent=rigs[item['parent']]
 ob.rotation_mode=item['rotation_mode'];ob.matrix_basis=Matrix(item['matrix_parent_local'])
 for d in item['drivers']:ob.driver_add(d['data_path'],d['array_index']).driver.expression=d['expression']
reconstructed={}
for item in doc['instances']:
 ob=bpy.data.objects.new('JSON_'+item['instance_id'],None);layout.objects.link(ob);ob.instance_type='COLLECTION';ob.instance_collection=components[item['component_id']];ob['palette_shift']=item['palette_shift']
 if item['animation_parent']:ob.parent=rigs[item['animation_parent']];ob.matrix_basis=Matrix(item['matrix_parent_local'])
 else:ob.parent=rf;ob.matrix_basis=Matrix(item['matrix_room_local'])
 reconstructed[item['instance_id']]=ob
report['json_replay_frames']=[]
for frame in [1,61,121,181,241]:
 s.frame_set(frame);replay.frame_set(frame);bpy.context.window.scene=s;s.view_layers[0].update();s_matrices={o.name:o.matrix_world.copy() for o in actual}
 bpy.context.window.scene=replay;replay.view_layers[0].update();err=max(max(abs(ob.matrix_world[i][j]-s_matrices[name][i][j]) for i in range(4) for j in range(4)) for name,ob in reconstructed.items())
 report['json_replay_frames'].append({'frame':frame,'matrix_max_error':err})
 if err>1e-4:report['issues'].append('JSON replay transform error')
# Geometry bboxes must match the original component layout, regardless of atmospheric/background overhang.
def bounds(instances):
 low=[float('inf')]*3;high=[float('-inf')]*3
 for ob in instances:
  for child in ob.instance_collection.objects:
   if child.type!='MESH':continue
   for p in child.bound_box:
    v=ob.matrix_world@child.matrix_local@Vector(p)
    for i in range(3):low[i]=min(low[i],v[i]);high[i]=max(high[i],v[i])
 return [low,high]
s.frame_set(1);replay.frame_set(1);bpy.context.window.scene=s;s.view_layers[0].update();a=bounds(actual);bpy.context.window.scene=replay;replay.view_layers[0].update();b=bounds(reconstructed.values())
report['bbox_original_layout']=a;report['bbox_json_replay']=b;report['bbox_max_error_m']=max(abs(a[i][j]-b[i][j]) for i in range(2) for j in range(3))
if report['bbox_max_error_m']>1e-4:report['issues'].append('JSON replay bbox mismatch')
# Preserve a self-contained JSON replay scene including atmosphere, camera and lighting copies.
env=bpy.data.collections.new('JSON重放_展示环境');replay.collection.children.link(env)
for src in bpy.data.collections['90_展示环境_灯光相机与动态'].all_objects:
 ob=src.copy();ob.name='JSON_'+src.name;env.objects.link(ob)
 if src.parent and src.parent.name in rigs:ob.parent=rigs[src.parent.name]
 if src==s.camera:replay.camera=ob
if s.compositing_node_group:
 nt=s.compositing_node_group.copy();replay.compositing_node_group=nt
 for n in nt.nodes:
  if n.bl_idname=='CompositorNodeRLayers':n.scene=replay
report['pass']=not report['issues']
(QA/'library_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
bpy.context.window.scene=s;s.frame_set(1);s.render.resolution_percentage=100;s.render.filepath=str(QA/'after_reorganization_full.png')
bpy.ops.wm.save_as_mainfile(filepath=str(LIB/'tower_district_components_v008.blend'))
bpy.context.window.scene=replay;replay.frame_set(1);replay.render.filepath=str(QA/'json_replay.png');bpy.ops.render.render(write_still=True)
print('LIBRARY_AND_JSON_REPLAY_VERIFIED '+json.dumps({'pass':report['pass'],'components':len(catalog),'instances':len(actual),'bbox_max_error_m':report['bbox_max_error_m'],'uv_faces':alluv,'issues':report['issues']},ensure_ascii=False),flush=True)

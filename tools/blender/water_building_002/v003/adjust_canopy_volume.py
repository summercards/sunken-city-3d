"""User-directed plant massing only: 18 crowns reused, zero added topology."""
import bpy,json,hashlib,shutil,math,os
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');V2=R/'art_source/scenes/water_building_002/v002';D=R/'art_source/scenes/water_building_002/v003';W=R.parent/'sea-work/water_building_002/v003';S=V2/'water_building_002_v002.blend';OUT=D/'water_building_002_v003.blend'
assert D.is_dir() and W.is_dir();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();parent_sha=sha(S)
# Always reload the accepted technical baseline so retries never multiply the scale.
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False);sc=bpy.context.scene
if not (W/'session_before_volume.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'session_before_volume.blend'),copy=True)
cat=json.loads((V2/'catalog.json').read_text(encoding='utf-8'))['components'];layout=json.loads((V2/'component_instances.json').read_text(encoding='utf-8'));plan=json.loads((V2/'component_plan.json').read_text(encoding='utf-8'));by={x['key']:x for x in cat};live={o.name:o for o in sc.objects}
# Reuse every crown. Values are center coordinates and xyz scale relative to v002.
A=[((6.8,-5.8,10.6),(2.0,1.6,1.5)),((2.2,-6.4,11.4),(2.2,1.9,1.6)),((5.5,-5.7,25.7),(2.,1.9,1.5)),((0.,-5.8,27.2),(2.,1.9,1.4)),((8.,-4.3,33.5),(2.,2.,1.7)),((9.1,.6,36.2),(1.9,1.9,1.7)),((3.8,2.,40.4),(2.3,2.,1.9)),((-.5,2.6,41.8),(2.1,2.2,1.7)),((-7.4,-5.,25.9),(1.8,1.6,1.5)),((-6.7,-5.7,10.6),(2.1,1.8,1.7)),((-7.8,.5,35.5),(2.,2.,1.6)),((-3.8,2.,40.5),(2.3,2.1,1.8))]
B=[((9.,-4.8,11.),(1.9,1.9,1.8)),((-1.9,-7.,10.1),(2.3,2.,2.)),((9.,3.,29.9),(2.,2.,2.)),((3.,4.,40.),(2.2,2.,2.)),((-10.,-3.,10.),(1.9,1.9,1.8)),((-5.,-4.7,35.5),(2.2,1.9,2.))]
# Shared master shape unchanged. Only crown instance volume / centers change.
def signature(o):
 m=o.data;h=hashlib.sha256();m.calc_loop_triangles()
 for v in m.vertices:h.update((','.join(format(float(x),'.8f') for x in v.co)+';').encode())
 for f in m.polygons:h.update(str(tuple(f.vertices)).encode())
 return {'hash':h.hexdigest(),'vertices':len(m.vertices),'polygons':len(m.polygons),'triangles':len(m.loop_triangles)}
def allsig():return {o.name:signature(o) for c in cat for o in bpy.data.collections[c['collection']].all_objects if o.type=='MESH'}
pre=allsig();changes=[]
# Before rendering is evidence, not the old report reused for changed geometry.
sc.camera.location=(52,-70,55);sc.camera.rotation_euler=(Vector((1.,0,20))-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=56
sc.render.filepath=str(W/'before.png');bpy.ops.render.render(write_still=True)
# Duplicate no meshes, leaves, or branches. All 167 instance objects remain.
for key,edits in [('crown_a',A),('crown_b',B)]:
 rows=[x for x in layout['instances'] if x['key']==key];assert len(rows)==len(edits)
 col=bpy.data.collections[by[key]['collection']];pts=[v.co for ob in col.all_objects if ob.type=='MESH' for v in ob.data.vertices];lo=Vector(tuple(min(v[a] for v in pts) for a in range(3)));hi=Vector(tuple(max(v[a] for v in pts) for a in range(3)));local_center=(lo+hi)*.5
 for row,(center,factors) in zip(rows,edits):
  obj=live[row['name']];before={'position':list(obj.location),'scale':list(obj.scale)};obj.scale=factors;obj.location=Vector(center)-Vector(tuple(local_center[a]*factors[a] for a in range(3)));row['position']=list(obj.location);row['scale']=list(obj.scale);row['rotation_euler_xyz']=list(obj.rotation_euler)
  changes.append({'name':obj.name,'key':key,'before':before,'after':{'position':list(obj.location),'scale':list(obj.scale),'center':center},'volume_factor':math.prod(factors),'operation':'existing_instance_scale_and_translation_only'})
post=allsig();assert pre==post,'topology or vertex data changed';assert len(changes)==18
# Non-crown instances are numerically identical to v002.
oldlayout=json.loads((V2/'component_instances.json').read_text(encoding='utf-8'))['instances'];nonchanged=[x['name'] for x in layout['instances'] if x['key'] not in ['crown_a','crown_b'] and x!=next(p for p in oldlayout if p['name']==x['name'])];assert not nonchanged
sc.name='WB002_VegetationMass_v003';sc['source_version']='v003';sc['revision']='existing_canopy_volume_only_no_new_geometry'
for c in cat:
 c['source_version']='v003';c['component_source']=f'art_source/scenes/water_building_002/v003/component_packages/{c["key"]}/{c["key"]}.blend'
 for oldkey in ['package_sha256','package_sha256_before_reopen','package_manifest','package_source_sha256','package_palette_sha256','glb_sha256','glb_path','optimized_triangles','optimized_meshes']:c.pop(oldkey,None)
plan['version']='v003';plan['source_parent']=S.relative_to(R).as_posix();plan['source_parent_sha256']=parent_sha;plan['status']='volume_revision_pending_visual_review';plan['vegetation_volume_revision']={'instruction':'Adjust flourishing ratio by existing volume only; no added detail','mesh_vertex_data_unchanged':True,'crown_instances_before':18,'crown_instances_after':18,'triangles_unchanged':True,'reference_match':'visual_mass_comparison_not_pixel_exact','changes':changes}
for row in plan['components']:
 row['source_version']='v003';row['component_source']=f'art_source/scenes/water_building_002/v003/component_packages/{row["key"]}/{row["key"]}.blend'
(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':cat},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'component_instances.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');shutil.copy2(V2/'reference.jpg',D/'reference.jpg')
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OUT),compress=True)
assert sha(S)==parent_sha;outsha=sha(OUT)
report={'source_parent_sha256':parent_sha,'source_sha256':outsha,'instance_count':len(layout['instances']),'crown_instances':18,'master_mesh_geometry_before':pre,'master_mesh_geometry_after':post,'topology_and_vertices_identical':pre==post,'non_crown_instance_changes':nonchanged,'triangles_before':10342,'triangles_after':10342,'details_added':0,'changes':changes}
(W/'volume_revision.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sc.render.filepath=str(W/'hero.png');bpy.ops.render.render(write_still=True)
print('VOLUME_REVISION',json.dumps({'source':str(OUT),'source_sha256':outsha,'triangles':10342,'instances':167,'changed_crown_instances':18,'new_meshes':0,'new_vertices':0,'new_triangles':0},ensure_ascii=False))

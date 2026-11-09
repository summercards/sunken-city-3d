"""Reject destructive boolean experiment and restore last complete visual candidate.
Does not modify registered v001/v002. Existing reports are rebound only by rerun.
"""
import bpy,json,hashlib,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v003';W=Path('D:/projects/sea-work/bld_20261109_a/v003');S=D/'bld_20261109_a_v003.blend'
if not (W/'fixed_layout_rejected.blend').exists():bpy.ops.wm.save_as_mainfile(filepath=str(W/'fixed_layout_rejected.blend'),copy=True)
# Independent package manifests still contain the complete pre-experiment geometry definitions.
rows=[]
for path in sorted((D/'component_packages').glob('*/asset_manifest.json')):rows.append(json.loads(path.read_text(encoding='utf-8')))
assert len(rows)==49
p=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));old=json.loads((R/'art_source/scenes/bld_20261109_a/v001/component_plan.json').read_text(encoding='utf-8'));witness=json.loads((W/'geometry_witness.json').read_text(encoding='utf-8'))
bpy.ops.wm.open_mainfile(filepath=str(W/'before_fixed_layout.blend'),load_ui=False,use_scripts=False)
sc=bpy.context.scene;assert sc.name=='BLDA_编号海上建筑_v003'
layout=[]
for e in rows:
 c=bpy.data.collections[e['collection']]
 for i in sc.objects:
  if i.instance_type=='COLLECTION' and i.instance_collection==c:layout.append({'name':i.name,'key':e['key'],'asset_id':e['asset_id'],'position':list(i.location),'rotation_euler_xyz':list(i.rotation_euler),'scale':list(i.scale)})
assert len(layout)==92
# Recover the matching complete candidate plan, not the failed fixed-layout plan.
basefields=['key','id','asset_id','name','component_family','family','group','layer','scope','building_class','origin','front_axis','allowed_rotations_z_deg','loaded_responsibility','collision_responsibility','bottom','top','kind','rho','version','form_layer','role','tilt_deg','tilt_kind','form_contract','extent','taper_along','attached_to','d_bottom','d_top']
p['components']=[{k:e[k] for k in basefields if k in e} for e in rows];p['contacts']=witness['contacts'];p['stylized_form']['contacts']=p['contacts'];p['stylized_form']['components']=p['components'];p['stylized_form']['relief']={'layers':2,'quoin_protrusion':.12,'quoin_blocks':4,'brick_blocks':0,'grooves':0,'brackets':4};p['stylized_form']['body']['triangles']=sum(e['triangles']*e['instance_count'] for e in rows if e['key'] in ['shell','slab','post','deck','roof_hut']);p['reference_instance_transforms_locked']=False;p['candidate_status']='partial_latest_contract_not_approved';p['geometry_route']='clean_v001_meshes_to_v003_real_sockets_complete_visual_candidate';p['rejected_experiment']='sea-work/bld_20261109_a/v003/fixed_layout_rejected.blend';p['known_issues']=['all_scene_surface_intersections','brief_requires_original_layout','only_4_quoin_and_4_brackets','not_ready_for_registered_v001_overwrite']
sc.camera.location=(-29,-29,22);sc.camera.rotation_euler=(Vector((0,0,7))-sc.camera.location).to_track_quat('-Z','Y').to_euler();sc.camera.data.ortho_scale=20.6
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(S),compress=True)
sha=hashlib.sha256(S.read_bytes()).hexdigest();witness['source_sha256']=sha;witness['restoration']='Last complete visual geometry restored; fixed-layout boolean experiment rejected.'
for file,data in [('component_plan.json',p),('catalog.json',{'schema':'sea.component_catalog','components':rows}),('component_instances.json',{'schema':'sea.component_instances','coordinate_contract':{'plane':'XY','up':'+Z','rotation':'Euler XYZ radians','godot_mapping':'(x,y,z)->(x,z,-y)'},'instances':layout})]:(D/file).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(W/'geometry_witness.json').write_text(json.dumps(witness,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
visual=json.loads((W/'visual_review.json').read_text(encoding='utf-8'));visual['source_sha256']=sha;visual['notes'].append('Restored the last complete candidate; global boolean failure rejected, no visual geometry promoted to accepted.');(W/'visual_review.json').write_text(json.dumps(visual,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report={'restored':True,'source_sha256':sha,'rejected_boolean_attempt_sha256':hashlib.sha256((W/'fixed_layout_rejected.blend').read_bytes()).hexdigest(),'v001_not_modified':True,'v002_not_modified':True,'stage':'partial_candidate_not_accepted','reports_must_be_rerun':True};(W/'restoration_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('COMPLETE_CANDIDATE_RESTORED',sha)

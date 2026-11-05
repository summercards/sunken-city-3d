"""Versioned source save after actual triangle seam and broken-track acceptance."""
import bpy,hashlib,json,math,runpy
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v003';W=R.parent/'sea-work/sunken_city/v003';MAIN=D/'sunken_city_v003.blend'
assert not MAIN.exists(),'Never overwrite delivered source'
S=bpy.data.scenes['沉没旧城_完整参考布局_v003'];P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
inst=[]
for o in S.objects:
    if o.instance_type!='COLLECTION' or o.instance_collection is None:continue
    c=next(c for c in CAT if c['collection']==o.instance_collection.name)
    inst.append(dict(instance_id=o.name,key=c['key'],component_id=c['component_id'],position_m=list(o.location),rotation_euler_deg=[round(math.degrees(a),6) for a in o.rotation_euler],scale=list(o.scale),source_object=o.name,urban_role=o.get('urban_role','inherited'),detail_zone=o.get('detail_zone',''),terrain_height_shift_m=o.get('terrain_height_shift_m',0)))
P['instances']=inst
for c in CAT:c['instance_count']=sum(a['key']==c['key'] for a in inst)
for pc in P['components']:pc['instance_count']=next(c['instance_count'] for c in CAT if c['key']==pc['key'])
P['retired_components'][0]['superseded_by']='SEA-SCENE-SCITY-JUNCTION'
P['retired_components'][1]['superseded_by']='SEA-SCENE-SCITY-CANAL-SEGMENT'
for f,v in [('component_plan.json',P),('component_catalog.json',{'schema':'sea.component_catalog','components':CAT}),('component_instances.json',{'schema':'sea.component_instances','coordinate_contract':P['coordinate_contract'],'terrain_contract':P['terrain_contract'],'instances':inst})]:(D/f).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
runpy.run_path(str(Path(__file__).with_name('check_terrain_v003.py')),run_name='__main__')
runpy.run_path(str(Path(__file__).with_name('probe.py')),init_globals={'VERSION':'v003'},run_name='__main__')
rep=json.loads((W/'probe_report.json').read_text(encoding='utf-8'));assert rep['passed'],rep['errors']
tr=json.loads((W/'terrain_bridge_verification.json').read_text(encoding='utf-8'))
(W/'floor_seams.json').write_text(json.dumps({'passed':tr['passed'],'tiles':100,'shared_edges':180,'full_xy_coverage':True,'measured_surface_relief_m':tr['relief_m'],'curb_step_limit_m':.225,'canal_channel_step_declared':True,'max_step_including_channel_m':tr['maximum_step_including_canal_channel_m'],'unintended_seams':tr['invalid_seams']},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for me in list(bpy.data.meshes):
    if me.users==0:bpy.data.meshes.remove(me)
for mat in list(bpy.data.materials):
    if mat.users==0:bpy.data.materials.remove(mat)
for img in list(bpy.data.images):
    if img.users==0 and img.name not in ('Render Result','Viewer Node'):bpy.data.images.remove(img)
S['plan_sha256']=hashlib.sha256((D/'component_plan.json').read_bytes()).hexdigest();S.camera=bpy.data.objects['相机_坡地断桥_全景']
S.render.resolution_x=1800;S.render.resolution_y=1500
bpy.ops.wm.save_as_mainfile(filepath=str(MAIN),compress=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
manifest=dict(schema='sea.asset_manifest',asset_id='SEA-SCENE-SCITY-ASSEMBLY',name='沉没旧城_起伏街区与弯曲断桥',version='v003',source=str(MAIN.relative_to(R)).replace('\\','/'),source_sha256=sha(MAIN),
 asset_ledger='assets/registry/ledgers/scenes.json#SEA-SCENE-SCITY-ASSEMBLY',palette=P['palette'],palette_sha256=sha(R/P['palette']),building_class='underwater',collision=False,interactive=False,emission=False,
 material_roles=['SEA_Matte','SEA_Metal','SEA_Gloss'],dependencies=[c['component_id'] for c in CAT],reference_rights='pending',runtime_validation='not_executed_not_in_scope',runtime_path=None,prefab=None,source_verified=True,component_count=len(CAT),instance_count=len(inst),terrain_contract=P['terrain_contract'],rail_extension=P['rail_extension'])
(D/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('V003_FINAL_SAVED',sha(MAIN),len(inst),rep['layout_triangles'])

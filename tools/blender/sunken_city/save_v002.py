"""Save new version only after passing independent local edit checks; never overwrite v001/v002."""
import bpy,hashlib,json,runpy
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v002';W=R.parent/'sea-work/sunken_city/v002'
MAIN=D/'sunken_city_v002.blend';assert not MAIN.exists(),'Delivered source exists, bump version'
runpy.run_path(str(Path(__file__).with_name('verify_detail_v002.py')),run_name='__main__')
runpy.run_path(str(Path(__file__).with_name('probe.py')),init_globals={'VERSION':'v002'},run_name='__main__')
report=json.loads((W/'probe_report.json').read_text(encoding='utf-8'));assert report['passed'],report['errors']
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
S=bpy.data.scenes['沉没旧城_完整参考布局_v002'];S.camera=bpy.data.objects['相机_补景_红框全景']
S.render.resolution_x=1800;S.render.resolution_y=1600
for screen in bpy.data.screens:
    for ar in screen.areas:
        if ar.type=='VIEW_3D':
            ar.spaces.active.shading.type='MATERIAL';ar.spaces.active.region_3d.view_perspective='CAMERA'
# No unused temporary meshes from failed candidate attempts should inflate this delivered source.
for me in list(bpy.data.meshes):
    if me.users==0:bpy.data.meshes.remove(me)
bpy.ops.wm.save_as_mainfile(filepath=str(MAIN),compress=True)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
manifest=dict(schema='sea.asset_manifest',asset_id='SEA-SCENE-SCITY-ASSEMBLY',name='沉没旧城_红框补景与道路横卧楼体',version='v002',
 source=str(MAIN.relative_to(R)).replace('\\','/'),source_sha256=sha(MAIN),asset_ledger='assets/registry/ledgers/scenes.json#SEA-SCENE-SCITY-ASSEMBLY',
 palette=P['palette'],palette_sha256=sha(R/P['palette']),building_class='underwater',collision=False,interactive=False,emission=False,
 material_roles=['SEA_Matte','SEA_Metal','SEA_Gloss'],dependencies=[c['component_id'] for c in CAT],
 reference_rights='pending',runtime_validation='not_executed_not_in_scope',runtime_path=None,prefab=None,
 source_verified=True,component_count=len(CAT),instance_count=len(P['instances']),coordinate_contract=P['coordinate_contract'],floor_contract=P['floor_contract'])
(D/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('V002_FINAL_SAVED',str(MAIN),sha(MAIN),report['layout_triangles'])

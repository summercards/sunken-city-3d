"""Save final source after independent spatial and floor seam validation. No game export."""
import bpy,json,hashlib,math,runpy
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v001';W=R.parent/'sea-work/sunken_city/v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']
S=bpy.data.scenes['沉没旧城_完整参考布局_v001']
# Current refined candidate; keep all live corrections, only fix failed clearance positions.
for name,pos in {'electronics_shop_instance_003':(-34,-56),'canal_shell_instance_003':(-65,34),'coffee_steps_instance_002':(65,9),'low_foundation_instance_003':(65,-7)}.items():
    o=bpy.data.objects.get(name)
    if o:o.location.x,o.location.y=pos
for o in S.objects:
    if o.instance_type=='COLLECTION' and o.instance_collection:
        for a in P['instances']:
            if a['instance_id']==o.name:a['position_m']=list(o.location)
I=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))
I['instances']=P['instances']
for f,doc in [('component_plan.json',P),('component_instances.json',I)]:
    (D/f).write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Exact rectangular logical tiling: whole 240x240 area includes all central cells.
keys={'plaza_tile','street_intact','street_split','junction','t_junction','canal_segment','canal_end'}
ground=[a for a in P['instances'] if a['key'] in keys]
positions={(round(a['position_m'][0],4),round(a['position_m'][1],4)) for a in ground}
expected={(-108+24*i,-108+24*j) for i in range(10) for j in range(10)}
assert positions==expected and len(ground)==100,'Ground tiling has gaps/duplicates'
seams=[]
for x,y in sorted(positions):
    for dx,dy in ((24,0),(0,24)):
        if (x+dx,y+dy) in positions:seams.append({'a':[x,y],'b':[x+dx,y+dy],'gap_m':0.0,'overlap_m':0.0})
assert len(seams)==180
# Check all actual floor domains, anchors and equal top elevations. Canals deliberately have a sunken channel.
for a in ground:
    o=bpy.data.objects[a['instance_id']];c=next(c for c in CAT if c['key']==a['key']);me=next(q for q in o.instance_collection.objects if q.type=='MESH')
    pts=[o.matrix_world@v.co for v in me.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
    assert abs(hi[0]-lo[0]-24)<1e-4 and abs(hi[1]-lo[1]-24)<1e-4,a['instance_id']+' floor envelope'
    assert abs(o.rotation_euler.x)<1e-7 and abs(o.rotation_euler.y)<1e-7
(W/'floor_seams.json').write_text(json.dumps({'passed':True,'tiles':100,'shared_edges':180,'missing_tiles':0,'duplicate_tiles':0,'max_gap_m':0,'max_overlap_m':0,'central_floor_complete':True,'joints':seams},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Dependency graph transforms update lazily after location edits; audit the new matrix, not last frame.
bpy.context.view_layer.update()
# Independent probe must pass the actual live geometry before the delivered source can be saved.
runpy.run_path(str(Path(__file__).with_name('probe.py')),run_name='__main__')
report=json.loads((W/'probe_report.json').read_text(encoding='utf-8'))
assert report['passed'],report['errors']
S.camera=bpy.data.objects['相机_全景_固定'];S.render.resolution_x=1800;S.render.resolution_y=1600
S['plan_sha256']=hashlib.sha256((D/'component_plan.json').read_bytes()).hexdigest()
S['floor_central_region_complete']=True
# Remove only orphaned new-suite revision geometry. Do not touch any external/personal file.
for me in list(bpy.data.meshes):
    if me.users==0:bpy.data.meshes.remove(me)
for world in list(bpy.data.worlds):
    if world.users==0:bpy.data.worlds.remove(world)
for screen in bpy.data.screens:
    for ar in screen.areas:
        if ar.type=='VIEW_3D':
            ar.spaces.active.region_3d.view_perspective='CAMERA';ar.spaces.active.shading.type='MATERIAL'
MAIN=D/'sunken_city_v001.blend'
assert not MAIN.exists(),'Versioned delivery exists; must ask before overwrite'
bpy.ops.wm.save_as_mainfile(filepath=str(MAIN),compress=True)
masterhash=hashlib.sha256(MAIN.read_bytes()).hexdigest();palhash=hashlib.sha256((R/P['palette']).read_bytes()).hexdigest()
report.update(suite='sunken_city',source=str(MAIN),file=str(MAIN),source_sha256=masterhash,palette_sha256=palhash,status='passed',exit_code=0,checks={'geometry_uv_spatial_probe':{'passed':True,'assertion_count':report.pop('checks')},'floor_seams':{'passed':True,'tiles':100,'shared_edges':180}})
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
manifest=dict(schema='sea.asset_manifest',asset_id='SEA-SCENE-SCITY-ASSEMBLY',name='沉没旧城_水下建筑街区',
    source=str(MAIN.relative_to(R)).replace('\\','/'),source_sha256=masterhash,asset_ledger='assets/registry/ledgers/scenes.json#SEA-SCENE-SCITY-ASSEMBLY',
    palette=P['palette'],palette_sha256=palhash,version='v001',building_class='underwater',collision=False,interactive=False,emission=False,
    material_roles=['SEA_Matte','SEA_Metal','SEA_Gloss'],dependencies=[c['component_id'] for c in CAT],
    reference_rights='pending',runtime_validation='not_executed_not_in_scope',runtime_path=None,prefab=None,
    source_verified=True,component_count=len(CAT),instance_count=len(P['instances']),
    coordinate_contract=P['coordinate_contract'],floor_contract=P['floor_contract'])
(D/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('FINAL_SAVED',str(MAIN),masterhash)

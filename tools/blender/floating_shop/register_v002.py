import json,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/floating_shop/v002';W=Path('D:/projects/sea-work/floating_shop/v002')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
q=json.loads((W/'verification.json').read_text(encoding='utf-8'));cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components']
assert q['passed'] and q['standalone_packages_reopened']==39 and len(q['views'])==5
assert sha(D/'floating_shop.blend')==q['source_sha256']
route=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'))['domains']['scenes'];lp=R/route['ledger'];book=json.loads(lp.read_text(encoding='utf-8'));old={x['asset_id']:x for x in book[route['asset_key']]}
ids={e['asset_id'] for e in cat}|{'SEA-SCENE-FSH-ASSEMBLY'}
for e in cat:
 p=R/e['component_source'];assert sha(p)==e['source_sha256'];row=old[e['asset_id']];assert row['version']=='v001' and sha(R/row['source'])==row['source_sha256'],'Unexpected predecessor changed'
 hist={'version':row['version'],'source':row['source'],'source_sha256':row['source_sha256'],'manifest':row['manifest']};row['source_history']=row.get('source_history',[])+[hist]
 row.update({'source':e['component_source'],'source_sha256':e['source_sha256'],'manifest':(p.parent/'asset_manifest.json').relative_to(R).as_posix(),'geometry_fingerprint':e['geometry_fingerprint'],'version':'v002','note':'海上悬浮商铺v002；平台宽3米/2.5倍，正面护栏开口；39独立包重开、源级检查通过，运行接入pending。'})
aid='SEA-SCENE-FSH-ASSEMBLY';row=old[aid];assert row['version']=='v001' and sha(R/row['source'])==row['source_sha256']
row['source_history']=row.get('source_history',[])+[{k:row[k] for k in ['version','source','source_sha256','manifest']}]
row.update({'version':'v002','source':(D/'floating_shop.blend').relative_to(R).as_posix(),'source_sha256':q['source_sha256'],'manifest':(D/'asset_manifest.json').relative_to(R).as_posix(),'note':'外环从1.2m加宽到3.0m，正面护栏净开口约3.43m，贯通店门的1.95m通路无陈设阻挡；248实例，仅源级完成。'})
am={'schema':'sea.scene.assembly_manifest','asset_id':aid,'name':'海上悬浮商铺','version':'v002','category':'building/structure','placement_layer':'above_water','asset_ledger':route['ledger']+'#'+aid,'source':row['source'],'source_sha256':row['source_sha256'],'runtime_status':'pending','license':row['license'],'reference':'reference.png','reference_sha256':q['reference_sha256'],'revision_reference':'revision_reference.png','revision_reference_sha256':sha(D/'revision_reference.png'),'component_catalog':'catalog.json','component_instances':'component_instances.json','palette_asset_id':'SEA-PALETTE-COZY-64','metrics':q['metrics'],'revision_metrics':q['revision_metrics'],'visual_review':{'status':'source_views_reviewed_user_art_acceptance_pending','views':q['views']},'previous_source':row['source_history'][-1]}
save(D/'asset_manifest.json',am);save(lp,book)
ip=R/'assets/registry/current_source_index.json';si=json.loads(ip.read_text(encoding='utf-8'))
for e in si['sources']:
 if e['asset_id'] in ids:e.update({k:old[e['asset_id']][k] for k in ['source','source_sha256','manifest']})
save(ip,si)
for v in q['views']:v['sha256']=sha(Path(v['path']))
q['exit_codes'].update({'revision':0,'source_validation':0,'render_views':0,'registration':0});q['resolved_attempts']=['源通路检查发现7cm门槛，压至甲板表面后重验通过','libraries.write独立包导出导致Blender进程异常退出；恢复已保存v002后改用隔离场景逐件保存/重开，39包通过']
q['visual_review']={'status':'source_views_reviewed_user_art_acceptance_pending','reviewed':['beauty','front','top','entry','building_only']};save(W/'verification.json',q);save(R/'docs/development/2026-10-30_floating_shop_v002_verification.json',q)
print(json.dumps({'updated_records':len(ids),'source_history_preserved':True,'version':'v002'},ensure_ascii=False))

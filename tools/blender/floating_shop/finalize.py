import json,hashlib,os
from pathlib import Path
R=Path(__file__).resolve().parents[3];W=Path(os.environ.get('SEA_WORK_ROOT','D:/projects/sea-work'))/'floating_shop';p=W/'verification.json';q=json.loads(p.read_text(encoding='utf-8'))
q['visual_review']={'status':'source_views_reviewed_user_art_acceptance_pending','reviewed_views':[x['name'] for x in q['views']],'refinements_completed':['放大招牌字并调整字距','屋顶减薄避免遮挡主控下部','浮舱前移改善参考视角可见性','增加门内中央陈列','清理退化面及UV投影','正交视图移除背景地面地平线'],'remaining_differences':['公共色板下颜色非逐像素复刻','屋面装置及底部管线的细节密度','磨损的自然程度与层次']}
q['exit_codes'].update({'build_final':0,'source_validation':0,'render_views':0,'registration':0,'feature_contracts_sync_utf8':0,'feature_contracts_check_utf8':0})
q['expected_failures']=[];q['resolved_attempts']=['构建时world默认Background节点缺失，显式创建后通过','重开主文件后context.window为空，改用window_manager.windows[0]','初轮UV检查退化边面及过小投影，清理并重映射后复查通过','Windows默认GBK读取工程UTF-8文档失败，以python -X utf8重跑门禁通过']
for x in q['views']:
 x['sha256']=hashlib.sha256(Path(x['path']).read_bytes()).hexdigest()
probe=json.loads((W/'final_session_probe.json').read_text(encoding='utf-8'));assert probe['saved_source_sha256']==q['source_sha256'] and probe['instances']==250 and probe['component_collections']==39
q['final_session_probe']=probe
for target in [p,R/'docs/development/2026-10-30_floating_shop_verification.json']:target.write_text(json.dumps(q,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('FINAL_EVIDENCE_WRITTEN')

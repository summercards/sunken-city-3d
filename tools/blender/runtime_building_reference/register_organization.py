# -*- coding: utf-8 -*-
"""Update reference names and paths only, preserving runtime paths and old hashes."""
from pathlib import Path
import json,hashlib,gzip,csv,os
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/runtime_building_reference/v002';OLD=D.parent/'v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.2'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
qa=json.loads((W/'verification.json').read_text());assert qa['passed'] and qa['reopened']==104
cat=json.loads((D/'catalog.json').read_text());route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes'];bp=R/route['ledger'];book=json.loads(bp.read_text());old_rows={e['asset_id']:e for e in book[route['asset_key']]}
rows=[];all_entries=cat['items']+cat['facilities']+cat['overviews']
for e in all_entries:
 p=R/e['source'];assert sha(p)==e['source_sha256'];e['stage']='runtime_reference_verified';e['runtime_status']='reference_only_no_replacement';e['asset_ledger']=route['ledger']+'#'+e['asset_id'];manifest_path=(D/(e['asset_key']+'_manifest.json')) if p.parent==D else p.parent/'asset_manifest.json';write(manifest_path,e)
 previous=old_rows.get(e['asset_id']);history=[]
 if previous:
  assert sha(R/previous['source'])==previous['source_sha256'],'Prior source drift'
  history=list(previous.get('previous_sources',[]));history.append({k:previous[k] for k in ['source','source_sha256','manifest','version']})
 row=dict(asset_id=e['asset_id'],name=e['name'],asset_key=e['asset_key'],domain='scenes',stage=e['stage'],source=e['source'],source_sha256=e['source_sha256'],manifest=str(manifest_path.relative_to(R)),version='0.2',runtime_path=e.get('runtime_source'),prefab=e.get('runtime_scene'),license='existing_project_asset_provenance_unchanged',geometry_fingerprint=e.get('geometry_fingerprint'),consumer_features=['SEA-ASSET'],category=e['category'],scope_label=e['scope_label'],facility_name=e.get('facility_name'),facility_key=e.get('facility_key'),region_collections=e.get('region_collections',{}),previous_sources=history,note='中文设施名与 Blender 显示名一致；英文 asset_key 与 Blender 文件名一致。按设施-海上区域/海下基座归类；Godot 原运行路径作为来源保留。')
 rows.append(row)
ids={e['asset_id'] for e in rows};book[route['asset_key']]=[e for e in book[route['asset_key']] if e['asset_id'] not in ids]+rows;write(bp,book)
ip=R/'assets/registry/current_source_index.json';index=json.loads(ip.read_text());index['sources']=[]
for route2 in json.loads((R/'assets/registry/ledger_index.json').read_text())['domains'].values():
 for e in json.loads((R/route2['ledger']).read_text())[route2['asset_key']]:index['sources'].append({k:e[k] for k in ['asset_id','source','source_sha256','manifest']})
write(ip,index)
# Keep all placement references in the same canonical asset namespace.
mapping={r['legacy_key']:r['asset_key'] for r in cat['items']}
with gzip.open(OLD/'background_instances.json.gz','rt',encoding='utf-8') as f:instances=json.load(f)
for e in instances['building_instances']+instances['detail_instances']:e['component']=mapping[e['component']]
instances['version']='0.2';instances['name_policy']='component 对应 asset_key；part 对应 background_templates 中的逻辑原件索引'
with gzip.open(D/'background_instances.json.gz','wt',encoding='utf-8') as f:json.dump(instances,f,ensure_ascii=False,separators=(',',':'))
templates=json.loads((OLD/'background_templates.json').read_text());write(D/'background_templates.json',templates)
cat['background_instances']='background_instances.json.gz';cat['background_templates']='background_templates.json';write(D/'catalog.json',cat)
categories={'playable_surface':'海面设施部件','background_building_component':'远景楼体组件','background_detail_component':'远景公共构件','playable_facility_assembly':'可玩设施总成','playable_reference_assembly':'海面设施总览','background_reference_assembly':'远景组件总览'}
with (D/'asset_index.csv').open('w',encoding='utf-8-sig',newline='') as f:
 out=csv.writer(f);out.writerow(['资产编号','中文名称','英文资产名','归属设施','范围','类别','海上区域集合','海下基座集合','Blender 文件','Godot 原始资产路径'])
 for e in all_entries:out.writerow([e['asset_id'],e['name'],e['asset_key'],e.get('facility_name',''),e['scope_label'],categories[e['category']],e.get('region_collections',{}).get('海上区域',''),e.get('region_collections',{}).get('海下基座',''),e['source'],e.get('runtime_source','')])
def link(e):return f'[{e["name"]}]({e["relative_blend"]})'
md=['# 当前游戏设施资产账本 · v0.2','','本表从场景资产分账本与本版 catalog 派生。中文名称、英文资产名、Blender 文件一一对应；资产编号沿用既有登记。','','| 中文名称 | 英文资产名 | 类别 | Blender 文件 | Godot 来源 |','|---|---|---|---|---|']
for e in cat['facilities']+cat['items']+cat['overviews']:
 md.append(f'| {e["name"]} | `{e["asset_key"]}` | {categories[e["category"]]} | {link(e)} | `{e.get("runtime_source", "")}` |')
(D/'资产账本.md').write_text('\n'.join(md)+'\n')
readme=['# 当前游戏建筑参照库 · 中文设施整理版 v0.2','','## 打开入口','','- [海面可玩设施总览](sea_playable_facilities_v0.2.blend)','- [远景建筑组件总览](background_building_components_v0.2.blend)','- [中文资产账本](资产账本.md)；[中文表头 CSV](asset_index.csv)','','## 五个设施独立文件','','| 设施 | 英文资产名 | Blender |','|---|---|---|']
for e in cat['facilities']:readme.append(f'| {e["name"]} | `{e["asset_key"]}` | {link(e)} |')
readme+=['','## Blender 中的层级','','```text']
for e in cat['facilities']:readme += [e['name'],'  '+e['name']+'-海上区域','  '+e['name']+'-海下基座']
readme+=['```','','总览只在最外层显示五个设施；每个设施的两个区域可以单独隐藏。区域内的对象继续使用中文设施和部件名称。97 个独立部件、5 个设施总成、2 个总览均可独立打开；详细对应见中文资产账本。','','## 命名和几何约定','','- 账本 `name` 与 Blender 中文显示名一致；`asset_key` 与英文文件名一致，文件名后接 `_v0.2.blend`。','- Godot 现有 `unit_01` 等路径保留为原始来源，通过稳定 AssetID、asset_key 和清单关联；本次不改正式游戏资源路径。','- 海上/海下分界为实际游戏水面 Godot Y=1.12（Blender Z=1.12）。跨水面的网格切为两个区域，合并显示保持原形；切面不额外封盖。','- 原 v0.1 文件保留。本版只整理命名、集合、引用及水面分区，位置、尺度、颜色和有效表面保持一致。','- 远景公共构件使用组件母版归类；这类归一化零件的海上/海下归属由实际摆放决定，不在母版上固定。','- 海面部件保留旧自动拆分边界，未声称每个旧 GLB 都等于一栋完整设施；设施总成提供完整区块参照。','- 远景实例清单已同步为本版英文资产名；逻辑部件索引可通过原始 source_instance 追溯到拆分后的区域对象。','','## 独立部件','','| 中文名称 | 英文资产名 | Blender |','|---|---|---|']
for e in cat['items']:
 if e['category']!='background_detail_component':readme.append(f'| {e["name"]} | `{e["asset_key"]}` | {link(e)} |')
(D/'README.md').write_text('\n'.join(readme)+'\n')
write(D/'naming_map.json',dict(version='0.2',entries=[{k:e.get(k) for k in ['asset_id','legacy_key','asset_key','name','facility_name','source','runtime_source','region_collections']} for e in all_entries]))
spec=R/'docs/features/asset/spec.md';s=spec.read_text();rule='| SEA-ASSET-R16 | 现状建筑参照库以中文设施名统一 Blender 场景/集合与资产账本 name，英文 asset_key 对应文件名，原 AssetID 与 Godot 来源稳定可追溯；总览按五个设施分组，每设施内部以“设施名字-海上区域 / 设施名字-海下基座”管理，水面拆分合并后保持原形；保留 v0.1 并交付命名整理版 v0.2 及中文账本。 |'
assert 'SEA-ASSET-R16' not in s;s=s.replace('\n\n### SEA-ASSET-R12','\n'+rule+'\n\n### SEA-ASSET-R12',1);spec.write_text(s)
ledger=R/'docs/features/asset/ledger.md';s=ledger.read_text();line='| SEA-ASSET-R16 | v0.2 中文设施归类与命名统一完成，源级验证通过 | 97 部件、5 设施总成、2 总览重开；中文 name、英文 asset_key/文件名逐条核对；海上/海下几何面积和包围盒验证；既有源和运行输入哈希保持；见本轮归类记录 |'
s=s.replace('\n\n## 资源与调用入口','\n'+line+'\n\n## 资源与调用入口',1)
s+='\n## 建筑参照库中文归类 v0.2（2026-10-25）\n\n- [中文资产账本](../../../art_source/scenes/runtime_building_reference/v002/资产账本.md)；[打开入口](../../../art_source/scenes/runtime_building_reference/v002/README.md)。\n- 五设施分别以“设施名字-海上区域 / 设施名字-海下基座”显示；英文资产名与文件名一致，中文名称与分账本一致。原运行资源路径保持来源追溯，v0.1 仍保留。\n- [验证记录](../../development/2026-10-25_runtime_building_reference_v02.md)。\n';ledger.write_text(s)
dev=R/'docs/development/2026-10-25_runtime_building_reference_v02.md';dev.write_text('# 建筑参照库 v0.2 中文设施归类\n\n用户要求：Blender、Godot 资产账本与文件统一命名，账本中文、资产英文；设施内区分“设施名字-海上区域”和“设施名字-海下基座”。\n\n交付：v002/README.md、资产账本.md、asset_index.csv、naming_map.json。97 独立部件按中文设施和英文 asset_key 重命名；新增 5 个设施总成，总览外层由 17 个不直观的 unit 名改为 5 个中文设施，每设施两个区域入口。原 99 个 AssetID 路径版本更新并保留 previous_sources；新增 5 个设施总成登记，不接受未知哈希变更。\n\n海上/海下以游戏水面 Y=1.12 分割，跨面的几何不封盖；切分前后有效表面积、包围盒及所有区域顶点高度检查通过。首次检测到旧网格独立点的包围盒丢失，已保留原独立点/线并重跑；最终 104 个文件保存重开、集合/文件名/中文名称/纹理与链接检查通过。原 v0.1 文件和运行输入哈希核对不变。\n\n本次只整理参照源，未运行 Godot 玩法或改动正式 GLB/TSCN。远景公共构件的水面归属随实例高度变化；旧空间单元仍有跨设施边界，已在中文账本保留原始来源。\n')
write(R/'docs/development/2026-10-25_runtime_building_reference_v02_verification.json',qa)
print('UPDATED',len(rows),'records; preserved prior source versions')

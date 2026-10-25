# -*- coding: utf-8 -*-
from pathlib import Path
import json,hashlib,os,csv
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/runtime_building_reference/v003';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.3'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
qa=json.loads((W/'verification.json').read_text());assert qa['passed'] and qa['changed_assets_reopened']==4
cat=json.loads((D/'catalog.json').read_text());split=json.loads((W/'split_checks.json').read_text());changed=split['changed_assets'];route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes'];bp=R/route['ledger'];book=json.loads(bp.read_text());existing={e['asset_id']:e for e in book[route['asset_key']]}
new_rows=[]
for e in changed:
 assert sha(R/e['source'])==e['source_sha256'];previous=existing.get(e['asset_id']);history=[]
 if previous:
  assert sha(R/previous['source'])==previous['source_sha256'];history=list(previous.get('previous_sources',[]));history.append({k:previous[k] for k in ['source','source_sha256','manifest','version']})
 e['stage']='runtime_reference_verified';e['runtime_status']='reference_only_no_replacement';write(R/e['manifest'],e)
 row=dict(asset_id=e['asset_id'],name=e['name'],asset_key=e['asset_key'],domain='scenes',stage=e['stage'],source=e['source'],source_sha256=e['source_sha256'],manifest=e['manifest'],version='0.3',runtime_path=e.get('runtime_source'),prefab=e.get('runtime_scene'),license='existing_project_asset_provenance_unchanged',geometry_fingerprint=None,consumer_features=['SEA-ASSET'],category=e['category'],scope_label=e['scope_label'],facility_name=e.get('facility_name'),facility_key=e.get('facility_key'),region_collections=e.get('region_collections',{}),previous_sources=history,note='绞盘打捞台与太阳能木屋为两个独立设施；各有海上区域和海下基座。当前为替换参照，不修改正式游戏资源。')
 new_rows.append(row)
ids={e['asset_id'] for e in new_rows};book[route['asset_key']]=[e for e in book[route['asset_key']] if e['asset_id'] not in ids]+new_rows;write(bp,book)
ip=R/'assets/registry/current_source_index.json';ix=json.loads(ip.read_text());ix['sources']=[]
for route2 in json.loads((R/'assets/registry/ledger_index.json').read_text())['domains'].values():
 for e in json.loads((R/route2['ledger']).read_text())[route2['asset_key']]:ix['sources'].append({k:e[k] for k in ['asset_id','source','source_sha256','manifest']})
write(ip,ix)
entries=cat['facilities']+cat['items']+cat['overviews']
md=['# 当前游戏设施资产账本 · v0.3','','绞盘打捞台从太阳能木屋独立拆出。未受影响的设施和部件继续引用 v0.2；下列路径均指向各自当前登记源。','','| 中文名称 | 英文资产名 | 所属设施 | Blender 源 | Godot 来源 |','|---|---|---|---|---|']
for e in entries:md.append(f'| {e["name"]} | `{e["asset_key"]}` | {e.get("facility_name", "总览")} | [{e["name"]}]({e["relative_blend"]}) | `{e.get("runtime_source", "")}` |')
(D/'资产账本.md').write_text('\n'.join(md)+'\n')
with (D/'asset_index.csv').open('w',encoding='utf-8-sig',newline='') as f:
 out=csv.writer(f);out.writerow(['资产编号','中文名称','英文资产名','所属设施','源版本','Blender 文件','海上集合','海下集合','Godot 来源'])
 for e in entries:out.writerow([e['asset_id'],e['name'],e['asset_key'],e.get('facility_name','总览'),e['version'],e['source'],e.get('region_collections',{}).get('海上区域',''),e.get('region_collections',{}).get('海下基座',''),e.get('runtime_source','')])
lines=['# 游戏建筑替换参照 · v0.3','','## 打开入口','','- [六设施总览](sea_playable_facilities_v0.3.blend)','- [太阳能木屋](facilities/solar_cabin/solar_cabin_v0.3.blend)','- [绞盘打捞台](facilities/salvage_station/salvage_station_v0.3.blend)','- [中文资产账本](资产账本.md)；[资产索引 CSV](asset_index.csv)','','## 独立设施','','绞盘打捞台与太阳能木屋是两个顶层设施，各自都有“设施名字-海上区域”和“设施名字-海下基座”。总览内任一设施均可独立隐藏，不会连带隐藏另一设施。','','| 设施 | 英文资产名 | 当前源 |','|---|---|---|']
for e in cat['facilities']:lines.append(f'| {e["name"]} | `{e["asset_key"]}` | [{e["name"]}]({e["relative_blend"]}) |')
lines+=['','## 拆分与定位','','- 原分组把整个家园港湾归到太阳能木屋，现按游戏中独立的 salvage 登岸点拆出绞盘打捞台，包括甲板、绞盘、立柱、下方支撑及附近装饰。','- 原运行单元 detail.glb 仍作为共同来源；Blender 与资产账本分别拥有独立设施 AssetID，不把旧 GLB 当作设施边界。','- 打捞台局部原点位于 Godot 世界坐标 (-12,0,13)，文件保留水面 Y=1.12 对应的海上/海下分类；总览按原世界位置摆放。','- 更新木屋港湾部件、木屋总成和总览；其余 v0.2 部件直接复用。v0.1/v0.2 保存不变。','- 原游戏 GLB/TSCN、碰撞、登岸点与玩法未改动。本版是制作替换参照。','','## 验证','','4 个新增/变更源均重开；集合与链接有效；拆分后的三角形总数、有效表面积和合并包围盒保持；两种结构预览已目视核对。']
(D/'README.md').write_text('\n'.join(lines)+'\n')
parent=D.parent;parent.joinpath('README.md').write_text('# 游戏建筑参照源\n\n当前版本：[v0.3 独立绞盘打捞台](v003/README.md)。\n\n- [海面六设施总览](v003/sea_playable_facilities_v0.3.blend)\n- [太阳能木屋](v003/facilities/solar_cabin/solar_cabin_v0.3.blend)\n- [绞盘打捞台](v003/facilities/salvage_station/salvage_station_v0.3.blend)\n- [中文资产账本](v003/资产账本.md)\n\n历史：[v0.2 中文归类版](v002/README.md)；[v0.1 原始快照](v001/README.md)。\n')
p=parent/'v002/README.md';s=p.read_text();s=s.replace('\n\n','\n\n> 当前版本：[v0.3 独立绞盘打捞台](../v003/README.md)。\n\n',1);p.write_text(s)
spec=R/'docs/features/asset/spec.md';s=spec.read_text();rule='| SEA-ASSET-R17 | 按用户截图将绞盘打捞台从太阳能木屋归类与源中拆开，登记两个独立设施，各有“设施名字-海上区域 / 设施名字-海下基座”；按完整连通构件转移绞盘、甲板、立柱与下方基座，保留原世界摆位、表面积和几何覆盖，总览增加独立入口，中文账本与英文文件同步。 |'
assert 'SEA-ASSET-R17' not in s;s=s.replace('\n\n### SEA-ASSET-R12','\n'+rule+'\n\n### SEA-ASSET-R12',1);spec.write_text(s)
ledger=R/'docs/features/asset/ledger.md';s=ledger.read_text();line='| SEA-ASSET-R17 | v0.3 源级拆分完成并验证，未改游戏运行资源 | 绞盘打捞台新增独立设施 AssetID；木屋港湾部件/木屋总成/六设施总览更新，4 源重开与集合检查；拆分几何覆盖保持，见本轮拆分记录 |';s=s.replace('\n\n## 资源与调用入口','\n'+line+'\n\n## 资源与调用入口',1)
s+='\n## 绞盘打捞台独立设施 v0.3（2026-10-25）\n\n- [本版入口](../../../art_source/scenes/runtime_building_reference/v003/README.md)；[中文资产账本](../../../art_source/scenes/runtime_building_reference/v003/资产账本.md)。\n- 太阳能木屋和绞盘打捞台分别为两个设施，绞盘平台已从木屋港湾部件移除；各自包含海上区域/海下基座。\n- [拆分与验证记录](../../development/2026-10-25_runtime_building_reference_v03.md)。\n';ledger.write_text(s)
dev=R/'docs/development/2026-10-25_runtime_building_reference_v03.md';dev.write_text('# 绞盘打捞台独立设施 v0.3\n\n用户截图中的绞盘甲板从太阳能木屋拆为独立设施 salvage_station，新增 SEA-REF-FACILITY-SALVAGE-STATION；已有三个 AssetID 更新当前源，previous_sources 保留旧版本。未受影响的源继续引用 v0.2。\n\n以独立 salvage 登岸点和 6.5×5.5 米甲板位置确定归属，按位置焊接后的连通图判定完整构件，不裁切构件表面；转移绞盘/甲板/立柱/支撑及附近装饰。新文件局部原点对应 Godot 世界 (-12,0,13)，总览保留原世界摆位。\n\n4 文件保存重开，六设施顶层入口、区域集合和链接检查通过；分割前后表面积与三角形总量一致。平台全高与近景已目视核对，旧 v0.2 与运行输入哈希不变。首个候选因旧孤立集合同名产生链接缺失，已撤至工程外并清理无用集合重建；最终核对通过。\n\nGodot 运行验证未执行：只整理 Blender 替换参照，没有修改正式 GLB/TSCN、碰撞或玩法。\n')
write(R/'docs/development/2026-10-25_runtime_building_reference_v03_verification.json',qa)
print('REGISTERED: 1 new facility, 3 updated reference assets')

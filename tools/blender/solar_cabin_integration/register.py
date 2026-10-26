# -*- coding: utf-8 -*-
from pathlib import Path
import json,hashlib,os
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v003/export/v001';W=R.parent/'sea-work/solar_cabin_integration';V=R.parent/'sea-work/verification';BACKUP=R.parent/'sea-work/backups/solar_cabin_replacement/v0.1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
run_names={'visual':'20261025-212135-solar-cabin-delivery-1d307b','functional':'20261025-211335-solar-cabin-final-functional-319d4b','other':'20261025-211038-solar-cabin-integration-7f3fbb','before':'20261025-205808-solar-cabin-before-5063d8'}
reports={k:json.loads((V/v/'report.json').read_text()) for k,v in run_names.items()}
assert reports['visual']['results']['visual-solar-cabin']['passed']
for key in ['surface','selftest']:assert reports['functional']['results'][key]['passed']
for key in ['click','management']:assert reports['other']['results'][key]['passed']
assert reports['before']['results']['visual-sea-style']['passed']
runtime=json.loads((V/run_names['visual']/'project/outputs/solar-cabin-runtime.json').read_text());assert runtime['failures']==0
export=json.loads((D/'export_manifest.json').read_text());assert sha(R/export['source'])==export['source_sha256'];assert sha(R/export['optimized_source'])==export['optimized_sha256'];assert sha(R/export['palette_source'])==export['palette_sha256']
placement=R/'art_source/scenes/sunny_bloom_retreat/v003/export/v001/placement/solar_cabin/solar_cabin_v1.0.blend';assert placement.is_file()
pm=json.loads((D/'placement_manifest.json').read_text());pm.update(placement_source=str(placement.relative_to(R)),placement_sha256=sha(placement));write(D/'placement_manifest.json',pm)
backup=json.loads((BACKUP/'backup_manifest.json').read_text());assert all(sha(BACKUP/e['path'])==e['sha256'] for e in backup['files'])
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes'];bp=R/route['ledger'];book=json.loads(bp.read_text());lookup={e['asset_id']:e for e in book[route['asset_key']]}
def bind(e,glb,prefab,scope,extra=None):
 row=lookup[e['asset_id']];assert sha(R/row['source'])==row['source_sha256'];row.update(runtime_path=glb,prefab=prefab,stage='runtime_integrated_verified',runtime_version='1.0',runtime_scope=scope,optimized_source=export['optimized_source'],optimized_sha256=export['optimized_sha256'],export_manifest=str((D/'export_manifest.json').relative_to(R)),runtime_verified=True)
 if extra:row.update(extra)
 mp=R/row['manifest'];manifest=json.loads(mp.read_text());manifest.update(runtime_path=glb,prefab=prefab,stage=row['stage'],runtime_status='integrated_verified',runtime_scope=scope,optimized_source=export['optimized_source'],export_manifest=row['export_manifest']);write(mp,manifest)
for e in export['components']:bind(e,e['glb'],e['prefab'],'海上区域组件')
assembly=lookup['SEA-SCENE-SBR-ASSEMBLY'];bind(assembly,'godot/assets/models/facilities/solar_cabin/instances.json','godot/scenes/facilities/solar_cabin_surface.tscn','太阳能木屋-海上区域',dict(note='用户指定源接入；49 组件独立 GLB/PackedScene，MultiMesh 复用；原制作源哈希不变，参考图授权状态沿用原登记。'))
reference=json.loads((R/'art_source/scenes/runtime_building_reference/v003/catalog.json').read_text());reference_by_key={e['asset_key']:e for e in reference['items']+reference['facilities']}
for e in export['legacy']:
 key=e['key'].removeprefix('base_');ref=reference_by_key[key];bind(ref,e['glb'],e['prefab'],'完整独立绞盘打捞台' if key=='salvage_station' else '仅海下基座；海上部分已由阳光繁花小屋替换')
solar=lookup['SEA-REF-FACILITY-SOLAR-CABIN'];prior={k:solar[k] for k in ['source','source_sha256','manifest','version']};history=list(solar.get('previous_sources',[]));history.append(prior)
solar.update(name='太阳能木屋',asset_key='solar_cabin',source=str(placement.relative_to(R)),source_sha256=sha(placement),manifest=str((placement.parent/'asset_manifest.json').relative_to(R)),version='1.0',runtime_version='1.0',stage='runtime_integrated_verified',runtime_path='godot/assets/models/facilities/solar_cabin/instances.json',prefab='godot/scenes/facilities/solar_cabin.tscn',runtime_verified=True,previous_sources=history,optimized_source=export['optimized_source'],export_manifest=str((D/'export_manifest.json').relative_to(R)),runtime_scope='阳光繁花小屋海上区域 + 原海下基座',note='0.1 备份保留此前源和运行文件；新装配以 sunny_bloom_retreat/v003 替换海上部分，保留海下基座与独立绞盘打捞台。')
write(placement.parent/'asset_manifest.json',dict(solar,asset_ledger=route['ledger']+'#'+solar['asset_id']))
optimized_id='SEA-SCENE-SBR-OPTIMIZED';assert optimized_id not in lookup
opt=dict(asset_id=optimized_id,name='太阳能木屋-独立优化导出源',domain='scenes',stage='runtime_integrated_verified',source=export['optimized_source'],source_sha256=export['optimized_sha256'],manifest=str((D/'optimized_asset_manifest.json').relative_to(R)),version='v001',runtime_path=None,prefab=None,license='existing_project_asset_provenance_unchanged',geometry_fingerprint=None,consumer_features=['SEA-ASSET','SEA-WORLD'],category='optimized_export_source',scope='scene_local',note='仅独立优化副本；保留原始源，逐组件导出。')
write(R/opt['manifest'],dict(opt,asset_ledger=route['ledger']+'#'+optimized_id));book[route['asset_key']].append(opt)
palette=lookup['SEA-PALETTE-COZY-64'];palette['runtime_path']='godot/assets/textures/shared/sea_cozy_8x8_512.png';palette['runtime_note']='从唯一制作色板导出的运行副本，PNG SHA-256 相同，无损/Nearest/无 mipmap。'
write(bp,book)
ip=R/'assets/registry/current_source_index.json';ix=json.loads(ip.read_text());ix['sources']=[]
for route2 in json.loads((R/'assets/registry/ledger_index.json').read_text())['domains'].values():
 for e in json.loads((R/route2['ledger']).read_text())[route2['asset_key']]:ix['sources'].append({k:e[k] for k in ['asset_id','source','source_sha256','manifest']})
write(ip,ix)
# Update only the explicitly edited pre-existing runtime inputs. Unknown drift aborts.
inventory_path=R/'assets/registry/runtime_resource_inventory.json';inventory=json.loads(inventory_path.read_text());allowed={'godot/assets/baked/shore.json','godot/assets/data/build_sites.json','godot/assets/data/gather_spots.json','godot/assets/data/plants_zone1_home_harbor.json','godot/assets/data/zones.json'}
updated=[]
for e in inventory['resources']:
 p=R/e['path'];actual=sha(p)
 if actual==e['sha256']:continue
 assert e['path'] in allowed,'Unrelated runtime drift: '+e['path'];e['previous_sha256']=e['sha256'];e['sha256']=actual;e['bytes']=p.stat().st_size;e['note']='本轮太阳能木屋接入的已审阅数据变更';updated.append(e['path'])
existing_paths={e['path'] for e in inventory['resources']};new_files=[]
for root in ['godot/assets/models/facilities','godot/assets/materials/solar_cabin','godot/assets/textures/shared']:
 for p in (R/root).rglob('*'):
  if p.is_file() and p.suffix not in ['.import','.uid'] and '_tex_' not in p.name:new_files.append(p)
for p in new_files:
 rel=str(p.relative_to(R))
 if rel in existing_paths:continue
 aid=next((e['asset_id'] for e in export['components'] if e['glb']==rel),solar['asset_id']);inventory['resources'].append(dict(path=rel,bytes=p.stat().st_size,sha256=sha(p),asset_id=aid,status='runtime_integrated_verified'))
write(inventory_path,inventory)
proof=dict(backup=str(BACKUP),backup_version='0.1',backup_files=len(backup['files']),backup_hashes_verified=True,source=export['source'],source_unchanged=True,optimized_source=export['optimized_source'],placement_source=str(placement.relative_to(R)),geometry_optimization=dict(triangles_before=export['expanded_triangles_before'],triangles_after=export['expanded_triangles_after'],reduction_ratio=1-export['expanded_triangles_after']/export['expanded_triangles_before']),fidelity_views_reviewed=['front','back','side','top'],runtime=runtime,verification_runs=run_names,results=dict(visual=reports['visual']['results']['visual-solar-cabin'],surface=reports['functional']['results']['surface'],selftest=reports['functional']['results']['selftest'],click=reports['other']['results']['click'],management=reports['other']['results']['management']),runtime_hash_updates=updated,not_run=['完整长期游玩性能基准','参考图商业授权审核'],resolved_failures=['Headless dummy renderer returns identity MultiMesh transforms; geometry probe now explicitly requires real renderer, 529 checks pass.','Two farm cells were outside narrow walkway; planter moved 0.345m inward, all 6 cells reachable.','Selftest held-interaction case inherited adjacent target rejection cooldown; drain through public update before unchanged move-cancellation assertion.'])
write(W/'delivery_verification.json',proof);write(R/'docs/development/2026-10-25_solar_cabin_integration_verification.json',proof)
spec=R/'docs/features/asset/spec.md';s=spec.read_text();rule='| SEA-ASSET-R18 | 按用户要求将当前源与运行文件复制备份为 0.1 快照，再以 sunny_bloom_retreat/v003 替换太阳能木屋海上区域；原制作源及外链色板不改，在独立优化源逐组件清理/导出，保持海下基座与独立打捞台。核对 1.15 倍比例、+Z 正面、平台 Y=2.15、实际包围盒，正式 PackedScene 接入并同步泊位/行走/种植点，真实渲染及专项验证后登记。 |';assert 'SEA-ASSET-R18' not in s;s=s.replace('\n\n### SEA-ASSET-R12','\n'+rule+'\n\n### SEA-ASSET-R12',1);spec.write_text(s)
ledger=R/'docs/features/asset/ledger.md';s=ledger.read_text();line='| SEA-ASSET-R18 | 已备份并正式接入，专项与真实渲染通过 | 0.1 快照逐文件哈希核对；49 独立组件与优化源，703920→688342 三角面；529 实机几何检查、30 条航路、种植点/点击/经营/自检通过；见太阳能木屋接入记录 |';s=s.replace('\n\n## 资源与调用入口','\n'+line+'\n\n## 资源与调用入口',1);s+='\n## 太阳能木屋正式接入（2026-10-25）\n\n- [接入与备份说明](../../development/2026-10-25_solar_cabin_integration.md)；[Blender 当前装配](../../../'+str(placement.relative_to(R))+')。\n- 用户指定 sunny_bloom_retreat/v003，海上部分按源比例统一 1.15 倍接入；海下基座及独立绞盘台保留。原源哈希不变，优化文件另存。\n- 源级完成状态与本次运行验证证据分开记录，参考图授权状态沿用原登记。\n';ledger.write_text(s)
for feature,text in [('world','SEA-WORLD-R01/R02/R03：家园区块定点手工接入太阳能木屋完整 PackedScene；旧四 GLB 节点显式隐藏保留回退，原基座与独立打捞台以稳定包装引用。'),('move','SEA-MOVE-R01/R02：新栈桥、前平台可走区域与 main 登岸点同步，六格菜箱可达；surface 338 检查与 click 30 检查通过。'),('nav','SEA-NAV：main 泊位随新栈桥移动，打捞台泊位保留；新增平台岸线范围，30 条跨泊位航路通过。')]:
 p=R/f'docs/features/{feature}/ledger.md';p.write_text(p.read_text()+'\n## 太阳能木屋接入影响验证（2026-10-25）\n\n'+text+' 验证入口：`python3 scripts/run_verification.py surface click management selftest visual-solar-cabin`；[证据](../../development/2026-10-25_solar_cabin_integration.md)。\n')
doc=R/'docs/development/2026-10-25_solar_cabin_integration.md';doc.write_text('''# 太阳能木屋 · 阳光繁花小屋正式接入

用户要求先复制备份当前文件为 0.1，再以 sunny_bloom_retreat.blend 的房屋替换太阳能木屋海上部分，核对尺寸范围与朝向。

## 备份与打开入口

- 0.1 备份：`'''+str(BACKUP)+'''`，原目录保持以保护 Blender 相对链接；backup_manifest.json 逐文件登记并验证。
- 当前 Blender 装配：[solar_cabin_v1.0.blend](../../'''+str(placement.relative_to(R))+''')。
- 原始制作源：[sunny_bloom_retreat.blend](../../'''+export['source']+''')，SHA-256 不变。
- 独立优化源：[solar_cabin_optimized_v001.blend](../../'''+export['optimized_source']+''')；[导出清单](../../'''+str((D/'export_manifest.json').relative_to(R))+''')。
- Godot 完整包装：[solar_cabin.tscn](../../godot/scenes/facilities/solar_cabin.tscn)，当前区块手工引用；内部海上和海下部分可分别选择。

## 大小、范围和方向

整体源统一放大 1.15 倍，不改变房体横纵比例；49 个母版和实例的原始相对摆位保留。地板 Y=2.15 米，主墙宽 5.75 米。含植物与双列栈桥的运行包围盒为 X≈10.5904、Z≈13.8165、Y≈8.0022 米，下界约 (-0.0227,1.12,-3.0097)，顶高约 9.1222 米。源前方 -Y 映射为 Godot +Z，yaw=0°。旧海下基座保留；新石平台底部在派生实例中延长 0.248 米以接到 Y=1.12 水面，房屋本体保持统一比例。

## 导出与装配

49 组件各有稳定 GLB 与 PackedScene，整体用组件实例批次绘制；建筑、陈设、花草按元数据管理，不导出一个合并整屋 GLB。四材质绑定公共色板运行副本，PNG 与制作色板 SHA 相同、Nearest、无 mipmap、无损。49 新 GLB 不内嵌贴图；历史基座/打捞台沿用旧顶点色及历史贴图材质。优化副本清理重复/退化几何、删除独立点并溶解低于 0.003 弧度的共面冗余，颜色/材质边界锁定；完整实例展开 703920→688342 三角面，约 2.21% 减少。正、背、侧、顶固定相机保真对照已目视核对。

仅定点编辑 zone1_home_harbor.tscn；旧四模型显式隐藏，未运行旧全量构建器。原海上散落植物退役，保留海下及打捞台植物。同步新平台可走区域、泊位、六格菜箱、建造牌和采集点；海下基座和打捞台为独立包装。角色/经济/经营规则未改。

## 当前实测

- 真实 Metal/Forward+ 渲染：529 条几何、色板、方向、实例、基座和登岸检查通过；正面、背面、俯视和上下文截图。
- surface：30 条航路、338 检查通过；selftest：537 通过，0 失败（含一条预期损坏 JSON 负向错误）。
- click 与 management 专项通过；完整退出码、隔离数据目录、预期/非预期错误见结构化验证 JSON。
- 首次 headless 模型探针读到 dummy renderer 的恒等实例矩阵，改为真实渲染验证；未以 headless 结果签署几何通过。首次发现两格菜箱超出可走边界，已内移并重新验证。采集中断自检的前次拒绝冷却经公开 update 消耗，原断言保留。
- 未执行长期性能基准；不以本次接入证明参考图商业授权，授权字段保持原状态。

所有运行验证经 scripts/run_verification.py，在 Autoload 前隔离用户数据；未读取或覆盖玩家存档。
''')
readme=['# 太阳能木屋 · 当前游戏装配','','[打开当前 Blender 装配](placement/solar_cabin/solar_cabin_v1.0.blend)；[独立优化源](solar_cabin_optimized_v001.blend)；[导出清单](export_manifest.json)。','','- 海上区域来自 sunny_bloom_retreat/v003，原母版未改。','- 下方为原海下基座；绞盘打捞台保持独立。','- 源比例 1.15，正面 Godot +Z，yaw=0°，平台 Y=2.15 米。','- 含花草与桥的范围约 10.59×13.82 米，水面以上最大高约 8.00 米。','','## 组件账本','','| 中文组件名 | AssetID | Godot PackedScene |','|---|---|---|']
for e in export['components']:readme.append(f'| {e["name"]} | {e["asset_id"]} | `{e["prefab"]}` |')
(D/'README.md').write_text('\n'.join(readme)+'\n')
parent=R/'art_source/scenes/runtime_building_reference';p=parent/'README.md';p.write_text('# 游戏建筑参照与当前装配\n\n太阳能木屋已正式替换：[当前 Blender 装配](../sunny_bloom_retreat/v003/export/v001/placement/solar_cabin/solar_cabin_v1.0.blend)；[接入说明](../sunny_bloom_retreat/v003/export/v001/README.md)。\n\n此前六设施参照保留：[v0.3 拆分版](v003/README.md)。替换前 0.1 快照位于工程外 sea-work/backups/solar_cabin_replacement/v0.1。\n')
backup_links=['# 替换前备份 · 0.1','','本目录是用户要求的替换前复制备份；文件名与内部目录保持原样，以保留 Blender 相对链接。快照版本号为 **0.1**。','','- [原六设施总览](art_source/scenes/runtime_building_reference/v003/sea_playable_facilities_v0.3.blend)','- [原太阳能木屋](art_source/scenes/runtime_building_reference/v003/facilities/solar_cabin/solar_cabin_v0.3.blend)','- [原绞盘打捞台](art_source/scenes/runtime_building_reference/v003/facilities/salvage_station/salvage_station_v0.3.blend)','- [指定新房制作源备份](art_source/scenes/sunny_bloom_retreat/v003/sunny_bloom_retreat.blend)','- [逐文件哈希清单](backup_manifest.json)','','原 GLB、正式区块 TSCN、相关数据和登记文件也在本快照中。回退时从对应相对路径恢复；新增导出资源可保留为未引用文件，无须批量删除。']
(BACKUP/'README.md').write_text('\n'.join(backup_links)+'\n')
print('Registered current runtime source, palette, 49 components, legacy scopes; runtime hash updates:',updated)

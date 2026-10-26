"""Register only the verified v006 revision; preserve all previous source rows."""
from pathlib import Path
import json,hashlib,struct
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v006';E=D/'export/v001';W=R.parent/'sea-work/solar_cabin_revision_v006';V=R.parent/'sea-work/verification/20261026-075446-solar-cabin-v006-3c222e'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
proof=json.loads((V/'report.json').read_text());assert all(e['passed'] for e in proof['results'].values());sourcecheck=json.loads((W/'source_verification.json').read_text());assert sourcecheck['passed']
for p,h in json.loads((W/'protected_sources.json').read_text()).items():assert sha(R/p)==h
snap=json.loads((W/'before/manifest.json').read_text());assert all(sha(W/'before'/e['path'])==e['sha256'] for e in snap)
export=json.loads((E/'export_manifest.json').read_text());assert sha(R/export['source'])==export['source_sha256'];assert sha(R/export['optimized_source'])==export['optimized_sha256']
cat=json.loads((D/'catalog.json').read_text())['components'];bykey={c['key']:c for c in cat};layout=json.loads((D/'component_instances.json').read_text())['instances']
for e in export['components']:
 assert sha(R/e['glb'])==e['glb_sha256'];imp=R/(e['glb']+'.import');assert 'gltf/embedded_image_handling=0' in imp.read_text()
 with (R/e['glb']).open('rb') as f:f.read(12);length,tag=struct.unpack('<II',f.read(8));gl=json.loads(f.read(length))
 assert not gl.get('images') and not gl.get('textures')
 before=sum(o['triangles_before'] for o in e['optimization']);after=e['exported_triangles']
 e.update(source=bykey[e['key']]['component_source'],source_sha256=sha(R/bykey[e['key']]['component_source']),source_version='v006',optimized_source=export['optimized_source'],optimized_sha256=export['optimized_sha256'],triangles_before=before,triangles_after=after,reduction_ratio=1-after/before,budget=None,budget_source='No explicit numeric cap for this revision',import_sha256=sha(imp),fidelity_review='passed fixed-camera front/back/side/top silhouette, openings, palette boundaries',runtime_verified=True)
write(E/'export_manifest.json',export)
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes'];bp=R/route['ledger'];book=json.loads(bp.read_text());rows=book[route['asset_key']];lookup={e['asset_id']:e for e in rows}
common=dict(domain='scenes',stage='runtime_integrated_verified',version='v006',runtime_version='1.3',runtime_verified=True,consumer_features=['SEA-ASSET','SEA-WORLD'],scope='scene_local',optimized_source=export['optimized_source'],optimized_sha256=export['optimized_sha256'],export_manifest=str((E/'export_manifest.json').relative_to(R)))
def put(aid,name,source,manifest,category,runtime_path,prefab,**extra):
 source=Path(source);source=source if source.is_absolute() else R/source;manifest=Path(manifest);manifest=manifest if manifest.is_absolute() else R/manifest
 row=lookup.get(aid)
 if row:
  assert sha(R/row['source'])==row['source_sha256'],'Unknown source drift '+aid
  if row['source']!=str(source.relative_to(R)):
   row.setdefault('previous_sources',[]).append({k:row[k] for k in ['source','source_sha256','manifest','version']})
 else:
  row={'asset_id':aid,'license':'pending_user_reference_rights_review','geometry_fingerprint':None};rows.append(row);lookup[aid]=row
 row.update(common,name=name,source=str(source.relative_to(R)),source_sha256=sha(source),manifest=str(manifest.relative_to(R)),category=category,runtime_path=runtime_path,prefab=prefab,**extra)
 write(manifest,dict(row,asset_ledger=route['ledger']+'#'+aid));return row
active={e['asset_id'] for e in cat}
for e in export['components']:
 c=bykey[e['key']];row=put(e['asset_id'],e['name'],c['component_source'],Path(c['component_source']).parent/'asset_manifest.json',e['category'],e['glb'],e['prefab'],asset_key=e['key'],runtime_scope='太阳能木屋-海上区域组件',geometry_fingerprint=c['geometry_fingerprint'],note='v006：全地面木铺板、去帆布和挂钩、伞桌移至右前角、花缩至75%；建筑与花草分离。')
for row in rows:
 if row['asset_id'].startswith('SEA-SCENE-SBR-') and row['asset_id'] not in active and row.get('category') in ['structure','flora','fixture']:
  row.update(stage='historical_source_retained',runtime_verified=False,runtime_active=False,runtime_scope='当前未使用；保留历史源与稳定组件供回退',note='历史退出组件及本轮移除的帆布/挂钩；历史资源保留。')
assembly=put('SEA-SCENE-SBR-ASSEMBLY','太阳能木屋-海上区域',D/'sunny_bloom_retreat.blend',D/'asset_manifest.json','scene_assembly','godot/assets/models/facilities/solar_cabin/instances.json','godot/scenes/facilities/solar_cabin_surface.tscn',asset_key='sunny_bloom_retreat',runtime_scope='四分区：后部建筑、太阳能房、可行动平台、桥',note='楼顶露台和地坪改暖木整板，移除帆布与挂钩；伞区移至右前角避开遮阳板，花缩至75%；既有厚底板和绳胎桥保留。')
opt=put('SEA-SCENE-SBR-OPTIMIZED','太阳能木屋-独立优化导出源',R/export['optimized_source'],E/'optimized_asset_manifest.json','optimized_export_source',None,None,note='45组件独立优化，原源/公共色板哈希保护；源与优化固定四视图核对。')
parts=[('rear_building','后部方形建筑'),('solar_room','前部倾斜太阳能房'),('front_platform','前方可行动平台-酒红'),('bridge','栈桥-暖木')]
for key,name in parts:
 aid='SEA-SCENE-SBR-MODULE-'+key.upper().replace('_','-');p=D/'modules'/key/(key+'.blend');put(aid,'太阳能木屋-'+name,p,p.parent/'asset_manifest.json','scene_module','godot/assets/models/facilities/solar_cabin/instances.json',f'godot/scenes/facilities/solar_cabin_{key}.tscn',asset_key=key,runtime_scope=key,instance_count=sum(e['module']==key for e in layout),note='独立可打开的 linked assembly；组件母版唯一，平台与桥不同色且分别管理。')
placement=E/'placement/solar_cabin/solar_cabin_v1.3.blend';pm=json.loads((E/'placement_manifest.json').read_text());assert pm['placement_sha256']==sha(placement)
put('SEA-REF-FACILITY-SOLAR-CABIN','太阳能木屋',placement,placement.parent/'asset_manifest.json','facility_assembly','godot/assets/models/facilities/solar_cabin/instances.json','godot/scenes/facilities/solar_cabin.tscn',asset_key='solar_cabin',runtime_scope='v006海上区域 + 七层新版海下基座',note='当前可编辑装配1.3；海上四分区，海下采用bloom_lower_building七层楼体，绞盘打捞台保持独立；0.1备份与上一版均保留。')

LD=R/'art_source/scenes/bloom_lower_building/v001';LE=LD/'export/v001';lower=json.loads((LE/'export_manifest.json').read_text());lowercheck=json.loads((W/'lower_source_verification.json').read_text());assert lowercheck['passed']
assert sha(R/lower['source'])==lower['source_sha256'] and sha(R/lower['optimized_source'])==lower['optimized_sha256']
active_lower={e['asset_id'] for e in lower['fit']['instances']};lower_common=dict(version='v001',runtime_version='1.0',optimized_source=lower['optimized_source'],optimized_sha256=lower['optimized_sha256'],export_manifest=str((LE/'export_manifest.json').relative_to(R)))
for e in lower['components']:
 assert sha(R/e['glb'])==e['glb_sha256']
 imp=R/(e['glb']+'.import');assert 'gltf/embedded_image_handling=0' in imp.read_text()
 before=sum(o['triangles_before'] for o in e['optimization']);after=e['exported_triangles'];e.update(triangles_before=before,triangles_after=after,reduction_ratio=1-after/before,import_sha256=sha(imp),source_version='v001',fidelity_review='passed fixed-camera front/back/side/top with actual fitting transform',runtime_verified=True,runtime_active=e['asset_id'] in active_lower)
 # Unused roof tiles/rims/buds remain valid independent exported components; current fit omits them.
 row=put(e['asset_id'],e['name'],e['source'],Path(e['source']).parent/'asset_manifest.json',e['category'],e['glb'],e['prefab'],asset_key=e['key'],runtime_scope='太阳能木屋-海下基座组件',note='七层新楼体组件；接口重叠的原屋顶砖/顶边/顶层花草不实例化，原制作源不改。')
 row.update(lower_common,runtime_active=e['asset_id'] in active_lower);write(R/row['manifest'],dict(row,asset_ledger=route['ledger']+'#'+e['asset_id']))
row=put('SEA-SCENE-BLB-ASSEMBLY','太阳能木屋-海下基座',LD/'bloom_lower_building.blend',LD/'asset_manifest.json','scene_assembly','godot/assets/models/facilities/bloom_lower_building/instances.json','godot/scenes/facilities/solar_cabin_submerged_base.tscn',runtime_scope='太阳能木屋-海下基座',note='七层新楼体替换全部旧海下基座；原独立源哈希不变，实例适配缩放2.5/1.5/1.5，顶板Y=1.46贴合木地板底面。')
row.update(lower_common);write(R/row['manifest'],dict(row,asset_ledger=route['ledger']+'#'+row['asset_id']))
row=put('SEA-SCENE-BLB-OPTIMIZED','太阳能木屋-海下基座独立优化源',R/lower['optimized_source'],LE/'optimized_asset_manifest.json','optimized_export_source',None,None,note='22个下半建筑组件独立优化，保存重开再逐个导出；原源及共享色板不变。')
row.update(lower_common);write(R/row['manifest'],dict(row,asset_ledger=route['ledger']+'#'+row['asset_id']))
for aid in ['SEA-REF-01-ZONE1-HOME-HARBOR--UNIT-01','SEA-REF-01-ZONE1-HOME-HARBOR--UNIT-02','SEA-REF-01-ZONE1-HOME-HARBOR--UNIT-03','SEA-REF-01-ZONE1-HOME-HARBOR--DETAIL']:
 row=lookup[aid];assert sha(R/row['source'])==row['source_sha256'];row.update(stage='historical_source_retained',runtime_active=False,runtime_verified=False,runtime_scope='历史参照；原海下基座已被七层新楼体替换',note='保留v0.x替换参照与稳定旧文件，当前太阳能木屋包装不再引用。');write(R/row['manifest'],dict(row,asset_ledger=route['ledger']+'#'+aid))
write(LE/'export_manifest.json',lower)
write(bp,book)
ip=R/'assets/registry/current_source_index.json';ix=json.loads(ip.read_text());ix['sources']=[]
for rt in json.loads((R/'assets/registry/ledger_index.json').read_text())['domains'].values():
 for e in json.loads((R/rt['ledger']).read_text())[rt['asset_key']]:ix['sources'].append({k:e[k] for k in ['asset_id','source','source_sha256','manifest']})
write(ip,ix)
# Hash updates are limited to explicit task inputs and exported active assets.
inventory_path=R/'assets/registry/runtime_resource_inventory.json';inventory=json.loads(inventory_path.read_text());allowed={e['glb'] for e in export['components']}|{'godot/assets/models/facilities/solar_cabin/instances.json','godot/assets/baked/shore.json','godot/assets/data/zones.json','godot/assets/data/build_sites.json','godot/assets/data/gather_spots.json','godot/assets/models/facilities/solar_cabin/revision_metrics.json'};updated=[]
for row in inventory['resources']:
 p=R/row['path'];h=sha(p)
 if h==row['sha256']:continue
 assert row['path'] in allowed,'Unrelated runtime drift: '+row['path']
 row.update(previous_sha256=row['sha256'],sha256=h,bytes=p.stat().st_size,note='v006模型/行走/泊位已审阅变更');updated.append(row['path'])
existing={e['path'] for e in inventory['resources']}
for path,aid in [(e['glb'],e['asset_id']) for e in export['components']]+[('godot/assets/models/facilities/solar_cabin/revision_metrics.json','SEA-SCENE-SBR-ASSEMBLY')]+[(e['glb'],e['asset_id']) for e in lower['components']]+[('godot/assets/models/facilities/bloom_lower_building/instances.json','SEA-SCENE-BLB-ASSEMBLY'),('godot/assets/models/facilities/bloom_lower_building/revision_metrics.json','SEA-SCENE-BLB-ASSEMBLY')]:
 if path not in existing:inventory['resources'].append(dict(path=path,bytes=(R/path).stat().st_size,sha256=sha(R/path),asset_id=aid,status='runtime_integrated_verified'))
write(inventory_path,inventory)
runtime=json.loads((V/'project/outputs/solar-cabin-runtime.json').read_text());verification=dict(version='v006',runtime_version='1.3',source=sourcecheck,lower_source=lowercheck,lower_optimization=dict(before=lower["expanded_triangles_before"],after=lower["expanded_triangles_after"]),protected_sources=json.loads((W/'protected_sources.json').read_text()),before_backup=str(W/'before'),before_backup_files=len(snap),runtime=runtime,runtime_results=proof['results'],run_dir=str(V),optimization=dict(before=export['expanded_triangles_before'],after=export['expanded_triangles_after'],reduction_ratio=1-export['expanded_triangles_after']/export['expanded_triangles_before']),fidelity_views_reviewed=['front','back','side','top'],runtime_hash_updates=updated,not_run=['长时间性能测试','参考图商业授权审核'])
write(W/'delivery_verification.json',verification);write(R/'docs/development/2026-10-26_solar_cabin_v006_verification.json',verification)
all_dir=R.parent/'sea-work/verification/20261026-075640-solar-cabin-v006-all-packages-67c37b';allproof=json.loads((all_dir/'report.json').read_text());assert all(e['passed'] for e in allproof['results'].values())
verification['all_component_load_check']=allproof['results'];verification['lower_instance_count']=len(lower['fit']['instances']);verification['lower_excluded_instances']=len(lower['fit']['excluded']);verification['lower_fit']=dict(scale_blender=[2.5,1.5,1.5],top_y=1.46,storeys=7)
write(W/'delivery_verification.json',verification);write(R/'docs/development/2026-10-26_solar_cabin_v006_verification.json',verification)
p=R/'docs/features/asset/spec.md';s=p.read_text();assert 'SEA-ASSET-R21' not in s;s=s.replace('\n\n### SEA-ASSET-R12','\n| SEA-ASSET-R21 | 太阳能木屋v006所有可见地坪及露台铺木板，移除楼顶帆布及挂钩；太阳伞移至平台右前角避开遮阳板，花朵缩小25%；以此前独立制作的七层bloom_lower_building替换旧海下基座，保留海上/海下归类及稳定包装，独立优化逐组件导出并核对接合、颜色、航路和实景。 |\n\n### SEA-ASSET-R12',1);p.write_text(s)
p=R/'docs/features/asset/ledger.md';s=p.read_text();s=s.replace('\n\n## 资源与调用入口','\n| SEA-ASSET-R21 | v006上下部分均正式接入，实景与专项通过 | 海上45组件161实例；海下22组件导出、19组件298实例使用；67组件独立加载、468实景检查、30航路503检查和537自检通过；见v006记录 |\n\n## 资源与调用入口',1)
s+='\n## 太阳能木屋 v006 / 新七层海下基座（2026-10-26）\n\n- [本轮记录](../../development/2026-10-26_solar_cabin_v006.md)；[源与总装入口](../../../art_source/scenes/sunny_bloom_retreat/v006/README.md)。\n- 木地板、去帆布、伞区避让、花缩小；海下基座已用新七层楼体替换。SEA-ASSET-R14原制作源保持，接入状态以本记录为准。\n';p.write_text(s)
p=R/'docs/features/world/ledger.md';p.write_text(p.read_text()+'\n## 太阳能木屋v006（2026-10-26）\n\n稳定solar_cabin_submerged_base.tscn已切换为七层新楼体组件，旧四个基座资源退出引用；海上四分区保持。实例脚本新增可配置数据和组件路径供上下部分分别使用。上岸、行走、泊位不变；468实景检查和30航路503检查通过。[本轮证据](../../development/2026-10-26_solar_cabin_v006.md)。\n')
readme='''# 太阳能木屋 v006 / 游戏装配 1.3

[海上制作源](sunny_bloom_retreat.blend) · [完整游戏比例装配](export/v001/placement/solar_cabin/solar_cabin_v1.3.blend) · [组件计划](component_plan.json)

完整装配按“太阳能木屋-海上区域 / 太阳能木屋-海下基座”分组；海下采用七层新版楼体，独立绞盘台保留。

| 中文分区 | Blender文件 |
|---|---|
'''
for key,name in parts:readme+=f'| 太阳能木屋-{name} | [{key}.blend](modules/{key}/{key}.blend) |\n'
readme+='''
新增木铺板覆盖后区地坪和顶楼露台；前平台仍酒红色、桥仍暖木色。顶楼帆布和挂钩移除，承重柱保留。太阳伞移至右前角，与遮阳板无交叠；粉/白花缩至原75%，花叶独立。

海上45组件、161实例；海下[独立原源](../../bloom_lower_building/v001/bloom_lower_building.blend)不改，22组件独立导出，当前实例化19组件共298次；原屋顶砖、顶边及会穿入上部木地板的顶层花草不实例化。旧v005和0.1备份保留。

海上Godot系数1.15，地板Y=2.15米。海下源Blender XYZ适配系数(2.5,1.5,1.5)，前向映射+Z，顶板Y=1.46贴木地板底面；七层保持。GLB和Godot包装路径稳定，按独立组件管理。
'''
(D/'README.md').write_text(readme)
(E/'README.md').write_text('# 太阳能木屋 v006 导出\n\n[完整游戏比例装配1.3](placement/solar_cabin/solar_cabin_v1.3.blend) · [海上独立优化源](solar_cabin_optimized_v001.blend) · [导出清单](export_manifest.json)\n\n上部45组件，下部来源bloom_lower_building/v001/export/v001，各自保留优化文件；不导出整屋GLB。\n')
(LE/'README.md').write_text('# 七层海下基座导出\n\n[独立优化源](bloom_lower_building_optimized_v001.blend) · [导出清单](export_manifest.json) · [上下建筑总装](../../../sunny_bloom_retreat/v006/export/v001/placement/solar_cabin/solar_cabin_v1.3.blend)\n\n22组件保存重开后逐个导出，当前19组件298实例用于太阳能木屋海下基座。原七层制作源保持不改；顶板接口Y=1.46米，源XYZ适配比例2.5/1.5/1.5。\n')
p=R/'art_source/scenes/bloom_lower_building/README.md';s=p.read_text();s=s.replace('按本轮附件单独制作，没有拼接到上半建筑。','独立制作源保留；2026-10-26已在游戏中作为太阳能木屋海下基座接入。').replace('Godot 接入、碰撞、运行性能、参考图商业授权及用户最终美术验收 pending。','2026-10-26：Godot组件接入、七层接合与真实渲染检查通过；共用既有游戏行走/导航，未新增室内玩法碰撞。长时间性能基准、参考图商业授权及用户最终美术验收 pending。\n\n[接入记录](../../../docs/development/2026-10-26_solar_cabin_v006.md) · [完整游戏比例装配](../sunny_bloom_retreat/v006/export/v001/placement/solar_cabin/solar_cabin_v1.3.blend)。');p.write_text(s)
p=R/'art_source/scenes/runtime_building_reference/README.md';s=p.read_text().replace('../sunny_bloom_retreat/v005/export/v001/placement/solar_cabin/solar_cabin_v1.2.blend','../sunny_bloom_retreat/v006/export/v001/placement/solar_cabin/solar_cabin_v1.3.blend').replace('../sunny_bloom_retreat/v005/README.md','../sunny_bloom_retreat/v006/README.md');p.write_text(s)
text='''# 太阳能木屋 v006：全木地坪、伞区避让及新海下基座

[制作源及模块入口](../../art_source/scenes/sunny_bloom_retreat/v006/README.md) · [完整装配1.3](../../art_source/scenes/sunny_bloom_retreat/v006/export/v001/placement/solar_cabin/solar_cabin_v1.3.blend) · [结构化验证](2026-10-26_solar_cabin_v006_verification.json)

## 本轮修改

以本任务已保存v005另存v006；后区水泥地坪、上层露台及右侧延伸地面改成暖木长板。室内地面也使用木色；酒红前平台与暖木桥维持异色分区。保留实体厚度和顶面高度，帆布及墙面固定钩移除，顶楼残柱继续保留。太阳伞、主桌、凳子和瓶子重新排在右前角；实际伞包络与遮阳板在平面上分离，避免穿插。粉花/白花均缩为75%，保留原方向和植物叶簇。

水下采用用户此前独立制作的bloom_lower_building/v001七层楼体，替换原四块旧海下基座。未改写该制作源，独立优化后逐组件导出；原屋顶铺砖、顶边和顶层会侵入木地板的花草不实例化，原源仍完整保留。22组件可独立加载，当前19种298实例；下层花朵亦缩至75%。

海下源XYZ实例适配比例2.5/1.5/1.5，Godot锚点(5.533,-17.02,1.6)，前向+Z；七层层高保留1.5倍，顶板上沿Y=1.46与海上厚木板底面对接。总包络包含花草约13.921×18.480×14.008米。根节点比例1，具体适配写入实例矩阵并在完整Blender装配内复现。

正式solar_cabin.tscn与海上/海下子包装路径保持；海下包装改引用新组件实例。组件脚本允许配置实例JSON和组件目录，海上保持默认值。独立绞盘台、主泊位、上岸点和可走区域不变；没有运行旧全区生成器。

## 当前验证

海上45组件及4分区保存重开、38266面PaletteUV检查通过；海下22独立包重新打开、26416面UV检查通过。v005输入、七层原源和共享色板哈希保护通过。上下优化文件均另存并重开后导出，无内嵌纹理，Closest公共色板。两套源/优化正背侧顶四视图对照通过，运行实景正背顶、场景上下文及水下接合视角已核对。

通过scripts/run_verification.py隔离存档执行：实景468检查0失败；当前64组件380检查，补充全部67组件独立加载检查；surface 30航路503检查；自检537通过。各专项exit0；仅自检有一条已知预期损坏JSON负向错误，无非预期错误。未执行长时间性能基准及与本次未变逻辑相关的click/management专项。

本轮修改前运行文件已复制到sea-work/solar_cabin_revision_v006/before，逐文件核对SHA；原0.1快照与v005保留。旧基座资源保留供回退，账本标为历史退出。参考图授权仍pending。没有Git提交。
'''
text+=f'\n备份{len(snap)}文件。海上优化展开三角面{export["expanded_triangles_before"]}→{export["expanded_triangles_after"]}；海下实际装配{lower["expanded_triangles_before"]}→{lower["expanded_triangles_after"]}。运行证据`{V}`，全组件补查`{all_dir}`。\n'
(R/'docs/development/2026-10-26_solar_cabin_v006.md').write_text(text)
print('Registered v006 plus new submerged base; protected prior sources and explicit runtime hashes.')

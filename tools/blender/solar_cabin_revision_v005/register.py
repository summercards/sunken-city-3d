"""Register only the verified v005 revision; preserve all previous source rows."""
from pathlib import Path
import json,hashlib,struct
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v005';E=D/'export/v001';W=R.parent/'sea-work/solar_cabin_revision_v005';V=R.parent/'sea-work/verification/20261025-225130-solar-cabin-v005-3d6e6c'
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
 e.update(source=bykey[e['key']]['component_source'],source_sha256=sha(R/bykey[e['key']]['component_source']),source_version='v005',optimized_source=export['optimized_source'],optimized_sha256=export['optimized_sha256'],triangles_before=before,triangles_after=after,reduction_ratio=1-after/before,budget=None,budget_source='No explicit numeric cap for this revision',import_sha256=sha(imp),fidelity_review='passed fixed-camera front/back/side/top silhouette, openings, palette boundaries',runtime_verified=True)
write(E/'export_manifest.json',export)
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes'];bp=R/route['ledger'];book=json.loads(bp.read_text());rows=book[route['asset_key']];lookup={e['asset_id']:e for e in rows}
common=dict(domain='scenes',stage='runtime_integrated_verified',version='v005',runtime_version='1.2',runtime_verified=True,consumer_features=['SEA-ASSET','SEA-WORLD'],scope='scene_local',optimized_source=export['optimized_source'],optimized_sha256=export['optimized_sha256'],export_manifest=str((E/'export_manifest.json').relative_to(R)))
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
 c=bykey[e['key']];row=put(e['asset_id'],e['name'],c['component_source'],Path(c['component_source']).parent/'asset_manifest.json',e['category'],e['glb'],e['prefab'],asset_key=e['key'],runtime_scope='太阳能木屋-海上区域组件',geometry_fingerprint=c['geometry_fingerprint'],note='v005：承重轴续柱、阳光房右移、底板加厚、桥延长和桥边绳/挂胎；建筑与花草分离。')
for row in rows:
 if row['asset_id'].startswith('SEA-SCENE-SBR-') and row['asset_id'] not in active and row.get('category') in ['structure','flora','fixture']:
  row.update(stage='historical_source_retained',runtime_verified=False,runtime_active=False,runtime_scope='当前未使用；保留历史源与稳定组件供回退',note='历史已移除的灰承台、细拼板、藤蔓、裂叶植物及本轮退出的棚架横梁；历史资源未删除。')
assembly=put('SEA-SCENE-SBR-ASSEMBLY','太阳能木屋-海上区域',D/'sunny_bloom_retreat.blend',D/'asset_manifest.json','scene_assembly','godot/assets/models/facilities/solar_cabin/instances.json','godot/scenes/facilities/solar_cabin_surface.tscn',asset_key='sunny_bloom_retreat',runtime_scope='四分区：后部建筑、太阳能房、可行动平台、桥',note='承重柱同轴向上延续、前低后高；阳光房右移1.25源单位让出梯子；地板厚0.60源单位，桥增加两排整板及两侧绳索/四个轮胎；右侧休闲区保留。')
opt=put('SEA-SCENE-SBR-OPTIMIZED','太阳能木屋-独立优化导出源',R/export['optimized_source'],E/'optimized_asset_manifest.json','optimized_export_source',None,None,note='47组件独立优化，原源/公共色板哈希保护；源与优化固定四视图核对。')
parts=[('rear_building','后部方形建筑'),('solar_room','前部倾斜太阳能房'),('front_platform','前方可行动平台-酒红'),('bridge','栈桥-暖木')]
for key,name in parts:
 aid='SEA-SCENE-SBR-MODULE-'+key.upper().replace('_','-');p=D/'modules'/key/(key+'.blend');put(aid,'太阳能木屋-'+name,p,p.parent/'asset_manifest.json','scene_module','godot/assets/models/facilities/solar_cabin/instances.json',f'godot/scenes/facilities/solar_cabin_{key}.tscn',asset_key=key,runtime_scope=key,instance_count=sum(e['module']==key for e in layout),note='独立可打开的 linked assembly；组件母版唯一，平台与桥不同色且分别管理。')
placement=E/'placement/solar_cabin/solar_cabin_v1.2.blend';pm=json.loads((E/'placement_manifest.json').read_text());assert pm['placement_sha256']==sha(placement)
put('SEA-REF-FACILITY-SOLAR-CABIN','太阳能木屋',placement,placement.parent/'asset_manifest.json','facility_assembly','godot/assets/models/facilities/solar_cabin/instances.json','godot/scenes/facilities/solar_cabin.tscn',asset_key='solar_cabin',runtime_scope='v005海上区域 + 原海下基座',note='当前可编辑装配1.2；海上四分区，绞盘打捞台保持独立；0.1备份与上一版均保留。')
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
 row.update(previous_sha256=row['sha256'],sha256=h,bytes=p.stat().st_size,note='v005模型/行走/泊位已审阅变更');updated.append(row['path'])
existing={e['path'] for e in inventory['resources']}
for path,aid in [(e['glb'],e['asset_id']) for e in export['components']]+[('godot/assets/models/facilities/solar_cabin/revision_metrics.json','SEA-SCENE-SBR-ASSEMBLY')]:
 if path not in existing:inventory['resources'].append(dict(path=path,bytes=(R/path).stat().st_size,sha256=sha(R/path),asset_id=aid,status='runtime_integrated_verified'))
write(inventory_path,inventory)
runtime=json.loads((V/'project/outputs/solar-cabin-runtime.json').read_text());verification=dict(version='v005',runtime_version='1.2',source=sourcecheck,protected_sources=json.loads((W/'protected_sources.json').read_text()),before_backup=str(W/'before'),before_backup_files=len(snap),runtime=runtime,runtime_results=proof['results'],run_dir=str(V),optimization=dict(before=export['expanded_triangles_before'],after=export['expanded_triangles_after'],reduction_ratio=1-export['expanded_triangles_after']/export['expanded_triangles_before']),fidelity_views_reviewed=['front','back','side','top'],runtime_hash_updates=updated,not_run=['长时间性能测试','参考图商业授权审核'])
write(W/'delivery_verification.json',verification);write(R/'docs/development/2026-10-25_solar_cabin_v005_verification.json',verification)
# Record this revision independently from the previous acceptance evidence.
spec=R/'docs/features/asset/spec.md';s=spec.read_text()
rule='| SEA-ASSET-R20 | 太阳能木屋 v005 顶楼水泥残柱与下方承重柱同轴延续，前柱低、后两柱高；阳光房整体右移让出梯子，底板加厚圆角且顶面高度不变；桥加长两排整板，侧边垂绳悬挂四个轮胎，两端保留通行。独立新版源、47组件与四分区，正式接入并同步桥头登岸、行走范围和岸线。 |'
assert 'SEA-ASSET-R20' not in s
s=s.replace('\n\n### SEA-ASSET-R12','\n'+rule+'\n\n### SEA-ASSET-R12',1);spec.write_text(s)
p=R/'docs/features/asset/ledger.md';s=p.read_text();line='| SEA-ASSET-R20 | v005 源级、接入与真实渲染通过 | 47组件163实例、4分区重开；37486面UV核验；112实景检查、259组件检查、30航路503检查、537自检通过；见v005记录 |'
s=s.replace('\n\n## 资源与调用入口','\n'+line+'\n\n## 资源与调用入口',1)
s+='\n## 太阳能木屋 v005（2026-10-25）\n\n- [本轮记录](../../development/2026-10-25_solar_cabin_v005.md)；[当前制作源](../../../art_source/scenes/sunny_bloom_retreat/v005/sunny_bloom_retreat.blend)。\n- 承重轴续柱、前低后高；阳光房右移；厚底板、延长桥、边绳和挂胎。旧版及0.1备份保留。\n';p.write_text(s)
for feature,content in [('world','SEA-WORLD：太阳能木屋四分区稳定包装接入v005；新增绳索与轮胎组件，真实渲染确认柱轴、梯子净空、桥边挂胎。'),('move','SEA-MOVE：桥长增加1.587米，更新主桥可走矩形和登岸点；顶面Y=2.15不变，30航路503检查及537自检通过。'),('nav','SEA-NAV：主桥泊位、登岸点及岸线随桥端向+Z延伸1.587米；30条跨区路线本轮通过，其他泊位不变。')]:
 p=R/f'docs/features/{feature}/ledger.md';p.write_text(p.read_text()+'\n## 太阳能木屋 v005（2026-10-25）\n\n'+content+' [当前证据](../../development/2026-10-25_solar_cabin_v005.md)。\n')
readme='''# 太阳能木屋 v005 / 游戏装配 1.2

[完整制作源](sunny_bloom_retreat.blend) · [游戏比例装配](export/v001/placement/solar_cabin/solar_cabin_v1.2.blend) · [组件计划](component_plan.json)

| 中文名称 | Blender文件 | Godot包装 |
|---|---|---|
'''
for key,name in parts:readme+=f'| 太阳能木屋-{name} | [{key}.blend](modules/{key}/{key}.blend) | `godot/scenes/facilities/solar_cabin_{key}.tscn` |\n'
readme+='''
顶楼三根柱沿下层承重轴向上延续，前低后高；阳光房向右平移，梯子净空；水泥地坪、酒红平台和暖木桥加厚圆角，顶面保持不变。桥增加两排横向整板，两侧垂绳共挂四个轮胎。太阳伞休闲区保留。

47组件、163实例；建筑与花草独立集合。旧v004和原0.1备份保留。游戏比例装配包括海上四分区、原海下基座及独立打捞台；制作源只有本次海上建筑。

Godot导入系数1.15，相对v003总1.725倍，正面+Z、地板Y=2.15米。主墙宽8.625米；阳光房较v004右移1.4375米，桥延长1.587米。含植物/绳胎包围盒约15.953×22.606米，高11.465米。
'''
(D/'README.md').write_text(readme)
(E/'README.md').write_text('# 太阳能木屋 v005 导出\n\n[当前游戏比例装配](placement/solar_cabin/solar_cabin_v1.2.blend) · [独立优化源](solar_cabin_optimized_v001.blend) · [导出清单](export_manifest.json)\n\n47组件分别导出，四个Godot分区包装独立；平台与桥异色分别管理。源与优化固定四视图比较通过。\n')
p=R/'art_source/scenes/runtime_building_reference/README.md';s=p.read_text().replace('../sunny_bloom_retreat/v004/export/v001/placement/solar_cabin/solar_cabin_v1.1.blend','../sunny_bloom_retreat/v005/export/v001/placement/solar_cabin/solar_cabin_v1.2.blend').replace('../sunny_bloom_retreat/v004/README.md','../sunny_bloom_retreat/v005/README.md');p.write_text(s)
text='''# 太阳能木屋 v005：续柱、梯子净空与延长挂胎桥

## 文件入口

- [完整制作源与四分区](../../art_source/scenes/sunny_bloom_retreat/v005/README.md)
- [游戏比例装配1.2](../../art_source/scenes/sunny_bloom_retreat/v005/export/v001/placement/solar_cabin/solar_cabin_v1.2.blend)
- [优化与导出清单](../../art_source/scenes/sunny_bloom_retreat/v005/export/v001/export_manifest.json)
- [结构化验证](2026-10-25_solar_cabin_v005_verification.json)

## 本轮修改

以已保存v004为输入另存v005，未运行旧全区构建器。三根顶楼水泥柱精确沿下层承重柱中心轴延续，前柱源高2.70、后两柱3.30；去掉原棚架横梁，以轻微不平的柱顶表达拆除上层后的残柱。遮阳布重新连接柱顶和墙面。

阳光房连屋面、太阳能板、侧墙、门窗和附属花草整体右移源X=1.25（游戏1.4375米），让出梯子；实际梯子与侧墙净距超过源0.55。水泥地坪、酒红平台和暖木桥实体厚度增至源0.60（游戏0.69米），加宽倒角，顶面仍是游戏Y=2.15米。原海下建筑基座保持，未恢复灰石承台。

桥由6排增加至8排横向整板，长度增加源1.38（游戏1.587米）；桥端绳柱、主泊位、上岸点、可走区域和岸线同步延伸。两侧麻绳自然下垂，各悬挂两个实体橡胶轮胎，共四个；吊绳接到侧绳，轮胎有贯穿圆孔和胎侧环纹，桥头/桥尾保持开放。

保留右侧太阳伞、桌椅、冷藏箱和盆栽；酒红平台和暖木桥继续独立管理。四语义分区不变，共47母版组件、163实例。稳定Godot包装不变，旧棚架横梁仅退出使用，历史文件不删除。

## 验收

源级47组件文件与4分区逐个重开，37486面PaletteUV检查通过；v004源及公共色板SHA保护通过。独立优化源保存重开再逐组件导出，四视图比较轮廓、开口及色块边界保持；47个GLB不内嵌纹理，导入embedded_image_handling=0，共用色板Nearest。

通过scripts/run_verification.py隔离存档执行当前版本：真实Metal渲染112检查、47组件259检查、surface 30航路503检查、自检537检查全部通过，退出码均0。selftest有一条既有预期损坏JSON负向测试错误；非预期错误0。源预览、优化四视图、游戏正面和场景上下文均已目视核对。

本轮未执行长时间性能基准，未重复与本次无关的click/management专项；参考图商业授权仍pending。原0.1快照、上一版源和本轮修改前快照保留，没有Git提交。
'''
text+=f'\n本轮备份{len(snap)}个文件，逐文件哈希核对。优化展开三角面{export["expanded_triangles_before"]}→{export["expanded_triangles_after"]}。运行证据：`{V}`。\n'
(R/'docs/development/2026-10-25_solar_cabin_v005.md').write_text(text)
print('Registered v005; current sources and 4 modules; runtime hashes updated:',len(updated))

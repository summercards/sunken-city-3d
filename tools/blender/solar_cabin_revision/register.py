"""Register only the verified v004 revision; preserve all previous source rows."""
from pathlib import Path
import json,hashlib,struct
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v004';E=D/'export/v001';W=R.parent/'sea-work/solar_cabin_revision_v004';V=R.parent/'sea-work/verification/20261025-222342-solar-cabin-v004-f0df84'
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
 e.update(source=bykey[e['key']]['component_source'],source_sha256=sha(R/bykey[e['key']]['component_source']),source_version='v004',optimized_source=export['optimized_source'],optimized_sha256=export['optimized_sha256'],triangles_before=before,triangles_after=after,reduction_ratio=1-after/before,budget=None,budget_source='No explicit numeric cap for this revision',import_sha256=sha(imp),fidelity_review='passed fixed-camera front/back/side/top silhouette, openings, palette boundaries',runtime_verified=True)
write(E/'export_manifest.json',export)
route=json.loads((R/'assets/registry/ledger_index.json').read_text())['domains']['scenes'];bp=R/route['ledger'];book=json.loads(bp.read_text());rows=book[route['asset_key']];lookup={e['asset_id']:e for e in rows}
common=dict(domain='scenes',stage='runtime_integrated_verified',version='v004',runtime_version='1.1',runtime_verified=True,consumer_features=['SEA-ASSET','SEA-WORLD'],scope='scene_local',optimized_source=export['optimized_source'],optimized_sha256=export['optimized_sha256'],export_manifest=str((E/'export_manifest.json').relative_to(R)))
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
 c=bykey[e['key']];row=put(e['asset_id'],e['name'],c['component_source'],Path(c['component_source']).parent/'asset_manifest.json',e['category'],e['glb'],e['prefab'],asset_key=e['key'],runtime_scope='太阳能木屋-海上区域组件',geometry_fingerprint=c['geometry_fingerprint'],note='v004：整体1.5倍修订，按实际可见实例复用；建筑与花草分离。')
for row in rows:
 if row['asset_id'].startswith('SEA-SCENE-SBR-') and row['asset_id'] not in active and row.get('category') in ['structure','flora','fixture']:
  row.update(stage='historical_source_retained',runtime_verified=False,runtime_active=False,runtime_scope='v004 未使用；保留 v003 源与稳定组件供回退',note='本轮按用户要求移除的灰承台、细拼板、藤蔓和裂叶植物；历史资源未删除。')
assembly=put('SEA-SCENE-SBR-ASSEMBLY','太阳能木屋-海上区域',D/'sunny_bloom_retreat.blend',D/'asset_manifest.json','scene_assembly','godot/assets/models/facilities/solar_cabin/instances.json','godot/scenes/facilities/solar_cabin_surface.tscn',asset_key='sunny_bloom_retreat',runtime_scope='四分区：后部建筑、太阳能房、可行动平台、桥',note='相对上一版整体放大50%；灰承台/藤蔓/裂叶移除，水泥后区和灰封顶、宽前窗、前伸太阳能房；保留右侧休闲区。')
opt=put('SEA-SCENE-SBR-OPTIMIZED','太阳能木屋-独立优化导出源',R/export['optimized_source'],E/'optimized_asset_manifest.json','optimized_export_source',None,None,note='46组件独立优化，原源/公共色板哈希保护；源与优化固定四视图核对。')
parts=[('rear_building','后部方形建筑'),('solar_room','前部倾斜太阳能房'),('front_platform','前方可行动平台-酒红'),('bridge','栈桥-暖木')]
for key,name in parts:
 aid='SEA-SCENE-SBR-MODULE-'+key.upper().replace('_','-');p=D/'modules'/key/(key+'.blend');put(aid,'太阳能木屋-'+name,p,p.parent/'asset_manifest.json','scene_module','godot/assets/models/facilities/solar_cabin/instances.json',f'godot/scenes/facilities/solar_cabin_{key}.tscn',asset_key=key,runtime_scope=key,instance_count=sum(e['module']==key for e in layout),note='独立可打开的 linked assembly；组件母版唯一，平台与桥不同色且分别管理。')
placement=E/'placement/solar_cabin/solar_cabin_v1.1.blend';pm=json.loads((E/'placement_manifest.json').read_text());assert pm['placement_sha256']==sha(placement)
put('SEA-REF-FACILITY-SOLAR-CABIN','太阳能木屋',placement,placement.parent/'asset_manifest.json','facility_assembly','godot/assets/models/facilities/solar_cabin/instances.json','godot/scenes/facilities/solar_cabin.tscn',asset_key='solar_cabin',runtime_scope='v004海上区域 + 原海下基座',note='当前可编辑装配1.1；海上四分区，绞盘打捞台保持独立；0.1备份与上一版均保留。')
write(bp,book)
ip=R/'assets/registry/current_source_index.json';ix=json.loads(ip.read_text());ix['sources']=[]
for rt in json.loads((R/'assets/registry/ledger_index.json').read_text())['domains'].values():
 for e in json.loads((R/rt['ledger']).read_text())[rt['asset_key']]:ix['sources'].append({k:e[k] for k in ['asset_id','source','source_sha256','manifest']})
write(ip,ix)
# Hash updates are limited to explicit task inputs and exported active assets.
inventory_path=R/'assets/registry/runtime_resource_inventory.json';inventory=json.loads(inventory_path.read_text());allowed={e['glb'] for e in export['components']}|{'godot/assets/models/facilities/solar_cabin/instances.json','godot/assets/baked/shore.json','godot/assets/data/zones.json','godot/assets/data/build_sites.json','godot/assets/data/gather_spots.json'};updated=[]
for row in inventory['resources']:
 p=R/row['path'];h=sha(p)
 if h==row['sha256']:continue
 assert row['path'] in allowed,'Unrelated runtime drift: '+row['path']
 row.update(previous_sha256=row['sha256'],sha256=h,bytes=p.stat().st_size,note='v004模型/行走/泊位已审阅变更');updated.append(row['path'])
existing={e['path'] for e in inventory['resources']}
for path,aid in [(e['glb'],e['asset_id']) for e in export['components']]+[('godot/assets/models/facilities/solar_cabin/revision_metrics.json','SEA-SCENE-SBR-ASSEMBLY')]:
 if path not in existing:inventory['resources'].append(dict(path=path,bytes=(R/path).stat().st_size,sha256=sha(R/path),asset_id=aid,status='runtime_integrated_verified'))
write(inventory_path,inventory)
runtime=json.loads((V/'project/outputs/solar-cabin-runtime.json').read_text());verification=dict(version='v004',runtime_version='1.1',source=sourcecheck,protected_sources=json.loads((W/'protected_sources.json').read_text()),before_backup=str(W/'before'),before_backup_files=len(snap),runtime=runtime,runtime_results=proof['results'],run_dir=str(V),optimization=dict(before=export['expanded_triangles_before'],after=export['expanded_triangles_after'],reduction_ratio=1-export['expanded_triangles_after']/export['expanded_triangles_before']),fidelity_views_reviewed=['front','back','side','top'],runtime_hash_updates=updated,not_run=['长时间性能测试','参考图商业授权审核'])
write(W/'delivery_verification.json',verification);write(R/'docs/development/2026-10-25_solar_cabin_v004_verification.json',verification)
spec=R/'docs/features/asset/spec.md';s=spec.read_text();rule='| SEA-ASSET-R19 | 太阳能木屋 v004 相对已接入版本连同后区整体放大50%，去除灰承台、藤蔓和裂叶植物；后区改水泥、灰封顶和宽窗，补后侧平台及连续女儿墙，梯子出口清空；太阳能房加宽加深向前延伸。前平台酒红横向整板、桥暖木整板且分别成组件；仅清桥入口，保留右侧太阳伞、桌椅、箱子和盆栽。独立新版源、四分区、组件导出与正式行走/泊位验证。 |';assert 'SEA-ASSET-R19' not in s;s=s.replace('\n\n### SEA-ASSET-R12','\n'+rule+'\n\n### SEA-ASSET-R12',1);spec.write_text(s)
p=R/'docs/features/asset/ledger.md';s=p.read_text();line='| SEA-ASSET-R19 | v004 源级、正式接入与真实渲染通过 | 46组件159实例，4独立分区文件；34772面UV核验，46独立包重开；104实机检查及46组件独立加载通过，surface/click/management/selftest本轮通过；见v004记录 |';s=s.replace('\n\n## 资源与调用入口','\n'+line+'\n\n## 资源与调用入口',1);s+='\n## 太阳能木屋 v004 模型修订（2026-10-25）\n\n- [本轮记录](../../development/2026-10-25_solar_cabin_v004.md)；[当前制作源](../../../art_source/scenes/sunny_bloom_retreat/v004/sunny_bloom_retreat.blend)。\n- 新版海上四分区与海下原基座分别管理，右侧太阳伞休闲区保留，桥入口和梯子顶端清空。\n';p.write_text(s)
for feature,content in [('world','SEA-WORLD：稳定太阳能木屋包装内改为四个独立海上分区，海下基座与打捞台保持；真实渲染确认整体1.5倍和后区扩建。'),('move','SEA-MOVE：同步放大后的桥与平台可走矩形、main 登岸点、种植点和交互点；surface、click、management、selftest 本轮全通过。'),('nav','SEA-NAV：同步新桥泊位及扩展岸线，30条航路本轮通过；未改变独立绞盘台泊位。')]:
 p=R/f'docs/features/{feature}/ledger.md';p.write_text(p.read_text()+'\n## 太阳能木屋 v004（2026-10-25）\n\n'+content+' [当前证据](../../development/2026-10-25_solar_cabin_v004.md)。\n')
readme='''# 太阳能木屋 v004 / 游戏装配 1.1

[完整制作源](sunny_bloom_retreat.blend) · [游戏比例装配](export/v001/placement/solar_cabin/solar_cabin_v1.1.blend) · [组件计划](component_plan.json)

## 独立分区

| 中文名称 | Blender文件 | Godot包装 |
|---|---|---|
'''
for key,name in parts:readme+=f'| 太阳能木屋-{name} | [{key}.blend](modules/{key}/{key}.blend) | `godot/scenes/facilities/solar_cabin_{key}.tscn` |\n'
readme+='''
平台采用酒红色横向整板，桥采用暖木色整板。桥入口清空，右侧休闲区、盆栽及外缘绳柱保留。原v003与0.1快照不改。

制作源相对v003放大1.5倍；游戏继续应用1.15导入比例，总比例为原v003的1.725倍，正面Godot +Z，地板Y=2.15米。后部主墙宽8.625米；整体含花草、桥的运行范围约14.52×21.02米。海下基座保留；本轮移除的是海上模型底部灰色承台。
'''
(D/'README.md').write_text(readme)
(E/'README.md').write_text('# 太阳能木屋 v004 导出\n\n[当前游戏比例装配](placement/solar_cabin/solar_cabin_v1.1.blend) · [独立优化源](solar_cabin_optimized_v001.blend) · [导出清单](export_manifest.json)\n\n46组件分别导出，原制作源及公共色板不改。四个Godot分区包装独立，平台与桥分别管理。\n')
p=R/'art_source/scenes/runtime_building_reference/README.md';s=p.read_text();s=s.replace('../sunny_bloom_retreat/v003/export/v001/placement/solar_cabin/solar_cabin_v1.0.blend','../sunny_bloom_retreat/v004/export/v001/placement/solar_cabin/solar_cabin_v1.1.blend').replace('../sunny_bloom_retreat/v003/export/v001/README.md','../sunny_bloom_retreat/v004/README.md');p.write_text(s)
(R/'docs/development/2026-10-25_solar_cabin_v004.md').write_text('''# 太阳能木屋 v004 模型修订与游戏接入

本轮根据用户七项修改及后续标注：整体连后部放大50%，平台与桥拆开且异色；保留右侧太阳伞休闲区、盆栽和边缘绳柱，仅移除桥入口的中间杂物；后侧增加实际平台进深及女儿墙，移除梯子出口植物。

## 打开入口

- [制作源与四分区](../../art_source/scenes/sunny_bloom_retreat/v004/README.md)
- [完整Blender制作源](../../art_source/scenes/sunny_bloom_retreat/v004/sunny_bloom_retreat.blend)
- [游戏比例装配](../../art_source/scenes/sunny_bloom_retreat/v004/export/v001/placement/solar_cabin/solar_cabin_v1.1.blend)
- [导出/优化清单](../../art_source/scenes/sunny_bloom_retreat/v004/export/v001/export_manifest.json)
- [结构化验证](2026-10-25_solar_cabin_v004_verification.json)

## 实际修改

海上结构原有灰色承台及灰石桥墩移除，水泥地坪保持实体厚度；原海下建筑基座不属于该灰承台。后部露台、棚架及原木质固定部分改水泥色，顶部封顶改灰色，前窗玻璃/窗框及实际墙洞共同加宽。去掉全部藤蔓与高大裂叶植物，其他花草仍与建筑分集合。

主体相对上一版均匀1.5倍；前方太阳能房在此之外局部宽度1.12倍、进深1.42倍，以后缘为锚向前延伸。后部上层小屋右侧补1.44米（放大前）宽的实楼板及支撑墙，连续女儿墙封后/右缘，梯子上落脚区清空。保留右侧太阳伞、桌椅、沙发、冷藏箱、花瓶、盆栽、地垫及边缘绳柱，随前伸房体重新排位。左前桥接入口净空。

前平台6根横向整板，酒红色；桥6根横向整板，暖木色。二者独立Blender分区及Godot PackedScene。四分区共46个母版组件、159实例，组件独立源包可打开。色板PNG没有改动；酒红板仅对berry格做有限HSV校正，Blender/Godot分别对应UV方向，保持四材质角色。

## 比例与接入

原v003到当前源1.5倍，Godot保持1.15的导入系数，总1.725倍。主墙宽8.625米，地板Y=2.15米，正面+Z；含花草和桥包围盒约14.516×21.019米，高10.872米。正式稳定solar_cabin.tscn保留，海上包装内部有四个独立子场景；海下基座和绞盘台保持。只定点更新家园区块行走矩形、上岸/泊位/种植与交互位置和岸线，不运行旧全区构建器。

## 验证与备份

源级46包重开、4分区重开、34772面PaletteUV检查通过；原v003和公共色板SHA-256不变。独立优化副本保存重开再导出；348100→346468三角面（约0.47%），四视图固定相机对比确认轮廓和开口保持。46个GLB不内嵌纹理，导入配置embedded_image_handling=0；共用色板Nearest、无损、无mipmap。

本轮运行通过scripts/run_verification.py隔离存档：visual-solar-cabin 104检查0失败，solar-components 46组件独立加载通过，surface的30条航路、click、management、selftest全通过，均exit0。selftest含既有一条预期损坏JSON负向测试错误，未发现非预期错误。真实Metal渲染正/背/顶/上下文截图已核对。没有以源级验证替代运行验证。

本轮开始前额外复制176文件至工程外sea-work/solar_cabin_revision_v004/before，逐文件核对SHA。用户原0.1备份保留，上一版源保留；没有提交Git。未执行长时间性能基准。
''')
print('Registered v004 current sources, 4 semantic modules; changed runtime hashes:',len(updated))

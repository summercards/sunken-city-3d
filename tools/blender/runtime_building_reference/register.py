# -*- coding: utf-8 -*-
"""Register only verified v0.1 references; never refresh unrelated hashes."""
import json,hashlib,os,csv
from pathlib import Path
from collections import Counter
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/runtime_building_reference/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
qa=json.loads((W/'verification.json').read_text());assert qa['passed'] and qa['reopened']==97
cat=json.loads((D/'catalog.json').read_text());index=json.loads((R/'assets/registry/ledger_index.json').read_text());route=index['domains']['scenes'];lp=R/route['ledger'];book=json.loads(lp.read_text())
rows=[]
for e in cat['items']:
    p=R/e['source'];assert sha(p)==e['source_sha256'];mp=p.parent/'asset_manifest.json'
    e['stage']='runtime_reference_verified';e['license']='existing_project_asset_provenance_unchanged';e['runtime_status']='reference_only_no_replacement'
    write(mp,e)
    rows.append(dict(asset_id=e['asset_id'],name=e['name'],domain='scenes',stage=e['stage'],source=e['source'],source_sha256=e['source_sha256'],manifest=str(mp.relative_to(R)),version='0.1',runtime_path=e['runtime_source'],prefab=e['runtime_scene'],license=e['license'],geometry_fingerprint=e.get('geometry_fingerprint'),consumer_features=['SEA-ASSET'],category=e['category'],scope_label=e['scope_label'],boundary_status=e['boundary_status'],note='当前运行资源反向转存的不可变替换参照；不是历史参数化原稿。海面可玩区与远景背景分账标注；未替换游戏。'))
for name,label,category in [('playable_overview','海面可玩区参照总览','playable_reference_assembly'),('background_building_library','六类远景楼体组件总览','background_reference_assembly')]:
    p=D/(name+'_v0.1.blend');aid='SEA-REF-01-'+name.upper().replace('_','-');mp=D/(name+'_manifest.json')
    e=dict(asset_id=aid,name=label,version='0.1',source=str(p.relative_to(R)),source_sha256=sha(p),asset_ledger=route['ledger']+'#'+aid,category=category,stage='runtime_reference_verified',runtime_status='reference_only_no_replacement',linked_sources='catalog.json')
    write(mp,e);rows.append(dict(asset_id=aid,name=label,domain='scenes',stage=e['stage'],source=e['source'],source_sha256=e['source_sha256'],manifest=str(mp.relative_to(R)),version='0.1',runtime_path=None,prefab=None,license='existing_project_asset_provenance_unchanged',geometry_fingerprint=None,consumer_features=['SEA-ASSET'],category=category,scope_label='海面可玩区' if name=='playable_overview' else '远景背景',note='链接独立 Blender 母版的查看装配；不是游戏替换资源。'))
existing={e['asset_id'] for e in book[route['asset_key']]};assert not existing.intersection(e['asset_id'] for e in rows),'Already registered; immutable baseline'
book[route['asset_key']].extend(rows);write(lp,book)
ip=R/'assets/registry/current_source_index.json';derived=json.loads(ip.read_text());derived['sources']=[]
for route2 in index['domains'].values():
    for e in json.loads((R/route2['ledger']).read_text())[route2['asset_key']]:derived['sources'].append({k:e[k] for k in ['asset_id','source','source_sha256','manifest']})
write(ip,derived);write(D/'catalog.json',cat)
with (D/'asset_index.csv').open('w',encoding='utf-8-sig',newline='') as f:
    out=csv.writer(f);out.writerow(['AssetID','名称','范围标注','类型','版本','Blender','运行来源','边界状态'])
    for e in rows:out.writerow([e['asset_id'],e['name'],e['scope_label'],e['category'],e['version'],e['source'],e['runtime_path'],e.get('boundary_status','assembly')])
lines=['# 游戏现状建筑参照库 v0.1','','本库由当前游戏引用的模型和实际环境批次转存，供替换时核对尺寸、位置、原点和构件关系。不是遗失的历史参数化 Blender 原稿。目录 `v001` 对应用户版本 **0.1**。','','## 打开入口','','- [海面五区总览](playable_overview_v0.1.blend)：按当前 Godot 世界坐标装配 17 个现有静态单元。','- [六类远景楼体组件库](background_building_library_v0.1.blend)：六类不同楼体各一个母版。','- [CSV 资产索引](asset_index.csv)：按“海面可玩区 / 远景背景”筛选，含每个独立 Blender 路径。','- [机器目录](catalog.json)；[远景实例清单（无损 gzip）](background_instances.json.gz)。','','## 文件与用途','','17 个海面静态模型单元、6 类远景楼体母版、74 类去重附属构件，共 97 个独立文件；另有 2 个链接总览。远景相同造型只存一个组件，颜色、缩放、旋转、位置单独记在实例清单。附属构件包含墙/基座/窗/叶片等旧网格及背景杂项，并非 74 栋不同楼体。','','海面单元沿用已有 GLB 边界，可能包含多栋结构或邻近陈设；`zone4_far_shore/detail` 是零三角面的线条上下文，不能当作独立建筑。水下独立区域未导出，但海面建筑原本延伸到水下的楼体保留。角色、船只动作、玩法生成物和独立植物系统不属于本次静态建筑快照。','','## 替换约定','','- 单位为米。Godot `(x,y,z)` 到 Blender 为 `(x,-z,y)`；组件保持原运行枢轴，不能一键归零网格或改底部原点。','- 可玩区文件里的根在局部原点；清单同时记录区块内坐标、区块原点和世界坐标。总览已经应用世界坐标。','- v0.1 作为只读参照。制作替换件另存 v0.2 或新组件，不覆盖基线。正式 TSCN 仍拥有游戏装配位置。','- 远景楼体保存 789 处来源摆放，783 处完整匹配；6 处原始楼体因旧区块拆分等原因不完整，实例清单保留实际成员，不能无条件补成整栋。','- 远景全部 249052 个当前启用网格实例都有唯一去向。成员校正矩阵保留原始精度；没有把重复摆放当成新资产。','- 纹理、顶点颜色、法线、尺寸保留；不把旧材质强行换成新色板。Godot 卡通光照、水下染色、风动、后处理不在 Blender 中复刻，预览仅作结构参照。','- Blender 导入器会丢弃旧 GLB 中重复顶点索引的退化三角形，数量逐文件登记；有效三角形与包围盒已核对。','','## 可玩区独立文件','','| 单元 | Blender |','|---|---|']
for e in cat['items']:
    if e['category']=='playable_surface':lines.append(f'| {e["name"]} | [{e["key"]}]({e["relative_blend"]}) |')
lines+=['','## 远景楼体独立组件','','| 类型 | Blender |','|---|---|']
for e in cat['items']:
    if e['category']=='background_building_component':lines.append(f'| {e["name"]} | [{e["key"]}]({e["relative_blend"]}) |')
(D/'README.md').write_text('\n'.join(lines)+'\n')
spec=R/'docs/features/asset/spec.md';s=spec.read_text();rule='| SEA-ASSET-R15 | 将当前游戏海面五个可玩区的静态建筑单元转存为独立 v0.1 Blender 替换参照；远景按重复楼体与附属几何去重为组件母版，位置/旋转/缩放/颜色记为实例，分账明确可玩区与远景背景。保留原运行几何与枢轴，不重着色、不替换正式场景，记录旧自动拆分边界和未复刻的动态效果；独立水下区域不在本轮范围。 |'
assert 'SEA-ASSET-R15' not in s;s=s.replace('\n\n### SEA-ASSET-R12', '\n'+rule+'\n\n### SEA-ASSET-R12');spec.write_text(s)
ledger=R/'docs/features/asset/ledger.md';s=ledger.read_text();line='| SEA-ASSET-R15 | v0.1 参照导出与几何回放验证通过；未执行游戏替换 | 17 个海面单元、6 类远景楼体、74 类附属构件；97 独立文件重开；249052 背景实例唯一归属、精确矩阵回放；源运行文件哈希不变；见本轮参照库记录 |'
s=s.replace('\n\n## 资源与调用入口','\n'+line+'\n\n## 资源与调用入口',1)
s+='\n## 游戏现状建筑 v0.1 替换参照（2026-10-25）\n\n- [参照库索引](../../../art_source/scenes/runtime_building_reference/v001/README.md)，[制作与验证记录](../../development/2026-10-25_runtime_building_reference_v01.md)。\n- 账本逐行标注 `playable_surface`、`background_building_component`、`background_detail_component`；重复远景不按每处摆放生成新母版。\n- 原始 GLB、TSCN、环境烘焙文件保持不变；这是运行现状反向转存，材质/合并边界仍以旧资产为准，未宣称恢复历史参数化源或通过 Godot 视觉替换验收。\n'
ledger.write_text(s)
dev=R/'docs/development/2026-10-25_runtime_building_reference_v01.md'
dev.write_text('# 当前游戏建筑 v0.1 参照库\n\n范围：用户确认海面可玩部分及远景背景，远景去重为不同组件；独立水下区域排除。\n\n交付：`art_source/scenes/runtime_building_reference/v001/README.md`。97 个独立源和 2 个链接总览；99 条新记录按资产总索引路由进入场景账本，未更新旧资产哈希。\n\n验证：97 文件保存重开、有效三角形/包围盒/图片与集合检查通过。249052 个启用背景实例唯一归属、无重复/漏项，精确矩阵回放误差 '+str(qa['max_exact_replay_matrix_error'])+'。已读取的运行输入哈希全部不变。6 类楼体从当前矩阵匹配恢复，783 个完整实例，6 个不完整原始实例保留成员。预览为 Blender 结构查看图，不等于 Godot shader 像素一致。\n\n初步空间切分候选已移至工程外，不作为交付；矩阵行列布局在比对中纠正。首次重开检查发现旧 GLB 退化三角形，按原索引实测确认并单列，不跳过有效三角形校验。恢复脚本首次解析 JS 小数失败已修正。最终导出、打包、重开校验进程退出码见验证 JSON。\n\n未执行游戏运行/导航/碰撞测试：本轮只读转存，没有接入或替换。旧烘焙的可玩区单元仍可能跨建筑边界，替换前须核对；背景附属件按几何与材质角色去重、颜色作为实例参数。\n')
write(R/'docs/development/2026-10-25_runtime_building_reference_v01_verification.json',qa)
print('REGISTERED',len(rows),'records')

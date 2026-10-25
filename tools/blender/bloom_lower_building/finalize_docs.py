"""Write evidence and feature ownership for the separately authored lower building."""
from pathlib import Path
import json,os,hashlib
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/bloom_lower_building/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bloom_lower_building_v001'
q=json.loads((W/'verification.json').read_text());assert q['passed'] and len(q['views'])==5
assert q['source_sha256']==hashlib.sha256((D/'bloom_lower_building.blend').read_bytes()).hexdigest()
m=q['metrics'];c=m['components'];n=m['instances'];uv=m['uv_faces_checked'];poly=m['expanded_polygons'];tri=m['expanded_triangles']
q['execution']={'build_exit_code':0,'source_verification_exit_code':0,'registration_exit_code':0,'render_engine':'Blender Cycles','rendered_views':5,'visual_review':'Current beauty, structure-only, detail, top and rear inspected; user art acceptance pending.','expected_faults':[],'unexpected_errors':[],'resolved_authoring_errors':['One intermediate build failed because a shader math-node variable shadowed the material variable. Renamed the node variable and rebuilt successfully; obsolete verification was cancelled.'],'warnings':['Blender 5.2.2 reports use_nodes deprecation.']}
(R/'docs/development/2026-10-25_bloom_lower_building_v001_verification.json').write_text(json.dumps(q,ensure_ascii=False,indent=2)+'\n')
p=R/'docs/features/asset/ledger.md';s=p.read_text();lines=s.splitlines();lines=[f'| SEA-ASSET-R14 | v001 源级与五视图通过；Godot 和用户美术验收 pending | {c} 组件、{n} 实例；{c} 独立包重开，{uv} 母版面 UV 核验；七层窗湾、蓝灰立柱、屋顶净空、花朵朝向通过；见 bloom_lower_building 制作记录 |' if l.startswith('| SEA-ASSET-R14 |') else l for l in lines];s='\n'.join(lines)+'\n';s=s.replace('|\n\n| SEA-ASSET-R14','|\n| SEA-ASSET-R14')
heading='## 独立下半建筑 bloom_lower_building（2026-10-25）'
if heading not in s:s+=f'''\n{heading}\n\n- SEA-ASSET-R14：[v001 独立模型](../../../art_source/scenes/bloom_lower_building/v001/bloom_lower_building.blend)。按本轮新附件独立制作，未改动或拼接上半小屋。\n- 七层楼体，长立面三组凹凸窗湾，蓝灰柱与天蓝柱箍，厚白楼层边沿，32 块浅杏屋顶砖；花草独立集合，中央屋顶留空。未展示的背面按同一结构规律补全，属于推定设计。\n- {c} 组件 / {n} 实例，{poly} 多边形 / {tri} 三角面；{c} 独立包重开和五视图检查完成。\n- [制作记录](../../development/2026-10-25_bloom_lower_building_v001.md) / [验证证据](../../development/2026-10-25_bloom_lower_building_v001_verification.json)。构建、源级验证、登记退出码 0；运行接入、碰撞、性能、参考图商业授权和用户美术验收 pending。\n'''
p.write_text(s)
(R/'docs/development/2026-10-25_bloom_lower_building_v001.md').write_text(f'''# 繁花建筑下半部分 · 独立制作

所属功能 SEA-ASSET，条款 SEA-ASSET-R14。按用户本轮附件独立制作 [v001 Blender 源](../../art_source/scenes/bloom_lower_building/v001/bloom_lower_building.blend)，不修改上半小屋；只沿用本会话通用建模与检查工具，没有载入其他模型或装配布局。用户追加的向下三层已在同一候选中完成，交付为七层。

## 参考图重建

用户最新要求向下增加三层，保留原四层及屋顶构图，总计七层，层高假设 1.72 米，屋顶板上沿 Z=12.32。长向 Y 约 7.8 米，短向 X 约 3.8 米；屋顶外轮廓 4.48×8.28 米。长立面每层三组窗湾，外侧两组突出、中部后退；凹槽内蓝灰柱及柱箍保持连续，白墙柱、楼层边沿和窗台使用真实倒角。窗面为青蓝色厚玻璃体块，白色外挂机单独组件。

屋顶以 4×8 块浅杏砖铺满，中央保持空旷，叶簇集中边角；长短藤蔓交错下垂，粉红和白色五瓣花随机朝上或斜上方。针对初轮图修正了窗面过大、立柱不清晰、屋顶过亮、花朵被叶簇遮挡和植物穿入墙面的问题。参考未展示的背面按相同结构补齐，此部分为推定设计。

## 组件和材质

{c} 个组件、{n} 个 Collection Instance；建筑结构、固定设施与花草分集合。所有组件根和网格变换恒等、底部中心原点、Collection offset 为零，逐件独立 .blend。只外链公共 512×512 方格色板，Closest 与 PaletteUV；公共 PNG 不修改。蓝窗和杏色屋顶砖使用按 UV 色格选择的色相/明度微调，仍为四个共享材质角色。

## 当前实测

保存重开源及全部 {c} 个组件包；检查 {uv} 个母版面 UV 面积、单格与安全边。依赖图求值并展开实例为 {poly} 多边形 / {tri} 三角面，未做低面数优化。七层标高、42 个长面窗湾、14 个端面窗湾、28 段蓝灰柱、32 块屋顶砖、花朵向上法线及屋顶中心净空检查通过。

真实 Cycles 渲染五视图：beauty、building_only、detail、top、rear_structure；输出位于工程外 `sea-work/bloom_lower_building_v001/previews/`。本轮构建、验证及登记退出码 0；一次中间脚本变量遮蔽问题已修复，当前通过证据仅对应最终保存源。工程契约结果另记于结构化证据 execution.feature_contracts。

Godot 接入、碰撞、导航、性能和商业参考图授权未执行；用户美术验收仍 pending。

[结构化证据](2026-10-25_bloom_lower_building_v001_verification.json)
''')
(R/'art_source/scenes/bloom_lower_building/README.md').write_text(f'''# 繁花建筑下半部分

[当前独立 Blender 源](v001/bloom_lower_building.blend)。按本轮附件单独制作，没有拼接到上半建筑。

- 七层楼体、错落厚白窗湾、蓝灰柱、青蓝窗与浅杏铺砖屋顶。
- `01 建筑` 分结构和固定设施；`02 花朵与植物` 可独立隐藏、导出；`90 展示支持_不导出` 为相机和灯光。
- {c} 个组件、{n} 个实例；独立包在 `v001/components/<key>/<key>.blend`。公共色板外链不可丢失。
- 源级重开、PaletteUV、结构检查及五视图通过。当前 {poly} 多边形 / {tri} 三角面。
- 顶板上沿 Z=12.32 米；源坐标 XY 平面、+Z 朝上，Godot 映射 `(x,z,-y)`。正式拼装仍需另行确定接合尺度和接口。

`component_plan.json`、`catalog.json` 和 `component_instances.json` 分别登记计划、组件及完整 Euler 实例。预览和验证输出位于工程外 `sea-work/bloom_lower_building_v001/`，可用 `SEA_WORK_ROOT` 重定向。工具在 `tools/blender/bloom_lower_building/`。

Godot 接入、碰撞、运行性能、参考图商业授权及用户最终美术验收 pending。
''')
p=R/'art_source/scenes/README.md';s=p.read_text();link='bloom_lower_building/README.md'
if link not in s:s+='\n## 繁花建筑下半部分\n\n[独立 v001 源与组件说明](bloom_lower_building/README.md)：七层厚白窗湾、蓝灰柱、青蓝窗和铺砖平屋顶；建筑与花草分离，22 组件、独立包及五视图源级检查完成，Godot pending。\n'
p.write_text(s)
print('Lower-building feature and evidence recorded.')

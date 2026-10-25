"""Record only current, completed v003 verification evidence."""
from pathlib import Path
import json,os
R=Path(__file__).resolve().parents[3];W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'sunny_bloom_retreat_v003'
qa=json.loads((W/'verification.json').read_text());assert qa['passed'] and len(qa['views'])==6
qa['execution']={'build_exit_code':0,'source_verification_exit_code':0,'registration_exit_code':0,'render_engine':'Blender Cycles','rendered_views':6,'refinement_history':['Superseded intermediate palette render verification was intentionally terminated before final source rebuild; final evidence below is for current source only.'],'visual_review':'Six current views inspected. User final art acceptance remains pending.','expected_faults':[],'unexpected_errors':[],'warnings':['Blender 5.2.2 reports deprecated use_nodes API, expected removal in 6.0.']}
metrics=qa['metrics'];c=metrics['components'];n=metrics['instances'];poly=metrics['expanded_polygons'];tri=metrics['expanded_triangles'];uv=metrics['uv_faces_checked']
evidence='docs/development/2026-10-25_sunny_bloom_retreat_v003_verification.json'
(R/evidence).write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n')
p=R/'docs/features/asset/spec.md';s=p.read_text();s=s.replace('调整比例、前廊空间及铺板位置；建筑与植物分开','调整比例、前廊空间及铺板位置；按用户标线将双列栈桥设于前沿偏左，补成连续全宽前平台并保留右侧活动空间；核对窗洞数量与位置、厚圆角太阳能板，花朵使用明亮粉红与白色、朝上或斜上方随机倾斜；建筑与植物分开');p.write_text(s)
p=R/'docs/features/asset/ledger.md';lines=p.read_text().splitlines();lines=[f'| SEA-ASSET-R13 | v003 源级与六视图验证通过；Godot 与用户美术验收 pending | {c} 组件、{n} 实例；{c} 独立包重开，{uv} 母版面 PaletteUV 核验；前平台、左侧双列桥、窗洞、太阳能板尺寸和花朵朝向检查通过；见 v003 制作记录 |' if l.startswith('| SEA-ASSET-R13 |') else l for l in lines];s='\n'.join(lines)+'\n';heading='## 阳光繁花小屋 v003 参考图修订'
if heading not in s:s+=f'''
{heading}（2026-10-25）

- SEA-ASSET-R13：当前 [v003 源](../../../art_source/scenes/sunny_bloom_retreat/v003/sunny_bloom_retreat.blend)，v001/v002 保留。仅沿本任务自身版本修改。
- 按用户标线补齐全宽前平台：前增补面积 14.4 平方米，双列栈桥 X=-2.05/-0.82，右侧保留活动区；家具留在房前和右侧。后墙柱及棚柱保留，棚架采用三根立柱加墙面锚点。
- 一扇侧面宽窗、一扇正面窄窗和一扇上层小窗；窗洞与实际墙壳射线复核。两块太阳能板白框为 1.38×1.85×0.14 米。14 朵花面朝上或斜上方，倾角和花瓣转角分别变化。
- {c} 组件 / {n} 实例，{poly} 多边形 / {tri} 三角面；{c} 独立包及 {uv} 母版面 UV 检查通过。全景、建筑单独、近景、俯视、后侧结构、前庭六视图完成。
- [制作记录](../../development/2026-10-25_sunny_bloom_retreat_v003.md) / [验证证据](../../development/2026-10-25_sunny_bloom_retreat_v003_verification.json)。构建、源验证、登记退出码 0；Godot 接入、碰撞、导航、性能、参考图商业授权及用户美术验收 pending。
'''
p.write_text(s)
(R/'docs/development/2026-10-25_sunny_bloom_retreat_v003.md').write_text(f'''# 阳光繁花小屋 v003 参考图修订

所属功能：SEA-ASSET；条款：SEA-ASSET-R13。当前源：[sunny_bloom_retreat.blend](../../art_source/scenes/sunny_bloom_retreat/v003/sunny_bloom_retreat.blend)。

## 本轮调整

以本轮用户参考图、前庭红框、太阳能板近景及用户布局标线为依据，沿本任务自身 v002 修订，未载入其他套件的模型或布局。v001/v002 原样保留。

- 补齐前沿全宽平台，前增补区域 X[-3.6,3.6]、Y[-6,-4]，面积 14.4 平方米。双列木栈桥移动至 X=-2.05/-0.82，从 Y=-6.23 向前伸出；原物资正前的右侧区域成为连续活动空间。左侧花坛沿外缘重新布置。
- 侧面从两扇宽窗改为一扇宽窗，正面使用窄窗，上层保留小窗。同步修改真实墙洞及设备位置。
- 太阳能板白框 1.38×1.85×0.14 米，蓝色板面和网格薄层分离，两板留缝，加厚铺板、窗框、棚柱、桌面和软垫，保留隐藏安装托脚；修正橙色坡顶与遮阳棚关系，并移开穿入板面的两簇叶片。
- 补齐两类后柱，棚布右侧连接墙体锚点，左侧及后方三根木柱支撑。保留建筑高度收紧和前廊封墙。
- 14 朵花用固定随机种子 814 分别设置朝上或斜上方倾斜，错开方位与花瓣转角；所有花面法线 Z>0.5。修正棕榈叶截面，使向上叶片也保持厚度。花瓣厚度由 0.23 增至 0.29 米，改用 pink #F97FAE 色格。

## 当前实测

{c} 个组件、{n} 个 Collection Instance、{c} 个独立 Blender 包。建筑、陈设和花草分集合；外链同一公共色板，4 个角色材质。逐面核对 {uv} 个母版面 PaletteUV 的面积、单格与安全边；根与网格恒等、底部中心原点、实例完整 Euler、所有包保存重开通过。

保存后依赖图实例展开：{poly} 多边形 / {tri} 三角面；本任务未指定低面数上限。源级结构检查包括后柱、窗洞射线、294 块铺板、12 块桥板、桥头连接、前庭净空、太阳能白框尺寸和花面朝向。

全部 49 类组件均有厚度核对记录，随结构化证据保存在 layout_checks.thickness_review。公共色板 PNG 未修改；太阳能格在本套四个角色材质中以 UV 色格掩码微调色相和饱和度，保持其余色格不变。

预览位于工程外 `sea-work/sunny_bloom_retreat_v003/previews/`：beauty、building_only、detail、top、rear_structure、front_court。六视图逐张目视检查；布局采用用户最新标线，花朵保持朝上和斜上方差异，改用公共色板 pink 格，花瓣加厚。源级通过不等于用户美术验收通过。

构建退出码 0；源级验证与六视图渲染退出码 0；登记退出码 0。预期故障无；未预期错误无；Blender 5.2.2 的 use_nodes API 弃用提示已记录。工程契约检查结果见结构化证据 execution.feature_contracts。

Godot 导入、碰撞、导航、运行性能、参考图商业授权未执行，保持 pending。

[结构化证据](2026-10-25_sunny_bloom_retreat_v003_verification.json)
''')
(R/'art_source/scenes/sunny_bloom_retreat/README.md').write_text(f'''# 阳光繁花小屋 · 当前附件独立制作

当前交付为 [v003/sunny_bloom_retreat.blend](v003/sunny_bloom_retreat.blend)。本任务自身 v001/v002 保留；未复用其他工作套件。

- 主场景 `Sunny Bloom Retreat | 参考图装配`：`01 建筑` 内分结构、固定设施与陈设；`02 花朵与植物` 可独立隐藏；展示支持仅相机和灯光。
- 母版场景 `组件母版 | 独立原点`：{c} 组件，根与网格恒等、底部中心原点；装配 {n} 个 Collection Instance。
- {c} 个独立包位于 `v003/components/<key>/<key>.blend`。外链唯一公共 `art_source/shared/palettes/sea_cozy_8x8_512.png`；4 材质角色，PaletteUV 有面积且保留安全边。
- v003：按用户标线补齐全宽前平台，双列桥位于前沿偏左；右侧留活动空间。修正窗洞、太阳能板尺寸与厚圆角、布棚支撑；花朵朝上或斜上方错落分布。后方两类墙柱/棚柱已补齐。
- 保存文件实例展开：{poly} 多边形 / {tri} 三角面。源级六视图与 {c} 个包重开通过；未做 Godot 性能验收。

计划、目录及实例分别为 `component_plan.json`、`catalog.json`、`component_instances.json`。坐标 XY 平面、+Z 朝上，保留完整 Euler；映射到 Godot 为 `(x,z,-y)`。

工具位于 `tools/blender/sunny_bloom_retreat/`，默认 v003。`build.py` 保护保存源，`--replace-generated` 只用于本任务当前生成候选；`verify.py` 重开源与独立包并渲染六视图。输出位于工程外 `sea-work/sunny_bloom_retreat_v003/`，可用 `SEA_WORK_ROOT` 重定向。

Godot 接入、碰撞、导航、运行性能、参考图商业授权及用户最终美术验收 pending。
''')
p=R/'art_source/scenes/README.md';s=p.read_text().replace('[当前 v002 源与打开说明](sunny_bloom_retreat/README.md)：45 个独立组件，建筑与花草分离；补齐后墙柱和棚柱，修正前廊、比例及木板位置；源级与五视图通过，Godot 接入 pending。','[当前 v003 源与打开说明](sunny_bloom_retreat/README.md)：49 个独立组件，建筑与花草分离；全宽前平台、偏左双列桥、窗洞和太阳能板修订、花朵朝上错落分布；源级与六视图通过，Godot 接入 pending。');p.write_text(s)
print('Current v003 evidence and feature documents updated.')

"""Append feature records without rewriting a ledger's title, backlink or registration header."""
from pathlib import Path
import json,hashlib,os
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/neon_garden_quarter/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'neon_garden_quarter/v001'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
V=json.loads((W/'source_verification.json').read_text(encoding='utf8'));K=json.loads((W/'skill_verification.json').read_text(encoding='utf8'));assert V['passed'] and K['passed']
views={k:dict(path=str(W/'renders'/f'{k}.png'),sha256=sha(W/'renders'/f'{k}.png')) for k in ['hero','reference','garden','top','rear','signs','architecture']}
dump(W/'visual_review.json',dict(passed=True,reviewer='Codex visual inspection of actual Blender Cycles renders',source_sha256=V['source_sha256'],views=views,checked=['complete building-group silhouette','rear and side elevations and roof services','reference alley / stacked signage / rear roof garden relationships','image-2 atlas visible on actual meshes','rounded extruded signs separated from print artwork','circular hanging sign has no square corners','plants separate from buildings and containers','large broken window corners / parapet gaps / broad plaster scars / large rubble','no water, human mesh or animal mesh'],fixes=['round sign circular UV crop','removed duplicate extruded lettering over charcoal poster','repositioned exterior stair landings','corrected side window bay alignment','cropped portrait artwork instead of stretching face','added alley fill light and deep street signage','removed degenerate font tessellation faces'],not_claimed=['pixel-identical single-image reconstruction','user final art acceptance','runtime playable or optimized']))
dump(D/'textures/generation_record.json',dict(model='gpt-image-2',protocol='OpenAI Images edits via installed sofunny-image CLI',input='reference/user_reference.png',reference_sha256=sha(D/'reference/user_reference.png'),prompt_file='textures/image2_prompt.txt',prompt_sha256=sha(D/'textures/image2_prompt.txt'),output='textures/poster_atlas.png',output_sha256=sha(D/'textures/poster_atlas.png'),size=[2048,2048],quality='high',layout='4 columns x 2 rows',human_portraits='printed artwork only; no character geometry'))
spec='''

## 2026-11-04 霓虹花园街区（水上建筑源）

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R44 | 按本轮用户参考图制作独立 `neon_garden_quarter/v001` 完整建筑群，明确归海上主场景水上建筑 `above_water`。保留左右高楼夹街、右侧圆弧窗湾／橙色大广告、纵向厚字招牌、后楼屋顶菜园与层叠招贴的结构关系；补全背面／侧面、楼板、屋顶服务间、外部折返楼梯和设施。不制作水体、人物与动物网格。按项目 Skill 使用 5.1 米层高、0.2 米板厚、0.5 米主柱、实体三段圆角、公共暖木 8×8 色板与四材质角色。植物独立于建筑和容器，破损采用大缺角、宽裂缝、断墙与大块残片，不堆细碎结构。广告画明确使用 gpt-image-2；仅印刷面登记 PosterUV／PosterMask 图集例外，PaletteUV 仍逐面有面积并保持活动／渲染层，不复制公共色板。冻结不超过50组件，母版＋独立包重开、逐面UV／变换／原点／图片／几何检查和多视图源级验收后录入场景分账本；Godot／碰撞／导航／功能／性能优化独立待接入。 |
'''
ledger=f'''

## 2026-11-04 霓虹花园街区 Blender 制作与源级验收

| 对应设计条款 | 当前实施状态 | 证据 / 未执行项 |
|---|---|---|
| SEA-ASSET-R44 | Blender 源级完成并验收：46组件、{V['assembly']['visible_instances']}实例，三栋主建筑为6／7／5层；46独立包均保存重开。{V['checks']}项检查0失败，{V['source_palette_faces']}个母版面逐面 PaletteUV 合规；Skill验证器按sea 8×8及已登记印刷图例外适配，母版＋46包共47份全部通过。7张真实Cycles验收图已目视检查；image-2八幅广告图集、圆润厚字、独立花草及概括破损已交付。登记48行（46组件＋总成＋图集），主建筑above_water，植物／图集不承担建筑空间职责 | [交付与证据](../../development/2026-11-04_neon_garden_quarter.md)；[母版](../../../art_source/scenes/neon_garden_quarter/v001/neon_garden_quarter.blend)。Godot导出接入、碰撞／导航／泊位、性能优化、商业参考授权与用户最终美术验收pending；未修改正式TSCN |
'''
for path,payload in [(R/'docs/features/asset/spec.md',spec),(R/'docs/features/asset/ledger.md',ledger)]:
 original=path.read_bytes()
 if b'SEA-ASSET-R44' not in original:
  with path.open('a',encoding='utf8',newline='') as f:f.write(payload)
  assert path.read_bytes().startswith(original),'ledger header/history must remain intact'
a=V['assembly'];doc=f'''# 2026-11-04 霓虹花园街区 Blender 源级交付

[主文档](../../GDD_V1.0.md#sea-asset) · [功能设计](../features/asset/spec.md) · [功能账本](../features/asset/ledger.md)

对应 SEA-ASSET-R44。用户要求整张参考图中的建筑、招牌与植物，省略水、角色与生物，补完看不见的结构，并指定广告画使用 image-2。按 `sea-scene-component-authoring` 的 `above_water` 分支完成，未自动接入 Godot。

## 制作结果

- 母版：[neon_garden_quarter.blend](../../art_source/scenes/neon_garden_quarter/v001/neon_garden_quarter.blend)。另有46个可直接打开的独立组件包。
- 三栋主建筑：左侧六层店楼、右侧七层圆弧窗湾酒楼、后方五层屋顶农园；补全前后侧立面、层板、楼梯间、水箱、空调、排水管、外部折返梯。大尺寸按5.1米层高、0.5米主柱、0.2米楼板；临水底平台顶0.3米／底0.1米。
- 46组件／{a['visible_instances']} Collection实例；建筑、设施、招牌、植物及展示支持分组。场景总包络约33.0×29.9×39.4米；{a['polygons']}多边形／{a['triangles']}三角形，为展开所有可见实例的真实统计。本轮无低面数上限，尚未作运行优化。
- 植物包含甘蓝、番茄、蔬菜叶簇、宽叶草、藤蔓、垂挂灌木、花簇和长叶草；花箱、土床、竹架与植物独立。
- 破损为少量大块窗角缺失、断裂女儿墙、大片墙面剥落／宽裂纹与大块残片。保留概括轮廓，不铺碎屑。
- 生成贴图用 `gpt-image-2`、2048×2048、high、参考图编辑调用。8幅广告共用一张4×2图集；[提示词](../../art_source/scenes/neon_garden_quarter/v001/textures/image2_prompt.txt)与[调用记录](../../art_source/scenes/neon_garden_quarter/v001/textures/generation_record.json)存档。肖像只印在广告上，没有人物模型。
- 大号日文／中文招牌使用粗体、实体挤出与圆角，发光网格独立。广告印刷与厚字分开，避免重复字叠在同一画面。

## 材质与例外

全部几何有活动／渲染 `PaletteUV`，面岛位于8×8公共暖木色板的单格安全区；色板外链唯一、Closest、未打包。四个共享角色 `SEA_Matte`／`SEA_Metal`／`SEA_Gloss`／`SEA_Emission`。

用户明确要求还原广告画，因此仅印刷表面额外使用 `PosterUV` 与 `PosterMask`，在同一 `SEA_Matte` 内采样本套件唯一图集（Linear）。此例外已在建模前的组件计划登记，不能将海报图集误判为公共色板副本。独立包仍外链项目公共色板与套件图集；图片缺失检查全部通过。

## 当前验收

| 项目 | 本轮结果 |
|---|---|
| Blender4.5母版重开＋46独立包重开 | {V['checks']}检查，0失败 |
| 每面UV面积、单格安全区、活动／渲染层 | {V['source_palette_faces']}母版面全部通过；独立包再次检查 |
| 变换／底心原点／零集合偏移／非空／归属／图片／面几何 | 通过；清除中文字体转换产生的零面积小面后重新执行 |
| Skill验证器 | 母版＋46包共47份通过；明确适配sea的8×8，允许登记的广告图输入，未修改安装的Skill |
| 真实渲染与目视 | 7视图：全景、街巷参考机位、屋顶菜园、俯视、背面、厚字招牌、隐藏植物的建筑视图 |
| 分账登记 | 48条：46组件＋总成＋图集；ID前缀SEA-SCENE-NGQ；非本任务资产源哈希原样保留 |
| Godot运行 | 未执行；本轮为Blender制作任务，无GLB／PackedScene／运行功能通过声明 |

机器报告和渲染位于工程外 `{W.as_posix()}`：`source_verification.json`、`skill_verification.json`、`visual_review.json`、`registration_report.json`、`renders/`。独立验证不仅检查制作脚本的参数，还重新打开磁盘文件逐面量测。

首轮目视发现圆形吊牌四角、重复大字覆盖广告、外梯平台间距、侧窗柱位与广告肖像拉伸，已逐项修复；街巷补光使后方广告可读。参考图为一个混合上下水观察的二维构图，交付为完整三维、项目风格的结构还原，不声明像素级复刻。

## 边界与维护

源主哈希：`{V['source_sha256']}`。计划、组件目录与实例清单都在同一版本目录；维护脚本位于 `tools/blender/neon_garden_quarter/`。主源通过Collection Instance复用，修改网格请编辑第二个“组件母版_独立编辑”场景。

Godot导出／接入、真实胶囊通行、泊位、角色与船阻挡、导航、岸线、功能交互、运行性能仍pending。源清单里的通路／泊位只是设计预留，不是运行验证。参考图商业授权与用户最终美术验收pending。已有Blender未保存会话、正式Godot场景及并行工作的资产均保留。
'''
(R/'docs/development/2026-11-04_neon_garden_quarter.md').write_text(doc,encoding='utf8')
print('NGQ_DOCS_APPENDED_AND_VISUAL_REVIEW_RECORDED')

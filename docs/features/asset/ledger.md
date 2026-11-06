# SEA-ASSET · 美术组件生产与登记 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-asset) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-ASSET",
  "status": "partial",
  "owner": "制作源负责人 / 各域资产账本",
  "code_paths": [
    "art_source",
    "assets/registry",
    "tools/blender"
  ],
  "verification": [
    "water-layer",
    "submerged-neighborhood",
    "visual-submerged-neighborhood",
    "reference-skiff",
    "visual-reference-skiff",
    "structure",
    "decorations",
    "visual-decorations",
    "visual-plot-shipping",
    "visual-home-lighting",
    "visual-kit-uv",
    "building-kit",
    "floating-shop",
    "sea-supply",
    "fishery-environment",
    "visual-fishery-environment"
  ]
}
```

## 2026-10-28 黄白木船与双桨

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-ASSET-R28 | 12组件/44实例、12独立包、公共PaletteUV及四视图通过；已接入正式Boat，参考商业权属pending | 源级46589检查、11697面/22888三角面，优化导出22695三角面；新船专项、实景、灯光及装饰回归见[交付记录](../../development/2026-10-28_reference_skiff.md)。全世界surface/selftest有1+4项既有失败，新旧Boat单文件对照一致，不记为全通过。 |

## 2026-11-03 顶层牧场接入（SEA-ASSET-R41 · v004 运行侧）

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-ASSET-R41 · v004 运行接入 | v004 已按 02b 完成「优化另存 → 独立重开 → 逐组件导出」，45 个组件各自一份稳定 GLB（`godot/assets/models/facilities/rooftop_ranch/components/<key>/<key>.glb`），持久优化件在 `art_source/scenes/ocean_rooftop_farm/v004/export/v004/*_optimized.blend`，源 Blend／组件包／公共色板哈希前后不变。Godot 侧建 45 个稳定组件 PackedScene 与总成 `godot/scenes/facilities/rooftop_ranch.tscn`，以「顶层牧场」接入 `main.tscn`。**本轮修掉一个真实缺陷**：组件 GLB 自带 StandardMaterial3D，若不在 `.tscn` 里序列化 `surface_material_override`，游戏内整栋楼是纯白无材质（首次实拍已复现）。现按 GLB 语义名（`SEA_Matte`／`SEA_Metal`／`SEA_Gloss`／`SEA_Emission`）逐 surface 写入公共色板材质覆盖，实拍确认混凝土灰、深色哑光消防梯、蓝色窗、绿草皮均正确。三角面优化 10498 → 10492（仅 `stair_landing_open` 去掉 1 个零面积面，其余零变化）。 | 导出清单 `art_source/scenes/ocean_rooftop_farm/v004/export/v004/export_manifest.json`；导入材质绑定 `godot/tools/rooftop_ranch_palette_import.gd`；实拍 `godot/outputs/rooftop_ranch_{sea,boarding,roof}.png`。**pending**：资产登记表（`register_v004.py` 尚未执行，账本行仍按上一节 pending 口径）、商业授权、用户最终美术验收。 |

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-ASSET-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-ASSET-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-ASSET-R03 | 部分实现；太阳能花屋按源级验收和运行接入分别登记 | 本套源验证通过；Godot 接入和参考图授权仍 pending，见本次制作记录 |
| SEA-ASSET-R04 | 本批完成，存量不追溯改写 | 当前风格源 v003：36 种组件、255 个 Collection Instance；建筑和花草分别归类，36 个独立包重开验证；v001/v002 保留 |
| SEA-ASSET-R05 | 本批完成 | 64 色公共 PNG、JSON 色名表；共享四材质角色，逐面 UV 非零面积、同格安全区验证 |
| SEA-ASSET-R06 | 本批完成源级验证，运行期 pending | 当前 v003 保留 v001 建筑真实倒角，重做圆润花叶；保存重开及四视图验证，见 v003 制作记录 |
| SEA-ASSET-R07 | 本批完成 | 工程内 .agents/skills/sea-scene-component-authoring/SKILL.md；路由场景分账本、登记 38 个新 AssetID |
| SEA-ASSET-R08 | 历史 v002 源级完成；当前 v003 不满足该预算 | 保存文件依赖图实测：整场景 1947 多边形 / 2999 三角面；平台 8.6×8.2 米，前方 6.85×1.20 米净空无陈设侵入 |
| SEA-ASSET-R09 | v003 风格源已制作，验证证据见修订记录 | 基于 v001 实际文件派生；31 项几何与摆位锁定，重做 5 项花叶组件；公共 PNG 与原版源哈希不变 |
| SEA-ASSET-R10 | 本批源级验证通过；Godot pending | 30 组件、142 Collection Instance；30 独立包重开，17690 母版面 UV 核验；见本轮制作记录 |
| SEA-ASSET-R11 | v004 源级验证通过；Godot 与商业授权 pending | 48 组件、340 Collection Instance；48 独立包重开，14629 母版面 UV 核验；整场景 208140 三角面；见 v004 制作记录 |
| SEA-ASSET-R12 | 本批源级完成；Godot 接入 pending | 38 组件、267 实例、38 独立包；14964 母版面 UV 核验；整场景 58966 多边形 / 108572 三角面；见热带花屋制作记录 |
| SEA-ASSET-R13 | v003 源级与六视图验证通过；Godot 与用户美术验收 pending | 49 组件、592 实例；49 独立包重开，46275 母版面 PaletteUV 核验；前平台、左侧双列桥、窗洞、太阳能板尺寸和花朵朝向检查通过；见 v003 制作记录 |
| SEA-ASSET-R14 | v001 源级与五视图通过；Godot 和用户美术验收 pending | 22 组件、414 实例；22 独立包重开，26416 母版面 UV 核验；七层窗湾、蓝灰立柱、屋顶净空、花朵朝向通过；见 bloom_lower_building 制作记录 |
| SEA-ASSET-R15 | v0.1 参照导出与几何回放验证通过；未执行游戏替换 | 17 个海面单元、6 类远景楼体、74 类附属构件；97 独立文件重开；249052 背景实例唯一归属、精确矩阵回放；源运行文件哈希不变；见本轮参照库记录 |
| SEA-ASSET-R16 | v0.2 中文设施归类与命名统一完成，源级验证通过 | 97 部件、5 设施总成、2 总览重开；中文 name、英文 asset_key/文件名逐条核对；海上/海下几何面积和包围盒验证；既有源和运行输入哈希保持；见本轮归类记录 |
| SEA-ASSET-R17 | v0.3 源级拆分完成并验证，未改游戏运行资源 | 绞盘打捞台新增独立设施 AssetID；木屋港湾部件/木屋总成/六设施总览更新，4 源重开与集合检查；拆分几何覆盖保持，见本轮拆分记录 |
| SEA-ASSET-R18 | 已备份并正式接入，专项与真实渲染通过 | 0.1 快照逐文件哈希核对；49 独立组件与优化源，703920→688342 三角面；529 实机几何检查、30 条航路、种植点/点击/经营/自检通过；见太阳能木屋接入记录 |
| SEA-ASSET-R19 | v004 源级、正式接入与真实渲染通过 | 46组件159实例，4独立分区文件；34772面UV核验，46独立包重开；104实机检查及46组件独立加载通过，surface/click/management/selftest本轮通过；见v004记录 |
| SEA-ASSET-R20 | v005 源级、接入与真实渲染通过 | 47组件163实例、4分区重开；37486面UV核验；112实景检查、259组件检查、30航路503检查、537自检通过；见v005记录 |
| SEA-ASSET-R21 | v006上下部分均正式接入，实景与专项通过 | 海上45组件161实例；海下22组件导出、19组件298实例使用；67组件独立加载、468实景检查、30航路503检查和537自检通过；见v006记录 |
| SEA-ASSET-R22 | v007源与模型专项接入通过；综合自检2项未通过 | 49组件160实例，71组件415独立检查、472实景检查和30航路503检查通过；原输入/旧色板保护，见[v007记录](../../development/2026-10-26_solar_cabin_v007.md) |
| SEA-ASSET-R23 | 已建立分类路由；未核验资产保持 pending | ledger_index.json 与7个独立类型分账本；[框架交付记录](../../development/2026-10-27_modular_framework.md) |
| SEA-ASSET-R24 | 运行组件拆分及账本完成；旧建筑合并网格内未辨识的陈设仍标待语义拆分 | 独立建筑包装13个、原植物组件42种、太阳房活动家具25实例、荷叶24实例、飞鸟/鱼群/鲸组件；见本轮记录 |
| SEA-ASSET-R25 | 基座放大与落水贴合已接入；专项通过，跨功能失败项经基线对照归为既有 | 海下白色基座顶板 11.20×12.42 → 16.24×17.77（X1.450/Z1.431），顶面四边各超出上层建筑0.40；平台下移0.30、板底水面+0.04、基座顶面与板底齐平；704实景检查与装饰/组件/最小循环检查通过，[记录](../../development/2026-10-27_solar_cabin_base_scale_and_waterline.md) |
| SEA-ASSET-R41 | 当前目标为 v003，48组件/895实例/48独立包；稳定 `SEA-SCENE-ORF2-*` ID 沿用，主源为 `art_source/scenes/ocean_rooftop_farm/v003/ocean_rooftop_farm_v003.blend`；v002 源与哈希基线不改；源验证文档状态先保持 pending，Godot/碰撞/导航/授权/最终美术验收仍 pending | 已通过 MCP 完成并保存：厚外挑无草水泥边台49.6×33.6×0.65米、深凹窗/宽主柱/三种破损窗、坡顶高差、不均苔藓；粗杆0.18–0.2米，金属 metallic 0.15/roughness 0.82；消防梯仅45–60米上三层6段及下挂残梯，屋顶入口删除共面桥面并以59.97米承接板边对边连接。登记门禁要求 `source_verification.json` 与 `skill_verification.json` 均 passed 且主源哈希匹配；脚本为 `tools/blender/ocean_rooftop_farm/register_v003.py`。 |

## 资源与调用入口

2026-10-30 SEA-ASSET-R02/R03/R23：`SEA-CHAR-RECEIVE-001`登记至索引解析的characters分账本，源为本项目已有节点动画体系内的`item_receive.gd`，包含原创抬举收包动作与挎包；运行专项与真实渲染通过，旧角色整体来源登记仍pending，作物源级未执行项保留。仅登记本次新源哈希，不刷新未知历史哈希。[交付与证据](../../development/2026-10-30_harvest_receive_animation.md)。

2026-10-28：SEA-ASSET-R01/R02/R03新增原创卡通十字波纹`SEA-VFX-WATER-CROSS-RIPPLE-001`，经总索引登记在vfx分账本。矢量/2048px源、512px线性蒙版、运行引用与授权分开记录；[当前制作与验证](../../development/2026-10-28_cartoon_cross_ripple.md)。

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-ASSET-R29 | 六栋独立源/优化/GLB/PackedScene已制作；源级与实景专项验证，参考权属pending | [本轮交付](../../development/2026-10-28_submerged_neighborhood.md)、[材质序列化](../../development/2026-10-29_submerged_buildings_main_placement.md)；逐栋880/784/636/438/496/716三角面，公共色板、逐面UV和六独立包重开通过；优化清理为零减面，未以三角化冒充减面；六栋调色板材质已从运行期脚本改为PackedScene内序列化覆盖，并由专项断言盯着；阳光房57个组件的同类运行期上色尚未序列化 |

- [art_source](../../../art_source)
- [assets/registry](../../../assets/registry)
- [tools/blender](../../../tools/blender)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

规划功能尚无正式接口实现。

## 验证记录

入口：`python3 scripts/check_feature_contracts.py`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 尚无本功能独立运行验收，不将结构通过视为玩法完成。

## 遗留与下一步

场景分账本现567行；两类职责登记已完成，运行接入、授权、新职责全子树验收和旧检查覆盖漏洞仍待完成。资产行数不代表独立建筑数量。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 太阳能花屋源级交付（2026-10-23）

- [场景目录与打开方法](../../../art_source/scenes/README.md)；[组件计划](../../../art_source/scenes/solar_flower_house/v001/component_plan.json)；[公共色板](../../../art_source/shared/palettes/sea_cozy_8x8_512.png)。
- AssetID 前缀 `SEA-SCENE-SOLAR-`，装配 `SEA-SCENE-SOLAR-FLOWER-HOUSE`，色板 `SEA-PALETTE-COZY-64`。38 条新记录通过总索引路由到场景分账本；旧 43 条源行不改。
- [本次制作记录](../../development/2026-10-23_solar_flower_house.md)与[结构化源级验证证据](../../development/2026-10-23_solar_flower_house_verification.json)。
- 当前未接入 Godot，没有替换游戏建筑、碰撞、导航或正式 TSCN。参考图商业授权待核验。

- 2026-10-24：本批 Blender 源验证与 Skill 校验通过（退出码 0）；工程契约同步及检查退出码 1，唯一错误为任务外 `godot/assets/materials/water.tres` 的既有运行哈希漂移。未修改该哈希；SEA-ASSET 主文档状态仍为“部分实现”。

## 太阳能花屋 v002 简约低面数修订（2026-10-24）

- 用户追加要求：花叶更饱满，风格更简约，所有面数 <=3000，木平台更大。按更严格的全场景三角面口径执行。
- v002 低面数源：[v002 母版](../../../art_source/scenes/solar_flower_house/v002/solar_flower_house.blend)，[实测预算](../../../art_source/scenes/solar_flower_house/v002/geometry_budget.json)。总实例展开后 1947 多边形、2999 三角面；母版单算为 822 多边形，不用该较小数字宣称整场景预算。
- 平台由约 7.4×6.6 米扩大到 8.6×8.2 米（名义面积增加约 44%），保持房屋尺度；前方连续净空检查通过。仅视觉源净空，尚未制作 Godot 碰撞或导航。
- v002 套件引用的 28 组件和装配沿用原 AssetID 更新到 v002，previous_sources 保留 v001 路径和哈希；8 个未复用旧组件仍保留登记。公共色板不改。
- [修订记录](../../development/2026-10-24_solar_flower_house_lowpoly.md)与[验证证据](../../development/2026-10-24_solar_flower_house_lowpoly_verification.json)。

- v002 本轮验证：Blender 源、实例展开预算、平台净空、独立包、UV 与真实渲染通过（退出码 0）；工程契约同步/检查仍仅因既有 water.tres 哈希漂移退出 1，未覆盖任务外记录。

## 太阳能花屋 v003 第一版风格修订（2026-10-24）

- 最新要求是先在第一版上调整色彩和花朵，参照用户新提供的游戏截图。直接打开 v001 派生 v003，未从 v002 回拼，也未运行 v001 全屋构建器。
- [当前风格母版](../../../art_source/scenes/solar_flower_house/v003/solar_flower_house.blend)，[范围锁定](../../../art_source/scenes/solar_flower_house/v003/scope_lock.json)，[配色映射](../../../art_source/scenes/solar_flower_house/v003/style_mapping.json)。
- 保留 30 项建筑组件及棕榈的几何和原始摆位；重做叶簇、藤叶、粉花、白花、黄花 5 项组件。米白/浅薄荷墙面、暖橙木色、粉白五瓣花与宽圆叶片，材质改为偏哑光。
- 当前为 36 组件、255 实例的风格源。3000 三角面优化暂缓，v002 的 2999 三角面结果仅属于 v002，不转用作本版验收结论；加大平台也仍保留在 v002。
- [本次修订记录](../../development/2026-10-24_solar_flower_house_style.md)与[验证证据](../../development/2026-10-24_solar_flower_house_style_verification.json)。Godot 接入仍 pending。

- v003 工程契约同步/检查退出 1：任务外 water.tres 哈希漂移，以及 README.md 指向尚缺失的网页目录迁移文档。未更新这些资源哈希或修改其他任务的文档；详细输出见本次验证记录。

## WorkBuddy 技能安装（2026-10-24）

- SEA-ASSET-R07：技能已安装至用户级 ~/.workbuddy/skills/sea-scene-component-authoring，工程镜像位于 .workbuddy/skills/sea-scene-component-authoring。
- 附带原始 8×8 公共色板 PNG、颜色 JSON 和 asset_manifest.json；PNG 哈希与原登记一致，不修改工作色板或资产哈希。
- 同步入口 .workbuddy/tools/sync_sea_scene_skill.py 连跑两次退出 0；逐文件 SHA-256 校验及漂移负向断言通过。详见 docs/development/2026-10-24_workbuddy_scene_skill.md。

## 参考图错层花屋码头（2026-10-24）

- 用户要求按附件完整还原，不接受自行简化和布局偏差；船不制作。首个简化候选已撤出交付，按附件重新制作 `pastel_flower_harbor/v001`。
- [完整 Blender 源](../../../art_source/scenes/pastel_flower_harbor/v001/pastel_flower_harbor.blend)；[本轮制作记录](../../development/2026-10-24_pastel_flower_harbor.md)；[结构化验证记录](../../development/2026-10-24_pastel_flower_harbor_verification.json)。
- 30 组件、142 实例，其中花草实例 67；建筑与花草分离。完整实例求值合计 146514 多边形 / 269760 三角面；当前请求未指定低面数上限。
- `SEA-SCENE-PFH-` 前缀，共 31 条新记录通过总索引路由到场景分账本；公共色板及已有太阳能花屋源不覆盖。源索引从分账本派生。
- 仅 Blender 源级交付；未接入 Godot，碰撞、导航、运行性能与参考图商业使用权 pending。

- 本批最终结果：源级验证及四视图渲染退出 0；工程契约同步/检查退出 1，仅有既有 water.tres 哈希漂移，未修改任务外哈希。参考图还原已目视核对，未声明像素级零偏差或用户美术验收通过。

## 太阳能花屋 v004 按新附件重做（2026-10-24）

- 用户提供新的等距截图要求高还原建模。新附件的层数、体量、栈桥拓扑与渔船都与 v001–v003 不同，故在 `v004/` 独立建版；v001–v003 及其源哈希、v002 的 3000 面结论、公共色板均不修改。
- [v004 母版](../../../art_source/scenes/solar_flower_house/v004/solar_flower_house.blend)；[冻结组件计划](../../../art_source/scenes/solar_flower_house/v004/component_plan.json)（48 项组件、23 族、栏杆族以 `infill` 变体轴拆实心女儿墙与通透栏杆）；[制作记录](../../development/2026-10-24_solar_flower_house_v004.md)与[验证证据](../../development/2026-10-24_solar_flower_house_v004_verification.json)。
- 源级实测：48 组件、340 实例、母版 14629 面，全部逐面 PaletteUV 有面积且落在单格安全区；48 个独立包全部重开通过；整场景展开 116541 多边形 / 208140 三角面。本轮按用户要求以高还原为目标，不设面数上限。
- 未接入 Godot，没有替换游戏建筑、碰撞、导航或正式 TSCN。参考图商业授权与四视图目视美术验收仍 pending；花朵密度、屋檐花带、渔船尺度与栈桩密度与参考图仍有差距，继续打磨项。

## 饱满卡通热带花屋（2026-10-24）

- 按当前附件独立制作 [tropical_flower_house/v001](../../../art_source/scenes/tropical_flower_house/v001/tropical_flower_house.blend)，旧花屋套件与公共色板保持原样。
- 建筑与设施 32 种、花草 6 种，267 个 Collection Instance；38 个独立包全部保存重开，原点、集合偏移、材质与每面 PaletteUV 检查通过。共用 `SEA-PALETTE-COZY-64`，无植物焊接入建筑。
- 保留实体倒角、宽厚叶片、圆瓣花和主要比例；重复铺板降为单段实体倒角，小叶使用较少分段。完整求值场景由中间版本 141076 三角面减少至 108572（约 23.0%），不以母版面数代替场景规模。
- [制作记录](../../development/2026-10-24_tropical_flower_house.md)与[结构化验证](../../development/2026-10-24_tropical_flower_house_verification.json)。全景、近景、俯视及建筑分离图为真实 Blender 渲染；用户最终美术验收未代签。
- 通过总索引登记 `SEA-SCENE-TFH-` 38 组件及 1 条装配记录。Godot 接入、运行性能、碰撞/导航与参考图商业授权 pending。

- 热带花屋最终验证：Blender 三个步骤均退出 0；工程契约同步及检查均退出 0，0 问题。没有用历史测试结果替代当前实测。

## 阳光繁花小屋独立制作与比例修订（2026-10-25）

- SEA-ASSET-R13：[v002 Blender 源](../../../art_source/scenes/sunny_bloom_retreat/v002/sunny_bloom_retreat.blend)，[组件与打开说明](../../../art_source/scenes/sunny_bloom_retreat/README.md)。本次附件独立从零制作，v001 是本任务自身的早期候选，保留不覆盖。
- 用户要求两处后柱都补：完成后侧白墙柱与棚架后柱；建筑竖向收紧 8%，调整前廊侧墙和斜顶封墙、窄木铺板、双列栈桥与入口陈设。
- 45 组件、490 实例；45 独立包重开与 40211 母版面 PaletteUV 校验通过；全景、建筑单独、近景、俯视、后侧结构五视图已渲染并目视核对。实例展开为 352554 多边形 / 662504 三角面，未声明低面数验收通过。
- [制作记录](../../development/2026-10-25_sunny_bloom_retreat.md)与[结构化证据](../../development/2026-10-25_sunny_bloom_retreat_verification.json)。46 条本套 AssetID 记录通过总索引路由登记；其他资产和公共色板哈希不重算。
- Blender 构建、源级验证与登记退出码均为 0；Godot 接入、碰撞、导航、运行性能、商业授权及用户最终美术验收仍 pending。

## 阳光繁花小屋 v003 参考图修订（2026-10-25）

- SEA-ASSET-R13：当前 [v003 源](../../../art_source/scenes/sunny_bloom_retreat/v003/sunny_bloom_retreat.blend)，v001/v002 保留。仅沿本任务自身版本修改。
- 按用户标线补齐全宽前平台：前增补面积 14.4 平方米，双列栈桥 X=-2.05/-0.82，右侧保留活动区；家具留在房前和右侧。后墙柱及棚柱保留，棚架采用三根立柱加墙面锚点。
- 一扇侧面宽窗、一扇正面窄窗和一扇上层小窗；窗洞与实际墙壳射线复核。两块太阳能板白框为 1.38×1.85×0.14 米。14 朵花面朝上或斜上方，倾角和花瓣转角分别变化。
- 49 组件 / 592 实例，374100 多边形 / 703920 三角面；49 独立包及 46275 母版面 UV 检查通过。全景、建筑单独、近景、俯视、后侧结构、前庭六视图完成。
- [制作记录](../../development/2026-10-25_sunny_bloom_retreat_v003.md) / [验证证据](../../development/2026-10-25_sunny_bloom_retreat_v003_verification.json)。构建、源验证、登记退出码 0；Godot 接入、碰撞、导航、性能、参考图商业授权及用户美术验收 pending。

## 独立下半建筑 bloom_lower_building（2026-10-25）

- SEA-ASSET-R14：[v001 独立模型](../../../art_source/scenes/bloom_lower_building/v001/bloom_lower_building.blend)。按本轮新附件独立制作，未改动或拼接上半小屋。
- 七层楼体，长立面三组凹凸窗湾，蓝灰柱与天蓝柱箍，厚白楼层边沿，32 块浅杏屋顶砖；花草独立集合，中央屋顶留空。未展示的背面按同一结构规律补全，属于推定设计。
- 22 组件 / 414 实例，526306 多边形 / 976564 三角面；22 独立包重开和五视图检查完成。
- [制作记录](../../development/2026-10-25_bloom_lower_building_v001.md) / [验证证据](../../development/2026-10-25_bloom_lower_building_v001_verification.json)。构建、源级验证、登记退出码 0；运行接入、碰撞、性能、参考图商业授权和用户美术验收 pending。

## 游戏现状建筑 v0.1 替换参照（2026-10-25）

- [参照库索引](../../../art_source/scenes/runtime_building_reference/v001/README.md)，[制作与验证记录](../../development/2026-10-25_runtime_building_reference_v01.md)。
- 账本逐行标注 `playable_surface`、`background_building_component`、`background_detail_component`；重复远景不按每处摆放生成新母版。
- 原始 GLB、TSCN、环境烘焙文件保持不变；这是运行现状反向转存，材质/合并边界仍以旧资产为准，未宣称恢复历史参数化源或通过 Godot 视觉替换验收。

## 建筑参照库中文归类 v0.2（2026-10-25）

- [中文资产账本](../../../art_source/scenes/runtime_building_reference/v002/资产账本.md)；[打开入口](../../../art_source/scenes/runtime_building_reference/v002/README.md)。
- 五设施分别以“设施名字-海上区域 / 设施名字-海下基座”显示；英文资产名与文件名一致，中文名称与分账本一致。原运行资源路径保持来源追溯，v0.1 仍保留。
- [验证记录](../../development/2026-10-25_runtime_building_reference_v02.md)。

## 绞盘打捞台独立设施 v0.3（2026-10-25）

- [本版入口](../../../art_source/scenes/runtime_building_reference/v003/README.md)；[中文资产账本](../../../art_source/scenes/runtime_building_reference/v003/资产账本.md)。
- 太阳能木屋和绞盘打捞台分别为两个设施，绞盘平台已从木屋港湾部件移除；各自包含海上区域/海下基座。
- [拆分与验证记录](../../development/2026-10-25_runtime_building_reference_v03.md)。

## 太阳能木屋正式接入（2026-10-25）

- [接入与备份说明](../../development/2026-10-25_solar_cabin_integration.md)；[Blender 当前装配](../../../art_source/scenes/sunny_bloom_retreat/v003/export/v001/placement/solar_cabin/solar_cabin_v1.0.blend)。
- 用户指定 sunny_bloom_retreat/v003，海上部分按源比例统一 1.15 倍接入；海下基座及独立绞盘台保留。原源哈希不变，优化文件另存。
- 源级完成状态与本次运行验证证据分开记录，参考图授权状态沿用原登记。

## 太阳能木屋 v004 模型修订（2026-10-25）

- [本轮记录](../../development/2026-10-25_solar_cabin_v004.md)；[当前制作源](../../../art_source/scenes/sunny_bloom_retreat/v004/sunny_bloom_retreat.blend)。
- 新版海上四分区与海下原基座分别管理，右侧太阳伞休闲区保留，桥入口和梯子顶端清空。

## 太阳能木屋 v005（2026-10-25）

- [本轮记录](../../development/2026-10-25_solar_cabin_v005.md)；[当前制作源](../../../art_source/scenes/sunny_bloom_retreat/v005/sunny_bloom_retreat.blend)。
- 承重轴续柱、前低后高；阳光房右移；厚底板、延长桥、边绳和挂胎。旧版及0.1备份保留。

## 太阳能木屋 v006 / 新七层海下基座（2026-10-26）

- [本轮记录](../../development/2026-10-26_solar_cabin_v006.md)；[源与总装入口](../../../art_source/scenes/sunny_bloom_retreat/v006/README.md)。
- 木地板、去帆布、伞区避让、花缩小；海下基座已用新七层楼体替换。SEA-ASSET-R14原制作源保持，接入状态以本记录为准。

## 太阳能木屋v007：用户手改接续（2026-10-26）

[新版源入口](../../../art_source/scenes/sunny_bloom_retreat/v007/README.md)；[交付记录](../../development/2026-10-26_solar_cabin_v007.md)。保留用户布局，木板错落、低饱和配色、绳端连接与基座暖米白已接入。源/组件/实景/航路通过；综合自检535通过2失败单列，不代签全工程通过。

2026-10-27 框架收尾：运行13组专项通过，架构边界0问题；最终契约门禁唯一失败为并行修改 water.tres 的运行哈希漂移，未批量接受。详见[最终门禁记录](../../development/2026-10-27_modular_framework.md#最终静态门禁与并发边界)。

## 2026-10-27 场景组件细分与动物恢复

见[本轮交付与验证记录](../../development/2026-10-27_scene_component_split.md)及[组件分类目录](../../../assets/registry/SCENE_COMPONENTS.md)。运行验证与素材授权分别登记；交互请求端口不代表玩家摆放编辑器已实现。

最终补验：decorations 1589项通过；visual-decorations 1592项通过（包含独立实例、真实鱼群近景和正常上浮环境恢复）。surface 503项/30航线、自检537项通过；静态契约32功能/426源资产/317运行哈希0问题。旧水下网页同机位测试缺基准未执行，单列在本轮记录。

## 2026-10-27 开始画面UI资产

`UI-TITLE-SEA-001` 在 `assets/registry/ledgers/ui.json` 独立登记，使用 `UI-FONT-LXGW975YUAN-SC-700`；源为程序化排字布局，参考图仅作风格依据。新增源索引记录，不批量接受历史哈希漂移。[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

2026-10-27 22:20 继续任务复核：当前开始页与最小循环真实渲染通过；全局契约检查中鱼群、鲸鱼两项源哈希漂移，保留原基线并记为待核验。详见[当前工作区复验](../../development/2026-10-27_minimum_loop_and_title.md#继续任务后的当前工作区复验2220)。

2026-10-27：新增独立木板平台 SEA-FARM-CULTIVATION-DECK 与木框土格 SEA-FARM-SOIL-CELL；复用 SEA-SCENE-SBR-COOLER 固定码头出货交互，原授权 pending 保留。[交付记录](../../development/2026-10-27_plot_shipping_loop.md)。

## 2026-10-28 薄木板与暖木色

| 对应设计条款 | 实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R26 | v008源与正式组件接入，当前专项通过 | [制作与验证](../../development/2026-10-28_thin_cabin_and_dayparts.md)，49组件、160实例；主板0.22米、板顶1.38、板底1.16；色板与旧源分别保留 |

## 2026-10-28 家园箱子与夜灯修复

SEA-ASSET-R02/R03/R24：通过总索引定位场景分账本，只修正SEA-SCENE-SBR-COOLER的运行时实例路径/位置/验证证据；保留源、GLB、AssetID与授权pending，未刷新任何资源哈希。

[交付记录](../../development/2026-10-28_home_lighting_recovery.md)。

## 2026-10-28 绞盘打捞台顶点色回填

| 对应设计条款 | 实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R27 | 已实现；`SEA-REF-FACILITY-SALVAGE-STATION` 运行时 GLB 顶点色回填 18808/18852（99.77%），几何/材质/节点未改 | `visual-salvage` 修前/修后同机位真实渲染对照；`assets/registry/ledgers/scenes.json` 的 `runtime_sha256` 与 `runtime_patch_log` |

来源未变：Blender 源、`source_sha256`、AssetID、授权 pending 全部保留。
运行时哈希只更新这一个文件，未批量刷新。

[本轮记录](../../development/2026-10-28_dock_seed_weather_asset_fix.md)。

## 2026-10-29 通用建造木板

SEA-ASSET-R02/R03：通过ledger_index登记原创程序几何SEA-BUILDING-WOOD-DECK，稳定预制体godot/scenes/buildables/wood_deck.tscn；引用现有SEA-FARM-SOIL-CELL，不改旧木面、美术源与许可。仅更新本轮items.json及新增木板源/场景资源哈希。[交付](../../development/2026-10-28_building_delivery.md)。

## 2026-10-29 作物独立资产域

| 对应设计条款 | 实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R30 | 已实现：`ledgers/crops.json` 建立 crops 域，生菜/番茄/南瓜各一行主记录；12 个阶段 GLB 入运行清单，制作源在 `art_source/crops/<id>/v001` | `structure` 契约检查 + [本轮记录](../../development/2026-10-29_crop_formalization.md) |

授权：三品种为本工程程序化自建，`license` 记 `project_authored_procedural_geometry`，不冒用外部来源。
源级「保存后重开 + 四视图渲染」尚未执行，阶段保持 `runtime_component_verified`，不写成已验收。
本域只新增记录，未刷新任何既有资产哈希。

## 2026-10-29 电线杆与花移出甲板

| 对应设计条款 | 实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R31 | 已实现；实景前后对照、几何边界与属性逐字节复核通过 | [板底与电线杆摆位](../../development/2026-10-29_deck_draft_pole_placement.md) |

SEA-ASSET-R31后续：上段杆身底端直接延长并移除旧下段32三角形，工具与备份见[本轮记录](../../development/2026-10-29_deck_draft_pole_placement.md)。真实渲染15项通过，已查看整根杆截图；功能契约同步/无参检查与架构检查均通过。

## 2026-10-30 模块化海上建造套件

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R32 | 已实现并接入；22件母版/独立包/GLB/PackedScene逐件登记，源重开/四视图/UV面积单格通过；PaletteUV唯一UV0及材质角色563项、22件正式世界建成和卡片真实鼠标/渲染通过 | [本轮记录](../../development/2026-10-30_modular_building_kit.md)及[机器证据](../../development/2026-10-30_modular_building_verification.json) |

独立来源为项目程序化自建，授权记`project_authored_procedural_geometry`；现有公共色板保持原归属。源级与游戏级结果分别登记，尚未通过的项不标记验收完成。

## 2026-10-30 巨手托举纪念品灯塔

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-ASSET-R33 | `liberty_lighthouse/v001` Blender母版、30独立组件包和四视图已完成；源级几何/UV/尺寸/原点检查通过；Godot、碰撞、导航、商业授权与用户最终美术验收pending | [制作与验收记录](../../development/2026-10-30_liberty_lighthouse.md)；55实例、48539母版面逐面检查、68759展开多边形/132596三角面；装配总高约25.4米。雨棚已归一为局部底部中心、世界下缘3.50米，甲板上净高约2.26米。巨手轮廓、雨棚环绕/招牌关系、真实开洞、锈蚀与透镜可见性仍需后续美术打磨，不代签最终美术验收。 |

2026-10-30组件UV修复（R32）：默认UVMap已从全部22源组件删除，PaletteUV为唯一活动/渲染层并导出为TEXCOORD_0；GLB保留四种SEA材质语义槽，KitVisual严格绑定共享材质，不再将丢失角色静默当Matte。`visual-kit-uv`563项/0失败，已查看全22件及浮台/油灯/花盆/风车近景。[修复与证据](../../development/2026-10-30_modular_building_kit.md)。

## 2026-10-30 海上悬浮商铺

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R34 | Blender MCP制作39组件、250实例，建筑/植物分离；39独立包已逐个重开，130283母版面PaletteUV/原点/恒等变换检查通过；真实多视图与源登记见记录。Godot、碰撞、导航、性能、参考图商业授权和用户最终美术验收pending。 | [制作记录](../../development/2026-10-30_floating_shop.md)、[机器证据](../../development/2026-10-30_floating_shop_verification.json)、[母版](../../../art_source/scenes/floating_shop/v001/floating_shop.blend) |

套件归建筑 `building/structure`，海上区域；植物组件归 `upgrade_attachment/plants` 并隶属同一设施。分账本经 `ledger_index.json` 的 `domains.scenes` 路由，`SEA-SCENE-FSH-` 共40条（39组件＋1装配），没有接受任务外哈希漂移。展开全实例为340075多边形/671437三角面，本次没有低面数预算，尚未作游戏优化。

### 海上悬浮商铺v002：加宽平台与正面入口

SEA-ASSET-R34当前源为[v002](../../../art_source/scenes/floating_shop/v002/floating_shop.blend)，v001保留。环廊宽3米（原1.2米的2.5倍），护栏开口约3.43米，门前1.95米连续通路几何检查无障碍；邮筒/售货装置移让、门槛压平。39组件/248实例，39独立包及130283母版面PaletteUV复验通过；展开339061多边形/669345三角面。40条原AssetID更新至v002并保留source_history，未新建重复主记录；Godot接入/运行通行/碰撞/导航/性能/商业授权及最终用户美术验收pending。[修订记录](../../development/2026-10-30_floating_shop_v002.md)、[机器证据](../../development/2026-10-30_floating_shop_v002_verification.json)。

## 2026-10-30 海上悬浮商铺接入 main

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R35 | v002 已导出运行 GLB（4 个材质角色合一、669345 三角面、50.4MB、无内嵌贴图），预制体 4 条 `surface_material_override` 序列化到 tscn；`main.tscn` 的 `World/SeaStructures/floating_shop` 摆放在阳光房主体中心正南 50 米，甲板顶面 = 水面 +0.26 米；`main._water_shapes()` 已接入 `World/SeaStructures`，浮店中心判为阻挡水域。行走/泊位/商店交互/参考图商业授权/用户最终美术验收 pending。 | `floating-shop` 21 项 0 失败、`visual-floating-shop` 三视图，[接入记录](../../development/2026-10-30_floating_shop_runtime.md)、[导出清单](../../../art_source/scenes/floating_shop/v002/export/v001/export_manifest.json) |

## 2026-10-31 海上悬浮商铺 v003：4:3矩形建筑替换

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R34 | v003 源级已完成：32组件/273实例/371母版网格、32独立包全部保存重开、63248母版面 PaletteUV 通过；底座 20.010×15.010 米、主体 12×9 米、封闭立面零门窗；v001/v002 源保留。16 个被取消的旧组件标 `historical_source_retained`，不计入当前装配 | [v003 制作与收尾记录](../../development/2026-10-31_floating_shop_v003.md)、[机器证据](../../development/2026-10-31_floating_shop_v003_verification.json)、[母版](../../../art_source/scenes/floating_shop/v003/floating_shop.blend) |
| SEA-ASSET-R35 | v003 已接入稳定运行 GLB：32组件/273实例烘成 4 个材质角色的单一网格，429474 三角面、32447188 字节、无内嵌贴图；预制体序列化四材质覆盖（Gloss 当时改为不透明釉面，后由 R37 改回透明玻璃）。按阳光房标准改 0.22 米实板（板顶水面 +0.26 米、板底 +0.04 米），水面阻挡按新矩形几何派生并覆盖四角。`floating-shop` / `visual-floating-shop` 当期 0 失败（零售细修后为 37 / 16 项）。行走/泊位/商店交互已由本轮 SEA-ASSET-R36 接入（见下）；参考图商业授权与用户最终美术验收仍 pending | [导出清单](../../../art_source/scenes/floating_shop/v003/export/v001/export_manifest.json)、[优化清单](../../../art_source/scenes/floating_shop/v003/export/v001/optimization_manifest.json)、[装配清单](../../../art_source/scenes/floating_shop/v003/asset_manifest.json) |

分账本登记同步：33 条 FSH 行为 v003 现状（24 更新含装配行、9 新增 AssetID），16 条标历史保留；`current_source_index.json` 由账本重建为 562 条，`runtime_resource_inventory.json` 6 条浮店运行资源逐条刷新哈希。运行时材质实际外链暖木色板 `sea_cabin_timber_8x8_512.png`，catalog 与组件 manifest 里残留的 `sea_cozy_8x8_512.png` 已按只读探针证据纠正；不重跑已验收产物。

同族建筑尺度基准（底层净高 4.866335 米、层高 5.086335 米、楼板 0.22 米、主柱 0.5175 米、平台板宽 0.893551 米、门框参照 3.070845 米）已写入[项目场景 skill 尺寸说明](../../../.agents/skills/sea-scene-component-authoring/references/building-scale.md)及其[机器表](../../../.agents/skills/sea-scene-component-authoring/references/building_scale.json)，由 `building-scale-reference` 探针从正式阳光房 v008 运行装配量取；不改阳光房本身。

## 2026-10-31 浮店承担最小区块职责

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R36 | 已实现；预制体根脚本换为 `src/world/sea_supply_zone.gd`（继承 ZoneScene），甲板按 20×15 名义甲板派生四条环廊行走矩形，封闭主体内部无行走矩形；`Visual` 下四个材质角色网格不再各自派生阻挡（覆写 `_ensure_blockers`），阻挡只由根下覆盖整栋建筑的 `Blockers` 提供；结构物不带 Plants/StaticBatch。`floating-shop` 32 项、`sea-supply` 37 项均 0 失败。 | [接入记录](../../development/2026-10-31_sea_supply_station.md) |

## 2026-10-31 浮店零售细修：摆件 / 广告牌 / 玻璃 / 店内装饰灯

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R37 | 已实现并接入：32→44 组件、273→296 实例、429474→520185 三角面（立体字重做并再放大 1.5 倍后）。正面 4 个玻璃橱窗（窗带 0.56–4.30 米）替换 4 块实墙板，Gloss 恢复透明；`sign_gifts` / `sign_drinks` 与 `sign_panel` 同带；明信片架/邮筒/售货机/冷藏箱在环廊外侧避开 3.2 米开口；店内 4 组货架 + 瓶 + 礼盒、4 盏吊灯 + 串灯均在窗带内。门仍为 0、主体内部仍不可走、外壳尺寸与摆放未动。`floating-shop` 37 项、`sea-supply` 37 项、`visual-floating-shop` 16 项均 0 失败。 | [零售细修记录](../../development/2026-10-31_floating_shop_retail_detail.md)、[装配清单](../../../art_source/scenes/floating_shop/v003/asset_manifest.json)、[导出清单](../../../art_source/scenes/floating_shop/v003/export/v001/export_manifest.json) |

## 2026-10-31 广告牌立体字：更粗更大更厚、三色、一块歪挂

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R37 | 三块广告牌的立体字重做：逐字挤出 0.10 米、圆角 0.027 米（原只有 0.007 / 0.0025，等于贴纸）；字号 SEA SUPPLY 0.62、GIFTS 0.66、COLD DRINKS 两行 0.74 / 0.30。三块牌各有主色：深蓝 / 红 / 青绿，其中红与青绿为本轮新增。排版按实测字宽逐字定位，允许超出奶黄面板；侧牌在 `max_width` 内**等比**缩放，绝不做单轴压扁（压扁会把笔画拉细，正是"不够饱满"的来源）。COLD DRINKS 绕 Y 轴右倾 3.2°。随后整组再放大 1.5 倍（挤深 0.12 米、字号 0.93/0.99/0.80/0.17），三块牌实测文字包围盒首尾相接不重叠，牌角图标缩至 0.74 倍让位而非删除。侧牌面板由 3.02 米加宽到 3.30 米给字腾地方，仍在 12 米墙 3.2 米空档内。外壳、尺寸、摆放、水线一律未动。`floating-shop` 37 项、`sea-supply` 37 项、`visual-floating-shop` 16 项均 0 失败。 | [零售细修记录](../../development/2026-10-31_floating_shop_retail_detail.md)、[装配清单](../../../art_source/scenes/floating_shop/v003/asset_manifest.json) |

## 2026-11-02 野外渔场

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R38 | 12组件/78实例、12独立Blend包、32301源级检查及skill验证器12包通过；原源不变、独立优化/12独立GLB与PackedScene、39逻辑/43真实渲染通过，13条资产已登记（参考授权pending） | [本轮交付](../../development/2026-11-02_wild_fishery.md)；fishery-environment / visual-fishery-environment |

## 渔场复用鱼群修订（2026-11-02）

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-ASSET-R39 | 正式设施64实例与独立彩色鱼群20条已接入；不改Blender制作源，旧定制鱼登记退出装配，鱼群复用同一AssetID | fishery-environment / visual-fishery-production；[交付](../../development/2026-11-02_fishery_production.md) |
| SEA-ASSET-R40 | 两类职责文档与资产登记完成，运行完整验收pending：567行含building_class，水上322／水下129／非建筑／范围外null 116；两个派生视图只引用AssetID。独立太阳能花屋总成角色改entity，BLB基座兼容角色与TSCN对齐part；基座／底框／水下舱件独立归水下观赏 | [两类入口](../../../assets/registry/BUILDING_CLASSES.md)、[职责规范](../../standards/水层分类与空间职责.md)、[本轮证据](../../development/2026-11-02_building_two_class_contract.md)。旧water_layer保留装配兼容，不是额外职责类；源／运行哈希及制作阶段未改。旧water-layer覆盖缺口、浮店空间故障及跨水线源分段继续pending |


## 2026-11-02 海上建筑清点与账本审计（当前实测）

SEA-ASSET-R15/R16/R17/R24/R33–R40：海上用途计入surface与amphibious，共339条资产行；正式场景8条设施总成对应7个地点（打捞台／野外渔场同址升级），另4套建筑源未接入、13种可建结构另计。太阳能花屋完整源误标part、BLB基座账本entity与TSCN part不一致、水层规范表与工具的LHL／种植件／家具例外不一致，均登记待修；不改分类、源、场景或哈希。浮店位置及水线旧问题本轮再次复现：floating-shop 41项5失败、sea-supply 37项8失败；water-layer 104项及真实截图脚本16项虽全绿，存在漏检，不能据此签当前可用／美术验收。原历史通过保留为历史事实，以本次审计说明当前边界。详见[清单、问题与当前验证](../../development/2026-11-02_surface_building_inventory_audit.md)。

## 2026-11-02 建筑职责两类整理（最新口径）

本轮按用户最新要求，把建筑职责收为水上功能／水下观赏两类，基座明确只观赏。新增主字段building_class与两类AssetID视图；旧amphibious／backdrop只作为历史装配／显示描述。前次审计S03完整花屋误标、S04基座角色不一致、S05规范表冲突已在本轮登记及文档层修正；S01浮店和S02运行检查漏洞未通过本轮文档整理冒充修复。实际源模型分段／标高及完整运行职责仍pending。

详见[本轮整理、静态校验与未执行项](../../development/2026-11-02_building_two_class_contract.md)。

范围补充：本轮仅海上主场景；“水下”只指该场景的观赏楼与基座。独立海底／潜水场景另行处理，不按本契约撤销其功能。43项未确认海上归属的独立塔区参考组件不进入两类视图；范围外不等于第三类建筑。

本轮最终静态验收：同步／复核均0问题；8项非法声明拒绝用例及海底范围排除用例通过，322／129两视图互斥完整。源／运行路径、哈希、阶段、授权保持；2377个运行／源支持文件未变。未运行Godot或真实渲染，新职责运行完整验收仍pending。[结果](../../development/2026-11-02_building_two_class_contract.md)。

## 2026-11-02 Skill尺寸基准取整（R06/R07）

已将一位小数的新制作基准直接写入项目sea-scene-component-authoring的SKILL.md：净高4.9米、层高5.1米、柱截面0.5米、楼板0.2米、门外包围3.1×1.8米，倒角与板缝用厘米一位小数。项目与用户级Skill及两份尺寸附件同步；原实测、模型、运行水线与资产哈希保持。适用范围与拼接套件／独立海底例外已写明。[本轮记录](../../development/2026-11-02_skill_building_baseline_rounding.md)。

本轮Skill校验：项目／用户副本quick_validate均退出0，三文件逐字节一致；原历史测量保持。功能契约sync及复核已执行，但被并发R41缺承接及main.gd运行哈希漂移阻断，未据此覆盖他人条款或刷新哈希，详见本轮记录。

## 并发计划条款承接补齐（2026-11-02）

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-ASSET-R41 | v003 已完成制作、独立重开与登记；48组件/895实例，稳定 `SEA-SCENE-ORF2-*` ID 沿用，v002 源与哈希基线保持不变。源级166项零失败、48组件包技能验证全部passed，主源哈希匹配后已更新49条主记录并保留previous_sources。Godot/碰撞/导航/商业授权/用户最终美术验收仍 pending | 主源 `art_source/scenes/ocean_rooftop_farm/v003/ocean_rooftop_farm_v003.blend`；验证目录 `D:/projects/sea-work/ocean_rooftop_farm/v003/`；登记脚本 `tools/blender/ocean_rooftop_farm/register_v003.py`。已通过 MCP 完成并保存厚外挑无草水泥边台、深凹窗/宽主柱/三种破损窗、坡顶高差、不均苔藓、粗杆及低金属材质修订；消防梯仅保留45–60米上三层6段和下挂残梯，屋顶入口采用59.97米承接板边对边连接。 |
| SEA-ASSET-R41 · v004 | pending：已准备45组件 catalog 与两组四状态升级元数据，但尚未登记。移除 `bed`/`field`/`cabbage`/`seedling`/`tomato`/`greenhouse`/`tank` 七类；历史作物、菜床、农田记录不删除、不刷新哈希；旧 greenhouse/tank 保留 v003 源路径并待标记 `superseded_by`。主源为 `art_source/scenes/ocean_rooftop_farm/v004/ocean_rooftop_farm_v004.blend`；四个状态各自独立包，socket 共底心 Z=60.05，默认 `unbuilt`，`game_logic_pending`；基础建筑不含四态，预期独立 `SEA-SCENE-ORF2-BASE-BUILDING` 且不计catalog，主总成仍 `SEA-SCENE-ORF2-ASSEMBLY`。已清除范围为屋顶菜畦/作物/主屋顶6太阳能，保留上层露台2太阳能。登记套件预计45包＋主总成＋base building=47条；执行脚本默认只预检，不执行登记。 | 执行门禁：`D:/projects/sea-work/ocean_rooftop_farm/v004/source_verification.json` 与 `skill_verification.json` 必须均 `passed`，主源及每包哈希必须匹配；严格校验当前账本与来源索引待替换49条旧源哈希，漂移即报错不掩盖。`ledger_index` 与 `current_source_index` 分开维护，保留非本任务索引行和 `previous_sources`。当前 v004 登记、Godot/碰撞/导航/升级逻辑/商业授权/用户最终美术验收均 pending。 |

## 2026-11-02 共用风格与水层差异路由（R06/R07/R40）

已在同一场景Skill增加先判building_class的流程，水上／水下各自加载一份差异附件，水下明确复用共用尺寸／比例／倒角／色板而不另复制数值。水线偏移移入水上差异；水下无碰撞／阻挡／行走／功能／岸线。项目与用户级五文件同步，独立海底场景排除；未修改资产、模型或运行场景。[本轮记录](../../development/2026-11-02_skill_water_class_branches.md)。

## 2026-11-02 水下街景十栋（当前实测）

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-ASSET-R42 | 源级完成：`submerged_street/v001` 十栋独立纯景观建筑，10 组件计划冻结后才建几何；11 行账本（10 栋 + 1 条 reference_only 装配）登记为 `building_class=underwater`、`stage=source_verified_runtime_integration_pending`。风格基准取自海下基座逐面实测（米白 82.3%／深蓝玻璃 7.2%／无近黑）；整包实测象牙 76.4%、近黑 3.6%、合计 11696 三角面，逐栋 ≤ 预算。Blender 内自检 0 失败（逐面 UV 面积与单格安全区、单层 PaletteUV、三角色材质无自发光、底心原点与恒等变换、无近黑大面、无共面 z-fighting）。10 独立包重开复核并导出无内嵌贴图 GLB。 | [交付、缺陷清单与门禁](../../development/2026-11-02_submerged_street.md)；`sea-work/submerged_street_v001/selfcheck_report.json`。**pending**：Godot PackedScene 与 main.tscn 摆位、碰撞/岸线审查、水下真实渲染、双拱商标与参考授权、用户美术验收 |
| SEA-ASSET-R43 | 接入与返工完成：十栋已在 `main.tscn` 的 `World/UnderwaterStreet`，专项 `test_submerged_street.gd` 476 项断言 0 失败（headless 与真实渲染各一次），已登记进 `run_verification.py`。高度改为屋顶对齐水面；按接入后真实观感返工 9 处（屋面光板补屋顶设备、底层窗与门共面渲染成黑块、桥底梁跨断口悬空、塌落桥面无支撑、瓦砾浮在水中、路牌取景斜视、街面人视装不下、渲染无海床、材质覆盖层级错位）。新增渲染像素级黑块断言后又抓出普通公寓门一处，修完最差一张纯黑占比 0.077%。三角面 12518，象牙 77.5%／近黑 3.4%。 | [交付与返工记录](../../development/2026-11-03_submerged_street_integration.md)；`sea-work/submerged_street_v001/selfcheck_report.json`、`godot/outputs/submerged-street-*.png`。**pending**：街区互穿阻挡是否加视觉碰撞、最终水下后期（雾／焦散）观感、双拱商标与参考授权、用户美术验收 |


## 2026-11-04 霓虹花园街区 Blender 制作与源级验收

| 对应设计条款 | 当前实施状态 | 证据 / 未执行项 |
|---|---|---|
| SEA-ASSET-R44 | Blender 源级完成并验收：46组件、639实例，三栋主建筑为6／7／5层；46独立包均保存重开。8896项检查0失败，44439个母版面逐面 PaletteUV 合规；Skill验证器按sea 8×8及已登记印刷图例外适配，母版＋46包共47份全部通过。7张真实Cycles验收图已目视检查；image-2八幅广告图集、圆润厚字、独立花草及概括破损已交付。登记48行（46组件＋总成＋图集），主建筑above_water，植物／图集不承担建筑空间职责 | [交付与证据](../../development/2026-11-04_neon_garden_quarter.md)；[母版](../../../art_source/scenes/neon_garden_quarter/v001/neon_garden_quarter.blend)。Godot导出接入、碰撞／导航／泊位、性能优化、商业参考授权与用户最终美术验收pending；未修改正式TSCN |


R44全局同步：已执行sync与无参复核，分别退出1／1；ORF旧源、zones／ocean_sky／zone1运行哈希与zones内容ID差异阻断，派生功能索引因此未更新。本套件源级验收通过，不以刷新任务外哈希掩盖全局失败。详见本轮交付记录。


## 2026-11-05 霓虹花园街区 v002 结构返工

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R45 | v002 Blender 源级验收完成。9.6 米菜园桥接两楼，右楼实墙、楼板和屋顶同弧。挂架定位、落地灯笼、严重缺墙断板和裂分地坪已完成。50 组件／439 实例，17909 项重开检查与 33 项结构检查零失败。Skill 验证覆盖母版与 50 包，10 张 Cycles 实图复核。51 条 v002 主记录，3 条历史组件，复用原图集。 | [本轮交付](../../development/2026-11-05_neon_garden_quarter_v002.md) · [母版](../../../art_source/scenes/neon_garden_quarter/v002/neon_garden_quarter.blend)。Godot、碰撞、导航、泊位、商业授权 pending。 |


## 2026-11-05 霓虹花园街区 v003

| 对应条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R46 | v003 已接入。右楼右移 12 米，菜园桥跨约 21.6 米且使用实体双坡。50 组件与 506 实例通过 Blender 重开、结构和 02b 导入验收。源级专项与真实游戏专项均通过，参考图商业授权 pending。 | [本轮交付](../../development/2026-11-05_neon_garden_quarter_v003.md) |

## 2026-11-05 家园外围残楼围挡（白盒 → 运行接入）

| 对应设计条款 | 当前实施状态 | 证据 / 未执行项 |
|---|---|---|
| SEA-ASSET-R47 | **源级 + 运行接入均已完成。** 46 组件（2 条 L 形转角残楼 + 每边 11 个 20 米件）、48 个围合实例，四边按「转角腿 10 + 11×20 + 转角腿 10 = 240」整除铺满；类型轮转 house_pair 14／single_house 15／forest_band 15／corner 2。三角面 130178、1943 个网格对象、单件最大 4908。46 个独立包保存重开通过；46 个 GLB 无内嵌贴图，导出三角面与源逐件相等。**口径变更三次**：150 → 90 → 240（最后一次按用户红框截图反推：红框 854×698 px，用围挡外接与霓虹花园 x=156 两点校准得 0.33 米/px，红框约 282 米宽、右界落在 x≈+150，霓虹花园恰在框外，故取 240 米见方）。旧尺寸产物已全部删除，仓库不留历史版本。**已修的 5 处真实缺陷**：① 转角对角漏水（只覆盖两腿）；② 倾斜绕底心旋转致整栋悬空（改按最低顶点压回水面）；③ 顶板不随墙顶破口下沉、悬空成托盘；④ 楼梯间坐在已塌的顶板上；⑤ **对角补块按单一朝向手工摆，母版转到需镜像的两个对角时整个落进可活动范围** —— 上一版 90 米时被运行期专项抓到 2 条矩形侵入圈内，本版直接删除该补块。**源级断言** 17635 项 0 失败（含内侧越界零几何、四边两高程 16 米无缺口、逐面 UV 安全区、单一材质、整栋不悬空、独立包重开）。**运行期专项** `sea-barrier` 通过：46 个包装可独立加载、材质落在真实 MeshInstance3D、48 个实例在主场景、每条矩形有实际尺寸、无矩形压进 240 圈内、四边每 0.5 米采样连续、进深 8 米处仍实心、**从圈内做四邻域连通搜索出不去**（0.5 米缝为步长）、`_is_open_water` 圈内开阔／圈外被挡。挡船走既有 `_collect_water_shapes` 入口（`World/SeaStructures` 下带 `rebuild_blockers` 的节点），未新建并行通道。 | 源 `art_source/scenes/sea_barrier/v001/sea_barrier.blend`；包装 `godot/scenes/components/barrier/`（46 个）；总装 `godot/scenes/world/sea_barrier.tscn`；运行 GLB `godot/assets/models/barrier/`；材质 `godot/assets/materials/barrier/matte.tres`；脚本 `godot/src/world/sea_barrier{,_component}.gd`；专项 `godot/tests/test_sea_barrier.gd`（`python3 scripts/run_verification.py sea-barrier`）；渲染 `sea-work/sea_barrier/v001/renders/` 9 张。**岸线自动生效**：围挡跨水线，走 `World/SeaStructures` 的轮廓种子那条路（与浮店同一套），实测墙内侧 1 米处距线 1.99 米、圈心 58.16 米，白波纹正常。**已接受的后果（用户 2026-11-05 决定「先封死、不看航路」）**：霓虹花园在 x=156、落在 240 墙外，所有往返它的航路断开 —— `surface` 航路数 42→30，其中 9 条涉及霓虹花园的航路由 `test_surface_movement.gd` 的 `SEALED_OFF` 显式登记为预期不可达，其余航路仍要求有解。另：相机 `zoom_max` 190 米不变，从家园中心看不到 240 米外的墙，必须开船靠近。**上述「封死」结论已于当日晚间失效，见本行末尾。****2026-11-05 晚 · 已从 main.tscn 摘除（用户要求）**：只删 `godot/scenes/main.tscn` 里我当初插入的 1 条 `ext_resource`（`36_barrier`）与 1 个节点（`World/SeaStructures/sea_barrier`），diff **0 增 3 删**，其余逐字节未动；资产、Blender 源、46 个组件包装、46 个 GLB、46 行登记（`maintenance_status` 仍为 `source_verified_runtime_pending`，与「源已验、运行未接入」现状一致）、98 行运行哈希全部保留，随时可重挂。**连带收尾三件**：① `test_surface_movement.gd` 的 `SEALED_OFF` 清空，霓虹花园重新可达；② 同文件「不可达目标不退回穿岸直线」原用 `1000,1000` 当不可达目标，探针实测该点 `is_open_water=true`、`segment_clear=false`、`plan_route_to` 返回 3 点（绕开家园建筑即可达），此前能通过只是**靠围挡封住海面**，属假前提，已改为真正的不可达目标 `(0,0)`（岸上，`is_open_water=false`，返回 0 点）；③ `test_sea_barrier.gd` 与 `capture_sea_barrier.gd` 改为「未挂载则降级/跳过」，重挂后断言与抓图自动恢复。**验证**：`sea-barrier` PASS（7012 项，包装与总装独立加载仍全验）、`visual-sea-barrier` PASS（跳过抓图）、`minimum-loop` PASS、`water-layer` PASS；`surface` 剩 2 项存量失败（上岸高度与地面一致、种植物件是独立场景 `home_plot`），另有 4 项（木桥连接可达、走回后执行上船、再次点击泊位回船、船未靠泊不能远程上岸）出现在 21:19–21:21，对应他人正在改的 `boat.gd`（21:19:28）、`character.gd`（21:21:23）、`character_motor.gd`（21:19:26），与摘除无关（21:18 同代码仅 3 项）。 |


## 2026-11-05 共享植被制作规范（设计交付）

| 对应设计条款 | 当前实施状态 | 证据 / 未执行项 |
|---|---|---|
| SEA-ASSET-R49 | 统一制作协议与迁移方法已文档化；没有新建生产资产，没有修改已有源/运行哈希。风权重制作、LOD、共享材质/导出器及新资产验收均 pending。 | [制作规范](../../standards/植被视效制作规范.md)、[评估方案](../ambient/vegetation_visual_plan.md)、[开发记录](../../development/2026-11-05_vegetation_visual_plan.md)。静态审计确认阳光房叶簇 5280 面、农场草 325 面、苔片 75 面，均无 COLOR/UV2；这是原始网格统计，不是全场运行性能。 |


## 2026-11-05 霓虹花园街区五组件拆分

| 条款 ID | 当前实施 | 证据 |
|---|---|---|
| SEA-ASSET-R48 | v004 五件独立 Blend 和 PackedScene 已接入。506 个叶实例保留原姿态并唯一归属。场景分账新增五个 AssetID，原总成升级到 v004。 | [交付与验收](../../development/2026-11-05_neon_garden_quarter_v004.md) |

## 2026-11-05 围栏内沉没旧城（Blender 源级）

| 对应设计条款 | 当前实施状态 | 证据 / 未执行项 |
|---|---|---|
| SEA-ASSET-R50 | 在活跃Blender MCP会话完成 `sunken_city/v001` 原始源：46定义、260实例，其中20种单栋建筑37实例；100块24×24米地板铺满240×240米，中央只禁新增建筑、不漏地板。按商铺/住宅巷/运河/车站前庭组织疏密，新增两种实际断腰/侧倒建筑和5栋倾斜沉降实例；道路、高架、车辆、电线、设施及独立海藻苔片齐备。主源与46独立包保存重开通过，1,325,000项源级检查0失败；1,323,711/1,323,711母版面PaletteUV有面积/安全格通过，母版+46包技能验证通过；180条地坪共边0逻辑缝/0重叠。47条源资产登记，纯水下观赏。 | [制作、返工、尺度与证据](../../development/2026-11-05_sunken_city.md) · [完整主源](../../../art_source/scenes/sunken_city/v001/sunken_city_v001.blend)。完整布局4,941,390三角面，为高保真原始源，游戏优化/LOD、GLB/PackedScene、Godot水下渲染、运行职责、商业参考授权及用户美术验收pending；未改正式TSCN或存档。全工程sync退出1（旧ORF源及3运行哈希漂移），无参数复核退出1（同4项+派生索引过期），不批量接受任务外哈希。 |

## 2026-11-05 沉没旧城 v002 红框补景与道路横卧

| 对应条款 | 当前实施状态 | 证据 / 待完成 |
|---|---|---|
| SEA-ASSET-R50 · v002 | 10处红框完成分组补景，新增116实例；50定义/376实例，整楼实例40（原37+3栋道路横卧）。新增4类低设施，三栋横卧楼复用原单栋母版。原46组件几何/UV/材质、100地板及原37栋楼姿态锁定不变，仅8个原街边设施按清单挪开。705项局部锁定/接地检查、1,330,632项源级检查0失败；1,329,047/1,329,047母版面UV通过；总源与50独立包重开及技能全部passed。51条当前源记录升级，47条保留v001 previous_sources。 | [本轮补景与验收](../../development/2026-11-05_sunken_city_v002.md) · [v002主源](../../../art_source/scenes/sunken_city/v002/sunken_city_v002.blend)。5,300,284三角面原始布局，Godot/LOD性能/商业参考权属/用户最终美术验收pending；v001文件原样保留，未改正式TSCN。 |

## 2026-11-05 沉没旧城 v003 起伏地形与弯曲断桥

| 对应条款 | 当前实施状态 | 证据 / 待完成 |
|---|---|---|
| SEA-ASSET-R50 · v003 | 50当前组件/388实例/40整楼，100块地坪保持全XY覆盖；4.8米下沉街坊与24米缓坡，路面/运河坡岸和既有设施联动高程。从旧桥第二段端头接出26米半径曲线，名义15米真实断口，新加两辆电车，总3辆。1061项坡地/高架专项、1,336,821项源级检查0失败；总源与50独立包重开/技能全部passed。预算不增加，丁字口/运河收口保留v002历史退役，当前50＋总成升级v003，两旧定义不删。 | [地形、轨道、验收和范围](../../development/2026-11-05_sunken_city_v003.md) · [v003主源](../../../art_source/scenes/sunken_city/v003/sunken_city_v003.blend)。5,367,916三角面原始布局，Godot/LOD性能/实际水下渲染/商业授权/用户最终美术验收pending。v001/v002文件原样保留，未改正式TSCN。 |


## 2026-11-05 柔软草皮 v002 与独立分账

| 对应设计条款 | 当前实施 | 证据与边界 |
|---|---|---|
| SEA-ASSET-R51 | 两个独立面片载体与一张Image-2 RGBA图集按独立AssetID登记到vegetation域，消费者为阳光房。18三角面草簇、8三角面苔藓；两份独立优化源重开，GLB保留COLOR_0/UV0且不嵌图。生成结果权利条款未专项审查、用户审美验收pending。 | [交付](../../development/2026-11-05_vegetation_soft_cards.md)；[独立资产账本](../../../assets/registry/ledgers/vegetation.json)；v001已退役，不冒充正式交付。 |


## 2026-11-05 室内房间 bedroom/v001

| 对应设计条款 | 当前实施 | 证据与边界 |
|---|---|---|
| SEA-ASSET-R52 | 13 个组件包（7 壳体 + 5 家具 + 门框门扇）7888 三角面，逐包独立 `.blend`、逐件 GLB 无内嵌贴图、组件 PackedScene 走公共色盘材质绑定；源级断言含 UV 单格内区、包围盒有限、家具原点贴地且对中、壳体房间尺度（5.32 米外包、墙高 2.75、后墙窗洞、前墙门洞）。登记 SEA-SCENE-BDR-001..013，运行资源哈希独立核验。 | [交付](../../development/2026-11-05_bedroom_room.md) · [组件计划](../../../art_source/rooms/bedroom/v001/component_plan.json)。房间灯/行走面/碰撞/镜头归 SEA-ROOM 的正式 TSCN；家具目录扩展、LOD、真实手柄与超宽屏构图 pending。 |


## 2026-11-05 v003宽叶草地和贴图草堆资产

| 对应设计条款 | 当前实施 | 证据 |
|---|---|---|
| SEA-ASSET-R51 | 草簇沿用SEA-VEG-GRASS-SOFT升v003并保留v002源历史；新增SEA-VEG-MOUND-SOFT（252三角面）及SEA-TEX-VEGETATION-MEADOW-ATLAS（2048RGBA）。苔藓保持，vegetation分账本现5份唯一记录。两份独立优化源已重开，GLB无内嵌贴图、UV/权重保真；两个正式区域真实渲染与性能通过。生成结果条款专项审查、用户审美验收pending。 | [交付与维护](../../development/2026-11-05_vegetation_meadow.md)；[资产主记录](../../../assets/registry/ledgers/vegetation.json) |


## 2026-11-05 ProtonScatter第三方试用资产登记

| 对应条款 | 当前实施 | 证据与边界 |
|---|---|---|
| SEA-ASSET-R51 | 3个上游示例GLB及1份可编辑试刷预设逐件登记至vegetation独立账本，source为真实上游GLB/本地预设，不伪造Blender母版。素材来源、固定提交、哈希、绑定方式、试用消费者与证据可追溯。 | [交付](../../development/2026-11-05_proton_scatter_trial.md)；阶段trial_verified_production_pending，素材发行审查与统一时钟接入待做；插件和试刷目录排除发行。 |

## 2026-11-05 沉没旧城 v003 Godot正式导入

| 对应条款 | 当前实施状态 | 证据 / 待完成 |
|---|---|---|
| SEA-ASSET-R50 · Godot导入 | 50组件均执行02b清理、持久优化另存重开、无图GLB及稳定PackedScene；源/色板52份哈希保持，2,565,218→2,565,204母版三角仅减14(0.000546%)，完整布局5,367,885三角，不宣称大幅减面。四机位保真对照通过；三个公共色板角色逐surface序列化。51当前源行登记运行/优化/GLB/Prefab/证据，两退役v002保持。用户确认恢复原水下根高度后，最终33338结构/124真实渲染/1239水层/141最小循环全部0失败，正式import退出0。 | [02b流程、缺陷修正与最终证据](../../development/2026-11-05_sunken_city_godot_import.md) · [正式总装](../../../godot/scenes/world/sunken_city.tscn)。近水屋顶可见，深层道路/断桥在当前海水下几乎不可辨，隔水可读性、LOD/帧率/显存、商业参考权属及用户美术验收pending；无水诊断不冒充正式效果。全工程静态sync退出1(3处任务外哈希漂移)，无参复核退出1(同3处+派生索引过期)，未刷新任务外哈希。 |

## 2026-11-05 沉没旧城 v004 统一限高浅水版

| 对应条款 | 当前实施 | 证据 / 边界 |
|---|---|---|
| SEA-ASSET-R50 | 以v003最高59.6591835米÷4固定统一上限14.9147959米，18建筑减层或断高残墙，2低楼及30非建筑保持。50组件/388实例，新主源/50独立包/优化文件重开通过；5744项独立限高、低楼与非建筑字节、姿态及接地0失败。母版三角981626→981616，运行布局2460631面；四机位保真通过。旧源全保留，v003完整运行ZIP归档。 | [制作、公式、运行与回退证据](../../development/2026-11-05_sunken_city_v004.md)。最终import及33916结构/182真实渲染/1191水层/141生活循环全部退出0。51当前v004运行记录及73条inventory已更新，51份v003完整历史保留；参考商业权属、LOD/设备性能与用户美术终审仍pending。全工程sync因5处任务外哈希退出1，无参复核另含派生索引共6项，SCITY本轮无错误，未刷新他人哈希；不把设计减层计作自动优化。 |

## 2026-11-06 沉没旧城 v005 连续海床、鱼群与海鸥

| 对应条款 | 当前实施 | 证据 / 边界 |
|---|---|---|
| SEA-ASSET-R50 | v005撤下外围40个edge_ramp，恢复原50组件/388实例；新增Terrain3D四region海床与三组程序化鱼群/两组海鸥运行装饰。v004 Blend、公共色板和50组件GLB/优化源受保护；v005登记新增海床与fauna记录。 | [v005制作与验收](../../development/2026-11-06_sunken_city_v005.md)。主源/50包/388结构/水层/海床/鱼鸥真实水面验收通过；LOD/性能、商业参考权属和用户终审pending。 |

## 2026-11-06 印刷面图集改为无损

| 对应条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-ASSET-R53 | 霓虹花园 `poster_atlas.png`（2048²）已按用户「以近景效果为主」改为 `compress/mode=0` 无损，`mipmaps/generate=true` 保留，`detect_3d/compress_to=0` 锁定。已用 `godot --headless --path godot --import` 重导入：日志确认只重导入该文件一个，`[remap]` 由 `path.s3tc` 改回 `path`，缓存生成 `.ctex` 7.93 MB（原 `.s3tc.ctex` 2.80 MB 变为无引用残留）。全量 `git status` 比对确认**无任何其他文件被改写**。运行清单 `poster_atlas.png.import` 一条同步为 985 B / `7f7d04ee…`。代价：显存约 2.8 MB → 约 10.5 MB（含 mipmap），本条明确接受。 | [本轮核实、重导入与 core 实跑](../../development/2026-11-06_doc_drift_sweep.md)；core 8 入口中 `visual-sunken-city`、`visual-crops` 真实渲染均 exit 0，换格式未引入崩溃 |

## 2026-11-06 植被资产在设施中的编辑入口

| 条款 ID | 实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R51 | 正式草皮、苔藓、草堆及原花草复用既有 AssetID。14 个草堆各有稳定的场景实例 ID，分区和单株摆位由设施场景保存。ProtonScatter 预览场景的运行哈希与移动验证已更新，仍为预览阶段。 | [独立植被账本](../../../assets/registry/ledgers/vegetation.json) · [设施编辑与验证](../../development/2026-11-06_vegetation_facility_editing.md) |

## 2026-11-06 五米建筑十组件与建筑 UI 登记

| 条款 ID | 实施状态 | 证据与边界 |
|---|---|---|
| SEA-ASSET-R54 | 源重开/PaletteUV、GLB静态及本轮正式游戏/真实渲染均通过；十件已由主线程签署并精确晋升 `runtime_integrated_verified`。十个唯一AssetID、独立manifest、来源投影及content_index保持同步；旧v001源资产与尺寸不改。 | [机器签署](../../development/2026-11-06_building_5m_verification.json)绑定本批全部运行文件哈希；最终222059 release-signed共13项全PASS/exit0，其中12专项2965 checks/0 failures，另`building-scale-reference`62 rows/0 failures独立记数。源报告30项组件检查/12份重开文件、UV坏岛0、123份保护文件未变；十GLB合计41972三角面、无内嵌图片。用户美术偏好、低端GPU/任意规模测试不由本轮签署覆盖。 |

本批登记路径：`godot/assets/models/building_kit/<id>/<id>.glb`、`godot/scenes/buildables/kit/<id>.tscn`、`godot/assets/data/building_kit_5m.json`；十件ID与条款见本功能规范R54。四个UI脚本 `building_book` / `recipe_card` / `recipe_thumbnail` / `demolition_tool` 已携原 `.uid` 移入 `godot/src/building/ui/`，inventory移除旧路径、保留asset关联；新增同目录 `building_view.gd` 与 `building_progress_presenter.gd`。本次仅登记已有迁移成果，不重写并行功能代码。

初次登记历史（非最终验收阶段）：专属工具 `tools/register_building_5m.py` 当时先校验现存源证据与冻结代码哈希，再精确写入十件及路径迁移；旧 `tools/register_building_kit.py` 仅修正KNOWN中的三条已搬路径，未执行旧脚本。代码仅更新已审阅的building域15个脚本哈希，main/导航/玩家/其他资产不刷新，未知漂移保持报红。该初次登记阶段未运行Godot或全局sync，亦未修改building/ui/save文档及GDD；不是对最终任务的描述。后续Godot真实渲染、release签署及主线程全局检查分别见下段与[完整任务交付](../../development/2026-11-06_building_5m_and_ui.md)。

最终签署依据已更新为 `D:/projects/sea-work/verification/20261106-222059-building-5m-release-signed-2a186b/report.json`：13项全PASS/exit0，12专项2965 checks/0 failures，另现场Sunroom对Catalog高度守卫`building-scale-reference`62 rows/0 failures。主线程通过 `tools/register_building_5m.py --promote-verified docs/development/2026-11-06_building_5m_verification.json --write` 绑定新机器签署，仅处理本批十件与已审阅运行资源；本次文档更新不执行该命令、不改registry。最终白名单20个代码文件与222059隔离副本完全一致，包含单个`ground_space.gd`适配；最新机器汇总44项`signed_source_comparison`均`matches_signed=true`，已确认新release副本；213331先签仍保留为历史，不混淆批次。不重算main、水材质、动物源等并行未知变更；上段15文件仅初次登记历史。

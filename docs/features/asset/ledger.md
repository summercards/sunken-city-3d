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
    "submerged-neighborhood",
    "visual-submerged-neighborhood",
    "reference-skiff",
    "visual-reference-skiff",
    "structure",
    "decorations",
    "visual-decorations",
    "visual-plot-shipping",
    "visual-home-lighting"
  ]
}
```

## 2026-10-28 黄白木船与双桨

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-ASSET-R28 | 12组件/44实例、12独立包、公共PaletteUV及四视图通过；已接入正式Boat，参考商业权属pending | 源级46589检查、11697面/22888三角面，优化导出22695三角面；新船专项、实景、灯光及装饰回归见[交付记录](../../development/2026-10-28_reference_skiff.md)。全世界surface/selftest有1+4项既有失败，新旧Boat单文件对照一致，不记为全通过。 |

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

## 资源与调用入口

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

首批登记现有 43 个独立组件；其他运行资源建立路径归属，生产级 AssetID 补登作为明确债务。

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

# 2026-11-11 楼房工坊 · 连续实体 model core

[主文档中控](../../GDD_V1.0.md#sea-workshop) · [功能设计](../features/workshop/spec.md) · [独立账本](../features/workshop/ledger.md) · [上一版编辑器记录](2026-11-10_building_workshop_editor.md)

## 本轮 model core 重构目标与实际范围

用户当前批评旧成品是「积木拼装」，不是结构严谨、工整的 professional model。本轮主线程重构 model core，不继续用 UI 堆功能掩盖模型问题。验收首先看真实模型大图、墙角/洞口/板边近景与整体轮廓；检查报告只用于追溯，不反复以测试数量表功。

「结构严谨」在本轮指连续实体几何、接合、净洞、参数映射和可复用整件组织，不表示进行了土木结构安全、受力或承载计算。

本轮实际修改连续壳几何与装配内核、配方默认/模式分支、会话原子生成探针、Store版本与quality元数据、preview真实三角面点选、编辑器capture/验收脚本，并在统一runner增加和增强workshop-shell专项；已执行隔离几何回归与真实编辑器实测。本记录覆盖整体代码重构、失败修正、实际证据及交付状态；不扩写为正式场景接入、资产正式登记或新stage整屋blend交付。

## 稳定条款与模式边界

新增独立条款 R19–R22，ledger 以四个独占条款行精确承接，不复用或改号 R01–R18。

| 条款 | 当前约束 |
|---|---|
| SEA-WORKSHOP-R19 | 连续墙壳、真实洞口/reveal、单实体框、统一 bay、连续整板/roof、整栋同一 taper 映射 |
| SEA-WORKSHOP-R20 | editor_new 的 authoring defaults 与 legacy defaults 分离；显式模式；damage/位移拒绝与会话原子提交 |
| SEA-WORKSHOP-R21 | 整层墙/板、整孔框与独立玻璃的整件槽/导出/替件；Native2 分件实体倒角例外 |
| SEA-WORKSHOP-R22 | 生成期 audit、实际 faces 与独立 QA、统一 runner、真实 editor/视觉/性能分域，不以历史通过代签 |

### 新建默认与旧配方兼容

- 编辑器新建 `editor_new` 调用 `Recipe.authoring_defaults()`：`construction_mode=shell_v2`，`aging=0`、`damage=0`、`vegetation_density=0`，墙绑定 `wall_sun`。clean 指干净、无损、无默认植物，不新增名为 clean 的配方字段。
- `Recipe.defaults()` 保留 `modular_v1`；旧配方缺少 construction_mode 时仍按 modular 解释。旧样例、破损能力与槽身份保留，不强转已存档，不批量改写旧源。
- UI 已有「连续实体 · 工整模型」和「旧版拼装 · 配方兼容」显式模式；最新真实editor功能报告已通过，具体批次与视觉未签边界见下。
- 模式切换不是旧 `lower_a` 等 partial slots 到新整层墙壳的迁移服务，不保证任意旧覆盖都能跨模式使用。
- 连续模式 `damage!=0` 当前明确拒绝，不能以删盒子冒充连续实体破损。旧 modular 继续有破损，但不再作为 professional model 的新建默认。
- 连续结构槽 `disabled:true`、结构 `excluded_slots`、非零offset由wrapper全部明确拒绝，含frame/glass；`disabled:false`/零offset不表示具备删结构能力。残留跳过分支或旧metadata不能作为可支持断壳的证据，植物槽不混同结构槽；未知组合不宣称支持。
- `WorkshopSession` 的patch、配方/catalog提交、`accept_loaded`和`new_document`在写状态前都做实际生成probe，失败原子拒绝，保留原配方/catalog/历史与最后成功预览。最新专项覆盖这些入口的拒绝与状态保留，不凭单个damage正向用例扩大到未测组合。

## 连续几何契约

### 墙壳、洞口与板

矩形四角或半宽半深 L 形六角轮廓按每层生成一个 `wall_shell_<floor>`。凸外角采用变形前半径0.07m的真实3段quarter-circle弧面，与墙run及厚度封面连续相接；内角/L凹角保持sharp miter，墙上下水平边不圆。圆角随整栋taper同映射，不存在用一排独立墙盒/柱盒掩盖接缝的专业默认。当前不支持任意多边形。

门窗真正贯穿墙厚，返回面 reveal 与外/内洞口倒角有实际面。窗框是单个闭合环实体；门框是单个封闭 U 形实体，不是三块或四块重叠盒子，也不在门底增假阈板。每条墙 run 依统一 bay 规则等分；短 L 臂、墙角余量、净洞与框材冲突明确拒绝，不静默压缩净洞。

楼板每层一个 `slab_<floor>`，屋顶仅一个 `roof_main`，矩形/L 形均为连续整板，不生成 cell roof boxes，不把 L 庭院填实。逐层层高累计，楼板厚度按对应层覆盖取值，墙顶与下一结构板的接合按实际几何核对。

### 整栋 global taper

所有墙、板、框、玻璃顶点共用同一映射：

`scale(y) = 1 - taper * clamp(y / total_height, 0, 1)`

`(x, y, z) -> (x * scale(y), y, z * scale(y))`

这不是每件以自身中心独立收分。净洞参数为变形前尺寸，变形后上下口宽、墙厚和实际包络随映射变化；不承诺非零 taper 后仍保持原始名义净宽。实际部件法线须从变形后几何核验，不能用平滑法线或 metadata 假装连续实体。

### Native2 实体倒角与例外

| 部位 | 实际参数/做法 | 不能宣称 |
|---|---|---|
| 连续结构板与 roof | `formed_band`，0.028m 实体倒角、3 segments；0.14m 出挑 | 不是平台装饰木板，不借平台装饰板规范冒称全风格已过 |
| 洞口 | 0.02m chamfer、1 segment；返回面连接内外单段 chamfer | 深度方向三个区间不是三段圆弧 |
| 框材 | 0.018m chamfer、1 segment | 不是3 segments quarter-circle |
| 墙凸外角 | 0.07m真实圆弧、3 segments，0/30/60/90度四个实际弧顶点；随global taper映射 | 不是单段chamfer或仅平滑法线 |
| 墙内角/L凹角及上下水平边 | 内角/L凹角sharp miter，墙上下水平边不圆 | 不是全体墙边圆角，也不是完整style已过 |
| 外部 prefab | 整件实际几何，不缩放凑尺寸；倒角宽度未测量时如实标记 | 不套用母型倒角参数声称替件已达标 |

这些是分件如实登记的 Native2 参数/例外，不把旧 R03 的默认3段扩写为全体部件都3段。凸外角真实圆弧已补并经实际顶环专项核验；完整style、内角圆弧与墙上下水平边圆弧仍未实现/未签。

## 连续 slot 与 prefab 所有权

| slot | 边界 |
|---|---|
| `wall_shell_<floor>` | 整层闭合墙壳，不是单 bay 或旧 lower_a 局部墙块 |
| `slab_<floor>` | 整层连续结构板 |
| `roof_main` | 整件连续屋顶 |
| `frame_<facade>_<floor>_<ordinal>` | 一个完整洞口框；窗环/门 U 形各为单实体 |
| `glass_<facade>_<floor>_<ordinal>` | 对应窗孔的独立玻璃 |

按整件导出模块，再按兼容整件替换。静态安全、族、轴向、pivot 与实际 mesh 包络仍需校验，禁止非等比或其他缩放凑尺寸；不匹配原子拒绝，其他槽与原定义不连带修改。

首跑实际执行 wall/frame/glass 的模块导出、PackedScene 重载、`apply_prefab_to_slot`、真实重建以及替件后 Store 往返；不是仅在 catalog 换个 component_id。整层 slab/roof 的完整替件组合与任意外部 prefab 不因此自动签过。候选模块不自动正式登记，不新增 AssetID，不改变既有来源/source/timing 或正式场景。

## 本轮实际代码与runner职责

| 源文件 | 职责 |
|---|---|
| `godot/src/workshop/shell_geometry.gd` | 闭合墙壳、洞口/reveal、框/玻璃、连续板、global taper；基线映射前实际边的闭合/定向 audit |
| `godot/src/workshop/shell_generator.gd` | shell静态装配、实际mesh faces碰撞、整件prefab；最终实际faces闭合/定向不合格时明确拒绝（含invalid prefab），校核后写root最终quality；root metadata 版本为 `sea_workshop_continuous_shell_v2`，模式为 shell_v2 |
| `godot/src/workshop/recipe.gd` | `authoring_defaults()` 与旧 `defaults()` 分离、construction_mode 契约及旧档兼容 |
| `godot/src/workshop/generator.gd` | 按 construction_mode 分支调用 shell；modular 旧分支保留 |
| `godot/src/workshop/session.gd` | patch/recipe/catalog提交、accept_loaded/new_document均在写状态前实际build probe，失败原子保留配方/catalog/历史/预览 |
| `godot/src/workshop/store.gd` | 从实际生成 root metadata 读取 generator version，manifest 记录 construction_mode/model_quality，避免 shell 误标为 legacy；静态打包/重载 |
| `godot/addons/building_workshop/catalog_adapter.gd` | 整件 slot 模块导出、prefab 实际接口预检和原子提交 |
| `godot/addons/building_workshop/editor_screen.gd` | 显式 mode 与新建 authoring defaults 接线 |
| `godot/addons/building_workshop/editor_preview.gd`、`editor_verification.gd` | preview以AABB粗筛、actual triangle ray作最终点选，避免整层AABB抢选窗孔；矩形/L真实editor新增点选断言；连续模型截图与独立SubViewport模型大图capture，生成截图不代签目视验收 |
| `godot/tests/test_workshop_shell.gd`、`scripts/run_verification.py` | 独立实际几何 QA 与统一入口 workshop-shell |

## 验收分域、历史修正与当前证据

### 生成期与独立 QA 不能互相冒充

1. `shell_geometry` 在基线映射前对实际生成边做位置焊接与 T 接处理后的闭合/定向 audit。
2. `shell_generator`对映射、装配及替件后的实际faces再做闭合/定向审计；invalid prefab或其他实际part不合格会明确失败，不再仅警告后成功。root最终quality的topology/verification按实际faces校核写入，但build.ok仍不代替独立QA、视觉或结构安全计算。
3. 独立 QA 另取实际 mesh 与 collision faces，经累计节点变换统一到建筑根坐标，核对边界、nonmanifold、定向、重复/退化面、单连通分量、窗环及正有向体积，并核对实际顶点法线、UV/色板；不只读取生成器自报 quality。
4. 全局/统一坐标法线应与实际变换后面朝向一致。首跑 fixture 根恒等、替件基变换保持恒等，法线属性检查按实际 mesh 局部顶点/法线完成；不扩写为任意旋转、镜像或缩放层级的 globalNormals 组合均已验证。
5. Store静态重载后重新取faces/碰撞与属性审计；slot/prefab/legacy单独留证。几何基线层的历史自述不取代shell root最终实际quality及外部独立报告；两者均不能删除视觉未签边界。

### 历史失败与修正（不覆盖原结果）

023726首跑与025025中间模型两批shell均552/0；025833增强专项716/21失败因测试跨clamped taper的y=0插值截面并非精确参数截面，已改用真实顶环/实际顶点核验，未放宽阈值；025806 editor 1489/4失败为输出限定根错误与脚本重复调用shell samples，均已修正后另跑，不能反改旧失败。

历史证据目录分别为 `20261111-023726-workshop-continuous-first-485d04`、`20261111-025025-workshop-continuous-rounded-611c84`、`20261111-025833-workshop-continuous-final-qa-bb7cb2`、`20261111-025806-editor-continuous-final-model-bbb46e`，均在 `D:/projects/sea-work/verification/` 下。旧编辑器327/0与editor_v001审计572/0仍保留，不能复用为本轮通过依据。

### 最新数值/静态专项实际结果

- 外层 `D:/projects/sea-work/verification/20261111-031500-workshop-continuous-verified-58a3bd/report.json` 已落盘：workshop-shell、workshop-rules、workshop-deep均exit_code=0、passed=true、unexpected_errors=[]。不是把此前pending提前写成通过，而是依据现有报告回填。
- 同批 `project/outputs/workshop_shell_report.json` 已核对为716 checks、0 failures，visual_acceptance明确未执行。这里只登记被测组合实绩，不宣称所有专项/任意参数/视觉已过。
- 覆盖矩形/L形1/3/5层、逐层高/板厚覆盖、left禁窗、实际凸角顶环0/30/60/90度弧点与法线/正体积/闭合/duplicate/nonmanifold、确定性、净洞/reveal与同源碰撞、session各入口原子拒绝、invalid prefab拒绝。
- wall/frame/glass整件模块实际export/apply后重建与Store静态重载，基线Store、实际生成版本metadata和两个legacy样例兼容分列留证；不承诺任意外部prefab或旧partial slot自动迁移。

### 最新真实 editor 实际结果与点选

外层 `D:/projects/sea-work/verification/20261111-031449-editor-continuous-delivery-6bf812/report.json` 已落盘：editor-workshop为real、exit0/passed=true、unexpected_errors=[]。同批 `project/outputs/workshop_editor_report.json` 已核对992项、failures=[]、passed=true，enginehint=true/is_playing=false、scene_unchanged=true、root_paused_unchanged=true。

preview现在用AABB仅粗筛，再按实际mesh三角面ray确定最近命中。矩形/L两项「点击洞口不先选中整层AABB」真实editor断言均通过；不再用整层墙壳包围盒抢走窗孔玻璃selection。该验证调用真实控件/端口与信号，不等同完整鼠标自动化。

该隔离项目 `project/outputs/` 下三张真实模型图已存在：

- `workshop_shell_model_rect.png`
- `workshop_shell_model_front.png`
- `workshop_shell_model_l.png`

三图来自1400×1100独立SubViewport；另有五张continuous_*为1600×1000真实editor framebuffer。交付三张模型大图已经主线程逐图目检，确认明显连续墙面、无棋盘拼格、圆外角高光、真实开口与板墙平齐。目检结论为「工整几何的基础模型已改，整体造型仍简洁，不冒称丰富美术终验」。报告图像字段art_accepted=false仍表示未签完整美术终验，不抵消本轮基础几何目检结论。

### 成品汇总与候选包状态

成品汇总已实际生成并读取：`D:/projects/sea-work/building_workshop/continuous_v002/outputs/continuous_delivery_report.json`，passed=true、checks_count=1348、failed_count=0。1348是交付脚本对实际报告、文件/hash、安全和完整性的核验，不是引擎专项计数之和；引用的真实editor实际992/0、geometry716/0，不采用重复两次shell samples的1481中间计数。汇总脚本engine_executed=false只说明其自身不执行Godot，实际引擎证据来自上述runner报告。

交付输出根为 `D:/projects/sea-work/building_workshop/continuous_v002/outputs/`，已核对八张PNG、ZIP及安装五件hash与report一致：

| 交付文件（相对输出根） | 内容/尺寸 |
|---|---|
| `workshop_shell_model_rect.png` | 矩形模型大图，1400×1100 |
| `workshop_shell_model_front.png` | 正面模型大图，1400×1100 |
| `workshop_shell_model_l.png` | L形模型大图，1400×1100 |
| `workshop_editor_1600x1000_continuous_rect.png` | 真实editor矩形，1600×1000 |
| `workshop_editor_1600x1000_continuous_front.png` | 真实editor正面，1600×1000 |
| `workshop_editor_1600x1000_continuous_back.png` | 真实editor背面，1600×1000 |
| `workshop_editor_1600x1000_continuous_l_top.png` | 真实editor L俯视，1600×1000 |
| `workshop_editor_1600x1000_continuous_l.png` | 真实editor L透视，1600×1000 |
| `model_comparison.png` | 1400×900真实对照排图；旧完整UI与新模型各自等比缩放、无裁剪/AI补图，视图条件不同，不作为等条件美术分数 |
| `continuous_candidates.zip` | 两楼原ID/revision_0001各五件JSON/TSCN及一份JSON说明，不含截图、Blender源或GLB |

ZIP完整路径为 `D:/projects/sea-work/building_workshop/continuous_v002/outputs/continuous_candidates.zip`，SHA256=`e2fd59200e4ed6dcbc7bfe21cfcaa4341316fd335d2a28b866ade6fcdb415e11`。公共色板 `res://assets/textures/shared/sea_cabin_timber_8x8_512.png` 未打包，SHA256=`f4b1f52544e9e785b2ef7ae5eabbe378a551f1c48b5ef0f79905f2a9f8f15d09`，使用时依赖生产工程同路径资源；不是可脱离该依赖的全资源包。

### 已装入工程的两个候选与五件manifest

矩形候选目录：`D:/projects/sea/godot/scenes/workshop_buildings/shell_rect_1794338160_71001671/revision_0001/`。

L形候选目录：`D:/projects/sea/godot/scenes/workshop_buildings/shell_l_1794338160_71001671/revision_0001/`。

两个目录均有下表五件，完整逐文件path/hash亦在交付report的bundles与candidate_installations中列出并核对。候选JSON状态为candidate_only / exported_pending_project_registration，formal_registration=pending；只是installed_candidate_only，不自动获得正式AssetID、不写registry或挂Main。

| 文件 | 矩形 SHA256 | L形 SHA256 |
|---|---|---|
| `building.recipe.json` | `b0f279964ce54c194b3fe281a4ae580804b8b3024901a5d16006acb1f1785538` | `e65697a481a2f82a1122316fe3c600a44708e8eeb7baa284e7c998234ea7b2e4` |
| `catalog_snapshot.json` | `38a5bc8328cfde4bb658856dbb30f200d6eb18c56e891948068173b7a877c9fc` | `38a5bc8328cfde4bb658856dbb30f200d6eb18c56e891948068173b7a877c9fc` |
| `building.tscn` | `509d6312e3d4f110a47c1203b3becb16dea47aa380c6ac7bacfe786444ebb3e5` | `093f04ccdddd6f1e50a6a2b67395bc0e95e345a407c260e1fd9604f0bd3b7e3d` |
| `candidate_manifest.json` | `137e4cf76c7c9ae8f9637b14cf10e0f6a7bb4b6b64e0ff2332652ebbfed8b141` | `4a28be19cf61a58c46169bd6d72841e2ad1c2b83ad77e3cb00288b8a11afa416` |
| `ledger.json` | `3a5ea6343a197162a1a0df963c1293b76ae3201b1b2d9b588b17e9230ab4220f` | `e546eda9362e49c366a211fedaa5e3e2a9558127e68994df97d9c36477b73683` |

manifest完整路径：

- `D:/projects/sea/godot/scenes/workshop_buildings/shell_rect_1794338160_71001671/revision_0001/candidate_manifest.json`
- `D:/projects/sea/godot/scenes/workshop_buildings/shell_l_1794338160_71001671/revision_0001/candidate_manifest.json`

矩形12×9m、3层实际总6376三角面，其中结构3200；同规格旧modular对照结构52428。3200对52428是结构对结构，不能拿结构面数与整楼总面数混比。L形12×12m、3层实际总7560三角面；名义尺寸不包含板出挑等实际包络。面数只是几何统计，不是美术分数或性能终验。

## 直接使用

1. 打开Godot编辑器顶部「楼房工坊」，无需运行游戏。进入时已有草稿/旧modular不会被强制替换或迁移。
2. 需要新模型时点击「新建」，新文档默认为「连续实体 · 工整模型」（shell_v2、干净无损无默认植物）。已有未保存内容按原确认流程处理。
3. 在「文件」页「刷新」，找到 `shell_rect_1794338160_71001671` 或 `shell_l_1794338160_71001671` 后打开配方；每楼由recipe与同目录catalog_snapshot恢复，可独立编辑，静态使用对应building.tscn。
4. 点选墙面时，当前连续槽 `wall_shell_<floor>` 是整层墙壳；点击「导出当前槽为独立模块」导出整层结构，不是旧版列表中 `lower_a` 等下方tiny局部。frame为整孔框、glass独立；不承诺旧partial slot自动映射。
5. 候选使用不等于正式登记；确认正式使用后仍须走SEA-ASSET路由。此轮交付为原生参数化JSON/TSCN，不是Blender/GLB制作链。

## 全库contracts实跑及未同步边界

`D:/projects/sea-work/building_workshop/continuous_v002/contracts_sync.log` 与 `contracts_check.log` 两项已实际执行，均exit1，不能因局部交付通过写全库通过。日志按实际行计数：

| 实跑 | source hash drift | runtime hash drift | 其他问题与总数 |
|---|---|---|---|
| contracts_sync | 8 | 67 | SEA-ASSET条款ledger缺失/多余；共76 issues |
| contracts_check | 8 | 67 | 同一SEA-ASSET问题，另SEA-WORKSHOP主表状态不一致、派生feature索引过期；共78 issues |

两日志均列44 features、1069 source assets、1510 runtime resource hashes。全库失败阻止sync成功更新主表，因此主表状态差异仍在；工坊账本保持partial，不手改GDD摘要、不批量刷新hash、不修他人SEA-ASSET-R67。交付汇总中的whole_project_contracts=not_provided表示汇总脚本未接收全库证据，不表示两项实跑未执行；此处独立记录实际日志。定稿未再改代码source、registry或脚本。

## 未签事项与后续交付

- 三张真实model大图的基础几何已经主线程目检：连续墙/无棋盘/圆外角高光/开口/平齐有实际改善；整体造型仍简洁，不冒称丰富美术终验。完整professional美术终验仍不能由UI布局图、非空截图或计数代替。
- 完整style、内角圆弧、墙上下水平边圆弧、复杂根系/墙面苔、stairs/navigation、全楼可达与性能仍未签；凸外角0.07m真实三段圆弧已实现不再列为未实现，仍不签整体美术；4D/受力、承载及土木结构安全计算未做。
- 连续drastic damage/非零damage、结构禁用true/excluded/非零位移明确拒绝；未知组合不宣称支持，任意外部prefab不承诺自动适配；不新增stage整屋blend承诺。
- 完整插件卸载重载/跨进程恢复、正式资产登记与正式世界/导航接入不随内核改为已完成。
- 定稿只读回查spec/ledger精确条款ID集合：两者均为R01–R22，共22条，无缺失、无多号；文档检查不代替引擎、视觉或全库验证。

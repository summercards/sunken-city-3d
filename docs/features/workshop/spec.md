# SEA-WORKSHOP · 参数楼房工坊

[主文档中控](../../../GDD_V1.0.md#sea-workshop) · [独立账本](ledger.md)

## 目标与边界

用户2026-11-10 22:45纠正主目标：制作工具必须在 Godot 编辑器中使用，无需运行游戏。主交付为 EditorPlugin「楼房工坊」主屏，拥有每栋独立编辑配方、组件绑定、局部覆盖、撤销历史、静态烘焙与候选登记。不拥有玩家建造布局、库存、世界时间、主存档或正式场景摆位。已实现的游戏内暂停菜单版保留，作为未来玩法模块基础；不以它替代编辑器工具，也不继续扩展其玩法。已有任意GLB不宣称可无损反推参数。

2026-11-11 当前纠偏：用户认为旧成品是「积木拼装」，不是结构严谨、工整的 professional model。本轮主线程重构 model core，以连续墙壳、真实洞口和连续结构板改善实际模型，不以 UI 堆功能或测试数量代替成品质量。新创作与连续模式以 R19–R22 为准；下文 V1/modular 与旧编辑器验收仍作历史保留，不代签本轮视觉。这里的「结构严谨」指几何、接合与模型组织，不是土木结构安全或承载计算。

## 设计条款与验收标准

| 条款 ID | 规则与验收 |
|---|---|
| SEA-WORKSHOP-R01 | 当前主入口为 Godot 编辑器顶部「楼房工坊」主屏，未按F5/F6即可编辑/预览/保存/烘焙；独立SubViewport不加载Main，不改变编辑器SceneTree暂停或玩家数据。原游戏内暂停菜单入口保留为未来玩法基础，其暂停/输入恢复协议仍有效，但不代替编辑器生产工具。 |
| SEA-WORKSHOP-R02 | 一栋楼一个稳定building_id、带版本JSON编辑配方；新建、打开、另存、保存、撤销/重做、取消与未保存退出有明确反馈。校验未来版本、非有限值、规模、路径穿越、未知字段/组件，坏输入不得破坏当前配方与预览。 |
| SEA-WORKSHOP-R03 | 规范预设读版本化机器数据；默认层高5.1m、板厚0.2m、净高=层高-板厚、主柱0.5m；门框外3.1×1.8m不是净洞，净洞独立校验。实体倒角默认3段并小于局部厚度一半，参数变化不得靠整件非等比缩放伪造倒角。 |
| SEA-WORKSHOP-R04 | V1支持矩形/组合L形、逐层与逐立面门窗配置、单槽覆盖；稳定slot_id不以数组位置作唯一身份。建筑/破损/植物随机种子独立；相同配方与catalog输出确定，不消耗玩法随机流。 |
| SEA-WORKSHOP-R05 | 表面老化与结构破损独立；允许完整、缺角、破窗、断墙/残板的受控样式；真实缺失几何同时影响碰撞，断口有封边。门洞/院落/破口不能被整栋AABB或单凸包封住；V1不实现实时刚体倒塌。 |
| SEA-WORKSHOP-R06 | catalog用稳定组件ID解析参数构件或白名单静态PackedScene，记录版本、接口、原点、轴向、尺寸与资源指纹。替换组件后slot、局部姿态、配方身份不变，不兼容替件明确拒绝；共享源材质与Mesh不被编辑预览修改。 |
| SEA-WORKSHOP-R07 | 植物在最终存在的屋顶/檐边/墙角/树穴语义区域生成，支持品种与小中大比例、密度、独立seed及局部锁定/排除。植物、花盆、建筑分别维护；不把LOD当生长档，不新增四季与作物玩法。 |
| SEA-WORKSHOP-R08 | 烘焙产物为无工坊重建脚本的独立静态TSCN，建筑按构件/材质分块，植物保留独立实例，材质与owner完整序列化。导出后重载比对几何/身份/空间声明；配方保留可再次编辑，不焊整楼与植物。 |
| SEA-WORKSHOP-R09 | 水上功能/主场景水下观赏/独立潜水使用明确spatial_profile：观赏模式全子树无碰撞/导航/岸线；其他模式从同一最终结构派生简化分段人物碰撞、允许站立表面及水面阻挡来源，不能据视觉楼板直接承诺全楼通行。 |
| SEA-WORKSHOP-R10 | 每楼导出独立JSON、TSCN、候选manifest与登记页，保留配方/catalog/生成器版本、hash、AssetID与来源。应用内候选登记与仓库正式资产账本分开；正式登记由SEA-ASSET路由唯一主记录，不自动改仓库账本/索引或替换主场景。 |
| SEA-WORKSHOP-R11 | 保存/导出先写临时文件和重载验证，再提交单次版本目录；重复导出不覆盖历史，失败不宣布成功、不损坏前一有效版；导出文件夹不能包含路径穿越。文件目录选择经限定端口，测试只写隔离用户目录和工程外产物。 |
| SEA-WORKSHOP-R12 | 经统一runner覆盖规则、静态重载、组件替换、缺口碰撞、确定性、取消/拒绝/撤销、游戏入口、文本输入/世界隔离、原暂停恢复与多分辨率真实渲染。源/功能/视觉/性能/用户美术终验分列，未验项pending。 |
| SEA-WORKSHOP-R13 | 主交付为 `addons/building_workshop/plugin.cfg` 注册的 EditorPlugin「楼房工坊」主屏；无需F5/F6，不加载Main或依赖Autoload，不暂停编辑器SceneTree，不自动替换/修改当前编辑scene及用户transform。仅用户显式点击「在3D打开」可打开已保存静态产物；生产工程enabled列表只增本插件，保留其他addons。运行版Panel/Host与暂停菜单入口保留为未来玩法，不删除、不拿它改名充当编辑器预览。 |
| SEA-WORKSHOP-R14 | 编辑器每栋保存到 `res://scenes/workshop_buildings/<building_id>/revision_NNNN/`，以实际Store的下划线命名为准；固定五件 `building.recipe.json`、`building.tscn`、`catalog_snapshot.json`、`candidate_manifest.json`、`ledger.json`。临时写入与重载校验后提交新revision，不覆盖历史。未保存草稿恢复文件独立为 `user://building_workshop_editor/recovery.json`，不进入游戏主存档或混用运行版候选根。 |
| SEA-WORKSHOP-R15 | 编辑器与运行版共用recipe/catalog/generator/mesh_builder/session/store六个纯内核脚本，通过 `@tool` 支持编辑期；共享内核最终回归 `D:/projects/sea-work/verification/20261111-003009-workshop-bake-regression-03b9c6/report.json` 中 rules/deep 均 exit0/passed=true，日志分别为24/0与41/0。重开每栋以同目录 `catalog_snapshot.json` 恢复绑定，不悄悄回退全局catalog。替件仅接 `res://scenes/components/` 下通过静态安全、实际尺寸、pivot、轴向与槽族校验的PackedScene；单槽替换建立局部独立componentID，不连带改变原组件、其他槽或整楼姿态，失败原子拒绝且可撤销。 |
| SEA-WORKSHOP-R16 | 右栏提供「导出当前槽为独立模块」按钮并调用实际 `screen.export_module_component` 端口；单槽模块导出为 `res://scenes/components/workshop_modules/<building_id>/<slot_id>/revisionNNNN/component.tscn` 与 `component_manifest.json`，此处实际适配器使用无下划线revision。记录building/slot/source_component身份、版本、实际包围盒、pivot、轴向和hash，静态重载比对后提交；不重写原source/timing等来源身份或原正式登记，不以模块导出自动产生AssetID。候选只在用户确认使用后才经register工具按SEA-ASSET路由正式登记，既有两个sample主记录保留。 |
| SEA-WORKSHOP-R17 | 编辑器主屏内可视化编辑基础参数、全局绑定、逐层与立面覆盖、稳定槽覆盖/禁用/恢复、独立aging/damage与植物品种/密度/三体量/seed/锁定排除；独立SubViewport提供点选、旋转缩放、正背俯透视、线框及实际碰撞显示。局部按钮不吞未应用字段，已排除槽保留恢复入口、不拿过期几何定位；保存与会话撤销/重做、文本自身撤销及取消确认边界分别验收。 |
| SEA-WORKSHOP-R18 | 插件生命周期已完成当前编辑器闭环验收：主屏隐藏/恢复、临时预览清理及屏幕重建可恢复snapshot、catalog、未应用输入与UI dirty；最新真实 `editor-workshop` 在隔离副本以 `--editor` 运行，exit 0 / passed=true，inner report 为327 checks/0 failures，确认无Main/Autoload、仅启用本插件、scene/root paused不变。该屏幕重建不是完整插件卸载重载或跨进程恢复；最新四张真实截图已审阅，但完整美术、性能、复杂根系/墙面苔、楼梯与全楼可达仍pending。 |
| SEA-WORKSHOP-R19 | 连续模式 `shell_v2` 的 model core 必须按每层矩形四角或 L 形六角轮廓生成单个闭合墙壳，墙凸外角采用半径0.07m、3 segments 的真实圆弧（变形前参数，随 global taper 映射）；内角与 L 凹角保持 sharp miter，墙上下水平边不圆，不由 cell boxes、独立墙段或满立面柱盒拼出轮廓。门窗为贯穿墙厚的真实洞口，具返回面 reveal；窗框为单个闭合环实体，门框为单个封闭 U 形实体而非叠盒，净洞与框材分开。每条墙 run 统一 bay 分配，冲突明确拒绝、不静默缩净洞。楼板每层一件连续整板、屋顶单件 `roof_main`，L 缺口不封空。全栋墙/板/框/玻璃共用同一随高度变化的 global taper 顶点映射，不是每件各自收分；尺寸参数为变形前值，变形后净孔、墙厚与包络按实际几何核验。「结构严谨」仅为模型几何契约，不签土木结构安全计算。 |
| SEA-WORKSHOP-R20 | 编辑器新建 `editor_new` 使用 `Recipe.authoring_defaults()`：`construction_mode=shell_v2`、clean（aging=0、damage=0、vegetation_density=0，无默认植物）、墙绑定 `wall_sun`。旧 `Recipe.defaults()` 与旧档缺模式字段仍为 `modular_v1`，保留旧样例、破损及原 slot 语义，不强转已存档、不批量改写。UI 必须显式区分「连续实体 · 工整模型」与「旧版拼装 · 配方兼容」。连续模式当前 `damage!=0` 明确拒绝；wrapper 对结构槽 `disabled:true`、结构 `excluded_slots` 与非零 offset 全部明确拒绝（含 frame/glass），不能用残留跳过代码或旧 metadata 声称支持断壳。旧 modular 有破损能力，但不是专业模型的新建默认。会话 patch/配方与catalog提交、`accept_loaded`、`new_document` 都须在写状态前做实际生成探针，失败原子拒绝并保留最后成功配方、catalog、历史与预览；未知组合不宣称支持。 |
| SEA-WORKSHOP-R21 | 连续槽边界为 `wall_shell_<floor>` 整层墙壳、`slab_<floor>` 整层板、`roof_main` 整屋顶、`frame_<facade>_<floor>_<ordinal>` 整孔框、同后缀 `glass_*` 独立玻璃；支持按整件导出静态模块与兼容 prefab 替换，不冒称旧 `lower_a` 等 partial slots 已映射到连续模式。替件仍需静态安全、族/轴向/pivot/实际包络校验，禁止缩放凑尺寸，失败原子拒绝；保留槽、配方与其他组件身份。Native2 分件例外须如实记录：连续结构板/屋顶采用 0.028m 实体倒角、3 segments、0.14m 出挑，是 formed_band 结构板而非平台装饰木板；洞口 0.02m chamfer / 1 segment，框 0.018m chamfer / 1 segment；墙凸外角为0.07m真实3段圆弧，内角/L凹角为锐miter且墙上下水平边不圆，不冒称全体墙边已圆角或所有部件均为 3 segments，不以参数标签或平滑法线假装实体倒角。 |
| SEA-WORKSHOP-R22 | 连续模式分层验收：`shell_geometry.gd` 对实际生成边执行闭合/定向 audit（基线映射前），装配层核对映射及替件后的实际 faces，闭合/定向无效的 prefab 明确拒绝，root 最终 quality 来自实际面校核而非仅警告；独立 QA 必须另取真实 mesh/碰撞 faces，按累计变换核对全局/统一坐标法线朝向、正体积、重复/退化面、边界与 nonmanifold、单连通实体/窗环、槽/prefab、Store 静态重载及 legacy，不凭生成器自报 quality 即签通过。统一 runner 入口新增 `workshop-shell`；矩形/L 形 1/3/5 层、逐层高与板厚覆盖、禁窗、Store 和 wall/frame/glass 实际整件替换分别留证。首跑为数值/静态专项，不代替真实 editor、性能或视觉；本轮用户结果以实际 model 大图及接缝/洞口/轮廓审阅为主，不反复以检查数量表功。preview 点选必须以 AABB 仅作粗筛、actual triangle ray 作最终命中，避免整层墙壳 AABB 抢选窗孔/玻璃，并在真实 editor 留断言证据。各批状态按实际 report 更新；不以数值/编辑器通过签完整 style、内角圆弧、墙上下水平边圆弧、drastic damage、复杂根系、stairs/navigation 或全楼可达。 |

## 接口与所有权

- `WorkshopRecipe`校验规范化配方并返回副本；`WorkshopCatalog`只读定义、兼容校验与指纹。
- `WorkshopGenerator`将配方展开为稳定slot与最终结构；网格、碰撞与生长表面同源。
- `WorkshopSession`唯一写编辑草稿与撤销栈；UI调用命令、查询，不访问Economy/Main/存档。
- `WorkshopStore`只写限定候选根，返回每栋独立文件和登记状态，不直接写工程账本。
- `WorkshopHost`处理暂停/模态生命周期，依赖由装配注入。正式场景仍由SEA-WORLD拥有，资源正式登记由SEA-ASSET拥有。

## 第一版交付限制

通用楼房不是任意雕塑建筑。复杂根系贴墙、实时破坏、任意旧网格参数识别、整城生成和后台正式写账本不纳入V1。组件允许后续换装；程序构件要明确为原生参数化来源，不冒称已完成Blender制作/02b链。

## 2026-11-10 V1 实施落点与未完成边界

本节只补当前工程事实，不删除或收窄上面的用户目标。当前实现由以下边界组成：

- 工坊代码为 `godot/src/workshop/{recipe,catalog,generator,mesh_builder,session,store,preview,panel,host}.gd`，机器数据为 `godot/data/workshop/{standards_v1,catalog_v1,palette_cells_v1}.json`，独立入口场景为 `godot/scenes/tools/building_workshop.tscn`。暂停菜单到楼房工坊是 Main/menu 的薄接线，编辑器不拥有玩家建造布局、库存、世界时间、主存档或正式场景摆位。
- 配方已支持矩形与组合 L 形、反复打开、撤销/重做、逐层覆盖、逐立面覆盖、槽位稳定 ID 与兼容组件替换；当前样例和默认落点为 3-floor。校验上限允许最多 8-floor，但宽深、开间、门窗、节点与三角面预算共同限制可用组合，不能把“上限 8”写成“所有 8 层尺寸都可用”。
- aging 与 damage 分开取值且使用独立 seed；damage 可受控删除窗、墙或屋顶片段，并由同源槽几何/碰撞表达缺口。四类程序植物为 shrub、moss、vine、tree，每类支持 small/medium/large，并按屋顶、外檐等语义区域布置。复杂根系贴墙和墙面刷苔不属于当前能力，不宣称全能植物生成。
- `spatial_profile` 只有 `above_water`、`scenic_underwater`、`dive_static` 三档。生成器按构件分件输出静态 concave/简化碰撞声明；门洞、院落与破口保留真实开口。`walk_surfaces` 与 `water_blockers` 只是候选产物的局部声明，不等于正式世界或导航自动接入；没有 stairs 时不签署整楼可达。
- 共享色板使用真实 UV，8px safe inset 由 `palette_cells_v1.json` 记录。原生参数构件使用真实圆角；默认 `bevel_width=0.06` 是 V1 简化档，标准文件状态为 `partial_source_style`，不等于完成美术终验，也不等于完整实现项目 Skill 语法（例如分件 rho 最长轴等尚未完整落地）。
- 每栋楼的候选导出固定为 `user://building_workshop/<building_id>/revision_NNNN/`，包含 `building.recipe.json`、`building.tscn`、`catalog_snapshot.json`、`candidate_manifest.json`、`ledger.json` 五件；临时目录重载验证通过后提交，历史 revision 不覆盖。候选登记与正式 SEA-ASSET 主记录分离。

## 当前实施状态对照

| 条款 | V1 当前状态 | 后续 / 未签边界 |
|---|---|---|
| R01–R02 | 已有暂停菜单入口、独立预览、暂停恢复、配方会话、打开/新建/另存 ID/导出/撤销/重做/取消反馈 | Main 集成专项仍需主线程修正测试假设后重跑，不能以当前失败批次签全通过 |
| R03–R04 | 已读版本化 standards/catalog，支持矩形/L 形、逐层/逐立面覆盖、稳定 slot 与三 seed | 非所有 8-floor 尺寸组合都可用；完整 Skill 风格语法仍 pending |
| R05–R07 | 已实现 aging/damage、真实缺口与局部碰撞、四类植物及三种体量/语义区域 | 复杂根系、墙面刷苔、实时倒塌和更广泛植物终验 pending |
| R08–R11 | 已导出无脚本静态 TSCN、分件节点、独立五件 revision、重载校验与不覆盖历史 | 正式运行资源接入、正式主场景摆位、性能与用户美术验收 pending |
| R09 | 三种空间 profile 与局部 walk/water 声明已实现 | 不自动接入正式世界/导航；无 stairs 不承诺全楼可达 |
| R12 | `workshop-rules`、`workshop-deep`、`visual-workshop`、`workshop-samples` 的历史专项证据保留 | R13–R18 的编辑器专项已另行验收；全库contracts仍受其他功能hash与SEA-ASSET条款问题影响，不把局部通过扩写成全库通过 |

`partial_source_style`、`runtime_path=null`、候选状态和所有 pending 项都是有意保留的工程状态，不应在后续文档中压成“完整美术制作”或“正式世界已接入”。

## 2026-11-10 22:45 编辑器目标覆盖与当前体系

上方“V1实施落点/当前实施状态对照”记录早先运行版阶段事实，尤其 `user://building_workshop/`、暂停/输入恢复和曾待重跑的Main集成；不作为编辑器当前保存根或当前验收结论。现行主目标以目标段、R01及R13–R18为准，运行版保留，不删除其历史。

- 编辑器实际职责目录为 `godot/addons/building_workshop/`：`plugin.cfg`、`plugin.gd`、`editor_screen.gd`、`editor_preview.gd`、`editor_store.gd`、`catalog_adapter.gd`、`editor_verification.gd`。主屏是Control、预览是独立SubViewportContainer/World3D；不是运行版CanvasLayer改名。原 `godot/src/workshop/{panel,host,preview}.gd` 保持运行版职责，六个共享内核 `recipe/catalog/generator/mesh_builder/session/store.gd` 已有 `@tool`。
- EditorStore继承共享Store，仅适配编辑器允许根、静态替件校验和编辑器来源manifest；默认根为 `res://scenes/workshop_buildings/`，验收端口另允许 `res://outputs/workshop_editor/`，不等于允许任意磁盘写入。生产工程保留 `material_guard`、`proton_scatter`、`terrain_3d` 并追加工坊；隔离验收副本只启用工坊，不能反向覆盖生产enabled列表。
- building保存与烘焙合为同一次五件revision提交；“独立编辑”由recipe+catalog snapshot承载，“静态使用”由无重建脚本的building.tscn承载。单槽导出是独立候选两件模块，不改变原楼配方身份与已有正式来源。替件后局部componentID可以变化，原组件定义与其他槽不跟随变化；不承诺任意尺寸替件自动拉伸适配。
- 候选 `ledger.json` 不是仓库资产账本；用户确认使用后才可经register工具正式登记。`tools/workshop/register_samples.py` 是当前两样例专用工具，不宣称已有任意楼/任意模块自动登记服务。既有两个sample AssetID与 `runtime_path=null` 保留，不新建主记录、不改原source/timing身份。
- Native程序构件仍 `partial_source_style`，不是完整美术Skill/Blender/02b链验收；复杂根系贴墙、墙面刷苔、楼梯与正式导航、全楼可达仍pending/未支持，不随编辑器入口切换升级。

### 验收证据分域

已读取 `D:/projects/sea-work/verification/20261110-224023-workshop-game-acceptance-00ec43/report.json`：`workshop-integration`、`visual-workshop` 均 `exit_code=0`、`passed=true`、`unexpected_errors=[]`；integration日志为25 checks/0 failures。这是运行版正式Main集成与真实运行版渲染的通过证据，只追加解释，不删除先前25/3失败历史。

编辑器真实runner名称为 `editor-workshop`，最新证据 `D:/projects/sea-work/verification/20261111-003009-editor-workshop-deliver-4b9df3/report.json` 为 exit0/passed=true；日志为327 checks/0 failures，inner报告位于该隔离项目 `project/outputs/workshop_editor_report.json`，enginehint=true、is_playing=false、scene_unchanged=true、root_paused_unchanged=true。真实 `--editor` 无Main/Autoload且仅启用工坊插件；四张真实截图（含 `damaged_l_plants`）通过布局断言并已审阅。`D:/projects/sea-work/building_workshop/editor_v001/delivery_report.json` 已重跑为 passed=true、audit_passed=true、checks_count=572、failed_count=0；其 `visual_acceptance=not_signed` 保持，不把审计通过扩写为美术终验。完整插件卸载重载/跨进程恢复、用户美术与性能另列pending。完整体系、目录、操作流程与验收矩阵见 [编辑器开发记录](../../development/2026-11-10_building_workshop_editor.md)。

## 2026-11-11 连续实体 model core 当前覆盖

本节承接 R19–R22，优先于旧 V1/编辑器章节对「当前默认」或「最新验收」的表述；旧 327/0 与 572/0 原文保留为历史，不能复用成本轮连续模型或真实 editor 的通过结论。

- 几何源为 `godot/src/workshop/shell_geometry.gd`，装配源为 `godot/src/workshop/shell_generator.gd`；后者版本 `sea_workshop_continuous_shell_v2`，负责静态节点、真实三角面碰撞与整件 prefab。`recipe.gd` 分离 authoring/legacy defaults，`generator.gd` 按 construction_mode 分支，`session.gd` 提交前做原子生成探针，`store.gd` 从实际生成根读取 generator version，并在 manifest 记录 mode/model_quality；不把 shell 产物误标为旧生成器。
- 当前墙凸外角已补0.07m真实3段圆弧；内角/L凹角仍sharp miter，墙上下水平边不圆。洞口0.02m与框0.018m仍各为单段chamfer，结构板0.028m三段与0.14m出挑例外不变。`shell_generator.gd` 对最终实际faces闭合/定向不合格的整件替换明确拒绝，再写root最终quality，不是仅警告后成功。
- `editor_screen.gd` 有显式模式和新建默认；`editor_preview.gd` 点选以box粗筛再actual triangle ray，避免整层AABB抢窗；`editor_verification.gd` 已在矩形/L实际窗孔验证玻璃命中优先。结构槽disabled:true/excluded/非零offset由wrapper全部拒绝，session patch/accept_loaded/new_document等入口均probe后原子提交；不再支持整件结构跳过。旧 `lower_a` 等partial slot不冒称已映射。
- 历史一行：023726首跑与025025中间模型均为shell 552/0；025833增强专项716/21失败来自测试在clamped taper的y=0两侧插值截面并非精确参数截面，已改用实际顶环核验，未放宽阈值；025806 editor 1489/4为输出限定根错误与脚本重复调用shell samples，修复后另跑，不反改旧结果。
- 已读取最终几何批次 `D:/projects/sea-work/verification/20261111-031500-workshop-continuous-verified-58a3bd/report.json`：workshop-shell、workshop-rules、workshop-deep均exit0/passed=true、unexpected_errors=[]；同批 `project/outputs/workshop_shell_report.json` 为716 checks/0 failures。覆盖矩形/L的1/3/5层、逐层高/板厚、禁窗、真实凸角顶环/法线/正体积/闭合、原子拒绝、Store、wall/frame/glass整件prefab与legacy；仅签该批被测组合。
- 已读取最新真实 editor `D:/projects/sea-work/verification/20261111-031449-editor-continuous-delivery-6bf812/report.json`：editor-workshop为real、exit0/passed=true、unexpected_errors=[]；同批 `project/outputs/workshop_editor_report.json` 为992项、failures=[]，包含矩形/L「点击洞口不先选中整层AABB」实际断言，enginehint=true/is_playing=false、scene/root paused不变。隔离 `project/outputs/` 的 `workshop_shell_model_rect.png`、`workshop_shell_model_front.png`、`workshop_shell_model_l.png` 已存在；三张交付模型大图现已由主线程目检：连续墙面、无棋盘拼格、圆外角高光、真实开口与板墙平齐可见；结论为「工整几何的基础模型已改，整体造型仍简洁，不冒称丰富美术终验」。
- 已读取交付汇总 `D:/projects/sea-work/building_workshop/continuous_v002/outputs/continuous_delivery_report.json`：passed=true、checks_count=1348、failed_count=0；其核对的实际editor为992/0、geometry为716/0，非重复调用两次shell的1481中间计数。汇总脚本自身不执行引擎，1348不是引擎专项合计；完整style、内角圆弧、墙上下水平边圆弧、drastic damage、复杂根系、楼梯/正式导航/全楼可达及性能继续未签，4D/受力与土木结构安全未做，不新增stage整屋blend承诺。
- 同交付 `outputs/continuous_candidates.zip` 与三张1400×1100模型图、五张1600×1000 continuous编辑器图已产生。ZIP只含两楼JSON/TSCN五件及JSON说明，依赖未打包的生产公共色板 `res://assets/textures/shared/sea_cabin_timber_8x8_512.png`；不是Blender/GLB或可脱离公共资源的完整资产包。`outputs/model_comparison.png` 只对真实旧完整UI截图与新模型图等比缩放并列，无AI补图、无猜裁剪；不等条件，不用于美术分数比较。

### 当前可用入口与候选文件

打开Godot编辑器顶部「楼房工坊」→「新建」，新文档默认为连续实体；启动/恢复不会强制覆盖旧草稿或将旧modular档转换。文件页「刷新」后可按下列两个building_id打开配方。选择 `wall_shell_<floor>` 导出的是整层墙壳，不是旧 `lower_a` 下方tiny局部槽。

- 矩形12×9m、3层：`godot/scenes/workshop_buildings/shell_rect_1794338160_71001671/revision_0001/`。
- L形12×12m、3层：`godot/scenes/workshop_buildings/shell_l_1794338160_71001671/revision_0001/`。

每目录五件为 `building.recipe.json`、`catalog_snapshot.json`、`building.tscn`、`candidate_manifest.json`、`ledger.json`；manifest完整路径分别为 `D:/projects/sea/godot/scenes/workshop_buildings/shell_rect_1794338160_71001671/revision_0001/candidate_manifest.json` 与 `D:/projects/sea/godot/scenes/workshop_buildings/shell_l_1794338160_71001671/revision_0001/candidate_manifest.json`。逐文件path/hash列于交付report的bundles/candidate_installations；状态为candidate_only / exported_pending_project_registration，formal_registration=pending，无新增正式注册。

全库contracts_sync/check均已实跑exit1：`D:/projects/sea-work/building_workshop/continuous_v002/contracts_sync.log` 为76 issues，`contracts_check.log` 为78 issues；两者均8 source hash drift、67 runtime hash drift，另有SEA-ASSET条款账本问题；check还报SEA-WORKSHOP主表状态差异及派生索引过期。因全库失败未成功sync主表，保持partial，不批量改hash、不修其他功能SEA-ASSET-R67、不改GDD/registry。交付report的whole_project_contracts=not_provided仅表示汇总脚本未纳入该证据，不表示全库检查未执行。

交付以真实模型大图与局部结构为主，不拿UI截图或历史测试数字替代professional model判断。详细五件hash、图像、使用步骤与验收边界见 [连续实体开发记录](../../development/2026-11-11_workshop_continuous_shell.md)。

## 2026-11-11 建筑结构多变体、窗构造与屋顶边界追加

本节承接 GDD 导航中的 SEA-WORKSHOP，并遵循 [SEA-ASSET-R68/R68a](../asset/spec.md#2026-11-10-参数楼房工坊候选资产登记规则) 的候选资产与原生参数化来源边界。以下 R23–R27 只描述建筑几何、配方、编辑器范围和候选交付契约；不把架构专项通过扩写成完整 editor、视觉、美术、性能、导航、建筑承载或防护规范通过。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-WORKSHOP-R23 | `architecture` 是 schema version 1 的可选增量对象。支持 `rectangle`、`l`、`t`、`u` 平面变体；`plan.wing_x` / `wing_z` 控制翼部比例，`setback_start` / `setback_step` 控制从指定层起的上层轮廓收缩。每层按收缩后实际轮廓生成墙壳；下层与上层接口由连续结构板封合并形成可识别露台面，L/T/U 缺口不填实。`Recipe.defaults()` 和缺少 `architecture` 的旧配方保持旧 modular_v1 解释及原 fingerprint；`Recipe.authoring_defaults()` 才写入规范化 architecture，默认新建仍为 shell_v2。旧 modular 配方存在非默认 architecture 时必须拒绝，不能静默忽略。 |
| SEA-WORKSHOP-R24 | 窗构造通过 `Config.window_settings` 合成，覆盖优先级为 global → floor → facade → single；旧配方的基础窗宽/高/窗台只作为基础值，局部覆盖不改变未覆盖字段。支持 `enabled`、`fixed` / `casement_left` / `casement_right` / `awning`，活动窗静态开角为0..80度，fixed 的开角必须为0；框宽、框深、玻璃厚度、recess、窗沿启用、窗沿 projection/thickness/extension 均为独立参数。`enabled=false` 封回实墙而不删除稳定 opening ordinal/id，编辑器保留选择与恢复入口；不得把单窗输入写入 global。 |
| SEA-WORKSHOP-R25 | 窗尺寸验证必须以活动扇/玻璃的完整旋转扫掠包络核验开间、楼板、洞口倒角安全区、墙厚和相邻洞口，并登记同层包络冲突；开角、框/玻璃装配间隙、recess、窗沿与楼板冲突或相邻包络重叠时原子拒绝，不 silent clamp、不静默缩小净洞或移位。成功几何保留真实 reveal、独立闭合框、活动扇/玻璃实体和窗沿板；应用失败保留上一份配方、历史与预览。 |
| SEA-WORKSHOP-R26 | 屋顶边界支持 `none`、`parapet`、`railing`、`mixed`。女儿墙、压顶和栏杆均使用实际轮廓内收后的路径；上层墙轮廓邻接处压制不应外露的边界，接口板封住下层形成的露台仍按实际 surface 处理。`mixed` 为栏杆立在女儿墙压顶之上，不穿插女儿墙；posts 与 pickets 分开建模，竖杆/横杆与立柱之间保持3mm clearance。总高、墙厚、cap 厚度/外挑、立柱间距、竖杆节距和杆宽均可配。`corner_end_cut=0.1m` 仅用于端部留间隔，不能宣称完整 guardrail safety；不签建筑承载或人群防护规范。 |
| SEA-WORKSHOP-R27 | 屋顶边 `gap_center` / `gap_width` 仅对 `roof_main` 的 edge override 生效，不自动复用到每个 terrace；边数量按真实轮廓动态为4/6/8。gap 必须通过长度边界、两端各0.15m margin及角部约束，未知/非法/越角的 gap 直接拒绝，不 clip；屋顶及窗构造均经 `shell_geometry` / `shell_generator` 的实际几何路径生成。新增 `architecture_config.gd`、`shell_window_geometry.gd`、`roof_edge_geometry.gd` 三个 helper 只作为原生参数化工程来源，不建立正式 Asset registry 主记录。 |

R23–R27 的编辑器门窗范围明确为全局、当前楼层、当前立面、当前窗四档；切换范围前若有未应用输入必须阻止切换，清除覆盖后恢复继承。架构专项的静态/实际验证与真实 editor 交互、五栋样楼候选保存、交付汇总和目视美术验收分域记录；未读到的本轮产物只记 pending，不提前签通过。楼梯导航、正式世界接入、全楼可达、建筑承载与防护规范不在本轮签署范围。

## 2026-11-11 工整模型 v3 · 立面构成与转角连续性追加

本节承接 GDD 导航中的 SEA-WORKSHOP，遵循 [SEA-ASSET-R68/R68a](../asset/spec.md#2026-11-10-参数楼房工坊候选资产登记规则) 的候选资产与原生参数化来源边界。R28–R40 只描述立面构成、转角接合、入口构造、退台围护默认、作者默认值与编辑器局部基线契约；不把几何修正扩写成完整艺术终验、建筑承载或防护规范通过。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-WORKSHOP-R28 | 立面必须读成"基座—墙身—檐口"三段，不得出现两种材质同面的水平亮带。结构板外轮廓内收（`SLAB_BAND` 取负值，当前30mm）藏进墙壳；板缘由**与墙同材质**的层间束带包住，束带只比墙皮凸出4mm，形成一道细阴影线而非彩色腰线。整栋一圈勒脚环落在 `y∈[0, 0.42]`，外凸60mm、内咬8mm，用环形实体生成以免封底堵门。墙与板的重叠量 `INSET` 只用于防浮点缝，上限2mm。 |
| SEA-WORKSHOP-R29 | 所有贴墙附件（勒脚、层间束带、压顶及后续同类构件）的外轮廓必须复用墙壳同源的圆角采段规则：凸外角按 `OUTER_CORNER_RADIUS` 圆弧采段、凹角保持 sharp miter。不得以直角 miter 近似贴墙轮廓——墙角会与墙壳圆弧错开成一条贯穿楼层的竖缝。环形实体的倒角只收Y方向，禁止对已圆弧化的XZ轮廓再次 offset。 |
| SEA-WORKSHOP-R30 | 入口雨棚为独立平板，背面必须咬入墙体（不得从墙皮外侧凭空起始留缝），正面挑出并超出门洞两侧；至少两根落地柱，柱脚落到 `y=0`，柱截面不小于120mm。不生成无支撑的悬挑构件，雨棚不与门框、窗框或相邻窗洞穿插；超出净层高时明确跳过而不是压薄。 |
| SEA-WORKSHOP-R31 | 退台等非 `roof_main` 的 surface 默认不生成屋顶边界附属结构（`none`），需要围护时在 `edge_overrides` 按 surface 显式开启。理由：把 `roof_main` 的模式套到逐段截断的退台边会生成锯齿状碎墙块。`roof_edge_quality.contacts` 顶层为各 surface contacts 的并集，编辑器与文档读同一处。 |
| SEA-WORKSHOP-R32 | `Recipe.authoring_defaults()` 承载新建住宅比例与立面默认：层高3.6m、板厚0.18m、窗1.5×1.9m、窗台0.95m、门1.6×2.4m，并默认开启窗台板与女儿墙（`roof.mode=parapet`、高0.9m）。`Recipe.defaults()` 与缺字段旧配方保持原值与原 fingerprint，不迁移存档。 |
| SEA-WORKSHOP-R33 | 编辑器的局部输入基线（楼层/立面/槽位/窗构造）必须在控件按 session 重建之后重新捕获，禁止把上一份文档的控件值当作基线。存在未应用输入时，失败原因必须列出具体控件键，不得只给通用一句话；未应用输入不得静默提交为已应用。 |
| SEA-WORKSHOP-R34 | 门洞必须生成实际门扇，不得留成能看穿室内的墙洞。门扇为单块闭合实体，落在门框净尺寸内、四周留不小于2mm装配缝，从墙外皮退进不小于50mm；门扇厚度不小于40mm、倒角不大于5mm。不生成门把手、玻璃视窗或双开门分缝——无构造依据的附件一律不做。门扇与雨棚柱、勒脚、相邻窗框不得穿插。 |
| SEA-WORKSHOP-R35 | `architecture.form` 是可选增量对象，提供三档形体作用域：`structure`（整楼收分，写入 `taper`）、`opening`（窗口/门洞梯形化）、`accessory`（配件变径与自由边收窄）。每档给 `min` / `max` 区间与 `sign`，由 `seed` 经稳定散列落值；同一 seed 与区间必须得到同一落值，几何可复现。区间须落在语法边界内（structure 0.01–0.10、opening 0.01–0.04、accessory 0.01–0.08），`max` 不得小于 `min`。`enabled=false` 时不落值、不改 `taper`、不生成任何锥度，退化为正交模型。 |
| SEA-WORKSHOP-R36 | 结构族收分同时受两个上限约束，最终取更严的一个：①墙倾角 `taper_max = tan(θ)·H_total / max(W_base, D_base)`，θ 由 `form.max_tilt_deg` 给出，可调范围 1–15°、默认 8°（SKILL 的 4° 是基线建议值，不再写死）；②`taper` 字段自身合法范围 0–0.10，是硬上限。超限必须明确拒绝，并指明是哪一重在拦：被倾角拦就给出该体量的可用上限并提示可调大 `max_tilt_deg`；被 `taper` 字段拦就直说 0.10 是字段硬上限、调倾角无用。禁止静默压小。`structure.sign` 只允许 positive——不做上大下小的墙。 |
| SEA-WORKSHOP-R37 | 形体变形必须贯穿到实际几何而非只改参数：洞口梯形后，墙面补角、返回面、窗框、玻璃、活动扇、门扇必须共用同一 `pull`（= rho × 净宽 / 2）派生，任一处不跟随会造成洞口肩部破面。贴墙附件（勒脚、层间束带、雨棚板）只允许收自由边，与墙咬合的边不得收缩，否则构件脱离宿主。配件局部变径只施加于自由竖立件（雨棚柱等）。 |
| SEA-WORKSHOP-R38 | 形体幅度必须可调到肉眼可见，不得停留在「开了等于没开」。语法区间取 structure 0.01–0.10、opening 0.01–0.12、accessory 0.01–0.18；新建默认 structure 3–6%、opening 3–6%、accessory 4–10%，在 12×9m 三层楼（8° 下可用收分 0.126）体量上可落到 5% 级别。幅度上限是**语法边界**而非审美建议：是否好看由档位（SF-A/B/C）与用户的区间选择决定。 |
| SEA-WORKSHOP-R39 | 窗洞可逐洞独立取号：`form.opening.sign` 取 `positive`（全部上窄下宽）、`negative`（全部上宽下窄）、`mixed`（逐列独立取号）。`mixed` 的取号键是「立面_序号」**不含楼层**，同一竖列上下各层必须同向——逐片掷骰子会把立面读成噪点，而不是手作感。`structure` 与 `accessory` 一律不允许 `mixed`。 |
| SEA-WORKSHOP-R40 | 上宽下窄（`pull < 0`）与上窄下宽共用同一套几何派生：洞口环、返回面、窗框、玻璃、活动扇、门扇全部由同一个 `pull` 派生，`pull` 允许为负。洞口在 XZ 的挖空范围与墙垛/开间校验必须用**最大外廓** `_hole_bounds`（下沿矩形与上沿梯形取并集），不能只用下沿矩形：否则上沿扩出去的部分会被网格重新补成墙，且相邻洞口可能在下沿以外相撞。返回面与墙面补角在 `pull > 0` 时补上部三角、`pull < 0` 时补下部三角，两条斜边与返回面共用端点。 |

## 2026-11-12 承重柱与楼层腰线追加

本节承接 R35–R40 的形体与洞口体系，遵循 [SEA-ASSET-R68/R68a](../asset/spec.md#2026-11-10-参数楼房工坊候选资产登记规则) 的候选资产与原生参数化来源边界。R41–R46 只描述立面上的竖向承重柱、楼层腰线与其编辑器/替换契约；**不签结构承载**——柱是立面构造件，不是受力构件，不做荷载计算、不做抗震或土木结构验算。

| 条款 ID | 规则与验收 |
|---|---|
| SEA-WORKSHOP-R41 | `architecture.pilaster` 是 schema version 1 的可选增量对象：`enabled`、`corner`（转角柱）、`middle`（窗间柱）、`width` 0.14–0.90m、`projection` 0.02–0.50m、`bite` 0.02–0.24m、`bevel` 0.003–0.06m。柱必须咬入墙体（`bite > 0`，不允许只贴在墙皮上），且 `projection + bite` 必须大于 2.5×`bevel`，否则柱没有实体厚度。`corner` 与 `middle` 各自独立开关，只开一种时另一种一件都不生成。柱压到洞口时必须整体拒绝并指明压到哪个洞口，不得裁短柱、移位或静默跳过该柱。只在 `shell_v2` 连续实体模式生效。`Recipe.defaults()` 保持关闭（不改既有配方外观），`Recipe.authoring_defaults()` 默认开启。 |
| SEA-WORKSHOP-R42 | 转角柱必须是**单件** L 形八边形：沿相邻两个立面各伸出一条腿、外角按墙同源圆角采段倒角。禁止用两根方块柱在角上叠加——叠件在贴墙轮廓上会留一条贯穿楼层的竖缝，且不是单连通件。窗间柱为单件方柱，立在相邻洞口之间的墙垛中心；墙垛放不下该柱宽时拒绝并报出该开间。每根柱各自成件（`pilaster_<floor>_c<n>` / `pilaster_<floor>_m<n>`），一块网格只能装一个 part，不许多块几何塞进同一件。 |
| SEA-WORKSHOP-R43 | `architecture.band` 是可选增量对象：`enabled`、`projection` 0.01–0.32m、`thickness` 0.08–0.80m、`bevel` 0.003–0.05m，`thickness` 必须大于 2.5×`bevel`。腰线落在楼层结构板位置，**只在 `0..floors-2` 层生成**：顶层没有上层楼板，不生成腰线。有柱时按柱分段（每段一件 `band_<floor>_<i>`，段端让开柱身 0.01m），无柱时整圈一个环件（`band_<floor>_ring`）。 |
| SEA-WORKSHOP-R44 | 腰线必须收在柱后：实际凸出量 `projection = min(band.projection, max(pilaster.projection - 0.04, 0.03))`。理由是实测出来的——腰线只要比柱多出 8mm，转角处就会多出一圈悬挑薄片，近景读成一个浮空小块。这是**派生约束**不是校验失败，因此不拒绝配方；但编辑器读数必须显示实际凸出量并注明「收在柱后」，不得只显示用户输入值。 |
| SEA-WORKSHOP-R45 | 柱与腰线的组件替换契约各自独立：`pilaster_` → `pillar_cozy`（family=`pillar`）、`band_` → `band_cozy`（family=`slab`），不得复用 `wall_sun`。同材质不等于同替换契约——复用墙组件会在替换墙面时把柱与腰线一起换掉，第二次保存因模块包络失配被拒。 |
| SEA-WORKSHOP-R46 | 编辑器「构架」页提供柱开关 / 角柱 / 窗间柱 / 柱宽 / 柱凸出 / 咬入，腰线开关 / 腰线凸出 / 腰线厚度，以及一个「应用构架」按钮；两开关互不连坐（关柱后腰线保留）。应用时必须先把控件值并进 `architecture` 再提交：`_architecture_snapshot()` 读的是 session 里的旧配方，直接提交它等于把刚拨的数值原样丢掉（v4 实测 8 项验收全挂在这一条上）。非 `shell_v2` 模式明确拒绝构架应用。 |

构架件与形体件可以同时开启：形体只收结构、洞口与自由端配件，柱宽/柱凸出/腰线厚度按用户值原样使用，不做额外的锥度补偿。验收口径为「件数与开关一致、逐层等量、顶层无腰线、每件单连通闭合、腰线比柱更靠墙」。建筑承载、柱距结构计算、柱头柱础装饰、腰线分缝均未做，也不在本轮签署范围内。

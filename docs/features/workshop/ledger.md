# SEA-WORKSHOP · 参数楼房工坊 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-workshop) · [功能文档](spec.md)

## 登记头

```json
{
  "feature_id": "SEA-WORKSHOP",
  "status": "partial",
  "owner": "WorkshopSession / WorkshopStore；正式资产登记归SEA-ASSET，正式摆位归SEA-WORLD",
  "code_paths": [
    "godot/src/workshop/recipe.gd",
    "godot/src/workshop/catalog.gd",
    "godot/src/workshop/generator.gd",
    "godot/src/workshop/mesh_builder.gd",
    "godot/src/workshop/session.gd",
    "godot/src/workshop/store.gd",
    "godot/src/workshop/preview.gd",
    "godot/src/workshop/panel.gd",
    "godot/src/workshop/host.gd",
    "godot/src/bootstrap/main.gd",
    "godot/src/ui/island_menu.gd",
    "godot/data/workshop/standards_v1.json",
    "godot/data/workshop/catalog_v1.json",
    "godot/data/workshop/palette_cells_v1.json",
    "godot/scenes/tools/building_workshop.tscn",
    "godot/addons/building_workshop/plugin.cfg",
    "godot/addons/building_workshop/plugin.gd",
    "godot/addons/building_workshop/editor_screen.gd",
    "godot/addons/building_workshop/editor_preview.gd",
    "godot/addons/building_workshop/editor_store.gd",
    "godot/addons/building_workshop/catalog_adapter.gd",
    "godot/addons/building_workshop/editor_verification.gd",
    "godot/src/workshop/shell_geometry.gd",
    "godot/src/workshop/shell_generator.gd"
  ],
  "verification": [
    "workshop-rules",
    "workshop-deep",
    "visual-workshop",
    "workshop-samples",
    "workshop-integration",
    "editor-workshop",
    "workshop-shell"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-WORKSHOP-R01 | planned | 游戏内入口与暂停/输入生命周期待实现实测 |
| SEA-WORKSHOP-R02 | planned | 每楼配方、校验、另存与历史待实现实测 |
| SEA-WORKSHOP-R03 | planned | 规范机器表与真实倒角待实现实测 |
| SEA-WORKSHOP-R04 | planned | 矩形/L形、局部覆盖与确定性待实现实测 |
| SEA-WORKSHOP-R05 | planned | 老化、结构缺损与同源碰撞待实现实测 |
| SEA-WORKSHOP-R06 | planned | 稳定组件catalog与替换契约待实现实测 |
| SEA-WORKSHOP-R07 | planned | 语义生长区域与随机/锁定待实现实测 |
| SEA-WORKSHOP-R08 | planned | 静态场景打包与独立重载待实现实测 |
| SEA-WORKSHOP-R09 | planned | 水域职责与分段空间产物待实现实测 |
| SEA-WORKSHOP-R10 | planned | 独立文件、候选登记与正式路由待实现实测 |
| SEA-WORKSHOP-R11 | planned | 版本化目录、临时写入/失败保护待实现实测 |
| SEA-WORKSHOP-R12 | planned | runner专项、真实渲染、集成与未验边界待实际回填 |

> 上表保留初始登记快照；以下 `2026-11-10 V1 实施回填` 才是本轮按当前工程事实更新的实施状态，不删除历史目标。

## 2026-11-10 V1 实施回填

本节承接上方设计条款，不删除历史目标；这是早期运行版阶段的历史记录，保留当时“已实现但仍待主线程/产品验收”的状态，不把专项通过扩大成全工程通过。

| 对应设计条款 | 当前实施状态 | 证据 / 待核验 |
|---|---|---|
| SEA-WORKSHOP-R01 | implemented_pending_acceptance；暂停菜单 → Main → WorkshopHost → WorkshopPanel 已接入；面板自建 SubViewport，打开冻结世界并恢复原暂停值 | `godot/src/workshop/host.gd`、`panel.gd`、`preview.gd`、`godot/src/bootstrap/main.gd`、`godot/src/ui/island_menu.gd`；`visual-workshop` 已通过；正式 Main 集成修正后待重跑 |
| SEA-WORKSHOP-R02 | implemented_pending_acceptance；recipe/schema 校验、单楼 building_id、打开/新建/另存 ID/导出、撤销/重做、取消与未保存退出反馈已实现 | `recipe.gd`、`session.gd`、`store.gd`、`panel.gd`；`workshop-rules`、`workshop-deep` 通过；主集成 pending |
| SEA-WORKSHOP-R03 | implemented_pending_acceptance；standards_v1 机器表、默认 5.1/0.2/0.5、净高与门窗洞校验、默认三段倒角已实现 | `godot/data/workshop/standards_v1.json`、`recipe.gd`、`generator.gd`；状态明确为 `partial_source_style`，不签完整 Skill 风格或美术终验 |
| SEA-WORKSHOP-R04 | implemented_pending_acceptance；rectangle/L、逐层/逐立面覆盖、稳定 slot_id、组件替换、structure/damage/vegetation 独立 seed 与确定性已覆盖 | `session.gd`、`generator.gd`、`catalog_v1.json`；3-floor 样例导出通过；8-floor 只是上限，受尺寸和预算限制 |
| SEA-WORKSHOP-R05 | implemented_pending_acceptance；aging 与 damage 分离，破窗/断墙/屋顶片段删除与同源局部碰撞、门洞/院落真实开口已实现 | `generator.gd`、`mesh_builder.gd`；`workshop-deep` 与样例专项通过；实时刚体倒塌仍不在 V1 |
| SEA-WORKSHOP-R06 | implemented_pending_acceptance；catalog 稳定组件 ID、版本/接口/原点/轴向/尺寸/replaceable、槽族兼容拒绝与静态 prefab 白名单已实现 | `catalog.gd`、`catalog_v1.json`、`session.gd`；catalog 内部组件 ID 不作为正式独立 Asset 主记录 |
| SEA-WORKSHOP-R07 | implemented_pending_acceptance；shrub/moss/vine/tree 四类程序植物，small/medium/large、屋顶/外檐语义区域、密度与锁定/排除已实现 | `generator.gd`、`panel.gd`、`catalog_v1.json`；复杂根系与墙面刷苔不支持，不冒称全能植物系统 |
| SEA-WORKSHOP-R08 | implemented_pending_acceptance；导出为无脚本静态 TSCN，按构件/材质分块，植物保留独立实例，导出后静态重载比对通过 | `store.gd`；`workshop-rules`、`workshop-deep`、`workshop-samples` 通过 |
| SEA-WORKSHOP-R09 | implemented_pending_acceptance；`above_water`、`scenic_underwater`、`dive_static` 三 profile 与分件静态 concave/局部空间声明已实现 | `standards_v1.json`、`generator.gd`、候选 manifest；walk/water 仅局部声明，不等于正式世界/导航接入；无 stairs 不签全楼可达 |
| SEA-WORKSHOP-R10 | implemented_pending_acceptance；每楼五件候选文件、hash、generator/catalog 信息与候选 ledger 已输出；正式资产由 SEA-ASSET 唯一路由 | 两个正式样例 AssetID：`SEA-SCENE-WORKSHOP-SAMPLE-001`、`SEA-SCENE-WORKSHOP-SAMPLE-002`；工程外 manifest 与源索引已实际回链，runtime_path 为 null |
| SEA-WORKSHOP-R11 | implemented_pending_acceptance；临时目录写入、静态重载、失败清理、`revision_NNNN` 不覆盖历史、路径段限制已实现 | `store.gd`；样例 revision_0001 五件文件存在；用户目录与测试输出隔离规则已实现 |
| SEA-WORKSHOP-R12 | partial；规则/深度/视觉/样例专项均有 exit 0 / passed true，但该历史正式 Main 集成批次曾为25 checks、3 failures，失败来自测试错误假定 `LineEdit Ctrl+Z` 不改文本 | `D:/projects/sea-work/verification/20261110-212901-workshop-core-roundtrip-9e6e3c/report.json`：rules/deep 0；`D:/projects/sea-work/verification/20261110-221503-workshop-palette-ui-final-3030ca/report.json`：visual 104/0、samples 45/0；后续运行版与编辑器证据另行记录，旧批次不反改 |

### 样例与登记边界

正式样例使用 `art_source/scenes/building_workshop/v001/workshop_sample_001/` 与 `workshop_sample_002/`，每楼包含 `building.recipe.json`、`building.tscn`、`catalog_snapshot.json`、`candidate_manifest.json`、`ledger.json` 五件，样例各 5 件静态源组件/产物口径由工程外登记证据承接。两个正式 AssetID 已定向登记，但不是主场景运行接入；`runtime_path=null` 保持不变。`catalog_v1.json` 中的 10 个组件 ID 只是当前 scope 的内部稳定 key，未来若有独立制作/正式资产需求再另行引用和登记，不在本轮拆成独立 Asset 主记录。

### 验证状态约束

- `workshop-core-roundtrip` 的 `workshop-rules`、`workshop-deep` 均 `exit_code=0`、`passed=true`。
- `workshop-palette-ui-final` 的 `visual-workshop` 为 104/0，`workshop-samples` 为 45/0；视觉截图涵盖 1280×800、1600×1000、1920×1080 请求档位。
- 该历史主集成批次保留未重跑的25/3事实，不改写为通过，也不把后续编辑器审计器初次543检查数误写成最终通过。

## 2026-11-10 22:45 编辑器主目标与 R13–R18 承接

本节为现行覆盖；上方planned表、运行版V1回填与25/3失败批完整保留为历史。用户纠正主目标为Godot编辑器模块化房屋制作工具；运行版暂停菜单Panel/Host保留未来玩法，不删除、不替代编辑器主交付。登记头状态为 `partial`；条目中的 `implemented_pending_acceptance` 仅描述历史细项，不作为登记头枚举值。当前编辑器功能闭环已据真实报告验收通过；总体交付包含编辑器插件、共享内核与验证链的代码修改。

| 对应设计条款 | 当前实施状态 | 证据 / 未签边界 |
|---|---|---|
| SEA-WORKSHOP-R01 / SEA-WORKSHOP-R13 | implemented；EditorPlugin顶部主屏与工具菜单已通过最新真实编辑器验收，不需F5/F6；独立Control+SubViewport预览，不实例化runtime Panel、不加载Main/Autoload、不改暂停树、当前编辑scene及手摆transform | `D:/projects/sea-work/verification/20261111-003009-editor-workshop-deliver-4b9df3/report.json`：editor-workshop exit0/passed=true；inner report为327 checks/0 failures，真实--editor隔离副本无Main/Autoload且仅启用plugin。生产 `godot/project.godot` 保留其他addons并追加本插件 |
| SEA-WORKSHOP-R14 | implemented；EditorStore实际完成两次独立五件revision提交、静态重载与旧revision保护；草稿为 `user://building_workshop_editor/recovery.json`，与游戏存档分离 | inner report：revision1/revision2各五件、recipe+catalog往返、SHA256、静态PackedScene重载与两次geometry hash均通过；实际building版本带下划线 `revision_NNNN`，编辑器草稿恢复及UI dirty通过 |
| SEA-WORKSHOP-R15 | implemented；共享六个@tool纯内核、同目录catalog_snapshot、静态安全兼容检查与单槽独立componentID替换均通过 | 最新 inner report：全局多尺寸替件明确拒绝且不改状态，选中槽独立成功替件、catalog ID独立、其他槽和原组件不变；core regression `D:/projects/sea-work/verification/20261111-003009-workshop-bake-regression-03b9c6/report.json` 中 workshop-rules/workshop-deep 均 exit0/passed=true，日志分别24/0与41/0 |
| SEA-WORKSHOP-R16 | implemented；右栏「导出当前槽为独立模块」按钮与实际 `screen.export_module_component` 端口、单槽两件候选导出、重载与真正独立prefab替换均通过 | 最新 inner report实际通过可发现导出入口、`screen.export_module_component`、`component.tscn`/`component_manifest.json` 导出、静态重载、尺寸接口拒绝与选中槽独立替换；保存后meshcount相同，root_noMain成立；`catalog_adapter.gd:172` 的实际模块revision无下划线。原source/timing及已登记身份保持；仅候选，不自动正式入库，不新增AssetID |
| SEA-WORKSHOP-R17 | implemented；基础参数、逐层/立面、绑定/槽覆盖、破旧/植物与独立预览可视化通过真实UI验收 | 最新 inner report 的真实控件/按钮、局部覆盖不吞未应用字段、撤销/重做、取消弹窗、线框/碰撞叠层、四张真实截图与两种分辨率布局均通过；新增 `damaged_l_plants` 图已由主线程审阅，非空截图不单独等同美术终验 |
| SEA-WORKSHOP-R18 | implemented；当前编辑器生命周期闭环已通过：隐藏/恢复、临时预览清理、屏幕remove oldControl/queue_free后重建并恢复snapshot、catalog、未应用输入与UI dirty | 最新 `D:/projects/sea-work/verification/20261111-003009-editor-workshop-deliver-4b9df3/project/outputs/workshop_editor_report.json`：enginehint=true、is_playing=false、scene_unchanged=true、root_paused_unchanged=true、327 checks/0 failures。该屏幕重建不是完整插件卸载重载或跨进程恢复；四张真实截图已审阅；完整美术、性能、复杂根系/墙面苔、楼梯与全楼可达pending |

### 运行版证据补充（独立于 editor 验收）

已实际读取 `D:/projects/sea-work/verification/20261110-224023-workshop-game-acceptance-00ec43/report.json`：

- `workshop-integration`：`exit_code=0`、`passed=true`、`completion_marker=true`、`unexpected_errors=[]`；同批 `workshop-integration.log` 明确25 checks/0 failures。
- `visual-workshop`：`exit_code=0`、`passed=true`、`completion_marker=true`、`unexpected_errors=[]`，renderer为real。
- 原25/3是较早失败历史，不反改旧记录。登记头旧待重跑标签已由主线程改为实际入口 `workshop-integration`，并保留 `editor-workshop`；不恢复旧标签，不再把运行版集成描述为当前尚未执行，也不将25/0转签成编辑器通过。

### 当前编辑器验收与资产边界

`editor-workshop` 已完成最新真实编辑器功能闭环验收：`D:/projects/sea-work/verification/20261111-003009-editor-workshop-deliver-4b9df3/report.json` 为 exit0/passed=true；隔离项目内 `outputs/workshop_editor_report.json` 为 enginehint=true、is_playing=false、scene_unchanged=true、root_paused_unchanged=true，日志明确327 checks/0 failures。真实 `--editor` 无Main/Autoload且仅启用工坊插件；两种分辨率四张截图的布局断言通过，含 `damaged_l_plants` 且已由主线程审阅。验证器使用真实Control值/Button.pressed信号，不等于鼠标自动化；无Main/Autoload只在隔离副本验证，不修改生产工程配置。

屏幕生命周期重建已通过：remove oldControl/queue_free后恢复snapshot、catalog、未应用输入与UI dirty；右栏「导出当前槽为独立模块」按钮及 `screen.export_module_component` 端口已实际通过，单槽prefab替换成功且保存后meshcount相同、root_noMain成立。这不是完整插件卸载重载或跨进程恢复，二者继续pending。`D:/projects/sea-work/building_workshop/editor_v001/delivery_report.json` 已实际重跑为 `passed=true`、`audit_passed=true`、`checks_count=572`、`failed_count=0`；保留 `visual_acceptance=not_signed`，不把审计通过扩写为美术终验 [编辑器开发记录](../../development/2026-11-10_building_workshop_editor.md)。

候选ledger不自动登记，只有用户确认使用后才走register与SEA-ASSET唯一路由。当前 `tools/workshop/register_samples.py` 只服务既有两样例；`SEA-SCENE-WORKSHOP-SAMPLE-001/002`、原source/timing与 `runtime_path=null` 保留，无新增AssetID。Native `partial_source_style`、复杂根系/墙面苔、楼梯/正式导航与全楼可达、用户美术终审和性能未签边界保持，不随编辑器入口改为通过。

### 条款集合校验补记

上方R01/R13组合行保留；此处追加独占条款行供checker精确识别。R13当前已有真实editor-workshop通过证据，不扩写为完整插件卸载重载或全库通过。

| 对应设计条款 | 当前实施状态 | 证据 / 未签边界 |
|---|---|---|
| SEA-WORKSHOP-R13 | implemented；EditorPlugin顶部主屏与工具菜单、独立Control/SubViewport已通过最新真实编辑器验收；不需F5/F6，不加载Main/Autoload，不暂停编辑器树，不自动改当前编辑scene及手摆transform；运行版保留未来玩法 | `D:/projects/sea-work/verification/20261111-003009-editor-workshop-deliver-4b9df3/report.json` 与 inner report 327/0；真实--editor隔离副本无Main/Autoload且仅启用plugin。生产enabled保留其他addons，仅显式打开已保存产物才切换scene。runtime25/0不代签editor |

## 2026-11-11 连续实体 model core · R19–R22 追加承接

本节只追加当前覆盖，不重写以上历史；登记头继续 `partial`，只追加两个 shell code_paths 与 `workshop-shell` verification。用户批评旧成品是积木拼装，不是结构严谨、工整的 professional model；主线程本轮重构 model core，不以 UI 堆功能或检查数量替代模型结果。「结构严谨」仅限几何组织、洞口与接合，不是土木结构安全或承载计算。

| 对应设计条款 | 当前实施状态 | 证据 / 未签边界 |
|---|---|---|
| SEA-WORKSHOP-R19 | partial；`shell_geometry.gd` 已生成矩形四角/L 形六角逐层单闭合墙壳、共享 miter、真实贯穿门窗/reveal、单闭合窗环及单封闭 U 形门框、每 run 统一 bay、每层连续整板与单件 roof；墙板框玻璃共用整栋 taper，不是独立 cell boxes 收分 | `godot/src/workshop/shell_geometry.gd` 与 `shell_generator.gd`；下述首跑实际 faces/碰撞/法线/正体积与接缝射线覆盖矩形/L 形 1/3/5 层、逐层高/板厚、left 禁窗及 L 缺口不封空。几何数值专项通过不等于 professional model 视觉已验，也不签任意多边形或全部参数组合 |
| SEA-WORKSHOP-R20 | partial；编辑器新建走 `Recipe.authoring_defaults()`：shell_v2、aging=0、damage=0、vegetation_density=0、wall_sun；旧 `Recipe.defaults()`/缺字段旧档保留 modular_v1。UI 模式已显式接线；连续 damage 非0与非零结构 offset 拒绝，会话提交前实际 build probe 原子拒绝 | `recipe.gd`、`generator.gd`、`session.gd`、`editor_screen.gd`；首跑实际核验默认值、damage拒绝保留预览、两个旧样例缺省/显式 modular 的几何与槽一致且未改源。UI 默认/模式的本轮真实 editor 结果待主线程回填。整件 disabled/excluded 在装配层仅跳过并警告闭合不保证，不当作已验破损；未知组合不签，旧 modular 破损保留但不作专业默认 |
| SEA-WORKSHOP-R21 | partial；连续槽为 wall_shell整层/slab整层/roof整件/frame整孔/glass独立；整件静态导出与兼容 prefab 替换已实际覆盖 wall/frame/glass，不冒称 `lower_a` 等旧 partial slots 已映射。Native2 板/roof 明确采用 0.028m三段实体倒角、0.14m出挑 formed_band 结构板例外，不是平台装饰板；洞口0.02m单段chamfer、框0.018m单段chamfer，墙角miter而非bevel | 首跑 `prefabs.wall_shell_0`、`prefabs.frame_front_0_0`、`prefabs.glass_front_0_0` 的 export/apply 均实际成功，并各经 Store 静态重载；`catalog_adapter.gd` / `shell_generator.gd` 校验静态安全、实际包络/pivot/轴向，不缩放凑尺寸。未实测任意替件或 slab/roof 的整套替件组合；不声称所有部件3 segments、墙外角圆弧或完整style已过 |
| SEA-WORKSHOP-R22 | partial；统一 runner 已登记 `workshop-shell`，生成期闭合边audit、装配后实际面audit与独立QA分域；首跑数值/静态专项通过，真实 editor/模型大图目视/性能未签 | `scripts/run_verification.py` → `godot/tests/test_workshop_shell.gd`；首跑外层 report exit0/passed=true、headless、unexpected_errors=[]，inner `project/outputs/workshop_shell_report.json` 为552/0且visual_acceptance未执行。实际覆盖 faces/法线/正体积/duplicate/nonmanifold/连通窗环、槽与prefab、Store与legacy；全局/统一坐标法线要求不能仅用自报metadata代替。最新 editor 日志入口见下，不签所有checks或视觉通过 |

### 本轮可引用证据与主线程待回填

- 首跑外层：`D:/projects/sea-work/verification/20261111-023726-workshop-continuous-first-485d04/report.json`。
- 首跑内层：`D:/projects/sea-work/verification/20261111-023726-workshop-continuous-first-485d04/project/outputs/workshop_shell_report.json`（专项内相对路径 `outputs/workshop_shell_report.json`）。已只读核对552 checks/0 failures；其结论限于该批数值与静态保存/替件，不是所有checks通过或美术终验。
- 八组基线包含矩形/L 形1/3/5层、逐层6.1m层高/0.25m板厚覆盖与left禁窗；另有两个legacy样例、基线及wall/frame/glass实际替件后的Store往返。测试写入由该历史隔离runner完成，本轮文档维护未运行Godot。
- 最新真实 editor 正在主线程批次中：`D:/projects/sea-work/building_workshop/continuous_v002/editor_first.log`，结果未定，只登记日志入口，待主线程回填退出码、正式报告、实际模型大图路径与逐图审阅。`editor_preview.gd` / `editor_verification.gd` 的capture模型图代码存在，不等于大图已完成或视觉已通过。
- 旧327/0与572/0及其原报告完整保留，仅为上一版编辑器历史，不复用为当前连续模型或最新editor验收。完整style、墙外角圆弧、complex root、stairs/navigation、全楼可达与性能均未签。

### 本轮源职责与交付口径

`godot/src/workshop/shell_geometry.gd` 拥有闭合实体基线、洞口/框/板、全局taper与生成时边audit；`shell_generator.gd` 拥有实际装配/碰撞、最终faces audit、整件prefab与root metadata（`generator_version=sea_workshop_continuous_shell_v2`、`construction_mode=shell_v2`）。既有 `recipe.gd` 分离authoring_defaults与legacy defaults，`generator.gd` 按模式分支，`session.gd` 在提交前生成探针并原子拒绝失败，`store.gd` 按实际root版本写manifest的generator/mode/model_quality。生成器quality中的自述/历史未验证字符串不代替独立QA事实，也不能倒签视觉。

编辑器显式mode/default与模型图capture只服务当前内核与结果审阅，不扩写UI功能完成度。对用户交付优先展示实际model大图，检查报告用于追溯，不反复拿测试数量表功。未强转旧存档、未新登记AssetID、未改正式主场景或原资产来源。详细记录见 [连续实体开发记录](../../development/2026-11-11_workshop_continuous_shell.md)。

## 2026-11-11 连续实体最终几何与真实 editor 实绩追加

本节覆盖前节的中间态描述，不改写任何历史行。登记头仍为partial，R19–R22稳定ID不新增、不改号。前节「仅miter/外角圆弧未签」「结构可跳过且只警告」「最新editor进行中」均为当时快照；当前代码、实际报告与产物状态以下述回填为准。整体本轮包含model core、会话、preview、runner与验收代码修改和实际运行，不是只做文档维护。

### R19–R22 当前承接补充

- **R19**：shellgeometry墙凸外角已补变形前半径0.07m、3 segments真实quarter-circle弧面，与墙run/封面连续接合并共用global taper；内角/L凹角仍sharp miter，墙上下水平边不圆。真实洞口/reveal、单实体框、统一bay、连续整板/roof与全栋映射契约不变；不把三段外凸圆角扩写成所有边圆角或结构安全计算。
- **R20**：wrapper对结构槽disabled:true、结构excluded_slots、非零offset全部明确拒绝，含frame/glass；残留跳过代码或旧metadata不代表支持结构禁用。session patch、recipe/catalog提交、accept_loaded、new_document均实际生成probe后才原子提交，失败保留原配方/catalog/历史/预览；植物不混同结构槽。旧modular兼容及新建clean shell默认保留，连续非零damage/drastic damage仍不支持。
- **R21**：整层shellwall/板、整孔frame与独立glass整件导出替换边界不变，不映射旧lower_a等partial slots。Native2结构板/roof仍0.028m三段、0.14m出挑formed_band例外；opening0.02m与frame0.018m仍单段chamfer。shellroot最终quality来自实际faces闭合/定向校核，invalid prefab明确拒绝，不再只是warning后成功；不宣称任意prefab可适配。
- **R22**：生成期边audit、最终实际faces硬拒绝与独立QA分域。凸角QA改用实际顶环顶点，按实际面核对法线/正体积/duplicate/nonmanifold等；preview用box coarse筛选后actual triangle ray，避免整层AABB抢窗selection。矩形/L真实editor已各有点选断言通过，功能/截图生成与professional视觉终验仍分开。

### 历史失败保留一行

023726首跑与025025中间模型shell两批均552/0；025833增强专项716/21失败来自跨clamped taper的y=0插值截面不exact，已改实际顶环而非放宽阈值；025806 editor 1489/4来自输出限定根错误及脚本重复调用shell samples，已修后另跑，不反改旧结果。目录分别为 `D:/projects/sea-work/verification/20261111-025025-workshop-continuous-rounded-611c84/`、`20261111-025833-workshop-continuous-final-qa-bb7cb2/`、`20261111-025806-editor-continuous-final-model-bbb46e/`；首跑完整路径保留上节。旧327/0与572/0不复用为本轮通过。

### 已落盘最终专项与 editor 报告

- 几何外层 `D:/projects/sea-work/verification/20261111-031500-workshop-continuous-verified-58a3bd/report.json` 已实际读取：workshop-shell、workshop-rules、workshop-deep均exit0/passed=true、unexpected_errors=[]。同批 `project/outputs/workshop_shell_report.json` 为716 checks/0 failures，视觉未执行；不是沿用此前pending或预签所有checks。
- 真实editor外层 `D:/projects/sea-work/verification/20261111-031449-editor-continuous-delivery-6bf812/report.json` 已实际读取：editor-workshop为real、exit0/passed=true、unexpected_errors=[]；inner `project/outputs/workshop_editor_report.json` 为992项、failures=[]、passed=true，enginehint=true、is_playing=false、scene/root paused不变。矩形/L「点击洞口不先选中整层AABB」均passed=true。
- 上述editor隔离项目 `project/outputs/` 的 `workshop_shell_model_rect.png`、`workshop_shell_model_front.png`、`workshop_shell_model_l.png` 已确认存在，为1400×1100真实SubViewport模型图；continuous_*为1600×1000真实editor framebuffer。已生成不等于已逐图签署professional美术终验；不以非空截图/计数代替目视。
- 成品汇总目标 `D:/projects/sea-work/building_workshop/continuous_v002/outputs/continuous_delivery_report.json` 当前未产生；同交付outputs下 `continuous_candidates.zip` 与三图汇集尚未确认，只保留后续生成目标，不能借隔离截图签成品包已交付。后续按实际报告与文件核验更新。

完整style、内角圆弧、墙上下水平边圆弧、drastic damage、complex root、stairs/navigation、全楼可达、性能与用户美术终验保持未签；无新增stage整屋blend承诺，无正式资产登记/世界摆位自动接入。交付仍以实际model大图为主，测试报告只负责可追溯证据。

## 2026-11-11 continuous_v002 交付定稿追加

本节为当前交付事实，前节「成品未产生/图集未确认」完整保留为历史快照，不代表现在仍待回填；登记头继续partial。代码source没有为本次定稿再改，未改GDD/registry/script，未替他人刷新hash或修SEA-ASSET-R67。

- **交付与图像**：`D:/projects/sea-work/building_workshop/continuous_v002/outputs/continuous_delivery_report.json` 已生成，passed=true、checks_count=1348、failed_count=0。其实际editor证据992/0、geometry716/0（不是重复两次shell的1481中间计数），1348为交付核对项不是引擎计数合计。输出根同目录已有三张1400×1100模型大图、五张1600×1000 continuous编辑器图及 `model_comparison.png`；比较图仅真实旧完整UI与新model等比缩放，无AI/猜裁剪，条件不同不作美术分数。
- **主线程目检**：三张实际model图已经逐图审阅，连续墙面、无棋盘拼格、圆外角高光、真实开口与板墙平齐明显改善；结论为「工整几何的基础模型已改，整体造型仍简洁，不冒称丰富美术终验」。这承接R19/R21/R22基础模型改进，不升级成完整style或4D/受力/土木结构安全验收。
- **已安装候选**：`D:/projects/sea/godot/scenes/workshop_buildings/shell_rect_1794338160_71001671/revision_0001/` 与 `D:/projects/sea/godot/scenes/workshop_buildings/shell_l_1794338160_71001671/revision_0001/` 各有 `building.recipe.json`、`catalog_snapshot.json`、`building.tscn`、`candidate_manifest.json`、`ledger.json` 五件，安装hash已与report的bundles核对一致。manifest完整路径分别为 `D:/projects/sea/godot/scenes/workshop_buildings/shell_rect_1794338160_71001671/revision_0001/candidate_manifest.json`、`D:/projects/sea/godot/scenes/workshop_buildings/shell_l_1794338160_71001671/revision_0001/candidate_manifest.json`。逐文件path/hash在report及开发记录列出；JSON候选状态candidate_only / exported_pending_project_registration、formal_registration=pending，未正式注册。
- **包内容与依赖**：`D:/projects/sea-work/building_workshop/continuous_v002/outputs/continuous_candidates.zip` 已核对SHA256=`e2fd59200e4ed6dcbc7bfe21cfcaa4341316fd335d2a28b866ade6fcdb415e11`，只含两楼原ID/revision_0001五件JSON/TSCN和JSON说明；公共色板 `res://assets/textures/shared/sea_cabin_timber_8x8_512.png` 未打包，依赖生产工程同路径资源。不是Blender/GLB或独立全资源包。
- **实际模型口径**：矩形12×9m、3层总6376三角面，其中结构3200，对照旧modular结构52428，仅作结构对结构比较；L形12×12m、3层总7560三角面。不把结构数与整楼总数混比，不以面数签美术或性能。
- **直接使用**：编辑器「楼房工坊」→「新建」默认连续实体，不强制覆盖旧草稿/转换旧modular；文件页「刷新」后可查两新ID并开配方。点选wall_shell导出整层墙结构而非旧lower_a tiny局部；整孔frame与独立glass边界不变。完整操作、八图文件名与五件hash见 [开发记录](../../development/2026-11-11_workshop_continuous_shell.md)。
- **全库contracts未过**：`D:/projects/sea-work/building_workshop/continuous_v002/contracts_sync.log`、`contracts_check.log` 已各实跑exit1；两者均8 source hash drift、67 runtime hash drift。sync共76 issues（另SEA-ASSET条款ledger问题），check共78 issues（另主表SEA-WORKSHOP状态差异及派生索引过期）；44 features/1069 source assets/1510 runtime hashes。全库失败导致主表sync未成功，不能手改摘要或批量hash掩盖；交付report的whole_project_contracts=not_provided只是汇总未纳入日志，不等于没有实跑。

失败历史仍按上节一简句保留，不复用旧327/0、572/0或552/0代签本轮。完整style、内角与墙上下水平边圆弧、drastic damage、complex root、楼梯/导航/全楼可达、性能、插件完整卸载重载/跨进程恢复及正式世界接入未签；不新增stage整屋blend承诺。

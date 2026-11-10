# 2026-11-10 · Godot 编辑器模块化楼房工坊体系

[主文档导航](../../GDD_V1.0.md#sea-workshop) · [工坊设计](../features/workshop/spec.md) · [工坊账本](../features/workshop/ledger.md) · [资产账本](../features/asset/ledger.md) · [架构所有权](../architecture/module_contracts.md)

## 1. 22:45 目标纠正与交付范围

主目标是 **Godot 编辑器内的模块化房屋制作工具**，无需运行游戏。顶部「楼房工坊」EditorPlugin 主屏承担参数编辑、组件换装、独立预览、每栋保存与静态烘焙；用户原有场景及手摆transform不变。游戏内暂停菜单版已实现，保留作未来玩法基础，不删除，也不以它的通过结论替代编辑器验收。

对应 SEA-WORKSHOP-R01、R13–R18 与 SEA-ASSET-R68/R68a。工坊登记头状态为 `partial`，细项中的 `implemented_pending_acceptance` 仅表示历史细项，不作为登记头枚举值。总体交付包含编辑器插件、共享内核与验证链的代码修改；本文记录其实际职责与已验闭环及剩余边界。最新 editor-workshop 功能闭环已通过真实报告327/0与delivery audit 572/0；完整插件卸载重载/跨进程恢复、美术、性能及复杂能力仍pending。

文档与实施证据由工坊spec/ledger、资产ledger及本文共同承接；旧账本历史保留，登记头使用checker允许的状态。本文不替代代码交付，也不以文档检查或runtime通过扩大编辑器结论；本轮editor不新增正式资产，两个runtime样例及其正式记录保留。

## 2. 分层、所有权与依赖

依赖为编辑器适配层 → 共享工坊内核 → 只读规范/catalog/色板。运行版另经Panel/Host装配同一内核；编辑器不经过Main、Autoload、游戏存档或运行版CanvasLayer。

| 层 / 实际路径 | 所有权与边界 |
|---|---|
| `godot/addons/building_workshop/plugin.cfg`、`plugin.gd` | 注册EditorPlugin主屏与工具菜单，注入Store/替件/单槽导出/显式打开scene/资源扫描端口，管理生命周期与recovery；不启动F5/F6、不修改SceneTree.paused、不自动切换编辑scene |
| `godot/addons/building_workshop/editor_screen.gd` | 独立Control主屏，拥有控件、未应用字段、确认反馈与选中槽；业务修改经Session命令，不直接写正式资产账本 |
| `godot/addons/building_workshop/editor_preview.gd` | 独立SubViewportContainer，`own_world_3d=true`；仅拥有临时模型、灯光/环境/相机、槽点选和线框/碰撞叠层；不是运行版Panel或preview改名 |
| `godot/addons/building_workshop/editor_store.gd` | 继承共享Store，限定编辑器根与加载路径、加强prefab检查、增加editor来源manifest；复用版本提交，不复制第二套配方规则 |
| `godot/addons/building_workshop/catalog_adapter.gd` | 安全静态PackedScene检查、实际几何测量、局部独立componentID替件、单槽两件导出；不调用正式register |
| `godot/addons/building_workshop/editor_verification.gd` | 真实编辑器中执行验证并采集报告/截图，不是运行版`--script`面板测试，也不在生产目录生成fixture |
| `godot/src/workshop/recipe.gd`、`catalog.gd` | 配方校验/规范化与只读目录兼容、指纹；查询以副本隔离 |
| `godot/src/workshop/session.gd` | 唯一已应用草稿与会话撤销/重做所有者，联合提交recipe/catalog；UI未应用字段另行检测，不冒充已保存 |
| `godot/src/workshop/generator.gd`、`mesh_builder.gd` | 确定性槽、最终结构/植物网格和局部空间声明；不拥有正式场景布局 |
| `godot/src/workshop/store.gd` | 五件bundle、临时写入、静态重载、hash与revision历史保护 |
| `godot/src/workshop/panel.gd`、`host.gd`、`preview.gd` | 原运行版UI、暂停/输入生命周期和预览，保留未来玩法；不并入编辑器主屏 |

六个共享纯内核脚本 `recipe/catalog/generator/mesh_builder/session/store.gd` 已有 `@tool`，支持编辑期调用，不因此引入Main或Autoload。正式资产登记仍由SEA-ASSET唯一路由，正式摆位与世界空间接入仍由SEA-WORLD拥有。

生产 `godot/project.godot` 的enabled列表保留 `material_guard`、`proton_scatter`、`terrain_3d` 并追加 `building_workshop`。真实验收副本仅启用工坊属于隔离策略，不得用该副本列表替换生产其他addons。

## 3. 持久化、版本与三类产物

| 类型 | 实际根 / 文件 | 语义 |
|---|---|---|
| 编辑器整栋候选 | `res://scenes/workshop_buildings/<building_id>/revision_NNNN/` | building目录沿用共享Store的**带下划线**命名，不写成revisionNNNN |
| 每栋固定五件 | `building.recipe.json`、`building.tscn`、`catalog_snapshot.json`、`candidate_manifest.json`、`ledger.json` | 配方与目录快照可再编辑；静态TSCN可独立使用；manifest/ledger只是候选追溯 |
| 编辑器未保存恢复 | `user://building_workshop_editor/recovery.json` | recipe/catalog、dirty与未应用UI等恢复数据；不是游戏主存档，不宣称完整撤销历史跨进程持久化 |
| 单槽模块候选 | `res://scenes/components/workshop_modules/<building_id>/<slot_id>/revisionNNNN/` | 此处适配器实际为**不带下划线**命名，不强行统一成building版本格式 |
| 单槽固定两件 | `component.tscn`、`component_manifest.json` | 独立静态视觉模块与来源/几何/身份追溯；不复制脚本或原碰撞 |
| 运行版历史根 | `user://building_workshop/<building_id>/revision_NNNN/` | 运行版已有候选，不是编辑器默认保存位置，不迁移/删除历史 |
| 编辑器验证根 | 隔离副本内 `res://outputs/workshop_editor/` | EditorStore额外允许的验收端口，不是任意磁盘写入许可 |

“保存并烘焙”是一次五件版本提交：校验参数 → 临时目录写入 → 无工坊重建脚本的静态场景重载比对 → manifest/hash与候选ledger → 提交新revision。失败不宣布成功，不覆盖上一有效版。building.tscn不打包预览相机灯光；建筑分件、植物独立，空间声明只对应当前最终结构。

重开某栋强制读取同目录 `catalog_snapshot.json`，不静默回退全局目录；全局目录后续变化不应悄悄改写既有楼房绑定。草稿恢复先写临时文件并读回JSON，再尝试提交recovery；异常退出/断电耐久性、插件完整卸载重载与跨进程恢复仍须独立验收，不能据路径或代码存在签通过。

## 4. 编辑器操作闭环

1. 打开项目并启用插件，切换上方「楼房工坊」主屏，不按F5/F6；首次未刷新时到ProjectSettings确认插件已启用。新建或从文件页打开已保存建筑，也可载入版本化样例后另存新building_id。
2. 在结构/门窗/破旧/植物/空间/文件六页编辑基础参数、三seed和全局绑定。逐层与逐立面使用各自应用/清除按钮；局部操作保留尚未应用的基础字段，避免UI回填吞输入。
3. 在独立预览中旋转/缩放、正背俯透视、点选槽；通过槽列表编辑偏移、组件、生长档、禁用/恢复与植物锁定。线框和实际碰撞叠层辅助审阅，不改共享Mesh/Material。
4. 禁用槽应同步移除实际几何/碰撞，列表保留恢复入口；未生成槽不拿过期缓存几何作替换或植物锚点。清除槽覆盖不等于覆盖全局seed造成的破损结果。
5. 应用参数后保存并烘焙，生成新的五件revision；撤销/重做归Session，文本框自身Ctrl+Z不被会话抢占。新建/打开另一栋/载入样例涉及未保存字段时须确认，取消保留草稿。
6. 选中槽后点击右栏「导出当前槽为独立模块」，检查component.tscn与manifest重载；必要时修改该模块模型，再通过兼容性检查执行独立prefab替件，确认不兼容全局替件被拒绝且原组件/其他槽不变。
7. 需要检查静态产物时，用户显式点击「在3D打开」才打开最近保存的building.tscn；普通预览/保存不改变当前编辑scene、Main及用户transform。静态scene的手工编辑不宣称自动反推到参数配方；修改source geometry不对应JSON自动识别，仍需显式回到配方/槽绑定处理。

UI已有上述控件与命令接线，最新真实报告已签署其可用性、禁用恢复、布局与输入生命周期。右栏提供「导出当前槽为独立模块」按钮，并通过真实 `screen.export_module_component` 端口导出单槽模块；单槽prefab成功替换，保存后meshcount相同且root_noMain成立。

## 5. 兼容替件与单槽模块导出

替件仅允许 `res://scenes/components/` 下静态 `.tscn`。适配器实例化前检查PackedScene/资源树，拒绝脚本、非静态节点、嵌套/继承scene、信号连接及非允许资源；目前允许Node3D/MeshInstance3D静态视觉树，不把任意Prefab都叫兼容。

通过实际bounds、尺寸、pivot、轴向和catalog槽族校验后，选中槽建立局部独立componentID，再经Session联合提交recipe/catalog。原组件定义、其他同ID槽与整楼姿态保持；不兼容或全局同ID多尺寸场景明确拒绝，不靠拉伸适配。替件与撤销、保存、同目录snapshot重开应形成一致闭环。

单槽导出由 `catalog_adapter.gd:172` 的 `export_slot` 承担：复制视觉属性并计算实际包围盒，硬表面居中，普通植物底心、藤蔓顶心；记录 `building_id/slot_id/source_component_id`、实际pivot、`front_axis=-Z`、网格/三角数和hash。两件先写临时目录，重载比对后提交无下划线revisionNNNN；历史不覆盖。该流程不重写原source/timing等来源身份，也不把新的内部componentID提升成正式AssetID。

## 6. 候选、正式登记与已有样例

`candidate_manifest.json` 和 `ledger.json` 只记录候选。编辑器manifest声明 `authoring_context=editor`、`noMain=true`、`formal_registry_written=false`，不等于正式主场景资产或运行接入。

只有用户确认使用工具产物后，才经register工具按SEA-ASSET路由正式登记；当前 `tools/workshop/register_samples.py` 是两样例专用工具，不是任意楼房/模块自动登记服务。本轮editor不新增正式资产或AssetID，两个runtime样例及其正式记录保留；原source/timing与用户场景不改。

既有 `SEA-SCENE-WORKSHOP-SAMPLE-001`、`SEA-SCENE-WORKSHOP-SAMPLE-002` 保留，正式源仍在 `art_source/scenes/building_workshop/v001/workshop_sample_001/`、`workshop_sample_002/`，各五件；`runtime_path=null` 维持，不能称为主场景已接入。catalog内部组件key与单槽派生componentID均不是独立正式主记录。

## 7. 生命周期与保留限制

- 显示主屏开启预览更新，隐藏时 `UPDATE_DISABLED` 并停止拖拽；停用移除工具菜单、保存recovery、释放自有主屏及其预览世界。不清理用户场景或其它addons。
- 重新启用尝试读取并校验草稿，恢复UI未应用字段与当前配方；不连接游戏存档。当前已验隐藏/恢复及屏幕remove oldControl/queue_free重建；完整插件卸载/重载、跨进程恢复和异常终止效果仍pending。
- Native程序构件仍 `partial_source_style`，真实UV/8px safe inset/圆角不等于完整项目Skill风格、Blender源/GLB/02b链或用户美术终验。
- 四类程序植物及small/medium/large不代表复杂根系贴墙或墙面刷苔已实现；两者仍未支持/pending。最多8层受尺寸、节点与三角预算约束，不承诺任意8层组合。
- 三种 `spatial_profile` 保持：水上功能、水下观赏、潜水静态；观赏无碰撞/导航，walk/water只是局部声明。楼梯/正式导航与全楼可达、正式运行资源接入、设备/持续性能和用户美术终审仍pending，不因编辑器入口改变而升级。

## 8. 分域验收与当前证据

### 已读取的运行版通过证据

`D:/projects/sea-work/verification/20261110-224023-workshop-game-acceptance-00ec43/report.json` 实际可读：`workshop-integration` 与 `visual-workshop` 均 `exit_code=0`、`passed=true`、`completion_marker=true`、`unexpected_errors=[]`；integration日志明确25 checks/0 failures，visual入口使用real renderer。

这补充了运行版正式Main集成通过事实；旧planned表和较早25/3失败历史不删除、不反改。该报告不证明编辑器、完整插件启停、美术终验或全工程门禁通过，旧runtime开发记录不重写。

### 当前编辑器功能闭环验收：通过

统一runner实际名称 **`editor-workshop`**。最新真实证据为 `D:/projects/sea-work/verification/20261111-003009-editor-workshop-deliver-4b9df3/report.json`（exit0、passed=true），日志明确327 checks/0 failures；inner报告为 `D:/projects/sea-work/verification/20261111-003009-editor-workshop-deliver-4b9df3/project/outputs/workshop_editor_report.json`，enginehint=true、is_playing=false、scene_unchanged=true、root_paused_unchanged=true。实际命令使用 `--editor`、非`--script`，隔离项目无Main/Autoload且仅启用 `res://addons/building_workshop/plugin.cfg`。四张真实截图覆盖1280×800、1600×1000、门窗/立面页及 `damaged_l_plants`，布局断言通过，overview已由主线程审阅。右栏「导出当前槽为独立模块」按钮与真实 `screen.export_module_component` 端口通过。下表区分已验闭环与仍pending边界，不能将验证器源码断言数扩大为全库通过。

| 范围 | 应取证内容 | 当前签署 |
|---|---|---|
| 真编辑器隔离 | `--editor`、非`--script`、editor_hint=true、未运行scene、无Main/Autoload、隔离副本写入 | 已通过：runner exit0/passed=true；inner enginehint=true、is_playing=false，真实--editor仅启用工坊插件 |
| UI与Session | 实际控件/按钮信号、参数/局部覆盖、原子拒绝、未应用字段/取消/撤销重做、禁用恢复 | 已通过：最新inner 327 checks/0 failures；局部输入、取消、撤销重做、槽恢复均有真实断言 |
| 五件与重开 | 同building连续两revision、旧版hash不变、recipe+catalog往返、静态PackedScene几何/hash及owner/无脚本/不含预览灯相机 | 已通过：两revision各五件、重载/hash/旧revision保护通过；catalog外链色板未打包 |
| 模块与替件 | 单槽两件导出、全局多尺寸拒绝、选中槽成功兼容替换、不连带其他槽、身份/实际bounds | 已通过：右栏导出按钮与真实 `screen.export_module_component` 端口、component导出/reload、真实独立prefab替换与不兼容全局拒绝通过；保存后meshcount相同、root_noMain成立 |
| 环境不变 | 当前编辑scene root/transform、SceneTree.paused不变，不连接游戏存档 | 已通过：scene_unchanged=true、root_paused_unchanged=true、game_save_connected=false |
| 真实渲染 | 1280×800、1600×1000及门窗/立面/破旧植物页真实截图，实际窗口/布局/预览内容与主线程overview审阅 | 已通过编辑器布局证据：四张截图、两种分辨率、无popup且布局断言通过；`damaged_l_plants`已审阅，不以此签署完整美术验收 |
| 生命周期 | 隐藏/恢复停止/恢复预览；屏幕remove oldControl/queue_free重建恢复snapshot/catalog/未应用输入/UI dirty | 已通过当前屏生命周期重建；完整插件卸载重载、跨进程recovery另列pending |
| 产品边界 | 完整风格、复杂根系/墙面苔、楼梯导航/全楼可达、设备/持续性能、用户终审 | 保持pending/未支持 |

验证器当前输入方式为真实Control值与Button.pressed信号，不声称鼠标自动化；其生命周期声明只覆盖隐藏/恢复，不释放插件来伪造卸载测试。隔离副本清除Autoload/Main、只启用工坊，不修改生产工程对应配置。

### 当前已核对证据与剩余边界

- runner批次：`D:/projects/sea-work/verification/20261111-003009-editor-workshop-deliver-4b9df3/`；`report.json` 为 editor-workshop exit0/passed=true，日志为327 checks/0 failures。
- inner报告：`project/outputs/workshop_editor_report.json`；enginehint=true、is_playing=false、scene_unchanged=true、root_paused_unchanged=true、failures=[]、dependencies=[]、game_save_connected=false。
- 两revision五件、单槽component.tscn/manifest、静态重载/hash、真正独立prefab替换、全局不兼容拒绝、屏幕重建恢复snapshot/catalog/未应用输入/UI dirty、两种分辨率四张截图均已由真实报告覆盖；右栏导出按钮及 `screen.export_module_component` 端口通过，保存后meshcount相同、root_noMain成立；catalog source外链色板不打包，静态烘焙取消嵌套scene/继承以避免double mesh。
- `D:/projects/sea-work/building_workshop/editor_v001/delivery_report.json` 已实际重跑：`passed=true`、`audit_passed=true`、`checks_count=572`、`failed_count=0`；`visual_acceptance=not_signed` 继续保留，不把审计通过扩写为美术终验。
- 当前仍pending：完整插件卸载重载、跨进程recovery、复杂根系、墙面苔、楼梯/正式导航/全楼可达、完整美术、性能与用户终审。runtime原25/0、104/0只作为历史证据保留，不扩写为editor或全库通过。

共享内核最终回归：`D:/projects/sea-work/verification/20261111-003009-workshop-bake-regression-03b9c6/report.json` 中 rules/deep 均 exit0/passed=true，日志分别24/0与41/0，证明共享@tool内核回归不破坏原runtime。全库contracts sync/check实际均exit1：`contracts_sync.log` 为75 issues，`contracts_check.log` 为77 issues；source hash drift实际8、runtime hash drift实际66，另有SEA-ASSET条款集合与派生索引问题。`contract_status.json` 同样记录sync/check均exit1。`SEA-ASSET-R67`仅ledger存在而spec缺失属于他人问题，本轮不修改；不批量刷新旧hash。功能登记头继续保持 `partial`，不因局部editor闭环改为verified。

# 2026-11-17 树木与房屋工坊切换深检

[主文档](../../GDD_V1.0.md#sea-workshop) · [房屋设计](../features/workshop/spec.md) · [房屋账本](../features/workshop/ledger.md) · [树木设计](../features/plant_editor/spec.md) · [树木账本](../features/plant_editor/ledger.md) · [装配账本](../features/world/ledger.md)

## 范围与结论

用户反馈最近修改操作后，树木与房屋工坊互切会不显示或不正常工作。本轮不改房屋几何、静态Store、配色规则、主场景或用户摆位；在已有未提交改动上定向修复。故障不是已证实的单一高度归零问题：静态审计没有普通互切将Control高度写零的链，确认的是调度、显隐、旧实例结构、草稿恢复及跨插件生命周期存在多处缺口。没有操作原用户编辑器或读取、写入其真实草稿，不能宣称复现其原进程的唯一原因。

## 确认的问题与修复

| 问题 | 影响 | 当前修复 |
|---|---|---|
| 房屋隐藏仍消费160ms参数队列 | 主线程同步生成阻塞另一工坊，隐藏期间提交历史 | 隐藏停止计时，保留pending/failed/target；返回只恢复未尝试队列，显式应用可以重试失败 |
| 树返回无条件重试pending | 失败输入每次切屏重新执行 | 记录最近尝试签名，失败待用户纠正或显式重试；重复激活幂等 |
| 两工坊隐藏未结束滑块事务 | 后续独立操作误并入旧撤销 | 隐藏结束拖拽与历史合并身份，不清用户输入 |
| 旧树预览实例没有新导航节点 | 外部脚本更新后新handler使用空输入面 | 激活/输入幂等发现或补建导航层，迁移旧surface信号，不重复_ready、不清模型/世界 |
| 树首次取景使用尚未布局的视口 | 切回模型过小、裁切或近似空白 | 等真实可见和两帧尺寸稳定后完成首次取景；正常重建/互切保持用户镜头 |
| 房屋screen重建固定hidden | 当前主屏被选中但新screen不可见 | 重建恢复原active状态 |
| 草稿恢复失败后自动/退出覆盖 | 原失败草稿可能被默认文档覆盖 | 坏JSON、不可读、恢复失败锁住写回，明确提示先另存；房屋恢复先候选生成后提交 |
| 草资源未导入/null仍解引用 | 脚本异常后生成器仍可能交付残缺成功 | 资源库安全返回null；生成前预检，坏顶点/UV/索引结构化失败，释放独立候选 |
| 树风准备在Session提交后才执行 | 新配方/历史已提交但仍显示旧模型 | Session注入候选校验端口，编辑器提交前准备风材质；失败保状态/历史/旧root，成功复用已准备mesh |
| 装配只扫描一次工坊screen | 禁用重启或重建后信号/目标陈旧 | plugin+screen双身份连接，节点上线合并刷新、请求前核验，退出取消对应事务，旧回调/同token异工坊拒绝 |

已经开始的同步生成不可中途取消，本次保证隐藏后不再启动排队生成。无成功模型时提供“重试预览”，不是每帧或每次切屏盲目重建。草稿保护有意保持到插件重新加载，先保存独立候选，不能静默放弃原失败草稿。

## 代码位置

- `godot/addons/building_workshop/{plugin,editor_screen,editor_preview}.gd`：激活、队列、滑块事务、恢复与焦点。
- `godot/addons/plant_editor/{plugin,editor_screen,preview}.gd`：显隐、首次取景、迁移、重试、草稿门禁及候选准备。
- `godot/src/plant_authoring/{generator,session}.gd`、`godot/src/ambient/vegetation/library.gd`：失败传播与提交前校验；共享库所有权仍属SEA-AMBIENT。
- `godot/addons/scene_assembly/plugin.gd`：跨插件双身份信号生命周期，不改变Placement当前transform或只换Asset事务。
- `godot/addons/plant_editor/switch_verification.gd`（新增）、`editor_verification.gd`、`godot/tests/{test_plant_authoring,test_scene_assembly_editor}.gd`、`scripts/run_verification.py`：专项与完整回归。

## 已确认的真实验证

引擎 `/Applications/Godot.app/Contents/MacOS/Godot`，Godot4.7.2、Apple M6、Metal Forward+。全部经统一runner、工程外副本与独立user目录，不使用生产Main/Autoload。GUI任务最终串行，避免窗口焦点/扫描/停绘干扰。

| 专项 | 当前证据 | 结果 |
|---|---|---|
| 双工坊真实切换 | `/Users/zyq/work/sea-work/verification/20261117-193911-workshop-switch-serial-r5-1b3255/report.json` | 336/0；import/editor/runner exit0，completion=true，unexpected=[] |
| 植物作者内核 | `/Users/zyq/work/sea-work/verification/20261117-194137-workshop-switch-kernel-release-41a4f7/report.json` | 440/0、exit0、unexpected=[]；含提交前校验拒绝与候选释放 |
| 树屋集成 | 同上 | 540/0、exit0、unexpected=[] |
| 宿主安全 | 同上 | 155/0、exit0、unexpected=[] |

切换专项真实鼠标点击顶部标签，不补调_make_visible/set_screen_visible。覆盖普通多次往返、pending隐藏不提交/返回一次、失败输入切回不重试、滑块事务结束、模型/Session/历史/机位保持、实际滚轮/中拖、隐藏时钟/材质风停止、active rebuild，以及两工坊坏草稿的真实写入正反对照。专项336/0所用9个产品关键脚本与当前工作区逐字节一致；测试脚本后续只加强普通完整editor的安全检查与阶段日志。

### 真实图像

上述切换批次 `project/outputs/workshop_switch/` 共8张PNG：房屋/树往返各preview+editor、旧结构模拟迁移preview+editor、房屋active_rebuild preview+editor。已目检最终active_rebuild_editor.png及simulated_legacy_migration_editor.png；房屋完整可见、模块/导航栏未被预览覆盖；树模拟迁移图为测试导航放大后的近景，右侧裁切属于保留机位，不冒称整树入镜。另目检前一相同产品批次的往返房屋与整树整屏，模型和工具栏均正常。

内核为真实后端逻辑/网格/保存重载，不产生新截图，不能把它签为视觉验收或性能测试。

### 完整回归与失败历史

- `20261117-185513-workshop-switch-integration-0dc248`：房屋1499/0、装配159/0、各exit0，但运行期间源变化，不能作为最终源码证明。
- `20261117-194841-workshop-switch-integration-serial-release-1a230a`：房屋1499/0、装配159/0、各exit0、unexpected=[]、隔离源无变化；source_changed仅为plant editor_verification新增诊断日志，全部产品脚本一致。保留原source_consistent=false，不修改报告消错。
- `20261117-195329-workshop-switch-tree-long-42c365`：完整树2289/1、exit1。唯一失败“主屏不引用房屋或启动游戏 plugin.gd”为静态测试将安全门禁的目录存在检查误判为加载bootstrap。已限制为load/preload调用判定，保留禁止房屋引用、autoload及运行树无Main断言；不将该失败批次改签通过。
- 更早树完整回归360秒exit124，不能拿中途产生的截图签通过；长批实际完成说明需合理时限。
- 切换183249为首次焦点/输入时序12/3、exit1；184616为等待未请求draw导致内部期限283/3、退出-6；185501为JSON数字字典直接比较正对照336/2、exit1；185618为并发GUI/扫描阻塞5/1、exit1。改为事件缓冲刷新、按实际隐藏验收、截图明确请求draw，后续GUI串行。
- 内核194002为新增测试重复调用575/0，但第二组fixture未清理产生退出泄漏ERROR，engine exit0仍由runner判FAIL；移除重复调用后440/0、无unexpected。

完整树与房屋/装配当前最终签署在下方追加，不沿用旧结果。

## 全局门禁与登记边界

本轮仅定点登记14条明确改动的源码/测试字节；新增editor_preview、switch_verification与共享library的无AssetID记录，其他1862条记录及元数据原始字节不变，不重签既有随机/Store/导入噪音或源资产。最终14条核对在交付收口完成。

全库sync/check已实际执行，原始退出码见 `/Users/zyq/work/sea-work/workshop_switch_20261117/contracts_results.json`，原始日志同目录。历史资产哈希、断链、SEA-ASSET条款集合、候选输出根扫描及派生索引不属本轮修复，不批量刷hash掩盖。最终数字在下方追加。

## 未测与操作建议

- 旧结构迁移是模拟旧shape，不是真实脚本热重载；重启/禁用启用在隔离装配有断言，不等于原用户跨进程草稿恢复。
- 滑块事务通过控件信号建立、切屏走真实鼠标；未签物理按住左键跨顶部标签捕获。
- 树草稿测试显式emit真实timer.timeout并检查原保存连接，不是自然等待4秒；未在原user目录退出插件。
- 本轮不签GPU/FPS、Web/mobile、全部输入键位、人工手感、艺术终审或正式世界接入。
- 用户先将当前楼房/树分别保存独立候选，再重启一次Godot加载完整插件结构；普通切换不需反复重启。若出现“原草稿已保留”提示，不删文件，不直接用新文档覆盖；先另存当前配方再处理原草稿。可见模型但取景偏离时用“显示整栋”/“适配”；初始化资源失败时用“重试预览”。

## 最终签署

- 树完整编辑器：`/Users/zyq/work/sea-work/verification/20261117-200321-workshop-switch-tree-accepted-412775/report.json`，inner `project/outputs/plant_editor_report.json` **2289/0**，import/editor/runner **exit0**、completion=true、unexpected=[]，329项artifacts。最终主屏图已打开目检，不将329项全部称为目检。旧2289/1静态误报及超时记录保留。
- 房屋与装配：`/Users/zyq/work/sea-work/verification/20261117-201128-workshop-switch-integration-accepted-8cf925/report.json`，**1499/0、159/0**，import/两editor/runner **exit0**、completion=true、unexpected=[]；两项source_consistent=true，source_changed_during_run=false，隔离源码无变化。包含工坊完整禁用/启用、screen重建、陈旧pending与同token跨工坊隔离。
- 切换336/0、树2289/0、房1499/0、装配159/0、内核440/0、集成540/0、宿主155/0共7入口全部真实通过；不把这些断言数量当作独立人工操作数或性能指标。
- 最终工作区与房屋/装配快照的工坊、装配及两内核目录逐字节一致；切换9个产品关键脚本一致；`git diff --check` exit0，main.tscn/project.godot与HEAD无diff。原有其他未提交diff、导入噪音与历史产物保持，未commit/push。
- 定点14条运行记录当前SHA/bytes一致，非目标记录保持；共享资源库补充SEA-AMBIENT-R02承接，不发新AssetID。
- 最终全库同步 **540 issues / exit1**、正式检查 **541 issues / exit1**，46功能、1105源资产、1876运行记录。原始日志 `/Users/zyq/work/sea-work/workshop_switch_20261117/delivery_contracts_{sync,check}.log`，逐项退出码 `contracts_results.json`。包含472项其他runtime漂移、14源漂移、51历史断链及SEA-ASSET条款/候选输出根扫描/派生索引问题；本轮14个明确目标无漂移。记录进程exit0只表示结果写入成功，不替代两次内部exit1，不签全工程绿。


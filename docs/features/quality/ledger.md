# SEA-QUALITY · 验证与性能治理 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-quality) · [功能文档](spec.md)

2026-10-29初始六格修复（R01/R03/R04）：真实输入247项、原生渲染250项、玩家档只读副本40项全过；DIY渲染28项和完整种植出货61项回归通过。过程失败与夹具问题分别保留，不把模拟直接perform作为点击成功证据。[当前证据与未执行项](../../development/2026-10-29_initial_six_planters.md)。

2026-10-29种植区可踩踏（R01/R03/R04）：专项逻辑53项与真实渲染59项均0失败/退出0，建造、种植、物理移动、保存恢复及平台外缘回归通过。完整种植至出货流程首轮11失败、探针9失败，定位为测试点击与角色自动交互使用旧原点；修正角色状态锚点后14项锚点专项及61项真实输入全过。过程失败日志保留，未改出货规则。范围及当前证据见[本轮记录](../../development/2026-10-29_walk_on_planters.md)。

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-QUALITY",
  "status": "partial",
  "owner": "隔离验证 runner / 静态架构门禁",
  "code_paths": [
    "scripts",
    "godot/tests",
    "tests"
  ],
  "verification": [
    "structure",
    "framework-modules",
    "framework-integration",
    "save-protection",
    "visual-weather"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-QUALITY-R01 | 每项保留退出码/日志/renderer/user目录；失败历史与未执行项单列 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-QUALITY-R02 | 航路正式代码不引用parity；framework-modules和surface通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-QUALITY-R03 | 真实天气截图另跑；跨平台、设备和性能未签署完成 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-QUALITY-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-QUALITY-R05 | 已实现并专项核验 | [边界补强记录](../../development/2026-10-27_framework_boundary_hardening.md) |

## 资源与调用入口

- [scripts](../../../scripts)
- [godot/tests](../../../godot/tests)
- [tests](../../../tests)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

scripts/check_architecture.py；scripts/check_feature_contracts.py --sync 后无参数检查；run_verification.py 的 framework-modules/framework-integration/save-protection/visual-weather。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

入口：`python3 scripts/check_feature_contracts.py`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 尚无本功能独立运行验收，不将结构通过视为玩法完成。

- 2026-10-23 真实事件补充：visual-click 退出 1，第二地格点击目标断言失败；拆分前基线同样失败，完整根因待定位。不得以核心 click 通过覆盖此失败。详见[交付记录](../../development/2026-10-23_feature_split.md)。

## 遗留与下一步

增加无 Autoload 框架测试、跨进程恢复、坏档保护及真实天气截图。每项用独立用户目录，仅 seed/对应恢复专项有意共享；目标设备/发行测试仍单列。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-26 功能与健康审计

SEA-QUALITY-R01/R02/R03：31 项功能各有独立文档和账本。当前专项 modules 28、surface 503（30航路）、click 30、camera 8、management 36 均通过；selftest 530通过/7失败，visual-click 5失败，visual-management 2失败。结构初查 zones.json 哈希漂移。测试副本、预期错误、并发编辑限制及未执行项详见审计记录；整体保持 partial。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

增加无 Autoload 框架测试、跨进程恢复、坏档保护及真实天气截图。每项用独立用户目录，仅 seed/对应恢复专项有意共享；目标设备/发行测试仍单列。

新增条款 SEA-QUALITY-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

2026-10-27 框架收尾：运行13组专项通过，架构边界0问题；最终契约门禁唯一失败为并行修改 water.tres 的运行哈希漂移，未批量接受。详见[最终门禁记录](../../development/2026-10-27_modular_framework.md#最终静态门禁与并发边界)。

## 2026-10-27 查询与恢复边界补强

门禁新增种植/订单内部状态与Main私有调用检查；超长随机数用例首次退出0仍判失败，修复后复测。

[本轮实测记录](../../development/2026-10-27_framework_boundary_hardening.md)。

## 2026-10-29 海上自由建造专项

同日角色碰撞改造（SEA-QUALITY-R01/R03/R04）：新增character-motor、ground-space、actor-presentation、character-space-save专项；真实渲染另跑行走、最小循环、DIY/离岸建造。旧默认范围失败与改造前快照逐项对照，未删除断言或批量刷新资源哈希。过程失败、逐项退出码和未执行项见[角色框架交付](../../development/2026-10-29_character_physics_framework.md)，整体保持partial。

新增building-open-rules、building-space、building-ocean、building-open-seed/restart、visual-building-diy/ocean。诊断building-boundary-audit已改为修复后反例回归，不再要求旧缺陷成立；旧失败日志与历史审计保留。所有验证仍经runner在Autoload前隔离存档，完整退出码/渲染/未执行项见[本轮交付](../../development/2026-10-29_open_ocean_building.md)。

## 2026-10-29 WorkBuddy 行走架构复核

SEA-QUALITY-R01/R03/R04：阅读分享诊断并核对正式移动、航行、动态建造和模块所有权。通过统一runner的隔离工程完成当前主场景结构观测：6个WalkArea、0个PhysicsBody3D/CollisionShape3D及引擎NavigationRegion3D/NavigationAgent3D，角色为脚本直接移动的Node3D；自由建造已按布局派生可站中心区域。架构门禁退出0（15个独立规则/存储服务、0问题）。初次临时探针字段误读导致退出124，修复后结构观测退出0，失败日志保留。局部专项、官方依据、推荐边界和未执行项见[复核记录](../../development/2026-10-29_workbuddy_movement_architecture_review.md)。本轮仅诊断和登记，未实施碰撞/NavMesh迁移；整体状态保持partial。

当前栈桥专项：rope-bounds 14项、walk-deck-fit 16项均0失败/退出0。它们不含本轮真实输入与渲染验收，不据此宣称全部穿透已消失；最终契约检查逐项结果保存在复核记录列出的工程外contract_checks.json。

同日按用户未来二楼/楼梯方向补充影响评估：建议角色胶囊碰撞与三维陆地导航；核对到XZ地面查询、固定路径高度和恢复时重设Y的限制。约15–25个正式脚本为初步适配规模，另计场景/导航资源和测试，未冻结实施或工期；普通楼梯斜坡代理与竖直梯子动作分开设计。详见复核记录“后续两层房间、楼梯与碰撞迁移范围评估”。本轮仅新增评估文档，未运行楼梯样板或修改现行玩法。

## 2026-11-07 主场景帧率诊断

SEA-QUALITY-R03：隔离实景约 5.7–6.0 FPS，泛光开关差别小；时钟信号每帧两次触发居民日程同步，单次约 75–78 ms。渲染、普通处理和函数级对照、失败记录与未执行项见[诊断记录](../../development/2026-11-07_frame_diagnosis.md)。仅诊断，待后续修复及真实玩家档验证。

## 2026-11-11 当前性能深审与无损优化方案

SEA-QUALITY-R01/R02/R03/R04/R05：通过统一runner隔离当前Godot4.7.2/Forward+/RTX4060Ti工作树，正式Main函数、真实海面/室内/潜水消融与微基准均已重测。1600×1000关闭VSync海面帧p50约9.77–9.89ms、GPU7.28–7.32ms/绘制2410–2450；正常限速p95约31–32ms尚需线程/呈现追踪。室内诊断停室外处理A/B/A为5.357→3.940→5.349ms，绘制259、图元65691、GPU约1.627ms不变，支持纯表现停机优先；诊断粗停不是正式可直接接入方案。工坊隐藏SubViewport实际0→打开4→关闭0，排除持续后台渲染误判。水下Main保留同一身份，20/41/80m机位不签全地图；单次内存往返未据此判泄漏。

visual-frame-functions、visual-frame-diagnosis、两轮visual-performance-audit与修正微基准均PASS/exit0；building-perf239/0、npc-performance61/0亦PASS/exit0。首次类型推断exit1与首次微探针字段错误exit0但runner FAIL均保留，错误样本不进入结论。Performance TIME计数滞后被明确排除归因。只新增审计探针、runner登记及文档，不改正式效果/玩法/存档/手摆transform，不接入性能改造；27项实施方案、证据路径、截图目检、警告、失败及未执行项见[完整审计记录](../../development/2026-11-11_performance_audit.md)。状态保持partial，发行包、真实玩家档、低端机、功耗及10次资源往返仍待测。最终契约同步exit1/75项、无参数exit1/77项（资产承接/哈希漂移/并发工坊摘要索引），未接受未知哈希；摆放6处/0警告与架构25服务/0问题均exit0。

## 2026-11-11 无损优化第一批实施

SEA-QUALITY-R01–R05：用户授权后落地14个正式源文件的等价范围，主场景transform、项目默认渲染配置、存档codec/schema及Boat/RoomController保持前快照。室内只裁纯表现提交，不停冷却/经营/时钟和公开资源root查询；CropView同阶段免遍历仍发公开信号；Interactor同轮reach与Main同次仲裁复用；HUD事件合并/笔记显示签名、晴天停重绘但模拟相位连续；Water静态dirty、BakeStore同t去重；1536原算法岸线单slot SHA256缓存。

串行两轮室内三组p50中位6.222→4.782ms（23.14%）、5.236→4.458ms（14.86%），最终版本4.664ms；259draw/65691图元保持。海面收益波动，不签稳定FPS增加。1536岸线最终冷1397.965→热71.886ms，18MiB原始RGF字节相等、热EDT0；首次冷算仍在。海面/室内同相位1600×1000对照差异像素0。真实房间、天气与原生MultiMesh缓存118/0均通过，35PNG产出但仅指定图目检。

最终functional-final12项PASS/exit0：equivalence19/0、room112/0、sleep42/0、npc-clock303/0、npc-perf61/0、building-perf239/0、坏档seed/protection、save-seed、framework-integration52/0、ocean-pickups48/0、fishery33/0；输入click/keyboard-panels/pick-mesh/facing/boat-contact和单测UI19/0、reach15/0、headless cache119/0、crops96/0亦通过。water-params与visual-corner-notebook仍失败，但工程外优化前src反向对照证实完全相同的10缺参/5旧UI标签，未新增或掩盖。初夹具错误及宿主中断日志保留、最终独立重跑补齐。

仅登记本轮改前hash与原账本一致且已审阅验证的Notebook source和WaterSurface runtime两处，不接受Main/HUD/Fishery等既有未知漂移。最终契约sync76项/exit1、无参数78项/exit1；新增断链已消除，摆放6/0与架构25/0 exit0。完整源码范围、前后证据、27项逐条状态、未执行/回退见[实施记录](../../development/2026-11-11_performance_optimization.md)。整体保持partial，不签release/Web/低端机、功耗或完整27项已完成。

## 2026-11-13 全工程深度审计（仅审计与整改计划）

承接现行SEA-QUALITY-R01–R05。基线94ec42e0、所有运行批次干净工作树；46功能/1073资产/1510运行资源，63项去重问题与方案（P1 14/P2 39/P3 10；动态15/静态29/待验14/裁决3/测试治理2），不等同63玩家事故，未修生产。

- 当前逻辑40项32通过8失败（含2个exit124）；整体exit1。35有数值终局入口仅小计11303/16，不作全轮断言总数。旧范围/替代支撑/迁址夹具与真实garden失败、级联分开。
- selftest当前499 passed/33 failed另1 SCRIPT ERROR，exit1，不沿用旧536/1；三视觉room/quick-tools/gift-kiosk均exit0，68PNG只目检3图，60条uniform索引冲突警告待验。
- 存档/玩法/菜园反例通过正式runner工程外注入，marker仅诊断完成；预期复现错误与常量拒写保留原红。静态架构25/0 exit0、摆位6/0 exit0、治理10/10 exit0，契约初查499 issues exit1，后续sync/check如实回填。
- 发现二进制hash归一化、水密passed漏谓词、架构正则覆盖、旧夹具/脚本异常/证据不可携等验收缺口，优先补反例，不删除断言/批量签hash造绿。

完整证据与B0–B4计划见[审计记录](../../development/2026-11-13_engine_deep_audit.md)。登记头保持partial；所有生产修复、全量视觉、发行设备/许可/断电/长期项未签。

## 2026-11-13 B0/B1 修复实施与回归

本节承接审计整改计划，记录用户授权后的实际修复，不覆写审计初始结果。

- B0：哈希门禁只对明确文本允许CRLF，二进制按原始字节；水密审计的boundary/nonmanifold/缺记录失败并返回非零；framework/farming/building/wood旧夹具同步当前开放海域、7格2床、重绑定支撑、家园3槽密度。工程治理测试17/0，`git diff --check` exit0。
- B1：SaveGame/schema解码守卫、future模块保护、语义备份择优、唯一归档、farm/weather/NPC日期校验、room busy/过场代次、energy generation、Interactor action target、NpcCareerPanel suspend/resume均已接入。新增save-boundaries独立runner和interactor-action-target入口。
- 最终B0/B1回归命令：framework-modules、farming、building-simulate、wood-bundles、save-boundaries、interactor-action-target、room、energy、npc-careers、save-corrupt-seed、save-protection、save-reset、save-seed、framework-integration；全部**exit0/PASS**，证据 `/Users/zyq/work/sea-work/verification/20261113-165935-b0-b1-final-20261113-f58f38`；治理17/0同批前置通过。
- 真实渲染：本批全部headless，无截图；预期故障/警告/未执行保持单列。npc-integration旧天台/菜园桥锚点前置仍未纳入本批通过，菜园空间归属另属后续B2，不改用户摆位/资产/容差迁就。
- 当前契约：B0/B1后`check_feature_contracts.py --sync` exit1/531 issues，无参exit1/532 issues；历史资产/链接/条款/索引问题及本次代码路径未补登记仍阻断，全局不签。架构25/0、摆位6/0保持通过；未提交/推送，未改main.tscn、godot/assets、assets、art_source或玩家正式存档。

## 2026-11-13 B2 G04 菜园桥专项验证

本批只涉及霓虹花园 NPC 站位、相关测试与三份功能记录；不运行编辑器/导入器，不改资产源或哈希。生产修复将菜园 `NpcStations` 本地高度对齐模型派生桥面实际代表层，保留 `SUPPORT_TOLERANCE=0.05`，避免以容差掩盖高度差。

- `garden-npc`：正式 runner，`exit=0`；新增 height mismatch/支撑断言通过，5/5 菜园锚点有效、聚合40、豆豆按日程落位且不 fallback。证据：`/Users/zyq/work/sea-work/verification/20261113-182110-b2-g04-garden-local-height-7d0e06`。
- `npc-integration`：正式 runner，真实退出 `124`；仍在既有天台站位/路径断言失败后超时，未完成 marker，不能签为 G04 全集成通过。证据：`/Users/zyq/work/sea-work/verification/20261113-182405-b2-g04-npc-integration-170faf`。
- `npc-save-seed`：正式 runner，真实退出 `1`；失败于既有天台站位前置与稳定支撑恢复浮点断言（457 checks / 3 failures），非 G04 菜园桥断言；因 seed 未通过，未运行 `npc-save-restart`，不伪造跨进程结果。证据：`/Users/zyq/work/sea-work/verification/20261113-183556-b2-g04-npc-save-seed-77f9cc`。

## 2026-11-14 B2 验证证据分层承接

承接SEA-QUALITY-R01–R05：005436-b2-production-closeout-e11fda五入口PASS/exit0、unexpected=[]：session51/0、transactions103/0、reset-atomic98/0、pickup191/0、bedside1800/0（130合法布局、133真实胶囊/到门、26正式approach含13绕行）。005741-b2-integrated-final-dde4f5为19入口18PASS，**save-protection旧开关断言FAIL/exit1**，未来字节不变/原槽拒绝/另槽成功不抵消此失败；新断言源码改为实际保护与倒计时冻结，补跑待父。

本轮NPC集成853/0、seed527/0、restart280/0及garden26/0等已PASS，覆盖上节旧前置阻塞但不抹旧124/1。早批b2-reset-atomic-results.json为unit0、五seed引擎-9/runner1预期SIGKILL、五recover0/0；不能称普通全PASS，且早于当前memento修订，不用早批hash签当前跨进程。

父已有治理17、架构25/0、摆位6/0及diff-check exit0仅按原批证据登记；本次纯文档未运行这些测试。契约531/532和并行后533/534均历史失败，父最终另跑；真实visual-room/garden/sleep、审图及精确字节身份待父追加，不沿旧图冒签。legacy management --full-world36/1旧farm_plot_a夹具不可签，不恢复zone3凑绿；全selftest/设备断电/磁盘满/多进程写/长时泄漏未执行，agent_radius/zone2_glass警告保留。登记头partial不变；[B2主记录及全部报告/未决占位](../../development/2026-11-13_engine_deep_audit.md#b2-业务事务与空间修复最终回填2026-11-14)。

### B2 最终状态（2026-11-14）· [主记录](../../development/2026-11-13_engine_deep_audit.md#b2-最后复测与签署范围2026-11-14)
- 当前去重33个最新入口33PASS/exit0（30逻辑+3视觉，非单批/全selftest）；005436生产5项全PASS，012421有效旧确认强化session53/0，010438十入口全exit0含修订save-protection，012647 management按当前zone3退役内容37/0、不恢复生产，旧36/1及旧save-protection失败保留。证据源SHA、日志/PNG冻结于`/Users/zyq/work/sea-work/audit-2026-11-13/evidence/b2-final-run-index.json`。

## 2026-11-14 B3 验收治理承接

B3专项最终回归`20261114-104347-b3-final-regression-20261114-6155e0`中10个入口均exit0（Goal/查询副本、建筑解环/漂移、framework及save-seed）；默认minimal与`--full-world` management均exit0。工程治理31/31、摆位6/0、架构25/0、diff-check均exit0。runner配置派生已隔离，旧management 37/4归因于profile夹具错配并保留原始证据。B3最终契约门禁sync/check分别535/536 issues、均exit1，未刷hash/派生；全局资产事实冻结、视觉警告、设备/发行/长期边界仍未签，登记头不升级。
- 当前012203重置矩阵unit0、五seed预期引擎-9/runner1、五recover0、外层0，详见`/Users/zyq/work/sea-work/b2-reset-atomic-results.json`；三视觉18PNG（room8/garden4/sleep6）仅目检room-inside/garden-bubble-single/sleep-wake，菜园作物遮下半身不能签足底美术，醒来图是室外太阳房非室内，其余15图未逐图审阅。
- 最终契约sync532/check533 issues均exit1，未写派生/刷hash；17治理/25架构/6摆位/diff-check均exit0仅据既有证据，本次未跑。uniform索引/agent_radius/zone2glass警告保留；设备断电/磁盘满/并发写/长时泄漏/全selftest未签，登记头partial不变，不称全工程绿。

## 2026-11-14 B4 安全视觉与发行验证承接

Q03材质实例槽位已通过显式`instance_index`统一；D05新增只读发行闭包审计，缺PCK/closure输入返回UNEXECUTED而非误报通过；A08新增隔离生命周期证据协议和严格预热/测量负例。tooling87/87、材质参数10份/51文件、Q04导航采集6入口均exit0。visual-room、visual-gift-kiosk、workshop-rules exit0且不再出现Q03同名槽位冲突；visual-quick-tools 261 checks/20 failures保留为1920x1080截图夹具错配。agent_radius/zone2_glass警告、真实生命周期、平台包/许可/设备故障和长期性能仍未签，登记头不升级。

## 2026-11-14 B4 截图尺寸夹具专项复测

SEA-QUALITY-R01/R03/R04/R05：只改`test_quick_tools.gd:save_frame`，从当前viewport可见逻辑尺寸乘stretch独立派生渲染像素尺寸，逐张精确相等且宽高为正；保留非空/PNG保存、场景状态标签和真实输入/动效/hover/隐藏/时钟断言，不改runner、Main、场景资产、摆位或玩法。原始20失败实际覆盖1600/1920两组，上节口径由本节补正，历史失败及两次中间exit1保留。

最终正式runner证据`/Users/zyq/work/sea-work/verification/20261114-122154-b4-quick-tools-render-rect-20261114-bb6420`：真实Godot4.7.2/Metal4/Forward+，**266 checks/0 failures，引擎与runner均exit0**，无unexpected_errors。30张PNG路径及逐图IHDR/尺寸/标签矩阵在`png-size-evidence.json`，截图在`project/outputs/quick-tools-{1280x800,1600x1000,1920x1080}-{land,boat}-{opening,open,hover,closing,closed}.png`；本机原生窗口受限，三组实际PNG分别1280×800、1484×928、1649×928，不冒签原生1920×1080覆盖。仅目检1280 land-open与1920标签boat-hover两图，其他28张未逐图人工审阅；跨平台/DPI/设备、完整潜水往返及发行/长期可靠性未执行。`agent_radius`/`zone2_glass`警告保留，Q03 uniform槽位冲突未再出现；登记头partial不变。完整命令、过程红项及边界见[本轮记录](../../development/2026-11-13_engine_deep_audit.md#b4-visual-quick-tools-截图尺寸夹具修复2026-11-14)。本轮tooling重新实测87/87、exit0，diff-check exit0；契约sync535/check536 issues、均exit1，未刷hash/派生索引，不签全工程绿。

## 2026-11-14 B3/B4 最新工程外证据收尾（仅文档追加）

承接SEA-QUALITY-R01–R05，登记头partial及历史原文不变；现行spec已包含真实退出码、预期故障/未执行、独立视觉和失败保留要求，本次无需增改spec条款。[完整收尾与逐批路径](../../development/2026-11-13_engine_deep_audit.md#2026-11-14-b3b4-文档收尾与最新工程外证据)为统一回链。

- B3已有10逻辑入口PASS/exit0，management minimal/full-world各exit0；治理31/31、架构25/0、摆位6/0、diff-check exit0。契约最近实跑sync535/check536 issues、均exit1；本次与最新工程外收集器均未执行契约sync/check，不拿历史数字当追加后的新检查。
- B4已实现Q03共享槽位、D05只读闭包与A08采样证据协议；quick-tools尺寸夹具修复已有266/0、engine0/runner0，114407批room/gift/workshop各入口exit0但整批非全绿。最新证据根`/Users/zyq/work/sea-work/b4-validation-closeout-20261114/`的`b4-validation-summary.md/json`记录tooling87/87、material params 10登记/51文件、Q04六入口均exit0；workshop最新879/0、engine0/runner0为headless，不充当视觉证明。
- 首轮`verification/20261114-123153-b4-closeout-visual-e5b769/report.json`总runner1：quick102/2、engine1、marker=false、0PNG，失败为航行潜水消费/先停船提示，不是历史261/20尺寸错配；room engine124、marker=false、仅outside/door两PNG。独立quick`124023-…-58b845`为266/0、engine0/runner0、30PNG，独立room`124128-…-3576f7`为engine0/runner0、8PNG。两者首轮/独立各核对2835源文件差异0；只能签无改动复测可通过，根因未证，不签稳定性，首轮FAIL不转expected。
- gift在123153首轮合批runner1中自身engine0、53/0、passed/marker=true、30PNG；不能把整批runner1改成0，也不能误称gift引擎失败。用户补充后续独立视觉通过；所读摘要未附对应独立report/退出码，本次按用户补充登记，不冒填路径或混用早批114407。已有图片目检范围沿摘要列明，本次未新增审图，不宣称全PNG目检或原生大分辨率覆盖。
- D05 `release-closure-no-input.json`、A08 `a08-lifecycle-no-input.json`均为**UNEXECUTED/exit2**。真正daily_release/export与A08长期矩阵未启动命令，仍UNEXECUTED/exit=null；87个协议/合成单测不证明真实PCK/许可或WeakRef/Callable长期释放。
- 当前`/Users/zyq/work/sea-work/b2-reset-atomic-results.json`及11份原报告已更新：124724单位批engine0/runner0；124828–124832的intent/archive/replace/commit/future五seed均engine-9/runner1、expected_sigkill=true，五recover均engine0/runner0。此为当前矩阵的已有重跑，不是本次文档作业运行；收集器“历史引用未重跑”的描述仅属于它自己的采集批。accepted=true不抹seed非零，不签物理断电、目录fsync、磁盘满或并发写。

B4发行包/许可闭包、设备/跨平台、长期生命周期/性能仍未完成；agent_radius/zone2_glass/2D MSAA警告保留，不签零警告或零泄漏。审计没有B5；不升级verified。本次只追加指定六文档，不改代码/测试/runner/资产/登记JSON，不刷hash、不删R18事务文件，不启动Godot或sync；共享工作区既有他人修改全部保留。

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

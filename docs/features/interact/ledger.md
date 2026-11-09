# SEA-INTERACT · 点击与长按交互 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-interact) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-INTERACT",
  "status": "partial",
  "owner": "Interactor / Interactable / ActorController",
  "code_paths": [
    "godot/src/interaction"
  ],
  "verification": [
    "npc-conversation",
    "visual-npc-conversation",
    "facing-interaction",
    "visual-facing-interaction",
    "keyboard-farm-loop",
    "visual-keyboard-farm-loop",
    "keyboard-travel",
    "interaction-reach",
    "control-feel",
    "keyboard-control",
    "visual-corner-notebook",
    "click",
    "surface",
    "framework-integration",
    "visual-pocket-bubbles",
    "visual-plot-shipping",
    "interact-focus",
    "board-click",
    "unreachable-menu",
    "pick-mesh",
    "sea-supply"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-INTERACT-R01 | 现有交互查询与拒绝反馈；click/selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-INTERACT-R02 | cancel清除进度、锁定和自动输入；取消回调集成通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-INTERACT-R03 | 模态阻断auto_hold，精确目标接近；click与集成通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-INTERACT-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |

## 资源与调用入口

- [godot/src/interaction](../../../godot/src/interaction)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

Interactor.cancel / update；completed、blocked；ActorController.approach / complete_interaction / cancel。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py click surface framework-integration`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 click、surface 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

- 2026-10-23 真实事件补充：visual-click 退出 1，第二地格点击目标断言失败；拆分前基线同样失败，完整根因待定位。不得以核心 click 通过覆盖此失败。详见[交付记录](../../development/2026-10-23_feature_split.md)。

## 遗留与下一步

Main 保留输入路由；接近、自动按住及完成释放由 ActorController 状态管理，交互类型不拥有种植或订单规则。

## 变更记录

SEA-INTERACT-R11初始六格修复：固定六格与DIY格使用同一操作点算法；已靠泊船上的路径起点统一为泊位站立点。初始六格真实输入专项覆盖菜单、选种、接近、浇水、补水与显式收获。[实测](../../development/2026-10-29_initial_six_planters.md)。

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INTERACT-R11 | 接近按三维操作点求路，Interactor通过注入空间过滤；业务结算未改 | [角色框架实测](../../development/2026-10-29_character_physics_framework.md) |

SEA-INTERACT-R11：接近/可达性接高度查询，Interactor新增注入空间过滤端口；交互结算未改。验证与局限见[本轮交付](../../development/2026-10-29_character_physics_framework.md)。

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-26 功能与健康审计

SEA-INTERACT-R01/R02/R03：click 30项通过；真实visual-click有5项失败（种植入口、视角面板、保存按钮、第二地格命中、退出打捞），需区分旧UI测试假设与实际输入问题，保持partial。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

Main 保留输入路由；接近、自动按住及完成释放由 ActorController 状态管理，交互类型不拥有种植或订单规则。

新增条款 SEA-INTERACT-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-28 场景气泡与口袋界面

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INTERACT-R05 | 已实现；实际渲染与输入专项通过；设备/授权边界单列 | [交付记录](../../development/2026-10-28_pocket_action_bubbles.md) |

本轮运行结果、过程失败、退出码与未执行项集中记在交付记录。旧记录保留为历史，整体状态仍partial。


## 2026-10-28 HUD与笔记表现接线

展开的图标菜单也属于模态阻断，外点收起先消费点击。泊位自身船锚已承担悬停反馈，HoverCard对landing保留target与指针但不显示第二颗手形图标；其它交互物的小操作图标和气泡不变。

对应SEA-UI-R35–R38；[本轮交付](../../development/2026-10-28_corner_hud_notebook.md)。本功能整体状态与玩法边界保留。

## 2026-10-29 热区跟随物体

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INTERACT-R06 | 已实现；锚点由视觉包围盒推导，接近/自动长按/判定/图标/编辑器预览同源；14项专项及61项完整种植出货真实输入通过 | [锚点交付](../../development/2026-10-29_interact_focus_follows_object.md)；[本轮补齐与实测](../../development/2026-10-29_walk_on_planters.md) |

出货箱热区曾偏离物体 2.065 米（半径 2.4 米），根因是锚点写死节点原点而视觉带偏移。
本轮统一到 `Interactable.focus_position()`，全场景最差偏差由 2.065 米降到 0.0000 米。

新增 `interact-focus` 专项：8 项断言，实测 `8 checks, 0 failures`，退出 0。
同轮复跑 farming / modules / parity / ocean 均通过；click 3 项、management 4 项失败为
既有的航行与区块复原问题，与本轮改动无关（见交付记录末尾说明）。整体状态仍 partial。

## 2026-10-29 点船上船与图标换宿主

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INTERACT-R07 | 已实现；图标宿主随点击含义切换，船体可点 | [交付记录](../../development/2026-10-29_click_boat_to_board.md) |

根因：图标一律钉在 `dockEdge`，而船停在旁边 2.49 米处（zone5），俯视图标看起来压在船上；
且 `boat.gd` 没有拾取入口，点船体无反应。

新增 `board-click` 专项：12 项断言，实测 `12 checks, 0 failures`，退出 0。
同轮复跑 interact-focus / farming / modules / parity / ocean / camera 均通过。
click 的 3 项失败为既有的航行与区块复原问题，与本轮无关。整体状态仍 partial。

## 2026-10-29 移除世界里的聚焦环

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INTERACT-R08 | 已实现；`Interactable` 不再建任何 3D 焦点指示，焦点只走文案与悬浮图标 | [交付记录](../../development/2026-10-29_remove_focus_ring.md) |

根因：环按视觉包围盒放大（上限 3 倍），多格菜箱的包围盒覆盖整张培养甲板，
环被撑到直径约 3.4 米；抬高的土箱又把它切成几段，俯视时就是甲板上一道无意义的白弧。

场景装配后遍历整棵树：`FocusRing` 节点数 0。`interact-focus` / `farming` / `modules` /
`parity` 同轮复跑均退出 0。焦点状态、HUD 文案、悬浮卡片、编辑器热区预览均未改动，
整体状态仍 partial。


## 2026-10-29 到不了的地方也要能点出菜单

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INTERACT-R09 | 已实现；命中改为物体包围盒、菜单锚点兜底、走不到时逐项写明原因 | [交付记录](../../development/2026-10-29_unreachable_interaction_menu.md) |

根因是三处叠加，任一处都足以让「点了没反应」：

1. `HoverCard._pick()` 只认图标中心 30 px，而图标是命中之后才画的 —— 物体本体点不中。
   实测 z1 出货箱：箱体屏幕包围盒 240×275 px，本体中心离图标 775 px。
2. `_bubble_anchor()` 在投影出屏时返回 null，`_place()` 立刻 `close(true)` ——
   隔水看对面平台时锚点落在视口外，菜单开一帧就关。
3. `approach_action.execute()` 的 `area == null` / `start_walk` 失败都是静默 return false。

新增 `unreachable-menu` 专项：25 项断言，实测 `25 checks, 0 failures`，退出 0。
覆盖：点包围盒最远角（离图标 192 px）仍命中、24×24 米巨型包围盒不吞甲板、
菜单 40 帧后仍开且不压右上角、菜箱→种植→选种子的二级菜单、
跨区目标每项写原因且标题就是那句原因、灰项 toast、海面中央交互点接近有提示。

同轮复跑 interact-focus / board-click / farming / modules / building-integration /
pocket-bubbles / visual-pocket-bubbles 均退出 0。

`click` 的 3 项失败（新航线取消旧拾取、航行途中改道、建造菜单前往并自动交付）
用 HEAD 版本对照复跑，结果完全一致（32 checks, 3 failures），属既有航行与
区块复原问题，与本轮无关。整体状态仍 partial。

## 2026-10-29 热区按模型本体算

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INTERACT-R10 | 已实现；命中改为相机射线打模型三角形 | `pick-mesh` 9 项 0 失败；[交付记录](../../development/2026-10-29_pick_hotspot_follows_mesh.md) |

根因：上一轮把命中改成「物体屏幕 AABB 外扩 10 px」。单个物件没问题，
但 zone5 六个土箱并排，格心间距 2.15×2.575 米、模型 footprint 1.79×1.58 米，
真实缝隙只有约 0.36×0.99 米，俯视 9 米机位下屏幕上十几像素宽；
两侧 AABB 各外扩 10 px 就把整条缝盖满 —— 点甲板缝被判成点土箱，
既不走也不弹菜单。`BODY_AREA_LIMIT` 挡不住：单个土箱面积远低于阈值，
问题出在外扩叠加，不是单块太大。

改为射线 vs 三角形（Möller–Trumbore），gated by mesh 自身 OBB 粗筛。
实测面数：土箱 84、出货箱 752、告示牌 336，全部远低于 1500 阈值。
图标 30 px 只保留给没有几何的纯逻辑点（睡眠位）。
同一位置模型命中优先于图标热区。

同轮修掉 `hud.gd:924` 的 `var moved: bool = a if c else b`——
Godot 4.6 推断不出类型，整份 hud.gd 解析失败并连带 main.tscn 无法加载（1115 条
SCRIPT ERROR）。那是并行改动留下的，但会挡住所有验证，故改为显式 if/else。

同轮复跑 pick-mesh / unreachable-menu / interact-focus / board-click / farming /
modules / pocket-bubbles / building-approach 全部退出 0。整体状态仍 partial。

## 2026-10-31 结构物交互点

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-INTERACT-R12 | 已实现；`Objects/SupplyCounter` 挂在补给站正面招牌下的甲板上（`focus_anchor=node`，锚点 y=2.514），`interact()` 只发 `opened` 信号，组合根 `main._open_supply` 打开既有商店页；专项断言「靠妥 → 走到点（≤2 米）→ 按 E 使 `hud._tab=="shop"` 且面板打开」整条链路。 | `sea-supply` 37 项 0 失败；[接入记录](../../development/2026-10-31_sea_supply_station.md) |

## 2026-11-05 E 键上下船

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-INTERACT-R13 | 已实现；`_toggle_boat_by_key()` 复用 `_depart`/`_step_ashore`，泊位旁 2.4 米内按 E 上船、船上停稳按 E 上岸；有交互焦点时按距离让位给采集；提示条新增无焦点时的 `E 上船`/`E 上岸` | `keyboard-control`（上船、上岸、更近目标时不抢 E）；[本轮交付](../../development/2026-11-05_keyboard_control.md)。提示条外观的真实渲染截图未单独出。 |

## 2026-11-05 上下船去抖

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-INTERACT-R14 | 已实现；成功切换后 `BOAT_KEY_COOLDOWN` 0.35 s 内不再响应，`boarding` 过场单独挡掉 | `keyboard-control`、`control-feel`（第一次生效、第二次被吞）；[本轮交付](../../development/2026-11-05_control_feel.md)。冷却只作用于上下船。 |

## 2026-11-06 键盘可达性

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-INTERACT-R15 | 已实现；`_sea_pick_candidate` 只读查询 + `_press_boat_key` 分派，动作复用 `_handle_prop_click`；提示条与分派共用同一优先级 | `interaction-reach`（船边候选、提示文案、E 进入并跑完整条打捞链） |
| SEA-INTERACT-R16 | 已实现；`_near_landing_key()` 8 米内按最近泊位走 `_select_landing` | `interaction-reach`（离泊 2.2 米仍认得出泊位、E 靠回去并上岸）、`dock-seed`、`board-click` 复跑通过 |
| SEA-INTERACT-R17 | 已实现；`world_action_bubbles.press_default/index_for_key` + 气泡键位角标 + `main._unhandled_input` 的菜单分支 | `interaction-reach`（E 弹菜单、角标、数字映射、越界不选中、按号消费） |
| SEA-INTERACT-R18 | 已实现；`_setup_prompt` 恢复 `enabled = true`，徽标由 `spot.verb` 改为 `E`，空进度槽隐藏，提示条上移 14 px | `visual-interaction-reach`（真实渲染两张，采集焦点与上岸提示） |

[本轮交付](../../development/2026-11-06_keyboard_reach.md)。

## 2026-11-06 全键盘入口与近距图标（当前口径）

登记头仍为 `partial`。上午 R17 角标/R18 底部 prompt 的记录保留为历史；当前由 R19–R21 与 SEA-UI-R54 覆盖，不把旧截图当本轮视觉验收。

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-INTERACT-R19 | 近距稳定循环、同一显式选中目标优先E专项通过 | 200446报告farm606/0、travel374/0，均exit0、passed=true |
| SEA-INTERACT-R20 | 松开防连发、held-keys/echo/同帧保护与菜单不穿透专项通过 | 同一报告farm606/0、keyboard-control30/0、control-feel31/0、click32/0；194828真实渲染farm617/0 |
| SEA-INTERACT-R21 | 默认选中、方向/四种确认/数字与二级Esc返回专项通过 | farm606/0、visual617/0；完整路径见[总交付与矩阵](../../development/2026-11-06_keyboard_complete.md) |

- 证据根 `D:/projects/sea-work/verification/`：`20261106-200446-keyboard-release-regression-eae88a/report.json` 已含18项结果（14通过、4失败）；`20261106-194828-keyboard-visual-travel-final-09cca9/report.json` 的visual-farm617/0、travel374/0均exit0、passed=true，无unexpected_errors，9张唯一截图。本轮画面目视审阅watered/full-bag/harvest-overhead/already-watered确认无底部条及键位教程。
- 旅行旧374/0但负Rect造成runner FAIL仍保留为过程；`.abs()`修后两份最终report均通过，不再列修后待跑。
- interaction-reach35/1（第一项角标1）、dock-seed21/1（二级层级标题）、minimum-loop141/10（直接harvest及下游库存/出货）、harvest-receive80/1（E直接收获）均exit1，**属于本轮回归承接，不标范围外**。适配后`20261106-201957-keyboard-contract-regression-888baa/report.json`已通过interaction-reach35/0、dock-seed22/0、minimum-loop147/0、harvest-receive92/0，四项exit0、passed=true、completion_marker=true、unexpected_errors空；不再待填，仅主线程keyboard-final-contracts最终合批待附。
- 用户无提示新要求覆盖R18及UI-R52，原hover近距图标/进度与状态灰因保留，底部prompt与世界角标/教程行关闭。主动系统帮助是允许项；重新核实当前口袋源码已删除按1购买句与动作数字前缀，仅保留上限/余额/库存及动词数量，对应同步差异已解决，见总交付。
- 四功能仍partial；本次仅回填原文档及verification数组，不运行检查/sync，不动生产、哈希、用户TSCN或building文档。

## 2026-11-07 正面交互与泊位防误触

| 对应设计条款 | 当前实施状态 | 最终实测证据 / 边界 |
|---|---|---|
| SEA-INTERACT-R22 | 已实现并通过最终合批；角色+Z水平dot≥0.55、中心0.35m豁免；Q仅正面、离面失效；只有auto_hold+preferred明确自动目标绕过朝向，沿原hold一次消费命令 | `D:/projects/sea-work/verification/20261107-165822-movement-feel-final-9b7646/report.json`：当前真实Main的`facing-interaction`102/0、`visual-facing-interaction`105/0、farm636/0、travel374/0，均PASS/exit0、完成标记真、unexpected_errors空。farm改为先面对再逐格Q lock，保留六格入口、不偷移位置及Q不触发业务断言；`D:/projects/sea-work/verification/20261107-170723-movement-feel-render-final-950cd8/report.json`的visual-keyboard-farm-loop647/0与真shore163769/0双PASS/exit0无unexpected_errors，主任务已目检最新facing plot，面向格近距图标正确、无教程。[总交付](../../development/2026-11-07_movement_feel_refinement.md)。 |
| SEA-INTERACT-R23 | 已实现并通过最终合批；上船朝boat≥0.60、spot默认优先、boat alignment高出至少0.15可胜、Q明确spot保护；near与E同胜者。near dock朝park≥0.20（中心≤0.5m豁免）且plan_route非空 | 同一165822报告朝向102/0、视觉105/0及`interaction-reach`35/0通过；11项全PASS。NPC新世界端口由独立装配修复，已注入权威world_clock、enabled query并接owned_modal_input；旧NPC与菜箱重合/抢点失败仅作历史，不再pending；`D:/projects/sea-work/verification/20261107-172123-movement-latest-smoke-ed1994/report.json`的facing102/0 PASS进一步确认NPC/dive最新装配可启动，不外推为整套潜水完成。 |

继续沿SEA-UI-R54只显示原near图标/进度，`prompt.enabled=false`，无底部键位条/气泡教程；NPC与用户手摆未为凑测试挪位，旧断言未放宽，render与visualfarm不再待验。171743兼容批六项仅actor-presentation PASS：当时潜水并发重构、本地WorldEnvironment缺失，click32/3、board12/0、dock22/0、save10/0、water41/0全部runner FAIL，零失败断言不能代替runner PASS。新版Main已接DiveSession，172517-movement-current-compatible-8e5f98五项最终均runner PASS（board12/0、dock22/0、save10/0、boat-water-contact41/0、shift56/0）、exit0且无unexpected_errors；不修整套潜水或代签旧click潜水三项。功能仍`partial`；主任务17:16已执行sync20 issues、普通check21（43features/930assets/1255runtime），未强刷哈希；placed positions4项PASS/0warnings与本轮diffcheck通过，详见总交付。本次回填不改生产、GDD、registry/hash/TSCN。

## 2026-11-07 触发式交互

| 对应设计条款 | 当前实施状态 | 最终实测证据 / 边界 |
|---|---|---|
| SEA-INTERACT-R24 | 已实现并通过：`hold_time` 改为动作时长，种植格 0 瞬发；`acting`/`_acted_once`/`_wait_release` 重定义；`queue_command` 清闸门；`cancel` 只设「等松开」不开闸门 | `D:/projects/sea-work/verification/20261108-025201-clean1-d01069/report.json`：facing-interaction、control-feel、interaction-reach、keyboard-travel、keyboard-farm-loop、harvest-receive 六项全 PASS/exit0；`D:/projects/sea-work/verification/20261108-030208-sweep2-006789/report.json` 十三项（含 keyboard-panels/building/control、click、dock-seed、board-click、minimum-loop、initial-planters、farm-day-change）全 PASS/exit0。[总交付](../../development/2026-11-07_trigger_interaction.md)。 |
| SEA-INTERACT-R25 | 已实现并通过：候选不再按朝向过滤；`_refresh_target()` 按 `FACING_TIE=0.08` 分档比朝向→距离→优先级；新增 `refresh_now()` 供仲裁同步取焦点 | 同一 20261108-025201 报告 facing-interaction 与 keyboard-travel 全绿；`interaction-reach` 中「3 米处提示为空但 E 仍打捞」的一致性缺陷已修（`_boat_shortcut_text()` 补同源兜底）。农场夹具与 selftest 的采集打断断言已按触发式契约改写（不再等 hold 累积，改为验证动作被位移中止）。 |
| SEA-INTERACT-R26 | 已实现并通过：`_actor_in_boarding_zone()`（站立点 2.4 m 或船体 3.0 m）、`_near_landing_key()` 删船头 0.20 方向锥改热区 + 0.4 s 可航缓存、`DOCK_SETTLE_TOLERANCE` 统一 1.6 m | 20261108-031934-marker1-4f2e1f：facing-interaction、keyboard-travel、interaction-reach、control-feel 四项 PASS/exit0；`D:/projects/sea-work/verification/20261108-032313-visual-mark-a4fa46/report.json` visual-facing-interaction PASS，实景截图确认船体只剩一个锚图标。 |
| SEA-INTERACT-R27 | 已实现并通过：`_near_action()` 为唯一仲裁源，`_activate_near_action()` 替换原匿名 lambda（原来 `"leave"` 会掉进 else 误触打捞）；`_boat_shortcut_text()` 与 `_press_boat_key()` 对远距 pick 同源；`markers.suppress_query` 让码头标记在上船档让位 | `D:/projects/sea-work/verification/20261108-032620-visual-mark2-b3156f/report.json` visual-keyboard-farm-loop PASS；实景目检：种植格旁只出种植图标、底部无提示条与进度条，水面锚图标为常驻码头路标（不同目标，非重影）。 |

复用证据边界：`selftest` 仍 508 passed / 24 failed，失败集合与 2026-11-07 基线（190002-dive-map-switch-final）逐条比对只差三项浮动项（打捞冷却读数、航路长度数值、泊位两两可达条数），属既有历史失败，非本节引入；`keyboard-panels` 与 `minimum-loop` 的两处失败已定位为**范围外的前序改动**（作物表由 3 种扩到 6 种导致笔记页数变化；shop 命令改为独立商店面板）并已按新事实修正断言，非本节回归。整体仍 `partial`。


## 2026-11-08 NPC先对话再进入功能

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-INTERACT-R28 | implemented；最终验收回填见本节后续记录 | `npc-conversation`、`visual-npc-conversation`及相关规则/存档回归；实现与验收路径见[开发记录](../../development/2026-11-08_npc_conversation.md)。 |


### 本次最终验收签署

本节新增条款已实现并完成当前交互验收。13个独立入口5040/0，均exit0且unexpected_errors为空：NPC主场景473/0、真实渲染498/0（25张最终PNG全部状态已审）、规则655/0、世界136/0、资料话题1387/0、增量性能61/0、商店260/0、整局存档702/0、seed476/0、不同进程restart202/0、最小循环112/0、开场键盘39/0、点击39/0。报告选择、截图像素、逐图审阅、过程FAIL与最终覆盖均见[开发记录最终签署](../../development/2026-11-08_npc_conversation.md#最终签署本次交互专项通过2026-11-08)。资产/运行资源哈希门禁sync45、check46项仍FAIL/exit1，原基线漂移未批量重签；不以专项通过冒充全工程通过。手柄/触屏、低端/发行包、全部剧情人工游玩未执行，整体功能非完整产品verified。


## 2026-11-09 靠泊热点（park 合法化 + 已在旁边认领）

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-INTERACT-R29 | implemented；`_landing_data()` 归一化 park（≤3.5 m，带按原始值失效的缓存）、`building_access.landing_data()` 同规则、`_select_landing()` 新增「认领 + 滑入」一档（≤3.0 m 且直线可滑）、`_near_landing_key()` 与其同源、`_sail_to_landing()` 以路径终点为航行目标 | `dock-hotspot` 31/0 PASS，exit0，`D:/projects/sea-work/verification/20261109-171130-dock-hotspot-r6-f1015c/report.json`；终版复跑 `D:/projects/sea-work/verification/20261109-181016-final-regress-b44d74/report.json`（`dock-hotspot`/`camera`/`dock-seed`/`board-click`/`interaction-reach`/`interact-focus` 全 PASS）；改动前同用例 11 项失败且报「无法到达该泊位」（`D:/projects/sea-work/verification/20261109-171040-dock-hotspot-baseline3-836e50/report.json`）。同批 `dock-seed`、`board-click`、`interaction-reach`、`interact-focus`、`sea-supply`、`ocean` 复跑 PASS；`click` 的 runner FAIL 来自在飞的水下 shader（`CAMERA_POSITION_WORLD` 未知标识符，39 checks 0 failures），与本条无关。[本轮交付](../../development/2026-11-09_dock_hotspot_and_zoom_range.md)。 |

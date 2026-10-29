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
    "visual-corner-notebook",
    "click",
    "surface",
    "framework-integration",
    "visual-pocket-bubbles",
    "visual-plot-shipping",
    "interact-focus",
    "board-click",
    "unreachable-menu",
    "pick-mesh"
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
| SEA-INTERACT-R06 | 已实现；锚点由视觉包围盒推导，判定/图标/编辑器预览同源 | [交付记录](../../development/2026-10-29_interact_focus_follows_object.md) |

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

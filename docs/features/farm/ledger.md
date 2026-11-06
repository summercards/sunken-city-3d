# SEA-FARM · 种植与日常照料 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-farm) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-FARM",
  "status": "partial",
  "owner": "Farm / FarmField 场景适配",
  "code_paths": [
    "godot/src/farming",
    "godot/assets/data/crops.json",
    "godot/scenes/props/farm_plot.tscn",
    "godot/scenes/props/farm_cell.tscn"
  ],
  "verification": [
    "keyboard-farm-loop",
    "visual-keyboard-farm-loop",
    "keyboard-travel",
    "keyboard-panels",
    "visual-corner-notebook",
    "farming",
    "management",
    "modules",
    "framework-integration",
    "minimum-loop",
    "visual-plot-shipping",
    "initial-planters",
    "visual-initial-planters",
    "harvest-receive",
    "visual-harvest-receive",
    "farm-day-change"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-FARM-R01 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-FARM-R02 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-FARM-R03 | 容量、余额及多茬逻辑；farming/management通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FARM-R04 | farm v2与旧秒制迁移；farming/selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FARM-R05 | 无Autoload modules通过；场景显式注入Farm | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-FARM-R06 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |
| SEA-FARM-R07 | 已实现并专项核验 | [边界补强记录](../../development/2026-10-27_framework_boundary_hardening.md) |
| SEA-FARM-R08 | 已改用世界气泡，选择后接近并消费一次；实际鼠标三日种植/收获/出货通过 | [本轮证据](../../development/2026-10-28_pocket_action_bubbles.md) |
| SEA-FARM-R09 | 已实现，场景点击与存读专项验证 | [本轮证据](../../development/2026-10-27_plot_shipping_loop.md) |
| SEA-FARM-R11 | 已实现；双尺寸动态地格、带作物搬移/读档和空格注销验证通过 | [本轮交付](../../development/2026-10-29_open_ocean_building.md) |
| SEA-FARM-R12 | 已实现；六格真实输入247项、真实渲染250项及玩家档副本40项通过；新局显式登记、旧档保留作物和重复登记不重置通过 | [本轮交付](../../development/2026-10-29_initial_six_planters.md) |
| SEA-FARM-R13 | 已实现；三品种原产量只结算一次，正式鼠标收获只启动一次动画，满包不改作物且不庆祝；取消/恢复不重发奖励 | `harvest-receive`、`visual-harvest-receive`及farming回归；[本轮交付](../../development/2026-10-30_harvest_receive_animation.md) |

## 资源与调用入口

- [godot/src/farming](../../../godot/src/farming)
- [godot/assets/data/crops.json](../../../godot/assets/data/crops.json)
- [godot/scenes/props/farm_plot.tscn](../../../godot/scenes/props/farm_plot.tscn)
- [godot/scenes/props/farm_cell.tscn](../../../godot/scenes/props/farm_cell.tscn)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

configure；plant / water / harvest / advance_day / access_reason；register_plot / clear_plot_specs；plots_changed；farm v2 to_dict/from_dict。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py farming management modules framework-integration`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 farming、management、modules 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

Farm 的规则端口保留；FarmField/FarmPlot 显式注入 Farm，不再访问全局 Economy。开垦、工具升级、品质和季节仍为规划。

## 变更记录

2026-10-29 SEA-FARM-R11关联验证：穿越前后作物/水分/生长快照一致，成熟不自动收获；正常操作仍走原Farm命令，Farm代码未改。[通行实测](../../development/2026-10-29_walk_on_planters.md)。

- 2026-10-28：完成可建木板上放置种植箱的静态研究；确认可复用单格预制体及Farm规则，待补增量登记、交互接线与先登记后恢复作物的存档链路。[研究方案](../../development/2026-10-28_buildable_deck_planters_research.md)。现有种植状态与实现不变，未执行运行验收。

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-27 模块框架落地

Farm 的规则端口保留；FarmField/FarmPlot 显式注入 Farm，不再访问全局 Economy。开垦、工具升级、品质和季节仍为规划。

新增条款 SEA-FARM-R06 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-27 查询与恢复边界补强

state/spec/crop_def/plot_specs/crop_definitions 深副本；debug_set_growth 仅截图调试使用；modules31项覆盖。

[本轮实测记录](../../development/2026-10-27_framework_boundary_hardening.md)。

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

2026-10-27 场景点击循环：07:00收货、瓶盖、木土种植格及码头出货箱；[本轮记录](../../development/2026-10-27_plot_shipping_loop.md)。

2026-10-28：R08输入与视图更新；`visual-plot-shipping`覆盖按气泡播种/浇水/收获、已浇水拒绝、仅显示持有种子、07:00出货及存读。

## 2026-10-28 种植一律走种子二级

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-FARM-R09 | 已实现；单一种子也弹二级并标数量 | `dock-seed` 5 项断言；`visual-plot-menu` 真实点击两张截图 |
| SEA-FARM-R10 | 已实现；簇按包围盒夹取 | `visual-plot-menu` 锚点居中与靠边两种情况 |

[本轮记录](../../development/2026-10-28_dock_seed_weather_asset_fix.md)。


## 2026-10-28 HUD与笔记表现接线

种植入口归入海岛笔记的种植分类。UI读取crop_definitions、grow_days、yield_of、plot_specs、state、status_text与access_reason展示真实资料和地格状态；前往地格仍经plot_focus_requested，播种/浇水/收获继续在世界气泡中明确选择。规则和状态所有权保持Farm。

对应SEA-UI-R35–R38；[本轮交付](../../development/2026-10-28_corner_hud_notebook.md)。本功能整体状态与玩法边界保留。

## 2026-10-29 家园建造接入

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-FARM-R11 | 已实现；相关专项通过，详细范围以交付记录为准 | [本轮交付](../../development/2026-10-28_building_delivery.md) |

## 2026-11-01 作物按「天」结算

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-FARM-R14 | 已实现；`advance_to_day(calendar_day)` 为唯一换天入口并带 `grow_day` 水位线，醒来即生长、07:00 不重复、缺水停长、读档与旧档均不重长（23 项 0 失败） | [本轮交付](../../development/2026-11-01_farm_day_change.md) |

修订说明：本条取代 R02/R11 中「07:00 生长」的时机表述 —— 生长改为在睡觉醒来那一刻发生，07:00 只保留出货结算。R02 的「只推进一次已浇水作物」「缺水只停长」两件事不变，只是时刻提前。

## 2026-11-06 默认种植区全键盘闭环

登记头 `status: partial` 保持；默认键盘种植专项及四项旧契约适配回归已通过；主线程keyboard-final-contracts最终合批待附，不影响已接受结果。证据根为 `D:/projects/sea-work/verification/`。

| 对应设计条款 | 当前实施状态 | 实测证据 |
|---|---|---|
| SEA-FARM-R15 | 近距循环、选中目标E优先、成熟也先开菜单、二级返回与防连发专项通过 | `20261106-200446-keyboard-release-regression-eae88a/report.json`：keyboard-farm-loop606/0、travel374/0，均exit0、passed=true |
| SEA-FARM-R16 | 原命令播种/照料/三次床铺换天/收获/再播种、拒绝与成功一次表现专项通过 | 同一headless报告farm606/0；`20261106-194828-keyboard-visual-travel-final-09cca9/report.json`：visual-keyboard-farm-loop617/0、exit0、真实1280×800；9张唯一截图，本轮画面目视审阅4张确认无底部条/键位教程 |

同批回归 initial-planters247/0、walk-on-planters53/0、farm-day-change23/0通过。minimum-loop141/10（scene harvest及库存/仓储/出货连锁断言）、harvest-receive80/1（旧E直接收获预期）、dock-seed21/1（旧二级标题预期）、interaction-reach35/1（旧角标预期）均exit1，作为本轮过程失败保留，不标范围外。新菜单/无角标契约适配后，`20261106-201957-keyboard-contract-regression-888baa/report.json`：minimum-loop147/0、harvest-receive92/0、dock-seed22/0、interaction-reach35/0，四项均exit0、passed=true、completion_marker=true、unexpected_errors空；已收口，不再pending。主线程keyboard-final-contracts包含面板及旧pocket回归的最终批次待附。

旅行旧轮374/0但负Rect导致runner FAIL的过程保留；`.abs()`修复后194828与200446两份report均travel374/0、exit0、passed=true。夹具边界、截图清单与完整路径见[总交付](../../development/2026-11-06_keyboard_complete.md)。建造40/0与visual43/0仅引用[building设计](../building/spec.md)/[账本](../building/ledger.md)，未改其文档；不外推全部作物/DIY布局/full-world与设备验收。

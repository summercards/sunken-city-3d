# SEA-AQUA · 浅水养殖 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-aqua) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-AQUA",
  "status": "partial",
  "owner": "FisheryModel / FisheryVisual / FisheryHarvest / FisheryMarker；第五区特殊养殖仍规划",
  "code_paths": [
    "godot/src/aqua/fishery_service.gd",
    "godot/src/aqua/fishery_visual.gd",
    "godot/src/aqua/fishery_harvest.gd",
    "godot/src/ui/fishery_marker.gd",
    "godot/src/ui/fishery_panel.gd"
  ],
  "verification": [
    "fishery",
    "visual-fishery",
    "fishery-environment",
    "visual-fishery-environment",
    "fishery-production",
    "visual-fishery-production"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-AQUA-R01 | 规划待实现 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-AQUA-R02 | 家园渔场已定义并实现独立周期产鱼与收获；第五区投苗/投喂和特殊养殖仍规划 | R09/R10；fishery-production |
| SEA-AQUA-R03 | 家园改造切片已开放并具备存档和专项；第五区仍锁定规划 | R04–R10；本轮证据 |
| SEA-AQUA-R04 | 已实现；木牌气泡仅“建造渔场”，木板 100 + 鱼 50，背包与仓库合并计数扣费，不足禁用、已升级不重复扣 | [本轮交付](../../development/2026-11-01_energy_fishery_and_join.md)（`fishery` 28 项 0 失败） |
| SEA-AQUA-R05 | 已接入正式岸坪/围网，替换临时旗；原升级成本、重复拒绝、旧档/存读显隐均本轮通过 | [本轮交付](../../development/2026-11-02_wild_fishery.md) |
| SEA-AQUA-R06 | 12组件母版/独立包及独立优化源已交付；原板占地、1.33米表面、电线杆几何/材质/变换锁定均通过 | 同上，SEA-ASSET-R38 |
| SEA-AQUA-R07 | 22段网+22只浮漂；按最新要求改为独立现有海面鱼群20条，旧定制鱼退出装配；鱼群不写库存 | 同上 |
| SEA-AQUA-R08 | 升级状态驱动显隐、真实胶囊导航、围网水域和候选存档恢复，39项逻辑/43项真实渲染通过 | `fishery-environment` / `visual-fishery-environment` |

## 资源与调用入口

- `godot/src/aqua/fishery_service.gd`：`configure({count,pay,missing_text})`、`reason()`、`missing_text()`、`held()`、`can_upgrade()`、`upgrade()`、`to_dict()/from_dict()`、`changed` 信号；成本常量 `COST = {wood:100, fish:50}`。
- `godot/src/ui/fishery_panel.gd`：`build(body, economy, perform)`，与种植页共用行列表。
- `godot/src/aqua/fishery_visual.gd`：configure / apply_upgrade / supports / water_shapes / animate，消费unlocked，不写库存或升级状态。
- 家园周期产鱼/收获见R09/R10；第五区投苗/投喂及特殊产物仍规划。

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

渔场升级、周期观察与收获的公开接口见本页上下文；第五区特殊养殖尚无正式接口。

## 验证记录

当前入口：`fishery` / `visual-fishery` / `fishery-environment` / `visual-fishery-environment`，全部通过统一runner隔离用户数据。第五区特殊养殖仍待实现；家园周期产鱼按R09/R10及fishery-production独立核验。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 尚无本功能独立运行验收，不将结构通过视为玩法完成。

## 遗留与下一步

自动产鱼、储量、收获与存档已接入；第五区投苗、投喂及特殊产物仍规划。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 变更记录（续）

- 2026-11-01：家园补给站改造为渔场的第一段（R04/R05）落地并登记；状态由 `planned` 改为 `partial`，`code_paths` 与 `verification` 同步补齐。养殖生态仍为规划，不因本次升级自动升级完成度。

## 彩色鱼群与收获修订（2026-11-02）

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-AQUA-R09 | FisheryModel按唯一WorldClock每4小时积3鱼、上限24；睡觉跨时结算、满仓丢弃溢出、原子入包、背包满保留及新旧档防重复已接入 | fishery-production / visual-fishery-production；[本轮交付](../../development/2026-11-02_fishery_production.md) |
| SEA-AQUA-R10 | 原木牌升级后隐藏；独立屏幕圆按钮/数量、真实点击与E键同一业务命令；按最新要求移除此地点原三项服务，仅保留收获 | 同上，另复验fishery / fishery-environment |

公开端口新增configure中的can_receive/receive，命令observe(clock)、harvest()，查询pending/harvest_reason()。业务模型不访问全局Economy或Main。to_dict/from_dict扩为功能v2（根存档v4不变），空间存读仍走原投影。FisheryHarvest只显示并转发；现有鱼群独立位于zone1/FisherySchools。

## 本次验收记录

- 产鱼与完整点击：fishery-production 31项、visual-fishery-production 33项，均0失败；等待标题/菜单关闭后实跑气泡→接近→交互→入包，无鱼时商店入口同样通过。
- 设施与空间：fishery-environment 42项、visual-fishery-environment 46项；既有升级26项。minimum-loop 141项、ocean-pickups 48项、progress-bars 45项均0失败。
- 证据路径、退出码、真实渲染及初轮失败详见[本轮交付](../../development/2026-11-02_fishery_production.md)。全工程文档同步被并行SEA-BUILDING未收口条款及建造/导航哈希漂移阻挡，未批量更新其他工作基线。

## 圆按钮与入口精简修订

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-AQUA-R11 | 未建造仅建造渔场，建成后仅收获鱼类；移除此地点商店/仓库/出货箱，保留原生产与存读规则 | fishery / fishery-production / visual-fishery-production；[交付](../../development/2026-11-02_fishery_round_button.md) |

R10本轮换为独立FisheryMarker CanvasLayer，复用现有action_bubble和白色action_fish图，不再有3D图标/文字。FisheryHarvest只持交互锚点与注入命令；模型仍独占业务状态。前节“无鱼时商店可用”为上一轮记录，本轮明确取消该地点服务入口。

本次圆按钮最终：fishery-production 33项、visual-fishery-production 36项、fishery 26项、fishery-environment 42项均0失败；pocket-bubbles 59项、minimum-loop 141项相关回归通过。实际鼠标、镜头拉近、仅建造/收获、背包/存档均覆盖。全工程--sync被并行水层资产哈希登记阻挡；详见本轮交付。

## 2026-11-11无损性能优化第一批

承接 SEA-AQUA-R07/R08/R09；登记 JSON、status、原产鱼及收获条款与历史结果保持。

- FisheryVisual 隐藏时只推进 `_time`，跳过隐藏表现提交；这仅涉及视觉时基，不把 FisheryModel 的周期生产停掉或迁入表现层。
- 升级、pending/next_hour、唯一 WorldClock、满包保留和原子收获仍由原业务所有者管理；第五区特殊养殖、投苗/投喂的规划边界不升级。
- 主线程已提供 `performance-equivalence` 19/0；本次仅回填该批结果，不新增测试或复跑，不将历史 `fishery-production` 结果冒充本批完整经营回归。

[主记录](../../development/2026-11-11_performance_optimization.md)由主线程建立；最终视觉、存档及经营回归仍处理中，本节不预签完整验收。

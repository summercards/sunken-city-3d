# SEA-PICKUP · 海面漂流物与鱼群收取 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-pickup) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-PICKUP",
  "status": "partial",
  "owner": "SeaProps / 独立目标快照",
  "code_paths": [
    "godot/src/pickups"
  ],
  "verification": [
    "selftest",
    "visual-sea-style",
    "visual-fish-schools",
    "framework-integration",
    "minimum-loop",
    "ocean-pickups",
    "wood-density",
    "visual-ocean-pickups",
    "progress-bars"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-PICKUP-R01 | 目标接近走WaterNavigation；click/selftest通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-PICKUP-R02 | 重复旧目标返回空且不再发奖；集成验证 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-PICKUP-R03 | 奖励快照/取消目标规则；selftest/click通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-PICKUP-R04 | 本轮表现与专项通过 | 7 群共 35 条缩小彩色小鱼全部参与 S 型摆尾、变速冲刺与跃动游动；7 处网页版锚点保留；实机帧与水域检查通过。 [交付记录](../../development/2026-10-23_sea_visual_style.md) |
| SEA-PICKUP-R05 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-PICKUP-R06 | 已实现并专项核验 | [边界补强记录](../../development/2026-10-27_framework_boundary_hardening.md) |
| SEA-PICKUP-R07 | 本轮实现；正式最小范围与独立专项验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |

## 资源与调用入口

- [godot/src/pickups](../../../godot/src/pickups)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

2026-10-30新增：`sync_population(clock, boat_position)`组合唯一日历与船位，内部OceanPopulation拥有日次/缺失槽位，`ocean.to_dict/from_dict`持久化游戏小时截止时间。旧`apply_population_scope`仅用于未开启开放海域的历史独立夹具。

## 2026-10-30 开放海域与收获反馈

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-PICKUP-R11 | 已实现；九格资源覆盖远海四象限及1400m位置，回访保留缺失槽位，按真实导航避让 | `ocean-pickups`；[交付](../../development/2026-10-30_ocean_pickups.md) |
| SEA-PICKUP-R12 | 已实现；鱼群07:00日更、浮木独立6–10游戏小时补货、离线冻结、午夜/06:00不重复刷新、存读和旧档迁移 | `ocean-pickups`专项；[交付](../../development/2026-10-30_ocean_pickups.md) |
| SEA-PICKUP-R13 | 已实现；成功事件驱动物品图标上飘渐隐，拒绝不播、取消清理；真实木板/鱼收获渲染通过 | 逻辑43项与真实渲染13项；[交付](../../development/2026-10-30_ocean_pickups.md) |
| SEA-PICKUP-R14 | 已实现并专项通过：阳光房补给区总计6束；外海仅原30%，按整数余数分配；鱼群保留原布局，读密集旧档立即生效且保留冷却 | `wood-density`16项、`ocean-pickups`43项、`visual-ocean-pickups`14项通过，生活141项/建造53项回归通过；[本轮交付](../../development/2026-10-30_wood_density.md) |

## 2026-10-30 打捞巡航不拧正船头

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-PICKUP-R15 | 已实现：`sail_to` 新增 `align_at_arrival`（默认 true）；打捞两处调用传 false，到站 `_yaw_to` 就地改成当前朝向、`_dock_left` 归零，停稳后船头不再自转 | `ocean-pickups` 新增三条正向断言（到站朝向是航行方向而非出发朝向、停稳后 40 帧角度变化 < 0.01、`_dock_left` 为 0）与一条反向对照（靠泊仍保留 > 0.5 rad 拧正量）；[本轮交付](../../development/2026-10-30_detail_fixes.md) |

collect_crate / collect_fish / nearest_crate / nearest_school / to_dict / from_dict；collected、fish_collected；pickups 快照见存档协议。`try_pickup`（停船瞬收）已删除：停船只代表「可以开始捞」，结算由场景侧打捞计时触发。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py selftest visual-sea-style framework-integration`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

SeaProps 注入区域查询和 give_resource，拥有目标ID、随机流与相对补货计时；表现仍在本模块内部维护，完整生态与养殖不是本功能。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

- 2026-10-23 画面优化：7 群的全部鱼均参与移动；7 处网页版锚点保留；实机帧与水域检查通过。 [独立验证与截图记录](../../development/2026-10-23_sea_visual_style.md)。

## 2026-10-27 模块框架落地

SeaProps 注入区域查询和 give_resource，拥有目标ID、随机流与相对补货计时；表现仍在本模块内部维护，完整生态与养殖不是本功能。

新增条款 SEA-PICKUP-R05 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-27 查询与恢复边界补强

save_schema语义检查；SeaProps接受旧版显式reset；坏档不会重新生成已收物资。

[本轮实测记录](../../development/2026-10-27_framework_boundary_hardening.md)。

## 2026-10-27 当前最小循环与开始画面

本节及本轮修改条款优先于下方保留的历史范围。默认发布配置只开放家园生活循环；旧全功能验证须显式 `--full-world`，不能代替最小版本验收。接口、迁移及实测见[交付记录](../../development/2026-10-27_minimum_loop_and_title.md)。

## 2026-10-27 鱼群外观与单群散布

鱼群模型与游动改为直接移植网页版 `web/fish-schools.js`：扁胖椭球身体 + 三角尾鳍 + 深色眼珠，轨道巡游、切线朝向、尾鳍按 9 rad/s 摆动，并随同一套波浪采样浮在浪面之上。配色改用网页版薄荷青系并按 Godot 成像链路反补偿。单群 3–6 条按抖过的黄金角螺旋 + 两两互斥铺开，最近间距 ≥ 1.05 m，不再是共心一圈。

新增专项 `visual-fish-schools`（55 项）覆盖：鱼型、色板饱和度、单群最小间距、8 个时刻的"腹侧恒在浪面之上"、真实动画位移，以及水下 7 群的细长型与四色轮换。

见[本轮交付与验证记录](../../development/2026-10-27_fish_school_port.md)。

### 同日第三轮修订

可捕捞鱼群恢复网页版原尺寸（`SIZE` 0.5 → 1.0）：它是玩家要靠近、要点的交互目标，缩小后难辨认也难点中。配套：贴水抬升量按公式自动回到 0.42 m，地盘半径 1.45 → 2.00 m、最小间距 1.05 → 1.30 m，避免鱼变大后相对间距缩水又挤回去。装饰群与可捕捞群尺寸不同属有意分化（氛围 vs 交互目标）。

## 2026-10-28 可捕捞鱼群：沉到水下、涟漪压淡减圈

主人三条要求：**涟漪透明度调低、少一些**；**鱼往下挪到水里去**。

- 沉深：改用与装饰群同一口径 —— 鱼**最高点**在浪面之下的米数（`SUBMERGE = 0.40`，每条另叠 0.015–0.045 的深度微差），半高乘该条鱼自己的实例缩放。原来的 `RIDE_LIFT = 0.29 + 0.11·SIZE + 0.02 = 0.42` 是「抬到浪峰之上」，已废弃。
- 涟漪：双圈 + 两道脉冲 → **单圈 + 一道**；透明度 0.56 → 0.20；圈色从近白 `(0.76,0.98,0.95)` 改为水青灰 `(0.34,0.58,0.58)`。只降 alpha 不够，实测 0.28 时圈峰值仍是 `(225,227,215)` 而水面只有 `(143,177,189)`，差的 80 级全在「近白 × 高 alpha」上。
- 点击锚点随鱼下沉 0.45 m；否则点鱼身偏出小半米。
- 漂流物资的圈保持旧观感（`make_ripple` 默认参数不变），并有断言盯着不被牵连。

`visual-fish-schools` 本轮 135 项 0 失败，新增 12 条：可捕捞群每条鱼的沉深上下限、群内纵深差、涟漪透明度/圈数/波数/亮度、涟漪只有一层（`build()` 叠两层时参数怎么调都调不淡）、漂流物资圈未被牵连。

见[本轮交付与验证记录](../../development/2026-10-28_fish_catch_submerge_and_ripple.md)。

## 2026-10-29 家园建造接入

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-PICKUP-R08 | 已实现；相关专项通过，详细范围以交付记录为准 | [本轮交付](../../development/2026-10-28_building_delivery.md) |

## 2026-10-29 拾取流程：停下才打捞

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-PICKUP-R09 | 已实现：三阶段状态机 IDLE → SAILING → GATHERING；航行段零进度，停稳且够得着才开捞，打捞走满才结算；`progress-bars` 45 项、`visual-pickup-progress` 12 项、`building-integration` 38 项全部 0 失败 | 推进到只剩 3 米仍在航行时条不出现；停稳后条从 0 出现、0.6 秒到 0.50、走满才进账；停稳但离目标 20 米时作废不打捞；`try_pickup` 瞬收路径已删除；[本轮交付](../../development/2026-10-29_pickup_progress_bar.md) |
| SEA-PICKUP-R10 | 已实现：条挂**角色头顶**（1.35 米 + 16 px 屏幕偏移），`progress-bars` 覆盖 | 目标在相机背后时条仍可见、条心对准角色误差 < 2 px、条与目标投影点分开 1517 px、角色移动条跟随 242.8 px |

三次失败都记在这里，不隐藏：

1. 同日首版从点击那一刻就把 0% 的条挂在**目标上方**，船还在几十米外 —— 玩家读到的是"还没开始捞就已经有进度"。
2. 之后改成"按剩余航程折算、最后 2 秒露条"，主人夜里实机仍然"看不到进度条"：条挂在目标上，而镜头跟着角色走，目标一偏出取景框条就一起消失。挂点改为**角色**。
3. 再然后主人指出**根因不在表现层**：`PICK_REVEAL_SECONDS` 那套写法让船还在划、人还没停下，条就已经在走 —— "角色还没停船就开始走进度条，很不合理"。改成玩法状态机：航行段彻底没有进度，停稳才是「开始打捞」，打捞计时走满才结算。同时删掉 `try_pickup` 那一停就瞬收的旧路径（它与新规则自相矛盾），`PICK_REVEAL_SECONDS` 一并废弃。

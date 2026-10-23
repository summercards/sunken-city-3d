# SEA-PICKUP · 海面漂流物与鱼群收取 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-pickup) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-PICKUP",
  "status": "partial",
  "owner": "SeaProps",
  "code_paths": [
    "godot/src/pickups"
  ],
  "verification": [
    "selftest",
    "visual-sea-style"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-PICKUP-R01 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-PICKUP-R02 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-PICKUP-R03 | 部分实现，按下方边界核验 | 当前代码入口与本轮验证记录；不以历史通过签署本条完成 |
| SEA-PICKUP-R04 | 本轮表现与专项通过 | 7 群共 35 条缩小彩色小鱼全部参与 S 型摆尾、变速冲刺与跃动游动；7 处网页版锚点保留；实机帧与水域检查通过。 [交付记录](../../development/2026-10-23_sea_visual_style.md) |

## 资源与调用入口

- [godot/src/pickups](../../../godot/src/pickups)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

以下是拆分时的代码事实快照，便于定位公开命令、查询和事件；不等于允许直接访问所有内部字段。变更接口时同步本页与功能文档。

- `godot/src/pickups/sea_props.gd`：命令/查询 `build(), try_pickup(boat_pos: Vector3, boat_stopped: bool), collect_crate(crate: Dictionary), collect_fish(school: Dictionary), pick(screen_pos: Vector2, cam: Camera3D, radius := 26.0), nearest_crate(pos: Vector3, radius := 12.0), nearest_school(pos: Vector3, radius := 12.0)`；事件 `collected(kind: String, label: String, reward: Dictionary), fish_collected(label: String)`。

- `fish_school_visual.gd`：`build(rng, count, phase)` 建立明确鱼实例数组；`animate(time, water)` 更新所有鱼和尾鳍；`make_ripple / sync_ripple` 为鱼群与漂流物共享涟漪表现。
- `SeaProps.water_surface`、`water_point_clear(Vector2)` 由 Main 装配注入，表现层不自行寻找主场景。位置保留 `WEB_ANCHORS` 七点，之后采用网页版泊位包围盒 + 12 米及 9 米群间距。

## 验证记录

入口：`python3 scripts/run_verification.py selftest`。

本轮实测结果统一见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 selftest 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

目标管理与部分动态几何同处 SeaProps，完整生态与养殖不是本功能。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

- 2026-10-23 画面优化：7 群的全部鱼均参与移动；7 处网页版锚点保留；实机帧与水域检查通过。 [独立验证与截图记录](../../development/2026-10-23_sea_visual_style.md)。

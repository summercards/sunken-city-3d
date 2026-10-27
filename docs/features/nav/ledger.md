# SEA-NAV · 航行与靠泊 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-nav) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-NAV",
  "status": "partial",
  "owner": "WaterNavigation / Boat",
  "code_paths": [
    "godot/src/navigation/water_navigation.gd",
    "godot/src/navigation/sail_nav.gd",
    "godot/src/navigation/boat.gd",
    "godot/src/navigation/route_ribbon.gd"
  ],
  "verification": [
    "surface",
    "selftest",
    "framework-modules"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-NAV-R01 | 正式WaterNavigation查询/求路/验段；绕障模块和surface通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-NAV-R02 | Boat保留加减速和转向，每步段检；surface通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-NAV-R03 | 30条有向航路全部通过，旧路接管由click/surface覆盖 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-NAV-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |

## 资源与调用入口

- [godot/src/navigation/water_navigation.gd](../../../godot/src/navigation/water_navigation.gd)
- [godot/src/navigation/sail_nav.gd](../../../godot/src/navigation/sail_nav.gd)
- [godot/src/navigation/boat.gd](../../../godot/src/navigation/boat.gd)
- [godot/src/navigation/route_ribbon.gd](../../../godot/src/navigation/route_ribbon.gd)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

is_open_water / plan_route_to / valid_route / segment_clear / invalidate；shape_query；Boat.sail_to / sail_to_point / remaining_route；segment_clear、speed_multiplier 注入；arrived、navigation_blocked。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py surface selftest framework-modules`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 surface、selftest 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

正式航路算法位于 src/navigation；WaterNavigation 拥有水域判断、网格和路线验证，Boat 逐步调用 segment_clear。30条路线回归只是样本，不代表全海域穷举。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 太阳能木屋接入影响验证（2026-10-25）

SEA-NAV：main 泊位随新栈桥移动，打捞台泊位保留；新增平台岸线范围，30 条跨泊位航路通过。 验证入口：`python3 scripts/run_verification.py surface click management selftest visual-solar-cabin`；[证据](../../development/2026-10-25_solar_cabin_integration.md)。

## 太阳能木屋 v004（2026-10-25）

SEA-NAV：同步新桥泊位及扩展岸线，30条航路本轮通过；未改变独立绞盘台泊位。 [当前证据](../../development/2026-10-25_solar_cabin_v004.md)。

## 太阳能木屋 v005（2026-10-25）

SEA-NAV：主桥泊位、登岸点及岸线随桥端向+Z延伸1.587米；30条跨区路线本轮通过，其他泊位不变。 [当前证据](../../development/2026-10-25_solar_cabin_v005.md)。

## 2026-10-26 功能与健康审计

SEA-NAV-R01/R02/R03：surface 30条有向航路503项通过，含30/60/120FPS抵达一致性；selftest岛心/绕行/泊位航线等另有失败，几何判据与正式专项冲突，需要核对当前场景，不能直接认定全部穿模或豁免。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

正式航路算法位于 src/navigation；WaterNavigation 拥有水域判断、网格和路线验证，Boat 逐步调用 segment_clear。30条路线回归只是样本，不代表全海域穷举。

新增条款 SEA-NAV-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

## 2026-10-27 航行指令提示静默

按用户要求，划船移动不再弹提示条：删除「划向那里」「启航 · <区块>」「启航 · <区块> · <上岸点>」「驶向鱼群」「驶向<漂流物>」五处发出指令时的复述（`godot/src/bootstrap/main.gd`）。移动意图改由航线丝带与落点准星表达。

保留「抵达」「已停船」等结果提示与「无法到达」「这里没有可通行航路」等拒绝原因；`hud.toast` 本体与纸条样式未改。

SEA-NAV-R01/R02/R03 实现未改动，本轮回归 click、surface、selftest 均退出 0：[记录](../../development/2026-10-27_sail_toast_silence.md) · `sea-work/verification/20261027-111208-verification-83e9e6`。真实窗口目视复核未执行，文案已按源码检索确认清除。

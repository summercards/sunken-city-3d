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
    "framework-integration"
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

## 资源与调用入口

- [godot/src/pickups](../../../godot/src/pickups)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

collect_crate / collect_fish / nearest_crate / nearest_school / to_dict / from_dict；collected、fish_collected；pickups 快照见存档协议。

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

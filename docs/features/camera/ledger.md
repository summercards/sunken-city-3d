# SEA-CAMERA · 相机跟随与手动控制 · 独立账本

[主文档中控](../../../GDD_V1.0.md#sea-camera) · [功能文档](spec.md)

## 登记头

以下为本功能状态的唯一编辑源；主文档状态摘要与机器索引由工具读取本页汇总。`partial` 不代表失败，`planned` 不代表已有实现。

```json
{
  "feature_id": "SEA-CAMERA",
  "status": "partial",
  "owner": "OrbitCam / follow、manual 状态",
  "code_paths": [
    "godot/src/camera"
  ],
  "verification": [
    "visual-title-screen-day",
    "visual-title-screen-night",
    "visual-title-screen-dawn",
    "camera",
    "click",
    "framework-modules",
    "visual-title-screen"
  ]
}
```

## 设计承接与实施条目

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-CAMERA-R01 | follow/manual状态独立；camera8项通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-CAMERA-R02 | pan/orbit/zoom动作独立，阻断端口；click/camera通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-CAMERA-R03 | 潜水阶段切换及退出回海面；selftest与framework-integration通过 | [2026-10-27实测](../../development/2026-10-27_modular_framework.md) |
| SEA-CAMERA-R04 | 已实现并专项核验 | [框架交付记录](../../development/2026-10-27_modular_framework.md)；[模块接口约定](../../architecture/module_contracts.md) |
| SEA-CAMERA-R05 | 独立镜头适配已实现，真实鼠标入场验证 | [本轮交付](../../development/2026-10-27_minimum_loop_and_title.md) |

## 资源与调用入口

- [godot/src/camera](../../../godot/src/camera)

资产记录见 [资产总入口](../../../assets/registry/README.md)。共用资产按 AssetID 引用；未取得生产 AssetID 的旧运行资源通过路径定位并标注补登，不自动认定正式资产验收完成。

## 当前接口清单

resume_follow / suspend_follow / restore_follow / setup / set_distance；状态见 camera/states，动作见 camera/actions。

[模块接口约定](../../architecture/module_contracts.md) 给出跨功能依赖、状态机和持久化契约；兼容字段仅供已有调试工具，不作为新增业务写入口。

## 验证记录

当前入口：`python3 scripts/run_verification.py camera click framework-modules`。

2026-10-23 历史实测结果见 [工程拆分记录](../../development/2026-10-23_feature_split.md)，该记录标明每项测试、退出码、日志与未执行项。历史验证不自动升级为本次通过。与本功能目标相关但未被现有测试覆盖的条款仍保持待核验。

- 2026-10-23 验证：主文档、条款承接、路径与资产结构检查通过。 核心专项 camera、click 本轮均退出 0；测试覆盖范围以[验证摘要](../../development/2026-10-23_verification_summary.json)为准。

## 遗留与下一步

镜头拆为 follow/manual 状态和 pan/orbit/zoom 动作，UI 阻断经 input_blocked 回调注入，读档恢复跟随。跨分辨率与目标设备手感仍需验收。

## 变更记录

- 2026-10-23：从主文档和现有工程建立本功能独立文档、账本与代码入口；目标设计完整保留，未修改玩法数值。

## 2026-10-26 功能与健康审计

SEA-CAMERA-R01/R02/R03：camera 8项通过，含默认跟随、手动接管、恢复与30/60/120FPS阻尼。visual-click打开视角面板失败；完整设备、遮挡与人工手感未验，保持partial。

[本轮审计与证据](../../development/2026-10-26_feature_architecture_save_3c_audit.md)。本轮只审计和登记，未修改玩法实现。

## 2026-10-27 模块框架落地

镜头拆为 follow/manual 状态和 pan/orbit/zoom 动作，UI 阻断经 input_blocked 回调注入，读档恢复跟随。跨分辨率与目标设备手感仍需验收。

新增条款 SEA-CAMERA-R04 已接入独立文件和公开接口。本次结果见 [框架交付记录](../../development/2026-10-27_modular_framework.md)；此前审计是历史观测，已修复项以本次实测为准，未覆盖目标保持原状态。

2026-10-27 接口收口：公开姿态入口：apply_pose / orbit；Main 不再调用镜头私有姿态方法。

## 2026-10-28 开始构图与存档时刻

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-CAMERA-R06 | 已实现；保持角度的房屋上移、按钮右移、三分辨率原生布局，白天/夜间/清晨存档冷启动与实际点击入场光照连续核验 | [本轮交付](../../development/2026-10-28_title_composition_saved_time.md) |

开始机位只在TitleCamera临时接管，不改变玩家存档姿态；未修改光照时段参数、资产资源或存档格式。当前整体功能状态保持原状，目标设备等边界见交付记录。

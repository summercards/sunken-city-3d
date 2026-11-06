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
    "keyboard-travel",
    "visual-keyboard-farm-loop",
    "control-feel",
    "keyboard-control",
    "visual-corner-notebook",
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

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-CAMERA-R09 | follow按角色真实高度，manual保留旧范围；镜头数值未改 | [角色框架实测](../../development/2026-10-29_character_physics_framework.md) |

SEA-CAMERA-R09：仅移除follow模式的旧10m高度夹限，保留manual范围和全部镜头数值。camera与角色物理集成证据见[本轮交付](../../development/2026-10-29_character_physics_framework.md)。

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


## 2026-10-28 右下视角锁定

| 对应条款 | 实施状态 | 证据 |
|---|---|---|
| SEA-CAMERA-R07 | 已实现；真实鼠标点定位图标恢复跟随、手动观察释放、状态颜色回填及三分辨率右下布局 | [本轮交付](../../development/2026-10-28_hud_date_camera_lock.md) |

复用原resume_follow/follow_enabled，不增加镜头状态写入者；UI只有展示状态。

## 2026-10-29 自由海域镜头

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-CAMERA-R08 | 已实现；远处相机目标不被旧边界夹回，真实海上施工近景通过 | [本轮交付](../../development/2026-10-29_open_ocean_building.md) |

## 2026-11-02 新旅程与角色档案

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-CAMERA-R10 | 已接入，专项与回归以本轮记录为准 | `onboarding / visual-avatar`；[交付](../../development/2026-11-02_avatar_and_arrival.md) |

## 2026-11-05 缩放上限 77.8 米

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-CAMERA-R11 | 已实现（含同日修订）；`zoom_max` 190→**77.8**（旧区间 9~190 的 38%），开局 `distance` 保持 54.25 不变；滚轮/捏合/面板均被钉在 77.8 米，下限 9 米；8 个需要更宽机位的证据脚本在自己文件内临时抬高 `zoom_max` | `camera` 12 项、`visual-camera-zoom` 14 项；[本轮交付](../../development/2026-11-05_camera_zoom_max_38.md) |

玩家侧只有一条变化：能拉到的最远处从 190 m 收到 77.8 m，开局机位不变。FOV、俯角、阻尼、跟随/手动接管、UI 阻断、存档字段均未改动；工具侧的 `zoom_max` 抬高只影响证据取景，不代表玩家可达范围。

首次落地按 38 m 实施，同日由主人指认「截图那个取景才是最远」后修订为 77.8 m。
38 m 那一版的实施与实测记录保留在交付文档中，作为被推翻过程的证据，不作为当前状态。

## 2026-11-05 键盘不再驱动镜头

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-CAMERA-R12 | 已实现；删除 `OrbitCam._keyboard()` 的平移与 Q/E 旋转，键盘全部归角色与交互，镜头只保留鼠标拖拽/旋转/滚轮/捏合；跟随、俯角、FOV、阻尼、77.8 米上限、UI 阻断未改 | `keyboard-control`（按住方向键时 `cam.target` 不变）、`camera` 复跑通过；[本轮交付](../../development/2026-11-05_keyboard_control.md) |

## 2026-11-05 · 尺度联动

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-CAMERA-R13 | 已实现；`Dimensions.CAMERA_FOCUS = 0.7×SCALE = 1.05` 统一替换 `follow.gd`/`orbit_camera.gd`/`main.gd` 三处/`room_controller.gd` 的写死 0.7；到达与捏人肖像的中心、距离、横移同乘 | `camera` 与 `onboarding` exit0（`camera-follow` 的「跟随世界坐标」断言改为对 1.05 m 取点）。[本轮交付](../../development/2026-11-05_character_scale_150.md) |


## 2026-11-05 跟随手感

| 对应设计条款 | 当前实施状态 | 证据 / 边界 |
|---|---|---|
| SEA-CAMERA-R14 | 已实现；`_track_subject` 做位移继承 + 速度估计 + 前视缓动，`follow.gd` 只负责把前视加进目标点；跟随时不再残留匀速滞后 | `control-feel`（前视 1.19 m、残差 0.016 m、站定回零）、`camera`、`visual-camera-zoom`、`visual-walk-facing` 复跑通过；[本轮交付](../../development/2026-11-05_control_feel.md)。手动接管/固定机位/房间环视不加前视。 |

## 2026-11-06 独立键盘取景入口

登记头仍 `partial`。历史 R12 的「只留鼠标」由 R15 覆盖；WASD/方向/Q/E不驱动镜头的约束保留。

| 对应设计条款 | 当前实施状态 | 证据 / 待验 |
|---|---|---|
| SEA-CAMERA-R15 | `[`/`]`旋转、`-`/`=`缩放、F恢复跟随的正式室外键盘路径已通过；复用门禁与既有状态 | `test_keyboard_travel.gd:201`；`20261106-200446-keyboard-release-regression-eae88a/report.json`：travel374/0、camera12/0、keyboard-control30/0、control-feel31/0，均exit0、passed=true |

证据根`D:/projects/sea-work/verification/`，`20261106-194828-keyboard-visual-travel-final-09cca9/report.json`同样travel374/0通过，visual-farm617/0为真实渲染种植链，不冒称室内镜头边界视觉专项。旧374/0因负Rect导致runner FAIL保留为过程，`.abs()`修后已两轮通过，不再pending。200446完整报告14通过/4失败，其中interaction-reach/dock-seed/minimum-loop/harvest-receive旧契约失败保留为过程；201957适配报告已分别35/0、22/0、147/0、92/0，均exit0、passed=true，不再待填。主线程keyboard-final-contracts最终批次待附，不以旧批次冒称新批次通过。完整路径、室内/设备/组合边界见[总交付](../../development/2026-11-06_keyboard_complete.md)；整体partial。没有改用户TSCN、资产/哈希或运行新检查。

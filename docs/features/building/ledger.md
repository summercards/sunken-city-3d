# SEA-BUILDING · 家园拼接建造 · 独立账本

[主文档](../../../GDD_V1.0.md#sea-building) · [设计](spec.md)

```json
{
  "feature_id": "SEA-BUILDING",
  "status": "implemented",
  "owner": "BuildingService / BuildingWorld / BuildingController",
  "code_paths": ["godot/src/building"],
  "verification": ["building", "building-integration", "visual-building", "building-restart"]
}
```

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILDING-R01 | 已实现；本轮专项通过 | 菜单、手册与真实渲染 |
| SEA-BUILDING-R02 | 已实现；本轮专项通过 | 陆地资格与未来策略注入 |
| SEA-BUILDING-R03 | 已实现；本轮专项通过 | 成本、计时、重复与预览取消 |
| SEA-BUILDING-R04 | 已实现；本轮专项通过 | 独立种植区与农场闭环 |
| SEA-BUILDING-R05 | 已实现；本轮专项通过 | 行走、绕障与泊位保护 |
| SEA-BUILDING-R06 | 已实现；本轮专项通过 | 冷热恢复、施工恢复与坏档 |
| SEA-BUILDING-R07 | 已实现；本轮专项通过 | 无Autoload专项 |
| SEA-BUILDING-R08 | 已实现；15项实景与几何检查通过，双水面吃水线可见 | [板底与电线杆摆位](../../development/2026-10-29_deck_draft_pole_placement.md) |

实施与验证记录：[本轮交付](../../development/2026-10-28_building_delivery.md)。

2026-10-29收尾：当前集成38检查通过；独立两进程冷启动5+8检查通过，坏档保护通过；15服务架构边界检查通过。

2026-10-29 00:32–00:40 复验（并行作物接入后的当前工作区）：`building` 20项、`building-integration` 38项、`building-seed` 5项、`building-restart` 8项、`visual-building` 19项全部PASS；同轮`farming` 35项、`minimum-loop` 77项、`framework-modules` 50项、`pocket-services` 28项、`save-corrupt-seed`、`save-protection`全部PASS。`check_architecture.py` 15服务0问题。`check_feature_contracts.py --sync`在00:35:16的窗口内为0问题，但随后并发的作物资产重写使crop源/运行期哈希漂移与`crops`高度断言失败，全局门禁当前为红，均由并行SEA-CROP任务承担，本功能未代其重算。`visual-building`首次在未导入的隔离工程中因新作物纹理缺失报20项资源错误，属并行作物的导入前置条件，`--import-assets`后复跑通过；该次失败不计作建造回归。证据目录`D:/projects/sea-work/verification/`下`20261029-003237-building-resume-7f7eed`、`20261029-003346-building-resume-visual-975be0`、`20261029-003551-building-resume-integration-8b4e07`。

2026-10-29最终收尾：上述并行临时红项已清除。`--sync`及无参功能检查均PASS（35功能、459源资产、387运行期哈希、0问题）；架构检查15服务0问题。`20261029-080045-building-visual-layout-d983d2`导入及真实渲染再次PASS，鼠标/按键19检查0失败；已查看书本、虚影与种植完成截图。测试补齐初次点击前的延迟布局等待，002616超时轮保留为失败记录。

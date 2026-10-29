# SEA-BUILDING · 家园拼接建造 · 独立账本

[主文档](../../../GDD_V1.0.md#sea-building) · [设计](spec.md)

```json
{
  "feature_id": "SEA-BUILDING",
  "status": "partial",
  "owner": "BuildingService / BuildingWorld / BuildingController",
  "code_paths": ["godot/src/building"],
  "verification": ["building", "building-integration", "visual-building", "building-restart", "progress-bars", "building-boundary-audit", "visual-building-boundary-audit"]
}
```

| 对应设计条款 | 当前实施状态 | 证据 / 验证要求 |
|---|---|---|
| SEA-BUILDING-R01 | 已实现；本轮专项通过 | 菜单、手册与真实渲染 |
| SEA-BUILDING-R02 | 现行两圈/24新板/西侧泊位限制已实现；手册与超界反馈缺失 | 陆地资格与未来策略注入；[边界审计](../../development/2026-10-29_building_boundary_audit.md) |
| SEA-BUILDING-R03 | 已实现；本轮专项通过 | 成本、计时、重复与预览取消 |
| SEA-BUILDING-R04 | 部分实现；跨板自由摆位可用，但未校验角色通行宽度；服务层另接受封路布局 | [摆位修正](../../development/2026-10-29_planter_free_placement.md)；[当前反例](../../development/2026-10-29_building_boundary_audit.md) |
| SEA-BUILDING-R05 | 木面与船阻挡增量已实现；实际吸附布局留极窄通路，非吸附服务层布局另可断连 | [当前反例](../../development/2026-10-29_building_boundary_audit.md) |
| SEA-BUILDING-R06 | 部分实现；小布局恢复通过，但服务允许实例数超过保存/恢复的54上限 | [55实例起校验拒绝](../../development/2026-10-29_building_boundary_audit.md) |
| SEA-BUILDING-R07 | 已实现；本轮专项通过 | 无Autoload专项 |
| SEA-BUILDING-R08 | 已实现；15项实景与几何检查通过，双水面吃水线可见 | [板底与电线杆摆位](../../development/2026-10-29_deck_draft_pole_placement.md) |
| SEA-BUILDING-R09 | 已实现：施工条换成 92×8 px 自绘细条（原约 20 px） | `progress-bars` 26 项 0 失败；`building-integration` 38 项照旧通过；[本轮交付](../../development/2026-10-29_pickup_progress_bar.md) |
| SEA-BUILDING-R10 | 正常接近流程已实现；服务层封路布局下不可达施工点仍给“点击施工”预览，确认时才拒绝 | `building-approach` 18项通过；[原交付](../../development/2026-10-29_build_requires_approach.md)；[当前审计](../../development/2026-10-29_building_boundary_audit.md) |

实施与验证记录：[本轮交付](../../development/2026-10-28_building_delivery.md)。

2026-10-29收尾：当前集成38检查通过；独立两进程冷启动5+8检查通过，坏档保护通过；15服务架构边界检查通过。

2026-10-29 00:32–00:40 复验（并行作物接入后的当前工作区）：`building` 20项、`building-integration` 38项、`building-seed` 5项、`building-restart` 8项、`visual-building` 19项全部PASS；同轮`farming` 35项、`minimum-loop` 77项、`framework-modules` 50项、`pocket-services` 28项、`save-corrupt-seed`、`save-protection`全部PASS。`check_architecture.py` 15服务0问题。`check_feature_contracts.py --sync`在00:35:16的窗口内为0问题，但随后并发的作物资产重写使crop源/运行期哈希漂移与`crops`高度断言失败，全局门禁当前为红，均由并行SEA-CROP任务承担，本功能未代其重算。`visual-building`首次在未导入的隔离工程中因新作物纹理缺失报20项资源错误，属并行作物的导入前置条件，`--import-assets`后复跑通过；该次失败不计作建造回归。证据目录`D:/projects/sea-work/verification/`下`20261029-003237-building-resume-7f7eed`、`20261029-003346-building-resume-visual-975be0`、`20261029-003551-building-resume-integration-8b4e07`。

2026-10-29最终收尾：上述并行临时红项已清除。`--sync`及无参功能检查均PASS（35功能、459源资产、387运行期哈希、0问题）；架构检查15服务0问题。`20261029-080045-building-visual-layout-d983d2`导入及真实渲染再次PASS，鼠标/按键19检查0失败；已查看书本、虚影与种植完成截图。测试补齐初次点击前的延迟布局等待，002616超时轮保留为失败记录。

2026-10-29 11:40–11:55 种植区摆位修正（R04）：旧判定把单块板内缩12厘米当边界，x容差仅±5.8厘米，比0.1米吸附步长还窄，因此光标离开板中心两三个像素就红，玩家实际上建不出种植区；同时`support`板只允许一格，跨板摆放不可能。改为以已完工木板的**并集**为边界（4厘米外缘边距）、只禁止与已有种植区重叠，`walk_rects` 对每块板减去每一个种植区footprint，接近点被拉回最近走道；越出木面不足0.4米时由`snap_planter`吸到最近合法格点，重叠与压角色不吸。`support` 降为主支撑板，旧档仍全部合法。`building` 29项、`building-integration` 38项、`building-restart` 8项、`building-seed` 5项、`visual-building` 21项全部0失败（新增接缝覆盖/单侧越界/缺口越界/偏离中心可建/贴边吸回/远处仍拒6条断言）。首轮`visual-building`有`rotate key`冷启动抖动，连续两轮复跑PASS并保留该失败记录。

## 2026-10-29 建造要先走到工地

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-BUILDING-R10 | 已实现；点击虚影只排队，角色走到格子旁站定才扣材料开工 | [交付记录](../../development/2026-10-29_build_requires_approach.md) |

旧实现 `handle_input` 里点击虚影直接 `service.begin(preview)`：五米外点一下，
木板上就自己长出了进度条 —— 建造读起来像在 map 上点按钮，而不是在自己家里动手。

新增 `building-approach` 专项：18 项断言，实测 `18 checks, 0 failures`，退出 0。
覆盖：人还在远处时不开工也不扣料、等待期间虚影锁在目标格、走到位自动开工且只扣一次、
开工后人确实站在工地边、退出建造模式清排队且不再自己开工、站在旁边点一下当场开工。

控制器新增三个注入端口（`stand_point` / `approach` / `actor_state`），不读全局。
`_construction_stand_point` 沿「角色这一侧」由近到远探 1.15/1.5/1.9/2.4 米，
取第一个落在可走矩形且有通路的位置 —— 新木板格本身还没进可行走面，不能直接拿格心当目标。

同轮复跑：`building` / `building-integration` / `building-restart` / `visual-building`（24 项）
/ `unreachable-menu` / `interact-focus` / `board-click` / `farming` / `modules` / `pocket-bubbles`
全部退出 0。整体状态仍 partial（拆除与海上施工未做）。

## 2026-10-29 外围木板不可建与机制完整性审计

本节为当前状态；此前通过记录只说明其覆盖样例，不能覆盖本轮新反例。登记头改为`partial`，原因是R04/R06已有目标未闭环，而非把明确不开放的拆除/海上施工算作失败。

最终`building-boundary-audit`与真实渲染`visual-building-boundary-audit`各31项、退出0：成功复现固定两圈边界、泛化提示、实际0.1米吸附布局缺角色通行宽度检查，以及24新板+36箱共60实例被存档54上限拒绝。另单独复现服务/快照端接受非吸附坐标的封路布局，以及此布局下不可达格仍提示点击施工，明确不把该服务层反例当成鼠标吸附直接复现。**审计探针通过表示反例复现成功，不代表建造机制验收通过。** 其中R06为P1保存风险；R04/R05通行宽度、服务层完整性及边界显示/提示列P2。

同轮原有专项：`building`29项、`building-approach`18项、`building-integration`38项、`building-seed`5项、`building-restart`8项均退出0；真实输入`visual-building`结果及完整证据见[审计记录](../../development/2026-10-29_building_boundary_audit.md)。本次未修改玩法限制、费用、布局状态或玩家存档。

# 设施移位后的植被与手动编辑

[主文档](../../GDD_V1.0.md) · [SEA-AMBIENT-R19](../features/ambient/spec.md) · [功能账本](../features/ambient/ledger.md) · [独立植被资产账本](../../assets/registry/ledgers/vegetation.json)

2026-11-06 的主场景已保存牧场的新位置和朝向。旧取景器按原世界坐标拍摄，ProtonScatter 预览也原先把试刷层放在与设施并列的节点。正式草皮本来由设施局部布局生成，实拍确认移位后有覆盖。当前正式取景从实际设施换算镜头，试刷层与相机进入预览设施子树。

## 编辑权属

- 主场景决定设施根变换，设施场景决定草皮分区、天台草堆和阳光房各株的局部变换。对照[设施摆放台账](../features/world/placed_positions.md)。
- 草皮继续按 JSON 分块实例化。阳光房 394 个实例分 18 批，天台 5358 个草簇分 24 批。分区中苔藓随草皮移动。14 个草堆分别实例化共享 `mound_soft.tscn`，保留原始 ID、尺度、相位和颜色变化。
- 阳光房 56 株原花草的初始变换、资产 ID、材质、归属和升级显隐保留。模块重建只更新生成的视觉子节点。
- 原植被资产继续复用，只更新 ProtonScatter 预览的运行哈希。正式场景使用 v003，试刷场景继续展示上游效果和编辑器修改器。[编辑步骤](../features/ambient/vegetation_meadow.md#在-godot-里手动摆放)
- 为使主场景能启动并完成实拍，给口袋栏翻页索引补充整型声明，并将建筑 UI 已迁移文件的预加载路径指向现有目录。

## 运行证据

所有运行使用统一验证器隔离用户数据。正式图像、风动帧与四秒并排视频 `vegetation_facility_wind.mp4` 在 `D:/projects/sea-work/verification/20261106-142004-vegetation-edit-verify-122bfb/project/outputs/`。试刷移动后的图像及性能数据在 `D:/projects/sea-work/verification/20261106-142527-vegetation-facility-final-956ec0/project/outputs/`。

| 专项 | 退出码 | 结果 |
|---|---:|---|
| vegetation-contract | 0 | 515315 项通过，覆盖移动和旋转设施、草皮分区刷新及单株编辑保留 |
| visual-vegetation | 0 | 新位置的牧场、阳光房各景别与 GPU 实例变换读回通过，两个场景各 120 张连续风动帧 |
| visual-proton-preview | 0 | 11542 原版实例。验证实际生成的 MultiMesh 跟随设施旋转及平移，移动后截图 |
| visual-vegetation-performance | 0 | RTX 4060 Ti、i7-14700KF、1280×800、Forward+。相对无新植被基线，风动植被的 GPU p95 增量为阳光房 0.029 ms、天台 0.385 ms。常态更新 CPU p95 为 0.034 / 0.028 ms。整帧 p95 为 20.567 / 25.361 ms |
| rooftop-ranch | 1 | 655 项中 1 失败，现有泊位点与几何阻挡冲突。设施实际变换、步行及直接上岸链路断言通过。隔离对照 `20261106-142819-vegetation-placement-baseline-9b1b0e` 仅换回改动前植被后复现同一失败 |
| water-layer | 0 | 植物重建保留了原先会被清掉的海下基座禁用阻挡声明。初跑检查误取该声明，现按所有子节点查找有效阻挡，保留对水下阻挡的拒绝检查。最终复测 `20261106-143029-vegetation-water-layer-c2a79d` 通过 |
| minimum-loop | 0 | 最终 141 项通过。初跑虽然退出 0，仍因笔记本面板写入 Button 的旧属性被判失败。工作区面板更新后复跑无意外脚本错误 |

`check_placed_positions.py` 三处实测位通过。已执行文档与资产契约的同步及检查，全库仍有建筑 UI 迁移旧路径、UI/主场景依赖和沉没旧城哈希漂移，未补写这些未核验资源。植被试刷的哈希、字节数和验证证据已按实际运行文件更新。

当前未执行 GUI 中拖动后保存的人工验收及其他硬件/渲染器性能复测。试刷的素材发行与统一风时钟接入仍待验收。

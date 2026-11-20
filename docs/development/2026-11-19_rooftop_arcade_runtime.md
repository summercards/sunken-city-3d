# 海上屋顶街机维修铺 · Godot 运行接入

[SEA-ASSET](../features/asset/spec.md) · [SEA-WORLD](../features/world/spec.md) · [摆放台账](../features/world/placed_positions.md)

- 原源：`art_source/scenes/rooftop_arcade/v001/rooftop_arcade.blend`，`SEA-SCENE-RAC`。母版、独立源组件、原交换 GLB 与组装动画不改。新[优化导出清单](../../art_source/scenes/rooftop_arcade/v001/export/v001/runtime_export_manifest.json)记录源和独立优化版哈希、41 件逐项统计及稳定运行路径。
- 优化以组件/材质角色为边界合并网格对象，967 → 71；单份组件合计 163,364 三角面，优化前后不变，不把三角化描述成减面。位置、UV、材质角色指纹一致。Blender 同机位四组对照 PSNR 为正 69.02、后 71.78、右 66.70、总览 42.44 dB，原图在工程外 `sea-work/rooftop_arcade_v001/runtime/`。未做帧预算验收。
- [正式运行总装](../../godot/scenes/facilities/rooftop_arcade.tscn)保留 355 个静态实例，米制，Blender `-Y` → Godot `+Z`。共享运行色板绑定至四种材质角色；Godot 导入只读取新静态 GLB，不消费组装动画。现有 42 条资产记录定点补记，不发新 ID。
- 主场景只新增一个资源和一个实例（原场景变换不动）；区块为 `World/SeaStructures/rooftop_arcade`。礼品商亭南侧为初次参考位。浮台西侧单泊位；允许外侧甲板行走，不开放室内、阁楼、外梯、经营或小游戏。紧凑外形维持源比例；窄甲板使用按现有胶囊半径预收边的角色中心活动域，未放宽共用导航参数。船阻挡由实际浮台水线切片派生。回退可仅从 Main 摘除新增实例和对应区块配置，保留源和组件。

当前默认 F5 启动的是 `main_minimal.tscn` 白盒，不显示街机屋。查看街机屋需使用完整玩法入口；按[最小白盒交付说明](2026-11-19_minimal_main.md)的恢复步骤操作。本任务不改变全局启动入口。

## 验收

- `20261119-190653-rooftop-arcade-deck-e04245`：隔离导入 exit 0；逻辑 239/0 与真实渲染 245/0 均 exit 0、完成标记为真、无非预期引擎错误。三张实拍逐图目检：商亭同框、船侧靠近、角色登岸。通过游戏控制器走了甲板往返并返船，不是手工摆人物。
- 最初普通地面烘焙丢掉窄甲板：两项街机屋专项当时 exit 1，后由精确活动域解决。第一轮礼品商亭回归 exit 0；`surface` 540 项中 2 失败，`landing-markers` 有远端平台搭建拒绝和后续泊位检查失败；不把未通过的集成项标为通过。参考图商业权属、人工美术终审和未开放楼层不在通过范围。
- 最终 `20261119-190925-rooftop-arcade-final-170c3e`：正式隔离导入 exit 0；专项 240/0、实拍 246/0、礼品商亭回归均 exit 0。新增家园至街机屋泊位的航线规划验证；实船全程人工驾驶未执行。`surface` 540/2、`landing-markers` 24/3，均 exit 1，尚未做无街机屋对照归因。最终报告及三图在工程外 `sea-work/verification/20261119-190925-rooftop-arcade-final-170c3e/`。
- 摆放校验 9 项、0 警告、exit 0。最终全库契约同步 543 项、正式检查 544 项，两者 exit 1（实施前正式检查也是 544 项）；未逐项证明两次问题完全相同。日志见工程外 `sea-work/rooftop_arcade_v001/runtime/`。未批量重签非本次资产。

# 2026-11-20 · 正式家园 F5 临时试坡

[主文档](../../GDD_V1.0.md#feature-control) · [世界](../features/world/ledger.md) · [移动](../features/move/ledger.md)

## 找到与拆除

正式 F5 打开完整 `main.tscn`。新旅人正常建档、结束码头开场对白后，在面前的家园木甲板上找「临时上坡 · WASD」木坡（低层梯脚左侧）。用 WASD / 方向键走上坡顶，转身下坡回到原甲板，无需跳跃。旧档若在其他地方，先回 zone1 家园。实窗画面来自隔离账号，新玩家档仅为测试数据。

编辑时打开 `godot/scenes/zones/zone1_home_harbor.tscn`，删除 `WalkAreas/TemporaryHomeRamp` 实例即可（文本修改可一起移除专用 `temporary_ramp` 引用）。标识、坡面、坡顶和支撑随实例移除；共享的白盒 `ramp.tscn` 不删。撤下后同时将位置台账行改为历史记录。初摆与实测见[摆放台账](../features/world/placed_positions.md)，既有场景手摆不变。

## 本轮验收

- 实例复用木坡外观，视觉自带的碰撞层关闭；正式 `GroundSpace` 用实例的三角支撑。`FreeWalkAction` 的候选步优先沿当前片，接缝仅允许同空间、现有最大台阶差内的相邻支撑，`CharacterMotor` 仍管实际胶囊扫掠。坡段高差约 0.72 m、长约 2.16 m。
- `20261120-140524-home-ramp-f5-3f60f9`：默认实窗启动 exit 0；试坡首轮 16/1、engine/runner exit 1。已上下坡，但返回原甲板时旧的单片检查拒绝继续。保留失败记录。
- `20261120-140844-home-ramp-retest-abd5f7`：资源导入、正式默认实窗启动、`visual-formal-home-ramp` 18/0、`interaction-reach` 36/0、`sunroom-runtime` 全部通过，各 exit 0，runner exit 0。Metal Forward+；正式标题点击、开场和 WASD 派发。脚下高度约 1.38 → 2.10 → 1.38 m，走回原甲板，移动连续，无跳跃或途中传送。
- 外部证据在 `sea-work/verification/<批次>`，三帧位于 `project/outputs/home-ramp-{01-spawn,02-top,03-exit}.png`，坡顶画面已目检。实窗为脚本操作，不是人工签收；未测发行包及目标平台。未动阳光房 `SurfaceCollision`，本轮不签署用户报告的蓝线、正式船壳或新上下船判定。

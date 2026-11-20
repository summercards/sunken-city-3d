# 2026-11-20 · 正式阳光房下层临水窗前甲板

[主文档](../../GDD_V1.0.md#sea-sunroom) · [功能账本](../features/sunroom/ledger.md)

此次以正式 F5、zone1 原位置和用户所述「下层临水亮窗、梯脚左侧」复现。未收到原录像或得知其 checkout；对照使用同一个重建机位（46°，1280×800、Metal Forward+），不宣称与原片像素一致，也不按蓝色归因。

## 首次接触与唯一局部修改

在正式 `Explorer` 用同一 0.22 m／1.30 m 胶囊、层 512／掩码 256 从窗前横扫。第一接触为 `Main/World/Zones/Zone1HomeHarbor/GroundSpace/GroundBoundary` 的运行时 `CollisionShape3D`（shape 0，节点序号为该次实例所得），归 GroundSpace 把走域外沿转换所得的实体；body 和 shape 的世界变换为单位矩阵，三角面直接用世界坐标，层 256／掩码 512。首接触 `(3.5, 2.4603, 4.15)`，法线 +X。真实 W/A/S/D 于该处被 WalkArea 更早拒在中心 X 约 3.79。A/B 单独关闭 SurfaceCollision 或 GroundFloor，横扫仍撞 GroundBoundary；仅关闭 GroundBoundary，横扫无接触，但原走域仍拒走，故排除不是修复。下扫为 GroundFloor；关它则失去该支撑。BlockerSet 的中心线水域查询仍为拒绝，它不是胶囊碰撞体。

真渲染读取 `concrete_slab`实例表面（外观为木甲板）和相邻 `narrow_window` / `house`。旧边线两侧均有约 1.38 m 的同标高铺板，窗前石/木平台模块实打实连续。`zone1_home_harbor.tscn` 只在原下层 `Walk_zone1_home_dock` 追加一条手工划定的支撑矩形，接通铺板与梯脚带，不从渲染 Mesh 生成碰撞，不改变模型、墙盒、修缮、梯子端点或其他区块。散步和地面投影因此共享一致边界。

## 验证

- `20261120-142008-sunroom-deck-ab-76083e`：原版诊断 5/0，exit 0，不是修复通过。`20261120-142114-sunroom-deck-wood-evidence-4237c3`：真渲染补实物件名及表面采样，exit 0。
- `20261120-142315-sunroom-deck-fixed-388a54`：测试脚本数组类型错误，专项 19/3，exit 1。`20261120-142356-sunroom-deck-fixed-r2-a42207`：首轮脚本时序和停下后一帧 stale 接触判据失败，19/2，exit 1；改以持续输入取样及停下后实际向下扫验证，不放宽碰撞。
- `20261120-142519-sunroom-deck-fixed-r3-b4475b`：19/0，engine/runner exit 0，1280×800 实窗。跨过原 X≈3.5 的位置，原胶囊从 `(4.05,1.38,4.15)` 走至 `(0.789434,1.379963,4.165899)`，无离地。实墙对照的形状为 `SurfaceCollision/FrontWallLeft`，斜扫命中 `(2.500977,2.4603,2.63)`，真实键盘停在墙外、仍有下方支撑；水侧边仍由 GroundBoundary 阻挡。实走梯脚走廊后调用原梯子交互，上、下为原连续动作，无换位补丁。非用户亲自试玩；未验证原录像像素、全部墙盒或船壳。
- 同追踪机位图：`sea-work/verification/<批次>/project/outputs/sunroom-deck-{01-reconstruction,02-after-walk,03-wall,04-ladder}.png`。日志 `[deck-contact]` 给出了完整 body、shape、owner、变换、掩码、法线和位移。

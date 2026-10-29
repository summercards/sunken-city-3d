# 交互热区按模型本体算（2026-10-29）

对应条款：[SEA-INTERACT-R10](../features/interact/spec.md)。证据：`pick-mesh`（9 项）、`visual-pick-mesh`。

## 现象

站在 zone5 平台的土箱中间，点两格之间的甲板空地（用户截图红框）——
走不过去，点击被土箱吃掉。

## 根因：命中用「屏幕 AABB 外扩」，相邻格子的缝被两侧盖满

上一轮为了修「物体本体点不中」，把命中改成「鼠标到物体屏幕包围盒的距离」，
再外扩 10 px。在单个物件上没问题，放到**并排的六个土箱**上就崩了：

```
土箱格心间距：2.15 × 2.575 米
土箱模型 footprint：1.79 × 1.58 米
→ 相邻两格之间真实缝隙：约 0.36 × 0.99 米
```

俯视 9 米机位下，这条缝在屏幕上只有十几像素宽；两侧 AABB 各外扩 10 px，
**整条缝被盖满**。点缝里的甲板，判定不是「点地面」，而是「点土箱」——
于是既没走路，也没弹菜单（土箱此刻没有可执行动作）。

`BODY_AREA_LIMIT`（面积 > 视口 12% 就不参与）挡不住这个：
单个土箱的屏幕面积远低于阈值，问题出在**外扩 + 相邻叠加**，不是单块太大。

## 修法：真的按模型做

用户在需求里写得很直接：「功能热区就按照模型去做吧」。

于是命中改成 **射线 vs 三角形**：

```gdscript
# 屏幕点 → 世界射线
var ray_o := camera.project_ray_origin(screen)
var ray_d := camera.project_ray_normal(screen)
var t := _ray_visual_t(ray_o, ray_d, spot)   # < 0 表示没打到
```

实现要点：

| 点 | 做法 | 理由 |
|---|---|---|
| 遍历范围 | 从 `visual_root()` 往下找 `MeshInstance3D` | 与 `visual_aabb()` 同一套可见性口径；热区预览、阻挡体不算模型 |
| 粗筛 | 每个网格自身 AABB × 世界变换得到的 OBB 做 `intersects_ray` | 这一步很便宜，对 BoxMesh 类物件已经是精确的，能省掉绝大多数三角形测试 |
| 精确命中 | Möller–Trumbore，局部空间求交 | 方向不归一化，参数 t 与世界射线同刻度 |
| 三角形缓存 | 按 mesh 实例 ID 存，上限 96 项 | 网格是资源，不变量；实测本工程最大是出货箱 752 面 |
| 高模兜底 | 单个网格 > 1500 面就放弃三角形，只用 OBB | 防止某个高模物件把悬停拖卡 |

实测面数（`[m]` 探针）：

```
Cell1 / platform_plot:0..5   meshes=7  tris=84
ShippingBox                  meshes=1  tris=752
TradeBoard                   meshes=19 tris=336
SleepCheckpoint              meshes=0（纯逻辑点）
```

全部远低于阈值，逐三角形求交没有性能问题。

图标热区（30 px）保留为**补充**路径：给没有几何的纯逻辑点（睡眠位）用，
也让「鼠标正好停在图标上」不至于落空。两条路径同时命中时，**打到模型的一律优先**：

```gdscript
var score := (-10.0 + body_t * 0.01) if on_body else (icon_dist - priority * 2.2)
```

## 顺带修掉的两个测试/并发故障

`hud.gd:924` 的

```gdscript
var moved: bool = a if c else b
```

在 Godot 4.6 下推断不出类型，整份 `hud.gd` 解析失败 —— 连带 `main.tscn` 加载不出来，
所有验证都会在编译期炸掉（日志里有 1115 条 SCRIPT ERROR）。这行是并行改动留下的，
但会挡住本轮门禁，所以顺手改成显式 if/else 分支。

另一个：`visual-building` 里用 `main.hud.services.action_body.get_child(0)` 找购买按钮，
而商店面板现在先插一行「−/n/+」数量步进，第一个子节点已经是 `HBoxContainer`，
`button()` 收到非 Button 直接报类型错误（退出 124）。改成遍历子节点按
`service_action == "buy"` 定位 —— 面板结构以后再调也不会错位。

## 验证

```
pick-mesh            PASS exit=0    9 checks, 0 failures
unreachable-menu     PASS exit=0   24 checks, 0 failures
interact-focus       PASS exit=0
board-click          PASS exit=0
farming              PASS exit=0
modules              PASS exit=0
pocket-bubbles       PASS exit=0
building-approach    PASS exit=0
```

`pick-mesh` 覆盖：

1. 土箱屏幕上确实存在被模型覆盖的点；
2. 点土箱本体 → 命中它；
3. **点在两格之间的甲板缝 → 不命中任何交互物**（这是用户报的那个 bug）；
4. 包围盒角外侧、模型其实不存在的空间 → 射线不命中；
5. 走不到的目标仍然不出现在命中结果里，但仍可查到（用于说明原因）；
6. **点甲板缝会触发走向那里** —— 不只「没被吞」，而是走路真的动了。

`unreachable-menu` 相应改了两处旧断言：原来用「屏幕包围盒的角」当本体采样点，
现在命中按三角形算，角上往往是空的，改成在包围盒里采样找真正被模型覆盖的点。

## 实景

同一机位，先点土箱本体、再点两格之间的缝：

| 文件 | 内容 |
|---|---|
| [pickmesh-1-overview.png](evidence/2026-10-29_pick_mesh/pickmesh-1-overview.png) | 俯视整片平台，六格土箱与之间的甲板缝 |
| [pickmesh-2-body-click.png](evidence/2026-10-29_pick_mesh/pickmesh-2-body-click.png) | 点土箱本体：弹出操作菜单（种植 / 浇水 / 收获） |
| [pickmesh-3-seam-click.png](evidence/2026-10-29_pick_mesh/pickmesh-3-seam-click.png) | 点两格之间的缝：**不弹菜单**，角色开始走 |
| [pickmesh-5-seam-arrived.png](evidence/2026-10-29_pick_mesh/pickmesh-5-seam-arrived.png) | 走到缝里停住 |

日志里可直接看到判定：

```
[shot] body point=(323.7, 407.1) hit=true    → 2-body-click bubbles=true
[shot] seam point=(453.6, 460.8) found=true pick=   → 3-seam-click walking=true
```

## 边界

- 旋转体、凹形件按三角形判，天然正确；但**薄片/单面网格**从背面看会「点不到」
  —— 目前工程里的交互物都是实体盒体，没有这个风险。真出现单面片时补
  `cull_disabled` 双面判定即可。
- 命中只在 `visual_root()` 下找 `MeshInstance3D`，`MultiMeshInstance3D` 不参与
  （当前没有多实例交互物）。
- 三角形缓存按 `mesh.get_instance_id()` 存。网格热重载（编辑器里改 glb）后
  实例 ID 会变，缓存自动失效，不需要手动清。

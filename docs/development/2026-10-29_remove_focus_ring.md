# 移除世界里的聚焦环（2026-10-29）

对应条款：[SEA-INTERACT-R08](../features/interact/spec.md)。证据：`interact-focus`。

## 现象

在浅水养殖台（zone5）站到菜箱边，木甲板上会出现一道半透明的青白弧带，
横跨两个土箱之间、左右各断一次，看起来像「随手划上去的一道白漆」，
而不是任何可读的反馈。用户要求去掉。

## 根因：聚焦环的尺寸按整张甲板算，又被土箱切碎

`Interactable._build_focus_ring()` 有一颗贴地 torus（内径 .44 / 外径 .56），
尺寸由视觉包围盒反推：

```gdscript
var half := _geometry_half_extent()      # max(包围盒 x, z) / 2
var s := clampf((half + 0.35) / 0.56, 1.0, 3.0)
_ring_base_scale = Vector3(s, 1.0, s)
```

菜箱是「一个 farm_bed + 6 个 Cell」的结构，bed 的包围盒把整张培养甲板都包进去
（zone5 实测半宽 ≈ 2.0 米），于是 s 直接顶到上限 3.0，环的世界直径被撑到约 3.4 米。

三件事叠在一起，弧带就出来了：

1. **太大**：环的半径已经跟「判定半径 2.4 米」没关系了，读者无从判断它在指示什么；
2. **被切碎**：土箱比环高（0.28 米 vs 环贴地 0.09 米），环从箱子后面穿过，被遮成几段；
3. **颜色像水痕**：unlit + 0.75 alpha 的 `#8fe8d6`，在浅色木甲板上就是一道白弧。

俯视镜头里，一段 3 米长、被切成两截、还不知道在圈什么的弧 —— 没有信息量。

## 修法：删掉环，焦点只用文案 + 悬浮图标表达

`Interactable` 移除 `_build_focus_ring()` 及其全部消费者：
`_ring` / `_ring_mat` / `_ring_base_scale` / `_sync_ring_to_anchor()`，
`_process` 里的呼吸与自转，`focus_enter()` / `focus_exit()` 的显隐，
以及 `visual_root()` 里排除 `FocusRing` 的分支。

焦点状态本身一个字没动：

| 行为 | 改动前 | 改动后 |
|---|---|---|
| `focused` 置位 / `focus_changed` 信号 | 有 | 有（不变） |
| HUD 焦点文案 | 有 | 有（不变） |
| HoverCard 悬浮卡片 | 有 | 有（不变） |
| 编辑器热区预览（选中时画圆盘） | 有 | 有（不变，仅编辑器） |
| 世界里贴地环 | 有 | **无** |

`focus_position()` 的注释同步改口 —— 它的消费者现在是「判定 / 悬浮图标 / 编辑器预览」，
不再是三者各说各话里的一员。

## 验证

`python3 scripts/run_verification.py interact-focus farming modules parity`

```
interact-focus PASS exit=0
farming        PASS exit=0
modules        PASS exit=0
parity         PASS exit=0
```

`interact-focus` 的 8 项断言不依赖环：锚点=视觉中心、移动视觉锚点跟随、
新位置可选中 / 旧位置选不中、`focus_anchor = node` 逃生口，全部照旧通过。

真实渲染取证（同一机位，聚焦 / 非聚焦各一张）：

| 文件 | 内容 |
|---|---|
| `sea-work/focus-ring/z5-unfocus.png` | 焦点不在菜箱，甲板干净 |
| `sea-work/focus-ring/z5-focus.png` | **同一机位**，`focus_enter()` 后，甲板上不再出现弧带 |

两图其余差异只来自水面动画与 HUD 时钟；甲板与土箱区域没有新增任何线条。

结构性断言（场景装配完成后遍历整棵树）：

```
[no-ring] FocusRing 节点数=0  场景 TorusMesh 数=3
```

`FocusRing` 名字的节点已归零；剩下的 3 颗 TorusMesh 分别是采集点的绳圈道具、
点击落点环（`ClickReticle`，一次性扩散后自消）与一处装饰轮，都不是焦点反馈。

动画时序、悬浮卡片与焦点文案不受影响；未运行 `click`（该专项 3 项失败为既有的航行与
区块复原问题，与本轮无关）、未运行 `visual-*` 系列。

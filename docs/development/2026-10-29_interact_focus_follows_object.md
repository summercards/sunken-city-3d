# 交互热区跟随物体（2026-10-29）

对应条款：[SEA-INTERACT-R06](../features/interact/spec.md)。证据：`interact-focus`。

## 现象

把出货箱挪到码头另一侧后，箱子看得见，却要走回原来那块空地才能按 E。
悬浮图标也飘在旧位置，和箱子对不上。

## 根因：锚点写死在节点原点

热区判据原本是 `spot.global_position`，而视觉是**带偏移的子节点**：

```
[node name="ShippingBox"]  transform 位置 (3, 1.38, 14.6)   ← 热区用这个
[node name="Visual"]       position (-1.40, 0, +1.52)       ← 箱子真身在这
```

实测偏差 **2.065 米**，而 `focus_radius` 只有 2.4 米 —— 热区中心几乎落在箱子外面。
移动视觉不会改变节点原点，所以怎么挪都对不上。

同一模式的全场景扫描（30 个 Interactable）：

| 物件 | 偏差 | 半径 |
|---|---|---|
| ShippingBox | **2.065** | 2.4 |
| TradeBoard | 0.520 | 2.6 |
| SalvageWinch | 0.415 | 2.6 |
| BuildSite × 3 | 0.380 | 2.6 |
| 采集点 / 菜格 | ≤ 0.047 | 2.4 |

前四类都是「视觉带偏移或缩放」的物件；采集点和菜格视觉就摆在原点，所以没暴露。

## 修法：锚点由几何推导，三处共用

`Interactable` 新增唯一锚点来源：

```gdscript
func focus_position() -> Vector3:
    if focus_anchor == "node":
        return global_position + focus_offset
    return _geometry_anchor() + focus_offset
```

`_geometry_anchor()` 取视觉包围盒的 XZ 中心 + 自身高度（Y 保持节点原点，环才能贴地）。
包围盒按视觉 transform 缓存，视觉不动就不重算。

三个消费者改为同一个来源，否则会各说各话：

| 消费者 | 原来 | 现在 |
|---|---|---|
| `Interactor._refresh_target()` | `spot.global_position` | `spot.focus_position()` |
| `HoverCard` 图标锚点 | `spot.global_position` | `spot.focus_position()` |
| 聚焦环位置 | 固定挂原点 | 每帧跟 `focus_position()` |

> 聚焦环当天晚些时候整条移除（尺寸按整张甲板放大、被土箱切碎，读成一道白弧），
> 见 [移除世界里的聚焦环](2026-10-29_remove_focus_ring.md)。锚点契约不变。

配套两个开关：

- `focus_anchor`：`geometry`（默认）或 `node`（无视觉几何时用，如睡眠点）。
- `auto_radius`：半径取 `max(focus_radius, 视觉 XZ 半宽)`，大件站边上也够得着。
- `show_heat_preview`：编辑器里选中该节点时画一个透明圆盘表示判定范围，摆场景时能看见。

## DIY 场景的行为

只挪 `Visual`（或它下面的模型），热区、图标、环会一起跟过去，不需要回头对齐任何隐形锚点。
只挪根节点也照旧有效 —— 几何锚点是相对根节点计算的。

## 验证

`tests/test_interact_focus.gd`，8 项断言，覆盖三条契约：

1. 锚点 == 视觉包围盒 XZ 中心（偏差 < 0.01 米）；
2. 视觉移动 `(3, 0, -2)` 后锚点同步移动同样的量，且仍与新的视觉中心重合；
3. 站在物体旁能选中，站回旧锚点位置选不中（证明热区真的搬走了）；
4. `node` 模式仍能退回节点原点（精确锚点的逃生口）。

实测输出：

```
[interact-focus] 8 checks, 0 failures
```

真实渲染证据：把 `Visual` 挪 `(3.4, 0, -2.6)` 后，
`anchor=(4.999918, 1.38, 13.51747)` / `ring=(4.999918, 1.47, 13.51747)` /
`visual_center=(4.999918, 1.91958, 13.51747)` —— 三者 XZ 完全重合，环围住箱子。

## 未改变的行为

- 判定仍是「距离 + 朝向排序 + 优先级」，朝向只影响排序，不是硬门槛。
- 松手/离开/切换目标的中止逻辑（R02）未改动。
- 点击先出气泡、再接近执行的命令端口（R05）未改动。
- 采集点、菜格、睡眠点的实际判定范围不变（它们原本偏差就接近 0）。

## 同轮复跑（区分新增与既有失败）

| 检查 | 结果 | 说明 |
|---|---|---|
| interact-focus | PASS exit=0 | 本轮新增 |
| farming / modules / parity / ocean | PASS exit=0 | 未受影响 |
| click | FAIL exit=1，32 checks 3 failures | 既有：新航线取消旧拾取 / 航行途中改道 / 建造菜单前往并自动交付 |
| management | FAIL exit=1，36 checks 4 failed | 既有：经济与船等级相关断言 |
| selftest | FAIL | 既有：区块复原 zone1 / 船位复原 |

click 与 management 的失败项均为航行与区块复原，本轮改动只触及交互锚点选取、
悬浮图标锚点与聚焦环位置，不涉及航路、经济或存档复原。改动前后失败数量一致
（click 3 项、management 4 项），据此判断为既有问题。

## 顺带修掉的材质回写隐患

本轮排查中确认：编辑器插件原先在加载时调用 `set_shader_parameter` 补参数，
会把 .tres 标成「已修改」，随后保存场景即触发回写、参数被清空 —— 守卫自己成了肇事者。

已改为「编辑器只修磁盘文本、绝不改内存资源」：`MaterialParamGuard.repair_disk()`
补 `ext_resource` 与 `shader_parameter` 行，再让 `EditorFileSystem.scan()` 重新导入。
实测编辑器加载前后 5 个材质 md5 完全不变。

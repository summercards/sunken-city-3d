---
name: sea-godot-traps
description: sea 项目里与 Godot 编辑器和渲染相关的已知陷阱：@tool 脚本改写场景、材质参数丢失、CozyUI 覆盖控件样式、导入器噪音、水面两套材质与调参面板。改渲染、调参、跑编辑器相关操作前先读。
---

# sea 的 Godot 坑位

## 场景会被 @tool 脚本改写

`godot/src/rendering/water_surface.gd` 是 `@tool`：在编辑器上下文里 `_ready()` 会用 `_make_grid()` 的 257² 网格替换 PlaneMesh，场景一保存就把 ArrayMesh 烘进 `godot/scenes/main.tscn`，文件从几十 KB 涨到 1.2 MB。

任何 Godot 导入/扫描/编辑器操作之后，先 `git status`，再：

```bash
git checkout -- godot/scenes/main.tscn   # 仅当该文件没有未提交改动
```

有未提交改动时要手工处理，别整文件 checkout。

## `source_color` 的 vec3 uniform 必须存 Color

着色器里 `uniform vec3 xxx : source_color` 对应的 `.tres` 行必须写 `Color(...)`，**不能写 `Vector3(...)`**。两者读出来的数值一样，但只要用 `ResourceSaver` 保存一次（在编辑器里点保存也算），该行会变成 `= null`，参数直接丢失并且不报错。

`godot/tools/check_water_params.gd` 会检查这一点，改完水面相关资源就跑一遍。

## 调参面板与着色器必须同步

- 面板按当前方案分发清单：原版 `water.gdshader` 60 个参数、吸收式 `water_absorption.gdshader` 37 个。**加 uniform 必须同时加清单项**，否则 `check_water_params.gd` 会从着色器反读类型与 `hint_range` 对账时报 FAIL（它还会核对 `.tres` 的取值与存储类型）。
- 面板值存 `user://water.cfg`，并带一行 `__mat_sig`（`water.tres` 的 md5）。改了 `water.tres` 的出厂值，旧存档会自动作废——这是故意的。排查「参数改了没生效」先看存档里有没有旧值。
- 收藏（整套参数切换）在 `user://water_presets.cfg`，与 `water.cfg` 分开。写盘必须用不过滤的 `_preset_order_all()`，否则存一次会抹掉另一套方案（原版/吸收式）的收藏名。

## 两套水面并存

- 切换只换 `WaterSurface.material_override`（`schemes` 注册表 + `use_scheme()`），网格、波场、尾迹、桨环、岸线图共用。
- **波场 `ocean_sample()` / `bow_height()` 被 `boat.gd` 复用算吃水**，任何一方换波场都会让船穿水或浮空。
- 吸收式的 `depth_distance` 出厂 14 m、配 `beers_law` 2.2，别再往回调：照参考实现的池子尺度（3.5 m / 5.5）拍出来整片均匀青，水下沉没城市会被整片涂掉。这两个值是拿「城市可读性」换来的。
- `wave_scale` 是 Water 节点的导出属性，不在材质里；出厂值写在 `water_surface.gd` 的导出默认值上（写进 `main.tscn` 会被编辑器重写丢掉）。

## CozyUI 会覆盖所有 Control 的样式

`godot/src/bootstrap/main.gd` 里 `CozyUI.apply_tree(self)` 加 `node_added` 钩子，把所有 Control 刷成奶油底、珊瑚色按钮、按钮最小高 38 px。调试面板、临时覆盖层要在 `_ready()` 里 `set_meta("cozy_skip", true)`，否则排版会被改花。

## 导入器噪音

- `.glb.import` 里多出字段、`.tres` 加 uid、`.import` 时间戳变化，多数是导入器自动改写，`git diff` 没有实质内容，别提交。
- `git status` 残留的 `M` 可能只是 index stat 缓存，`git update-index --refresh` 能消掉。

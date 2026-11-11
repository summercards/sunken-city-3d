# 承重壁柱与楼层腰线（工坊 v4）

- 日期：2026-11-12
- 特性：SEA-WORKSHOP（条款 R41–R46）
- 范围：`shell_v2` 连续实体的立面竖向柱与楼层水平腰线、配置 schema、组件替换契约、编辑器「构架」页、架构专项与真实 editor 验收
- 不签：建筑承载/结构计算、柱头柱础装饰、腰线分缝、室内梁柱对应

## 起因

上一轮（形体 v2）把整楼收分、窗洞梯形化与逐列取号做完了，立面仍然只有「基座—墙身—檐口」的横向分节。用户要的是**竖向量感**：转角要有承重柱、窗与窗之间要有柱、每层的楼板位置要有凸出的腰线，三条都要能单独开关、参数可调。

这一轮的核心判断是：**柱和腰线是立面构造件，不是受力构件**。所以不写任何承载计算、不签结构安全；文档里也不许用「承重」去暗示结构验算，只有用户口语里的「承重柱」这个词被保留为构件名。

## 做了什么

### 1. 配置 schema（`architecture_config.gd`）

```gdscript
const PILASTER_FIELDS := ["enabled", "corner", "middle", "width", "projection", "bite", "bevel"]
const PILASTER_BOUNDS := {
    "width": [0.14, 0.90], "projection": [0.02, 0.50], "bite": [0.02, 0.24], "bevel": [0.003, 0.06]
}
const BAND_FIELDS := ["enabled", "projection", "thickness", "bevel"]
const BAND_BOUNDS := {"projection": [0.01, 0.32], "thickness": [0.08, 0.80], "bevel": [0.003, 0.05]}
```

校验里两条不是「美观建议」而是几何必要条件：

- `bite > 0`：柱必须咬进墙体。`bite = 0` 等于把柱贴在墙皮上，墙与柱之间会有一条理论上零宽、实际上会因浮点缝漏光的缝。
- `projection + bite > 2.5 × bevel`：这是柱在法向上的总厚度。厚度不够倒角吃，倒角会把柱削成一条棱，读不出实体。

`Recipe.defaults()` 保持两节 `enabled: false`——旧配方（含两栋历史候选和全部 `data/workshop/samples/`）的外观与 fingerprint 不能因为加了这个功能而变。`Recipe.authoring_defaults()`（新建文档）才默认开启。

### 2. 几何（`shell_geometry.gd`）

**转角柱必须是单件 L 形八边形。** 第一版是「两个方块柱在角上叠」——空间上看着对，但保存重载时的闭合审计按共享边图数连通分量，两个相交方块是**两个分量**，整件被拒。改成 `_corner_pilaster_polygon()` 生成一个八边形轮廓（沿本段伸 `width`、沿上段回收 `width`、法向从 `-bite` 到 `+projection`），一次 `_solid()` 成一件，问题消失。

**每根柱各自成件。** 同理，一个 part 的网格必须单连通，所以不能把四根转角柱塞进一个 buffer。命名 `pilaster_<floor>_c<n>` / `pilaster_<floor>_m<n>`。

**窗间柱压洞口要明确拒绝。** `_pilaster_clear()` 检查柱的 X 范围与洞口最大外廓（`reach`，不是下沿矩形——上宽下窄的洞上沿更宽）是否相交，撞了就写 `context.error` 并返回 false，整栋生成失败。不裁短柱、不挪位：挪过位置的柱看起来像随机竖条，比报错难查得多。

**腰线只在非顶层生成**（`floor >= floors-1` 直接返回）。顶层已经有女儿墙压顶收头，再叠一道腰线会读成两道檐口。无柱时整圈一个环件 `band_<floor>_ring`；有柱时按段生成 `band_<floor>_<i>`，段端让开柱身 `width/2 + 0.01`。

**腰线必须收在柱后**：

```gdscript
projection = minf(projection, maxf(pilaster.projection - 0.04, 0.03))
```

这是实测出来的约束。最早的写法是「腰线比柱稍微大一点点」（多 8mm），想在柱的上下留一道细阴影——结果转角处多出一圈悬挑薄片，近景里读成一个浮空的小方块。反过来收、收得有富余（40mm），柱的凸出才真正读得出来。因为这是**派生**不是校验，所以不拒绝配方；但编辑器读数必须显示实际值。

### 3. 组件替换契约（`catalog_v1.json` + `recipe.gd`）

新增两个组件：

- `band_cozy`（family `slab`）——腰线
- `pillar_cozy`（family `pillar`）——柱

为什么不复用 `wall_sun`：同材质 ≠ 同替换契约。复用墙组件会让「替换墙面」这个动作把柱和腰线一起换掉，而替件 prefab 的包络是按墙模块 nominal 尺寸做的，第二次保存时逐槽包络校验失败、整个 revision 落不下来。这个坑在 v3 的束带上已经踩过一次（第二次保存失败），这次提前拆开了。

### 4. 编辑器「构架」页

`PAGES` 从 7 页变 8 页，插在「形体」之后：「结构｜门窗｜破旧｜植物｜空间｜构架｜形体｜文件」。

控件：`pilaster_enabled` / `pilaster_corner` / `pilaster_middle` / `pilaster_width` / `pilaster_projection` / `pilaster_bite`、`band_enabled` / `band_projection` / `band_thickness`、`frame_apply`。

**这里有一个必须记住的写法**：`_apply_frame()` 不能直接 `session.apply_patch({"architecture": _architecture_snapshot()})`。`_architecture_snapshot()` 读的是 **session 里的旧配方**，把用户刚拨的控件值原样丢掉。必须先并进去：

```gdscript
var architecture: Dictionary = _architecture_snapshot()
architecture["pilaster"] = _frame_pilaster_values(architecture)
architecture["band"] = _frame_band_values(architecture)
var result: Dictionary = session.apply_patch({"architecture": architecture})
```

这个 bug 的表现很误导：按钮按下去有响应、状态栏写「构架已应用」（因为 `_frame_summary()` 读的是控件值，不是快照），但预览里一件柱都没多、快照里 `pilaster.enabled` 还是 false。8 项断言全挂在这一条上。

### 5. 验收

`editor_verification.gd`：

- `_test_frame_controls()`：控件存在性 → 基线载入 → 开关组合 → 件数/凸出关系/顶层无腰线 → 互不连坐 → 恢复。
- `_verify_shell_geometry()` 的 forbidden 清单：原来把任何非 `wall_shell_/slab_/frame_/glass_/sill_/plinth_/canopy_/parapet_…` 的件都当 legacy 违规件拒绝，现在 `pilaster_` / `band_` 放行，但**换成了两条更严的断言**——按楼层统计件数，要求逐层等量、顶层无腰线。放行不等于不管。
- `_status_text()`：读状态栏文字。`_result_button()` 只表示「按钮被按到了」，不是「操作成功」；拒绝原因必须能进断言 detail。
- `_test_frame_controls()` 的基线改用 `_orthographic_recipe()` 自造 shell_v2 文档，不再拿「当前文档」当基线——上一个用例（形体）结束时会把编辑器留在 `modular_v1` 老配方上，构架会被正确地拒绝，那测的就不是构架而是模式守卫。

`test_workshop_architecture.gd` 的 `_test_frame()`：三组开关组合、`_pilaster_clear()` 单元测试、腰线压回断言。`_pilaster_clear` 走单元测试而不是整楼生成，因为收窄开间会先被「开口与墙角冲突」拦下，测不出这条守卫。

## 实测结果

| 项 | 结果 | 证据 |
|---|---|---|
| 几何三项（shell / rules / deep） | exit0, passed=true | `20261112-002526-frame-v004-d8ccea/report.json` |
| 架构专项 | exit0, passed=true | `20261112-002417-frame-v004-77d115/report.json` |
| 真实 editor | exit0, passed=true, 2214 项 0 失败 | `20261112-005440-frame-v008-9cfe9f/report.json` |

构架专项实测值：

- 开柱后柱件 **42**（rect 3 层，14/层）；只开柱时腰线 **0** 件。
- 开腰线后腰线 **8** 件（rect 4 边 × 2 层）；顶层 0 件。
- `post_front = -4.680` / `band_front = -4.640`，柱比腰线更凸 40mm（0.18 vs 0.10）。
- 关柱后腰线仍在（两开关互不连坐）。
- L 形 12×12m：柱 16/16/16，腰线 6/6。

## 出图

`godot/tools/render_workshop_ornament.gd`，输出到 `D:/projects/sea-work/building_workshop/ornament_v001/`，7 组配方 × 3 机位 = 21 张：

| 配方 | 柱 | 腰线 | 用途 |
|---|---|---|---|
| `orn_all` | 转角+窗间 | 0.09 / 0.26 | 基准 |
| `orn_none` | 关 | 关 | 对照 |
| `orn_corner` | 只转角 | 开 | 只开一种 |
| `orn_middle` | 只窗间 | 开 | 只开一种 |
| `orn_band_off` | 开 | 关 | 关腰线 |
| `orn_deep` | 开 | 0.20 / 0.34 | 腰线故意比柱更凸，验压回 |
| `orn_flat` | 开 | 0.04 / 0.14 | 浅腰线 |

机位 `_three_quarter`（斜角）/ `_corner`（转角近景）/ `_joint`（楼层节点近景）。**正视不是验收机位**：柱与墙同色，正面平光下两者会糊成一片，看不出凸出。

目检结论：斜角与近景下转角柱、窗间柱、楼层腰线的凸出可读；腰线被压回柱后，转角没有悬挑薄片；无破面、无黑色缝隙。整体读成「有竖向分节和楼层线的立面」，但仍属参数化基础模型，不是美术终验。

## 复现

```text
cd D:/projects/sea
python scripts/run_verification.py workshop-shell workshop-architecture workshop-rules workshop-deep
python scripts/run_verification.py editor-workshop --timeout 480

cd godot
godot --path . --resolution 1500x1150 --script res://tools/render_workshop_ornament.gd -- "D:/projects/sea-work/building_workshop/ornament_v001"
```

`editor-workshop` 必须给 `--timeout 480`：柱子按件拆开后零件数明显变多，默认超时会误报。

## 踩过的坑（按发现顺序）

1. **`_apply_frame()` 丢控件值** —— 直接提交 `_architecture_snapshot()`。状态栏显示成功，几何没变。修法见上。
2. **基线拿错文档** —— `_test_frame_controls` 用「当前文档」当基线，而形体用例结束时文档是 `modular_v1`，构架被正确拒绝，看起来像构架坏了。改成 `_orthographic_recipe()` 自造。
3. **forbidden 清单误伤新构件** —— 柱与腰线被当 legacy 违规件。放行的同时补了逐层等量断言，避免「放行 = 不查」。
4. **腰线比柱多 8mm 会出悬挑薄片** —— 转角多出一圈浮空小块。改成收在柱后 40mm。
5. **两个方块拼转角柱过不了闭合审计** —— 共享边图上是两个分量。改成单件八边形。
6. **`_result_button()` 不能当结果** —— 只证明按钮被按到。必须读 `status_label.text` 或快照。

## 未做（明确不在这轮）

- 建筑承载、柱距结构计算、抗震/土木结构安全 —— 不做也不签。
- 柱头柱础装饰、腰线分缝与断头处理、柱与室内梁的对应关系。
- 宽扁低层楼「柱宽下限不可达」没有提示：`width` 最小 0.14m，墙垛比这还窄时只能靠 `_pilaster_clear` 的洞口拒绝兜住，没有「这栋楼根本放不下柱」的整楼级提示。
- 候选楼房 bundle 未重新导出（几何已变）。历史三批候选保持原样，需要新候选时在编辑器「文件」页重新保存。

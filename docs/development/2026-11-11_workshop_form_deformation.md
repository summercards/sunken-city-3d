# 2026-11-11 楼房工坊 · 形体变形（区间 + 种子，三档作用域）

[主文档中控](../../GDD_V1.0.md#sea-workshop) · [功能设计](../features/workshop/spec.md) · [独立账本](../features/workshop/ledger.md) · [工整模型 v3](2026-11-11_workshop_shell_v3_structure.md) · [skill 形体语法](../../../.workbuddy/skills/sea-scene-component-authoring/references/stylized-form-grammar.md)

## 用户要求与对应设计

主人要求：房屋的形体变形要**可以调整**，有**随机值的幅度范围**，分**整楼、窗户、配件**三处。

这与 sea-scene-component-authoring skill 的 `stylized-form-grammar.md` 是同一件事的两种说法：

| skill 原文要求 | 本次实现 |
|---|---|
| "不许有方形，不许有直筒"；`1% ≤ \|ρ\| ≤ 10%` | 三档 `min`/`max` 区间，边界按族收紧 |
| `ρ = 1 − 上口尺寸 / 下口尺寸` | 同一口径；`sign` 决定正锥/倒锥 |
| 结构族必须同向、幅度克制（1%–3%） | `structure` 强制 `sign=positive`，拒绝倒锥 |
| 梯形窗"上口略窄于下口，玻璃随之梯形" | `opening` 档，洞口+返回面+框+玻璃+门扇全跟随 |
| 线性件"圆柱必须变径" | `accessory` 档，雨棚柱按截面收分 |
| `wall_tilt ≤ 4°`：`ρ_max = tan(4°)·H/W` | `structure_limit()` 硬上限，超限拒绝并报可用值 |

**skill 没有规定"随机"这一层**——它给的是区间语法。随机落值是本次新增的机制：给区间 + `seed`，落值由稳定散列决定，同一 seed 永远同一栋楼。

## schema

`architecture.form`（可选增量，soul 层不动，缺字段的旧配方完全不受影响）：

```json
"form": {
  "enabled": true, "preset": "SF-B", "seed": 11010,
  "structure": {"min": 0.012, "max": 0.020, "sign": "positive"},
  "opening":   {"min": 0.020, "max": 0.032, "sign": "positive"},
  "accessory": {"min": 0.030, "max": 0.055, "sign": "positive"}
}
```

| 档 | 作用对象 | 语法边界 | 实际落点 |
|---|---|---|---|
| `structure` | 整楼收分，写入 `taper` | 0.01–0.10 | 墙壳/勒脚/束带/屋顶全部顶点共用映射 |
| `opening` | 窗、门洞 | 0.01–0.04 | `pull = rho × 净宽 / 2`，逐洞口按自身净宽算 |
| `accessory` | 雨棚柱、雨棚板自由边 | 0.01–0.08 | 柱按截面收分；雨棚只收外缘 |

### 落值算法

```text
value = min + (max - min) × unit_noise(seed, category)
unit_noise = FNV-1a 32bit(str(seed) + "|" + category) mod 1000003 / 1000003
```

用 FNV-1a 而不是引擎内置 hash：跨引擎版本稳定，同一配方存下来隔几个月再打开还是同一栋楼。

实测（SF-B、seed 11010）：structure 0.0174、opening 0.0283、accessory 0.0375。

### 4° 墙倾角上限的正确口径

skill 给的是 `ρ_max = tan(4°)·H_floor / W_base`。但本几何的收分是**摊在整栋高度**上的：

```text
单层墙的 ρ_floor = taper · h_floor / H_total
β = atan(ρ_floor · W / h_floor) = atan(taper · W / H_total)
∴ taper_max = tan(4°) · H_total / max(W_base, D_base)
```

`h_floor` 上下约掉。所以上限只取决于**总高与底宽之比**，不取决于单层高。按单层高算会把可用幅度低估约 `1/floors` 倍。

| 体量 | 下限幅 | 说明 |
|---|---:|---|
| 12×9m、3层（总高10.8m） | 0.0210 | 上限很低，收分必然克制 |
| 9×9m、8层（总高28.8m） | 0.0699 | 可拉到语法上限 |

**这是关键的一条：宽扁楼看不出形变是正确行为，不是功能没生效。** 目检对比图证实了这点——同参数下 12m 三层楼 SF-C 只有像素级差异，8 层瘦高楼 SF-C 收分明眼可见。

## 几何实现

### 洞口梯形必须全链条跟随

只改洞口轮廓不改框/玻璃，会在洞口肩部露出破面。共用同一个 `pull` 派生：

| 部位 | 处理 |
|---|---|
| 墙面 | `_face_grid` 保留矩形洞网格，另补洞口肩部两块三角（斜边与返回面同层斜边共端点） |
| 返回面 | `_hole_poly` 返回 4 点梯形环，`_reveal` 直接用 |
| 窗框 | `_opening_quad` 内外环同 pull |
| 玻璃 | `_glass` 同一 pull；`shell_window_geometry` 同步 |
| 门扇 | `_tapered_solid` 底/顶轮廓不同宽 |
| 门框 | U 形上沿两侧各内收 pull |

### 贴墙件只收自由边

勒脚、层间束带、雨棚板的**靠墙边不能收缩**——收缩就会脱离宿主，违反 skill 的接缝契约（`gap_m 2–20mm`，禁 `coplanar`/`interpenetrate`）。

- 勒脚/束带：用与墙同源的 `_rounded_outline`，整圈同缩，与墙保持咬合。
- 雨棚板：`_run_wedge` 让靠墙边保持原宽、自由边按 ρ 收窄。
- 雨棚柱：`_taper_section` 局部变径，柱脚精确落在 `y=0`，只由 `_vertical_accessory()` 白名单触发。

### 附带修的组件归属 bug

`belt_*` 原先复用 `wall_sun`，导致"替换墙组件"会把层间束带一起替换，第二次保存时 prefab 包络校验失败。改为独立 `band_cozy`（`family: slab`、`color: cozy` 与墙同色）+ `_slot_family()` 把 `belt_/plinth_/canopy_` 归到板族。

**这条值得记住：同一视觉材质不等于同一条替换契约。组件绑定决定的是"整件替换的粒度"，不是颜色。**

## 编辑器

新增「形体」页（插在「空间」与「文件」之间，既有页索引不变；`copy_sample` 改为 `PAGES.find("文件")` 查表）：

- 开关、强度档位（SF-A/B/C 一键填六个数）、种子
- 三档各自的 `min` / `max` 六个 SpinBox
- 「应用形体」「换一个种子」
- 落值读数：`落值：整楼1.740% · 窗2.830% · 配件3.750%` + 当前体量的 4° 上限

**taper 归属处理**：形体开启时 `taper` 是派生值，UI 里禁用该输入并写明"由形体「整楼结构」区间 + 种子决定"，避免"改了没反应"。

## 实测

| 套件 | 结果 | 证据 |
|---|---|---|
| workshop-shell | PASS exit=0 | `20261111-180846-verification-51d1d1` |
| workshop-architecture | PASS exit=0 | 同上 |
| workshop-rules | PASS exit=0 | 同上 |
| workshop-deep | PASS exit=0 | 同上 |
| editor-workshop | PASS exit=0，1900 checks / 0 failures | `20261111-180553-form-v008-6d95b0` |

### 新增断言

`test_workshop_architecture.gd` 的 `_test_form`：

- 落值在区间内、不为 0、同 seed 可复现、换 seed 会变
- 结构落值写入 `taper`；关形体时不改写
- 超出 4° 上限 / 结构倒锥 / `min>max` / 未知字段 全部拒绝
- **实际几何**：玻璃与窗框上口窄于下口、雨棚柱非直筒、墙壳随整楼收分
- 关形体后同一窗回正交矩形

`editor_verification.gd` 的 `_test_form_controls`：控件存在、应用后快照与 taper 归属正确、换种子落值改变、超限被拒且原因含可用上限、关形体后 taper 交回手改且玻璃回正交。

### 测试基线的必要修正

形体开启后 `taper` 是派生值，所有用显式 `taper` 做受控基线的旧测试都必须显式关形体，否则断言口径与几何不一致（曾导致 shell 专项 113 项假失败）：

- `test_workshop_shell.gd` 夹具 → `form.enabled = false`
- `test_workshop_architecture.gd` 的 `_recipe()` → 同上
- `editor_verification.gd` 的 `_fresh_architecture_recipe()` → 同上

## 目检

同机位对照图（`D:/projects/sea-work/building_workshop/form_v001/`）：

| 文件 | 内容 |
|---|---|
| `form_off.png` | 关形体：墙边完全垂直，窗洞正交矩形，柱等宽直筒 |
| `form_sfa/sfb/sfc.png` | 三档，12×9×3层；正视差异仅像素级 |
| `form_seed_1/2/3.png` | 同区间不同种子，落值 1.84/1.99/1.27% |
| `form_tall_off.png` | 9×9×8层关形体 |
| `form_tall_sfb/sfc.png` | 同体量开形体：SF-C 收分**明显可见**，窗洞上窄下宽 |
| `*_up.png` | 低机位仰视，收分在轮廓上更易读 |
| `compare_bands.png` / `compare_seeds.png` | 四格对照排图 |

结论：**机制生效且幅度可调**；宽扁楼克制、瘦高楼明显，均由同一条公式决定。不签"任意体量都能看出形变"——4° 物理上限不允许。

## 未签边界

- 未签完整 professional 美术终验、性能、楼梯导航、正式世界接入。
- `opening` 档只做梯形，未做窗洞歪斜/旋转（skill 允许倾斜的只有挂件，结构件禁倾斜）。
- `accessory` 档目前只覆盖雨棚柱与雨棚板；花池/水塔/招牌等独立件尚未生成，故未接入。
- 未签"任意极小体量"的可用性：宽扁且低层的楼，4° 上限可能低于 1% 语法下限，此时开启形体也不会有可见变化——这种情况应提示用户换轴向或加高，当前只拒绝超上限、未主动提示"下限不可达"。
- 不签建筑承载、受力计算或土木结构安全。

## 复现

```text
cd D:/projects/sea
python scripts/run_verification.py workshop-shell workshop-architecture workshop-rules workshop-deep
python scripts/run_verification.py editor-workshop

cd godot
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1400x1100 \
  --script res://tools/render_workshop_form.gd -- "D:/projects/sea-work/building_workshop/form_v001"
```

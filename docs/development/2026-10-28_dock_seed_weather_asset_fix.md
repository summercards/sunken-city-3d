# 登陆标记双向、种植选种、固定天气、打捞台白模

- 日期：2026-10-28
- 功能：SEA-MOVE / SEA-NAV、SEA-FARM、SEA-WEATHER、SEA-ASSET
- 依据：用户四条截图反馈 ——
  1. 点登陆按钮后船靠岸，角色应自动上岸；在岸上点同一按钮，角色应回到船上坐下。
  2. 点「种植」时包裹里不止一个种子，应弹出二级界面选种子再种。
  3. 现在天气一直是下雨，先改成非随机天气。
  4. 小平台的贴图丢了，要修回来。

## 1. 登陆标记：一个按钮，两个方向

### 改前

`_select_landing` 只在「船已经停在这个泊位」时做事：

```gdscript
if 停在该泊位:
    if 角色在岸上: _depart(func(): pass)      # 走回泊位 → 上船
    else:          走到 stand_position()      # 上岸
    return
_ sail_to_landing(...)                        # 否则只开船，开完就停在那儿
```

问题在最后一行：点「浅水养殖台」的意图是「过去并站上去」，而实现只做到「开过去」，
玩家还得再点一次同一个图标。`_depart(func(): pass)` 那个空回调也让上船没有回执。

### 改后

| 角色当前状态 | 点标记的结果 |
|---|---|
| 在岸上 | 沿同一块地面走回泊位 → `boarding` → `boat_idle`，角色挂到船下 |
| 在船上，且船就在此泊位 | 走到 `landing.stand_position()` → `ashore_idle`，角色挂回世界 |
| 在船上，但船不在此泊位（含别的区块） | 先航行；`_ashore_on_arrival = true`；靠妥回调里直接上岸 |

一次性意图 `_ashore_on_arrival` 有 6 个清零点，缺一个就会出现「上一次点登陆、
这一次只是划船，人却被莫名送下船」：

| 清零点 | 为什么 |
|---|---|
| `_on_boat_arrived` 消费后 | 意图只作用于这一趟 |
| `_cancel_action` | Esc / 停止行动 |
| `_try_sail_to`（点水面划过去） | 这是纯水面动作 |
| `_handle_prop_click`（鱼群 / 漂流物） | 同上 |
| `boat.navigation_blocked`（岸线挡停） | 没到岸，意图作废 |
| `restore_world_state`（读档） | 存档里没有这个意图 |

状态机没有新增状态或边：上岸复用 `start_walk(landing.ground(), stand_position())`，
上船复用 `depart()`。`main.gd` 里 `docked` 保持显式 `var docked: bool =`，理由见
[巨鲸材质记录](2026-10-28_whale_plain_material.md) 的连带修复段。

## 2. 种植：一律走种子二级

### 改前

```gdscript
"command": func():
    if owned.size()==1: _queue_plot_action(spot,"plant",str(owned[0]))   # 直种
    else:               _open_seed_bubbles(spot)
```

只有一种种子时跳过二级。玩家手里明明有三包，点一下就没得选，也看不出刚种掉的是哪一包。

### 改后

`plant` 命令无条件 `_open_seed_bubbles(spot)`。二级菜单同时补了两处表达：

| 项 | 改前 | 改后 |
|---|---|---|
| 层级标题 | 无 | 气泡簇上方奶油胶囊「选择种子」（`PanelContainer` + `Cozy.surface` + `Cozy.world_text(0.52)`）；裸深棕字落在木地板/水面上读不清 |
| 每颗气泡下方 | 无 | 奶油胶囊「生菜 ×3」（`ActionBubble.caption` 自绘，`Cozy.surface` 圆角） |
| 视口夹取 | 夹锚点到 `[160, vp-160]` | 按气泡簇包围盒（含胶囊 40px 与标题）夹取 |

夹取改法有据：旧实现假设气泡都在锚点左上一点点，而二级菜单沿整条上弧排开，
锚点靠屏幕左边时最外侧那颗会被切掉半截。标题高度也改成按 `hint_box` 的实际
最小尺寸算（`HINT_GAP = 14`），不再用固定 `-38` —— 三颗气泡时弧顶那颗正好顶到字。

## 3. 天气固定为晴

`weather.json` 增加 `mode: "fixed"` 与 `fixed_kind: "clear"`。`WeatherService`：

- `configure` 读 `mode`，`fixed` 时立即把 `kind` 设成 `fixed_kind`
- `tick` 在 `fixed` 下直接返回，不推 `seed`、不消耗 `remaining`、不发 `changed`
- `to_dict` 写 `version: 2`
- `from_dict` 遇到 `version < 2`（旧档没有版本字段）时**丢弃存档里的 kind** 并落到
  `fixed_kind`。这一条是必须的：旧版天气是随机轮换的，旧档里存着的很可能是 `rain`，
  也就是说玩家读一次档又会变回下雨 —— 用户看到的「一直下雨」正是这么来的。

轮换逻辑没有删除，仍归同一个服务所有（`seed` 推进、tick 分段一致、离线冻结的断言
在 `framework-modules` 里照旧通过），将来恢复只改配置。

屏幕层（`weather_presenter.gd`）与光照分类（SEA-WEATHER-R06）一行未动：晴天下
`rain = 0`，雨线自然不画。

## 4. 打捞台白模：顶点色在拆分导出时丢了

### 定位

用户截图里那块「小平台」是**家园补给站**（`绞盘打捞台`，`Models/绞盘打捞台`，
世界坐标约 `(-13.5, 1.6, 12.5)`），不是浅水养殖台。它是
`SEA-REF-FACILITY-SALVAGE-STATION`，从 zone1 的 `detail.glb` 拆出来的独立设施。

沿材质链一层层查下去：

| 层 | 事实 |
|---|---|
| 场景 | `salvage_station.tscn` → `legacy_facility_materials.gd` 按 `material_bindings.json` 覆盖表面材质 |
| 材质 | `baked_tn_1000.tres`：`toon.gdshader`，`use_texture = false`、`depth_tint = true`。**上色完全靠顶点色**（`toon.gdshader` 里 `base = COLOR`） |
| GLB | `salvage_station.glb` 主体 primitive 的 `COLOR_0` **全是 (1,1,1)**；17115 个顶点只有 1 种颜色 |
| Blender 源 | `salvage_station_v0.3.blend` 的 `Color` 属性完好，`BYTE_COLOR` / `CORNER`，采样正常 |

结论：美术没丢，**丢在拆分导出这一步**。同源的 `zone1_home_harbor/units/detail.glb`
里同一批顶点是有颜色的，所以可以直接回填。

### 修复

`tools/restore_salvage_vertex_colors.py`：按世界坐标（1e-4）从 `detail.glb` 建
「位置 → 颜色」表（实测 7972 个位置，**0 歧义**），把颜色写回 `salvage_station.glb`
的 `COLOR_0` 浮点区间。JSON 结构、几何、节点、材质一个字节没动。

| primitive | 顶点 | 精确命中 | 0.2m 内近似 | 未命中 | 颜色种类 前→后 |
|---|---|---|---|---|---|
| surface p0 | 1305 | 1302 | 24 | 3 | 11 → 13 |
| surface p1 | 60 | 60 | 0 | 0 | 1 → 2 |
| surface p2 | 132 | 132 | 0 | 0 | 2 → 2 |
| surface p3 | 17115 | 17096 | 25 | 19 | 1 → 33 |
| submerged p0 | 158 | 155 | 24 | 3 | 3 → 5 |
| submerged p1 | 82 | 63 | 25 | 19 | 3 → 7 |

「近似」是拆分时切开面新增的顶点，取 0.2 m 内最近源顶点的颜色；「未命中」44 个
留在原值（纯白），占全部 18852 个顶点的 0.23%，肉眼不可辨。

## 验证

| 检查 | 结果 | 说明 |
|---|---|---|
| `dock-seed`（新增，headless） | PASS，21 checks / 0 failures | 上下船三态、意图清零点、二级菜单、固定天气 |
| `visual-plot-menu`（新增，真实渲染） | PASS | 真实鼠标点「种植」→ 二级弹出，两张截图 |
| `visual-plot-shipping`（真实渲染） | PASS，61 checks | 补了「种植 → 选种」中间一步 |
| `framework-modules` | PASS | 天气 tick 分段/恢复断言仍成立 |
| `click`（`--full-world`） | PASS，31 checks | 最小范围下 3 项失败属既有：那三条走的是 `Scope.minimal()` 关掉的功能 |
| `minimum-loop` | PASS | 最小循环未受影响 |
| `visual-salvage`（新增，真实渲染） | PASS | 修前/修后同机位对照 |

抓图证据在 `sea-work/verification/20261028-144010-salvafter-708a36`（修后）与
`20261028-143932-salvbefore-da07d2`（修前，复现用户截图）。

## 已知未做

- `check_feature_contracts.py` 仍报 1 条 `godot/assets/materials/world_env.tres` 哈希漂移。
  该文件在本轮开始前就处于未提交修改状态（SSAO/glow/ambient 参数调整），本轮未触碰，
  未按批量更新哈希处理 —— 需要调光的人自己复核后再决定是否登记。
  `salvage_station.glb` 的漂移是本轮真实改动，已同步 `runtime_resource_inventory.json`
  的哈希，并在 `assets/registry/ledgers/scenes.json` 登记 `runtime_sha256` 与
  `runtime_patch_log`，来源可追。
- 天气固定为晴是**临时定版**。雨季、云量对光照的影响仍只在 `daylight_rig` 的天气分类里，
  没有做进画面差异。

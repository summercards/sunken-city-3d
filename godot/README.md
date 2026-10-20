# 晴空水巷 · Godot 版

网页版（`sea/` 根目录，Three.js）的 1:1 画面移植。**静态场景由网页版烘焙而来**，
光照 / 水面 / 动画 / 玩法在 Godot 内原生重建。

> **资产结构与命名规范见 [`docs/资产与命名规范.md`](../docs/资产与命名规范.md)。** 改资产前先读它。
> 正本就在本目录；`~/Documents/sea` 是早期草稿，不要再往那里改。

## 运行

```sh
~/Applications/Godot.app/Contents/MacOS/Godot --path godot
```

调试参数（写在 `--` 之后）：

| 参数 | 作用 |
| --- | --- |
| `--capture` | 等画面稳定后截图到 `outputs/godot-preview.png` 并退出 |
| `--frames=N` | 截图前多等 N 帧（默认 90） |
| `--panel` | 展开建造面板 |
| `--zone=zone3` | 直接把船摆到该区块并对齐镜头，用于逐区块回归截图 |
| `--selftest` | 跑逻辑自检（358 项）后退出 |
| `--dive` | 直接下潜 |
| `--look=x,y,z` | 镜头对准世界坐标（核对细节） |
| `--stand=x,y,z` | 把小人放到世界坐标（核对落脚面） |
| `--panel` / `--tab=bag` / `--tab=build` | 打开面板并指定页签 |
| `--grant=wood:12,parts:5` | 直接给物品（截图/演示用） |
| `--build=home_cabin` / `--buildp=0.4` | 直接开工某建造点 / 指定施工进度 |
| `--farm=ready` / `--farm=mid` | 把菜箱推到成熟 / 半程缺水（截图用） |
| `--crop=tomato` | 指定播种作物（生菜/番茄/南瓜） |
| `--sites=2` | 把所有建造点提到同一等级（演示用） |
| `--grade` | 启动就打开滤镜面板 |
| `--grade=0.96,1.05,1.06,1.08` | 直接套一组滤镜（曝光,亮度,对比度,饱和度） |

## 玩法：交互与采集

靠近采集物 2.4m 内会出现焦点环与底部提示，**按住 E** 读条采集；松手、走开或换目标都会中断。
采完物件枯竭变暗，冷却结束原地恢复。部分点位有建造前提（如铁道站的玻璃需要车站 2 级）。

- 规则实现在 `scripts/core/`（`interactable` / `gather_spot` / `gather_field` / `interactor`），
  提示条是 `scripts/ui/interact_prompt.gd`；
- 摆放表 `assets/data/gather_spots.json` 由 `tools/build_gather_spots.py` 从行走矩形 + 建筑包围盒求解生成，
  **不要手写坐标**（很容易埋进建筑里）；
- 重生成：`python3 tools/build_gather_spots.py`。

功能重做的路线与进度见 `docs/功能重做计划.md`。

## 玩法：背包与建造

**Tab / B** 打开面板，默认「背包」页：`背包 7 / 24 格`，每样物品按堆叠上限分格，
空位画暗格；货币（海贝）不占格，单独一行。装不下时产出不会静默消失，会提示「背包已满」。
「建造」页与背包同一面板，成本显示为图标 + 数量，材料不够的按钮自动灰显。

- 物品定义在 `assets/data/items.json`（唯一来源），**加物品只改这张表**；
- 账本是 `scripts/core/inventory.gd`：叠放、容量、原子扣除、`to_dict/from_dict` 存档接口；
- `scripts/economy.gd` 只剩规则（建造点/设施/打捞/船），资源读写全部经 `inventory`，
  旧的 `Economy.wood` 之类属性作为兼容层保留（读=查账本，写=改账本）。

## 画面：对齐网页版

画面基准是网页版本身，不是「感觉像」。两件事必须用同一份数据/同一张图对比：

- **岸线水纹**：`tools/capture_shore.cjs` 直接从网页版 `window.__shoreOutline` 抓 25 个形状写进
  `assets/baked/shore.json`（水深吸收、水线泡沫、外扩波纹全靠它）。**不要自己按 zones.json 重算**：
  网页版用的是 `zone.regions`，和 `walk.rects` 不是同一份（圆楼那块差最多），重算会让波纹漂在空水域上。
- **参考图**：`tools/capture_reference.cjs` 截网页版 1440x900 **建成态**（先拉满建造等级，
  否则圆楼顶上是空地，和 Godot 的烘焙资产对不上），存 `outputs/reference-web.png`。

光照用线性单位标定（`scripts/main.gd`）：`sun 0.48`、`ambient 0.56`、`hemi/ground 0.10`、`violet 0.07`，
`tonemap ACES / exposure 0.96`，**不做 contrast/saturation 加成**（加了会过曝、发灰）。
材质保留极弱高光（`SPECULAR 0.10 / ROUGHNESS 0.94`）——全关高光会让大面积浅墙糊成白纸。

实测（裁掉 HUD 后与参考图比）：亮度 113.5 vs 114.7、开阔水面 (16,120,156) vs (15,121,158)、
暖色像素 (189,187,143) vs (195,186,146)、过曝像素 0.19% vs 0%。水面色阶用 `use_debanding` 消除。

## 玩法：建造与升级

每块可升级的建筑旁立着一块**施工牌**。走近按住 **E** 交付材料，缺一件都不开工；
交付后牌子转琥珀色、立起警示围栏、堆上木料与木箱，开始真实倒计时（18~34 秒，按等级递增）。
走开、关面板、去别的区块都不会停工——计时在 `Economy.site_work` 里，不在节点里。
到点才升级，围栏与材料收起。

「建造」页是台账：等级、下一级费用、施工进度与剩余秒数，按钮是**「前往」**
（把镜头挪到牌子旁），真正的施工必须在世界里做。

- 规则：`Economy.begin_site_upgrade()` / `tick_sites()` / `site_work_progress()`；
- 世界：`scripts/core/build_site.gd`（牌子 + 现场）、`build_field.gd`（读表生成）；
- 摆放表 `assets/data/build_sites.json` 由 `tools/build_build_sites.py` 求解，
  **不要手写**：牌子必须落在行走面上、离建筑 0.9m、离采集点 ≥2.2m（否则抢焦点）；
- 费用与工期在 `Economy.SITES`，改数值不用改代码。

## 玩法：种植与温室

世界里三只木箱：木屋菜箱（需木屋 Lv.2）、圆弧农场菜箱、远海浮台菜箱。
走近按住 **E**：空地播种、缺水浇水、成熟收获；湿着的时候按 E 只会告诉你还差几秒。

- **状态长在箱子上**：土色随含水量由浅变深，作物分「芽 → 叶 → 结果」三段，
  缺水时叶片发黄下垂、生长停住，**但不会枯死**；
- 一茬要浇几次水（番茄 46 秒长成、一次浇水维持 18 秒）；走开不会替你浇，也不会惩罚你；
- **加作物只改** `assets/data/crops.json`，产量引用的物品必须在 `items.json`；
- 温室（已建设施）＝ 生长 0.72 倍 + 浇水多撑 30% + 每茬多收 1 份；
- 规则在 `scripts/core/farm.gd`（`Economy.farm`），世界节点是 `farm_plot.gd` / `farm_field.gd`；
- 摆放表 `assets/data/plots.json` 由 `tools/build_plots.py` 求解，**不要手写**。

## 场景结构

```
scenes/
├─ main.tscn                    主场景：整个海面世界都在这里，可直接在编辑器里摆
│     World/WorldEnvironment    Environment 资源（assets/materials/world_env.tres）
│     World/Lights/{Sun,HemisphereFill,VioletShadow,GroundBounce}
│     World/Water               PlaneMesh + ShaderMaterial（assets/materials/water.tres）
│     World/Zones/<区块>        区块场景实例
│     World/Gameplay/*          SeaProps / GatherField / BuildField / FarmField
│     Camera                    轨道相机（target / orbit_dir / distance 都在 Inspector 里）
│     Boat + Boat/Explorer      小船与小人
│     Birds / Underwater        飞鸟与海底世界（海底平时隐藏）
│     LandingMarkers / HUD / InteractPrompt / ColorGrade
├─ world/environment.tscn       外围沉没街区（非区块）
├─ zones/zone1_home_harbor.tscn 每区块一个场景
│     ├─ StaticBatch            烘焙几何（MultiMesh，读 assets/zones/<zone>/）
│     ├─ ModelRoot              glb 模型单元（读 assets/models/<zone>/，默认路径）
│     ├─ WalkAreas/Walk_<id>    可行动区域（矩形 + 站立面高度）
│     ├─ Landings               上岸点（预留容器）
│     └─ Plants                 植物场（读 assets/data/plants_<zone>.json）
└─ plants/
   ├─ common/<id>.tscn          通用植物：任何区块都能用
   └─ zones/<zone>/<id>.tscn    区块专用植物：与区块绑定，自带摆动与效果
```

区块坐标系：**区块内坐标相对区块 origin，y 是绝对高度**；搬区块只改 origin。

`geometry_source` 二选一：`models`（默认，glb 可替换）/ `baked`（回退，实例批次）。

> 打开 `scenes/main.tscn` 后按 **F** 框住整个场景（编辑器视角默认在原点附近，
> 第一次打开可能正对着某栋楼内部）。区块建筑由 `model_zone.gd` 在编辑器里预览，
> 所以打开就能看见实际轮廓，不用运行游戏。

**能手动编辑的东西都在场景里。** 灯光、水面、相机、小人的初始站位、UI 层都是真实节点，
`main.gd` 只做「找到它们 → 接线」，找不到时才退回程序化创建（供老场景/测试用）。
环境与水面的参数在 `assets/materials/*.tres` 里，改完重启游戏即生效；
重新生成这两份资源：`Godot --headless --path . --script res://tools/make_scene_resources.gd`。
运行时对比：`Godot --path . -- --source=baked`。

## 滤镜面板（P）

按 **P** 打开左上角面板，实时调**曝光 / 亮度 / 对比度 / 饱和度**，改的是 `WorldEnvironment`
那一个 Environment 的 `tonemap_exposure` 与 `adjustment_*`，也就是整幅画面的最终调色。

- 拖动即时生效；「复位」回到场景资源的默认值；
- 「复制参数」把四个数复制成一行，便于记进文档/提交信息；
- 「写入场景」直接把当前值写回 `assets/materials/world_env.tres`（开发环境可用，导出版只读）；
- 数值同时存在 `user://filter.cfg`，重启仍是调好的样子。

## 资产管线

```
网页版 ──export_from_web.cjs──► assets/baked/
                                   │
              ┌────────────────────┼─────────────────────┐
   build_plants.py           build_zones.py         build_models.py
   （叶片 → 植株 → 原型      （按区块切实例 →       （实例矩阵烘进顶点 →
     → 通用/专用）             区块/环境/主场景）      区块 glb + 单元 glb）
              │                    │                      │
   scenes/plants/ + 摆放表    assets/zones/ + 场景    assets/models/zones/
```

完整重建（网页版改了才需要）：

```sh
cd sea && python3 -m http.server 8765 --bind 127.0.0.1
cd godot
NODE_PATH=/Users/summercards/.workbuddy/binaries/node/workspace/node_modules \
  /Users/summercards/.workbuddy/binaries/node/versions/22.22.2/bin/node tools/export_from_web.cjs
python3 tools/make_shore.py
python3 tools/build_plants.py
python3 tools/build_zones.py
python3 tools/build_models.py
~/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --quit --path .
```

> 最后一步重建 `.godot/imported` 缓存与 glb 导入，漏了会报 `Failed loading resource: tex_N.png`。

## 海底世界（独立地图，四块分离）

海底不是把相机压到水面下，而是一张独立地图，按内容拆成四个可单独维护的区块：

```
scenes/underwater/
├─ underwater_world.tscn     UnderwaterWorld：Regions / Deco / Chests / DiveCamera
└─ region_<region>.tscn      basin（礁盆台地）/ neighborhood（沉没街区）/ reef（珊瑚海草）/ trench（北境海沟）
```

```sh
Godot --path . -- --dive                        # 直接下潜
Godot --path . -- --dive --uwat=-2,-200,-120    # 传送到海沟（调试用）
Godot --path . -- --dive --uwat=-14,-6,20       # 传送到民宅前
```

- 游动 WASD、E 上浮、Q 下潜、右键拖拽环视、滚轮拉远、Esc 上浮；点宝箱自动游过去，3 米内搜索 3 秒开箱。
- 四块各带 glb：`assets/models/underwater/<region>/{<region>.glb, units/*.glb, manifest.json}`。
- 鱼群 / 气泡 / 光柱 / 微粒 / 水面顶盖 / 宝箱 / 灯光都是运行时生成，不进 glb。
- 重烘：`node tools/export_underwater.cjs && python3 tools/build_underwater.py`（网页版要在跑）。

## 模型资产（glb）

每个区块产出独立的模型文件，可直接在 Blender 里改：

```
assets/models/zones/<zone_key>/
├─ <zone_key>.glb            整区总装
├─ units/unit_01.glb         单栋建筑 / 构件（按体量锚点自动切分）
├─ units/detail.glb          零散件合并
├─ manifest.json             摆放 + 包围盒 + 材质槽 + 顶点数
└─ units.json                划分表（anchor + radius，可手改）
```

- 单位米、Y-up、枢轴在单元水平中心 + 世界 y=0。
- 顶点色存线性 `COLOR_0`，材质槽顺序与 glb primitive 一致。
- 改模型：Blender 覆盖同名 glb → `--headless --editor --quit` 重导入 → `./verify.sh`。
- `build_models.py` 是全量重建，会覆盖同名 glb；手工改过的模型要先备份。
- 外围 `environment` 900 万顶点（约 420MB），不纳入模型层，仍走 `StaticBatch`；
  需要时 `python3 tools/build_models.py --env` 临时生成。

## 验收

```sh
# 逻辑：区块场景结构 / 可行动区域 / 植物两级库 / 船与到站
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path godot -- --selftest

# 画面：总览 + 单区块
~/Applications/Godot.app/Contents/MacOS/Godot --path godot --resolution 1440x900 -- --capture
~/Applications/Godot.app/Contents/MacOS/Godot --path godot -- --zone=zone5 --capture
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path godot --script res://tests/compare.gd

# 核心逻辑 parity（zones / economy / sail_nav，422 条）
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path godot --script res://tests/test_core.gd
```

画面基准：网页版 `outputs/harbor-lush.png`。
当前 1440x900 下平均亮度 0.471（网页 0.445），暗部 2.9%（0.7%），亮部 12.0%（12.9%）。

## 三条硬规则

1. **烘焙取「建成态」**：绿植挂在建造等级上，导出前要拉满 `buildSites[].level`，否则满墙植物全丢。
2. **先抽植物再切区块**：`build_plants.py` 产出 `plant_claim.json`，`build_zones.py` 据此排除，
   否则同一片叶子会被画两遍。
3. **Godot 4.7 把 `var x := <Variant>` 当编译错误**：从 Dictionary 取值必须显式标类型。

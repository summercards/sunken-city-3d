# 2026-11-06 · 文档与实现漂移清理（第二轮）

上一轮（[摆放位置权威链](2026-11-06_placement_authority.md)）解决了坐标类冲突。本轮处理剩下的
「文档写的和跑的不是一个东西」，并查实两条新的实质问题。

## 一、已修（8 处，全部是文档/注释，无运行改动）

| # | 位置 | 原状 | 现写法 |
|---|---|---|---|
| 1 | `godot/src/time/sleep_cycle.gd:11` | 注释「正常入睡（23:00 自动或**门口点击**）」 | 改「23:00 自动或**床上点击**，2026-11-05 起入口在室内床铺，此前的太阳房门口月亮检查点已删除」 |
| 2 | `docs/features/sleep/spec.md` 资产边界 | 「复用太阳房入口…月亮是临时检查点标记」——按现状读等于还在用月亮 | 整句删除并标注 2026-10-28 临时方案已于 11-05 作废；改为「睡觉不自带美术资产，床与房间由 SEA-ROOM 拥有，本功能只消费 `sleep_requested`」，引 `SEA-SCENE-BDR-009` |
| 3 | `docs/features/sleep/ledger.md` 10-28 行 | 「门口点击」无标注 | 就地加注「已由 2026-11-05 室内床迁移取代，此处保留历史口径」 |
| 4 | `GDD_V1.0.md` 第 28 行标题 | 「**当前可玩版本**：太阳房最小生活循环（2026-10-27）」，但标题下挂着 11-05→11-01 共 25 条后续条目 | 改「当前可玩版本与阶段记录」，并加一句说明：本节按时间**倒序**追加，10-27 原文在末尾，被覆盖处就地标注 |
| 5 | `GDD_V1.0.md` 10-27 正文 | 读起来像现状 | 加 `### 2026-10-27 阶段记录` 小标题 + 引用块列出 3 处覆盖：范围、睡觉入口、命令开关；「太阳房入口点击睡觉」原句加删除线。**数值（80 瓶盖／3 包种子／3 个浇水日／07:00 结算）保留不动** |
| 6 | `GDD_V1.0.md` 3.1 区域尺度 | 只有「建议核心可玩区域约 45×40 米」+「保留远海沉没街町」 | 补 `HOME_WATER = Rect2(-18,-12,55,48)` 这个代码真值；补默认范围实际含哪些区块；标注 `SAIL_BOUNDS` 是历史取景参考、原文已注明不作航行围栏；zone3/zone4 移除事实与「资产全保留可加回」 |
| 7 | `GDD_V1.0.md` 第 6 节前 20 分钟 | 四条节奏全是规划口吻 | 加现状对照块，逐段标：0–3 分钟入场已换、3–7 分钟闭环完整、7–12 分钟**居民未实现**、12–20 分钟**远海街町已移除所以走不通**；结论明说「只有第 2 段完整，首局节奏不能算达成」 |
| 8 | `GDD_V1.0.md` 第 9 节优先级 | P0–P3 无实现对照 | 加 13 行对照表，标出已达成（ONBOARDING／INVENTORY／WAREHOUSE／ORDER／SAVE／QUALITY／zone5）、未达成（船体改造、打捞菜单、居民、任务）、已作废（Three.js 作可玩、「保留三处可玩建筑」） |
| 9 | `README.md` `web/` 描述 | 「仍是事实上的数值基准」——与 GDD 第 5 节「历史网页数值不作为当前 Godot 数值」直接矛盾 | 改「**数值基准以 Godot 侧为准**，网页数值是历史口径」 |
| 10 | `README.md` 常用命令 | 只有契约检查，没有位置检查 | 补 `check_placed_positions.py` 一行，并给契约检查补 `--sync` 提示 |

## 二、新查实的两个实质问题

### 1. 海报图集被引擎自动转成 VRAM 压缩（画质风险）

`godot/assets/textures/facilities/neon_garden_quarter/poster_atlas.png.import` 在
11-05 首次提交与随后的 checkpoint 之间发生实质变化：

| 参数 | 11-05 首提 | 当前 | 影响 |
|---|---|---|---|
| `compress/mode` | `0`（无损） | `2`（VRAM / s3tc_bptc） | 有损块压缩，文字边缘与大面积平色易出块状伪影 |
| `mipmaps/generate` | `false` | `true` | 3D 远景不闪烁，是改进 |
| `vram_texture` | `false` | `true` | 显存占用降低 |
| `detect_3d/compress_to` | `1` | `0` | 引擎已关闭后续自动检测（一次性转换完成） |

成因：该贴图被 3D 材质引用，Godot 导入时的 `detect_3d` 机制自动把 2D 无损贴图改成 VRAM 压缩。
这不是人手改的，是引擎行为。

**为什么要单独提**：这块图集正是霓虹花园「纵向厚字招牌、橙色大广告、层叠招贴」的印刷面，按
`SEA-ASSET-R44` 的登记口径属于 `PosterUV/PosterMask` 图集例外 —— 画面清晰度敏感。而它现在是有损压缩。
`mipmap` 打开是好事，`compress/mode=2` 需要判断：近景可读优先就应显式设回 `0`；显存/性能优先就接受，
但要写进账本，别让它以「哈希漂移」的名义挂着没人管。

**未处理**：这属于画质取舍，且改动会重新导入整张图集、影响 50 个组件的外观，需要一次真实渲染对照才能定。
本轮只查清成因与参数差异，**没有改 import 设置、没有刷哈希**。

### 2. 顶层牧场总装登记落后三代

顶层牧场总装（登记 ID `SEA-SCENE-ORF-ASSEMBLY`，`ORF` 是 `ocean_rooftop_farm` 的目录缩写，下同）在 `assets/registry/ledgers/scenes.json` 里仍指向
`art_source/scenes/ocean_rooftop_farm/v001/ocean_rooftop_farm.blend`，`stage = source_verified_runtime_pending`。

但实际运行用的是：**v004 的 45 个组件 GLB** + **v006 的整楼根位置**（`Y=-55.92`）。
登记值落后三代，而 v006 目录里只有 `ocean_rooftop_farm_v006.blend` 一个文件 —— 没有
`component_plan.json`、没有 `export/`、没有验证产物（v005 都还有 plan 与 export）。

`register_v004.py` 的硬门禁是：`source_verification.json` 与 `skill_verification.json` 必须
`passed`，且 skill 行数必须正好 45。这两份文件所在的 `sea-work/ocean_rooftop_farm/` 目录**当前不存在**。

所以这条**不是刷一个哈希能解决的**：要先跑 `verify_v004.py` + `validate_skill_v004.py` 重建双验证
（需 Blender），再决定 v006 是「只改根变换、资产仍算 v004」还是另立版本。本轮不动。

## 三、确认不算问题（避免下轮重复排查）

| 疑点 | 结论 |
|---|---|
| `command_enabled` 默认禁用 `build` → 建造是不是死了 | **不是**。`build` 只禁用面板里的「建造计划」详情页；建造本体走 `craft`「建造手册」，入口在 `corner_hud.gd:45` 的默认 entries 里，可见可用 |
| 同上，`camera` 被禁用 → 相机不能用 | 不是。禁的是暂停菜单的取景入口，相机本体正常（`zoom_max = 77.8`） |
| `SAIL_BOUNDS = Rect2(-75,-75,150,150)` 但霓虹花园在 x≈156 | 不是围栏。`play_scope.gd:9` 注释原文写明「Free ocean building/sailing no longer uses this rectangle as a fence or relocates a valid distant save back inside it」 |
| `zones.json` 里还有 zone3/zone4 | 正常。它是参考数据，`main.tscn` 已不挂载这两块；`play_scope.gd` 的 `zone_enabled` 白名单里也没有它们 |
| `plants_zone3_arc_farm.json` / `plants_zone4_far_shore.json` 还在 | 正常，同上 |
| `avatar_dimensions.gd` `SCALE := 1.5` | 与文档「角色放大 50%」一致 |
| 作物 `grow_days: 3` | 与文档「3 个浇水日」一致 |
| `radiance_size = 3` 从天空材质 `ocean_sky.tres` 被删 | 语义等价。Godot 4 的 `Sky.radiance_size` 默认值就是 `RADIANCE_SIZE_256`（=3），编辑器重存时省略了默认值；同时补了 `uid`。但**未登记哈希前需要一次实拍确认**，本轮不刷 |

## 三、用户决定后的处置（2026-11-06 09:25）

上一轮列的三件待决，用户当场给了两条决定，第三条要求换措辞。

### 1. 浮店非均匀缩放 —— 用户：有意为之，手动调的

**处置**：不再当缺陷。

- 摆放台账加一列「缩放确认」，浮店填 `有意 —— 用户 2026-11-06 口头确认「我手动调的」`；
- `check_placed_positions.py` 改判定：非均匀缩放时先读台账这一列，写 `有意` 就只打 `NOTE`，
  空着或写 `待确认` 才 WARN。**这是把「人已确认」这个信息变成脚本能读的输入**，否则每次跑都重报一遍。
- 可航性不因此成立：甲板仍在世界 -12 米量级、船位 `Y=-12.4096`，`floating-shop` 41 项 5 失败、
  `sea-supply` 37 项 8 失败**如实挂着，不按参考位重算**。用户明确「先不管」，所以泊位、行走投影
  与这些断言都留给真正要用补给站停靠时再按实测标高处理。

### 2. 海报图集 —— 用户：以近景效果为主

**处置**：改回无损，并堵住引擎再次自动压缩的路。

| 参数 | 改前 | 改后 | 理由 |
|---|---|---|---|
| `compress/mode` | `2`（VRAM / s3tc_bptc） | **`0`（无损）** | 招牌字、广告画、招贴是近景阅读物，块压缩会在文字边缘与平色块出伪影 |
| `mipmaps/generate` | `true` | **`true`（保留）** | 近景只用 mip0，mipmap 不影响近景清晰度，但能消掉远景闪烁 —— 纯收益，不跟着一起关 |
| `detect_3d/compress_to` | `0` | **`0`（保留）** | 这是关键：`0` 表示引擎不再按 3D 引用自动转 VRAM。保持 0，否则下次导入又会被打回 `mode=2` |

执行过程与证据：

1. 改 `[params]` 后跑 `godot --headless --path godot --import`（本机 4.6.3）；
2. 日志确认**只重导入 `poster_atlas.png` 一个文件**（`reimport | poster_atlas.png`，1 steps）；
3. `import` 文件由引擎重写：`path.s3tc` → `path`，`dest_files` 指向 `.ctex`，`imported_formats` 与
   `vram_texture: true` 消失；
4. 缓存产物：新 `.ctex` 7.93 MB（2048² RGBA 无损 + mipmap），旧 `.s3tc.ctex` 2.80 MB 变为无引用残留；
5. `git status` 全量比对：**除 import 文件外无任何文件被 4.6.3 改写**，`.tscn`／`.tres` 一个字节没动；
6. 登记：`assets/registry/runtime_resource_inventory.json` 的 `poster_atlas.png.import` 一条
   由 `986 B / 5f5f3dff…` 更新为 `985 B / 7f7d04ee…`。`check_feature_contracts.py` 该项漂移随之消失。

代价：显存从约 2.8 MB 升到约 10.5 MB（含 mipmap）。这是「近景优先」的定价，记在这里，不藏。

### 3. 「不要用 ORF 这种代号」

`ORF` 是 `ocean_rooftop_farm` 的目录缩写，只在登记 ID `SEA-SCENE-ORF-ASSEMBLY` 里出现。
**AssetID 不能改**（账本、来源索引、运行清单全按它对齐），但文档与对话里一律写「顶层牧场」/「顶层牧场总装」，
首次出现处注明 ID 与缩写来源。本轮已把本文所有 `ORF` 措辞改掉。

## 四、core全量实跑（本轮唯一一次运行验证）

海报图集换了导入格式，必须确认游戏没崩、并且真跑到用它的场景，所以本轮跑了
`python3 scripts/run_verification.py`（默认 `core`）。证据目录
`D:\projects\sea-work\verification\20261106-092811-verification-51a4c4`。

### 结果

| 入口 | 结果 | checks | 说明 |
|---|---|---|---|
| `sunken-city` | PASS | exit 0 | — |
| `visual-sunken-city` | PASS | exit 0 | 真实渲染（1280×800 / 60fps） |
| `modules` | PASS | exit 0 | — |
| `parity` | PASS | exit 0 | — |
| `farming` | **FAIL** | 35 checks / 2 failed | 断言未跟随 zone3 移除，见下 |
| `crops` | PASS | exit 0 | — |
| `visual-crops` | PASS | exit 0 | 真实渲染 |
| `surface` | **FAIL** | 2 failed | 存量失败，见下 |

**海报图集换格式未引入任何崩溃**：`visual-sunken-city` 与 `visual-crops` 都是真实渲染，两个入口均 exit 0；
`modules` 拿到 10052 段岸线几何（与 11-05 记录的约 10050 同量级）。这解决了「改完贴图必须实跑确认」这一关。

### 新发现：`farming` 的断言没跟上「圆弧农场从主场景移除」

失败原文（`godot/tests/test_farming.gd:27-28`）：

```gdscript
check(farm.specs.size() == 13, "13 个独立地格（太阳房 1 + 圆弧农场 6 + 浅水 6）")
check(get_nodes_in_group("farm_beds").size() == 3, "三个场景种植床")
```

时间线查证：

| 时间 | 事件 |
|---|---|
| 2026-10-28（`f54a4083`） | 断言写成「13 格 / 3 个种植床」，当时 zone3 圆弧农场挂在主场景 |
| 2026-11-04（`b4601d57`） | 按「只保留横滨」把 zone3 从 `main.tscn` 移除，**断言没跟着改** |
| 2026-11-06（本轮） | 跑 core 全量，这条第一次被记录下来 |

也就是说：**从 11-04 起 `farming` 一直是红的，只是这两天没跑过 core**。这本身就是「工作没进文档」的连带证据 ——
移除 zone3 那次只更新了 `play_scope.gd` 白名单和 `test_minimum_loop`，漏了 `test_farming`。

两条路，**本轮不擅自选**（改测试断言等于改验收标准，需用户定）：
- **A. 把 zone3 加回主场景**：恢复 6 格与四区块，`farming` 自然绿，但推翻 11-04 的「只保留横滨」决定；
- **B. 改断言成派生式**：期望值从「主场景实际挂载的 `farm_beds`」派生，而不是硬编码 13；
  同时保留「核心 1 + 6 格必须在」的下限，避免以后场景被删空也绿灯。

倾向 B —— 因为「只保留横滨」是 11-04 明确决定，而且硬编码场景清单的断言会随每次场景调整再红一次。
但 B 需要把「圆弧农场 6 格」改成「若 zone3 挂载则含 6 格」，这个取舍得用户点头。

### `surface` 的 2 项失败是存量，不是本轮引入

```
FAIL 上岸高度与地面一致
FAIL 种植物件是独立场景 home_plot
```

这两条与 2026-11-05 围栏摘除那次的记录完全一致（`world/ledger.md` 原文：「`surface` 剩 2 项存量失败
（上岸高度与地面一致、种植物件是独立场景 `home_plot`）」），本轮未触碰相关代码，**确认为存量**。

顺带一个有意义的观察：`surface` 这次把 `sea_supply` 当起点跑通了：

```
[surface] sea_supplymain -> zone2main frames=2674
[surface] sea_supplymain -> zone5main frames=1360
[surface] sea_supplymain -> rooftop_ranchmain frames=2518
[surface] sea_supplymain -> neon_garden_quartermain frames=2787
```

浮店被摆到 `(69.9, -18.1, 46.4)` 之后，它作为「不挡路的远处结构物」反而让这些航路成立 ——
从侧面印证那个位置是有意挪走的，不是误拖。

## 五、顶层牧场 v001 母版被覆盖（查证并已修复）

在处理最后一项契约失败时查出的事实，**严重程度高于前面所有条目**。

### 事实

账本 `SEA-SCENE-ORF-ASSEMBLY` 登记的源是 `art_source/scenes/ocean_rooftop_farm/v001/ocean_rooftop_farm.blend`，
哈希 `060a3c4d…`。工作区里这个文件当时是 `4e54a29c…`（303571 字节）。

三项交叉核对：

| 对象 | 大小 | sha256 前 16 位 |
|---|---|---|
| 账本登记值 | — | `060a3c4d6b4fe702` |
| git `b4601d57^` 里的 v001 | 379247 | **`060a3c4d6b4fe702`** ← 与账本一致 |
| 工作区的 v001（修复前） | 303571 | `4e54a29c8b75b49c` |
| v002 / v003 / v004 / v005 / v006 母版 | 773188 / 789011 / 689684 / 277116 / 277924 | 全部不匹配 |

**结论**：账本没错，是 v001 母版被就地覆盖了；覆盖后的内容**不等于任何一个已归档版本**，
是一个没有版号的中间态。也就是说 v001 的原始母版在工作区里已经不存在，只剩 git 历史里那一份。

（`v001/component_packages/` 下 45 个组件包哈希全部与账本相符，**只有母版这一个文件被覆盖**。）

### 处置

1. 先把被覆盖的中间态备份到工程外：
   `D:\projects\sea-work\ocean_rooftop_farm\v001_overwritten_20261106\ocean_rooftop_farm.blend.overwritten`（303571 字节，留作追溯）；
2. `git show b4601d57^:art_source/.../v001/ocean_rooftop_farm.blend` 取回原始母版，
   先校验哈希等于 `060a3c4d6b4fe702` 再落盘；
3. 落盘后复查：`379247` 字节、哈希 `060a3c4d6b4fe702`，与账本一致；
4. **账本行一个字没改** —— 修复的是文件，不是登记。这一点很重要：如果反过来改登记去迁就坏文件，
   就把「源被覆盖」永久洗成「源就这样」。

### 影响面

- 运行不受影响：正式运行用的是 v004 的 45 个组件 GLB + v006 的整楼根位置，v001 母版只作历史归档；
- 这也意味着「登记落后三代」依旧成立（账本仍指 v001，实际跑 v004/v006），但**它不再是哈希失败**，
  而是一个纯粹的登记口径问题，等 Blender 重跑双验证后再升登记。

## 六、本轮验证汇总

| 项 | 结果 |
|---|---|
| `check_placed_positions.py` | **PASS，3 结构 0 失败 0 WARN**（浮店缩放已在台账标「有意」，脚本只打 NOTE） |
| `check_feature_contracts.py --sync` | **PASS，40 功能 / 867 源 / 1026 运行资源，0 issues** |
| `check_feature_contracts.py`（无参） | **PASS，0 issues** |
| `run_verification.py`（core，8 入口） | 6 通过；`farming` 2 项失败（断言未跟随 zone3 移除）、`surface` 2 项失败（存量） |

**契约检查从 4 项红到 0 issues**，这是 2026-11-02 以来第一次全绿：

| 原红项 | 怎么消的 |
|---|---|
| 海报图集运行哈希 | 改无损 + 重导入 + 如实登记（用户指令） |
| 天空材质运行哈希 | 探针证明 `radiance_size` 省略等于默认值 3，材质颜色原值不变，登记 |
| 顶层牧场源哈希 | **恢复被覆盖的 v001 母版**，不改登记 |
| 派生索引过期 | 前三项清零后 `--sync` 自动落盘，`feature_index.json` 已更新 |

天空材质的核实方式（可复算）：一次性探针读 `Sky.new().radiance_size` 与
`load("res://assets/materials/ocean_sky.tres").radiance_size`，两者均为 `3`，
`sky_top_color` / `sky_horizon_color` 与文件原值逐位一致；探针跑完即删，未留在工程里。

**仍未处理**：`farming` 断言（需用户选 A/B）、`surface` 2 项存量失败、顶层牧场登记口径升级（需 Blender）。

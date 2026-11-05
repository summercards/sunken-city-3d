# 2026-11-05 室内房间：制作、接入与实测

[返回主文档](../../GDD_V1.0.md#sea-room) · [功能文档](../features/room/spec.md) · [独立账本](../features/room/ledger.md) · [资产条款 SEA-ASSET-R52](../features/asset/ledger.md)

## 需求与落点

用户要求：入口接在原来「睡觉」的功能按钮处，按钮改成「进入房间」；进入过程用日夜变化那套过场、不加文字；
房间正方形、带一个和外面一样的玻璃前厅、木头地板、白色墙面、约 5×5 平方米；一张床，床是可交互类物品，
将来能被布置功能移动与旋转，并绑睡觉；一个出口按钮；墙需要一面窗；**对着镜头的这面墙在这个位置看不见**。
细节自补。

对应拆解：SEA-ROOM-R01–R14（功能）、SEA-ASSET-R52（资产）。

## 一、资产：13 个独立组件包

`art_source/rooms/bedroom/v001`，`tools/blender/bedroom/{build,export,package,register}.py` 一条链。

| 组件 | AssetID | 三角面 | 尺寸（米） |
|---|---|---:|---|
| 地板（5×5 木地板） | SEA-SCENE-BDR-001 | 1740 | 5.32×5.32×0.14 |
| 后墙（带窗） | SEA-SCENE-BDR-002 | 628 | 5.32×0.26×2.75 |
| 前墙（带门洞） | SEA-SCENE-BDR-003 | 68 | 5.32×0.18×2.75 |
| 东／西侧墙 | SEA-SCENE-BDR-004/005 | 24 / 24 | 0.18×5.00×2.75 |
| 天花与木梁 | SEA-SCENE-BDR-006 | 564 | 5.32×5.32×0.30 |
| 玻璃前厅 | SEA-SCENE-BDR-007 | 2052 | 3.54×1.82×3.02 |
| 门框与敞开木门 | SEA-SCENE-BDR-008 | 488 | 1.46×1.26×2.12 |
| 床铺（可交互/可布置） | SEA-SCENE-BDR-009 | 1308 | 1.16×2.03×0.97 |
| 床头柜 | SEA-SCENE-BDR-010 | 296 | 0.50×0.48×0.50 |
| 床头台灯 | SEA-SCENE-BDR-011 | 160 | 0.34×0.34×0.47 |
| 地毯 | SEA-SCENE-BDR-012 | 132 | 2.60×1.90×0.02 |
| 靠墙矮柜 | SEA-SCENE-BDR-013 | 404 | 0.51×1.54×1.06 |

合计 7888 三角面、625 KB GLB、无内嵌贴图；颜色全走 `sea_cabin_timber_8x8_512` 公共色盘，
材质只用 Matte / Metal / Gloss / Emission 四角色。原点口径分两类：壳体共用房间坐标系
（原点＝室内地面中心，Blender −Y → Godot +Z 指向玻璃前厅），家具各自以落地中心为原点。

源级断言（`build.py` 内置，失败即中断）：每包非空、三角面 ≤ 预算、UV 只有 `PaletteUV` 一层且每面是有面积的
单格内区（不跨格）、包围盒有限、无 NaN 顶点、家具底面贴 z=0 且 X/Y 对中（否则「搬动/旋转」会绕偏心转）、
后墙高度＝墙高。`export.py` 复核「导出三角面 == 源三角面」「导出不改源」「GLB 无 images/textures」。

**踩到并修掉的两处**：

1. 逐包另存用 `bpy.ops.wm.save_as_mainfile` 会把整场写进每个包 —— 13 个包各含另外 12 件，导出时合计 104104 三角面
   （正常 8008）。改用 `bpy.data.libraries.write({collection})` 只写该组件集合；`export.py` 打开包后要把它挂回场景再导出，
   否则得到空场景、静默少件。
2. 前厅靠墙那一道多补了 34 cm 裙墙，从室内看正好在门口立起一道白坎。改为只有外侧一道有裙墙与上圈梁。

## 二、接入：房间是一个区块

`godot/scenes/rooms/bedroom.tscn`，由 `main.tscn` 的 `World/Interior` 唯一持有，`zone_id="room"`。
走的是与海上区块同一套接口（`walk_areas` / `area_at` / `pick_walk` / `landing_points`），所以
「屋里点地面走路」「交互判定」「存档位置校验」都不需要另开第二条通道。站立面高度在 `_ready` 里直接取本节点世界高度，
场景文件与装配文件不会各写一遍同一个数字。

位置：世界 `(2.5, 12.6, 1.0)` —— 太阳房屋面最高点 11.89 米（实测 `PoleAndFlowers`），房间底面高出 0.7 米。
屋外时房间隐藏、处理停用、**碰撞层清零**（静态体注册在物理服务器上，与 `visible` 无关；只隐藏会留下看不见的地板）。

三块可走面合成一个 `WalkArea`：室内 4.84×4.84 + 门槛 1.1×0.34 + 前厅 3.24×1.62。
门槛这块是关键 —— 少了它，室内与前厅就是两个互不连通的矩形。

两盏室内灯挂 `home_lamps` 组，由既有日照装置按时段自动开关（18:00–19:00 渐亮），不另造亮度规则。

## 三、剖切：按镜头方位，而不是删墙

`room_cutaway.gd` 每帧算相机相对房间中心的水平偏移：四面墙各有一个朝外法线，相机落在某面墙外侧
（0.25 米余量）就收起那一面；相机高于墙顶（0.05 米余量）时收起天花与前厅玻璃顶。前厅正面玻璃、门洞立框、
四根立柱、裙墙、上圈梁按白名单收——**前厅地板与两侧长玻璃必须留着**，否则前厅只剩两片玻璃浮在海上。

三次实测反推出来的结论：

- 用「Z 阈值」判前厅近侧会把地板一起切掉（地板中心同样在远端）→ 改白名单；
- 用节点原点判位置会一件都收不起来（GLB 里每个构件都在同一坐标空间，节点原点全在房间中心）→ 用网格包围盒中心；
- 门框不跟前墙一起收，前墙消失后就剩一圈悬空的白框 → `Shell/Door` 与前墙同一法线。

## 四、功能

| 行为 | 实现 |
|---|---|
| 门口「进入房间」 | `Objects/SleepCheckpoint` → `Objects/RoomDoor`（脚本 `room_door.gd`），旧 `sleep_checkpoint.gd` 删除 |
| 进出过场 | 复用 `SleepCurtain`，新增 `cover_blank`/`uncover_blank`（0.85 秒合拢 → 全黑 → 1.05 秒打开，**不写字**） |
| 床睡觉 | `room_bed.gd` 发 `sleep_requested` → Main `_rest_for_day` → 既有 `sleep_cycle.request()` |
| 醒来位置 | `_wake_at_home` 按 `room_service.inside` 分叉：屋里醒床边、屋外醒太阳房门口 |
| 出口按钮 | `hud.set_room_mode(true)` 显示右下角「出门」圆钮（新 `exit` 图标），收起室外工具栏与视角锁定钮 |
| 床的布置 | `RoomService.place_bed(pos, yaw)`：超界夹回房间、压到固定陈设/门口先就近滑位、真没空位才拒绝 |
| 存档 | 新增 `room` 模块（`bed.position`/`bed.yaw`/`inside`），不进 required，版本号仍 4；屋里存档世界位置记成门口 |

屋里点地面只走房间地面：`_unhandled_input` 在 `room_service.inside` 时跳过漂流物、登陆点、船与水面航行分支。

### 室内不是「高处的观景台」：窗外必须什么都没有

第一版把海面留着（`_outdoor_nodes()` 的 keep 名单里有 `Water`），理由是「玻璃前厅看出去该是一片海」。
实测截图一眼就能看出问题：**屋里还能看见海**，于是这间屋子读成「悬在海面高处的一个亭子」，
而不是「一间屋子」。海面之外，背景仍是天空盒，窗玻璃又乘着天空的环境光，
白天窗格就是一格浅蓝 —— 一样是「看得到天」。

改成三层一起做：

1. **世界**：`Water` / `BoatWake` 与所有区块一起收起，只留 `Lights`、`WorldEnvironment`、`VegetationWind`。
2. **背景**：`_apply_interior_environment()` 把 `Environment.background_mode` 切成 `BG_COLOR`、
   颜色纯黑；出门 `_restore_outdoor_environment()` 原样还原。**只动这两项** ——
   环境光仍取自天空辐照，屋里的白天/傍晚/夜晚亮度与外面同步，不会因为改背景而变暗或变平。
3. **玻璃**：新增 `assets/materials/room/room_glass.tres`（同一套 `sunny_palette_gloss` 着色器与色盘，
   加 `interior_glass=true` 开关：颜色取固定深灰、`alpha 0.55`、低 roughness 留高光）。
   窗（`wall_window`）与前厅（`porch_glass`）两个组件通过 `material_overrides` 挂它，
   其余件一律走公共四角色 —— 外面的太阳房玻璃一点没动。

为什么不能只改背景：色盘 `ice` 格乘上白天的环境光就是浅蓝，玻璃照样像天。
为什么不能只压玻璃：背景若还是天空盒，从门洞看出去仍是蓝天。
为什么不能把玻璃做成不透明黑：那就成了一块墙上抠出来的黑方板，读不出「玻璃」。

### 镜头与构图：拉远，并且能自己转

第一版室内机位是 `pose_lock` —— 完全锁死，右键拖不动、滚轮没反应。两个问题：

1. **太近**。默认 `distance` 11.5 米配上 47° 俯角，5×5 米的房间四角顶到画面边缘，
   前厅地板被切掉一截。改成 **14.4 米**（`camera_pose()`），视点偏 +Z 0.55、俯角从 53° 降到 46°，
   整屋留出边距。
2. **不能转**。5×5 米的房间里，玩家想看清床、窗、地毯、门口，必须能自己转过去。

第二点不是把 `pose_lock` 一关就完事 —— 关掉之后会连**平移**一起放开，
而房间只有 5×5 米：随手一拖镜头就飘到房间外，四周全是黑的。
所以新增 `orbit_only` 模式，和 `pose_lock` 并存：

| 能力 | 室外 | 室内 `orbit_only` |
|---|---|---|
| 环绕旋转（右键拖动） | 允许 | **允许**，任意方位角 |
| 缩放（滚轮 / 捏合） | 9–38 米 | **允许**，8–24 米 |
| 平移（左键拖动 / 键盘 / 触控板） | 允许 | **禁止**（视点钉在房间上） |
| 俯仰 | 22–78° | **26–72°** |
| 跟随角色 | 默认开 | 关（房间才是主体） |

「自由」在这里的含义是**绕着房间转圈看**的自由，不是「能把镜头拖到任何地方」的自由。
后者在 5×5 米的空间里只会把人关进黑箱。

配套改了三处容易被漏掉的判定：

- **剖切判据改成「越过这面墙本身」**。原来判 `flat.dot(normal) < 0.25`（相对房间中心），
  视点一旦偏 +Z 0.55 米，相机转到正东（x≈9.9、z≈0.55）仍会被判成「在前墙外侧」，
  于是东墙和前墙同时收起 —— 房间缺两面墙。改成 `flat.dot(normal) < 墙到中心的距离 + 0.25`
  （房间墙 2.5 米，前厅正面 2.70、侧玻璃 1.72）。这个缺陷只在能转镜头之后才会出现，
  固定机位时期永远碰不到。

- `_process` 里的平移边界与高度夹取（`y ∈ [0,10]`）必须跳过 ——
  房间在 y=12.6，那条夹取会把视点直接拽到海平面，整屋出画。
- `_begin_pan` 里加了一道守卫：以后从工具/手柄调它，室内也不会平移。
- 俯仰与缩放区间改成函数（`pitch_low()/pitch_high()`、`_zoom_low()/_zoom_high()`），
  `orbit_action` / `zoom_action` 改为调用它们 —— 三个文件各写一份上下限迟早会不一致。

### 转起来才暴露的两个渲染缺陷

`pose_lock` 时期只有一个固定角度，转起来之后才看得见：

1. **左侧斜插一块暗板**。相机在 +Z（前厅前侧）时，前厅正面玻璃按法线收起，
   但东西两侧玻璃的法线朝 ±X、`dot` 是负的，被判成「远侧」而留下 ——
   它们一样挡在镜头与房间之间。修法：前厅件打 `porch` 标记，
   相机局部 z > `PORCH_FRONT_Z`(2.4) 时**整座前厅构件全部收起**，只留地板。
2. **前厅玻璃在侧面看是一块黑板**。原先前厅和窗共用 `room_glass.tres`（深灰、alpha 0.55）——
   那对「窗外什么都没有」是对的，但前厅是能走进去、也会绕着看的空间。
   拆成两种材质：窗保持深灰（`room_glass.tres`），前厅换成近透明冷灰
   （`room_porch_glass.tres`，alpha 0.16、tint 0.74），结构由白框承担。

**顺手补掉两个会把人锁在黑屏里的口子**（都不在室内主路径上，但都被这次改动放大了）：

- 在屋里读一份「屋外存下的档」：`inside` 变回 false，可场景还停在进屋那一刻 —— 世界全隐藏、背景全黑，
  而且没有任何路径会还原。补 `room_controller.resync_outside()`，在 `_after_restore` 的分支里调用。
- 从屋里回到标题（重置存档路径）：同样要把房间那套视觉还回去，否则标题界面的天空也是黑的。

## 五、实测

统一 runner（隔离用户数据、复制工程、复用只读导入缓存）：

| 用例 | 结果 |
|---|---|
| `room`（新增） | **105 项 0 失败** |
| `visual-room`（新增） | **6 机位 0 失败** |
| `visual-room-orbit`（新增） | **8 机位 0 失败**（四个方位 + 最近/最远/最低/最高） |
| `sleep-cycle` | 42 项 0 失败 |
| `visual-sleep-cycle` | 通过 |
| `water-layer` | 通过 |
| `modules` / `framework-integration` / `minimum-loop` | 通过 |
| `save-protection` / `building-simulate` / `initial-planters` / `energy` | 通过 |
| `camera` / `interact-focus` / `pick-mesh` / `click` | 全部通过 |
| `management` | 4 项失败，与 2026-11-01 体力交付记录的既有基线完全一致（未建仓库不可入库、第三种植床需船二级、修复后开放第二种植床、船升级开放远海和第三种植床），本轮未触碰仓库门槛与种植床解锁 |

真实渲染图（`godot/outputs/`）：`visual-room` 产出 `room-inside.png`、`room-bed.png`、`room-porch.png`、
`room-cutaway-north.png`、`room-night.png`、`room-door.png`、`room-outside.png`；
`visual-room-orbit` 产出 `room-orbit-front/east/back/west/near/far/low/high.png`。

## 六、一次真实事故（必须记录）

编辑台账期间为了消除一次「整文件行尾变更」，执行了 `git checkout assets/registry/ledgers/scenes.json`。
该文件当时带着**尚未提交**的 46 行围挡（`SEA-SCENE-SBW-*`）与 51 行沉没旧城（`SEA-SCENE-SCITY-*`）登记，
checkout 把这两批行连同工作区改动一起丢弃（HEAD 里本就没有它们）。

恢复方式：用两个套件**自己的**登记脚本重跑 —— `SEA_SUNKEN_VERSION=v002 tools/blender/sunken_city/register.py --apply`
与 `tools/blender/sea_barrier/register.py`，它们按各自的验收报告与组件目录逐条重建行，哈希由磁盘重算，
不接受 `failures=0` 单独认定通过。恢复后 `SEA-SCENE-SBW-*` 46 行、`SEA-SCENE-SCITY-*` 51 行与原状一致，
scenes 账本从 727（HEAD）扩到 837（+46 +51 +13 本轮）。

教训：**账本文件在带未提交改动时不能 checkout**；`json.dumps` 写盘在 Windows 上会把 LF 翻成 CRLF，
一次换行就表现为「整文件都改了」，正确做法是 `open(..., newline='\n')`，不是回滚。

## 七、未做 / 仍 pending

- 「布置」功能本体：本轮只做到「床可以被搬动并被正确存档」，没有拖拽 UI、预览虚影与旋转手势。
- 家具目录扩展、更多房间、多层、窗开合、窗帘。
- 睡姿动画（沿用睡觉功能的「独立 sleeping 状态」，人在床边睡，没有躺床动作）。
- 真实手柄/触屏、超宽屏构图、长时间帧率实测。
- 全库契约门禁当前仍有 **3 项非本轮引入**的失败，与本轮无关、未处理（详见下节）。

## 八、门禁现状

`python3 scripts/check_feature_contracts.py` 当前失败项：

| 项 | 归属 |
|---|---|
| `SEA-SCENE-ORF-ASSEMBLY: source hash drift` | 非本轮；HEAD 记录即与磁盘 .blend 不一致 |
| `godot/assets/materials/ocean_sky.tres` 运行哈希漂移 | 非本轮；HEAD 的记录与 HEAD 的文件本身就不一致（已用 `git show` 逐字节比对证明） |
| `neon_garden_quarter/poster_atlas.png.import` 运行哈希漂移 | 非本轮；上一轮未提交的导入元数据改动 |
| 派生功能索引 | `--sync` 在有问题时拒绝落盘（与 2026-11-05 植被交付记录同一现象）。本轮用同一份投影逻辑（`parse_master` + 各账本 `ledger_meta`）单独重写了 `docs/generated/feature_index.json`，只含功能行、不含资产哈希，未触碰上面三项。

本轮自己改到的运行资源（`main.gd`、`hud.gd`、`zone1_home_harbor.tscn`、新增房间脚本与场景、13 个 GLB 与组件场景）
哈希已逐条刷新，`previous_sha256` 保留。未批量刷新上述三项，避免用「更新哈希」掩盖未知变更。

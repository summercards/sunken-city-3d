# 2026-10-31 平台归为一类：拼接木板与两种浮台共用贴边拼接

关联 SEA-BUILDING-R02 / R14 / R22。布局状态仍只由 BuildingService 写入；本轮只改分类、吸附求解与建造资格，不动费用、工期、存档格式和资产。

## 用户报告

「水上木板有两种逻辑：最早的拼接木板能和现在的拼接，有拼接提示，这些拼接可以走得过去。但另外两种，4×4 和 2×4 的却会隔一些。……正常应该分两类。帮我把结构 12 件归到拼接木板那一类，拼接是由结构衍生出去的那种。……不能隔空造，需要有连接体才可以。」

## 实测复现（改造前）

在正式 Service 上扫光标，看 `snap_foundation` 给出什么：

| 光标位置（旧板西侧） | 4×4 落点 | 与旧板的缝 | 判定 |
|---|---|---|---|
| 板边 0.0 m | `(2.0,-4.0)` 4×4 | 重叠 2.775 m | 红·不能覆盖原有平台 |
| 板边 0.5 m | `(0.0,-4.0)` | 重叠 0.775 m | 红 |
| 板边 2.5 m | `(-2.0,-4.0)` | 悬空 1.225 m | 红 |
| 2×4 板边 0.5 m | `(1.0,-4.0)` | **+0.225 m 真空缝** | 绿，但走不过去 |

空旷海面 900 m 处的 4×4：`preview_reason` 返回空字符串，即**允许隔空起板**。

## 根因

1. **贴边候选被光标半径挡死**。旧实现用 `point.distance_squared_to(center) < 1.45²` 接受候选。4 米浮台贴边时中心天然离光标 2 米以上，永远达不到阈值，于是全部退回世界 2 米整数网格 —— 而旧板网格步长是 2.15 / 2.575，两者不可能对齐，落点必与旧板重叠。
2. **沿边方向吸附到 1 米节拍**，再用 `clampf(±0.5)` 放宽，导致浮台可以只搭上 0.175 米也算“贴边”，形成错台和缝隙；2.575 与 2.0 两套节拍不统一。
3. **浮台没有连接体要求**。`Assembly.reason` 的 foundation 分支只查重叠与原有平台，隔空造一路放行。
4. **分类三分裂**：`deck` 一类、`foundation` 一类（category=structure）、其余结构件被标成 `furnishing`（category=furnishing，group=structure）。手册页签因此把浮台和墙柱堆在同一页，行为却各走一套代码。

## 改造

### 分类收敛为两类

`BuildingCatalog` 的目录 now 只有 `platform` / `structure` / `decoration` 三种 category，行为上两类：

- **platform**：`deck`（拼接木板）、`raft_4x4`、`raft_2x4`。共用贴边拼接、承载并集、行走面、水线、存档。
- **structure / decoration**：其余 10 件框架件与 10 件摆件。必须落在完工承载面并满足挂点。

`is_deck()` 保留为 `is_platform()` 的同义词，`is_furnishing()` 改为「非平台」，语义与改造前逐项一致（raft=false、wall=true、planter=true、deck=false），因此相关调用点无需改动。

手册页签相应拆成「全部 / 拼接平台 / 框架结构 / 生活摆件 / 种植」，平台页 3 件、框架页 10 件。

### 贴边求解改为边对齐

`snap_foundation` 重写：

1. 对每块已完工承载面（含固定木面 `@base`）的 4 条边，先把候选的一条边**贴到该边所在直线**。
2. 沿这条边滑动，候选位置取「与某块板的角点共线」，得到齐平候选集合。
3. 只保留与并集接触长度 ≥ `JOIN_MIN=0.6` 米且不重叠的候选。
4. 用**光标到候选矩形的距离**（不是到中心）排序，取最近的一个。

0.6 米门槛高于角色直径 0.44 米，保证跨缝可走；角接触（共边长度为 0）不算相连。

自由整数网格位置只在船上成立：`free_water` 为真、且光标落点离所有承载面都超过 0.6 米时才返回。岸上永远走贴边求解。

### 连接体成为建造资格

`BuildingService._platform_join_reason` 在 `geometry_reason(strict_join=true)` 里执行：新平台必须与已有承载并集有 ≥0.6 米接缝。`origin="boat"` 是唯一豁免，因为船就是运料的连接体。

旧板沿用网格四邻判定，同一套豁免。

`strict_join=false` 只用于 `validate_snapshot`：**旧档里已经存在的孤立平台照常读档**，新门禁只约束新开工，不追溯破坏既有布局。这条与 spec「已有历史布局不强制通过新布局安全门禁」一致。

### 来源字段

`origin`（`shore` / `boat`）是瞬态命令字段，由 `BuildingController._afloat()` 从 `actor_state.mode()` 派生；`_record` 不写存档，`validate_snapshot` 把它列入瞬态字段拒绝清单。

## 被推翻的旧断言

以下断言代表上一版口径，本轮明确反转，不是“修测试让其通过”：

| 位置 | 旧断言 | 新断言 |
|---|---|---|
| `test_building_open_rules.gd` | `disconnected foundation accepted by geometry; policy owns eligibility` | 岸上远处起板必须被拒；船上可以 |
| `test_building.gd` | `remote foundation geometry allowed` | 同上，拆成两条正反断言 |
| `test_building_kit.gd` | 夹具直接建孤立浮台 | 夹具显式传 `origin="boat"`，真实贴边路径交由 `building-join` 覆盖 |

`test_building_kit.gd` 的 `build()` 增加 `origin` 参数并默认 `boat`，原因写进注释：这些用例的意图是「每件构件都能建」，起点位置是任意的；贴边规则由新专项负责，避免用同一份夹具同时承担两种语义。

`test_building_visual.gd` 有一处**真实测试缺陷**被本轮暴露：它直接点 `recipe_buttons.planter`，隐含依赖「planter 卡片在第 1 页」。手册按类别重排后 planter 落到种植页，卡片被 `hide()`，点击落空，`recipe` 仍是空串，于是 `update_preview` 提前返回、`preview={}`、四条断言连带失败。修法是让它走玩家真实路径：先点「种植」页签再点卡片，并新增一条 `planting tab selects the planter` 断言锁住这件事。这不是迁就实现，而是原测试本来就绕过了一级导航。

## 验收

全部经 `scripts/run_verification.py` 在 Autoload 前隔离用户目录运行，未写入玩家存档。

| 专项 | 结果 | 证据目录 |
|---|---|---|
| `building-join`（新） | 37 项 0 失败 | `20261031-002840-joinfix5-8c7357` |
| `building-open-rules` | 122 项 0 失败 | 同上 |
| `building` | 30 项 0 失败 | `20261031-002451-joinfix-a4182f` |
| `building-space` | 18 项 0 失败 | `20261031-002840-joinfix5-8c7357` |
| `building-integration` | 53 项 0 失败 | 同上 |
| `kit-safety` | 72 项 0 失败 | 同上 |
| `building-kit` | 121 项 0 失败 | 同上 |
| `visual-recipe-cards`（真实鼠标） | 108 项 0 失败 | `20261031-003506-joinfix-cards2-0972f8` |
| `building-approach` | 18 项 0 失败 | `20261031-002922-joinfix6-7d13d7` |
| `building-restart`（两进程） | 11 + 5 项 0 失败 | 同上 |
| `ground-space` | 33 项 0 失败 | 同上 |
| `character-space-save` | 10 项 0 失败 | 同上 |
| `visual-building` / `visual-building-kit`（真实渲染） | 均 PASS 退出 0 | `20261031-003928-joinfix-final2`、`20261031-003305-joinfix-visual-00e532` |

`building-join` 覆盖：两类判定、岸上/船上隔空差异、5 个光标距离的贴边齐平、旧板→4×4→2×4 链条、三段接缝的实际行走连通、角接触不算相连、框架仍需支撑、孤立平台旧档可读可拆可续建。

实景核对：`kit-assembly.png` 里 4×4 浮台与旧板并成一片连续木面，无错台、无真空缝；`recipe-cards-platform.png` 平台页只有 3 张卡；`recipe-cards-all.png` 首屏按「平台 → 框架」排序；`recipe-cards-decoration.png` 生活摆件页 10 件独立成页。

门禁：功能契约 `--sync` 与无参检查均 PASS（35 功能、553 源资产、465 运行期哈希、0 问题）；架构检查 17 个独立规则/存储服务、0 问题。

## 未执行 / 边界

- 手机触屏与实体手柄专项仍未执行，与上一轮一致。
- 4 米浮台贴 2.575 米旧板边时，齐平一端必然悬空 1.425 米；这是保留旧板尺寸的既定结果，不视为缺陷。
- 本轮未对「孤立平台仅船上可建」做手柄/触屏路径的实机验证。


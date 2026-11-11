# 2026-11-11 楼房工坊 · 工整模型 v3（基座/束带/窗台/雨棚/女儿墙）

[主文档中控](../../GDD_V1.0.md#sea-workshop) · [功能设计](../features/workshop/spec.md) · [独立账本](../features/workshop/ledger.md) · [上一轮连续壳](2026-11-11_workshop_continuous_shell.md) · [架构变体](2026-11-11_workshop_architecture_variants.md)

## 用户批评与这一轮的目标

主人看前两轮的成品，判断"不是程序化一个结构严谨的房子，是拼起来的"。这一轮不以测试数量为目标，只解决"看起来像拼装"的具体成因，验收标准是**整栋大图与局部近景里没有拼装痕迹**。

逐条定位到六类可指认的成因，并各自给出几何修正：

| 现象 | 成因（代码层） | 这一轮的做法 |
|---|---|---|
| 层间一条亮带，像两块料对接 | 楼板外缘与墙皮同面，且板/墙是两种材质 | 板内收 30mm 藏进墙壳，另加同色"层间束带"封板缘 |
| 建筑像浮在板面上 | 没有基座，墙直接从结构板起 | 整栋一圈勒脚环，咬入墙皮 8mm |
| 立面没有收头 | 默认 `roof.mode=none`，屋顶是裸板 | 新建默认女儿墙 + 压顶 |
| 窗洞是墙上挖的方洞 | 默认 `sill_enabled=false` | 新建默认窗台板 0.16 挑出 / 0.08 厚 |
| 墙角一条贯穿竖缝 | 贴墙附件用直角 miter，墙是圆弧 | 勒脚/束带改用与墙同源的 `_rounded_outline` |
| 入口就是墙上一个洞 | 只有门框，没有雨棚，也没有门扇 | 门头雨棚平板 + 两根落地柱 + 实体门扇 |

另外把新建默认的建筑比例从"仓库"改回"住宅"：层高 5.1m → 3.6m，板厚 0.2 → 0.18，窗 1.4×1.8 → 1.5×1.9，门 1.4×2.8 → 1.6×2.4。旧配方仍按 `Recipe.defaults()` 的旧值解释，不改存档、不迁移。

## 几何实现

### 楼板与层间束带

```text
SLAB_BAND   = -0.03      # 板轮廓向外偏移量取负 = 内收 30mm
BELT_PROJECTION = 0.004  # 束带比墙皮凸 4mm
BELT_BEVEL  = 0.004
```

束带高度覆盖 `[本层墙顶 - INSET, 本层楼面标高]`，即正好包住下一层的板缘，材质跟随墙体组件（`wall_sun`），不引入第三种颜色。立面因此读成"基座—墙身—檐口"三段，层间只剩一道 4mm 的细阴影线。

### 接头重叠量

`INSET` 从 3mm 收到 0.8mm。3mm 在两个高度上会形成可见凹槽，而它的唯一作用是防浮点缝。

```text
wall_bottom = base - INSET
wall_top    = base + net_height + INSET
```

`test_workshop_shell.gd` 的层高断言改成读 `ShellGeometry.INSET`，并单独断言 `0 < INSET <= 2mm`，不再把数字写死在测试里。

### 勒脚

整圈环形实体，外轮廓比墙皮凸 60mm、内轮廓咬入 8mm、高 420mm，落在 `y ∈ [0, 0.42]`。用 `_ring_solid` 生成——外/内两条同点数轮廓，避免像板那样封成实心块挡住门。

### 入口雨棚

```text
CANOPY_PROJECTION = 1.05   # 挑出
CANOPY_EXTENSION  = 0.40   # 两侧超出门洞
CANOPY_THICKNESS  = 0.18
CANOPY_LIFT       = 0.16   # 门框顶到雨棚底
CANOPY_POST       = 0.18   # 柱截面
```

雨棚背面取 `run` 深度 +0.06（向墙内咬入），正面为 `back - 1.05`；两根柱从雨棚外端 `+0.10` 处起算、柱脚落到 `y=0`。柱心离门框净边 0.32m，避免在透视里被读成门框延伸出的杆。

### 转角连续性（这一轮修的最隐蔽一处）

勒脚与层间束带最初用 `_offset()` 生成直角 miter 轮廓，而墙壳的凸外角是 0.07m 三段圆弧。两者在墙角各走各的，近景里形成一条贯穿楼层的竖缝——是"拼装感"里最难解释、但目检一眼就看得到的那条。

修法：新增 `_rounded_outline(polygon, inset)`，复用墙壳同一套 `_corner_arc` 采段规则（凸角圆弧、凹角 miter），勒脚与束带都改用它；同时 `_ring_solid` 的倒角只收 Y 方向，不再对 XZ 再做 offset（二次 offset 会把圆弧重新 miter 化）。

### 门洞必须是门（正视图才暴露的问题）

正面出图时看清了：门洞是空的，透过它能看见室内楼板——读起来是"墙上挖了个洞"，不是入口。

补 `_door_leaf`：单块闭合实体板，按门框净尺寸落在洞口内。

```text
DOOR_LEAF_THICKNESS = 0.05   # 门扇厚
DOOR_LEAF_RECESS    = 0.06   # 从墙外皮退进
DOOR_LEAF_GAP       = 0.002  # 四周装配缝
DOOR_LEAF_BEVEL     = 0.004
```

slot 记 `door_<suffix>`、kind 记 `frame`。**不生成门把手、玻璃视窗、双开门分缝**——那些没有构造依据可以照抄，猜出来只会多一处假细节。

顺带修了雨棚柱的横向位置：原先柱心用 `half - CANOPY_POST_INSET - POST/2`，柱内表面会压进门洞净宽边缘；改为从雨棚端部内缩 `BEVEL` 起算，柱内表面落在门框之外。

### 退台默认不加围护

`roof_edge_geometry.gd` 原先会把 `roof_main` 的 `mode` 应用到每个 terrace surface，退台处逐段截断出的女儿墙读成一排锯齿碎块。改为：退台 surface 默认 `none`，需要围护时给该 surface 的边写 `edge_overrides` 显式开启。`roof_edge_quality.contacts` 同时改成各 surface contacts 的并集，编辑器和文档读同一处。

## 编辑器侧修正

| 问题 | 原因 | 修法 |
|---|---|---|
| 载入配方后保存被拦"存在未应用输入" | `_refresh_architecture_controls` 改完控件值后没有重取窗口局部基线 | 刷新末尾补 `_capture_window_local_baseline()` |
| 新文档永远报 `component_id` 未应用 | `refresh_preview` 无条件恢复旧 `_local_baseline`，把上一份文档的槽位值带进来 | 非 `preserve_slot_fields` 时按重建后的槽位重取基线 |
| 失败提示只有一句通用话 | 只返回布尔 | 新增 `_pending_local_fields()`，原因里列出具体控件键 |

## 验证

### 实测（均为本轮实跑，不改写历史批次）

| 套件 | 结果 | 证据目录 |
|---|---|---|
| workshop-shell | PASS exit=0 | `D:/projects/sea-work/verification/20261111-165719-verification-dd2b68` |
| workshop-architecture | PASS exit=0 | 同上 |
| workshop-rules | PASS exit=0 | 同上 |
| workshop-deep | PASS exit=0 | 同上 |
| editor-workshop | PASS exit=0，1819 checks / 0 failures | `D:/projects/sea-work/verification/20261111-170241-shell-v3-doors2-55f69d` |

editor 报告 `passed=true`、`enginehint=true`、`is_playing=false`、`scene_unchanged=true`。

### 顺带修的验证基建

`scripts/run_verification.py` 用默认 locale 读 `godot/project.godot`，在中文 Windows 上偶发 `UnicodeDecodeError: 'gbk' codec can't decode byte 0x88`（文件里含 `·`）。改为显式 `encoding='utf-8'` 读写。

### 主线程目检（这一轮的真正验收）

整栋与局部共七张图，逐张看过：

- `rect_three_quarter.png` / `rect_front.png` / `rect_back.png`：层间亮带消失，立面读成三段式，窗台成排、女儿墙有压顶。
- `rect_entrance_detail.png`：雨棚咬进墙、两根柱落地在门洞两侧、门扇在框内退进，没有浮空件、没有可看穿的洞。
- `rect_front.png`：正立面门居中、窗成排对齐、基座与檐口两条水平线笔直。
- `rect_corner_detail.png`：凸角竖缝在改用同源圆弧轮廓后消失，束带在转角连续。
- `u_terrace_three_quarter.png`：退台不再出锯齿碎墙。
- `l_three_quarter.png`：L 凹角两墙连续，屋顶栏杆立在压顶上。

目检结论：**"拼装感"的三个主因（材质同面、无基座、无收头）已消除**；整体仍是简洁的住宅体量，不冒称丰富美术终验。

## 交付

输出根：`D:/projects/sea-work/building_workshop/shell_v3/outputs/`

| 文件 | 内容 |
|---|---|
| `rect_three_quarter.png` 等 7 张 | 1600×1200 真实 SubViewport 渲染（整栋 / 正面 / 背面 / 墙角近景 / 入口近景 / L / U 退台） |
| `workshop_shell_model_rect.png` 等 3 张 | 1400×1100 编辑器内独立离屏模型图 |
| `workshop_editor_1600x1000_continuous_*.png` 5 张 | 1600×1000 真实编辑器 framebuffer |
| `shell_rect_1794387870_107701812/`、`shell_l_1794387870_107701812/` | 五件候选 bundle |
| `shell_v3_delivery_report.json` | 43 项文件/hash/状态核对，passed=true、failed_count=0；引用 editor 1819 项 / 0 failures |

已装入工程：

- `D:/projects/sea/godot/scenes/workshop_buildings/shell_rect_1794387870_107701812/revision_0001/`
- `D:/projects/sea/godot/scenes/workshop_buildings/shell_l_1794387870_107701812/revision_0001/`

候选项实际字段为 `candidate_ledger_status=exported_pending_project_registration`、`formal_registry_written=false`、`noMain=true`；不是正式资产，未写 registry、未挂 Main。

## 实际面数

| 体量 | 部件数 | 总三角面 | 结构三角面 | 节点 | 碰撞体 |
|---|---|---|---|---|---|
| 矩形 12×9m 3层 | 141 | 9896 | 4020 | 164 | 9 |
| L 12×12m 3层 | 159 | 11708 | 5016 | 182 | 9 |
| U 16×13m 3层退台 | 203 | 15168 | 6496 | 226 | 9 |

结构三角面从上轮 3200 升到 4020，增加量来自勒脚环、层间束带（三件）、雨棚三件——都是消除拼装感所必需的实际构件，不是加密细分。门扇另记 60 面（属配件，不计入结构）。总面数仍在 180000 预算内，节点数远低于 2000。

## 未签边界

- 未签完整 professional 美术终验、性能、复杂根系/墙面苔、楼梯导航、全楼可达、正式世界接入。
- 不签建筑承载、受力计算、土木结构安全或人群防护规范；"结构严谨"只指几何、接合、洞口、轮廓与模型组织。
- 女儿墙只做单圈 0.9m，未做女儿墙压顶分缝、屋面排水坡、屋面设备。
- 内角圆弧、墙上下水平边圆弧仍未实现。
- 雨棚只做门头平板+两根柱，未做雨棚排水、采光顶、门斗。
- 未签编辑器中"人工连续改多个控件再保存"的完整操作路径；本轮修的是基线错位导致的误拦。

## 复现

```text
cd D:/projects/sea
python scripts/run_verification.py workshop-shell workshop-architecture workshop-rules workshop-deep
python scripts/run_verification.py editor-workshop
python tools/workshop/finalize_shell_v3_delivery.py
```

渲染审阅图（不进编辑器、不写工程资源）：

```text
cd D:/projects/sea/godot
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x1200 \
  --script res://tools/render_workshop_shell_v3.gd -- "D:/projects/sea-work/building_workshop/shell_v3"
```

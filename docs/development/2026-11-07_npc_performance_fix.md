# 2026-11-07 NPC 性能修复与天台收尾

[主文档](../../GDD_V1.0.md#sea-resident) · [NPC设计](../features/resident/spec.md) · [NPC账本](../features/resident/ledger.md) · [时间设计](../features/time/spec.md) · [时间账本](../features/time/ledger.md) · [模块契约](../architecture/module_contracts.md) · [施工记录](2026-11-07_npc_module_framework.md) · [原帧诊断与追加结果](2026-11-07_frame_diagnosis.md)

## 1. 当前范围与证据口径

用户已暂停住所。Main已移除resident_harbor实例及zones/scope绑定，source保留；七人全在既有rooftop_ranch用户手摆root下的NpcStations35局部Marker，无物理住房，UI仅“暂驻天台”。用户root与其他旧transform未动。历史住所R01–R07/source资源继续partial / deferred，本轮不恢复住房开发，不以历史住所版PASS代签天台版。

七人/七配件、21个人+4关系事件、84日常对白、9关系边、五职业端口、独立NPC与独立Shop、两商店11商品和三花各四stage已实现，有专项；实现与专项通过不自动等于完整产品验收。最终证据已收齐：213213 shop-rules259/0，214439天台integration/save/seed/restart/visual五项合计2277/0，均exit0/PASS、unexpected_errors空；旧7项UI失败已由最终复验解决，历史保留。14PNG已产出，主线程已目检seven-residents、flower-purchase、story-choice三图，其余11图仍待人工审阅，不称14全目检。NPC/Shop登记implemented（已实现待完整产品验收），不标verified。

以下读取现有统一runner报告和日志，不声称文档线程重新运行Godot。各报告head均为 `aa12686907371f5e389e5923f259a2f886738235`，同时含未提交working_tree记录及工程外project快照；不能仅凭相同head声称快照内容完全相同。实际进程命令、隔离user_data、退出码与错误列表以各report.json为准。

## 2. 根因与修复契约

旧诊断显示Main._process中位153.23ms，sleep_cycle.advance、world_clock.tick与npc sync调用各约75–78ms；sleep内部tick后Main再次tick，时间信号又同步触发NPC全量日程/锚点工作。原诊断保留，不回写旧结果。

| 所有者 / 条款 | 当前实现与不可回退的门禁 |
|---|---|
| WorldClock / SEA-TIME-R12 | Main只调sleep_cycle.advance(delta)，由其内部至多tick一次，删除Main第二次clock.tick；有效delta cap到23:00睡点，暂停/睡眠不推进。06:00醒与07:00经营晨次分离，不新增时钟或存档字段 |
| Main时钟订阅 | clock.changed → Main._on_npc_clock_changed → Presenter.notify_world；只拷贝小型世界字典，不在信号栈解析日程、采anchor_snapshot、投影或寻路 |
| Presenter / SEA-RESIDENT-R14 | 0.5s检测日/分钟、任意日程from/to、conditions.hour_from/hour_to、21:30边界、天气、关系/剧情，以及手摆Marker/root/support变化；变化才执行全量同步，不仅硬编码06/10/17等默认时间段 |
| WorldPorts与站位provider | 每batch仅1次anchor_snapshot；别名缓存稳定ID、不缓存旧世界站位；support cache须随active/surface/revision及Marker/root变换失效，不把失效站位继续用于路径 |
| idle与恢复 | idle不每physics帧投影支撑；检测批次核对支撑，移动仍走原CharacterMotor/GroundSpace；失支撑停止/隐藏与fallback不变。force读档/恢复刷新保留，优化不得丢失暂停恢复、日程或布局变化 |

保持泛光、七人、现有画质和用户摆位；没有靠关特效、降质或删NPC获得本轮性能结果。NPC不推进时间、不拥有Shop交易；Shop继续由ShopService/Catalog/Panel和Inventory原子端口独立维护。

实现入口：[Main](../../godot/src/bootstrap/main.gd)、[SleepCycle](../../godot/src/time/sleep_cycle.gd)、[Presenter](../../godot/src/npc/npc_world_presenter.gd)、[WorldPorts](../../godot/src/npc/npc_world_ports.gd)、[天台provider](../../godot/src/npc/npc_rooftop_anchors.gd)。

## 3. 真实渲染帧率与函数探针

[报告](../../../sea-work/verification/20261107-211435-npc-fps-after-fix-6e7a56/report.json) · [帧诊断日志](../../../sea-work/verification/20261107-211435-npc-fps-after-fix-6e7a56/visual-frame-diagnosis.log) · [函数日志](../../../sea-work/verification/20261107-211435-npc-fps-after-fix-6e7a56/visual-frame-functions.log)。两项exit0/PASS，unexpected_errors为空；既有资源UID回退及导航精度WARNING仍见日志，不宣称无警告。

设备RTX 4060 Ti，Vulkan Forward+、Godot4.6.3，日志实际viewport为1600×1000；report命令含启动分辨率1280×800，不能混作实测viewport。runner固定模拟步长60，真实帧时由时钟测量，是隔离场景结果，不是发行包、其他设备或玩家存档实时性能。

| 工况 | FPS | 帧p50 / p95（ms） | draw p50 |
|---|---:|---:|---:|
| 泛光开 | 59.943 | 16.681 / 18.097 | 3186 |
| 泛光关（仅诊断对照） | 59.956 | 16.703 / 17.790 | 3177 |
| 泛光再开（保留） | 59.956 | 16.690 / 17.900 | 3179 |

| 五次顺序调用统计 | 旧median（ms） | 新median（ms） | 解释 |
|---|---:|---:|---|
| Main._process | 153.23 | 0.752 | 新样本0.742/0.751/0.752/0.998/1.943 |
| npc_sync | 77.62 | 0.008 | 新样本0.007/0.007/0.008/0.019/2.458；含首轮2.458ms，重复无变化调用走增量/短路，不是每次全量sync仅0.008ms |
| sleep_cycle.advance | 75.11 | 0.017 | 高频时钟通知不再同步阻塞NPC解析 |
| world_clock.tick | 75.85 | 0.012 | 探针独立调用；生产Main不再第二次调用 |

旧~5.7FPS与新~60FPS的场景并不完全一致：旧住所已撤，draw由3654–3955降至约3186。因此不能把全部约10倍提升归为纯算法，也不能将当前60FPS读成无上限吞吐量。函数探针对照直接支持“同步阻塞已消除”；该结论与场景绘制量变化分别记录。

复验入口（仅列可复现命令，不声称本线程执行）：

```bash
python scripts/run_verification.py visual-frame-functions visual-frame-diagnosis --label npc-fps-after-fix
```

## 4. 规则、性能、主时钟与通行证据

| 独立证据 | 已确认结果 | 限定 |
|---|---|---|
| [204747小fixture报告](../../../sea-work/verification/20261107-204747-npc-performance-final-8687e2/report.json) / [性能日志](../../../sea-work/verification/20261107-204747-npc-performance-final-8687e2/npc-performance.log) | npc-performance 61 checks / 0 failures、exit0；120次notify+sync合计558μs；npc-world也PASS | 小fixture指标，不是正式Main每120帧成本或设备吞吐承诺 |
| [211435合批报告](../../../sea-work/verification/20261107-211435-npc-performance-rooftop-7e1d96/report.json) | npc-performance61/0、npc-rules655/0、npc-world119/0、npc-appearance2469/0、npc-careers71/0、flower-crops1233/0、sleep-cycle42/0，七项均exit0/PASS | 同报告shop-rules失败，不签整批通过；headless外观专项不能替代真实截图 |
| [212152主时钟报告](../../../sea-work/verification/20261107-212152-npc-clock-once-cc6ca7/report.json) | npc-clock301/0、sleep-cycle42/0，均exit0/PASS、unexpected_errors空 | 真实Main单推进/睡眠回归；不是完整天台integration/save/restart |
| [211124天台通行报告](../../../sea-work/verification/20261107-211124-rooftop-access-final-5ada04/report.json) | rooftop-npc-access772/0、rooftop-ranch655/0、water-layer1613/0，三专项均exit0/PASS | 同报告landing-markers另有失败，不能写整报告全绿 |

天台泊位本轮仅调局部Marker `(26.4,57.3,-2.1)`、boat `(26.4,57.04,-5.1)` 与yaw=PI/2，以避开shore_environment旧圆弧楼shape；这是当前局部测量值，不是世界坐标硬约束。用户rooftop_ranch root及其他旧transform未动，无新物理房屋，不改旧圆弧楼资产来掩盖阻挡。

主时钟可复验命令：

```bash
python scripts/run_verification.py npc-clock sleep-cycle --label npc-clock-once
```

其余报告的真实命令、脚本入口、隔离路径与版本以各report.json为准；本轮不重跑作者工具、不修改runner、不批量刷资产哈希。

## 5. 历史失败处置与独立未验项

- **shop-rules失败历史（已解决）**：211435合批为218 checks / 7 failures、exit1。失败为键盘增量、鼠标增量、鼠标减量、Enter购买成功不关闭、向下选择下一商品、E确认购买、购买失败不关闭且原因可读。213213最终输入复验259/0、exit0已解决，旧报告不改写，不用flowers或NPC专项替代。
- **通行报告的额外失败**：landing-markers为exit1，远端平台fixture受体力不足影响，并有far active landing、current return landing断言失败；原因与最终修复由主线程核实，不擅自归因或以三专项PASS抹去。
- **全量天台运行主验已收齐**：214439五项2277/0、exit0/PASS，14张PNG已生成；当前只确认主线程三图目检，其余11张待审。签署依据为当前天台独立报告，不挪用192319住所版integration/save历史PASS。
- **住房deferred**：source资源、七屋/50m²/家具/住所35Marker等历史条款保留，不要求本轮恢复制作/接入/验收，不把资源仍在记作当前住房已完成。
- **设备与全局门禁**：其他设备/低端机、发行包、玩家当前存档、全位置/全路线及资产权属未由本轮帧探针签署；全局sync/check与并行漂移由主线程最终汇总，不能等同当前专项全绿。

## 6. 主线程最终待填位置

本节由待填表更新为**最终范围签署 / 剩余产品验收表**；标题保留以维持既有相对锚点。运行证据已收齐，不再等待执行。

| 签署项 | 最终证据与明确边界 | 同步文档位置 |
|---|---|---|
| shop UI修复复验：已通过 | [213213报告](../../../sea-work/verification/20261107-213213-shop-input-final-638cdf/report.json)：shop-rules259/0，exit0/PASS、unexpected_errors空；原218/7失败已解决但保留。真实进程命令与快照见report | [Shop账本](../features/shop/ledger.md)、[施工记录最终签署](2026-11-07_npc_module_framework.md#14-最终天台交付范围签署) |
| 天台integration/save/restart：已通过 | [214439报告](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/report.json)：integration668/0、save618/0、seed408/0、restart202/0、visual381/0，合计2277/0，五项exit0/PASS、unexpected_errors空；真实HUD航行/上下船/消防梯/七点走路/点击与E/职业/7请求礼物/坏档原子/重启profile隔离已验 | [NPC账本](../features/resident/ledger.md)、施工记录第14节 |
| 14截图：产出已通过，人工审阅部分完成 | 目录project/outputs/npc-release-*.png共14；主线程实际目检seven-residents、flower-purchase、story-choice三图，七人原天台草地/无新住房/配件区别、花店5商品价格与购买、剧情2choices及天台暂驻UI已确认；其余11图待人工审阅 | 本文第8节逐图相对链接、施工记录第14节、GDD最终签署 |
| 状态：NPC/Shop implemented，非verified | 当前R01–R14实际运行实现通过；未覆盖完整产品验收为R02/R07全剧情人工体验、R08/R11/R13剩余截图审阅、R11/R14设备/发行包/持续性能。住宅仍partial/deferred，R01–R07不签完成；时间保持implemented | NPC/Shop ledger状态；GDD摘要与派生索引由主线程最终统一同步 |
| 全局门禁：由主线程收口 | 上轮20/22问题是历史检查；shop verification已由主线程改为shop-rules/npc-integration/npc-save/visual-npc-release，住所摘要稍后按partial规范改；本轮不重跑global check，不擅自声称其他漂移已解决 | 本文第7节历史与第8节最新声明；主线程最终sync/check |

本轮文档仅依据已存在证据记录已实现、已验、失败和待验；最终主线程新结果应追加，不反写原帧诊断或删除失败历史。

## 7. 文档线程定向检查与全局门禁交接

- 定向只读校验exit0：4份ledger登记头JSON原样保留且可解码；resident/time/residence/shop条款分别14/12/7/9，与账本集合一致；指定12份文档共386个相对文件链接无缺失。原帧诊断正文完整保留（Edit工具归一了末尾混合换行），只在末尾追加新结果。git diff --check在指定范围exit0。
- 按AGENTS执行 `python scripts/check_feature_contracts.py --sync` 后再执行无参检查：**sync exit1 / 20 issues；check exit1 / 22 issues**。43 features、967 source assets、1367 runtime hashes；不写全局PASS。同步因已有问题未落盘，不修改生成索引。
- 上轮待主线程收口清单（保留历史）：SEA-SHOP登记头历史verification=`shop-modules`未注册（上轮按要求保留JSON未改，本轮已由主线程解决）；SEA-DECO-ANIMAL-FISH-SCHOOL源哈希漂移；16份runtime哈希漂移（seabed_material/water/world_env、main.tscn、zone1、main.gd、play_scope、walk_area、npc_world_ports/presenter、actor_controller/character、save_game/schema、shop_panel、sunroom_region）；zones.json与npc/dialogues.json内容索引漂移。无参另报SEA-RESIDENCE主文档摘要与partial不一致、derived feature index stale。
- 上述为上一轮全局检查的历史实测问题，不推定全由本线程或NPC算法引起；未批量重签哈希，未修改独占范围外代码、registry、runner。本轮主线程已修shop verification；住所摘要由主线程稍后规范化，其余全局结果由其最终sync/check，不重复执行、不把20/22旧数当当前重跑结果。

## 8. 最终天台运行签署与14图清单

最终[shop输入报告](../../../sea-work/verification/20261107-213213-shop-input-final-638cdf/report.json)为259 checks / 0 failures，exit0/PASS。[天台交付报告](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/report.json)五项分别668/618/408/202/381 checks、均0 failures，总2277/0；全部exit0、passed=true、completion_marker=true、unexpected_errors=[]。两组head均aa12686907371f5e389e5923f259a2f886738235，未提交working_tree与工程外project快照、实际完整命令均在报告中；本线程只读证据，未重新运行。

当前天台主验已证明真实HUD航行、上下船、消防梯、七点实际行走、鼠标点击与E交互、各职业端口、七人请求/礼物、坏档原子性及重启后玩家profile不变。不是只看节点数量，也不是挪用住所版历史PASS。NPC当前R01–R14实际运行实现通过，Shop当前交易/独立面板与联合存档实现通过，登记implemented（已实现待完整产品验收），不标verified；住房仍partial/deferred，未恢复、未签完成。

真实渲染为Forward+/RTX4060Ti、日志viewport1600×1000；启动命令1280×800与实际viewport分别记录。主线程**已实际目检三图**，不是本线程新目检：

| PNG（全部属于214439快照） | 人工审阅状态 |
|---|---|
| [seven-residents](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-seven-residents.png) | 主线程已目检：7人站原天台草地，无新住房，形象区别/配件可辨 |
| [flower-purchase](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-flower-purchase.png) | 主线程已目检：花店正确5商品/价格，购买成功 |
| [story-choice](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-story-choice.png) | 主线程已目检：剧情文字可读、2choices；三图审阅已确认UI“天台暂驻”语义 |
| [overview](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-overview.png) | 已产出，待人工审阅 |
| [luo_yan](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-luo_yan.png) | 已产出，待人工审阅 |
| [mu_he](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-mu_he.png) | 已产出，待人工审阅 |
| [ji_chen](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-ji_chen.png) | 已产出，待人工审阅 |
| [nan_zhi](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-nan_zhi.png) | 已产出，待人工审阅 |
| [bai_shi](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-bai_shi.png) | 已产出，待人工审阅 |
| [hua_yi](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-hua_yi.png) | 已产出，待人工审阅 |
| [bao_he](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-bao_he.png) | 已产出，待人工审阅 |
| [general-shop](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-general-shop.png) | 已产出，待人工审阅 |
| [relationships](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-relationships.png) | 已产出，待人工审阅 |
| [ship-career](../../../sea-work/verification/20261107-214439-npc-rooftop-delivery-f2b50f/project/outputs/npc-release-ship-career.png) | 已产出，待人工审阅 |

保留59.943FPS和所有函数统计及场景差异归因，不从本轮2277断言推导持续性能、全剧情人工体验或发行包/多设备通过。211435 shop七项失败已由213213解决；211124 landing-markers额外失败仍留历史，当前天台航行/通行链已由214439通过，但不声称其原专项单独重跑或故障全修。全局门禁由主线程另签。

最终文档定向复核exit0：12份独占文档419个相对文件链接无缺失；resident/shop/time/residence条款14/9/12/7与账本对齐，四份JSON可解码，状态依次implemented/implemented/implemented/partial，Shop主线程已修verification保持原新值。14PNG存在、最终五项2277/0逐日志核对一致，原帧诊断正文保护与指定范围diff --check通过。此处记录文档线程当时未执行global check；后续主线程结果见第9节，不覆盖此前历史。

## 9. 主线程最终回归、视觉审阅与门禁

### 9.1 最新成批实测

- [221054最终回归](../../../sea-work/verification/20261107-221054-npc-final-regression-bc8a22/report.json)：11项全部PASS/exit0、unexpected_errors空，共 **5324 checks / 0 failures**。npc-shop18、performance61、clock301、rules655、shop259、world119、appearance2469、careers71、flower-crops1233、crops96、sleep42。`npc-performance` 在无Autoload隔离配置复测；原三作物完整保留，测试扩为六品种。
- [222551最新工作树复验](../../../sea-work/verification/20261107-222551-npc-final-live-worktree-6eb68a/report.json)：真实外观渲染 **241 PNG / 0 failures**；旧购买兼容入口44/0、正式集成668/0、存档618/0、seed408/0、restart202/0，六项全部PASS/exit0、unexpected_errors空。不得把之后其他会话写入的新改动自动视为此快照已验。
- 222259历史补验：外观脚本实际241图/0失败/exit0，但runner完成标记配置错误，报告正确保留FAIL；已修正marker并用222551重新跑通。旧pocket补验捕获并行Interator触发式迁移中`_holding_last`未声明的编译错误；仅补兼容声明保留并行逻辑，随后该会话继续完成acting迁移。旧拖拽测试改直接打开保留HUD适配器，生产商店命令仍打开独立ShopPanel；222551真实44/0证明兼容入口而非把生产商店改回旧UI。原失败日志不删除、不改写。

### 9.2 已追加的图审与交付文件

主线程现已查看天台overview原图、七人场景联系图（覆盖七张单人）、功能面板联系图（general-shop / relationships / ship-career / story-choice），并另查看七人正面设计图。14张正式场景图均经过原图或联系图层级审阅；没有发现严重裁切、浮空或新住所错误。七人主色/肤色/轮廓清楚，正面设计图可见卷绳、种袋、护目镜、工具带、灯章、花剪和货签/腰包；天台草较高，远景会遮住腿部与小配件，不能据联系图声称全部细节/全部动作全视角人工验收。241张动作/配件图已自动捕获，不逐张冒签人工检查。

交付位于工程外 `D:/projects/sea-work/outputs/npc-rooftop-delivery/`：`index.html` 真实截图与证据预览、`npc-rooftop-14-screenshots.zip`、`npc-character-design-10-views.zip`、`verification-summary.json`。预览不是网页玩法原型，不被Godot引用。NPC设计/账本、Shop设计/账本、时间/作物/库存/Avatar追加接口与施工记录均已更新；住所保持deferred。

### 9.3 最终全局门禁（仍未通过）

主线程执行`python scripts/check_feature_contracts.py --sync` 后再执行无参数检查，最新为 **sync exit1 / 17 issues；check exit1 / 18 issues**（43 features / 967 source assets / 1370 runtime hashes）。早先16/17问题为上一快照，新增土壤源漂移来自继续变化的工作区。具体为：

- 3个source漂移：`SEA-DECO-ANIMAL-FISH-SCHOOL`、`SEA-FARM-SOIL-CELL`、`SEA-SCENE-SUNROOM-UNDERWATER-REGION`。
- 14个runtime漂移：`godot/assets/materials/sunken_city/seabed_material.tres`、`godot/assets/materials/water.tres`、`godot/assets/materials/world_env.tres`、`godot/scenes/main.tscn`、`godot/scenes/zones/zone1_home_harbor.tscn`、`godot/src/bootstrap/main.gd`、`godot/src/navigation/walk_area.gd`、`godot/src/player/actor_controller.gd`、`godot/src/player/character.gd`、`godot/src/save/save_game.gd`、`godot/src/save/save_schema.gd`、`godot/scenes/underwater/sunroom_region.tscn`、`godot/src/diving/sunroom_region.gd`、`godot/shaders/sunroom_underwater_surface.gdshader`。
- 无参数检查另报derived feature index stale。同步为全局原子门禁，因上述混合/未知漂移未写派生索引；主文档三条状态已按对应账本定点一致化。已修Shop未知verification与dialogues主键npc_id/暂停住所zone内容索引，本轮明确NPC/Shop/草地站位登记定点重签；未批量掩盖他人或混合变更。
- 独立架构门禁扩展到NPC六规则与Shop两规则，**25项独立服务 / 0 issues**，并增加NPC→Shop及反向实现导入禁止；摆位门禁 **3结构 / 0 warning**，`git diff --check` exit0。它们不代替全局hash门禁。

当前功能实现交付完成，但全工程合同仍受工作区漂移阻塞；发行包/其他设备/长时间性能/全剧情人工体验和源级美术仍未签署。

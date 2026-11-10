# 2026-11-11 无损性能优化第一批实施与验收

所属中控：SEA-QUALITY-R01–R05；承接上一轮27项方案。用户授权“进行优化，完成后更新优化文档”。本轮选择有证据、可证明等价的第一批落地，不把全部27项候选标成完成。LOD、阴影降档、删效果、存档安全削减均未实施。

## 一、改动边界与输入快照

- 正式工程`godot/`；所有运行经`scripts/run_verification.py`在Autoload前隔离user目录；未用真实玩家存档。
- 开始HEAD为c966bd9c2a3bf0220be874236d63998b67818647，工作树原有大量未提交更改。当前前快照619文件、哈希及git状态在`D:/projects/sea-work/outputs/performance-optimization-20261111/before`和`evidence/before_manifest.json`。
- `main.tscn`、`project.godot`逐字节未改，用户摆位、分辨率/阴影/抗锯齿默认和正式shader/材质保留。SaveGame、SaveSchema、RoomController、Boat、FarmPlot、RoofReveal、ShopSightline最终与前快照一致。曾试验后撤回的门控不计完成。
- 本轮拥有14个源文件变更：ambient/plant、aqua/fishery_visual、bootstrap/main、crops/crop_view、gathering/gather_spot、interaction/interactor、pickups/sea_props、rendering/shore_distance、rendering/water_surface、ui/hud、ui/notebook、weather/weather_presenter、world/bake_store、world/zone_batch。
- 工作期间`workshop/recipe.gd`、`workshop/generator.gd`有并发更改，不属本轮，不覆盖、不归功。最后功能batch的上述14个源码与当前版本哈希一致。

## 二、已实施

1. OPT-01部分：Main室内不再提交室外zone材质、水面网格/uniform/wake；CPU公开波时钟仍每帧同步。隐藏SeaProps不提交鱼体/水纹重表现，但公开root位置/yaw/roll、legacy漂移、冷却和序列化elapsed继续；plant成长/phase继续，隐藏只停transform；GatherSpot仅available且隐藏时跳浮动，冷却继续；FisheryVisual保持_time仅跳隐藏变换。
2. OPT-03/04：同一Main表现更新只仲裁一次近距操作，输入动作仍独立重新查；Interactor同轮扫描复用reach和位置，不跨帧缓存动态可达性。
3. OPT-05：WaterSurface静态waves/scale/default参数仅dirty时提交，保留节点调参、原位数组变更、shader替换/方案切换失效；Main删除重复u_time/u_boat写入。
4. OPT-06：BakeStore共享材质按同t及资源集合数量去重，zone仍有各自本地材质职责。
5. OPT-07：晴天/潜水停WeatherPresenter process及重绘；Main通过advance_time(delta)保持模拟时间，不读系统墙钟，雨起停及时清空。日照仍连续；HUD日期天气文本相同不重写。
6. OPT-09部分：HUD业务信号同帧合并deferred刷新，公开_refresh/refresh_view仍同步；Notebook用完整显示数据签名跳过重复重建，不改变分类/页码/选择/事实与时钟更新。
7. 补充发现：CropView同阶段原先每帧重新遍历网格并重写tint。现在同阶段免重复visible/tint遍历，set_stage仍按旧契约每次发stage_changed，切品种/缺水/空状态不变。未改Farm生长真值。
8. OPT-15：1536²最终RGF岸线缓存，版本/完整精度线段+尺度+bounds+水位+region+outline+resolution内容SHA256；单内存条目与固定磁盘slot20MiB上限。长度/格式/key/payload hash校验，截断/尾部/损坏拒绝重建，写失败降级，不目录扫描、不递归删除。缓存仅派生数据不进存档，cache_enabled可关闭。

新增专项`test_shore_distance_cache.gd`、`test_ui_refresh_performance.gd`、`test_interactor_query_reuse.gd`、`test_performance_equivalence.gd`；新增`tools/profile_optimization_result.gd`及runner注册。runner的`--source-overlay`仅把工程外前快照src覆盖到隔离副本，用同一探针配对，不碰正式源码。

## 三、实测收益与画面

设备i7-14700KF/RTX4060Ti，Godot4.7.2/Vulkan Forward+，1600×1000。配对探针VSync关，固定模拟步长60但真实帧间隔来自Time.get_ticks_usec；不是发行/设备全签。每次surface/room各3组×300帧，顺序相同；系统后台未独占，波动单列。

| 配对 | 室内三组p50的中位ms | 改后ms | 减少 |
|---|---:|---:|---:|
| 第一轮 | 6.222 | 4.782 | 23.14% |
| 独立复测 | 5.236 | 4.458 | 14.86% |
| 最终版本 | 对照参考以上区间 | 4.664 | 不另拼接百分比 |

室内259次绘制/65691图元保持，GPU约1.63–1.65ms。收益是CPU/提交减少，不是降画质。海面第一轮中位11.014→10.104ms，但独立复测9.568→9.675ms，最终9.764ms，因此**海面整体FPS提升未签稳定收益**，不承诺所有场景加帧。第一次进入后的机位不同（出屋恢复跟随）只做同序号前后比，不能混作一个固定机位样本。

1536岸线同一冻结世界输入：冷1384.704→热70.763ms；复测1381.019→69.132ms；最终1397.965→71.886ms（约19.4倍、减少94.86%）。18874368字节完全相同；热EDT为0。几何切片仍需做，首次缺失仍有冷开销；存18MiB进程缓存和最多slot/tmp磁盘开销是明确代价。动态布局导致输入变时必须冷算，不宣称整段Main启动缩短19倍。

最终版本与优化前同探针同相位PNG：海面、室内均1600×1000，RGB RMS=[0,0,0]、差异像素0。静态图只证明这些机位，不替代全部运动/角度。真实房间专项inside/porch/night与海岛笔记1600图已目检，35张PNG有产出，不称35全人工看过。冻结室内probe停止RoomCutaway会保留屋顶，前后相同，不拿它代替正常室内剖切；正常专项inside已确认床/窗/地毯可见。

## 四、最终运行证据

根目录`D:/projects/sea-work/verification`，每项report包含原始退出码、脚本错误、命令、user槽与工作树。

- `20261111-015839-perf-opt-unit-final-177018`：UI19/0、Interactor15/0、岸线headless119/0、crops96/0、ocean均PASS/exit0。
- `20261111-020354-perf-opt-regression-input-a25b2b`：equivalence19/0、UI19/0、click、keyboard-panels、pick-mesh、facing-interaction、boat-water-contact均PASS/exit0；water-params失败见下。
- `20261111-021225-perf-opt-functional-final-1fb360`：equivalence19/0、room112/0、sleep42/0、npc-clock303/0、npc-performance61/0、building-perf239/0、坏档seed/protection、save-seed/framework-integration52/0、ocean-pickups48/0、fishery-production33/0，12入口全PASS/exit0，unexpected_errors为空。
- `20261111-021225-perf-opt-visual-regression-5b9763`：visual-room、visual-weather、visual-shore-distance-cache PASS/exit0；真实MultiMesh原生读回平移0.5m、缓存118/0。visual-corner-notebook失败见下。
- 配对前`20261111-020557-perf-opt-paired-before-da3791`、后`020643-perf-opt-paired-after-d30340`、独立前`020859-perf-opt-paired-before-repeat2-fb650c`、独立后`021033-perf-opt-paired-after-repeat-41c487`均PASS/exit0。
- 最终`20261111-022159-perf-opt-final-measured-96f20e`：visual-optimization-result和visual-frame-functions均PASS/exit0。

## 五、失败历史、反向对照与未执行

- 首缓存MultiMesh失效2失败：headless Dummy后端set/get transform空实现/恒单位；单独CPU注入夹具与原生无缓存对照明确限制，真实renderer118项通过原生路径。未减断言。
- 首UI测试：Variant类型推断、未注入模型/font夹具、雨切换错误预期；修夹具后19项通过。首equivalence stub缺rowing_state、空材质集合和严格浮点角度比较，修夹具后19项通过。
- room旧断言“室内zoom_max小于室外”因用户此前改室外35.14m而失效；室内scale1.5×24=36m原样保留。改测试为room.orbit_zoom_range一致，不改任一相机参数。
- `water-params`两方案各5项缺参（boat_hull_count、boat_blade_count、boat_contact_strength、boat_oar_strength、runtime_contact_count）。源快照对照`20261111-021331-perf-opt-existing-water-param-baseline-f38384`同样失败/exit1。本轮不改shader/P面板范围，不删断言转绿。
- `visual-corner-notebook`92/5：LEFT翻页3、旧shop/storage launcher2。优化前`20261111-021846-perf-opt-notebook-before-2c4eb6`与优化后`021931-perf-opt-notebook-after-0e7711`同5标签/exit1，无新增错误；keyboard-panels与签名单测通过。失败仍pending，不冒充UI全验收。
- 较长执行批次两次约120秒中断：contracts在npc-clock起始、before-repeat在load起始。无完整report不记PASS；最终功能batch和独立前复测补齐。中断不归因游戏崩溃。
- 未执行：真实玩家档、release/Web新包、低端/集显、功耗、硬件VRAM、长时自动保存、10次潜水资源平台、全部运动镜头。既有14张以上渲染通过不签全设备。

## 六、工程门禁与登记边界

架构25独立服务/0问题、手摆6处/0警告通过。全局资产条款与源/运行hash漂移仍存在；不批量接受。仅两处原登记与优化前LF哈希一致、且本轮已审阅/验证的条目定向登记：UI-NOTEBOOK-001 source及current_source_index；water_surface runtime行。保留旧hash、证据和授权pending，不接纳改前已漂移的Main/HUD/Fishery等。

最终同步exit1/76项，无参数exit1/78项；主要仍为资产条款/源与运行hash漂移，以及SEA-WORKSHOP状态和派生索引变化。架构exit0/25服务/0问题，摆放exit0/6处/0警告。本轮新增文档broken link在本文创建后复跑已全部消除，不计作既有债务。哈希定点登记后不再报UI-NOTEBOOK或water_surface本轮漂移；改前已漂移的Main/HUD/Fishery未批量接受，故仍报红。全局不能签通过。

## 七、剩余方案与回退

OPT-02完整指针revision、OPT-08材质/日照更多dirty、OPT-10容量预算/建造预览、OPT-11人口触发合并、OPT-12 NPC revision，及OPT-13/14/16–27中的合批/阴影贡献/碰撞烘焙/流式/材质owner/存档异步/工坊lazy/LOD/遮挡/shader/粒子/GPU风/纹理/航行索引均未全部实施，按原方案继续。OPT-01/05/06/07/09仅上述确切范围完成，不统称27项完成。

回退参考外部before快照和owned_source_changes清单；逐文件对照后仅撤本轮diff，不覆盖原dirty用户更改或并发工坊。关闭岸线cache_enabled可回到原计算且图像相同；派生缓存不影响存档，可坏后自动重建。不要git reset/checkout整文件，也不要删除个人user数据。

## 八、文档更新

原V1.0 Word保留完整审计正文，新增第十二章实施结果，并在封面和开头增加V1.1状态说明；同时另存`sea_性能审计与无损优化方案_V1.1_已实施.docx`。原文“不实施”句明确标为历史审计时状态，避免把历史与本轮完成混读。更新版已保存并结构核验：12个Heading1、51个Heading2、17张表、5张内嵌图，原4图保留，新对照图添加；Word updateFields=true，目录可刷新收录新章。更新版、对照图和证据包位于工程外`D:/projects/sea-work/outputs/performance-optimization-20261111`。转换服务提示未接会话备份，本轮已另存原V1.0备份，未覆盖其历史内容。

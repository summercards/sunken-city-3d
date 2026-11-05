# 2026-11-05 阳光房柔软草皮 v002

归属 SEA-AMBIENT-R17、SEA-ASSET-R51。[当前制作与复用手册](../features/ambient/vegetation_soft_cards.md) · [独立植被账本](../../assets/registry/ledgers/vegetation.json)。

用户否定了 v001 的实体草堆、几何草叶和稀疏覆盖，要求用带草叶贴图的柔和面片；并明确先做阳光房草皮、可以少量苔藓，保留阳光房原有花草对象。此修订覆盖前一轮两处设施的实施顺序。

## 实际改动

- 阳光房花草构建器恢复到原提交的同字节版本，56株原有植物的AssetID、位置和表现保持；未修改原模型、花朵或草对象。顶层牧场场景亦恢复原提交内容。
- Image-2使用用户视频帧作参考，通过sofunny-image的OpenAI Images编辑接口生成2048方形RGBA图集；原始生成图、精确裁切/留边的处理版和生成描述均保留。
- 新增两种可复用载体：18三角面的三向分段草叶面片簇、8三角面的苔藓贴片。各自具有独立Blender源、独立优化源、GLB和稳定PackedScene；单根叶片轮廓完全由RGBA贴图承担。
- 阳光房铺设1301草簇、122苔藓贴片。主体是屋顶空调外侧的连续草皮、二层女儿墙顶的窄带；大部分苔藓位于草根下，另四处小点缀。草高约19–29厘米，避免空调检修区、太阳能板与露台活动空间。
- 共享GPU风动固定根部，草叶末端和空间阵风柔动；苔藓主体保持固定。分块MultiMesh、无逐叶CPU动画、无细草阴影。近景保留绘制层次，远景收敛反差，避免高密度细叶形成硬闪点。
- 生产图集采用真实alpha，线性mipmap/各向异性采样及alpha裁切。未采用普通整面半透明叠加；新增贴图UV0例外仅限本族，原建筑与花草的PaletteUV未改。

## 审阅和管理

原生渲染审阅包含整栋、屋顶近景、低掠视、真实微距、女儿墙、远景和有/无草皮对照；风动留存90帧30FPS序列。独立小样仅用于材质检查，不代替正式主场景。图集灰底预览验证了透明草叶间隙和碎叶边缘。

独立资产域vegetation由总索引路由，登记三份主记录：SEA-VEG-GRASS-SOFT、SEA-VEG-MOSS-SOFT、SEA-TEX-VEGETATION-SOFT-ATLAS。每行维护源/优化源/运行哈希、消费者与分维度证据。生成结果的权利条款未专项审查，账本保留pending；用户审美验收同样不伪称通过。

v001源保留历史并标记REJECTED，导出的候选运行文件移至工程外`sea-work/vegetation_soft_20261105/rejected_v001_runtime/`。旧工具拒绝重新覆盖当前系统。未批量更新任何其他工作的未知哈希。

## 验证记录

统一runner在Autoload之前隔离存档。最终报告、性能数字、退出码及文档门禁见下方验收附录；检查成功仅代表其覆盖的行为，不表示整个植被计划或所有硬件锁60FPS。

修复/排除的本轮问题：

- 植物替换范围过宽：已完整撤回原有花草替换和牧场试铺。
- v001视觉方向错误：退役实体叶片候选，改RGBA草叶面片。
- 默认相机下细草过亮/细碎：降低远景反差，连续覆盖，使用真实微距检查实际叶形。
- 微距检查曾被正式相机9米最小距离夹取：仅截图工具允许局部微距，正式游戏相机参数不改。
- 首轮测试的局部变量类型推断错误：修正为明确Array后，2658项契约断言通过。
- 并行房间模块编辑期间，几次全场景快照出现尚未完成的接口/类型错误：对应失败日志保留，未按“有图”或“进程退出0”冒充整项通过，最终以当前工作区重新运行的结果为准。

当前仍未制作：草堆与花朵的贴图重制、顶层牧场新草皮、墙面动态苔绒、水生植物。后续按用户确认的范围沿用同一共享系统推进。


## 当前验收附录（2026-11-05 15:50 快照）

统一报告：`D:/projects/sea-work/verification/20261105-155056-soft-turf-verified-1f59a8/report.json`。六项均退出0，无预期故障或未识别错误：vegetation-contract（2658项、0失败）、visual-vegetation、visual-vegetation-performance、rooftop-ranch（655项、0失败）、water-layer、minimum-loop（141项、0失败）。原始日志与工作区快照保留于报告目录。独立小样另有`20261105-154324-soft-card-study-934d7b`，通过但不代替正式实测。

原生预览与可分享文件位于`D:/projects/sea-work/vegetation_soft_20261105/`：game_macro.png、game_close.png、game_overview.png、game_before_after.jpg、grass_wind.mp4（90帧、30FPS、3秒），另有完整RGBA图集审阅和来源/登记报告。动态是Godot真实风动采样，非AI视频。

性能设备：Intel i7-14700KF / RTX4060Ti，Forward+，1280×800，每模式180帧。根Viewport GPU计时包含其渲染通道，脚本CPU另计。

| 视角 | 原场景GPU p95 | 新风动GPU p95 | 差值 | 植被脚本CPU p95 | 全分块LOD检查CPU p95 |
|---|---:|---:|---:|---:|---:|
| 阳光房默认构图 | 5.193 ms | 5.195 ms | +0.002 ms | 0.028 ms | 0.041 ms |
| 屋顶近景 | 4.132 ms | 4.405 ms | +0.273 ms | 0.023 ms | 0.035 ms |

阳光房1423实例分16批绘制，单项增量满足GPU≤2ms/CPU≤0.3ms初始预算。整帧p95为22.145ms/17.020ms，当前后台还运行其他Godot进程；因此不宣称整项目全视角稳定60FPS。报告的high_density与当前Standard同为100%作者密度，是满密度复测，不视为更大面积压力测试。

功能契约全库检查按要求执行`--sync`及无参数：分别退出1，7项/8项问题。与本轮植被无关的未解决项：SEA-SLEEP声明的sleep_checkpoint.gd缺失、SEA-SCENE-ORF-ASSEMBLY源哈希漂移，以及ocean_sky.tres、neon海报.import、zone1_home_harbor.tscn、main.gd、hud.gd运行哈希漂移；无参数另报派生功能索引过期。全局sync因这些现有问题拒绝落盘。未批量刷新它们，植被三份新资产的源/优化源/GLB/贴图/包装哈希单独核验通过。最新门禁原始输出见同证据目录feature_contracts_sync.log及feature_contracts.log。

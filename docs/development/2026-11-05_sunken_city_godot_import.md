# 2026-11-05 沉没旧城 v003 正式 Godot 导入

[主文档](../../GDD_V1.0.md#sea-asset) · [资产设计](../features/asset/spec.md) · [资产账本](../features/asset/ledger.md) · [世界设计 SEA-WORLD-R20](../features/world/spec.md) · [v003源级历史](2026-11-05_sunken_city_v003.md)

## 用户范围与正式接入

用户16:41要求将已完成的Blender资产导入Godot。本轮按02b规范执行，不重制建筑、不改变用户已确认的深度与布局。它是**海上主场景水面下的观赏旧城**，不是独立潜水玩法地图。

- [正式总装](../../godot/scenes/world/sunken_city.tscn)，挂载 `main.tscn → World/SunkenCity`。
- [50个稳定组件PackedScene目录](../../godot/scenes/components/scenery/sunken_city)，每件独立可加载。
- [稳定GLB与运行清单](../../godot/assets/models/scenery/sunken_city/runtime_manifest.json)。50个GLB各自位于 `<key>/<key>.glb`。
- [三个持久色板材质目录](../../godot/assets/materials/sunken_city)，StandardMaterial3D分别承接Matte/Metal/Gloss；无自发光、最近邻、禁止repeat、双面、公共暖木512×512色板。
- 50当前组件、388实例、40完整建筑实例、100地坪域、3电车、4曲线跨段。正式实例完整XYZ Euler及缩放由TSCN持有，后续Godot手改不自动被Blender JSON覆盖。
- 主场景只新增一条ext_resource与一个World/SunkenCity节点；移除这两个新增块后必须逐字节等于本次接入前的实时备份。现有卧室/草皮/岛屿/牧场/浮店并行改动保持，不运行旧场景构建器。
- 总装声明submerged/entity、组件submerged/part，building_class=underwater；全子树无脚本、碰撞、Area、BlockerSet、WalkArea、导航、泊位、交互、资源、存档和岸线种子。

## 原源保护与02b独立优化

原始主源：`art_source/scenes/sunken_city/v003/sunken_city_v003.blend`，SHA-256 `e4a2ed7ec61456f0754c754158ab34dbb13e923e94b7601c18f1d2c19cb696f3`。

50组件源、主源、公共色板合计52份受保护输入，执行前后哈希相同；v001/v002不动。

- 每组件打开已验收独立包，网格单用户化，只在派生工作文件执行清理。
- 执行1e-6米重合顶点焊接、重复面、零面积面、孤立边/点清理；真正共面且材质/色格/法线一致的平面内边才作为溶解候选。没有按朝下法线删除底面，没有全库Decimate。
- 保留3段倒角、窗洞、断口、文字、细杆、内部未知面和背面；没有可安全简化的件记录实际零变化，不把三角化算作优化。
- 持久优化文件位于 [export/v003](../../art_source/scenes/sunken_city/v003/export/v003)，50份 `<key>_optimized.blend`。每份先保存，再重开，核对实际面数、包络、原点与逐面PaletteUV，最后从重开的优化文件导出GLB。
- [导出清单](../../art_source/scenes/sunken_city/v003/export/v003/export_manifest.json)逐件登记源/优化/GLB路径与哈希、执行操作、前后面数、减面率、包络、色格面积漂移及导入节点语义。

**实际母版三角面：2,565,218 → 2,565,204，仅减少14面，减面率约0.000546%。** 完整388实例展开为5,367,885面（源5,367,916）。50GLB合计161,678,180字节。这是完整保真接入，不是大幅性能优化；自动LOD未生成，运行帧率/显存性能完整评估仍pending。

## 保真证据

工程外工作目录：`D:/projects/sea-work/sunken_city/v003/import/`。

`fidelity_{game_angle,front,back,side}_{source,optimized}.png` 同镜头/光照/尺度/引擎渲染8张前后图，已逐视角目视检查剪影、开口、破损、坡地和色块。抽样通道MAE约0.000032–0.000080，98.3%–99.3%采样通道完全一致；未把像素数值当作唯一美术结论。后续仅优化文件节点名改ASCII，无几何/材质变化。`fidelity_verification.json`保存源保护和父级目视结论passed。

## 导入中实际发现并修正的问题

1. 初次使用4.6.3导入当前4.7工程，导入编辑器超时退出124，且中文GLB叶节点名出现Unicode/vanished警告。切换本机当前工程使用的4.7.2，并仅将优化文件及GLB节点命名稳定为 `Root_<key>/Mesh_<key>`，不改中文显示根或原始源。
2. Godot在GLB文件外增加默认场景根，实际mesh路径为`Visual/Root_<key>/Mesh_<key>`，不是`Visual/Mesh_<key>`。首次结构专项抓到材质覆盖失效，修正每件TSCN真实mesh路径并重新运行，不能以“文件存在”当作材质成功。
3. Blender→Godot基变换在运行清单按列向量记录，而TSCN的Variant文本基按行序列化；初版旋转转置，西侧楼/设施朝向翻转。修正文本行列顺序，以388实例各12项矩阵断言守住，不依赖位置或AABB侥幸通过。
4. 初版metadata缺少water_layer_role；水层回归抓到389项缺声明。补总装entity和组件part，再重跑完整职责与结构专项。没有忽略旧回归报错。
5. GLB均无内嵌images/textures；`.glb.import`显式Discard图片，公共色板无损/无MipMap。关闭自动LOD/shadow mesh烘焙（真实投影仍开启）、lightmap烘焙和动画导入，保证三角面口径清楚。相关`.import`不被gitignore吞掉。
6. 运行复验期间编辑器将 `World/SunkenCity` 根Y整体上移38.04888米，26栋楼越出海面。检测后未擅自覆盖，向用户确认；用户明确选择“恢复原水下深度（推荐）”。先备份当时实时main，只把该根Y改为0；`depth_restore_verification.json`断言before/after仅该一行变化。其他编辑器新增unique_id、wind脚本UID、ArrayMesh自动资源ID和空白保存全部保留，登记时做规范化语义差异核对。最终四项验收均在恢复后的真实main完成。

## 运行检查与真实可见性

全部测试经 `scripts/run_verification.py`，先隔离用户数据再构造Autoload，不访问玩家真实存档。

最终轮 `20261105-180807-sunken-city-restored-depth-final-28d3d5`：正式import退出0；sunken-city **33338检查0失败**、visual-sunken-city **124检查0失败**、water-layer **1239检查0失败**、minimum-loop **141检查0失败**，全部退出0。此前矩阵修正轮/缺role失败轮/根节点上移期间的失败轮均保留，不拿前轮通过代替最终状态。

实际海水截图结论：

- 靠近海面的最高楼顶约2.76米深，可见青蓝色屋面、水箱与轮廓；10米深屋顶更淡。
- 街面约62米深，高架/断桥也在约50–60米深，**当前全局海水吸收下几乎不可辨**。节点真实可见、投影入框、PNG不为空不代表深水细节美术通过。
- `bridge-through-water-diagnostic-no-water.png`仅为同机位隐藏水面的诊断，能确认色板、曲线、电车和断口正常；它不是正式水下效果。拍完恢复水面/时钟/天气/相机，未改水深吸收参数。
- 夜景保留真实冷色暗水，废弃旧城没有自发光；近水屋顶非常暗，深层不可辨。这是现深度/海水设置的视觉限制，不通过抬升整个街区或加发光偷偷规避。

因此“组件导入、布局映射、无功能职责”与“深层街景隔水可读性”分开：前者验收通过后登记，后者仍是明确待用户确认的视觉调优项，需单独决定调整海水吸收/深度或保留隐约远景，当前不擅改。

## 资产登记与回滚

50组件+总成共51条当前AssetID写稳定GLB/Prefab/优化源/哈希/验证证据；两个旧v002退役定义保留，原source/source_sha256/previous_sources和参考授权pending不改。运行清单只接受本任务157份新增资源及main本次增量的1条更新，不批量刷新其他资产漂移。登记脚本读取最终测试原始日志/退出码和隔离工程拷贝哈希，默认dry-run，`--apply`才写。

主场景接入前实时备份在工程外 `import/main_before_sunken_city.tscn`。回滚应移除本次两块引用并由版本控制恢复本任务运行文件；不要删除源/优化文件，也不要用该备份覆盖之后别人的main修改。没有自动提交或重写历史提交。

未执行：运行LOD/帧率目标、远海全设备覆盖、商业参考素材授权、用户美术终审。未新增玩法、碰撞或存档字段。

## 最终登记与全工程边界

恢复原深度后的最终运行报告为 `D:/projects/sea-work/verification/20261105-180807-sunken-city-restored-depth-final-28d3d5/report.json`；正式导入、33338结构、124渲染、1239水层、141最小循环均退出0。实际运行登记已再次执行退出0，51条当前v003资产 `runtime_integrated=true`、2条退役v002仍保留，原主源/组件blend未写入；最新`runtime_registration.json`引用本轮最终报告，稳定预制体和总装哈希已同步。

登记前发现场景分账本被另一轮写入恢复为v002的51条，严格门禁拒绝继续；先用原v003源报告和哈希重做限定SCITY的源登记，恢复53条(51当前+2历史)后才登记运行。没有全量回滚分账本、覆盖其他新增资产或将新源哈希填成旧源。

最终静态检查真实执行：40功能、867源资产、1023运行资源哈希。分类视图同步退出0、修改既有资产行0；`--sync`退出1、3项阻断：`SEA-SCENE-ORF-ASSEMBLY`旧源哈希、`godot/assets/materials/ocean_sky.tres`、`godot/assets/textures/facilities/neon_garden_quarter/poster_atlas.png.import`。无参数复核退出1，除上述3项外另含派生feature index过期，共4项。没有SCITY源/运行新错误，未通过批量刷任务外哈希隐藏失败。**本套件运行通过、全工程静态门禁未通过、深层街景隔水可读性待调三件事分别记录。**

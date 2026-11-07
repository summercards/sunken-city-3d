# 2026-11-07 参考图海上礼品商亭

[主文档](../../GDD_V1.0.md) · [资产](../features/asset/spec.md) · [世界](../features/world/spec.md) · [移动](../features/move/spec.md)

## 授权范围与输入

用户要求直接通过活跃 Blender MCP 制作附件房屋及全部配件，对照参考修正；替代原海上商店，旧模型降为其它设施。新设施初次参考位在阳光房当前主体中心东南方向 200 米；有上岸口、真实可走甲板，平台起伏时角色随动，不制作水下建筑基座。形状、比例、颜色、风格和饱满倒角以附件为准，不走写实路线。参考图片保存在新套件内，商业参考权属保持 pending。

采用项目 `sea-scene-component-authoring` 的水上差异、`blender-mcp-bridge` 及 `02b-godot-model-asset-import-standard`。47 项组件先冻结计划，结构/固定陈设/植物分集合，每项独立母版 Collection、独立包、独立优化源与稳定 GLB/PackedScene。共享既有 bright cozy 公共色板，以保持图中奶白、黄、蓝、橙色；本批登记该色板选择例外，不改变暖木色板或任何旧源。

## 制作契约

18×18 米圆角方形甲板，圆角半径约 2 米；10.8×10.8 米圆角商亭，墙净高 4.9 米、柱 0.5 米、承重铺板厚 0.2 米。厚船舷/灰护舷属于独立外壳，不把铺板加厚。保留参考的蓝白圆垂雨棚、POSTCARDS/GIFTS/COLD DRINKS 立体字、奶黄灯箱、屋顶圆盘/弯管/射灯/信号灯、救生圈、木凳、盆栽、明信片架、邮筒、冰柜、垃圾桶、轮胎、梯子及船底浅浮筒/推进器。浅橙浮筒是参考里的漂浮装备，不是海下建筑基座。

旧主场景商店变换由用户手动拥有，原缩放/下沉位置完整保留为旧驿站景观；新商店使用原 `sea_supply` 身份和稳定设施场景入口。新摆放仅作为带入参考位，后续只认正式 TSCN，绝对坐标不作为永久断言。

## 当前基线

开工前工作区存在 terrain DLL 删除及一批未跟踪 Godot UID，不纳入本轮修改。UTF-8 模式基线契约有 4 项：鱼群源哈希、water.tres 运行哈希、bootstrap/main.gd 运行哈希、派生功能索引过期。摆位检查 3 项通过、0 warning；浮店非均匀缩放已被用户确认。

## 制作与接入记录

制作、源重开、优化、导出、Godot 运行和真实渲染结果在本节后续追加。未完成阶段保持 pending。

## Blender 源级与 02b 最终结果

47 个母版、379 个实例，结构、固定陈设、植物分别管理。47 个独立包均为打开即有场景几何的实际 Blender 文件；不能把含 Collection 的库文件当成可直接打开的组件包。最终母版与全部独立包保存重开后，446047 项检查、146118 次面 UV 检查通过；每面 PaletteUV 有面积、单格内留 8px 安全区，根/网格恒等、Collection offset 为零、底心原点、唯一外链公共色板及四材质角色通过。七方向、近景和建筑单独渲染位于 `D:/projects/sea-work/gift_kiosk/v001/`。

承重甲板与奶油/灰护舷分件；护舷、十字管梁、四只浅橙浮筒、中央推进器/灯芯、检修板的六种水下视觉件只渲染。甲板的水面阻挡只扫描 `Visual/Structure/deck_001`，水下视觉子树不提供空间和岸线。未制作水下建筑基座。

原始母版、47 包及公共色板共 49 份保护文件哈希不变。优化另存 `art_source/scenes/gift_kiosk/v001/export/v001/gift_kiosk_optimized_v001.blend`，重开后导出。逐件实际执行退化面/重复面/孤立点及重合点清理；保留三段圆角、字形、底面、背面和全部参考焦点。母版三角 141000 → 140981（清理19面，不把三角化冒充减面）；全实例运行几何 518314 三角。GLB 按材质角色归并输出面，不改变源组件边界；47 件共 10264132 字节，无 images/textures 内嵌。

Blender 4.5 原生 glTF 操作器在 Collection Instance 依赖图求值中发生 `BKE_base_eval_flags` 崩溃，制作源不受影响。最终采用活跃 GUI 内 MCP 执行的数据导出器，直接读取已保存并重开的优化网格、split normals、PaletteUV 和材质角色，不调用该依赖图操作器。独立审计逐三角比较实际 GLB 与 bpy 数据，140981 面的位置、角法线、UV 和材质均一致。四个固定镜头原始/优化渲染 RGB RMS 最大 0.04474/255，>24 色阶变化像素比例为零。所有证据均为真实 Blender 渲染，不是生成图片。

## Godot 接入、摆放与修正

稳定入口仍为 `godot/scenes/facilities/floating_shop.tscn` / `sea_supply`，总装引用47个稳定组件 PackedScene。正式导入在统一 runner 隔离工程执行，import exit0。公共色板无损、无 mipmap、最近邻；材质在正式导入期绑定到实际网格，编辑器可见，不靠运行时补色。保持四种语义角色；招牌共用的 `metal_lettering.tres` 沿用 Metal 角色，接收正常昼夜灯光、保留投影，仅不接收导致薄字正面颗粒的自阴影；未改全局光照、水或其它资产材质。

初次参考位按本轮运行探针测得阳光房主体 AABB 合并中心 XZ `(6.15, 2.47)` 加东南200米计算，为 `(147.571356, 1.12, 143.891356)`。这只是带入参考位；后续始终以 `main.tscn` 用户摆放为准，偏差记在[摆放台账](../features/world/placed_positions.md)。主场景仅5增1删：一条旧驿站资源、旧节点重命名/替换包装、新商店节点；旧模型原始12项变换保留，其他结构物位置不动。

旧模型作为不登岸的「旧海上驿站」地标，走既有 SEA-WORLD-R13 的非区块海上结构契约：保留几何派生水面避让，不拥有 ZoneID、上岸点、角色碰撞或补给交互。它仍保留原水上建筑源类别，未因用户把模型下沉而改成水下类。`activity_role=navigation_only` 是使用职责的显式声明，不是第三种建筑分类。水层专项已补充此既有契约：无活动面的结构必须显式声明 navigation_only，并验证无区块身份、无角色碰撞、无交互，仍要求有效船只阻挡出口；未声明的缺活动面依旧失败。

实机首轮发现 TSCN 浮点矩阵按行序列化、Basis 构造按列接收，导致侧面招牌朝内。已经改正，379 个实例均用 Godot 自己的 Basis 独立对照 Blender 原始旋转/缩放/位置，未以截图非空代替方向验收。后续近景抓到薄字自阴影颗粒，受控 A/B 确认后仅修招牌材质接收阴影，不关建筑投影。

## 运行专项与边界

正式角色经既有靠泊→上岸→走到补给点→打开补给页→回船链路；导航从家园到参考泊位有4点合法折线。环廊、入口及室内中央可走，海域、店墙和真实陈设脚下拒绝；路径经 GroundSpace 和角色胶囊执行。设施单一所有者驱动 Y 起伏，视觉/WalkArea/碰撞/导航/交互同步，泊船点固定实际水线；不新增玩法存档字段。

30/60/120 FPS、14秒受控支撑测试：起伏峰峰值 0.269085米，站立相对支撑误差0；导航/碰撞重烘焙0次。七段真实胶囊行走最大脚底误差0.002143米，键盘行走/松手、交互、回船后脱离承载通过。读档到另一浮动相位会重新贴合当前支撑，避免保留旧相位的悬空高度。非法海面角色存档继续拒绝。

过程结果如实保留：首轮6369/0，矩阵和读档补验后7128/0；对应日夜/上岸/补给/20帧承载真实渲染53/0。整体回归中 ground-space、character-motor、character-space-save、keyboard-control、board-click、minimum-loop 均通过；首轮 water-layer 1591/1，唯一失败为旧模型降级后不再提供 WalkArea，已按上述既有 R13 职责补齐明确声明与专项断言，最终复跑结果另附。没有把该红项当成已通过。

当前过程报告：`D:/projects/sea-work/verification/20261107-135237-gift-kiosk-final-art-and-motion-a282b3/report.json` 与 `20261107-135552-gift-kiosk-regression-241d0f/report.json`。源/导出/保真/摆放/登记证据在 `D:/projects/sea-work/gift_kiosk/v001/`。最终发布复跑在本节后追加；不同阶段退出码、预期拒绝与未执行项分别记录。

未执行：参考图商业权属专项核验、用户最终美术偏好验收、低端GPU/任意规模LOD性能、手柄/触屏。已知工程基线：鱼群源、water.tres、bootstrap/main.gd 的三处既有哈希差异未刷新；期间另有任务外 npc_catalog 引用缺失曾被全局门禁发现，按最终检查结果记录，不顺手修改任务外代码或哈希。

## 最终签署（当前文件）

最终统一 runner：`D:/projects/sea-work/verification/20261107-140056-gift-kiosk-release-final-dc0ce0/report.json`。

| 阶段 | 当前结果 | 退出码 / 错误 |
|---|---|---|
| 正式资产导入 | PASS，包含字面阴影材质修正 | exit0；无意外ERROR。保留旧素材UID路径兜底及编辑器插件退出泄漏WARNING，不宣称0 warning |
| gift-kiosk | 7129 checks / 0 failures；47组件/379实例、三种帧率、真实胶囊行走、上下船/补给、跨相位读档 | exit0，unexpected_errors=[] |
| visual-gift-kiosk | 53 checks / 0 failures；日/夜/正背侧顶/真实角色/补给页/20帧受控漂浮/旧驿站 | exit0，unexpected_errors=[]；已逐图目视 |
| water-layer | 1594 checks / 0 failures；包含旧驿站navigation_only严格声明及无角色功能检查 | exit0，unexpected_errors=[] |
| 相关集成 | ground-space、character-motor、character-space-save、keyboard-control、board-click、minimum-loop全部PASS | 均exit0；minimum-loop147/0。过程水层红项已由上行最终复跑关闭 |

[机器交付签署](2026-11-07_gift_kiosk_verification.json)绑定当前制作源、优化/导出、49份保护文件、正式资源哈希、实际摆位、runner报告及未执行项。功能代码、设施和主场景与最终隔离快照逐文件SHA一致。48条新资产（47组件+总成）与171条本轮审阅运行文件已定向登记，未刷新三处既有漂移；新增脚本UID从正式导入结果原样保留。

最终预览：`D:/projects/sea-work/gift_kiosk/v001/final/`，包含 Blender 主视图、Godot 日夜和角色近景、实际补给页以及 `floating-support.gif`（20个真实渲染帧，受控支撑验证，非帧率性能录像）。旧模型的源/GLB及用户变换保持；新店无水下建筑基座。后续美术修改从 `gift_kiosk/v001/gift_kiosk.blend` 派生新版本，正式Godot入口和用户摆位仍保持稳定。


## 最后静态检查记录

摆放、两类职责策略dry-run和git diff --check通过（exit0；git仅有既有CRLF转换提示）。按要求先sync再无参数复核；全局门禁尚未通过，原始输出保存在机器签署和 `D:/projects/sea-work/gift_kiosk/v001/final_static_checks.json`。当前剩余为三处开工前即存在的鱼群源/water.tres/bootstrap main哈希差异，以及制作期间出现的 `docs/features/shop/spec.md` 主文档未登记；无参数检查另报派生索引过期。上述项没有通过刷新哈希或补写任务外功能来隐藏。本批R55/R24/R25/R18、48条新资产、源/优化/运行身份和两类视图均未报错。

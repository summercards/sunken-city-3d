# 海上悬浮商铺v003 · 4:3矩形建筑及游戏替换

承接SEA-ASSET-R34/R35及SEA-WORLD-R13。用户要求自主设计约4:3方形底座与建筑，商店门窗取消、屋顶不再圆形，完成后自行迭代并代入。

## 造型与源

[v003制作母版](../../art_source/scenes/floating_shop/v003/floating_shop.blend)、[组件及打开说明](../../art_source/scenes/floating_shop/v003/README.md)、[冻结计划](../../art_source/scenes/floating_shop/v003/component_plan.json)、[机器证据](2026-10-31_floating_shop_v003_verification.json)。v001/v002原样保留。

本轮将“不要商店门窗”按取消原店门/橱窗、改为封闭建筑立面落实，没有再补另一套玻璃门窗。底座名义20×15米，主体12×9米，均约4:3；实际底座含圆角包边20.010×15.010米，比值1.333111；含护舷全件20.5×15.5米。低坡矩形金属屋顶取代圆盘屋面，方形主控箱取代圆柱穹顶。墙面为奶油横缝板、青绿角柱和墙脚。蓝白遮棚转为直边环绕，黄色直栏保留前平台约3米开口。植物、护舷、救生圈及动力层继续表达海上设施，货箱、长凳、系泊柱取代零售陈列。原铭牌在首轮渲染被屋檐挡住，已前移到檐口外，四向复看无遮挡。

32个母版Collection、273个实例、371个母版网格；32独立包全部保存重开。63248母版面逐面PaletteUV有面积/单格/安全边距、唯一UV0、Closest/外链公共色板、四材质角色、恒等变换、底部中心与零偏移通过。展开为237778多边形/468299三角面，总高9.170335米。旧玻璃窗/店门/后门/陈列/弧栏组件均不在当前装配中；它们的历史资产记录和源仍保留。前侧平台2.4米宽检查带无陈设阻挡，但封闭主体不承诺可以进入。

## 优化、保真与稳定导出

按场景导入skill在独立[优化文件](../../art_source/scenes/floating_shop/v003/export/v001/floating_shop_optimized_v001.blend)逐组件执行合并重复顶点、退化/孤立几何清理、小角度共面溶解，并对护舷/植物/球舱等高密度曲面进行受控精简。材质与色格保持，逐面UV重新映射到原色格；不删除未证明不可见的底面/背面。没有用户面数上限，budget明确为空。

同实例集合口径：源468299三角面，优化429474，减少8.291%；各件前后计数、操作及零变化原因见[优化清单](../../art_source/scenes/floating_shop/v003/export/v001/optimization_manifest.json)。组件最大包络变化约0.000381米。源及公共色板优化前后SHA-256一致。优化文件另存后重开，四个同相机/灯光/尺度视图已实际渲染对比，形体、开口、颜色、阴影目视通过；最终用户美术验收没有代签。首次派生保存的色板相对路径被Blender二次重映射，保真图暴露粉色；已修复外链、重载和保存，再渲染核验。

沿用本项目R35单一装配GLB、四个材质网格接口（逐组件优化仍单独登记），没有重建正式main。稳定文件`godot/assets/models/facilities/floating_shop/floating_shop.glb`现为429474三角面、32447188字节；仅4个FSH_SEA_*网格，没有展示地面、相机、灯或内嵌图片。材质仍由预制体序列化绑定，Gloss角色由玻璃改为不透明釉面货箱盖。源/优化/运行哈希、边界与坐标见[导出清单](../../art_source/scenes/floating_shop/v003/export/v001/export_manifest.json)。

## 游戏与验证边界

正式PackedScene路径、AssetID、World/SeaStructures/floating_shop实例、阳光房主体正南50米和甲板局部2.514米均保留。按阳光房标准改为0.22米实板：板顶水面+0.26米、板底水面+0.04米，覆盖R35“厚板必须沉水”的历史断言，动力层仍在水下。水面阻挡由同一BlockerSet从新几何派生。专项新增矩形四角阻挡检查，并以实际几何包络替代旧固定18.5米范围。截图增加矩形全景/正面，仍由`scripts/run_verification.py`在Autoload前隔离用户数据。

所有源预览和优化对比输出在工程外`sea-work/floating_shop/v003/`，正式游戏验证记录在统一runner的隔离目录；最终退出码和截图目录记录在机器证据。未新增WalkArea、泊位、交易、存档或玩法规则，相关未接入项继续pending。商业授权与用户最终美术验收pending。

Blender 4.5 GUI内清理旧scene时出现访问冲突，随后一次视口依赖图缓存又崩溃；制作源/旧版均已保护，重开保存源后使用隔离包保存复查完成。异常、修复后的成功结果、未执行项分别登记，不把崩溃中的文件当最终交付。

## 账本收尾（接续会话补做）

前一轮制作与验证跑完但未登记，收尾补齐以下项：

- 装配级`asset_manifest.json`缺失（v001/v002均有），按实测数据补建。
- 场景分账本40条FSH记录全部停在v002：23个共有组件与装配行更新到v003，9个新组件登记新AssetID（`SEA-SCENE-FSH-BENCH/BOLLARD/CARGO-CRATE/CORNER-POST/PLINTH/RAIL-STRAIGHT/ROOF-VENT/SIGN-PANEL/WALL-PANEL`），16个被封闭立面取消的旧组件标`historical_source_retained`，v002源与独立包保留、不计入当前装配。
- `current_source_index.json`按新账本重建（562条），`runtime_resource_inventory.json`逐条刷新浮店GLB/预制体/四材质的字节数与SHA-256，未批量接受漂移。
- **色板字段纠错**：catalog与组件manifest的`palette`仍写`sea_cozy_8x8_512.png`，但全部v003 blend实际外链`sea_cabin_timber_8x8_512.png`。以只读探针`tools/blender/floating_shop/inspect_palette_link_v003.py`打开母版/组件包/优化文件确认，色板SHA-256`f4b1f525…15d09`与优化清单前后值一致；已修正catalog17条与32个组件manifest的`palette`/`palette_sha256`，未改动blend。残留：blend内image datablock名仍是旧名，只影响可读性。
- 本文早期数字（267实例、467703/428879三角面、8.301%、32401168字节、底座20.03×15.03米）是尺度校准前的旧值，已按最终manifest改为273实例、468299/429474三角面、8.291%、32447188字节、20.010×15.010米。
- [机器证据](2026-10-31_floating_shop_v003_verification.json)汇总源验证、优化、导出与统一runner结果：`floating-shop`32项、`visual-floating-shop`12项均退出码0、无意外错误。

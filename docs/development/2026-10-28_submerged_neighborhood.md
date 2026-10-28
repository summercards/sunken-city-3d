# 2026-10-28 阳光房水下纯景观建筑

本轮依据用户水下街区效果图，完成六栋独立建筑并接入当前阳光房周围水下。每栋独立 Blender 包、GLB 和稳定 PackedScene；分类为 `decoration/underwater_buildings`。交付所有者为 SEA-ASSET-R29 / SEA-WORLD-R10，资产主记录通过 `assets/registry/ledger_index.json` 路由到 scenes 分账本；装配记录另计，不作为第七栋建筑。

## 制作与面数

源入口：[母版与独立包说明](../../art_source/scenes/submerged_neighborhood/README.md)；[冻结计划](../../art_source/scenes/submerged_neighborhood/v001/component_plan.json)；[优化与导出证据](../../art_source/scenes/submerged_neighborhood/v001/export_manifest.json)。

| 建筑 | AssetID尾段 | 多边形 | 实际导出三角面 |
|---|---|---:|---:|
| 错层檐线楼 | TERRACED-TOWER | 424 | 880 |
| 弧角窗廊楼 | ROUNDED-TOWER | 351 | 784 |
| 窄身竖窗楼 | SLENDER-TOWER | 298 | 636 |
| L形矮楼 | STEPPED-LOWRISE | 213 | 438 |
| 窄顶附楼 | FLAT-ANNEX | 232 | 496 |
| 后排板楼 | REAR-SLAB | 338 | 716 |

总计3950三角面；每栋包含檐线、女儿墙、屋顶凸台、窗格、挑台和附着墙漆，导出及Godot实际导入均≤1000。未以多边形面数代替三角面。建筑与现有阳光房、基座、植物和船各自独立；没有附带资源产出或玩法逻辑。

公共色板沿用唯一源PNG，运行侧引用现有同哈希公共色板。一个SEA_Matte材质角色；每面PaletteUV有面积、位于单格安全区，图片Closest采样且外链。轮廓屋檐和凸台有实体单段倒角；GLB不内嵌图片。公共运行色板导入设置按色板契约改为无损且关闭MipMap，原图未改。

独立优化文件：`art_source/scenes/submerged_neighborhood/v001/export/v001/submerged_neighborhood_optimized.blend`。逐栋执行重复点合并、退化边清理、孤立点清理及法线复核；实际零减面，保留可从水下看到的背面、底面与檐底，不声称三角化产生减面。优化前后四个固定镜头渲染平均RGB差均低于0.00002/255，几何预算一致。母版与色板前后SHA-256不变。

六个独立包均已保存重开，原点在底部中心、变换恒等、Collection偏移为零，前向Blender+Y映射为Godot-Z。源里的Collection实例布局为参考追溯；本次实景间距修订只改正式TSCN。

## 正式布局与维护

布局入口：[neighborhood.tscn](../../godot/scenes/decorations/underwater/neighborhood.tscn)，由 `Zone1HomeHarbor/UnderwaterScenery` 引用，默认最小生活范围内可见。单栋入口位于 `godot/scenes/decorations/underwater/buildings/`，模型位于 `godot/assets/models/scenery/submerged_neighborhood/`。

| 实例 | Godot位置 X/Y/Z（米） |
|---|---|
| terraced_tower | 17.6 / -21.5 / -10.8 |
| rounded_tower | -10.4 / -20.4 / 2.0 |
| slender_tower | -1.2 / -16.2 / -9.2 |
| stepped_lowrise | 0.2 / -12.0 / 24.0 |
| flat_annex | -7.3 / -14.6 / 15.8 |
| rear_slab | -11.2 / -23.0 / -11.0 |

参考关系为左侧弧楼、后退的窄楼与高楼、前方两层距离的较低屋顶和斜向水道。用户追加要求后取消初版围绕阳光房摆一圈的分布：两座背景楼退到阳光房后方不同深度，前景只留两种不等高的屋顶，形成左侧密集楼岸、右侧阳光房重心和有疏密的水面留白。原阳光房海下基座实际MultiMesh包络为 `(-4.921,-17.32,-5.298)` 至 `(15.266,1.16,14.745)`；新楼全部与此包络、互相之间分离，所有屋顶低于水面。每栋包装显式Blockers.mode=none、blocks_water=false；无CollisionObject、无interactable，独立岸线探针测得0条水线段。用户追加的水下黑斑修订见后文，光照关键帧、波场和导航规则保持。

## 当前实测

所有运行都通过 `scripts/run_verification.py`，在Autoload前隔离用户数据。

- 首次正式导入：`20261028-222456-submerged-neighborhood-332df7`，asset-import退出0；首轮图像与预算检查通过，但随后发现基座MultiMesh未纳入包围盒，旧84项结果不用于最终间距签署。
- 加强检查：`20261028-222714-submerged-final-b891ea`，发现三栋初始摆位与基座包络重叠，实景专项退出1。正式TSCN修正三栋位置；同轮minimum-loop、reference-skiff各自退出0。
- 首版修正间距后的实景：`20261028-222807-submerged-layout-final-a94a56`，86 checks / 0 failures，退出0；真实Vulkan渲染，含海面参考视角、同镜头隐藏建筑前图、俯视、去水几何检查和夜景。此时独立加载、导入三角面、纯景观身份、材质、完整包络、无导航/岸线影响通过；布局随后按用户要求继续修订，以后文最新交付为准。
- 最终集成：`20261028-222859-submerged-integration-a69b95`，minimum-loop 77 checks / 0 failures，退出0。
- 预期故障：无。最终运行非预期脚本/引擎错误：0；非阻断提示为无2D内容时启用2D MSAA的既有警告。
- Blender独立包初次使用library-write遇到引擎崩溃，已改为从保存母版逐栋重开并通过save-as另存。修复后的package_export运行退出0；源、优化和六个独立包全部重开验证。
- 未执行：微信/移动设备、整套历史全功能验证、用户最终美术验收与参考图商业权属审核；本任务不据此标记这些项目已通过。

外部日志、实景和源级八张渲染位于 `D:/projects/sea-work/`，机器报告见同名开发JSON。源级四视图与优化四视图已目视核对；隐藏立面按同一建筑规律补全，不声明单图不可见结构的精确复原。

## 全局契约边界

按要求运行 `python -X utf8 scripts/check_feature_contracts.py --sync` 再运行无参数检查。开工时已有water.tres和world_env.tres两处运行材质哈希漂移、派生功能索引过期。只登记本任务新资产，不刷新这两处未知变更的哈希；实际最终门禁结果写入同名开发JSON。本批运行专项通过不等于整个工作区全部门禁通过。

## 用户追加：有节奏的分布与全时段水下光斑

布局由一圈相近距离改成沿斜向水道的错层：左岸弧楼在前，后排板楼退远且下沉，窄身楼错开在中间，右后高楼部分被阳光房遮挡；前景L形楼与窄附楼保留不同高度、不同离岸距离。上表为最终位置；源参考实例清单仍作追溯，正式TSCN拥有这次布局修订。

原版水面的大块黑印来自`color *= 1.0 - caustic_term`：所谓光斑实际在压暗建筑。8时段×2方案的真实像素负向探针，96检查中15项失败，正午弧楼16×16屋顶样本平均亮度下降0.0711、局部最差下降0.1386（0–1范围）。该故障复现保存在`20261028-223415-submerged-caustic-before-7a7df7`，没有把失败结果当作通过。

两套水面改为共享 `submerged_caustic_light.gdshaderinc`：保持几何锚定与水深筛选，用有上限的浅青色光贡献保留建筑基底亮度，随既有日照输出权重衰减，完整夜间没有日光自发亮。波场、真实建筑阴影、季节/天气/时段预设、P面板的参数与用户配置不改。旧R10关于“以暗斑表达焦散”的实施说明由R21取代。

修后`20261028-223510-submerged-light-layout-final-23c131`的光斑专项96项通过；该轮布局检查发现窄附楼与基座边缘有0.3米包络重叠，继续将其左移至X=-7.3。最新交付与逐时段像素数据以同名JSON列出的`submerged-delivery`运行报告为准；16组时段/方案各保留开启、关闭两帧。相关集成`20261028-223619-submerged-final-regressions-69475e`的ocean、visual-atmosphere、minimum-loop均退出0，布局的中间失败单独保留。

最终交付运行 `20261028-223721-submerged-delivery-fc2816`：建筑89项/0失败、光斑96项/0失败，两项均退出0。相关回归为ocean 141项、visual-atmosphere 68项、minimum-loop 77项，均0失败和退出0。资产账本已改用本次最终布局报告登记，不沿用被后续修改覆盖的装配哈希。

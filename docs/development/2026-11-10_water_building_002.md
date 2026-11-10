# 编号002水上普通建筑：制作、植被体量修订与游戏接入

[主文档](../../GDD_V1.0.md) · [SEA-ASSET-R65](../features/asset/spec.md) · [资产账本](../features/asset/ledger.md) · [SEA-WORLD-R13/R21](../features/world/spec.md) · [摆放台账](../features/world/placed_positions.md)

## 当前结论

编号002的v003源、28独立组件包、持久优化源、28组件GLB、28稳定PackedScene及总装已完成。总装正式加入 `World/SeaStructures/water_building_002`；不是在测试里临时注入。当前统一runner正式导入及五个专项全部通过。源级、运行技术与美术终审分开记录，不把历史全库问题或未做项目签成通过。

- AssetID：`SEA-SCENE-WATER-BUILDING-002`；显示编号002。
- 类别：普通水上建筑，`building / above_water / surface/entity`。
- 源版本：v003。28组件，167个实例，625个求值后网格实例。
- 全场景：**10342三角面 / 6293多边形**，不是仅统计母版；目标约10000，偏差 `(10342-10000)/10000=3.42%`。
- 七层米白旧楼、绿窗、前阳台、方形空调与排水管、屋顶及侧挑太阳能板、缠楼树干与大树冠保留；不做细碎3D字。
- 6种植物组件（trunk_a/trunk_b/crown_a/crown_b/vine/flower）为 `building_class=null / none/none`，其余22组件为 `above_water/surface/part`，总成另占1行，共29行主记录。

## 用户追加：只调体积，不增加细节

v002被指出植被茂盛比例不符原画；v003仅缩放、平移原有18个树冠实例，不新增叶片、枝条、网格或三角形。

独立重开v002/v003复查得到：113母版网格的顶点与拓扑签名一致；非树冠149实例矩阵零变化；实例仍为167；三角面10342不变。18树冠中17个为非均匀缩放，另1个源数据为均匀2倍；游戏保留全部矩阵，而非只保留位置或单轴朝向。

同机位全画幅绿色像素占比由3.8514%升至12.0648%，倍数 `177352/56615=3.1326`。这只是相同机位前后绿量指标，不是原画植被覆盖率或还原度评分。图与数据：

- `D:/projects/sea-work/water_building_002/v003/reference_before_after.jpg`
- `volume_revision.json`、`volume_visual_comparison.json`、`source_verification.json`

## 正式来源与保护

| 角色 | 路径 | SHA-256 |
|---|---|---|
| 制作源 | `art_source/scenes/water_building_002/v003/water_building_002_v003.blend` | `b362c1b669b5ad2a7d32705df2339182e8d2447f9fd35a53d95c76b7d8541751` |
| 独立持久优化源 | `art_source/scenes/water_building_002/v003/export/v003/water_building_002_optimized_v003.blend` | `c7258d213104fd643cab1ea9418ec6bd32a5c3b4a085e1f5b678780d47897dc9` |
| 公共色板 | `art_source/shared/palettes/sea_cabin_timber_8x8_512.png` | `f4b1f52544e9e785b2ef7ae5eabbe378a551f1c48b5ef0f79905f2a9f8f15d09` |

独立包位于同版本的 `component_packages/<key>/<key>.blend`。同版本 `export/v003/optimization_manifest.json` 汇总28组件各自实际清理操作、before/after三角面、减面率、零变化原因、预算来源、源/优化/GLB哈希与保真边界，由已完成的源级报告提取，不重跑建模或覆盖源。优化只在独立文件上检查、清理已确认的退化面/重复面/孤立点，记录逐组件before/after与零变化原因，保留倒角和轮廓。没有可安全删除的几何时不强行减形；本轮展开三角面保持10342，`R=(T_before-T_after)/T_before=0%`，不将三角化宣称为减面。材质角色合并只在各组件内部进行，不跨建筑/植物合并。

28包保存重开、源与外链色板哈希保护、恒等母版变换/底心原点/零集合偏移、唯一PaletteUV、逐面非零面积与8px格内安全边、外链Closest和三语义材质通过。独立形体样本76/76通过。计划检查0超限、1项因缺body.triangles而跳过；33反例与1正例自测符合预期。没有以此签署全场景接缝穷举。

## Godot增量接入

- GLB：`godot/assets/models/facilities/water_building_002/components/<key>/<key>.glb`，共28。
- 组件包装：`godot/scenes/components/facilities/water_building_002/<key>.tscn`，共28。
- 总装：`godot/scenes/facilities/water_building_002.tscn`。
- 来源初始化及测试数据：`godot/assets/data/water_building_002_instances.json`，不是生产自动回灌布局。
- 总装分为Visual/Structure、Furnishings、Plants；Plants可独立隐藏，不参与水面占地。
- Blender到Godot映射为 `C(x,y,z)=(x,z,-y)`，实例矩阵为 `C*M*C^-1`，包含XYZ旋转与非均匀缩放。
- 真实Mesh节点逐surface序列化公共暖木色板材质（SEA_Matte/SEA_Metal/SEA_Gloss），不靠运行脚本补白模。
- 28个GLB均images=0/textures=0；导入设置embedded_image_handling=0、generate_lods=false，投影开启，保留来源面数。
- 旧v001整栋GLB仍保留在磁盘作为历史产物，但v003总装不引用它，也不登记为当前已验资源。

主场景只增加1条ext_resource和1个002节点（diff共4行新增）。所有既有节点transform与接入前备份比较零变化。002初次参考位 `(188.57135,1.12,143.89136)` 在水上商店邻侧建筑列、001东侧，中心距001为23.5米；参考不是硬性验收坐标，后续以用户手改TSCN为准。

结构自身sea_structure与BlockerSet从Visual/Structure实际水线几何派生36条占地矩形，专项逐条验证已进入main._water_shapes。植物没有独立阻挡；不创建Zone、WalkArea、泊位、人物碰撞、交互、生产或存档字段。移动结构后的阻挡随结构重算测试使用0.4米格的整数倍平移，避免把世界栅格量化误差误当成位置错误。

## 本轮真实缺陷与修复

1. 首次游戏实拍树冠/树干等出现白模：Godot导入场景有额外根节点，且把Blender名称中的点替换成下划线。原覆盖挂在错误节点；现按实际导入层级和名称序列化覆盖，不修改源几何或公共材质。
2. 文本TSCN的Basis序列化口径与GDScript Basis(Vector3,...)不同，导致旋转实例矩阵转置。已修文本写出顺序，并用167实例矩阵逐一比对；侧窗和太阳能倾角不再丢失。
3. 001已有普通建筑缺navigation_only元数据，水层专项报1项失败。仅补自身职责元数据，不移动、不修改其源或模型，也不替001签独立专项完成。
4. 001账本manifest原指B1109A的component_plan，缺asset_ledger且身份不匹配；现新增001专用manifest并修回链，保留源和原哈希。旧B1109A登记完全不动。
5. 原位置检查只计Zone绑定，漏掉普通非Zone海上建筑。补充直接SeaStructures子节点的台账和transform核验；当前6结构/0失败/0警告，不新增假区块。

## 当前正式运行证据

所有Godot运行经 `scripts/run_verification.py` 隔离Autoload前用户数据，不访问正式存档。

| 运行项 | 实测 | 退出码 |
|---|---:|---:|
| 正式asset-import | 0 unexpected errors | 0 |
| water-building-002 | 1441 checks / 0 failures | 0 |
| visual-water-building-002 | 12 checks / 0 failures，真实GPU四图 | 0 |
| water-layer | 1794 checks / 0 failures | 0 |
| gift-kiosk邻店回归 | 7129 checks / 0 failures | 0 |
| minimum-loop回归 | 112 checks / 0 failures | 0 |

前四项：`D:/projects/sea-work/verification/20261110-145440-wb002-v003-final-0984d1/report.json`。

邻店及最小流程：`D:/projects/sea-work/verification/20261110-150026-wb002-neighbor-regression-fb097a/report.json`。

实际图片在第一报告的project/outputs下：water-building-002-hero/back/roof/shop-context.png。四图均已目视，确认绿树冠、木色树干、深蓝太阳能板、七层建筑轮廓与邻店位置；这不代替用户美术终审。实测总包络含扩大树冠约29.84×44.09×17.71米（Godot XYZ）。

运行命令：

```text
python scripts/run_verification.py water-building-002 visual-water-building-002 water-layer --import-assets --label wb002-v003-final --timeout 240
python scripts/run_verification.py gift-kiosk minimum-loop --label wb002-neighbor-regression --timeout 240
```

上述运行通过GODOT环境变量指定本机Godot4.7.2。历史首轮失败报告保留，不被最终报告覆盖。

## 登记、审计与全工程边界

场景分账本新增29主记录，current_source_index按全域四字段投影一致；above_water视图含23行，6植物不进建筑视图。源、28包、优化源、28GLB哈希均独立复核不变。29行与manifest状态为 `runtime_integrated_user_art_review_pending`，source与runtime字段一致。运行资源清单新增当前002的88项资源，不刷新main或任何无关旧资源基线。

工程外证据：`registration.json`、`runtime_integration.json`、`runtime_integration_registration.json`、`delivery_audit.json`。定向审计与全工程通过是两回事。

本轮执行 `check_feature_contracts.py --sync` 后再执行无参检查；001的KeyError已消除。最终sync exit1/69项，check exit1/70项：8项旧source哈希漂移、61项runtime哈希漂移（含main既有基线），无参检查另有1项derived feature index stale。未批量重算旧哈希；因为校验器仅在零issues时写同步，派生索引未被强制改写。最初发现的R63条款单元格含附注导致承接匹配缺失已就地修格式，未改其历史事实；早期出现的workshop缺失脚本问题在最终工作区已不存在，本轮未修改该模块。日志为工程外 `contracts_sync.log` / `contracts_check.log`，机器结果为 `contract_gate_result.json`。

尚未签署：用户美术终审、原画商业授权、全局接缝穷举、性能playtest、专门绕002的端到端船只航线。普通建筑没有登岸功能不属于漏接，不能自动扩展成商店或生产设施。

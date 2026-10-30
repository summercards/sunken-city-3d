# 海上悬浮商铺 · Blender MCP制作

功能：SEA-ASSET；条款：SEA-ASSET-R34。用户要求以七视角附件制作房屋、周边设施与植物，使用项目场景制作skill，直接在Blender构建、查看并比较修正，按建筑登记。本轮交付Blender制作源，没有接入正式Godot场景。

## 源与归类

- [完整母版](../../art_source/scenes/floating_shop/v001/floating_shop.blend)、[打开说明](../../art_source/scenes/floating_shop/README.md)。
- [冻结组件计划](../../art_source/scenes/floating_shop/v001/component_plan.json)、[组件目录](../../art_source/scenes/floating_shop/v001/catalog.json)、[实例布局](../../art_source/scenes/floating_shop/v001/component_instances.json)。
- [机器验证](2026-10-30_floating_shop_verification.json)。渲染与安全备份放工程外`D:/projects/sea-work/floating_shop/`，遵循`SEA_WORK_ROOT`。
- 按总索引的`domains.scenes`写入`assets/registry/ledgers/scenes.json`。`SEA-SCENE-FSH-ASSEMBLY`归`building/structure`及`above_water`；39组件跟随同一facility，花叶单列`upgrade_attachment/plants`。源索引派生，不批量刷新其他资产的哈希。

## 尺寸与造型

12米解释为商铺店体直径；1.2米外环廊位于店体外，因此平台直径约14.4米，含轮胎与包边实际外包络约14.90×14.49米。总高7.525米（含喷口内芯），开放门洞实际净宽2.0米、净高2.200米，护栏含球头高1.100米。参考中的层界以搭接表达，不能把设备、招牌、顶盖重复累加。

正面-Y：三段弧形米黄招牌、信封/礼物/饮料图标、蓝白条纹雨棚、青绿窗框、开放门洞、明信片架、红邮筒、ICE冷藏箱、黄色售货机与盆栽。背面为封墙、小门和电箱。屋面有米黄圆柱/浅灰穹顶主控、蓝色顶饰、四组黑色射灯、两段弯管阀门、电气盒和信号灯。底部中央金属主推进舱、两只橙色球形浮舱、辅助喷嘴、辐射支臂管线、配重及正面偏右爬梯。10只轮胎、左右红白救生圈环绕。

公共8×8色板保持不变；全部组件外链同一PNG，最多SEA_Matte、SEA_Metal、SEA_Gloss、SEA_Emission四材质角色。发光喷口、射灯透镜与信号灯几何独立，未把整座建筑设为自发光。屋面、甲板及球舱有独立几何磨损斑和结构接缝；植物使用饱满宽叶、曲面圆瓣。

## 在Blender中比较与修订

通过已运行的BlenderMCP裸TCP服务执行bpy代码，所有正式几何在GUI会话中创建；没有headless代替制作。先保存默认会话安全副本，再建立独立场景。初轮真实渲染发现招牌字偏小/间距大、厚屋顶遮住主控底部、俯角遮住动力层，以及门内陈列不足。实际修订为加大招牌立体字、屋面厚度减半、浮舱前移、补入中央陈列架并调整观察角度。公共色板和既有建筑未覆盖。

源检查发现小件倒角产生的退化几何/UV，已清理退化边面，并将过小投影面映射到单格内有面积UV。修正后全部母版及独立包复查通过。逐包验证的`read_factory_settings`卸载了BlenderMCP；为继续渲染，重新打开同一保存源的GUI验证会话并恢复已安装插件，没有使用`--background`。原会话与安全副本保留。

## 本次实测

39个母版Collection、250个实例、636个母版网格；39个独立包均保存后重开。检查130283个母版面：唯一PaletteUV为UV0、逐面有面积/单格/至少8px边距、外链色板Closest采样、四材质角色、根/网格恒等变换、底部中心原点、集合偏移为零、非空几何与实例清单一致，通过。真实门洞、护栏、轮胎本体尺寸与10只轮胎/2只浮舱数量断言通过。

依赖图逐可见实例展开340075多边形、671437三角面；用户没有规定面数上限，此为源级细化资产，游戏性能与低模优化未执行。不得用母版面数替代装配面数。

渲染目标：beauty、front、back、left、right、top45、top、bottom、detail、building_only，共10张真实Blender渲染。近景、建筑分离图与七方向分别记录在机器证据的`views`中。用户最终美术验收没有代签；公共色板下的颜色、细部密度及磨损层次与参考仍有差异。

## 验证边界与退出码

Blender构建、源级检查及独立包重开通过，退出0。源登记、真实渲染及项目契约检查最终结果见下方收尾记录与机器证据。首次检查中的退化UV已修复，未将失败结果隐去。Godot导入、碰撞、导航、运行性能、参考图商业授权及用户最终美术验收未执行，均保持pending；本轮无游戏运行验证，因此不绕过`scripts/run_verification.py`直接启动游戏。

### 最终收尾

10张真实渲染已逐张目视检查；正交四方向另移除展示地面造成的地平线。源登记成功40条（39组件＋1建筑装配），未修改任务外主记录或哈希。构建、源级验证、十视图渲染、登记均退出0。`python -X utf8 scripts/check_feature_contracts.py --sync`及无参检查均通过：35功能、553源资产、459运行资源哈希，0问题。最初Windows默认GBK读取文档失败，未改项目检查器，以Python UTF-8模式重跑解决。没有预期故障用例；已解决的制作/验证异常和未执行项分别列在机器证据中。

用户打开母版即可继续修改；当前源未做Godot导出或运行优化。参考图原文件与SHA-256已随计划留存，商业授权pending。

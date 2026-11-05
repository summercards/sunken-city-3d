# 2026-11-05 ProtonScatter原版天台试刷

对应SEA-AMBIENT-R12/R18、SEA-ASSET-R51。[使用方法](../features/ambient/proton_scatter_trial.md) · [独立植被账本](../../assets/registry/ledgers/vegetation.json)。用户要求直接用仓库附带效果刷一个版本查看，本轮实际安装、调用插件，并保留可编辑预设。

## 实际版本

插件4.2.0，提交7198cc00078ebde61307578137c3f35223c6e438。上游地址、MIT代码/模型与示例贴图条件见[仓库README](https://github.com/HungryProton/scatter)。源码完整位于godot/addons/proton_scatter，已在项目插件列表启用，未修改上游模型、贴图或风动shader。

两个真实ProtonScatter节点分别生成11500草实例和42灌木实例，使用上游Create Inside Random、Randomize Transforms和正/负ScatterShape；按8米分块共60个绘制批次。随机种子110505/110506，配置、形状及原生修改器保存为可编辑TSCN。不是用项目自有撒点器模拟插件效果。

原版示例草10/6三角面、灌木42三角面。保留原色截图；另做绿色适配，只更改Gradient三色与wind_strength=0.45。原版草/灌木材料都使用上游grass.gdshader及其TIME/噪声风动。阳光房原花草与正式main默认v003保持；试刷场景独立保存，不自动把插件运行生成和示例纹理带进发行版。

## 兼容处理与失败历史

1. 直接使用示例TSCN时，旧导入节点Plane011等名称失配，材质挂不上，首次截图出现白片；completion marker虽然为0失败，美术检查拒绝该版。随后用相同原版GLB，通过ScatterItem.override_material挂相同原版ShaderMaterial，未改几何或shader。
2. 自动运行更新使退出树时再次构建，曾在completion marker之后报instance uniform缓冲不足；统一runner据完整日志判失败。关闭enable_updates_in_game并显式full_rebuild后解决，没有加大全项目缓冲。
3. 并行沉没街景资源接入后，后续全场景快照出现新GLB尚未导入；全库导入虽完成资产阶段，但在编辑布局阶段超时124，Unicode/失效节点警告保留。未隐藏这些错误，也未将它们算作native试刷通过。
4. 最终试刷与保存重开测试改为使用正式天台的独立视效台；相机与主场景灯光配置复用，Main海面合成与新沉没街景集成不在此范围。

首次干净主场景实拍：D:/projects/sea-work/verification/20261105-171949-proton-native-review-d6e772，visual-proton-scatter退出0。该目录的绿色近景和120帧用于主场景效果展示；每帧按原生60FPS编码，2秒，不把它误编码成半速视频。

最终可复现报告：D:/projects/sea-work/verification/20261105-173934-proton-focused-stage-eedf1a/report.json。visual-proton-scatter与visual-proton-preview均退出0、无未识别错误。保存后场景重开生成11542实例；材质落在实际网格，插件内部body RID和collision shapes均为空。

## 性能范围

独立天台视效台，RTX4060Ti，1280×800，Forward+，每模式90帧根Viewport计时：v003 GPU p50/p95为1.333/1.455ms，插件绿色试刷为0.992/1.000ms；渲染CPU p95分别1.571/0.677ms。这是同一独立台的比较，不代替全游戏60FPS或其他设备验证，也不与前一轮包含完整Main的数字直接比较。

## 可复用入口与后续边界

Godot打开res://scenes/vegetation_authoring/proton_rooftop_preview.tscn，F6可运行独立预览；rooftop_scatter_authoring.tscn保存两组原生修改器、ScatterItem及正负Box形状。制作配置、源预设、模型清单与manifest在art_source/vegetation/proton_scatter_trial/v001。

三份原版演示模型及一份预设分别登记到vegetation账本，状态trial_verified_production_pending；来源是上游GLB，不伪造Blender母版。示例贴图条款、统一暂停/显隐时钟接入和正式采用仍pending。插件和试刷目录排除在发行预设之外，正式Main不依赖运行时ProtonScatter重刷。

原生主场景图片/视频、独立台原色/绿色对照、可编辑场景重开图、原始点位和运行日志在D:/projects/sea-work/proton_scatter_trial_20261105/。文档门禁结果见下方附录，保留其他任务的未知哈希漂移。


## 文档门禁附录

`check_feature_contracts.py --sync`退出1；完整输出：`D:\projects\sea-work\proton_scatter_trial_20261105\feature_contracts_sync.log`。

`check_feature_contracts.py `退出1；完整输出：`D:\projects\sea-work\proton_scatter_trial_20261105\feature_contracts.log`。

全库未解决的其他来源/运行哈希漂移保留，不通过批量刷新消除。试刷和保存重开专项当前均通过，正式全世界集成仍未签署。

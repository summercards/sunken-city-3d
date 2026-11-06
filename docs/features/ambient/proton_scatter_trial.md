# ProtonScatter 原版示例天台试刷

[主文档](../../../GDD_V1.0.md#sea-ambient) · [植被资产账本](../../../assets/registry/ledgers/vegetation.json) · [上游仓库](https://github.com/HungryProton/scatter)

2026-11-05 用户要求直接用仓库效果刷一版看。本轮已经安装并启用ProtonScatter 4.2.0，固定提交`7198cc00078ebde61307578137c3f35223c6e438`，实际调用插件节点和修改器，使用仓库附带的两种草和一种灌木模型、原版grass.gdshader及贴图。

## 直接查看和调整

Godot打开 `res://scenes/vegetation_authoring/proton_rooftop_preview.tscn`，可在3D视口查看，或按F6运行独立预览。此场景使用正式天台模型，隐藏该场景实例中的v003草层；主场景默认草层保持v003，阳光房原花草保持。

可编辑散布预设是 `rooftop_scatter_authoring.tscn`。打开它选中 `NativeGrass` 或 `NativeBushes`：

- Modifier Stack的Create Inside (Random)修改Amount；当前草11500、灌木42。
- Randomize Transforms控制随机朝向和比例；General的Global Seed固定随机结果。
- 正Box为屋顶允许域，负Box为道路、楼梯入口、现有设施与未来升级排除区。灌木另避开中部种植空间。
- ScatterItem选择原版GLB，Source Scale分别为草0.8、灌木1.65；材质通过Override Material明确挂到真实网格。
- 绿色预览的材质在预设中内嵌保存，可在Override Material展开Gradient和Wind Strength调整。只改色阶和风强度0.45，原版模型、贴图、shader和风动算法保持。

采用插件原生的Create Inside Random＋Randomize Transforms＋ScatterShape正负区域；不是项目自己的随机撒点算法。原版实例化和8米空间分块生成11542实例，当前60个绘制批次。所有keep_static_colliders关闭；检查插件内部Physics RID也为空，避免只看节点树漏掉插件物理资源。

## 实际踩到的兼容问题

上游示例TSCN引用了旧导入器的Plane011等节点名，在当前Godot4.7.2中挂材质失效，第一次出现白片。本轮使用同一个原版GLB，通过ScatterItem.override_material绑定同一原版材质，修复了真实网格上的绑定；没有改上游模型或shader。

运行中自动更新使退出树时再次触发构建，曾在结束阶段耗尽instance uniform缓冲。关闭enable_updates_in_game，使用明确full_rebuild解决；保留force_rebuild_on_load以便编辑预设和重开预览自动生成。未通过加大全项目缓冲掩盖问题。

插件代码和模型按上游MIT管理；示例贴图另遵循上游README注明的Textures.com使用条件。本轮是工程内试刷，不作为独立贴图包分发。第三方素材权利专项审查及正式发行接入保持pending。插件demos和试刷场景已经排除在发行预设之外。

## 复现和管理

```powershell
python3 -X utf8 scripts/run_verification.py visual-proton-scatter visual-proton-preview
```

所有运行通过统一runner隔离用户数据。第一次成功实拍在正式主场景中完成，之后的最终可复现测试使用正式天台及相机/灯光设置组成独立视效台，避免加载并行编辑中的沉没街景。`capture_proton_scatter.gd`输出当前v003对照、上游原色、绿色适配、近景/远景、原生风动帧、真实插件点位和可编辑修改器预设；`test_proton_preview.gd`重开保存后的场景验证11542实例。独立视效台不代替Main海面合成或全世界集成验收。源配置在`art_source/vegetation/proton_scatter_trial/v001/`。

试刷使用上游TIME风动，尚未替换正式系统的暂停/显隐时钟契约；此项与跨设备性能、素材发行审查一起保留为正式采用时的接入工作，不把本轮预览冒充全部生产验收。当前试刷原生结果、性能与退出码见[交付记录](../../development/2026-11-05_proton_scatter_trial.md)。

## 设施移动后的试刷

打开 `godot/scenes/vegetation_authoring/proton_rooftop_preview.tscn` 并按 F6。预览中的 `RooftopRanch` 同时持有 `NativeScatter` 和预览相机，移动或旋转设施时，生成的草和灌木及相机随它移动。编辑散布形状和修改器时继续使用 `rooftop_scatter_authoring.tscn`。正式主场景的草皮和草堆入口见[手动编辑说明](vegetation_meadow.md#在-godot-里手动摆放)。

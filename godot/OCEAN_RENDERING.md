# 水面、白浪与边缘波纹（2026-10-22）

视觉参考：TechFusion《花了一周在Unity中写的风格化海洋环境渲染》
https://www.bilibili.com/video/BV1TqM76nEWf/

保留并重做白边、海面白浪和船行浪。参考视频中的岸线细白边、向外扩散的弯曲浪线，以及间歇出现、推进后消散的白浪分别由同一水面 Shader 表现。没有在海面摆放白色条带、泡沫贴片或固定描边网格。

## 自动岸线

`scripts/world/shore_distance.gd` 遍历实际可见场景几何（MeshInstance3D / MultiMesh），求三角形与海拔 1.12 米平面的交线，再生成欧氏距离纹理。材质不再使用旧 `shore.json` 中的矩形；旧 JSON 仍供原有导航逻辑使用。

- 合并 GLB 按焊接顶点连通性拆分，避免薄片装饰、旧水花管线等被当成实体岸线。排除高度小于 0.5 米的连通分量、隐藏对象和完全没入水中的对象。
- 1536×1536 RG 浮点纹理：R 为到轮廓的米制距离，G 为附近实体的尺寸系数。小箱子、细柱产生更小的波纹，避免大圆圈包围小物体。
- 覆盖相机平移范围加 24 米边界；当前为 204×204 米，每像素约 0.133 米。每次启动从当前场景重新生成，移动/旋转/更换场景模型后无需手画岸线。
- 运行中主动改动静态场景或水位时，调用 `Water.rebuild_shoreline(roots, region)` 重建。并非每帧重切静态模型；移动船体使用当帧深度交界和实际航迹。

`shaders/ocean_foam.gdshaderinc` 根据距离产生细接触白边和错相的外推波包。轮廓有小幅扇贝状弯曲，浪线在传播时拉薄、断裂并消散，复位前强度归零。岸浪同时贡献最多约 2.4 厘米的位移和相应法线，不只改变颜色。

## 海面白浪与材质

- 开阔海面的白浪与主波相位共用方向、色散速度、横向弯曲和时钟。低频空间/时间包络控制出现与消退，不铺满海面，也不是独立漂移的白色斑块。
- 浪头有较亮的细前缘，后侧是逐渐变薄的半透明泡沫；多尺度程序纹理生成不规则边缘与细小孔隙，亚像素纹理淡出以减少闪烁。
- 白沫使用受场景光照影响的浅色材质、较高粗糙度和较低透射，保留明暗与厚薄层次；不使用白色自发光。
- `water.gdshader` 保留深度吸收、屏幕折射、GGX 高光与天空环境反射。水粗糙度默认 0.17，水/空气 F0 约 0.02037。透射颜色不再被水材质重复照亮。
- 可调参数：`shore_foam_strength`、`crest_foam_strength`、`foam_color`、`water_roughness`。

## 基础波浪与船行浪

- `World/Water`：连续 257×257 网格，观察目标附近 0.5 米间距，外围逐渐稀疏。四组带横向弯曲和振幅包络的解析波，避免无限长的平行条纹。
- `ocean_waves` 每项为 `(方向 X, 方向 Z, 振幅米, 波长米)`。基础波的 CPU 浮力与 GPU 位移共用参数和时钟。船体采用四点采样计算升沉、俯仰和横摇；自身尾流和微小岸浪未反馈到浮力。
- `World/BoatWake` 只保存最多 64 个世界空间历史点，压缩为最多 32 个 Shader 采样点；尾浪随真实转向弯曲，停止后继续扩散并在 9 秒内消退，传送时清空。
- 尾浪的位移、法线及细白沫都在水面材质中计算，不另画白色尾带。船首有局部肩浪；划桨和停船保留法线涟漪。
- `boat.json` 的七条旧白色装饰管仍不参与显示。鱼群静态双圆环不恢复，玩法交互保留。

## 验证与预览

```sh
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path godot --script res://tests/test_ocean.gd
~/Applications/Godot.app/Contents/MacOS/Godot --path godot --script res://tests/test_ocean.gd
bash godot/verify_surface.sh
~/Applications/Godot.app/Contents/MacOS/Godot --path godot --write-movie outputs/water-upgrade/wave-detail.avi --fixed-fps 30 --script res://tools/capture_wave_detail.gd
~/Applications/Godot.app/Contents/MacOS/Godot --path godot --write-movie outputs/water-upgrade/shore-waves.avi --fixed-fps 30 --script res://tools/capture_ocean.gd
```

专项覆盖：波高/梯度、浮力与导航解耦、尾浪转向/停船/传送、实际网格交线与欧氏距离、模型移动/旋转、隐藏/全浸没对象、MultiMesh 实例变换，以及合并模型内薄片的排除。Headless 的 Dummy RenderingServer 不保留 MultiMesh 实例变换，因此这一项额外用 Metal 实际渲染后端验证。

最新录像为 `outputs/water-upgrade/wave-detail.mp4`（固定镜头观察白浪和岸线）与 `shore-waves.mp4`（航行）。历史 `clean-ocean.mp4` 是误删白沫的迭代，已不代表当前实现。录像固定 30 Hz 离线录制，不能据此推断实时 FPS。

这是风格化解析水面和程序泡沫，不是完整流体求解器；反射来自场景灯光和天空，尚未实现建筑平面镜像反射。P 面板的个人滤镜仍优先，录像使用曝光 1.05、亮度/对比度/饱和度 1.0。独立海底地图不受影响。

最新模型结构为 [v008 组件库](../../art_source/environments/tower_zones/tower_district/source/common_components/v008/README.md)。以下为 v007 初次场景制作记录。

# TOWER DISTRICT / 方块街区场景

最终文件：`source/tower_district_v007.blend`。当前 Blender 会话已加载此文件，主场景为 `TD_TOWER_DISTRICT_FINAL`。

## 查看
- 主参考镜头：`TD_Reference_Camera`，1920×810；按小键盘 0 进入相机视图，F12 渲染。参考图上下黑边不属于场景内容，因此输出使用有效画幅。
- 动画：1–240 帧、24 fps、10 秒。时间轴播放可查看悬浮无人机、四组旋翼、雨丝、飘纸、隧道车辆；灯牌、扫描灯、体积噪声也有驱动。旋翼运动为连续角度，视觉首尾闭合。
- `previews/tower_district_motion.mp4` 为 960×406、12 fps 的 10 秒轻量预览。源文件仍按 24 fps 工作，可提高采样后重新渲染。
- `TD_Detail_Camera` 是招牌、无人机与机电近景；`TD_Top_Camera` 是全场结构俯视镜头。文件默认保持主参考镜头。
- 灯雾必须用渲染视图或最终渲染查看。实体视图不显示体积效果；材质预览的质量与最终渲染存在差异。

## 内容
按参考图拆分 16 个区域，详见《区域分析与制作清单.md》。完整场景包括高架闸口、主招牌及灯栅、桥下通道、两侧店面、ATM、信息终端、LIQUOR 竖牌、机电管道、通风机组、广告、路灯与交通灯、车辆、湿路面、人行道、碎屑、远景楼群、无人机及光雾雨纸。无人物。

可见实体全部为硬边盒体或旋转后的平面盒体；轮胎、护圈、箭头采用阶梯格块。没有圆柱、圆球、曲线文字、倒角或细分曲面。车辆玻璃采用倾斜矩形硬面，避免密集台阶造成百叶窗误读。体积散射、镜头虚化与光学衰减保留连续效果。

共享色盘已打包在 Blend 中，同时保留 `source/tower_palette.png`。4 个表面材质角色是 `TD_Metal`、`TD_Matte`、`TD_WetPaint`、`TD_Emission`；6 个体积材质独立管理。逐面 PaletteUV 有面积且位于单个色格内。对象按建筑、招牌、机电、店面、道路、车辆、动态和灯光分组，可独立编辑。

## 验证与范围
`qa/scene_verification.json` 记录实体拓扑、向外法线、无平滑面、色盘 UV、动态驱动与循环首尾误差；`qa/scene_manifest.json` 记录对象、材质、世界包围盒、灯光和相机。检查以当前最终场景为范围，不把备份场景的默认立方体纳入。

本次是参考图的三维风格化重建。无人物后，中间街面比参考图开阔；遮挡后方、背面和画外区域按可见结构补足。没有修改现有 sea 游戏代码，也没有进行 Godot 接入、碰撞制作或游戏性能验收。

## 文件
- `source/tower_district_v007.blend`：最终可编辑场景。
- `source/00_original_session_backup.blend`：操作前 Blender 空场景备份。
- `source/iterations/`：制作中间版本，可回看。
- `source/reference.jpg`：用户提供的原始参考图。
- `previews/tower_district_final.png`：最终主镜头。
- `previews/tower_district_motion.mp4`：动态预览。
- `previews/mechanical_detail.png`：机电与无人机近景。
- `previews/structure_top.png`：无光雾的结构俯视检查图。
- `scripts/`：建模、材质、灯雾、动画、渲染及检查脚本。

若需要完整重建，在已连接的 Blender MCP 会话按顺序运行：`build_scene.py` → `refine_scene.py` → `final_geometry_pass.py` → `finalize.py` → `fog_polish.py` → `atmosphere_finish.py` → `finish_light_balance.py`。通过 `python3 scripts/bridge.py <脚本路径>` 发送。生成器只重建 TD_ 命名的数据；重建前仍应保存自己的后续手改。`revise_source.py` 是制作过程的一次性源码迁移记录，不在重建序列中。

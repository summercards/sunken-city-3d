# 黄白木船 v001

用户 2026-10-28 附件为视觉依据。原图及 SHA-256 在 `component_plan.json`；外观按黄白船壳、三排暖木座板、船外机、绿色帆布包、防撞浮球和两支木桨制作。参考图的商业权属保持 pending，几何为本工程新制作。

- 制作入口：`reference_skiff.blend`。组件母版和参考装配为两个场景，12项母版、44个 Collection Instance。12个独立包在 `component_packages/`。
- 唯一公共色板：`art_source/shared/palettes/sea_cozy_8x8_512.png`。源文件外链、不打包；三种角色 `SEA_Matte/Metal/Gloss`，每面 `PaletteUV` 安全岛。
- 船头 Blender +Y → Godot -Z；运行静水面 `Y=1.12`，船局部水线为0。船体含舷边的包围盒精确沿用旧船：宽2.574708924、高1.073136871、长5.397479548米。桨、机身和挂灯属于附属物，不参与船壳包络。
- 源装配实测11697多边形、22888三角面；独立优化副本导出后的44实例共22695三角面。数字不包含既有运行灯笼/灯杆、角色与展示支持。
- 正式装配：`godot/scenes/props/reference_skiff.tscn`。船体/配件用独立 PackedScene，桨用两个旋转包装；源JSON只做追溯，后续摆位直接编辑TSCN。
- 航行、转向、水线、船锚、存档字段和泊位数据继续由既有 Boat/WaterNavigation 所有。原船烘焙文件保留。

生产工具在 `tools/blender/reference_skiff/`：`prepare.py`先冻结计划，`build.py`创建新源与独立包，`verify_export.py -- --render`重开核验、四视图并导出独立优化副本；`initialize_runtime.py --initialize-runtime`仅允许首次初始化新场景，遇到已有正式TSCN拒绝覆盖。`repack.py`可从已保存母版恢复独立包；`refine.py`记录本轮一次性内肋修订，已修订源拒绝重复执行。

Godot所有运行验证经 `scripts/run_verification.py`，具体退出码、实景和集成限制见 `docs/development/2026-10-28_reference_skiff.md`。预览和日志在工程外 `sea-work/reference_skiff_v001/` 与 `sea-work/verification/`。

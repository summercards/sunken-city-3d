# 阳光繁花小屋 · 当前附件独立制作

当前交付为 [v003/sunny_bloom_retreat.blend](v003/sunny_bloom_retreat.blend)。本任务自身 v001/v002 保留；未复用其他工作套件。

- 主场景 `Sunny Bloom Retreat | 参考图装配`：`01 建筑` 内分结构、固定设施与陈设；`02 花朵与植物` 可独立隐藏；展示支持仅相机和灯光。
- 母版场景 `组件母版 | 独立原点`：49 组件，根与网格恒等、底部中心原点；装配 592 个 Collection Instance。
- 49 个独立包位于 `v003/components/<key>/<key>.blend`。外链唯一公共 `art_source/shared/palettes/sea_cozy_8x8_512.png`；4 材质角色，PaletteUV 有面积且保留安全边。
- v003：按用户标线补齐全宽前平台，双列桥位于前沿偏左；右侧留活动空间。修正窗洞、太阳能板尺寸与厚圆角、布棚支撑；花朵朝上或斜上方错落分布。后方两类墙柱/棚柱已补齐。
- 保存文件实例展开：374100 多边形 / 703920 三角面。源级六视图与 49 个包重开通过；未做 Godot 性能验收。

计划、目录及实例分别为 `component_plan.json`、`catalog.json`、`component_instances.json`。坐标 XY 平面、+Z 朝上，保留完整 Euler；映射到 Godot 为 `(x,z,-y)`。

工具位于 `tools/blender/sunny_bloom_retreat/`，默认 v003。`build.py` 保护保存源，`--replace-generated` 只用于本任务当前生成候选；`verify.py` 重开源与独立包并渲染六视图。输出位于工程外 `sea-work/sunny_bloom_retreat_v003/`，可用 `SEA_WORK_ROOT` 重定向。

Godot 接入、碰撞、导航、运行性能、参考图商业授权及用户最终美术验收 pending。

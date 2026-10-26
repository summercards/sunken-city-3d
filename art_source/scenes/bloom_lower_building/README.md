# 繁花建筑下半部分

[当前独立 Blender 源](v001/bloom_lower_building.blend)。独立制作源保留；2026-10-26已在游戏中作为太阳能木屋海下基座接入。

- 七层楼体、错落厚白窗湾、蓝灰柱、青蓝窗与浅杏铺砖屋顶。
- `01 建筑` 分结构和固定设施；`02 花朵与植物` 可独立隐藏、导出；`90 展示支持_不导出` 为相机和灯光。
- 22 个组件、414 个实例；独立包在 `v001/components/<key>/<key>.blend`。公共色板外链不可丢失。
- 源级重开、PaletteUV、结构检查及五视图通过。当前 526306 多边形 / 976564 三角面。
- 顶板上沿 Z=12.32 米；源坐标 XY 平面、+Z 朝上，Godot 映射 `(x,z,-y)`。正式拼装仍需另行确定接合尺度和接口。

`component_plan.json`、`catalog.json` 和 `component_instances.json` 分别登记计划、组件及完整 Euler 实例。预览和验证输出位于工程外 `sea-work/bloom_lower_building_v001/`，可用 `SEA_WORK_ROOT` 重定向。工具在 `tools/blender/bloom_lower_building/`。

2026-10-26：Godot组件接入、七层接合与真实渲染检查通过；共用既有游戏行走/导航，未新增室内玩法碰撞。长时间性能基准、参考图商业授权及用户最终美术验收 pending。

[接入记录](../../../docs/development/2026-10-26_solar_cabin_v006.md) · [完整游戏比例装配](../sunny_bloom_retreat/v006/export/v001/placement/solar_cabin/solar_cabin_v1.3.blend)。

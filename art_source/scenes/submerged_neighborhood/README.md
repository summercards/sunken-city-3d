# 阳光房水下景观建筑

制作母版：[v001/submerged_neighborhood.blend](v001/submerged_neighborhood.blend)。其中“独立建筑母版”场景包含六栋独立 Collection，“水下街区_参考布局”场景只包含其 Collection Instance 和展示相机、灯光。

每栋独立打开入口为 `v001/component_packages/<key>/<key>.blend`，共用 `art_source/shared/palettes/sea_cozy_8x8_512.png`；不打包或复制色板。独立优化文件是 `v001/export/v001/submerged_neighborhood_optimized.blend`，GLB 必须从重开后的优化文件逐栋导出。

| key | 名称 | 多边形 | 导出三角面 |
|---|---|---:|---:|
| terraced_tower | 错层檐线楼 | 424 | 880 |
| rounded_tower | 弧角窗廊楼 | 351 | 784 |
| slender_tower | 窄身竖窗楼 | 298 | 636 |
| stepped_lowrise | L形矮楼 | 213 | 438 |
| flat_annex | 窄顶附楼 | 232 | 496 |
| rear_slab | 后排板楼 | 338 | 716 |

总计 3950 三角面；每栋上限 1000，包含女儿墙、挑台和窗格全部附着几何。没有用大多边形隐藏导出面数。当前清理没有减少三角面，保留轮廓和材质边界的理由见 `export_manifest.json`。

分类：`decoration/underwater_buildings`；纯景观、无碰撞、无行走区域、无互动与资源产出。正式布局由 `godot/scenes/decorations/underwater/neighborhood.tscn` 拥有，阳光房原基座继续独立维护。参考图未显露的立面为规律补全；商业参考权属保持 pending。

制作工具位于 `tools/blender/submerged_neighborhood/`：先 prepare 冻结计划，再 build 保存源，最后 package_export 逐栋重开验证、独立另存优化和导出；initialize_runtime 只允许初始化尚不存在的新 TSCN。旧正式场景不能重生成覆盖。

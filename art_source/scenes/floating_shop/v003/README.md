# v003 · 矩形海上补给建筑

制作母版：`floating_shop.blend`，场景“海上悬浮商铺_v003”。这是当前版，旧v001/v002保留。

- 底座约20×15米，主体约12×9米，均约4:3；边角有实体倒角。
- 矩形低坡屋顶、方形主控箱、封闭奶油色横缝墙板；没有原商店门、橱窗和店内陈列。
- 蓝白直线遮棚、黄色直栏、前侧平台开口、护舷/救生圈/植物保留，新增长凳、货箱、系泊柱和矩形通风盒。
- 32组件、273实例；建筑与植物分别放在`FSH_建筑与固定设施`、`FSH_植物附件`。相机/照明/地面在`FSH_展示支持`，不进入游戏。
- 单件在`component_packages/<key>/<key>.blend`，均保存后重开验证。材质外链仓库唯一公共色板 `art_source/shared/palettes/sea_cabin_timber_8x8_512.png`（阳光房暖木变体，SHA-256 `f4b1f525…15d09`），保留仓库相对目录。注意 blend 内贴图 datablock 名仍沿用旧名 `sea_cozy_8x8_512.png`，实际 filepath 是暖木变体；改名前不要按名字判断色板。
- 游戏输出来自独立的`export/v001/floating_shop_optimized_v001.blend`；逐组件优化、源保护、保真与导出数据记录在同目录两个manifest中。制作母版未因优化回写。
- 装配级登记见`asset_manifest.json`：32组件/273实例、371母版网格、63248母版面、展开468299三角面、优化后429474三角面、GLB 32447188字节。尺寸契约与冻结计划见`component_plan.json`，尺度基准为`.agents/skills/sea-scene-component-authoring/references/building_scale.json`。

正式游戏仍引用`godot/scenes/facilities/floating_shop.tscn`及稳定GLB，不重建main场景；现有阳光房主体南50米、水面上0.26米甲板关系保持。2026-10-31 起这个预制体同时是最小区块 `sea_supply`：四条环廊可走、一个泊位、招牌下一个补给入口（见 `docs/development/2026-10-31_sea_supply_station.md`）。封闭主体仍不承诺可进入，本轮没有新增店内空间。

源检查/渲染/优化对照在工程外`sea-work/floating_shop/v003/`；统一Godot runner隔离实测与最终结果见`docs/development/2026-10-31_floating_shop_v003.md`和同名verification JSON。参考图商业授权及用户最终美术验收pending。

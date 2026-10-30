# 海上悬浮商铺

当前源：[`v002/floating_shop.blend`](v002/floating_shop.blend)。在Blender中打开后选择“海上悬浮商铺_v002”场景。v001原样保留。

v002：外环站人平台从1.2米加宽到3.0米（2.5倍），平台直径约18米；护栏、轮胎和边缘配重随外移，正面护栏留3.43米开口，与2米店门对齐。邮筒和售货装置让开中央路线，门槛压平；从外缘到店门有1.95米宽连续无遮挡通路。39组件、248实例及独立包重开/UV/尺寸复验通过。详见 `docs/development/2026-10-30_floating_shop_v002.md`。

- `FSH_建筑与固定设施`：圆盘商铺、屋面设备、环廊、招牌、陈列与悬浮动力系统。
- `FSH_植物附件`：独立宽叶植物和小花；花盆在设施集合，不与植物焊接。
- `FSH_展示支持`：相机、灯光和奶油色背景地面，不是游戏组件。
- 39份组件母版不直接显示，当前装配使用248个Collection Instance。需要单件编辑时，打开 `v002/component_packages/<key>/<key>.blend`。

店体直径12米，当前平台增加每侧3米环廊；含护舷外包络约18.50×18.11米，总高7.525米。正面为Blender -Y、向上+Z，Godot映射 `(x,y,z) → (x,z,-y)`。门洞净尺寸2.0×2.2米。造型按七视角参考制作并保留sea海上建筑的公共色板风格。

色板外链到 `art_source/shared/palettes/sea_cozy_8x8_512.png`；请保留仓库相对目录，禁止将色板复制进套件。当前组件计划、实例布局、catalog与asset_manifest均在v002中。

分类为建筑/商店、海上区域。源登记：`assets/registry/ledgers/scenes.json`，前缀`SEA-SCENE-FSH-`。**已接入正式场景**：运行GLB `godot/assets/models/facilities/floating_shop/floating_shop.glb`（导出脚本 `tools/blender/floating_shop/export_runtime.py`，248实例按四材质角色烘合并为四块网格，无内嵌贴图），预制体 `godot/scenes/facilities/floating_shop.tscn`，正式摆放 `godot/scenes/main.tscn` 的 `World/SeaStructures/floating_shop`（阳光房主体正南50米，甲板顶面水面+0.26米）。水面阻挡由预制体自带 `Blockers` 派生；行走面、泊位、商店交互、面数优化及参考图商业授权仍 pending。详见 `docs/development/2026-10-30_floating_shop_runtime.md`。

制作与源级核查脚本：`tools/blender/floating_shop/`；渲染和安全备份：工程外 `D:/projects/sea-work/floating_shop/`，可用`SEA_WORK_ROOT`重定向。详细记录见 `docs/development/2026-10-30_floating_shop.md`。

# sea 场景制作源

所属功能：[SEA-ASSET](../../docs/features/asset/spec.md)。正式运行资源位于 `godot/assets`；本目录不参与 Godot 打包。

场景资产主记录通过 [ledger_index.json](../../assets/registry/ledger_index.json) 的 `domains.scenes` 路由到 [场景分账本](../../assets/registry/ledgers/scenes.json)。不另建重复主表；[源索引](../../assets/registry/current_source_index.json)由分账本派生。

## 清新错层花屋码头（本轮参考图套件）

- [打开 Blender 完整源](pastel_flower_harbor/v001/pastel_flower_harbor.blend)
- [冻结计划](pastel_flower_harbor/v001/component_plan.json) · [组件目录](pastel_flower_harbor/v001/component_catalog.json) · [实例清单](pastel_flower_harbor/v001/component_instances.json)
- 30 种组件，建筑/设施与花草分离；独立包位于 `pastel_flower_harbor/v001/component_packages/`。
- 对应本轮用户附件：错层奶油花屋、太阳能前廊、双列同向码头、按附件分布的圆润花叶，不含船。
- [制作记录与验证](../../docs/development/2026-10-24_pastel_flower_harbor.md)。工具位于 `tools/blender/pastel_flower_harbor/`；输出在工程外 `../sea-work/pastel_flower_harbor/`。

## 太阳能花屋（当前风格源 v003）

- [可打开的完整 Blender 母版](solar_flower_house/v003/solar_flower_house.blend)
- [制作前组件计划](solar_flower_house/v003/component_plan.json)与[实际组件目录](solar_flower_house/v003/component_catalog.json)
- [实例位置、完整旋转与缩放](solar_flower_house/v003/component_instances.json)
- `component_packages/<slug>/<slug>.blend`：独立组件源，建筑和花草均可单独打开。
- [公共 64 色方格色板](../shared/palettes/sea_cozy_8x8_512.png)与[色名、色值和格子坐标](../shared/palettes/sea_cozy_8x8_512.json)
- [sea 专用制作 Skill](../../.agents/skills/sea-scene-component-authoring/SKILL.md)
- [本次制作与验收记录](../../docs/development/2026-10-24_solar_flower_house_style.md)

完整源中的 `太阳能花屋_参考装配` 场景含 `建筑_实例`、`花草_实例` 两组，可分别隐藏。`组件母版_建筑与花草` 场景拥有唯一网格母版。展示相机、光源和背景位于 `90_展示环境_不导出`，不属于资产包。

这是 Blender 源级资产：米制尺寸依据参考图估计，尚未对齐现有玩法碰撞；未生成正式 Godot GLB/Prefab，不替换当前游戏建筑。参考图来源为用户附件，商业使用权仍为 pending。

## 可复现工具

脚本位于 `tools/blender/solar_flower_house/`，仅处理本套新资产：

1. Blender 执行 `build_source.py -- --render`，从冻结计划制作母版。已有源默认拒绝覆盖；制作期间明确修正本生成候选才使用 `--replace-generated`。
2. Blender 执行 `finalize_packages.py`，从已保存母版制作真正可打开的独立 `.blend`。
3. Blender 执行 `verify_source.py -- --render`，重开总源和所有独立包、逐面验证 PaletteUV 并渲染分离图、近景与俯视。
4. Python 执行 `register_sources.py`，仅在源级门禁通过后更新本套资产行及派生索引。

Blender 命令应使用 `--background --python-exit-code 1 --python <脚本>`，防止 Python 异常被进程退出码 0 掩盖。图片和 QA 默认写到工程外 `../sea-work/solar_flower_house/`，可用 `SEA_WORK_ROOT` 改根目录。上述脚本不负责初始化或重生成正式 TSCN。

保留的低面数版本 v002：28 个组件、84 个实例，总计 1947 多边形 / 2999 三角面（完整场景实例展开后计数）。平台 8.6×8.2 米；v001 高细节源原样保留。复现 v002 使用 `build_lowpoly.py`，随后对 finalize_packages.py、verify_source.py、register_sources.py 传 `--version v002`；Blender 的脚本参数放在 `--` 后。新预览与 QA 在 `../sea-work/solar_flower_house_v002/`。


当前 v003 直接打开 v001 母版，用 `restyle_v003.py` 调整配色和 5 项花叶组件；建筑几何与摆位锁定，详见 `v003/scope_lock.json`。36 个组件、255 个实例，保留第一版细节，不宣称达到 3000 三角面。公共色板 PNG 不变，通过 PaletteUV 改用现有色格。

复现 v003 后，对 finalize_packages.py、verify_source.py、register_sources.py 传 `--version v003`。预览、QA 与日志在 `../sea-work/solar_flower_house_v003/`。前两版不覆盖；v002 的平台扩建和低面数版本可继续独立使用。

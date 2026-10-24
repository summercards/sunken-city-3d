# 太阳能花屋 v004 · 按 2026-10-24 新附件重做的等距小屋

所属功能：SEA-ASSET；设计条款 R03–R07、R11。用户本轮附件是一张等距视角的双层白墙小屋：屋顶露台带米色小屋、右前方挑出的太阳能门廊（橙色台面＋黄白尖旗遮阳棚）、浅木栈桥与黄色渔船。

## 为什么是新版本

新附件的体量、层数、栈桥拓扑和船只都与 v001–v003 不同：旧版是单层石基小屋配三块斜置电池板，新版是两层白墙＋独立屋顶小屋＋单坡屋面大电池阵。按套件既有做法保留 v001–v003，本次在 `v004/` 独立建版，不复用旧几何，也不覆盖任何历史文件。

## 制作顺序

1. 先写 `plan_v004.py` 冻结 48 项组件计划（23 个语义族，单族 ≤3，栏杆族用 `infill` 变体轴拆成实心女儿墙与通透栏杆），记录参考图 SHA-256、米制假设与色板哈希，再开始建模。
2. `build_v004.py` 逐组件在局部坐标建模：几何居中、底面在 z=0、`Collection.instance_offset` 归零；`end()` 统一归一化、合并网格并挂 `ROOT_<slug>` 空物体。
3. 装配场景只放 Collection Instance；建筑与花草分属两个顶层实例集合，展示环境在 `90_展示环境_不导出`。
4. `finalize_packages.py --version v004` 用 `libraries.load` 生成 48 个可独立打开的组件包，色板外链不打包。
5. `verify_source.py --version v004 --render` 重开母版与全部独立包做源级校验并出四视图。

## 关键做法

- **色板**：全程只用 `art_source/shared/palettes/sea_cozy_8x8_512.png`，图片节点 `Closest`、由 `PaletteUV` 驱动；逐面 UV 是半径 0.022（约 11 px）的小岛，落在单色格中心，安全边 ≥21 px。材质只有 `SEA_Matte` 四个共享角色，没有新增颜色材质。
- **屋面**：门廊单坡屋面与电池阵整体绕 X 倾斜 10.5°，电池片用 `solar` 色、底下垫白色电池床让缝读成白线，蓝色托盘做边框；板上木垫板独立成件。
- **花叶分离**：叶簇、藤蔓、波斯菊、雏菊、黄花苞都是花草集合的独立组件，没有焊进花箱或墙里；花瓣是扁椭球五瓣 + 花心球，叶簇是放射状宽椭圆叶。所有花箱、花盆只负责容器。
- **倒角**：板材、柱、栏杆按实际尺度设 0.012–0.05 米倒角并配加权法线；花叶走平滑曲面，不用平滑着色伪装倒角。
- **成片**：等距正交镜头（35.26° 仰角、前左方位）按装配包围盒自动取景，24 张白色背景 + 暖调 RGB 曲线只作用于几何（alpha over 白色底），背景保持纯白。

## 文件与登记

- [v004 母版](../../../art_source/scenes/solar_flower_house/v004/solar_flower_house.blend)
- [冻结组件计划](../../../art_source/scenes/solar_flower_house/v004/component_plan.json)
- [组件清单](../../../art_source/scenes/solar_flower_house/v004/component_catalog.json) / [实例清单](../../../art_source/scenes/solar_flower_house/v004/component_instances.json) / [组件树](../../../art_source/scenes/solar_flower_house/v004/component_tree.txt)
- [48 个独立组件包](../../../art_source/scenes/solar_flower_house/v004/component_packages)
- [参考图](../../../art_source/scenes/solar_flower_house/v004/reference.png)
- [结构化源级验证](2026-10-24_solar_flower_house_v004_verification.json)
- 制作脚本：[计划](../../../tools/blender/solar_flower_house/plan_v004.py)、[构建](../../../tools/blender/solar_flower_house/build_v004.py)

AssetID 前缀 `SEA-SCENE-SOLAR-`，装配 `SEA-SCENE-SOLAR-FLOWER-HOUSE` 版本更新为 v004，旧 v001–v003 源路径与哈希保留在 `previous_sources`；公共色板 `SEA-PALETTE-COZY-64` 不变。

## 实测数据

- 组件 48、实例 340、母版面 14629、母版顶点 14748，逐面 PaletteUV 检查 14629 面。
- 整场景按依赖图展开后 **116541 多边形 / 208140 三角面**。该套件本轮用户要求是高还原，没有设面数上限；v002 的 3000 面结论仅属于 v002，不套用本版。
- 米制假设：基座 5.65×6.00 米、台面 z=0、栈桥面 z=0.60、橙台面 z=0.95、一层墙 0–2.40、二层板 2.40–2.60、二层体 2.60–4.40、屋顶露台 4.40–4.58、小屋 4.58–6.08，门廊坡屋面 10.5°。参考图无标尺，仅为独立美术源假设。

## 验证边界

源文件重开、48 个独立包重开、逐面 UV 面积与安全格、色板外链与未打包、材质角色、根与网格变换恒等、原点居中与记录包围盒全部通过（退出码 0，错误列表为空）。四张真实 Cycles 渲染（成片、建筑单独、近景、俯视）在工程外 `../sea-work/solar_flower_house_v004/previews/`。

未执行：Godot 导入、运行时碰撞与导航、游戏内性能、参考图商业授权核验。因此本版仍是 **source_verified_runtime_pending**，不是已接入游戏的美术验收结论；参考图授权保持 pending。

## 与参考图的已知差异

已核对但未完全对齐的项：花朵密度仍低于参考图、屋檐花带更薄、渔船略小、栈桥立柱比参考图更稀。这些属于继续打磨项，本轮不宣称像素级一致，也不宣称用户美术验收通过。

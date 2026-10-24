# 太阳能花屋 v002：饱满花叶、简约造型与 3000 面预算

FeatureID：SEA-ASSET；日期：2026-10-24。

用户要求花和叶子更饱满、风格更简约、所有面数不超过 3000，并扩大木头可行走平台。本次另存 v002，完整保留 v001 文件及哈希。

## 交付

当前母版为 `art_source/scenes/solar_flower_house/v002/solar_flower_house.blend`，组件仍分别归属建筑和花草。共 28 个组件定义、84 个 Collection Instance。28 个独立组件 `.blend` 与相应 manifest 均已保存并重开检查。

- 花朵改为较大的厚五瓣轮廓，减少数量并扩大单朵体积。
- 叶片改为少量宽厚体块；主要绿植使用两段截面保持饱满，不用成片小薄叶堆密度。
- 去掉木纹、螺钉、麻绳股、密集电池栅线及次要陈设，保留太阳能屋顶、门窗、棚、帆、救生圈、轮胎、家具等主要识别结构。
- 主要建筑轮廓使用实体单段倒角与加权法线；段数服从用户指定的总面数预算。共享 64 色方格色板和 PaletteUV 保持不变。
- 木平台从名义 7.4×6.6 米扩大为 8.6×8.2 米，面积约从 48.84 增至 70.52 平方米，增加约 44%。房体保持 4.8×3.6 米，新增面积留在前方及两侧。

## 预算口径与实测

不是仅统计母版：从保存文件的活动场景依赖图读取修改器求值后的每个网格实例，再实际三角化求和。隐藏的母版库不重复加到实例统计中；展示集合只有相机和灯，无展示网格可漏计。

| 项目 | 实测 |
|---|---:|
| 唯一组件数 | 28 |
| 装配实例数 | 84 |
| 展开后网格数（发光体独立） | 86 |
| 母版多边形数 | 822 |
| 整场景展开后的多边形数 | 1947 |
| **整场景展开后的三角面数** | **2999 / 3000** |

`geometry_budget.json` 含每种组件的单件面数、实例数与合计；独立重开验收确认生成记录和实际依赖图的数值相等。全部 822 个母版面的 UV 有面积、位于单格安全区，实例共享同一份已验证的网格和色板。

前方净空盒为 Blender 坐标 `min=(-3.65,-3.85,1.70)`、`max=(3.20,-2.65,3.50)`，即 6.85 米宽、1.20 米深的连续通行带。保守逐实例包围盒检查没有陈设侵入；平台和墩柱作为承载结构排除。此为源级空间检查，未宣称 Godot 角色行走或导航已验证。

## 资产状态与旧源保留

场景分账本通过 `ledger_index.json` 解析。28 个组件和总装配使用原 AssetID 升级当前源到 v002，并以 `previous_sources` 保留 v001 路径、版本、manifest 和 SHA-256。未使用的 8 个 v001 组件保留独立登记，总资产行仍为 81，未创建重复 AssetID。公共色板仍为 v001。

Skill 已补充“整场景修改器求值后三角形预算”和“紧预算允许单段实体倒角”的规则。3000 上限只属于本套件，不强加给其他场景。

## 验证与预览

命令和实际退出码详见 `2026-10-24_solar_flower_house_lowpoly_verification.json`。本次相关命令：

1. Blender `--background --factory-startup --python-exit-code 1 --python tools/blender/solar_flower_house/build_lowpoly.py -- --replace-generated --render`。
2. Blender 执行 `finalize_packages.py -- --version v002`。
3. Blender 执行 `verify_source.py -- --version v002 --render`。
4. Python 执行 `register_sources.py --version v002`。
5. Skill 校验、`check_feature_contracts.py --sync`，以及不带参数的检查。

真实 Cycles 全景、建筑单独图、近景、俯视图位于工程外 `../sea-work/solar_flower_house_v002/previews/`。临时 `.blend1` 移到同级 backups，未混入制作源目录。

未执行：Godot 导入、正式碰撞与导航、游戏性能测试、参考图商业授权核验。仍为 `source_verified_runtime_pending`。本任务不修改正式 Godot 场景、运行资源或玩家存档。

## 全工程检查状态

本轮 `check_feature_contracts.py --sync` 和不带参数检查均退出 1，唯一错误仍为任务外 `godot/assets/materials/water.tres` 哈希漂移。31 个功能、81 个源资产中，本批源资产未报错。未覆盖海面资源哈希；SEA-ASSET 主文档摘要仍为部分实现，`--sync` 的原子写回被该任务外问题阻止。源级检查、组件包重开、预算、UV、净空、渲染与 Skill 校验退出码均为 0。29 份被升级的 v001 组件/装配源哈希逐份复核不变。

# 饱满卡通热带花屋 · 源级制作

所属功能：SEA-ASSET；承接 R01–R07、R12。日期：2026-10-24。

## 输入与范围

使用本轮附件 `codex-clipboard-18bf0e22-1b03-479c-a366-5627310ed18f.png`，归档在套件内 `reference.png`，哈希由冻结计划记录。用户要求参考 02-battle-room-component-decomposer 的贴图使用和组件归类规则，建筑与花草分离，保持饱满卡通体积、倒角和比例，并节省不必要面数。采用 sea-scene-component-authoring 的项目目录、公共色板和登记方式，不继承 ShellStorm2 的尺度、战局身份或互用率约束。

新建 `art_source/scenes/tropical_flower_house/v001`，保留所有旧花屋源。图中可见的奶白两层体量、露台软布棚、两片太阳能板、黄白条纹棚、空调、蓝门窗、家具、遮阳伞、冷藏箱、双列栈桥和粉白花叶分别落为组件。尺寸从单张图估算，主平台 7.4×6.8 米、主楼 5.2×3.5×2.85 米；不可见背面延续可见结构。尚未对齐玩法碰撞与角色尺度。

## 交付

- [完整母版](../../art_source/scenes/tropical_flower_house/v001/tropical_flower_house.blend)
- [冻结计划](../../art_source/scenes/tropical_flower_house/v001/component_plan.json)、[组件目录](../../art_source/scenes/tropical_flower_house/v001/component_catalog.json)、[实例清单](../../art_source/scenes/tropical_flower_house/v001/component_instances.json)
- [实际几何预算](../../art_source/scenes/tropical_flower_house/v001/geometry_budget.json)
- 38 个独立包：`component_packages/<slug>/<slug>.blend`；每包有自己的 manifest、局部底部中心原点、几何指纹与源哈希。
- `热带花屋_参考装配` 场景含 `建筑_实例` 与 `花草_实例`，可分别隐藏。唯一母版在 `组件母版_建筑与花草` 场景；展示相机和灯不在组件包中。
- 38 种组件含 32 种建筑/陈设、6 种花草，267 个实例，其中花草实例 65。计划总额 50，剩余 12；每族最多 3。粉花五瓣、雏菊六瓣为不同轮廓，非仅换色复制。
- 通过资产总入口路由到场景分账本，新增 `SEA-SCENE-TFH-` 38 条组件记录与 1 条装配记录；派生源索引同步。

## 材质与减面

所有网格外链同一 `SEA-PALETTE-COZY-64` 色板，不复制/打包图片。四种共享角色为 Matte、Metal、Gloss、Emission；PaletteUV 是活动编辑及渲染层，每面小岛有面积、落单格、留安全边；图像使用 Closest。发光灯芯单独命名与分离。公共 PNG 与 HEAD 版本逐字节相同。

硬表面保留真实倒角：主要大轮廓三段、一般部件两段、重复铺板一段并用加权法线保留平面。小叶片用 10×6 分段球面，大花瓣用 12×8，裂叶使用有厚度的闭合曲面；没有依靠细分修改器堆面数。太阳能栅线无倒角，不建不可辨的螺钉和木纹。

保存文件依赖图实测：**58966 多边形 / 108572 三角面**，包括所有可见实例，排除隐藏母版重复计数。母版共有 14964 面，不能用这个数替代整场景预算。相较本轮中间版本 141076 三角面下降约 **23.0%**。本轮无用户指定的绝对面数上限，不套用旧套件的 3000 面结论。

## 实测与视觉修正

先冻结 36 项计划，后按参考补入栈桥灰石支撑及扁宽屋顶空调，先更新计划至 38 项再建对应几何。修正露台前沿压住太阳能板的问题；补齐栈桥支撑、加厚圆叶、调整垂藤排列，并把下层分块墙改为连续开窗墙壳，消除角缝。完整装配重复项均是 Collection Instance。

保存后重开母版与全部 38 个独立包；原点、根/网格变换、Collection.instance_offset、包络、非空几何、材质角色、图片路径、逐面 UV、实例数量/变换/归属、预算和包哈希检查通过。14964 个母版面逐面验证。

全景、建筑分离、近景、俯视图均由保存的 Blender 源真实渲染，位于工程外 `../sea-work/tropical_flower_house/previews/`。进行了目视复核：体量层次、棚弧、太阳能板与露台关系、双列栈桥、建筑/花草独立性。当前花带密度、裂叶形状及内景细节仍是风格化重建，未声称像素级还原或代签用户美术验收。

初次验证工具仍引用旧套件场景名，产生 KeyError，未生成通过报告；已修正。最终流程显式使用 `--python-exit-code 1`，避免 Blender 默认退出码掩盖 Python 异常；最终 build、独立包输出、源级验证/四视图渲染分别记录真实退出码，见[结构化记录](2026-10-24_tropical_flower_house_verification.json)。没有预期故障注入。

## 复现与未执行项

工具位于 `tools/blender/tropical_flower_house/`：先 `plan_source.py`，再由 Blender 顺序运行 `build_source.py`、`finalize_packages.py`、`verify_source.py -- --render`，最后 Python 运行 `register_sources.py`。Blender 需带 `--background --factory-startup --python-exit-code 1 --python`。已有母版默认拒绝覆盖，只有明确更新本生成候选时才使用 `--replace-generated`。`SEA_WORK_ROOT` 可改工程外输出根。临时 `.blend1` 已移至工程外本套件 backups。

交付阶段为 Blender 源级完成。Godot 导入、GLB/Prefab、碰撞、导航、运行性能与参考图商业授权均 pending；没有修改正式 TSCN 或运行资产。将来运行验收须使用 `scripts/run_verification.py`。本轮不以结构检查代替游戏实测。

## 最终检查结果

本轮最终 Blender 构建、独立包输出、重开/UV/实例检查及四视图渲染均退出 0。功能契约 `--sync` 与无参数检查均退出 0：31 功能、186 源资产、219 运行资源哈希，0 问题。公共色板与既有资产未改写。本轮未执行 Godot 运行验证。

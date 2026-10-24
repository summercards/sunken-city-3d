# 太阳能花屋：Blender 场景源与 sea 场景制作规范

FeatureID：SEA-ASSET。2026-10-23 开始制作，2026-10-24 完成源级交付。

## 结果与范围

按用户提供的太阳能花屋参考图建立独立场景制作源。奶油墙壳、六块蓝色太阳能板、木平台、圆窗、侧面拱门、青色门扇、条纹棚、遮阳帆、梯子、绳栏、轮胎、救生圈、灯和生活陈设均有可编辑几何。建筑使用真实多段倒角；花叶使用平滑曲面。参考图无比例尺，平台约 7.4×6.6 米，尺寸是假设，不更改现有游戏尺度。

- 主源：`art_source/scenes/solar_flower_house/v001/solar_flower_house.blend`。
- 36 个唯一组件、255 个 Collection Instance，包含 30 个建筑/设施组件与 6 个花草组件。
- 两组独立归属：`建筑_实例` / `花草_实例`，对应母版在另一场景 `组件母版_建筑与花草`；花盆与植物分离。
- 36 个独立 `.blend` 包：`component_packages/<slug>/<slug>.blend`，打开即有本组件活动场景。
- 组件计划、目录、实例清单、逐件 manifest 和目录树保留在主源同目录；源级几何共 157,674 个多边形，这是母版统计，不是游戏运行预算。
- 场景账本复用总索引已声明的唯一 `scenes` 分账本。新增 38 个 AssetID：36 组件、1 参考装配、1 公共色板；保留旧 43 条源记录，总数 81。

## 公共色板与 Skill

`art_source/shared/palettes/sea_cozy_8x8_512.png` 为 512×512、8×8 的 64 色方格图，配套 JSON 记录名称、sRGB 与格子坐标。每个面的小 UV 岛都有面积并位于单一格子的安全内区，所有组件外链同一图片，Closest 采样，活动与渲染 UV 均为 PaletteUV。共享四个质感角色：SEA_Matte、SEA_Metal、SEA_Gloss、SEA_Emission；灯芯单独输出为 emissive 网格。

适配后的 Skill 保存在 `.agents/skills/sea-scene-component-authoring/SKILL.md`。它保留指定 `02-battle-room-component-decomposer` 的先计划后制作、组件预算、语义归类和母版实例原则，并吸收 `blender-game-prop-standard` 的色板 UV 细则。移除 ShellStorm2 路径、战局房型、12 米墙高和紫色工业配色约束。原用户级 Skill 未覆盖，sea 版本随仓库保存。

## 真实渲染与目视修正

Blender 5.2.2 LTS、Cycles 渲染，正交镜头，Standard 色彩管理。预览位于工程外 `../sea-work/solar_flower_house/previews/`：

- `solar_flower_house_beauty.png`：完整参考镜头。
- `building_only.png`：隐藏全部花草，检查建筑独立性和结构。
- `detail.png`：门窗、棚、家具与花草近景。
- `top.png`：俯视检查平台、屋顶与设施分布。

首轮目视发现遮阳帆与条纹棚局部交叠、放大绳桩导致帆杆过粗。更新计划后增加独立细帆杆，将计划从 35 调整为 36，收窄帆布并减少圆窗上方藤蔓遮挡。调整灯光与色彩管理后再次真实渲染；最终没有以生成图片替代模型渲染。

## 验证与已修正问题

最终命令、退出码、数据与日志路径见同目录 `2026-10-23_solar_flower_house_verification.json`。源级验证使用 Blender；本次没有 Godot 运行变更，因此没有借助历史游戏测试签署运行接入。

- 完整源和全部 36 个独立包保存后重开。
- 原点为包围盒底部中心；ROOT、Mesh 变换恒等；Collection.instance_offset 为零。
- 逐实例核对组件、位置、完整 Euler XYZ 旋转、统一缩放和分类；太阳能板倾角没有丢失。
- 157,674 个多边形逐面核对 UV 面积、同格、安全边、活动层；验证唯一外链色板和最多四种材质角色。
- 实测发现并修复墙体布尔运算产生的额外 UV 层。
- 实测 Blender `libraries.write` 对新建未同步场景崩溃，且库文件直接打开会呈现空活动场景。改成从已保存母版加载组件到新场景，再常规 save_as_mainfile，验收增加活动场景非空断言。
- Blender 最终命令使用 `--python-exit-code 1`，避免 Python 异常被退出码 0 掩盖。
- Skill frontmatter 校验通过；校验器依赖 PyYAML 装于工程外隔离环境。

## 未执行与下一阶段

本次为源级交付，`source_verified_runtime_pending`。没有导出整屋 GLB，也没有修改已有 Godot 建筑、正式 TSCN、碰撞、导航和玩法规则。正式组件 GLB、稳定 Prefab、碰撞/挂点、导入材质和游戏性能均未执行。后续接入需单独评估源网格简化与实例性能，并通过 `scripts/run_verification.py` 隔离用户数据运行验证。

参考图来源为本次用户附件，保留原图哈希；商业授权尚未核验，标记 pending。色板为本次原创色值排列。其他进行中的海面渲染工作及其哈希记录未修改。

## 全工程契约检查的任务外阻塞

`python3 scripts/check_feature_contracts.py --sync` 和不带参数检查均实际运行，退出码均为 1；唯一错误为 `runtime hash drift: godot/assets/materials/water.tres`。该文件及运行资源索引在开工时已经存在海面渲染工作的未提交修改，本次没有接受或覆盖其哈希。检查共读取 31 个功能、81 个源资产和 219 个运行资源哈希，本批场景源未报错。`--sync` 因全局检查失败没有执行原子写回；SEA-ASSET 摘要本来就是 partial/部分实现，本次保持该状态，无需改变主文档状态值。不能将该结果声称为全工程检查通过。

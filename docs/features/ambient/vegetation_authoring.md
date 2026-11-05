> 本页为已退役的 v001 历史制作说明。用户否定实体草堆/几何草叶方案；所有当前制作、铺设与复用以 [v002 柔软贴图草皮手册](vegetation_soft_cards.md) 为准。本页旧数量、旧消费者和旧资产不是当前交付状态。

# 共享植被制作与铺设手册

[主文档](../../../GDD_V1.0.md#sea-ambient) · [功能设计](spec.md) · [功能账本](ledger.md) · [植被独立资产账本](../../../assets/registry/ledgers/vegetation.json)

2026-11-05 实装范围：阳光房、顶层牧场。两处复用同一套原创网格、色板与 GPU 风动。草堆参考视频的圆润绿量和细叶活动，未复制视频模型，也不声称还原了视频的原始算法。

## 找资产与直接复用

| AssetID | 组件文件名 | 三角面 | 用途 |
|---|---|---:|---|
| SEA-VEG-GRASS-FINE | grass_fine | 60 | 细叶分段草簇 |
| SEA-VEG-GRASS-ROUND | grass_round | 60 | 宽圆叶短草 |
| SEA-VEG-MOUND-ROUND | mound_round | 1308 | 圆润蓬松草堆 |
| SEA-VEG-MOUND-SPREAD | mound_spread | 1308 | 铺展草堆 |
| SEA-VEG-BROADLEAF | broadleaf | 324 | 独立盆栽植物，不含花盆 |
| SEA-VEG-DAISY | daisy | 720 | 三枝白瓣野花 |
| SEA-VEG-PINK-FLOWER | pink_flower | 720 | 三枝粉瓣野花 |
| SEA-VEG-TURF-PAD | turf_pad | 28 | 1×1 米柔边覆盖基底，可缩放 |

把 `godot/scenes/components/vegetation/<文件名>.tscn` 拖入场景即可复用，统一底心原点、Godot Y 向上。每件的独立制作源、独立优化源、GLB、包装、哈希、消费者及验收证据以植被分账本为唯一记录。旧建筑分账本中的植物历史记录保留，不再新增重复 AssetID。

运行包装使用 `piece.gd`，实际 MeshInstance3D 上绑定公共 ShaderMaterial；不是把材质写在没有网格的父节点上。单件独立预览时没有风控制器则保持静止。正式主场景 `World/VegetationWind` 是唯一风参数写入者，新增区域不得再添加第二个全局控制器。

## 已铺区域与编辑入口

- 阳光房：56 株原附件换成共享植物，保留原实例 ID、变换、花盆、升级阈值与所属模块；海下基座不在本次迁移范围。楼顶空气调节器周围及二层女儿墙顶铺草，蓝色太阳能板、走道与门口保留。
- 顶层牧场：原连续草皮基底保留；新布局含 4005 草簇、16 草堆、10 野花、8 盆栽。90 旧草、160 旧草簇、原盆栽视觉节点保留路径并标记 `vegetation_replaced`，由新布局负责显示。水下旧植物不在本次迁移范围。

制作配方是 `art_source/vegetation/v001/layout_recipes.json`。`rect=[xmin,zmin,xmax,zmax]`、`y` 都是**所属设施的局部 Godot 坐标**，`y` 是实际承载面的顶面；顶层牧场为 60.05，根节点下沉后的世界高度是 4.13。不能用世界海面高度替代屋顶局部高度。

`exclusions` 留出踏石道路、木板横道、房屋、盆栽和未来温室/水塔占地。草根经过逐点排除检查；底层行走、升级占地和阻挡仍由原功能拥有，植被无碰撞、无导航、无产出。

调整已铺区域后执行：

```powershell
python3 -X utf8 tools/blender/vegetation/assemble.py --layout-only
```

此命令只烘焙布局，保留已调好的共享材质。产物为 `godot/data/vegetation/layouts/*.json`：显式实例 ID、位置、缩放、朝向与相位；同一配方和 seed 重建结果一致。编辑配方后重新打开消费者场景，或调用 `VegetationTurf.rebuild()`。正式运行只读取烘焙实例，不投射、不随机撒点。

新增其他区域时，将同格式 `regions` 数组写入新配方，再执行：

```powershell
python3 -X utf8 tools/blender/vegetation/assemble.py --layout-only --scope my_garden --recipe <新配方.json>
```

在所属场景添加 Node3D，挂 `res://src/ambient/vegetation/patch.gd`，设置 `layout_path` 为新布局资源；节点填写 `metadata/visual_only=true`。将消费者补入使用资产的账本行。小件直接放 PackedScene，大面积草地用 patch；无需重新制作 shader，也不需要安装 Scatter。

## 风、材质和性能档位

公共风在 `godot/shaders/vegetation/wind.gdshaderinc`，材质入口在 `godot/assets/materials/vegetation/`，资产到材质映射在 `godot/data/vegetation/catalog.json`。主弯曲、局部叶片摆动和世界空间阵风共享时钟；固定底部和草堆的主体保持稳定，上层叶片参与变形。不是刚体整体摇晃。

风控制器 `set_wind(strength, direction)` 是天气接入端口，强度限定 0–2。当前沿用晴天微风 0.8；没有给 WeatherService 虚构风字段。暂停和 World 隐藏冻结时钟，睡觉跳日不直接改变视觉相位。`sample_at(seconds)` 用于可重复验收。

COLOR 为线性权重数据：R 主弯曲、G 叶片细动、B 叶相位、A AO；不是顶点着色，也不是透明度。UV0 仍是 PaletteUV。MultiMesh 关闭实例颜色，开启 custom data，X 为稳定相位、Z=1 表示有效实例数据；Y/W 为保留字段，本版不把 W 当第二次生长缩放。所有叶片为不透明几何，不写 ALPHA，不使用透明淡出。

草地采用 8 米分块、每 0.35 秒最多一次投影尺寸判断及滞回；相机不动不重复更新。小于约 1.1 像素的细草隐藏，连续绿底仍显示。近景 Low/Standard/High 保留约 50%/80%/100% 草簇，远一些再降为 35% 的该档密度。可通过 patch 的 `quality` 选择档位。草叶和基底不投射阴影，草堆与较大植物保留阴影。包围盒额外覆盖 0.6 米风动余量。

共享材质参数同时登记 `godot/assets/materials/shader_param_contract.json`。调参时同步该基线；不要为每片叶复制材质。渲染参数真实重开、原生录屏和性能证据见本轮交付记录。PC 60 FPS 是整帧目标，不能把单项 GPU 增量达标写成整机所有视角锁 60。

## 制作新植物或改模型

先查重并更新组件计划。当前可复现脚本是 `tools/blender/vegetation/build.py`；它只写本套件 `art_source/vegetation/v001/`，不会执行旧建筑构建器。正式交付后修改几何应开 v002，保留 v001 与原 AssetID 的历史源，不能用重新生成覆盖已登记版本来掩盖变更。

母版 `<key>.blend` 与 `<key>_optimized.blend` 分开保存；优化源做微小重合点合并和退化边清理，保留 UV/权重。两份均重开审计。每件 `production_report.json` 记录优化前后数据、真实哈希与操作，不虚报面数缩减。GLB 导出不内嵌图片，真实导出属性检查必须包含 COLOR_0/TEXCOORD_0。

草皮基底为固定几何，本轮不包含墙面青苔短绒、海面荷叶或作物生长动画。新资源接入前分别确认模型、风权重和 gameplay 所有权，不能给作物套上装饰草的规模化布置规则。

## 当前验收入口

```powershell
python3 -X utf8 scripts/run_verification.py vegetation-contract visual-vegetation rooftop-ranch
python3 -X utf8 scripts/run_verification.py visual-vegetation-performance
python3 -X utf8 scripts/check_feature_contracts.py --sync
python3 -X utf8 scripts/check_feature_contracts.py
```

统一 runner 隔离用户存档，输出到工程外 `sea-work/verification/`。结构专项检查根权重、负样本拒绝、稳定布局、重建不重复、升级与暂停/显隐；原生渲染检查每个批次的上传变换、近/中/远景及连续风动帧。性能脚本用 Godot [RenderingServer 的 viewport GPU/CPU 计时](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu)，另记植被脚本 CPU 开销；帧间隔和 GPU 渲染耗时分别报告。

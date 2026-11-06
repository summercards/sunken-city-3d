# 宽叶草地与天台草堆 v003

[主文档](../../../GDD_V1.0.md#sea-ambient) · [独立植被账本](../../../assets/registry/ledgers/vegetation.json) · [交付与实测](../../development/2026-11-05_vegetation_meadow.md)

本版承接用户“草太碎、太小、远景看不见”及“在顶层牧场天台放草堆，草地和草堆要有明显风动”的修订。v003 为当前版本；v002 只保留苔藓与历史，不能运行旧组装工具覆盖当前布局。

## 当前资源与范围

| 资源 | AssetID | 形态/预算 | 消费者 |
|---|---|---|---|
| grass_soft | SEA-VEG-GRASS-SOFT | 3张分段面片，18三角面，约0.74米宽、0.48米高 | 阳光房、顶层牧场 |
| mound_soft | SEA-VEG-MOUND-SOFT | 42张交叠面片，252三角面，约2.96×2.42×1.13米 | 顶层牧场 |
| meadow_atlas | SEA-TEX-VEGETATION-MEADOW-ATLAS | 2048 RGBA，两种宽叶草扇、两种草堆叶簇 | 上述两处 |
| moss_soft | SEA-VEG-MOSS-SOFT | v002低矮苔藓保持 | 阳光房 |

新Image-2图集以视频帧及旧细草图集为参考，明确减少为每簇约9–12片宽曲叶，去掉微小叶脉与亮点。叶片形状与软边来自透明贴图；面片只承担层叠与弯曲，不逐叶建实体。草堆没有隐藏实体球、实心内核或建筑碰撞。

阳光房为272大草簇＋原122苔藓贴片；原花朵与原草对象保持。顶层牧场为5358草簇＋14处草堆，连续基底沿用原屋顶草皮；旧90草/160细草实例仅隐藏并保留原路径/变换，不和新草重复绘制。旧盆栽与建筑、道路、楼梯、泊位及升级规则保持。

草堆沿边缘和空地成组布置，排除道路、设施和未来温室/水塔占地。楼顶实际承载面仍是局部Y=60.05，设施下沉后世界Y=4.13。禁止按海面Y直接摆屋顶草。

## 风动和远景

共享风控制器默认强度1.1；草叶最大位移参数0.20米，草堆0.30米。根权重固定，顶端渐强，同方向阵风约2.77米/秒经过世界空间，再叠小幅叶尖活动。形变同步改变柔化法线，远景只加轻微受光起伏帮助读出同一阵风，主要运动仍是顶点形变。

草簇宽度约为上一版的2.5倍，叶片本身也减少并加宽；远景颜色收拢为连贯绿量。Standard近景保留100%，中景约80%，很远处仍保留45%轮廓；不再直接清空细草。Low额外乘65%。苔藓和草堆保留。空间分块、滞回及额外0.6米包围盒继续使用，全部细草不投射阴影。

暂停/隐藏World冻结风时钟；退出房间等显隐往返沿用同一所有者。场景不再各建一套风系统，风相位与布局不写入经营状态或存档。

## 修改与复用

- 配方：`art_source/vegetation/v003/layout_recipes.json`。
- 重铺两处：`python3 -X utf8 tools/blender/vegetation/assemble_meadow.py`。修改配方后运行，保持稳定运行路径，登记真实变化。
- 改图集处理：`prepare_meadow_atlas.py`；保留原生成图与`texture_brief.txt`，仅做alpha裁切、归一化与留边。
- 改源载体：Blender后台运行`build_meadow.py`。独立母版与优化源分开保存、重开；UV0为BotanicalUV，COLOR为风权重。
- 单件复用：`godot/scenes/components/vegetation/mound_soft.tscn`或`grass_soft.tscn`。大面积用patch读取烘焙布局；不要复制shader/风控制器。
- 资产定位、当前源/历史源、消费者和哈希只维护独立植被账本；草沿用原AssetID并保留v002 previous_sources，新增草堆与新图集各一行。

所有运行检查使用统一runner的隔离用户数据工程。当前入口：vegetation-contract、visual-vegetation、visual-vegetation-performance、rooftop-ranch、water-layer、minimum-loop。录屏需覆盖正常游戏镜头和远景，不以微距叶形清晰代替远景验收。实际硬件、耗时、退出码和剩余边界见交付记录。

## 在 Godot 里手动摆放

直接打开下列设施或子场景，在场景树选中对应节点，用移动、旋转和缩放手柄或检查器的 Transform 调整，保存场景即可。要改主场景中整个设施的位置，就在 `main.tscn` 移动设施根节点，植被会一起移动。

| 场景 | 选取节点 | 可调整内容 |
|---|---|---|
| `rooftop_ranch.tscn` | `VegetationTurf/Regions/roof_lawn` | 天台整片草皮的位置、朝向、尺寸和显隐 |
| `rooftop_ranch.tscn` | `VegetationTurf/Plants/Mound_*` | 单个草堆。新增草堆可实例化 `mound_soft.tscn` |
| `solar_cabin_surface.tscn` | `VegetationTurf/Regions` 内的 `upper_roof_meadow`、`left_parapet`、`front_parapet`、`moss_accents` | 屋顶草皮、侧沿、前沿和独立苔藓组。分区内的苔藓会跟着同一草皮分区移动 |
| `solar_cabin_rear_building.tscn`、`solar_cabin_solar_room.tscn`、`solar_cabin_front_platform.tscn` | `flower_*`、`leaf_*` 等带原组件名和实例编号的花草节点 | 逐株调整，保存后的变换随模块和设施移动 |

`VegetationTurf` 检查器里的 **Refresh grass preview** 可重建编辑器预览。场景中保存的是草皮分区和草堆的位置。单根草继续按布局 JSON 批量生成，密度、边界和道路避让由配方维护。移动整片草皮时同时检查它与设施边缘、道路的对齐情况。天台草堆的 JSON 点位用于追溯原始布局，当前摆位以 `VegetationTurf/Plants` 中的 TSCN 为准。阳光房花草的编号用于绑定原模型和升级显隐，拖动时保留节点名。

工具配方改动先走工程外候选，审阅草皮分区原点及布局变化后逐文件接入。其他场景仍可直接复用草簇、草堆预制体和共享风动。[设施实测位置](../world/placed_positions.md)

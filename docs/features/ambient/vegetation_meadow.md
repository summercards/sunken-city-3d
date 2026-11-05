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

> 当前版本已更新为 [v003宽叶草地与天台草堆](vegetation_meadow.md)。本页保留v002历史说明；当前制作请用assemble_meadow.py/build_meadow.py。

# 阳光房柔软草皮：制作和复用

[主文档](../../../GDD_V1.0.md#sea-ambient) · [功能设计](spec.md) · [功能账本](ledger.md) · [独立植被资产账本](../../../assets/registry/ledgers/vegetation.json)

2026-11-05 用户修订后的当前版本为 **v002**。本轮只铺阳光房草皮、少量苔藓；阳光房原有 56 株花草的对象、AssetID、位置、形状和材质全部保留。顶层牧场先恢复原状。v001 实体草堆/几何草叶方案被用户否定，其运行候选移到工程外，不登记成正式资产。

## 视觉与铺设

Image-2 以用户视频帧为参考生成一张 2048×2048 RGBA 草叶/苔藓图集，两种草叶扇和两种苔藓形态。真正的草叶轮廓、弯曲形态和颜色来自贴图。草皮每簇只有三个交错分段面片，共18三角面；没有逐叶实体建模。苔藓使用8三角面的小幅起伏贴片，主体固定。

本轮布局：1301草簇、122苔藓贴片。苔藓大部分作为草根下的细碎覆盖层，另外四处是小面积点缀。草间距约10.5厘米，草高约19–29厘米，三张交错贴片和随机朝向形成连续覆盖。局部支撑面为小屋顶10.847米、女儿墙顶7.895米；原平台和泊位沿用原功能。空调检修区排除，太阳能板和露台活动面不铺满。

使用 alpha scissor、线性 mipmap 和各向异性采样。草和苔藓均不投射细碎阴影。叶层法线向上柔化；近景保留绘制的叶脉和根部层次，远景收敛细叶颜色反差，降低闪烁。不是普通整面半透明混合，也不是实体草叶。

## 三份独立资产

| AssetID | 稳定复用入口 | 职责 |
|---|---|---|
| SEA-VEG-GRASS-SOFT | godot/scenes/components/vegetation/grass_soft.tscn | 可摆动的草叶贴片簇 |
| SEA-VEG-MOSS-SOFT | godot/scenes/components/vegetation/moss_soft.tscn | 低矮苔藓覆盖 |
| SEA-TEX-VEGETATION-SOFT-ATLAS | godot/assets/textures/vegetation/soft_atlas.png | 共用RGBA色彩/透明图集 |

唯一主记录在 `assets/registry/ledgers/vegetation.json`，通过 `ledger_index.json` 的 vegetation 域路由。几何和贴图分别记录源、优化源或处理过程、哈希、消费者、运行与视觉证据，不把它们重复登进 scenes。

源在 `art_source/vegetation/v002/`。原始 Image-2 图完整保留，`texture_brief.txt` 是生成描述，`texture_production.json` 记录输入帧哈希、四格裁切及处理。处理只做 alpha 精确裁切、254→255归一化和16像素留边，不重画叶片。正式图集也保存在此目录，运行文件是同哈希副本。

本族是用户明确要求的制作例外：UV0 为 `BotanicalUV`，采样 RGBA 植物贴图，替代本族原来的 PaletteUV 纯色色格。建筑、花盆及原有花草的色板规范不受影响。COLOR 继续保存风权重，禁止当作着色乘到贴图上。

## 风和性能

`World/VegetationWind` 唯一写入时间、强度和方向，晴天微风默认0.8。共享 `soft_cards.gdshader` 消费统一风时钟：根固定、顶端渐强，阵风沿世界方向传播，另加小幅叶尖细动；风不更新每簇Transform。暂停/World隐藏冻结，跳日不重抽布局。

`VegetationTurf` 以4米网格分块 MultiMesh；基底苔藓始终保留，细草按屏幕尺寸和滞回分级。Standard保留近景全部密度，Low约65%。每0.35秒最多检查一次；相机没变就跳过重复更新。包围盒覆盖额外0.6米位移。细草无碰撞、导航、交互、玩法状态或岸线职责。

## 调整、增铺与再制作

1. 在 `art_source/vegetation/v002/layout_recipes.json` 修改局部矩形、顶面高度和排除区。
2. 执行 `python3 -X utf8 tools/blender/vegetation/assemble_soft.py`，得到显式的稳定实例布局 `godot/data/vegetation/layouts/solar_cabin.json`。
3. 重开场景或调用 `VegetationTurf.rebuild()`。换其他承载面前先实测顶面，不按海面高度猜位置。
4. 单件复用可直接拖入上表PackedScene。大面积仍用patch；不要为每个区域复制shader和风控制器。

图集再处理入口：`prepare_soft_atlas.py`。几何载体入口：`build_soft_cards.py`，使用Blender后台执行。每件分别保存母版和 `*_optimized.blend`、重开检查并导出无内嵌贴图GLB；源材质绑定图集，可独立打开查看。优化报告如实记录操作，不虚报三角面缩减。

共享材质在 `godot/assets/materials/vegetation/`，参数登记到 `shader_param_contract.json`；调参后同步本基线。以后修改图集、布局、几何或通道时更新版本、哈希和消费者证据，不改既有建筑植物资产来代替草皮制作。

## 验收

所有Godot运行均经 `scripts/run_verification.py`，先隔离用户数据。

```powershell
python3 -X utf8 scripts/run_verification.py vegetation-contract visual-vegetation
python3 -X utf8 scripts/run_verification.py visual-vegetation-performance rooftop-ranch water-layer minimum-loop
```

`vegetation-contract` 检查56株原花草保持、贴图通道、根固定、坏权重拒绝、暂停/显隐、重复重建、道路检修区与动态包围盒。`visual-vegetation` 输出原场景前后、近景、掠视、宏观叶片和90帧真实风动。`visual-vegetation-study` 为不加载玩法脚本的独立材质小样，不能代替正式主场景证据。

GPU计时使用Godot [RenderingServer的viewport计时](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu)，CPU脚本与帧间隔单列；草地通过单项预算不表示整个项目所有硬件都锁60帧。透明裁切与采样方式按[Godot 4.7空间着色器接口](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)实现。真实运行结果、失败历史与证据路径见[本轮记录](../../development/2026-11-05_vegetation_soft_cards.md)。

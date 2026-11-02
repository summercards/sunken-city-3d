# submerged_street · 阳光房水下街景（十栋）

十栋独立纯景观建筑，按用户 2026-11-02 的文字清单制作：断掉的高架桥、破旧公寓楼（L 形＋消防梯）、快餐车、快餐连锁餐厅、高层公寓楼、红绿灯、电线杆和电线、高速公路路牌、施工中的大楼、普通公寓楼。

风格基准是**阳光房海下基座**（`art_source/scenes/bloom_lower_building/v002/`），不是目测配色：先逐面采样基座的全部 22 个网格并按面积累计，得到米白三色 82.3%／深蓝玻璃 7.2%／钢灰 1.0%／暖点缀 2.0%、无近黑；十栋按同一分配。层高 2.6 米、窗台 0.4、窗带 1.0 取自同一份基座实例清单，属登记在案的尺度例外（见 `v001/design_brief.md` 与 SEA-ASSET-R42）。

## 目录

```text
v001/
├─ design_brief.md          设计简报：色彩与比例怎么从底座量出来的
├─ component_plan.json      冻结于建模前的 10 项组件计划（含 AssetID、预算、色角色、破败表达）
├─ submerged_street.blend   母版：独立建筑母版 + 沉没街道_参考布局 + 展示支持
├─ catalog.json             逐栋实测三角面、包络、材质角色
├─ component_instances.json 参考排布（正式摆位由 Godot TSCN 拥有）
├─ export_manifest.json     独立包、优化副本、GLB、保真与哈希
├─ asset_manifest.json      装配记录
├─ component_packages/<key>/  逐栋可单独打开的 .blend 与清单
└─ export/v001/submerged_street_optimized.blend  只做过焊点清理的副本（不减面）
```

## 制作与验收工具

```text
tools/blender/submerged_street/
├─ build.py           生成母版与参考布局（不覆盖既有 Godot 场景）
├─ verify.py          Blender 内自检 + 24 张真实渲染
├─ preview.py         迭代期单栋快看
├─ package_export.py  逐栋独立包、优化副本、GLB、保真比对
└─ register.py        写入 scenes 账本、源索引与运行资源清单
```

运行：

```text
blender --background --factory-startup --python tools/blender/submerged_street/build.py
blender --background --factory-startup --python tools/blender/submerged_street/verify.py
blender --background --factory-startup --python tools/blender/submerged_street/package_export.py
python -X utf8 tools/blender/submerged_street/register.py
python -X utf8 tools/apply_water_layer.py
python -X utf8 scripts/check_feature_contracts.py --sync
```

渲染与报告写到工程外 `sea-work/submerged_street_v001/`（可用 `SEA_WORK_ROOT` 重定向）。

## 边界

- `building_class = underwater`，全子树纯观赏：无碰撞、可走面、泊位、导航障碍、交互、产出、玩法状态、岸线来源。
- 无自发光材质：废弃街景夜间不得自发亮。
- 公共色板只有一份，位于 `art_source/shared/palettes/sea_cabin_muted_8x8_512.png`，不复制到本套件。
- Godot 摆位、碰撞审查、水下真实渲染、双拱商标与参考授权、用户美术验收均为 pending。

# 2026-11-02 水下街景十栋（submerged_street v001）

按用户要求，在阳光房周围水下新增十栋独立纯景观建筑，全部在 Blender 内制作并完成自检。色彩与比例以**阳光房海下基座**为唯一风格基准，不另起一套配色。

交付所有者：SEA-ASSET-R42（本轮新增条款）／SEA-WORLD 的正式摆位另计。资产主记录写入 `assets/registry/ledgers/scenes.json`，`building_class = underwater`。

## 一、风格基准怎么定的（不是目测）

打开 `art_source/scenes/bloom_lower_building/v002/bloom_lower_building.blend`，对 22 个网格的**每一个面**读 `PaletteUV` 中心，映射到 `sea_cabin_muted_8x8_512.png` 的 8×8 色格，按面面积累计。原始日志 `sea-work/submerged_street_v001/base_palette_probe.log`。

| 色格 | 名称 | 占基座可见面积 |
|---|---|---:|
| r0c4 | white | 50.3% |
| r0c2 | plaster | 25.9% |
| r0c0 | cream | 6.1% |
| r2c5 | solar | 3.7% |
| r2c2 | aqua | 3.1% |
| 其余（叶绿、珊瑚、钢灰等） | — | ≤4.7% 各自 |

结论：奶油米白三色合计 **82.3%** 是主色，深蓝玻璃系 **7.2%**，钢灰 **1.0%**，暖点缀 **2.0%**，没有近黑、没有高饱和撞色。十栋按同一比例分配。

比例从同一份实例清单量取：楼板 Z 在 0 / 1.72 / 3.44 / 5.16 / 6.88 / 8.60 / 10.32，屋面 12.32 → 层高 1.72 源单位、7 层；运行侧按 2.5/1.5/1.5 适配后为 **层高 2.6 米**，窗台 0.4、窗带 1.0、板厚 0.2。

这条尺度与 `sea-scene-component-authoring` 里 5.1 米／0.5 米柱的阳光房水上默认值不同。这是登记在案的**尺度例外**（用户明确要求"按底座的比例风格"），不修改 SKILL 默认值，也不影响其他套件。

## 二、十栋与实测面数

| # | 建筑 | AssetID 尾段 | 三角面 | 预算 |
|---:|---|---|---:|---:|
| 1 | 断掉的高架桥 | VIADUCT | 1544 | 2000 |
| 2 | 破旧公寓楼（L 形＋消防梯） | L-APARTMENT | 1676 | 2200 |
| 3 | 快餐车 | FOOD-TRUCK | 960 | 1000 |
| 4 | 快餐连锁餐厅（双拱招牌） | QUICK-SERVE | 1048 | 1600 |
| 5 | 高层公寓楼 | HIGHRISE | 1214 | 2000 |
| 6 | 红绿灯 | TRAFFIC-LIGHT | 634 | 700 |
| 7 | 电线杆和电线 | UTILITY-POLES | 810 | 900 |
| 8 | 高速公路路牌 | HIGHWAY-SIGN | 596 | 900 |
| 9 | 施工中的大楼 | CONSTRUCTION | 1882 | 2400 |
| 10 | 普通公寓楼 | WALKUP | 1332 | 1800 |

合计 **11696 三角面**。预算不是估算值：`build.py` 在每个建筑 join 之后读取求值后的 loop triangles，超预算直接断言失败（本轮真的挡住了 5 次）。

## 三、源级自检（Blender 内，`verify.py`）

保存后重新打开母版，逐项断言：

- 10 个独立 Collection，各自只有一个 join 后的对象；Collection `instance_offset` 为零，对象与网格变换恒等。
- **逐面 PaletteUV**：每个面是单一色格、UV 岛有面积、全部 loop 落在色格内 8 像素安全区；活动层与渲染层都是 `PaletteUV`；只有一层 UV。
- 材质只有 `SEA_Matte` / `SEA_Metal` / `SEA_Gloss` 三角色，无 `.001` 副本、无自发光；色板外链唯一 PNG、`Closest` 插值、不打包。
- 三角面逐栋 ≤ 预算，且与 `catalog.json` 一致。
- 原点在**真实包络**的底心（含檐口、招牌等外挑件），底面 z=0。
- 纯观赏职责：`building_class=underwater`、`collision=none`、`interactive=False`，无碰撞／导航修改器。
- **色调按亮度分档**，不按色名硬编码：象牙（亮度 ≥0.70）、中间调、近黑（<0.34）、玻璃、暖色、绿。整包象牙 76.4%、近黑 3.6%，与底座的 82.3%／0% 同族。
- 两项**从实际缺陷里长出来的检查**：
  - 单面面积 >2 m² 且亮度 <0.34 判为"近黑大面"（曾把整条深蓝窗带读成黑板）。
  - 共面重合面组检测（曾让高架桥断口渲染出黑色缝隙）。

结果：**0 失败**，`sea-work/submerged_street_v001/selfcheck_report.json`。

## 四、渲染

24 张 Cycles 渲染，同一套三点日光、同一曝光，逐栋隔离（其余建筑 hide_render），外加街区四视图：

- 每栋 `*_three_quarter.png`、`*_top.png`。
- `street_overview.png`（东南俯视）、`street_plan.png`（正俯）、`street_low.png`（街面人视，透视 30mm）、`street_reverse.png`（反向）。

街面视图加了"主体点在画面内"的 NDC 断言——第一版透视相机取景偏离，渲染出来是一张空背景图，靠这条断言抓到的。

## 五、公开包、GLB 与保真

`package_export.py` 逐栋重开母版 → 另存独立包 → **再打开独立包**复核（场景数、对象数、面数、UV、材质）→ 从独立包导出 GLB。

- 10 个独立 `.blend` 与 10 个 GLB，GLB 无内嵌图片、`PaletteUV` 作为 `TEXCOORD_0`、三角面与账本一致。
- 另存优化副本 `export/v001/submerged_street_optimized.blend`：只做重复点合并、退化边清理、孤立点清理、法线复核。**不减面，三角面前后相同**，不当成减面成果。
- 保真：同机位渲染源与优化版，正面/俯视平均 RGB 差最大 **0.0013/255**；母版与公共色板哈希前后不变。

## 六、本轮自己改掉的问题（逐条，含原因）

| 现象 | 原因 | 处理 |
|---|---|---|
| 断口渲染出黑色缝隙 | 断口另加的第二块盖面与原切面**共面冲突**（z-fighting） | 改成外凸碎块，并把"共面重合面组"写成检查 |
| 深蓝窗带像黑板 | 二层整条 10.2 米窗带是单个大面 | 拆成 5 段窗＋窗梃；新增近黑大面检查 |
| 高速路牌断角是黑槽 | 断角用两块错位薄板拼，中间漏缝 | 改成带缺口的**整体实体板**（新增 `plate()` 轮廓挤出） |
| 路牌面板整块变白 | 牌框板压在面板同层且更靠前 | 牌框移到面板背后，只露边框 |
| 快餐车雨棚悬空成斜片 | 五片棚布共用同一中心点，只有一块在车上 | 沿棚杆均匀分布，加横杆与斜撑 |
| 电线杆接线箱吊在空中 | 入户线端点算错，箱子凭空悬浮 | 箱体贴杆加固定带，引下线沿杆走 |
| 电线端点离开绝缘子 | 横担与电线同轴，绝缘子不在线上 | 横担转 90° 跨街，电线沿街，两端落在绝缘子上 |
| 施工场地弃料漂离楼体 | 弃料坐标超出女儿墙外 7 米 | 收回到围挡内侧 |
| 麦当劳双拱悬在立面外 | 招牌立在芒萨尔檐口前沿 | 移到屋面平台，加两条支腿 |

## 七、账本与门禁

- `scenes.json` 新增 **11 行**（10 栋 + 1 条 `reference_only` 装配记录），`building_class=underwater`，`stage=source_verified_runtime_integration_pending`，`license` 记参考与商标权属 pending（双拱造型保留）。
- 派生源索引、运行资源清单已同步；`tools/apply_water_layer.py` 显示 11 行更新、两份视图重建。
- `python -X utf8 scripts/check_feature_contracts.py --sync` → **PASS：39 features / 637 source assets / 527 runtime resources / 0 issues**；无参数复核同为 0 issues。

## 八、明确的未完成项

- **Godot 接入未做**：没有新增 PackedScene、没有放进 `main.tscn`，也没有碰撞／岸线派生审查。`component_instances.json` 只是可追溯的参考排布，正式摆位仍由 TSCN 拥有。
- **水下渲染未验**：源级棚拍是深蓝底三点日光，不是游戏水下着色器与焦散；水面透视观感需接入后另测。
- **商业授权 pending**：本轮无附件参考图，形状来自用户文字清单与底座实测；双拱标志属商标范畴，未做法律审核。
- **用户美术验收 pending**：十栋的体型、破败程度与色彩比例需要用户拍板，我这边只是按实测基准做到自洽。

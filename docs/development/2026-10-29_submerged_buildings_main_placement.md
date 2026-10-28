# 水下景观六栋：贴图为什么会掉、摆位为什么搬到 main

功能：SEA-WORLD-R10 · SEA-ASSET-R29 · 主文档 [功能表](../../GDD_V1.0.md#sea-world)

承接 Codex 会话中断前最后一句：「先排查贴图变白的原因，并保留你已经调整的位置，把六栋景观建筑分别作为独立实例放进 main 场景。」

## 一、贴图变白的根因

六栋建筑的 `.tscn` 里**没有一条材质覆盖**。颜色全靠 `src/world/submerged_building.gd` 的 `@tool _ready()` 在运行期 `set_surface_override_material()` 补上；GLB 自身只有 `SEA_Matte` 一个材质，`baseColorFactor = [0.8, 0.8, 0.8]`、`textures = 0`、`images = None`。

也就是说：**脚本没跑，模型就是那块 0.8 灰的底材**。以下任一情况都会命中——

- 编辑器里重新实例化节点、切换「可编辑子节点」后新建的副本；
- 脚本报错被跳过（并行任务改坏过一次类型声明，同一类故障）；
- 节点被搬到新父级、`_ready()` 尚未执行的那一帧被截图。

这不是「贴图文件丢了」。本轮实测调色板全员完好：

| 检查 | 结果 |
|---|---|
| `sea_cozy_8x8_512.png` | 512×512，像素 `#fff6df/#efb467/#5db8d1` 与源一致 |
| `sea_cabin_timber_8x8_512.png` | 512×512，S3TC 解压后 `#e1dbb5`，与源 `#e0dab6` 误差 1 |
| 六栋 GLB | `textures=0`、`images=None`，只有 `SEA_Matte` 灰底 |

**同一类隐患还在阳光房身上，且规模更大**：`scenes/components/solar_cabin/` 下 57 个组件全部用 `sunny_palette_binding.gd` 运行期上色，序列化覆盖数为 **0**。这一轮没有动它（改动面 57 个正式预制体，超出本次请求），但如果哪天阳光房又整片发白，先看这里，不是贴图坏了。

## 二、本轮改了什么

| 层 | 变化 |
|---|---|
| 材质 | 六栋 `buildings/*.tscn` 各加一条 `[ext_resource type="Material" ... matte.tres]`，并在 `Visual` 节点写 `surface_material_override/0`。颜色从此是场景数据，不再取决于脚本有没有跑 |
| 摆放 | `main.tscn` 的 `World` 下新建 `UnderwaterScenery`，六栋各自一个独立实例（位置从原分组场景原样搬来，未改坐标），可在完整场景里逐个选中对照调整 |
| 收口 | `zone1_home_harbor.tscn` 删除 `UnderwaterScenery` 实例与它的 `ext_resource`；`neighborhood.tscn` 降级为**仅参考**（`metadata/status = "reference_only_not_instanced"`），不再被任何正式场景实例化 |
| 断言 | 测试新增 3 条：材质必须序列化在预制体里（读 `PackedScene.get_state()`，不实例化）、摆放父级必须是 `World`、zone1 不得再自带一份 |

为什么不让两份场景并存：两份坐标就是两份真相，改一边另一边静默失效。宁可留一个明确写着「仅参考」的文件，也不留一个看起来还是权威的旧入口。

## 三、验证

| 项 | 运行目录 | 结果 |
|---|---|---|
| 六栋专项（headless） | `20261029-005022-main-placement-00fb45` | exit 0，`95 checks, 0 failures` |
| 六栋专项（真实渲染） | `20261029-005101-main-placement-visual-7a29f6` | exit 0，`95 checks, 0 failures`，截图 6 张 |
| 契约与结构 | `python3 scripts/check_feature_contracts.py --sync` 与无参 | `35 features, 459 source assets, 387 runtime resource hashes; 0 issues` |

改动前的基线：`20261029-003535-resume-before-69b714`（89 项通过），用于确认「搬位前后画面等价」——两张 `submerged-geometry-review.png` 逐像素同源，说明位置没有被动过。

渲染截图：`20261029-005101-main-placement-visual-7a29f6/project/outputs/submerged-{surface-reference,geometry-review,surface-top,night}.png`。

## 四、现在怎么调这六栋

1. 打开 `godot/scenes/main.tscn`，展开 `World → UnderwaterScenery`。
2. 六个子节点就是六栋，点谁选谁，右侧直接改 `position`；想换角度把实例的 `rotation` 加上即可。
3. 保存后改动落在 `main.tscn`，不会再被 `neighborhood.tscn` 覆盖。
4. 改完跑 `python3 scripts/run_verification.py visual-submerged-neighborhood` 复查：屋顶必须仍在海面以下、彼此不相交、与阳光房基座留有水道。

## 五、新增或移动一栋要同步的六处

`buildings/<key>.tscn`（含材质覆盖）→ `main.tscn` 的 `UnderwaterScenery` 下加一个实例 → `assets/registry/ledgers/scenes.json` 一条主记录（`runtime_instances` 写 `World/UnderwaterScenery/<key>`、`prefab_sha256` 重算）→ `runtime_resource_inventory.json` 一条 → `crops` 无关，但 `submerged-neighborhood` 测试的 `KEYS` 要加 → 跑 `check_feature_contracts.py --sync`。缺任一处，专项或结构检查会红。

## 六、未执行与保留

- 阳光房 57 个组件的材质序列化未做（见第一节），需要单独一轮，会触及正式预制体。
- 源级「保存后重开 + 四视图渲染」未重跑，资产阶段仍是 `source_runtime_verified_provenance_pending`，参考图商业授权待确认。
- 本轮没有改任何一栋的坐标、旋转、缩放，只换了摆放的所有者和材质来源。
- 用户若已在编辑器里手改过位置但未保存，这次改动不会带回那些未保存的编辑。

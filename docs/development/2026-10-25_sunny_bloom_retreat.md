# SEA-ASSET-R13 · 阳光繁花小屋制作与比例修订

本任务从 2026-10-24 的单张蓝底附件开始。用户明确要求不参考其他工作的错误内容，因此新建 `sunny_bloom_retreat`，几何和布局独立编写，仅沿用项目公共色板与制作契约。初始阶段曾查看未登记候选；用户纠正后已停止该方向，未载入该候选模型或组件用于本次制作。

当前源：`art_source/scenes/sunny_bloom_retreat/v002/sunny_bloom_retreat.blend`。本次自身的 v001 原样保留。参考 PNG SHA-256：`5256abd23999c8a6b8c34cbfd425ccce2f72c74ecfc53a39d8606beb0d1f3545`。

## 用户修订与具体结果

- 比例偏高：建筑与陈设围绕完成地坪 Z=0.68m 将竖向比例收紧到 0.92；植物保持母版厚度，调整附着点高度。
- “后方墙柱”经用户确认两处都补：新增白色墙柱组件，主房后侧 3 根、其他墙角和上层后角有支撑；补后侧露台矮墙。遮阳棚保留 4 木柱，将右柱移至 X=-0.57m，后横梁接通，避免埋入上层墙体。
- 前方小空间：侧墙进深从 1.33m 改到 1.73m，补后封墙和窗顶至斜屋面的白色封墙，使用实际窗洞和玻璃，内部有木桌、软垫与盆栽。
- 木板与码头：平台使用 216 块 0.595×0.395m 窄木板；桥两列中心 X=1.15/2.38m，6 排共 12 块；桥与平台几何间距 0.0125m。冷藏箱后退至 Y=-3.25m，避免贴桥口。
- 建筑结构、固定陈设与花草分集合；植物没有焊接到盆器、墙体或屋面；发光几何独立。

## 交付与源级实测

45 类组件 / 490 个 Collection Instance，其中花草 103 个实例。45 个独立组件包全部保存重开；组件底部中心、集合偏移为零、网格和根恒等变换通过。40211 个母版面均有非零面积 PaletteUV 小岛，位于同一色格安全区；共用 PNG 外链、Closest 采样、四材质角色通过。

依赖图展开实例后 352554 多边形 / 662504 三角面。当前没有用户指定硬面数上限，未宣称低面数或游戏性能通过。公共色板 SHA-256 `6906f7284161e58b5c1733fa00591d309ce8d5b5aac7e458e9679513bd4e50a1`，未修改色板文件。

专项检查：主房后柱 3 根、棚柱 4 根且与上层房体 XY 包络无重叠、铺板 216 块、桥板 12 块、桥端对接间隙及冷藏箱桥口避让均通过。此为源级几何检查，不替代 Godot 碰撞/导航。

## 验证记录

使用 Blender 5.2.2 LTS 的实际 bpy 建模与 Cycles 渲染。命令带 `--python-exit-code 1`，避免 Python 失败被 Blender 正常退出掩盖。初次开发中对象合并后的失效引用已修复；最终保存源重新运行验证，历史结果不作为当前文件证据。

- 构建：退出码 0；日志 `sea-work/sunny_bloom_retreat_v002/build.log`。
- 源级重开与渲染：退出码 0；日志 `sea-work/sunny_bloom_retreat_v002/verify.log`。
- 实际渲染：全景、建筑单独、近景、俯视及后侧结构视图，写工程外 `sea-work/sunny_bloom_retreat_v002/previews/`。
- 预期故障：无。Blender 6.0 API 的弃用提示与当前 Blender 5.2 执行失败分开记录。
- 未执行：Godot 导入、运行、碰撞、导航、游戏性能及商业授权核验。未修改正式 TSCN 或游戏资源。Godot 验证后续必须使用 `scripts/run_verification.py`。
- 视觉验收：本轮逐视图核对结构与布局，不宣称像素级一致或用户美术验收通过。

场景分账本通过 `assets/registry/ledger_index.json` 路由，仅新增本套 `SEA-SCENE-SBR-` 记录，派生索引从分账本读取；不重算或覆盖其他工作的资产哈希。

Final contract synchronization and check: both exit 0. The first metadata check exposed a missing asset_ledger manifest link in this new kit; fixed only this kit and reran both checks successfully. Logs: sea-work/sunny_bloom_retreat_v002/contracts_sync.log and contracts_check.log.

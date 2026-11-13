# 2026-11-09 本机（Apple M1）帧率归因：绘制批次才是瓶颈

[主文档](../../GDD_V1.0.md) · [上一轮帧诊断](2026-11-07_frame_diagnosis.md) · [NPC 性能修复](2026-11-07_npc_performance_fix.md)

## 1. 结论

用户报告"目前游戏很卡"。本轮在本机（Apple M1、8 核 GPU、Metal 3.2、Forward+、Godot 4.7.2）实测主场景 **8.1–8.7 FPS**，帧时 112–122 ms，绘制批次 2735–2744。

**不是脚本 bug，也不是某一项特效。** 三组对照：

| 对照 | FPS | 帧时 p50 | draws | 相对基线 |
|---|---:|---:|---:|---:|
| 基线 | 8.64 | 115.8 ms | 2744 | — |
| 关闭全部节点 `_process` | 11.15 | 93.1 ms | — | +28% |
| 只关主场景 `_process` | 8.49 | 115.3 ms | — | ±0% |
| 关方向光阴影 | 9.76 | 103.0 ms | 1973 | +13% |
| 关 SSAO | 8.85 | 114.4 ms | 2736 | +2% |
| 关 MSAA（原 4×） | 9.91 | 105.5 ms | 2731 | +15% |
| 3D 分辨率缩放到 0.5 | 11.03 | 96.7 ms | 2730 | +28% |
| 关去色带 | 8.43 | 120.8 ms | 2731 | 0 |
| **以上全关 + 半分辨率** | **16.95** | 56.4 ms | 1965 | +96% |

把阴影、SSAO、MSAA、去色带全部关掉、渲染像素只剩四分之一，仍然只有 17 FPS。说明上限被**每帧绘制次数**锁死：本次基线 2744 个 draw call，其中方向光阴影 pass 独占 771 个。

上一轮（2026-11-07）在 Windows + RTX 4060 Ti 上同样 3186 draws 可以跑 59.9 FPS，因此这不是回归，是设备差异：M1 的每 draw 提交成本远高于桌面独显，而这个场景是靠大量独立小件堆出来的。

## 2. 绘制来源

`main.tscn` 里 `World` 下各块实例化的独立小件（每个 1–2 个 surface，阴影 pass 再翻一倍）：

| 场景 | 节点数 | 主要构成 |
|---|---:|---|
| `rooftop_ranch.tscn` | 760 | tuft×160、grass×90、window×51、window_broken×48、window_cracked×45、stone×45、rail×43、parapet×37、balcony×36 |
| `floating_shop.tscn` | 381 | gift×63、bottle×60、rail_post×41、rail_bar×38、awning×48 |
| `sunken_city.tscn` | 388 | rubble_cluster×59、plaza_tile×48、moss_patch×36、street_intact×28、kelp_clump×22 |

全部挂在各自 `Models` 节点下，是散件而不是批次。植被的 `VegetationTurf` 走 `layout.json` 分块 MultiMesh（`scene_owned_assets` 只排除 `mound_soft`），合批机制本身是现成的；这三个场景的 `Models` 没有走这条路。

`zones/*.tscn` 有 `StaticBatch`（`src/world/zone_batch.gd` + `assets/zones/*/bake.json`），但 zone1 显式 `enabled = false`，且 bake 目录是 10-19 的旧产物，已与当前手摆位置脱节。

## 3. 另外两条叠加因素

- **Retina 2×**：`project.godot` 未设 `display/window/dpi/allow_hidpi`，窗口 1600×1000 逻辑像素在 M1 上实际按 3200×2000 渲染（实测 `screen_scale=2.0`）。半分辨率只回收 28%，说明填充率不是主因，但这部分仍应回收。
- **阴影**：`directional_shadow/size=8192`、`directional_shadow_max_distance=220`、`msaa_3d=2`（4×）。8192 的阴影贴图每帧要把阴影投射体重画一遍，实测占 771 draws。

## 4. 建议顺序

1. **先回收便宜的**：`msaa_3d` 4×→关、`directional_shadow/size` 8192→4096、`max_distance` 220→90、小装饰 `cast_shadow=OFF`、3D 缩放 0.75。按上表叠加估计落在 12–15 FPS，仍然不算能玩，但可作为中间档。
2. **治本：把 `Models` 下的小件合批**。同一网格 + 同一材质的散件（tuft/grass/window/stone/tile/gift…）改成 MultiMesh 或并入 `zone_batch` 的 bake 流程，把 draw 从 2744 压到 800 以内；按 16.6 µs/draw 的实测边际成本，这是唯一能把帧时降到 30 ms 量级的路径。
3. 远景块按相机距离整块隐藏（`Zone2/Zone5` 目前在主场景常驻）。

## 5. 工具与复验

新增 `godot/tools/profile_frame_render_budget.gd`，在 `scripts/run_verification.py` 注册为 `visual-frame-budget`；它打印 viewport/window/screen_scale/msaa/shadow/ssao/glow 现状后逐项开关测量，测完恢复原状，不改工程配置。

```bash
python scripts/run_verification.py visual-frame-diagnosis visual-frame-budget --label m1-render-budget
```

证据：`sea-work/verification/20261109-105303-m1-perf-check-27c4bd`（`visual-frame-diagnosis`）、`20261109-105518-m1-perf-subsystems-63191f`（`visual-frame-subsystems`）、`20261109-105648-m1-render-budget-a38f75`（`visual-frame-budget`），三项均 exit 0/PASS。

未覆盖：玩家真实存档状态、水下与室内视角、发行包、其他设备。本轮只做归因，未改玩法、未降画质、未改场景结构。

## 6. 更正（同日晚）

本文第 1、4 节把瓶颈判为「每帧绘制次数」并据此建议合批，**该判断已被推翻**，原文保留不删。同日改用正常游戏循环（`--print-fps`）复测：

- 同一隔离工程，正常循环是 16 FPS，本文的 `--script` 探针测得 8.6 FPS，绝对值不可比；探针只可用于看单项趋势。
- 把 rooftop_ranch / floating_shop / sunken_city 三块共 1529 件散件整块隐藏，帧率 16 → 15，**合批没有收益**（它们在 31° 视锥外）。
- 隐藏 `World/Water` 一项就从 16 涨到 27；关 4× MSAA 到 20；分辨率与帧率近似反比。

真因是填充率/带宽（全屏透明水面 + MSAA），不是绘制批次。新数据与结论见 [填充率归因](2026-11-09_fillrate_research.md)。第 4 节的「先做 A、再做 B 合批」不成立，请以新文档的第 4 节为准。


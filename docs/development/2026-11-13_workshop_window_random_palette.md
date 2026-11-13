# 老王场景工坊：窗型、植物随机幅度与64格配色

FeatureID：SEA-WORKSHOP。承接用户2026-11-12 23:22要求。

## 1. 窗型与固定窗

固定窗此前只显示配方变化，实际玻璃仍使用旧的20mm/墙厚中心路径，导致调玻璃厚度、窗框退入等参数不明显。本轮修正 `shell_window_geometry._glass()`：

- 有 architecture 窗配置时，玻璃真实使用 `settings.glass_thickness` 和 `settings.recess`。
- 旧无 architecture 配方继续使用兼容默认路径。
- fixed 的框宽、框深、recess、玻璃厚度、窗沿都进入真实 Mesh。
- `casement_left` 与 `casement_right` 使用相反侧铰链；`awning` 使用顶部横向铰链；fixed 保持零角度。
- 保留净洞、框、楼板、相邻窗和扫掠包络拒绝，不静默缩窗。

证据：

- `/Users/zyq/work/sea-work/verification/20261112-234346-window-core-verified-b86644/report.json`
- workshop-architecture、workshop-shell 均 exit 0 / passed=true。
- 中间固定窗包络测试曾失败，修复后保留历史报告，不覆盖旧证据。

## 2. 植物/树枝随机与幅度

配方新增：

- `vegetation_random_enabled`
- `vegetation_variation`，0..1
- `vegetation_seed`

开启随机时，生成后按稳定 `vegetation_seed + slot_id` 改变植物实例：

- 平面位置：最多约 ±0.25m × 幅度
- 等比尺寸：最多约 ±20% × 幅度
- 绕 Y 旋转：最多 ±180° × 幅度

关闭随机时，seed不影响姿态；密度和small/medium/large生长权重仍然有效。锁定植物位置不漂移，藤蔓仍遵守檐边限制，随机不进入玩法全局随机流。

编辑器植物页提供随机开关、随机幅度、植物种子、密度和三档生长权重滑块，实时预览走同一Session事务。

证据：

- `/Users/zyq/work/sea-work/verification/20261113-001201-vegetation-core-final-4b8213/report.json`：rules/deep exit0。
- `/Users/zyq/work/sea-work/verification/20261113-001156-vegetation-upgrade-final-81e1a6/report.json`：真实 editor-upgrade exit0，内部667/0。
- 中间首轮超时、绘制时序失败保留历史，最终批未复用失败结论。

## 3. 8×8棋盘格64色

`architecture.palette` 支持：

- `color_mode=manual/auto`
- `color_seed`
- `color_cell=[row,column]`，0..7
- `materials`：SEA_Matte、SEA_Metal、SEA_Gloss、SEA_Emission
- `slots`：wall、pillar、band、frame、glass、plant、slab、roof

覆盖优先级：slot > material role > global。auto按稳定FNV散列取64格；manual直接取指定格。颜色只改PaletteUV/UV2，不改共享ShaderMaterial、shader或PNG，也不复制材质。外部prefab不擅自重着色。

固定窗 frame/glass、结构并集、植物Mesh均经过真实UV和保存重载验证；结构并集算法未改。

编辑器“配色”页提供：

- 材质球/部件目标
- auto/manual模式
- 颜色种子HSlider
- 8列64格GridContainer
- 自动落点高亮

证据：

- `/Users/zyq/work/sea-work/verification/20261113-003336-palette-rules-final-218b50/report.json`：694/0。
- `/Users/zyq/work/sea-work/verification/20261113-003301-palette-geometry-final-f6fc38/report.json`：workshop-union、workshop-shell均exit0。
- `/Users/zyq/work/sea-work/verification/20261113-003157-palette-editor-final-4770b5/report.json`：真实编辑器exit0，含64格、自动/手动、UV/hash、重载和UI断言。

## 当前边界

- 颜色变化是PaletteUV选格，不是贴图绘制、渐变、老化纹理或每实例独立材质参数。
- 随机幅度是稳定程序扰动，不是自然枝条拓扑重建；复杂根系、墙面刷苔和真实树种枝干仍不属于本轮。
- 完整美术终验、性能、插件跨进程恢复、正式世界接入和旧全量Main集成仍未签。
- 全库contracts仍有既有哈希漂移、跨机路径断链、SEA-ASSET行集和派生索引问题；本轮不批量刷新未知哈希。

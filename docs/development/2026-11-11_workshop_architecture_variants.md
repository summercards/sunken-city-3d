# 2026-11-11 楼房工坊 · 建筑结构多变体与窗屋顶架构

[主文档中控](../../GDD_V1.0.md#sea-workshop) · [功能设计](../features/workshop/spec.md) · [独立账本](../features/workshop/ledger.md) · [资产规格](../features/asset/spec.md#2026-11-10-参数楼房工坊候选资产登记规则) · [连续实体开发记录](2026-11-11_workshop_continuous_shell.md)

## 记录范围

本轮只维护文档事实，不改代码；代码路径和验证结果均来自已读工程文件与实际日志。GDD 导航将 SEA-WORKSHOP 定位为“编辑器楼房工坊与独立制作资产（运行版保留）”，其依赖 SEA-ASSET、SEA-WORLD、SEA-AMBIENT。候选资产必须继续遵循 SEA-ASSET-R68/R68a：候选导出不自动成为正式主场景资产，原生参数化来源不得伪造为 Blender/GLB/02b 生产链。

本轮新增条款为 SEA-WORKSHOP-R23–R27，按独立账本逐行承接。登记头保持 `status: partial`；不把架构专项通过扩写成完整编辑器、视觉、美术、性能、导航、建筑承载或防护规范通过。

## 实现结构

### 可选 architecture schema

`architecture_config.gd` 定义 schema version 1 的可选增量配置，并提供默认值、规范化、字段/范围/有限数值校验及窗口/屋顶边解析。支持矩形、L、T、U 轮廓；`wing_x`、`wing_z`、`setback_start`、`setback_step` 进入连续壳的实际 footprint 与逐层 contour。上层 contour 收缩时，`shell_geometry.gd` 为下层接口保留结构板 surface，并把上层墙外轮廓作为 terrace 的邻接轮廓；不填实 L/T/U 的缺口。

`Recipe.defaults()` 不主动加入 architecture，因此缺字段的旧配方继续按旧 modular_v1 解释并保持旧 fingerprint；`Recipe.authoring_defaults()` 才加入 `Config.defaults()`，新建配方继续使用 shell_v2、干净无损且无默认植物。`recipe.gd` 明确拒绝旧 modular 配方中的非默认 architecture，不能静默忽略复杂建筑配置。

### 窗构造

`Config.window_settings()` 的有效值从基础窗参数和 architecture.window 合成，随后按 floor、facade、single 层级覆盖；局部稀疏字段不补写成其他层级。窗口支持 `fixed`、`casement_left`、`casement_right`、`awning`，活动开角限制为0..80度，fixed 的开角必须为0；框宽/深、玻璃厚度、recess、窗沿启用及窗沿 projection/thickness/extension 进入实际生成。

`enabled=false` 跳过该窗的洞口附件并由墙壳封回实墙，但 editor 保留 opening id 的缓存/选择恢复路径；重新启用后可恢复。同一个单窗应用只写 `architecture.window_overrides[opening_id]`，不写 global。编辑器提供 global、floor、facade、single 四档范围，存在未应用输入时阻止切换；清除当前范围覆盖后恢复继承。

`shell_window_geometry.gd` 对活动扇和玻璃求完整开合扫掠包络，核对开间、楼板、洞口/墙厚安全区、窗沿及相邻 opening 的间隙与重叠。非法尺寸、装配间隙不足、穿墙、窗沿冲突或相邻包络碰撞均原子拒绝；实现没有 silent clamp 或静默缩净洞。成功结果包含实际活动扇、玻璃实体、reveal、闭合框和窗沿几何。

### 屋顶边界

`roof_edge_geometry.gd` 支持 `none`、`parapet`、`railing`、`mixed`。女儿墙、压顶和栏杆沿真实 surface 轮廓内收；存在上层墙轮廓时，仅对外露边界生成附属结构，避免把每个 terrace 自动复制成 roof_main 的边界。

`mixed` 中女儿墙先生成，栏杆立在压顶上方；posts、rails、pickets 使用独立几何，pickets 与 posts 保持3mm clearance。配置支持围护总高、墙厚、压顶厚度/外挑、立柱间距、竖杆节距和杆宽。端部 `corner_end_cut=0.1m` 只留下角部间隔，不构成完整 guardrail safety；代码 quality 也明确不签建筑承载或人群防护规范。

`gap_center` / `gap_width` 的 edge override 只在 `surface_id == roof_main` 时合并。gap 通过边长、两端各0.15m margin及中心比例校验；跨边端、越角、未知或无效 gap 拒绝而不是 clip。边选项按真实轮廓动态提供4/6/8条边。

## 编辑器接线边界

`editor_screen.gd` 已接入建筑架构、窗构造和屋顶边界控件：

- 结构形态：rectangle / L / T / U；翼部比例与逐层退台。
- 窗范围：global / floor / facade / single；窗启用、窗型、开角、框、玻璃、recess、窗沿和尺寸。
- 屋顶：none / parapet / railing / mixed；总高、墙厚、压顶、立柱、竖杆和杆宽；动态边及边 gap 覆盖。
- 各范围均有应用和清除入口；清除后恢复继承，未应用的局部输入不会被切范围吞掉。

`editor_scope` 仅表示编辑器配置范围，不代表真实 editor 本轮已经通过。连续生成仍由 `shell_geometry.gd` 和 `shell_generator.gd` 承接，失败时保留上一份成功配方、catalog、历史和预览。

## 已读实际证据

已读取：

- `D:/projects/sea-work/verification/20261111-143300-architecture-resume-regression-6e8b10/report.json`
  - `workshop-architecture`：`exit_code=0`、`passed=true`，日志为 **135 checks / 0 failures**。
  - 同批 `workshop-shell`：`exit_code=0`、`passed=true`，日志为 **716 checks / 0 failures**。
  - 同批 `workshop-rules`：日志为 **24 checks / 0 failures**。
  - 同批 `workshop-deep`：日志为 **41 checks / 0 failures**。
  - 这些是架构/连续壳/规则/深度专项证据，不代签真实 editor 交互、视觉、美术、性能、导航或安全规范。
- `D:/projects/sea-work/building_workshop/architecture_v001/editor_interaction.log`
  - 当前实际批次记录 `editor-workshop FAIL exit=1`，**1421 checks / 7 failures**。
  - 日志已记录 architecture samples 及 parapet、railing、window detail 三类截图捕获，但截图生成不等于目视通过。
  - 该 editor 批次不签通过；先前 editor_resume 的 UI 缩进 parse error 已由主线程修复，但本记录不把修复前后混写成通过。

## 候选交付状态

本轮目标是每栋楼静态保存五件 candidate bundle，并记录源 hash；当前尚未读到由 `tools/workshop/finalize_architecture_delivery.py` 生成的五样楼交付结果和 delivery report，因此只记录为待生成/待回填，不填写猜测的 building_id、路径、hash、面数或截图结论。

候选仍不是正式 registry 主记录；当前不新增正式 AssetID，不自动挂入 Main，不签正式世界摆位、导航或运行接入。正式登记仍由 SEA-ASSET 唯一路由负责。

## 未签边界

- 本轮未签完整 professional 美术终验、性能、复杂根系/墙面苔、楼梯导航、全楼可达、正式世界接入。
- 不签建筑承载、受力计算、土木结构安全或人群防护规范；“结构严谨”只指几何、接合、洞口、轮廓和模型组织。
- 不把 `corner_end_cut=0.1m` 的栏杆端部间隔写成完整护栏安全；不把 roof_main edge gap 自动复用为每个 terrace 的安全围护。
- 不把当前 editor 1421/7 失败批次、待生成五栋候选或待生成 delivery report 写成通过。

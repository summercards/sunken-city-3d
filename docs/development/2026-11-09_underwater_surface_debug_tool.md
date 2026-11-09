# 2026-11-09 P键水下海面调试工具

[主文档中控](../../GDD_V1.0.md#sea-ocean) · [OCEAN规格](../features/ocean/spec.md) · [OCEAN账本](../features/ocean/ledger.md) · [模块契约](../architecture/module_contracts.md)

## 1. 用户目标

用户要求：在 P 键调试工具中增加一套专门用于水下海面效果的工具，把水下海面的数值全部放进去，调试完成后可以保存。

现有 P 键 `ColorGradePanel` 只属于海面 Main；潜水时 Main 会被 `DiveSession` 脱树，旧图的水面还是 `UwDeco` 动态创建。因此不能把水下参数直接塞进水上 `water.cfg`，也不能让脱树后的海面面板偷偷成为第二个水下状态所有者。

## 2. 实施边界

- 新增 `UnderwaterSurfaceDebug`，由 `DiveSession` 创建一个唯一实例。
- 潜水状态下 P 打开，Esc/P 关闭；关闭后不保留模态拦截。
- 家园地图暴露 `sunroom_region._surface_material`；旧九图暴露 `UwDeco._ceiling.material_override`。两类材质都消费同一份 `uw_surface_shared.gdshaderinc`。
- 面板打开时通过 `underwater_surface_debug_open` meta 让 `DiveRuntimeController` 停止位移、自动路线和水下输入；不冻结渲染时钟，不改水位、观察深度、太阳方向或日照强度。
- 水位、view depth、sun direction、sun color、sun strength 属于 Map/Session 的运行时真值，只在顶部显示只读快照。
- 面板保存到 `user://underwater_surface.cfg` 的 `[underwater_surface]`，不写 `water.tres`、`water.cfg`、Main、玩家存档或 `light_slots.cfg`。

## 3. 参数清单

`godot/src/rendering/underwater_surface_params.gd` 是唯一参数源，共48项：

1. 波场与法线：法线尺度、法线强度、波场 X/Z 尺度、时间倍率、法线双层漂移和副层变换、波坡法线倍率、视线扰动、仰视混合；
2. 波脊亮纹：波光强度、波脊起止、法线混入、断续起止、最低覆盖、断续变化、仰角混合；
3. 蓝面颜色：底部/顶部蓝色、波脊颜色、深度波脊倍率、无日光底亮、深度减光起止与倍率；
4. 太阳高光：水下 IOR、高光锐度、抗闪方差除数、峰值、核心/晕混合、最大混合、高光颜色；
5. 边界与时间：远端淡出起止、水雾融合量、显示色上限。

每项包含中文名、范围、步长、默认值；面板按清单生成 slider、ColorPicker 或 vec2 控件。共享 shader 的每个调试 uniform 都由专用测试断言清单覆盖。

## 4. 保存行为

面板动作：

- `保存当前`：保存全量参数和版本号；
- `加载已保存`：重新读取 `[underwater_surface]` 并即时写活动材质；
- `恢复默认`：取参数清单默认值，写活动材质并保存；
- `复制参数`：复制全部 `key = value` 行，便于回填代码或记录；
- 关闭面板：自动保存当前值。

第一次参数化尝试把显示色 uniform 标记为 `source_color`，导致默认显示色被再次做颜色空间转换，真实 `zone1 / 41m` 背景单调减光断言失败。已改为原始 display-space vec3，保留签署版本默认观感；没有放宽断言。

## 5. 验收

专用行为入口：

`D:/sea-visual-check/verification/20261109-211539-underwater-surface-debug-behavior2-fa66e4`

结果：110/0。覆盖参数清单、shader uniform、P开关、即时写入、保存文件、新实例加载、恢复默认。

最终整合：

`D:/sea-visual-check/verification/20261109-213426-underwater-surface-debug-signed-82ad44/report.json`

| 入口 | checks | failures | 结果 |
|---|---:|---:|---|
| underwater-surface-debug | 110 | 0 | PASS |
| visual-underwater-experience | 475 | 0 | PASS |
| underwater-experience | 179 | 0 | PASS |
| dive-transition | 226 | 0 | PASS |
| dive-control | 396 | 0 | PASS |
| dive-maps | 338 | 0 | PASS |
| ocean | 148 | 0 | PASS |
| 合计 | **1871** | **0** | 全部 exit0 / unexpected=[] |

真实 Vulkan Forward+ 水下画面保持原签署批次的深度递减；原海面波场、浮力、尾迹、岸线回归通过。此前一次参数化批次的 `zone1 / 41m` 单调减光失败已在去掉 `source_color` 二次转换后复跑通过。

## 6. 未签边界

本工具专项不等于全工程发布签署。低端设备、长时/连续性能、完整物理折射、用户美术终审和全局资源登记门禁仍未签。全局资源 sync/只读检查的已知问题不通过批量重签隐藏。

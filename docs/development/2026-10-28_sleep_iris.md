# 2026-10-28 · 睡觉与起床圆形过场

[主文档](../../GDD_V1.0.md#sea-sleep) · [睡觉文档](../features/sleep/spec.md) · [独立账本](../features/sleep/ledger.md)

## 实际行为

点击太阳房睡觉点、菜单睡觉和23:00自动睡觉共用一套过场：

1. 玩法界面和世界交互标记收起，黑色从屏幕四周向角色位置收拢，历时0.85秒。
2. 圆孔完全关闭后，黑幕显示“晚安，明天见”（自动睡觉为“夜深了，回家休息”），随后在黑幕期间切换日期、回到家门口。
3. 黑幕上显示“第N天 · 早上06:00”，文字淡去后，从醒来角色的新屏幕位置向外展开，历时1.05秒。
4. 全部打开后恢复玩法UI、解除输入和时间暂停，并按原流程自动存档。07:00出货/生长语义保持原契约。

圆幕使用独立canvas shader，按像素距离保持正圆，1.5像素软边；完全关闭时圆心也不漏画面，完全打开时最远屏幕角落也无黑边。屏幕大小变化会更新尺寸；角色被手动镜头移出画面时，圆心夹到最近的屏幕边界。收拢/展开分别采样圆心，房屋/相机位置在黑幕后切换。

## 工程边界

SleepCurtain只拥有表现阶段、文字与输入消费，通过focus_query读取屏幕位置；时钟推进仍归WorldClock，睡觉流程归SleepCycle。新增shader是界面实现代码，未修改光照参数、资产源或游戏存档格式。Main只提供投影查询，并保存/恢复CanvasLayer可见性；天气雨线和世界渲染继续运行。

正式入口：`godot/src/ui/sleep_curtain.gd`、`godot/shaders/sleep_iris.gdshader`。测试沿用统一runner的visual-sleep-cycle，增加逐阶段图片与像素验证。

## 验证

统一runner本轮实测，全部退出0、无预期故障、无脚本或着色器错误：

| 专项 | 结果 |
|---|---|
| visual-sleep-cycle | 37项/0失败；真实点击、圆幕阶段顺序、时间在闭合后切换、黑色边角/可见圆心、UI隐藏恢复、输入/存档锁、23:00自动入睡、06:00自动存档 |
| minimum-loop | 77项/0失败；06:00醒来与07:00结算保持分离 |
| visual-title-screen | 24项/0失败；开始画面及其时间/输入隔离正常 |
| check_feature_contracts --sync及无参数 | 33功能、429源资产、317运行哈希，0 issues |

证据目录：`D:/projects/sea-work/verification/20261028-093724-sleep-iris-clean-ui-2492be/`。完整退出码及命令见[机器记录](2026-10-28_sleep_iris.json)。

已亲眼查看实际渲染的sleep-iris-closing、sleep-iris-closed、sleep-iris-morning、sleep-iris-opening及清理UI后的收拢/展开帧。所有截图/日志均在工程外sea-work，测试数据在Autoload前隔离。未执行项：GL后端、移动端/Web和触控/手柄专项。


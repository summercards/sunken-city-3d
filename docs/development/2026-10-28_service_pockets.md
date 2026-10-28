# 2026-10-28 出货箱、仓库与商店口袋界面

Request ID：`21726f14-a5f7-438f-9db2-83ed622dd271`。承接“重做交互物体与背包界面”中断的最后一轮：出货箱的世界气泡已替换，但打开后仍显示旧文字详情卡。本轮完成其内部界面及同类服务入口，关联 SEA-UI-R28、SEA-ORDER-R10、SEA-WAREHOUSE-R05、SEA-INVENTORY-R07。

## 最终行为

- 出货箱、保管仓库、种子小铺共用 `PocketService`。上方为背包，下方为待出货物品、仓库存货或种子目录；奶油背板、手绘物品、空位圆点、物品名称胶囊及黄色操作气泡沿用口袋风格。
- 背包每页最多24格，服务库存每页8格；真实容量和堆叠数来自各自所有者，48格出货箱/仓库共6页，缩小背包容量不会制造额外空位。
- 点击物品选择存入/取回1件或所选整叠，商店显示实际售价并购买1包。出货箱实时显示待结算金额，不即时出售，也不包含睡觉按钮。非收购品显示原因；满包拒绝保持两端数量。
- 实体箱子、补给站和 HUD 命令统一进入网格。Esc先收起物品操作气泡，再按原返回链关闭界面；面板消费鼠标输入，关闭动画期间不再次执行物品操作。
- 沿用既有 Inventory、WarehouseService、DailyShipping、Farm 命令。07:00结算、售价、存档格式和库存所有权均保持原规则。

## 实现与接口

- `godot/src/ui/pocket_service.gd`：独立表现视图，注入 `query(service)`，仅发 `operation_requested(id, action, amount)` 和 `close_requested`。
- `godot/src/ui/hud.gd`：组装服务快照、分派命令，三个服务页在旧详情构建前进入独立网格；`island_menu.gd` 同步隐藏/恢复服务页。
- `godot/src/orders/daily_shipping.gd`：`query()`增加 `capacity`、`slots_used` 只读字段，界面不推测容量。
- `godot/tests/test_pocket_services.gd` 验证真实鼠标存取和分页；`test_plot_shipping_loop.gd` 从场景箱子的屏幕坐标点击开始，覆盖气泡、接近、网格、存取、07:00结算和保存恢复。

## 本次恢复后的实测

所有运行通过 `scripts/run_verification.py`，在 Autoload 前隔离用户数据。完整退出码、预期故障、意外错误和日志路径见[机器记录](2026-10-28_service_pockets.json)。

| 检查 | 渲染 | 结果 |
|---|---|---|
| visual-pocket-services | 真实 Vulkan / Forward+ | 28项通过，退出0；鼠标单件/整叠存入、取回、仓储、商店、容量、分页、Esc及1280×800 / 1600×1000 / 1920×1080 |
| visual-plot-shipping | 真实 Vulkan / Forward+ | 59项通过，退出0；实体箱入口未进入旧详情卡，次日收货与存读通过 |
| visual-pocket-bubbles | 真实 Vulkan / Forward+ | 65项通过，退出0；世界图标、气泡和原口袋回归 |
| minimum-loop | headless | 77项通过，退出0 |
| framework-modules | headless | 30项通过，退出0 |
| save-seed / framework-integration（完整世界） | headless | 保存种子准备通过；44项集成检查通过，均退出0 |

本轮三项真实渲染专项没有预期故障或非预期脚本错误，已目视检查出货箱三种尺寸及商店、取回操作截图。截图和隔离工程位于 `D:/projects/sea-work/verification/20261028-111635-service-pockets-resumed-3d9a8d/`，不放入正式游戏资源。

## 过程失败与边界

中断轮次中 `service-pockets-delivery-80722d` 的鼠标存入检查失败，并因缺少预期物品触发空值访问；随后 `service-pockets-capacity-final-f0fe86` 28项通过。本次重新运行当前源码通过，旧失败保留在机器记录，不能用旧截图代替本次验证。

完整世界 selftest 当前为535项通过、3项失败（退出1）：`home_cabin`、`zone1_shell`、`zone1_wood` 的目标点不在可行走面。中断前同一轮已存在这三项失败，恢复后仍复现；它们与本轮UI专项分开登记，未修改场景几何或放宽断言。

触控/手柄、长期运行和独立导出包未执行。沿用 `UI-ACTION-HANDDRAWN-001`、`UI-POCKET-HANDDRAWN-001`，没有新建图像；既有图像的供应商条款核验仍按UI分账本保留pending，不以功能实测代替授权核验。完整功能状态继续为partial。

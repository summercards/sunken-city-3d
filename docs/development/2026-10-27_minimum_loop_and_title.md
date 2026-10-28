# 2026-10-27 太阳房最小循环与开始画面

[主文档](../../GDD_V1.0.md) · [逐项退出码、命令及日志](2026-10-27_minimum_loop_and_title.json)

## 当前可玩交付

默认保留太阳房、家园补给站、浅水平台和附近鱼点。太阳房与浅水平台的12格土地可使用，圆弧农场6格及其已有作物冻结，进度不删。隐藏其它区块、远景建筑、采集和建造牌；潜水、建设、打捞钩、潜水镜、相机参数、滤镜等入口灰显并阻断命令。全功能开发配置保留，必须显式传入 `--full-world`。

新档有80海贝、3包生菜种子。点击家园泊位上岸，打开种植页选择作物，点击床格播种，再点一次浇水。生菜需要3个浇水日；岸上可补水，休息到早晨。鱼点点击后小船驶近收取。商店出售三种现有种子；海贝或空间不足不扣款。

保管仓库48格，种子、鱼、农产品和材料都能存取，不自动出售。出货箱另有48格，只收鱼/蔬菜/番茄/南瓜；玩家显式放入，结算前可取回。每天08:00自动清货入账，收据在出货页查询。自然经过早晨与休息共用同一晨次水位线；午夜不结算，午夜后休息不会额外跳过一天。缺水停长，离线不补收益。满包时鱼群/成熟作物/仓库物品留在原处。

家园补给站沿用现有独立交易板表现，在当前配置中放到打捞浮台可行走地面，提供商店/仓库/出货入口；顶部也提供直接入口，存取/购买要求先上岸。没有新增已完成的养殖生态、鱼竿小游戏或NPC剧情。岸上种植平台使用现有种植功能。

航行上限3.4→2.6米/秒，转向0.95→1.8弧度/秒，保留原加减速、碰撞范围、航路及逐段合法性验证。最小区域为x[-18,37)、z[-12,36)。近岸鱼点右侧不可到达时改用鱼点本身的合法水域接近。

## 开始画面与反馈

默认启动先显示实景开始页：太阳房偏左，右侧奶白倾斜SEA与“开始游戏”，使用同一份已有OFL授权圆体做程序化排字；参考图只提供风格依据，不声称使用参考原字体。标题渐显并轻移，按钮延迟显现；没有HUD、世界标记、拾取圈、菜单或系统提示。可点击或Enter/Space进入，重复激活受锁保护。

进入前冻结经营、日历、天气、拾取补货及自动存盘；水面与装饰动物仍有表现。标题退场后1.1秒镜头过渡到进入前保存的游戏镜头，再恢复UI与输入。默认继续已加载的存档，不覆盖进度。

系统消息为右上480宽轻提示，取消底部系统对话纸及打字机。修复无悬停目标时左上角仍显示空白提示底板的问题，并加入真实界面回归。角色发言另用 `HUD.show_dialogue(speaker,text)` / `character_dialogue.gd`，目前无新增NPC剧情。

## 所有权和接口

| 责任 | 独立文件 / 端口 |
|---|---|
| 当前开放范围 | `godot/src/core/play_scope.gd`；Main装配到Zones资格、导航区域、鱼群刷新配置 |
| 仓库 | `godot/src/warehouse/warehouse_service.gd`；deposit/withdraw；自身Inventory |
| 双端物品转移 | `godot/src/inventory/inventory_transfer.gd`；预检容量与数量，完成后统一发布数量/容量事件 |
| 出货与晨次 | `godot/src/orders/daily_shipping.gd`；deposit/withdraw/query/observe/to_dict/from_dict；注入Inventory、grow和sync_day |
| 种植 | Farm继续拥有作物状态；advance_day(accessible_only)、sync_calendar_day |
| 生活界面 | `godot/src/ui/home_loop_panel.gd`只发公开命令，HUD负责显示与岸上条件 |
| 开始页 | `godot/src/ui/start_screen.gd`发start_requested，不持有经济状态 |
| 临时开始镜头 | `godot/src/camera/title_camera.gd` begin/blend/finish，保存与还原变换/FOV/处理状态 |
| 对话 | `godot/src/ui/character_dialogue.gd`只接角色名和发言 |

资产 `UI-TITLE-SEA-001` 通过 ledger_index 路由到UI分账本，复用 `UI-FONT-LXGW975YUAN-SC-700`；仅新增源索引，不重算既有素材基线。

## 存档

根格式升级v3，`economy.daily_loop`必填，保存货箱、最后结算晨次、收据。v0-v2经过decode明确迁移为空出货箱，首次观察时对齐当前晨次，不补发过去收益。当前档缺字段、类型错误、未来晨次或非法出货品拒绝。旧档仍保留背包、仓库、作物、设施等数据；远处角色回家园船上，随后正常靠泊。

SnapshotRegistry增加busy查询；恢复、晨次结算期间不允许写出中间快照。恢复仍全量校验后原子应用，结束统一刷新；重复observe及恢复结算后快照不会再次付钱。未对玩家真实存档运行测试。

## 验证

所有运行检查经 `scripts/run_verification.py`，在Autoload前隔离用户目录。报告中的render字段区分真实Forward+与headless；退出码如实保存。

- 正式最小配置：`minimum-loop` 76项通过，`visual-minimum-loop` 77项真实渲染通过。覆盖实体播种/浇水/收获、12格范围、双向航行、4个鱼点可达、平台补给站可达、买种余额与满包拒绝、仓库不卖货、出货撤回、08:00阈值与重复结算、磁盘往返、旧档迁移及远处回家。
- 正式开始页：`visual-title-screen` 23项通过，使用真实GUI鼠标点击，不直接调用进入游戏；检查冻结时间/鱼群补货、隐藏其它CanvasLayer、同源字体、淡入完成、恢复UI与操作。
- 完整开发配置回归（`--full-world`）：modules31、farming31、management36、surface503项/30航线、framework-modules30、framework-integration40、camera8、自检537通过；跨进程正常存读与坏档保护通过。完整开发回归不代替默认最小配置验收。
- 前期失败已保留在JSON记录：测试取错read返回键导致脚本异常；开始页第一次鼠标测试使用物理/逻辑坐标混用，改为Viewport逻辑坐标真实点击后通过；自检船桨检查将掉头等待误当作向前划桨且只比两帧，现先等到真实划桨再采样完整周期，通过537项。没有降低运行时碰撞/航行门槛。
- 未执行：手机/触控/手柄、真实断电或磁盘故障、长期经济平衡、NPC内容验收。未实现的养殖、远海、居民及建造等继续保持原功能账本，不标完成。

## 主要证据目录

- `D:/projects/sea-work/verification/20261027-181756-home-loop-final-visual-dc9da9/`：最后开始页截图。
- `D:/projects/sea-work/verification/20261027-182251-home-loop-clean-ui-d6f5cc/`：最后经营截图及77项真实渲染检查，包含空悬停提示隐藏。
- `D:/projects/sea-work/verification/20261027-181937-home-loop-final-commands-8b534b/`：最后命令/存档循环检查。
- `D:/projects/sea-work/verification/20261027-181710-home-loop-selftest-stroke-0f567d/`：537项完整自检。
- `D:/projects/sea-work/verification/20261027-181113-minimum-loop-save-v3-a70277/`：v3框架、跨进程存读及坏档保护；其中早期船桨失败由上项补验。

无需重生成或覆盖正式TSCN；既有场景资产拆分改动全部保留。

## 继续任务后的当前工作区复验（22:20）

当前工作区包含后续鱼群/鲸鱼改动。本次重新通过统一验证入口执行真实渲染 `minimum-loop`（77项）与 `visual-title-screen`（23项），退出码均0。证据：`D:/projects/sea-work/verification/20261027-222049-home-loop-current-workspace-f24a8a/`。历史537项自检仅代表对应记录的版本，不作为这批后续资产改动的当前实测。

最终功能契约同步与检查均发现2项源哈希漂移：`SEA-DECO-ANIMAL-FISH-SCHOOL`、`SEA-DECO-ANIMAL-WHALE`。两项资产保持待核验；未覆盖其最新代码，也未刷新哈希掩盖差异。当前功能循环/开始页通过，不等于全局资产门禁通过。

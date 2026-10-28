# 2026-10-28 开始界面构图与存档时刻

承接SEA-CAMERA-R06、SEA-UI-R34、SEA-BOOT-R05；同时复核SEA-SAVE已有恢复顺序与SEA-TIME开始阶段暂停规则，不新增存档版本、时钟或玩法数值。

## 画面调整

TitleCamera原方向normalize(-0.50,0.53,0.69)、31°FOV、64m观察距离、水平12m构图偏移均保留。只沿相机自身上方向反向平移3.4m，等量移动观察点与相机位置，不旋转镜头，不挪房屋。房屋主体在画面中上移约10%，保留左侧主体、右侧标题的布局。

“开始游戏”的横向锚点由0.66改为0.755，避开右侧种植平台和亮色水线；文字风格、字号、倾斜、淡入、点击淡出和1.1秒入场镜头不变。未加文字背板或全屏蒙版。

## 存档时间连续性

原实现默认槽位已经恢复，但_begin_title又强制apply(9.0)，直到入场结束才按存档时刻输出，造成明显换光。本轮只把该入口改为daylight_rig.apply(world_clock.query().hour)，沿用已恢复的同一时钟。开始阶段主循环继续不推进时间、天气、经营与自动存档，入场结束后才恢复正常计时。无存档继续使用新局07:00，没有写入假09:00或更改既有光照预设。

## 真实验证

统一runner增加title-clock-seed和三个visual-title-screen案例，只让这四个检查共享专用隔离用户目录。种子通过正式save_game写出09:00、21:15、次日06:00三个合法v3快照。每个真实渲染进程先把所选测试档复制到隔离默认槽，再正常冷启动Main，由正式启动读档流程恢复。

每例核验第一帧光照时刻、标题显示期间时间冻结、三种分辨率、角度/FOV不变、房屋上移、按钮右移及不越界。通过真实GUI点击进入，逐帧比较太阳强度/色彩/变换、环境/天空/对比度、水色/高光与家园灯，过渡全程一致；入场后UI与游戏镜头恢复，时钟正常继续。

| 检查 | 退出码 | 完成标记 |
|---|---|---|
| visual-title-screen | 0 | [title-screen] 25 checks, 0 failures |
| title-clock-seed | 0 | [title-clock-seed] ok=true |
| visual-title-screen-day | 0 | [title-saved] 26 checks, 0 failures |
| visual-title-screen-night | 0 | [title-saved] 26 checks, 0 failures |
| visual-title-screen-dawn | 0 | [title-saved] 26 checks, 0 failures |
| camera | 0 | [camera-follow] 8 checks, failures=0 |
| minimum-loop | 0 | [minimum-loop] 77 checks, 0 failures |
| daylight | 0 | [daylight] 231 checks, 0 failures |

白天、夜晚、清晨各26项，覆盖1280×800、1600×1000、1920×1080；总78项全部通过。原开始页面25项、游戏镜头、最小生活循环与昼夜回归也通过。所有最终选用日志预期故障0、非预期SCRIPT/SHADER/ERROR为0；无2D内容截图时存在引擎2D MSAA性能警告，未作为功能错误。

首轮出现一项测试误判：JSON解析将数字读为浮点，直接比较整个字典与带整型day的时钟字典失败。修正为day、seconds、day_length数值逐项精确对比；没有改存档实现或放宽时间相等判据，首次失败日志保留在title-composition目录。

截图与分项数据位于 `D:\projects\sea-work\verification\20261028-164507-title-saved-light-5936f3/project/outputs`，同名JSON登记每个日志与完成标记。预览总览位于工程外sea-work/title-screen-20261028/title-day-night.png。

## 边界与保留

未编辑正式TSCN、材质、光照时段数值或美术制作源；未写回玩家存档或调光配置。仍按原过程恢复玩家镜头和交互，功能整体状态不因本轮专项变为全平台验收。移动/掌机输入、WebGL/兼容渲染、断电与磁盘故障未执行。

功能账本与主文档由check_feature_contracts.py --sync同步，再执行无参数结构检查。

资产登记补充：由ledger_index路由到UI分账本，UI-TITLE-SEA-001的源为start_screen.gd。反向还原唯一一行按钮横向锚点后，字节哈希与旧登记完全一致，因此仅将此资产升为v002、同步该行源哈希与manifest/源索引；字体与授权记录保留，未刷新无关资产哈希。

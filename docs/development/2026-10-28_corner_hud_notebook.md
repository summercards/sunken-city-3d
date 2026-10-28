# 2026-10-28 左下文字、右上图标与海岛笔记

本次承接SEA-UI-R35–R38，并接线SEA-FARM / SEA-INVENTORY / SEA-TIME / SEA-NAV / SEA-INTERACT。按用户后续纠正，左下没有背板，保留原白色加粗圆体；右上入口及展开项均为饱满彩色图标，不显示常驻文字。

## 最终表现

- 左下集中日期时间/天气、瓶盖、背包占用，约284×170设计区域；26/36/28px同源圆体、原合成加粗、偏移软投影，outline和shadow_outline均为0。行动按钮也只有文字。
- 右上一个72px图标，点击展开背包、笔记、商店、仓库、出货箱、航海图、设置。鼠标/焦点放大，图标可用悬停提示识别。Esc和外点先收起，拦截该次世界点击；选择后进入真实功能。
- 海岛笔记顶部四类目录：总目录、种植、物产、生活。下方每页最多六张资料卡，右侧详情；底部页码、上一页和下一页。种植页含实际作物资料和已注册地格；物产显示实际背包/仓库数量和出货单价。可前往地格或进入既有服务，保留背包返回链；N可直接打开。
- 泊位使用UI-ACTION-HANDDRAWN-001的白色船锚；正常30px青绿圆，进入64px邻域平滑放大到50px暖金圆，离开缩回；去掉地点文字和第二颗手形悬停气泡，26px命中半径、稳定ID与双向上下船不变。

## 所有权与文件

`corner_hud.gd`只展示信息和发命令，`launcher_icon.gd`绘制图标；`notebook.gd`拥有分类/页/选中项这些临时UI状态，`notebook_data.gd`读取注入Economy下各模块的公开查询并返回新字典。HUD继续分发既有服务命令和地格聚焦信号。WorldClock和Inventory/Farm/Warehouse/DailyShipping仍是状态唯一写入者，没有新增存档字段。

Main原有日期Label引用现在指向HUD里的同一Label，继续由原查询更新；开始画面和睡觉显隐链保留。泊位与HoverCard共用Main注入的指针查询，避免两处不同坐标源；日常读取真实视口鼠标。自动验证使用项目既有的debug指针端口固定位置，实际渲染缩放与颜色，不依赖Windows外部鼠标位置。原生GUI事件仍负责菜单点击、分类、翻页与返回。

新程序化源登记UI-HUD-CORNERS-001和UI-NOTEBOOK-001，沿总索引进入UI分账本。既有UI资产行逐条与HEAD相同，原图/字体未改；现有手绘图标授权pending状态保留，没有刷新历史图片或运行资源哈希。上午、中午、傍晚等光照文件不在本轮差异内。

## 实测

所有运行经scripts/run_verification.py，在Autoload前隔离user://，截图位于工程外sea-work。完整日志/退出码见同名JSON。

| 检查 | 结果 | 渲染 |
|---|---|---|
| visual-corner-notebook | 75项 / 0失败，退出0 | Forward+ / RTX4060Ti，1280×800、1600×1000、1920×1080 |
| visual-world-text | 23项 / 0失败，退出0 | 真实渲染 |
| visual-pocket-bubbles | 65项 / 0失败，退出0 | 真实渲染 |
| visual-pocket-services | 28项 / 0失败，退出0 | 真实渲染 |
| visual-title-screen | 25项 / 0失败，退出0 | 真实渲染 |
| sleep-cycle | 33项 / 0失败，退出0 | headless逻辑 |
| minimum-loop | 77项 / 0失败，退出0 | headless逻辑 |

本轮没有预期故障场景；各通过项unexpected_errors为空。开始画面有引擎2D MSAA无内容提示，未出现脚本错误或泄漏。触控和手柄设备专项未执行，玩家审美确认留待用户查看实景。

实现中修复了消息遮住菜单首项的问题，并显式清除继承的shadow_outline_size=1。早期缩放自动检查把合成视口事件当作持久系统鼠标坐标，产生失败；改为同一注入指针查询后实测远离30.0px、靠近49.94px、离开缩回，末页禁用/单次翻页/菜单真实跳转/无点击穿透等均通过。

最终实景：`D:/projects/sea-work/verification/20261028-180843-corner-verified-4c09e1/project/outputs/`。文档结构和资产检查通过后记录于同名JSON的contract_checks。

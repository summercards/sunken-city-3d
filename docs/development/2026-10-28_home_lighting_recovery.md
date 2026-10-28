# 2026-10-28 家园箱子、夜灯、船体受光与P键续接交付

[主文档](../../GDD_V1.0.md#feature-control) · [机器证据](2026-10-28_home_lighting_recovery.json)

## 请求与续接范围

续接“修复箱子、夜间灯光和P键”，对应请求ID `8dc9a330-b868-4a82-90d2-1d1615b10d1b`。原要求为恢复缺失小箱子、入夜点亮房间、船接受光照、恢复P调试。读取原聊天与已有失败日志后继续已有修改；本轮追加修复光照面板key/prop映射、补齐夜间基准断言，完成当前隔离实测与账本。

## 最终行为

- 白盖蓝箱沿用 `SEA-SCENE-SBR-COOLER` 与原GLB，作为 `zone1_home_harbor.tscn` 中 `Objects/ShippingBox/Visual` 的稳定PackedScene实例。交互锚点 `(1.05,1.38,15.15)`，底面实测Y=1.38；可见包围盒1.56975×1.07916×1.185938米。原front_platform里的cooler显式排除，避免新版实例清单摆回房旁后码头只剩空交互点。
- 太阳房、露台与屋顶三盏暖色OmniLight随18–19点渐亮，午夜保持，05:30–07:00渐灭；玻璃按公共色板格位变暖发光。夜间日光、补光、天空和海面日光提亮仍归零，局部灯通过真实距离与遮挡衰减，不增加屏幕蒙版。
- 船的旧unlit标记、蓝色增亮与ambient_boost退役；船体、桨和细节统一使用接收场景灯的材质。共享toon着色器保留既有定向光风格，局部光额外按ATTENUATION衰减，水下补偿随昼夜归零。
- P在最小范围可开关，并可从口袋切入；Esc关闭P后不误开暂停菜单。面板仍模态且不压暗画面。光照参数通过light_params.prop接入DaylightRig：修复原先sun_energy等面板键与light_energy等属性名不一致，造成下一帧被昼夜基准覆盖的问题；夜里读取、保存的是09:00基准，不把夜间零能量保存为出厂值。

## 当前实测

全部由 `scripts/run_verification.py` 在Autoload前隔离用户数据。真实渲染与headless分开记录；本表各项均passed=true，当前预期错误0、非预期错误0。

| 检查 | 渲染 | 结果 | 退出码 |
|---|---|---|---|
| visual-home-lighting | real | [home-lighting] 112 checks, 0 failures | 0 |
| visual-home-lighting | real | [home-lighting] 109 checks, 0 failures | 0 |
| daylight | headless | [daylight] 194 checks, 0 failures | 0 |
| minimum-loop | headless | [minimum-loop] 77 checks, 0 failures | 0 |
| lighting-params | headless | [lighting-params] 172 checks, 0 failures | 0 |
| lighting-panel | headless | [light-probe] 22 checks, 0 failures | 0 |
| visual-title-screen | real | [title-screen] 25 checks, 0 failures | 0 |
| visual-plot-shipping | real | [plot-shipping] 59 checks, 0 failures | 0 |
| visual-cabin-dayparts | real | [cabin-dayparts] 75 checks, 0 failures | 0 |
| ocean | headless | [ocean] checks=141 failures=0 | 0 |
| decorations | headless | [decorations] 1589 checks, failures=0 | 0 |

最后一轮真实渲染专项的16个相关源码/场景/着色器文件与当前工作区逐字节一致，详见JSON。光照保存专项覆盖太阳/环境写入、朝向互不覆盖、配置重开/复位与滤镜段保留；箱子专项使用真实viewport输入，出货流程覆盖点击、存取和07:00结算。仅修改load_steps资源计数提示后的最终专项也已重跑。

夜灯能量由运行时回读、船体像素取自最终截图：19:00三灯能量合计6.10，09:00为0；同机位船区域白天、全暗和局部暖灯的RGB分别记录在机器证据中。局部暖灯为受控验证光，测试结束释放，不作为船上永久补光。

## 过程失败

中断前的home-lighting-before/first/panes/regression等日志与退出码完整保留在JSON的prior_attempts。最后一次中断前失败为“P lighting controls edit the daylight baseline”，本轮修复prop映射后转绿。初期故障和未完成尝试没有被当前通过覆盖。

## 资产和边界

从 `assets/registry/ledger_index.json` 路由到场景分账本，只维护cooler的运行摆位和验证链接；保留源/GLB/稳定AssetID，未重导出资产或批量刷新哈希。参考图授权仍为pending。

本轮未执行gl_compatibility、触控/手柄、独立导出包、完整世界自检及真实连续24小时游玩；不据此签署这些范围通过。未改玩家存档、经济售价、经营时间或正式TSCN的其它手工布局。

## 证据图

工程外 `D:/projects/sea-work/home-lighting-recovery/`：`home-box-actions.png`、`home-night.png`、`home-debug-p.png`、`home-boat-day.png`、`home-boat-dark.png`、`home-boat-local-light.png`。原始日志和运行副本路径见JSON。

工程契约收尾：`python3 scripts/check_feature_contracts.py --sync` 与无参数检查均退出0，33个功能、432项源资产、346个运行资源哈希，0问题；`git diff --check`退出0。

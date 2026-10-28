# 2026-10-28 清晨、下午与夜海真实光照/水深

关联：SEA-OCEAN-R15–R19、SEA-NAV-R07、SEA-TIME-R01/R08/R09。最新用户要求覆盖旧“19点后全暗”视觉方案；上午、中午、傍晚的已有日照与保存偏移必须保留。

## 最终画面与实现

- 06:00：太阳高度约3.37°、橙金直射与较冷暗部，减少填充光，形成清晨长阴影。天空采用日出蓝/桃色，不沿用紫色夕阳端点。
- 14:12–16:00：太阳、环境、天空能量恢复到上午同级，只略调色温和方位。
- 夜间：太阳保持为零；水面使用受光ALBEDO、世界波面法线和PBR高光，海水不自行发光。WaterMoon是真实方向灯，由DaylightRig按夜色权重驱动，只照水面接收层；船灯、屋灯及普通引擎灯直接被渲染器计算，没有灯位数组、屏幕亮斑或另画的倒影。
- 夜间水深：用深度纹理还原垂直水柱，浅水透出已受光的水下建筑和海床；深水逐渐加深并变得更不透明。双水面方案均保留此行为。浅/深水色、深水距离、浅水不透明度、粗糙度共5项放入P面板，支持原季节/天气/时段偏移。
- 窗灯：按凹入玻璃面/独立门玻璃材质限制琥珀发光；窗框与格条前面不发光。降低三盏局部灯的白亮溢出，保留原开关灯时间。
- 船灯：复用SEA-SCENE-SBR-LANTERN，挂在船头；真实OmniLight3D随船和船体摇摆，按家园灯曲线渐亮/渐灭。灯壳不遮住自己内部的光源；没有改变航线、速度、吃水或碰撞。

最终版本已移除开发中尝试的程序夜海波纹与手动灯位反光。后续用户指出水面应实际受光、夜间需要水深后，分别以真实灯对照和水下物体透视对照验证，不以“看着像亮了”代替。

`night_water_params.gd` 对旧材质缺少的新夜间字段提供内存初始化，避免正在运行的旧调参器另存材质时丢掉新字段；不强迫覆盖用户已有水面资源。两套water.tres的最终内容与登记哈希一致。

## 已认可时段保留

已与本轮开始前的隔离副本逐项比较07:00、11:00、12:00、14:00、17:00、18:18关键帧：8项曲线数值及label全部相同。`daylight` 增加正午、夕阳冻结断言，并继续检查07–11点的完整基准恢复。夜间新材质分支在这几个已认可时段的权重为零，日间ALPHA保持1。

玩家的filter.cfg、light_slots.cfg、water.cfg、water_presets.cfg仅只读备份/复制；没有从验证进程向玩家目录写回。工作期间实时夜间/水面配置发生过更新，因此不宣称整份文件哈希始终不变，也没有用旧备份覆盖新值；已分别核对原有morning/noon/sunset保存组，除浮点序列化尾数外语义一致。细项与哈希见同名JSON。

## 真实渲染与受控证据

普通测试灯不登记进DaylightRig，直接加入引擎场景：目标海面红通道由 0.1248 变为 0.2161；移灯后回到 0.1248。关闭实际灯与环境光后，开阔海面亮度为 0.0000。这验证的是实际光照响应。

深度验证使用0.6m与5m两个受光物体，固定几何和深度缓冲，只切换物体的亮/暗材质；用无水对照归一化，排除灯光距离的影响。原版保留对比为 0.830 / 0.310，吸收式为 0.588 / 0.466，均为浅水高于深水。

截图、关闭灯对照、移灯对照、双方案深度对照均在 `D:\projects\sea-work\verification\20261028-155114-atmosphere-verified-delivery-3c1c90\project\outputs`。四格总览：`D:/projects/sea-work/atmosphere-20261028/atmosphere-preview.png`。

## 验证

全部运行经scripts/run_verification.py，在Autoload前隔离用户目录。主交付目录：`D:\projects\sea-work\verification\20261028-155114-atmosphere-verified-delivery-3c1c90`。

| 检查 | 模式 | 退出码 | 完成标记 |
|---|---|---|---|
| daylight | headless | 0 | [daylight] 231 checks, 0 failures |
| water-params | headless | 0 | [water-params] PASS 原版 · 78 个参数与着色器一致（另有 21 个豁免） / [water-params] PASS 吸收式 · 45 个参数与着色器一致（另有 21 个豁免） |
| lighting-params | headless | 0 | [lighting-params] 221 checks, 0 failures |
| lighting-panel | headless | 0 | [light-probe] 61 checks, 0 failures |
| visual-atmosphere | real | 0 | [atmosphere] 68 checks, 0 failures |
| minimum-loop | headless | 0 | [minimum-loop] 77 checks, 0 failures |
| sleep-cycle | headless | 0 | [sleep-cycle] 33 checks, 0 failures |
| visual-home-lighting | real | 0 | [home-lighting] 114 checks, 0 failures |
| ocean | headless | 0 | [ocean] checks=141 failures=0 |
| visual-cabin-dayparts | real | 0 | [cabin-dayparts] 75 checks, 0 failures |
| surface | headless | 0 | [surface] routes=30 checks=503 failures=0 |

最终选用日志的预期故障：0；非预期脚本/着色器/引擎ERROR：0。真实空UI截图时有Godot“2D MSAA启用但没有2D内容”的性能警告，不是脚本或着色器错误。

首次surface误在最小范围运行，旧测试包含锁定区域，退出1/27个失败；随后按其旧完整世界契约显式--full-world，30条路线/503项通过。原始失败日志保留，未改导航规则来迎合旧测试。

未执行：gl_compatibility/WebGL真实渲染、移动/目标设备与用户对最终氛围的主观确认。当前实测后端为Windows Forward+ / RTX4060Ti。

## 资源与账本

灯笼原AssetID从ledger_index.json解析的场景分账本确认，源文件和GLB未改，原授权状态pending_user_reference_rights_review保留。运行时资源清单只核对一处既有Environment基线差异：ambient sky=0.82，SSAO半径/强度/受光=1.05/0.55/0.19，glow=0.39；这些值在本任务首次读取时已存在，文件本身未被本任务修改。审阅后只更新这一行登记哈希并留审计记录，资产补登状态仍为pending，不批量更新其他源或资源哈希。

功能账本、主文档与生成索引由check_feature_contracts.py --sync同步，再运行普通检查。

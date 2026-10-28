# 2026-10-28 外舷夜航照水灯

对应SEA-NAV-R08、SEA-OCEAN-R20。用户要求设计能实际照亮海面的船灯；原船灯的主要反馈是船舱/箱子变亮，不能用这一点代替舷外水面照明。

## 灯具设计

复用原灯笼资产与实例ID，在船头左外舷加短木杆挂灯。木杆是Boat运行包装内置几何，与桨同类，不新增道具、交互、碰撞或玩法数值。灯笼挂点(-1.08,0.95,-1.35)，灯源(-1.13,1.17,-1.35)，玻璃朝向舷外；静水面上方约1.17m。

船灯改为有遮光方向的真实SpotLight3D：暖色(1,0.65,0.28)，引擎能量8.0，最大距离9m，半角60°，光束方向normalize(-0.55,-0.83,-0.08)，主要向下、向舷外照水。保留真实阴影、距离与角度衰减，降低高光系数至0.35；先前仅把Omni增亮的试验会照白近处船板，因此最终选择定向照水方案。

光源沿用Model/BoatLamp稳定节点路径，灯笼沿用boat/furnishing/bow_lantern实例ID。DaylightRig按Light3D基类收集home_lamps/boat_lamps，仍只有一个船灯；时段驱动及强度唯一写入者不变。保留原家园灯、夜间水深、真实水面受光以及上午/中午/傍晚预设，未修改水面着色器或夜海参数。

## 实景证据

新增visual-boat-lamp专项，将图像像素反投影到真实水面，按船体局部坐标圈定舷外纯水区域，排除“船体很亮所以误判海面很亮”。近区x[-4,-1.7]、z[-3.4,0.6]；远区x[-9,-7]；另采相反一侧水面。开/关灯使用同一机位、冻结时间和场景状态，仅改真实灯能量。

原版近水区域红通道平均增量0.1450、绿通道0.1027，61.0%样本达到明显暖光阈值；远处红增量0.000044，相反一侧0.000001。吸收式对应近水红增量0.4299，暖光覆盖91.8%。船移动/旋转后旧区域没有残留暖光。

旧灯先按相同门槛作负对照，17项中8项失败，目标左舷近水区域暖光覆盖为0；日志保留。最终17项全部通过，门槛未为最终参数放宽。

截图与原始报告：`D:\projects\sea-work\verification\20261028-162525-boat-lamp-delivery-4d0160`。开关灯总览：`D:/projects/sea-work/boat-light-20261028/boat-light-on-off.png`。

## 验证与保护范围

所有运行验证经scripts/run_verification.py隔离项目和用户数据，光照配置仅只读复制。

| 专项 | 退出码 | 完成标记 |
|---|---|---|
| daylight | 0 | [daylight] 231 checks, 0 failures |
| visual-boat-lamp | 0 | [boat-navigation-lamp] 17 checks, 0 failures |
| visual-home-lighting | 0 | [home-lighting] 114 checks, 0 failures |
| visual-atmosphere | 0 | [atmosphere] 68 checks, 0 failures |
| minimum-loop | 0 | [minimum-loop] 77 checks, 0 failures |

最终日志中预期故障0，非预期SCRIPT/SHADER/ERROR为0；无2D界面截图有Godot的2D MSAA空内容性能警告。未执行WebGL/兼容渲染与移动设备验证。

daylight_presets.gd和night_water_params.gd与本次开始备份逐字节一致；daylight同时复验已认可的上午、正午、夕阳数值。未写回玩家调参、Environment资源、材质或制作源。原灯笼授权pending继续保留，不批量更新任何资源哈希。

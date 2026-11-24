# 2026-11-23 阳光房二楼栏杆和花草显隐

二楼 13 段栏杆共用 `SEA-SCENE-SBR-PARAPET`。导出时跳过 Blender 母版集合里单独命名的「夹层玻璃」，将 872 个三角面减至 828 个。稳定栏杆场景改用 `parapet_open_v2.glb`，保留框架、竖杆、原色盘与原碰撞。原始 Blend 及旧 GLB 留存，导出副本在工程外 `sea-work/sunroom_railing_20261123/`。主场景摆位和碰撞场景沿用当前工作区版本。归 SEA-SUNROOM-R24。[栏杆场景](../../godot/scenes/components/solar_cabin/v1_6/parapet.tscn) · [导出清单](../../godot/assets/models/facilities/solar_cabin/v1_6/export_manifest.json)

区块等级刷新遍历建筑附件，曾重新打开已经按修缮阶段或季节隐藏的花草。读档完成时，这次刷新发生在阳光房表现同步之后。现在阳光房的花草由 `SunroomView` 控制显隐，进场时直接使用装配层提供的状态。复验覆盖新局 1 株小雏菊、修梯后 5 株、休整后春季 56 株、秋季 53 株、冬季 42 株，以及从休整态读回修梯档。归 SEA-SUNROOM-R05/R06。[显隐脚本](../../godot/src/facilities/sunroom_view.gd)

## 验证

证据位于工程外 `sea-work/verification/`。正式主场景的同机位前后对照为 `20261123-110558-sunroom-railing-baseline-37e794` 和 `20261123-111020-sunroom-railing-plants-final-6f88c2` 各自的 `project/outputs/sunroom-1-6-upper-railing.png`，已目检。资产导入和下表各项退出 0。

| 检查 | 结果 |
|---|---|
| 真实渲染 `visual-sunroom-animation` | 444/0，另抓取落装与完工帧 |
| `sunroom-runtime` | 49/0，覆盖区块刷新、三个修缮阶段、季节和实际存读档 |
| `sunroom-surface-collision` | 49/0 |
| `sunroom-repair` | 14/0 |
| `vegetation-contract` | 515315/0 |
| 摆位核对 | 28 处，0 警告 |

修复前 `20261123-110724-sunroom-plant-bug-4d7ae4` 预期复现 5 项显隐失败，退出 1。最终专项无预期故障或意外错误。发行包未执行。

首次实窗检查调用了已移除的航线表现节点，退出 124。移除测试中的旧调用后，修改前的实窗基线通过。全库功能同步与只读检查仍分别有 551 和 552 项既有问题，均退出 1。只读检查与修改前问题数一致，本次阳光房条款和栏杆资源无报错。

# 2026-11-07 礼品商亭屋顶展开消隐

[主文档](../../GDD_V1.0.md) · [世界规范](../features/world/spec.md) · [世界账本](../features/world/ledger.md)

## 用户要求与实现

用户要求进入附图商亭后能看到室内，顶棚围绕角色展开、平滑消散，离开后再出现，细节由本轮把控。归SEA-WORLD-R25，复用SEA-ASSET-R55既有美术资产。

正式floating_shop.tscn标记78个顶部根：顶板、顶沿、立体招牌、蓝白雨棚、顶盘、顶上弯管/射灯/信号灯及悬挂灯。背墙弯管不属于屋顶；墙体、玻璃、货架、商品、地面、角色与甲板设施保持可见。原47组件与379实例的位置/比例/材质源不重新生成，Blender和GLB不修改。

RoofReveal只拥有该设施的表现状态。Main通过configure_view_subject注入实际玩家和岸上状态查询；不在表现脚本内读取GameState/Economy等全局对象。以当前Visual的局部坐标判室内，跟随平台浮动和设施旋转；圆角入口边界约±5.12m，高度取甲板上0.3m并限高差0.55m。已经进入后延伸0.32m退出缓冲，门边小幅走动不闪烁。船上不触发。

进入约0.95秒，柔边圆孔以角色为中心向外扩张，末段整体淡出；室内保持整个顶盖不可见，避免残留顶上设备遮挡。退出约0.75秒反向恢复，中途往返从当前进度反转，中心在离开时停留于最后室内位置。使用设施局部空间的统一遮罩，所有顶部组件有相同开口。关闭时还原准确的原实例材质引用；开启只为本设施创建少量共享ShaderMaterial，不修改公共材质或网格资源。

不改主场景摆位、镜头、角色行走/碰撞、导航/上下船、支撑浮动或存档格式。状态由当前角色位置自然重建，室内读档无需新增持久字段。原始装配生成器的receipt不刷新，保护正式TSCN手改。

## 本轮验证过程

所有Godot执行均经scripts/run_verification.py建立工程外副本及隔离用户数据，再进入Autoload。真实渲染、退出码、预期故障、非预期错误分别记录。

- 初次20261107-164140-gift-kiosk-roof-reveal-22713c：roof-reveal 364检查/1失败，原因是新增测试误以为独立组件材质override应为null，已改为与加载时原引用比较；没有改生产材质。visual-roof-reveal 74检查/0失败、进程exit0，但NPC新接口需要住所参数而旧Main只传1参数，runner正确判FAIL。图像已亲看：角色/货架/商品可见，孔洞从门内向外展开，闭合后顶盖完整。
- 修正测试后的20261107-164417-gift-kiosk-roof-regression-d22c82：设施独立专项127/0、exit0、runner PASS；实际主场景屋顶专项364/0、商亭集成7129/0、镜头12/0，均exit0，但同一NPC装配接口错误仍使runner FAIL。该主场景批次不能称全绿。独立设施使用正式PackedScene及非恒等旋转摆放，并验证浮动和材质还原，不绕过生产控制器。

最终复验结果与静态契约结果在后续章节追加。预期故障为空；完整无关功能套件、低端设备性能不在本轮执行范围。


## 最终实测结果

最终统一runner副本：`D:/projects/sea-work/verification/20261107-164731-gift-kiosk-roof-final-36558c/report.json`。并行NPC接口修正后，重新取完整主场景快照运行，不改测试为跳过NPC，也不在副本里删场景。

| 专项 | 检查 / 失败 | 进程退出码 | runner |
|---|---|---|---|
| roof-reveal-component | 127 / 0 | 0 | PASS |
| roof-reveal（实际角色进出） | 364 / 0 | 0 | PASS |
| visual-roof-reveal（实际GPU渲染） | 74 / 0 | 0 | PASS |
| gift-kiosk（源实例矩阵、上岸、行走、浮动承载和补给） | 7129 / 0 | 0 | PASS |
| camera | 12 / 0 | 0 | PASS |
| water-layer（相关全世界回归） | 2092 / 111 | 1 | FAIL |

屋顶与商亭范围合计7706检查/0失败，五专项均无非预期引擎/脚本错误；预期故障为空。water-layer的111条失败全部位于并行新增`World/SeaStructures/resident_harbor`，理由为新住所还未具备该套件识别的船只阻挡归属；没有商亭路径失败。本轮不改住所场景或水层测试来消掉这些红项，不将六项合批报告宣称为全通过。

真实渲染逐帧亲看完整屋顶、圆孔展开中间态、室内近景和退出完整恢复，物件没有留在空中遮挡角色。媒体在`D:/projects/sea-work/gift_kiosk/roof_reveal/`：`enter-exit.gif`是真实角色走入/走出连续帧（仅缩放及GIF编码），`inside.png`和`interior-close.png`为实际截图。

只登记本轮七个已验证运行文件和商亭总成prefab/runtime哈希；机器签署见[本轮签署](2026-11-07_gift_kiosk_roof_reveal_verification.json)。主Main含NPC/阳光房等并行修改，保留其未知总哈希漂移，不以屋顶验收替其它功能签署。47源组件、Blender母版、优化源、GLB、公共色板与手动摆位均未修改。旧生成器的receipt不更新，正式TSCN受既有覆写保护。


## 静态交付检查

最终静态检查日志与退出码已写入本轮机器签署。check_feature_contracts.py --sync与无参数检查均exit1：并行GDD新登记的docs/features/residence/spec.md及ledger.md尚不存在，检查器在读取这些文件时抛FileNotFoundError，未能完成全局摘要同步。不替其它施工功能编造空文档或刷新未知哈希来冒充全绿。check_placed_positions.py为4结构/0警告/exit0；git diff --check为exit0（仅LF/CRLF提示）。七个本轮运行文件与最终验收副本SHA-256仍逐一相同。

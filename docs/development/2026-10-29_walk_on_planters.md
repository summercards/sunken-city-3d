# 2026-10-29 种植区可踩踏

本轮按用户截图要求，把固定六格、DIY标准培养土、小型培养土及其蔬菜设为人物可穿行区域。角色可以穿过、停在种植格内；种植、浇水、收获仍须显式操作。同步在原角色框架任务范围内补齐自动交互锚点的一处遗漏。主条款为SEA-BUILDING-R16，关联SEA-BUILDING-R05、SEA-MOVE-R08、SEA-WORLD-R11/R12、SEA-FARM-R11和SEA-INTERACT-R06。

本记录替代同日角色框架交付中“保留种植格占地扣除”的旧口径，旧记录保留用于追溯。

## 正式修改范围

| 文件 | 修改及边界 |
|---|---|
| `godot/src/building/building_catalog.gd` | 两种培养土声明`blocks_actor=false`，提供目录查询。未来需要挡人的摆件可显式声明，不按视觉模型一律加碰撞。费用、工期、尺寸与配方不变。 |
| `godot/src/building/building_space.gd` | 只从行走面扣除明确挡人的占地；可穿行种植格增加内部操作站位，保留侧面候选点。平台外缘内缩、支撑关系及连通保护继续生效。 |
| `godot/src/building/building_world.gd` | 固定六格默认不扣除行走面；DIY恢复资格遵循同一阻挡声明。固定格仍可用显式元数据声明阻挡。 |
| `godot/src/player/states/interacting.gd` | 到位自动长按改用与接近/焦点相同的`focus_position()`，纯节点目标保留原点后备。保留2.2米门槛、模态阻断及业务执行入口。 |

土框、土壤与蔬菜的模型、材质、布局和阶段表现保持原样。人物沿原木面高度连续行走，低矮土框作为可穿行表现，不新增抬升台阶或新楼梯模型。建设占位、承载、重叠限制及作物写入所有权不变；未修改Farm、Crop、奖励、订单、出货、航行或存档格式。

## 当前专项实测

所有运行通过`scripts/run_verification.py`，在Autoload前隔离工程和用户数据，未使用玩家存档。

| 验证 | 当前结果 | 工程外证据 |
|---|---|---|
| `walk-on-planters` | 53项、0失败、退出0；无预期故障及非预期引擎错误 | `D:/projects/sea-work/verification/20261029-230813-pass-through-planter-regression-c576df/report.json` |
| `visual-walk-on-planters` | 原生渲染59项、0失败、退出0；无预期故障及非预期引擎错误 | `D:/projects/sea-work/verification/20261029-230923-pass-through-planter-render-d3bc23/report.json` |
| `building-space / building / building-integration / building-approach / building-open-rules / building-ocean / building-open-seed / building-open-restart / farming / character-motor / ground-space` | 全部PASS、各退出0 | `D:/projects/sea-work/verification/20261029-230802-passable-planter-regression-69f679/report.json` |
| `building-boundary-audit / dock-seed / board-click / minimum-loop` | 全部PASS、各退出0 | `D:/projects/sea-work/verification/20261029-231024-passable-planter-adjacent-5c47eb/report.json` |
| `visual-building-diy` | 原生渲染与鼠标/按键28项、0失败、退出0 | `D:/projects/sea-work/verification/20261029-231124-passable-planter-real-input-f8ba7c/report.json` |
| `interact-focus / visual-plot-shipping` | 锚点边界14项、完整真实输入种植至出货61项，均0失败/退出0，无预期或非预期错误 | `D:/projects/sea-work/verification/20261029-231726-planter-interaction-complete-0a6a9b/report.json` |
| 修正锚点后：`unreachable-menu / pocket-bubbles / farming / walk-on-planters / character-motor / ground-space / actor-presentation / character-space-save / minimum-loop / board-click` | 10组全部PASS、各退出0，无预期或非预期错误 | `D:/projects/sea-work/verification/20261029-231749-planter-final-character-integration-96d9c0/report.json` |

专项在正式场景与角色控制器上覆盖：六个固定格逐格穿过；成熟蔬菜不被踩坏、不触发自动收获、不改变库存；点击、接近、显式收获仍有效；两种DIY培养土种植/浇水后可穿过；站在土格保存恢复有效；人物胶囊仍受平台外围阻挡，海面坐标仍被恢复校验拒绝。

同步更新旧测试中“培养土必须挖空行走面”的断言，保留明确实物阻挡的反例；新增`godot/tests/test_walk_on_planters.gd`和runner入口。边界审计的历史夹道样例现在要求可穿行，不再把种植格当封路家具。

已查看真实截图：

- [固定成熟种植格](D:/projects/sea-work/verification/20261029-230923-pass-through-planter-render-d3bc23/project/outputs/planter-walk-fixed-mature.png)
- [DIY培养土内站立](D:/projects/sea-work/verification/20261029-230923-pass-through-planter-render-d3bc23/project/outputs/planter-walk-diy-planter.png)

## 扩展检查与交付边界

完整`visual-plot-shipping`首轮为61项/11失败/退出1，种植至显式收获部分通过，失败从出货箱屏幕拾取开始。测试仍点击节点旧原点，改用正式锚点的工程外探针降至9失败/退出1；探针为`20261029-231419-shipping-formal-anchor-probe-a6bc68`，两轮失败日志均保留。

随后确认角色状态仍按旧原点检查自动长按：当时人物距视觉锚点0.722米、距节点原点2.393米，超过原2.2米门槛，所以已经走到箱旁仍不执行。该问题在本轮前已存在，不是培养土通行导致。修正角色状态的锚点，并同步测试点击位置，正式复跑完整61项全过；未修改出货、库存、07:00结算规则及场景摆位。`interact-focus`补充视觉偏移、模态阻断、离开2.2米、纯节点后备及目标消失的6项断言，当前14项全过。

当前正式运行脚本相对上轮角色框架交付只改上表4个文件。逐文件哈希、每组退出码和静态门禁记录在`D:/projects/sea-work/audits/2026-10-29-walk-on-planters/`；架构15服务0问题，功能同步与无参检查35功能/459源资产/392运行期哈希0问题，`git diff --check`退出0。

本轮未新增二楼、楼梯、动画素材或功能玩法；未进行目标设备和发行包验收。本轮专项通过不替代旧默认套件尚存失败的单独验收。

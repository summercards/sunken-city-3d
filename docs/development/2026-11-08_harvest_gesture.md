# 2026-11-08 收成动作：固定臂长的自然示意

[主文档](../../GDD_V1.0.md#sea-move) · [功能设计](../features/move/spec.md) · [功能账本](../features/move/ledger.md)

对应SEA-MOVE-R14/R17/R28；SEA-FARM-R13仍拥有成功事件和唯一奖励结算。用户要求收成时手上有示意动作即可，不必接触作物或包口，避免手臂被拉长。

## 修正结果

原`item_receive._pose_arm`按作物轨迹与肩根的距离计算`stretch`，同时为头部净空进一步缩短可达距离，导致上下臂和实际蒙皮一起伸长。本轮移除该追物解算，改为肩根固定、胸前屈肘抬手、左手先收回、右手稍后放下。上下臂长度只读当前Avatar体型的`arm_length`，肘关节沿原局部轴旋转；不为展示物品移动肩根或拉长袖子。

作物仍独立沿现有轨迹在帽顶上方展示，再缩入右侧挎包；包盖同步开合。保留2.4秒、三种作物、成功一次性、全部中断及存档清理。未改Farm注入端口、产量、生长、角色根位移、物理碰撞、导航、正式TSCN或用户手动摆位。

正式源与运行入口仍为`godot/src/player/animation/item_receive.gd`。这是当前sea程序角色表现修正，无Blender/GLB重导。资产由`assets/registry/ledger_index.json`解析到characters分账本，只更新`SEA-CHAR-RECEIVE-001`及该脚本对应的运行资源哈希；保留旧哈希，不批量刷新其他未知变更。版本v009。

## 当前实测

全部运行验证经`scripts/run_verification.py`，在Autoload前隔离用户数据，使用本机Godot 4.6.3；没有读取或修改玩家档。原`GODOT`名字解析未命中可执行文件，按`windows-cli-tool-provisioning`定位运行实例，使用runner已有的GODOT环境变量端口指定现有安装，未改验证脚本。

| 项目 | 结果与证据 |
|---|---|
| actor-presentation | 31项/0失败，exit0，完成标记真，无非预期错误 |
| harvest-receive | 137项/0失败，exit0，完成标记真，无非预期错误；含真实鼠标、E菜单+Enter、三种作物原产量一次性、满包拒绝、7类中断、存读与长帧 |
| avatar-skinning | 80项/0失败，exit0，完成标记真，无非预期错误；实际连续蒙皮仍跟随手腕控制 |
| visual-harvest-receive（首轮） | 150项/0失败，exit0，无非预期错误；12张1280×800原生截图与96帧连续动作。已目视确认胸前手势与短臂；首轮构图裁掉帽上物品顶部，已只调整测试镜头的瞄准高度，复拍见最终记录 |
| avatar-customization（首轮） | exit124，240秒超时，未完成标记；没有FAIL断言或非预期脚本/引擎错误。几何矩阵与密集收成采样已完成，到主场景存读阶段触发超时；不计为通过，600秒上限重跑中 |

上述非渲染批次：`D:/projects/sea-work/verification/20261108-032857-harvest-gesture-0a4892/report.json`。首轮真实渲染：`D:/projects/sea-work/verification/20261108-033145-harvest-gesture-render-2edc73/report.json`。

新增回归逐帧覆盖五组体型×30/60/120FPS，分别比较两侧上下臂控制长度、实际`upper_skin/lower_skin`纵向缩放与Avatar原始体型比例，检查肩根、有限变换与根位置。该检查直接约束用户反馈中的真实拉伸原因，不再把“手掌碰到作物”作为通过条件。现有体型专项保留衣服/头部穿插检查。

## 错误分类与范围

预期拒绝：背包满、未知作物请求、主动取消/替换；均为正常业务返回，没有预期引擎错误。现有外部材质UID回退警告单独保留，不冒充脚本错误，也未通过刷资产哈希掩盖。首轮全体型超时记录保留。

最终复拍、必要集成、全体型重跑和文档门禁结果在后文追加。未执行：手柄/触屏、低端设备性能、所有外观组合穷举、新的获物业务入口；本轮不新增音效或资产授权结论。

## 最终复验与可查看证据

| 项目 | 最终结果 |
|---|---|
| avatar-customization重跑 | 3559项/0失败，exit0、passed=true、完成标记真、unexpected_errors空。包含衣服/头部真实蒙皮穿插、五组体型密集26相位、三种展示物、完整档案存读；首轮exit124留为过程记录 |
| visual-harvest-receive最终复拍 | 150项/0失败，exit0、passed=true、完成标记真、unexpected_errors空；12张1280×800原生截图与96帧。已目视检查南瓜展示、收包与抬起途中的连续帧，确认胸前自然屈肘、手臂不拉长；测试构图包含帽上作物 |
| character-space-save | 10项/0失败，exit0、passed=true、完成标记真、unexpected_errors空 |
| save-seed | exit0、passed=true，为集成提供独立存档种子 |
| framework-integration当前修正 | 52项/1失败，exit1；唯一失败`interaction opens action bubbles without planting`，runner将该FAIL行列为unexpected_errors，不记为通过；没有SCRIPT ERROR或SHADER ERROR |
| framework-integration旧动作对照 | 同样52项/同一1失败、exit1。复制同一份最终隔离快照，只把item_receive.gd恢复成修正前已登记哈希6da04912…；其余代码/场景/测试保留该快照。说明该交互菜单失败独立于本次收成动作修正，本轮不改菜单规则迎合断言 |
| feature contracts --sync / 普通检查 | 均exit1，分别27/30项；43功能、967源资产、1381运行资源。剩余为鱼群/土壤源、NPC/商店/海底材质/主场景/导航/存档等本轮范围外哈希漂移；普通检查另含SEA-SHOP/SEA-RESIDENT主摘要未同步及派生索引过期。sync按工具规则拒绝在有问题时写入摘要；没有强刷未知哈希。本轮获物源、运行记录及source index已精确同步，未报本轮动作漂移或R28承接缺失 |
| placed positions / diff --check | 均exit0；3个手摆结构、0警告。源/测试/功能文档/账本/角色契约/本资产manifest差异无空白错误 |

最终复拍/存读/集成报告：`D:/projects/sea-work/verification/20261108-033358-harvest-gesture-final-e9b3b0/report.json`。体型完整通过：`D:/projects/sea-work/verification/20261108-033430-harvest-avatar-final-0e097b/report.json`。旧动作对照：`D:/projects/sea-work/verification/20261108-033751-harvest-gesture-baseline-d22e68/report.json`及同目录`baseline-control.json`；生成脚本在`D:/projects/sea-work/probes/harvest_gesture_baseline.py`，执行的是正式runner的main与隔离流程。最终门禁日志与退出码：`D:/projects/sea-work/verification/20261108-harvest-gesture-gates/report.json`。

[仓内机器摘要](2026-11-08_harvest_gesture_verification.json)逐项保留退出码、完成标记、预期/非预期错误、未执行项和报告路径，并确认正式动作与测试文件逐字节等于最终受测快照。当前动画源SHA-256：`92afa0c7fa39ed7ea496f5a8bb230e2f7256132e03138254509e2430ab790434`；原源哈希按HEAD的CRLF字节复核为`6da04912c9b099b193b11785521ae5b6768afaa0397f25fae498c6f92f29ef9d`。

可查看预览：`D:/projects/sea-work/previews/harvest-gesture-20261108.gif`，由最终实景96帧以FFmpeg转码，15FPS、640×400、3.2秒，编码exit0。该文件及所有截图均位于工程外。整体功能仍partial，不将局部修正或对照失败记为整套工程通过。
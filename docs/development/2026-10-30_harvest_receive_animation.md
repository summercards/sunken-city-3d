# 2026-10-30 收获举高与收包动画

所属条款：SEA-MOVE-R14（动作与生命周期）、SEA-FARM-R13（成功事件）、SEA-CROP-R14（实物副本）；资产归SEA-ASSET-R02/R03/R23。主文档、独立spec/ledger、角色契约与模块接口已同步。

## 交付行为

收获成功后，角色俯身取物，双手举到帽顶上方，停留约0.43秒，再沿身前弧线送到右侧挎包，包盖打开、物品缩入、包身轻微鼓起后合盖，恢复站姿。全程2.4秒，播种/浇水保留原1.1秒。生菜展示一株，番茄展示一颗，南瓜展示一颗带蒂的果实；奖励数量按原Farm返回值，代表实物不等于只获得一个。

角色当前正式源为程序节点模型，仍沿用此体系。`harvesting_action.gd`消费独立`item_receive.gd`，复用动作token及开始/完成/取消生命周期；没有改角色主碰撞、导航、根位移或正式TSCN。肩部抬起、袖长和双手支撑由表现采样，取消时恢复。新增可见皮棕挎包及斜挎带，包口是收物落点。

FarmPlot成功acted→FarmField→Main统一接线。原长按开始提前播收获、气泡命令再次播动作两条路径已移除。气泡和E成功都只启动一次；满包与未成熟不播放成功。Farm规则代码、注入端口、奖励数量、成长与番茄续茬不变。奖励在原业务时点结算；走开/取消动画不撤回奖励，动画完成也不再发奖。

`HarvestVisual.create`从CropCatalog的成熟模型复制已有mesh/material；生菜按菜心的水平距离选择一簇叶片，番茄/南瓜按模型部件名选择一份果实。不改现有GLB、材质、地格四阶段或授权状态。临时物品不含碰撞，不进入存档。

## 契约与资产登记

- 正式入口：`Character.play_receive_item(crop_id)`、`play_farm_action(event,payload={})`、`play_action(id,context={})`；状态仍由ActorController拥有。
- 新资产`SEA-CHAR-RECEIVE-001`从总索引解析到`assets/registry/ledgers/characters.json`；源/运行均为本次程序动作/挎包文件，manifest列出依赖与当前验证。
- 原角色整体尚未逐项核对的源与授权仍pending；新条目不冒充整个人物制作验收。复用作物资产原来的源级四视图未执行项保持登记。
- 当前接入收获；商店、仓库存取、海面拾取没有自动触发这段动作。网页原型未同步修改。

## 当前实测

验证均通过`scripts/run_verification.py`，在Autoload前创建独立用户目录，未读取或修改玩家档。Godot 4.6.3，真实渲染使用NVIDIA GeForce RTX 4060 Ti / Forward+。

专项证据：`D:/projects/sea-work/verification/20261030-075745-harvest-receive-acceptance-22c9a2/`；最终实景/连续动作：`D:/projects/sea-work/verification/20261030-075825-harvest-visual-delivery-755975/`。完整退出码和错误分类见各自`report.json`；[仓内验证摘要](2026-10-30_harvest_receive_verification.json)保留结果索引。

| 项目 | 当前结果 |
|---|---|
| actor-presentation | exit 0，31项/0失败，原生命周期/注册/替换与播种浇水兼容通过 |
| harvest-receive | exit 0，80项/0失败，含真实鼠标与E输入 |
| visual-harvest-receive | exit 0，93项/0失败；三品种×取物/举高/收包/站姿12张原生截图，另有96帧连续动作 |
| initial-planters | exit 0，247项/0失败，六格完整播种/三日浇水/收获回归 |
| farming / crops | exit 0，各35/60项，0失败 |
| character-space-save / sleep-cycle | exit 0，各10/33项，0失败 |
| save-seed | exit 0，进程间存档种子写入成功 |
| framework-integration | exit 1，44项/1失败；撤去本次动画的对照也为同一失败，见下方 |
| feature contracts --sync / feature contracts / architecture | 均exit 0；35功能、460源资产、393运行资源哈希，0问题 |

覆盖三品种原产量、一次成功一次表现、头顶高度和双手位置、包盖开合/收物隐藏、真实鼠标气泡→接近→长按→收获、E物理按键输入→长按→成功、满包保留作物、七类中断、30/60/120FPS、长帧、正式存档恢复。正常完成/取消期间不改业务快照与人物根。

真实截图位于专项证据目录`project/outputs/receive-<crop>-<phase>.png`。已目视检查三种实物的举高及收包姿势、手部和包口。产物保留工程外，不复制PNG进仓库。

集成证据：`D:/projects/sea-work/verification/20261030-075148-harvest-integration-d1061d/`；角色动作与初始六格：`D:/projects/sea-work/verification/20261030-075450-harvest-delivery-7d535f/`。通过项目均无非预期脚本/引擎错误。

连续预览：`D:/projects/sea-work/previews/harvest-receive-20261030.mp4`（1280×800、30FPS、3.2秒）及同名GIF（640×400、15FPS）。源为最终实景运行直接导出的96帧，FFmpeg编码退出0；动作通过真实FarmPlot成功事件触发。初版预览被存档恢复的宽镜头覆盖，已重新固定近景并重新导出；宽镜头试跑不作为最终预览。

## 失败记录与未执行项

开发首轮runner受Windows默认GBK影响无法读取UTF-8工程配置，后续统一以`PYTHONUTF8=1`执行，未改动玩家配置。初版测试误把RefCounted时钟当Node调用导致脚本错误；修正后重跑。首版输入探针按钮坐标缺括号、满包fixture使用了不存在的plank ID，均已修正；袖长测试改为测真实手掌节点坐标。以上试跑不计当前通过，旧日志保留。

本次预期故障仅满包拒绝与主动中断，均为正常返回，无预期引擎错误。正式检查中的非预期脚本/引擎错误由report.json单列，不以截图代替退出码。既有导航agent_radius取整警告保留。

综合回归唯一失败是`unsafe world position rejected before economy apply`：旧用例要求拒绝船位`[999,1,999,0]`，当前自由海域实现允许该位置。工程外对照保留其他当前改动，只把Character与harvesting采样恢复HEAD，并撤去Main的本次四处接线，仍为44项/同一1失败。对照由统一runner隔离并运行，证据`D:/projects/sea-work/verification/20261030-075513-harvest-without-animation-control-cecf68/`；`animation-baseline.json`记录恢复范围与哈希，脚本`D:/projects/sea-work/probes/harvest_without_animation_control.py`。本轮不把该测试记为通过，也不改自由航海规则来迎合旧断言。

本次相关代码仅Character、harvesting sampler、独立item_receive、HarvestVisual及Main农作成功事件/旧调用清理，原有表现专项和runner增加验证入口；设计与账本按上述条款更新。共享工作区同期海面拾取/存档等其他改动保留，未回滚或代签验收。新增资产只插入自己的源/运行哈希，未知历史资产未重新登记哈希。

未执行：Blender角色制模/动作导出（本次无对应资产）、移动端/触屏、手柄、多分辨率、其他获物入口、全世界穷举。未新增获得音效。

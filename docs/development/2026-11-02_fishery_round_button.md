# 渔场收获圆按钮与入口精简（2026-11-02）

用户指出原3D鱼图标/收获文字存在海面切边，要求改为与现有操作圆按钮同款，地点只保留建造渔场、收获鱼类。

## 最终改动

- 新FisheryMarker独立CanvasLayer，从原交互锚点投影到屏幕，直接复用action_bubble的76px青绿圆底、奶油描边、白色action_fish剪影和既有悬停/焦点反馈；数量在圆下奶油胶囊显示。移除原Sprite3D/Label3D，按钮不再进入海面深度、折射和透明合成路径。
- 圆按钮可直接点击，转发既有可达性检查、角色走近与收获命令；不需要再展开服务菜单。无鱼显示“生长中”并说明原因，不发奖。UI不写业务库存，不复制产鱼逻辑；E键仍使用同一FisheryModel.harvest命令。
- 未建造时旧木牌只提供“建造渔场”；建成后旧木牌隐藏，只提供“收获鱼类”。移除此地点商店/仓库/出货箱及订单入口；全局右上菜单等既有服务入口保留。旧木牌的E键也只打开渔场建造页，完成交互后不悬留自动操作。
- 镜头移动/缩放更新投影，按钮保持屏幕尺寸，边缘留出数量位置；未建造、镜头背后/过远、标题、模态及潜水时收起。独立按钮接收指针，原3D锚点不再额外画手形悬停图标。

归SEA-AQUA-R04/R10/R11、SEA-UI-R48。建造成本100木板+50鱼、每4游戏小时3鱼/上限24、背包满保留储量、原子领取、防重复、新旧存档规则保留。原渔网/浮漂/独立彩色鱼群/岸坪通行和电线杆未修改，不重新导出Blender或覆盖手工TSCN。

## 入口与资产

- godot/src/ui/fishery_marker.gd：只管屏幕按钮及harvest_requested请求，世界位置/状态/可见性均通过注入端口获取。
- godot/src/aqua/fishery_harvest.gd：只持3D交互锚点与注入业务命令，不创建任何3D图标或文字。
- main组合根绑定按钮请求，分阶段提供唯一地点动作；旧木牌的opened也改接建造页。
- 复用UI-ACTION-HANDDRAWN-001的action_fish原图，未新造AssetID或改图片源/色板；新代码与已审阅修改逐路径同步运行资源清单，未知工作区哈希不批量接纳。

## 当前实测

全部Godot运行验证均使用scripts/run_verification.py，Autoload前隔离用户数据。第一轮fishery 26项、fishery-production 32项均通过；初轮新Presenter有Control全锚点同时写size的WARNING，改为左上锚点并手动按视口设置尺寸后复验，该新WARNING不再出现。

圆按钮/生产/设施专项：
`D:/projects/sea-work/verification/20261102-163200-fishery-round-ui-a91f70/report.json`

- fishery-production 32项、visual-fishery-production 34项（原生渲染）通过，含真实root.push_input鼠标按下/抬起→按钮→角色接近→领取入包，空渔场不打开服务、不重复发奖，菜单仅收获鱼类、原3D图标和文字均不存在，原存档/产鱼边界回归。
- fishery-environment 42项、visual-fishery-environment 46项均通过，原岸坪/真实胶囊/电线杆/围网水域/鱼群/新旧档专项保留。

最终增加镜头拉近/按钮尺寸稳定检查及近景截图，证据：
`D:/projects/sea-work/verification/20261102-163821-fishery-round-delivery-4c24ea/`

结果在最终report.json中逐项记录，原生图位于project/outputs/fishery-harvest-ready.png、fishery-harvest-close.png和fishery-harvest-menu.png。全景已亲眼验收：白色鱼剪影和圆下数量完整，未再出现海面切边；地点不再出现三项服务气泡。

预期故障：空储量、满背包、重复领取、坏档均由API拒绝，无预期引擎错误。已有导航体素精度WARNING单列，不当作预期故障。未执行手柄/发行平台、现实离线收益、长时人工游玩及整套core；没有写入玩家存档。

主文档、SEA-AQUA/SEA-UI设计与独立账本、UI资产消费者及运行清单已更新，文档同步检查与最终统计在收尾记录。

追加复验说明：上一轮final副本在共享工作区迁移水层分类时抓到空字符串export_enum参数，Godot4.6.3拒绝编译，导致继承SceneComponent的鱼群等未加载；该副本的后续调用错误不算圆按钮验收通过。随后相关注解已改为合法非空枚举，默认空字符串待登记语义保留，当前源重新经统一runner验证；没有回退该水层声明。

## 最终结果

| 检查 | 当前结果 | 退出码 | 状态 |
|---|---|---:|---|
| fishery-production | [fishery-production] 33 checks, 0 failures | 0 | 通过 |
| visual-fishery-production | [fishery-production] 36 checks, 0 failures | 0 | 通过 |
| fishery | [fishery] 26 checks, 0 failures | 0 | 通过 |
| pocket-bubbles | [pocket-bubbles] 59 checks, 0 failures | 0 | 通过 |
| minimum-loop | [minimum-loop] 141 checks, 0 failures | 0 | 通过 |
| fishery-environment | [fishery-environment] 42 checks, 0 failures | 0 | 通过 |

上表除visual项为真实渲染外均为headless，所有非预期SCRIPT/SHADER/引擎错误为0。补充设施真实渲染visual-fishery-environment 46项0失败见163200专项；最新版设施逻辑42项再次通过。近景已亲眼检查，白色剪影、圆边与数量完整；暖金色为同款按钮既有的悬停/焦点反馈，默认青绿。

最终运行源码的FisheryVisual新增water_layer/water_layer_role导出元数据已逐行审阅，保持跨水线分类且未改模型/通行行为，专项在当前声明上重新实测后只更新该脚本基线。没有批量接纳其他变更。

文档门禁：按要求运行check_feature_contracts.py --sync及无参数检查；当前仍受并行水层登记写入的35项场景资源哈希漂移阻挡（无参数检查另报派生索引未同步），包括建造件、水下建筑、船、旧设施及区块。没有用批量重算哈希掩盖这些变化；功能条款/独立账本与本任务源码登记没有新增报错。feature-sync.log和feature-check.log保留原始输出。主文档正文、功能设计和账本已更新，派生feature_index待全工程水层登记收口后由统一工具写回。

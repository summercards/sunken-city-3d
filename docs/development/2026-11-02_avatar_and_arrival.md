# 新旅程码头开场与角色定制 · 2026-11-02

本次交付把新存档的「实景标题 → 真实泊位站立 → 镜头拉近 → 取名 → 外观搭配 → 旅人证确认 → 原子保存 → 日常生活」接入正式Godot工程。既有玩家继续原入场；暂停菜单「我的模样 · 姓名与外观」可再次修改，取消完整还原，确认同时保存整局。未操作玩家实际存档；所有运行由统一runner在Autoload之前隔离用户目录。

功能分别由[SEA-AVATAR设计](../features/avatar/spec.md)/[账本](../features/avatar/ledger.md)、[SEA-ONBOARDING设计](../features/onboarding/spec.md)/[账本](../features/onboarding/ledger.md)管理。主文档只登记全局关系，不复制详细规则。

## 内容与维护边界

- AvatarProfile唯一写入已提交档案；界面草稿深拷贝。AvatarSession以注入save Callable协调确认、失败回滚和重试。主装配不实现姓名或外观规则。
- AvatarCatalog提供8类、18稳定槽位、95选项。肤色6、发型6、发色8、眼形4、瞳色6、眉3、鼻3、嘴4、脸颊3、上衣4、裤2、鞋3、帽4、眼镜3；上装/下装/鞋/帽各9配色。无性别限制。
- 原创程序几何按用户随后提供的指定图校准比例（下节追加验收优先于最初通用头身设定），保留BodyPivot/HeadLook/肩肘髋膝、原挎包、潜水装备和动作消费者。根缩放1，米制、+Y上/+Z前，胶囊0.22m/1.30m保持。没有使用动物之森角色、图案或图标，没有制作或声称审计Blender/GLB。
- 新生产资产经ledger_index路由：SEA-CHAR-AVATAR-001（角色程序源）与SEA-UI-AVATAR-001（创建界面），清单记录逐文件哈希。字体、船与码头沿用原资产各自的来源登记，不替旧资产补签授权。
- `profile.version=1`独立顶层快照，根存档v4保持。旧缺profile经decode/直接restore显式补已完成默认旅人，存在但坏的profile拒绝；未来外观ID保留、当前默认展示。`design_refs`和`extensions`往返保存，16KiB预算；当前只预留DIY设计引用，没有绘图、外部模型导入或分享。
- 创建期间主装配锁住玩法/日历/经营/天气/自动存档，水面继续表现；ArrivalFlow与ArrivalCamera通过注入泊位/相机端口协调，不反向依赖Main/Economy。
- 正式场景TSCN、导航布局、经营数值与网页原型未由本次重生成。Main已有大量未提交改动全部保留。

## 视觉与输入验收

界面使用现有圆体、奶油纸张、青绿选中与暖黄确认；左侧真实人物，右侧可滚动目录。已检查1280×800、1600×1000、1920×1080纸页、页签和页脚可操作，真实鼠标取名→换发型→滚动到眼镜→旋转→确认保存→再次编辑→取消；真实键盘先空名Enter，再继续输入，不能跳过姓名。

首轮截图暴露栏杆挡住身体、发顶过高、条纹悬浮：分别修正为沿码头向海取景、压低圆润发顶、材质贴身条纹。额外输入测试发现空名提交后文本框退出编辑，已启用keep_editing_on_text_submit，保留错误提示与输入焦点。鼠标/滚轮测试事件补齐按下与松开；旧昼夜标题夹具明确标记已完成角色，继续独立测试旧档流程，不把新旅程当旧档入场。

当前原生截图存于工程外：

- `D:/projects/sea-work/verification/20261102-190320-avatar-visual-accepted-3cf0fc/project/outputs/avatar-02-name.png`
- 同目录`avatar-03-hair-1280.png`、`avatar-03-hair-1600.png`、`avatar-03-hair-1920.png`
- 同目录`avatar-05-glasses.png`、`avatar-06-turn.png`、`avatar-07-card.png`、`avatar-08-gameplay.png`

## 当前专项与退出码

机器摘要见[本轮验证JSON](2026-11-02_avatar_and_arrival_verification.json)。下列目录为当前独立隔离运行，均由`scripts/run_verification.py`启动；每项退出码/预期错误/非预期错误保存在原report.json。

| 运行 | 覆盖 | 当前结果 |
|---|---|---|
| 185754-avatar-integration-b35b6c | avatar 133项、avatar-restart 5项、onboarding 22项、save-reset 27项、save-protection及配对seed、framework-integration 44项、character-motor 42项、actor-presentation 31项、harvest-receive 80项 | 11项入口全部exit=0，非预期错误0 |
| 185956-avatar-final-3e24a4 / onboarding | 增加未输入默认名时Enter拒绝，当前开场23项 | exit=0，非预期错误0 |
| 190320-avatar-visual-accepted-3cf0fc / visual-avatar | 真实键鼠、附件滚动、三分辨率、确认与重开取消37项 | exit=0，非预期错误0 |
| 同上 / title-clock-seed、visual-title-screen-day、visual-title-screen-night | 已完成角色旧档昼夜时刻/标题/实际入场 | exit=0，非预期错误0 |
| 190531-avatar-dawn-input-4c3161 | 清晨旧档冷启动与原始点击路径，补明确鼠标移动及点击到达断言 | 见机器摘要 |

早期失败证据保留：185057-avatar-first（测试的JSON数字类型比较与StringName扩展键）；185236-avatar-v2（原测试窗口坐标未转换）；185956-avatar-final与190158-avatar-ui-input（新增输入组合发现焦点/模拟释放问题）；190320清晨旧标题点击未命中，旧测试补鼠标移动与点击到达断言后独立复测。未删除失败目录，也没有用历史通过替代当前失败。

Main运行哈希变动先与`173802-surface-building-inventory-render-570ec1/project/src/bootstrap/main.gd`核对，该文件的原始SHA-256精确等于既有登记`052bfe5f68f49180ee526fcdca14a165d2d0ac26355d7c82965a0e662faca7a3`；差异只有本轮角色/开场接线，再更新该单一路径。其它运行/源哈希未批量刷新。

## 未执行与后续范围

未执行真实存储断电/磁盘满/移动设备/触摸/手柄/中文系统IME人工长流程/发行包验收；存储失败以注入失败返回验证回滚与重试。当前环境为Windows Godot4.6.3 Forward+ / RTX4060Ti。中文姓名经过实际文件保存与独立进程恢复；系统IME候选框属于设备项。未来DIY绘图与内容仓库留独立扩展，尚未制作。已按用户要求完成自行比例和画面验收；本次标记已实现待完整验收，设备未执行项单独保留，不影响本轮按用户指定图自行验收。

## 用户指定角色比例 · 最终追加验收

用户要求「角色比例严格按照这个的来，自己进行验收」。原始230×350截图复制到art_source/characters/avatar/v001/reference_proportions.png，原始像素不变；reference_contract.json记录人工轮廓标点、可见部位和测量误差。参考图不进入Godot运行工程或导出包。比例验收不再使用之前的通用2.6头身估计。

调整：加宽且压低头脸，收窄肩和腰，延长相对旧版的腿、缩小手脚；球形上身改圆角裁片式轮廓，去掉腰部鼓包，补齐肘膝连接。礼帽、马甲、皮鞋与烟紫色作为可保存目录选项加入。无帽发顶约1.26m，基本肩半宽0.162m、髋高0.42m，功能胶囊仍0.22m/1.30m，根及整体表现根缩放保持1。腕部IK和挎包按同一尺寸表适配，动作时长、奖励边界与1.60m举物高度保持。

实际网格投影从Mesh顶点计算，不读取一组常量假装验收。固定近似原图3/4相机（方向-0.42,0.23,1），截图以等高、同鞋底线对齐，仅均匀缩放和移动相机，不单轴拉伸。解剖对照板因原图未背包，仅暂藏可选配饰挎包；正式创建画面另外验证真实挎包和全部当前流程。

| 实测项 | 原图目标 | 当前实际 | 相对偏差 |
|---|---:|---:|---:|
| 头脸宽/高 | 1.5357 | 1.5160 | 1.28% |
| 肩宽/头宽 | 0.5814 | 0.5876 | 1.07% |
| 躯干宽/头宽 | 0.4186 | 0.4247 | 1.44% |
| 腿长/头高 | 0.9048 | 0.9226 | 1.96% |
| 躯干长/头高 | 0.8214 | 0.8214 | <0.01% |
| 双脚跨度/头宽 | 0.3798 | 0.3818 | 0.53% |

所有条目阈值为相对偏差≤5%，本轮最大1.96%。源图约±3px标点不确定性保留在契约中，不声称从模糊单图恢复唯一三维尺寸。第一轮目视仍发现肩部断开、躯干鼓、膝肘接缝与帽子/对照机位不合适，已迭代修正后再验，未以第一份绿项代替最终自验。

最终目录：`D:/projects/sea-work/verification/20261102-192735-avatar-reference-acceptance-8096ac`。`outputs/avatar-reference-three-quarter.png`、`avatar-reference-front.png`、`avatar-reference-side.png`和`avatar-proportions.json`为原生渲染/实测；创建三分辨率截图位于同目录。该批次角色专项随新95选项重新运行；原比对早期结果为历史证据。当前摘要见本轮verification.json的reference_proportions_final批次。

资产SEA-CHAR-RECEIVE-001本次v002是已审阅腕部静止尺寸/缩小挎包适配，仅更新自身源与共同尺寸依赖；其余旧动作源哈希保持。原v001源可在此前190320隔离副本找到。商业参考图权利不作主张，程序几何和UI为项目新写；自验完成不需要用户重复审批。


最终静态门禁：`check_feature_contracts.py --sync`与无参数复核均exit=0，39功能/580源资产/515运行哈希/0问题；`check_architecture.py`exit=0，17独立服务/0问题。并发SEA-ASSET-R41仅补「设计计划、制作与验收待回填」承接行，未认定屋顶农场完成。严格保留原未知来源状态；除本次已审阅Main、获物源及新增角色/UI/目录外，未批量刷新哈希。

最新专项总计8入口全部exit=0，分别为比例原生渲染13项、角色140项、跨进程5项、开场23项、物理42项、动作生命周期31项、获物80项、实际界面键鼠37项；非预期错误0。用户要求自行验收已执行，最终等高对照、正面、侧面和创建界面均亲眼检查。

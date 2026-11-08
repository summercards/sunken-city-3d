# 2026-11-08 NPC先对话，再进入功能

[主文档](../../GDD_V1.0.md#sea-resident) · [居民设计](../features/resident/spec.md) · [居民账本](../features/resident/ledger.md)

用户要求点击NPC后先面向玩家，在现有底部对话框说话，有功能时在右侧出现小菜单；初次介绍、概率日常和满足条件的剧情先于功能问候。此次只改Godot正式交互和展示，不动建筑/Marker用户摆放。

实现：Main对NPC绕过世界操作气泡，仍经原approach/Interactor到位后瞬发；NPC停止日程并朝玩家转身，玩家面向NPC。NpcSession入场自动请求NpcService.start_conversation。未听完初见按既有last_talk_day重听；之后既有条件剧情优先，剩余按游戏日确定性25%取样插入日常，否则直接进入功能问候。读完台词才出现“商店/职业功能、聊聊、退出”。人物资料、话题、礼物、事件、请求、关系网保留在主动选择的聊聊路径。

展示直接注入HUD已有CharacterDialogue实例。CharacterDialogue新增外部会话呈现端口，NPC继续持有DialogueRunner与所有结算；不把NPC会话当作开场narrative再次取消自己。首确认补全、次确认推进、分支在右侧选择；关闭/暂停/睡眠/室内/读档清理会话与选项；NPC本身不买卖。阿店初见为南边海域漂流来客三句介绍，营业问候“今天的库存还有这些，看看吧。”。

新增条款为SEA-RESIDENT-R19/R20/R21、SEA-INTERACT-R28、SEA-UI-R58、SEA-SHOP-R11。npc.version仍1，无新随机/seen_intro存档字段；首次听完沿原talk每日+16，完成记录沿原seen_events/choice_flags，请求和Inventory交易规则未改。

运行均经scripts/run_verification.py在Autoload前隔离用户目录，--skip-title --nosave，不读写默认用户槽位。引擎由本机运行进程定位为I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe；PowerShell设置PYTHONUTF8=1避免默认GBK读中文文档失败。真实渲染用Vulkan Forward+ / RTX4060Ti。

## 当前运行证据

- 首轮npc-rules 655/0，exit0；npc-world旧“按Enter进菜单”契约失配，72/2且有session_id访问错误，保留20261108-103339-npc-conversation-compile-c9380a原报告，已更新新流程测试，后续136/0覆盖。
- 20261108-103558-npc-conversation-main-65fea3：414/2，exit1，两个失败把1280窗口像素误当1600逻辑画布；改用实际get_visible_rect，不降低内容完整/不重叠断言。
- 20261108-103800-npc-conversation-visual-4c7860：438/0，exit0，unexpected_errors为空；24张PNG，已查看四张联系图全部24状态，另打开船老大功能问候原图。七人初见/功能问候、两店、剧情前后、三种窗口及聊聊菜单。1920×1080窗口原KEEP画布输出1728×1080，明确记录实际PNG尺寸；后续EXPAND工况另拍，不把窗口名冒充图像像素。
- 20261108-104003-npc-conversation-regression-dbf1e4：npc-world136/0、npc-rules655/0、shop-rules260/0，均exit0；profile旧菜单层级及save旧gifts入口失败保留。资料测试显式走聊聊，确认帧之间等待；存档适配真实新入口后重跑，不改生产规则。
- 20261108-104028-npc-conversation-profile-1f9396：npc-profile-ui1387/0，exit0，7人公开资料、隐私、28话题、42看法、9关系、键鼠导航、取消/过期按钮和无副作用仍通过。
- 20261108-104131-npc-conversation-final-68aefe：新增E测试首轮使用push_input只发UI事件，没有更新Input轮询，七人14项失败，保留日志；修为Input.parse_input_event模拟真实按下/释放，未改生产E键。该批npc-save 702/0，exit0，严格坏档、整局恢复、确认/商店中读档、未来档保护通过；seed/restart仍运行中。

本轮最后报告、真实渲染逐图审阅、未执行项、退出码及全局门禁将追加在下节；不以过程失败冒充最终通过。


## 最终签署：本次交互专项通过（2026-11-08）
当前工作树七个生产脚本逐文件LF归一化字节与release隔离副本一致，SHA-256证据保存在工程外acceptance.json。当前NPC交互实现完成，整体功能仍implemented，不冒称全产品verified。
| 专项 | 检查数 / 失败 | 退出码 | 报告目录 |
|---|---|---|---|
| npc-conversation | 473 / 0 | 0 | `20261108-104749-npc-conversation-headless-final-aad8b0` |
| visual-npc-conversation | 498 / 0 | 0 | `20261108-104628-npc-conversation-release-149113` |
| npc-rules | 655 / 0 | 0 | `20261108-104003-npc-conversation-regression-dbf1e4` |
| npc-world | 136 / 0 | 0 | `20261108-104003-npc-conversation-regression-dbf1e4` |
| npc-profile-ui | 1387 / 0 | 0 | `20261108-104028-npc-conversation-profile-1f9396` |
| npc-performance | 61 / 0 | 0 | `20261108-104628-npc-conversation-release-149113` |
| shop-rules | 260 / 0 | 0 | `20261108-104003-npc-conversation-regression-dbf1e4` |
| npc-save | 702 / 0 | 0 | `20261108-104131-npc-conversation-final-68aefe` |
| npc-save-seed | 476 / 0 | 0 | `20261108-104628-npc-conversation-release-149113` |
| npc-save-restart | 202 / 0 | 0 | `20261108-104628-npc-conversation-release-149113` |
| minimum-loop | 112 / 0 | 0 | `20261108-104749-npc-conversation-headless-final-aad8b0` |
| keyboard-entry | 39 / 0 | 0 | `20261108-104511-npc-conversation-compatibility-c8b43f` |
| click | 39 / 0 | 0 | `20261108-104511-npc-conversation-compatibility-c8b43f` |

13个独立入口合计5040项、0失败，全部exit0、completion_marker=true、unexpected_errors=[]。release中额外一次真实渲染npc-conversation 498/0是重复覆盖，不计入以上合计。所有报告父目录为`D:/projects/sea-work/verification/`。

真实渲染最终报告为`20261108-104628-npc-conversation-release-149113/report.json`：visual-npc-conversation 498/0，25张PNG。原始输出`project/outputs/npc-conversation/`；工程外另复制到`D:/projects/sea-work/outputs/npc-conversation/final/`。已查看5张联系图的全部25状态，含七人介绍/服务、两店、正确船老大现场的剧情及分支、三种窗口与聊聊。最终layout/chat PNG分别实测1280×800、1600×1000、1920×1080；EXPAND只用于验收窗口测试，不改项目原KEEP设置。画面无中央资料面板入场、底部台词与右侧选项可读、边界完整。复核页：`D:/projects/sea-work/outputs/npc-conversation/acceptance.html`，机器摘要同目录`acceptance.json`。

过程失败继续保留：104131的E UI事件模拟缺少Input轮询，104243继承旧快照14项E失败；104334已修E且七人均通过，但重复回店的1.7m测试站点落在柜台/障碍附近，428/1。最终重复回店改走3.5m可达前点与原approach链，不放宽生产碰撞或到位阈值。104243还有同一重复站点失败，总460/15，最终release无此问题。104131跨进程回看202/1来自把新入场剧情合法提交也算作回看副作用；已把基线放到进入档案后、回看前，最终202/0。104511性能61/1因旧测再次start talk（入场已自动开始），最小循环112/1因旧测要求底部UI实例为null；改为断言已有活动对白、系统提示时底部panel不可见，最终分别61/0和112/0。均未靠改生产规则取绿。

预期故障：最终13项无预期故障、无非预期错误。引擎导航agent_radius取整与旧资源UID回退警告如实保留，未记成业务失败。未执行项：完整远海航程集成、全部25事件所有分支的人工游玩、触屏/手柄、低端/发行包和长期FPS；已有完整规则内容检查、当前分支/取消/回看/存档/两店购买不是这些未执行项的替代。用户美术主验仍以用户反馈为准。

结构校验：`python scripts/check_architecture.py` exit0（25独立规则/存储服务0issues）；`python scripts/check_placed_positions.py` exit0（3结构0警告）；`git diff --check` exit0。`godot/scenes/main.tscn`无本次diff，既有用户transform未改。工作区同时存在其他任务的ocean_population、海面采集测试/抓图及最初11个.glb.import改动，未覆盖或签为本任务成果。

全局门禁没有通过：`PYTHONUTF8=1 python scripts/check_feature_contracts.py --sync` exit1、45issues；普通检查exit1、46issues（额外derived stale）。3项source哈希及42项runtime哈希漂移；`--sync`在有issues时按脚本设计不写派生索引。日志在`D:/projects/sea-work/outputs/npc-conversation/contracts-{sync,check}.log`。只读溯源`hash-origin-audit.json`证明本次涉及的Main、NpcPanel/Service/Session/Presenter与dialogues登记基线连HEAD也不匹配；NpcInteractable基线匹配HEAD，本次已知0.12→0改动及上述历史漂移一并明确pending，不批量更新原哈希。CharacterDialogue尚无runtime单列登记。功能条款/账本集合与新验证入口有效，但不能宣称全工程门禁绿色。

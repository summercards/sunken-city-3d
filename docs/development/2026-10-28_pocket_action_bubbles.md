# 2026-10-28 · 世界操作气泡与手绘口袋

本次对应 SEA-UI / SEA-INTERACT / SEA-INVENTORY / SEA-FARM。用户要求缩小交互入口、悬停不显示文案、点击后显示物体上方的动画图标气泡，并按所附口袋参考重做背包，背板无需弯曲。

## 交付行为

- 悬停是38px绿色手掌图标，没有名称、状态、说明或原大卡。图标使用独立样式，防止共享奶油面板装饰器覆盖绿色底而让白图标失去对比。
- 点击种植格只打开播种、浇水、收获三个76px气泡；不可用动作灰显，点击后才给轻提示。播种只使用实际持有的种子，多种时再选种子图标。供给站显示商店、仓库、出货箱三枚气泡，睡觉与其它可交互设施同用此入口。
- 气泡依物体世界坐标随相机投影；出屏/对象失效关闭，靠边保持可点。0.24秒BACK/OUT展开，间隔0.035秒；0.16秒缩回并淡出。点空白或Esc先收起，不执行世界动作，也不弹暂停菜单。动画偏好关闭时即时展开/收起。
- 选择操作后才调用原接近、长按与完成边界。Interactor新增`queue_command`只持有一次注入命令；执行前清空，取消清空。数量仍由Farm/Inventory/仓储/出货所有者写入，未修改物价、日历、生长、产量或存档字段。
- B/Tab直接打开独立横向口袋：平直奶油圆角背板、8列真实容量、无底物品格、真实拆堆、空位圆点、绿色名称胶囊、手套指针、黄色物品操作气泡和独立瓶盖钱包。背包期间隐藏重复资源大字与地图标记。生活手册保留独立按钮。
- 口袋物品操作沿用存入保管仓库1件、放入出货箱1件以及去种植的现有命令。手柄/触控尚未验收；键盘方向键/Enter/Esc和真实鼠标已经验证。

## 图标与来源

使用`sofunny-image`技能，通过Sofunny AIKey图片API调用用户指定的`gpt-image-2`，使用所附参考图作风格参考。旧令牌首次调用返回Invalid token；用户提供替代令牌后，以相同模型、提示词及参数成功生成。令牌只传入当次子进程环境，未保存至仓库或素材记录。

| 资产 | 制作源 | 提示词 | 运行资源 |
|---|---|---|---|
| UI-ACTION-HANDDRAWN-001 | [12枚白色剪影源](../../art_source/ui/handdrawn/v001/action-icons-source.png) | [完整提示词](../../art_source/ui/handdrawn/v001/action_icons_prompt.txt) | `godot/assets/ui/handdrawn/action_*.png` |
| UI-POCKET-HANDDRAWN-001 | [16枚物品插画源](../../art_source/ui/handdrawn/v001/pocket-icons-source.png) | [完整提示词](../../art_source/ui/handdrawn/v001/pocket_icons_prompt.txt) | `godot/assets/ui/handdrawn/item_*.png` |

由[拆分脚本](../../scripts/prepare_handdrawn_ui.py)按单元裁切、抠底、统一256px透明PNG，不重画生成内容。[来源与逐图哈希](../../godot/assets/ui/handdrawn/provenance.json)保留模型、提示词及文件校验。用户参考截图不入发行资源。

从`assets/registry/ledger_index.json`定位UI分账本后新增上述两个源包，源索引只追加两行，运行清单只追加28张新图；不刷新任何已有源/运行资源哈希。接入与渲染验证完成，供图平台商业使用条款独立保留`pending_provider_terms_review`。挖掘等备用图标已制作；项目当前没有挖掘命令，本轮未新增挖掘玩法。

## 当前实测

所有游戏验证通过`scripts/run_verification.py`启动；Autoload前已隔离项目名和用户目录。截图、日志和运行副本留在工程外`D:/projects/sea-work/verification/`，未使用玩家存档。机器记录及过程失败见[完整结果](2026-10-28_pocket_action_bubbles.json)。

| 检查 | 配置与结果 | 证据目录（sea-work/verification/下） |
|---|---|---|
| 新图片导入 | 隔离工程导入，退出0，无脚本/引擎错误 | `20261028-101826-pocket-bubbles-art-e28244` |
| visual-pocket-bubbles | 当前真实Forward+渲染，65项/0失败，退出0；悬停图标、动画中间帧、Esc/空白关闭、输入隔离、真实拆堆和容量、1280×800/1600×1000/1920×1080 | `20261028-102904-pocket-bubbles-delivery-cfc669` |
| visual-plot-shipping | 当前真实鼠标输入，58项/0失败，退出0；从选气泡到三日种植、收获、存取出货、07:00结算、存读 | 同上 |
| visual-sleep-cycle | 真实点击睡觉气泡后，圆幕与06:00/07:00流程38项/0失败，退出0 | 同上 |
| minimum-loop / title-screen | 最小发布配置通过，退出0 | `20261028-102237-pocket-bubbles-integration-8d5be5` |
| framework-modules | 无Autoload模块专项30项/0失败，退出0 | 同上 |
| click / farming | `--full-world`；点击31项、种植31项均0失败，退出0 | `20261028-102343-pocket-bubbles-full-world-d7b40d` |
| save-seed / framework-integration | `--full-world`跨进程存读与新一次性命令边界，均退出0 | `20261028-102742-pocket-bubbles-framework-final-a70267` |
| selftest | `--full-world`全量自检538项通过/0失败，退出0；故意损坏JSON的预期错误由runner单列 | `20261028-102925-pocket-bubbles-selftest-1b2b1a` |

真实渲染图位于最终视觉目录的`project/outputs/`：`hover-icon.png`、`plot-bubble.png`、`three-service-bubbles.png`、`pockets-item-actions.png`与各分辨率`pockets-*.png`、`bubbles-*.png`；种植生长、出货、睡觉圆幕截图另按专项命名。

## 过程失败及修正

初次runner因Windows默认GBK读项目UTF-8文本失败，之后在调用环境设置`PYTHONUTF8=1`。初次素材抠底仍有低透明背景残留，已按源色底阈值移除并目视检查最终运行PNG。悬停图标曾被通用装饰器刷回奶白，新增独立样式标记和对比度断言后修复。

扩展回归初次误用最小发布配置，旧点击/浇水测试尝试已关闭的建设、远海、18格种植等内容；框架测试还按旧配置访问空漂流物列表。对应失败、退出码及脚本错误均保留在机器记录中，随后明确使用`--full-world`。另有旧测试仍预期直接打开`plot_options`并调用旧回调，睡觉测试仍预期第一次点击就开始睡觉；均改为验证气泡选择后执行，未恢复旧UI或挂隐藏旧容器。两次已卡在旧断言后的隔离框架进程被定点终止，退出4294967295如实登记；最终框架重跑退出0。

未执行：触控/手柄、长时连续界面压力测试、独立发行包、平台商业条款核验。整体功能仍partial，不以本轮UI专项声称其它设备或全部历史功能完成。

## 最终合同检查与并发工作区边界

本轮初次完整合同检查为33功能、429源资产、317运行哈希、0问题。新增UI资产后，只追加2份源包、28张运行图，并更新四份功能文档和账本。最终11份交互/UI脚本与通过真实渲染的隔离运行副本一致（仅规范化行尾与EOF空行）。

收尾时，太阳房GLB、材质、instances与zones.json在10:30—10:33期间出现并发修改，先15项、随后更多既有运行哈希漂移。它们不属于本轮UI修改，未审查其资产制作来源，也未修改这些文件或刷新旧哈希。已经执行`--sync`及无参数检查，实际退出码1与完整差异单列于机器记录的`feature_contract_check`。功能派生摘要额外使用检查器本身的`parse_master/ledger_meta`及同一投影逻辑同步；最终没有功能条款、路径、资产ID、来源索引或派生摘要错误，剩余均为上述运行资产哈希差异。全局资产门禁保持pending，不以本轮专项通过掩盖它。

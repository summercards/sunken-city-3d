# 2026-11-13 sea 工程深度审计与整改计划

[主文档中控](../../GDD_V1.0.md#feature-control) · [质量账本](../features/quality/ledger.md) · [存档账本](../features/save/ledger.md) · [资产账本](../features/asset/ledger.md)

## 范围与基线

- 源码基线 `94ec42e09095ea0e31646b81b93e3027d489c6ad`；开始及所有引擎审计批次的工作区均干净。本轮随后仅追加审计记录和入口，不改生产代码、资产、shader、主场景/用户Transform，不读写玩家正式存档，不修复问题，不批量刷新哈希。
- 对46/46功能导航、spec、ledger建覆盖矩阵，重点调用链深审框架、内容数据、存档、经营、交互、移动、潜水、NPC及资产治理；不是46功能逐行为穷举。
- 工程外交付根 `/Users/zyq/work/sea-work/audit-2026-11-13/`。63项去重登记与逐项方案：`issues.json`；报告制作源 `output/sea-deep-audit-20261113/stage1/final_draft.md`；正式Word交付路径 `output/sea-deep-audit-20261113/stage3/sea工程深度审计与整改方案_2026-11-13.docx`。文档转换及打包结果以最终交付卡和证据清单为准，不将该路径声明当成功证明。

## 结论与优先级

现有模块化基础真实，但尚不能签署架构独立、存档安全、玩法与账本一致的完整健康结论。63项包含缺陷、结构债、治理风险和待裁决事项，不是63个已发生玩家事故：P1=14、P2=39、P3=10，未确认P0；动态复现15、静态确认29、风险待验14、规则待裁决3、测试治理2。

优先修：候选二楼状态校验(S01)、语义坏主档与备份(S02)、未来模块保护(S03/S06)、归档碰撞(S04)、畸形decode(S05)、过场/疲劳门禁(S08/S09)、动作目标锁定(G01)、潜水返树职业端口(G02)。菜园桥5个Marker比派生面高0.737953m导致0/5锚点、总聚合35/40、豆豆可见但回退天台(G04)，不同于已接受街口下沉，不抬用户根或放宽支撑门槛。

资产重点：二进制CRLF归一化错误放行32 GLB(R01)、水密passed漏核心谓词(R02)、模板残留当前身份字段矛盾、45正式牧场GLB漏运行清单、8源/123运行真实内容漂移、许可pending与可携证据缺口。469差异路径字节等HEAD，属于已提交治理基线，非本轮弄脏。不把820条license pending当已侵权。

已排除误报：固定建造/一级船费const真实拒写，不能据静态说可改真实价格；Goal设施仅展示容器污染，权威支付不变。用户接受的位置、暂停住所、规划任务/音乐/音效/植物工坊不列回归。

## 当前实测与退出码

| 批次/检查 | 结果 | 原始证据 |
|---|---|---|
| 架构边界 | exit0；25服务/0 issues，覆盖有限 | 工程外审计根 `evidence/check_architecture.py.log` |
| 功能契约 | exit1；499 issues，不能签整体通过 | `evidence/check_feature_contracts.py.log` |
| 摆放台账 | exit0；6结构/0警告 | `evidence/check_placed_positions.py.log` |
| Python治理 | exit0；10/10 | `evidence/engineering-guards.exit.json`及日志 |
| 当前逻辑专项 | 40项32通过8失败，其中2项exit124；整体exit1 | `/Users/zyq/work/sea-work/verification/20261113-123757-deep-audit-20261113-199237/report.json` |
| 自检 | exit1；499 passed/33 failed，另1 SCRIPT ERROR，不沿用旧536/1 | `/Users/zyq/work/sea-work/verification/20261113-131204-deep-audit-visual-20261113-444694/selftest.log` |
| 真实room/quick-tools/gift-kiosk | 3项exit0/PASS，68PNG | 同一444694目录report及project/outputs |
| 存档反例 | 2入口；wrapper exit1，畸形decode7错误原样保红 | `/Users/zyq/work/sea-work/verification/20261113-124339-save-data-readonly-audit-cffaaf/report.json` |
| 玩法反例/常量裁决 | 9入口；wrapper exit1，5常量拒写负例保红 | `/Users/zyq/work/sea-work/verification/20261113-124651-audit-gameplay-dynamic-b16e30/report.json` |
| 菜园桥定向诊断 | exit1；8条/3失败，完成marker=true、无脚本异常 | `/Users/zyq/work/sea-work/verification/20261113-131805-audit-garden-readonly-8d6b04/report.json` |

40专项35入口有数值终局小计11303 checks/16 failures，不是全轮断言总数；24条FAIL与1脚本错误并非24新bug。失败包含开放范围/7格2床/替代支撑/三维面/prefab/迁址/密度旧夹具，wood测试采8束测10次索引越界，NPC seed受boot失败阻断并级联restart；仍保留真实garden失败。NPC集成超时具体停点未定。详见工程外 `evidence/test-triage.md`。

**真实渲染**：仅room8、quick-tools30、gift-kiosk30共68PNG；主线程目检3张(room-inside、1280 land-open、gift-kiosk-hero-day)，未称全图审。三视觉88 WARNING含60条同名instance uniform不同索引，需后续正确性验收，不签零警告。退出实例泄漏与导航/采集点吸附警告单列未归因。

**预期故障**：主动复现畸形decode、只读常量拒写与garden红项；原runner的exit/错误过滤未放宽，诊断完成不等于功能健康。

**未执行**：全部功能组合、全部Blend重开/GLB逐件渲染、68图全目检、二楼真实攀梯双进程自动加载、默认家园/五职业全矩阵、房间23点竞态、全owner重入、全部模块版本/平台存储/断电/磁盘满、实际PCK、远端CI、低端长时、音频听验与许可审核。

## 修改计划（仅计划，尚未实施）

1. B0：冻结证据，修二进制哈希/水密门禁与过时/挂起测试，保留真实红项，补治理负例（5条）。
2. B1：存档保护与关键生命周期止血；decode/版本→完整备份→候选世界→唯一归档；统一事务busy、target/token、挂起恢复（11条）。
3. B2：业务原子收支与保存窗口、迁移/消费者/autosave/reset体验、模态睡眠关闭、床与菜园局部空间（11条）。
4. B3：owned/integration/dependency编辑权、窄端口与规则归域、内容schema、条款/索引、资产身份/hash/manifest/分类/闭包/证据逐项归因（30条）。
5. B4：instance uniform、资源释放、导出包/平台故障/长期性能及许可发布闭包（6条）。

Main/HUD/SaveSchema整合热点由单一整合者串行接线，不机械按行拆文件；修复按FeatureID回到spec与ledger，反例先红后绿、专项后集成、如适用再真实视觉设备；每批可回滚。不扩大存档格式/ContentID变更，确需迁移先订契约。

全局门禁sync及无参最终检查的结果追加在本记录后续章节；未清零前明确失败，不因文档或索引回填宣称生产修复完成。

## 最终静态收尾

仅追加审计入口/质量、存档、资产、启动、交互、世界六功能账本后，正式执行：`check_feature_contracts.py --sync` exit1/498 issues；无参数检查exit1/499 issues（多一条派生索引陈旧）。检查器仅无issues才写回，故本轮未修改派生索引、主表状态摘要或资产JSON。日志 `evidence/final-contract-sync.log`、`final-contract-check.log` 与 `final-contract-results.json` 保留全部原始问题。`git diff --check` exit0。生产源、配置、模型、材质、主场景和用户位置均无diff；所有已有受跟踪文档变更为末尾追加，无删改历史。

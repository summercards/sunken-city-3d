# 2026-10-23 · 主文档中控与功能工程拆分

[主文档](../../GDD_V1.0.md#feature-control)

## 备份与工作基线

- 拆分前工作区已提交并推送：`826a0012bc3fbd2100452104c8f5b6942814b075`。
- 远程备份分支：`codex/backup-before-feature-split-20261023`，已通过 `git ls-remote` 核对提交一致。
- 施工分支：`codex/feature-controlled-structure`。
- 备份包含拆分前未提交的命名、水面修改、审计报告及非忽略截图。被 Git 忽略的缓存/大体积产物不在此远程备份内，原本地文件保留。

## 已实施

1. 升级现有 GDD 为唯一中控；登记 31 项功能，每项独立 spec.md、ledger.md，双向导航、条款承接与状态来源明确。
2. 原 GDD、开发计划、功能重做计划原文完整归档；当前计划入口指回主文档，旧完成度不再作为当前状态。
3. 62 个 Godot 脚本与 UID 按职责归位；旧经济/区域/航路镜像进入 tests/parity；场景和代码引用同步。路径清单见 [迁移映射](2026-10-23_path_migration.json)。
4. FarmModel、OrderBoard 通过注入端口访问库存和进度；UI 作物选择改为命令。新增不加载 Main、无 Autoload 的正式规则测试。
5. 建立资产路由、场景分账本、源索引、内容 ID 索引和运行资源基线：43 份组件源登记、218 个运行文件路径/哈希、8 张内容表。
6. 统一验证 runner 隔离用户数据、记录完整日志和真实退出码；增加主文档/功能文件/资产/路径/依赖门禁。
7. 7 个会重写正式场景或资产的旧构建器增加候选副本保护；导出排除测试、工具、截图、文档及候选标记。

## 基线验证

Godot：4.7.2.stable.official.ed1daf0bf。

拆分前 8 组：parity、farming、surface、click、management、camera、ocean、selftest 全部退出 0，完成标记通过，无非预期脚本错误。selftest 的精确坏 JSON 故障注入单列。

原始证据目录：`sea-work/verification/20261023-163848-before-split-1be5ff/`（仓库同级）。该目录含每项日志与 report.json；日志不作为游戏运行资源入库。

端口拆分后：modules、farming、management 全部通过。证据：`sea-work/verification/20261023-165051-feature-ports-2bd0cc/`。modules 不启动任何 Autoload，不加载主场景。

## 最终验证

证据摘要：[逐项退出码、故障分类与日志 SHA-256](2026-10-23_verification_summary.json)。原始日志和截图保存在仓库同级 `sea-work/verification/`，摘要随 Git 交付。

| 检查 | 结果 | 证据目录 / 说明 |
|---|---|---|
| Godot 编辑器重新导入 | 退出 0，无 ERROR/WARNING | `/tmp/sea-split-final-import.log`；首次搬迁缓存重建诊断不作最终验收 |
| 核心回归 9 组 | 全部退出 0 | `20261023-165838-after-split-127b48`：modules、parity、farming、surface、click、management、camera、ocean、selftest |
| 独立规则 | modules 通过 | 无任何 Autoload、无 Main；覆盖种植/订单规则和氧气/打捞模型 |
| 种植、经营真实渲染 | 退出 0 | `20261023-170010-split-real-render-a0ea26`：visual-farming、visual-management；种植截图已目视核对 |
| 水下深度和截图套件 | 退出 0 | 上述目录 visual-underwater-depth；`20261023-170129-split-underwater-4e1565` 的 visual-underwater-capture |
| 鼠标真实事件 | **退出 1，未通过** | visual-click 的“直接点击世界中的第二格命中正确目标”断言失败；其余断言通过 |
| 主文档/功能/资产门禁 | 通过 | 31 项功能、43 项源登记、218 项运行资源哈希；10 项工程门禁单测通过 |
| 实际 Web PCK 导出与索引审计 | 退出 0，通过 | [包内容报告](2026-10-23_export_pack_audit.json)：584 项，105,261,300 字节，禁止条目 0、必要入口缺失 0；索引结束位置与文件长度一致 |

selftest 精确坏 JSON 输入为 1 次预期故障；所有通过项目无非预期脚本错误。首次真实渲染副本出现纹理 UID 回退警告，runner 随后补充复制 UID 缓存；警告与错误分别看待，不据此签署所有资源正式验收。

鼠标断言已用拆分前隔离工程重跑，`20261023-163848-before-split-1be5ff/baseline-visual-click.log` 同样失败，不能归因为本次迁移。额外诊断表明投影点可识别第二格，直接调用接近入口可以启动；真实事件时序与场景状态的完整根因仍待定位。没有绕过或放宽断言，交互功能保持 partial。

PCK 临时文件在审计后删除，索引报告及工程外导出日志保留；未上传发行包，也未把资源包审计当作目标浏览器或设备启动验收。

## 明确保留的工程债务与未执行项

- Main 仍有集中协调逻辑；Economy 仍承载建造、设施、船升级、仓库和目标；SaveGame 仍有 Main/HUD 私有字段访问。这些都在对应独立账本登记，没有用搬目录宣称完全解耦。
- 角色移动/潜水等完整功能的专项仍依赖主场景；独立规则替身先覆盖种植、订单、氧气、打捞。
- 43 份资产为源级登记，正式 Godot 接入未凭空补齐；授权来源待审查。218 个旧运行文件尚未全部取得生产 AssetID。
- 居民、天气、独立养殖、任务成就、音效、音乐保留 planned，未新增玩法或数值。
- 根网页仍承担烘焙来源；现有 outputs 含历史工具与必要来源，未批量清空。现有大型二进制未重写 Git 历史或强行迁 LFS。
- 发行资源包已实导并审计；完整 Web 启动与设备兼容性、长期经济平衡和完整人工首局体验尚未执行。鼠标真实事件断言的既有失败仍待定位。各功能目标完成度仍依据自身账本。

## 维护方式

从主文档功能条目进入独立文档和账本，完成改动后更新账本，执行 `python3 scripts/check_feature_contracts.py --sync`，再运行普通检查和相应专项。本次没有创建新玩法来填满 planned 目录。

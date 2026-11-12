# 老王场景工坊 · 生成失败与操作布局修复

日期：2026-11-12。FeatureID SEA-WORKSHOP，R47–R49。植物工坊按用户指令暂停，调研及六个内核草稿留原地，未验证、未接入口。

## 用户问题与根因

截图显示“参数未提交：未知组件 band_cozy”。当前catalog_v1.json确实含该项，但旧草稿/已保存文档拥有独立catalog快照，新建会复用session.catalog，旧目录缺少新增腰线/壁柱。用新配方碰旧目录产生真实拒绝。仅检查默认目录的历史测试漏掉此路径。

## 本轮变更

- `catalog.gd` 新增 editor_catalog(snapshot)：重新读取版本化JSON，只补缺少的内置ID，不覆盖存在的参数组件、prefab、自定义定义。运行旧档parser与Store仍保留严格快照契约。
- `editor_screen.gd` 在configure/new/apply及恢复/打开连续实体时补目录；旧草稿不自动载入、旧配方UI打开明确拒绝并提示新建，旧样例列表过滤；不删除旧文件或静默迁移。
- UI建模内核控件隐藏，不再显示旧版方案；重复旧形状隐藏，保留矩形/L/T/U的统一结构形态。保留隐藏控件仅供历史parser回归，不向作者提供入口。
- 左侧是基础框架/门窗/构架/形体参数，右侧是槽位与绑定。主操作“应用参数并生成楼房”固定在所有滚动区域之外，260×46；应用全部参数移到顶部工具栏。全局参数点击主按钮一次提交并重建；局部范围尚未应用仍拒绝，避免错误范围提交。
- “打开”从硬编码页5改成查找“文件”，避免新增页面后落到构架页。
- plugin.cfg/plugin.gd/editor_screen/验收主屏名称改“老王场景工坊”；旧草稿路径、插件路径和候选路径不改。
- shell草稿恢复成功后更新状态提示，清掉上一次旧草稿拒绝原因。

## 验证

- 首批真实editor：`20261112-115532-laowang-editor-repair-21d3b6`，2498项/0失败。
- 中间截图批：`20261112-120037-laowang-framework-delivery-4ec27f`，2532项/1失败。错误来自验收把状态栏解释旧稿拒绝的提示当成旧方案UI；只排除状态文字，保留旧入口不可见断言。
- 最终真实editor：`D:/projects/sea-work/verification/20261112-120447-laowang-framework-final-7539e2/report.json`，2532项/0失败、exit0/PASS、unexpected_errors=[]、enginehint=true、is_playing=false、scene_unchanged=true。
- 几何回归：`20261112-115949-laowang-repair-regression-77e1ed`，workshop-shell/architecture/rules/deep均exit0/PASS。
- 旧目录夹具真实删除band_cozy/pillar_cozy，并修改wall版本。configure后只补两项、wall定义保留；新建并实际生成8段腰线/42柱；真实pressed后width、构架与形体进入snapshot，mesh hash和bounds变化；旧shell草稿恢复geometry一致；旧legacy草稿明确拒绝且现场不变。
- 两档1280×800/1600×1000验证主按钮完整可见、无ScrollContainer祖先、在左栏上方。最终基础框架截图已目检。

## 界限

不更改Main或玩家手摆场景，不清理用户楼房候选，不批量更新资产hash。工程存在并行quick_tools/UI任务，工作区非本轮文件保持。全库contracts同步仍受既有资产承接/hash漂移及暂停植物草稿路径约束阻挡，不能声称全库通过；workshop新增条款承接已补齐。未主动提交/推送本轮修改。

## 使用

重新载入编辑器插件或重开Godot后，点顶部“老王场景工坊”。如果原来是旧版拼装草稿，点击“新建”；左侧改尺寸/结构形态等，点固定“应用参数并生成楼房”。默认连续实体，无需再选择建模内核。

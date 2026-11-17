# 2026-11-17 建筑工坊预览恢复与导航

归属 SEA-WORKSHOP-R17、R18。用户反馈预览空白、不能像 Godot 移动视角，要求提供聚焦防止镜头找不回来。

## 原因与范围

- 明确代码风险：隐藏恢复时立即按临时 viewport 尺寸取景，尺寸只要大于零即标记 fitted，显示后 resize 不重新拟合。改为等待可见布局两帧，隐藏/尺寸未完成时不锁定首次取景。
- 原来只有左键旋转和滚轮缩放，确实没有平移/飞行或找回对象功能。
- 草稿恢复原来忽略 refresh_preview 失败并报告成功；现在原样返回失败。无效构建根不先清空前一有效预览。
- 上述为可证实风险和修复，未现场复现用户原进程，不能断言截图唯一根因。

## 操作

中键环绕；Shift+中键平移；右键环视、按住右键 WASD/QE 飞行，Shift加速；滚轮缩放。兼容左键点击选槽/拖动环绕。F 仅在预览获得焦点时使用，聚焦选中真实槽，没有选中则整栋；「显示整栋」忽略当前选择直接找回楼房。隐藏/失焦/框外松键清理移动状态。本轮未实现无限鼠标捕获和所有 Godot 自定义键位。

同楼实时生成仍保留镜头，不改几何、配方、Store、外挂或用户摆位。main.tscn LF规范化内容与 HEAD 一致；不改其 transform。

## 实测历史与当前状态

产物根为工程外 `../sea-work/verification/`。

1. `20261117-153835-workshop-preview-navigation-f88231`：import exit0；editor exit1、1453检查/2失败。增加按钮使小窗口出现水平滚动条挤压预览，修正该行隐藏滚动条；隔离工程缺 scene_assembly 依赖错误另列。
2. `20261117-154243-workshop-preview-final-b2653a`：1471/0、engine exit0，但缺 plant_authoring 预加载依赖，runner exit1。不能签通过。
3. `20261117-154442-workshop-preview-live-recovery-2f0c93`：1474/0，但同依赖错误。直接嵌入 viewport 图 `project/outputs/workshop_live_preview_recovered.png` 已目检可见完整建筑；不是另行重取景的模型图。
4. `20261117-154544-workshop-preview-delivery-d5fcb8`：import/editor/runner exit0；运行期间补了框外松键防卡住代码，source_changed_during_run=true，故不拿此批代签最新源码。
5. `20261117-154700-workshop-preview-release-3216b8`：最终真实editor/import/runner均exit0，1474/0、completion=true、unexpected=[]、source_consistent=true、source_changed_during_run=false；三个改动GDScript与隔离快照字节一致。直接嵌入viewport前景像素及隐藏重建取景断言通过。

runner 补全 attachments 测试依赖：scene_assembly 以及它需要的 plant_authoring，只作用隔离副本。新增聚焦八角可见、平移、F、选槽聚焦、不改历史、隐藏生成及嵌入前景像素检查。新增导航断言部分直接调用 GUI handler/端口，不冒称人工鼠标键盘全链终验。

## 全库门禁与未执行项

本轮 sync exit1（539 issues），check exit1（540 issues），日志 `../sea-work/workshop-preview-contracts-{sync,check}.log`。保留已有 source/runtime hash drift、派生索引等，不批量改哈希。当前专项不是全工程通过。

生产 Main 未运行；原用户进程恢复原草稿、完整物理鼠标飞行操作、跨平台终验、性能与用户艺术终验未执行。无预期故障豁免，前轮非零均保留真实失败。

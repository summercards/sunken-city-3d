# 2026-11-17 树木工坊预览导航修复

归属 SEA-PLANT-EDITOR R10/R13。仅改树预览、树编辑器验收和本功能文档，不改建筑工坊、runner、植物生成、Main、用户摆位或资产。契约最终同步由主线程统一执行。

## 修复

原 SubViewportContainer 同时显示纹理和接收 GUI 输入，工具栏没有显式层级，三个鼠标键均只旋转。现预览框裁切渲染，纹理容器 mouse_filter=IGNORE / 子viewport禁GUI输入；独立上层 Control 获得鼠标与键盘焦点，工具栏位于独立高层。左/右拖旋转、中键或Shift拖屏幕平移，透视/正交按实际可见跨度缩放平移速度；滚轮缩放，单击选枝、双击聚焦，F 聚焦选枝或适配全部。失焦/隐藏/停用清除拖动态，漏释放以button_mask清理。

## 验证与失败历史

全部运行只通过 scripts/run_verification.py。首次未指定 GODOT 退出2，随后显式 /Applications/Godot.app/Contents/MacOS/Godot。

- 20261117-160455-tree-preview-navigation-364905：editor-plant超时exit124，runner exit1；测试动态类型推断before/old_yaw报parse，已改显式Vector3/float。不可当通过。
- 20261117-160937-tree-preview-gui-8dc821：未先导入草模型资源导致初始化缺资源，启动导入对话框截获前两个真实按钮点击；editor-plant exit124 / runner exit1。已改用--import-assets，并在GUI测试开始等待资源扫描结束。
- 20261117-161432-tree-preview-gui-final-8e18f4：使用--visual --import-assets，asset-import exit0；完整编辑器专项执行中，最终状态见本记录后续追加，不提前签成功。

最终批真实Metal Forward+ / Godot4.7.2 / Apple M6；Input.warp_mouse + Input.parse_input_event注入四按钮、平移、旋转、滚轮与F，不直接调用生产输入处理器。navigation_after_button_0..3.png为各按钮点击后整屏，navigation_after_pan_orbit.png为导航后整屏，均在该批project/outputs/plant_editor_evidence。已目检button_1与pan_orbit两张，俯视方向和旋转/平移效果存在，四工具按钮仍清楚可见，未被纹理盖住；不是人工鼠标操作。

未独立GUI覆盖Shift拖、双击、窗口失焦、正交平移比例的极值及各显示器DPI；本轮不签这些已实测。没有性能基准、Main/潜水/移动/Web或艺术终审。全库契约主线程处理，历史失败保留。

## 必要内核回归

20261117-162000-tree-navigation-kernel-5ae377未带--visual，Dummy后端无法读回MultiMesh导致plant-authoring 260项5失败、exit1；integration/guard exit0。没有改生产代码迎合Dummy。随后20261117-162050-tree-navigation-kernel-real-d078f3经--visual --import-assets真实Metal后端：plant-authoring 260/0、plant-integration 540/0、host-scene-guard 155/0，三项exit0、passed=true、completion_marker=true、unexpected_errors=[]，import0、runner0。这组为逻辑/保存回归，没有新截图，不是性能基准。

## 最终编辑器结果

最终`20261117-161432-tree-preview-gui-final-8e18f4/report.json`与`project/outputs/plant_editor_report.json`已读取：**2289 checks / 0 failures，editor/runner/import均exit0、passed=true、completion_marker=true、unexpected_errors=[]、warnings=[]**。本次新增18项=13个GUI/结构断言+5张真实截图检查，原专项完整保留；总artifacts329，不声称329张全目检。新增五张分别navigation_after_button_0..3.png与navigation_after_pan_orbit.png，已打开目检正面、俯视和pan_orbit3张。生产preview.gd与editor_verification.gd与报告隔离快照逐字节相等；git diff --check退出0，Main无diff。主线程全库契约另行统一，不将专项通过写成全局通过。

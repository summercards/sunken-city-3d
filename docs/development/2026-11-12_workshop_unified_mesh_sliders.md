# 老王场景工坊：结构融合与窗滑块实时预览

FeatureID：SEA-WORKSHOP；条款R57–R61。用户2026-11-12 18:11要求，优先一体结构，再解决窗参数调节不可见。

## 实施

- `godot/src/workshop/shell_union_geometry.gd`：生成期同步CSG布尔并集。100倍坐标求交后恢复米制；0.1mm与引擎TriangleMesh一致的量化、同线分边、退化薄片修复与成对反向面清除。最终必须实际边图单连通/闭合/定向/正体积/无重复退化，并通过逐面双侧源实体射线核验，失败拒绝，不回退拼壳join。
- `shell_generator.gd`：墙、板、主屋顶、柱、腰线、束带、勒脚只输出一件可见`structure_union`；原槽为无网格语义节点，内存`semantic_sources`保留编辑母型。碰撞直接来自union真实faces，水平面及支撑从实际融合几何读取。窗/门/窗沿/植物及雨棚、屋顶围护附件保持独立。
- `shell_geometry.gd`：转角柱改为实心咬合六边形母型，消除旧回折产生的内部隔片；不靠两个角柱盒子相叠。
- `editor_preview.gd` / `catalog_adapter.gd`：语义槽点选使用真实三角精筛；母型仍可单独导出并标记`semantic_source_module`，不冒称最终融合切片；实时更新保持相机。
- `architecture_config.gd` / `shell_window_geometry.gd`：框宽最大.40m、深.60m、玻璃.10m、净宽高各6m、窗沿外挑1m/厚与伸出.50m。框允许凸出墙面，但不能完全脱离墙洞；净孔、窗扇扫掠、楼板、相邻窗包络仍限制。
- `editor_screen.gd`：窗数值全部HSlider，显示只读数值/上下限，160ms调度自动预览，支持全局/楼层/立面/单窗。失败保留上次成功模型与滑块输入。
- `session.gd`：新增公开`preview_candidate`事务，唯一写入草稿和撤销；真实构建一次，成功提交并直接给预览，拖拽合并历史。UI不再直接写Session内部历史。
- `editor_store.gd`：记录union源码hash；静态五件bundle不包含运行时CSG或重建脚本，不改旧revision。
- `upgrade_verification.gd`、`test_workshop_union.gd`、已有shell/architecture测试与统一runner同步适配；保留用户原有`visual-frame-budget`改动。

## 实测与证据

统一引擎Godot4.7.2 `/Applications/Godot.app/Contents/MacOS/Godot`，使用`scripts/run_verification.py`；所有产物在工程外sea-work。

1. `/Users/zyq/work/sea-work/verification/20261112-223629-workshop-unified-final-78963c/report.json`：union24533/0、shell18077/0、architecture3133/0、rules24/0、deep41/0，全部exit0/true，无unexpected_errors。独立union覆盖64组矩形/L/T/U、柱腰线开关、收分/退台，另包含五层L回归、join重叠盒负例、实际碰撞与静态重载。
2. `/Users/zyq/work/sea-work/verification/20261112-223629-workshop-sliders-final-811cc9/report.json`：真实editor-upgrade203/0、exit0/true，无unexpected_errors。真实HSlider值及drag信号，经Timer更新；非人工鼠标自动化。无Main/Autoload、scene不变、不暂停编辑器。相机保持、局部范围隔离、其他未提交楼宽保留、失败回滚、单次拖拽一条撤销、源模块导出与五件静态重载全部通过。
3. 真实模型及UI图片：第二批`project/outputs/upgrade_*.png`；模型1400×1100，UI记录实际2048×1200，不伪称1280×800/1600×1000验收。典型等待+生成约0.38–1.15秒，160ms只是调度延迟；不承诺60fps或任意大楼实时性能。
4. 主场景、shared材质、PNG、shader的git diff为空；不注册正式Asset、不替换摆位、不重写历史候选。

中间失败不抹除：早期union64曾有16组内部边界误差；后续五层L又在量化分边处出现1处内部薄片。通过实体咬合、CSG尺度、薄三角link约束处理及分边后重复反向面消除修正，未取消门禁/降低探针距离/删除fixture；最终重新全跑。旧框深必须完全塞进墙厚的校验确实使调整失效，本轮改为实体交集约束。

## 使用

打开Godot项目，进入“老王场景工坊”。新建或载入shell配方后生成即采用融合结构，柱、腰线仍在“构架”页独立开关。

“门窗”页选择全局/楼层/立面/单窗，再拖滑块；自动生成，不需点应用。窗框.275m即旧默认.11m的2.5倍；若要净窗3.75×4.75m，先在结构页应用能容纳它的开间/层高（验收fixture：开间6m、层高6.8m、12×12m、2层、form关闭）。尺寸放不下会明确报原因，不偷偷改楼房或缩窗。

旧已导出的TSCN不会自动变化，需从配方重新生成并保存为新revision。源槽模块导出是编辑母型，整楼静态成品才是融合结果。

## 验收边界

本次专项真实渲染与几何通过不等于完整专业美术终验。旧editor-workshop全量矩阵未全部按新语义重跑；运行版Main集成仍受既有资源缓存缺失阻塞。完整插件卸载/跨进程恢复、任意8层组合、性能门禁、导航/楼梯/全楼可达、正式世界接入未签。全库契约同步exit1（498 issues）、check exit1（499 issues），其中445条source/runtime hash drift、51条跨机断链，另有SEA-ASSET行集及派生索引问题；本轮未批量hash刷新或手改摘要。日志在工程外`workshop_contracts_{sync,check}_20261112.log`。

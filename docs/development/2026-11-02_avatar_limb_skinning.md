# 角色连续四肢与骨骼蒙皮 · 2026-11-02

按用户圈选的肘部、膝部接缝修订：每条完整手臂（含手）和完整腿（含脚）各一张连续封闭的网格，改由真正Skeleton3D/Skin渐变权重弯曲。原分段胶囊、关节球与独立手脚网格已移除，不通过加球/遮挡或挪动分段补缝。

功能归[SEA-AVATAR设计/账本](../features/avatar/spec.md)（R14）和[SEA-MOVE设计/账本](../features/move/spec.md)（R17）。用户指定的上一轮静止比例保留；存档格式、外观ID、角色功能根与碰撞归属保持。

## 运行契约与维护

- 程序源：`godot/src/avatar/avatar_limb_skinning.gd`；着色：`godot/shaders/avatar_limb.gdshader`。这是可维护的Godot程序网格/骨骼源，没有声称制作Blender/GLB。
- BodyPivot下LimbSkeleton有21骨：root，4组upper/lower/tip控制骨，以及各自upper_skin/lower_skin伸长辅助骨。真实名称、父子及静止原点由引擎导出到`art_source/characters/avatar/v002/rig_contract.json`。
- 每条手臂626顶点/1248三角面，每条腿530顶点/1056三角面，合计2312顶点/4608三角面；4张网格各一表面、闭合且只有1个连通分量，所有边恰被两个三角面共享。每顶点4权重通道，当前最多2个非零影响，权重和1；每条有264个多骨影响顶点，覆盖弯曲与末端过渡。
- 原动作只写不可见肩肘/髋膝/手脚控制；Character在动作采样后交给骨骼适配器。四肢只有这一套可见蒙皮表现。上/下段独立辅助骨只拉长当前段，不把非均匀缩放传入下一旋转关节，避免举物长臂产生剪切或变粗。
- 袖口、裤脚、鞋底仅为同一网格内的材质分色；换装只改着色参数，不重建骨架/权重。渲染由GPU变形，生产帧不CPU修改顶点；`deformed_points`是验收/量测只读端口。
- 手/脚控制Marker路径保持，获物腕部求解同步适配；物品仍1.60m举高、2.4秒、原奖励时点和取消语义。自验发现旧抬肩方案会让宽头角色的手臂穿头，已保留肩根、让肘部弧线从脸前经过，双腕仍支持物品前下角。
- 0.22m半径/1.30m高胶囊、人物根、移动速度、导航、背包奖励、profile v1/根存档v4没有改为骨骼状态存储。换装/取消/恢复仍能回到稳定待机。

依据[Godot Skeleton3D接口](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html)与[ArrayMesh的权重/绕序约定](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html)，并以当前Godot4.6.3实测为准；不是只根据API文档认定效果。

## 当前实测

统一入口`scripts/run_verification.py`，在Autoload前隔离用户数据。目录：`D:/projects/sea-work/verification/20261102-201548-avatar-skin-delivery-c9a28d`。机器记录见[完整摘要](2026-11-02_avatar_limb_skinning_verification.json)。

| 入口 | 当前结果 | 覆盖 |
|---|---|---|
| avatar-skinning | 80项，exit=0 | 原生骨骼/绑定、网格封闭与单连通、归一权重、面绕序、0/30/60/90/120°四肢截面不塌陷、静止顶点不被CPU改写、真实腕位、六种动作 |
| visual-avatar-skinning | 92项，exit=0 | 上述检查、11张原生图、仅旋转骨骼且控制/网格对象不动时GPU像素确实改变 |
| visual-avatar-proportions | 13项，exit=0 | 原图六项比例/物理尺寸、真实四肢网格投影，最大相对偏差1.68%，原阈值5% |
| avatar | 140项，exit=0 | 95选项映射、换装、草稿/取消、写失败回滚/重试与旧档兼容 |
| avatar-restart | 5项，exit=0 | 独立进程姓名/形象/DIY引用恢复 |
| onboarding | 23项，exit=0 | 码头开场、输入锁、取名、保存、重置归档 |
| character-motor | 42项，exit=0 | 原物理/地面/模式接口 |
| actor-presentation | 31项，exit=0 | 原七动作生命周期与扩展、取消/重复/token |
| harvest-receive | 80项，exit=0 | 三作物、真实接近/成功、手部支持、包盖、原奖励和7类中断 |
| visual-avatar | 37项，exit=0 | 三分辨率实际键鼠、换装、保存、重开/取消 |

本批次全部10入口exit=0，非预期脚本/引擎错误0；没有注入预期故障。用户实际存档未参与测试。

真实渲染输出位于该目录`project/outputs/`：`avatar-skin-01-neutral.png`、`avatar-skin-bone-only.png`、`avatar-skin-02-bend90.png`、`avatar-skin-03-elbow-close.png`、`avatar-skin-04-knee-close.png`，以及walking/rowing/planting/watering/harvesting/swimming六个action图；最终捏人界面为`avatar-07-card.png`。已亲眼检查肘膝近景、弯曲及动作截图。

早期证据保留：195915为新模块类型推导编译错误；200234拓扑检查抓出首版三角形面绕序与法线反向，已按引擎原生SphereMesh约定修正；200628新增GPU单骨检查发现测试角色在入树后仍自动采样待机，导致“控制不动”的测试前提不成立，已在build后禁用测试角色自动采样并独立复测；200904通过GPU与比例测试，自验再发现举物穿头，201145修正并重跑获物；本最终批次再次完整通过。旧失败未删除、不混充为当前验收。

## 资产与后续

SEA-CHAR-RIG-001新增原生蒙皮资产；SEA-CHAR-AVATAR-001升v002，SEA-CHAR-RECEIVE-001升v003，仅审阅自身改动及骨架/着色依赖。注册由ledger_index路由；`tools/register_avatar_skinning.py`核对工程外精确旧源基线，只更新这三条与相关运行路径，不批量刷新其他域或Main哈希。原源基线在`D:/projects/sea-work/avatar-skinning-baseline`。

未执行触摸/手柄/移动设备、所有服饰×所有动作的长期人工穷举及发行包平台验收。已测当前PC正常运行、关键动作和0–120°关节范围；不宣称180°扭转和任意极端反关节都通过。后续DIY仍消费稳定选项/材质引用，图案编辑器不属于本次内容。

最终静态门禁：功能契约sync与无参数复核均exit=0，39功能/626源资产/517运行哈希/0问题；架构17独立服务/0问题；本轮改动diff空白检查通过。GPU单骨证明在控制节点不动时改变2507个角色区域像素。骨架和原动作链路已自行验收完成，无需额外用户审批。

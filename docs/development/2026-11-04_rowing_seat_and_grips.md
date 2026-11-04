# 2026-11-04 · 坐船位置、握桨与双桨长度

用户反馈：角色划船时双手够不到桨，身体没有坐在船上。范围为SEA-MOVE-R18 / SEA-NAV-R13；只调整既有正式角色表现与小船装配，不改航速、路线、奖励、存档或船体水线。

## 修正

- 旧人物根在船局部 `(0,0.62,-0.30)`，停船切回站立；动作只按相位转手臂，既没有坐姿，也没有握点关系。现在正式TSCN的 `RowingSeat=(0,0.6025,0.32)` 落在中排座板前半部；座板实际顶面为0.602500m。停船、取消航行及船上恢复均保持坐姿。
- `ActorController`拥有是否坐船的状态投影；上船由 `Boat.boarding_position()` 提供位置。`Character`只通过注入的 `rowing_pose_query` 读取座位世界变换和双桨Grip，表现绕髋部微倾、随Model摇摆，纯表现不移动玩法根。离座完整清除平移/关节，恢复岸上或潜水动作。
- 双腿原先在座板中心屈膝时仍会穿过前沿，已把坐点前移、保持大腿近水平并让小腿绕到板前。专项检查实际骨骼变形顶点与两块座板，不以膝盖角度常量代替穿插证据。
- 原桨长约3.164464m，沿桨杆轴缩至82%，约2.594860m；只调整现有TSCN实例，杆与桨叶厚度/宽度、原GLB、Blender源、UV与材质保持。右桨实例轴向偏移由1.032232改为0.300330m（左侧镜像），实际握点深入桨架内侧约0.87m。
- 双桨轴及桨架一起移到船局部z=0.36m。保留左右x=±1.10m、转轴y=0.68m和原单一相位/出力/转向差异；停船yaw约±0.08rad、抬桨倾角约±0.22rad。划动yaw幅度0.17rad，倾角0.28+cos(phase)×0.24rad；双手使用当前体型的真实臂长解算，不通过伸长或拖动桨架补齐。
- 原BladeContact继续随实际桨叶变换。接水测试原先硬编码“距船中心超过3m”，不适用于缩短后的桨；现改为逐入水帧核对水花位置与真实桨叶一致，并验证水花仍在船体之外。

## 当前实测

统一入口 `scripts/run_verification.py` 在构造Autoload之前建立独立工程/用户目录，未修改玩家存档。使用Godot 4.7.2 / Forward+ / RTX4060Ti原生渲染。

最终汇总：`D:/projects/sea-work/rowing-fit-20261104/verification.json`。6入口共19028检查、0失败、退出码均0，预期/非预期脚本错误均为空。人物/动作批次：`D:/projects/sea-work/verification/20261104-162628-rowing-accepted-f1aa4d/report.json`（前4项接受，其中水花渲染超时单独重验）；接水最终批次：`D:/projects/sea-work/verification/20261104-163538-rowing-water-frame-check-24e9f3/report.json`（headless与真实渲染均接受）。

| 验证 | 当前结果 | 覆盖 |
|---|---|---|
| rowing-fit | PASS，18797检查，exit 0 | 默认及胖瘦/臂粗/腿长混合极值共9组，30/60/120FPS、静止/35%/满力、左右/直行、24相位及船体摇摆；真实座板/蒙皮腿、手掌、根不变、取消/上下船/潜水恢复 |
| actor-presentation | PASS，31检查，exit 0 | 动作时序、替换/取消、事件及业务边界 |
| avatar-skinning | PASS，80检查，exit 0 | 既有骨架/网格/权重和动作链路 |
| visual-rowing-game | PASS，22检查，exit 0 | 正式main场景中拉桨/中段/回桨/停船/侧面原生帧，正式接线与离座/返船碰撞状态 |
| boat-water-contact | PASS，41检查，exit 0 | 真实桨叶逐入水帧接触、轮廓、停船不再溅水 |
| visual-boat-water-contact | PASS，57检查，exit 0 | 两套海面真实渲染、吃水轮廓、桨叶接水位置、出入水次数及水花像素 |

最新几何结果：手掌最大偏差0.000001043m；臀部与座板最大高度差0.00655693m；座板内部腿部顶点命中0；桨叶接触点相对静水面y范围约−0.07918至+0.65607m。数值来自当前实例变换与真实网格，不是只读配置。

此前同轮集成：`D:/projects/sea-work/verification/20261104-161721-rowing-seat-edge-469123/report.json` 中 `board-click`、`reference-skiff` exit 0；接水测试8项旧距离断言失败已按实际几何修正，不能把该批次整体记为通过。`D:/projects/sea-work/verification/20261104-162112-rowing-final-visual-7556ab/report.json` 中独立原生渲染18797项、正式场景17项exit 0，5视图已逐图查看。最终批次额外补了离座重置与正式上下船断言。

## 验证边界与调试记录

预期故障：最终专项未注入故障，预期脚本错误为空；非预期错误与退出码以最终report逐项保留。现有楼顶牧场导入含Unicode节点名/丢失节点覆盖警告及导航警告，未改无关资产或消音。最早全场景基线120秒超时；首次水花真实渲染360秒超时，测试补上首次绘制提交及每12步让出绘制帧后，按同一几何/像素标准重跑通过；一次探针路径写错后已修正；座点前移后的长腿瘦体握距18项失败，桨架z由0.40收至0.36后恢复；失败报告仍保留在工程外，没有把它们当验收绿项。

未执行：触摸/手柄、所有服装和DIY参数笛卡尔积、发行包、长时间设备性能。没有制作或宣称审计新的Blender/GLB；小船参考图商业授权仍pending。

## 账本与来源

通过 `assets/registry/ledger_index.json` 定位scenes与characters。仅更新已核对前身的角色表现及组合根资源、小船装配和桨Prefab记录；不新增AssetID，不改原模型源哈希，不更新未知场景/海洋/区块变更。初始隔离副本完整保存改前代码，逐行差异仅本轮座位/姿态接线；审计：`D:/projects/sea-work/rowing-fit-20261104/registry_audit.json`。

小船旧Prefab/装配登记哈希追溯到提交3e683fe2的CRLF字节；到HEAD的差异只有BladeContact挂点、water_layer/water_layer_role元数据，均已审阅并保留previous哈希。正式TSCN拥有本轮座点/双桨长度与位置，不将其回写或覆盖旧Blender装配。

功能文档/账本新增SEA-MOVE-R18与SEA-NAV-R13，主文档摘要链接本记录。全工程已按顺序运行 `python scripts/check_feature_contracts.py --sync`、无参数检查：均exit 1。最终同步7项、检查8项范围外问题：SEA-WORLD账本缺JSON登记头；SEA-SCENE-ORF-ASSEMBLY源哈希；source index；zones资源哈希和内容ID；ocean_sky资源哈希；末轮另见zone1_home_harbor.tscn资源哈希变动（本次未编辑该文件，未刷新其未知哈希）；检查额外有派生索引未同步（同步被前述问题阻止）。没有本次MOVE/NAV条款、入口、路径、链接或已审阅资源哈希失败，不以批量更新掩盖。完整输出：`D:/projects/sea-work/rowing-fit-20261104/feature-contracts.json`。

## 原生画面

已逐图查看正式main中的拉桨、中段、回桨、停船、侧视，以及两套水面的接水全景和近景。

- 正式角色回桨：`D:/projects/sea-work/verification/20261104-162628-rowing-accepted-f1aa4d/project/outputs/rowing-game-recovery.png`
- 正式角色侧视：`D:/projects/sea-work/verification/20261104-162628-rowing-accepted-f1aa4d/project/outputs/rowing-game-side.png`
- 水面两套全部证据：`D:/projects/sea-work/verification/20261104-163538-rowing-water-frame-check-24e9f3/project/outputs/`

## 后续用户反馈与验收修正

用户随后明确指出手臂仍扭转。上文“整体自然”的结论过早：到点、臀部接触和不穿板并不证明肘部弯曲方向与扭转正确。当前以SEA-MOVE-R19 / SEA-NAV-R14及[第二轮交付](2026-11-04_rowing_arm_direction.md)为准，旧数值仅作为历史证据，不能代替当前复验。

# 2026-10-29 拼接板吃水与电线杆摆位

[主文档](../../GDD_V1.0.md#sea-building) · [建造设计](../features/building/spec.md) · [建造账本](../features/building/ledger.md) · [资产账本](../features/asset/ledger.md)。

用户要求：拼接板保持顶面高度，只往下加厚以接触海面；绞盘平台的电线杆与花朝第二张截图右侧水域平移，解决穿板。

## 改动

- 通用木板`deck_visual.gd`厚度0.10→0.50米，中心Y=-厚度/2，所有增量朝下。世界顶面1.48、底面0.98、水面基准1.12；走路、建造坐标及种植摆件高度不变。预览与已建木板共用同一预制体。
- 原`salvage_station.glb`的电线杆/绞盘/花叶与旁边漂浮木料同处一个primitive。工具`tools/split_salvage_pole_group.py`按完整连通组件拆出独立`PoleAndFlowers`节点；16894顶点、7948三角形归入新组。旁边漂浮木料保留135三角形，全部几何合计9378三角形不变；顶点属性逐字节保留。
- 正式`godot/scenes/facilities/salvage_station.tscn`拥有组位移：局部(+2.2,0,+2.4)米，对应默认视角朝画面右侧水域。平台整体、桌子、舱口、荷叶、海下基座与角色交互点未平移。
- 旧`.blend`保留作源参照，布局由TSCN维护，不自动回灌重导。旧GLB备份在工程外`sea-work/backups/salvage_station-4aaef9b50fca.glb`。重复运行拆组工具会识别已完成状态，不会再次位移；输入哈希不符时拒绝改写。
- 补足厚度后，旧静态岸线图仍不会自动收录后建木板。因此BuildingWorld只读查询完工矩形，经组合入口投影到WaterSurface的24项上限通道；两套水材质共用`runtime_water_contacts.gdshaderinc`接触距离查询，各自保留原泡沫风格。施工虚影不产生水线，切换水材质与恢复布局同步更新，无每次施工重烘焙卡顿。

## 验证

所有运行经统一runner、独立user目录。当前证据在工程外`D:/projects/sea-work/verification/`：

| 运行目录 | 实测与退出码 |
|---|---|
| `20261029-081804-building-waterline-final-307b4e` | visual-building-fit 12项、building-integration 38项、building-seed 5项、building-restart 8项全部PASS，退出0 |
| `20261029-082727-building-fit-both-schemes-1e70fa` | visual-building-fit 13项、building-seed 5项、building-restart 11项全部PASS，退出0；加入两套水面真实渲染、移动后整体边界检查和冷启动水线恢复断言 |
| `20261029-082933-building-fit-shared-contact-b7638d` | visual-building-fit 15项全部PASS，退出0；核对shader真实声明通道，补齐吸收水面接触距离查询，最终双水面实景通过 |

已查看最后一轮`project/outputs/fit-{station-before,station-after,deck-before,deck-after,deck-after-absorption}.png`。082727轮目视发现吸收方案没有消费新增通道，单靠get_shader_parameter读取回写值会误判；随后共享距离include并增加实际shader uniform声明检查，最终原方案与吸收方案都能看到新增板底的接触泡沫。顶面1.48、底面0.98米由实际Mesh AABB验证，电线杆与花整体包围盒已在原板边之外。冷启动仅为完工木板恢复水线，未完工板在剩余时间结束后加入，不重复扣费。

离线GLB复核：受影响primitive原8083个三角形与拆后两组逐面比较，POSITION/NORMAL/TEXCOORD_0/COLOR_0完全相同；海下mesh和materials保持相同；全设施9378三角形不变。

第一次`081342-building-draft-pole`、第二次`081551-building-draft-water`运行几何检查通过，但主场景当前Water节点被编辑器隐藏，图中没有水，不能证明吃水效果。此后的捕获工具只在隔离场景临时show水面；`081636-building-fit-visible-water`发现板底已接海但静态岸线未更新，随后增加完工矩形接触通道，并以上表最后两轮为最终证据。正式main.tscn的用户编辑状态保留。

已执行`check_feature_contracts.py --sync`及无参检查，当前均报告6项其他材质哈希差异：ocean_sky、solar_cabin/sunny_{emission,gloss,matte,metal}、water。工作期间另有编辑器保存main.tscn、solar_cabin.tscn与材质改动，未回退、未代其重算哈希；本轮仅登记明确修改的木板源、绞盘GLB/包装、BuildingWorld、水面接触接口与foam include。架构检查PASS，15服务0问题。全局摘要同步受这6项差异阻断，不能宣称全工程门禁通过。

## 后续：杆身延长接通

按新截图直接延长移动后上方杆身底端：17个截面顶点沿既有轴向下移动(-2.34243,-23.24495,-4.21352)米，其余上段/花/绞盘不变；删除旧海下独立杆身32三角形。整杆底端约Y=-22.125，原立柱位置清空；正式水平摆位保持。补丁工具tools/extend_salvage_pole.py，备份在sea-work/backups/salvage-before-extension-f0c1b55a265d.glb。

本次证据：`20261029-101430-pole-extension-final-70e6d5`，visual-building-fit 15项0失败、退出0；已查看`project/outputs/fit-pole-full.png`，杆身连续延伸，旧下段已移除。功能契约`--sync`/无参检查35功能459源资产392运行资源均0问题，架构15服务0问题。首次导入轮`101311`因沿用旧“整体包围盒不跨板边”断言失败；延长后的水下部分允许向原轴下方延伸，改为只检查海上段净空后复验通过。

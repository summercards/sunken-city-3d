# 2026-11-07 商亭近侧墙体与陈设透视

[主文档](../../GDD_V1.0.md) · [世界规范](../features/world/spec.md) · [账本](../features/world/ledger.md)

用户标出从镜头一侧遮住角色和室内的墙框/物件，要求有形状地半消失。本轮仅实现运行时表现，不改Blender、GLB、内装布局、用户手动摆位或任何玩法空间。

## 表现与所有权

新增shop_sightline.gd和shader，正式floating_shop只加一个资源及SightlineReveal节点。沿用RoofReveal的圆角/高度/门边缓冲室内判定；设施注入角色与Camera3D，Main只新增相机端口参数，不持表现进度。默认4.3m×3.8m半径的椭圆按相机投影换算屏幕尺寸，中心取角色上身1.05m，柔边约22%、核心保留8%原不透明度，0.35秒平滑进出。退出时锚定最后室内局部位置继续跟随浮动，防止窗口追着出门角色扫过外墙。

shader同时要求片元位于镜头朝向的近侧半平面和角色前方视深度。只做视深度会误淡化远侧高墙，因此还保留XZ近侧门限；真正远侧的墙、挂钟和柜台不会因为高度而被误收。相机直接俯视且没有XZ近侧方向时保持原材质。相机换向和缩放只被读取，不改变任何相机状态。

范围包括商亭墙框/玻璃/门框、非顶部的店内货架/商品及前景邮筒/明信片架/冰柜等；屋顶标记的78根不参与，防止与原顶盖控制互相抢材质。地砖Floor、甲板、船体/浮筒、栏杆等不参与。仅候选中的近侧网格换临时实例surface材质，其它仍用原资源；共享角色材质缓存，不修改共享网格/材质。玻璃保留原透明度和双面规则；关闭后恢复原始override引用。节点visible、碰撞、导航、补给与存档不受影响。

## 验收

所有Godot运行使用scripts/run_verification.py的工程外副本和隔离用户数据。初次组件专项968检查/0失败、exit0/runner PASS，覆盖30/60/120fps、准确投影中心、相机反向、浮动随动、进出反转、原引用和节点可见性、销毁角色恢复。实际日夜前后、柔边中间态、八方向和真实走出恢复的GPU截图正在审阅。最终结果在后续章节追加。


## 最终实测与交付

| 专项 | 实测检查 / 失败 | 退出码 | runner |
|---|---|---|---|
| shop-sightline | 968 / 0 | 0 | PASS |
| visual-shop-sightline | 20 / 0 | 0 | PASS |
| roof-reveal | 364 / 0 | 0 | PASS |
| gift-kiosk-interior | 349 / 0 | 0 | PASS |
| camera | 12 / 0 | 0 | PASS |

前两项在D:/projects/sea-work/verification/20261107-190758-shop-sightline-first-5930c3/report.json；相关回归在D:/projects/sea-work/verification/20261107-191040-shop-sightline-regression-c712d9/report.json。五项共1713检查、0失败，均exit0/runner PASS，无非预期脚本或引擎错误，预期故障为空。

GPU实际画面已亲看白天/夜晚before和after、中间透明状态、反向机位及走出后恢复。椭圆内的近侧梁柱、货架和商品形成柔边局部透视，角色全身和地砖可辨；核心保留浅轮廓，窗口外家具轮廓完整。反向机位会改收后墙/门侧，原来远侧陈设保持可见。原屋顶78根消隐独立工作，进出和原购物交互回归通过，镜头自身变换未被改变。

实际室内共315候选网格、4份角色材质；截图机位185个近侧网格参加遮罩，其余保持原材质。原源文件60份、GLB58份哈希核对不变（旧外观与内装两套件），本轮只为6份有验证的运行资源更新登记和商亭prefab哈希。Main只增加相机注入参数，整个文件与回归副本哈希一致；其全局registry含并行改动，因此不刷新未知总哈希。

最终媒体在D:/projects/sea-work/gift_kiosk/sightline/final/：after-night.png为与用户截图同类机位的实景效果，before-night.png可直接对照，另有白天与opposite orbit-04.png。源截图未绘制或修图。

静态校验：check_feature_contracts.py --sync退出1/26项，随后普通检查退出1/27项（多派生索引stale）；问题为并行SHOP入口、旧鱼/住所源与Main/水材质/阳光房/移动/存档/HUD及zones索引漂移，本轮不批量接受未知变动。相关完整输出在机器签署，不能称全局契约通过。check_placed_positions为4结构0警告、exit0；git diff --check退出0（仅行尾提示）。本任务未改main.tscn或用户摆放。

继续任务后的最后核查：上述6份运行文件与Main仍逐一匹配已验证副本；正式场景SightlineReveal节点和实际Camera3D注入均存在，文档/世界账本已追加最终结果。未执行低端设备性能和完整无关功能套件。[机器签署](2026-11-07_gift_kiosk_sightline_verification.json)。

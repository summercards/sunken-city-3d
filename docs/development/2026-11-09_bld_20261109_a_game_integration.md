# B1109A 编号001水上普通建筑接入

## 用户要求

将低面数版本接入游戏；在资产账本中增加水上建筑普通建筑，使用编号 `001`；分类保持标准 `above_water`；放到水上商店边上。

## 接入结果

- AssetID：`SEA-SCENE-WATER-BUILDING-001`
- 显示名：水上普通建筑001
- 分类：`category=building` / `building_class=above_water`
- 水层：`surface` / `entity`
- 运行职责：视觉 + 水面船只阻挡；不拥有商店交互、不拥有生产、不擅自创建独立可行走区
- 源：`art_source/scenes/bld_20261109_a/v004_lowpoly/bld_20261109_a_v004_lowpoly.blend`
- 源 SHA-256：`7b709696615f82888eb27e8103ce727056cc9d11faa8ab1b9f3e87d9cd3d4598`
- 运行 GLB：`godot/assets/models/facilities/water_building_001/water_building_001.glb`
- 运行 GLB SHA-256：`dd8c58d309af5f5cfddefaa94909d3d87061839dd2fbaa068e26e72fa1afaef2`
- 包装场景：`godot/scenes/facilities/water_building_001.tscn`
- 低面数：整栋 9736 三角面；运行 GLB 独立重新打开后 9527 三角面，差异来自导出时的重复顶点/索引合并，不是额外几何。
- 49 个低面数组件包此前已 49/49 重开通过。

## 主场景摆位

在 `godot/scenes/main.tscn` 的 `World/SeaStructures` 下新增 `water_building_001`，当前参考位为：

`(165.07135, 1.12, 143.89136)`

水上商店当前主场景位为 `(147.57135, 1.12, 143.89136)`。编号001放在商店 +X 方向，根节点间距约17.5米，按建筑外接尺寸约11米计算，约留2米间隙。该位置只作为首次带入参考位；用户后续手动摆放以 `main.tscn` 实测 transform 为准，已写入 `docs/features/world/placed_positions.md`。

## 已验证

- GLB 为单场景结构，Blender 独立重开成功。
- GLB 633 个网格对象、9527 三角面、3 个材质角色、0 张内嵌图片。
- `check_placed_positions.py`：3 个结构，0 失败，0 warning。
- 静态文件核对：main 节点、包装场景、GLB、场景分账本 JSON 均存在/可解析。

## 尚未完成

- 当前机器未发现可调用的 Godot 可执行文件，尚未执行正式 `godot --headless --import`。
- 因此 GLB 的 `.import` 文件尚未生成，包装场景尚未由 Godot 实际加载，运行期水面阻挡和画面尚未签字。
- `runtime_integrated` 保持 pending；商业权利与用户最终美术验收保持 pending。
- 工程既有 69 项历史源/运行哈希漂移仍存在；本轮不刷新旧哈希，不把该问题归到编号001。

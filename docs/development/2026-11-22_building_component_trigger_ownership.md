# 2026-11-22 建筑组件与独立设施触发区域归属

## 目标

统一建筑单位和建筑上独立设施的场景归属。建筑移动时，码头、房间进出口、楼梯和通行面一起移动。种植区块、出货箱、采集物等设施保持独立脚本、独立状态和独立交互热区，只通过父建筑实例跟随摆放。

## 本轮修改

- `solar_cabin.tscn` 新增建筑自有 `WalkAreas`，包含下层甲板、上层甲板、主泊位、`BoatPark`、`DockEdge/DockingArea` 和临时上坡组件。
- `solar_cabin.tscn` 新增 `Facilities`，把 `home_plot`、`ShippingBox`、`RoomDoor` 作为独立物件挂在阳光房根节点下。
- `gather_spots.json` 的阳光房采集点声明 `facility=solar_cabin`，`GatherField` 装配时将其挂入 `Facilities/GatherSpots`，并使用全局坐标吸附到当前建筑实体地面。
- `zone1_home_harbor.tscn` 删除阳光房原来的主泊位、阳光房上层走域、菜箱、出货箱和房门，区块继续保留绞盘泊位、渔场和其他区块级对象。
- `ZoneScene` 递归收集建筑子树公开的 `WalkArea`，并继续统一登记 `LandingPoint`。
- Main 的出货箱、房门和睡眠/标题/醒来逻辑改为从阳光房实例的 `Facilities` 查找，不再读取 `zone1/Objects` 旧路径。
- 更新相关测试路径和 world/sunroom/facility 账本条目。

## 验证

- Godot headless 项目启动与场景导入：exit 0。
- `sunroom-runtime`：exit 0。
- `sunroom-surface-collision`：exit 0。
- `interaction-reach`：现有测试夹具在 `test_interaction_reach.gd:103` 仍写入退役的 `ActorController.walk_area` 属性，runner 超时并返回 exit 124。这是测试入口兼容问题，不是场景加载错误。

## 当前边界

`Interactable` 已统一通过自身的 `InteractionTrigger` Area3D 和玩家 `InteractionSensor` 进行范围判断，`Interactor.interaction_context` 负责隔离 shore/room/sea。阳光房独立设施已经接入该链路。其他建筑的旧空间节点仍按各自场景逐步迁移，潜水场景本轮没有改动。

## 2026-11-22 阳光房家具与边缘阻挡补充

`solar_cabin_surface_collision.tscn` 增加凳子、桌子代理和上下层临海边缘防跌落盒。角色碰撞使用 `SCENE_GROUND_LAYER=8192`，船体 `HullContact` 仍使用独立层，不改变船只靠泊。桥口、梯脚和墙体门洞保持可通行。

`sunroom-surface-collision` 与 `sunroom-runtime` 均 exit 0。正式综合 `visual-formal-sunroom-deck` 仍有历史夹具依赖 `GroundBoundary`、旧梯状态的失败，未把该综合专项当作本轮家具/边缘碰撞的通过证据。

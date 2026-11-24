# 2026-11-22 原生 3C、NPC 寻路与 AI 状态收口

## 实施

- `GroundSpace.native_route()` 直接消费 `NavigationServer3D` 路径点。
- 建造站位、房间床边和住所查询改为统一使用 `native_route()`。
- `NpcWorldPresenter` 通过 `CharacterMotor.move_ground()` 执行 NPC 移动，导航点只表达意图，场景碰撞决定实际位移和滑动。
- NPC 世界观察快照新增 moving、performing、blocked、idle 状态。日程动作目前只映射到浇水/收获表现，未伪造业务结算。
- 无连续地面路线时不再把 NPC 写到目标锚点，改为 blocked 并尝试返回住所。
- NPC 集成测试去掉 `Boat.arrived` 和自动航行占位，改成手动 `Boat.set_drive()`、船壳泊位触发区和 E 交接。
- 主场景启用查询增加 `dive` 与建造控制器空值保护。

## 验证

`npc-world`、`npc-performance`、`npc-rules`、`npc-careers`、`ground-space`、`room`、`building-integration` 均通过，退出码为 0。`npc-integration` 脚本编译通过。

完整 `main.tscn` 集成启动仍会记录既有 `main.gd:_setup_building()` 的 `building_world.gd` GDScript `new` 错误，并在上船阶段停住。本轮没有把该错误归因于导航或船壳逻辑，也没有修改用户手摆场景与潜水系统。

## 未完成

NPC 真实播种、浇水、收获、业务原子提交、行为失败重试和跨场景运输仍未实现。旧 `route()`/`path_between()` 名称保留为兼容转发，正式运行时消费者已统一到 `native_route()`。

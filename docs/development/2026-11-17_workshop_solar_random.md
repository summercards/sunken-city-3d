# 2026-11-17 随机房屋固定阳光房配色

归 SEA-WORKSHOP-R84/R89。用户反馈树工坊视图按钮消失/视角不能移动，并明确建筑随机不要变窗和窗框颜色、全部保留阳光房配色。树预览修复由独立 plant_editor 改动承接，本记录只管建筑随机。

## 实施

编辑器 `_random_house_now` 在候选提交之前调用纯 `RandomRecipe.solar_colors`：以 authoring_defaults 的阳光房完整手动色板、shading与aging为准，清理旧全局/楼层/立面/单窗颜色字段，保留窗几何设置。框色格[2,3]、玻璃[2,1]；结构与窗型仍可随机。保持原 building_id/revision；取消/失败原房和输入不动，成功与配色为单次可撤销事务。没有改共享材质、PNG、Main、旧保存配方或原有显式保色create接口。

## 验证记录

- core首跑 `20261117-155959-workshop-solar-colors-core-7ea5ce`：17851/1、exit1。新增测试故意设置立面width=1.0，而复用audit要求所有洞宽等全局值，造成夹具假前提冲突；保留几何字段验证改用同原全局width，不放宽audit。
- editor首跑 `20261117-155914-workshop-solar-random-a9fa4f`：1499/0、engine exit0，但复制到了并行树预览编辑中的源码，plant preview parse错误，runner exit1，不能签整批通过。
- editor第二轮 `20261117-160447-workshop-solar-random-final-2b508f`：复制到并行树测试未完成的类型推断表达式，plant editor_verification.gd:148/158解析错误，inner1499/0、engine exit0、runner exit1，同样不签通过。最终等树代码/测试稳定后串行重跑。
- 当前源码增加随机后实际窗/框Mesh UV逐点色格检查，并验证完整阳光房色板、同seed重现、undo/redo与失败回滚。

core最终 `20261117-160131-workshop-solar-colors-core-final-6fe2fe`：17851/0、exit0。已目检首轮editor真实随机房图，窗框统一青蓝、玻璃浅蓝、墙象牙与木板配色可见；首轮依赖错误保留，不签整批成功。最终稳定editor `20261117-161422-workshop-solar-delivery-4825fe`：1499/0，import/editor/runner均exit0、unexpected=[]、source_consistent=true、source_changed_during_run=false。实际窗/框UV、阳光房完整色板、同seed、取消/失败/undo/redo均通过。

本轮全库sync exit1/543 issues，正式check exit1/544 issues，日志 `../sea-work/workshop-solar-contracts-{sync,check}.log`；未批量重写漂移哈希。生产Main、用户原进程、性能/艺术终验未执行，不以专项代签全工程。

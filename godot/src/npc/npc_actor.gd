extends Character
## 仅组装独立NPC表现；不查询世界、玩家档案或任何玩法服务。
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const Accessories = preload("res://src/npc/npc_accessories.gd")
var npc_id := ""
var accessory_id := ""
var display_name := ""
var _npc_profile: Dictionary = {}
var _accessories = Accessories.new()

func configure(row: Dictionary) -> void:
	# 必须先进入场景树，Character的蒙皮和获物姿势才能读取有效全局变换。
	if not is_inside_tree():
		push_error("NpcActor.configure需要先add_child")
		return
	_accessories.clear()
	npc_id = str(row.get("id", ""))
	display_name = str(row.get("display_name", npc_id))
	accessory_id = str(row.get("accessory_id", ""))
	_npc_profile = {"version":1, "name":display_name, "completed":true,
		"appearance":Catalog.effective(row.get("appearance", {})),
		"morphs":Catalog.effective_morphs(row.get("morphs", {})),
		"design_refs":{}, "extensions":{}}
	if body_pivot == null: build()
	apply_avatar(_npc_profile)
	# NPC路径消费者只切换set_walking；使用Character原有步频，不另写动画。
	walk_speed_ratio = 1.0
	# NPC职业装备替代旅人通用挎包；不修改Character或玩家实例。
	_item_receive.bag.hide()
	body_pivot.get_node("SatchelStrap").hide()
	_accessories.configure(self, accessory_id)
	set_meta("npc_id", npc_id)
	set_meta("npc_display_name", display_name)

func clear_accessories() -> void:
	_accessories.clear()

func accessory_metrics() -> Dictionary:
	return _accessories.metrics(self)

func appearance_report() -> Dictionary:
	return {"npc_id":npc_id, "display_name":display_name, "accessory_id":accessory_id,
		"profile":_npc_profile.duplicate(true), "geometry":avatar_geometry_report(),
		"accessories":accessory_metrics(), "animation":animation_state(),
		"root_scale":scale, "body_scale":body_pivot.scale if body_pivot != null else Vector3.ONE}

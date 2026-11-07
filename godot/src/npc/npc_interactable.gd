extends Interactable
## 世界适配只发起交谈；商店经营者也先进入同一居民会话。
signal npc_requested(npc_id: String)
var npc_id := ""
var shop_id := ""
var _available := false

func configure(id_value: String, label_value: String, vendor_shop := "") -> void:
	npc_id = id_value
	shop_id = vendor_shop
	id = id_value
	label = label_value
	verb = "交谈"
	priority = 8
	focus_radius = 2.4
	hold_time = 0.12
	focus_anchor = "node"
	auto_radius = false

func set_available(value: bool) -> void:
	_available = value
	if not value: focus_exit()

func can_interact() -> bool:
	return _available and is_visible_in_tree() and not get_tree().paused

func interact(_actor: Node3D) -> Dictionary:
	if not can_interact(): return {"blocked": "现在不方便交谈"}
	npc_requested.emit(npc_id)
	return {"event": "npc_requested", "npc_id": npc_id}

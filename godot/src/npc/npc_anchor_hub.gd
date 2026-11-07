extends Node3D
## 聚合只读世界站位；共享日程名按居民所属场地解释，不跨海替换目标。
const Rooftop = preload("res://src/npc/npc_rooftop_anchors.gd")
var _providers: Array[WeakRef] = []

func configure(providers: Array) -> void:
	_providers.clear()
	for provider in providers:
		if is_instance_valid(provider) and provider.has_method("anchor_snapshot"):
			_providers.append(weakref(provider))

func anchor_snapshot() -> Dictionary:
	var result := {}
	for ref in _providers:
		var provider = ref.get_ref()
		if is_instance_valid(provider): result.merge(provider.anchor_snapshot())
	return result

func home_labels() -> Dictionary:
	var result := {}
	for ref in _providers:
		var provider = ref.get_ref()
		if is_instance_valid(provider): result.merge(provider.home_labels())
	return result

func canonical_anchor_for_npc(anchor_id: String, npc: Dictionary) -> String:
	var home := str(npc.get("residence_id", ""))
	if home == "residence_general_store":
		if anchor_id == "anchor_home_dock": return home + "_social"
		if anchor_id == "anchor_general_store": return "anchor_general_store"
	# 花店共享货架是天台活动，不允许误解为阿店的浮店柜台。
	if anchor_id == "anchor_general_store":
		return "anchor_flower_shop" if home == "residence_flower_shop" else home + "_social"
	return str(Rooftop.ALIASES.get(anchor_id, anchor_id))

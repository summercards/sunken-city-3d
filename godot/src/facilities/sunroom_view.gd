@tool
extends Node3D
## Visual projection for SEA-SUNROOM. It owns no progression or inventory state.
## Main injects the stage/season from SunroomService after the scene is ready.

const RUINED := "ruined"
const LADDER_FIXED := "ladder_fixed"
const RESTORED := "restored"
const SceneComponent = preload("res://src/ambient/scene_component.gd")

var _stage := RUINED
var _season := "spring"
var visual_root: Node

func configure(root: Node) -> void:
	visual_root = root

func apply_stage(stage: String, season := "spring") -> void:
	_stage = stage if stage in [RUINED, LADDER_FIXED, RESTORED] else RUINED
	_season = season
	var root := visual_root if visual_root != null else self
	for node in root.find_children("*", "Node", true, false):
		if not is_instance_valid(node):
			continue
		if node.has_method("set_sunroom_damage"):
			node.set_sunroom_damage(_stage == RUINED)
		var component := str(node.get_meta("asset_component", ""))
		var generated_name := str(node.name)
		if component == "ladder" or generated_name.begins_with("ladder_"):
			node.visible = true
			continue
		if component == "roof_sofa" or generated_name.begins_with("roof_sofa_"):
			node.visible = _stage == RESTORED
			continue
		if node is SceneComponent and node.component_kind == "upgrade_attachment":
			node.upgrade_controls_visibility = false
			node.visible = _flora_visible(node)
	# The two logical upper interactions are only available in their matching stage.
	for node in root.find_children("*", "Node", true, false):
		if node.has_method("set_sunroom_stage"):
			node.set_sunroom_stage(_stage)

func stage() -> String:
	return _stage

func season() -> String:
	return _season

func _flora_visible(node: Node) -> bool:
	var name := str(node.name)
	var component := str(node.get_meta("asset_component", ""))
	# New game: one small daisy only. It is deliberately on the lower/front deck,
	# so the first visible plant is not a promise that the upper floor is usable.
	if _stage == RUINED:
		return name == "daisy_158" or (component == "daisy" and name.ends_with("_158"))
	# Repairing the ladder opens a small cared-for lower-deck cluster. Upper flora
	# remains absent until the upper room is restored.
	if _stage == LADDER_FIXED:
		if str(node.get("attachment_slot")) in ["rear_building", "solar_room"]:
			return false
		return name in ["daisy_158", "daisy_159", "sprout_150", "sprout_151", "foliage_153"]
	# The full authored flora returns, filtered by the current calendar season.
	if _season == "winter":
		return not name.begins_with("pink_flower") and not name.begins_with("sprout")
	if _season == "autumn":
		return not name.begins_with("pink_flower")
	return true

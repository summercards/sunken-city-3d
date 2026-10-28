@tool
extends "res://src/interaction/interactable.gd"
signal sleep_requested

func _on_ready() -> void:
	id = "home_sleep"
	label = "太阳房 · 睡觉"
	verb = "睡到早上 06:00"
	priority = 4
	hold_time = 0.15
	focus_radius = 2.4
	var sign := Label3D.new()
	sign.name = "SleepSign"
	sign.text = "☾"
	sign.font = preload("res://src/ui/ui_font.gd").embedded()
	sign.font_size = 70
	sign.pixel_size = 0.012
	sign.position.y = 0.75
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color("fff6d8")
	sign.outline_size = 0
	add_child(sign)

func interact(_actor: Node3D) -> Dictionary:
	sleep_requested.emit()
	return {"event":"sleep_requested"}

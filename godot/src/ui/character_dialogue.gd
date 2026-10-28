extends CanvasLayer
## Only explicit character dialogue uses this bottom panel. System notices use HUD.toast.
signal closed
var panel: PanelContainer
var speaker_label: Label
var line_label: Label

func _ready() -> void:
	layer = 70
	panel = PanelContainer.new()
	add_child(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	speaker_label = Label.new()
	body.add_child(speaker_label)
	line_label = Label.new()
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size = Vector2(600,90)
	body.add_child(line_label)
	var close := Button.new()
	close.text = "继续"
	close.pressed.connect(func(): panel.hide();closed.emit())
	body.add_child(close)
	preload("res://src/ui/cozy_ui.gd").style_tree(panel)
	panel.hide()

func show_line(speaker: String, text: String) -> void:
	if speaker.strip_edges().is_empty() or text.strip_edges().is_empty(): return
	speaker_label.text = speaker
	line_label.text = text
	panel.position = Vector2((get_viewport().get_visible_rect().size.x-640)/2,get_viewport().get_visible_rect().size.y-240)
	panel.show()

@tool
extends Node3D
@export var dimensions := Vector2(2.15,2.575)
@export var thickness := 0.50
@export var ghost := false

func _ready() -> void:
	$Model.scale = Vector3(dimensions.x / 2.15, thickness / 0.5, dimensions.y / 2.575)
	var collider: CollisionShape3D = $SurfaceCollision/Deck
	collider.position.y = -thickness * 0.5
	var box := collider.shape as BoxShape3D
	box.size = Vector3(dimensions.x, thickness, dimensions.y)
	if not ghost:
		return
	$SurfaceCollision.collision_layer = 0
	var preview := StandardMaterial3D.new()
	preview.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview.render_priority = 10
	preview.albedo_color = Color(0.55,0.95,0.78,0.45)
	preview.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for plank: MeshInstance3D in $Model.get_children():
		plank.material_override = preview
		plank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

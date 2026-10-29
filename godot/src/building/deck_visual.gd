@tool
extends Node3D
## Reusable timber module, sharing the existing cultivation deck's plank profile.
@export var dimensions := Vector2(2.15,2.575)
## The origin is the fixed walking surface; add draft entirely below it.
@export var thickness := 0.50
@export var ghost := false
func _ready() -> void:
	var count := maxi(1,ceili(dimensions.x/0.5))
	for i in count:
		var plank:=MeshInstance3D.new()
		var mesh:=BoxMesh.new();mesh.size=Vector3(dimensions.x/count-0.025,thickness,dimensions.y)
		plank.mesh=mesh;plank.position=Vector3(-dimensions.x/2+(i+0.5)*dimensions.x/count,-thickness/2,0)
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color("#b88b55").lerp(Color("#d4b282"),float(i%3)*0.25)
		material.roughness=0.94
		if ghost:
			material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			material.render_priority=10
			material.albedo_color=Color(0.55,0.95,0.78,0.45)
			material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			plank.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plank.material_override=material;add_child(plank)

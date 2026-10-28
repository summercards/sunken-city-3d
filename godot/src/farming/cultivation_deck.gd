@tool
extends Node3D
## Independent wooden platform surface. FarmPlot owns the six soil beds above it.
func _ready() -> void:
	for i in 13:
		var plank := MeshInstance3D.new()
		plank.name = "Plank%02d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.47,0.10,5.15)
		plank.mesh = mesh
		plank.position = Vector3(-3.0+i*0.50,0.0,0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#b88b55").lerp(Color("#d4b282"),float(i%3)*0.25)
		material.roughness = 0.94
		plank.material_override = material
		add_child(plank)

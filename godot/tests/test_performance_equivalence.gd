extends SceneTree
## Exact contracts for performance changes. Unified runner owns user:// isolation.
const Crop = preload("res://src/crops/crop_view.gd")
const Water = preload("res://src/rendering/water_surface.gd")
const Bake = preload("res://src/world/bake_store.gd")
const SeaPropsScript = preload("res://src/pickups/sea_props.gd")
var checks := 0
var failures := 0
var stage_signals := 0

class BoatStub extends Node3D:
	var model: Node3D
	func wake_uniform() -> Vector4: return Vector4.ZERO
	func starts_sailing() -> bool: return false
	func rowing_state() -> Vector2: return Vector2.ZERO

func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL [performance-equivalence] ",label)

func run() -> void:
	var crop := Crop.new()
	root.add_child(crop)
	crop.show_crop("lettuce")
	crop.set_stage(2)
	crop.stage_changed.connect(func(_stage: int): stage_signals += 1)
	var applied := crop.stage_apply_count
	for i in 120: crop.set_stage(2)
	check(crop.stage_apply_count == applied, "unchanged crop stage skips visibility/tint traversal")
	check(stage_signals == 120, "public set_stage signal contract retained even for same stage")
	crop.set_dry(true)
	var overrides := []
	for mesh in crop._collect_meshes(): overrides.append(mesh.material_override)
	crop.set_stage(2)
	var same := true
	var meshes := crop._collect_meshes()
	for i in meshes.size(): same = same and meshes[i].material_override == overrides[i]
	check(same and not overrides.is_empty(), "same stage preserves existing dry overrides")
	crop.set_stage(3)
	check(crop.current_stage() == 3 and crop._shown_stage == 3 and crop.stage_apply_count == applied+1, "changed stage applies immediately")
	crop.set_dry(false)
	var restored := true
	for mesh in crop._collect_meshes(): restored = restored and mesh.material_override == null
	check(restored, "watering restores original material")
	crop.show_crop("tomato")
	check(crop.current_crop() == "tomato" and crop._shown_stage == 3, "switch crop invalidates stage projection")
	crop.show_crop("")
	crop.set_stage(1)
	crop.show_crop("")
	check(crop.current_stage() == -1, "repeated empty crop clears public stage state")

	var surface := Water.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	surface.material_override = material
	root.add_child(surface)
	var boat := BoatStub.new()
	boat.model = Node3D.new()
	boat.add_child(boat.model)
	root.add_child(boat)
	var initial := surface.static_sync_count
	for i in 120: surface.update_surface(float(i)/60.0,boat,Vector3.ZERO)
	check(surface.static_sync_count == initial, "static wave/contact defaults are not submitted per frame")
	check(is_equal_approx(float(surface.current_material().get_shader_parameter("u_time")),119.0/60.0), "dynamic water clock continues every update")
	surface.wave_scale = 0.8
	surface.update_surface(2.0,boat,Vector3.ZERO)
	check(surface.static_sync_count == initial+1 and is_equal_approx(float(surface.current_material().get_shader_parameter("wave_scale")),0.8), "node amplitude edits invalidate static sync")
	var waves := surface.ocean_waves.duplicate()
	waves[0].z += 0.01
	surface.ocean_waves = waves
	surface.update_surface(2.1,boat,Vector3.ZERO)
	check(surface.static_sync_count == initial+2, "in-place wave content change invalidates sync")
	var replacement := ShaderMaterial.new()
	replacement.shader = material.shader
	surface.register_scheme("candidate",replacement)
	surface.use_scheme("candidate")
	check(surface.current_material().get_shader_parameter("ocean_waves") == waves, "scheme replacement receives full static state")

	Bake.material(-1,true,false,false,true)
	var writes := Bake.timed_write_count
	Bake.update_time(1001.0)
	var first := Bake.timed_write_count
	for i in 5: Bake.update_time(1001.0)
	check(first > writes and Bake.timed_write_count == first, "shared timed materials submitted once, not once per zone")
	Bake.update_time(1002.0)
	check(Bake.timed_write_count > first, "next simulation time updates shared materials")

	var props := SeaPropsScript.new()
	props.ocean_enabled = true
	root.add_child(props)
	props._spawn_crate(Vector2(10,10),"perf/one")
	props.set_process(false)
	props.hide()
	props._process(1.0)
	var row: Dictionary = props.crates[0]
	var base: Vector3 = row.base
	var expected := Vector3(base.x + sin(props._t*0.24+float(row.phase))*0.45,1.12+sin(props._t*1.15+float(row.phase))*0.07,base.z+cos(props._t*0.19+float(row.phase))*0.45)
	check(row.root.position.is_equal_approx(expected), "hidden resource root stays current for public spatial queries")
	check(not props.nearest_crate(expected,0.1).is_empty(), "hidden nearest query observes current root")
	props.ocean_enabled = false
	props._pending = [10.0]
	props._pending_fish = [12.0]
	props._process(1.0)
	check(props._pending == [9.0] and props._pending_fish == [11.0], "hidden legacy restock timers continue")
	check(is_equal_approx(float(props.to_dict().elapsed),2.0), "hidden elapsed remains serialized without format changes")
	props.show()
	props._process(0.0)
	check(is_equal_approx(float(row.root.rotation.y),float(row.yaw)+sin(props._t*0.3+float(row.phase))*0.35), "first visible frame samples current cosmetic phase")

	props.queue_free(); crop.queue_free(); surface.queue_free(); boat.queue_free()
	await process_frame
	print("[performance-equivalence] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

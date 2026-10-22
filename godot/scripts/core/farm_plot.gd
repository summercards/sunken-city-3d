@tool
extends "res://scripts/core/interactable.gd"
class_name FarmPlot
## 世界里的菜箱。
##
## 一物四态：空地 / 生长 / 缺水 / 可收。状态不靠 UI 说，直接长在箱子上：
##   - 土壤颜色随含水量变化（干=浅土黄，湿=深褐）；
##   - 作物分三段长大（芽 / 叶 / 结果）；
##   - 缺水时叶片发黄下垂，但不会枯死；
##   - 成熟时果实微微发光，远处也能看见。
##
## 规则全在 `Economy.farm`（FarmModel），这里只负责造型、焦点文案与把 E 转给它。

signal acted(plot_id: String, event: String, payload: Dictionary)

@export var plot_id := ""
@export var zone_id := ""
@export var plot_name := "菜箱"
@export var requires_site := ""
@export var requires_level := 0

## 四段造型：0 空地/土丘、1 芽、2 叶、3 结果。
var _stage_roots: Array = []
var _leaf_mat: StandardMaterial3D
var _fruit_mat: StandardMaterial3D
var _soil_mat: StandardMaterial3D
var _shadow: MeshInstance3D
var _plant_root: Node3D
var _last_phase := ""
var _last_crop := ""


func setup(data: Dictionary) -> void:
	plot_id = str(data.get("id", plot_id))
	zone_id = str(data.get("zone", zone_id))
	plot_name = str(data.get("name", plot_name))
	label = plot_name
	requires_site = str(data.get("requires_site", ""))
	requires_level = int(data.get("requires_level", 0))
	position = Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
	rotation.y = float(data.get("yaw", 0.0))
	id = plot_id
	priority = 2
	focus_radius = 2.4
	accent = Color("#9fe07a")


func _on_ready() -> void:
	id = plot_id
	label = plot_name
	priority = 2
	focus_radius = 2.4
	accent = Color("#9fe07a")
	add_to_group("farm_plots")
	_build_box()
	_build_plant()
	# 编辑器里 Economy 是占位实例，不能读种植状态；只把菜箱本身摆出来。
	if Engine.is_editor_hint():
		return
	_sync(0.0)


func _on_tick(delta: float) -> void:
	_sync(delta)


## 焦点文案：动作 + 菜箱名 + 当前状态。
func focus_text() -> String:
	var farm = Economy.farm
	if farm == null:
		return "%s · %s" % [verb, plot_name]
	return "%s · %s（%s）" % [verb, plot_name, farm.status_text(plot_id)]


func blocked_reason() -> String:
	return Economy.farm.blocked_reason(plot_id) if Economy.farm != null else "种植系统未就绪"


func interact(_actor: Node3D) -> Dictionary:
	var farm = Economy.farm
	if farm == null:
		return {"blocked": "种植系统未就绪"}
	var result: Dictionary = farm.interact(plot_id, farm.selected_crop)
	if result.has("blocked"):
		return result
	_pop()
	acted.emit(plot_id, str(result.get("event", "")), result)
	return result


# ---- 造型 -------------------------------------------------------------------

func _build_box() -> void:
	# 底板 + 四边框：像一个真的木箱，而不是一块贴图。
	var wood := _mat(Color("#a9784a"))
	var wood_dark := _mat(Color("#7d5634"))
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.30, 0.10, 0.90)
	base.mesh = bm
	base.position = Vector3(0, 0.05, 0)
	base.material_override = wood_dark
	add_child(base)

	for spec in [
		[Vector3(1.30, 0.26, 0.07), Vector3(0, 0.20, -0.415)],
		[Vector3(1.30, 0.26, 0.07), Vector3(0, 0.20, 0.415)],
		[Vector3(0.07, 0.26, 0.76), Vector3(-0.615, 0.20, 0)],
		[Vector3(0.07, 0.26, 0.76), Vector3(0.615, 0.20, 0)],
	]:
		var side := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = spec[0]
		side.mesh = sm
		side.position = spec[1]
		side.material_override = wood
		add_child(side)

	_soil_mat = _mat(Color("#8a6a48"))
	var soil := MeshInstance3D.new()
	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(1.16, 0.10, 0.76)
	soil.mesh = soil_mesh
	soil.position = Vector3(0, 0.28, 0)
	soil.material_override = _soil_mat
	add_child(soil)

	_build_shadow()


## 接触阴影：没有它，箱子像贴纸一样浮在甲板上。
func _build_shadow() -> void:
	_shadow = MeshInstance3D.new()
	_shadow.name = "ContactShadow"
	var dm := BoxMesh.new()
	dm.size = Vector3(1.52, 0.008, 1.12)
	_shadow.mesh = dm
	_shadow.position = Vector3(0, 0.006, 0)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.02, 0.09, 0.12, 0.22)
	_shadow.material_override = mat
	add_child(_shadow)


func _build_plant() -> void:
	_plant_root = Node3D.new()
	_plant_root.name = "Plants"
	add_child(_plant_root)

	_leaf_mat = _mat(Color("#7fbf58"))
	_fruit_mat = _lit_mat(Color("#e2685a"))
	_fruit_mat.emission_energy_multiplier = 0.35

	for stage in 4:
		var root := Node3D.new()
		root.name = "Stage%d" % stage
		_plant_root.add_child(root)
		_stage_roots.append(root)

	# 每个阶段往对应 root 里塞一份造型，切换时只改 visible。
	for i in 3:
		_build_stage_meshes(0, Vector3(-0.36 + i * 0.36, 0.0, -0.10 + (i % 2) * 0.22), 0.9 + 0.1 * i)
		_build_stage_meshes(1, Vector3(-0.36 + i * 0.36, 0.0, -0.10 + (i % 2) * 0.22), 0.9 + 0.1 * i)
		_build_stage_meshes(2, Vector3(-0.36 + i * 0.36, 0.0, -0.10 + (i % 2) * 0.22), 0.9 + 0.1 * i)
		_build_stage_meshes(3, Vector3(-0.36 + i * 0.36, 0.0, -0.10 + (i % 2) * 0.22), 0.9 + 0.1 * i)


func _build_stage_meshes(stage: int, offset: Vector3, s: float) -> void:
	var root: Node3D = _stage_roots[stage]
	var base := Node3D.new()
	base.position = offset
	base.scale = Vector3(s, s, s)
	root.add_child(base)

	if stage == 0:
		# 刚播下：三小撮翻过的土。
		for i in 3:
			var bump := MeshInstance3D.new()
			var bm := SphereMesh.new()
			bm.radius = 0.055
			bm.height = 0.06
			bm.radial_segments = 8
			bm.rings = 4
			bump.mesh = bm
			bump.position = Vector3((i - 1) * 0.06, 0.02, 0)
			bump.material_override = _soil_mat
			base.add_child(bump)
		return

	var stem_h := 0.12 if stage == 1 else 0.30
	var stem := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.012
	sm.bottom_radius = 0.016
	sm.height = stem_h
	stem.mesh = sm
	stem.position = Vector3(0, 0.30 + stem_h * 0.5, 0)
	stem.material_override = _leaf_mat
	base.add_child(stem)

	var leaf_count := 2 if stage == 1 else 6
	for i in leaf_count:
		# 每片叶子挂在绕 Y 旋转的支点上，再向外伸出并下垂：
		# 直接把盒子按欧拉角摆，叶面会朝上翻，远看像一堆绿色方块。
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0.30 + stem_h * (0.62 + 0.07 * i), 0)
		pivot.rotation.y = TAU * float(i) / float(maxi(leaf_count, 1))
		base.add_child(pivot)

		var leaf := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.20, 0.014, 0.11) if stage > 1 else Vector3(0.11, 0.012, 0.07)
		leaf.mesh = lm
		leaf.position = Vector3(0.105, 0.0, 0.0)
		leaf.rotation.z = -0.42 if stage > 1 else -0.2
		leaf.material_override = _leaf_mat
		pivot.add_child(leaf)

	if stage >= 3:
		# 结果：果实颜色由作物表决定，成熟时微微发光。
		for i in 3:
			var fruit := MeshInstance3D.new()
			var fm := SphereMesh.new()
			fm.radius = 0.075
			fm.height = 0.15
			fm.radial_segments = 10
			fm.rings = 6
			fruit.mesh = fm
			var ang := TAU * float(i) / 3.0 + 0.5
			fruit.position = Vector3(cos(ang) * 0.135, 0.30 + stem_h * 0.40, sin(ang) * 0.135)
			fruit.material_override = _fruit_mat
			base.add_child(fruit)


# ---- 状态同步 ---------------------------------------------------------------

func _sync(_delta: float) -> void:
	var farm = Economy.farm
	if farm == null:
		return
	var phase: String = farm.phase(plot_id)
	var p: float = farm.progress(plot_id)
	var crop_id: String = farm.crop_of(plot_id)

	var stage := 0
	if phase == "ready":
		stage = 3
	elif phase == "growing":
		stage = 1 if p < 0.45 else (2 if p < 0.92 else 3)

	for i in _stage_roots.size():
		var node: Node3D = _stage_roots[i]
		node.visible = (i == stage) and phase != "empty"

	# 生长中给一点体积变化，避免阶段切换太跳。
	if phase == "growing" and _stage_roots.size() > stage:
		var growing: Node3D = _stage_roots[stage]
		var k := 0.72 + 0.28 * clampf(p, 0.0, 1.0)
		growing.scale = Vector3(k, k, k)
	elif phase == "ready" and _stage_roots.size() > 3:
		var ripe: Node3D = _stage_roots[3]
		ripe.scale = Vector3.ONE

	# 土壤：越湿越深。干土偏浅黄，湿土接近深褐。
	var thirst: float = 1.0
	var wet: float = 0.28 if phase == "empty" else clampf(float(farm.state(plot_id).water) / maxf(thirst, 0.001), 0.0, 1.0)
	if _soil_mat != null:
		_soil_mat.albedo_color = Color("#9a7a52").lerp(Color("#4b3524"), wet)

	# 缺水：叶色转黄发暗，果实也就不再亮。
	var dry: bool = phase == "growing" and farm.is_dry(plot_id)
	if _leaf_mat != null:
		var green := Color("#7fbf58")
		if dry:
			green = green.lerp(Color("#b9a45a"), 0.55).darkened(0.12)
		_leaf_mat.albedo_color = green
	if _fruit_mat != null:
		var crop: Dictionary = farm.crop_def(crop_id)
		var color := Color(str(crop.get("color", "#e2685a")))
		_fruit_mat.albedo_color = color
		_fruit_mat.emission = color if phase == "ready" else Color.BLACK
		_fruit_mat.emission_energy_multiplier = 0.45 if phase == "ready" else 0.0

	# 焦点文案与按住时长跟着动作走：浇水比收获慢一点，播种最快。
	verb = farm.action_label(plot_id)
	hold_time = 0.95 if verb == "播种" else (1.25 if verb == "浇水" else (1.1 if verb == "收获" else 0.35))
	if phase == "ready":
		accent = Color("#ffd27a")
	elif dry:
		accent = Color("#e8c06a")
	else:
		accent = Color("#9fe07a")

	# 作物换了要重刷一次造型（果实颜色、阶段）。
	if crop_id != _last_crop or phase != _last_phase:
		_last_crop = crop_id
		_last_phase = phase


func _pop() -> void:
	if _plant_root == null:
		return
	var tw := create_tween()
	_plant_root.scale = Vector3(0.92, 0.92, 0.92)
	tw.tween_property(_plant_root, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	m.metallic_specular = 0.08
	return m


func _lit_mat(color: Color) -> StandardMaterial3D:
	var m := _mat(color)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.3
	return m

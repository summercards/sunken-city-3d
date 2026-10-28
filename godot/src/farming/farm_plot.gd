@tool
extends "res://src/interaction/interactable.gd"
class_name FarmPlot
const Farm_modelDependency = preload("res://src/farming/farm.gd")
const StageDef = preload("res://src/crops/crop_stage.gd")
const CropViewLib = preload("res://src/crops/crop_view.gd")
var farm_model: Farm_modelDependency
## 世界里的菜箱。
##
## 它只管三件事：木箱造型、焦点文案、把动作转给 farm_model。
## 作物长什么样由 SEA-CROP 的 CropView 负责——这里不再构造任何作物网格。
##
## 一物四态：空地 / 生长 / 缺水 / 可收。状态不靠 UI 说，直接长在箱子上：
##   - 土壤颜色随含水量变化（干=浅土黄，湿=深褐）；
##   - 作物四阶段由 CropView 切换，缺水只把作物压黄，不跳阶段；
##   - 成熟形态由美术资产本身表达，不额外贴发光片。
##
## 规则全在 `farm_model`（FarmModel），这里只负责造型、焦点文案与把 E 转给它。

signal interaction_requested(plot_id: String)
var use_action_menu := false

signal acted(plot_id: String, event: String, payload: Dictionary)

@export var plot_id := ""
@export var zone_id := ""
@export var plot_name := "菜箱"
@export var requires_site := ""
@export var requires_level := 0

var _soil_mat: StandardMaterial3D
var _shadow: MeshInstance3D
var _crop_view: CropView
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
	_build_crop_view()
	# 编辑器里 Economy 是占位实例，不能读种植状态；只把菜箱与预览作物摆出来。
	if Engine.is_editor_hint():
		return
	_sync(0.0)


func _on_tick(delta: float) -> void:
	_sync(delta)


## 焦点文案：动作 + 菜箱名 + 当前状态。
func focus_text() -> String:
	var farm = farm_model
	if farm == null:
		return "%s · %s" % [verb, plot_name]
	return "%s · %s（%s）" % [verb, plot_name, farm.status_text(plot_id)]


func blocked_reason() -> String:
	if farm_model == null: return "种植系统未就绪"
	if use_action_menu and farm_model.phase(plot_id) != "ready": return farm_model.access_reason(plot_id)
	return farm_model.blocked_reason(plot_id)


func interact(_actor: Node3D) -> Dictionary:
	var farm = farm_model
	if farm == null:
		return {"blocked": "种植系统未就绪"}
	if use_action_menu and farm.phase(plot_id) != "ready":
		interaction_requested.emit(plot_id)
		return {"event":"options"}
	return perform("harvest" if farm.phase(plot_id)=="ready" else ("plant" if farm.is_empty(plot_id) else "water"),farm.selected_crop)

func perform(action: String, crop_id := "") -> Dictionary:
	var result: Dictionary
	match action:
		"plant": result = farm_model.plant(plot_id,crop_id)
		"water": result = farm_model.water(plot_id)
		"harvest": result = farm_model.harvest(plot_id)
		"refill": return farm_model.refill()
		_: return {"blocked":"未知操作"}
	if result.has("blocked"):
		return result
	_pop()
	acted.emit(plot_id, str(result.get("event", "")), result)
	return result


## 作物表现入口。测试与调试工具用它读当前阶段，不必自己翻节点树。
func crop_view() -> CropView:
	return _crop_view


func current_stage() -> int:
	return _crop_view.current_stage() if _crop_view != null else -1


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


## 作物表现容器。土面高度 0.33，作物几何以土面为原点。
func _build_crop_view() -> void:
	_crop_view = CropViewLib.new()
	_crop_view.name = "Crop"
	_crop_view.position = Vector3(0.0, 0.33, 0.0)
	_crop_view.preview_crop = "lettuce"
	_crop_view.preview_stage = StageDef.HARVEST
	add_child(_crop_view)


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


# ---- 状态同步 ---------------------------------------------------------------

func _sync(_delta: float) -> void:
	var farm = farm_model
	if farm == null:
		return
	var phase: String = farm.phase(plot_id)
	var p: float = farm.progress(plot_id)
	var crop_id: String = farm.crop_of(plot_id)
	var dry: bool = farm.is_dry(plot_id)

	# 阶段映射是 SEA-CROP 的规则，这里只转交，不自己算阈值。
	var stage := StageDef.stage_for_progress(p, phase == "ready")
	if _crop_view != null:
		_crop_view.show_crop(crop_id)
		_crop_view.set_stage(stage)
		_crop_view.set_dry(dry)

	# 土壤：越湿越深。干土偏浅黄，湿土接近深褐。
	var wet: float = 0.28 if phase == "empty" else clampf(float(farm.state(plot_id).water), 0.0, 1.0)
	if _soil_mat != null:
		_soil_mat.albedo_color = Color("#9a7a52").lerp(Color("#4b3524"), wet)

	# 焦点文案与按住时长跟着动作走：浇水比收获慢一点，播种最快。
	verb = "选择种子" if use_action_menu and phase == "empty" else ("照料" if use_action_menu and phase == "growing" else farm.action_label(plot_id))
	hold_time = 0.95 if verb == "播种" else (1.25 if verb == "浇水" else (1.1 if verb == "收获" else 0.35))
	if phase == "ready":
		accent = Color("#ffd27a")
	elif dry:
		accent = Color("#e8c06a")
	else:
		accent = Color("#9fe07a")

	_last_crop = crop_id
	_last_phase = phase


## 播种/收获的动作反馈：整体轻弹一下。这不是阶段开关，阶段只由可见性切换。
func _pop() -> void:
	if _crop_view == null:
		return
	var tw := create_tween()
	_crop_view.scale = Vector3(0.92, 0.92, 0.92)
	tw.tween_property(_crop_view, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	m.metallic_specular = 0.08
	return m

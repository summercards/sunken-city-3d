@tool
extends "res://src/interaction/interactable.gd"
## 世界里的建造牌。
##
## 旧实现是「面板里点一下 → 等级 +1」，材料够就瞬间完成，等级只是个数字。
## 现在建造分成三段：
##
##   待施工（牌子立着，提示「[E] 交付材料」）
##     → 交付：一次扣齐材料，脚手架立起来，开始真实倒计时
##     → 竣工：等级 +1，脚手架收起，牌子换成新等级
##
## 计时归 `Economy.site_work` 管（关界面、走开、切区块都照走），
## 这个节点只负责造型、焦点文案和把进度画出来——规则和表现分开，headless 才能断言。

## 交付材料成功时发出：上层用它播提示与音效。
signal work_started(site_id: String, site_name: String, seconds: float)

var site_id := ""
var zone_id := ""
var site_name := ""
var accent_idle := Color("#4fdcc2")
var accent_build := Color("#ffb43c")
var accent_done := Color("#8effc0")

var _scaffold: Node3D
var _board: MeshInstance3D
var _board_mat: StandardMaterial3D
var _lamp: OmniLight3D
var _pulse := 0.0
var _pop := 0.0


func setup(row: Dictionary) -> void:
	site_id = str(row.get("id", ""))
	zone_id = str(row.get("zone", ""))
	site_name = str(row.get("name", site_id))
	id = "build_%s" % site_id
	name = "BuildSite_%s" % site_id
	position = Vector3(float(row.get("x", 0.0)), float(row.get("y", 0.0)), float(row.get("z", 0.0)))
	rotation.y = float(row.get("yaw", 0.0))
	priority = 3
	focus_radius = 2.6
	accent = accent_idle


func _on_ready() -> void:
	_build_sign()
	_build_scaffold()
	_build_lamp()
	# 编辑器里 autoload 是占位实例（脚本非 tool），碰 Economy 会报
	# "Attempt to call a method on a placeholder instance"，所以只摆造型。
	if Engine.is_editor_hint():
		return
	_refresh_state()
	if not Economy.site_work_finished.is_connected(_on_finished):
		Economy.site_work_finished.connect(_on_finished)
	if not Economy.sites_changed.is_connected(_refresh_state):
		Economy.sites_changed.connect(_refresh_state)


func _on_tick(delta: float) -> void:
	_pulse += delta
	if _pop > 0.0:
		_pop = maxf(0.0, _pop - delta * 1.6)
		var s := 1.0 + sin(_pop * PI) * 0.16
		scale = Vector3(s, s, s)
	if Economy.is_building(site_id):
		# 施工中的节奏感：材料堆轻微起伏，灯在呼吸。
		if _scaffold != null:
			_scaffold.position.y = sin(_pulse * 2.4) * 0.02
		if _lamp != null:
			_lamp.light_energy = 0.5 + sin(_pulse * 3.6) * 0.25


func focus_text() -> String:
	var lvl := Economy.site_level(site_id)
	if Economy.site_maxed(site_id):
		return "%s · Lv.%d（满级）" % [site_name, lvl]
	if Economy.is_building(site_id):
		return "%s · 施工中 %d%%" % [site_name, int(Economy.site_work_progress(site_id) * 100.0)]
	return "%s · Lv.%d → Lv.%d" % [site_name, lvl, lvl + 1]


func can_interact() -> bool:
	return true


## 施工中按住只会看进度；交付时按住 0.9 秒，避免误触扣掉一堆材料。
func hold_time_for() -> float:
	return 0.9 if _can_deliver() else 0.25


func blocked_reason() -> String:
	if Economy.site_maxed(site_id): return "%s 已经是最高等级" % site_name
	if Economy.is_building(site_id): return "还在施工，剩 %d 秒" % int(ceil(Economy.site_work_left(site_id)))
	var cost := Economy.site_next_cost(site_id)
	return "材料不够：%s" % Economy.construction_missing_text(cost) if not Economy.construction_has(cost) else ""

func interact(_actor: Node3D) -> Dictionary:
	if Economy.site_maxed(site_id):
		return {"blocked": "%s 已经是最高等级" % site_name}
	if Economy.is_building(site_id):
		return {"blocked": "还在施工，剩 %d 秒" % int(ceil(Economy.site_work_left(site_id)))}
	var cost := Economy.site_next_cost(site_id)
	if not Economy.construction_has(cost):
		return {"blocked": "材料不够：%s" % Economy.construction_missing_text(cost)}
	var r: Dictionary = Economy.begin_site_upgrade(site_id)
	if not r.get("ok", false):
		return {"blocked": str(r.get("reason", "现在不能施工"))}
	work_started.emit(site_id, site_name, float(r.get("seconds", 20.0)))
	return {
		"event": "site_work_started",
		"site": site_id,
		"name": site_name,
		"seconds": float(r.get("seconds", 20.0)),
		"cost": cost,
	}


func _can_deliver() -> bool:
	return not Economy.site_maxed(site_id) and not Economy.is_building(site_id)


func _on_finished(id: String, level: int) -> void:
	if id != site_id:
		return
	_pop = 1.0
	_refresh_state()
	# 竣工的一瞬间亮一下，玩家不看 HUD 也能注意到。
	if _lamp != null:
		var tw := create_tween()
		tw.tween_property(_lamp, "light_energy", 3.2, 0.12)
		tw.tween_property(_lamp, "light_energy", 0.0, 0.9)
	var board := create_tween()
	board.tween_property(self, "position:y", position.y + 0.12, 0.14)
	board.tween_property(self, "position:y", position.y, 0.26).set_trans(Tween.TRANS_BOUNCE)


func _refresh_state() -> void:
	var building := Economy.is_building(site_id)
	var maxed := Economy.site_maxed(site_id)
	if _scaffold != null:
		_scaffold.visible = building
	if _board != null:
		var c := accent_build if building else (accent_idle if not maxed else accent_done)
		_board_mat.albedo_color = c
		_board_mat.emission = c
		_board_mat.emission_energy_multiplier = 0.45 if building else 0.18
	label = "%s Lv.%d" % [site_name, Economy.site_level(site_id)]
	verb = "查看进度" if building else ("查看" if maxed else "交付材料")
	hold_time = hold_time_for()


## ---- 造型 -------------------------------------------------------------------

func _build_sign() -> void:
	var wood := _mat(Color("#8a6a45"))
	var board_mat := _lit_mat(Color("#8fe8d6"))
	_board_mat = board_mat
	for sx in [-0.38, 0.38]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.08, 1.12, 0.08)
		post.mesh = pm
		post.position = Vector3(sx, 0.56, 0)
		post.material_override = wood
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(post)

	_board = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.98, 0.56, 0.06)
	_board.mesh = bm
	_board.position = Vector3(0, 1.16, 0)
	_board.material_override = board_mat
	add_child(_board)

	# 牌面上一块浅色「图纸」，让牌子在远处也能读出是个告示。
	var paper := MeshInstance3D.new()
	var pm2 := BoxMesh.new()
	pm2.size = Vector3(0.50, 0.28, 0.012)
	paper.mesh = pm2
	paper.position = Vector3(0, 1.17, 0.038)
	paper.material_override = _mat(Color("#f3f7f2"))
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paper)

	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.42
	disc.height = 0.008
	disc.radial_segments = 16
	var shadow := MeshInstance3D.new()
	shadow.mesh = disc
	shadow.position = Vector3(0, 0.012, 0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.02, 0.10, 0.14, 0.18)
	shadow.material_override = smat
	add_child(shadow)


## 施工中的现场：材料堆 + 低矮的警示围栏。
## 一开始用了 4 根 2.1m 的脚手架，结果把 1.2m 的牌子整个吞掉，
## 远处只看到一堆木条——现在改成贴着地面的材料与围栏，牌子始终是视觉主体。
func _build_scaffold() -> void:
	_scaffold = Node3D.new()
	_scaffold.name = "WorkScene"
	_scaffold.visible = false
	add_child(_scaffold)

	var wood := _mat(Color("#b98f5c"))
	for i in 3:
		var plank := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.62, 0.07, 0.26)
		plank.mesh = pm
		plank.position = Vector3(-0.02, 0.04 + i * 0.075, 0.58)
		plank.rotation.y = 0.12 * (i - 1)
		plank.material_override = wood
		_scaffold.add_child(plank)

	var crate := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.34, 0.34, 0.34)
	crate.mesh = cm
	crate.position = Vector3(0.52, 0.17, 0.5)
	crate.rotation.y = 0.35
	crate.material_override = wood
	_scaffold.add_child(crate)

	# 警示围栏：两根横杆，琥珀色，只在施工期间出现。
	var hazard := _lit_mat(Color("#ffa93a"))
	hazard.emission_energy_multiplier = 0.35
	for y in [0.34, 0.52]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(1.16, 0.055, 0.055)
		rail.mesh = rm
		rail.position = Vector3(0, y, 0.36)
		rail.material_override = hazard
		_scaffold.add_child(rail)
	for sx in [-0.56, 0.56]:
		var post := MeshInstance3D.new()
		var pm2 := BoxMesh.new()
		pm2.size = Vector3(0.06, 0.62, 0.06)
		post.mesh = pm2
		post.position = Vector3(sx, 0.31, 0.36)
		post.material_override = wood
		_scaffold.add_child(post)


func _build_lamp() -> void:
	_lamp = OmniLight3D.new()
	_lamp.light_color = accent_build
	_lamp.light_energy = 0.0
	_lamp.omni_range = 3.2
	_lamp.position = Vector3(0, 1.3, 0)
	add_child(_lamp)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.94
	m.metallic = 0.0
	return m


func _lit_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.2
	m.roughness = 0.9
	return m
